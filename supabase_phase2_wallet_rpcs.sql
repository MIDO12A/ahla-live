-- ============================================================
-- Phase 2: RPCs آمنة للعمليات المالية بين المستخدمين
-- ------------------------------------------------------------
-- هذه الدوال SECURITY DEFINER تسمح بعمليات محفظة/إحصائيات على
-- حسابات مستخدمين آخرين بشكل atomic — بديل آمن عن PATCH المباشر
-- على users الذي سيُحظر عند تفعيل users_write_guard=enforce.
--
-- شغّل في Supabase Dashboard → SQL Editor بعد
-- supabase_session_tokens.sql.
-- ============================================================

-- ─── 1) bump_user_stat — زيادة عدّاد إحصائي بقائمة بيضاء ────────────
-- الحقول المسموحة فقط — لا يمكن استخدامها لكتابة حقول عشوائية.
CREATE OR REPLACE FUNCTION public.bump_user_stat(
  p_uid text,
  p_field text,
  p_delta bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed text[] := ARRAY[
    'total_gifts_received', 'total_gifts_sent',
    'charm', 'wealth_exp', 'gems_exp'
  ];
BEGIN
  -- ✅ جلسة صالحة مطلوبة — لا يمكن استدعاؤها بدون حساب مسجّل
  IF public.app_request_uid() IS NULL THEN
    RETURN jsonb_build_object('status', 'unauthorized');
  END IF;
  IF p_uid IS NULL OR p_uid = '' OR p_delta IS NULL OR p_delta = 0 THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;
  IF NOT (p_field = ANY (v_allowed)) THEN
    RETURN jsonb_build_object('status', 'field_not_allowed');
  END IF;

  EXECUTE format(
    'UPDATE public.users SET %I = COALESCE(%I, 0) + $1, updated_at = now()
     WHERE uid = $2 OR id = $2',
    p_field, p_field
  ) USING p_delta, p_uid;

  RETURN jsonb_build_object('status', 'ok');
END;
$$;

GRANT EXECUTE ON FUNCTION public.bump_user_stat(text, text, bigint)
  TO anon, authenticated, service_role;

-- ─── 2) adjust_user_wallet — تعديل كوينز/ماس atomic ──────────────────
-- يستخدم للعمليات بين المستخدمين (مكافآت، شحن، تحويل).
-- لا يسمح بجعل الرصيد سالباً للكوينز.
CREATE OR REPLACE FUNCTION public.adjust_user_wallet(
  p_uid text,
  p_coins_delta bigint DEFAULT 0,
  p_diamonds_delta bigint DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coins bigint;
  v_diamonds bigint;
BEGIN
  -- ✅ جلسة صالحة مطلوبة
  IF public.app_request_uid() IS NULL THEN
    RETURN jsonb_build_object('status', 'unauthorized');
  END IF;
  IF p_uid IS NULL OR p_uid = '' THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;
  IF COALESCE(p_coins_delta, 0) = 0 AND COALESCE(p_diamonds_delta, 0) = 0 THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;

  -- منع الرصيد السالب للكوينز
  IF p_coins_delta < 0 THEN
    SELECT COALESCE(coins, 0) INTO v_coins
    FROM public.users WHERE uid = p_uid OR id = p_uid LIMIT 1;
    IF v_coins IS NULL OR v_coins + p_coins_delta < 0 THEN
      RETURN jsonb_build_object('status', 'insufficient_coins');
    END IF;
  END IF;

  UPDATE public.users SET
    coins    = GREATEST(0, COALESCE(coins, 0)    + COALESCE(p_coins_delta, 0)),
    diamonds = GREATEST(0, COALESCE(diamonds, 0) + COALESCE(p_diamonds_delta, 0)),
    updated_at = now()
  WHERE uid = p_uid OR id = p_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'user_not_found');
  END IF;
  RETURN jsonb_build_object('status', 'ok');
END;
$$;

GRANT EXECUTE ON FUNCTION public.adjust_user_wallet(text, bigint, bigint)
  TO anon, authenticated, service_role;

