-- ==============================================================================
-- RECHARGE AGENCY CASH OUT & EXCHANGE TIERS SYSTEM
-- نظام صرف ألماس وكالة الشحن وإدارة باقات الصرف وتحويل الرواتب
-- ==============================================================================

-- 1. Ensure table agency_wallets has all balance & stats columns
CREATE TABLE IF NOT EXISTS public.agency_wallets (
  agency_profile_id uuid PRIMARY KEY,
  gold_balance bigint NOT NULL DEFAULT 0 CHECK (gold_balance >= 0),
  diamond_balance bigint NOT NULL DEFAULT 0 CHECK (diamond_balance >= 0),
  total_received bigint NOT NULL DEFAULT 0 CHECK (total_received >= 0),
  total_withdrawn bigint NOT NULL DEFAULT 0 CHECK (total_withdrawn >= 0),
  total_earnings bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS gold_balance bigint NOT NULL DEFAULT 0 CHECK (gold_balance >= 0);
ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS diamond_balance bigint NOT NULL DEFAULT 0 CHECK (diamond_balance >= 0);
ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS total_received bigint NOT NULL DEFAULT 0 CHECK (total_received >= 0);
ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS total_withdrawn bigint NOT NULL DEFAULT 0 CHECK (total_withdrawn >= 0);
ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS total_earnings bigint NOT NULL DEFAULT 0;
ALTER TABLE public.agency_wallets ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- 2. Transactions table for agent diamond wallet
CREATE TABLE IF NOT EXISTS public.agent_diamond_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id uuid NOT NULL,
  sender_id uuid,
  sender_name text,
  sender_avatar text,
  sender_kayan_id text,
  txn_type text NOT NULL, -- 'received_from_host', 'received_from_agency', 'admin_withdrawal', 'exchange_to_coins'
  diamonds_amount bigint NOT NULL,
  coins_amount bigint DEFAULT 0,
  usd_amount numeric(10, 2) DEFAULT 0,
  balance_after bigint,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS agent_diamond_transactions_agent_idx
  ON public.agent_diamond_transactions (agent_id, created_at DESC);

-- 3. Recharge Agency Exchange Tiers Table (باقات صرف الألماس إلى كوينز)
CREATE TABLE IF NOT EXISTS public.recharge_agency_exchange_tiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usd_amount numeric(10, 2) NOT NULL DEFAULT 1.00,
  diamonds_cost bigint NOT NULL DEFAULT 15000,
  coins_received bigint NOT NULL DEFAULT 1000,
  title text NOT NULL DEFAULT '',
  badge_text text DEFAULT NULL,
  is_active boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- RLS for Exchange Tiers
ALTER TABLE public.recharge_agency_exchange_tiers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read active exchange tiers" ON public.recharge_agency_exchange_tiers;
CREATE POLICY "Anyone can read active exchange tiers"
  ON public.recharge_agency_exchange_tiers FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Service role / admin full access on exchange tiers" ON public.recharge_agency_exchange_tiers;
CREATE POLICY "Service role / admin full access on exchange tiers"
  ON public.recharge_agency_exchange_tiers FOR ALL
  USING (true)
  WITH CHECK (true);

-- 4. Seed default tiers if none exist
INSERT INTO public.recharge_agency_exchange_tiers (usd_amount, diamonds_cost, coins_received, title, badge_text, sort_order)
SELECT 1.00, 15000, 1000, 'باقة 1 دولار', 'أساسي', 1
WHERE NOT EXISTS (SELECT 1 FROM public.recharge_agency_exchange_tiers WHERE usd_amount = 1.00 AND diamonds_cost = 15000);

INSERT INTO public.recharge_agency_exchange_tiers (usd_amount, diamonds_cost, coins_received, title, badge_text, sort_order)
SELECT 2.00, 30000, 30000, 'باقة 2 دولار', 'شائع', 2
WHERE NOT EXISTS (SELECT 1 FROM public.recharge_agency_exchange_tiers WHERE usd_amount = 2.00 AND diamonds_cost = 30000);

INSERT INTO public.recharge_agency_exchange_tiers (usd_amount, diamonds_cost, coins_received, title, badge_text, sort_order)
SELECT 5.00, 75000, 80000, 'باقة 5 دولار', 'توفير', 3
WHERE NOT EXISTS (SELECT 1 FROM public.recharge_agency_exchange_tiers WHERE usd_amount = 5.00 AND diamonds_cost = 75000);

INSERT INTO public.recharge_agency_exchange_tiers (usd_amount, diamonds_cost, coins_received, title, badge_text, sort_order)
SELECT 10.00, 150000, 165000, 'باقة 10 دولار', 'أفضل قيمة', 4
WHERE NOT EXISTS (SELECT 1 FROM public.recharge_agency_exchange_tiers WHERE usd_amount = 10.00 AND diamonds_cost = 150000);

INSERT INTO public.recharge_agency_exchange_tiers (usd_amount, diamonds_cost, coins_received, title, badge_text, sort_order)
SELECT 20.00, 300000, 340000, 'باقة 20 دولار', 'VIP', 5
WHERE NOT EXISTS (SELECT 1 FROM public.recharge_agency_exchange_tiers WHERE usd_amount = 20.00 AND diamonds_cost = 300000);

-- 5. RPC: Get Agent Diamond Wallet Data (Balance + Stats + Recent Txns)
CREATE OR REPLACE FUNCTION public.agent_get_diamond_wallet()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_wallet record;
  v_txns jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- Ensure wallet row exists
  INSERT INTO public.agency_wallets (agency_profile_id, diamond_balance, gold_balance, total_received, total_withdrawn)
  VALUES (v_uid, 0, 0, 0, 0)
  ON CONFLICT (agency_profile_id) DO NOTHING;

  SELECT * INTO v_wallet FROM public.agency_wallets WHERE agency_profile_id = v_uid;

  SELECT coalesce(jsonb_agg(to_jsonb(t.*)), '[]'::jsonb)
  INTO v_txns
  FROM (
    SELECT id, agent_id, sender_id, sender_name, sender_avatar, sender_kayan_id,
           txn_type, diamonds_amount, coins_amount, usd_amount, balance_after, notes, created_at
    FROM public.agent_diamond_transactions
    WHERE agent_id = v_uid
    ORDER BY created_at DESC
    LIMIT 100
  ) t;

  RETURN jsonb_build_object(
    'wallet', to_jsonb(v_wallet),
    'transactions', v_txns
  );
END;
$$;

-- 6. RPC: Atomic Exchange Diamonds to Agency Coins
CREATE OR REPLACE FUNCTION public.agent_exchange_diamonds_to_coins(
  p_tier_id uuid,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tier record;
  v_wallet record;
  v_new_diamond bigint;
  v_new_gold bigint;
  v_new_withdrawn bigint;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مسجل الدخول');
  END IF;

  -- 1. Fetch requested exchange tier
  SELECT * INTO v_tier
  FROM public.recharge_agency_exchange_tiers
  WHERE id = p_tier_id AND is_active = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'باقة الصرف غير موجودة أو معطلة حالياً');
  END IF;

  -- 2. Lock & fetch agency wallet
  SELECT * INTO v_wallet
  FROM public.agency_wallets
  WHERE agency_profile_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'لم يتم العثور على محفظة الوكالة');
  END IF;

  IF v_wallet.diamond_balance < v_tier.diamonds_cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', format('رصيد الألماس المتاح لا يكفي (المتاح: %s 💎، المطلوب: %s 💎)', v_wallet.diamond_balance, v_tier.diamonds_cost)
    );
  END IF;

  v_new_diamond := v_wallet.diamond_balance - v_tier.diamonds_cost;
  v_new_gold := v_wallet.gold_balance + v_tier.coins_received;
  v_new_withdrawn := v_wallet.total_withdrawn + v_tier.diamonds_cost;

  -- 3. Update agency wallet (strictly agency_wallets, never users.coins)
  UPDATE public.agency_wallets
  SET diamond_balance = v_new_diamond,
      gold_balance = v_new_gold,
      total_withdrawn = v_new_withdrawn,
      updated_at = now()
  WHERE agency_profile_id = v_uid;

  -- 4. Log transaction
  INSERT INTO public.agent_diamond_transactions (
    agent_id,
    sender_id,
    sender_name,
    txn_type,
    diamonds_amount,
    coins_amount,
    usd_amount,
    balance_after,
    notes
  ) VALUES (
    v_uid,
    v_uid,
    'صرف أرباح الوكالة',
    'exchange_to_coins',
    v_tier.diamonds_cost,
    v_tier.coins_received,
    v_tier.usd_amount,
    v_new_diamond,
    format('صرف %s ماسة ($%s) إلى %s كوينز في محفظة وكالة الشحن', v_tier.diamonds_cost, v_tier.usd_amount, v_tier.coins_received)
  );

  RETURN jsonb_build_object(
    'success', true,
    'message', format('تم صرف %s كوينز وإضافتها لمحفظة الوكالة بنجاح! 🪙', v_tier.coins_received),
    'new_diamond_balance', v_new_diamond,
    'new_gold_balance', v_new_gold,
    'coins_received', v_tier.coins_received,
    'diamonds_deducted', v_tier.diamonds_cost
  );
END;
$$;

-- 7. Grant RPC execute permissions
GRANT EXECUTE ON FUNCTION public.agent_get_diamond_wallet() TO authenticated;
GRANT EXECUTE ON FUNCTION public.agent_exchange_diamonds_to_coins(uuid, text) TO authenticated;

-- 8. Enable Realtime Publications
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.agency_wallets;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.agent_diamond_transactions;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.recharge_agency_exchange_tiers;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

-- 9. Zero out legacy recharge agent commission settings
UPDATE public.commission_settings
SET percentage = 0, value = 0
WHERE key IN ('recharge_agent_host_rate', 'recharge_agent_agency_rate');
