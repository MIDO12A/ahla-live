-- ============================================================
-- إصلاح نظام عمولات الوكالة (Agency Commission)
-- ------------------------------------------------------------
-- المشاكل التي يعالجها هذا الملف:
--  1) دالة agency_accrue_commission غير موجودة في قاعدة البيانات،
--     والمسار الأساسي agency_credit_host_target_diamonds ينجح قبل
--     الوصول للاحتياط — لذا pending_commission_diamonds يبقى 0 دائماً.
--     الحل: Trigger على host_agency_members يحتسب العمولة المعلقة
--     تلقائياً عند أي زيادة في أرباح الماس — يغطي كل مسارات الإيداع.
--  2) المنطقة الزمنية 'Asia/Cairo' غير معروفة لـ Postgres
--     (الصحيح Africa/Cairo) — تُفشل agency_compute_next_release
--     فيبقى next_commission_release_at = NULL فلا يُصدر شيء تلقائياً.
--  3) لا يوجد مجدول دوري يستدعي agency_release_due_commissions —
--     نضيف مهمة pg_cron كل ساعة (إن كانت الإضافة متاحة).
--
-- شغّل هذا الملف كاملاً في Supabase Dashboard → SQL Editor.
-- ============================================================

-- ─── 1) إصلاح المنطقة الزمنية ────────────────────────────────────────
UPDATE public.app_config
SET value = jsonb_set(value::jsonb, '{timezone}', to_jsonb('Africa/Cairo'::text))
WHERE key = 'agency_commission_cycle'
  AND value::jsonb ->> 'timezone' = 'Asia/Cairo';

-- ─── 2) دالة احتساب العمولة المعلقة ──────────────────────────────────
-- تستدعيها الـ Trigger وأي مسار احتياطي في التطبيق.
CREATE OR REPLACE FUNCTION public.agency_accrue_commission(
  p_agency_id text,
  p_diamonds integer,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pending integer;
BEGIN
  IF p_agency_id IS NULL OR p_agency_id = '' OR COALESCE(p_diamonds, 0) <= 0 THEN
    RETURN jsonb_build_object('status', 'invalid', 'credited', 0);
  END IF;

  UPDATE public.host_agencies
  SET pending_commission_diamonds =
        COALESCE(pending_commission_diamonds, 0) + p_diamonds
  WHERE id::text = p_agency_id
  RETURNING pending_commission_diamonds INTO v_pending;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'agency_not_found', 'credited', 0);
  END IF;

  RETURN jsonb_build_object(
    'status', 'ok',
    'credited', p_diamonds,
    'pending', v_pending
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.agency_accrue_commission(text, integer, text)
  TO authenticated, service_role, anon;

-- ─── 3) دالة الـ Trigger: احتساب العمولة عند زيادة أرباح الماس ──────
-- تُطلق عند أي UPDATE على صف عضو الوكالة. تحتسب الفرق في الأرباح
-- (أكبر فرق بين العمودين الشهري والتراكمي — أحدهما قد لا يتحدث في
-- بعض المسارات) وتضيف نسبة العمولة إلى pending_commission_diamonds.
-- لا تُحتسب عمولة على أرباح مالك الوكالة نفسه.
CREATE OR REPLACE FUNCTION public.trg_accrue_agency_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delta_monthly   integer;
  v_delta_cumulative integer;
  v_delta          integer;
  v_owner_uid      text;
  v_rate_text      text;
  v_rate           numeric;
  v_commission     integer;
