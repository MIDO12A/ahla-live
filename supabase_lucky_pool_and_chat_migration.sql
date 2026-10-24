-- =========================================================================
-- AHLA-LIVE: SERVER LUCKY POOL, AUTO-REFILL & PRIVATE MESSAGES MIGRATION
-- =========================================================================

-- 1. إنشاء جدول محفظة الحظ في السيرفر (Lucky Server Pool)
CREATE TABLE IF NOT EXISTS public.lucky_pools (
    id TEXT PRIMARY KEY DEFAULT 'main',
    balance BIGINT NOT NULL DEFAULT 0,
    total_deposited BIGINT NOT NULL DEFAULT 0,
    total_paid_out BIGINT NOT NULL DEFAULT 0,
    min_reserve BIGINT NOT NULL DEFAULT 10000,
    auto_refill_amount BIGINT NOT NULL DEFAULT 50000,
    auto_refill_enabled BOOLEAN NOT NULL DEFAULT false,
    win_rate FLOAT DEFAULT 15.0,
    loss_rate FLOAT DEFAULT 85.0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- إدراج المحفظة الرئيسية الافتراضية إن لم تكن موجودة
INSERT INTO public.lucky_pools (id, balance, total_deposited, total_paid_out, min_reserve, auto_refill_amount, auto_refill_enabled, win_rate, loss_rate)
VALUES ('main', 100000, 100000, 0, 10000, 50000, true, 15.0, 85.0)
ON CONFLICT (id) DO NOTHING;

-- 2. إنشاء جدول سجلات محفظة الحظ (التعبئة اليدوية، التلقائية، النفاذ، وصرف الأرباح)
CREATE TABLE IF NOT EXISTS public.lucky_pool_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pool_id TEXT NOT NULL DEFAULT 'main',
    log_type TEXT NOT NULL, -- 'manual_refill', 'auto_refill', 'depleted', 'payout'
    amount BIGINT NOT NULL DEFAULT 0,
    balance_before BIGINT NOT NULL DEFAULT 0,
    balance_after BIGINT NOT NULL DEFAULT 0,
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lucky_pool_logs_created ON public.lucky_pool_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lucky_pool_logs_type ON public.lucky_pool_logs (log_type);

-- تفعيل سياسات الأمان أو إتاحة الوصول
ALTER TABLE public.lucky_pools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lucky_pool_logs ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'lucky_pools' AND policyname = 'lucky_pools_all') THEN
    CREATE POLICY "lucky_pools_all" ON public.lucky_pools FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'lucky_pool_logs' AND policyname = 'lucky_pool_logs_all') THEN
    CREATE POLICY "lucky_pool_logs_all" ON public.lucky_pool_logs FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 3. دالة تعبئة محفظة الحظ يدوياً أو تلقائياً (RPC)
CREATE OR REPLACE FUNCTION public.refill_lucky_pool(
    p_amount BIGINT,
    p_type TEXT DEFAULT 'manual_refill',
    p_note TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
    v_balance_before BIGINT;
    v_balance_after BIGINT;
BEGIN
    IF p_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'المبلغ يجب أن يكون أكبر من 0');
    END IF;

    SELECT balance INTO v_balance_before
    FROM public.lucky_pools
    WHERE id = 'main'
    FOR UPDATE;

    IF v_balance_before IS NULL THEN
        INSERT INTO public.lucky_pools (id, balance, total_deposited)
        VALUES ('main', p_amount, p_amount)
        RETURNING balance INTO v_balance_after;
        v_balance_before := 0;
    ELSE
        v_balance_after := v_balance_before + p_amount;
        UPDATE public.lucky_pools
        SET 
            balance = v_balance_after,
            total_deposited = total_deposited + p_amount,
            updated_at = NOW()
        WHERE id = 'main';
    END IF;

    INSERT INTO public.lucky_pool_logs (
        pool_id, log_type, amount, balance_before, balance_after, note
    ) VALUES (
        'main', p_type, p_amount, v_balance_before, v_balance_after, p_note
    );

    RETURN jsonb_build_object(
        'success', true,
        'balance_before', v_balance_before,
        'balance_after', v_balance_after,
        'amount', p_amount,
        'type', p_type
    );
