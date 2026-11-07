-- ============================================================================
-- Agency Commission Release Cycle
-- ----------------------------------------------------------------------------
-- Previously, every gift credited the agency owner's 20% commission straight
-- into host_agency_members.diamonds_available (instantly withdrawable).
--
-- New model:
--   1. Commission is ACCRUED into host_agencies.pending_commission_diamonds.
--   2. It is RELEASED to the owner wallet only on the configured cycle
--      (daily / weekly / monthly), respecting:
--         - week_start       : 1=Monday .. 7=Sunday
--         - release_day      : weekly => ISO weekday (1..7)
--                              monthly => day of month (1..28)
--         - release_time     : HH:MM in the configured timezone
--         - timezone         : e.g. Asia/Riyadh (app-wide timing)
--         - auto_release     : true => release automatically when due
--   3. Admin can always force-release from the dashboard.
-- ============================================================================

-- 1) Pending / released commission buckets
ALTER TABLE public.host_agencies
  ADD COLUMN IF NOT EXISTS pending_commission_diamonds  bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS released_commission_diamonds bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_commission_release_at   timestamptz,
  ADD COLUMN IF NOT EXISTS next_commission_release_at   timestamptz;

-- 2) Default cycle config (single JSON object in app_config)
INSERT INTO public.app_config (key, value)
VALUES (
  'agency_commission_cycle',
  '{"period":"monthly","week_start":1,"release_day":1,"release_time":"00:00","timezone":"Asia/Riyadh","auto_release":false}'::jsonb
)
ON CONFLICT (key) DO NOTHING;

-- Keep the legacy key in sync for old clients (do not overwrite existing value)
INSERT INTO public.app_config (key, value)
VALUES ('agency_commission_period', '"monthly"'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- 3) Effective cycle config with safe defaults
CREATE OR REPLACE FUNCTION public.agency_commission_cycle_config()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v jsonb;
BEGIN
  SELECT value INTO v FROM public.app_config WHERE key = 'agency_commission_cycle';
  v := COALESCE(v, '{}'::jsonb);

  RETURN jsonb_build_object(
    'period',       COALESCE(NULLIF(v->>'period', ''), 'monthly'),
    'week_start',   COALESCE(NULLIF(v->>'week_start', '')::int, 1),
    'release_day',  COALESCE(NULLIF(v->>'release_day', '')::int, 1),
    'release_time', COALESCE(NULLIF(v->>'release_time', ''), '00:00'),
    'timezone',     COALESCE(NULLIF(v->>'timezone', ''), 'UTC'),
    'auto_release', COALESCE(NULLIF(v->>'auto_release', '')::boolean, false)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'period', 'monthly',
    'week_start', 1,
    'release_day', 1,
    'release_time', '00:00',
    'timezone', 'UTC',
    'auto_release', false
  );
END;
$$;

-- 4) Next release timestamp (computed from the cycle config)
CREATE OR REPLACE FUNCTION public.agency_compute_next_release(p_from timestamptz DEFAULT now())
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cfg        jsonb := public.agency_commission_cycle_config();
  v_period   text  := COALESCE(cfg->>'period', 'monthly');
  v_tz       text  := COALESCE(NULLIF(cfg->>'timezone', ''), 'UTC');
  v_time     time;
  v_local    timestamp;
  v_cand     timestamp;
  v_dow      int;
  v_day      int;
BEGIN
  BEGIN
    v_time := COALESCE(NULLIF(cfg->>'release_time', '')::time, '00:00'::time);
  EXCEPTION WHEN OTHERS THEN
    v_time := '00:00'::time;
  END;

  v_local := p_from AT TIME ZONE v_tz;

  IF v_period = 'daily' THEN
    v_cand := date_trunc('day', v_local) + v_time;
    IF v_cand <= v_local THEN
      v_cand := v_cand + interval '1 day';
    END IF;

  ELSIF v_period = 'weekly' THEN
    v_dow := COALESCE(NULLIF(cfg->>'release_day', '')::int, 1);
    IF v_dow < 1 OR v_dow > 7 THEN
      v_dow := 1;
    END IF;
    v_cand := date_trunc('day', v_local) + v_time
              + ((v_dow - EXTRACT(ISODOW FROM v_local)::int) || ' days')::interval;
    IF v_cand <= v_local THEN
      v_cand := v_cand + interval '7 days';
    END IF;

  ELSE
    v_day := COALESCE(NULLIF(cfg->>'release_day', '')::int, 1);
    IF v_day < 1 THEN
      v_day := 1;
    END IF;
    IF v_day > 28 THEN
      v_day := 28;
    END IF;
    v_cand := date_trunc('month', v_local)
              + ((v_day - 1) || ' days')::interval
              + v_time;
    IF v_cand <= v_local THEN
      v_cand := date_trunc('month', v_local) + interval '1 month'
                + ((v_day - 1) || ' days')::interval
                + v_time;
    END IF;
  END IF;

  RETURN v_cand AT TIME ZONE v_tz;
END;
$$;

