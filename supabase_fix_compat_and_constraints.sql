-- ==============================================================================
-- SUPABASE COMPATIBILITY & SCHEMA FIX MIGRATION
-- Fixes:
-- 1. room_messages: adds uid column & bi-directional sync with sender_uid
-- 2. room_blocks: adds user_id column & bi-directional sync with blocked_uid
-- 3. sent_gifts: adds uid column & bi-directional sync with sender_id
-- 4. user_wallets: adds uid column & bi-directional sync with user_id
-- 5. notifications: adds uid, type, data columns
-- 6. room_messages_room_id_fkey: drops foreign key constraint so messages never fail
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

-- 6. PERMISSIONS & REALTIME
GRANT ALL ON TABLE public.room_messages TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.room_blocks TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.sent_gifts TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.user_wallets TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.notifications TO anon, authenticated, service_role;

-- Success confirmation
SELECT 'Schema compatibility fixes applied successfully!' AS status;
