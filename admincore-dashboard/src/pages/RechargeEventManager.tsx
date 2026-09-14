import { useEffect, useState } from 'react';
import { getAppConfig, updateAppConfig } from '../lib/db';
import { uploadAppAsset } from '../lib/storage';
import { 
  Save, Upload, Eye, Plus, Trash2, Edit2, Palette, CheckCircle2, 
  Sparkles, Image as ImageIcon, Smartphone, Layers, Crown, Coins
} from 'lucide-react';
import { to6Hex } from '../lib/colors';

export interface RechargeTier {
  tier: number;
  requiredCoins: number;
  rewardLabel: string;
  rewardCoins: number;
  icon: string;
  svga: string;
  daysValid: number;
  tagText?: string;
}

const DEFAULT_TIERS: RechargeTier[] = [
  { tier: 1, requiredCoins: 100000, rewardLabel: '100K', rewardCoins: 5000, icon: 'assets/recharge_event/100K.png', svga: '100k.svga', daysValid: 7, tagText: 'HOT' },
  { tier: 2, requiredCoins: 500000, rewardLabel: '500K', rewardCoins: 30000, icon: 'assets/recharge_event/500K.png', svga: '500k.svga', daysValid: 15, tagText: 'VIP' },
  { tier: 3, requiredCoins: 1000000, rewardLabel: '1M', rewardCoins: 70000, icon: 'assets/recharge_event/1M.png', svga: '1M.svga', daysValid: 30, tagText: '1M' },
  { tier: 4, requiredCoins: 5000000, rewardLabel: '5M', rewardCoins: 400000, icon: 'assets/recharge_event/5M.png', svga: '5M.svga', daysValid: 30, tagText: '5M' },
  { tier: 5, requiredCoins: 10000000, rewardLabel: '10M', rewardCoins: 900000, icon: 'assets/recharge_event/10M.png', svga: '10M.svga', daysValid: 60, tagText: '10M' },
  { tier: 6, requiredCoins: 20000000, rewardLabel: '20M', rewardCoins: 2000000, icon: 'assets/recharge_event/20M.png', svga: '20m.svga', daysValid: 60, tagText: '20M' },
  { tier: 7, requiredCoins: 40000000, rewardLabel: '40M', rewardCoins: 4500000, icon: 'assets/recharge_event/40M.png', svga: '40M.svga', daysValid: 90, tagText: '40M' },
  { tier: 8, requiredCoins: 60000000, rewardLabel: '60M', rewardCoins: 7000000, icon: 'assets/recharge_event/60M.png', svga: '60M.svga', daysValid: 90, tagText: '60M' },
  { tier: 9, requiredCoins: 80000000, rewardLabel: '80M', rewardCoins: 10000000, icon: 'assets/recharge_event/80M.png', svga: '80M.svga', daysValid: 90, tagText: '80M' },
  { tier: 10, requiredCoins: 100000000, rewardLabel: '100M', rewardCoins: 14000000, icon: 'assets/recharge_event/100M.png', svga: '100M.svga', daysValid: 180, tagText: '100M' },
  { tier: 11, requiredCoins: 200000000, rewardLabel: '200M', rewardCoins: 30000000, icon: 'assets/recharge_event/200M.png', svga: '200M.svga', daysValid: 180, tagText: '200M' },
  { tier: 12, requiredCoins: 300000000, rewardLabel: '300M', rewardCoins: 50000000, icon: 'assets/recharge_event/300M.png', svga: '300M.svga', daysValid: 365, tagText: '300M' },
  { tier: 13, requiredCoins: 400000000, rewardLabel: '400M', rewardCoins: 75000000, icon: 'assets/recharge_event/400M.png', svga: '400M.svga', daysValid: 365, tagText: '400M' },
  { tier: 14, requiredCoins: 500000000, rewardLabel: '500M', rewardCoins: 100000000, icon: 'assets/recharge_event/500M.png', svga: '500M.svga', daysValid: 365, tagText: '500M' }
];

