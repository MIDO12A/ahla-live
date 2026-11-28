import { useEffect, useState, useContext } from 'react';
import { GiftModel, GiftCategory } from '../types';
import { getGifts, getGiftCategories, deleteGift, updateGift, addGift } from '../lib/db';
import { uploadGiftIcon, uploadGiftAnimation } from '../lib/storage';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import { Plus, Save, X, Sparkles, Gift, Tag } from 'lucide-react';
import { Link } from 'react-router-dom';
import GiftNavTabs from '../components/GiftNavTabs';
import { I18nContext } from '../lib/i18n';
import { mergeGiftCategories } from '../lib/giftCategories';

export default function GiftsPage() {
  const [gifts, setGifts] = useState<GiftModel[]>([]);
  const [categories, setCategories] = useState<GiftCategory[]>([]);
  // نحتفظ بالتبويب الأخير أثناء التنقل بين الأقسام عشان الرجوع لصفحة الهدايا
  // ما يرجّعكش دايماً لتبويب «الكل».
  const [activeTab, setActiveTab] = useState<string>(
    () => sessionStorage.getItem('admin_gifts_active_tab') || 'all',
  );
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<GiftModel | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [form, setForm] = useState({
    id: '', name: '', value: 0, iconAsset: '', animationAsset: '',
    type: 1, // (1: normal, 2: VIP, 3: lucky, 4: backpack, 5: CP)
    isVap: false, isLucky: false, isStar: false, isMusic: false,
    packageCount: 0, sortOrder: 0, categoryId: '',
    nameKey: '', photoKey: '', receiverNameKey: '', receiverPhotoKey: '', countKey: '', defaultImage: '',
    isCpGift: false, cpGiftDurationHours: 0,
    luckyRtp: 85, luckyMaxMultiplier: 100, luckyBurst: true, luckyDisplayMode: 'cards',
  });
  const { t } = useContext(I18nContext);

  useEffect(() => {
    sessionStorage.setItem('admin_gifts_active_tab', activeTab);
  }, [activeTab]);

  const load = async () => {
    const [d, cats] = await Promise.all([getGifts(), getGiftCategories()]);
    // ✅ نفس مصدر تصنيفات صفحة «تصنيفات الهدايا» — الأقسام الأساسية تظهر
    //    هنا أيضاً في التبويبات وقائمة اختيار التصنيف عند إضافة هدية.
    //    صفوف قاعدة البيانات تتفوق في الاسم/الترتيب/الظهور (isActive).
    const mergedCats = mergeGiftCategories(cats);
    setActiveTab(prev =>
      prev !== 'all' && !mergedCats.some(c => c.id === prev) ? 'all' : prev,
    );
    setGifts(d); setCategories(mergedCats); setLoading(false);
  };
  useEffect(() => { load(); }, []);

  const resetForm = (targetCatId?: string) => {
    const cat = targetCatId || (activeTab !== 'all' ? activeTab : 'general');
    let type = 1;
    let isLucky = false;
    let isVap = false;
    let isCp = false;
    if (isLuckyCategoryId(cat)) { type = 3; isLucky = true; }
    else if (cat === 'luxury' || cat === 'celebrity') { type = 2; isVap = true; }
    else if (cat === 'cp') { type = 5; isCp = true; }
    else if (cat === 'backpack') { type = 4; }

    setForm({
      id: '', name: '', value: 0, iconAsset: '', animationAsset: '',
      type,
      isVap,
      isLucky,
      isStar: false,
      isMusic: false,
      packageCount: 0,
      sortOrder: 0,
      categoryId: cat,
      nameKey: '', photoKey: '', receiverNameKey: '', receiverPhotoKey: '', countKey: '', defaultImage: '',
      isCpGift: isCp,
      cpGiftDurationHours: 0,
      luckyRtp: 85, luckyMaxMultiplier: 100, luckyBurst: true, luckyDisplayMode: 'cards'
    });
  };

  const handleEdit = (g: GiftModel) => {
    setEditing(g);
    setForm({
      id: g.id,
      name: g.name,
      value: g.value,
      iconAsset: g.iconAsset,
      animationAsset: g.animationAsset || '',
      type: (g as any).type ?? 1,
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
    const savedCat = form.categoryId || (form.isLucky ? 'lucky' : 'all');
    setEditing(null);
    setActiveTab(savedCat);
    resetForm(savedCat === 'all' ? undefined : savedCat);
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
    const savedCat = form.categoryId || (form.isLucky ? 'lucky' : 'all');
    setShowAdd(false);
    setActiveTab(savedCat);
    resetForm(savedCat === 'all' ? undefined : savedCat);
    load();
  };

  const handleDelete = async (g: GiftModel) => {
    if (confirm(`Delete gift "${g.name}"?`)) await deleteGift(g.id);
    load();
  };

  const updateField = (field: string, value: unknown) => setForm(p => ({ ...p, [field]: value }));

  // ✅ التصنيف المعتمد هو category_id من جدول gift_categories —
  //    والـ type الرقمي (1-5) قيمة قديمة للأنواع القياسية فقط.
  const catIdForType = (t?: number) =>
    t === 3 ? 'lucky' : t === 2 ? 'celebrity' : t === 5 ? 'cp' : t === 4 ? 'backpack' : 'general';

  // ✅ القسم «حظ» = التصنيف القياسي lucky أو أي تصنيف مخصص معلّم isLucky
  //    من صفحة Gift Categories — كده اختيار أي قسم حظ بيحافظ على نوع الهدية.
  const isLuckyCategoryId = (catId?: string | null) => {
    if (!catId) return false;
    if (catId === 'lucky') return true;
    return categories.find(c => c.id === catId)?.isLucky === true;
  };

  const giftMatchesTab = (g: GiftModel, cat: GiftCategory): boolean => {
    const gType = (g as any).type;
    if (cat.isLucky || cat.id === 'lucky') {
      return g.isLucky || gType === 3 || g.categoryId === cat.id || g.categoryId === 'lucky';
    }
    if (cat.id === 'celebrity' || cat.id === 'luxury') {
      return !g.isLucky && (g.categoryId === 'celebrity' || g.categoryId === 'luxury' || gType === 2 || g.categoryId === cat.id);
    }
    if (cat.id === 'cp') return !g.isLucky && (g.isCpGift || g.categoryId === 'cp' || gType === 5 || g.categoryId === cat.id);
    if (cat.id === 'backpack') return !g.isLucky && (g.categoryId === 'backpack' || gType === 4 || g.categoryId === cat.id);
    if (cat.id === 'general' || cat.id === 'normal') {
      if (g.isLucky || g.isCpGift || gType === 2 || gType === 3 || gType === 4 || gType === 5) return false;
      return g.categoryId === 'general' || g.categoryId === 'normal' || g.categoryId === cat.id || !g.categoryId || gType === 1 || !gType;
    }
    return g.categoryId === cat.id;
  };

  const applyCategoryId = (catId: string) => {
    setForm(prev => {
      let type = 1;
      let isLucky = false;
      let isVap = false;
      let isCp = false;
      if (isLuckyCategoryId(catId)) { type = 3; isLucky = true; }
      else if (catId === 'celebrity' || catId === 'luxury') { type = 2; isVap = true; }
      else if (catId === 'cp') { type = 5; isCp = true; }
      else if (catId === 'backpack') { type = 4; }
      return { ...prev, categoryId: catId, type, isLucky, isVap, isCpGift: isCp };
    });
  };

  return (
    <div className="space-y-6">
      <GiftNavTabs />
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
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">القسم / التاب (Category / Tab)</label>
              <select value={form.categoryId || catIdForType(form.type)} onChange={e => applyCategoryId(e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                <option value="">-- بدون قسم (عام) --</option>
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
                // ✅ الهدية الحظ لازم تروح لقسم lucky عشان تظهر في تاب الحظ
                //    في اللوحة وفي التطبيق — كان بيغيّر نوعها بس والقسم يفضل
                //    «عام» فالتاب بيفضي ويرجع لأول تاب.
                const chk = e.target.checked;
                setForm(prev => ({
                  ...prev,
                  isLucky: chk,
                  type: chk ? 3 : (prev.type === 3 ? 1 : prev.type),
                  categoryId: chk
                    ? 'lucky'
                    : (prev.categoryId === 'lucky' ? 'general' : prev.categoryId),
                }));
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
                setForm(prev => ({
                  ...prev,
                  isVap: chk,
                  type: chk ? 2 : (prev.type === 2 ? 1 : prev.type),
                }));
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
                setForm(prev => ({
                  ...prev,
                  isCpGift: chk,
                  type: chk ? 5 : (prev.type === 5 ? 1 : prev.type),
                }));
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

      {/* Individual Category Tabs / الأقسام الفردية للهدايا */}
      <div className="flex flex-wrap items-center gap-1.5 bg-[#141417] p-2 rounded-2xl border border-white/5">
        <button
          onClick={() => setActiveTab('all')}
          className={`px-3.5 py-1.5 rounded-xl text-xs font-semibold transition-all flex items-center gap-1.5 ${
            activeTab === 'all'
              ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
              : 'bg-white/5 text-slate-400 hover:text-white hover:bg-white/10'
          }`}
        >
          <span>الكل (جميع الهدايا)</span>
          <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-black/30 font-mono">
            {gifts.length}
          </span>
        </button>

        {categories.map(cat => {
          const isActive = activeTab === cat.id;
          const count = gifts.filter(g => giftMatchesTab(g, cat)).length;

          return (
            <button
              key={cat.id}
              onClick={() => setActiveTab(cat.id)}
              className={`px-3.5 py-1.5 rounded-xl text-xs font-semibold transition-all flex items-center gap-1.5 ${
                isActive
                  ? cat.isLucky || cat.id === 'lucky'
                    ? 'bg-emerald-600 text-white shadow-md shadow-emerald-600/30'
                    : cat.id === 'cp'
                    ? 'bg-rose-600 text-white shadow-md shadow-rose-600/30'
                    : cat.id === 'luxury'
                    ? 'bg-amber-600 text-white shadow-md shadow-amber-600/30'
                    : 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'bg-white/5 text-slate-400 hover:text-white hover:bg-white/10'
              }`}
            >
              <span>{cat.name}</span>
              <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-black/30 font-mono">
                {count}
              </span>
            </button>
          );
        })}
        <Link
          to="/gift-categories"
          className="px-3 py-1.5 rounded-xl text-xs font-semibold bg-indigo-500/10 text-indigo-400 hover:bg-indigo-500/20 hover:text-indigo-300 border border-indigo-500/20 transition-all flex items-center gap-1.5 ml-auto"
          title="إدارة وتعديل وإضافة تصنيفات وأقسام الهدايا"
        >
          <Tag className="w-3.5 h-3.5" />
          <span>إدارة التصنيفات</span>
        </Link>
      </div>

      <DataTable
        loading={loading}
        columns={[
          { key: 'iconAsset', label: '', width: '40px', render: g => g.iconAsset ? <img src={g.iconAsset} className="w-6 h-6 object-contain" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} /> : <div className="w-6 h-6 rounded bg-slate-800" /> },
          { key: 'name', label: t('gift.name'), sortable: true, render: g => {
              const n = String(g.name || (g as any).nameAr || (g as any).name_ar || '').trim()
              const readable = n && n !== 'null' && !/^[0-9a-f]{8}-/i.test(n) && !/^[a-z]+_\d+$/.test(n)
              return <span className={readable ? '' : 'text-slate-500 italic'}>{readable ? n : '—'}</span>
            } },
          { key: 'categoryId', label: 'Category', render: g => { const cat = categories.find(c => c.id === g.categoryId); return <span className="text-[10px] text-slate-400">{cat ? cat.name : '-'}</span>; } },
          { key: 'value', label: t('gift.value'), sortable: true, render: g => <span className="text-amber-400 font-mono">{g.value}</span> },
          { key: 'isLucky', label: '🍀 الحظ', render: g => g.isLucky ? <span className="px-1.5 py-0.5 rounded bg-emerald-500/20 text-emerald-300 font-bold text-[10px]">🍀 حظ</span> : '-' },
          { key: 'isVap', label: 'VAP', render: g => g.isVap ? <span className="px-1.5 py-0.5 rounded bg-purple-500/20 text-purple-300 font-bold text-[10px]">VAP</span> : '-' },
          { key: 'isStar', label: '☆', render: g => g.isStar ? <span className="text-amber-400">✓</span> : '-' },
          { key: 'isMusic', label: '♪', render: g => g.isMusic ? <span className="text-emerald-400">✓</span> : '-' },
          { key: 'isCpGift', label: 'CP', render: g => g.isCpGift ? <span className="text-rose-400 font-semibold">♥ {g.cpGiftDurationHours ? `${Math.round(g.cpGiftDurationHours / 24)}d` : ''}</span> : '-' },
          { key: 'sortOrder', label: 'Order', sortable: true },
        ]}
        data={
          activeTab === 'all'
            ? gifts
            : gifts.filter(g => {
                const cat = categories.find(c => c.id === activeTab);
                return cat ? giftMatchesTab(g, cat) : g.categoryId === activeTab;
              })
        }
        searchKeys={['name', 'id']}
        onEdit={handleEdit}
        onDelete={handleDelete}
      />
    </div>
  );
}
