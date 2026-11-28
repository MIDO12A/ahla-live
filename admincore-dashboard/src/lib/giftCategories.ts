import type { GiftCategory } from '../types';

/**
 * الأقسام الأساسية للهدايا — موجودة في التطبيق الأصلي (gift_panel.dart)
 * وتظهر دائماً في اللوحة. الاسم/الترتيب/الظهور قابل للتعديل من صفحة
 * «تصنيفات الهدايا». تُستخدم ك مصدر واحد لكل الصفحات عشان التبويبات
 * بتاعة «إدارة الهدايا» تتطابق مع «تصنيفات الهدايا».
 */
export const CODE_BASE_CATEGORIES: GiftCategory[] = [
  { id: 'general', name: 'عام', sortOrder: 0 },
  { id: 'celebrity', name: 'المشاهير', sortOrder: 1 },
  { id: 'lucky', name: 'الحظ (Lucky)', sortOrder: 2, isLucky: true },
  { id: 'cp', name: 'CP', sortOrder: 3 },
];

/** دمج أقسام الكود مع صفوف قاعدة البيانات (صفوف DB تتفوق في الاسم/الإعدادات). */
export function mergeGiftCategories(rows: GiftCategory[]): GiftCategory[] {
  const map = new Map<string, GiftCategory>();
  CODE_BASE_CATEGORIES.forEach(c => map.set(c.id, c));
  rows.forEach(c => { if (c.id) map.set(c.id, c); });
  return Array.from(map.values())
    .filter(c => c.isActive !== false)
    .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));
}
