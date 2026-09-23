import { useEffect, useState, useContext } from 'react';
import { StoreItemModel, StoreCategory } from '../types';
import {
  getStoreItems,
  deleteStoreItem,
  updateStoreItem,
  addStoreItem,
  getStoreCategories,
  addStoreCategory,
  updateStoreCategory,
  deleteStoreCategory,
} from '../lib/db';
import { uploadStoreItem } from '../lib/storage';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import { Coins, Plus, Save, X, Trash2, FolderPlus, Package, Layers } from 'lucide-react';
import { I18nContext } from '../lib/i18n';

const DEFAULT_CATEGORIES: StoreCategory[] = [
  { id: 'frame', key: 'frame', name: 'إطار الرأس', iconAsset: 'assets/mipmap-xxhdpi/mine_mall_type_head_wear_nor_ic.webp', selectedIconAsset: 'assets/mipmap-xxhdpi/mine_mall_type_head_wear_pre_ic.webp', sortOrder: 1, isActive: true },
  { id: 'bubble', key: 'bubble', name: 'الفقاعة', iconAsset: 'assets/mipmap-xxhdpi/mine_mall_type_bubble_nor_ic.webp', selectedIconAsset: 'assets/mipmap-xxhdpi/mine_mall_type_bubble_pre_ic.webp', sortOrder: 2, isActive: true },
  { id: 'entrance', key: 'entrance', name: 'تأثير الدخول', iconAsset: 'assets/mipmap-xxhdpi/mine_mall_type_entrance_nor_ic.webp', selectedIconAsset: 'assets/mipmap-xxhdpi/mine_mall_type_entrance_pre_ic.webp', sortOrder: 3, isActive: true },
  { id: 'car', key: 'car', name: 'مركبة الدخول', iconAsset: 'assets/mipmap-xxhdpi/mine_mall_type_car_nor_ic.webp', selectedIconAsset: 'assets/mipmap-xxhdpi/mine_mall_type_car_pre_ic.webp', sortOrder: 4, isActive: true },
  { id: 'cover', key: 'cover', name: 'غلاف الملف الشخصي', iconAsset: 'assets/mipmap-xxhdpi/ic_profile_card.png', selectedIconAsset: 'assets/mipmap-xxhdpi/ic_profile_card.png', sortOrder: 5, isActive: true },
  { id: 'ring', key: 'ring', name: 'الخواتم', iconAsset: 'assets/mipmap-xxhdpi/ic_id_card_prop.png', selectedIconAsset: 'assets/mipmap-xxhdpi/ic_id_card_prop.png', sortOrder: 6, isActive: true },
  { id: 'badge', key: 'badge', name: 'الشارات والأوسمة', iconAsset: 'assets/mipmap-xxhdpi/ic_new_user_badge.png', selectedIconAsset: 'assets/mipmap-xxhdpi/ic_new_user_badge.png', sortOrder: 7, isActive: true },
  { id: 'special', key: 'special', name: 'المؤثرات الخاصة', iconAsset: 'assets/mipmap-xxhdpi/mine_mall_tab_vip_ic.webp', selectedIconAsset: 'assets/mipmap-xxhdpi/mine_mall_tab_vip_ic.webp', sortOrder: 8, isActive: true },
  { id: 'mic_wave', key: 'mic_wave', name: 'موجات المايك الصوتية', iconAsset: 'assets/room_speaking_wave_male.svga', selectedIconAsset: 'assets/room_speaking_wave_male.svga', sortOrder: 9, isActive: true },
];

const svgaCategories = new Set(['entrance', 'car', 'cover', 'mic_wave']);

