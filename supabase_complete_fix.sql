-- ==============================================================================
-- SUPABASE COMPLETE MASTER REPAIR & MIGRATION SCRIPT
-- Project URL: https://pxyqgeitjdsilgfftnyd.supabase.co
-- SQL Editor: https://supabase.com/dashboard/project/pxyqgeitjdsilgfftnyd/sql/ecd9128d-cda7-4aa4-887c-143d75f4b60a
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. USERS & PROFILES COMPATIBILITY
CREATE TABLE IF NOT EXISTS public.users (
  uid TEXT PRIMARY KEY,
  custom_id TEXT UNIQUE,
  name TEXT DEFAULT '',
  email TEXT DEFAULT '',
  photo_url TEXT DEFAULT '',
  coins BIGINT DEFAULT 0,
  diamonds BIGINT DEFAULT 0,
  gender TEXT DEFAULT 'male',
  signature TEXT DEFAULT '',
  country TEXT DEFAULT 'EG',
  country_code TEXT DEFAULT 'eg',
  age INT DEFAULT 18,
  active_frame TEXT,
  active_headwear TEXT,
  active_bubble TEXT,
  active_entrance TEXT,
  active_car TEXT,
  active_cover TEXT,
  active_necklace TEXT,
  active_mic_wave TEXT,
  profile_bg_url TEXT,
  owned_items JSONB DEFAULT '[]',
  owned_badges JSONB DEFAULT '[]',
  owned_necklaces JSONB DEFAULT '[]',
  owned_level_frames JSONB DEFAULT '[]',
  owned_level_badges JSONB DEFAULT '[]',
  owned_vip_items JSONB DEFAULT '[]',
  album JSONB DEFAULT '[]',
  hosted_room_id TEXT,
  followed_rooms JSONB DEFAULT '[]',
  total_gifts_sent BIGINT DEFAULT 0,
  total_gifts_received BIGINT DEFAULT 0,
  level INT DEFAULT 1,
  experience BIGINT DEFAULT 0,
  followers INT DEFAULT 0,
  following INT DEFAULT 0,
  visitors INT DEFAULT 0,
  charm BIGINT DEFAULT 0,
  wealth_level INT DEFAULT 1,
  wealth_exp BIGINT DEFAULT 0,
  recharge_level INT DEFAULT 1,
  recharge_exp BIGINT DEFAULT 0,
  gems_level INT DEFAULT 1,
  gems_exp BIGINT DEFAULT 0,
  is_recharge_agent BOOLEAN DEFAULT false,
  recharge_agency_name TEXT,
  recharge_agency_logo TEXT,
  whatsapp_number TEXT,
  phone TEXT DEFAULT '',
  last_ip TEXT DEFAULT '',
  banned BOOLEAN DEFAULT false,
  ban_reason TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS id TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS avatar TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS agency_id TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_host_agent BOOLEAN DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS owned_level_necklaces JSONB DEFAULT '[]';

UPDATE public.users SET id = uid WHERE id IS NULL OR id = '';
UPDATE public.users SET avatar = photo_url WHERE avatar IS NULL OR avatar = '';

CREATE OR REPLACE FUNCTION public.sync_user_compatibility_fields()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.uid IS NOT NULL AND (NEW.id IS NULL OR NEW.id = '') THEN
    NEW.id := NEW.uid;
  ELSIF NEW.id IS NOT NULL AND (NEW.uid IS NULL OR NEW.uid = '') THEN
    NEW.uid := NEW.id;
  END IF;
  
  IF NEW.photo_url IS NOT NULL AND (NEW.avatar IS NULL OR NEW.avatar = '') THEN
    NEW.avatar := NEW.photo_url;
  ELSIF NEW.avatar IS NOT NULL AND (NEW.photo_url IS NULL OR NEW.photo_url = '') THEN
    NEW.photo_url := NEW.avatar;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_user_compat ON public.users;
CREATE TRIGGER trg_sync_user_compat
BEFORE INSERT OR UPDATE ON public.users
FOR EACH ROW EXECUTE FUNCTION public.sync_user_compatibility_fields();

-- 2. ADMIN & AUDIT
CREATE TABLE IF NOT EXISTS public.admin_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT NOT NULL UNIQUE,
  email TEXT,
  role TEXT DEFAULT 'admin',
  permissions JSONB DEFAULT '["all"]',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.dashboard_bans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT NOT NULL,
  reason TEXT DEFAULT '',
  banned_by TEXT DEFAULT 'admin',
  banned_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.admin_action_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_uid TEXT NOT NULL,
  action TEXT NOT NULL,
  target_id TEXT,
  details JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bds (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. CP SUBSYSTEM
CREATE TABLE IF NOT EXISTS public.cp_gifts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  value INT NOT NULL DEFAULT 1,
  icon_asset TEXT,
  animation_asset TEXT,
  sort_order INT DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.cp_cars (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  icon_asset TEXT,
  svga_asset TEXT,
  sort_order INT DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.cp_rank_rewards (
  id TEXT PRIMARY KEY,
  rank INT NOT NULL,
  title TEXT DEFAULT '',
  reward_coins BIGINT DEFAULT 0,
  reward_diamonds BIGINT DEFAULT 0,
  badge_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.cp_settings (
  key TEXT PRIMARY KEY,
  value JSONB,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. REWARDS, TASKS & UNIONS
CREATE TABLE IF NOT EXISTS public.signin_rewards (
  id TEXT PRIMARY KEY,
  day_number INT NOT NULL,
  reward_type TEXT DEFAULT 'coins',
  amount INT DEFAULT 0,
  icon_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.tasks_config (
  id TEXT PRIMARY KEY,
  title TEXT,
  description TEXT,
  type TEXT,
  target INT DEFAULT 1,
  reward_coins INT DEFAULT 0,
  reward_exp INT DEFAULT 0,
  icon_url TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.unions (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  tag TEXT,
  leader_uid TEXT REFERENCES public.users(uid) ON DELETE SET NULL,
  member_count INT DEFAULT 1,
  max_members INT DEFAULT 50,
  logo_url TEXT,
  announcement TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. GIFTS & CATEGORIES
CREATE TABLE IF NOT EXISTS public.gift_categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.gifts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  value INT NOT NULL DEFAULT 1,
  icon_asset TEXT,
  animation_asset TEXT,
  category_id TEXT,
  is_vap BOOLEAN DEFAULT false,
  is_lucky BOOLEAN DEFAULT false,
  is_star BOOLEAN DEFAULT false,
  is_music BOOLEAN DEFAULT false,
  package_count INT DEFAULT 1,
  sort_order INT DEFAULT 0,
  name_key TEXT,
  photo_key TEXT,
  default_image TEXT,
  wealth_xp INT DEFAULT 0,
  gems_xp INT DEFAULT 0
);

ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS is_cp_gift BOOLEAN DEFAULT false;
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS type INT DEFAULT 1;
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS receiver_name_key TEXT;
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS receiver_photo_key TEXT;
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS count_key TEXT;
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS cp_gift_duration_hours INT DEFAULT 0;
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS lucky_rtp INT DEFAULT 85;
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS lucky_max_multiplier INT DEFAULT 100;
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS lucky_burst BOOLEAN DEFAULT true;
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS lucky_display_mode TEXT DEFAULT 'cards';

-- 6. STORE ITEMS
CREATE TABLE IF NOT EXISTS public.store_items (
  item_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  icon_asset TEXT,
  price INT NOT NULL DEFAULT 0,
  svga_asset TEXT,
  animation_url TEXT,
  is_premium BOOLEAN DEFAULT false,
  name_key TEXT,
  photo_key TEXT,
  default_image TEXT
);

ALTER TABLE public.store_items ADD COLUMN IF NOT EXISTS custom_id TEXT;
ALTER TABLE public.store_items ADD COLUMN IF NOT EXISTS color_effect TEXT DEFAULT 'golden';
ALTER TABLE public.store_items ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT true;
ALTER TABLE public.store_items ADD COLUMN IF NOT EXISTS is_sold BOOLEAN DEFAULT false;

-- 7. APP CONFIG & ASSETS
CREATE TABLE IF NOT EXISTS public.app_config (
  key TEXT PRIMARY KEY,
  value JSONB
);

CREATE TABLE IF NOT EXISTS public.app_assets (
  key TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  type TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.app_assets ADD COLUMN IF NOT EXISTS id TEXT;
ALTER TABLE public.app_assets ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE public.app_assets ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE public.app_assets ADD COLUMN IF NOT EXISTS subcategory TEXT;
ALTER TABLE public.app_assets ADD COLUMN IF NOT EXISTS local_path TEXT;
ALTER TABLE public.app_assets ADD COLUMN IF NOT EXISTS remote_url TEXT;
ALTER TABLE public.app_assets ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

UPDATE public.app_assets SET remote_url = url WHERE remote_url IS NULL OR remote_url = '';
UPDATE public.app_assets SET url = remote_url WHERE url IS NULL OR url = '';

-- 8. RLS POLICIES FOR ALL TABLES (Allow Full Read & Write)
DO $$
DECLARE
  tbl text;
  all_tables text[] := ARRAY[
    'users', 'user_stats', 'profile_visits', 'user_backpack', 'user_wallets',
    'rooms', 'room_members', 'room_seats', 'room_messages', 'room_blocks',
    'gifts', 'gift_categories', 'sent_gifts', 'sent_lucky_gifts', 'lucky_bags', 'gift_banner_configs',
    'store_categories', 'store_items', 'gifted_items',
    'broadcasts', 'global_announcements',
    'conversations', 'private_messages', 'follows', 'reports', 'blocks',
    'agency_level_config', 'host_agencies', 'host_agency_members', 'host_agency_join_requests',
    'agency_wallets', 'agency_diamond_ledger', 'agency_chat_messages', 'agency_chat_mutes',
    'agency_withdrawal_requests', 'agency_free_agents', 'agency_transfers', 'agency_applications',
    'agency_achieved_targets', 'agency_milestones', 'agency_screenshot_reports',
    'host_milestones', 'host_salaries', 'host_usd_wallets',
    'agent_usd_wallets', 'agent_withdrawal_requests', 'agent_recharge_transactions',
    'recharge_event_progress', 'commission_settings',
    'level_config', 'vip_config', 'user_vips', 'badges', 'necklaces', 'ranking_frames',
    'banners', 'app_config', 'app_assets', 'notifications', 'bug_reports',
    'dashboard_bans', 'admin_users', 'admin_action_logs', 'bds',
    'signin_rewards', 'cp_gifts', 'cp_cars', 'cp_rank_rewards', 'cp_settings',
    'tasks_config', 'unions'
  ];
BEGIN
  FOREACH tbl IN ARRAY all_tables LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
      EXECUTE format('DROP POLICY IF EXISTS "%s_all" ON public.%I', tbl, tbl);
      EXECUTE format('CREATE POLICY "%s_all" ON public.%I FOR ALL USING (true) WITH CHECK (true)', tbl, tbl);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END $$;

-- 9. REALTIME PUBLICATION
DO $$
DECLARE
  tbl text;
  realtime_tables text[] := ARRAY[
    'users', 'user_stats', 'user_wallets',
    'rooms', 'room_members', 'room_seats', 'room_messages', 'room_blocks',
    'sent_gifts', 'sent_lucky_gifts', 'lucky_bags',
    'broadcasts', 'global_announcements',
    'conversations', 'private_messages',
    'host_agencies', 'host_agency_members', 'host_agency_join_requests',
    'agency_chat_messages', 'agency_wallets',
    'agent_usd_wallets', 'agent_recharge_transactions',
    'notifications', 'banners', 'app_config', 'store_items', 'gifts', 'app_assets',
    'dashboard_bans', 'admin_users', 'signin_rewards', 'cp_gifts', 'cp_settings'
  ];
BEGIN
  FOREACH tbl IN ARRAY realtime_tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables 
      WHERE pubname = 'supabase_realtime' AND tablename = tbl
    ) THEN
      BEGIN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', tbl);
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
  END LOOP;
END $$;

-- 10. DEFAULT SUPER ADMIN
INSERT INTO public.admin_users (uid, email, role, permissions)
VALUES 
  ('tOZ3rdICADU6CSxoRx3Trydfve23', 'm3290556@gmail.com', 'super_admin', '["all"]')
ON CONFLICT (uid) DO UPDATE SET role = 'super_admin', permissions = '["all"]';
