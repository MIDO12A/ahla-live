-- ==============================================================================
-- BACKEND DIAMOND SYNC & FINANCIAL ENGINE MIGRATION (v2 - Dynamic Auto-Healing)
-- محرك الربط المالي الموحد عبر الباك إند وقاعدة البيانات لجميع جداول الألماس
-- ==============================================================================

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

  -- أ. مزامنة الرصيد القابل للسحب وألماس الشهر في host_agency_members ليكونا متطابقين تماماً
  UPDATE public.host_agency_members
  SET 
    diamonds = NEW.diamonds,
    diamonds_balance = NEW.diamonds,
    diamonds_available = NEW.diamonds,
    diamonds_earned_monthly = NEW.diamonds,
    updated_at = now()
  WHERE user_id = v_uid_text 
     OR host_uid = v_uid_text
     OR (v_uid_uuid IS NOT NULL AND (user_id = v_uid_uuid::text OR host_uid = v_uid_uuid::text));

  -- ب. إذا كان المستخدم مالك وكالة، مزامنة محفظة الوكالة agency_wallets
  IF EXISTS (
    SELECT 1 FROM public.host_agencies 
    WHERE owner_uid = v_uid_text OR owner_id = v_uid_text
  ) THEN
    UPDATE public.agency_wallets
    SET 
      diamond_balance = NEW.diamonds,
      updated_at = now()
    WHERE (v_uid_uuid IS NOT NULL AND agency_profile_id = v_uid_uuid);
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

-- 3. دالة التريجر العكسي من جدول host_agency_members: توحيد رصيد السحب وألماس الشهر ونقله لـ users
CREATE OR REPLACE FUNCTION public.trg_sync_agency_member_diamonds_to_user()
RETURNS TRIGGER AS $$
DECLARE
  v_target_diamonds bigint;
  v_uid_text text;
BEGIN
  -- منع التكرار اللانهائي
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  -- توحيد القيمة لأعلى رقم متاح أو المتغير الجديد
  v_target_diamonds := GREATEST(
    COALESCE(NEW.diamonds_earned_monthly, 0),
    COALESCE(NEW.diamonds_balance, 0),
    COALESCE(NEW.diamonds, 0)
  );

  NEW.diamonds := v_target_diamonds;
  NEW.diamonds_balance := v_target_diamonds;
  NEW.diamonds_available := v_target_diamonds;
  NEW.diamonds_earned_monthly := v_target_diamonds;

  v_uid_text := COALESCE(NEW.user_id, NEW.host_uid);
  IF v_uid_text IS NOT NULL AND v_uid_text <> '' THEN
    UPDATE public.users
    SET diamonds = v_target_diamonds
    WHERE uid = v_uid_text OR id::text = v_uid_text;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_agency_member_diamonds ON public.host_agency_members;
CREATE TRIGGER trg_sync_agency_member_diamonds
  BEFORE UPDATE OF diamonds, diamonds_balance, diamonds_earned_monthly ON public.host_agency_members
  FOR EACH ROW
  WHEN (
    OLD.diamonds IS DISTINCT FROM NEW.diamonds OR 
    OLD.diamonds_balance IS DISTINCT FROM NEW.diamonds_balance OR
    OLD.diamonds_earned_monthly IS DISTINCT FROM NEW.diamonds_earned_monthly
  )
  EXECUTE FUNCTION public.trg_sync_agency_member_diamonds_to_user();

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
  v_total_monthly bigint;
  v_total_cum bigint;