-- 5) Accrue commission (no wallet credit — sits in pending bucket)
CREATE OR REPLACE FUNCTION public.agency_accrue_commission(
  p_agency_id text,
  p_diamonds  bigint,
  p_note      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner   text;
  v_pending bigint;
BEGIN
  IF p_agency_id IS NULL OR p_agency_id = '' OR COALESCE(p_diamonds, 0) <= 0 THEN
    RETURN jsonb_build_object('status', 'invalid_input');
  END IF;

  UPDATE public.host_agencies
  SET pending_commission_diamonds = COALESCE(pending_commission_diamonds, 0) + p_diamonds,
      next_commission_release_at  = COALESCE(next_commission_release_at, public.agency_compute_next_release()),
      updated_at = now()
  WHERE id::text = p_agency_id
  RETURNING pending_commission_diamonds,
            COALESCE(NULLIF(owner_uid, ''), owner_id::text)
    INTO v_pending, v_owner;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'agency_not_found');
  END IF;

  INSERT INTO public.agency_diamond_ledger
    (agency_id, user_id, txn_type, amount, direction, balance_after, note, sender_name, created_at)
  VALUES
    (p_agency_id, v_owner, 'commission_accrual', p_diamonds, 1, v_pending,
     COALESCE(p_note, 'استحقاق عمولة وكالة (بانتظار دورة الإصدار)'),
     'النظام', now());

  RETURN jsonb_build_object('status', 'ok', 'pending', v_pending);
END;
$$;

-- 6) Release pending commission to the owner wallet
CREATE OR REPLACE FUNCTION public.agency_release_commission(
  p_agency_id text,
  p_force     boolean DEFAULT false,
  p_note      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_agency      public.host_agencies%ROWTYPE;
  v_cfg         jsonb;
  v_next        timestamptz;
  v_pending     bigint;
  v_owner       text;
  v_member      public.host_agency_members%ROWTYPE;
  v_new_balance bigint;
  v_new_avail   bigint;
  v_new_next    timestamptz;
BEGIN
  SELECT * INTO v_agency
  FROM public.host_agencies
  WHERE id::text = p_agency_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'agency_not_found');
  END IF;

  v_cfg     := public.agency_commission_cycle_config();
  v_next    := COALESCE(v_agency.next_commission_release_at, public.agency_compute_next_release());
  v_pending := COALESCE(v_agency.pending_commission_diamonds, 0);

  IF v_pending <= 0 THEN
    RETURN jsonb_build_object(
      'status', 'nothing_to_release',
      'pending', 0,
      'next_release_at', v_next
    );
  END IF;

  IF NOT p_force THEN
    IF COALESCE((v_cfg->>'auto_release')::boolean, false) = false
       OR now() < v_next THEN
      RETURN jsonb_build_object(
        'status', 'not_due',
        'pending', v_pending,
        'next_release_at', v_next
      );
    END IF;
  END IF;

  v_owner := COALESCE(NULLIF(v_agency.owner_uid, ''), v_agency.owner_id::text);
  IF v_owner IS NULL OR v_owner = '' THEN
    RETURN jsonb_build_object('status', 'owner_missing', 'pending', v_pending);
  END IF;

  SELECT * INTO v_member
  FROM public.host_agency_members
  WHERE agency_id::text = p_agency_id
    AND (user_id::text = v_owner OR host_uid::text = v_owner)
  ORDER BY CASE WHEN role = 'owner' THEN 0 ELSE 1 END
  LIMIT 1
  FOR UPDATE;

  IF v_member.id IS NULL THEN
    v_new_balance := v_pending;
    v_new_avail   := v_pending;
    INSERT INTO public.host_agency_members
      (agency_id, host_uid, user_id, role, status,
       diamonds, diamonds_balance, diamonds_available,
       diamonds_earned_cumulative, joined_at, created_at, updated_at)
    VALUES
      (p_agency_id, v_owner, v_owner, 'owner', 'active',
       v_new_balance, v_new_balance, v_new_avail,
       v_pending, now(), now(), now());
  ELSE
    v_new_balance := COALESCE(v_member.diamonds_balance, v_member.diamonds, 0) + v_pending;
    v_new_avail   := COALESCE(v_member.diamonds_available, v_member.diamonds_balance, v_member.diamonds, 0) + v_pending;
    -- NOTE: cumulative is intentionally NOT incremented here to avoid
    -- double-counting the host income already included in agency totals.
    UPDATE public.host_agency_members
    SET diamonds             = v_new_balance,
        diamonds_balance     = v_new_balance,
        diamonds_available   = v_new_avail,
        updated_at           = now()
    WHERE id = v_member.id;
  END IF;

  v_new_next := public.agency_compute_next_release(now() + interval '1 second');

  UPDATE public.host_agencies
  SET pending_commission_diamonds  = 0,
      released_commission_diamonds = COALESCE(released_commission_diamonds, 0) + v_pending,
      last_commission_release_at   = now(),
      next_commission_release_at   = v_new_next,
      updated_at                   = now()
  WHERE id::text = p_agency_id;

  INSERT INTO public.agency_diamond_ledger
    (agency_id, user_id, txn_type, amount, direction, balance_after, note, sender_name, created_at)
  VALUES
    (p_agency_id, v_owner, 'commission_release', v_pending, 1, v_new_balance,
     COALESCE(p_note, 'إصدار عمولة الوكالة حسب الدورة المعتمدة'),
     'الإدارة', now());

  PERFORM public.agency_recalc_totals(p_agency_id);

  RETURN jsonb_build_object(
    'status', 'released',
    'released', v_pending,
    'owner_uid', v_owner,
    'balance_after', v_new_balance,
    'next_release_at', v_new_next
  );
