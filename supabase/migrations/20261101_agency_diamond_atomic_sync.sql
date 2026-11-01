-- ============================================================================
-- 20261101_agency_diamond_atomic_sync.sql
-- إصلاح جذري لمزامنة أرصدة الوكالة:
--   1) مصدر واحد للحقيقة (users.diamonds) + مزامنة صريحة لبقية الجداول.
--   2) إزالة التريجرات المتضاربة التي كانت تُعيد القيم القديمة أو تُصفّر
--      "ألماس الشهر" أو تُضاعف الهدايا.
--   3) دوال RPC ذرية (Atomic) للهدايا، تعديل الأدمن، وطلبات السحب.
--
-- آمن للتشغيل المتكرر (Idempotent).
-- ============================================================================

-- ─────────────────────────────────────────────────────────────
-- 0) أعمدة مفقودة / توافق المخطط
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.host_agency_members ADD COLUMN IF NOT EXISTS diamonds bigint DEFAULT 0;
ALTER TABLE public.host_agency_members ADD COLUMN IF NOT EXISTS diamonds_balance bigint DEFAULT 0;
ALTER TABLE public.host_agency_members ADD COLUMN IF NOT EXISTS diamonds_available bigint DEFAULT 0;
ALTER TABLE public.host_agency_members ADD COLUMN IF NOT EXISTS diamonds_earned_monthly bigint DEFAULT 0;
ALTER TABLE public.host_agency_members ADD COLUMN IF NOT EXISTS diamonds_earned_cumulative bigint DEFAULT 0;
ALTER TABLE public.host_agency_members ADD COLUMN IF NOT EXISTS diamonds_pending_withdrawal bigint DEFAULT 0;
ALTER TABLE public.host_agency_members ADD COLUMN IF NOT EXISTS user_id text;
ALTER TABLE public.host_agency_members ADD COLUMN IF NOT EXISTS host_uid text;
ALTER TABLE public.host_agency_members ADD COLUMN IF NOT EXISTS status text DEFAULT 'active';
ALTER TABLE public.host_agency_members ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE public.host_agencies ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE public.host_agencies ADD COLUMN IF NOT EXISTS owner_uid text;
ALTER TABLE public.host_agencies ADD COLUMN IF NOT EXISTS owner_id text;
ALTER TABLE public.host_agencies ADD COLUMN IF NOT EXISTS total_diamonds_monthly bigint DEFAULT 0;
ALTER TABLE public.host_agencies ADD COLUMN IF NOT EXISTS monthly_diamonds bigint DEFAULT 0;
ALTER TABLE public.host_agencies ADD COLUMN IF NOT EXISTS total_diamonds_cumulative bigint DEFAULT 0;
ALTER TABLE public.host_agencies ADD COLUMN IF NOT EXISTS total_diamonds_earned bigint DEFAULT 0;

ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS agency_id text;
ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS owner_uid text;
ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS diamond_balance bigint DEFAULT 0;
ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS gold_balance bigint DEFAULT 0;
ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS total_received bigint DEFAULT 0;
ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS total_withdrawn bigint DEFAULT 0;
ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- محفظة الوكالة: السماح بصف لكل وكالة عبر agency_id
-- (المخطط القديم كان يجعل agency_profile_id مفتاحاً أساسياً إلزامياً،
--  ولهذا كانت كل عمليات الإدخال بالكود تفشل بصمت.)
DO $$
DECLARE
  v_pk text;
  v_def text;
BEGIN
  SELECT conname, pg_get_constraintdef(oid)
  INTO v_pk, v_def
  FROM pg_constraint
  WHERE conrelid = 'public.agency_wallets'::regclass AND contype = 'p';

  -- نحذف المفتاح الأساسي فقط إذا كان على agency_profile_id (المخطط القديم)
  IF v_pk IS NOT NULL AND v_def ILIKE '%agency_profile_id%' THEN
    EXECUTE format('ALTER TABLE public.agency_wallets DROP CONSTRAINT %I', v_pk);
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'agency_wallets'
      AND column_name = 'agency_profile_id'
  ) THEN
    EXECUTE 'ALTER TABLE public.agency_wallets ALTER COLUMN agency_profile_id DROP NOT NULL';
  END IF;
