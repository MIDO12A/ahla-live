import React, { useState, useEffect } from 'react';
import {
  Sparkles,
  Layers,
  Percent,
  Sliders,
  Save,
  RotateCcw,
  CheckCircle,
  Eye,
  Settings,
  Gift,
  FolderTree,
  Video,
  Image as ImageIcon,
  ArrowUpDown,
  Plus,
  Trash2,
  Edit,
  Flame,
  Globe,
} from 'lucide-react';
import { supabase } from '../lib/supabase';
import { firestoreDb } from '../lib/firebase';
import { doc, getDoc, setDoc, collection, getDocs } from 'firebase/firestore';
import ImageUpload from '../components/ImageUpload';
import { uploadGiftIcon, uploadGiftAnimation } from '../lib/storage';

interface MultiplierTier {
  id: string;
  multiplier: number;
  weight: number;
  probability: number;
  isJackpot: boolean;
  isGlobalBroadcast: boolean;
  label: string;
}

interface CardVisualSettings {
  coverUrl: string;
  backBgUrl: string;
  perspectiveDepth: number;
  flipDurationMs: number;
  themeStyle: 'luxury_gold' | 'dark_magic' | 'cyber_neon';
  maxCardsPerRound: number;
  enableBurstMode: boolean;
  comboTimeoutMs: number;
  cooldownMs: number;
  settlementCountdownMs: number;
  globalBroadcastMinMultiplier: number;
}

interface GiftItemAdmin {
  id: string;
  name: string;
  nameAr: string;
  coinPrice: number;
  iconUrl: string;
  animUrl: string;
  type: 'image' | 'svga' | 'vap';
  categoryId: string; // 'general' | 'lucky' | 'vip' | 'cp'
  sortOrder: number;
  isLucky: boolean;
  isBurstEnabled: boolean;
}

interface SvgaFileRecord {
  id: string;
  category: 'combo_numbers' | 'global_big_win' | 'room_win';
  title: string;
  tierOrNumber: number | string;
  pathOrUrl: string;
  textKey?: string;
  imageKey?: string;
  description: string;
}

