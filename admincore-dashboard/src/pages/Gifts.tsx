import { useEffect, useState, useContext } from 'react';
import { GiftModel, GiftCategory } from '../types';
import { getGifts, getGiftCategories, deleteGift, updateGift, addGift } from '../lib/db';
import { uploadGiftIcon, uploadGiftAnimation } from '../lib/storage';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import { Plus, Save, X } from 'lucide-react';
import { I18nContext } from '../lib/i18n';

export default function GiftsPage() {
  const [gifts, setGifts] = useState<GiftModel[]>([]);
  const [categories, setCategories] = useState<GiftCategory[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<GiftModel | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [form, setForm] = useState({
    id: '', name: '', value: 0, iconAsset: '', animationAsset: '',
    type: 1, // TODO: Critical fix - Add type field for gift classification (1: normal, 2: VIP, 3: lucky, 4: backpack, 5: CP)
    isVap: false, isLucky: false, isStar: false, isMusic: false,
    packageCount: 0, sortOrder: 0, categoryId: '',
    nameKey: '', photoKey: '', receiverNameKey: '', receiverPhotoKey: '', countKey: '', defaultImage: '',
    isCpGift: false, cpGiftDurationHours: 0,
    luckyRtp: 85, luckyMaxMultiplier: 100, luckyBurst: true, luckyDisplayMode: 'cards',
  });
  const { t } = useContext(I18nContext);

  const STANDARD_CATEGORIES: GiftCategory[] = [
    { id: 'normal', name: 'شائع (عادي)', sortOrder: 1 },
    { id: 'luxury', name: '👑 فاخر (VIP)', sortOrder: 2 },
    { id: 'lucky', name: '🍀 الحظ (Lucky)', sortOrder: 3 },
    { id: 'cp', name: '💍 الارتباط (CP)', sortOrder: 4 },
    { id: 'backpack', name: '🎒 الحقيبة (Backpack)', sortOrder: 5 },
  ];

  const load = async () => {
    const [d, cats] = await Promise.all([getGifts(), getGiftCategories()]);
    const existingIds = new Set(cats.map(c => c.id));
    const mergedCats = [...cats];
    for (const sc of STANDARD_CATEGORIES) {
      if (!existingIds.has(sc.id)) {
        mergedCats.push(sc);
      }
    }
    mergedCats.sort((a, b) => a.sortOrder - b.sortOrder);
    setGifts(d); setCategories(mergedCats); setLoading(false);
  };
  useEffect(() => { load(); }, []);

  const resetForm = () => setForm({ id: '', name: '', value: 0, iconAsset: '', animationAsset: '', type: 1, isVap: false, isLucky: false, isStar: false, isMusic: false, packageCount: 0, sortOrder: 0, categoryId: '', nameKey: '', photoKey: '', receiverNameKey: '', receiverPhotoKey: '', countKey: '', defaultImage: '', isCpGift: false, cpGiftDurationHours: 0, luckyRtp: 85, luckyMaxMultiplier: 100, luckyBurst: true, luckyDisplayMode: 'cards' });

  const handleEdit = (g: GiftModel) => {
    setEditing(g);
    setForm({
      id: g.id,
      name: g.name,
      value: g.value,
      iconAsset: g.iconAsset,
      animationAsset: g.animationAsset || '',
      type: g.type ?? 1,
      isVap: g.isVap,
      isLucky: g.isLucky,
      isStar: g.isStar,
      isMusic: g.isMusic,
      packageCount: g.packageCount,
      sortOrder: g.sortOrder,
      categoryId: g.categoryId || '',
      nameKey: g.nameKey || (g as any).name_key || '',
      photoKey: g.photoKey || (g as any).photo_key || '',
      receiverNameKey: g.receiverNameKey || (g as any).receiver_name_key || '',
      receiverPhotoKey: g.receiverPhotoKey || (g as any).receiver_photo_key || '',
      countKey: g.countKey || (g as any).count_key || '',
      defaultImage: g.defaultImage || (g as any).default_image || '',
      isCpGift: g.isCpGift || false,
      cpGiftDurationHours: g.cpGiftDurationHours || 0,
      luckyRtp: g.luckyRtp ?? 85,
      luckyMaxMultiplier: g.luckyMaxMultiplier ?? 100,
      luckyBurst: g.luckyBurst ?? true,
      luckyDisplayMode: g.luckyDisplayMode ?? 'cards'
    });
    setShowAdd(false);
  };

  const handleSave = async () => {
    if (!editing) return;
    await updateGift(editing.id, {
      ...form,
      categoryId: form.categoryId || null,
      animationAsset: form.animationAsset || null,
      nameKey: form.nameKey || null,
      name_key: form.nameKey || null,
      photoKey: form.photoKey || null,
      photo_key: form.photoKey || null,
      receiverNameKey: form.receiverNameKey || null,
      receiver_name_key: form.receiverNameKey || null,
      receiverPhotoKey: form.receiverPhotoKey || null,
      receiver_photo_key: form.receiverPhotoKey || null,
      countKey: form.countKey || null,
      count_key: form.countKey || null,
      defaultImage: form.defaultImage || null,
      default_image: form.defaultImage || null,
    });
    setEditing(null);
    resetForm();
    load();
  };

  const handleAdd = async () => {
    const id = `gift_${Date.now()}`;
    await addGift(id, {
      ...form,
      id,
      categoryId: form.categoryId || null,
      animationAsset: form.animationAsset || null,
      nameKey: form.nameKey || null,
      name_key: form.nameKey || null,
      photoKey: form.photoKey || null,
      photo_key: form.photoKey || null,
      receiverNameKey: form.receiverNameKey || null,
      receiver_name_key: form.receiverNameKey || null,
      receiverPhotoKey: form.receiverPhotoKey || null,
      receiver_photo_key: form.receiverPhotoKey || null,
      countKey: form.countKey || null,
      count_key: form.countKey || null,
      defaultImage: form.defaultImage || null,
      default_image: form.defaultImage || null,
    });
    setShowAdd(false);
    resetForm();
    load();
  };

  const handleDelete = async (g: GiftModel) => {
    if (confirm(`Delete gift "${g.name}"?`)) await deleteGift(g.id);
    load();
  };

  const updateField = (field: string, value: unknown) => setForm(p => ({ ...p, [field]: value }));

  const handleTypeChange = (typeVal: number) => {
    setForm(prev => {
      let catId = prev.categoryId;
      let isLucky = prev.isLucky;
      let isVap = prev.isVap;
      let isCp = prev.isCpGift;
      if (typeVal === 3) {
        catId = 'lucky';
        isLucky = true;
        isVap = false;
        isCp = false;
      } else if (typeVal === 2) {
        catId = 'luxury';
        isVap = true;
        isLucky = false;
        isCp = false;
      } else if (typeVal === 5) {
        catId = 'cp';
        isCp = true;
        isLucky = false;
        isVap = false;
      } else if (typeVal === 4) {
        catId = 'backpack';
        isLucky = false;
      } else if (typeVal === 1) {
        if (['lucky', 'luxury', 'cp', 'backpack'].includes(catId)) catId = 'normal';
        isLucky = false;
        isVap = false;
        isCp = false;
      }
      return { ...prev, type: typeVal, categoryId: catId, isLucky, isVap, isCpGift: isCp };
    });
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-white text-lg font-semibold">{t('gift.management')}</h2>
          <p className="text-slate-500 text-xs mt-0.5">{gifts.length} {t('gift.count')}</p>
        </div>
        <button onClick={() => { setShowAdd(!showAdd); setEditing(null); resetForm(); }} className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
          <Plus className="w-3.5 h-3.5" /> {showAdd ? t('cancel') : t('gift.add')}
        </button>
      </div>

      {(editing || showAdd) && (
        <div className="bg-[#141417] rounded-2xl border border-indigo-500/20 p-6 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-white font-semibold text-sm">{editing ? `${t('gift.edit')}: ${editing.name}` : t('gift.new')}</h3>
            <button onClick={() => { setEditing(null); setShowAdd(false); }} className="text-slate-400 hover:text-white"><X className="w-4 h-4" /></button>
          </div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <ImageUpload
              currentUrl={form.iconAsset}
              onUpload={file => uploadGiftIcon(file, form.id || `new_${Date.now()}`)}
              onUrlChange={url => updateField('iconAsset', url)}
              label={t('upload')}
            />
            <ImageUpload
              currentUrl={form.animationAsset}
              onUpload={file => uploadGiftAnimation(file, form.id || `new_${Date.now()}`)}
              onUrlChange={url => updateField('animationAsset', url)}
              label="Animation (SVGA)"
              accept=".svga,.json,.zip,.mp4,.vap"
            />
            {(['name', 'value', 'packageCount', 'sortOrder'] as const).map(f => (
              <div key={f}>
                <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{f}</label>
                <input type={['value', 'packageCount', 'sortOrder'].includes(f) ? 'number' : 'text'} value={form[f]} onChange={e => updateField(f, ['value', 'packageCount', 'sortOrder'].includes(f) ? Number(e.target.value) : e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
              </div>
            ))}
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Type (نوع الهدية)</label>
              <select value={form.type ?? 1} onChange={e => handleTypeChange(Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                <option value="1">1: عادي (Normal)</option>
                <option value="2">2: فاخر/VIP (Luxury)</option>
                <option value="3">3: حظ (Lucky)</option>
                <option value="4">4: حقيبة (Backpack)</option>
                <option value="5">5: CP (Couple)</option>
              </select>
            </div>
            <div>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Category (القسم)</label>
              <select value={form.categoryId} onChange={e => {
                const val = e.target.value;
                setForm(prev => {
                  let type = prev.type;
                  let isLucky = prev.isLucky;
                  let isVap = prev.isVap;
                  let isCp = prev.isCpGift;
                  if (val === 'lucky') { type = 3; isLucky = true; isVap = false; isCp = false; }
                  else if (val === 'luxury') { type = 2; isVap = true; isLucky = false; isCp = false; }
                  else if (val === 'cp') { type = 5; isCp = true; isLucky = false; isVap = false; }
                  else if (val === 'backpack') { type = 4; isLucky = false; }
                  else if (val === 'normal') { type = 1; isLucky = false; isVap = false; isCp = false; }
                  return { ...prev, categoryId: val, type, isLucky, isVap, isCpGift: isCp };
                });
              }} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                <option value="">-- No category --</option>
                {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </div>
            {form.animationAsset && (
              <>
                <div className="col-span-1 md:col-span-2 bg-white/5 p-2.5 rounded-xl border border-white/10 space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold text-amber-400">🔑 مفاتيح الطبقات الديناميكية (Dynamic SVGA / VAP Keys)</span>
                    <span className="text-[10px] text-slate-400">يمكن وضع مفتاح واحد أو عدة مفاتيح مفصولة بفواصل (e.g. key1, key2)</span>
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2">
                    <div>
                      <label className="block text-[10px] uppercase text-slate-300 font-bold mb-1">مفتاح اسم المرسل (Sender Name)</label>
                      <input type="text" value={form.nameKey} onChange={e => updateField('nameKey', e.target.value)} placeholder="e.g. txt_name, name, sender_name" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                    </div>
                    <div>
                      <label className="block text-[10px] uppercase text-slate-300 font-bold mb-1">مفتاح صورة المرسل (Sender Avatar)</label>
                      <input type="text" value={form.photoKey} onChange={e => updateField('photoKey', e.target.value)} placeholder="e.g. img_avatar, avatar, user_avatar" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                    </div>
                    <div>
                      <label className="block text-[10px] uppercase text-slate-300 font-bold mb-1">مفتاح اسم المستلم (Receiver Name)</label>
                      <input type="text" value={form.receiverNameKey} onChange={e => updateField('receiverNameKey', e.target.value)} placeholder="e.g. receiver_name, target_name" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                    </div>
                    <div>
                      <label className="block text-[10px] uppercase text-slate-300 font-bold mb-1">مفتاح صورة المستلم (Receiver Avatar)</label>
                      <input type="text" value={form.receiverPhotoKey} onChange={e => updateField('receiverPhotoKey', e.target.value)} placeholder="e.g. receiver_avatar, target_avatar" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                    </div>
                    <div>
                      <label className="block text-[10px] uppercase text-slate-300 font-bold mb-1">مفتاح عدد الهدية (Gift Count)</label>
                      <input type="text" value={form.countKey} onChange={e => updateField('countKey', e.target.value)} placeholder="e.g. gift_count, count" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" />
                    </div>
                    <div>
                      <label className="block text-[10px] uppercase text-slate-300 font-bold mb-1">صورة احتياطية (Default Image URL)</label>
                      <input type="text" value={form.defaultImage} onChange={e => updateField('defaultImage', e.target.value)} placeholder="Fallback if user has no photo" className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                    </div>
                  </div>
                </div>
              </>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-4 pt-2 border-t border-white/5">
            <label className={`flex items-center gap-2 px-3 py-1.5 rounded-lg border text-xs font-bold transition-all cursor-pointer ${form.isLucky ? 'bg-emerald-500/20 border-emerald-500/50 text-emerald-300' : 'bg-white/5 border-white/10 text-slate-400 hover:text-white'}`}>
              <input type="checkbox" checked={form.isLucky} onChange={e => {
                const chk = e.target.checked;
                handleTypeChange(chk ? 3 : 1);
              }} className="accent-emerald-500 w-4 h-4" />
              <span>🍀 هدية حظ (Lucky Gift)</span>
            </label>

            {form.isLucky && (
              <div className="w-full bg-emerald-950/30 border border-emerald-500/30 rounded-xl p-3.5 space-y-2 mt-2">
                <div className="flex items-center justify-between text-xs font-bold text-emerald-400">
                  <span>⚙️ إعدادات نسب أرباح ومضاعفات هدية الحظ</span>
                  <span className="text-[10px] bg-emerald-500/20 px-2 py-0.5 rounded text-emerald-300">مربوطة تلقائياً بسستم الحظ</span>
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
                  <div>
                    <label className="block text-[10px] text-slate-400 font-bold mb-1">نسبة العائد (RTP %)</label>
                    <input type="number" min={50} max={100} placeholder="85" value={form.luckyRtp ?? 85} onChange={e => updateField('luckyRtp', Number(e.target.value))} className="w-full bg-[#121214] border border-emerald-500/30 rounded-lg p-1.5 text-xs text-emerald-300 font-bold" />
                  </div>
                  <div>
                    <label className="block text-[10px] text-slate-400 font-bold mb-1">أعلى مضاعف (Max Mult)</label>
                    <select value={form.luckyMaxMultiplier ?? 100} onChange={e => updateField('luckyMaxMultiplier', Number(e.target.value))} className="w-full bg-[#121214] border border-emerald-500/30 rounded-lg p-1.5 text-xs text-emerald-300 font-bold">
                      <option value="100">100X (محافظ)</option>
                      <option value="250">250X (متوسط)</option>
                      <option value="500">500X (قوي)</option>
                      <option value="1000">1000X (أسطوري)</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[10px] text-slate-400 font-bold mb-1">انفجار الحظ (Burst)</label>
                    <select value={form.luckyBurst === false ? 'false' : 'true'} onChange={e => updateField('luckyBurst', e.target.value === 'true')} className="w-full bg-[#121214] border border-emerald-500/30 rounded-lg p-1.5 text-xs text-emerald-300 font-bold">
                      <option value="true">مفعل (Auto Burst)</option>
                      <option value="false">معطل</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[10px] text-slate-400 font-bold mb-1">طريقة العرض في الروم</label>
                    <select value={form.luckyDisplayMode ?? 'cards'} onChange={e => updateField('luckyDisplayMode', e.target.value)} className="w-full bg-[#121214] border border-emerald-500/30 rounded-lg p-1.5 text-xs text-emerald-300 font-bold">
                      <option value="cards">كروت 3D + SVGA + بانر</option>
                      <option value="svga">SVGA فقط</option>
                    </select>
                  </div>
                </div>
              </div>
            )}

            <label className={`flex items-center gap-2 px-3 py-1.5 rounded-lg border text-xs font-bold transition-all cursor-pointer ${form.isVap ? 'bg-purple-500/20 border-purple-500/50 text-purple-300' : 'bg-white/5 border-white/10 text-slate-400 hover:text-white'}`}>
              <input type="checkbox" checked={form.isVap} onChange={e => {
                const chk = e.target.checked;
                handleTypeChange(chk ? 2 : 1);
              }} className="accent-purple-500 w-4 h-4" />
              <span>🎬 تأثير VAP (Alpha MP4)</span>
            </label>

            {(['isStar', 'isMusic'] as const).map(f => (
              <label key={f} className="flex items-center gap-1.5 text-xs text-slate-400 cursor-pointer">
                <input type="checkbox" checked={form[f]} onChange={e => updateField(f, e.target.checked)} className="accent-indigo-500" />
                {f === 'isStar' ? '⭐ مميزة' : '🎵 صوتية'}
              </label>
            ))}

            <label className="flex items-center gap-1.5 text-xs text-rose-400 font-semibold cursor-pointer">
              <input type="checkbox" checked={form.isCpGift} onChange={e => {
                const chk = e.target.checked;
                handleTypeChange(chk ? 5 : 1);
              }} className="accent-rose-500" />
              CP Gift
            </label>
            {form.isCpGift && (
              <div className="flex items-center gap-1.5">
                <label className="text-[10px] uppercase text-slate-400 font-bold">Duration (hrs)</label>
                <input type="number" min={0} value={form.cpGiftDurationHours} onChange={e => updateField('cpGiftDurationHours', Number(e.target.value))} className="w-20 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
              </div>
            )}
          </div>
          <div className="flex gap-2">
            <button onClick={editing ? handleSave : handleAdd} className="px-5 py-2 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-bold rounded-lg flex items-center gap-1.5 shadow-lg shadow-emerald-900/30">
              <Save className="w-3.5 h-3.5" /> {editing ? t('save') : t('gift.add')}
            </button>
          </div>
        </div>
      )}

      <DataTable
        loading={loading}
        columns={[
          { key: 'iconAsset', label: '', width: '40px', render: g => g.iconAsset ? <img src={g.iconAsset} className="w-6 h-6 object-contain" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} /> : <div className="w-6 h-6 rounded bg-slate-800" /> },
          { key: 'name', label: t('gift.name'), sortable: true },
          { key: 'categoryId', label: 'Category', render: g => { const cat = categories.find(c => c.id === g.categoryId); return <span className="text-[10px] text-slate-400">{cat ? cat.name : '-'}</span>; } },
          { key: 'value', label: t('gift.value'), sortable: true, render: g => <span className="text-amber-400 font-mono">{g.value}</span> },
          { key: 'isLucky', label: '🍀 الحظ', render: g => g.isLucky ? <span className="px-1.5 py-0.5 rounded bg-emerald-500/20 text-emerald-300 font-bold text-[10px]">🍀 حظ</span> : '-' },
          { key: 'isVap', label: 'VAP', render: g => g.isVap ? <span className="px-1.5 py-0.5 rounded bg-purple-500/20 text-purple-300 font-bold text-[10px]">VAP</span> : '-' },
          { key: 'isStar', label: '☆', render: g => g.isStar ? <span className="text-amber-400">✓</span> : '-' },
          { key: 'isMusic', label: '♪', render: g => g.isMusic ? <span className="text-emerald-400">✓</span> : '-' },
          { key: 'isCpGift', label: 'CP', render: g => g.isCpGift ? <span className="text-rose-400 font-semibold">♥ {g.cpGiftDurationHours ? `${Math.round(g.cpGiftDurationHours / 24)}d` : ''}</span> : '-' },
          { key: 'sortOrder', label: 'Order', sortable: true },
        ]}
        data={gifts}
        searchKeys={['name', 'id']}
        onEdit={handleEdit}
        onDelete={handleDelete}
      />
    </div>
  );
}