END $$;

-- دمج أي صفوف مكررة قبل فرض التفرد على agency_id
DELETE FROM public.agency_wallets w
USING public.agency_wallets w2
WHERE w.agency_id IS NOT NULL
  AND w.agency_id = w2.agency_id
  AND (
    COALESCE(w.diamond_balance, 0) < COALESCE(w2.diamond_balance, 0)
    OR (COALESCE(w.diamond_balance, 0) = COALESCE(w2.diamond_balance, 0) AND w.ctid < w2.ctid)
  );

CREATE UNIQUE INDEX IF NOT EXISTS uq_agency_wallets_agency_id
  ON public.agency_wallets (agency_id)
  WHERE agency_id IS NOT NULL;

ALTER TABLE public.agency_diamond_ledger ADD COLUMN IF NOT EXISTS balance_after bigint DEFAULT 0;
ALTER TABLE public.agency_diamond_ledger ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE public.agency_diamond_ledger ADD COLUMN IF NOT EXISTS sender_id text;
ALTER TABLE public.agency_diamond_ledger ADD COLUMN IF NOT EXISTS sender_name text;
ALTER TABLE public.agency_diamond_ledger ADD COLUMN IF NOT EXISTS gift_name text;
ALTER TABLE public.agency_diamond_ledger ADD COLUMN IF NOT EXISTS idempotency_key text;

DELETE FROM public.agency_diamond_ledger a
USING public.agency_diamond_ledger b
WHERE a.idempotency_key IS NOT NULL
  AND a.idempotency_key = b.idempotency_key
  AND a.ctid < b.ctid;

CREATE UNIQUE INDEX IF NOT EXISTS uq_adl_idempotency_key
  ON public.agency_diamond_ledger (idempotency_key);

ALTER TABLE public.agency_withdrawal_requests ADD COLUMN IF NOT EXISTS amount bigint;
ALTER TABLE public.agency_withdrawal_requests ADD COLUMN IF NOT EXISTS details jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.agency_withdrawal_requests ADD COLUMN IF NOT EXISTS user_id text;
ALTER TABLE public.agency_withdrawal_requests ADD COLUMN IF NOT EXISTS diamonds_amount bigint;
ALTER TABLE public.agency_withdrawal_requests ADD COLUMN IF NOT EXISTS payment_details jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.agency_withdrawal_requests ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;
ALTER TABLE public.agency_withdrawal_requests ADD COLUMN IF NOT EXISTS reviewed_by uuid;
ALTER TABLE public.agency_withdrawal_requests ADD COLUMN IF NOT EXISTS admin_notes text;

-- سجل ألماس المستخدم (قد لا يكون موجوداً على بعض المشاريع)
CREATE TABLE IF NOT EXISTS public.user_diamond_logs (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL,
  amount         bigint NOT NULL,
  type           text NOT NULL,
  balance_before bigint,
  balance_after  bigint,
  admin_name     text DEFAULT 'الإدارة',
  reason         text,
  metadata       jsonb DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_diamond_logs ADD COLUMN IF NOT EXISTS admin_name text DEFAULT 'الإدارة';
ALTER TABLE public.user_diamond_logs ADD COLUMN IF NOT EXISTS reason text;
ALTER TABLE public.user_diamond_logs ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT '{}'::jsonb;

-- توحيد القيم القديمة (بدون تصفير الشهر)
UPDATE public.host_agency_members
SET diamonds = diamonds_balance
WHERE COALESCE(diamonds, 0) = 0 AND COALESCE(diamonds_balance, 0) > 0;

UPDATE public.host_agency_members
SET diamonds_balance = diamonds
WHERE COALESCE(diamonds_balance, 0) = 0 AND COALESCE(diamonds, 0) > 0;

UPDATE public.host_agency_members
SET diamonds_available = diamonds_balance
WHERE COALESCE(diamonds_available, 0) = 0 AND COALESCE(diamonds_balance, 0) > 0;

UPDATE public.host_agencies
SET monthly_diamonds = total_diamonds_monthly
WHERE COALESCE(monthly_diamonds, 0) = 0 AND COALESCE(total_diamonds_monthly, 0) > 0;

-- ─────────────────────────────────────────────────────────────
-- 1) إزالة التريجرات المتضاربة
--    كانت:
--      * trg_sync_user_diamonds          → يفرض monthly = رصيد المستخدم
--      * trg_sync_agency_member_diamonds → يعيد GREATEST(...) إلى users
--    والنتيجة: أرقام متضاربة + خصومات تبدو غير مطبقة + مضاعفة هدايا.
-- ─────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_sync_user_diamonds ON public.users;
DROP TRIGGER IF EXISTS trg_sync_agency_member_diamonds ON public.host_agency_members;

