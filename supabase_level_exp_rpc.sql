-- ============================================================
-- add_user_exp — منح خبرة مستوى atomic على السيرفر
-- ------------------------------------------------------------
-- بديل آمن عن LevelService.addExp في التطبيق (read-modify-write
-- على العميل) — يعمل لأي uid (مرسل/مستلم) بدون race، ويمنح مكافآت
-- المستوى (كوينز/ماس/فريم/شارة) في نفس الـ transaction.
-- يتطلب session token صالح (app_request_uid).
-- شغّل في SQL Editor.
-- ============================================================

CREATE OR REPLACE FUNCTION public.add_user_exp(
  p_uid text,
  p_type text,
  p_amount bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user record;
  v_exp_field text;
  v_level_field text;
  v_level int;
  v_exp bigint;
  v_old_level int;
  v_cfg record;
  v_max_level int;
  v_reward_coins bigint := 0;
  v_reward_diamonds bigint := 0;
  v_new_frames jsonb := '[]'::jsonb;
  v_new_badges jsonb := '[]'::jsonb;
  v_last_frame text;
BEGIN
  -- ✅ جلسة صالحة مطلوبة
  IF public.app_request_uid() IS NULL THEN
    RETURN jsonb_build_object('status', 'unauthorized');
  END IF;
  IF p_uid IS NULL OR p_uid = ''
     OR p_type NOT IN ('wealth', 'recharge', 'gems')
     OR p_amount IS NULL OR p_amount <= 0 THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;

  v_exp_field := p_type || '_exp';
  v_level_field := p_type || '_level';

  -- أعلى مستوى مُعرَّف في level_config لهذا النوع
  SELECT COALESCE(MAX(level), 1) INTO v_max_level
  FROM public.level_config WHERE type = p_type;

  -- قراءة الحالة الحالية (uid أو id)
  EXECUTE format(
    'SELECT %I AS lvl, %I AS exp FROM public.users WHERE uid = $1 OR id = $1 LIMIT 1',
    v_level_field, v_exp_field
  ) INTO v_user USING p_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'user_not_found');
  END IF;

  v_level := COALESCE(v_user.lvl, 1);
  v_exp := COALESCE(v_user.exp, 0) + p_amount;
  v_old_level := v_level;

  -- حلقة الصعود — نفس منطق addExp في التطبيق
  LOOP
    IF v_level >= v_max_level THEN EXIT; END IF;
    SELECT max_exp, rewards, frame_url, badge_url
      INTO v_cfg
    FROM public.level_config
    WHERE type = p_type AND level = v_level
    ORDER BY level
    LIMIT 1;
    IF NOT FOUND THEN EXIT; END IF;
    IF v_exp >= COALESCE(v_cfg.max_exp, 1000) THEN
      v_exp := v_exp - COALESCE(v_cfg.max_exp, 1000);
      v_level := v_level + 1;
      IF v_cfg.rewards ? 'coins' THEN
        v_reward_coins := v_reward_coins + COALESCE((v_cfg.rewards->>'coins')::bigint, 0);
      END IF;
      IF v_cfg.rewards ? 'diamonds' THEN
        v_reward_diamonds := v_reward_diamonds + COALESCE((v_cfg.rewards->>'diamonds')::bigint, 0);
      END IF;
      IF v_cfg.frame_url IS NOT NULL AND v_cfg.frame_url <> '' THEN
        v_new_frames := v_new_frames || to_jsonb(v_cfg.frame_url);
        v_last_frame := v_cfg.frame_url;
      END IF;
      IF v_cfg.badge_url IS NOT NULL AND v_cfg.badge_url <> '' THEN
        v_new_badges := v_new_badges || to_jsonb(v_cfg.badge_url);
      END IF;
    ELSE
      EXIT;
    END IF;
  END LOOP;

  -- تحديث الصف — كل الحقول في UPDATE واحد
  EXECUTE format(
    'UPDATE public.users SET
       %I = $1,
       %I = $2,
       owned_level_frames = COALESCE(owned_level_frames, ''[]''::jsonb) || $3::jsonb,
       owned_level_badges = COALESCE(owned_level_badges, ''[]''::jsonb) || $4::jsonb,
       coins = COALESCE(coins, 0) + $5,
       diamonds = COALESCE(diamonds, 0) + $6,
       updated_at = now()
     WHERE uid = $7 OR id = $7',
    v_exp_field, v_level_field
  ) USING v_exp, v_level, v_new_frames, v_new_badges,
          v_reward_coins, v_reward_diamonds, p_uid;

  -- تفعيل آخر فريم مكتسب تلقائياً (نفس سلوك التطبيق)
  IF v_last_frame IS NOT NULL THEN
    UPDATE public.users SET active_frame = v_last_frame
    WHERE (uid = p_uid OR id = p_uid);
  END IF;

  RETURN jsonb_build_object(
    'status', 'ok',
    'old_level', v_old_level,
    'new_level', v_level,
    'exp', v_exp,
    'leveled_up', v_level > v_old_level,
    'reward_coins', v_reward_coins,
    'reward_diamonds', v_reward_diamonds,
    'new_frames', v_new_frames,
    'new_badges', v_new_badges
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_user_exp(text, text, bigint)
  TO anon, authenticated, service_role;
