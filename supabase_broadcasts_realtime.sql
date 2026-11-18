-- ============================================================
-- تفعيل Supabase Realtime على جدول broadcasts
-- ------------------------------------------------------------
-- نص فوز هدية الحظ (واللافتات) يُدرج في broadcasts، لكن الجدول
-- لم يكن مشتركاً في نشر supabase_realtime — فكان كل عميل يعتمد
-- على polling كل 250ms. بعد هذا التفعيل يصل الإدراج لحظياً عبر
-- WebSocket، ويبقى الـ polling احتياطياً فقط.
--
-- شغّل في Supabase Dashboard → SQL Editor.
-- ============================================================

-- إضافة الجدول لنشر Realtime (آمن للتكرار)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'broadcasts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.broadcasts;
  END IF;
END $$;

-- التأكد أن Realtime مفعّل للمشروع (عادة مفعّل افتراضياً)
-- إذا لم تكن الإضافة موجودة فعّلها من Database → Extensions.