BEGIN
  IF NEW.agency_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_delta_monthly :=
    COALESCE(NEW.diamonds_earned_monthly, 0)
    - COALESCE(OLD.diamonds_earned_monthly, 0);
  v_delta_cumulative :=
    COALESCE(NEW.diamonds_earned_cumulative, 0)
    - COALESCE(OLD.diamonds_earned_cumulative, 0);

  -- نأخذ أكبر فرق موجب — يغطي المسارات التي تحدّث أحد العمودين فقط.
  v_delta := GREATEST(v_delta_monthly, v_delta_cumulative, 0);
  IF v_delta <= 0 THEN
    RETURN NEW;
  END IF;

  -- هوية مالك الوكالة (عمود مباشر أو دور owner في الأعضاء)
  SELECT owner_uid::text INTO v_owner_uid
  FROM public.host_agencies
  WHERE id::text = NEW.agency_id::text
  LIMIT 1;

  IF v_owner_uid IS NULL OR v_owner_uid = '' THEN
    SELECT COALESCE(user_id, host_uid)::text INTO v_owner_uid
    FROM public.host_agency_members
    WHERE agency_id::text = NEW.agency_id::text
      AND role = 'owner'
    LIMIT 1;
  END IF;

  -- المالك لا يدفع عمولة لنفسه
  IF v_owner_uid IS NOT NULL AND v_owner_uid <> '' AND (
       COALESCE(NEW.user_id::text, '') = v_owner_uid
    OR COALESCE(NEW.host_uid::text, '') = v_owner_uid
  ) THEN
    RETURN NEW;
  END IF;

  -- نسبة العمولة من app_config: agency_rate ثم agency_financial_policy
  -- (أي خطأ في قراءة الإعدادات يجب ألا يُسقط تحديث العضو — نلتقطه هنا)
  BEGIN
    v_rate := NULL;
    SELECT value::text INTO v_rate_text
    FROM public.app_config WHERE key = 'agency_rate' LIMIT 1;
    IF v_rate_text IS NOT NULL THEN
      v_rate := NULLIF(regexp_replace(v_rate_text, '[^0-9.]', '', 'g'), '')::numeric;
    END IF;
    IF v_rate IS NULL OR v_rate <= 0 THEN
      SELECT (value::jsonb ->> 'agency_rate_pct')::numeric INTO v_rate
      FROM public.app_config WHERE key = 'agency_financial_policy' LIMIT 1;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_rate := NULL;
  END;
  IF v_rate IS NULL OR v_rate <= 0 THEN
    v_rate := 20; -- الافتراضي مثل لوحة التحكم
  END IF;
  IF v_rate <= 1 THEN
    v_rate := v_rate * 100; -- 0.12 → 12
  END IF;

  v_commission := ROUND(v_delta * v_rate / 100.0)::integer;
  IF v_commission <= 0 THEN
    RETURN NEW;
  END IF;

  UPDATE public.host_agencies
  SET pending_commission_diamonds =
        COALESCE(pending_commission_diamonds, 0) + v_commission
  WHERE id::text = NEW.agency_id::text;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_accrue_agency_commission ON public.host_agency_members;
CREATE TRIGGER trg_accrue_agency_commission
AFTER UPDATE ON public.host_agency_members
FOR EACH ROW
EXECUTE FUNCTION public.trg_accrue_agency_commission();

-- ─── 4) إعادة حساب موعد الإصدار القادم بعد إصلاح التوقيت ────────────
DO $$
DECLARE
  v_next timestamptz;
BEGIN
  SELECT public.agency_compute_next_release() INTO v_next;
  IF v_next IS NOT NULL THEN
    UPDATE public.host_agencies
    SET next_commission_release_at = v_next;
  END IF;
END $$;

-- ─── 5) مجدول الإصدار التلقائي (pg_cron — كل ساعة) ──────────────────
-- agency_release_due_commissions يفرز العمولات المستحقة حسب
-- next_commission_release_at، فإن لم تكن الإضافة متاحة تُدار يدوياً
-- من اللوحة أو عند فتح شاشة الصرف في التطبيق.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'agency-release-due-commissions') THEN
      PERFORM cron.unschedule('agency-release-due-commissions');
    END IF;
    PERFORM cron.schedule(
      'agency-release-due-commissions',
      '17 * * * *',
      'SELECT public.agency_release_due_commissions()'
    );
  END IF;
END $$;
