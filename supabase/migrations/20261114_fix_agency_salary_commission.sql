-- ─────────────────────────────────────────────────────────────
-- Salary payout must not reduce the agency commission base.
--
-- diamonds_earned_monthly is consumed when the host withdraws salary,
-- but the same amount is moved into unpacked_target_diamonds so the
-- owner commission (monthly + unpacked) stays intact. Rejecting a
-- frozen request reverses both counters.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.agency_request_withdrawal_v2(
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
  v_monthly bigint := 0;
  v_exchangeable bigint := 0;
  v_new_balance bigint := 0;
  v_new_monthly bigint := 0;
  v_request_id uuid;
  v_per_usd numeric := 15000;
  v_net_usd numeric := 0;
  v_idem text;
BEGIN
  v_uid := auth.uid()::text;
  IF v_uid IS NULL OR v_uid = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthorized');
  END IF;
  IF p_user_id IS NOT NULL AND p_user_id <> '' AND p_user_id <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
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
  ORDER BY joined_at NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF v_member.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_member');
  END IF;

  v_available := COALESCE(v_member.diamonds_available,
    v_member.diamonds_balance, 0);
  v_monthly := GREATEST(0, COALESCE(v_member.diamonds_earned_monthly, 0));
  v_exchangeable := LEAST(v_available, v_monthly);

  IF v_exchangeable < p_diamonds THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'insufficient_exchangeable_balance',
      'available', v_available,
      'monthly', v_monthly,
      'exchangeable', v_exchangeable
    );
  END IF;

  v_new_balance := GREATEST(0, v_available - p_diamonds);
  v_new_monthly := GREATEST(0, v_monthly - p_diamonds);

  UPDATE public.host_agency_members
  SET diamonds = v_new_balance,
      diamonds_balance = v_new_balance,
      diamonds_available = v_new_balance,
      diamonds_earned_monthly = v_new_monthly,
      diamonds_pending_withdrawal = COALESCE(diamonds_pending_withdrawal, 0) + p_diamonds,
      unpacked_target_diamonds = COALESCE(unpacked_target_diamonds, 0) + p_diamonds,
      has_unpacked_target = true,
      updated_at = now()
  WHERE id = v_member.id;

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
       'frozen', true,
       'monthly_deducted', true,
       'request_type', 'host_cash_withdrawal',
       'monthly_before', v_monthly),
     'pending', now())
  RETURNING id INTO v_request_id;

  IF v_idem IS NOT NULL AND v_member.agency_id IS NOT NULL THEN
    INSERT INTO public.agency_diamond_ledger
      (agency_id, user_id, txn_type, amount, direction, balance_after,
       note, idempotency_key, created_at)
    VALUES
      (v_member.agency_id, v_uid, 'withdrawal_request', p_diamonds, -1,
       v_new_balance, 'طلب سحب — مبلغ مجمّد',
       'withdraw_' || v_idem, now())
    ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;

  PERFORM public.agency_recalc_totals(v_member.agency_id);

  RETURN jsonb_build_object(
    'success', true,
    'request_id', v_request_id,
    'diamonds', p_diamonds,
    'new_balance', v_new_balance,
    'monthly_after', v_new_monthly,
    'exchangeable_before', v_exchangeable,
    'net_usd', v_net_usd,
    'status', 'pending'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.agency_request_withdrawal_v2(bigint, jsonb, text, text)
  TO authenticated, service_role, anon;

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
  v_frozen boolean := false;
  v_monthly_deducted boolean := false;
  v_is_owner boolean := false;
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
  v_monthly_deducted := COALESCE((v_req.details->>'monthly_deducted')::boolean, false);

  SELECT COALESCE(bool_or(role = 'owner'), false)
  INTO v_is_owner
  FROM public.host_agency_members
  WHERE (user_id::text = v_req.user_id::text OR host_uid::text = v_req.user_id::text)
    AND (v_req.agency_id IS NULL OR agency_id::text = v_req.agency_id::text);

  IF v_frozen THEN
    UPDATE public.host_agency_members
    SET diamonds_pending_withdrawal =
          GREATEST(0, COALESCE(diamonds_pending_withdrawal, 0) - v_amount),
        diamonds_earned_monthly = CASE
          WHEN v_is_owner THEN COALESCE(diamonds_earned_monthly, 0)
          WHEN v_monthly_deducted THEN COALESCE(diamonds_earned_monthly, 0)
          ELSE GREATEST(0, COALESCE(diamonds_earned_monthly, 0) - v_amount)
        END,
        unpacked_target_diamonds = CASE
          WHEN v_is_owner OR v_monthly_deducted
            THEN COALESCE(unpacked_target_diamonds, 0)
          ELSE COALESCE(unpacked_target_diamonds, 0) + v_amount
        END,
        has_unpacked_target = CASE
          WHEN v_is_owner OR v_monthly_deducted THEN has_unpacked_target
          ELSE true
        END,
        updated_at = now()
    WHERE agency_id::text = v_req.agency_id::text
      AND (user_id::text = v_req.user_id::text OR host_uid::text = v_req.user_id::text);
  ELSE
    -- طلبات قديمة لم تُجمّد المبلغ: نخصمه الآن من محفظة العضو فقط
    UPDATE public.host_agency_members
    SET diamonds = GREATEST(0, COALESCE(diamonds, 0) - v_amount),
        diamonds_balance = GREATEST(0, COALESCE(diamonds_balance, 0) - v_amount),
        diamonds_available = GREATEST(0, COALESCE(diamonds_available, 0) - v_amount),
        diamonds_pending_withdrawal =
          GREATEST(0, COALESCE(diamonds_pending_withdrawal, 0) - v_amount),
        diamonds_earned_monthly = CASE
          WHEN v_is_owner THEN COALESCE(diamonds_earned_monthly, 0)
          ELSE GREATEST(0, COALESCE(diamonds_earned_monthly, 0) - v_amount)
        END,
        unpacked_target_diamonds = CASE
          WHEN v_is_owner THEN COALESCE(unpacked_target_diamonds, 0)
          ELSE COALESCE(unpacked_target_diamonds, 0) + v_amount
        END,
        has_unpacked_target = CASE
          WHEN v_is_owner THEN has_unpacked_target
          ELSE true
        END,
        updated_at = now()
    WHERE agency_id::text = v_req.agency_id::text
      AND (user_id::text = v_req.user_id::text OR host_uid::text = v_req.user_id::text);
  END IF;

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
  v_monthly_deducted boolean := false;
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
  v_monthly_deducted := COALESCE((v_req.details->>'monthly_deducted')::boolean, false);

  IF v_frozen THEN
    UPDATE public.host_agency_members
    SET diamonds = COALESCE(diamonds, 0) + v_amount,
        diamonds_balance = COALESCE(diamonds_balance, 0) + v_amount,
        diamonds_available = COALESCE(diamonds_available, 0) + v_amount,
        diamonds_pending_withdrawal =
          GREATEST(0, COALESCE(diamonds_pending_withdrawal, 0) - v_amount),
        diamonds_earned_monthly = CASE
          WHEN v_monthly_deducted
            THEN COALESCE(diamonds_earned_monthly, 0) + v_amount
          ELSE COALESCE(diamonds_earned_monthly, 0)
        END,
        unpacked_target_diamonds = CASE
          WHEN v_monthly_deducted
            THEN GREATEST(0, COALESCE(unpacked_target_diamonds, 0) - v_amount)
          ELSE COALESCE(unpacked_target_diamonds, 0)
        END,
        updated_at = now()
    WHERE agency_id::text = v_req.agency_id::text
      AND (user_id::text = v_req.user_id::text OR host_uid::text = v_req.user_id::text);
  END IF;

  UPDATE public.agency_withdrawal_requests
  SET status = 'rejected', reviewed_at = now(),
      admin_notes = COALESCE(p_notes, p_admin_name)
  WHERE id = p_request_id;

  RETURN jsonb_build_object('success', true, 'status', 'rejected', 'amount', v_amount);
END;
$$;

GRANT EXECUTE ON FUNCTION public.agency_approve_withdrawal(uuid, text)
  TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.agency_reject_withdrawal(uuid, text, text)
  TO authenticated, service_role, anon;

NOTIFY pgrst, 'reload schema';
