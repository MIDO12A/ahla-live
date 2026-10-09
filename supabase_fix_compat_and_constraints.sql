-- ==============================================================================
-- SUPABASE COMPATIBILITY & SCHEMA FIX MIGRATION (COMPLETE & ROBUST)
-- Fixes:
-- 1. room_messages: adds uid column & bi-directional sync with sender_uid
-- 2. room_blocks: adds user_id column & bi-directional sync with blocked_uid
-- 3. sent_gifts: adds uid column & bi-directional sync with sender_id
-- 4. user_wallets: adds uid column & bi-directional sync with user_id
-- 5. notifications: adds uid, type, data columns
-- 6. room_messages_room_id_fkey: drops foreign key constraint so messages never fail
-- 7. host_agency_members: adds user_id & host_uid bi-directional sync & status triggers
-- 8. host_agency_join_requests: adds user_id, host_uid, applicant_uid sync
-- 9. host_agencies: adds owner_id, owner_uid, monthly_diamonds sync
-- 10. users: adds id column synced with uid for compatibility
-- ==============================================================================

-- 1. FIX: room_messages
ALTER TABLE IF EXISTS public.room_messages DROP CONSTRAINT IF EXISTS room_messages_room_id_fkey;
ALTER TABLE IF EXISTS public.room_messages ADD COLUMN IF NOT EXISTS uid TEXT;
UPDATE public.room_messages SET uid = sender_uid WHERE uid IS NULL AND sender_uid IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_room_messages_uid()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.uid IS NULL AND NEW.sender_uid IS NOT NULL THEN
    NEW.uid := NEW.sender_uid;
  ELSIF NEW.sender_uid IS NULL AND NEW.uid IS NOT NULL THEN
    NEW.sender_uid := NEW.uid;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_room_messages_uid ON public.room_messages;
CREATE TRIGGER trg_sync_room_messages_uid
BEFORE INSERT OR UPDATE ON public.room_messages
FOR EACH ROW EXECUTE FUNCTION public.sync_room_messages_uid();


-- 2. FIX: room_blocks
ALTER TABLE IF EXISTS public.room_blocks ADD COLUMN IF NOT EXISTS user_id TEXT;
UPDATE public.room_blocks SET user_id = blocked_uid WHERE user_id IS NULL AND blocked_uid IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_room_blocks_user_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.user_id IS NULL AND NEW.blocked_uid IS NOT NULL THEN
    NEW.user_id := NEW.blocked_uid;
  ELSIF NEW.blocked_uid IS NULL AND NEW.user_id IS NOT NULL THEN
    NEW.blocked_uid := NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_room_blocks_user_id ON public.room_blocks;
CREATE TRIGGER trg_sync_room_blocks_user_id
BEFORE INSERT OR UPDATE ON public.room_blocks
FOR EACH ROW EXECUTE FUNCTION public.sync_room_blocks_user_id();


-- 3. FIX: sent_gifts
ALTER TABLE IF EXISTS public.sent_gifts ADD COLUMN IF NOT EXISTS uid TEXT;
UPDATE public.sent_gifts SET uid = sender_id WHERE uid IS NULL AND sender_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_sent_gifts_uid()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.uid IS NULL AND NEW.sender_id IS NOT NULL THEN
    NEW.uid := NEW.sender_id;
  ELSIF NEW.sender_id IS NULL AND NEW.uid IS NOT NULL THEN
    NEW.sender_id := NEW.uid;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_sent_gifts_uid ON public.sent_gifts;
CREATE TRIGGER trg_sync_sent_gifts_uid
BEFORE INSERT OR UPDATE ON public.sent_gifts
FOR EACH ROW EXECUTE FUNCTION public.sync_sent_gifts_uid();


