-- Migration: 20261006_follows_and_profile_visits.sql
-- Create follows and profile_visits tables for real user follower/following and profile visit tracking

CREATE TABLE IF NOT EXISTS public.follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_uid TEXT NOT NULL,
    following_uid TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_follower_following UNIQUE(follower_uid, following_uid)
);

CREATE INDEX IF NOT EXISTS idx_follows_follower_uid ON public.follows(follower_uid);
CREATE INDEX IF NOT EXISTS idx_follows_following_uid ON public.follows(following_uid);

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'follows' AND policyname = 'Allow select follows for all'
    ) THEN
        CREATE POLICY "Allow select follows for all" ON public.follows FOR SELECT USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'follows' AND policyname = 'Allow insert follows for all'
    ) THEN
        CREATE POLICY "Allow insert follows for all" ON public.follows FOR INSERT WITH CHECK (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'follows' AND policyname = 'Allow delete follows for all'
    ) THEN
        CREATE POLICY "Allow delete follows for all" ON public.follows FOR DELETE USING (true);
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.profile_visits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    visited_uid TEXT NOT NULL,
    visitor_uid TEXT NOT NULL,
    visited_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profile_visits_visited_uid ON public.profile_visits(visited_uid);
CREATE INDEX IF NOT EXISTS idx_profile_visits_visitor_uid ON public.profile_visits(visitor_uid);
CREATE INDEX IF NOT EXISTS idx_profile_visits_visited_at ON public.profile_visits(visited_at DESC);

ALTER TABLE public.profile_visits ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'profile_visits' AND policyname = 'Allow select profile_visits for all'
    ) THEN
        CREATE POLICY "Allow select profile_visits for all" ON public.profile_visits FOR SELECT USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'profile_visits' AND policyname = 'Allow insert profile_visits for all'
    ) THEN
        CREATE POLICY "Allow insert profile_visits for all" ON public.profile_visits FOR INSERT WITH CHECK (true);
    END IF;
END $$;
