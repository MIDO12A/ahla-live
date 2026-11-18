-- ============================================================================
-- إصلاح تصنيفات الترتيب (Leaderboards)
-- ----------------------------------------------------------------------------
-- المشكلة: الـ 9 Views (daily/weekly/monthly × wealth/charm/rooms) كانت مبنية
-- على جدول `gift_transactions` الفارغ (0 صفوف)، بينما التطبيق يكتب الهدايا في
-- جدول `sent_gifts` (آلاف الصفوف). لذلك تُرجع كل الـ Views [] ويظهر الترتيب
-- فارغاً إلا عبر المسار الاحتياطي في Flutter (الذي كان بدوره مقصوصاً على 1000
-- صف بسبب سقف PostgREST).
--
-- الحل: إعادة بناء الـ 9 Views لتجميع الهدايا من `sent_gifts` من جهة الخادم:
--   * الثروة (wealth)  = مجموع الهدايا المُرسَلة  (sender_id)
--   * السحر (charm)    = مجموع الهدايا المُستلَمة (receiver_id)
--   * الغرف (rooms)    = مجموع هدايا كل غرفة     (room_id)
-- القيمة المُحتسبة = value * count (مطابقة لـ SentGiftModel.totalValue).
--
-- شغّل هذا الملف على مشروع Supabase (SQL Editor أو migrations).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0) Drop old leaderboard objects first.
--    Migration 20261115_room_rankings_and_signin_fixes.sql recreated the
--    three room leaderboards as TABLES, so a plain DROP VIEW fails with
--    42809: "is not a view". Drop whichever kind actually exists.
--    CREATE OR REPLACE also cannot change an existing column type
--    (`points` was numeric, now bigint from SUM(value * count)).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_name text;
  v_kind "char";
BEGIN
  FOREACH v_name IN ARRAY ARRAY[
    'daily_wealth_ranking', 'weekly_wealth_ranking', 'monthly_wealth_ranking',
    'daily_charm_ranking', 'weekly_charm_ranking', 'monthly_charm_ranking',
    'daily_rooms_ranking', 'weekly_rooms_ranking', 'monthly_rooms_ranking'
  ] LOOP
    SELECT c.relkind INTO v_kind
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = v_name;

    IF v_kind IN ('v', 'm') THEN
      EXECUTE format('DROP VIEW IF EXISTS public.%I CASCADE', v_name);
    ELSIF v_kind IN ('r', 'p') THEN
      EXECUTE format('DROP TABLE IF EXISTS public.%I CASCADE', v_name);
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 1) ترتيب الثروة — الهدايا المُرسَلة
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.daily_wealth_ranking AS
SELECT
    u.id                                        AS uid,
    u.id                                        AS user_id,
    COALESCE(u.custom_id, u.id)                 AS custom_id,
    COALESCE(u.custom_id, u.id)                 AS display_id,
    COALESCE(u.name, 'مستخدم')                  AS name,
    COALESCE(u.photo_url, u.avatar, '')         AS photo_url,
    COALESCE(u.photo_url, u.avatar, '')         AS "photoUrl",
    COALESCE(u.level, 1)                        AS level,
    SUM(g.value * COALESCE(g.count, 1))         AS points
FROM public.sent_gifts g
JOIN public.users u ON (u.id = g.sender_id OR u.uid = g.sender_id)
WHERE g.created_at >= NOW() - INTERVAL '1 day'
GROUP BY u.id, u.custom_id, u.name, u.photo_url, u.avatar, u.level
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.weekly_wealth_ranking AS
SELECT
    u.id                                        AS uid,
    u.id                                        AS user_id,
    COALESCE(u.custom_id, u.id)                 AS custom_id,
    COALESCE(u.custom_id, u.id)                 AS display_id,
    COALESCE(u.name, 'مستخدم')                  AS name,
    COALESCE(u.photo_url, u.avatar, '')         AS photo_url,
    COALESCE(u.photo_url, u.avatar, '')         AS "photoUrl",
    COALESCE(u.level, 1)                        AS level,
    SUM(g.value * COALESCE(g.count, 1))         AS points
