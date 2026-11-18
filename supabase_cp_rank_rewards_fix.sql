-- ============================================================
-- cp_rank_rewards — ترحيل للمخطط الجديد (slots/period/reward_type)
-- ------------------------------------------------------------
-- الجدول كان بالمخطط القديم (id/rank/title/reward_coins/...)
-- بينما التطبيق ولوحة التحكم يتوقعان المخطط الجديد
-- (period, rank_position, slot_index, reward_type, labels, urls, is_active).
-- بدون هذا الترحيل: حفظ اللوحة يعطي 400 والمكافآت تختفي.
-- الآمن: الأعمدة القديمة تبقى (لا حذف بيانات).
-- ============================================================

ALTER TABLE public.cp_rank_rewards
  ALTER COLUMN rank DROP NOT NULL;

ALTER TABLE public.cp_rank_rewards
  ADD COLUMN IF NOT EXISTS period        text    NOT NULL DEFAULT 'weekly',
  ADD COLUMN IF NOT EXISTS rank_position integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS slot_index    integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reward_type   text    NOT NULL DEFAULT 'frame_svga',
  ADD COLUMN IF NOT EXISTS label_ar      text    NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS label_en      text    NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS svga_url      text    NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS image_url     text    NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS is_active     boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS updated_at    timestamptz NOT NULL DEFAULT now();

-- index للقراءة حسب الفترة (التطبيق يفلتر period)
CREATE INDEX IF NOT EXISTS idx_cp_rank_rewards_period
  ON public.cp_rank_rewards (period, rank_position, slot_index);
