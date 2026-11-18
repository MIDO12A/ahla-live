import { useEffect, useState, useContext } from 'react';
import { I18nContext } from '../lib/i18n';
import { listenCollection } from '../lib/supabase';
import { getCpGifts, addCpGift, updateCpGift, deleteCpGift, getCpCars, addCpCar, updateCpCar, deleteCpCar, getCpSettings, updateCpSetting, getCpRankRewards, upsertCpRankReward, deleteCpRankReward, distributeCpRewards, expireCpRewards, getCpRewardConfig, saveCpRewardConfig, getActiveRewards, getDistributionHistory, getGifts, getStoreItems } from '../lib/db';
import { uploadAppAsset } from '../lib/storage';
import type { CpGiftModel, CpCarModel, CpRankRewardModel, GiftModel, StoreItemModel } from '../types';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import { Plus, Save, X, Gift, Car, Calendar, Settings, Award, Upload, RotateCcw, Zap, Trash2, RefreshCw, Heart, ShoppingBag } from 'lucide-react';

const defaultGiftForm = {
  id: '',
  name: '',
  nameAr: '',
  nameEn: '',
  iconUrl: '',
  svgaUrl: '',
  value: 100,
  durationType: 'days',
  durationValue: 1,
  durationDays: 1,
  sortOrder: 0,
  isActive: true,
  maleRewardName: '',
  maleRewardType: 'frame',
  maleRewardSvga: '',
  maleRewardIcon: '',
  maleRewardCoins: 0,
  maleRewardDays: 7,
  femaleRewardName: '',
  femaleRewardType: 'frame',
  femaleRewardSvga: '',
  femaleRewardIcon: '',
  femaleRewardCoins: 0,
  femaleRewardDays: 7,
};
const defaultCarForm = { id: '', name: '', nameAr: '', nameEn: '', svgaUrl: '', thumbnailUrl: '', sortOrder: 0, isActive: true };

