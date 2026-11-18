-- =============================================================================
-- Game Provider Server-to-Server API
-- =============================================================================
-- يتيح لسيرفر شركة الألعاب تسوية جولات الألعاب (رهان/فوز) مباشرة على
-- رصيد المستخدم في Supabase — بدل الاعتماد على JS Bridge داخل التطبيق.
--
-- الحماية:
--   1. سر مشترك (game_provider_secret) يجب أن يطابقه الطلب.
--   2. دالة game_provider_settle_round تضبط GUC داخلي
--      app.write_guard_bypass='provider' يتجاوز trg_users_write_guard
--      داخل معاملتها فقط — لا يمكن استغلاله من خارجها.
--
-- طريقة الاستخدام (من الباكند):
--   POST {SUPABASE_URL}/rest/v1/rpc/game_provider_settle_round
--   { "p_secret": "...", "p_user_id": "...", "p_user_name": "...",
--     "p_game_id": "ludo", "p_bet_amount": 1000, "p_win_amount": 5000 }
-- =============================================================================

-- ─── 1) السر المشترك — غيّره لقيمة قوية وخليها نفسها في env الباكند ─────
INSERT INTO public.app_config (key, value)
VALUES ('game_provider_secret', '"gms_8f3kQ2xL9pR7vN4cT1wY"')
ON CONFLICT (key) DO NOTHING;

-- ─── 2) حارس الكتابة — إضافة bypass داخلي لمعاملات المزوّد فقط ──────────
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

  -- ✅ bypass داخلي: دوال SECURITY DEFINER الموثوقة (مزوّد الألعاب)
  --    تضبط app.write_guard_bypass='provider' عبر set_config داخل
  --    معاملتها — يعمل في audit وenforce معاً ولا يمكن تمريره خارجياً.
  IF current_setting('app.write_guard_bypass', true) = 'provider' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- مشرفو لوحة التحكم: JWT حقيقي من Supabase Auth + موجودون في
  -- admin_users → يُسمح لهم بالكتابة على أي صف (دورهم الإداري).
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

-- ─── 3) تسوية جولة لعبة — ذرّية: رصيد + سجل + pool ─────────────────────
CREATE OR REPLACE FUNCTION public.game_provider_settle_round(
  p_secret text,
  p_user_id text,
  p_user_name text,
  p_game_id text,
  p_bet_amount bigint DEFAULT 0,
  p_win_amount bigint DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expected text;
  v_coins bigint;
  v_net bigint;
  v_bet bigint := GREATEST(0, COALESCE(p_bet_amount, 0));
  v_win bigint := GREATEST(0, COALESCE(p_win_amount, 0));
BEGIN
  -- التحقق من السر المشترك
  SELECT value::text INTO v_expected
  FROM public.app_config WHERE key = 'game_provider_secret' LIMIT 1;
  v_expected := trim(both '"' from COALESCE(v_expected, ''));
  IF v_expected = '' OR p_secret IS NULL OR p_secret <> v_expected THEN
    RETURN jsonb_build_object('status', 'unauthorized');
  END IF;

  IF p_user_id IS NULL OR p_user_id = '' OR p_game_id IS NULL OR p_game_id = '' THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;
  IF v_bet = 0 AND v_win = 0 THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;

  -- فتح bypass الحارس داخل هذه المعاملة فقط
  PERFORM set_config('app.write_guard_bypass', 'provider', true);

  -- صافي الجولة = الفوز − الرهان (قد يكون سالباً)
  v_net := v_win - v_bet;

  -- تحديث ذرّي: UPDATE ياخد قفل الصف ويحسب من أحدث قيمة، فما يحصلش lost update
  -- لما يجي callbacks متوازية (ظهر في السجل: رصيد قديم اتقرأ أكتر من مرة).
  UPDATE public.users u
  SET coins = COALESCE(u.coins, 0) + v_net,
      updated_at = now()
  WHERE (u.uid = p_user_id OR u.id = p_user_id)
    AND COALESCE(u.coins, 0) + v_net >= 0
  RETURNING u.coins INTO v_coins;

  IF v_coins IS NULL THEN
    SELECT COALESCE(coins, 0) INTO v_coins
    FROM public.users WHERE uid = p_user_id OR id = p_user_id LIMIT 1;
    IF v_coins IS NULL THEN
      RETURN jsonb_build_object('status', 'user_not_found');
    END IF;
    RETURN jsonb_build_object('status', 'insufficient_coins', 'coins', v_coins);
  END IF;

  -- سجل الجولة
  INSERT INTO public.game_bet_records (
    game_id, user_id, user_name,
    bet_amount, win_amount, net_result, is_win, created_at
  ) VALUES (
    p_game_id, p_user_id,
    COALESCE(NULLIF(p_user_name, ''), 'Player'),
    v_bet, v_win, v_net, v_win > 0, now()
  );

  -- رصيد الـ pool: الرهان يضيف للبيت، الفوز يخصم منه
  BEGIN
    PERFORM public.increment_game_pool_balance(p_game_id, v_bet - v_win);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- v_coins رجع من RETURNING بعد إضافة v_net — ما نضيفهوش تاني.
  RETURN jsonb_build_object(
    'status', 'ok',
    'net', v_net,
    'coins', v_coins
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.game_provider_settle_round(text, text, text, text, bigint, bigint)
  TO anon, authenticated, service_role;
