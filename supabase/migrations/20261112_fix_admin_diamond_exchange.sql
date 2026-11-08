-- Fix: admin diamond adjustments must sync the host agency wallet, and
-- diamond->coins exchange must work with the app's anon-key REST calls.

CREATE OR REPLACE FUNCTION public.agency_exchange_diamonds_v2(
  p_diamonds bigint,
  p_idempotency_key text DEFAULT NULL,
  p_user_id text DEFAULT NULL,
  p_coins_per_diamond numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid text;
  v_auth_uid text;
  v_idem text;
  v_user_diamonds bigint := 0;
  v_new_diamonds bigint := 0;
  v_new_monthly bigint := 0;
  v_member record;
  v_agency_id text;
  v_available bigint := 0;
  v_exchangeable bigint := 0;
  v_mult numeric := 1;
  v_coins bigint := 0;
BEGIN
  v_auth_uid := NULLIF(auth.uid()::text, '');
  v_uid := COALESCE(v_auth_uid, NULLIF(p_user_id, ''));

  IF v_uid IS NULL OR v_uid = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthorized');
  END IF;
  IF v_auth_uid IS NOT NULL AND p_user_id IS NOT NULL AND p_user_id <> '' AND p_user_id <> v_auth_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  IF COALESCE(p_diamonds, 0) <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_amount');
  END IF;

  v_idem := NULLIF(p_idempotency_key, '');
  IF v_idem IS NOT NULL THEN
    SELECT coins, balance_after
    INTO v_coins, v_new_diamonds
    FROM public.diamond_exchange_log
    WHERE idempotency_key = v_idem
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true,
        'duplicate', true,
        'coins_received', v_coins,
        'new_balance', v_new_diamonds
      );
    END IF;
  END IF;

  SELECT COALESCE(diamonds, 0)
  INTO v_user_diamonds
  FROM public.users
  WHERE uid::text = v_uid OR id::text = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'user_not_found');
  END IF;

  SELECT *
  INTO v_member
  FROM public.host_agency_members
  WHERE user_id::text = v_uid OR host_uid::text = v_uid
  ORDER BY joined_at NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF v_member.id IS NOT NULL THEN
    v_agency_id := v_member.agency_id;
    v_available := COALESCE(v_member.diamonds_available,
      v_member.diamonds_balance, 0);
    v_exchangeable := LEAST(
      v_available,
      GREATEST(0, COALESCE(v_member.diamonds_earned_monthly, 0))
    );
  ELSE
    v_available := GREATEST(0, v_user_diamonds);
    v_exchangeable := v_available;
  END IF;

  IF v_exchangeable < p_diamonds THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'insufficient_balance',
      'available', v_exchangeable
    );
  END IF;

  v_mult := COALESCE(NULLIF(p_coins_per_diamond, 0), 1);
  IF v_mult <= 0 THEN
    v_mult := 1;
  END IF;
  v_coins := FLOOR(p_diamonds * v_mult)::bigint;
  v_new_diamonds := GREATEST(0, v_available - p_diamonds);

  IF v_member.id IS NOT NULL THEN
    v_new_monthly := GREATEST(0, COALESCE(v_member.diamonds_earned_monthly, 0) - p_diamonds);

    UPDATE public.host_agency_members
    SET diamonds = v_new_diamonds,
        diamonds_balance = v_new_diamonds,
        diamonds_available = v_new_diamonds,
        diamonds_earned_monthly = v_new_monthly,
        unpacked_target_diamonds = COALESCE(unpacked_target_diamonds, 0) + p_diamonds,
        has_unpacked_target = true,
        updated_at = now()
    WHERE id = v_member.id;

    UPDATE public.users
    SET coins = COALESCE(coins, 0) + v_coins,
        updated_at = now()
    WHERE uid::text = v_uid OR id::text = v_uid;

    PERFORM public.agency_recalc_totals(v_agency_id);

    IF v_agency_id IS NOT NULL AND v_idem IS NOT NULL THEN
      INSERT INTO public.agency_diamond_ledger
        (agency_id, user_id, txn_type, amount, direction, balance_after,
         note, idempotency_key, created_at)
      VALUES
        (v_agency_id, v_uid, 'exchange', p_diamonds, -1, v_new_diamonds,
         'تبديل ألماس إلى كوينز', v_idem, now())
      ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;
  ELSE
    UPDATE public.users
    SET diamonds = v_new_diamonds,
        coins = COALESCE(coins, 0) + v_coins,
        updated_at = now()
    WHERE uid::text = v_uid OR id::text = v_uid;
  END IF;

  IF v_idem IS NOT NULL THEN
    INSERT INTO public.diamond_exchange_log
      (user_id, diamonds, coins, balance_after, idempotency_key, created_at)
    VALUES
      (v_uid, p_diamonds, v_coins, v_new_diamonds, v_idem, now())
    ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'duplicate', false,
    'diamonds', p_diamonds,
    'coins_received', v_coins,
    'new_balance', v_new_diamonds,
    'diamonds_earned_monthly', v_new_monthly
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.agency_exchange_diamonds_v2(bigint, text, text, numeric)
  TO authenticated, service_role, anon;

