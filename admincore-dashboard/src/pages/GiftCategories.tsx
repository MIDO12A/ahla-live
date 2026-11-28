import { useEffect, useState, useContext } from 'react';
import { GiftCategory } from '../types';
import { getGiftCategoriesWithError, addGiftCategory, updateGiftCategory, deleteGiftCategory } from '../lib/db';
import { supabase } from '../lib/supabase';
import { Plus, Save, X, Trash2 } from 'lucide-react';
import GiftNavTabs from '../components/GiftNavTabs';
import { I18nContext } from '../lib/i18n';
import { CODE_BASE_CATEGORIES } from '../lib/giftCategories';

export default function GiftCategoriesPage() {
  const [cats, setCats] = useState<GiftCategory[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<GiftCategory | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [form, setForm] = useState({ name: '', sortOrder: 0, isLucky: false, isActive: true });
  const [error, setError] = useState<string | null>(null);
  const { t } = useContext(I18nContext);

  let cancelled = false;
  const load = async () => {
    const { rows, error: err } = await getGiftCategoriesWithError();
    if (!cancelled) {
      // ✅ القائمة تبدأ بالأقسام الأساسية (الكود) — تظهر في اللوحة حتى لو
      //    عاد السيرفر فاضي — أسماؤها قابلة للتعديل (isActive = عرض في التطبيق).
      const serverMap = new Map(rows.map(c => [c.id, c]));
      const seen = new Set(CODE_BASE_CATEGORIES.map(b => b.id));
      const merged = [
        ...CODE_BASE_CATEGORIES.map(b => serverMap.get(b.id) ?? b),
        ...rows.filter(c => !seen.has(c.id) && c.isActive !== false),
      ];
      setCats(merged);
      setError(err ?? null);
      setLoading(false);
    }
  };
  useEffect(() => {
    void load();
    // ✅ أي تغيير على gift_categories من أي مكان (اللوحة أو التطبيق)
    //    يحدّث القائمة فوراً بدل ما نستنى تحديث يدوي للصفحة.
    const channel = supabase
      .channel('gift_categories_admin')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'gift_categories' },
        () => { void load(); },
      )
      .subscribe();
    return () => {
      cancelled = true;
      supabase.removeChannel(channel);
    };
  }, []);

  const resetForm = () => setForm({ name: '', sortOrder: cats.length, isLucky: false, isActive: true });

  const handleEdit = (c: GiftCategory) => {
    setEditing(c);
    setForm({ name: c.name, sortOrder: c.sortOrder, isLucky: c.isLucky ?? false, isActive: c.isActive ?? true });
    setShowAdd(false);
  };

  const handleSave = async () => {
    if (!editing) return;
    const res = await updateGiftCategory(editing.id, form);
    if (!res.ok) {
      setError(`تعذّر حفظ التصنيف: ${res.error}`);
      return;
    }
    setError(null);
    setEditing(null); resetForm();
    load();
  };

  const handleDelete = async (c: GiftCategory) => {
    if (!confirm(`Delete category "${c.name}"?\nGifts using it will be kept but unassigned.`)) return;
    setBusyId(c.id);
    try {
      const result = await deleteGiftCategory(c.id);
      if (!result.ok) {
        alert(`Cannot delete "${c.name}": ${result.error}`);
        return;
      }
      await load();
    } finally {
      setBusyId(null);
    }
  };

  const handleAdd = async () => {
    if (!form.name.trim()) {
      setError('اكتب اسم القسم أولاً.');
      return;
    }
    const id = `cat_${Date.now()}`;
    const res = await addGiftCategory(id, { id, ...form });
    if (!res.ok) {
      setError(`تعذّر إضافة التصنيف: ${res.error}`);
      return;
    }
    setError(null);
    setShowAdd(false); resetForm();
    await load();
  };

  const handleSeedStandard = async () => {
    // ✅ نزرع نفس أقسام صندوق الهدايا الموجودة في كود التطبيق (gift_panel.dart)
    //    عشان اللي يتعدّل هنا ينعكس مباشرة على تبويبات الصندوق داخل الغرفة.
    const standards: GiftCategory[] = CODE_BASE_CATEGORIES;
    for (const sc of standards) {
      const res = await addGiftCategory(sc.id, sc);
      if (!res.ok) {
        setError(`تعذّر إضافة القسم القياسي "${sc.name}": ${res.error}`);
        await load();
        return;
      }
    }
    setError(null);
    await load();
  };

  const updateField = (f: string, v: unknown) => setForm(p => ({ ...p, [f]: v }));

  return (
    <div className="space-y-6">
      <GiftNavTabs />
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-white text-lg font-semibold">Gift Categories</h2>
          <p className="text-slate-500 text-xs mt-0.5">{cats.length} categories</p>
          <p className="text-indigo-300/70 text-[10px] mt-1">هذه تبويبات صندوق الهدايا في التطبيق — غيّر الاسم وسيظهر مباشرة داخل الغرفة.</p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={handleSeedStandard} className="px-3 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1 shadow-md shadow-emerald-900/20">
            🔄 مزامنة أقسام صندوق الهدايا (6 أقسام)
          </button>
          <button onClick={() => { setShowAdd(!showAdd); setEditing(null); resetForm(); }} className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
            <Plus className="w-3.5 h-3.5" /> {showAdd ? 'Cancel' : 'Add Category'}
          </button>
        </div>
      </div>

      {error && (
        <div className="rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-2 text-[11px] text-red-200 flex items-start gap-2">
          <span className="mt-0.5">⚠️</span>
          <span className="flex-1">{error}</span>
          <button onClick={() => void load()} className="underline whitespace-nowrap">إعادة المحاولة</button>
        </div>
      )}

      {(editing || showAdd) && (
        <div className="bg-[#141417] rounded-2xl border border-indigo-500/20 p-6 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-white font-semibold text-sm">{editing ? `Editing: ${editing.name}` : 'New Category'}</h3>
            <button onClick={() => { setEditing(null); setShowAdd(false); }} className="text-slate-400 hover:text-white"><X className="w-4 h-4" /></button>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Name</label>
              <input type="text" value={form.name} onChange={e => updateField('name', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Sort Order</label>
              <input type="number" value={form.sortOrder} onChange={e => updateField('sortOrder', Number(e.target.value))} className="w-20 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
            </div>
          </div>
          <label className="flex items-center gap-2 cursor-pointer select-none">
            <input
              type="checkbox"
              checked={form.isLucky}
              onChange={e => updateField('isLucky', e.target.checked)}
              className="w-4 h-4 accent-amber-500"
            />
            <span className="text-xs text-amber-300 font-semibold">🍀 قسم حظ (Lucky) — الهدايا تحته هدايا محظوظة</span>
          </label>
          <label className="flex items-center gap-2 cursor-pointer select-none">
            <input
              type="checkbox"
              checked={form.isActive}
              onChange={e => updateField('isActive', e.target.checked)}
              className="w-4 h-4 accent-emerald-500"
            />
            <span className="text-xs text-slate-400" title="أقسام صندوق الهدايا الأساسية تظهر دائماً في التطبيق — الخيار يخص الأقسام المضافة فقط">إظهار في التطبيق (للأقسام المضافة)</span>
          </label>
          <div className="flex gap-2">
            <button onClick={editing ? handleSave : handleAdd} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
              <Save className="w-3 h-3" /> {editing ? 'Save Changes' : 'Add Category'}
            </button>
          </div>
        </div>
      )}

      {loading ? (
        <div className="text-center py-12 text-slate-500 text-xs">Loading...</div>
      ) : cats.length === 0 ? (
        <div className="text-center py-12 text-slate-500 text-xs">
          {error ? 'تعذّر تحميل التصنيفات من السيرفر — راجع رسالة الخطأ أعلاه.' : 'No categories yet.'}
        </div>
      ) : (
        <div className="space-y-3">
          {cats.map(c => (
            <div key={c.id} className="bg-[#141417] rounded-2xl border border-white/5 p-4 flex items-center gap-4 hover:border-white/10 transition-colors">
              <div className="flex-1 min-w-0">
                <div className="text-white text-xs font-medium truncate">
                  {c.name}
                  {CODE_BASE_CATEGORIES.some(b => b.id === c.id) && (
                    <span className="text-[9px] text-indigo-400 ms-2">(تبويب صندوق الهدايا)</span>
                  )}
                </div>
                <div className="text-[10px] text-slate-500 mt-1">Order: {c.sortOrder}</div>
              </div>
              <div className="flex items-center gap-2">
                <button onClick={() => handleEdit(c)} className="text-[10px] text-indigo-400 hover:text-indigo-300 font-semibold">Edit</button>
                <button
                  onClick={() => handleDelete(c)}
                  disabled={busyId === c.id}
                  title={busyId === c.id ? 'Deleting...' : 'Delete category'}
                  className="text-[10px] text-rose-400 hover:text-rose-300 font-semibold disabled:opacity-40 disabled:cursor-not-allowed"
                >
                  {busyId === c.id ? '…' : <Trash2 className="w-3 h-3" />}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
