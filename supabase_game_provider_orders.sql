-- =============================================================================
-- Game Provider Idempotency Orders
-- =============================================================================
-- backend/src/routes/games.ts يستخدم هذا الجدول لمنع تسوية نفس الـ orderId مرتين
-- في /change-balance و /make-up-orders.
--
-- ⚠️ لازم تتنفّذ على Supabase قبل تشغيل ربط شركة الألعاب.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.game_provider_orders (
  order_id    text PRIMARY KEY,
  game_id     text,
  round_id    text,
  uid         text,
  coin        bigint,
  type        text,
  reward_type text,
  win_id      text,
  room_id     text,
  direction   text,          -- 'debit' | 'credit'
  makeup      boolean NOT NULL DEFAULT false,
  result      jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS game_provider_orders_uid_idx
  ON public.game_provider_orders (uid, created_at DESC);
CREATE INDEX IF NOT EXISTS game_provider_orders_game_idx
  ON public.game_provider_orders (game_id, created_at DESC);

-- الصلاحيات: الباك إند يستخدم SUPABASE_SERVICE_KEY لو متوفر، وإلا المفتاح العام.
ALTER TABLE public.game_provider_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS game_provider_orders_service ON public.game_provider_orders;
CREATE POLICY game_provider_orders_service ON public.game_provider_orders
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ✅ اترك هذه القاعدة فقط إذا كان الباك إند يعمل بالمفتاح العام (الافتراضي حالياً).
--    لو ضبطت SUPABASE_SERVICE_KEY على Vercel، احذف قاعدة anon دي.
DROP POLICY IF EXISTS game_provider_orders_anon ON public.game_provider_orders;
CREATE POLICY game_provider_orders_anon ON public.game_provider_orders
  FOR ALL TO anon USING (true) WITH CHECK (true);

GRANT SELECT, INSERT ON public.game_provider_orders TO anon, authenticated, service_role;

COMMENT ON TABLE public.game_provider_orders IS
  'StyeParty callback idempotency — order_id فريد، يمنع تسوية الجولة مرتين';