-- ─────────────────────────────────────────────────────────────
-- 2) إعادة حساب إجماليات الوكالة من أعضائها
-- ─────────────────────────────────────────────────────────────
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
  IF p_agency_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(SUM(COALESCE(diamonds_earned_monthly, 0)), 0),
         COALESCE(SUM(COALESCE(diamonds_earned_cumulative, 0)), 0)
  INTO v_monthly, v_cum
  FROM public.host_agency_members
  WHERE agency_id = p_agency_id;

  UPDATE public.host_agencies
  SET total_diamonds_monthly = v_monthly,
      monthly_diamonds = v_monthly,
      total_diamonds_cumulative = v_cum,
      total_diamonds_earned = v_cum,
      updated_at = now()
  WHERE id = p_agency_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.agency_recalc_totals(text) TO authenticated, service_role, anon;

-- ─────────────────────────────────────────────────────────────
-- 3) RPC ذري لإضافة ألماس هدية للمضيف + عمولة الوكالة
--    - يحدّث users.diamonds + host_agency_members + host_agencies
--    - يضيف عمولة المالك إلى agency_wallets (حتى لو كان المالك هو المضيف)
--    - يسجل في agency_diamond_ledger مع idempotency
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.agency_credit_gift_diamonds(
  p_host_uid text,
  p_diamonds bigint,
  p_agency_rate_pct numeric DEFAULT NULL,
  p_idem_key text DEFAULT NULL,
  p_source text DEFAULT 'gift'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member record;
  v_agency_id text;
  v_owner_uid text;
  v_user_uuid uuid;
  v_rate numeric := 0;
  v_commission bigint := 0;
  v_new_balance bigint := 0;
  v_idem text;
BEGIN
  IF p_host_uid IS NULL OR p_host_uid = '' OR COALESCE(p_diamonds, 0) <= 0 THEN
    RETURN jsonb_build_object('status', 'error', 'error', 'invalid_input');
  END IF;

  v_idem := NULLIF(p_idem_key, '');
  IF v_idem IS NULL THEN
    v_idem := p_source || '_' || p_host_uid || '_' || gen_random_uuid()::text;
  END IF;

  -- Idempotency
  IF EXISTS (SELECT 1 FROM public.agency_diamond_ledger WHERE idempotency_key = v_idem) THEN
    RETURN jsonb_build_object('status', 'already_processed', 'idem_key', v_idem);
  END IF;

  BEGIN
    v_user_uuid := p_host_uid::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_user_uuid := NULL;
  END;

  -- 1) رصيد المستخدم (المصدر الموحد)
  UPDATE public.users
  SET diamonds = COALESCE(diamonds, 0) + p_diamonds,
      updated_at = now()
  WHERE uid::text = p_host_uid OR id::text = p_host_uid;

  -- 2) عضوية الوكالة
  SELECT *
  INTO v_member
  FROM public.host_agency_members
  WHERE (user_id::text = p_host_uid OR host_uid::text = p_host_uid)
    AND COALESCE(status, 'active') <> 'kicked'
  ORDER BY joined_at NULLS LAST
  LIMIT 1;

  IF v_member.id IS NOT NULL THEN
    v_agency_id := v_member.agency_id;
    v_new_balance := COALESCE(v_member.diamonds_balance, v_member.diamonds, 0) + p_diamonds;

    UPDATE public.host_agency_members
    SET diamonds = COALESCE(diamonds, 0) + p_diamonds,
        diamonds_balance = COALESCE(diamonds_balance, 0) + p_diamonds,
        diamonds_available = COALESCE(diamonds_available, 0) + p_diamonds,
        diamonds_earned_monthly = COALESCE(diamonds_earned_monthly, 0) + p_diamonds,
        diamonds_earned_cumulative = COALESCE(diamonds_earned_cumulative, 0) + p_diamonds
    WHERE id = v_member.id;

    -- 3) عمولة الوكالة (تُضاف فوق نصيب المضيف بدون خصم منه)
    IF v_agency_id IS NOT NULL THEN
      SELECT COALESCE(NULLIF(owner_uid, ''), owner_id::text)
      INTO v_owner_uid
      FROM public.host_agencies
      WHERE id = v_agency_id;

      IF p_agency_rate_pct IS NOT NULL AND p_agency_rate_pct > 0 THEN
        -- النسبة تأتي كنسبة مئوية (مثال: 20 تعني 20%)
        v_rate := p_agency_rate_pct / 100.0;
      ELSE
        -- مصدر الحقيقة: app_config.agency_rate (نسبة مئوية)
        BEGIN
          SELECT (value::text)::numeric INTO v_rate
          FROM public.app_config WHERE key = 'agency_rate';
        EXCEPTION WHEN OTHERS THEN
          v_rate := NULL;
        END;
        IF v_rate IS NULL OR v_rate <= 0 THEN
          SELECT percentage INTO v_rate FROM public.commission_settings WHERE key = 'agency_rate';
        END IF;
        v_rate := COALESCE(v_rate, 20);
        IF v_rate > 1 THEN
          v_rate := v_rate / 100.0;
        END IF;
      END IF;

      v_commission := ROUND(p_diamonds * v_rate)::bigint;

      IF v_commission > 0 THEN
        BEGIN
          UPDATE public.agency_wallets
          SET diamond_balance = COALESCE(diamond_balance, 0) + v_commission,
              total_received = COALESCE(total_received, 0) + v_commission,
              owner_uid = COALESCE(owner_uid, v_owner_uid),
              updated_at = now()
          WHERE agency_id = v_agency_id;

          IF NOT FOUND THEN
            INSERT INTO public.agency_wallets
              (agency_id, owner_uid, diamond_balance,
               gold_balance, total_received, total_withdrawn, updated_at)
            VALUES
              (v_agency_id, v_owner_uid, v_commission,
               0, v_commission, 0, now());
          END IF;
        EXCEPTION WHEN OTHERS THEN
          -- لا نُفشل الهدية بسبب محفظة الوكالة
          RAISE WARNING 'agency_credit_gift_diamonds wallet error: %', SQLERRM;
        END;
      END IF;

      -- إعادة حساب إجماليات الوكالة
      PERFORM public.agency_recalc_totals(v_agency_id);

      -- سجل الوكالة
      IF v_user_uuid IS NOT NULL THEN
        INSERT INTO public.agency_diamond_ledger
          (agency_id, user_id, txn_type, amount, direction, balance_after,
           note, sender_name, gift_name, idempotency_key, created_at)
        VALUES
          (v_agency_id, v_user_uuid::text, p_source, p_diamonds, 1, v_new_balance,
           'هدية/دخل ألماس', NULL, p_source, v_idem, now())
        ON CONFLICT (idempotency_key) DO NOTHING;
      END IF;
    END IF;

    RETURN jsonb_build_object(
      'status', 'ok',
      'agency_id', v_agency_id,
      'balance', v_new_balance,
      'commission', v_commission
    );
  END IF;

  -- ليس عضواً في وكالة: تم تحديث users.diamonds فقط
  RETURN jsonb_build_object('status', 'not_member', 'credited', p_diamonds);