-- 4. FIX: user_wallets
ALTER TABLE IF EXISTS public.user_wallets ADD COLUMN IF NOT EXISTS uid TEXT;
UPDATE public.user_wallets SET uid = user_id WHERE uid IS NULL AND user_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_user_wallets_uid()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.uid IS NULL AND NEW.user_id IS NOT NULL THEN
    NEW.uid := NEW.user_id;
  ELSIF NEW.user_id IS NULL AND NEW.uid IS NOT NULL THEN
    NEW.user_id := NEW.uid;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_user_wallets_uid ON public.user_wallets;
CREATE TRIGGER trg_sync_user_wallets_uid
BEFORE INSERT OR UPDATE ON public.user_wallets
FOR EACH ROW EXECUTE FUNCTION public.sync_user_wallets_uid();


-- 5. FIX: notifications
ALTER TABLE IF EXISTS public.notifications ADD COLUMN IF NOT EXISTS uid TEXT;
ALTER TABLE IF EXISTS public.notifications ADD COLUMN IF NOT EXISTS type TEXT DEFAULT 'system';
ALTER TABLE IF EXISTS public.notifications ADD COLUMN IF NOT EXISTS data JSONB DEFAULT '{}';


-- 6. FIX: host_agency_members (user_id and host_uid sync)
ALTER TABLE IF EXISTS public.host_agency_members ADD COLUMN IF NOT EXISTS user_id TEXT;
ALTER TABLE IF EXISTS public.host_agency_members ADD COLUMN IF NOT EXISTS host_uid TEXT;
ALTER TABLE IF EXISTS public.host_agency_members ADD COLUMN IF NOT EXISTS joined_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE IF EXISTS public.host_agency_members ADD COLUMN IF NOT EXISTS kicked_at TIMESTAMPTZ;

UPDATE public.host_agency_members SET user_id = host_uid WHERE user_id IS NULL AND host_uid IS NOT NULL;
UPDATE public.host_agency_members SET host_uid = user_id WHERE host_uid IS NULL AND user_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_host_agency_members_uids()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.user_id IS NULL AND NEW.host_uid IS NOT NULL THEN
    NEW.user_id := NEW.host_uid;
  ELSIF NEW.host_uid IS NULL AND NEW.user_id IS NOT NULL THEN
    NEW.host_uid := NEW.user_id;
  END IF;
  IF NEW.joined_at IS NULL THEN
    NEW.joined_at := NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_host_agency_members_uids ON public.host_agency_members;
CREATE TRIGGER trg_sync_host_agency_members_uids
BEFORE INSERT OR UPDATE ON public.host_agency_members
FOR EACH ROW EXECUTE FUNCTION public.sync_host_agency_members_uids();


-- 7. FIX: host_agency_join_requests (user_id, host_uid, applicant_uid sync)
ALTER TABLE IF EXISTS public.host_agency_join_requests ADD COLUMN IF NOT EXISTS user_id TEXT;
ALTER TABLE IF EXISTS public.host_agency_join_requests ADD COLUMN IF NOT EXISTS host_uid TEXT;
ALTER TABLE IF EXISTS public.host_agency_join_requests ADD COLUMN IF NOT EXISTS applicant_uid TEXT;
ALTER TABLE IF EXISTS public.host_agency_join_requests ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

UPDATE public.host_agency_join_requests SET user_id = host_uid WHERE user_id IS NULL AND host_uid IS NOT NULL;
UPDATE public.host_agency_join_requests SET host_uid = user_id WHERE host_uid IS NULL AND user_id IS NOT NULL;
UPDATE public.host_agency_join_requests SET applicant_uid = COALESCE(user_id, host_uid) WHERE applicant_uid IS NULL;

CREATE OR REPLACE FUNCTION public.sync_host_agency_join_requests_uids()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.user_id IS NULL AND NEW.host_uid IS NOT NULL THEN
    NEW.user_id := NEW.host_uid;
  ELSIF NEW.host_uid IS NULL AND NEW.user_id IS NOT NULL THEN
    NEW.host_uid := NEW.user_id;
  END IF;
  IF NEW.applicant_uid IS NULL THEN
    NEW.applicant_uid := COALESCE(NEW.user_id, NEW.host_uid);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_host_agency_join_requests_uids ON public.host_agency_join_requests;
