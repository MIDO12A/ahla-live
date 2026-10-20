-- =========================================================================
-- MIGRATION: Create, Harmonize and Seed public.commission_settings Table
-- Fix: Alters columns to NUMERIC(20, 4) to prevent precision 5, scale 2 overflow
-- =========================================================================

-- 1. Create the commission_settings table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.commission_settings (
    id UUID DEFAULT gen_random_uuid(),
    key TEXT NOT NULL,
    value NUMERIC(20, 4) NOT NULL DEFAULT 0,
    percentage NUMERIC(20, 4) NOT NULL DEFAULT 0,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by TEXT DEFAULT NULL
);

-- 2. Alter existing columns or add missing columns (Fixes numeric field overflow: NUMERIC(5, 2) -> NUMERIC(20, 4))
DO $$
BEGIN
    -- percentage column: alter to NUMERIC(20, 4) if exists, add if not
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'commission_settings' AND column_name = 'percentage'
    ) THEN
        ALTER TABLE public.commission_settings ALTER COLUMN percentage TYPE NUMERIC(20, 4);
    ELSE
        ALTER TABLE public.commission_settings ADD COLUMN percentage NUMERIC(20, 4) NOT NULL DEFAULT 0;
    END IF;

    -- value column: alter to NUMERIC(20, 4) if exists, add if not
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'commission_settings' AND column_name = 'value'
    ) THEN
        ALTER TABLE public.commission_settings ALTER COLUMN value TYPE NUMERIC(20, 4);
    ELSE
        ALTER TABLE public.commission_settings ADD COLUMN value NUMERIC(20, 4) NOT NULL DEFAULT 0;
    END IF;

    -- id column
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'commission_settings' AND column_name = 'id'
    ) THEN
        ALTER TABLE public.commission_settings ADD COLUMN id UUID DEFAULT gen_random_uuid();
    END IF;

    -- description column
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'commission_settings' AND column_name = 'description'
    ) THEN
        ALTER TABLE public.commission_settings ADD COLUMN description TEXT;
    END IF;

    -- updated_at column
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'commission_settings' AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE public.commission_settings ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    -- updated_by column
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'commission_settings' AND column_name = 'updated_by'
    ) THEN
        ALTER TABLE public.commission_settings ADD COLUMN updated_by TEXT;
    END IF;
END $$;

-- 3. Ensure 'key' has UNIQUE or PRIMARY KEY constraint
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        JOIN pg_class t ON c.conrelid = t.oid
        JOIN pg_namespace n ON t.relnamespace = n.oid
        WHERE n.nspname = 'public' AND t.relname = 'commission_settings'
          AND c.contype IN ('p', 'u')
    ) THEN
        ALTER TABLE public.commission_settings ADD CONSTRAINT commission_settings_key_unique UNIQUE (key);
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

-- 4. Seed and update all standard rates and financial configs (Safe from overflow)
INSERT INTO public.commission_settings (key, value, percentage, description, updated_at)
VALUES
    ('coins_per_usd', 15000, 15000, 'سعر الصرف المعتمد: عدد الكوينز مقابل كل 1 دولار أمريكي (1$ = 15,000 كوينز)', NOW()),
    ('host_rate', 100, 100, 'نسبة استلام المضيف من كوينز الهدية (%) وتحويلها لألماس', NOW()),
    ('agency_rate', 10, 10, 'نسبة راتب وكيل المضيف من ماس المضيف (%)', NOW()),
    ('host_target_exchange_rate', 60, 60, 'نسبة راتب المضيف في حال فك ألماس التارجت (%)', NOW()),
    ('recharge_agent_host_rate', 10, 10, 'عمولة وكيل الشحن من راتب المضيف (%)', NOW()),
    ('recharge_agent_agency_rate', 10, 10, 'عمولة وكيل الشحن من راتب وكيل المضيف (%)', NOW()),
    ('platform_rate', 17.72, 17.72, 'نسبة الإدارة والمتبقي للنظام (%)', NOW()),
    ('first_target_diamonds', 150000, 150000, 'قيمة التارجت الأول بالألماس (150,000 ماس)', NOW()),
    ('gold_to_diamond', 1.0, 1.0, 'معدل تحويل الذهب إلى ألماس (1:1 افتراضياً)', NOW()),
    ('diamonds_per_usd', 15000, 15000, 'عدد الألماس الذي يساوي دولاراً واحداً في الحسابات المالية', NOW())
ON CONFLICT (key) DO UPDATE SET
    value = EXCLUDED.value,
    percentage = EXCLUDED.percentage,
    description = EXCLUDED.description,
    updated_at = NOW();

-- 5. Enable Row Level Security (RLS)
ALTER TABLE public.commission_settings ENABLE ROW LEVEL SECURITY;

-- 6. Create universal access policies (Read and Write for authenticated / anon)
DROP POLICY IF EXISTS "commission_settings_read" ON public.commission_settings;
DROP POLICY IF EXISTS "commission_settings_admin" ON public.commission_settings;
DROP POLICY IF EXISTS "commission_settings_all" ON public.commission_settings;
DROP POLICY IF EXISTS "commission_settings_select_policy" ON public.commission_settings;
DROP POLICY IF EXISTS "commission_settings_all_policy" ON public.commission_settings;

CREATE POLICY "commission_settings_all" ON public.commission_settings
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- 7. Grant full permissions to anon, authenticated, and service_role
GRANT ALL ON TABLE public.commission_settings TO anon, authenticated, service_role;

-- 8. Add to Realtime publication
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.commission_settings;
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;