END;
$$;

GRANT EXECUTE ON FUNCTION public.agency_credit_gift_diamonds(text, bigint, numeric, text, text)
  TO authenticated, service_role, anon;

-- ─────────────────────────────────────────────────────────────
-- 4) RPC مركزي معدّل لتعديل ألماس المستخدم من الأدمن
--    (يستخدم الفرق delta بدل إعادة تعيين "ألماس الشهر")
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_process_diamond_transaction(
  p_user_id text,
  p_amount bigint,
  p_type text,
  p_reason text DEFAULT 'تعديل رصيد من الإدارة',
  p_admin_name text DEFAULT 'الإدارة',
  p_sync_monthly_target boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current bigint := 0;
  v_new bigint := 0;
  v_abs bigint;
  v_diff bigint;
  v_user_uuid uuid;
  v_member record;
  v_agency_id text;
BEGIN
  v_abs := ABS(p_amount);
  IF v_abs <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'المبلغ يجب أن يكون أكبر من صفر');
  END IF;

  BEGIN
    v_user_uuid := p_user_id::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_user_uuid := NULL;
  END;

  SELECT diamonds INTO v_current
  FROM public.users
  WHERE uid::text = p_user_id OR id::text = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
  END IF;

  v_current := COALESCE(v_current, 0);
  IF p_type = 'add' THEN
    v_diff := v_abs;
    v_new := v_current + v_abs;
  ELSE
    v_diff := -v_abs;
    v_new := GREATEST(0, v_current - v_abs);
  END IF;

  UPDATE public.users
  SET diamonds = v_new, updated_at = now()
  WHERE uid::text = p_user_id OR id::text = p_user_id;

  SELECT * INTO v_member
  FROM public.host_agency_members
  WHERE user_id::text = p_user_id OR host_uid::text = p_user_id
  LIMIT 1;

  IF v_member.id IS NOT NULL THEN
    v_agency_id := v_member.agency_id;

    UPDATE public.host_agency_members
    SET diamonds = v_new,
        diamonds_balance = v_new,
        diamonds_available = v_new,
        diamonds_earned_monthly = CASE
          WHEN p_sync_monthly_target
            THEN GREATEST(0, COALESCE(diamonds_earned_monthly, 0) + v_diff)
          ELSE COALESCE(diamonds_earned_monthly, 0)
        END,
        diamonds_earned_cumulative = GREATEST(0, COALESCE(diamonds_earned_cumulative, 0) + v_diff)
    WHERE id = v_member.id;

    PERFORM public.agency_recalc_totals(v_agency_id);

    IF v_agency_id IS NOT NULL AND v_user_uuid IS NOT NULL THEN
      INSERT INTO public.agency_diamond_ledger
        (agency_id, user_id, txn_type, amount, direction, balance_after,
         note, sender_name, gift_name, created_at)
      VALUES
        (v_agency_id, v_user_uuid::text,
         CASE WHEN p_type = 'add' THEN 'admin_credit' ELSE 'admin_deduct' END,
         v_abs, CASE WHEN p_type = 'add' THEN 1 ELSE -1 END, v_new,
         p_reason, p_admin_name, p_reason, now());
    END IF;
  END IF;

  -- سجل المستخدم (لا نُفشل العملية إن لم يوجد الجدول/العمود)
  IF v_user_uuid IS NOT NULL THEN
    BEGIN
      INSERT INTO public.user_diamond_logs
        (user_id, amount, type, balance_before, balance_after, admin_name, reason, created_at)
      VALUES
        (v_user_uuid, v_diff,
         CASE WHEN p_type = 'add' THEN 'admin_add' ELSE 'admin_deduct' END,
         v_current, v_new, p_admin_name, p_reason, now());
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'user_diamond_logs insert skipped: %', SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'old_diamonds', v_current,
    'new_diamonds', v_new,
    'amount', v_abs,
    'type', p_type,
    'agency_synced', v_member.id IS NOT NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_process_diamond_transaction(text, bigint, text, text, text, boolean)
  TO authenticated, service_role, anon;