export default function RechargeEventManager() {
  const [tiers, setTiers] = useState<RechargeTier[]>(DEFAULT_TIERS);
  const [activeTab, setActiveTab] = useState<'tiers' | 'design' | 'preview'>('tiers');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState('');
  const [previewTier, setPreviewTier] = useState<RechargeTier | null>(null);

  // Settings matching D:40 layout & customizations
  const [title, setTitle] = useState('اشحن واحصل على مكافآت ملكية فورية');
  const [titleColor, setTitleColor] = useState('#FFFFFF');
  const [headerTextImage, setHeaderTextImage] = useState('');
  
  // Assets Overrides
  const [dialogBgImage, setDialogBgImage] = useState('assets/recharge_event/recharge_remind_dialog_bg.webp');
  const [itemBgImage, setItemBgImage] = useState('assets/recharge_event/recharge_remind_item_bg.webp');
  const [tagImage, setTagImage] = useState('assets/recharge_event/recharge_remind_tag_ic.png');
  const [coinsImage, setCoinsImage] = useState('assets/recharge_event/recharge_remind_coins_ic.webp');
  const [btnImage, setBtnImage] = useState('assets/recharge_event/recharge_remind_btn_ic.webp');
  const [closeBtnImage, setCloseBtnImage] = useState('assets/recharge_event/recharge_remind_close_ic.png');

  // Text & Colors
  const [btnText, setBtnText] = useState('اشحن الآن');
  const [btnTextColor, setBtnTextColor] = useState('#441200');
  const [tagTextColor, setTagTextColor] = useState('#FFE957');
  const [itemLabelColor, setItemLabelColor] = useState('#FFE957');
  const [overlayBgColor, setOverlayBgColor] = useState('#000000B3');

  // Modal for Tier Add/Edit
  const [editingIndex, setEditingIndex] = useState<number | null>(null);
  const [showModal, setShowModal] = useState(false);
  const [modalForm, setModalForm] = useState<RechargeTier>({
    tier: 15, requiredCoins: 600000000, rewardLabel: '600M', rewardCoins: 120000000, icon: '', svga: '', daysValid: 365, tagText: '600M'
  });

  useEffect(() => {
    (async () => {
      try {
        const cfg = await getAppConfig();
        if (cfg) {
          const raw = cfg as any;
          if (raw.recharge_event_tiers && Array.isArray(raw.recharge_event_tiers) && raw.recharge_event_tiers.length > 0) {
            setTiers(raw.recharge_event_tiers);
          }
          const s = raw.recharge_event_settings || {};
          if (s.title !== undefined) setTitle(s.title);
          if (s.titleColor) setTitleColor(s.titleColor);
          if (s.headerTextImage) setHeaderTextImage(s.headerTextImage);
          if (s.dialogBgImage) setDialogBgImage(s.dialogBgImage);
          if (s.itemBgImage) setItemBgImage(s.itemBgImage);
          if (s.tagImage) setTagImage(s.tagImage);
          if (s.coinsImage) setCoinsImage(s.coinsImage);
          if (s.btnImage) setBtnImage(s.btnImage);
          if (s.btnText !== undefined) setBtnText(s.btnText);
          if (s.btnTextColor) setBtnTextColor(s.btnTextColor);
          if (s.tagTextColor) setTagTextColor(s.tagTextColor);
          if (s.itemLabelColor) setItemLabelColor(s.itemLabelColor);
          if (s.overlayBgColor) setOverlayBgColor(s.overlayBgColor);
        }
      } catch (e) {
        console.warn(e);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const showNotification = (text: string) => {
    setMsg(text);
    setTimeout(() => setMsg(''), 3500);
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      await updateAppConfig({
        recharge_event_tiers: tiers,
        recharge_event_settings: {
          title, titleColor, headerTextImage,
          dialogBgImage, itemBgImage, tagImage, coinsImage, btnImage, closeBtnImage,
          btnText, btnTextColor, tagTextColor, itemLabelColor, overlayBgColor
        }
      } as any);
      showNotification('✅ تم حفظ إعدادات وحدث الشحن المطابق لـ D:40 بنجاح!');
    } catch (e) {
      showNotification('❌ فشل الحفظ، يرجى المحاولة لاحقاً');
    } finally {
      setSaving(false);
    }
  };

  const handleUploadFile = async (file: File, folder: string, onUploaded: (url: string) => void) => {
    try {
      const path = `recharge_event/${folder}/${Date.now()}_${file.name}`;
      const url = await uploadAppAsset(file, path);
      if (url) {
        onUploaded(url);
        showNotification('✅ تم رفع الملف بنجاح!');
      }
    } catch {
      showNotification('❌ فشل رفع الملف');
    }
  };

  const openAdd = () => {
    const nextTier = tiers.length > 0 ? Math.max(...tiers.map(t => t.tier)) + 1 : 1;
    setEditingIndex(null);
    setModalForm({
      tier: nextTier,
      requiredCoins: 600000000,
      rewardLabel: nextTier + '00M',
      rewardCoins: 120000000,
      icon: '',
      svga: '',
      daysValid: 365,
      tagText: nextTier + '00M'
    });
    setShowModal(true);
  };

  const openEdit = (idx: number) => {
    setEditingIndex(idx);
    setModalForm({ ...tiers[idx] });
    setShowModal(true);
  };

  const saveModal = () => {
    if (editingIndex !== null) {
      const copy = [...tiers];
      copy[editingIndex] = { ...modalForm };
      copy.sort((a, b) => a.requiredCoins - b.requiredCoins);
      setTiers(copy);
    } else {
      const copy = [...tiers, { ...modalForm }];
      copy.sort((a, b) => a.requiredCoins - b.requiredCoins);
      setTiers(copy);
    }
    setShowModal(false);
    showNotification('تم تحديث المستوى في القائمة (اضغط حفظ التعديلات للتثبيت)');
  };

  const deleteTier = (idx: number) => {
    if (confirm('هل أنت متأكد من حذف هذا المستوى والمكافأة؟')) {
      setTiers(tiers.filter((_, i) => i !== idx));
      showNotification('تم حذف المستوى من القائمة');
    }
  };

  const resetToD40Defaults = () => {
    if (confirm('هل تريد استعادة التصميم الأصلي الافتراضي لـ D:40؟')) {
      setTiers(DEFAULT_TIERS);
      setTitle('اشحن واحصل على مكافآت ملكية فورية');
      setTitleColor('#FFFFFF');
      setHeaderTextImage('');
      setDialogBgImage('assets/recharge_event/recharge_remind_dialog_bg.webp');
      setItemBgImage('assets/recharge_event/recharge_remind_item_bg.webp');
      setTagImage('assets/recharge_event/recharge_remind_tag_ic.png');
      setCoinsImage('assets/recharge_event/recharge_remind_coins_ic.webp');
      setBtnImage('assets/recharge_event/recharge_remind_btn_ic.webp');
      setBtnText('اشحن الآن');
      setBtnTextColor('#441200');
      setTagTextColor('#FFE957');
      setItemLabelColor('#FFE957');
      setOverlayBgColor('#000000B3');
      showNotification('تمت استعادة الإعدادات الأصلية الافتراضية');
    }
  };

  return (
    <div className="space-y-6 max-w-7xl mx-auto pb-16">
      {/* Top Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-[#141417] border border-amber-500/30 p-6 rounded-3xl shadow-xl relative overflow-hidden">
        <div className="absolute top-0 right-0 w-80 h-80 bg-amber-500/10 rounded-full blur-3xl pointer-events-none" />
        <div className="relative z-10 flex items-center gap-4">
          <div className="w-14 h-14 rounded-2xl bg-gradient-to-tr from-amber-500 to-amber-700 flex items-center justify-center text-white shadow-lg shadow-amber-600/30">
            <Crown className="w-8 h-8 text-amber-200" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-xl font-black text-white">حدث الشحن الملكي (المطابق لتطبيق D:40 الأصلي)</h1>
              <span className="text-[11px] font-bold px-2.5 py-0.5 rounded-full bg-amber-500/20 text-amber-400 border border-amber-500/30">D:40 Authentic</span>
            </div>
            <p className="text-xs text-slate-400 mt-1">
              لوحة التحكم الكاملة في تصميم حدث الشحن الأصلي (شبكة 3 أعمدة، الإطار الملكي، الياقوت، مؤثّرات الـ SVGA، تحويل النصوص لصور، وتعديل كل الجوائز والألوان)
            </p>
          </div>
        </div>

        <div className="relative z-10 flex items-center gap-2">
          <button
            onClick={resetToD40Defaults}
            className="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs font-semibold rounded-xl transition flex items-center gap-1.5"
            title="استعادة الافتراضي"
          >
            <span>استعادة إعدادات D:40</span>
          </button>
          <button
            onClick={handleSave}
            disabled={saving}
            className="px-6 py-2 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-600 hover:to-amber-700 text-white text-xs font-bold rounded-xl shadow-lg shadow-amber-600/30 transition flex items-center gap-2"
          >
            <Save className="w-4 h-4" /> {saving ? 'جارٍ الحفظ...' : 'حفظ التعديلات في التطبيق'}
          </button>
        </div>
      </div>

      {msg && (
        <div className="bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs px-4 py-3 rounded-xl flex items-center gap-2">
          <CheckCircle2 className="w-4 h-4 shrink-0" />
          <span>{msg}</span>
        </div>
      )}

      {/* Tabs */}
      <div className="flex gap-2 border-b border-white/5 pb-2">
        <button
          onClick={() => setActiveTab('tiers')}
          className={`px-5 py-2.5 text-xs font-bold rounded-xl transition flex items-center gap-2 ${activeTab === 'tiers' ? 'bg-amber-500 text-black shadow-lg shadow-amber-500/30' : 'text-slate-400 hover:bg-white/5 hover:text-white'}`}
        >
          <Layers className="w-4 h-4" />
          <span>المستويات والمكافآت والـ SVGA ({tiers.length})</span>
        </button>

        <button
          onClick={() => setActiveTab('design')}
          className={`px-5 py-2.5 text-xs font-bold rounded-xl transition flex items-center gap-2 ${activeTab === 'design' ? 'bg-amber-500 text-black shadow-lg shadow-amber-500/30' : 'text-slate-400 hover:bg-white/5 hover:text-white'}`}
        >
          <Palette className="w-4 h-4" />
          <span>التصميم الأصلي، الألوان وتحويل النصوص إلى صور</span>
        </button>

        <button
          onClick={() => setActiveTab('preview')}
          className={`px-5 py-2.5 text-xs font-bold rounded-xl transition flex items-center gap-2 ${activeTab === 'preview' ? 'bg-amber-500 text-black shadow-lg shadow-amber-500/30' : 'text-slate-400 hover:bg-white/5 hover:text-white'}`}
        >
          <Eye className="w-4 h-4" />
          <span>المعاينة الحية للنافذة الملكية (D:40 Live Mockup)</span>
        </button>
      </div>

      {/* ─── TIERS TAB ─── */}
      {activeTab === 'tiers' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-sm font-bold text-white">مستويات الشحن والجوائز (الأيقونات ومؤثرات الـ SVGA)</h3>
              <p className="text-[11px] text-slate-400">يمكنك تعديل أي مستوى، إضافة مستويات جديدة، تغيير التارجت أو رفع أيقونة/SVGA جديدة</p>
            </div>
            <button
              onClick={openAdd}
              className="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold rounded-xl shadow-lg shadow-emerald-600/20 transition flex items-center gap-1.5"
            >
              <Plus className="w-4 h-4" /> إضافة مستوى وجائزة جديدة
            </button>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-7 gap-3">
            {tiers.map((t, idx) => (
              <div 
                key={t.tier} 
                className="bg-[#141417] border border-amber-500/20 hover:border-amber-400/60 rounded-2xl p-3 transition duration-300 flex flex-col justify-between shadow-md relative group"
              >
                <div>
                  {/* Card Header with Tier and Tag */}
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/30">
                      #{t.tier}
                    </span>
                    <span className="text-[10px] font-bold text-rose-400 bg-rose-500/10 px-1.5 py-0.2 rounded border border-rose-500/20">
                      {t.tagText || t.rewardLabel}
                    </span>
                  </div>

                  {/* Frame Item with D:40 styling */}
                  <div className="relative w-20 h-24 mx-auto mb-2 flex items-center justify-center">
                    <img 
                      src={itemBgImage} 
                      alt="" 
                      className="absolute inset-0 w-full h-full object-contain pointer-events-none drop-shadow-md"
                    />
                    <div className="relative z-10 w-12 h-12 flex items-center justify-center">
                      <img
                        src={t.icon || `assets/recharge_event/${t.rewardLabel}.png`}
                        alt={t.rewardLabel}
                        className="w-full h-full object-contain"
                        onError={e => { (e.target as HTMLElement).style.display = 'none'; }}
                      />
                    </div>
                  </div>

                  <div className="text-center space-y-1">
                    <p className="font-extrabold text-xs text-amber-300">{t.rewardLabel}</p>
                    <div className="bg-slate-900/60 rounded-lg py-1 px-1.5 text-[10px] text-slate-300 font-mono">
                      {t.requiredCoins.toLocaleString()} 🪙
                    </div>
                    <div className="text-[9px] text-emerald-400 font-medium">
                      +{t.rewardCoins.toLocaleString()} بونص
                    </div>
                    <div className="text-[9px] text-indigo-300 truncate font-mono" title={t.svga}>
                      🎬 {t.svga}
                    </div>
                  </div>
                </div>

                <div className="mt-3 pt-2 border-t border-white/5 flex items-center justify-between gap-1">
                  <button 
                    onClick={() => openEdit(idx)} 
                    className="flex-1 py-1 bg-indigo-600/20 hover:bg-indigo-600/40 text-indigo-300 rounded-lg text-[10px] font-semibold flex items-center justify-center gap-1"
                  >
                    <Edit2 className="w-3 h-3" /> تعديل
                  </button>
                  <button 
                    onClick={() => setPreviewTier(t)} 
                    className="p-1 bg-amber-500/20 hover:bg-amber-500/40 text-amber-300 rounded-lg text-[10px]"
                    title="معاينة الجائزة"
                  >
                    <Eye className="w-3.5 h-3.5" />
                  </button>
                  <button 
                    onClick={() => deleteTier(idx)} 
                    className="p-1 bg-rose-600/20 hover:bg-rose-600/40 text-rose-400 rounded-lg text-[10px]"
                    title="حذف المستوى"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ─── DESIGN & TEXT-TO-IMAGE TAB ─── */}
      {activeTab === 'design' && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Custom Assets & Text-to-Image */}
          <div className="bg-[#141417] border border-white/5 rounded-3xl p-6 space-y-5 shadow-lg">
            <div className="flex items-center gap-2 border-b border-white/5 pb-3">
              <ImageIcon className="w-5 h-5 text-amber-400" />
              <h3 className="text-sm font-bold text-white">ملحقات التصميم الأصلية واستبدال النصوص بصور (Text-to-Image)</h3>
            </div>

            <div className="space-y-4 text-xs">
              {/* Header Text or Banner Image */}
              <div className="p-4 bg-slate-900/60 rounded-2xl border border-amber-500/20 space-y-2">
                <label className="block text-amber-300 font-bold">
                  👑 عنوان حدث الشحن (نص أو صورة مصممة بديلة):
                </label>
                <input 
                  type="text" 
                  value={title} 
                  onChange={e => setTitle(e.target.value)} 
                  placeholder="نص العنوان التوضيحي..." 
                  className="w-full bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white" 
                />
                <div className="pt-2">
                  <span className="block text-[11px] text-slate-400 mb-1">استبدال العنوان بصورة بانر مصممة (Text-To-Image):</span>
                  <div className="flex gap-2">
                    <input 
                      type="text" 
                      value={headerTextImage} 
                      onChange={e => setHeaderTextImage(e.target.value)} 
                      placeholder="رابط أو مسار صورة العنوان المرفوعة..." 
                      className="flex-1 bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white" 
                    />
                    <label className="cursor-pointer px-3 py-2 bg-indigo-600 hover:bg-indigo-500 text-white rounded-xl font-bold flex items-center gap-1 shrink-0">
                      <Upload className="w-3.5 h-3.5" /> رفع صورة
                      <input 
                        type="file" 
                        accept="image/*" 
                        className="hidden" 
                        onChange={e => { const f = e.target.files?.[0]; if (f) handleUploadFile(f, 'headers', setHeaderTextImage); }} 
                      />
                    </label>
                  </div>
                </div>
              </div>

              {/* Dialog Royal Frame BG */}
              <div className="p-4 bg-slate-900/60 rounded-2xl border border-white/5 space-y-2">
                <label className="block text-slate-300 font-bold">
                  🏰 خلفية النافذة الملكية الأصلية (Dialog Background WebP):
                </label>
                <div className="flex gap-2">
                  <input 
                    type="text" 
                    value={dialogBgImage} 
                    onChange={e => setDialogBgImage(e.target.value)} 
                    className="flex-1 bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white font-mono text-[11px]" 
                  />
                  <label className="cursor-pointer px-3 py-2 bg-amber-600 hover:bg-amber-500 text-white rounded-xl font-bold flex items-center gap-1 shrink-0">
                    <Upload className="w-3.5 h-3.5" /> رفع بديل
                    <input 
                      type="file" 
                      accept="image/*" 
                      className="hidden" 
                      onChange={e => { const f = e.target.files?.[0]; if (f) handleUploadFile(f, 'dialog_bg', setDialogBgImage); }} 
                    />
                  </label>
                </div>
              </div>

              {/* Item Card Frame Image */}
              <div className="p-4 bg-slate-900/60 rounded-2xl border border-white/5 space-y-2">
                <label className="block text-slate-300 font-bold">
                  💎 إطار كرت المكافأة الأصلي مع الياقوت (Item Frame BG):
                </label>
                <div className="flex gap-2">
                  <input 
                    type="text" 
                    value={itemBgImage} 
                    onChange={e => setItemBgImage(e.target.value)} 
                    className="flex-1 bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white font-mono text-[11px]" 
                  />
                  <label className="cursor-pointer px-3 py-2 bg-amber-600 hover:bg-amber-500 text-white rounded-xl font-bold flex items-center gap-1 shrink-0">
                    <Upload className="w-3.5 h-3.5" /> رفع بديل
                    <input 
                      type="file" 
                      accept="image/*" 
                      className="hidden" 
                      onChange={e => { const f = e.target.files?.[0]; if (f) handleUploadFile(f, 'item_bg', setItemBgImage); }} 
                    />
                  </label>
                </div>
              </div>

              {/* Coins Pile Image */}
              <div className="p-4 bg-slate-900/60 rounded-2xl border border-white/5 space-y-2">
                <label className="block text-slate-300 font-bold">
                  🪙 صورة كومة الكوينز الذهبية السفلية (Coins Pile WebP):
                </label>
                <div className="flex gap-2">
                  <input 
                    type="text" 
                    value={coinsImage} 
                    onChange={e => setCoinsImage(e.target.value)} 
                    className="flex-1 bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white font-mono text-[11px]" 
                  />
                  <label className="cursor-pointer px-3 py-2 bg-amber-600 hover:bg-amber-500 text-white rounded-xl font-bold flex items-center gap-1 shrink-0">
                    <Upload className="w-3.5 h-3.5" /> رفع بديل
                    <input 
                      type="file" 
                      accept="image/*" 
                      className="hidden" 
                      onChange={e => { const f = e.target.files?.[0]; if (f) handleUploadFile(f, 'coins', setCoinsImage); }} 
                    />
                  </label>
                </div>
              </div>

              {/* Action Button Image */}
              <div className="p-4 bg-slate-900/60 rounded-2xl border border-white/5 space-y-2">
                <label className="block text-slate-300 font-bold">
                  🔘 صورة زر الشحن الذهبي (Confirm Button WebP):
                </label>
                <div className="flex gap-2">
                  <input 
                    type="text" 
                    value={btnImage} 
                    onChange={e => setBtnImage(e.target.value)} 
                    className="flex-1 bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white font-mono text-[11px]" 
                  />
                  <label className="cursor-pointer px-3 py-2 bg-amber-600 hover:bg-amber-500 text-white rounded-xl font-bold flex items-center gap-1 shrink-0">
                    <Upload className="w-3.5 h-3.5" /> رفع بديل
                    <input 
                      type="file" 
                      accept="image/*" 
                      className="hidden" 
                      onChange={e => { const f = e.target.files?.[0]; if (f) handleUploadFile(f, 'btn', setBtnImage); }} 
                    />
                  </label>
                </div>
              </div>
            </div>
          </div>

          {/* Texts & Colors Customization */}
          <div className="bg-[#141417] border border-white/5 rounded-3xl p-6 space-y-5 shadow-lg">
            <div className="flex items-center gap-2 border-b border-white/5 pb-3">
              <Palette className="w-5 h-5 text-amber-400" />
              <h3 className="text-sm font-bold text-white">تخصيص الألوان والنصوص (Colors & Typography)</h3>
            </div>

            <div className="space-y-4 text-xs">
              <div>
                <label className="block text-slate-300 font-bold mb-1">نص زر الشحن (Button Text):</label>
                <input 
                  type="text" 
                  value={btnText} 
                  onChange={e => setBtnText(e.target.value)} 
                  className="w-full bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white font-bold" 
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="bg-slate-900/60 p-3 rounded-xl border border-white/5">
                  <label className="block text-slate-400 font-bold mb-1.5">لون خط نص الزر الذهبي:</label>
                  <div className="flex items-center gap-2">
                    <input 
                      type="color" 
                      value={to6Hex(btnTextColor)} 
                      onChange={e => setBtnTextColor(e.target.value)} 
                      className="w-8 h-8 rounded cursor-pointer bg-transparent border-none" 
                    />
                    <span className="font-mono text-[11px] text-white">{btnTextColor}</span>
                  </div>
                </div>

                <div className="bg-slate-900/60 p-3 rounded-xl border border-white/5">
                  <label className="block text-slate-400 font-bold mb-1.5">لون نص العنوان التوضيحي:</label>
                  <div className="flex items-center gap-2">
                    <input 
                      type="color" 
                      value={to6Hex(titleColor)} 
                      onChange={e => setTitleColor(e.target.value)} 
                      className="w-8 h-8 rounded cursor-pointer bg-transparent border-none" 
                    />
                    <span className="font-mono text-[11px] text-white">{titleColor}</span>
                  </div>
                </div>

                <div className="bg-slate-900/60 p-3 rounded-xl border border-white/5">
                  <label className="block text-slate-400 font-bold mb-1.5">لون نص شارة التاج (Tag Text):</label>
                  <div className="flex items-center gap-2">
                    <input 
                      type="color" 
                      value={to6Hex(tagTextColor)} 
                      onChange={e => setTagTextColor(e.target.value)} 
                      className="w-8 h-8 rounded cursor-pointer bg-transparent border-none" 
                    />
                    <span className="font-mono text-[11px] text-white">{tagTextColor}</span>
                  </div>
                </div>

                <div className="bg-slate-900/60 p-3 rounded-xl border border-white/5">
                  <label className="block text-slate-400 font-bold mb-1.5">لون نصوص أسماء المكافآت:</label>
                  <div className="flex items-center gap-2">
                    <input 
                      type="color" 
                      value={to6Hex(itemLabelColor)} 
                      onChange={e => setItemLabelColor(e.target.value)} 
                      className="w-8 h-8 rounded cursor-pointer bg-transparent border-none" 
                    />
                    <span className="font-mono text-[11px] text-white">{itemLabelColor}</span>
                  </div>
                </div>
              </div>

              {/* Tag Badge Image override */}
              <div className="p-4 bg-slate-900/60 rounded-2xl border border-white/5 space-y-2">
                <label className="block text-slate-300 font-bold">
                  🏷️ صورة شارة التميز الحمراء (Tag Badge PNG):
                </label>
                <div className="flex gap-2">
                  <input 
                    type="text" 
                    value={tagImage} 
                    onChange={e => setTagImage(e.target.value)} 
                    className="flex-1 bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white font-mono text-[11px]" 
                  />
                  <label className="cursor-pointer px-3 py-2 bg-rose-600 hover:bg-rose-500 text-white rounded-xl font-bold flex items-center gap-1 shrink-0">
                    <Upload className="w-3.5 h-3.5" /> رفع بديل
                    <input 
                      type="file" 
                      accept="image/*" 
                      className="hidden" 
                      onChange={e => { const f = e.target.files?.[0]; if (f) handleUploadFile(f, 'tags', setTagImage); }} 
                    />
                  </label>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ─── PREVIEW TAB: AUTHENTIC D:40 DIALOG ─── */}
      {activeTab === 'preview' && (
        <div className="bg-[#0b0b0e] border border-amber-500/30 rounded-3xl p-6 flex flex-col items-center justify-center relative min-h-[640px]">
          <div className="absolute top-4 right-6 text-xs text-amber-400/80 font-bold flex items-center gap-1.5">
            <Smartphone className="w-4 h-4" />
            <span>معاينة حية دقيقة تحاكي ملف recharge_remind_dialog.xml في D:40</span>
          </div>

          {/* D:40 Royal Dialog Container (Width: 320px, Height: 460px proportional) */}
          <div className="relative w-[310px] h-[450px] flex flex-col items-center justify-between select-none">
            
            {/* 1. Royal Crown Dialog Arch Background */}
            <img 
              src={dialogBgImage} 
              alt="Dialog BG" 
              className="absolute top-0 left-0 w-full h-[385px] object-fill pointer-events-none drop-shadow-2xl z-0"
              onError={e => { (e.target as HTMLImageElement).src = 'assets/recharge_event/recharge_remind_dialog_bg.webp'; }}
            />

            {/* 2. Top Title / Guideline Area (starts at 25% height) */}
            <div className="relative z-10 w-full pt-[96px] px-5 text-center">
              {headerTextImage ? (
                <img src={headerTextImage} alt="Header" className="max-h-8 object-contain mx-auto" />
              ) : (
                <p 
                  className="text-[11px] font-bold leading-tight drop-shadow" 
                  style={{ color: titleColor }}
                >
                  {title}
                </p>
              )}
            </div>

            {/* 3. 3-Column Grid of Royal Frame Items */}
            <div className="relative z-10 w-full px-4 pt-2 pb-8 h-[220px] overflow-y-auto grid grid-cols-3 gap-2">
              {tiers.map((t) => (
                <div 
                  key={t.tier} 
                  onClick={() => setPreviewTier(t)}
                  className="flex flex-col items-center cursor-pointer transition hover:scale-105 active:scale-95 group"
                >
                  {/* Item Royal Frame Card */}
                  <div className="relative w-[80px] h-[92px] flex items-center justify-center">
                    {/* The Royal Frame with Rubies */}
                    <img 
                      src={itemBgImage} 
                      alt="" 
                      className="absolute inset-0 w-full h-full object-contain pointer-events-none"
                    />

                    {/* Tag badge on top right */}
                    <div className="absolute top-[8px] right-[2px] w-[34px] h-[22px] flex items-center justify-center">
                      <img src={tagImage} alt="" className="absolute inset-0 w-full h-full object-contain" />
                      <span 
                        className="relative z-10 text-[9px] font-black leading-none drop-shadow"
                        style={{ color: tagTextColor }}
                      >
                        {t.tagText || t.rewardLabel}
                      </span>
                    </div>

                    {/* Reward Tier Icon */}
                    <div className="relative z-10 w-[50px] h-[40px] flex items-center justify-center pt-1">
                      <img 
                        src={t.icon || `assets/recharge_event/${t.rewardLabel}.png`} 
                        alt={t.rewardLabel} 
                        className="max-w-full max-h-full object-contain"
                        onError={e => { (e.target as HTMLElement).style.display = 'none'; }}
                      />
                    </div>
                  </div>

                  {/* Reward Name & Coins */}
                  <span 
                    className="text-[10px] font-bold mt-0.5 drop-shadow text-center"
                    style={{ color: itemLabelColor }}
                  >
                    {t.rewardLabel}
                  </span>
                </div>
              ))}
            </div>

            {/* 4. Bottom Pile of Coins */}
            <div className="absolute bottom-[40px] left-0 right-0 h-[48px] px-2 pointer-events-none z-10">
              <img 
                src={coinsImage} 
                alt="Coins" 
                className="w-full h-full object-contain drop-shadow"
              />
            </div>

            {/* 5. Golden Confirm Button (Go Now / اشحن الآن) */}
            <div className="relative z-20 -mt-2">
              <button 
                onClick={() => alert('محاكاة زر اشحن الآن: سيتم فتح صفحة باقات الشحن في التطبيق')}
                className="relative w-[138px] h-[48px] flex items-center justify-center cursor-pointer transition hover:brightness-110 active:scale-95"
              >
                <img 
                  src={btnImage} 
                  alt="Button" 
                  className="absolute inset-0 w-full h-full object-contain drop-shadow-lg"
                />
                <span 
                  className="relative z-10 font-black text-lg tracking-wide drop-shadow"
                  style={{ color: btnTextColor }}
                >
                  {btnText}
                </span>
              </button>
            </div>

            {/* 6. Close Button below button */}
            <div className="relative z-20 mt-1">
              <button 
                onClick={() => alert('إغلاق نافذة حدث الشحن')}
                className="w-8 h-8 rounded-full flex items-center justify-center transition hover:opacity-80 active:scale-90"
              >
                <img src={closeBtnImage} alt="Close" className="w-7 h-7 object-contain" />
              </button>
            </div>

          </div>
        </div>
      )}

      {/* ─── ADD / EDIT MODAL ─── */}
      {showModal && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#141417] border border-amber-500/30 rounded-3xl w-full max-w-lg p-6 space-y-4 shadow-2xl">
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <h3 className="font-bold text-white text-sm flex items-center gap-2">
                <Crown className="w-4 h-4 text-amber-400" />
                <span>{editingIndex !== null ? 'تعديل مستوى ومكافأة الشحن' : 'إضافة مستوى ومكافأة جديدة'}</span>
              </h3>
              <button onClick={() => setShowModal(false)} className="text-slate-400 hover:text-white">✕</button>
            </div>

            <div className="space-y-3 text-xs">
              <div className="grid grid-cols-3 gap-3">
                <div>
                  <label className="block text-slate-400 font-bold mb-1">رقم المستوى (Tier):</label>
                  <input 
                    type="number" 
                    value={modalForm.tier} 
                    onChange={e => setModalForm(p => ({ ...p, tier: Number(e.target.value) }))} 
                    className="w-full bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white" 
                  />
                </div>
                <div>
                  <label className="block text-slate-400 font-bold mb-1">تسمية الجائزة (100K..):</label>
                  <input 
                    type="text" 
                    value={modalForm.rewardLabel} 
                    onChange={e => setModalForm(p => ({ ...p, rewardLabel: e.target.value }))} 
                    className="w-full bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white font-bold" 
                  />
                </div>
                <div>
                  <label className="block text-slate-400 font-bold mb-1">نص الشارة (Tag):</label>
                  <input 
                    type="text" 
                    value={modalForm.tagText || ''} 
                    onChange={e => setModalForm(p => ({ ...p, tagText: e.target.value }))} 
                    placeholder="HOT أو 100K..." 
                    className="w-full bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white" 
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-slate-400 font-bold mb-1">الكوينز المطلوبة (Target):</label>
                  <input 
                    type="number" 
                    value={modalForm.requiredCoins} 
                    onChange={e => setModalForm(p => ({ ...p, requiredCoins: Number(e.target.value) }))} 
                    className="w-full bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white font-mono" 
                  />
                </div>
                <div>
                  <label className="block text-slate-400 font-bold mb-1">بونص كوينز إضافي:</label>
                  <input 
                    type="number" 
                    value={modalForm.rewardCoins} 
                    onChange={e => setModalForm(p => ({ ...p, rewardCoins: Number(e.target.value) }))} 
                    className="w-full bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white font-mono" 
                  />
                </div>
              </div>

              <div>
                <label className="block text-slate-400 font-bold mb-1">أيقونة المكافأة (PNG):</label>
                <div className="flex items-center gap-2">
                  <input 
                    type="text" 
                    value={modalForm.icon} 
                    onChange={e => setModalForm(p => ({ ...p, icon: e.target.value }))} 
                    placeholder="assets/recharge_event/100K.png أو رابط..." 
                    className="flex-1 bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white font-mono text-[11px]" 
                  />
                  <label className="cursor-pointer px-3 py-2 bg-indigo-600 hover:bg-indigo-500 text-white rounded-xl font-bold flex items-center gap-1 shrink-0">
                    <Upload className="w-3.5 h-3.5" /> رفع PNG
                    <input 
                      type="file" 
                      accept="image/*" 
                      className="hidden" 
                      onChange={e => { const f = e.target.files?.[0]; if (f) handleUploadFile(f, 'icons', url => setModalForm(p => ({ ...p, icon: url }))); }} 
                    />
                  </label>
                </div>
              </div>

              <div>
                <label className="block text-slate-400 font-bold mb-1">مؤثر الـ SVGA المتحرك:</label>
                <div className="flex items-center gap-2">
                  <input 
                    type="text" 
                    value={modalForm.svga} 
                    onChange={e => setModalForm(p => ({ ...p, svga: e.target.value }))} 
                    placeholder="100k.svga أو رابط..." 
                    className="flex-1 bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white font-mono text-[11px]" 
                  />
                  <label className="cursor-pointer px-3 py-2 bg-amber-600 hover:bg-amber-500 text-white rounded-xl font-bold flex items-center gap-1 shrink-0">
                    <Upload className="w-3.5 h-3.5" /> رفع SVGA
                    <input 
                      type="file" 
                      accept=".svga" 
                      className="hidden" 
                      onChange={e => { const f = e.target.files?.[0]; if (f) handleUploadFile(f, 'svga', url => setModalForm(p => ({ ...p, svga: url }))); }} 
                    />
                  </label>
                </div>
              </div>

              <div>
                <label className="block text-slate-400 font-bold mb-1">صلاحية المكافأة (بالأيام):</label>
                <input 
                  type="number" 
                  value={modalForm.daysValid} 
                  onChange={e => setModalForm(p => ({ ...p, daysValid: Number(e.target.value) }))} 
                  className="w-full bg-[#161618] border border-white/10 rounded-xl px-3 py-2 text-white" 
                />
              </div>
            </div>

            <div className="pt-3 border-t border-white/5 flex gap-2">
              <button 
                onClick={saveModal} 
                className="flex-1 py-2.5 bg-amber-500 hover:bg-amber-600 text-black text-xs font-bold rounded-xl shadow-lg shadow-amber-500/20"
              >
                تأكيد وإضافة للقائمة
              </button>
              <button 
                onClick={() => setShowModal(false)} 
                className="px-4 py-2.5 bg-slate-800 text-slate-300 text-xs font-semibold rounded-xl"
              >
                إلغاء
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ─── PREVIEW DETAIL MODAL ─── */}
      {previewTier && (
        <div className="fixed inset-0 z-50 bg-black/85 backdrop-blur-md flex items-center justify-center p-4">
          <div className="bg-[#141417] border border-amber-500/40 rounded-3xl w-full max-w-sm p-6 text-center space-y-4 shadow-2xl relative">
            <button 
              onClick={() => setPreviewTier(null)}
              className="absolute top-4 right-4 text-slate-400 hover:text-white"
            >
              ✕
            </button>

            <div className="relative w-28 h-32 mx-auto flex items-center justify-center">
              <img src={itemBgImage} alt="" className="absolute inset-0 w-full h-full object-contain pointer-events-none" />
              <img 
                src={previewTier.icon || `assets/recharge_event/${previewTier.rewardLabel}.png`} 
                alt="" 
                className="relative z-10 w-16 h-16 object-contain" 
                onError={e => { (e.target as HTMLElement).style.display = 'none'; }}
              />
            </div>

            <div>
              <h3 className="text-xl font-black text-white">{previewTier.rewardLabel}</h3>
              <p className="text-xs text-amber-400 font-bold mt-1">تارجت الشحن: {previewTier.requiredCoins.toLocaleString()} كوينز</p>
            </div>

            <div className="bg-slate-900/80 p-3.5 rounded-2xl border border-white/5 text-xs text-slate-300 space-y-2 text-right">
              <div className="flex justify-between">
                <span className="text-slate-400">بونص كوينز فوري:</span>
                <span className="font-bold text-emerald-400">+{previewTier.rewardCoins.toLocaleString()} كوينز</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-400">مؤثر الـ SVGA:</span>
                <span className="font-mono text-[11px] text-indigo-300">{previewTier.svga}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-400">مدة صلاحية المكافأة:</span>
                <span className="font-bold text-white">{previewTier.daysValid} يوم</span>
              </div>
            </div>

            <button 
              onClick={() => setPreviewTier(null)}
              className="w-full py-2.5 bg-amber-500 hover:bg-amber-600 text-black font-bold text-xs rounded-xl"
            >
              إغلاق
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