export default function StorePage() {
  const [activeTab, setActiveTab] = useState<'items' | 'categories'>('items');
  const [items, setItems] = useState<StoreItemModel[]>([]);
  const [categories, setCategories] = useState<StoreCategory[]>([]);
  const [loading, setLoading] = useState(true);

  // Store Item Form State
  const [editing, setEditing] = useState<StoreItemModel | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [form, setForm] = useState({
    name: '',
    category: 'frame',
    iconAsset: '',
    price: 0,
    svgaAsset: '',
    videoAsset: '',
    isPremium: false,
    isHidden: false,
    nameKey: '',
    photoKey: '',
    defaultImage: '',
  });

  // Category Form State
  const [catEditing, setCatEditing] = useState<StoreCategory | null>(null);
  const [showCatAdd, setShowCatAdd] = useState(false);
  const [catForm, setCatForm] = useState({
    name: '',
    key: '',
    iconAsset: '',
    selectedIconAsset: '',
    sortOrder: 1,
    isActive: true,
  });

  const { t } = useContext(I18nContext);

  const load = async () => {
    setLoading(true);
    const [itemsData, catsData] = await Promise.all([getStoreItems(), getStoreCategories()]);
    setItems(itemsData);
    if (catsData.length > 0) {
      setCategories(catsData);
    } else {
      setCategories(DEFAULT_CATEGORIES);
    }
    setLoading(false);
  };

  useEffect(() => {
    load();
  }, []);

  // --- Store Items Handlers ---
  const resetForm = () =>
    setForm({
      name: '',
      category: categories[0]?.key || 'frame',
      iconAsset: '',
      price: 0,
      svgaAsset: '',
      videoAsset: '',
      isPremium: false,
      isHidden: false,
      nameKey: '',
      photoKey: '',
      defaultImage: '',
    });

  const handleEdit = (item: StoreItemModel) => {
    setEditing(item);
    setForm({
      name: item.name,
      category: item.category,
      iconAsset: item.iconAsset,
      price: item.price,
      svgaAsset: item.svgaAsset || '',
      videoAsset: item.videoAsset || '',
      isPremium: item.isPremium,
      isHidden: item.isHidden || false,
      nameKey: item.nameKey || '',
      photoKey: item.photoKey || '',
      defaultImage: item.defaultImage || '',
    });
    setShowAdd(false);
  };

  const handleSave = async () => {
    if (!editing) return;
    await updateStoreItem(editing.itemId, {
      ...form,
      svgaAsset: form.svgaAsset || null,
      videoAsset: form.videoAsset || null,
      nameKey: form.nameKey || null,
      photoKey: form.photoKey || null,
      defaultImage: form.defaultImage || null,
      isHidden: form.isHidden,
    });
    setEditing(null);
    resetForm();
    load();
  };

  const handleDelete = async (item: StoreItemModel) => {
    if (confirm(`Delete ${item.name}?`)) {
      await deleteStoreItem(item.itemId);
      load();
    }
  };

  const handleAdd = async () => {
    const id = `store_${Date.now()}`;
    await addStoreItem(id, {
      ...form,
      itemId: id,
      svgaAsset: form.svgaAsset || null,
      videoAsset: form.videoAsset || null,
      nameKey: form.nameKey || null,
      photoKey: form.photoKey || null,
      defaultImage: form.defaultImage || null,
      isHidden: form.isHidden,
    });
    setShowAdd(false);
    resetForm();
    load();
  };

  // --- Category Handlers ---
  const resetCatForm = () =>
    setCatForm({
      name: '',
      key: '',
      iconAsset: '',
      selectedIconAsset: '',
      sortOrder: categories.length + 1,
      isActive: true,
    });

  const handleCatEdit = (cat: StoreCategory) => {
    setCatEditing(cat);
    setCatForm({
      name: cat.name,
      key: cat.key || cat.id,
      iconAsset: cat.iconAsset || '',
      selectedIconAsset: cat.selectedIconAsset || '',
      sortOrder: cat.sortOrder || 1,
      isActive: cat.isActive ?? true,
    });
    setShowCatAdd(false);
  };

  const handleCatSave = async () => {
    if (!catEditing) return;
    await updateStoreCategory(catEditing.id, {
      ...catForm,
      id: catEditing.id,
      key: catForm.key.trim().toLowerCase(),
    });
    setCatEditing(null);
    resetCatForm();
    load();
  };

  const handleCatDelete = async (cat: StoreCategory) => {
    if (confirm(`هل أنت متأكد من حذف قسم "${cat.name}"؟`)) {
      await deleteStoreCategory(cat.id);
      load();
    }
  };

  const handleCatAdd = async () => {
    const key = (catForm.key || catForm.name).trim().toLowerCase().replace(/\s+/g, '_');
    const id = key || `cat_${Date.now()}`;
    await addStoreCategory(id, {
      ...catForm,
      id,
      key,
    });
    setShowCatAdd(false);
    resetCatForm();
    load();
  };

  const handleSeedStandardCats = async () => {
    for (const sc of DEFAULT_CATEGORIES) {
      await addStoreCategory(sc.id, sc);
    }
    await load();
  };

  const updateField = (f: string, v: unknown) => setForm(p => ({ ...p, [f]: v }));
  const updateCatField = (f: string, v: unknown) => setCatForm(p => ({ ...p, [f]: v }));
  const showDynamicKeys = svgaCategories.has(form.category);

  return (
    <div className="space-y-6">
      {/* Header & Tabs */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 border-b border-white/5 pb-4">
        <div>
          <h2 className="text-white text-lg font-semibold">{t('store.management')}</h2>
          <p className="text-slate-500 text-xs mt-0.5">
            {items.length} {t('store.count')} • {categories.length} أقسام
          </p>
        </div>

        {/* Tab Switcher */}
        <div className="flex items-center gap-2 bg-[#121215] p-1 rounded-xl border border-white/5">
          <button
            onClick={() => setActiveTab('items')}
            className={`px-3 py-1.5 rounded-lg text-xs font-semibold flex items-center gap-1.5 transition-all ${
              activeTab === 'items'
                ? 'bg-indigo-600 text-white shadow'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <Package className="w-3.5 h-3.5" />
            عناصر المتجر
          </button>
          <button
            onClick={() => setActiveTab('categories')}
            className={`px-3 py-1.5 rounded-lg text-xs font-semibold flex items-center gap-1.5 transition-all ${
              activeTab === 'categories'
                ? 'bg-indigo-600 text-white shadow'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <Layers className="w-3.5 h-3.5" />
            أقسام المتجر
          </button>
        </div>

        {/* Action Button */}
        <div>
          {activeTab === 'items' ? (
            <button
              onClick={() => {
                setShowAdd(!showAdd);
                setEditing(null);
                resetForm();
              }}
              className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1 shadow"
            >
              <Plus className="w-3.5 h-3.5" /> {showAdd ? t('cancel') : t('store.add')}
            </button>
          ) : (
            <div className="flex items-center gap-2">
              <button
                onClick={handleSeedStandardCats}
                className="px-3 py-1.5 bg-emerald-600/20 hover:bg-emerald-600/30 text-emerald-300 border border-emerald-500/30 text-xs font-semibold rounded-lg flex items-center gap-1"
                title="إضافة الأقسام القياسية الثمانية"
              >
                🔄 استرجاع الأقسام القياسية
              </button>
              <button
                onClick={() => {
                  setShowCatAdd(!showCatAdd);
                  setCatEditing(null);
                  resetCatForm();
                }}
                className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1 shadow"
              >
                <FolderPlus className="w-3.5 h-3.5" /> {showCatAdd ? t('cancel') : 'إضافة قسم جديد'}
              </button>
            </div>
          )}
        </div>
      </div>

      {/* ═══════════════════════════════════════════════════════════ */}
      {/* TAB 1: STORE ITEMS */}
      {/* ═══════════════════════════════════════════════════════════ */}
      {activeTab === 'items' && (
        <div className="space-y-6">
          {(editing || showAdd) && (
            <div className="bg-[#141417] rounded-2xl border border-indigo-500/20 p-6 space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-white font-semibold text-sm">
                  {editing ? `${t('store.edit')}: ${editing.name}` : t('store.new')}
                </h3>
                <button
                  onClick={() => {
                    setEditing(null);
                    setShowAdd(false);
                  }}
                  className="text-slate-400 hover:text-white"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <ImageUpload
                  currentUrl={form.iconAsset}
                  onUpload={file => uploadStoreItem(file, editing?.itemId || `new_${Date.now()}`)}
                  onUrlChange={url => updateField('iconAsset', url)}
                  label={t('upload')}
                />
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                    {t('gift.name')}
                  </label>
                  <input
                    type="text"
                    value={form.name}
                    onChange={e => updateField('name', e.target.value)}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                  />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                    {t('store.category')}
                  </label>
                  <select
                    value={form.category}
                    onChange={e => updateField('category', e.target.value)}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                  >
                    {categories.map(c => (
                      <option key={c.key || c.id} value={c.key || c.id}>
                        {c.name} ({c.key || c.id})
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                    {t('store.price')}
                  </label>
                  <input
                    type="number"
                    value={form.price}
                    onChange={e => updateField('price', Number(e.target.value))}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                  />
                </div>
                <div className="col-span-2">
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                    SVGA Asset URL / ملف الأنيميشن
                  </label>
                  <ImageUpload
                    currentUrl={form.svgaAsset}
                    onUpload={file => uploadStoreItem(file, editing?.itemId || `new_${Date.now()}`)}
                    onUrlChange={url => updateField('svgaAsset', url)}
                    label="Animation"
                    accept=".svga,.json,.zip"
                  />
                </div>
                <div className="col-span-2">
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                    Video Asset URL (MP4/VAP)
                  </label>
                  <ImageUpload
                    currentUrl={form.videoAsset}
                    onUpload={file => uploadStoreItem(file, editing?.itemId || `new_${Date.now()}`)}
                    onUrlChange={url => updateField('videoAsset', url)}
                    label="Video"
                    accept=".mp4,.vap"
                  />
                </div>
                {showDynamicKeys && (
                  <>
                    <div>
                      <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                        Name Key
                      </label>
                      <input
                        type="text"
                        value={form.nameKey}
                        onChange={e => updateField('nameKey', e.target.value)}
                        placeholder="e.g. txt_name"
                        className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                      />
                    </div>
                    <div>
                      <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                        Photo Key
                      </label>
                      <input
                        type="text"
                        value={form.photoKey}
                        onChange={e => updateField('photoKey', e.target.value)}
                        placeholder="e.g. img_avatar"
                        className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                      />
                    </div>
                    <div className="col-span-2">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                        Default Image URL
                      </label>
                      <ImageUpload
                        currentUrl={form.defaultImage}
                        onUpload={file =>
                          uploadStoreItem(file, `default_${editing?.itemId || `new_${Date.now()}`}`)
                        }
                        onUrlChange={url => updateField('defaultImage', url)}
                        label="Default Image"
                        accept="image/*"
                      />
                    </div>
                  </>
                )}
              </div>
              <div className="flex items-center gap-6">
                <label className="flex items-center gap-1.5 text-xs text-slate-400">
                  <input
                    type="checkbox"
                    checked={form.isPremium}
                    onChange={e => updateField('isPremium', e.target.checked)}
                    className="accent-indigo-500"
                  />
                  {t('store.premium')}
                </label>
                <label className="flex items-center gap-1.5 text-xs text-amber-300 font-semibold cursor-pointer">
                  <input
                    type="checkbox"
                    checked={form.isHidden}
                    onChange={e => updateField('isHidden', e.target.checked)}
                    className="accent-amber-500"
                  />
                  🔒 إخفاء من المتجر العام (حصري للأحداث ومكافآت الـ CP فقط)
                </label>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={editing ? handleSave : handleAdd}
                  className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1"
                >
                  <Save className="w-3 h-3" /> {editing ? t('save') : t('store.add')}
                </button>
              </div>
            </div>
          )}

          <DataTable
            loading={loading}
            columns={[
              {
                key: 'iconAsset',
                label: '',
                width: '40px',
                render: i =>
                  i.iconAsset ? (
                    <img src={i.iconAsset} className="w-6 h-6 object-contain" />
                  ) : (
                    <div className="w-6 h-6 rounded bg-slate-800" />
                  ),
              },
              { key: 'name', label: t('gift.name'), sortable: true },
              {
                key: 'category',
                label: t('store.category'),
                sortable: true,
                render: i => {
                  const c = categories.find(cat => (cat.key || cat.id) === i.category);
                  return (
                    <span className="text-indigo-400 text-[11px] font-medium">
                      {c ? c.name : i.category}
                    </span>
                  );
                },
              },
              {
                key: 'price',
                label: t('store.price'),
                sortable: true,
                render: i => (
                  <span className="flex items-center gap-1 text-amber-400">
                    <Coins className="w-3 h-3" />
                    {i.price}
                  </span>
                ),
              },
              {
                key: 'isPremium',
                label: t('store.premium'),
                render: i => (i.isPremium ? <span className="text-rose-400">✓</span> : '-'),
              },
              {
                key: 'isHidden',
                label: 'حالة العرض',
                render: i =>
                  i.isHidden ? (
                    <span className="px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-300 text-[10px] font-bold">
                      🔒 مخفي (أحداث/مكافآت)
                    </span>
                  ) : (
                    <span className="px-1.5 py-0.5 rounded bg-emerald-500/20 text-emerald-300 text-[10px]">
                      🟢 معروض بالمتجر
                    </span>
                  ),
              },
            ]}
            data={items}
            searchKeys={['name', 'category']}
            onEdit={handleEdit}
            onDelete={handleDelete}
          />
        </div>
      )}

      {/* ═══════════════════════════════════════════════════════════ */}
      {/* TAB 2: STORE CATEGORIES MANAGEMENT */}
      {/* ═══════════════════════════════════════════════════════════ */}
      {activeTab === 'categories' && (
        <div className="space-y-6">
          {(catEditing || showCatAdd) && (
            <div className="bg-[#141417] rounded-2xl border border-indigo-500/20 p-6 space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-white font-semibold text-sm">
                  {catEditing ? `تعديل القسم: ${catEditing.name}` : 'إضافة قسم جديد للمتجر'}
                </h3>
                <button
                  onClick={() => {
                    setCatEditing(null);
                    setShowCatAdd(false);
                  }}
                  className="text-slate-400 hover:text-white"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                {/* Category Icon */}
                <ImageUpload
                  currentUrl={catForm.iconAsset}
                  onUpload={file =>
                    uploadStoreItem(file, `cat_icon_${catEditing?.id || Date.now()}`)
                  }
                  onUrlChange={url => updateCatField('iconAsset', url)}
                  label="أيقونة القسم (عادية)"
                />

                {/* Selected Icon */}
                <ImageUpload
                  currentUrl={catForm.selectedIconAsset}
                  onUpload={file =>
                    uploadStoreItem(file, `cat_sel_icon_${catEditing?.id || Date.now()}`)
                  }
                  onUrlChange={url => updateCatField('selectedIconAsset', url)}
                  label="أيقونة التحديد (اختياري)"
                />

                <div className="space-y-3">
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                      اسم القسم (عربي)
                    </label>
                    <input
                      type="text"
                      value={catForm.name}
                      onChange={e => updateCatField('name', e.target.value)}
                      placeholder="مثال: الخواتم، الأجنحة..."
                      className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                    />
                  </div>

                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                      معرف القسم (Key بالإنجليزية)
                    </label>
                    <input
                      type="text"
                      value={catForm.key}
                      onChange={e => updateCatField('key', e.target.value)}
                      placeholder="e.g. ring, wings, pet"
                      className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                    />
                  </div>

                  <div className="grid grid-cols-2 gap-2">
                    <div>
                      <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">
                        ترتيب العرض
                      </label>
                      <input
                        type="number"
                        value={catForm.sortOrder}
                        onChange={e => updateCatField('sortOrder', Number(e.target.value))}
                        className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                      />
                    </div>
                    <div className="flex items-center pt-4">
                      <label className="flex items-center gap-1.5 text-xs text-slate-300 font-medium cursor-pointer">
                        <input
                          type="checkbox"
                          checked={catForm.isActive}
                          onChange={e => updateCatField('isActive', e.target.checked)}
                          className="accent-indigo-500"
                        />
                        قسم مفعل
                      </label>
                    </div>
                  </div>
                </div>
              </div>

              <div className="flex gap-2 pt-2">
                <button
                  onClick={catEditing ? handleCatSave : handleCatAdd}
                  className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1 shadow"
                >
                  <Save className="w-3 h-3" />
                  {catEditing ? 'حفظ التعديلات' : 'إضافة القسم'}
                </button>
              </div>
            </div>
          )}

          {/* Categories Grid/List */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {categories.map(cat => (
              <div
                key={cat.id || cat.key}
                className="bg-[#141417] rounded-xl border border-white/5 p-4 flex items-center gap-3.5 hover:border-white/10 transition-colors"
              >
                <div className="w-12 h-12 rounded-lg bg-slate-900 border border-white/10 flex items-center justify-center overflow-hidden flex-shrink-0">
                  {cat.iconAsset ? (
                    <img
                      src={cat.iconAsset}
                      alt={cat.name}
                      className="w-8 h-8 object-contain"
                      onError={e => {
                        (e.target as HTMLImageElement).src =
                          'https://placehold.co/48x48/1e1e24/fff?text=Icon';
                      }}
                    />
                  ) : (
                    <Layers className="w-5 h-5 text-slate-500" />
                  )}
                </div>

                <div className="flex-1 min-w-0">
                  <div className="text-white text-xs font-semibold truncate flex items-center gap-1.5">
                    {cat.name}
                    {cat.isActive === false && (
                      <span className="text-[9px] px-1 py-0.2 bg-rose-500/20 text-rose-300 rounded">
                        معطل
                      </span>
                    )}
                  </div>
                  <div className="text-[11px] text-indigo-400 font-mono mt-0.5">
                    {cat.key || cat.id}
                  </div>
                  <div className="text-[10px] text-slate-500">
                    الترتيب: {cat.sortOrder} • العناصر:{' '}
                    {items.filter(i => i.category === (cat.key || cat.id)).length}
                  </div>
                </div>

                <div className="flex items-center gap-1.5">
                  <button
                    onClick={() => handleCatEdit(cat)}
                    className="px-2 py-1 text-[11px] text-indigo-400 hover:text-indigo-300 hover:bg-indigo-500/10 rounded font-medium"
                  >
                    تعديل
                  </button>
                  <button
                    onClick={() => handleCatDelete(cat)}
                    className="p-1 text-rose-400 hover:text-rose-300 hover:bg-rose-500/10 rounded"
                    title="حذف القسم"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