-- ─────────────────────────────────────────────────────────────
-- 5) RPC طلب سحب من المضيف (تجميد فوري + idempotency)
--    التوقيع مطابق لاستدعاء Flutter:
--      agency_request_withdrawal(p_diamonds, p_bank_details, p_idempotency_key)
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.agency_request_withdrawal(bigint, jsonb, text);
DROP FUNCTION IF EXISTS public.agency_request_withdrawal(bigint, text);

CREATE OR REPLACE FUNCTION public.agency_request_withdrawal(
  p_diamonds bigint,
  p_bank_details jsonb DEFAULT '{}'::jsonb,
  p_idempotency_key text DEFAULT NULL,
  p_user_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid text;
  v_member record;
  v_available bigint := 0;
  v_request_id uuid;
  v_per_usd numeric := 15000;
  v_net_usd numeric := 0;
  v_idem text;
BEGIN
  -- التطبيق يستخدم مفتاح anon، لذلك نأخذ المعرّف من الوسيط أو من الـ JWT
  v_uid := COALESCE(auth.uid()::text, NULLIF(p_user_id, ''));
  IF v_uid IS NULL OR v_uid = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthorized');
  END IF;

  IF COALESCE(p_diamonds, 0) <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_amount');
  END IF;

  v_idem := NULLIF(p_idempotency_key, '');
  IF v_idem IS NOT NULL THEN
    SELECT id INTO v_request_id
    FROM public.agency_withdrawal_requests
    WHERE user_id::text = v_uid
      AND (details->>'idempotency_key') = v_idem
    LIMIT 1;
    IF v_request_id IS NOT NULL THEN
      RETURN jsonb_build_object('success', true, 'request_id', v_request_id,
                                'duplicate', true, 'net_usd', 0);
    END IF;
  END IF;

  SELECT * INTO v_member
  FROM public.host_agency_members
  WHERE user_id::text = v_uid OR host_uid::text = v_uid
  LIMIT 1;

  IF v_member.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_member');
  END IF;

  v_available := COALESCE(v_member.diamonds_available, v_member.diamonds_balance, 0);
  IF v_available < p_diamonds THEN
    RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance',
                              'available', v_available);
  END IF;

  -- تجميد المبلغ: يُخصم من الرصيد المتاح/القابل للسحب ويُسجَّل كمعلّق
  UPDATE public.host_agency_members
  SET diamonds = GREATEST(0, COALESCE(diamonds, 0) - p_diamonds),
      diamonds_balance = GREATEST(0, COALESCE(diamonds_balance, 0) - p_diamonds),
      diamonds_available = GREATEST(0, COALESCE(diamonds_available, 0) - p_diamonds),
      diamonds_pending_withdrawal = COALESCE(diamonds_pending_withdrawal, 0) + p_diamonds
  WHERE id = v_member.id;

  -- خصم فوري من رصيد المستخدم حتى لا يُستهلك المبلغ المجمّد
  UPDATE public.users
  SET diamonds = GREATEST(0, COALESCE(diamonds, 0) - p_diamonds),
      updated_at = now()
  WHERE uid::text = v_uid OR id::text = v_uid;

  SELECT COALESCE(value, 15000) INTO v_per_usd
  FROM public.commission_settings WHERE key = 'diamonds_per_usd';
  v_per_usd := COALESCE(NULLIF(v_per_usd, 0), 15000);
  v_net_usd := ROUND((p_diamonds / v_per_usd)::numeric, 2);

  INSERT INTO public.agency_withdrawal_requests
    (user_id, agency_id, diamonds_amount, amount, payment_method,
     payment_details, details, status, created_at)
  VALUES
    (v_uid, v_member.agency_id, p_diamonds, p_diamonds,
     COALESCE(p_bank_details->>'method', 'bank_transfer'),
     p_bank_details,
     COALESCE(p_bank_details, '{}'::jsonb) || jsonb_build_object(
       'idempotency_key', COALESCE(v_idem, ''),
       'frozen', true),
     'pending', now())
  RETURNING id INTO v_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', v_request_id,
    'diamonds', p_diamonds,
    'net_usd', v_net_usd,
    'status', 'pending'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.agency_request_withdrawal(bigint, jsonb, text, text)
  TO authenticated, service_role, anon;