END;
$func$;

-- 4. تحديث المعاملة الذرية لهدايا الحظ (process_lucky_gift) للربط الصارم بمحفظة الحظ
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
    
    -- متغيرات محفظة الحظ
    v_pool_balance BIGINT := 0;
    v_pool_min_reserve BIGINT := 10000;
    v_pool_refill_amount BIGINT := 50000;
    v_pool_refill_enabled BOOLEAN := false;
    v_pool_is_depleted BOOLEAN := false;
    
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

    -- قفل صف المستخدم لمنع التلاعب (Row Lock)
    SELECT COALESCE(coins, 0)
    INTO v_user_balance
    FROM public.users
    WHERE id = p_user_id OR uid = p_user_id
    LIMIT 1
    FOR UPDATE;

    IF v_user_balance IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
    END IF;

    -- جلب إعدادات الهدية وسعرها
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

    -- قفل وفحص محفظة الحظ بالسيرفر
    SELECT 
        COALESCE(balance, 0),
        COALESCE(min_reserve, 10000),
        COALESCE(auto_refill_amount, 50000),
        COALESCE(auto_refill_enabled, false),
        COALESCE(win_rate, v_win_rate)
    INTO 
        v_pool_balance,
        v_pool_min_reserve,
        v_pool_refill_amount,
        v_pool_refill_enabled,
        v_win_rate
    FROM public.lucky_pools
    WHERE id = 'main'
    LIMIT 1
    FOR UPDATE;

    -- فحص النفاذ وإمكانية التعبئة التلقائية
    IF v_pool_balance <= 0 THEN
        IF v_pool_refill_enabled THEN
            -- تنفيذ تعبئة تلقائية فورية
            UPDATE public.lucky_pools
            SET 
                balance = balance + v_pool_refill_amount,
                total_deposited = total_deposited + v_pool_refill_amount,
                updated_at = NOW()
            WHERE id = 'main';

            INSERT INTO public.lucky_pool_logs (
                pool_id, log_type, amount, balance_before, balance_after, note
            ) VALUES (
                'main', 'auto_refill', v_pool_refill_amount, v_pool_balance, (v_pool_balance + v_pool_refill_amount), 'تعبئة تلقائية عند محاولة السحب والمحفظة فارغة'
            );
            v_pool_balance := v_pool_balance + v_pool_refill_amount;
        ELSE
            -- المحفظة نافذة ولا توجد تعبئة تلقائية -> خسارة حتمية 100%
            v_pool_is_depleted := true;
            INSERT INTO public.lucky_pool_logs (
                pool_id, log_type, amount, balance_before, balance_after, note
            ) VALUES (
                'main', 'depleted', 0, v_pool_balance, v_pool_balance, 'محاولة لعب أثناء نفاذ محفظة الحظ - تم تحويل النتيجة لخسارة 0X'
            );
        END IF;
    END IF;

    -- خوارزمية السحب
    FOR i IN 1..p_count LOOP
        IF v_pool_is_depleted OR v_pool_balance <= 0 THEN
            -- حظر المكسب تماماً عند نفاذ المحفظة
            v_multipliers := array_append(v_multipliers, 0);
        ELSE
            v_roll := random() * 100.0;
            
            IF v_roll < v_win_rate THEN
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

                -- التحقق من تغطية المحفظة لمبلغ الفوز
                IF (v_total_won + (v_unit_price * v_current_mult)) <= v_pool_balance THEN
                    v_is_win := true;
                    v_total_won := v_total_won + (v_unit_price * v_current_mult);
                    IF v_current_mult > v_highest_mult THEN
                        v_highest_mult := v_current_mult;
                    END IF;
                    v_multipliers := array_append(v_multipliers, v_current_mult);
                ELSE
                    -- المحفظة لا تكفي هذا المضاعف العالي
                    v_multipliers := array_append(v_multipliers, 0);
                END IF;
            ELSE
                -- خسارة عادية (0X)
                v_multipliers := array_append(v_multipliers, 0);
            END IF;
        END IF;
    END LOOP;

    -- خصم أرباح الفوز من محفظة الحظ وتحديث سجلاتها
    IF v_total_won > 0 THEN
        UPDATE public.lucky_pools
        SET 
            balance = GREATEST(0, balance - v_total_won),
            total_paid_out = total_paid_out + v_total_won,
            updated_at = NOW()
        WHERE id = 'main';

        INSERT INTO public.lucky_pool_logs (
            pool_id, log_type, amount, balance_before, balance_after, note
        ) VALUES (
            'main', 'payout', v_total_won, v_pool_balance, (v_pool_balance - v_total_won), 
            'صرف أرباح فوز للاعب ' || p_user_id || ' بمضاعف ' || v_highest_mult || 'X'
        );

        -- فحص إذا انخفض الرصيد تحت الحد الأدنى وهناك تعبئة تلقائية
        IF (v_pool_balance - v_total_won) < v_pool_min_reserve AND v_pool_refill_enabled THEN
            UPDATE public.lucky_pools
            SET 
                balance = balance + v_pool_refill_amount,
                total_deposited = total_deposited + v_pool_refill_amount,
                updated_at = NOW()
            WHERE id = 'main';

            INSERT INTO public.lucky_pool_logs (
                pool_id, log_type, amount, balance_before, balance_after, note
            ) VALUES (
                'main', 'auto_refill', v_pool_refill_amount, (v_pool_balance - v_total_won), 
                (v_pool_balance - v_total_won + v_pool_refill_amount), 
                'تعبئة تلقائية بسبب انخفاض رصيد المحفظة عن الحد الأدنى الاحتياطي'
            );
        END IF;
    END IF;

    -- حساب وتحديث رصيد اللاعب
    v_new_balance := v_user_balance - v_total_cost + v_total_won;

    UPDATE public.users
    SET 
        coins = v_new_balance,
        total_gifts_sent = COALESCE(total_gifts_sent, 0) + v_total_cost
    WHERE id = p_user_id OR uid = p_user_id;

    -- تحديث رصيد المستلم (ألماس)
    IF p_user_id != p_receiver_id THEN
        v_diamond_reward := ROUND(v_total_cost * 0.10); -- النسبة الافتراضية للتارجت
        UPDATE public.users
        SET 
            diamonds = COALESCE(diamonds, 0) + v_diamond_reward,
            total_gifts_received = COALESCE(total_gifts_received, 0) + v_total_cost
        WHERE id = p_receiver_id OR uid = p_receiver_id;
    END IF;

    -- تسجيل في جدول transaction_logs
    INSERT INTO public.transaction_logs (
        user_id, room_id, receiver_id, gift_id, cost, won_coins, multiplier, is_win, balance_before, balance_after
    ) VALUES (
        p_user_id, p_room_id, p_receiver_id, p_gift_id, v_total_cost, v_total_won, v_highest_mult, v_is_win, v_user_balance, v_new_balance
    );

    RETURN jsonb_build_object(
        'success', true,
        'cost', v_total_cost,
        'won_coins', v_total_won,
        'multiplier', v_highest_mult,
        'multipliers', to_jsonb(v_multipliers),
        'is_win', v_is_win,
        'new_balance', v_new_balance,
        'is_big_win', (v_highest_mult >= 50),
        'pool_depleted', v_pool_is_depleted
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$func$;

-- 5. تصليح وتوسيع جدول الرسائل الخاصة (private_messages) والمحادثات (conversations)
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS conversation_id TEXT;
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS receiver_uid TEXT;
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS receiver_name TEXT;
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS receiver_photo_url TEXT;
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS type TEXT DEFAULT 'text';
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS timestamp BIGINT;

CREATE INDEX IF NOT EXISTS idx_private_messages_conversation_id ON public.private_messages (conversation_id);
CREATE INDEX IF NOT EXISTS idx_private_messages_timestamp ON public.private_messages (timestamp);

-- فك أي تعليق في صلاحيات الرسائل والمحادثات
ALTER TABLE public.private_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'private_messages' AND policyname = 'private_messages_all_access') THEN
    CREATE POLICY "private_messages_all_access" ON public.private_messages FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'conversations' AND policyname = 'conversations_all_access') THEN
    CREATE POLICY "conversations_all_access" ON public.conversations FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