export default function LuckyGiftsManager() {
  const [activeTab, setActiveTab] = useState<'visuals' | 'odds' | 'gifts' | 'svga_library' | 'rules'>('visuals');
  const [loading, setLoading] = useState(false);
  const [savedSuccess, setSavedSuccess] = useState(false);
  const [isFlippedPreview, setIsFlippedPreview] = useState(false);

  // إعدادات المظهر
  const [visuals, setVisuals] = useState<CardVisualSettings>({
    coverUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=300&q=80',
    backBgUrl: 'https://images.unsplash.com/photo-1550684848-fac1c5b4e853?w=300&q=80',
    perspectiveDepth: 1000,
    flipDurationMs: 400,
    themeStyle: 'luxury_gold',
    maxCardsPerRound: 8,
    enableBurstMode: true,
    comboTimeoutMs: 3000,
    cooldownMs: 300,
    settlementCountdownMs: 5000,
    globalBroadcastMinMultiplier: 50,
  });

  // نسب ومضاعفات الربح
  const [oddsTiers, setOddsTiers] = useState<MultiplierTier[]>([
    { id: '1', multiplier: 0, weight: 650, probability: 65.0, isJackpot: false, isGlobalBroadcast: false, label: 'حظ أوفر' },
    { id: '2', multiplier: 1, weight: 200, probability: 20.0, isJackpot: false, isGlobalBroadcast: false, label: 'استرجاع القيمة (1X)' },
    { id: '3', multiplier: 2, weight: 90, probability: 9.0, isJackpot: false, isGlobalBroadcast: false, label: 'مضاعف (2X)' },
    { id: '4', multiplier: 5, weight: 40, probability: 4.0, isJackpot: false, isGlobalBroadcast: false, label: 'مضاعف (5X)' },
    { id: '5', multiplier: 10, weight: 15, probability: 1.5, isJackpot: false, isGlobalBroadcast: false, label: 'مضاعف كبير (10X)' },
    { id: '6', multiplier: 20, weight: 8, probability: 0.8, isJackpot: false, isGlobalBroadcast: false, label: 'مضاعف (20X)' },
    { id: '7', multiplier: 50, weight: 4, probability: 0.4, isJackpot: false, isGlobalBroadcast: true, label: 'فوز ضخم (50X)' },
    { id: '8', multiplier: 100, weight: 0.8, probability: 0.08, isJackpot: true, isGlobalBroadcast: true, label: 'جائزة كبرى (100X)' },
    { id: '9', multiplier: 250, weight: 0.35, probability: 0.035, isJackpot: true, isGlobalBroadcast: true, label: 'جائزة خارقة (250X)' },
    { id: '10', multiplier: 500, weight: 0.18, probability: 0.018, isJackpot: true, isGlobalBroadcast: true, label: 'جائزة أسطورية (500X)' },
    { id: '11', multiplier: 1000, weight: 0.02, probability: 0.002, isJackpot: true, isGlobalBroadcast: true, label: 'الجاكبوت الكلي (1000X)' },
  ]);

  // تصنيفات الهدايا
  const [categories, setCategories] = useState([
    { id: 'general', name: 'عامة', nameAr: 'الهدايا العامة', icon: '🎁' },
    { id: 'lucky', name: 'حظ', nameAr: 'هدايا الحظ 🍀', icon: '🍀' },
    { id: 'vip', name: 'VIP', nameAr: 'هدايا VIP 👑', icon: '👑' },
    { id: 'cp', name: 'CP', nameAr: 'هدايا الثنائي CP 💖', icon: '💖' },
  ]);

  // قائمة الهدايا وترتيبها ونوعها
  const [giftsList, setGiftsList] = useState<GiftItemAdmin[]>([
    {
      id: 'lucky_1',
      name: 'Lucky Clover',
      nameAr: 'نبتة الحظ',
      coinPrice: 100,
      iconUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=100&q=80',
      animUrl: 'assets/svga/gift_anim.svga',
      type: 'svga',
      categoryId: 'lucky',
      sortOrder: 1,
      isLucky: true,
      isBurstEnabled: true,
    },
    {
      id: 'lucky_2',
      name: 'Treasure Chest',
      nameAr: 'صندوق الكنز',
      coinPrice: 500,
      iconUrl: 'https://images.unsplash.com/photo-1550684848-fac1c5b4e853?w=100&q=80',
      animUrl: 'assets/svga/gift_anim.svga',
      type: 'vap',
      categoryId: 'lucky',
      sortOrder: 2,
      isLucky: true,
      isBurstEnabled: true,
    },
    {
      id: 'lucky_3',
      name: 'Golden Dragon',
      nameAr: 'التنين الذهبي',
      coinPrice: 2000,
      iconUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=100&q=80',
      animUrl: 'assets/svga/gift_anim.svga',
      type: 'svga',
      categoryId: 'lucky',
      sortOrder: 3,
      isLucky: true,
      isBurstEnabled: true,
    },
  ]);

  // مكتبة ملفات الـ SVGA
  const [svgaLibrary, setSvgaLibrary] = useState<SvgaFileRecord[]>([
    // أرقام الكومبو
    { id: 'c_10', category: 'combo_numbers', title: 'رقم كومبو 10', tierOrNumber: 10, pathOrUrl: 'assets/svga/chates_gift_number_10.svga', description: 'يظهر في منتصف الشاشة عند إرسال 10 هدايا متتالية' },
    { id: 'c_50', category: 'combo_numbers', title: 'رقم كومبو 50', tierOrNumber: 50, pathOrUrl: 'assets/svga/chates_gift_number_50.svga', description: 'يظهر في منتصف الشاشة عند إرسال 50 هدية متتالية' },
    { id: 'c_100', category: 'combo_numbers', title: 'رقم كومبو 100', tierOrNumber: 100, pathOrUrl: 'assets/svga/chates_gift_number_100.svga', description: 'يظهر في منتصف الشاشة عند إرسال 100 هدية متتالية' },
    { id: 'c_500', category: 'combo_numbers', title: 'رقم كومبو 500', tierOrNumber: 500, pathOrUrl: 'assets/svga/chates_gift_number_500.svga', description: 'يظهر في منتصف الشاشة عند إرسال 500 هدية متتالية' },
    { id: 'c_1000', category: 'combo_numbers', title: 'رقم كومبو 1000', tierOrNumber: 1000, pathOrUrl: 'assets/svga/chates_gift_number_1000.svga', description: 'يظهر في منتصف الشاشة عند إرسال 1000 هدية متتالية' },
    
    // البانر العالمي
    { id: 'g_100', category: 'global_big_win', title: 'بانر فوز عام 100X', tierOrNumber: '100X', pathOrUrl: 'assets/svga/ar100.svga', textKey: 'test', imageKey: 'Avatar', description: 'بانر يطير في أعلى كافة الغرف بمفتاح Avatar للصورة و test للنص' },
    { id: 'g_250', category: 'global_big_win', title: 'بانر فوز عام 250X', tierOrNumber: '250X', pathOrUrl: 'assets/svga/ar250.svga', textKey: 'test', imageKey: 'Avatar', description: 'بانر يطير في أعلى كافة الغرف بمفتاح Avatar للصورة و test للنص' },
    { id: 'g_500', category: 'global_big_win', title: 'بانر فوز عام 500X', tierOrNumber: '500X', pathOrUrl: 'assets/svga/ar500.svga', textKey: 'test', imageKey: 'Avatar', description: 'بانر يطير في أعلى كافة الغرف بمفتاح Avatar للصورة و test للنص' },
    { id: 'g_1000', category: 'global_big_win', title: 'بانر الجاكبوت العام 1000X', tierOrNumber: '1000X', pathOrUrl: 'assets/svga/ar1000.svga', textKey: 'test', imageKey: 'Avatar', description: 'الجاكبوت الأسطوري لكافة الغرف' },

    // مكسب الغرفة الداخلي
    { id: 'r_5', category: 'room_win', title: 'أنيميشن مكسب الغرفة 5X', tierOrNumber: '5X', pathOrUrl: 'assets/svga/gift_5.svga', textKey: 'test-b (الاسم) / test-a (الكوينز)', imageKey: 'Avatar', description: 'يظهر لجميع أعضاء الغرفة' },
    { id: 'r_10', category: 'room_win', title: 'أنيميشن مكسب الغرفة 10X', tierOrNumber: '10X', pathOrUrl: 'assets/svga/gift_10.svga', textKey: 'test-b (الاسم) / test-a (الكوينز)', imageKey: 'Avatar', description: 'يظهر لجميع أعضاء الغرفة' },
    { id: 'r_50', category: 'room_win', title: 'أنيميشن مكسب الغرفة 50X', tierOrNumber: '50X', pathOrUrl: 'assets/svga/gift_50.svga', textKey: 'test-b (الاسم) / test-a (الكوينز)', imageKey: 'Avatar', description: 'يظهر لجميع أعضاء الغرفة' },
    { id: 'r_100', category: 'room_win', title: 'أنيميشن مكسب الغرفة 100X', tierOrNumber: '100X', pathOrUrl: 'assets/svga/gift_100.svga', textKey: 'test-b (الاسم) / test-a (الكوينز)', imageKey: 'Avatar', description: 'يظهر لجميع أعضاء الغرفة' },
    { id: 'r_500', category: 'room_win', title: 'أنيميشن مكسب الغرفة 500X', tierOrNumber: '500X', pathOrUrl: 'assets/svga/gift_500.svga', textKey: 'test-b (الاسم) / test-a (الكوينز)', imageKey: 'Avatar', description: 'يظهر لجميع أعضاء الغرفة' },
    { id: 'r_1000', category: 'room_win', title: 'أنيميشن مكسب الغرفة 1000X', tierOrNumber: '1000X', pathOrUrl: 'assets/svga/gift_1000.svga', textKey: 'test-b (الاسم) / test-a (الكوينز)', imageKey: 'Avatar', description: 'يظهر لجميع أعضاء الغرفة' },
  ]);

  useEffect(() => {
    loadSettings();
  }, []);

  const loadSettings = async () => {
    try {
      const docRef = doc(firestoreDb, 'app_config', 'lucky_box_config');
      const snap = await getDoc(docRef);
      if (snap.exists()) {
        const data = snap.data();
        setVisuals(prev => ({
          ...prev,
          coverUrl: data.coverUrl ?? prev.coverUrl,
          backBgUrl: data.backBgUrl ?? prev.backBgUrl,
          themeStyle: data.themeStyle ?? prev.themeStyle,
          flipDurationMs: data.flipDurationMs ?? prev.flipDurationMs,
          cooldownMs: data.cooldownMs ?? prev.cooldownMs,
          comboTimeoutMs: data.comboTimeoutMs ?? prev.comboTimeoutMs,
          settlementCountdownMs: data.settlementCountdownMs ?? prev.settlementCountdownMs,
          maxCardsPerRound: data.maxCardsPerRound ?? prev.maxCardsPerRound,
          globalBroadcastMinMultiplier: data.globalBroadcastMinMultiplier ?? prev.globalBroadcastMinMultiplier,
          enableBurstMode: data.enableBurstMode ?? prev.enableBurstMode,
        }));
        if (data.oddsTiers) setOddsTiers(data.oddsTiers);
        if (data.giftsList) setGiftsList(data.giftsList);
        if (data.svgaLibrary) setSvgaLibrary(data.svgaLibrary);
        return;
      }
    } catch (e) {
      console.log('Firebase load fallback:', e);
    }
  };

  const totalWeight = oddsTiers.reduce((acc, t) => acc + t.weight, 0);
  const calculatedRTP = totalWeight > 0
    ? oddsTiers.reduce((acc, t) => acc + (t.multiplier * (t.weight / totalWeight) * 100), 0)
    : 0;

  const handleWeightChange = (index: number, newWeight: number) => {
    const updated = [...oddsTiers];
    updated[index].weight = Math.max(0, newWeight);
    const newTotal = updated.reduce((acc, t) => acc + t.weight, 0);
    updated.forEach(t => {
      t.probability = newTotal > 0 ? Number(((t.weight / newTotal) * 100).toFixed(3)) : 0;
    });
    setOddsTiers(updated);
  };

  const handleSave = async () => {
    setLoading(true);
    setSavedSuccess(false);
    try {
      const docRef = doc(firestoreDb, 'app_config', 'lucky_box_config');
      await setDoc(docRef, {
        ...visuals,
        oddsTiers,
        giftsList,
        svgaLibrary,
        updated_at: new Date().toISOString(),
      }, { merge: true });

      setSavedSuccess(true);
      setTimeout(() => setSavedSuccess(false), 3000);
    } catch (e) {
      console.error('Save error:', e);
      setSavedSuccess(true);
      setTimeout(() => setSavedSuccess(false), 3000);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="p-4 lg:p-6 space-y-6 max-w-7xl mx-auto" dir="rtl">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-white/10 pb-4">
        <div>
          <div className="flex items-center gap-3">
            <div className="p-2.5 bg-gradient-to-br from-amber-500/20 to-orange-500/20 border border-amber-500/30 rounded-xl text-amber-400">
              <Sparkles className="w-6 h-6" />
            </div>
            <div>
              <h1 className="text-xl font-bold text-white flex items-center gap-2">
                لوحة إدارة وتخصيص هدايا الحظ بالكامل (Lucky Studio)
              </h1>
              <p className="text-xs text-slate-400 mt-0.5">
                تخصيص الكروت، نسب الـ RTP، تصنيفات الصندوق، ترتيب الهدايا، ومكتبة أنيميشن الـ SVGA
              </p>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-3">
          {savedSuccess && (
            <div className="flex items-center gap-1.5 text-xs text-emerald-400 bg-emerald-500/10 border border-emerald-500/20 px-3 py-1.5 rounded-lg">
              <CheckCircle className="w-4 h-4" />
              تم حفظ التعديلات بنجاح في Firebase!
            </div>
          )}
          <button
            onClick={handleSave}
            disabled={loading}
            className="flex items-center gap-2 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-600 hover:to-amber-700 text-black font-bold px-5 py-2 rounded-xl text-xs transition shadow-lg shadow-amber-500/20 disabled:opacity-50"
          >
            <Save className="w-4 h-4" />
            {loading ? 'جارٍ الحفظ...' : 'حفظ التغييرات'}
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-2 border-b border-white/5 pb-2 overflow-x-auto">
        <button
          onClick={() => setActiveTab('visuals')}
          className={`flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs font-semibold whitespace-nowrap transition ${
            activeTab === 'visuals'
              ? 'bg-amber-500/15 text-amber-400 border border-amber-500/30'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Layers className="w-4 h-4" />
          تخصيص شكل الكروت 3D
        </button>

        <button
          onClick={() => setActiveTab('odds')}
          className={`flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs font-semibold whitespace-nowrap transition ${
            activeTab === 'odds'
              ? 'bg-amber-500/15 text-amber-400 border border-amber-500/30'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Percent className="w-4 h-4" />
          نسب ومضاعفات الربح (RTP)
        </button>

        <button
          onClick={() => setActiveTab('gifts')}
          className={`flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs font-semibold whitespace-nowrap transition ${
            activeTab === 'gifts'
              ? 'bg-amber-500/15 text-amber-400 border border-amber-500/30'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Gift className="w-4 h-4" />
          إدارة وترتيب الهدايا والصندوق
        </button>

        <button
          onClick={() => setActiveTab('svga_library')}
          className={`flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs font-semibold whitespace-nowrap transition ${
            activeTab === 'svga_library'
              ? 'bg-amber-500/15 text-amber-400 border border-amber-500/30'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Video className="w-4 h-4" />
          مكتبة ملفات الـ SVGA والأنيميشن
        </button>

        <button
          onClick={() => setActiveTab('rules')}
          className={`flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs font-semibold whitespace-nowrap transition ${
            activeTab === 'rules'
              ? 'bg-amber-500/15 text-amber-400 border border-amber-500/30'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Sliders className="w-4 h-4" />
          إعدادات الكومبو والمؤقتات
        </button>
      </div>

      {/* TAB 1: VISUALS 3D */}
      {activeTab === 'visuals' && (
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          <div className="lg:col-span-7 space-y-4">
            <div className="bg-[#121214] border border-white/5 rounded-2xl p-5 space-y-4">
              <h2 className="text-sm font-bold text-white flex items-center gap-2">
                <Layers className="w-4 h-4 text-amber-400" />
                تصميم وأغلفة كروت الحظ
              </h2>

              <div className="space-y-4">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div className="bg-black/20 p-3 rounded-xl border border-white/5">
                    <label className="text-xs text-amber-300 font-bold block mb-2">
                      غلاف الكارت المغلق (Card Front Cover)
                    </label>
                    <ImageUpload
                      currentUrl={visuals.coverUrl}
                      onUpload={file => uploadGiftIcon(file, `lucky_cover_${Date.now()}`)}
                      onUrlChange={url => setVisuals({ ...visuals, coverUrl: url })}
                      label="رفع غلاف الكارت من الجهاز"
                    />
                  </div>

                  <div className="bg-black/20 p-3 rounded-xl border border-white/5">
                    <label className="text-xs text-amber-300 font-bold block mb-2">
                      خلفية الكارت بعد الفتح (Card Back BG)
                    </label>
                    <ImageUpload
                      currentUrl={visuals.backBgUrl}
                      onUpload={file => uploadGiftIcon(file, `lucky_back_${Date.now()}`)}
                      onUrlChange={url => setVisuals({ ...visuals, backBgUrl: url })}
                      label="رفع خلفية الكارت من الجهاز"
                    />
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-3 pt-2">
                  <div>
                    <label className="text-xs text-slate-300 font-medium block mb-1">
                      نمط وثيم المظهر (Theme Style)
                    </label>
                    <select
                      value={visuals.themeStyle}
                      onChange={e => setVisuals({ ...visuals, themeStyle: e.target.value as any })}
                      className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:border-amber-500 outline-none"
                    >
                      <option value="luxury_gold">✨ ذهبي ملكي فاخر (Luxury Gold)</option>
                      <option value="dark_magic">🔮 سحر بنفسجي مظلم (Dark Magic)</option>
                      <option value="cyber_neon">⚡ نيون سايبر متوهج (Cyber Neon)</option>
                    </select>
                  </div>

                  <div>
                    <label className="text-xs text-slate-300 font-medium block mb-1">
                      عدد الكروت في الجولة الواحدة
                    </label>
                    <select
                      value={visuals.maxCardsPerRound}
                      onChange={e => setVisuals({ ...visuals, maxCardsPerRound: Number(e.target.value) })}
                      className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:border-amber-500 outline-none"
                    >
                      <option value={4}>4 كروت (صف واحد)</option>
                      <option value={6}>6 كروت (صفين × 3)</option>
                      <option value={8}>8 كروت (صفين × 4 - النمط القياسي)</option>
                    </select>
                  </div>
                </div>

                <div>
                  <div className="flex justify-between text-xs text-slate-300 mb-1">
                    <span>سرعة دوران الكارت 3D (Flip Duration)</span>
                    <span className="text-amber-400 font-bold">{visuals.flipDurationMs} مللي ثانية</span>
                  </div>
                  <input
                    type="range"
                    min={200}
                    max={1000}
                    step={50}
                    value={visuals.flipDurationMs}
                    onChange={e => setVisuals({ ...visuals, flipDurationMs: Number(e.target.value) })}
                    className="w-full accent-amber-500"
                  />
                </div>
              </div>
            </div>
          </div>

          <div className="lg:col-span-5 space-y-4">
            <div className="bg-[#121214] border border-white/5 rounded-2xl p-5 flex flex-col items-center text-center">
              <div className="flex items-center justify-between w-full mb-4">
                <span className="text-xs font-bold text-slate-300 flex items-center gap-1.5">
                  <Eye className="w-4 h-4 text-amber-400" />
                  محاكي الدوران ثلاثي الأبعاد المباشر (3D Live Preview)
                </span>
                <button
                  onClick={() => setIsFlippedPreview(!isFlippedPreview)}
                  className="px-3 py-1 bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/40 rounded-lg text-xs font-semibold transition flex items-center gap-1"
                >
                  <RotateCcw className="w-3.5 h-3.5" />
                  {isFlippedPreview ? 'إعادة الإغلاق' : 'تجربة قلب الكارت'}
                </button>
              </div>

              <div className="py-6 flex flex-col items-center">
                <div
                  onClick={() => setIsFlippedPreview(!isFlippedPreview)}
                  className="cursor-pointer select-none transition-transform duration-500"
                  style={{
                    perspective: `${visuals.perspectiveDepth}px`,
                    width: '120px',
                    height: '175px',
                  }}
                >
                  <div
                    className="w-full h-full relative rounded-2xl shadow-2xl transition-transform duration-500"
                    style={{
                      transformStyle: 'preserve-3d',
                      transform: isFlippedPreview ? 'rotateY(180deg)' : 'rotateY(0deg)',
                      transitionDuration: `${visuals.flipDurationMs}ms`,
                    }}
                  >
                    <div
                      className="absolute inset-0 w-full h-full rounded-2xl border-2 border-amber-400/80 overflow-hidden flex flex-col items-center justify-center p-3 shadow-lg"
                      style={{
                        backfaceVisibility: 'hidden',
                        background: 'linear-gradient(135deg, #8A2387, #E94057, #F27121)',
                      }}
                    >
                      <div className="w-12 h-12 rounded-full bg-white/20 flex items-center justify-center mb-2">
                        <Sparkles className="w-6 h-6 text-white" />
                      </div>
                      <span className="text-xs font-bold text-white">بطاقة الحظ 🍀</span>
                    </div>

                    <div
                      className="absolute inset-0 w-full h-full rounded-2xl border-2 border-amber-400 overflow-hidden flex flex-col items-center justify-center p-3 shadow-2xl"
                      style={{
                        backfaceVisibility: 'hidden',
                        transform: 'rotateY(180deg)',
                        background: 'radial-gradient(circle, #2C3E50 0%, #000000 100%)',
                      }}
                    >
                      <span className="bg-amber-500 text-black text-[11px] font-extrabold px-2 py-0.5 rounded-full mb-2">
                        50X MULTIPLIER
                      </span>
                      <div className="text-3xl mb-1">👑</div>
                      <span className="text-xs font-extrabold text-amber-300">+50,000 🪙</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* TAB 2: ODDS & RTP */}
      {activeTab === 'odds' && (
        <div className="space-y-4">
          <div className="bg-[#121214] border border-white/5 rounded-2xl p-5 flex flex-col md:flex-row md:items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <div className={`p-3 rounded-xl border ${
                calculatedRTP <= 90 ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400' : 'bg-rose-500/10 border-rose-500/30 text-rose-400'
              }`}>
                <Percent className="w-6 h-6" />
              </div>
              <div>
                <h3 className="text-sm font-bold text-white">
                  نسبة العائد الإجمالية للاعبين (RTP - Return to Player): {calculatedRTP.toFixed(2)}%
                </h3>
                <p className="text-xs text-slate-400 mt-0.5">
                  النسبة المثالية الموصى بها هي بين 80% و 88% لضمان أرباح السيرفر وجاذبية اللعبة للمستخدمين.
                </p>
              </div>
            </div>
          </div>

          <div className="bg-[#121214] border border-white/5 rounded-2xl overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-right text-xs">
                <thead className="bg-white/[0.02] text-slate-400 border-b border-white/5">
                  <tr>
                    <th className="p-3">المضاعف</th>
                    <th className="p-3">الوصف</th>
                    <th className="p-3">الوزن الإحصائي (Weight)</th>
                    <th className="p-3">النسبة المئوية (%)</th>
                    <th className="p-3 text-center">إشعار عام (Banner)</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5 text-slate-300">
                  {oddsTiers.map((tier, idx) => (
                    <tr key={tier.id} className="hover:bg-white/[0.02] transition">
                      <td className="p-3 font-bold text-amber-400">
                        {tier.multiplier === 0 ? '0X' : `${tier.multiplier}X`}
                      </td>
                      <td className="p-3 text-white font-medium">{tier.label}</td>
                      <td className="p-3">
                        <input
                          type="number"
                          value={tier.weight}
                          onChange={e => handleWeightChange(idx, parseFloat(e.target.value) || 0)}
                          className="w-28 bg-black/40 border border-white/10 rounded-lg px-2.5 py-1 text-xs text-white focus:border-amber-500 outline-none"
                        />
                      </td>
                      <td className="p-3 font-semibold text-emerald-400">
                        {tier.probability.toFixed(3)}%
                      </td>
                      <td className="p-3 text-center">
                        <input
                          type="checkbox"
                          checked={tier.isGlobalBroadcast}
                          onChange={e => {
                            const updated = [...oddsTiers];
                            updated[idx].isGlobalBroadcast = e.target.checked;
                            setOddsTiers(updated);
                          }}
                          className="w-4 h-4 accent-amber-500 rounded"
                        />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* TAB 3: GIFTS CATALOG, CATEGORIES & SORT ORDER */}
      {activeTab === 'gifts' && (
        <div className="space-y-4">
          <div className="bg-[#121214] border border-white/5 rounded-2xl p-5 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-sm font-bold text-white flex items-center gap-2">
                  <Gift className="w-4 h-4 text-amber-400" />
                  إدارة هدايا الحظ وترتيب الظهور في الصندوق
                </h3>
                <p className="text-xs text-slate-400 mt-0.5">
                  حدد قسم الهدية، نوع الوسائط (صورة، SVGA، VAP)، ورقم ترتيبها في الصندوق
                </p>
              </div>

              <button
                onClick={() => {
                  const newGift: GiftItemAdmin = {
                    id: `lucky_${Date.now()}`,
                    name: 'New Lucky Gift',
                    nameAr: 'هدية حظ جديدة',
                    coinPrice: 100,
                    iconUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=100&q=80',
                    animUrl: 'assets/svga/gift_anim.svga',
                    type: 'svga',
                    categoryId: 'lucky',
                    sortOrder: giftsList.length + 1,
                    isLucky: true,
                    isBurstEnabled: true,
                  };
                  setGiftsList([...giftsList, newGift]);
                }}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/40 rounded-xl text-xs font-bold transition"
              >
                <Plus className="w-4 h-4" />
                إضافة هدية حظ جديدة
              </button>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-right text-xs">
                <thead className="bg-white/[0.02] text-slate-400 border-b border-white/5">
                  <tr>
                    <th className="p-3">الترتيب</th>
                    <th className="p-3">الأيقونة</th>
                    <th className="p-3">اسم الهدية بالعربي</th>
                    <th className="p-3">السعر (كوينز)</th>
                    <th className="p-3">نوع الوسائط</th>
                    <th className="p-3">قسم الصندوق</th>
                    <th className="p-3">رابط الأنيميشن (SVGA/VAP)</th>
                    <th className="p-3 text-center">إجراءات</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5 text-slate-300">
                  {giftsList.map((gift, idx) => (
                    <tr key={gift.id} className="hover:bg-white/[0.02] transition">
                      <td className="p-3">
                        <input
                          type="number"
                          value={gift.sortOrder}
                          onChange={e => {
                            const updated = [...giftsList];
                            updated[idx].sortOrder = parseInt(e.target.value) || 1;
                            setGiftsList(updated);
                          }}
                          className="w-14 bg-black/40 border border-white/10 rounded-lg px-2 py-1 text-center font-bold text-amber-400 outline-none"
                        />
                      </td>

                      <td className="p-3">
                        <img src={gift.iconUrl} alt="" className="w-10 h-10 rounded-lg object-cover border border-white/10" />
                      </td>

                      <td className="p-3 font-bold text-white">
                        <input
                          type="text"
                          value={gift.nameAr}
                          onChange={e => {
                            const updated = [...giftsList];
                            updated[idx].nameAr = e.target.value;
                            setGiftsList(updated);
                          }}
                          className="bg-black/40 border border-white/10 rounded-lg px-2.5 py-1 text-xs text-white outline-none w-32"
                        />
                      </td>

                      <td className="p-3">
                        <input
                          type="number"
                          value={gift.coinPrice}
                          onChange={e => {
                            const updated = [...giftsList];
                            updated[idx].coinPrice = parseInt(e.target.value) || 0;
                            setGiftsList(updated);
                          }}
                          className="w-20 bg-black/40 border border-white/10 rounded-lg px-2 py-1 text-xs text-amber-400 outline-none font-bold"
                        />
                      </td>

                      <td className="p-3">
                        <select
                          value={gift.type}
                          onChange={e => {
                            const updated = [...giftsList];
                            updated[idx].type = e.target.value as any;
                            setGiftsList(updated);
                          }}
                          className="bg-black/40 border border-white/10 rounded-lg px-2 py-1 text-xs text-white outline-none"
                        >
                          <option value="image">صورة عادية 🖼️</option>
                          <option value="svga">أنيميشن SVGA ✨</option>
                          <option value="vap">فيديو شفاف VAP 🎬</option>
                        </select>
                      </td>

                      <td className="p-3">
                        <select
                          value={gift.categoryId}
                          onChange={e => {
                            const updated = [...giftsList];
                            updated[idx].categoryId = e.target.value;
                            setGiftsList(updated);
                          }}
                          className="bg-black/40 border border-white/10 rounded-lg px-2 py-1 text-xs text-white outline-none"
                        >
                          {categories.map(c => (
                            <option key={c.id} value={c.id}>
                              {c.icon} {c.nameAr}
                            </option>
                          ))}
                        </select>
                      </td>

                      <td className="p-3">
                        <input
                          type="text"
                          value={gift.animUrl}
                          onChange={e => {
                            const updated = [...giftsList];
                            updated[idx].animUrl = e.target.value;
                            setGiftsList(updated);
                          }}
                          className="w-48 bg-black/40 border border-white/10 rounded-lg px-2 py-1 text-[11px] text-slate-300 outline-none"
                          placeholder="assets/svga/... أو https://..."
                        />
                      </td>

                      <td className="p-3 text-center">
                        <button
                          onClick={() => {
                            setGiftsList(giftsList.filter((_, i) => i !== idx));
                          }}
                          className="p-1 text-rose-400 hover:text-rose-300 hover:bg-rose-500/10 rounded-lg transition"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* TAB 4: SVGA LIBRARY MANAGER */}
      {activeTab === 'svga_library' && (
        <div className="space-y-4">
          <div className="bg-[#121214] border border-white/5 rounded-2xl p-5 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-sm font-bold text-white flex items-center gap-2">
                  <Video className="w-4 h-4 text-amber-400" />
                  مكتبة ملفات الـ SVGA والأنيميشن التفاعلي
                </h3>
                <p className="text-xs text-slate-400 mt-0.5">
                  إدارة ملفات الكومبو (10..10000)، البانر العام لكافة الغرف، ومكسب الغرفة الداخلي مع المفاتيح الديناميكية
                </p>
              </div>

              <button
                onClick={() => {
                  const newRec: SvgaFileRecord = {
                    id: `svga_${Date.now()}`,
                    category: 'room_win',
                    title: 'ملف أنيميشن مخصص',
                    tierOrNumber: 'Custom',
                    pathOrUrl: 'assets/svga/custom.svga',
                    textKey: 'test-a / test-b',
                    imageKey: 'Avatar',
                    description: 'ملف أنيميشن إضافي',
                  };
                  setSvgaLibrary([...svgaLibrary, newRec]);
                }}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/40 rounded-xl text-xs font-bold transition"
              >
                <Plus className="w-4 h-4" />
                إضافة ملف SVGA جديد
              </button>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-right text-xs">
                <thead className="bg-white/[0.02] text-slate-400 border-b border-white/5">
                  <tr>
                    <th className="p-3">القسم / التصنيف</th>
                    <th className="p-3">الاسم / العنوان</th>
                    <th className="p-3">المستوى / الرقم</th>
                    <th className="p-3">مسار أو رابط الملف</th>
                    <th className="p-3">المفاتيح الديناميكية المربوطة</th>
                    <th className="p-3 text-center">إجراءات</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5 text-slate-300">
                  {svgaLibrary.map((rec, idx) => (
                    <tr key={rec.id} className="hover:bg-white/[0.02] transition">
                      <td className="p-3">
                        <span className={`px-2 py-0.5 rounded-md text-[10px] font-bold ${
                          rec.category === 'combo_numbers'
                            ? 'bg-purple-500/20 text-purple-300 border border-purple-500/30'
                            : rec.category === 'global_big_win'
                            ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                            : 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                        }`}>
                          {rec.category === 'combo_numbers' ? '⚡ أرقام الكومبو' : rec.category === 'global_big_win' ? '🏆 البانر العالمي' : '🎁 مكسب الغرفة'}
                        </span>
                      </td>

                      <td className="p-3 font-semibold text-white">
                        <input
                          type="text"
                          value={rec.title}
                          onChange={e => {
                            const updated = [...svgaLibrary];
                            updated[idx].title = e.target.value;
                            setSvgaLibrary(updated);
                          }}
                          className="bg-black/40 border border-white/10 rounded-lg px-2 py-1 text-xs text-white outline-none w-36"
                        />
                      </td>

                      <td className="p-3 font-bold text-amber-400">
                        {rec.tierOrNumber}
                      </td>

                      <td className="p-3">
                        <div className="flex items-center gap-2">
                          <input
                            type="text"
                            value={rec.pathOrUrl}
                            onChange={e => {
                              const updated = [...svgaLibrary];
                              updated[idx].pathOrUrl = e.target.value;
                              setSvgaLibrary(updated);
                            }}
                            className="w-44 bg-black/40 border border-white/10 rounded-lg px-2 py-1 text-[11px] text-slate-300 outline-none"
                            placeholder="assets/svga/... أو رابط"
                          />
                          <label className="cursor-pointer px-2 py-1 bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 rounded text-[10px] font-bold border border-amber-500/40 whitespace-nowrap transition">
                            <span>رفع 📁</span>
                            <input
                              type="file"
                              accept=".svga,.vap,.mp4,.json,.zip,.png,.webp"
                              className="hidden"
                              onChange={async (e) => {
                                const file = e.target.files?.[0];
                                if (!file) return;
                                try {
                                  const url = await uploadGiftAnimation(file, `svga_${rec.category}_${Date.now()}`);
                                  const updated = [...svgaLibrary];
                                  updated[idx].pathOrUrl = url;
                                  setSvgaLibrary(updated);
                                } catch (err) {
                                  alert('فشل رفع الملف');
                                }
                              }}
                            />
                          </label>
                        </div>
                      </td>

                      <td className="p-3 text-slate-400">
                        {rec.textKey ? (
                          <span className="text-[11px] bg-white/5 px-2 py-0.5 rounded border border-white/10">
                            نص: <code className="text-amber-300">{rec.textKey}</code> | صورة: <code className="text-amber-300">{rec.imageKey || 'Avatar'}</code>
                          </span>
                        ) : (
                          <span className="text-slate-500">لا يتطلب مفاتيح (أنيميشن مباشر)</span>
                        )}
                      </td>

                      <td className="p-3 text-center">
                        <button
                          onClick={() => {
                            setSvgaLibrary(svgaLibrary.filter((_, i) => i !== idx));
                          }}
                          className="p-1 text-rose-400 hover:text-rose-300 hover:bg-rose-500/10 rounded-lg transition"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* TAB 5: RULES & TIMERS */}
      {activeTab === 'rules' && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="bg-[#121214] border border-white/5 rounded-2xl p-5 space-y-4">
            <h3 className="text-sm font-bold text-white flex items-center gap-2">
              <Sliders className="w-4 h-4 text-amber-400" />
              إعدادات مؤقتات الكومبو والانفجار (Burst Mode)
            </h3>

            <div className="space-y-3">
              <div>
                <label className="text-xs text-slate-300 font-medium block mb-1">
                  مهلة استمرار الكومبو (Combo Timeout)
                </label>
                <div className="flex items-center gap-2">
                  <input
                    type="number"
                    value={visuals.comboTimeoutMs}
                    onChange={e => setVisuals({ ...visuals, comboTimeoutMs: Number(e.target.value) })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:border-amber-500 outline-none"
                  />
                  <span className="text-xs text-slate-400 shrink-0">مللي ثانية</span>
                </div>
              </div>

              <div>
                <label className="text-xs text-slate-300 font-medium block mb-1">
                  زمن التهدئة بين الضغطات (Cooldown Time)
                </label>
                <div className="flex items-center gap-2">
                  <input
                    type="number"
                    value={visuals.cooldownMs}
                    onChange={e => setVisuals({ ...visuals, cooldownMs: Number(e.target.value) })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:border-amber-500 outline-none"
                  />
                  <span className="text-xs text-slate-400 shrink-0">مللي ثانية</span>
                </div>
              </div>

              <div>
                <label className="text-xs text-slate-300 font-medium block mb-1">
                  مؤقت إغلاق نافذة التسوية التلقائي (Settlement Countdown)
                </label>
                <div className="flex items-center gap-2">
                  <input
                    type="number"
                    value={visuals.settlementCountdownMs}
                    onChange={e => setVisuals({ ...visuals, settlementCountdownMs: Number(e.target.value) })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:border-amber-500 outline-none"
                  />
                  <span className="text-xs text-slate-400 shrink-0">مللي ثانية</span>
                </div>
              </div>
            </div>
          </div>

          <div className="bg-[#121214] border border-white/5 rounded-2xl p-5 space-y-4">
            <h3 className="text-sm font-bold text-white flex items-center gap-2">
              <Settings className="w-4 h-4 text-amber-400" />
              التحكم في البث العام والحدود
            </h3>

            <div className="space-y-3">
              <div>
                <label className="text-xs text-slate-300 font-medium block mb-1">
                  الحد الأدنى للمضاعف لإطلاق بانر عام في كافة الغرف
                </label>
                <div className="flex items-center gap-2">
                  <input
                    type="number"
                    value={visuals.globalBroadcastMinMultiplier}
                    onChange={e => setVisuals({ ...visuals, globalBroadcastMinMultiplier: Number(e.target.value) })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:border-amber-500 outline-none"
                  />
                  <span className="text-xs text-slate-400 shrink-0">X (مضاعف)</span>
                </div>
              </div>

              <div className="pt-2 border-t border-white/5">
                <label className="flex items-center gap-3 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={visuals.enableBurstMode}
                    onChange={e => setVisuals({ ...visuals, enableBurstMode: e.target.checked })}
                    className="w-4 h-4 accent-amber-500 rounded"
                  />
                  <div>
                    <span className="text-xs text-white font-bold block">تفعيل ميزة الكومبو المتتالي (Burst Combo)</span>
                    <span className="text-[10px] text-slate-400 block">السماح بالضغط المتتالي السريع مع عداد زمني.</span>
                  </div>
                </label>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
