import { useEffect, useState, useContext } from 'react';
import { BannerKeyBinding, GiftBannerConfig, GiftCategory } from '../types';
import { getGiftBannerConfigs, addGiftBannerConfig, updateGiftBannerConfig, deleteGiftBannerConfig, getGiftCategories } from '../lib/db';
import { uploadGiftBannerSvga } from '../lib/storage';
import ImageUpload from '../components/ImageUpload';
import GiftNavTabs from '../components/GiftNavTabs';
import { Plus, Save, X, Trash2 } from 'lucide-react';
import { I18nContext } from '../lib/i18n';

// مصادر البيانات التي يمكن حقنها في أي مفتاح داخل ملف اللافتة
const KEY_SOURCES: { value: string; label: string; kind: 'image' | 'text' | 'any' }[] = [
  { value: 'sender_photo', label: 'صورة المرسل (أفاتار)', kind: 'image' },
  { value: 'receiver_photo', label: 'صورة المستلم / الفائز (أفاتار)', kind: 'image' },
  { value: 'gift_icon', label: 'أيقونة الهدية', kind: 'image' },
  { value: 'gift_count', label: 'عدد الهدايا (×N)', kind: 'text' },
  { value: 'sender_name', label: 'اسم المرسل', kind: 'text' },
  { value: 'gift_name', label: 'اسم الهدية', kind: 'text' },
  { value: 'multiplier', label: 'المضاعف رقم بس (10)', kind: 'text' },
  { value: 'multiplier_x', label: 'المضاعف مع X (10X)', kind: 'text' },
  { value: 'total_coins', label: 'الإجمالي / التكلفة 🪙', kind: 'text' },
  { value: 'won_coins', label: 'الربح / الفوز 🪙 (الحظ)', kind: 'text' },
  { value: 'room_name', label: 'اسم الغرفة', kind: 'text' },
  { value: 'content', label: 'نص البث كامل', kind: 'text' },
  { value: 'custom', label: 'نص ثابت مخصص ✏️', kind: 'any' },
];

const DEFAULT_KEY_MAP: BannerKeyBinding[] = [
  { key: 'user_r', type: 'image', source: 'sender_photo' },
  { key: 'user_l', type: 'image', source: 'receiver_photo' },
  { key: 'number', type: 'text', source: 'gift_count' },
  { key: 'gift', type: 'image', source: 'gift_icon' },
];

function keyMapFromConfig(c: GiftBannerConfig): BannerKeyBinding[] {
  if (c.keyMap && c.keyMap.length > 0) return c.keyMap.map(k => ({ ...k }));
  // توافق رجعي: نبني الخريطة من الأعمدة القديمة إن لم توجد key_map
  return [
    { key: c.userRKey || 'user_r', type: 'image', source: 'sender_photo' },
    { key: c.userLKey || 'user_l', type: 'image', source: 'receiver_photo' },
    { key: c.numberKey || 'number', type: 'text', source: 'gift_count' },
    { key: c.giftKey || 'gift', type: 'image', source: 'gift_icon' },
  ];
}

// اشتقاق الأعمدة القديمة من الخريطة حتى تبقى متوافقة مع إصدارات التطبيق القديمة
function deriveLegacyKeys(km: BannerKeyBinding[]) {
  const find = (src: string) => km.find(k => k.source === src)?.key || '';
  return {
    userRKey: find('sender_photo') || 'user_r',
    userLKey: find('receiver_photo') || 'user_l',
    numberKey: find('gift_count') || 'number',
    giftKey: find('gift_icon') || 'gift',
  };
}