-- ─────────────────────────────────────────────────────────────
-- 6) RPC اعتماد/رفض السحب (يحرّك الأرصدة فعلياً)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.agency_approve_withdrawal(
  p_request_id uuid,
  p_admin_name text DEFAULT 'الإدارة'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req record;
  v_amount bigint;
BEGIN
  SELECT * INTO v_req
  FROM public.agency_withdrawal_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_req.status <> 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_status', 'status', v_req.status);
  END IF;

  v_amount := COALESCE(v_req.diamonds_amount, v_req.amount, 0);

  -- المبلغ مُجمّد مسبقاً: نُفرغ المعلّق فقط
  UPDATE public.host_agency_members
  SET diamonds_pending_withdrawal = GREATEST(0, COALESCE(diamonds_pending_withdrawal, 0) - v_amount)
  WHERE agency_id = v_req.agency_id
    AND (user_id::text = v_req.user_id::text OR host_uid::text = v_req.user_id::text);

  UPDATE public.agency_withdrawal_requests
  SET status = 'approved', reviewed_at = now(), admin_notes = p_admin_name
  WHERE id = p_request_id;

  RETURN jsonb_build_object('success', true, 'status', 'approved', 'amount', v_amount);
END;
$$;

CREATE OR REPLACE FUNCTION public.agency_reject_withdrawal(
  p_request_id uuid,
  p_admin_name text DEFAULT 'الإدارة',
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req record;
  v_amount bigint;
  v_frozen boolean := false;
BEGIN
  SELECT * INTO v_req
  FROM public.agency_withdrawal_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_req.status <> 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_status', 'status', v_req.status);
  END IF;

  v_amount := COALESCE(v_req.diamonds_amount, v_req.amount, 0);
  v_frozen := COALESCE((v_req.details->>'frozen')::boolean, false);

  IF v_frozen THEN
    -- إعادة المبلغ المجمّد إلى الرصيد المتاح + رصيد المستخدم
    UPDATE public.host_agency_members
    SET diamonds = COALESCE(diamonds, 0) + v_amount,
        diamonds_balance = COALESCE(diamonds_balance, 0) + v_amount,
        diamonds_available = COALESCE(diamonds_available, 0) + v_amount,
        diamonds_pending_withdrawal = GREATEST(0, COALESCE(diamonds_pending_withdrawal, 0) - v_amount)
    WHERE agency_id = v_req.agency_id
      AND (user_id::text = v_req.user_id::text OR host_uid::text = v_req.user_id::text);

    IF v_req.user_id IS NOT NULL THEN
      UPDATE public.users
      SET diamonds = COALESCE(diamonds, 0) + v_amount,
          updated_at = now()
      WHERE uid::text = v_req.user_id::text OR id::text = v_req.user_id::text;
    END IF;
  END IF;

  UPDATE public.agency_withdrawal_requests
  SET status = 'rejected', reviewed_at = now(),
      admin_notes = COALESCE(p_notes, p_admin_name)
  WHERE id = p_request_id;

  RETURN jsonb_build_object('success', true, 'status', 'rejected', 'amount', v_amount);
END;
$$;

GRANT EXECUTE ON FUNCTION public.agency_approve_withdrawal(uuid, text) TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.agency_reject_withdrawal(uuid, text, text) TO authenticated, service_role, anon;

-- ─────────────────────────────────────────────────────────────
-- 7) مزامنة البيانات الحالية مرة واحدة (إصلاح الأرقام القائمة)
-- ─────────────────────────────────────────────────────────────
-- users.diamonds هو المصدر الموحد: نُعيد ضبط عضوية الوكالة عليه (مع احترام المجمّد)
UPDATE public.host_agency_members m
SET diamonds = u.diamonds,
    diamonds_balance = u.diamonds,
    diamonds_available = GREATEST(0, u.diamonds - COALESCE(m.diamonds_pending_withdrawal, 0))
FROM public.users u
WHERE COALESCE(m.user_id::text, m.host_uid) = u.uid::text
  AND (
    COALESCE(m.diamonds, 0) <> COALESCE(u.diamonds, 0)
    OR COALESCE(m.diamonds_balance, 0) <> COALESCE(u.diamonds, 0)
  );

UPDATE public.host_agency_members m
SET diamonds_available = GREATEST(0, COALESCE(m.diamonds_balance, 0) - COALESCE(m.diamonds_pending_withdrawal, 0))
WHERE COALESCE(m.diamonds_available, 0)
      <> GREATEST(0, COALESCE(m.diamonds_balance, 0) - COALESCE(m.diamonds_pending_withdrawal, 0));

DO $$
DECLARE
  v_agency text;
BEGIN
  FOR v_agency IN SELECT id::text FROM public.host_agencies LOOP
    PERFORM public.agency_recalc_totals(v_agency);
  END LOOP;
END $$;