-- ─── 3) credit_user_diamonds — إضافة ماس لهدية/مكافأة ────────────────
-- نسخة SQL ذرّية من fallback في creditHostAgencyMemberDiamonds:
--   • عضو وكالة → محفظة الوكالة (host_agency_members) + إجماليات
--     الوكالة المحسوبة من مجموع الأعضاء الفعلي.
--   • غير عضو → users.diamonds الشخصي.
-- ملاحظة: لا تحسب عمولة الوكالة — ذلك عبر
-- agency_credit_host_target_diamonds أو الـ Trigger.
CREATE OR REPLACE FUNCTION public.credit_user_diamonds(
  p_uid text,
  p_diamonds bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member record;
  v_agency_id text;
  v_new_diamonds bigint;
  v_true_monthly bigint := 0;
  v_true_cumulative bigint := 0;
BEGIN
  -- ✅ جلسة صالحة مطلوبة
  IF public.app_request_uid() IS NULL THEN
    RETURN jsonb_build_object('status', 'unauthorized');
  END IF;
  IF p_uid IS NULL OR p_uid = '' OR p_diamonds IS NULL OR p_diamonds <= 0 THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;

  -- عضو وكالة؟
  SELECT * INTO v_member
  FROM public.host_agency_members
  WHERE host_uid = p_uid OR user_id = p_uid
  LIMIT 1;

  IF FOUND THEN
    v_agency_id := v_member.agency_id;
    v_new_diamonds := GREATEST(0,
      COALESCE(v_member.diamonds_balance,
               v_member.diamonds_available,
               v_member.diamonds, 0)
      + p_diamonds);

    UPDATE public.host_agency_members SET
      diamonds = v_new_diamonds,
      diamonds_balance = v_new_diamonds,
      diamonds_available = v_new_diamonds,
      diamonds_earned_monthly =
        COALESCE(diamonds_earned_monthly, 0) + p_diamonds,
      diamonds_earned_cumulative =
        COALESCE(diamonds_earned_cumulative, 0) + p_diamonds,
      updated_at = now()
    WHERE id = v_member.id;

    -- إجماليات الوكالة = مجموع الأعضاء الفعلي (لا جمع تراكمي)
    IF v_agency_id IS NOT NULL AND v_agency_id <> '' THEN
      SELECT
        COALESCE(SUM(diamonds_earned_monthly), 0),
        COALESCE(SUM(diamonds_earned_cumulative), 0)
      INTO v_true_monthly, v_true_cumulative
      FROM public.host_agency_members
      WHERE agency_id = v_agency_id;

      UPDATE public.host_agencies SET
        total_diamonds_monthly = v_true_monthly,
        total_diamonds_cumulative = v_true_cumulative,
        updated_at = now()
      WHERE id = v_agency_id;
    END IF;

    RETURN jsonb_build_object('status', 'ok', 'via', 'agency');
  END IF;

  -- غير عضو: المحفظة الشخصية
  UPDATE public.users SET
    diamonds = COALESCE(diamonds, 0) + p_diamonds,
    updated_at = now()
  WHERE uid = p_uid OR id = p_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'user_not_found');
  END IF;
  RETURN jsonb_build_object('status', 'ok', 'via', 'personal');
END;
$$;

GRANT EXECUTE ON FUNCTION public.credit_user_diamonds(text, bigint)
  TO anon, authenticated, service_role;

-- ─── 4) set_user_field — تعيين حقل نصي بقائمة بيضاء ─────────────────
-- للحقول التجميلية التي تُمنح كمكافآت (فريم/فقاعة/مؤثر دخول)
-- على حسابات مستخدمين آخرين — بديل PATCH المباشر.
CREATE OR REPLACE FUNCTION public.set_user_field(
  p_uid text,
  p_field text,
  p_value text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed text[] := ARRAY[
    'active_frame', 'active_bubble', 'active_entrance',
    'active_avatar_frame', 'title', 'signature'
  ];
BEGIN
  IF public.app_request_uid() IS NULL THEN
    RETURN jsonb_build_object('status', 'unauthorized');
  END IF;
  IF p_uid IS NULL OR p_uid = ''
     OR NOT (p_field = ANY (v_allowed)) THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;

  EXECUTE format(
    'UPDATE public.users SET %I = $1, updated_at = now()
     WHERE uid = $2 OR id = $2',
    p_field
  ) USING p_value, p_uid;

  RETURN jsonb_build_object('status', 'ok');
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_user_field(text, text, text)
  TO anon, authenticated, service_role;
