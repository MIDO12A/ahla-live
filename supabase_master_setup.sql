-- ==============================================================================
-- 🚀 SUPABASE MASTER SCHEMA & RULES SETUP (100% IDENTICAL TO FIREBASE)
-- Project ID: pxyqgeitjdsilgfftnyd
-- Dashboard: https://supabase.com/dashboard/project/pxyqgeitjdsilgfftnyd/sql
-- ==============================================================================
-- هذا السكربت يطابق 100% بنية بيانات Firebase بالكامل بكافة المجموعات والحقول
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. USERS & PROFILES
-- ============================================================
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

CREATE OR REPLACE VIEW public.profiles AS
SELECT 
  uid as id,
  uid,
  name as display_name,
  name,
  email,
  photo_url as avatar_url,
  photo_url,
  custom_id,
  coins,
  diamonds,
  gender,
  signature,
  country,
  country_code,
  level,
  banned,
  created_at
FROM public.users;

-- ============================================================
-- 2. USER STATS, VISITS, BACKPACK & WALLETS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_stats (
  user_id TEXT PRIMARY KEY REFERENCES public.users(uid) ON DELETE CASCADE,
  visitors INT DEFAULT 0,
  profile_likes INT DEFAULT 0,
  moments_count INT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.profile_visits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visitor_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  visited_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  visited_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_backpack (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  item_id TEXT NOT NULL,
  category TEXT NOT NULL,
  name TEXT,
  icon_url TEXT,
  svga_url TEXT,
  count INT DEFAULT 1,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_wallets (
  user_id TEXT PRIMARY KEY REFERENCES public.users(uid) ON DELETE CASCADE,
  gold_balance BIGINT DEFAULT 0,
  diamond_balance BIGINT DEFAULT 0,
  frozen_gold BIGINT DEFAULT 0,
  frozen_diamonds BIGINT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 3. ROOMS & LIVE AUDIO STREAMING
-- ============================================================
CREATE TABLE IF NOT EXISTS public.rooms (
  room_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  room_photo_url TEXT DEFAULT '',
  host_uid TEXT REFERENCES public.users(uid) ON DELETE SET NULL,
  host_name TEXT DEFAULT '',
  host_photo_url TEXT DEFAULT '',
  member_count INT DEFAULT 0,
  max_members INT DEFAULT 50,
  is_locked BOOLEAN DEFAULT false,
  category TEXT DEFAULT 'عام',
  country TEXT DEFAULT 'EG',
  password TEXT DEFAULT '',
  seat_count INT DEFAULT 8,
  seat_style TEXT DEFAULT 'default',
  seat_color TEXT DEFAULT '#DE880F',
  total_gifts BIGINT DEFAULT 0,
  hot_value BIGINT DEFAULT 0,
  bg_image TEXT DEFAULT '',
  announcement TEXT DEFAULT '',
  is_chat_locked BOOLEAN DEFAULT false,
  chat_cleared_at BIGINT DEFAULT 0,
  moderators TEXT[] DEFAULT '{}',
  rocket_energy INT DEFAULT 0,
  rocket_target INT DEFAULT 5000,
  rocket_burst_active BOOLEAN DEFAULT false,
  rocket_burst_id TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.room_members (
  room_id TEXT REFERENCES public.rooms(room_id) ON DELETE CASCADE,
  uid TEXT REFERENCES public.users(uid) ON DELETE CASCADE,
  name TEXT,
  photo_url TEXT,
  role TEXT DEFAULT 'member',
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (room_id, uid)
);

CREATE TABLE IF NOT EXISTS public.room_seats (
  room_id TEXT REFERENCES public.rooms(room_id) ON DELETE CASCADE,
  seat_index INT NOT NULL,
  uid TEXT REFERENCES public.users(uid) ON DELETE SET NULL,
  name TEXT,
  photo_url TEXT,
  active_frame TEXT,
  active_car TEXT,
  is_muted BOOLEAN DEFAULT false,
  is_locked BOOLEAN DEFAULT false,
  taken_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (room_id, seat_index)
);

CREATE TABLE IF NOT EXISTS public.room_messages (
  msg_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id TEXT REFERENCES public.rooms(room_id) ON DELETE CASCADE,
  sender_uid TEXT,
  sender_name TEXT DEFAULT 'مستخدم',
  sender_photo_url TEXT DEFAULT '',
  text TEXT DEFAULT '',
  type TEXT DEFAULT 'text',
  image_url TEXT DEFAULT '',
  active_bubble TEXT,
  gift_payload JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.room_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id TEXT NOT NULL REFERENCES public.rooms(room_id) ON DELETE CASCADE,
  blocker_uid TEXT NOT NULL,
  blocked_uid TEXT NOT NULL,
  reason TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 4. GIFTS, LUCKY GIFTS & LUCKY BAGS
-- ============================================================
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
  category_id TEXT REFERENCES public.gift_categories(id),
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

CREATE TABLE IF NOT EXISTS public.sent_gifts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id TEXT REFERENCES public.rooms(room_id) ON DELETE CASCADE,
  gift_id TEXT REFERENCES public.gifts(id),
  gift_name TEXT,
  animation_asset TEXT,
  sender_id TEXT REFERENCES public.users(uid) ON DELETE SET NULL,
  sender_name TEXT,
  sender_photo_url TEXT,
  receiver_id TEXT REFERENCES public.users(uid) ON DELETE SET NULL,
  receiver_name TEXT,
  value INT NOT NULL,
  count INT DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sent_lucky_gifts (
  id TEXT PRIMARY KEY,
  gift_id TEXT NOT NULL,
  gift_name TEXT,
  gift_name_ar TEXT,
  gift_icon_url TEXT,
  sender_id TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  sender_name TEXT,
  sender_photo_url TEXT,
  receiver_id TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  receiver_name TEXT,
  room_id TEXT NOT NULL REFERENCES public.rooms(room_id) ON DELETE CASCADE,
  value INT NOT NULL,
  count INT DEFAULT 1,
  combo_id TEXT,
  combo_count INT DEFAULT 1,
  won_coins BIGINT DEFAULT 0,
  multipliers JSONB DEFAULT '[]',
  is_big_win BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.lucky_bags (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES public.rooms(room_id) ON DELETE CASCADE,
  sender_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  sender_name TEXT,
  sender_photo TEXT,
  total_value BIGINT NOT NULL,
  remaining_value BIGINT NOT NULL,
  total_count INT NOT NULL,
  remaining_count INT NOT NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'claimed', 'expired')),
  claims JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.gift_banner_configs (
  id TEXT PRIMARY KEY,
  category_id TEXT REFERENCES public.gift_categories(id),
  threshold_coins INT DEFAULT 5000,
  svga_url TEXT NOT NULL,
  user_r_key TEXT DEFAULT 'user_r',
  user_l_key TEXT DEFAULT 'user_l',
  number_key TEXT DEFAULT 'number',
  gift_key TEXT DEFAULT 'gift',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 5. STORE, CATEGORIES & GIFTED ITEMS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.store_categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

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

CREATE TABLE IF NOT EXISTS public.gifted_items (
  id TEXT PRIMARY KEY,
  uid TEXT REFERENCES public.users(uid) ON DELETE CASCADE,
  item_id TEXT,
  item_category TEXT,
  item_name TEXT,
  item_icon TEXT,
  svga_asset TEXT,
  sent_by TEXT,
  sent_by_name TEXT,
  sent_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ
);

-- ============================================================
-- 6. BROADCASTS & GLOBAL ANNOUNCEMENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.broadcasts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_uid TEXT NOT NULL,
  sender_name TEXT,
  sender_photo_url TEXT,
  room_id TEXT NOT NULL,
  room_name TEXT,
  content TEXT,
  gift_icon TEXT,
  multiplier INT,
  type TEXT DEFAULT 'lucky_gift',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.global_announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL,
  sender_name TEXT,
  gift_name TEXT,
  room_id TEXT,
  multiplier INT,
  total_won BIGINT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 7. SOCIAL, CHAT & CONVERSATIONS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.conversations (
  conv_id TEXT PRIMARY KEY,
  uid TEXT REFERENCES public.users(uid) ON DELETE CASCADE,
  other_uid TEXT REFERENCES public.users(uid) ON DELETE CASCADE,
  other_name TEXT DEFAULT '',
  other_photo_url TEXT DEFAULT '',
  last_message TEXT DEFAULT '',
  last_time TIMESTAMPTZ DEFAULT NOW(),
  unread_count INT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.private_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conv_id TEXT NOT NULL REFERENCES public.conversations(conv_id) ON DELETE CASCADE,
  sender_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  receiver_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  message_type TEXT DEFAULT 'text',
  text TEXT DEFAULT '',
  media_url TEXT DEFAULT '',
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.follows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  following_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(follower_uid, following_uid)
);

CREATE TABLE IF NOT EXISTS public.reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  reported_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'pending',
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  blocked_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(blocker_uid, blocked_uid)
);

-- ============================================================
-- 8. COMPLETE HOST AGENCY SUBSYSTEM (EXACT FIREBASE MATCH)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.agency_level_config (
  level INT PRIMARY KEY,
  level_name TEXT NOT NULL,
  min_exp BIGINT NOT NULL,
  admin_limit INT NOT NULL DEFAULT 2,
  members_limit INT NOT NULL DEFAULT 20,
  maintain_exp_percentage NUMERIC(5,2) NOT NULL DEFAULT 30.00,
  badge_icon_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO public.agency_level_config (level, level_name, min_exp, admin_limit, members_limit, maintain_exp_percentage)
VALUES 
  (1, 'برونز', 0, 2, 20, 30.00),
  (2, 'فضي', 50000, 3, 50, 30.00),
  (3, 'ذهبي', 200000, 5, 100, 30.00),
  (4, 'بلاتيني', 800000, 8, 200, 30.00),
  (5, 'ألماسي', 2500000, 12, 500, 30.00)
ON CONFLICT (level) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.host_agencies (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  agency_code BIGINT UNIQUE,
  owner_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  description TEXT DEFAULT '',
  logo_url TEXT DEFAULT '',
  background_url TEXT DEFAULT '',
  announcement TEXT DEFAULT '',
  level INT NOT NULL DEFAULT 1 REFERENCES public.agency_level_config(level),
  monthly_exp BIGINT NOT NULL DEFAULT 0,
  total_exp BIGINT NOT NULL DEFAULT 0,
  total_diamonds_monthly BIGINT DEFAULT 0,
  total_diamonds_cumulative BIGINT DEFAULT 0,
  member_count INT NOT NULL DEFAULT 1,
  admin_count INT NOT NULL DEFAULT 0,
  status TEXT DEFAULT 'active',
  is_active BOOLEAN NOT NULL DEFAULT true,
  data JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.host_agency_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id TEXT NOT NULL REFERENCES public.host_agencies(id) ON DELETE CASCADE,
  host_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  role TEXT DEFAULT 'host',
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'pending_exit', 'suspended', 'terminated')),
  diamonds BIGINT DEFAULT 0,
  diamonds_balance BIGINT DEFAULT 0,
  diamonds_available BIGINT DEFAULT 0,
  diamonds_earned_monthly BIGINT DEFAULT 0,
  diamonds_earned_cumulative BIGINT DEFAULT 0,
  daily_target BIGINT DEFAULT 0,
  monthly_target BIGINT DEFAULT 0,
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.host_agency_join_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id TEXT NOT NULL REFERENCES public.host_agencies(id) ON DELETE CASCADE,
  host_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  rejection_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '3 days')
);

CREATE TABLE IF NOT EXISTS public.agency_wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_profile_id TEXT NOT NULL,
  gold_balance BIGINT DEFAULT 0,
  diamond_balance BIGINT DEFAULT 0,
  total_earnings BIGINT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.agency_diamond_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id TEXT NOT NULL REFERENCES public.host_agencies(id) ON DELETE CASCADE,
  user_id TEXT REFERENCES public.users(uid) ON DELETE SET NULL,
  sender_id TEXT,
  sender_name TEXT,
  gift_id TEXT,
  gift_name TEXT,
  amount BIGINT NOT NULL,
  direction INT DEFAULT 1,
  txn_type TEXT DEFAULT 'gift',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.agency_chat_messages (
  id BIGINT PRIMARY KEY,
  agency_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  display_name TEXT DEFAULT 'مستخدم',
  message_type TEXT DEFAULT 'text',
  body TEXT,
  asset_url TEXT,
  asset_duration_secs INT,
  view_duration_seconds INT,
  is_view_once BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.agency_chat_mutes (
  agency_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  muted_until TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (agency_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.agency_withdrawal_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id TEXT NOT NULL,
  amount BIGINT NOT NULL,
  status TEXT DEFAULT 'pending',
  payment_method TEXT,
  details JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.agency_free_agents (
  user_id TEXT PRIMARY KEY REFERENCES public.users(uid) ON DELETE CASCADE,
  status TEXT DEFAULT 'free',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.agency_transfers (
  id TEXT PRIMARY KEY,
  agency_id TEXT NOT NULL,
  from_uid TEXT NOT NULL,
  to_uid TEXT NOT NULL,
  diamonds BIGINT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.agency_applications (
  id TEXT PRIMARY KEY,
  applicant_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  agency_name TEXT NOT NULL,
  description TEXT,
  whatsapp TEXT,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.agency_achieved_targets (
  id TEXT PRIMARY KEY,
  agency_id TEXT NOT NULL,
  target_diamonds BIGINT NOT NULL,
  reward_amount NUMERIC(10,2) NOT NULL,
  month TEXT NOT NULL,
  achieved_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.agency_milestones (
  id TEXT PRIMARY KEY,
  agency_id TEXT NOT NULL,
  milestone_type TEXT,
  diamonds_target BIGINT,
  reward_usd NUMERIC(10,2),
  achieved BOOLEAN DEFAULT false,
  achieved_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.agency_screenshot_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id TEXT NOT NULL,
  reporter_uid TEXT NOT NULL,
  screenshot_url TEXT NOT NULL,
  reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.host_milestones (
  id TEXT PRIMARY KEY,
  host_uid TEXT NOT NULL,
  milestone_type TEXT,
  diamonds_target BIGINT,
  reward_usd NUMERIC(10,2),
  achieved BOOLEAN DEFAULT false,
  achieved_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.host_salaries (
  id TEXT PRIMARY KEY,
  host_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  agency_id TEXT NOT NULL,
  month TEXT NOT NULL,
  total_diamonds BIGINT DEFAULT 0,
  base_salary_usd NUMERIC(10,2) DEFAULT 0.00,
  bonus_usd NUMERIC(10,2) DEFAULT 0.00,
  total_salary_usd NUMERIC(10,2) DEFAULT 0.00,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.host_usd_wallets (
  host_uid TEXT PRIMARY KEY REFERENCES public.users(uid) ON DELETE CASCADE,
  balance_usd NUMERIC(10,2) DEFAULT 0.00,
  frozen_usd NUMERIC(10,2) DEFAULT 0.00,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 9. RECHARGE AGENTS & USD WALLETS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.agent_usd_wallets (
  agent_id TEXT PRIMARY KEY REFERENCES public.users(uid) ON DELETE CASCADE,
  balance_usd NUMERIC(12,2) DEFAULT 0.00,
  frozen_usd NUMERIC(12,2) DEFAULT 0.00,
  total_recharged_usd NUMERIC(12,2) DEFAULT 0.00,
  pin_hash TEXT,
  quick_amounts JSONB DEFAULT '[10, 50, 100, 500]',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.agent_withdrawal_requests (
  id TEXT PRIMARY KEY,
  agent_id TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  agent_name TEXT,
  amount_usd NUMERIC(12,2) NOT NULL,
  payment_method TEXT,
  account_details JSONB DEFAULT '{}',
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by TEXT
);

CREATE TABLE IF NOT EXISTS public.agent_recharge_transactions (
  id TEXT PRIMARY KEY,
  agent_id TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  target_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  target_custom_id TEXT,
  amount_coins BIGINT NOT NULL,
  amount_usd NUMERIC(12,2) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.recharge_event_progress (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
  event_id TEXT NOT NULL,
  coins_recharged BIGINT DEFAULT 0,
  claimed_tiers JSONB DEFAULT '[]',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.commission_settings (
  key TEXT PRIMARY KEY,
  percentage NUMERIC(5,2) DEFAULT 10.00,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 10. CONFIG, VIP, LEVELS & SYSTEM
-- ============================================================
CREATE TABLE IF NOT EXISTS public.level_config (
  type TEXT,
  level INT,
  min_exp BIGINT,
  max_exp BIGINT,
  title TEXT,
  image_url TEXT,
  frame_url TEXT,
  badge_url TEXT,
  rewards JSONB DEFAULT '{}',
  progress_color TEXT DEFAULT '#DE880F',
  box_image_url TEXT,
  PRIMARY KEY (type, level)
);

CREATE TABLE IF NOT EXISTS public.vip_config (
  tier INT PRIMARY KEY,
  name TEXT,
  min_spend BIGINT,
  price BIGINT,
  color TEXT,
  image_url TEXT,
  bg_url TEXT,
  logo_url TEXT,
  medal_url TEXT,
  medal_img_url TEXT,
  medal_name TEXT,
  headwear_url TEXT,
  headwear_img_url TEXT,
  headwear_name TEXT,
  bubble_url TEXT,
  bubble_img_url TEXT,
  bubble_name TEXT,
  car_url TEXT,
  car_img_url TEXT,
  car_name TEXT,
  ring_url TEXT,
  ring_img_url TEXT,
  ring_name TEXT
);

CREATE TABLE IF NOT EXISTS public.user_vips (
  uid TEXT PRIMARY KEY REFERENCES public.users(uid) ON DELETE CASCADE,
  tier INT REFERENCES public.vip_config(tier),
  purchased_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  auto_renew BOOLEAN DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.badges (
  id TEXT PRIMARY KEY,
  name TEXT,
  icon_url TEXT,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.necklaces (
  id TEXT PRIMARY KEY,
  name TEXT,
  icon_url TEXT,
  description TEXT,
  type TEXT DEFAULT 'admin',
  required_recharge_level INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ranking_frames (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category TEXT NOT NULL,
  rank INT NOT NULL CHECK (rank >= 1 AND rank <= 3),
  asset_url TEXT NOT NULL,
  asset_type TEXT NOT NULL DEFAULT 'webp',
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(category, rank)
);

CREATE TABLE IF NOT EXISTS public.banners (
  id TEXT PRIMARY KEY,
  image_url TEXT,
  link_url TEXT,
  title TEXT,
  sort_order INT DEFAULT 0,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

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

CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  target TEXT DEFAULT 'all',
  sent_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID
);

CREATE TABLE IF NOT EXISTS public.bug_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  error TEXT NOT NULL,
  stack_trace TEXT,
  device_info TEXT,
  type TEXT DEFAULT 'Code / Logic',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 11. STORAGE BUCKETS
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES 
  ('avatars', 'avatars', true),
  ('covers', 'covers', true),
  ('room_photos', 'room_photos', true),
  ('gift_assets', 'gift_assets', true),
  ('store_assets', 'store_assets', true),
  ('banners', 'banners', true),
  ('audio', 'audio', true),
  ('verifications', 'verifications', false)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Public Storage Access" ON storage.objects;
  CREATE POLICY "Public Storage Access" ON storage.objects FOR SELECT 
    USING (bucket_id IN ('avatars', 'covers', 'room_photos', 'gift_assets', 'store_assets', 'banners', 'audio'));

  DROP POLICY IF EXISTS "Authenticated Storage Upload" ON storage.objects;
  CREATE POLICY "Authenticated Storage Upload" ON storage.objects FOR INSERT 
    WITH CHECK (auth.role() = 'authenticated' OR auth.role() = 'anon');

  DROP POLICY IF EXISTS "Authenticated Storage Update" ON storage.objects;
  CREATE POLICY "Authenticated Storage Update" ON storage.objects FOR UPDATE 
    USING (auth.role() = 'authenticated' OR auth.role() = 'anon');
END $$;

-- ============================================================
-- 12. ROW LEVEL SECURITY (RLS) FOR ALL TABLES
-- ============================================================
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
    'banners', 'app_config', 'app_assets', 'notifications', 'bug_reports'
  ];
BEGIN
  FOREACH tbl IN ARRAY all_tables LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
      EXECUTE format('DROP POLICY IF EXISTS "%s_select" ON public.%I', tbl, tbl);
      EXECUTE format('CREATE POLICY "%s_select" ON public.%I FOR SELECT USING (true)', tbl, tbl);
      EXECUTE format('DROP POLICY IF EXISTS "%s_manage" ON public.%I', tbl, tbl);
      EXECUTE format('CREATE POLICY "%s_manage" ON public.%I FOR ALL USING (true) WITH CHECK (true)', tbl, tbl);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END $$;

-- ============================================================
-- 13. REALTIME PUBLICATIONS
-- ============================================================
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
    'notifications', 'banners', 'app_config'
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

-- ============================================================
-- 14. AUTH HOOK TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (uid, name, email, photo_url, coins, diamonds, custom_id)
  VALUES (
    NEW.id::text,
    COALESCE(
      NEW.raw_user_meta_data->>'name',
      SPLIT_PART(NEW.email, '@', 1),
      'User'
    ),
    COALESCE(NEW.email, ''),
    COALESCE(
      NEW.raw_user_meta_data->>'avatar_url',
      NEW.raw_user_meta_data->>'photoUrl',
      ''
    ),
    0,
    0,
    SUBSTRING(REPLACE(NEW.id::text, '-', ''), 1, 8)
  )
  ON CONFLICT (uid) DO NOTHING;

  INSERT INTO public.user_wallets (user_id, gold_balance, diamond_balance)
  VALUES (NEW.id::text, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_stats (user_id, visitors)
  VALUES (NEW.id::text, 0)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();
