-- ============================================================
-- تأمين تسجيل الدخول بالهاتف (OTP + PIN)
-- ------------------------------------------------------------
-- المشاكل التي يعالجها هذا الملف:
--  1) رموز OTP كانت تُخزَّن في app_config القابلة للقراءة بمفتاح anon
--     — أي شخص يستطيع قراءة otp_<phone> وسرقة رمز أي حساب.
--  2) PIN كان يُخزَّن في users.last_ip — قابل للقراءة والكتابة من أي
--     عميل anon، فيمكن تغيير PIN أي حساب أو سرقته لكسره offline.
--
-- الحل: جدولان مقيدان (RLS بدون سياسات = لا وصول لـ anon) + دوال
-- SECURITY DEFINER هي الواجهة الوحيدة للقراءة/التحقق.
--
-- شغّل هذا الملف كاملاً في Supabase Dashboard → SQL Editor.
-- ============================================================

-- ─── 1) جدول رموز OTP المقيد ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.login_otps (
  phone       text PRIMARY KEY,
  code        text NOT NULL,
  expires_at  timestamptz NOT NULL,
  attempts    integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.login_otps ENABLE ROW LEVEL SECURITY;
-- لا سياسات → anon/authenticated لا يستطيعان SELECT/INSERT/UPDATE/DELETE
REVOKE ALL ON public.login_otps FROM anon, authenticated;

-- ─── 2) جدول PIN المقيد ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.login_pins (
  phone       text PRIMARY KEY,
  pin_hash    text NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.login_pins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.login_pins FROM anon, authenticated;

-- ─── 3) طلب OTP: upsert عبر دالة آمنة ────────────────────────────────
CREATE OR REPLACE FUNCTION public.request_login_otp(
  p_phone text,
  p_code text,
  p_ttl_seconds integer DEFAULT 300
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_phone IS NULL OR p_phone = '' OR p_code IS NULL OR p_code = '' THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;

  INSERT INTO public.login_otps (phone, code, expires_at, attempts)
  VALUES (
    p_phone,
    p_code,
    now() + make_interval(secs => GREATEST(p_ttl_seconds, 60)),
    0
  )
  ON CONFLICT (phone) DO UPDATE
    SET code = EXCLUDED.code,
        expires_at = EXCLUDED.expires_at,
        attempts = 0,
        created_at = now();

  RETURN jsonb_build_object('status', 'ok');
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_login_otp(text, text, integer)
  TO anon, authenticated, service_role;

-- ─── 4) تحقق OTP: يعيد بيانات المستخدم أو new_user ──────────────────
CREATE OR REPLACE FUNCTION public.verify_login_otp(
  p_phone text,
  p_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.login_otps%ROWTYPE;
  v_user record;
BEGIN
  IF p_phone IS NULL OR p_phone = '' OR p_code IS NULL THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;

  SELECT * INTO v_row
  FROM public.login_otps
  WHERE phone = p_phone
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'no_otp');
  END IF;

  IF now() > v_row.expires_at THEN
    DELETE FROM public.login_otps WHERE phone = p_phone;
    RETURN jsonb_build_object('status', 'expired');
  END IF;

  IF v_row.attempts >= 5 THEN
    DELETE FROM public.login_otps WHERE phone = p_phone;
    RETURN jsonb_build_object('status', 'too_many');
  END IF;

  IF v_row.code <> p_code THEN
    UPDATE public.login_otps SET attempts = attempts + 1 WHERE phone = p_phone;
    RETURN jsonb_build_object('status', 'wrong_code');
  END IF;

  -- صحيح — ابطله فوراً لمنع إعادة الاستخدام
  DELETE FROM public.login_otps WHERE phone = p_phone;

  SELECT uid, id, name, photo_url, email, custom_id
    INTO v_user
  FROM public.users
  WHERE phone = p_phone
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'status', 'ok',
      'is_new', false,
      'uid', v_user.uid,
      'id', v_user.id,
      'name', v_user.name,
      'photo_url', v_user.photo_url,
      'email', v_user.email,
      'custom_id', v_user.custom_id
    );
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'is_new', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_login_otp(text, text)
  TO anon, authenticated, service_role;