END;
$$;

-- 7) Release all due commissions (used by auto-release + lazy app trigger)
CREATE OR REPLACE FUNCTION public.agency_release_due_commissions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cfg   jsonb := public.agency_commission_cycle_config();
  r       record;
  v_res   jsonb;
  v_count int := 0;
  v_total bigint := 0;
BEGIN
  IF COALESCE((v_cfg->>'auto_release')::boolean, false) = false THEN
    RETURN jsonb_build_object('status', 'auto_release_disabled', 'released_count', 0);
  END IF;

  FOR r IN
    SELECT id
    FROM public.host_agencies
    WHERE COALESCE(pending_commission_diamonds, 0) > 0
      AND COALESCE(next_commission_release_at, public.agency_compute_next_release()) <= now()
  LOOP
    v_res := public.agency_release_commission(
      r.id::text, false, 'إصدار تلقائي حسب دورة العمولة');
    IF v_res->>'status' = 'released' THEN
      v_count := v_count + 1;
      v_total := v_total + COALESCE((v_res->>'released')::bigint, 0);
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'ok',
    'released_count', v_count,
    'released_total', v_total
  );
END;
$$;

-- 8) Read-only release info for the app / admin dashboard
CREATE OR REPLACE FUNCTION public.agency_commission_release_info(p_agency_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_agency public.host_agencies%ROWTYPE;
BEGIN
  SELECT * INTO v_agency FROM public.host_agencies WHERE id::text = p_agency_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'agency_not_found');
  END IF;

  RETURN jsonb_build_object(
    'status', 'ok',
    'pending',  COALESCE(v_agency.pending_commission_diamonds, 0),
    'released', COALESCE(v_agency.released_commission_diamonds, 0),
    'last_release_at', v_agency.last_commission_release_at,
    'next_release_at', COALESCE(v_agency.next_commission_release_at, public.agency_compute_next_release()),
    'cycle', public.agency_commission_cycle_config()
  );
END;
$$;

-- 9) Rewrite gift/income credit: accrue owner commission instead of paying it
CREATE OR REPLACE FUNCTION public.agency_credit_host_target_diamonds(
  p_host_uid       text,
  p_diamonds       bigint,
  p_agency_rate_pct numeric DEFAULT NULL,
  p_idem_key       text DEFAULT NULL,
  p_source         text DEFAULT 'gift'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member       record;
  v_agency_id    text;
  v_owner_uid    text;
  v_user_uuid    uuid;
  v_rate         numeric := 0;
  v_commission   bigint := 0;
  v_new_balance  bigint := 0;
  v_pending      bigint := 0;
  v_idem         text;
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

  UPDATE public.host_agency_members
  SET diamonds                  = v_new_balance,
      diamonds_balance          = v_new_balance,
      diamonds_available        = v_new_balance,
      diamonds_earned_monthly   = COALESCE(diamonds_earned_monthly, 0) + p_diamonds,
      diamonds_earned_cumulative = COALESCE(diamonds_earned_cumulative, 0) + p_diamonds,
      updated_at                = now()
  WHERE id = v_member.id;

  IF v_agency_id IS NOT NULL THEN
    SELECT COALESCE(NULLIF(owner_uid, ''), owner_id::text)
    INTO v_owner_uid
    FROM public.host_agencies
    WHERE id::text = v_agency_id::text;

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

    -- ACCRUE (do NOT credit the owner wallet immediately)
    IF v_commission > 0 AND v_owner_uid IS NOT NULL
       AND v_owner_uid <> p_host_uid THEN
      UPDATE public.host_agencies
      SET pending_commission_diamonds = COALESCE(pending_commission_diamonds, 0) + v_commission,
          next_commission_release_at  = COALESCE(next_commission_release_at, public.agency_compute_next_release()),
          updated_at = now()
      WHERE id::text = v_agency_id::text
      RETURNING pending_commission_diamonds INTO v_pending;
    END IF;

    PERFORM public.agency_recalc_totals(v_agency_id);

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

-- 10) Ensure next release is populated for existing agencies
UPDATE public.host_agencies
SET next_commission_release_at = public.agency_compute_next_release()
WHERE next_commission_release_at IS NULL;

-- 11) Grants (RLS is bypassed inside SECURITY DEFINER; allow authenticated callers)
GRANT EXECUTE ON FUNCTION public.agency_commission_cycle_config() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.agency_compute_next_release(timestamptz) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.agency_accrue_commission(text, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.agency_release_commission(text, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.agency_release_due_commissions() TO authenticated;
GRANT EXECUTE ON FUNCTION public.agency_commission_release_info(text) TO authenticated, anon;
