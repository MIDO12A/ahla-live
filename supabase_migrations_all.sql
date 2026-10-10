-- ============================================================================
-- 1. تفعيل الإضافات وإنشاء الجداول الأساسية
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- جدول سجلات عمليات الهدايا ومعاملات الحظ (gift_transactions)
CREATE TABLE IF NOT EXISTS public.gift_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL,
    room_id TEXT NOT NULL,
    receiver_id TEXT NOT NULL,
    gift_id TEXT NOT NULL,
    cost BIGINT NOT NULL CHECK (cost >= 0),
    won_coins BIGINT NOT NULL DEFAULT 0 CHECK (won_coins >= 0),
    multiplier INT NOT NULL DEFAULT 0,
    is_win BOOLEAN NOT NULL DEFAULT false,
    balance_before BIGINT NOT NULL,
    balance_after BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- إنشاء فهارس (Indexes) سريعة للأداء والاستعلامات
CREATE INDEX IF NOT EXISTS idx_gift_tx_user_id ON public.gift_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_gift_tx_room_id ON public.gift_transactions(room_id);
CREATE INDEX IF NOT EXISTS idx_gift_tx_receiver_id ON public.gift_transactions(receiver_id);
CREATE INDEX IF NOT EXISTS idx_gift_tx_created_at ON public.gift_transactions(created_at DESC);

-- التأكد من وجود أعمدة الحظ في جدول الهدايا
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS win_rate NUMERIC DEFAULT 15.0;
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS max_multiplier INT DEFAULT 500;
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS is_lucky BOOLEAN DEFAULT false;

-- جدول سجل إرسال الهدايا للترتيب والإحصائيات
CREATE TABLE IF NOT EXISTS public.sent_gifts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id TEXT,
    gift_id TEXT,
    gift_name TEXT,
    animation_asset TEXT,
    sender_id TEXT NOT NULL,
    sender_name TEXT,
    sender_photo_url TEXT,
    receiver_id TEXT NOT NULL,
    receiver_name TEXT,
    value BIGINT NOT NULL DEFAULT 0,
    count INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sent_gifts_room_id ON public.sent_gifts(room_id);
CREATE INDEX IF NOT EXISTS idx_sent_gifts_sender_id ON public.sent_gifts(sender_id);
CREATE INDEX IF NOT EXISTS idx_sent_gifts_receiver_id ON public.sent_gifts(receiver_id);
CREATE INDEX IF NOT EXISTS idx_sent_gifts_created_at ON public.sent_gifts(created_at DESC);

