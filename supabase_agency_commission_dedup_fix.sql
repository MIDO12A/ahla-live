-- ============================================================
-- إصلاح ازدواج احتساب عمولة الوكالة (Double Commission Accrual)
-- ------------------------------------------------------------
-- المشكلة (مُثبتة بتجربة على transaction مُلغاة):
--   agency_credit_host_target_diamonds كان يضيف العمولة يدوياً إلى
--   pending_commission_diamonds، وفي نفس الوقت الـ Trigger
--   trg_accrue_agency_commission يلتقط نفس الزيادة في
--   diamonds_earned_* ويضيف العمولة مرة ثانية.
--   النتيجة: كل هدية لمضيف عضو وكالة تُحتسب عمولتها مرتين
--   (مثال: 1000 ماسة بنسبة 12% → pending += 240 بدل 120).
--
-- الحل:
--   1) إزالة كتلة الـ UPDATE اليدوي من
--      agency_credit_host_target_diamonds — الـ Trigger هو
--      نقطة الاحتساب الوحيدة لكل مسارات الإيداع
--      (credit_user_diamonds + المسار الاحتياطي في التطبيق).
--   2) حذف النسخة المكررة agency_accrue_commission(text,integer,text)
--      التي أنشأها supabase_agency_commission_fix.sql — بقيت
--      النسخة الأقدم (text,bigint,text) وهي الأغنى (تكتب
--      agency_diamond_ledger وتضبط next_commission_release_at).
--      الازدواج يُربك استدعاءات RPC (integer مقابل bigint).
--   3) إلغاء مهمة cron القديمة 'agency-commission-release'
--      (كل 5 دقائق) — المهمة المعتمدة هي
--      'agency-release-due-commissions' (كل ساعة عند :17).
--
-- شغّل هذا الملف في Supabase Dashboard → SQL Editor
-- أو عبر Management API مثل باقي ملفات الإصلاح.
-- ============================================================

-- ─── 1) agency_credit_host_target_diamonds بدون احتساب يدوي ────────
-- مطابق للنسخة الحالية في قاعدة البيانات مع حذف كتلة
-- UPDATE pending_commission_diamonds فقط — كل شيء آخر
-- (idempotency, wallets, ledger, totals) كما هو.
CREATE OR REPLACE FUNCTION public.agency_credit_host_target_diamonds(
  p_host_uid text,
  p_diamonds bigint,
  p_agency_rate_pct numeric DEFAULT NULL::numeric,
  p_idem_key text DEFAULT NULL::text,
  p_source text DEFAULT 'gift'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member       record;
  v_agency_id    text;
  v_rate         numeric := 0;
  v_commission   bigint := 0;
  v_new_balance  bigint := 0;
  v_pending      bigint := 0;
  v_idem         text;
  v_user_uuid    uuid;
BEGIN
  IF p_host_uid IS NULL OR p_host_uid = '' OR COALESCE(p_diamonds, 0) <= 0 THEN
    RETURN jsonb_build_object('status', 'error', 'error', 'invalid_input');
  END IF;

  v_idem := NULLIF(p_idem_key, '');
  IF v_idem IS NULL THEN
    v_idem := COALESCE(NULLIF(p_source, ''), 'income') || '_' || p_host_uid
      || '_' || gen_random_uuid()::text;
  END IF;

  IF EXISTS (SELECT 1 FROM public.agency_diamond_ledger WHERE idempotency_key = v_idem) THEN
    RETURN jsonb_build_object('status', 'already_processed', 'idem_key', v_idem);
  END IF;

  BEGIN
    v_user_uuid := p_host_uid::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_user_uuid := NULL;
  END;

  SELECT *
  INTO v_member
  FROM public.host_agency_members
  WHERE (user_id::text = p_host_uid OR host_uid::text = p_host_uid)
    AND COALESCE(status, 'active') <> 'kicked'
  ORDER BY joined_at NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF v_member.id IS NULL THEN
    -- Not an agency member: personal wallet fallback handled by the app.
    RETURN jsonb_build_object('status', 'not_member', 'credited', 0);
  END IF;

  v_agency_id  := v_member.agency_id;
  v_new_balance := COALESCE(v_member.diamonds_balance, v_member.diamonds, 0) + p_diamonds;

  -- ✅ هذا الـ UPDATE يُشغّل trg_accrue_agency_commission الذي يضيف
  --    عمولة الوكالة إلى pending_commission_diamonds تلقائياً —
  --    لا نضيفها هنا يدوياً حتى لا تتكرر.
  UPDATE public.host_agency_members
  SET diamonds                  = v_new_balance,
      diamonds_balance          = v_new_balance,
      diamonds_available        = v_new_balance,
      diamonds_earned_monthly   = COALESCE(diamonds_earned_monthly, 0) + p_diamonds,
      diamonds_earned_cumulative = COALESCE(diamonds_earned_cumulative, 0) + p_diamonds,
      updated_at                = now()
  WHERE id = v_member.id;

  IF v_agency_id IS NOT NULL THEN
    -- العمولة للعرض في الاستجابة فقط — الاحتساب الفعلي عبر الـ Trigger.
    IF p_agency_rate_pct IS NOT NULL AND p_agency_rate_pct > 0 THEN
      v_rate := p_agency_rate_pct / 100.0;
    ELSE
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

    PERFORM public.agency_recalc_totals(v_agency_id);

    -- قراءة الرصيد المعلّق بعد الـ Trigger لعرضه في الاستجابة
    SELECT COALESCE(pending_commission_diamonds, 0) INTO v_pending
    FROM public.host_agencies
    WHERE id::text = v_agency_id::text;

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
    'commission', v_commission,
    'pending_commission', v_pending
  );
END;
$$;

-- ─── 2) حذف النسخة المكررة من agency_accrue_commission ────────────
-- يبقى (text, bigint, text) فقط — يكتب agency_diamond_ledger
-- ويضبط next_commission_release_at.
DROP FUNCTION IF EXISTS public.agency_accrue_commission(text, integer, text);

-- ─── 3) إلغاء مهمة cron المكررة ────────────────────────────────────
-- 'agency-commission-release' (*/5) أقدم من المهمة المعتمدة
-- 'agency-release-due-commissions' (17 * * * *) — نشغّل واحدة فقط.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'agency-commission-release') THEN
    PERFORM cron.unschedule('agency-commission-release');
  END IF;
END $$;