FROM public.sent_gifts g
JOIN public.users u ON (u.id = g.sender_id OR u.uid = g.sender_id)
WHERE g.created_at >= NOW() - INTERVAL '7 days'
GROUP BY u.id, u.custom_id, u.name, u.photo_url, u.avatar, u.level
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.monthly_wealth_ranking AS
SELECT
    u.id                                        AS uid,
    u.id                                        AS user_id,
    COALESCE(u.custom_id, u.id)                 AS custom_id,
    COALESCE(u.custom_id, u.id)                 AS display_id,
    COALESCE(u.name, 'مستخدم')                  AS name,
    COALESCE(u.photo_url, u.avatar, '')         AS photo_url,
    COALESCE(u.photo_url, u.avatar, '')         AS "photoUrl",
    COALESCE(u.level, 1)                        AS level,
    SUM(g.value * COALESCE(g.count, 1))         AS points
FROM public.sent_gifts g
JOIN public.users u ON (u.id = g.sender_id OR u.uid = g.sender_id)
WHERE g.created_at >= NOW() - INTERVAL '30 days'
GROUP BY u.id, u.custom_id, u.name, u.photo_url, u.avatar, u.level
ORDER BY points DESC
LIMIT 100;

-- ---------------------------------------------------------------------------
-- 2) ترتيب السحر/الجاذبية — الهدايا المُستلَمة
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.daily_charm_ranking AS
SELECT
    u.id                                        AS uid,
    u.id                                        AS user_id,
    COALESCE(u.custom_id, u.id)                 AS custom_id,
    COALESCE(u.custom_id, u.id)                 AS display_id,
    COALESCE(u.name, 'مستخدم')                  AS name,
    COALESCE(u.photo_url, u.avatar, '')         AS photo_url,
    COALESCE(u.photo_url, u.avatar, '')         AS "photoUrl",
    COALESCE(u.level, 1)                        AS level,
    SUM(g.value * COALESCE(g.count, 1))         AS points
FROM public.sent_gifts g
JOIN public.users u ON (u.id = g.receiver_id OR u.uid = g.receiver_id)
WHERE g.created_at >= NOW() - INTERVAL '1 day'
GROUP BY u.id, u.custom_id, u.name, u.photo_url, u.avatar, u.level
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.weekly_charm_ranking AS
SELECT
    u.id                                        AS uid,
    u.id                                        AS user_id,
    COALESCE(u.custom_id, u.id)                 AS custom_id,
    COALESCE(u.custom_id, u.id)                 AS display_id,
    COALESCE(u.name, 'مستخدم')                  AS name,
    COALESCE(u.photo_url, u.avatar, '')         AS photo_url,
    COALESCE(u.photo_url, u.avatar, '')         AS "photoUrl",
    COALESCE(u.level, 1)                        AS level,
    SUM(g.value * COALESCE(g.count, 1))         AS points
FROM public.sent_gifts g
JOIN public.users u ON (u.id = g.receiver_id OR u.uid = g.receiver_id)
WHERE g.created_at >= NOW() - INTERVAL '7 days'
GROUP BY u.id, u.custom_id, u.name, u.photo_url, u.avatar, u.level
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.monthly_charm_ranking AS
SELECT
    u.id                                        AS uid,
    u.id                                        AS user_id,
    COALESCE(u.custom_id, u.id)                 AS custom_id,
    COALESCE(u.custom_id, u.id)                 AS display_id,
    COALESCE(u.name, 'مستخدم')                  AS name,
    COALESCE(u.photo_url, u.avatar, '')         AS photo_url,
    COALESCE(u.photo_url, u.avatar, '')         AS "photoUrl",
    COALESCE(u.level, 1)                        AS level,
    SUM(g.value * COALESCE(g.count, 1))         AS points
FROM public.sent_gifts g
JOIN public.users u ON (u.id = g.receiver_id OR u.uid = g.receiver_id)
WHERE g.created_at >= NOW() - INTERVAL '30 days'
GROUP BY u.id, u.custom_id, u.name, u.photo_url, u.avatar, u.level
ORDER BY points DESC
LIMIT 100;