-- ─── 5) تعيين PIN عبر دالة آمنة ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_login_pin(
  p_phone text,
  p_pin_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_phone IS NULL OR p_phone = '' OR p_pin_hash IS NULL OR p_pin_hash = '' THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;

  INSERT INTO public.login_pins (phone, pin_hash, updated_at)
  VALUES (p_phone, p_pin_hash, now())
  ON CONFLICT (phone) DO UPDATE
    SET pin_hash = EXCLUDED.pin_hash,
        updated_at = now();

  RETURN jsonb_build_object('status', 'ok');
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_login_pin(text, text)
  TO anon, authenticated, service_role;

-- ─── 6) تحقق PIN: ok / wrong / no_pin + بيانات المستخدم ──────────────
CREATE OR REPLACE FUNCTION public.verify_login_pin(
  p_phone text,
  p_pin_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pin record;
  v_user record;
BEGIN
  IF p_phone IS NULL OR p_phone = '' OR p_pin_hash IS NULL THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;

  SELECT * INTO v_pin FROM public.login_pins WHERE phone = p_phone;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'no_pin');
  END IF;

  IF v_pin.pin_hash <> p_pin_hash THEN
    RETURN jsonb_build_object('status', 'wrong');
  END IF;

  SELECT uid, id, name, photo_url, email, custom_id
    INTO v_user
  FROM public.users
  WHERE phone = p_phone
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'status', 'ok',
      'is_new', false,
      'uid', v_user.uid,
      'id', v_user.id,
      'name', v_user.name,
      'photo_url', v_user.photo_url,
      'email', v_user.email,
      'custom_id', v_user.custom_id
    );
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'is_new', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_login_pin(text, text)
  TO anon, authenticated, service_role;

-- ─── 7) تنظيف مفاتيح OTP القديمة المكشوفة في app_config ───────────────
DELETE FROM public.app_config WHERE key LIKE 'otp_%';

-- ─── 8) فهارس فريدة على custom_id و phone (إن لم توجد تكرارات) ────────
-- تمنع السيرفر نفسه من قبول آيدين أو رقمين مكررين — كانت التكرارات
-- ممكنة لأن الفحص كان يتم من العميل فقط (TOCTOU).
DO $$
DECLARE
  v_dupes int;
BEGIN
  SELECT COUNT(*) INTO v_dupes FROM (
    SELECT custom_id FROM public.users
    WHERE custom_id IS NOT NULL AND custom_id <> ''
    GROUP BY custom_id HAVING COUNT(*) > 1
  ) d;
  IF v_dupes = 0 THEN
    CREATE UNIQUE INDEX IF NOT EXISTS users_custom_id_uniq
      ON public.users (custom_id) WHERE custom_id IS NOT NULL AND custom_id <> '';
    RAISE NOTICE 'users_custom_id_uniq created';
  ELSE
    RAISE NOTICE 'Skipped users_custom_id_uniq: % duplicate custom_id values — clean them first', v_dupes;
  END IF;

  SELECT COUNT(*) INTO v_dupes FROM (
    SELECT phone FROM public.users
    WHERE phone IS NOT NULL AND phone <> ''
    GROUP BY phone HAVING COUNT(*) > 1
  ) d;
  IF v_dupes = 0 THEN
    CREATE UNIQUE INDEX IF NOT EXISTS users_phone_uniq
      ON public.users (phone) WHERE phone IS NOT NULL AND phone <> '';
    RAISE NOTICE 'users_phone_uniq created';
  ELSE
    RAISE NOTICE 'Skipped users_phone_uniq: % duplicate phone values — clean them first', v_dupes;
  END IF;
END $$;