-- ============================================================================
-- 2. دالة معالجة هدية الحظ الذرية الآمنة (process_lucky_gift) بـ SECURITY DEFINER
-- ============================================================================
CREATE OR REPLACE FUNCTION public.process_lucky_gift(
    p_user_id TEXT,
    p_room_id TEXT,
    p_receiver_id TEXT,
    p_gift_id TEXT,
    p_count INT DEFAULT 1
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $func$
DECLARE
    v_user_balance BIGINT;
    v_unit_price BIGINT;
    v_win_rate NUMERIC;
    v_max_mult INT;
    v_total_cost BIGINT;
    v_total_won BIGINT := 0;
    v_highest_mult INT := 0;
    v_multipliers INT[] := '{}';
    v_new_balance BIGINT;
    v_diamond_reward BIGINT;
    v_roll NUMERIC;
    v_mult_roll NUMERIC;
    v_current_mult INT;
    v_is_win BOOLEAN := false;
    v_is_big_win BOOLEAN := false;
BEGIN
    -- 1. التحقق من صحة المدخلات
    IF p_count IS NULL OR p_count <= 0 THEN
        p_count := 1;
    END IF;

    -- 2. قفل صف المستخدم (FOR UPDATE) لمنع تضارب المعاملات (Race Conditions)
    SELECT coins INTO v_user_balance
    FROM public.users
    WHERE id = p_user_id OR uid = p_user_id
    LIMIT 1
    FOR UPDATE;

    IF v_user_balance IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'المستخدم غير موجود'
        );
    END IF;

    -- 3. جلب تفاصيل الهدية ونسب الحظ
    SELECT 
        COALESCE(coin_price, COALESCE(price, COALESCE(value, 0))),
        COALESCE(win_rate, 15.0),
        COALESCE(max_multiplier, 500)
    INTO 
        v_unit_price,
        v_win_rate,
        v_max_mult
    FROM public.gifts
    WHERE id = p_gift_id
    LIMIT 1;

    IF v_unit_price IS NULL OR v_unit_price <= 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'الهدية غير صالحة'
        );
    END IF;

    v_total_cost := v_unit_price * p_count;

    -- 4. فحص كفاية الرصيد
    IF v_user_balance < v_total_cost THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'رصيد العملات غير كافٍ',
            'current_balance', v_user_balance,
            'required_cost', v_total_cost
        );
    END IF;

    -- 5. خوارزمية السحب العشوائي الموزونة لكل حبة على الخادم
    FOR i IN 1..p_count LOOP
        v_roll := random() * 100.0;
        
        IF v_roll < v_win_rate THEN
            v_is_win := true;
            v_mult_roll := random() * 100.0;
            
            IF v_mult_roll < 65.0 THEN
                v_current_mult := 1;
            ELSIF v_mult_roll < 88.0 THEN
                v_current_mult := 2;
            ELSIF v_mult_roll < 96.0 THEN
                v_current_mult := 5;
            ELSIF v_mult_roll < 98.8 THEN
                v_current_mult := 10;
            ELSIF v_mult_roll < 99.7 THEN
                v_current_mult := 20;
            ELSIF v_mult_roll < 99.95 THEN
                v_current_mult := LEAST(50, v_max_mult);
            ELSE
                v_current_mult := v_max_mult;
            END IF;

            v_total_won := v_total_won + (v_unit_price * v_current_mult);
            IF v_current_mult > v_highest_mult THEN
                v_highest_mult := v_current_mult;
            END IF;
            v_multipliers := array_append(v_multipliers, v_current_mult);
        ELSE
            v_multipliers := array_append(v_multipliers, 0);
        END IF;
    END LOOP;

    IF v_highest_mult >= 50 THEN
        v_is_big_win := true;
    END IF;

    -- 6. حساب الرصيد الصافي وتحديث رصيد المرسل ذرياً
    v_new_balance := v_user_balance - v_total_cost + v_total_won;

    UPDATE public.users
    SET 
        coins = v_new_balance,
        total_gifts_sent = COALESCE(total_gifts_sent, 0) + v_total_cost
    WHERE id = p_user_id OR uid = p_user_id;

    -- 7. تحديث رصيد المستلم (الألماس) والمستويات والتارجت إن لم يكن إرسال ذاتي
    IF p_user_id != p_receiver_id THEN
        v_diamond_reward := ROUND(v_total_cost * 0.35);
        UPDATE public.users
        SET 
            diamonds = COALESCE(diamonds, 0) + v_diamond_reward,
            total_gifts_received = COALESCE(total_gifts_received, 0) + v_total_cost
        WHERE id = p_receiver_id OR uid = p_receiver_id;

        UPDATE public.host_agency_members
        SET 
            diamonds_earned_monthly = COALESCE(diamonds_earned_monthly, 0) + v_diamond_reward,
            diamonds_balance = COALESCE(diamonds_balance, 0) + v_diamond_reward
        WHERE user_id = p_receiver_id;
    END IF;

    -- 8. تسجيل العملية في جدول gift_transactions
    INSERT INTO public.gift_transactions (
        user_id,
        room_id,
        receiver_id,
        gift_id,
        cost,
        won_coins,
        multiplier,
        is_win,
        balance_before,
        balance_after
    ) VALUES (
        p_user_id,
        p_room_id,
        p_receiver_id,
        p_gift_id,
        v_total_cost,
        v_total_won,
        v_highest_mult,
        v_is_win,
        v_user_balance,
        v_new_balance
    );

    -- 9. إرجاع النتيجة الكاملة
    RETURN jsonb_build_object(
        'success', true,
        'newBalance', v_new_balance,
        'cost', v_total_cost,
        'totalWon', v_total_won,
        'multiplier', v_highest_mult,
        'multipliers', to_jsonb(v_multipliers),
        'isBigWin', v_is_big_win,
        'isWin', v_is_win
    );
END;
$func$;