CREATE OR REPLACE FUNCTION public.admin_process_diamond_transaction(
  p_user_id text,
  p_amount bigint,
  p_type text,
  p_reason text DEFAULT 'تعديل رصيد من الإدارة',
  p_admin_name text DEFAULT 'المدير العام',
  p_sync_monthly_target boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_diamonds bigint := 0;
  v_new_diamonds bigint := 0;
  v_abs_amount bigint;
  v_diff bigint;
  v_user_uuid uuid;
  v_member record;
  v_agency_id text;
  v_member_balance bigint := 0;
  v_member_new bigint := 0;
  v_member_diff bigint := 0;
  v_member_monthly bigint := 0;
  v_member_cumulative bigint := 0;
  v_member_updated boolean := false;
  v_log_diff bigint := 0;
  v_log_before bigint := 0;
  v_log_after bigint := 0;
BEGIN
  v_abs_amount := ABS(COALESCE(p_amount, 0));
  IF v_abs_amount <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'المبلغ يجب أن يكون أكبر من صفر');
  END IF;

  IF p_type NOT IN ('add', 'deduct') THEN
    RETURN jsonb_build_object('success', false, 'error', 'نوع العملية غير صحيح');
  END IF;

  SELECT diamonds
  INTO v_current_diamonds
  FROM public.users
  WHERE uid::text = p_user_id OR id::text = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
  END IF;

  v_current_diamonds := COALESCE(v_current_diamonds, 0);

  BEGIN
    SELECT id::uuid INTO v_user_uuid
    FROM public.users
    WHERE uid::text = p_user_id OR id::text = p_user_id
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_user_uuid := NULL;
  END;

  IF p_type = 'add' THEN
    v_new_diamonds := v_current_diamonds + v_abs_amount;
  ELSE
    v_new_diamonds := GREATEST(0, v_current_diamonds - v_abs_amount);
  END IF;

  v_diff := v_new_diamonds - v_current_diamonds;

  UPDATE public.users
  SET diamonds = v_new_diamonds
  WHERE uid::text = p_user_id OR id::text = p_user_id;

  SELECT id, agency_id, diamonds, diamonds_balance, diamonds_available,
         diamonds_earned_monthly, diamonds_earned_cumulative
  INTO v_member
  FROM public.host_agency_members
  WHERE user_id::text = p_user_id OR host_uid::text = p_user_id
  ORDER BY joined_at NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    v_agency_id := v_member.agency_id::text;
    v_member_balance := GREATEST(0, COALESCE(
      v_member.diamonds_available, v_member.diamonds_balance, v_member.diamonds, 0));

    IF p_type = 'add' THEN
      v_member_new := v_member_balance + v_abs_amount;
    ELSE
      v_member_new := GREATEST(0, v_member_balance - v_abs_amount);
    END IF;

    v_member_diff := v_member_new - v_member_balance;

    IF p_sync_monthly_target THEN
      v_member_monthly := GREATEST(0, COALESCE(v_member.diamonds_earned_monthly, 0) + v_member_diff);
    ELSE
      v_member_monthly := COALESCE(v_member.diamonds_earned_monthly, 0);
    END IF;

    IF p_type = 'add' THEN
      v_member_cumulative := GREATEST(0, COALESCE(v_member.diamonds_earned_cumulative, 0) + v_member_diff);
    ELSE
      v_member_cumulative := COALESCE(v_member.diamonds_earned_cumulative, 0);
    END IF;

    UPDATE public.host_agency_members
    SET diamonds = v_member_new,
        diamonds_balance = v_member_new,
        diamonds_available = v_member_new,
        diamonds_earned_monthly = v_member_monthly,
        diamonds_earned_cumulative = v_member_cumulative,
        updated_at = now()
    WHERE id = v_member.id;

    IF v_agency_id IS NOT NULL AND v_agency_id <> '' THEN
      PERFORM public.agency_recalc_totals(v_agency_id);
    END IF;

    v_member_updated := true;
  END IF;

  IF v_member_updated THEN
    v_log_diff := v_member_diff;
    v_log_before := v_member_balance;
    v_log_after := v_member_new;
  ELSE
    v_log_diff := v_diff;
    v_log_before := v_current_diamonds;
    v_log_after := v_new_diamonds;
  END IF;

  IF v_user_uuid IS NOT NULL THEN
    INSERT INTO public.user_diamond_logs (
      user_id, amount, type, balance_before, balance_after,
      admin_name, reason, created_at
    ) VALUES (
      v_user_uuid, v_log_diff,
      CASE WHEN p_type = 'add' THEN 'admin_add' ELSE 'admin_deduct' END,
      v_log_before, v_log_after,
      p_admin_name, p_reason, now()
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'old_diamonds', v_current_diamonds,
    'new_diamonds', v_new_diamonds,
    'amount', v_abs_amount,
    'type', p_type,
    'monthly_synced', p_sync_monthly_target,
    'member_updated', v_member_updated,
    'member_diff', v_member_diff,
    'member_balance', v_member_new,
    'member_monthly', v_member_monthly,
    'member_cumulative', v_member_cumulative,
    'member_withdrawable', LEAST(v_member_new, v_member_monthly)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_process_diamond_transaction(text, bigint, text, text, text, boolean)
  TO authenticated, service_role, anon;