-- ---------------------------------------------------------------------------
-- 3) ترتيب الغرف — مجموع هدايا كل غرفة
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.daily_rooms_ranking AS
SELECT
    COALESCE(r.room_id, g.room_id)              AS id,
    COALESCE(r.room_id, g.room_id)              AS room_id,
    COALESCE(r.name, 'غرفة صوتية')              AS name,
    COALESCE(r.room_photo_url, '')              AS photo_url,
    COALESCE(r.room_photo_url, '')              AS "photoUrl",
    COALESCE(r.host_name, '')                   AS host_name,
    COALESCE(r.password, '')                    AS password,
    SUM(g.value * COALESCE(g.count, 1))         AS points
FROM public.sent_gifts g
LEFT JOIN public.rooms r ON (r.room_id = g.room_id)
WHERE g.created_at >= NOW() - INTERVAL '1 day'
  AND g.room_id IS NOT NULL AND g.room_id <> ''
GROUP BY r.room_id, g.room_id, r.name, r.room_photo_url, r.host_name, r.password
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.weekly_rooms_ranking AS
SELECT
    COALESCE(r.room_id, g.room_id)              AS id,
    COALESCE(r.room_id, g.room_id)              AS room_id,
    COALESCE(r.name, 'غرفة صوتية')              AS name,
    COALESCE(r.room_photo_url, '')              AS photo_url,
    COALESCE(r.room_photo_url, '')              AS "photoUrl",
    COALESCE(r.host_name, '')                   AS host_name,
    COALESCE(r.password, '')                    AS password,
    SUM(g.value * COALESCE(g.count, 1))         AS points
FROM public.sent_gifts g
LEFT JOIN public.rooms r ON (r.room_id = g.room_id)
WHERE g.created_at >= NOW() - INTERVAL '7 days'
  AND g.room_id IS NOT NULL AND g.room_id <> ''
GROUP BY r.room_id, g.room_id, r.name, r.room_photo_url, r.host_name, r.password
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.monthly_rooms_ranking AS
SELECT
    COALESCE(r.room_id, g.room_id)              AS id,
    COALESCE(r.room_id, g.room_id)              AS room_id,
    COALESCE(r.name, 'غرفة صوتية')              AS name,
    COALESCE(r.room_photo_url, '')              AS photo_url,
    COALESCE(r.room_photo_url, '')              AS "photoUrl",
    COALESCE(r.host_name, '')                   AS host_name,
    COALESCE(r.password, '')                    AS password,
    SUM(g.value * COALESCE(g.count, 1))         AS points
FROM public.sent_gifts g
LEFT JOIN public.rooms r ON (r.room_id = g.room_id)
WHERE g.created_at >= NOW() - INTERVAL '30 days'
  AND g.room_id IS NOT NULL AND g.room_id <> ''
GROUP BY r.room_id, g.room_id, r.name, r.room_photo_url, r.host_name, r.password
ORDER BY points DESC
LIMIT 100;

-- ---------------------------------------------------------------------------
-- 4) صلاحيات القراءة (PostgREST) — متوافقة مع anon/authenticated
-- ---------------------------------------------------------------------------
GRANT SELECT ON public.daily_wealth_ranking,
                public.weekly_wealth_ranking,
                public.monthly_wealth_ranking,
                public.daily_charm_ranking,
                public.weekly_charm_ranking,
                public.monthly_charm_ranking,
                public.daily_rooms_ranking,
                public.weekly_rooms_ranking,
                public.monthly_rooms_ranking
TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) فهارس مساعدة (تُسرّع التجميع حسب الفترة)
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_sent_gifts_sender_created
    ON public.sent_gifts(sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sent_gifts_receiver_created
    ON public.sent_gifts(receiver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sent_gifts_room_created
    ON public.sent_gifts(room_id, created_at DESC);

-- ============================================================================
-- تحقّق سريع بعد التشغيل:
--   SELECT * FROM daily_wealth_ranking LIMIT 10;
--   SELECT * FROM daily_charm_ranking  LIMIT 10;
--   SELECT * FROM daily_rooms_ranking  LIMIT 10;
-- ============================================================================