CREATE TRIGGER trg_sync_host_agency_join_requests_uids
BEFORE INSERT OR UPDATE ON public.host_agency_join_requests
FOR EACH ROW EXECUTE FUNCTION public.sync_host_agency_join_requests_uids();


-- 8. FIX: host_agencies (owner_id, owner_uid, monthly_diamonds sync)
ALTER TABLE IF EXISTS public.host_agencies ADD COLUMN IF NOT EXISTS owner_id TEXT;
ALTER TABLE IF EXISTS public.host_agencies ADD COLUMN IF NOT EXISTS owner_uid TEXT;
ALTER TABLE IF EXISTS public.host_agencies ADD COLUMN IF NOT EXISTS monthly_diamonds BIGINT DEFAULT 0;
ALTER TABLE IF EXISTS public.host_agencies ADD COLUMN IF NOT EXISTS total_diamonds_monthly BIGINT DEFAULT 0;

UPDATE public.host_agencies SET owner_id = owner_uid WHERE owner_id IS NULL AND owner_uid IS NOT NULL;
UPDATE public.host_agencies SET owner_uid = owner_id WHERE owner_uid IS NULL AND owner_id IS NOT NULL;
UPDATE public.host_agencies SET monthly_diamonds = total_diamonds_monthly WHERE monthly_diamonds = 0 AND total_diamonds_monthly > 0;
UPDATE public.host_agencies SET total_diamonds_monthly = monthly_diamonds WHERE total_diamonds_monthly = 0 AND monthly_diamonds > 0;

CREATE OR REPLACE FUNCTION public.sync_host_agencies_owners()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.owner_id IS NULL AND NEW.owner_uid IS NOT NULL THEN
    NEW.owner_id := NEW.owner_uid;
  ELSIF NEW.owner_uid IS NULL AND NEW.owner_id IS NOT NULL THEN
    NEW.owner_uid := NEW.owner_id;
  END IF;
  IF NEW.monthly_diamonds IS NULL AND NEW.total_diamonds_monthly IS NOT NULL THEN
    NEW.monthly_diamonds := NEW.total_diamonds_monthly;
  ELSIF NEW.total_diamonds_monthly IS NULL AND NEW.monthly_diamonds IS NOT NULL THEN
    NEW.total_diamonds_monthly := NEW.monthly_diamonds;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_host_agencies_owners ON public.host_agencies;
CREATE TRIGGER trg_sync_host_agencies_owners
BEFORE INSERT OR UPDATE ON public.host_agencies
FOR EACH ROW EXECUTE FUNCTION public.sync_host_agencies_owners();


-- 9. FIX: users (id column synced with uid for query compatibility)
ALTER TABLE IF EXISTS public.users ADD COLUMN IF NOT EXISTS id TEXT;
UPDATE public.users SET id = uid WHERE id IS NULL;

CREATE OR REPLACE FUNCTION public.sync_users_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.id IS NULL AND NEW.uid IS NOT NULL THEN
    NEW.id := NEW.uid;
  ELSIF NEW.uid IS NULL AND NEW.id IS NOT NULL THEN
    NEW.uid := NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_users_id ON public.users;
CREATE TRIGGER trg_sync_users_id
BEFORE INSERT OR UPDATE ON public.users
FOR EACH ROW EXECUTE FUNCTION public.sync_users_id();


-- 10. PERMISSIONS & REALTIME
GRANT ALL ON TABLE public.room_messages TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.room_blocks TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.sent_gifts TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.user_wallets TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.notifications TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.host_agency_members TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.host_agency_join_requests TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.host_agencies TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.users TO anon, authenticated, service_role;

SELECT 'All compatibility triggers and schema fixes successfully applied!' AS status;