-- ============================================================================
-- 2.1 دالة إرسال الهدية العادية الذرية (send_regular_gift) بـ SECURITY DEFINER
-- ============================================================================
CREATE OR REPLACE FUNCTION public.send_regular_gift(
    p_sender_id TEXT,
    p_room_id TEXT,
    p_receiver_id TEXT,
    p_gift_id TEXT,
    p_count INT DEFAULT 1
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $func$
DECLARE
    v_sender_coins BIGINT;
    v_gift_price BIGINT;
    v_total_cost BIGINT;
    v_diamond_reward BIGINT;
    v_new_sender_coins BIGINT;
BEGIN
    IF p_count IS NULL OR p_count <= 0 THEN
        p_count := 1;
    END IF;

    -- قفل صف المرسل لمنع Race Conditions
    SELECT coins INTO v_sender_coins
    FROM public.users
    WHERE id = p_sender_id OR uid = p_sender_id
    LIMIT 1
    FOR UPDATE;

    IF v_sender_coins IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'المرسل غير موجود');
    END IF;

    -- جلب سعر الهدية
    SELECT COALESCE(coin_price, COALESCE(price, COALESCE(value, 0)))
    INTO v_gift_price
    FROM public.gifts
    WHERE id = p_gift_id
    LIMIT 1;

    IF v_gift_price IS NULL OR v_gift_price <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'الهدية غير صالحة');
    END IF;

    v_total_cost := v_gift_price * p_count;

    IF v_sender_coins < v_total_cost THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'رصيد العملات غير كافٍ',
            'current_balance', v_sender_coins,
            'required_cost', v_total_cost
        );
    END IF;

    v_new_sender_coins := v_sender_coins - v_total_cost;

    -- خصم من المرسل
    UPDATE public.users
    SET 
        coins = v_new_sender_coins,
        total_gifts_sent = COALESCE(total_gifts_sent, 0) + v_total_cost
    WHERE id = p_sender_id OR uid = p_sender_id;

    -- إضافة الألماس للمستلم (35%)
    IF p_sender_id != p_receiver_id THEN
        v_diamond_reward := ROUND(v_total_cost * 0.35);
        UPDATE public.users
        SET 
            diamonds = COALESCE(diamonds, 0) + v_diamond_reward,
            total_gifts_received = COALESCE(total_gifts_received, 0) + v_total_cost
        WHERE id = p_receiver_id OR uid = p_receiver_id;

        UPDATE public.host_agency_members
        SET 
            diamonds_earned_monthly = COALESCE(diamonds_earned_monthly, 0) + v_diamond_reward,
            diamonds_balance = COALESCE(diamonds_balance, 0) + v_diamond_reward
        WHERE user_id = p_receiver_id;
    END IF;

    -- تسجيل في جدول sent_gifts
    INSERT INTO public.sent_gifts (
        room_id,
        gift_id,
        sender_id,
        receiver_id,
        value,
        count
    ) VALUES (
        p_room_id,
        p_gift_id,
        p_sender_id,
        p_receiver_id,
        v_total_cost,
        p_count
    );

    RETURN jsonb_build_object(
        'success', true,
        'new_balance', v_new_sender_coins,
        'total_cost', v_total_cost,
        'diamonds_added', v_diamond_reward
    );
END;
$func$;

-- ============================================================================
-- 2.2 دالة تحديث رصيد المستخدم الآمنة (update_user_balance) بـ SECURITY DEFINER
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_user_balance(
    p_user_id TEXT,
    p_coin_delta BIGINT,
    p_diamond_delta BIGINT DEFAULT 0,
    p_reason TEXT DEFAULT 'system_adjustment'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $func$
DECLARE
    v_current_coins BIGINT;
    v_current_diamonds BIGINT;
    v_new_coins BIGINT;
    v_new_diamonds BIGINT;
BEGIN
    SELECT coins, diamonds 
    INTO v_current_coins, v_current_diamonds
    FROM public.users
    WHERE id = p_user_id OR uid = p_user_id
    LIMIT 1
    FOR UPDATE;

    IF v_current_coins IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
    END IF;

    v_new_coins := v_current_coins + p_coin_delta;
    v_new_diamonds := v_current_diamonds + p_diamond_delta;

    IF v_new_coins < 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'الرصيد لا يسمح بالخصم');
    END IF;

    UPDATE public.users
    SET 
        coins = v_new_coins,
        diamonds = GREATEST(0, v_new_diamonds)
    WHERE id = p_user_id OR uid = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'new_coins', v_new_coins,
        'new_diamonds', GREATEST(0, v_new_diamonds),
        'reason', p_reason
    );
END;
$func$;

-- ============================================================================
-- 3. إنشاء الـ 9 VIEWS المخصصة لترتيب المتصدرين (Leaderboards)
-- ============================================================================

