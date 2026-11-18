-- ============================================================
-- نظام جلسات المستخدم (Session Tokens) — حماية الحسابات
-- ------------------------------------------------------------
-- الفكرة: بعد إثبات الهوية (OTP/PIN/Google) يصدر السيرفر توكناً
-- فريداً يُخزَّن في user_sessions (جدول مقيد لا يقرأه anon).
-- التطبيق يرسله في header «x-session-token» مع كل طلب.
-- دالة app_request_uid() تستخرجه — وبها يُبنى حارس الكتابة على
-- جدول users.
--
-- أوضاع الحارس (app_config.users_write_guard):
--   'off'     = معطّل (افتراضي) — لا شيء يُرفض
--   'audit'   = يسمح بالكتابة لكن يسجّل كل مخالفة في guard_violations
--   'enforce' = يرفض الكتابة بدون جلسة صالحة
--
-- شغّل في Supabase Dashboard → SQL Editor.
-- ============================================================

-- ─── 1) جدول الجلسات المقيد ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_sessions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uid          text,
  phone        text,
  token        text NOT NULL UNIQUE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL DEFAULT now() + interval '90 days',
  last_used_at timestamptz
);

CREATE INDEX IF NOT EXISTS user_sessions_token_idx ON public.user_sessions (token);
CREATE INDEX IF NOT EXISTS user_sessions_uid_idx ON public.user_sessions (uid);
CREATE INDEX IF NOT EXISTS user_sessions_phone_idx ON public.user_sessions (phone);

ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_sessions FROM anon, authenticated;

-- ─── 2) سجل مخالفات الحارس (لوضع audit) ──────────────────────────────
CREATE TABLE IF NOT EXISTS public.guard_violations (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  table_name text NOT NULL,
  op         text NOT NULL,
  row_uid    text,
  detail     jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.guard_violations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.guard_violations FROM anon, authenticated;

-- ─── 3) استخراج uid من توكن الجلسة ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.session_uid(p_token text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT uid FROM public.user_sessions
  WHERE token = p_token AND expires_at > now()
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.session_uid(text) TO anon, authenticated, service_role;

-- ─── 4) استخراج uid الجلسة من header الطلب ───────────────────────────
CREATE OR REPLACE FUNCTION public.app_request_uid()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token text;
BEGIN
  BEGIN
    v_token := current_setting('request.header.x-session-token', true);
  EXCEPTION WHEN OTHERS THEN
    v_token := NULL;
  END;
  IF v_token IS NULL OR v_token = '' THEN
    BEGIN
      v_token := current_setting('request.headers', true)::jsonb ->> 'x-session-token';
    EXCEPTION WHEN OTHERS THEN
      v_token := NULL;
    END;
  END IF;
  IF v_token IS NULL OR v_token = '' THEN RETURN NULL; END IF;
  RETURN public.session_uid(v_token);
END;
$$;

-- ─── 5) إصدار جلسة (داخلية — تُستدعى من دوال التحقق فقط) ─────────────
CREATE OR REPLACE FUNCTION public._issue_session(p_uid text, p_phone text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token text;
BEGIN
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  INSERT INTO public.user_sessions (uid, phone, token, expires_at)
  VALUES (
    NULLIF(p_uid, ''),
    NULLIF(p_phone, ''),
    v_token,
    now() + interval '90 days'
  );
  RETURN v_token;
END;
$$;

REVOKE ALL ON FUNCTION public._issue_session(text, text) FROM PUBLIC;

-- ─── 6) verify_login_otp مع إصدار الجلسة ─────────────────────────────
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
  v_uid text;
  v_token text;
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

  DELETE FROM public.login_otps WHERE phone = p_phone;

  SELECT uid, id, name, photo_url, email, custom_id
    INTO v_user
  FROM public.users
  WHERE phone = p_phone
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1;

  IF FOUND THEN
    v_uid := COALESCE(v_user.uid, v_user.id);
    v_token := public._issue_session(v_uid, p_phone);
    RETURN jsonb_build_object(
      'status', 'ok',
      'is_new', false,
      'uid', v_uid,
      'id', v_user.id,
      'name', v_user.name,
      'photo_url', v_user.photo_url,
      'email', v_user.email,
      'custom_id', v_user.custom_id,
      'session_token', v_token
    );
  END IF;

  v_token := public._issue_session(NULL, p_phone);
  RETURN jsonb_build_object('status', 'ok', 'is_new', true, 'session_token', v_token);
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_login_otp(text, text)
  TO anon, authenticated, service_role;

