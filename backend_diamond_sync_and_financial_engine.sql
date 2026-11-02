-- ==============================================================================
-- BACKEND DIAMOND SYNC & FINANCIAL ENGINE MIGRATION (v4 - 100% Cast-Safe)
-- محرك الربط المالي الموحد عبر الباك إند وقاعدة البيانات لجميع جداول الألماس
-- ==============================================================================

-- 0. التأكد من وجود الأعمدة الشائعة لتجنب أي خطأ عدم وجود العمود
ALTER TABLE public.host_agency_members ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE public.host_agencies ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- 1. التأكد من وجود جدول سجلات الألماس وأعمدته
CREATE TABLE IF NOT EXISTS public.user_diamond_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  amount bigint NOT NULL,
  type text NOT NULL, -- 'admin_add', 'admin_deduct', 'agency_disburse', 'user_exchange', 'gift'
  balance_before bigint,
  balance_after bigint,
  admin_name text DEFAULT 'الإدارة',
  reason text,
  metadata jsonb DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- التأكد من وجود كافة الأعمدة في حال كان الجدول منشأ سابقاً
ALTER TABLE public.user_diamond_logs ADD COLUMN IF NOT EXISTS admin_name text DEFAULT 'الإدارة';
ALTER TABLE public.user_diamond_logs ADD COLUMN IF NOT EXISTS reason text;
ALTER TABLE public.user_diamond_logs ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT '{}';

CREATE INDEX IF NOT EXISTS user_diamond_logs_uid_idx
  ON public.user_diamond_logs (user_id, created_at DESC);

-- السماح بالوصول الكامل لجدول السجلات
ALTER TABLE public.user_diamond_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all on user_diamond_logs" ON public.user_diamond_logs;
CREATE POLICY "Allow all on user_diamond_logs"
  ON public.user_diamond_logs FOR ALL
  TO authenticated, anon
  USING (true)
  WITH CHECK (true);

-- 2. دالة التريجر التلقائي من جدول users: لمزامنة الألماس فورياً وتوحيد رصيد السحب مع ألماس الشهر
CREATE OR REPLACE FUNCTION public.trg_sync_user_diamonds_to_agency()
RETURNS TRIGGER AS $$
DECLARE
  v_uid_text text;
  v_uid_uuid uuid;
BEGIN
  -- منع التكرار اللانهائي للتريجر (Recursion Protection)
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  v_uid_text := NEW.uid::text;
  BEGIN
    v_uid_uuid := NEW.uid::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_uid_uuid := NULL;
  END;

  -- أ. مزامنة الرصيد القابل للسحب فقط — لا نلمس ألماس الشهر/التراكمي
  UPDATE public.host_agency_members
  SET 
    diamonds = NEW.diamonds,
    diamonds_balance = NEW.diamonds,
    diamonds_available = NEW.diamonds,
    updated_at = now()
  WHERE user_id::text = v_uid_text 
     OR host_uid::text = v_uid_text
     OR (v_uid_uuid IS NOT NULL AND (user_id::text = v_uid_uuid::text OR host_uid::text = v_uid_uuid::text));

  -- ب. إذا كان المستخدم مالك وكالة، مزامنة محفظة الوكالة agency_wallets
  IF EXISTS (
    SELECT 1 FROM public.host_agencies 
    WHERE owner_uid::text = v_uid_text OR owner_id::text = v_uid_text
  ) THEN
    UPDATE public.agency_wallets
    SET 
      diamond_balance = NEW.diamonds
    WHERE agency_profile_id::text = v_uid_text
       OR (v_uid_uuid IS NOT NULL AND agency_profile_id::text = v_uid_uuid::text);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_user_diamonds ON public.users;
CREATE TRIGGER trg_sync_user_diamonds
  AFTER UPDATE OF diamonds ON public.users
  FOR EACH ROW
  WHEN (OLD.diamonds IS DISTINCT FROM NEW.diamonds)
  EXECUTE FUNCTION public.trg_sync_user_diamonds_to_agency();

-- 3. تم إلغاء التريجر العكسي نهائياً.
--    السبب: كان يفرض diamonds_earned_monthly = GREATEST(monthly, balance, diamonds)
--    فيرفع "إنتاج الشهر" إلى رصيد المحفظة ويسبب عدم تطابق كل الإجماليات.
--    الاتجاه الوحيد المسموح: users.diamonds (المحفظة) → host_agency_members (wallet fields).
DROP TRIGGER IF EXISTS trg_sync_agency_member_diamonds ON public.host_agency_members;
DROP FUNCTION IF EXISTS public.trg_sync_agency_member_diamonds_to_user();