const eventSettingKeys = [
  { key: 'weekly_reset_day', labelAr: 'يوم إعادة التعيين الأسبوعي', labelEn: 'Weekly Reset Day', type: 'select', options: ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'] },
  { key: 'event_start_date', labelAr: 'تاريخ بداية الحدث', labelEn: 'Event Start Date', type: 'date' },
  { key: 'event_duration_days', labelAr: 'مدة الحدث (أيام)', labelEn: 'Event Duration (Days)', type: 'number' },
  { key: 'min_score_for_prize', labelAr: 'الحد الأدنى للنقاط للجائزة', labelEn: 'Min Score for Prize', type: 'number' },
  { key: 'prize_1_name', labelAr: 'اسم جائزة الأول 🥇', labelEn: '1st Prize Name', type: 'text' },
  { key: 'prize_1_coins', labelAr: 'عملات الأول 🥇', labelEn: '1st Prize Coins', type: 'number' },
  { key: 'prize_1_svga', labelAr: 'SVGA جائزة الأول 🥇', labelEn: '1st Prize SVGA', type: 'image' },
  { key: 'prize_1_image', labelAr: 'صورة جائزة الأول 🥇', labelEn: '1st Prize Image', type: 'image' },
  { key: 'prize_2_name', labelAr: 'اسم جائزة الثاني 🥈', labelEn: '2nd Prize Name', type: 'text' },
  { key: 'prize_2_coins', labelAr: 'عملات الثاني 🥈', labelEn: '2nd Prize Coins', type: 'number' },
  { key: 'prize_2_svga', labelAr: 'SVGA جائزة الثاني 🥈', labelEn: '2nd Prize SVGA', type: 'image' },
  { key: 'prize_2_image', labelAr: 'صورة جائزة الثاني 🥈', labelEn: '2nd Prize Image', type: 'image' },
  { key: 'prize_3_name', labelAr: 'اسم جائزة الثالث 🥉', labelEn: '3rd Prize Name', type: 'text' },
  { key: 'prize_3_coins', labelAr: 'عملات الثالث 🥉', labelEn: '3rd Prize Coins', type: 'number' },
  { key: 'prize_3_svga', labelAr: 'SVGA جائزة الثالث 🥉', labelEn: '3rd Prize SVGA', type: 'image' },
  { key: 'prize_3_image', labelAr: 'صورة جائزة الثالث 🥉', labelEn: '3rd Prize Image', type: 'image' },
  { key: 'prize_notification', labelAr: 'نص الإشعار عند الفوز', labelEn: 'Prize Notification Text', type: 'textarea' },
  { key: 'cp_gift_duration', labelAr: 'مدة ربط هدية CP (ساعات)', labelEn: 'CP Gift Link Duration (Hours)', type: 'number' },
];

const tabs = [
  { key: 'gifts', labelAr: '🎁 هدايا CP', labelEn: 'CP Gifts', icon: Gift },
  { key: 'linkRewards', labelAr: '💑 مكافآت الارتباط (شاب وفتاة)', labelEn: 'Link Rewards (Boy & Girl)', icon: Heart },
  { key: 'cars', labelAr: '🚗 سيارات CP', labelEn: 'CP Cars', icon: Car },
  { key: 'rewards', labelAr: '🏆 جوائز المراكز', labelEn: 'Rank Rewards', icon: Award },
  { key: 'rewardsConfig', labelAr: '⚙️ إعدادات المكافآت', labelEn: 'Rewards Settings', icon: Settings },
  { key: 'autoDist', labelAr: '⚡ التوزيع التلقائي', labelEn: 'Auto-Distribution', icon: Zap },
  { key: 'events', labelAr: '📅 الأحداث والجوائز', labelEn: 'Events & Prizes', icon: Calendar },
  { key: 'settings', labelAr: '⚙️ الإعدادات العامة', labelEn: 'General Settings', icon: RotateCcw },
];

export default function CpFeaturesPage() {
  const { lang } = useContext(I18nContext);
  const isAr = lang === 'ar';
  const [activeTab, setActiveTab] = useState('gifts');

  // Loading & notification states
  const [loading, setLoading] = useState(true);
  const [msg, setMsg] = useState<string | null>(null);
  const showMsg = (m: string) => {
    setMsg(m);
    setTimeout(() => setMsg(null), 3000);
  };

  // Gifts state
  const [gifts, setGifts] = useState<CpGiftModel[]>([]);
  const [giftForm, setGiftForm] = useState(defaultGiftForm);
  const [editingGift, setEditingGift] = useState<string | null>(null);
  const [showAddGift, setShowAddGift] = useState(false);

  // Cars state
  const [cars, setCars] = useState<CpCarModel[]>([]);
  const [carForm, setCarForm] = useState(defaultCarForm);
  const [editingCar, setEditingCar] = useState<string | null>(null);
  const [showAddCar, setShowAddCar] = useState(false);

  // Rewards state
  const [rewards, setRewards] = useState<CpRankRewardModel[]>([]);
  const [rewardsPeriod, setRewardsPeriod] = useState('all');
  const [rewardsLoading, setRewardsLoading] = useState(false);
  const [rewardForm, setRewardForm] = useState({
    period: 'daily',
    rank_position: 1,
    sort_order: 0,
    target_partner: 'both',
    reward_type: 'frame_svga',
    label_ar: '',
    label_en: '',
    svga_url: '',
    image_url: '',
    is_active: true,
  });
  const [editingReward, setEditingReward] = useState<string | null>(null);
  const [showAddReward, setShowAddReward] = useState(false);

  // Auto-distribution state
  const [rewardConfig, setRewardConfig] = useState<any>(null);
  const [activeRewardsCount, setActiveRewardsCount] = useState(0);
  const [history, setHistory] = useState<any[]>([]);
  const [distributing, setDistributing] = useState(false);
  const [expiring, setExpiring] = useState(false);

  // Settings state
  const [cpSettings, setCpSettings] = useState<Record<string, string>>({});
  const [savingSettings, setSavingSettings] = useState(false);
  const [bondGiftIds, setBondGiftIds] = useState<string[]>([]);
  const [mainGifts, setMainGifts] = useState<GiftModel[]>([]);
  const [settingsLoadingGifts, setSettingsLoadingGifts] = useState(false);

  const loadGifts = async () => {
    try {
      const g = await getCpGifts();
      setGifts(g);
    } catch (e) {
      console.warn('loadGifts error:', e);
    }
  };

  const loadCars = async () => {
    try {
      const c = await getCpCars();
      setCars(c);
    } catch (e) {
      console.warn('loadCars error:', e);
    }
  };

  const loadRewards = async () => {
    try {
      setRewardsLoading(true);
      const r = await getCpRankRewards();
      setRewards(r);
    } catch (e) {
      console.warn('loadRewards error:', e);
    } finally {
      setRewardsLoading(false);
    }
  };

  const loadSettings = () => Promise.all([
    getCpSettings(),
    getGifts(),
  ]).then(([d, mg]) => {
    setCpSettings(d);
    const raw = d['cp_bond_gift_ids'] || d['cp_bond_gift_id'] || '';
    try {
      setBondGiftIds(JSON.parse(raw));
    } catch {
      setBondGiftIds(raw ? [raw] : []);
    }
    setMainGifts(mg);
  }).catch(e => console.warn('loadSettings error:', e));

  // Reload main gifts whenever settings tab becomes active
  useEffect(() => {
    if (activeTab === 'settings') {
      setSettingsLoadingGifts(true);
      getGifts().then(mg => {
        setMainGifts(mg);
        setSettingsLoadingGifts(false);
      }).catch(e => {
        console.warn('reload main gifts error:', e);
        setSettingsLoadingGifts(false);
      });
    }
  }, [activeTab]);

  const loadAutoDist = async () => {
    const cfg = await getCpRewardConfig();
    setRewardConfig(cfg);
    const active = await getActiveRewards();
    setActiveRewardsCount(active.length);
    const h = await getDistributionHistory();
    setHistory(h);
  };

  const [storeItems, setStoreItems] = useState<StoreItemModel[]>([]);

  const loadStoreItems = async () => {
    try {
      const si = await getStoreItems();
      setStoreItems(si);
    } catch (e) {
      console.warn('loadStoreItems error:', e);
    }
  };

  useEffect(() => {
    setLoading(true);
    Promise.all([loadGifts(), loadCars(), loadRewards(), loadSettings(), loadAutoDist(), loadStoreItems()])
      .finally(() => setLoading(false));
  }, []);

  // Realtime: أي تعديل على cp_rank_rewards (من تبويب آخر/نافذة أخرى) يظهر فوراً.
  useEffect(() => {
    const unsub = listenCollection('cp_rank_rewards', rows => {
      setRewards(rows.map((r: any) => ({
        id: r.id,
        period: r.period ?? 'weekly',
        rank_position: Number(r.rank_position ?? 1),
        slot_index: Number(r.slot_index ?? 0),
        reward_type: r.reward_type ?? 'frame_svga',
        label_ar: r.label_ar ?? '',
        label_en: r.label_en ?? '',
        svga_url: r.svga_url ?? '',
        image_url: r.image_url ?? '',
        isActive: (r.is_active ?? r.isActive) !== false,
      })));
    });
    return unsub;
  }, []);

  const resetGiftForm = () => { setGiftForm(defaultGiftForm); setEditingGift(null); setShowAddGift(false); };
  const resetCarForm = () => { setCarForm(defaultCarForm); setEditingCar(null); setShowAddCar(false); };
  const resetRewardForm = () => { setRewardForm({ period: 'daily', rank_position: 1, sort_order: 0, target_partner: 'both', reward_type: 'frame_svga', label_ar: '', label_en: '', svga_url: '', image_url: '', is_active: true }); setEditingReward(null); setShowAddReward(false); };

  const handleEditReward = (r: CpRankRewardModel) => {
    setEditingReward(r.id);
    setShowAddReward(false);
    setRewardForm({ period: r.period || 'daily', rank_position: r.rank_position ?? 1, sort_order: r.slot_index, target_partner: 'both', reward_type: r.reward_type || 'frame_svga', label_ar: r.label_ar, label_en: r.label_en, svga_url: r.svga_url || '', image_url: r.image_url || '', is_active: r.isActive !== false });
  };

  const handleSaveReward = async () => {
    await upsertCpRankReward(editingReward, { ...rewardForm, isActive: rewardForm.is_active, rank_position: rewardForm.rank_position, slot_index: rewardForm.sort_order });
    resetRewardForm();
    loadRewards();
    showMsg('Saved!');
  };

  const handleAddReward = async () => {
    if (!rewardForm.label_ar) { showMsg('Please enter Arabic label'); return; }
    await upsertCpRankReward(null, { ...rewardForm, isActive: rewardForm.is_active, rank_position: rewardForm.rank_position, slot_index: rewardForm.sort_order });
    resetRewardForm();
    loadRewards();
    showMsg('Added!');
  };

  const handleEditGift = (g: CpGiftModel) => {
    setEditingGift(g.id);
    setShowAddGift(false);
    setGiftForm({
      id: g.id,
      name: g.nameAr || g.name,
      nameAr: g.nameAr || '',
      nameEn: g.nameEn || '',
      iconUrl: g.iconUrl || '',
      svgaUrl: g.svgaUrl || '',
      value: g.value,
      durationDays: g.durationDays ?? (g.durationHours ? Math.round(g.durationHours / 24) : 1),
      sortOrder: g.sortOrder,
      isActive: g.isActive,
      maleRewardName: g.maleRewardName || '',
      maleRewardType: g.maleRewardType || 'frame',
      maleRewardSvga: g.maleRewardSvga || '',
      maleRewardIcon: g.maleRewardIcon || '',
      maleRewardCoins: g.maleRewardCoins || 0,
      maleRewardDays: g.maleRewardDays || 7,
      femaleRewardName: g.femaleRewardName || '',
      femaleRewardType: g.femaleRewardType || 'frame',
      femaleRewardSvga: g.femaleRewardSvga || '',
      femaleRewardIcon: g.femaleRewardIcon || '',
      femaleRewardCoins: g.femaleRewardCoins || 0,
      femaleRewardDays: g.femaleRewardDays || 7,
    });
  };

  const handleSaveGift = async () => {
    if (!editingGift) return;
    const durationHours = (giftForm.durationDays || 1) * 24;
    await updateCpGift(editingGift, {
      ...giftForm,
      durationHours,
      duration_hours: durationHours,
      duration_days: giftForm.durationDays || 1,
      male_reward_name: giftForm.maleRewardName,
      male_reward_type: giftForm.maleRewardType,
      male_reward_svga: giftForm.maleRewardSvga,
      male_reward_icon: giftForm.maleRewardIcon,
      male_reward_coins: giftForm.maleRewardCoins,
      male_reward_days: giftForm.maleRewardDays,
      female_reward_name: giftForm.femaleRewardName,
      female_reward_type: giftForm.femaleRewardType,
      female_reward_svga: giftForm.femaleRewardSvga,
      female_reward_icon: giftForm.femaleRewardIcon,
      female_reward_coins: giftForm.femaleRewardCoins,
      female_reward_days: giftForm.femaleRewardDays,
      iconUrl: giftForm.iconUrl || null,
      svgaUrl: giftForm.svgaUrl || null,
    } as any);
    resetGiftForm();
    loadGifts();
    showMsg('Saved!');
  };

  const handleAddGift = async () => {
    if (!giftForm.nameAr) { showMsg('Please enter Arabic name'); return; }
    const id = 'cp_gift_' + Date.now();
    const durationHours = (giftForm.durationDays || 1) * 24;
    await addCpGift(id, {
      ...giftForm,
      id,
      durationHours,
      duration_hours: durationHours,
      duration_days: giftForm.durationDays || 1,
      male_reward_name: giftForm.maleRewardName,
      male_reward_type: giftForm.maleRewardType,
      male_reward_svga: giftForm.maleRewardSvga,
      male_reward_icon: giftForm.maleRewardIcon,
      male_reward_coins: giftForm.maleRewardCoins,
      male_reward_days: giftForm.maleRewardDays,
      female_reward_name: giftForm.femaleRewardName,
      female_reward_type: giftForm.femaleRewardType,
      female_reward_svga: giftForm.femaleRewardSvga,
      female_reward_icon: giftForm.femaleRewardIcon,
      female_reward_coins: giftForm.femaleRewardCoins,
      female_reward_days: giftForm.femaleRewardDays,
      iconUrl: giftForm.iconUrl || null,
      svgaUrl: giftForm.svgaUrl || null,
    } as any);
    resetGiftForm();
    loadGifts();
    showMsg('Added!');
  };

  const handleEditCar = (c: CpCarModel) => {
    setEditingCar(c.id);
    setShowAddCar(false);
    setCarForm({ id: c.id, name: c.nameAr || c.name, nameAr: c.nameAr || '', nameEn: c.nameEn || '', svgaUrl: c.svgaUrl || '', thumbnailUrl: c.thumbnailUrl || '', sortOrder: c.sortOrder, isActive: c.isActive });
  };

  const handleSaveCar = async () => {
    if (!editingCar) return;
    await updateCpCar(editingCar, { ...carForm, svgaUrl: carForm.svgaUrl || null, thumbnailUrl: carForm.thumbnailUrl || null } as any);
    resetCarForm();
    loadCars();
    showMsg('Saved!');
  };

  const handleAddCar = async () => {
    if (!carForm.nameAr) { showMsg('Please enter Arabic name'); return; }
    const id = 'cp_car_' + Date.now();
    await addCpCar(id, { ...carForm, id, svgaUrl: carForm.svgaUrl || null, thumbnailUrl: carForm.thumbnailUrl || null } as any);
    resetCarForm();
    loadCars();
    showMsg('Added!');
  };

  const handleSaveSettings = async () => {
    setSavingSettings(true);
    for (const [key, value] of Object.entries(cpSettings)) {
      await updateCpSetting(key, value);
    }
    setSavingSettings(false);
    showMsg('Settings saved!');
  };

  const handleImageUpload = async (file: File, key: string) => {
    try {
      const path = `cp_features/${key}_${Date.now()}`;
      const url = await uploadAppAsset(file, path);
      if (url) setCpSettings(p => ({ ...p, [key]: url }));
    } catch (e) {
      showMsg('Upload failed');
    }
  };

  const updateForm = (form: any, setter: any, field: string, value: any) => setter((p: any) => ({ ...p, [field]: value }));

  if (loading) return <div className="text-slate-400 text-sm p-6">Loading...</div>;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-white text-lg font-semibold">{isAr ? '💑 ميزات CP' : '💑 CP Features'}</h2>
      </div>

      {msg && <div className="bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs px-4 py-2 rounded-lg">{msg}</div>}

      {/* Tabs */}
      <div className="flex gap-1 border-b border-white/5 overflow-x-auto">
        {tabs.map(t => (
          <button key={t.key} onClick={() => setActiveTab(t.key)}
            className={`px-3 py-2 text-xs font-medium whitespace-nowrap border-b-2 transition-all flex items-center gap-1.5 ${activeTab === t.key ? 'text-indigo-300 border-indigo-500' : 'text-slate-400 border-transparent hover:text-white'}`}>
            {isAr ? t.labelAr : t.labelEn}
          </button>
        ))}
      </div>

      {/* ════════════ GIFTS TAB ════════════ */}
      {activeTab === 'gifts' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <p className="text-slate-500 text-xs">{gifts.length} {isAr ? 'هدية' : 'gifts'}</p>
            <button onClick={() => { resetGiftForm(); setShowAddGift(!showAddGift); }}
              className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
              <Plus className="w-3.5 h-3.5" /> {showAddGift ? (isAr ? 'إلغاء' : 'Cancel') : (isAr ? 'إضافة هدية' : 'Add Gift')}
            </button>
          </div>

          {(editingGift || showAddGift) && (
            <div className="bg-[#141417] rounded-2xl border border-indigo-500/20 p-6 space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-white font-semibold text-sm">{editingGift ? (isAr ? 'تعديل' : 'Edit') + ' ' + giftForm.name : (isAr ? 'هدية جديدة' : 'New Gift')}</h3>
                <button onClick={resetGiftForm} className="text-slate-400 hover:text-white"><X className="w-4 h-4" /></button>
              </div>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'الاسم (عربي)' : 'Name (Arabic)'}</label>
                  <input value={giftForm.nameAr} onChange={e => updateForm(giftForm, setGiftForm, 'nameAr', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'الاسم (إنجليزي)' : 'Name (English)'}</label>
                  <input value={giftForm.nameEn} onChange={e => updateForm(giftForm, setGiftForm, 'nameEn', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'القيمة (coins)' : 'Value (coins)'}</label>
                  <input type="number" value={giftForm.value} onChange={e => updateForm(giftForm, setGiftForm, 'value', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-rose-400 font-bold mb-1">{isAr ? '⏳ مدة الارتباط (بالأيام)' : '⏳ Link Duration (Days)'}</label>
                  <input type="number" min="1" value={giftForm.durationDays} onChange={e => updateForm(giftForm, setGiftForm, 'durationDays', Number(e.target.value))} className="w-full bg-[#161618] border border-rose-500/30 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Sort Order</label>
                  <input type="number" value={giftForm.sortOrder} onChange={e => updateForm(giftForm, setGiftForm, 'sortOrder', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'نشط' : 'Active'}</label>
                  <label className="flex items-center gap-2 mt-1">
                    <input type="checkbox" checked={giftForm.isActive} onChange={e => updateForm(giftForm, setGiftForm, 'isActive', e.target.checked)} className="w-4 h-4" />
                    <span className="text-xs text-slate-400">{giftForm.isActive ? (isAr ? 'مفعل' : 'Enabled') : (isAr ? 'معطل' : 'Disabled')}</span>
                  </label>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <ImageUpload currentUrl={giftForm.iconUrl} onUpload={file => uploadAppAsset(file, `cp_gift_icon_${Date.now()}`)} onUrlChange={url => updateForm(giftForm, setGiftForm, 'iconUrl', url)} label={isAr ? 'أيقونة الهدية' : 'Gift Icon'} accept="image/*,.webp,.png,.svg" />
                <ImageUpload currentUrl={giftForm.svgaUrl} onUpload={file => uploadAppAsset(file, `cp_gift_svga_${Date.now()}`)} onUrlChange={url => updateForm(giftForm, setGiftForm, 'svgaUrl', url)} label={isAr ? 'ملف الأنميشن (SVGA)' : 'Animation (SVGA)'} accept=".svga,.zip,.mp4,.vap" />
              </div>

              {/* Male Partner Reward */}
              <div className="border border-blue-500/20 bg-blue-950/10 rounded-xl p-4 space-y-3">
                <h4 className="text-blue-400 font-semibold text-xs flex items-center gap-1.5">👦 {isAr ? 'مكافأة الشاب / الذكر عند تفعيل الارتباط (اختياري)' : 'Boy / Male Link Reward (Optional)'}</h4>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                  <div>
                    <label className="block text-[10px] text-slate-400 font-bold mb-1">{isAr ? 'اسم المكافأة' : 'Reward Name'}</label>
                    <input value={giftForm.maleRewardName} onChange={e => updateForm(giftForm, setGiftForm, 'maleRewardName', e.target.value)} placeholder={isAr ? 'مثال: خاتم الفارس الذهبي' : 'e.g. Gold Ring'} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                  <div>
                    <label className="block text-[10px] text-slate-400 font-bold mb-1">{isAr ? 'نوع المكافأة' : 'Reward Type'}</label>
                    <select value={giftForm.maleRewardType} onChange={e => updateForm(giftForm, setGiftForm, 'maleRewardType', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                      <option value="frame">{isAr ? 'إطار (Frame)' : 'Frame'}</option>
                      <option value="badge">{isAr ? 'وسام (Badge)' : 'Badge'}</option>
                      <option value="necklace">{isAr ? 'قلادة (Necklace)' : 'Necklace'}</option>
                      <option value="ring">{isAr ? 'خاتم CP (Ring)' : 'Ring'}</option>
                      <option value="entrance">{isAr ? 'مآثر دخول (Entrance)' : 'Entrance'}</option>
                      <option value="coins">{isAr ? 'عملات فقط (Coins)' : 'Coins'}</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[10px] text-slate-400 font-bold mb-1">{isAr ? 'عملات إضافية' : 'Bonus Coins'}</label>
                    <input type="number" value={giftForm.maleRewardCoins} onChange={e => updateForm(giftForm, setGiftForm, 'maleRewardCoins', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                  <div>
                    <label className="block text-[10px] text-slate-400 font-bold mb-1">{isAr ? 'مدة المكافأة (أيام)' : 'Reward Validity (Days)'}</label>
                    <input type="number" min="1" value={giftForm.maleRewardDays} onChange={e => updateForm(giftForm, setGiftForm, 'maleRewardDays', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <ImageUpload currentUrl={giftForm.maleRewardIcon} onUpload={file => uploadAppAsset(file, `cp_male_reward_icon_${Date.now()}`)} onUrlChange={url => updateForm(giftForm, setGiftForm, 'maleRewardIcon', url)} label={isAr ? 'صورة/أيقونة مكافأة الشاب' : 'Boy Reward Icon'} accept="image/*,.webp,.png" />
                  <ImageUpload currentUrl={giftForm.maleRewardSvga} onUpload={file => uploadAppAsset(file, `cp_male_reward_svga_${Date.now()}`)} onUrlChange={url => updateForm(giftForm, setGiftForm, 'maleRewardSvga', url)} label={isAr ? 'ملف SVGA لمكافأة الشاب' : 'Boy Reward SVGA'} accept=".svga,.zip,.mp4,.vap" />
                </div>
              </div>

              {/* Female Partner Reward */}
              <div className="border border-pink-500/20 bg-pink-950/10 rounded-xl p-4 space-y-3">
                <h4 className="text-pink-400 font-semibold text-xs flex items-center gap-1.5">👧 {isAr ? 'مكافأة الفتاة / الأنثى عند تفعيل الارتباط (اختياري)' : 'Girl / Female Link Reward (Optional)'}</h4>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                  <div>
                    <label className="block text-[10px] text-slate-400 font-bold mb-1">{isAr ? 'اسم المكافأة' : 'Reward Name'}</label>
                    <input value={giftForm.femaleRewardName} onChange={e => updateForm(giftForm, setGiftForm, 'femaleRewardName', e.target.value)} placeholder={isAr ? 'مثال: تاج الأميرة الوردي' : 'e.g. Princess Crown'} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                  <div>
                    <label className="block text-[10px] text-slate-400 font-bold mb-1">{isAr ? 'نوع المكافأة' : 'Reward Type'}</label>
                    <select value={giftForm.femaleRewardType} onChange={e => updateForm(giftForm, setGiftForm, 'femaleRewardType', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                      <option value="frame">{isAr ? 'إطار (Frame)' : 'Frame'}</option>
                      <option value="badge">{isAr ? 'وسام (Badge)' : 'Badge'}</option>
                      <option value="necklace">{isAr ? 'قلادة (Necklace)' : 'Necklace'}</option>
                      <option value="ring">{isAr ? 'خاتم CP (Ring)' : 'Ring'}</option>
                      <option value="entrance">{isAr ? 'مآثر دخول (Entrance)' : 'Entrance'}</option>
                      <option value="coins">{isAr ? 'عملات فقط (Coins)' : 'Coins'}</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[10px] text-slate-400 font-bold mb-1">{isAr ? 'عملات إضافية' : 'Bonus Coins'}</label>
                    <input type="number" value={giftForm.femaleRewardCoins} onChange={e => updateForm(giftForm, setGiftForm, 'femaleRewardCoins', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                  <div>
                    <label className="block text-[10px] text-slate-400 font-bold mb-1">{isAr ? 'مدة المكافأة (أيام)' : 'Reward Validity (Days)'}</label>
                    <input type="number" min="1" value={giftForm.femaleRewardDays} onChange={e => updateForm(giftForm, setGiftForm, 'femaleRewardDays', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <ImageUpload currentUrl={giftForm.femaleRewardIcon} onUpload={file => uploadAppAsset(file, `cp_female_reward_icon_${Date.now()}`)} onUrlChange={url => updateForm(giftForm, setGiftForm, 'femaleRewardIcon', url)} label={isAr ? 'صورة/أيقونة مكافأة الفتاة' : 'Girl Reward Icon'} accept="image/*,.webp,.png" />
                  <ImageUpload currentUrl={giftForm.femaleRewardSvga} onUpload={file => uploadAppAsset(file, `cp_female_reward_svga_${Date.now()}`)} onUrlChange={url => updateForm(giftForm, setGiftForm, 'femaleRewardSvga', url)} label={isAr ? 'ملف SVGA لمكافأة الفتاة' : 'Girl Reward SVGA'} accept=".svga,.zip,.mp4,.vap" />
                </div>
              </div>

              <button onClick={editingGift ? handleSaveGift : handleAddGift} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
                <Save className="w-3 h-3" /> {editingGift ? (isAr ? 'حفظ' : 'Save') : (isAr ? 'إضافة' : 'Add')}
              </button>
            </div>
          )}

          <DataTable loading={loading} searchKeys={['name', 'nameAr', 'nameEn']}
            columns={[
              { key: 'iconUrl', label: '', render: (g: CpGiftModel) => g.iconUrl ? <img src={g.iconUrl} className="w-8 h-8 object-contain rounded" /> : <div className="w-8 h-8 rounded bg-slate-800 flex items-center justify-center text-lg">{isAr ? '🎁' : '🎁'}</div> },
              { key: 'nameAr', label: isAr ? 'الاسم' : 'Name', sortable: true },
              { key: 'value', label: isAr ? 'القيمة' : 'Value', sortable: true },
              { key: 'durationDays', label: isAr ? 'مدة الارتباط' : 'Duration', render: (g: CpGiftModel) => <span className="text-amber-400 font-semibold">{g.durationDays || (g.durationHours ? Math.round(g.durationHours / 24) : 1)} {isAr ? 'يوم' : 'days'}</span> },
              { key: 'sortOrder', label: 'Order', sortable: true },
              { key: 'isActive', label: isAr ? 'نشط' : 'Active', render: (g: CpGiftModel) => <span className={g.isActive ? 'text-emerald-400' : 'text-rose-400'}>{g.isActive ? (isAr ? 'نعم' : 'Yes') : (isAr ? 'لا' : 'No')}</span> },
            ]}
            data={gifts} onEdit={handleEditGift} onDelete={async (g) => { if (confirm(`Delete ${g.nameAr}?`)) { await deleteCpGift(g.id); loadGifts(); } }} />
        </div>
      )}

      {/* ════════════ LINK REWARDS TAB ════════════ */}
      {activeTab === 'linkRewards' && (
        <div className="space-y-6">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-white text-sm font-semibold">{isAr ? '💑 مكافآت الارتباط التلقائية (الشاب والفتاة)' : '💑 CP Link Rewards (Boy & Girl)'}</h3>
              <p className="text-slate-400 text-xs mt-0.5">{isAr ? 'المكافآت التي يستلمها كل من الرابط والمرتبط في حقيبته فور قبول طلب ارتباط الـ CP' : 'Rewards automatically granted to both partners upon CP link acceptance'}</p>
            </div>
            <button onClick={handleSaveSettings} disabled={savingSettings}
              className="px-4 py-2 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1.5 shadow-lg">
              <Save className="w-4 h-4" /> {savingSettings ? (isAr ? 'جاري الحفظ...' : 'Saving...') : (isAr ? 'حفظ إعدادات المكافآت' : 'Save Rewards')}
            </button>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Male Partner Global Reward */}
            <div className="bg-[#141417] rounded-2xl border border-blue-500/20 p-6 space-y-4">
              <div className="flex items-center justify-between border-b border-white/5 pb-3">
                <div className="flex items-center gap-2">
                  <span className="text-xl">👦</span>
                  <h4 className="text-blue-400 font-bold text-sm">{isAr ? 'مكافأة الشاب / الذكر (الرابط)' : 'Boy / Male Partner Reward'}</h4>
                </div>
                {storeItems.length > 0 && (
                  <div className="flex items-center gap-1.5">
                    <ShoppingBag className="w-3.5 h-3.5 text-blue-400" />
                    <select
                      onChange={e => {
                        const item = storeItems.find(s => s.itemId === e.target.value);
                        if (item) {
                          setCpSettings(p => ({
                            ...p,
                            cp_link_male_reward_name: item.name,
                            cp_link_male_reward_type: item.category === 'car' ? 'car' : item.category === 'entrance' ? 'entrance' : item.category === 'necklace' ? 'necklace' : item.category === 'badge' ? 'badge' : 'frame',
                            cp_link_male_reward_icon: item.iconAsset || '',
                            cp_link_male_reward_svga: item.svgaAsset || item.videoAsset || '',
                          }));
                        }
                      }}
                      defaultValue=""
                      className="bg-[#161618] border border-blue-500/30 text-blue-300 text-[11px] rounded-lg py-1 px-2"
                    >
                      <option value="">{isAr ? '🛍️ اختيار من المتجر...' : '🛍️ Pick from Store...'}</option>
                      {storeItems.map(item => (
                        <option key={item.itemId} value={item.itemId}>
                          {item.name} ({item.category}) {item.isHidden ? '🔒' : ''}
                        </option>
                      ))}
                    </select>
                  </div>
                )}
              </div>
              <div className="space-y-3">
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'اسم المكافأة' : 'Reward Name'}</label>
                  <input value={cpSettings['cp_link_male_reward_name'] ?? 'خاتم الـ CP الفضي'} onChange={e => setCpSettings(p => ({ ...p, cp_link_male_reward_name: e.target.value }))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div className="grid grid-cols-3 gap-3">
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'نوع المكافأة' : 'Reward Type'}</label>
                    <select value={cpSettings['cp_link_male_reward_type'] ?? 'ring'} onChange={e => setCpSettings(p => ({ ...p, cp_link_male_reward_type: e.target.value }))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                      <option value="frame">{isAr ? 'إطار (Frame)' : 'Frame'}</option>
                      <option value="badge">{isAr ? 'وسام (Badge)' : 'Badge'}</option>
                      <option value="necklace">{isAr ? 'قلادة (Necklace)' : 'Necklace'}</option>
                      <option value="ring">{isAr ? 'خاتم CP (Ring)' : 'Ring'}</option>
                      <option value="entrance">{isAr ? 'مآثر دخول (Entrance)' : 'Entrance'}</option>
                      <option value="car">{isAr ? 'سيارة (Car)' : 'Car'}</option>
                      <option value="coins">{isAr ? 'عملات فقط (Coins)' : 'Coins'}</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'عملات إضافية' : 'Bonus Coins'}</label>
                    <input type="number" value={cpSettings['cp_link_male_reward_coins'] ?? '0'} onChange={e => setCpSettings(p => ({ ...p, cp_link_male_reward_coins: e.target.value }))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'مدة المكافأة (أيام)' : 'Validity (Days)'}</label>
                    <input type="number" min="1" value={cpSettings['cp_link_male_reward_days'] ?? '7'} onChange={e => setCpSettings(p => ({ ...p, cp_link_male_reward_days: e.target.value }))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3 pt-2">
                  <ImageUpload currentUrl={cpSettings['cp_link_male_reward_icon'] ?? ''} onUpload={file => handleImageUpload(file, 'cp_link_male_reward_icon')} onUrlChange={url => setCpSettings(p => ({ ...p, cp_link_male_reward_icon: url }))} label={isAr ? 'صورة/أيقونة المكافأة' : 'Reward Icon'} accept="image/*,.webp,.png" />
                  <ImageUpload currentUrl={cpSettings['cp_link_male_reward_svga'] ?? ''} onUpload={file => handleImageUpload(file, 'cp_link_male_reward_svga')} onUrlChange={url => setCpSettings(p => ({ ...p, cp_link_male_reward_svga: url }))} label={isAr ? 'ملف SVGA للمكافأة' : 'Reward SVGA'} accept=".svga,.zip,.mp4,.vap" />
                </div>
              </div>
            </div>

            {/* Female Partner Global Reward */}
            <div className="bg-[#141417] rounded-2xl border border-pink-500/20 p-6 space-y-4">
              <div className="flex items-center justify-between border-b border-white/5 pb-3">
                <div className="flex items-center gap-2">
                  <span className="text-xl">👧</span>
                  <h4 className="text-pink-400 font-bold text-sm">{isAr ? 'مكافأة الفتاة / الأنثى (المرتبط)' : 'Girl / Female Partner Reward'}</h4>
                </div>
                {storeItems.length > 0 && (
                  <div className="flex items-center gap-1.5">
                    <ShoppingBag className="w-3.5 h-3.5 text-pink-400" />
                    <select
                      onChange={e => {
                        const item = storeItems.find(s => s.itemId === e.target.value);
                        if (item) {
                          setCpSettings(p => ({
                            ...p,
                            cp_link_female_reward_name: item.name,
                            cp_link_female_reward_type: item.category === 'car' ? 'car' : item.category === 'entrance' ? 'entrance' : item.category === 'necklace' ? 'necklace' : item.category === 'badge' ? 'badge' : 'frame',
                            cp_link_female_reward_icon: item.iconAsset || '',
                            cp_link_female_reward_svga: item.svgaAsset || item.videoAsset || '',
                          }));
                        }
                      }}
                      defaultValue=""
                      className="bg-[#161618] border border-pink-500/30 text-pink-300 text-[11px] rounded-lg py-1 px-2"
                    >
                      <option value="">{isAr ? '🛍️ اختيار من المتجر...' : '🛍️ Pick from Store...'}</option>
                      {storeItems.map(item => (
                        <option key={item.itemId} value={item.itemId}>
                          {item.name} ({item.category}) {item.isHidden ? '🔒' : ''}
                        </option>
                      ))}
                    </select>
                  </div>
                )}
              </div>
              <div className="space-y-3">
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'اسم المكافأة' : 'Reward Name'}</label>
                  <input value={cpSettings['cp_link_female_reward_name'] ?? 'خاتم الـ CP الوردي'} onChange={e => setCpSettings(p => ({ ...p, cp_link_female_reward_name: e.target.value }))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div className="grid grid-cols-3 gap-3">
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'نوع المكافأة' : 'Reward Type'}</label>
                    <select value={cpSettings['cp_link_female_reward_type'] ?? 'ring'} onChange={e => setCpSettings(p => ({ ...p, cp_link_female_reward_type: e.target.value }))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                      <option value="frame">{isAr ? 'إطار (Frame)' : 'Frame'}</option>
                      <option value="badge">{isAr ? 'وسام (Badge)' : 'Badge'}</option>
                      <option value="necklace">{isAr ? 'قلادة (Necklace)' : 'Necklace'}</option>
                      <option value="ring">{isAr ? 'خاتم CP (Ring)' : 'Ring'}</option>
                      <option value="entrance">{isAr ? 'مآثر دخول (Entrance)' : 'Entrance'}</option>
                      <option value="car">{isAr ? 'سيارة (Car)' : 'Car'}</option>
                      <option value="coins">{isAr ? 'عملات فقط (Coins)' : 'Coins'}</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'عملات إضافية' : 'Bonus Coins'}</label>
                    <input type="number" value={cpSettings['cp_link_female_reward_coins'] ?? '0'} onChange={e => setCpSettings(p => ({ ...p, cp_link_female_reward_coins: e.target.value }))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'مدة المكافأة (أيام)' : 'Validity (Days)'}</label>
                    <input type="number" min="1" value={cpSettings['cp_link_female_reward_days'] ?? '7'} onChange={e => setCpSettings(p => ({ ...p, cp_link_female_reward_days: e.target.value }))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3 pt-2">
                  <ImageUpload currentUrl={cpSettings['cp_link_female_reward_icon'] ?? ''} onUpload={file => handleImageUpload(file, 'cp_link_female_reward_icon')} onUrlChange={url => setCpSettings(p => ({ ...p, cp_link_female_reward_icon: url }))} label={isAr ? 'صورة/أيقونة المكافأة' : 'Reward Icon'} accept="image/*,.webp,.png" />
                  <ImageUpload currentUrl={cpSettings['cp_link_female_reward_svga'] ?? ''} onUpload={file => handleImageUpload(file, 'cp_link_female_reward_svga')} onUrlChange={url => setCpSettings(p => ({ ...p, cp_link_female_reward_svga: url }))} label={isAr ? 'ملف SVGA للمكافأة' : 'Reward SVGA'} accept=".svga,.zip,.mp4,.vap" />
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ════════════ CARS TAB ════════════ */}
      {activeTab === 'cars' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <p className="text-slate-500 text-xs">{cars.length} {isAr ? 'سيارة' : 'cars'}</p>
            <button onClick={() => { resetCarForm(); setShowAddCar(!showAddCar); }}
              className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
              <Plus className="w-3.5 h-3.5" /> {showAddCar ? (isAr ? 'إلغاء' : 'Cancel') : (isAr ? 'إضافة سيارة' : 'Add Car')}
            </button>
          </div>

          {(editingCar || showAddCar) && (
            <div className="bg-[#141417] rounded-2xl border border-indigo-500/20 p-6 space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-white font-semibold text-sm">{editingCar ? (isAr ? 'تعديل' : 'Edit') + ' ' + carForm.name : (isAr ? 'سيارة جديدة' : 'New Car')}</h3>
                <button onClick={resetCarForm} className="text-slate-400 hover:text-white"><X className="w-4 h-4" /></button>
              </div>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'الاسم (عربي)' : 'Name (Arabic)'}</label>
                  <input value={carForm.nameAr} onChange={e => updateForm(carForm, setCarForm, 'nameAr', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'الاسم (إنجليزي)' : 'Name (English)'}</label>
                  <input value={carForm.nameEn} onChange={e => updateForm(carForm, setCarForm, 'nameEn', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">Sort Order</label>
                  <input type="number" value={carForm.sortOrder} onChange={e => updateForm(carForm, setCarForm, 'sortOrder', Number(e.target.value))} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'نشط' : 'Active'}</label>
                  <label className="flex items-center gap-2 mt-1">
                    <input type="checkbox" checked={carForm.isActive} onChange={e => updateForm(carForm, setCarForm, 'isActive', e.target.checked)} className="w-4 h-4" />
                    <span className="text-xs text-slate-400">{carForm.isActive ? (isAr ? 'مفعل' : 'Enabled') : (isAr ? 'معطل' : 'Disabled')}</span>
                  </label>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <ImageUpload currentUrl={carForm.svgaUrl} onUpload={file => uploadAppAsset(file, `cp_car_svga_${Date.now()}`)} onUrlChange={url => updateForm(carForm, setCarForm, 'svgaUrl', url)} label={isAr ? 'ملف السيارة (SVGA)' : 'Car SVG/SVGA'} accept=".svga,.zip,.mp4,.vap,.webp,.png,.svg" />
                <ImageUpload currentUrl={carForm.thumbnailUrl} onUpload={file => uploadAppAsset(file, `cp_car_thumb_${Date.now()}`)} onUrlChange={url => updateForm(carForm, setCarForm, 'thumbnailUrl', url)} label={isAr ? 'صورة مصغرة' : 'Thumbnail'} accept="image/*,.webp,.png" />
              </div>
              <button onClick={editingCar ? handleSaveCar : handleAddCar} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
                <Save className="w-3 h-3" /> {editingCar ? (isAr ? 'حفظ' : 'Save') : (isAr ? 'إضافة' : 'Add')}
              </button>
            </div>
          )}

          <DataTable loading={loading} searchKeys={['name', 'nameAr', 'nameEn']}
            columns={[
              { key: 'thumbnailUrl', label: '', render: (c: CpCarModel) => c.thumbnailUrl ? <img src={c.thumbnailUrl} className="w-10 h-10 object-contain rounded" /> : <div className="w-10 h-10 rounded bg-slate-800 flex items-center justify-center text-lg">🚗</div> },
              { key: 'nameAr', label: isAr ? 'الاسم' : 'Name', sortable: true },
              { key: 'sortOrder', label: 'Order', sortable: true },
              { key: 'isActive', label: isAr ? 'نشط' : 'Active', render: (c: CpCarModel) => <span className={c.isActive ? 'text-emerald-400' : 'text-rose-400'}>{c.isActive ? (isAr ? 'نعم' : 'Yes') : (isAr ? 'لا' : 'No')}</span> },
            ]}
            data={cars} onEdit={handleEditCar} onDelete={async (c) => { if (confirm(`Delete ${c.nameAr}?`)) { await deleteCpCar(c.id); loadCars(); } }} />
        </div>
      )}

      {/* ════════════ RANK REWARDS TAB ════════════ */}
      {activeTab === 'rewards' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <p className="text-slate-500 text-xs">{rewardsLoading ? (isAr ? 'جارٍ التحميل...' : 'Loading...') : `${rewards.length} ${isAr ? 'مكافأة' : 'rewards'}`}</p>
            <button onClick={() => { resetRewardForm(); setShowAddReward(!showAddReward); }}
              className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
              <Plus className="w-3.5 h-3.5" /> {showAddReward ? (isAr ? 'إلغاء' : 'Cancel') : (isAr ? 'إضافة مكافأة' : 'Add Reward')}
            </button>
          </div>

          {/* Period filter tabs */}
          <div className="flex gap-2">
            {[
              { key: 'all', labelAr: 'الكل', labelEn: 'All' },
              { key: 'daily', labelAr: 'يومي', labelEn: 'Daily' },
              { key: 'weekly', labelAr: 'أسبوعي', labelEn: 'Weekly' },
              { key: 'monthly', labelAr: 'شهري', labelEn: 'Monthly' },
            ].map(tab => (
              <button key={tab.key} onClick={() => setRewardsPeriod(tab.key)}
                className={`px-3 py-1 rounded-lg text-[11px] font-semibold transition-colors ${rewardsPeriod === tab.key ? 'bg-indigo-600 text-white' : 'bg-white/5 text-slate-400 hover:bg-white/10'}`}>
                {isAr ? tab.labelAr : tab.labelEn}
              </button>
            ))}
          </div>

          {(editingReward || showAddReward) && (
            <div className="bg-[#141417] rounded-2xl border border-indigo-500/20 p-6 space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-white font-semibold text-sm">{editingReward ? (isAr ? 'تعديل' : 'Edit') : (isAr ? 'مكافأة جديدة' : 'New Reward')}</h3>
                <div className="flex items-center gap-3">
                  {storeItems.length > 0 && (
                    <div className="flex items-center gap-1.5">
                      <ShoppingBag className="w-3.5 h-3.5 text-amber-400" />
                      <select
                        onChange={e => {
                          const item = storeItems.find(s => s.itemId === e.target.value);
                          if (item) {
                            setRewardForm(p => ({
                              ...p,
                              label_ar: item.name,
                              label_en: item.name,
                              reward_type: item.category === 'entrance' ? 'entrance_svga' : item.category === 'badge' ? 'badge' : item.category === 'necklace' ? 'necklace' : 'frame_svga',
                              image_url: item.iconAsset || '',
                              svga_url: item.svgaAsset || item.videoAsset || '',
                            }));
                          }
                        }}
                        defaultValue=""
                        className="bg-[#161618] border border-amber-500/30 text-amber-300 text-[11px] rounded-lg py-1 px-2"
                      >
                        <option value="">{isAr ? '🛍️ اختيار من المتجر...' : '🛍️ Pick from Store...'}</option>
                        {storeItems.map(item => (
                          <option key={item.itemId} value={item.itemId}>
                            {item.name} ({item.category}) {item.isHidden ? '🔒' : ''}
                          </option>
                        ))}
                      </select>
                    </div>
                  )}
                  <button onClick={resetRewardForm} className="text-slate-400 hover:text-white"><X className="w-4 h-4" /></button>
                </div>
              </div>
              <div className="grid grid-cols-2 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'الفترة' : 'Period'}</label>
                  <select value={rewardForm.period} onChange={e => setRewardForm(p => ({ ...p, period: e.target.value }))}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                    <option value="daily">{isAr ? 'يومي' : 'Daily'}</option>
                    <option value="weekly">{isAr ? 'أسبوعي' : 'Weekly'}</option>
                    <option value="monthly">{isAr ? 'شهري' : 'Monthly'}</option>
                  </select>
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'المركز (الترتيب)' : 'Rank Position'}</label>
                  <select value={rewardForm.rank_position} onChange={e => setRewardForm(p => ({ ...p, rank_position: Number(e.target.value) }))}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                    {[1,2,3,4,5,6,7,8,9,10].map(n => (
                      <option key={n} value={n}>{isAr ? `Top ${n}` : `#${n}`}</option>
                    ))}
                  </select>
                  <p className="text-[10px] text-slate-500 mt-0.5">{isAr ? 'المركز اللي هتظهر فيه المكافأة (الأول = أعلى ترتيب)' : 'Which rank this reward belongs to (1 = highest)'}</p>
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'ترتيب الظهور' : 'Sort Order'}</label>
                  <input type="number" value={rewardForm.sort_order} onChange={e => setRewardForm(p => ({ ...p, sort_order: Number(e.target.value) }))}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  <p className="text-[10px] text-slate-500 mt-0.5">{isAr ? 'رقم 1 = أول مربع, 2 = ثاني مربع... (داخل نفس المركز)' : '1 = first box, 2 = second box... (within same rank)'}</p>
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'نوع المكافأة' : 'Reward Type'}</label>
                  <select value={rewardForm.reward_type} onChange={e => setRewardForm(p => ({ ...p, reward_type: e.target.value }))}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                    <option value="frame_svga">{isAr ? '🖼️ إطار SVGA' : '🖼️ Frame SVGA'}</option>
                    <option value="entrance_svga">{isAr ? '🚪 دخوله SVGA' : '🚪 Entrance SVGA'}</option>
                    <option value="entrance_effect">{isAr ? '✨ مآثر دخول' : '✨ Entrance Effect'}</option>
                    <option value="badge">{isAr ? '🏅 وسام' : '🏅 Badge'}</option>
                    <option value="necklace">{isAr ? '📿 قلاده' : '📿 Necklace'}</option>
                  </select>
                  <p className="text-[10px] text-slate-500 mt-0.5">{isAr ? 'نوع المكافأة يحدد مكان ظهورها في شاشة التصنيف (إطار = على الصورة)' : 'Reward type determines where it appears on the ranking screen'}</p>
                </div>
              </div>
              <div className="flex items-center gap-3 pt-1">
                <label className="flex items-center gap-2">
                  <input type="checkbox" checked={rewardForm.is_active} onChange={e => setRewardForm(p => ({ ...p, is_active: e.target.checked }))} className="w-4 h-4" />
                  <span className="text-xs text-slate-300">{isAr ? 'مفعلة (تظهر للمستخدمين)' : 'Active (visible to users)'}</span>
                </label>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'الاسم (عربي)' : 'Label (Arabic)'}</label>
                  <input value={rewardForm.label_ar} onChange={e => setRewardForm(p => ({ ...p, label_ar: e.target.value }))}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'الاسم (إنجليزي)' : 'Label (English)'}</label>
                  <input value={rewardForm.label_en} onChange={e => setRewardForm(p => ({ ...p, label_en: e.target.value }))}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <ImageUpload currentUrl={rewardForm.svga_url} onUpload={file => uploadAppAsset(file, `cp_reward_svga_${Date.now()}`)} onUrlChange={url => setRewardForm(p => ({ ...p, svga_url: url }))} label={isAr ? 'ملف المكافأة (SVGA)' : 'Reward SVGA'} accept=".svga,.zip,.mp4,.vap,.webp,.png,.svg" />
                <ImageUpload currentUrl={rewardForm.image_url} onUpload={file => uploadAppAsset(file, `cp_reward_img_${Date.now()}`)} onUrlChange={url => setRewardForm(p => ({ ...p, image_url: url }))} label={isAr ? 'صورة المكافأة' : 'Reward Image'} accept="image/*,.webp,.png" />
              </div>              <div className="flex gap-2">
                <button onClick={editingReward ? handleSaveReward : handleAddReward} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
                  <Save className="w-3 h-3" /> {editingReward ? (isAr ? 'حفظ' : 'Save') : (isAr ? 'إضافة' : 'Add')}
                </button>
              </div>
            </div>
          )}

          <div className="bg-[#141417] rounded-2xl border border-white/5 p-6">
            {(() => {
              const filtered = rewardsPeriod === 'all' ? rewards : rewards.filter(r => r.period === rewardsPeriod);
              const sorted = [...filtered].sort((a, b) => a.rank_position - b.rank_position || a.slot_index - b.slot_index);
              return sorted.length === 0 ? (
                <p className="text-slate-600 text-xs">{isAr ? 'لا توجد مكافآت' : 'No rewards configured'}</p>
              ) : (
                <div className="flex flex-wrap gap-3">
                  {sorted.map(r => (
                    <div key={r.id} className={`bg-[#161618] rounded-lg border p-3 w-36 ${r.isActive === false ? 'border-rose-500/20 opacity-70' : 'border-white/5'}`}>
                      <div className="flex items-center justify-between mb-1">
                        <span className={`text-[9px] px-1.5 py-0.5 rounded ${r.isActive === false ? 'bg-rose-600/20 text-rose-400' : 'bg-emerald-600/20 text-emerald-400'}`}>
                          {r.isActive === false ? (isAr ? 'معطلة' : 'Off') : (isAr ? 'مفعلة' : 'On')}
                        </span>
                        <button
                          onClick={async () => {
                            const next = r.isActive === false;
                            if (confirm((isAr ? `تفعيل المكافأة «${r.label_ar}»؟` : `Enable reward "${r.label_ar}"?`) + (next ? '' : (isAr ? '\nلن تظهر في التطبيق' : '\nIt will no longer appear in the app')))) {
                              await upsertCpRankReward(r.id, { ...r, isActive: next });
                              showMsg(next ? (isAr ? '✅ تم التفعيل' : '✅ Enabled') : (isAr ? '⏸️ تم التعطيل' : '⏸️ Disabled'));
                            }
                          }}
                          className={`px-2 py-0.5 text-[10px] rounded ${r.isActive === false ? 'bg-emerald-600/20 hover:bg-emerald-600/30 text-emerald-400' : 'bg-rose-600/20 hover:bg-rose-600/30 text-rose-400'}`}
                          title={isAr ? 'تفعيل/تعطيل' : 'Toggle active'}
                        >
                          {r.isActive === false ? (isAr ? 'تفعيل' : 'Enable') : (isAr ? 'تعطيل' : 'Disable')}
                        </button>
                      </div>
                      <div className="flex items-center justify-center h-16 mb-2">
                        {r.svga_url ? (
                          <img src={r.svga_url} className="w-12 h-12 object-contain rounded" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} />
                        ) : r.image_url ? (
                          <img src={r.image_url} className="w-12 h-12 object-contain rounded" />
                        ) : (
                          <div className="w-12 h-12 rounded bg-slate-700 flex items-center justify-center text-lg">🏆</div>
                        )}
                      </div>
                      <p className="text-white text-xs text-center truncate">{r.label_ar}</p>
                      <p className="text-slate-500 text-[10px] text-center truncate">{r.label_en}</p>
                      <div className="flex items-center justify-center gap-1 mt-1">
                        <span className="bg-amber-600/20 text-amber-400 text-[10px] px-1.5 py-0.5 rounded">{isAr ? 'ترتيب' : 'Rank'} #{r.rank_position}</span>
                        <span className="bg-indigo-600/20 text-indigo-400 text-[10px] px-1.5 py-0.5 rounded">{isAr ? 'ظهور' : 'Slot'} {r.slot_index}</span>
                      </div>
                      <div className="flex gap-1 mt-2 justify-center">
                        <button onClick={() => handleEditReward(r)} className="px-2 py-0.5 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-400 text-[10px] rounded">{isAr ? 'تعديل' : 'Edit'}</button>
                        <button onClick={async () => { if (confirm(`Delete ${r.label_ar}?`)) { await deleteCpRankReward(r.id); loadRewards(); } }} className="px-2 py-0.5 bg-rose-600/20 hover:bg-rose-600/30 text-rose-400 text-[10px] rounded">{isAr ? 'حذف' : 'Delete'}</button>
                      </div>
                    </div>
                  ))}
                </div>
              );
            })()}
          </div>
        </div>
      )}

      {/* ════════════ REWARDS CONFIG TAB ════════════ */}
      {activeTab === 'rewardsConfig' && (
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-6">
          <div className="flex items-center justify-between">
            <h3 className="text-white text-sm font-semibold">{isAr ? '⚙️ إعدادات شاشة المكافآت' : '⚙️ Rewards Screen Settings'}</h3>
            <button onClick={handleSaveSettings} disabled={savingSettings}
              className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
              <Save className="w-3.5 h-3.5" /> {savingSettings ? (isAr ? 'جاري الحفظ...' : 'Saving...') : (isAr ? 'حفظ الكل' : 'Save All')}
            </button>
          </div>

          {/* عدد أيام كل فترة */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {[
              { key: 'rewards_daily_days', labelAr: 'عدد أيام اليومي', labelEn: 'Daily Days', def: '1' },
              { key: 'rewards_weekly_days', labelAr: 'عدد أيام الأسبوعي', labelEn: 'Weekly Days', def: '7' },
              { key: 'rewards_monthly_days', labelAr: 'عدد أيام الشهري', labelEn: 'Monthly Days', def: '30' },
            ].map(({ key, labelAr, labelEn, def }) => (
              <div key={key}>
                <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? labelAr : labelEn}</label>
                <input type="number" value={cpSettings[key] ?? def} onChange={e => setCpSettings(p => ({ ...p, [key]: e.target.value }))}
                  className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
              </div>
            ))}
          </div>

          <div className="border-t border-white/5 pt-4">
            <h4 className="text-white text-xs font-semibold mb-3">{isAr ? '🕐 وقت الحدث' : '🕐 Event Time'}</h4>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {[
                { key: 'rewards_event_enabled', labelAr: 'تفعيل الحدث', labelEn: 'Event Enabled', type: 'toggle' },
                { key: 'rewards_event_start', labelAr: 'بداية الحدث', labelEn: 'Event Start', type: 'datetime' },
                { key: 'rewards_event_end', labelAr: 'نهاية الحدث', labelEn: 'Event End', type: 'datetime' },
              ].map(({ key, labelAr, labelEn, type }) => {
                const val = cpSettings[key] ?? (type === 'toggle' ? 'true' : '');
                return (
                  <div key={key}>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? labelAr : labelEn}</label>
                    {type === 'toggle' ? (
                      <select value={val} onChange={e => setCpSettings(p => ({ ...p, [key]: e.target.value }))}
                        className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                        <option value="true">{isAr ? 'مفعل' : 'Enabled'}</option>
                        <option value="false">{isAr ? 'معطل' : 'Disabled'}</option>
                      </select>
                    ) : (
                      <input type="datetime-local" value={val} onChange={e => setCpSettings(p => ({ ...p, [key]: e.target.value }))}
                        className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          <div className="border-t border-white/5 pt-4">
            <h4 className="text-white text-xs font-semibold mb-3">{isAr ? '👁️ إظهار/إخفاء الفترات' : '👁️ Show/Hide Periods'}</h4>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {[
                { key: 'rewards_show_daily', labelAr: 'إظهار اليومي', labelEn: 'Show Daily' },
                { key: 'rewards_show_weekly', labelAr: 'إظهار الأسبوعي', labelEn: 'Show Weekly' },
                { key: 'rewards_show_monthly', labelAr: 'إظهار الشهري', labelEn: 'Show Monthly' },
              ].map(({ key, labelAr, labelEn }) => {
                const val = cpSettings[key] ?? 'true';
                return (
                  <div key={key}>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? labelAr : labelEn}</label>
                    <select value={val} onChange={e => setCpSettings(p => ({ ...p, [key]: e.target.value }))}
                      className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                      <option value="true">{isAr ? 'ظاهر' : 'Visible'}</option>
                      <option value="false">{isAr ? 'مخفي' : 'Hidden'}</option>
                    </select>
                  </div>
                );
              })}
            </div>
          </div>

          <div className="border-t border-white/5 pt-4">
            <label className="flex items-center gap-2 mb-3">
              <span className="text-white text-xs font-semibold">{isAr ? '📦 إظهار صناديق الجوائز' : '📦 Show Reward Boxes'}</span>
              <select value={cpSettings['rewards_show_boxes'] ?? 'true'} onChange={e => setCpSettings(p => ({ ...p, rewards_show_boxes: e.target.value }))}
                className="bg-[#161618] border border-white/10 rounded-lg py-1 px-2 text-xs text-white">
                <option value="true">{isAr ? 'ظاهر' : 'Visible'}</option>
                <option value="false">{isAr ? 'مخفي' : 'Hidden'}</option>
              </select>
            </label>
          </div>

          <div className="border-t border-white/5 pt-4">
            <h4 className="text-white text-xs font-semibold mb-3">{isAr ? '🖼️ خلفية مربع المكافأة' : '🖼️ Reward Box Background'}</h4>
            <p className="text-[10px] text-slate-500 mb-2">{isAr ? 'الصورة دي تظهر كخلفية لكل مربعات المكافآت (بتطبق على الكل)' : 'This image appears as background for all reward boxes (applies to all)'}</p>
            <ImageUpload currentUrl={cpSettings['rewards_box_bg'] ?? ''} onUpload={file => handleImageUpload(file, 'rewards_box_bg')} onUrlChange={url => setCpSettings(p => ({ ...p, rewards_box_bg: url }))} label={isAr ? 'خلفية المربع' : 'Box Background'} accept="image/*,.webp,.png,.svg" />
          </div>

          <div className="border-t border-white/5 pt-4">
            <h4 className="text-white text-xs font-semibold mb-3">{isAr ? '📝 نص القواعد' : '📝 Rules Text'}</h4>
            <div className="space-y-3">
              <div>
                <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'القواعد (عربي)' : 'Rules (Arabic)'}</label>
                <textarea value={cpSettings['rewards_rules_ar'] ?? ''} onChange={e => setCpSettings(p => ({ ...p, rewards_rules_ar: e.target.value }))} rows={4}
                  className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
              </div>
              <div>
                <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'القواعد (إنجليزي)' : 'Rules (English)'}</label>
                <textarea value={cpSettings['rewards_rules_en'] ?? ''} onChange={e => setCpSettings(p => ({ ...p, rewards_rules_en: e.target.value }))} rows={4}
                  className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ════════════ AUTO-DISTRIBUTION TAB ════════════ */}
      {activeTab === 'autoDist' && (
        <div className="space-y-4">
          <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-6">
            <div className="flex items-center justify-between">
              <h3 className="text-white text-sm font-semibold">{isAr ? '⚡ إعدادات التوزيع التلقائي' : '⚡ Auto-Distribution Settings'}</h3>
            </div>

            {rewardConfig && (
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'نوع الفترة' : 'Period Type'}</label>
                  <select value={rewardConfig.period_type} onChange={e => setRewardConfig((p: any) => ({ ...p, period_type: e.target.value }))}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                    <option value="daily">{isAr ? 'يومي' : 'Daily'}</option>
                    <option value="weekly">{isAr ? 'أسبوعي' : 'Weekly'}</option>
                    <option value="monthly">{isAr ? 'شهري' : 'Monthly'}</option>
                    <option value="custom">{isAr ? 'مخصص (أيام)' : 'Custom (Days)'}</option>
                  </select>
                </div>
                {rewardConfig.period_type === 'custom' && (
                  <div>
                    <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'عدد الأيام المخصصة' : 'Custom Days'}</label>
                    <input type="number" value={rewardConfig.custom_days} onChange={e => setRewardConfig((p: any) => ({ ...p, custom_days: Number(e.target.value) }))}
                      className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  </div>
                )}
                <div>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? 'مدة صلاحية المكافأة (أيام)' : 'Reward Duration (Days)'}</label>
                  <input type="number" value={rewardConfig.reward_duration_days} onChange={e => setRewardConfig((p: any) => ({ ...p, reward_duration_days: Number(e.target.value) }))}
                    className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  <p className="text-[10px] text-slate-500 mt-0.5">{isAr ? 'بعد هذه المدة، المكافأة تتحذف تلقائياً من المستخدم' : 'After this, rewards auto-remove from user'}</p>
                </div>
              </div>
            )}

            {rewardConfig?.next_distribution && new Date(rewardConfig.next_distribution).getTime() > 0 && (
              <div className="bg-indigo-600/10 border border-indigo-500/20 rounded-lg p-3 text-xs text-indigo-300">
                <span className="font-semibold">{isAr ? '⏰ التوزيع القادم:' : '⏰ Next Distribution:'}</span>{' '}
                {new Date(rewardConfig.next_distribution).toLocaleDateString(isAr ? 'ar-EG' : 'en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', hour: '2-digit', minute: '2-digit' })}
              </div>
            )}

            <div className="flex items-center gap-3 pt-2">
              <button onClick={async () => {
                await saveCpRewardConfig(rewardConfig);
                showMsg(isAr ? '✅ تم حفظ الإعدادات' : '✅ Settings saved');
              }} className="px-4 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
                <Save className="w-3.5 h-3.5" /> {isAr ? 'حفظ الإعدادات' : 'Save Settings'}
              </button>
              <button onClick={async () => {
                setDistributing(true);
                try {
                  const r = await distributeCpRewards();
                  showMsg(r.success ? `✅ ${r.message}` : `❌ ${r.message}`);
                  await loadAutoDist();
                } finally { setDistributing(false); }
              }} disabled={distributing} className="px-4 py-1.5 bg-amber-600 hover:bg-amber-700 disabled:opacity-50 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
                <RefreshCw className={`w-3.5 h-3.5 ${distributing ? 'animate-spin' : ''}`} /> {distributing ? (isAr ? 'جاري التوزيع...' : 'Distributing...') : (isAr ? '🔄 توزيع الآن' : 'Distribute Now')}
              </button>
              <button onClick={async () => {
                setExpiring(true);
                try {
                  const r = await expireCpRewards();
                  showMsg(r.removed > 0 ? `✅ تم حذف ${r.removed} مكافأة منتهية` : (isAr ? 'ℹ️ لا توجد مكافآت منتهية' : 'ℹ️ No expired rewards'));
                  await loadAutoDist();
                } finally { setExpiring(false); }
              }} disabled={expiring} className="px-4 py-1.5 bg-rose-600/80 hover:bg-rose-700 disabled:opacity-50 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
                <Trash2 className="w-3.5 h-3.5" /> {expiring ? (isAr ? 'جاري التنظيف...' : 'Cleaning...') : (isAr ? '🧹 تنظيف المنتهية' : 'Clean Expired')}
              </button>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="bg-[#141417] rounded-2xl border border-white/5 p-6">
              <h4 className="text-white text-xs font-semibold mb-3">{isAr ? '📊 المكافآت النشطة حالياً' : '📊 Active Rewards'}</h4>
              <p className="text-2xl text-emerald-400 font-bold">{activeRewardsCount}</p>
              <p className="text-[10px] text-slate-500 mt-1">{isAr ? 'إجمالي المكافآت الموزعة على المستخدمين ولم تنتهِ صلاحيتها بعد' : 'Total rewards distributed to users not yet expired'}</p>
            </div>
            <div className="bg-[#141417] rounded-2xl border border-white/5 p-6">
              <h4 className="text-white text-xs font-semibold mb-3">{isAr ? '📜 سجل التوزيع' : '📜 Distribution History'}</h4>
              <div className="max-h-48 overflow-y-auto space-y-1">
                {history.length === 0 ? (
                  <p className="text-slate-600 text-xs">{isAr ? 'لا يوجد سجل بعد' : 'No history yet'}</p>
                ) : (
                  [...history].reverse().map((h: any, i: number) => (
                    <div key={i} className="bg-[#161618] rounded px-2 py-1">
                      <p className="text-[10px] text-slate-400">{new Date(h.timestamp).toLocaleString(isAr ? 'ar-EG' : 'en-US')}</p>
                      {h.details?.map((d: any, j: number) => (
                        <p key={j} className="text-[10px] text-white">
                          #{d.rank} — {d.user1?.slice(0, 8)}... + {d.user2?.slice(0, 8)}... ({d.score} pts, {d.rewards} item(s))
                        </p>
                      ))}
                    </div>
                  ))
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ════════════ EVENTS & PRIZES TAB ════════════ */}
      {activeTab === 'events' && (
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-6">
          <div className="flex items-center justify-between">
            <h3 className="text-white text-sm font-semibold">{isAr ? '📅 الأحداث والجوائز الأسبوعية' : '📅 Events & Weekly Prizes'}</h3>
            <button onClick={handleSaveSettings} disabled={savingSettings}
              className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
              <Save className="w-3.5 h-3.5" /> {savingSettings ? (isAr ? 'جاري الحفظ...' : 'Saving...') : (isAr ? 'حفظ الكل' : 'Save All')}
            </button>
          </div>

          <div className="space-y-4">
            {eventSettingKeys.map(({ key, labelAr, labelEn, type, options }) => {
              const val = cpSettings[key] || '';
              return (
                <div key={key}>
                  <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{isAr ? labelAr : labelEn}</label>
                  {type === 'select' ? (
                    <select value={val} onChange={e => setCpSettings(p => ({ ...p, [key]: e.target.value }))}
                      className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white">
                      {options?.map(o => <option key={o} value={o}>{o}</option>)}
                    </select>
                  ) : type === 'date' ? (
                    <input type="date" value={val} onChange={e => setCpSettings(p => ({ ...p, [key]: e.target.value }))}
                      className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  ) : type === 'number' ? (
                    <input type="number" value={val} onChange={e => setCpSettings(p => ({ ...p, [key]: e.target.value }))}
                      className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  ) : type === 'textarea' ? (
                    <textarea value={val} onChange={e => setCpSettings(p => ({ ...p, [key]: e.target.value }))} rows={2}
                      className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" />
                  ) : type === 'image' ? (
                    <div className="flex gap-2 items-start">
                      <input type="text" value={val} onChange={e => setCpSettings(p => ({ ...p, [key]: e.target.value }))}
                        className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" placeholder="URL" />
                      <label className="cursor-pointer px-2 py-1.5 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-400 rounded-lg">
                        <Upload className="w-3.5 h-3.5" />
                        <input type="file" accept="image/*,.svga,.mp4,.webp,.vap,.json" className="hidden" onChange={e => { const file = e.target.files?.[0]; if (file) handleImageUpload(file, key); }} />
                      </label>
                    </div>
                  ) : (
                    <input type="text" value={val} onChange={e => setCpSettings(p => ({ ...p, [key]: e.target.value }))}
                      className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white" placeholder={isAr ? labelAr : labelEn} />
                  )}
                  {(type === 'image' && val) && (
                    val.endsWith('.mp4') || val.endsWith('.webm') ?
                      <video src={val} className="mt-1 w-20 h-20 object-contain rounded border border-white/5" controls /> :
                      <img src={val} alt={labelAr} className="mt-1 w-20 h-20 object-contain rounded border border-white/5" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} />
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* ════════════ SETTINGS TAB ════════════ */}
      {activeTab === 'settings' && (
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-6">
          <h3 className="text-white text-sm font-semibold">{isAr ? '⚙️ إعدادات CP' : '⚙️ CP Settings'}</h3>

          {/* Bond gift selector — multi-select grid from main gifts table */}
          <div className="bg-[#161618] rounded-lg border border-indigo-500/20 p-4 space-y-3">
            <div className="flex items-center justify-between">
              <h4 className="text-white text-xs font-semibold">{isAr ? '🎁 هدايا ربط CP — اختر مجموعة من الهدايا الرئيسية' : '🎁 CP Bond Gifts — Select Multiple from Main Gifts'}</h4>
              <button onClick={() => { setSettingsLoadingGifts(true); getGifts().then(mg => { setMainGifts(mg); setSettingsLoadingGifts(false); }).catch(() => setSettingsLoadingGifts(false)); }}
                className="px-2 py-1 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-400 text-[10px] rounded flex items-center gap-1">
                <RefreshCw className={`w-3 h-3 ${settingsLoadingGifts ? 'animate-spin' : ''}`} /> {isAr ? 'تحديث' : 'Refresh'}
              </button>
            </div>
            <p className="text-[10px] text-slate-500">{isAr ? 'اضغط على الهدايا اللي عايزها تكون هدايا ربط CP (اللي يقدر المستخدم يختار منها ويرسلها لربط العلاقة). اختر واحدة أو أكتر.' : 'Tap the gifts you want as CP bond gifts (users can pick from these to initiate a CP relationship). Select one or more.'}</p>
            <div className="flex flex-wrap gap-3">
              {settingsLoadingGifts ? (
                <div className="flex items-center gap-2 py-4">
                  <RefreshCw className="w-4 h-4 animate-spin text-indigo-400" />
                  <span className="text-slate-400 text-xs">{isAr ? 'جاري التحميل...' : 'Loading...'}</span>
                </div>
              ) : mainGifts.map(g => {
                const isSelected = bondGiftIds.includes(g.id);
                const icon = g.iconAsset || g.defaultImage || '';
                return (
                  <div key={g.id} onClick={() => setBondGiftIds(prev => prev.includes(g.id) ? prev.filter(id => id !== g.id) : [...prev, g.id])}
                    className={`relative w-28 cursor-pointer rounded-lg border-2 p-3 text-center transition-all ${
                      isSelected
                        ? 'border-emerald-400 bg-emerald-900/30 shadow-lg shadow-emerald-500/20'
                        : 'border-white/10 bg-[#141417] hover:border-indigo-400/50'
                    }`}>
                    {isSelected && (
                      <div className="absolute -top-2 -right-2 w-5 h-5 bg-emerald-500 rounded-full flex items-center justify-center">
                        <span className="text-white text-[10px]">✓</span>
                      </div>
                    )}
                    <div className="flex items-center justify-center h-14 mb-1">
                      {icon ? (
                        <img src={icon} className="w-10 h-10 object-contain rounded" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} />
                      ) : (
                        <div className="w-10 h-10 rounded bg-slate-700 flex items-center justify-center text-lg">🎁</div>
                      )}
                    </div>
                    <p className="text-white text-[11px] truncate">{g.name}</p>
                    <p className="text-amber-400 text-[10px]">{g.value} <span className="text-slate-500">coin</span></p>
                    {g.animationAsset && <p className="text-indigo-400 text-[9px] truncate mt-0.5">{isAr ? 'رسوم متحركة ✓' : 'Animation ✓'}</p>}
                  </div>
                );
              })}
              {!settingsLoadingGifts && mainGifts.length === 0 && (
                <p className="text-slate-500 text-xs py-4">{isAr ? 'لا توجد هدايا رئيسية مضافة. أضف هدايا من قسم "الهدايا" أولاً.' : 'No main gifts yet. Add them from the "Gifts" section first.'}</p>
              )}
            </div>
            <div className="flex items-center gap-2 pt-2 border-t border-white/5">
              <p className="text-[10px] text-slate-500 flex-1">
                {bondGiftIds.length > 0
                  ? isAr ? `✓ تم اختيار ${bondGiftIds.length} هدية` : `✓ ${bondGiftIds.length} gift(s) selected`
                  : isAr ? 'لم يتم اختيار أي هدية' : 'No gifts selected'}
              </p>
              <div className="flex gap-2">
                <button onClick={() => setBondGiftIds([])} disabled={bondGiftIds.length === 0}
                  className="px-3 py-1.5 bg-rose-600/30 hover:bg-rose-700/50 disabled:opacity-30 disabled:cursor-not-allowed text-xs text-rose-300 font-semibold rounded-lg">
                  {isAr ? 'إلغاء التحديد' : 'Clear'}
                </button>
                <button onClick={async () => {
                  setSavingSettings(true);
                  const json = JSON.stringify(bondGiftIds);
                  await updateCpSetting('cp_bond_gift_ids', json);
                  await updateCpSetting('cp_bond_gift_id', bondGiftIds[0] || '');
                  setCpSettings(p => ({ ...p, cp_bond_gift_ids: json, cp_bond_gift_id: bondGiftIds[0] || '' }));
                  setSavingSettings(false);
                  showMsg(isAr ? `✅ تم حفظ ${bondGiftIds.length} هدية ربط` : `✅ ${bondGiftIds.length} bond gift(s) saved`);
                }} disabled={savingSettings || bondGiftIds.length === 0}
                  className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 disabled:cursor-not-allowed text-xs text-white font-semibold rounded-lg">
                  {savingSettings ? '...' : (isAr ? 'حفظ المجموعة' : 'Save Selection')}
                </button>
              </div>
            </div>
          </div>

          <div className="text-xs text-slate-400 space-y-2">
            <p>{isAr ? 'جميع الإعدادات الحالية من قاعدة البيانات:' : 'All current CP settings:'}</p>
            <div className="grid grid-cols-2 gap-2 mt-4">
              {Object.entries(cpSettings).map(([key, value]) => (
                <div key={key} className="bg-[#161618] rounded-lg p-3 border border-white/5">
                  <span className="text-[10px] text-indigo-400 font-mono">{key}</span>
                  <p className="text-white text-xs mt-1 break-all">{value || '(empty)'}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