CREATE OR REPLACE VIEW public.daily_wealth_ranking AS
SELECT 
    u.id AS uid,
    u.id AS user_id,
    COALESCE(u.custom_id, u.id) AS custom_id,
    COALESCE(u.custom_id, u.id) AS display_id,
    COALESCE(u.name, 'مستخدم') AS name,
    COALESCE(u.photo_url, COALESCE(u.avatar, '')) AS photo_url,
    COALESCE(u.photo_url, COALESCE(u.avatar, '')) AS "photoUrl",
    COALESCE(u.level, 1) AS level,
    SUM(g.cost) AS points
FROM public.gift_transactions g
JOIN public.users u ON (u.id = g.user_id OR u.uid = g.user_id)
WHERE g.created_at >= NOW() - INTERVAL '1 day'
GROUP BY u.id, u.custom_id, u.name, u.photo_url, u.avatar, u.level
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.weekly_wealth_ranking AS
SELECT 
    u.id AS uid,
    u.id AS user_id,
    COALESCE(u.custom_id, u.id) AS custom_id,
    COALESCE(u.custom_id, u.id) AS display_id,
    COALESCE(u.name, 'مستخدم') AS name,
    COALESCE(u.photo_url, COALESCE(u.avatar, '')) AS photo_url,
    COALESCE(u.photo_url, COALESCE(u.avatar, '')) AS "photoUrl",
    COALESCE(u.level, 1) AS level,
    SUM(g.cost) AS points
FROM public.gift_transactions g
JOIN public.users u ON (u.id = g.user_id OR u.uid = g.user_id)
WHERE g.created_at >= NOW() - INTERVAL '7 days'
GROUP BY u.id, u.custom_id, u.name, u.photo_url, u.avatar, u.level
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.monthly_wealth_ranking AS
SELECT 
    u.id AS uid,
    u.id AS user_id,
    COALESCE(u.custom_id, u.id) AS custom_id,
    COALESCE(u.custom_id, u.id) AS display_id,
    COALESCE(u.name, 'مستخدم') AS name,
    COALESCE(u.photo_url, COALESCE(u.avatar, '')) AS photo_url,
    COALESCE(u.photo_url, COALESCE(u.avatar, '')) AS "photoUrl",
    COALESCE(u.level, 1) AS level,
    SUM(g.cost) AS points
FROM public.gift_transactions g
JOIN public.users u ON (u.id = g.user_id OR u.uid = g.user_id)
WHERE g.created_at >= NOW() - INTERVAL '30 days'
GROUP BY u.id, u.custom_id, u.name, u.photo_url, u.avatar, u.level
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.daily_charm_ranking AS
SELECT 
    u.id AS uid,
    u.id AS user_id,
    COALESCE(u.custom_id, u.id) AS custom_id,
    COALESCE(u.custom_id, u.id) AS display_id,
    COALESCE(u.name, 'مستخدم') AS name,
    COALESCE(u.photo_url, COALESCE(u.avatar, '')) AS photo_url,
    COALESCE(u.photo_url, COALESCE(u.avatar, '')) AS "photoUrl",
    COALESCE(u.level, 1) AS level,
    SUM(g.cost) AS points
FROM public.gift_transactions g
JOIN public.users u ON (u.id = g.receiver_id OR u.uid = g.receiver_id)
WHERE g.created_at >= NOW() - INTERVAL '1 day'
GROUP BY u.id, u.custom_id, u.name, u.photo_url, u.avatar, u.level
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.weekly_charm_ranking AS
SELECT 
    u.id AS uid,
    u.id AS user_id,
    COALESCE(u.custom_id, u.id) AS custom_id,
    COALESCE(u.custom_id, u.id) AS display_id,
    COALESCE(u.name, 'مستخدم') AS name,
    COALESCE(u.photo_url, COALESCE(u.avatar, '')) AS photo_url,
    COALESCE(u.photo_url, COALESCE(u.avatar, '')) AS "photoUrl",
    COALESCE(u.level, 1) AS level,
    SUM(g.cost) AS points
