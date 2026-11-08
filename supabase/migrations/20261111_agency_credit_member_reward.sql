-- 20261111_agency_credit_member_reward.sql
-- إضافة RPC لصرف مكافآت التارجت (نوع diamonds) عبر دفتر الوكالة بدل التعديل المباشر على الرصيد.
-- لا تُحتسب عمولة على مكافآت التارجت (العمولة تُحتسب فقط على إنتاج الهدايا).

CREATE OR REPLACE FUNCTION public.agency_credit_member_reward(
  p_host_uid text,
  p_diamonds bigint,
  p_idem_key text DEFAULT NULL,
  p_note text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_member      record;
  v_agency_id   text;
  v_new_balance bigint := 0;
  v_idem        text;
BEGIN
  IF p_host_uid IS NULL OR p_host_uid = '' OR COALESCE(p_diamonds, 0) <= 0 THEN
    RETURN jsonb_build_object('status', 'invalid_input');
  END IF;

  v_idem := NULLIF(p_idem_key, '');
  IF v_idem IS NULL THEN
    v_idem := 'target_reward_' || p_host_uid || '_' || gen_random_uuid()::text;
  END IF;

  IF EXISTS (SELECT 1 FROM public.agency_diamond_ledger WHERE idempotency_key = v_idem) THEN
    RETURN jsonb_build_object('status', 'already_processed', 'idem_key', v_idem);
  END IF;

  SELECT *
  INTO v_member
  FROM public.host_agency_members
  WHERE (user_id::text = p_host_uid OR host_uid::text = p_host_uid)
    AND COALESCE(status, 'active') <> 'kicked'
  ORDER BY joined_at NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF v_member.id IS NULL THEN
    RETURN jsonb_build_object('status', 'not_member');
  END IF;

  v_agency_id := v_member.agency_id;
  v_new_balance := COALESCE(v_member.diamonds_balance, v_member.diamonds, 0) + p_diamonds;

  UPDATE public.host_agency_members
  SET diamonds            = v_new_balance,
      diamonds_balance    = v_new_balance,
      diamonds_available  = v_new_balance,
      updated_at          = now()
  WHERE id = v_member.id;

  INSERT INTO public.agency_diamond_ledger
    (agency_id, user_id, txn_type, amount, direction, balance_after,
     note, sender_name, idempotency_key, created_at)
  VALUES
    (v_agency_id, p_host_uid, 'target_reward', p_diamonds, 1, v_new_balance,
     COALESCE(p_note, 'مكافأة تارجت'), 'النظام', v_idem, now())
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN jsonb_build_object('status', 'ok', 'balance', v_new_balance);
END;
$function$;