-- 3.1 إعادة حساب إجماليات الوكالة من أعضائها (مصدر واحد للحقيقة)
CREATE OR REPLACE FUNCTION public.agency_recalc_totals(p_agency_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_monthly bigint := 0;
  v_cum bigint := 0;
BEGIN
  IF p_agency_id IS NULL OR p_agency_id = '' THEN
    RETURN;
  END IF;

  SELECT COALESCE(SUM(COALESCE(diamonds_earned_monthly, 0)), 0),
         COALESCE(SUM(COALESCE(diamonds_earned_cumulative, 0)), 0)
  INTO v_monthly, v_cum
  FROM public.host_agency_members
  WHERE agency_id::text = p_agency_id;

  UPDATE public.host_agencies
  SET total_diamonds_monthly = v_monthly,
      monthly_diamonds = v_monthly,
      total_diamonds_cumulative = v_cum,
      total_diamonds_earned = v_cum,
      updated_at = now()
  WHERE id::text = p_agency_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.agency_recalc_totals(text) TO authenticated, service_role, anon;

-- 4. دالة RPC المركزية لتنفيذ كافة العمليات المالية من الباك إند ذرّياً (Atomic Backend Financial RPC)
CREATE OR REPLACE FUNCTION public.admin_process_diamond_transaction(
  p_user_id text,
  p_amount bigint,
  p_type text, -- 'add' أو 'deduct'
  p_reason text DEFAULT 'تعديل رصيد من الإدارة',
  p_admin_name text DEFAULT 'المدير العام',
  p_sync_monthly_target boolean DEFAULT true
)
RETURNS jsonb AS $$
DECLARE
  v_current_diamonds bigint := 0;
  v_new_diamonds bigint := 0;
  v_abs_amount bigint;
  v_diff bigint;
  v_user_uuid uuid;
  v_member_record record;
  v_agency_id text;
  v_monthly_delta bigint := 0;
  v_cum_delta bigint := 0;
BEGIN
  v_abs_amount := ABS(COALESCE(p_amount, 0));
  IF v_abs_amount <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'المبلغ يجب أن يكون أكبر من صفر');
  END IF;

  IF p_type NOT IN ('add', 'deduct') THEN
    RETURN jsonb_build_object('success', false, 'error', 'نوع العملية غير صحيح');
  END IF;

  -- 1. جلب رصيد المستخدم الحالي مع قفل الصف لمنع تضارب المعاملات (FOR UPDATE)
  SELECT diamonds, id INTO v_current_diamonds, v_user_uuid
  FROM public.users
  WHERE uid::text = p_user_id OR id::text = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
  END IF;

  v_current_diamonds := COALESCE(v_current_diamonds, 0);

  -- 2. حساب الرصيد الجديد (الخصم لا يتجاوز الرصيد الفعلي)
  IF p_type = 'add' THEN
    v_new_diamonds := v_current_diamonds + v_abs_amount;
  ELSE
    v_new_diamonds := GREATEST(0, v_current_diamonds - v_abs_amount);
  END IF;

  v_diff := v_new_diamonds - v_current_diamonds;
  v_monthly_delta := v_diff;
  v_cum_delta := CASE WHEN p_type = 'add' THEN v_diff ELSE 0 END;

  -- 3. تحديث جدول المستخدمين (سوف يطلق التريجر التلقائي أيضاً للمحفظة والوكالة)
  UPDATE public.users
  SET diamonds = v_new_diamonds
  WHERE uid::text = p_user_id OR id::text = p_user_id;

  -- 4. فحص عضوية الوكالة وتحديث بياناتها
  SELECT id, agency_id, diamonds_earned_monthly, diamonds_earned_cumulative
  INTO v_member_record
  FROM public.host_agency_members
  WHERE user_id::text = p_user_id OR host_uid::text = p_user_id
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    v_agency_id := v_member_record.agency_id::text;

    UPDATE public.host_agency_members
    SET 
      diamonds = v_new_diamonds,
      diamonds_balance = v_new_diamonds,
      diamonds_available = v_new_diamonds,
      diamonds_earned_monthly = CASE
        WHEN p_sync_monthly_target THEN
          GREATEST(0, COALESCE(diamonds_earned_monthly, 0) + v_monthly_delta)
        ELSE COALESCE(diamonds_earned_monthly, 0)
      END,
      diamonds_earned_cumulative = GREATEST(
        0,
        COALESCE(diamonds_earned_cumulative, 0) + v_cum_delta
      ),
      updated_at = now()
    WHERE id = v_member_record.id;

    -- إعادة حساب إجمالي الوكالة من مجموع الأعضاء (مصدر واحد للحقيقة)
    IF v_agency_id IS NOT NULL AND v_agency_id <> '' THEN
      PERFORM public.agency_recalc_totals(v_agency_id);
    END IF;
  END IF;

  -- 5. تسجيل العملية في سجل الألماس user_diamond_logs
  IF v_user_uuid IS NULL THEN
    BEGIN
      v_user_uuid := p_user_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_user_uuid := NULL;
    END;
  END IF;

  IF v_user_uuid IS NOT NULL THEN
    INSERT INTO public.user_diamond_logs (
      user_id,
      amount,
      type,
      balance_before,
      balance_after,
      admin_name,
      reason,
      created_at
    ) VALUES (
      v_user_uuid,
      v_diff,
      CASE WHEN p_type = 'add' THEN 'admin_add' ELSE 'admin_deduct' END,
      v_current_diamonds,
      v_new_diamonds,
      p_admin_name,
      p_reason,
      now()
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'old_diamonds', v_current_diamonds,
    'new_diamonds', v_new_diamonds,
    'amount', v_abs_amount,
    'type', p_type,
    'agency_synced', FOUND
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.admin_process_diamond_transaction TO authenticated, service_role, anon;

-- ==============================================================================
-- 5. إصلاح وتوحيد فوري لجميع الحسابات الحالية (Instant Full Auto-Healing)
-- ==============================================================================
-- القاعدة: users.diamonds = المحفظة فقط، ولا يُستخدم أبداً كمصدر لإنتاج الشهر أو التراكمي.

-- أ. مزامنة محفظة العضو فقط من users.diamonds (بدون لمس monthly/cumulative)
UPDATE public.host_agency_members m
SET 
  diamonds = COALESCE(u.diamonds, 0),
  diamonds_balance = COALESCE(u.diamonds, 0),
  diamonds_available = COALESCE(u.diamonds, 0),
  updated_at = now()
FROM public.users u
WHERE (m.user_id::text = u.uid::text OR m.host_uid::text = u.uid::text OR m.user_id::text = u.id::text)
  AND (
    COALESCE(m.diamonds, 0) <> COALESCE(u.diamonds, 0)
    OR COALESCE(m.diamonds_balance, 0) <> COALESCE(u.diamonds, 0)
    OR COALESCE(m.diamonds_available, 0) <> COALESCE(u.diamonds, 0)
  );

-- ب. تصحيح التراكمي ليكون دائماً >= إنتاج الشهر لنفس العضو (ترحيل بيانات قديمة فقط)
UPDATE public.host_agency_members
SET diamonds_earned_cumulative = diamonds_earned_monthly,
    updated_at = now()
WHERE COALESCE(diamonds_earned_cumulative, 0) < COALESCE(diamonds_earned_monthly, 0);

-- ج. توحيد محفظة الوكالة agency_wallets لمالك الوكالة (Cast-Safe 100%)
UPDATE public.agency_wallets w
SET diamond_balance = u.diamonds
FROM public.users u
WHERE (w.agency_profile_id::text = u.uid::text OR w.agency_profile_id::text = u.id::text);

-- د. إعادة حساب إجماليات الوكالات في host_agencies من مجموع الأعضاء
UPDATE public.host_agencies a
SET 
  total_diamonds_monthly = sub.total_monthly,
  monthly_diamonds = sub.total_monthly,
  total_diamonds_cumulative = sub.total_cumulative,
  total_diamonds_earned = sub.total_cumulative,
  updated_at = now()
FROM (
  SELECT agency_id::text AS agency_id,
         COALESCE(SUM(COALESCE(diamonds_earned_monthly, 0)), 0) AS total_monthly,
         COALESCE(SUM(COALESCE(diamonds_earned_cumulative, 0)), 0) AS total_cumulative
  FROM public.host_agency_members
  WHERE agency_id IS NOT NULL
  GROUP BY agency_id::text
) sub
WHERE a.id::text = sub.agency_id;

-- هـ. تصفير إجماليات أي وكالة ليس لديها أعضاء (بدلاً من إبقاء أرقام قديمة)
UPDATE public.host_agencies a
SET total_diamonds_monthly = 0,
    monthly_diamonds = 0,
    total_diamonds_cumulative = 0,
    total_diamonds_earned = 0,
    updated_at = now()
WHERE NOT EXISTS (
  SELECT 1 FROM public.host_agency_members m WHERE m.agency_id::text = a.id::text
);
