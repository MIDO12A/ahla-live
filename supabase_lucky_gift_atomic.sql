-- =========================================================================
-- AHLA-LIVE: SECURE ATOMIC LUCKY GIFT SYSTEM
-- =========================================================================

-- 1. إضافة أعمدة التحكم بنسب الحظ لجدول الهدايا
ALTER TABLE public.gifts 
ADD COLUMN IF NOT EXISTS is_lucky BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS win_rate FLOAT DEFAULT 15.0,
ADD COLUMN IF NOT EXISTS max_multiplier INT DEFAULT 500;

-- 2. إنشاء جدول سجل المعاملات المالية (Audit Log)
CREATE TABLE IF NOT EXISTS public.transaction_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    room_id TEXT NOT NULL,
    receiver_id TEXT NOT NULL,
    gift_id TEXT NOT NULL,
    cost INT NOT NULL,
    won_coins INT NOT NULL DEFAULT 0,
    multiplier INT NOT NULL DEFAULT 0,
    is_win BOOLEAN NOT NULL DEFAULT false,
    balance_before INT NOT NULL,
    balance_after INT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trans_user_created ON public.transaction_logs (user_id, created_at DESC);

-- 3. دالة المعاملة الذرية الآمنة (Atomic RPC Function)
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
SET search_path = public
AS $func$
DECLARE
    v_user_balance INT;
    v_unit_price INT;
    v_total_cost INT;
    v_win_rate FLOAT;
    v_max_mult INT;
    v_is_lucky BOOLEAN;
    
    v_total_won INT := 0;
    v_highest_mult INT := 0;
    v_roll FLOAT;
    v_current_mult INT;
    v_mult_roll FLOAT;
    v_multipliers INT[] := '{}';
    
    v_new_balance INT;
    v_diamond_reward INT;
    v_is_win BOOLEAN := false;
BEGIN
    IF p_count <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'عدد الهدايا يجب أن يكون 1 على الأقل');
    END IF;

    -- قفل صف المستخدم لمنع التلاعب والتصريف المزدوج (Row Lock)
    SELECT COALESCE(coins, 0)
    INTO v_user_balance
    FROM public.users
    WHERE id = p_user_id OR uid = p_user_id
    LIMIT 1
    FOR UPDATE;

    IF v_user_balance IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
    END IF;

    -- جلب إعدادات الهدية وسعرها ونسبة فوزها
    SELECT 
        COALESCE(coin_price, price, 0),
        COALESCE(win_rate, 15.0),
        COALESCE(max_multiplier, 500),
        COALESCE(is_lucky, true)
    INTO 
        v_unit_price,
        v_win_rate,
        v_max_mult,
        v_is_lucky
    FROM public.gifts
    WHERE id = p_gift_id
    LIMIT 1;

    IF v_unit_price IS NULL OR v_unit_price <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'الهدية غير صالحة');
    END IF;

    v_total_cost := v_unit_price * p_count;

    IF v_user_balance < v_total_cost THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'رصيد العملات غير كافٍ',
            'current_balance', v_user_balance,
            'required_cost', v_total_cost
        );
    END IF;

    -- خوارزمية السحب العشوائي الآمن المشفرة لكل حبة
    FOR i IN 1..p_count LOOP
        v_roll := random() * 100.0; -- رقم عشوائي بين 0 و 99.9999
        
        -- المقارنة بدقة: إذا كان الرقم أقل من win_rate (مثلاً 15.0) يفوز، وإلا خسارة حتمية
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
            -- خسارة حتمية (المكسب 0)
            v_multipliers := array_append(v_multipliers, 0);
        END IF;
    END LOOP;

    -- حساب الرصيد الجديد ذرياً
    v_new_balance := v_user_balance - v_total_cost + v_total_won;

    -- تحديث رصيد المرسل
    UPDATE public.users
    SET 
        coins = v_new_balance,
        total_gifts_sent = COALESCE(total_gifts_sent, 0) + v_total_cost
    WHERE id = p_user_id OR uid = p_user_id;

    -- تحديث رصيد المستلم (ألماس) إذا لم يكن المرسل هو المستلم
    IF p_user_id != p_receiver_id THEN
        v_diamond_reward := ROUND(v_total_cost * 0.35);
        UPDATE public.users
        SET 
            diamonds = COALESCE(diamonds, 0) + v_diamond_reward,
            total_gifts_received = COALESCE(total_gifts_received, 0) + v_total_cost
        WHERE id = p_receiver_id OR uid = p_receiver_id;
    END IF;

    -- تسجيل في جدول transaction_logs لمنع التلاعب
    INSERT INTO public.transaction_logs (
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

    RETURN jsonb_build_object(
        'success', true,
        'cost', v_total_cost,
        'won_coins', v_total_won,
        'multiplier', v_highest_mult,
        'multipliers', to_jsonb(v_multipliers),
        'is_win', v_is_win,
        'new_balance', v_new_balance,
        'is_big_win', (v_highest_mult >= 50)
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$func$;