FROM public.gift_transactions g
JOIN public.users u ON (u.id = g.receiver_id OR u.uid = g.receiver_id)
WHERE g.created_at >= NOW() - INTERVAL '7 days'
GROUP BY u.id, u.custom_id, u.name, u.photo_url, u.avatar, u.level
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.monthly_charm_ranking AS
SELECT 
    u.id AS uid,
    u.id AS user_id,
    COALESCE(u.custom_id, u.id) AS custom_id,
    COALESCE(u.custom_id, u.id) AS display_id,
    COALESCE(u.name, 'مستخدم') AS name,
    COALESCE(u.photo_url, COALESCE(u.avatar, '')) AS photo_url,
    COALESCE(u.photo_url, COALESCE(u.avatar, '')) AS "photoUrl",
    COALESCE(u.level, 1) AS level,
    SUM(g.cost) AS points
FROM public.gift_transactions g
JOIN public.users u ON (u.id = g.receiver_id OR u.uid = g.receiver_id)
WHERE g.created_at >= NOW() - INTERVAL '30 days'
GROUP BY u.id, u.custom_id, u.name, u.photo_url, u.avatar, u.level
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.daily_rooms_ranking AS
SELECT 
    COALESCE(r.room_id, g.room_id) AS id,
    COALESCE(r.room_id, g.room_id) AS room_id,
    COALESCE(r.name, 'غرفة صوتية') AS name,
    COALESCE(r.room_photo_url, '') AS photo_url,
    COALESCE(r.room_photo_url, '') AS "photoUrl",
    COALESCE(r.host_name, '') AS host_name,
    COALESCE(r.password, '') AS password,
    SUM(g.cost) AS points
FROM public.gift_transactions g
LEFT JOIN public.rooms r ON (r.room_id = g.room_id)
WHERE g.created_at >= NOW() - INTERVAL '1 day'
GROUP BY r.room_id, g.room_id, r.name, r.room_photo_url, r.host_name, r.password
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.weekly_rooms_ranking AS
SELECT 
    COALESCE(r.room_id, g.room_id) AS id,
    COALESCE(r.room_id, g.room_id) AS room_id,
    COALESCE(r.name, 'غرفة صوتية') AS name,
    COALESCE(r.room_photo_url, '') AS photo_url,
    COALESCE(r.room_photo_url, '') AS "photoUrl",
    COALESCE(r.host_name, '') AS host_name,
    COALESCE(r.password, '') AS password,
    SUM(g.cost) AS points
FROM public.gift_transactions g
LEFT JOIN public.rooms r ON (r.room_id = g.room_id)
WHERE g.created_at >= NOW() - INTERVAL '7 days'
GROUP BY r.room_id, g.room_id, r.name, r.room_photo_url, r.host_name, r.password
ORDER BY points DESC
LIMIT 100;

CREATE OR REPLACE VIEW public.monthly_rooms_ranking AS
SELECT 
    COALESCE(r.room_id, g.room_id) AS id,
    COALESCE(r.room_id, g.room_id) AS room_id,
    COALESCE(r.name, 'غرفة صوتية') AS name,
    COALESCE(r.room_photo_url, '') AS photo_url,
    COALESCE(r.room_photo_url, '') AS "photoUrl",
    COALESCE(r.host_name, '') AS host_name,
    COALESCE(r.password, '') AS password,
    SUM(g.cost) AS points
FROM public.gift_transactions g
LEFT JOIN public.rooms r ON (r.room_id = g.room_id)
WHERE g.created_at >= NOW() - INTERVAL '30 days'
GROUP BY r.room_id, g.room_id, r.name, r.room_photo_url, r.host_name, r.password
ORDER BY points DESC
LIMIT 100;

-- ============================================================================
-- 4. إنشاء VIEW الوكالات النشطة الحقيقية (active_agencies)
-- ============================================================================
CREATE OR REPLACE VIEW public.active_agencies AS
SELECT 
    id,
    name,
    COALESCE(logo_url, '') AS photo_url,
    COALESCE(logo_url, '') AS logo_url,
    COALESCE(tier, 'C') AS tier,
    COALESCE(member_count, 0) AS member_count,
    COALESCE(total_diamonds_monthly, 0) AS total_diamonds_monthly,
    COALESCE(is_hall_of_fame, false) AS is_hall_of_fame,
    owner_uid,
    created_at
FROM public.host_agencies
WHERE COALESCE(is_active, true) = true
ORDER BY total_diamonds_monthly DESC;

-- ============================================================================
-- 5. تفعيل Supabase Realtime لجدول notifications و gift_transactions
-- ============================================================================
ALTER TABLE public.notifications REPLICA IDENTITY FULL;
DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'gift_transactions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.gift_transactions;
    END IF;
END $block$;
