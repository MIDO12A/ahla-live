-- ============================================================
-- 1. room_blocks table – ban users from specific rooms
-- ============================================================
CREATE TABLE IF NOT EXISTS public.room_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id TEXT NOT NULL,
  blocker_uid TEXT NOT NULL,
  blocked_uid TEXT NOT NULL,
  reason TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_room_blocks_room ON public.room_blocks(room_id);
CREATE INDEX IF NOT EXISTS idx_room_blocks_blocked ON public.room_blocks(blocked_uid);

-- RLS
ALTER TABLE public.room_blocks ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to read room_blocks for rooms they are in
CREATE POLICY "room_blocks_select" ON public.room_blocks
  FOR SELECT
  USING (auth.uid()::text = blocker_uid OR auth.uid()::text = blocked_uid);

-- Allow authenticated users to insert (block someone)
CREATE POLICY "room_blocks_insert" ON public.room_blocks
  FOR INSERT
  WITH CHECK (auth.uid()::text = blocker_uid);

-- Allow blocker to delete (unblock)
CREATE POLICY "room_blocks_delete" ON public.room_blocks
  FOR DELETE
  USING (auth.uid()::text = blocker_uid);

-- ============================================================
-- 2. bug_reports table – for ErrorReportingService
-- ============================================================
CREATE TABLE IF NOT EXISTS public.bug_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  error TEXT NOT NULL,
  stack_trace TEXT,
  device_info TEXT,
  type TEXT DEFAULT 'Code / Logic',
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.bug_reports ENABLE ROW LEVEL SECURITY;

-- Allow any authenticated user to insert error reports
CREATE POLICY "bug_reports_insert" ON public.bug_reports
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- Only the report author (if we store uid) or admins can read; for now allow inserts only (no select).

-- ============================================================
-- 3. (Optional) RLS for private_messages – allow senders and
--    receivers to read/insert
-- ============================================================
-- If private_messages already has RLS, enable these:
-- ALTER TABLE public.private_messages ENABLE ROW LEVEL SECURITY;
--
-- CREATE POLICY "private_messages_insert" ON public.private_messages
--   FOR INSERT
--   WITH CHECK (auth.uid()::text = sender_uid);
--
-- CREATE POLICY "private_messages_select" ON public.private_messages
--   FOR SELECT
--   USING (auth.uid()::text = sender_uid OR auth.uid()::text = receiver_uid);

-- ============================================================
-- 4. (Optional) RLS for conversations table
-- ============================================================
-- CREATE POLICY "conversations_select" ON public.conversations
--   FOR SELECT
--   USING (auth.uid()::text = uid);
--
-- CREATE POLICY "conversations_insert" ON public.conversations
--   FOR INSERT
--   WITH CHECK (auth.uid()::text = uid);
--
-- CREATE POLICY "conversations_update" ON public.conversations
--   FOR UPDATE
--   USING (auth.uid()::text = uid);