-- ─── 7) verify_login_pin مع إصدار الجلسة ─────────────────────────────
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
  v_uid text;
  v_token text;
BEGIN
  IF p_phone IS NULL OR p_phone = '' OR p_pin_hash IS NULL THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;

  SELECT * INTO v_pin FROM public.login_pins WHERE phone = p_phone;

  IF NOT FOUND THEN
    v_token := public._issue_session(NULL, p_phone);
    RETURN jsonb_build_object('status', 'no_pin', 'session_token', v_token);
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
    v_uid := COALESCE(v_user.uid, v_user.id);
    v_token := public._issue_session(v_uid, p_phone);
    RETURN jsonb_build_object(
      'status', 'ok',
      'is_new', false,
      'uid', v_uid,
      'id', v_user.id,
      'name', v_user.name,
      'photo_url', v_user.photo_url,
      'email', v_user.email,
      'custom_id', v_user.custom_id,
      'session_token', v_token
    );
  END IF;

  v_token := public._issue_session(NULL, p_phone);
  RETURN jsonb_build_object('status', 'ok', 'is_new', true, 'session_token', v_token);
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_login_pin(text, text)
  TO anon, authenticated, service_role;

-- ─── 8) إصدار جلسة لمستخدمي Google (عبر Supabase Auth JWT) ───────────
CREATE OR REPLACE FUNCTION public.create_session(p_uid text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_uid text;
  v_token text;
BEGIN
  BEGIN
    v_auth_uid := auth.uid()::text;
  EXCEPTION WHEN OTHERS THEN
    v_auth_uid := NULL;
  END;

  IF v_auth_uid IS NULL OR v_auth_uid = '' OR v_auth_uid <> p_uid THEN
    RETURN jsonb_build_object('status', 'not_authorized');
  END IF;

  v_token := public._issue_session(p_uid, NULL);
  RETURN jsonb_build_object('status', 'ok', 'session_token', v_token);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_session(text)
  TO anon, authenticated, service_role;

-- ─── 9) ربط جلسات الهاتف اليتيمة بالـ uid عند إنشاء الحساب ───────────
CREATE OR REPLACE FUNCTION public.trg_bind_session_on_user_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.phone IS NOT NULL AND NEW.phone <> '' THEN
    UPDATE public.user_sessions
    SET uid = COALESCE(NEW.uid, NEW.id), last_used_at = now()
    WHERE phone = NEW.phone AND uid IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bind_session_on_user_insert ON public.users;
CREATE TRIGGER trg_bind_session_on_user_insert
AFTER INSERT ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.trg_bind_session_on_user_insert();

-- ─── 10) حارس الكتابة على users — أوضاع off/audit/enforce ───────────
CREATE OR REPLACE FUNCTION public.trg_users_write_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode text;
  v_uid text;
  v_row_uid text;
  v_row_phone text;
  v_allowed boolean := false;
  v_row jsonb;