BEGIN
  v_abs_amount := ABS(p_amount);
  IF v_abs_amount <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'المبلغ يجب أن يكون أكبر من صفر');
  END IF;

  -- 1. جلب رصيد المستخدم الحالي مع قفل الصف لمنع تضارب المعاملات (FOR UPDATE)
  SELECT diamonds INTO v_current_diamonds
  FROM public.users
  WHERE uid = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
  END IF;

  v_current_diamonds := COALESCE(v_current_diamonds, 0);

  -- 2. حساب الرصيد الجديد
  IF p_type = 'add' THEN
    v_diff := v_abs_amount;
    v_new_diamonds := v_current_diamonds + v_abs_amount;
  ELSE
    v_diff := -v_abs_amount;
    v_new_diamonds := GREATEST(0, v_current_diamonds - v_abs_amount);
  END IF;

  -- 3. تحديث جدول المستخدمين (سوف يطلق التريجر التلقائي أيضاً للمحفظة والوكالة)
  UPDATE public.users
  SET diamonds = v_new_diamonds
  WHERE uid = p_user_id;

  -- 4. فحص عضوية الوكالة وتحديث بياناتها
  SELECT id, agency_id, diamonds_earned_monthly, diamonds_earned_cumulative
  INTO v_member_record
  FROM public.host_agency_members
  WHERE user_id = p_user_id OR host_uid = p_user_id
  LIMIT 1;

  IF FOUND THEN
    v_agency_id := v_member_record.agency_id;

    UPDATE public.host_agency_members
    SET 
      diamonds = v_new_diamonds,
      diamonds_balance = v_new_diamonds,
      diamonds_available = v_new_diamonds,
      diamonds_earned_monthly = v_new_diamonds,
      diamonds_earned_cumulative = GREATEST(COALESCE(diamonds_earned_cumulative, 0), v_new_diamonds),
      updated_at = now()
    WHERE id = v_member_record.id;

    -- إعادة حساب إجمالي الوكالة كاملاً
    IF v_agency_id IS NOT NULL AND v_agency_id <> '' THEN
      SELECT 
        COALESCE(SUM(diamonds_earned_monthly), 0),
        COALESCE(SUM(diamonds_earned_cumulative), 0)
      INTO v_total_monthly, v_total_cum
      FROM public.host_agency_members
      WHERE agency_id = v_agency_id;

      UPDATE public.host_agencies
      SET 
        total_diamonds_monthly = v_total_monthly,
        total_diamonds_cumulative = v_total_cum,
        monthly_diamonds = v_total_monthly,
        updated_at = now()
      WHERE id = v_agency_id;
    END IF;
  END IF;

  -- 5. تسجيل العملية في سجل الألماس user_diamond_logs
  BEGIN
    v_user_uuid := p_user_id::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_user_uuid := NULL;
  END;

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
-- أ. توحيد رصيد السحب وألماس الشهر في host_agency_members لأعلى قيمة محققة
UPDATE public.host_agency_members
SET 
  diamonds = GREATEST(COALESCE(diamonds_earned_monthly, 0), COALESCE(diamonds_balance, 0), COALESCE(diamonds, 0)),
  diamonds_balance = GREATEST(COALESCE(diamonds_earned_monthly, 0), COALESCE(diamonds_balance, 0), COALESCE(diamonds, 0)),
  diamonds_available = GREATEST(COALESCE(diamonds_earned_monthly, 0), COALESCE(diamonds_balance, 0), COALESCE(diamonds, 0)),
  diamonds_earned_monthly = GREATEST(COALESCE(diamonds_earned_monthly, 0), COALESCE(diamonds_balance, 0), COALESCE(diamonds, 0)),
  updated_at = now();

-- ب. توحيد جدول users لمطابقة الرصيد الموحد
UPDATE public.users u
SET diamonds = m.diamonds_balance
FROM public.host_agency_members m
WHERE (m.user_id = u.uid OR m.host_uid = u.uid OR m.user_id = u.id::text)
  AND m.diamonds_balance IS NOT NULL
  AND m.diamonds_balance <> COALESCE(u.diamonds, 0);

-- ج. إعادة حساب إجماليات الوكالات في host_agencies
UPDATE public.host_agencies a
SET 
  total_diamonds_monthly = sub.total_monthly,
  monthly_diamonds = sub.total_monthly
FROM (
  SELECT agency_id, COALESCE(SUM(diamonds_earned_monthly), 0) AS total_monthly
  FROM public.host_agency_members
  GROUP BY agency_id
) sub
WHERE a.id = sub.agency_id;