export default function GiftBannerConfigsPage() {
  const [configs, setConfigs] = useState<GiftBannerConfig[]>([]);
  const [categories, setCategories] = useState<GiftCategory[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<GiftBannerConfig | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [form, setForm] = useState({
    categoryId: '', thresholdCoins: 0, svgaUrl: '', bannerType: '',
    keyMap: [] as BannerKeyBinding[],
    isActive: true,
  });
  const { t } = useContext(I18nContext);

  const load = async () => {
    const [d, cats] = await Promise.all([getGiftBannerConfigs(), getGiftCategories()]);
    setConfigs(d); setCategories(cats); setLoading(false);
  };
  useEffect(() => { load(); }, []);

  const resetForm = () => setForm({
    categoryId: '', thresholdCoins: 0, svgaUrl: '', bannerType: '',
    keyMap: DEFAULT_KEY_MAP.map(k => ({ ...k })),
    isActive: true,
  });

  const handleEdit = (c: GiftBannerConfig) => {
    setEditing(c);
    setForm({
      categoryId: c.categoryId || '', thresholdCoins: c.thresholdCoins, svgaUrl: c.svgaUrl,
      bannerType: c.bannerType || '',
      keyMap: keyMapFromConfig(c),
      isActive: c.isActive,
    });
    setShowAdd(false);
  };

  const buildPayload = () => {
    const rawCat = form.categoryId?.trim();
    return {
      ...form,
      categoryId: rawCat ? rawCat : null,
      ...deriveLegacyKeys(form.keyMap),
    };
  };

  const handleSave = async () => {
    if (!editing) return;
    try {
      await updateGiftBannerConfig(editing.id, buildPayload());
      setEditing(null); resetForm();
      load();
    } catch (e) {
      alert(`Save failed: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const handleDelete = async (c: GiftBannerConfig) => {
    if (confirm(`Delete banner config "${c.id}"?`)) {
      try {
        await deleteGiftBannerConfig(c.id);
        load();
      } catch (e) {
        alert(`Delete failed: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
  };

  const handleAdd = async () => {
    const id = `gbc_${Date.now()}`;
    try {
      await addGiftBannerConfig(id, { id, ...buildPayload() });
      setShowAdd(false); resetForm();
      load();
    } catch (e) {
      alert(`Add failed: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const updateField = (f: string, v: unknown) => setForm(p => ({ ...p, [f]: v }));

  const updateKey = (i: number, patch: Partial<BannerKeyBinding>) =>
    setForm(p => ({
      ...p,
      keyMap: p.keyMap.map((k, idx) => (idx === i ? { ...k, ...patch } : k)),
    }));

  const removeKey = (i: number) =>
    setForm(p => ({ ...p, keyMap: p.keyMap.filter((_, idx) => idx !== i) }));

  const addKey = () =>
    setForm(p => ({
      ...p,
      keyMap: [...p.keyMap, { key: '', type: 'text', source: 'content' }],
    }));

  return (
    <div className="space-y-6">
      <GiftNavTabs />
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-white text-lg font-semibold">Gift Banner Configs (SVGA Strip)</h2>
          <p className="text-slate-500 text-xs mt-0.5">{configs.length} banner configs</p>
        </div>
        <button onClick={() => { setShowAdd(!showAdd); setEditing(null); resetForm(); }} className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
          <Plus className="w-3.5 h-3.5" /> {showAdd ? 'Cancel' : 'Add Config'}
        </button>
      </div>

      {(editing || showAdd) && (
        <div className="bg-[#141417] rounded-2xl border border-indigo-500/20 p-6 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-white font-semibold text-sm">{editing ? `Editing: ${editing.id}` : 'New Banner Config'}</h3>
            <button onClick={() => { setEditing(null); setShowAdd(false); }} className="text-slate-400 hover:text-white"><X className="w-4 h-4" /></button>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Gift Category</label>
              <select value={form.categoryId || ''} onChange={e => updateField('categoryId', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                <option value="">All Categories (عام لكافة الهدايا)</option>
                {categories.map(cat => (
                  <option key={cat.id} value={cat.id}>{cat.name}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Threshold Coins</label>
              <input type="number" value={form.thresholdCoins} onChange={e => updateField('thresholdCoins', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
              <p className="text-[9px] text-slate-600 mt-1">لكل التصنيفات: الحد الأدنى لتكلفة الهدية — لهدية الحظ: الحد الأدنى للكوينز المربوحة</p>
            </div>
            <div className="flex items-end">
              <label className="flex items-center gap-1.5 text-xs text-slate-400 pb-1.5">
                <input type="checkbox" checked={form.isActive} onChange={e => updateField('isActive', e.target.checked)} className="accent-indigo-500" />
                Active
              </label>
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Banner Type (نوع اللافتة)</label>
              <select value={form.bannerType} onChange={e => updateField('bannerType', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                <option value="">تلقائي (Auto — من امتداد الملف)</option>
                <option value="svga">SVGA — أنيميشن بمفاتيح</option>
                <option value="vap">VAP — فيديو شفاف بمفاتيح</option>
                <option value="mp4">MP4 — فيديو بمفاتيح</option>
                <option value="png">PNG — صورة ثابتة (بدون مفاتيح)</option>
                <option value="webp">WEBP — صورة ثابتة (بدون مفاتيح)</option>
              </select>
            </div>
            <ImageUpload
              currentUrl={form.svgaUrl}
              onUpload={file => uploadGiftBannerSvga(file, editing?.id || `new_${Date.now()}`)}
              onUrlChange={url => updateField('svgaUrl', url)}
              label="Banner File (SVGA/VAP/MP4/PNG/WEBP)"
              accept=".svga,.vap,.mp4,.png,.webp,.gif,.jpg,.jpeg,.json,.zip"
            />
          </div>

          {/* ═══ محرر المفاتيح الديناميكي ═══ */}
          <div className="rounded-xl border border-white/10 bg-black/20 p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div>
                <h4 className="text-white text-xs font-semibold">🔑 مفاتيح اللافتة (Banner Keys)</h4>
                <p className="text-[10px] text-slate-500 mt-0.5">
                  عرّف أي مفتاح موجود في ملف الأنيميشن — اختر نوعه (صورة/نص) ومصدر بياناته. للصور تُحقن روابط الصور، وللنصوص تُحقن القيم النصية.
                </p>
              </div>
              <button onClick={addKey} className="px-2.5 py-1 bg-indigo-600/80 hover:bg-indigo-600 text-[10px] text-white font-semibold rounded-lg flex items-center gap-1 shrink-0">
                <Plus className="w-3 h-3" /> إضافة مفتاح
              </button>
            </div>

            {form.keyMap.length === 0 && (
              <p className="text-[10px] text-slate-600 text-center py-2">لا توجد مفاتيح — أضف أول مفتاح لملف اللافتة</p>
            )}

            <div className="space-y-2">
              {form.keyMap.map((k, i) => {
                const src = KEY_SOURCES.find(s => s.value === k.source);
                return (
                  <div key={i} className="grid grid-cols-12 gap-2 items-center">
                    <input
                      type="text"
                      value={k.key}
                      onChange={e => updateKey(i, { key: e.target.value })}
                      placeholder="key_name"
                      className="col-span-3 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono"
                    />
                    <select
                      value={k.type}
                      onChange={e => updateKey(i, { type: e.target.value })}
                      className="col-span-2 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                    >
                      <option value="image">🖼️ صورة</option>
                      <option value="text">🔤 نص</option>
                    </select>
                    <select
                      value={k.source}
                      onChange={e => updateKey(i, { source: e.target.value })}
                      className="col-span-4 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                    >
                      {KEY_SOURCES.map(s => (
                        <option key={s.value} value={s.value}>{s.label}</option>
                      ))}
                    </select>
                    <button
                      onClick={() => removeKey(i)}
                      className="col-span-1 text-rose-400 hover:text-rose-300 flex justify-center"
                      title="حذف المفتاح"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                    {k.source === 'custom' && (
                      <input
                        type="text"
                        value={k.value || ''}
                        onChange={e => updateKey(i, { value: e.target.value })}
                        placeholder="القيمة الثابتة (نص)..."
                        className="col-span-12 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                      />
                    )}
                    {src && src.kind !== 'any' && k.type !== src.kind && k.source !== 'custom' && (
                      <p className="col-span-12 text-[9px] text-amber-500/80 -mt-1">
                        ⚠️ هذا المصدر {src.kind === 'image' ? 'صورة' : 'نص'} — سيُعامل المفتاح كـ {k.type === 'image' ? 'صورة' : 'نص'} حسب اختيارك
                      </p>
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          <div className="flex gap-2">
            <button onClick={editing ? handleSave : handleAdd} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
              <Save className="w-3 h-3" /> {editing ? 'Save Changes' : 'Add Config'}
            </button>
          </div>
        </div>
      )}

      {loading ? (
        <div className="text-center py-12 text-slate-500 text-xs">Loading...</div>
      ) : configs.length === 0 ? (
        <div className="text-center py-12 text-slate-500 text-xs">No banner configs yet.</div>
      ) : (
        <div className="space-y-3">
          {configs.map(c => (
            <div key={c.id} className="bg-[#141417] rounded-2xl border border-white/5 p-4 flex items-center gap-4 hover:border-white/10 transition-colors">
              {c.svgaUrl ? (
                <div className="w-24 h-14 rounded-lg bg-gradient-to-br from-indigo-500/20 to-purple-500/20 border border-indigo-500/30 flex items-center justify-center text-[10px] text-indigo-400">SVGA</div>
              ) : (
                <div className="w-24 h-14 rounded-lg bg-slate-800 flex items-center justify-center text-[10px] text-slate-600">No File</div>
              )}
              <div className="flex-1 min-w-0">
                  <div className="text-white text-xs font-medium truncate">{c.id}</div>
                  <div className="text-[10px] text-slate-500 mt-1">
                    {c.categoryId ? (
                      <span className="text-indigo-400 font-mono">
                        {c.categoryId === 'lucky_bag' ? '🧧 حقيبة الحظ (Lucky Bag)' :
                         c.categoryId === 'lucky_gift' ? '🍀 هدية الحظ (Lucky Gift)' :
                         c.categoryId === 'lucky' ? '🍀 الحظ عام (Lucky)' :
                         (categories.find(cat => cat.id === c.categoryId)?.name || c.categoryId)}
                      </span>
                    ) : <span className="text-slate-500">All Categories (عام)</span>}
                    <span className="mx-1.5">·</span>
                    Threshold: <span className="text-amber-400 font-mono">{c.thresholdCoins}</span> coins
                    <span className={`ml-2 text-[9px] px-1.5 py-0.5 rounded-full ${c.isActive ? 'bg-emerald-500/10 text-emerald-400' : 'bg-slate-500/10 text-slate-500'}`}>{c.isActive ? 'Active' : 'Inactive'}</span>
                  </div>
                  <div className="text-[9px] text-slate-600 mt-0.5">
                    Keys: {(c.keyMap && c.keyMap.length > 0
                      ? c.keyMap.map(k => `${k.key}←${k.source}`).join(', ')
                      : `${c.userRKey}, ${c.userLKey}, ${c.numberKey}, ${c.giftKey}`)}
                  </div>
              </div>
              <div className="flex items-center gap-2">
                <button onClick={() => handleEdit(c)} className="text-[10px] text-indigo-400 hover:text-indigo-300 font-semibold">Edit</button>
                <button onClick={() => handleDelete(c)} className="text-[10px] text-rose-400 hover:text-rose-300 font-semibold"><Trash2 className="w-3 h-3" /></button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