BEGIN
  SELECT value::text INTO v_mode
  FROM public.app_config WHERE key = 'users_write_guard' LIMIT 1;
  v_mode := lower(COALESCE(v_mode, 'off'));
  -- '"off"' قد تصل مقتبسة — نظّفها
  v_mode := trim(both '"' from v_mode);
  IF v_mode = 'off' OR v_mode = '' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- مشرفو لوحة التحكم: JWT حقيقي من Supabase Auth + موجودون في
  -- admin_users → يُسمح لهم بالكتابة على أي صف (دورهم الإداري).
  -- جلسة supabase-js تُجدَّد تلقائياً فهي فعلياً دائمة المدة.
  BEGIN
    IF auth.role() = 'authenticated' THEN
      DECLARE
        v_jwt_email text;
        v_jwt_uid text;
      BEGIN
        v_jwt_email := lower(COALESCE(auth.jwt() ->> 'email', ''));
        v_jwt_uid := COALESCE(auth.uid()::text, '');
        IF (v_jwt_email <> '' AND EXISTS (
              SELECT 1 FROM public.admin_users
              WHERE lower(email) = v_jwt_email
            ))
           OR (v_jwt_uid <> '' AND EXISTS (
              SELECT 1 FROM public.admin_users
              WHERE uid = v_jwt_uid
            )) THEN
          RETURN COALESCE(NEW, OLD);
        END IF;
      END;
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- service_role يتجاوز الحارس دائماً
  BEGIN
    IF auth.role() = 'service_role' THEN
      RETURN COALESCE(NEW, OLD);
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  v_uid := public.app_request_uid();
  v_row := COALESCE(to_jsonb(NEW), to_jsonb(OLD));
  v_row_uid := COALESCE(v_row ->> 'uid', v_row ->> 'id');
  v_row_phone := v_row ->> 'phone';

  -- الجلسة صالحة إذا كان uid الجلسة = uid الصف، أو (للإدراج)
  -- جلسة هاتفية غير مرتبطة تطابق phone الصف الجديد.
  IF v_uid IS NOT NULL AND v_row_uid IS NOT NULL AND v_uid = v_row_uid THEN
    v_allowed := true;
  ELSIF TG_OP = 'INSERT'
        AND v_row_phone IS NOT NULL AND v_row_phone <> ''
        AND EXISTS (
          SELECT 1 FROM public.user_sessions s
          WHERE s.phone = v_row_phone AND s.uid IS NULL
        ) THEN
    v_allowed := true;
  END IF;

  IF v_allowed THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- audit: سجّل المخالفة واسمح — جمع بيانات قبل التفعيل
  IF v_mode = 'audit' THEN
    INSERT INTO public.guard_violations (table_name, op, row_uid, detail)
    VALUES (
      'users', TG_OP, v_row_uid,
      jsonb_build_object(
        'session_uid', v_uid,
        'row_phone', v_row_phone,
        'changed_keys', (
          SELECT COALESCE(jsonb_agg(k), '[]'::jsonb)
          FROM jsonb_object_keys(
            CASE WHEN TG_OP = 'INSERT' THEN to_jsonb(NEW)
                 ELSE to_jsonb(OLD) END
          ) k
        )
      )
    );
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- enforce: ارفض
  RAISE EXCEPTION 'users_write_denied: no valid session for % on uid=%',
    TG_OP, v_row_uid;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_write_guard ON public.users;
CREATE TRIGGER trg_users_write_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.trg_users_write_guard();

-- ─── 11) change_login_pin — تغيير رمز الدخول بعد التحقق من القديم ────
CREATE OR REPLACE FUNCTION public.change_login_pin(
  p_phone text,
  p_old_pin_hash text,
  p_new_pin_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pin record;
BEGIN
  IF p_phone IS NULL OR p_phone = ''
     OR p_old_pin_hash IS NULL OR p_new_pin_hash IS NULL THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;

  SELECT * INTO v_pin FROM public.login_pins WHERE phone = p_phone;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'no_pin');
  END IF;
  IF v_pin.pin_hash <> p_old_pin_hash THEN
    RETURN jsonb_build_object('status', 'wrong_old');
  END IF;

  UPDATE public.login_pins
  SET pin_hash = p_new_pin_hash, updated_at = now()
  WHERE phone = p_phone;

  RETURN jsonb_build_object('status', 'ok');
EXCEPTION WHEN undefined_column THEN
  -- عمود updated_at قد لا يوجد في المخطط القديم — حدّث بدونها
  UPDATE public.login_pins SET pin_hash = p_new_pin_hash WHERE phone = p_phone;
  RETURN jsonb_build_object('status', 'ok');
END;
$$;

GRANT EXECUTE ON FUNCTION public.change_login_pin(text, text, text)
  TO anon, authenticated, service_role;

-- وضع الحارس الافتراضي: audit — يسجّل المخالفات بدون كسر شيء،
-- راجع guard_violations ثم حوّل الكتابات المتبقية لـ RPCs وفعّل enforce.
INSERT INTO public.app_config (key, value)
VALUES ('users_write_guard', '"audit"')
ON CONFLICT (key) DO UPDATE SET value = '"audit"';
