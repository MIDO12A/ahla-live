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
  Upload,
} from 'lucide-react';
import { supabase } from '../lib/supabase';
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
  svgaUrl?: string; // رابط أو مسار ملف الـ SVGA المخصص للمضاعف
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

  // نسب ومضاعفات الربح مع ملفات الـ SVGA المخصصة لكل مضاعف
  const [oddsTiers, setOddsTiers] = useState<MultiplierTier[]>([
    { id: '1', multiplier: 0, weight: 650, probability: 65.0, isJackpot: false, isGlobalBroadcast: false, label: 'حظ أوفر (خسارة)', svgaUrl: '' },
    { id: '2', multiplier: 1, weight: 200, probability: 20.0, isJackpot: false, isGlobalBroadcast: false, label: 'استرجاع القيمة (1X)', svgaUrl: '' },
    { id: '3', multiplier: 2, weight: 90, probability: 9.0, isJackpot: false, isGlobalBroadcast: false, label: 'مضاعف (2X)', svgaUrl: '' },
    { id: '4', multiplier: 5, weight: 40, probability: 4.0, isJackpot: false, isGlobalBroadcast: false, label: 'مضاعف (5X)', svgaUrl: 'assets/svga/gift_5.svga' },
    { id: '5', multiplier: 10, weight: 15, probability: 1.5, isJackpot: false, isGlobalBroadcast: false, label: 'مضاعف كبير (10X)', svgaUrl: 'assets/svga/gift_10.svga' },
    { id: '6', multiplier: 20, weight: 8, probability: 0.8, isJackpot: false, isGlobalBroadcast: false, label: 'مضاعف (20X)', svgaUrl: 'assets/svga/gift_20.svga' },
    { id: '7', multiplier: 50, weight: 4, probability: 0.4, isJackpot: false, isGlobalBroadcast: true, label: 'فوز ضخم (50X)', svgaUrl: 'assets/svga/gift_50.svga' },
    { id: '8', multiplier: 100, weight: 0.8, probability: 0.08, isJackpot: true, isGlobalBroadcast: true, label: 'جائزة كبرى (100X)', svgaUrl: 'assets/svga/ar100.svga' },
    { id: '9', multiplier: 250, weight: 0.35, probability: 0.035, isJackpot: true, isGlobalBroadcast: true, label: 'جائزة خارقة (250X)', svgaUrl: 'assets/svga/ar250.svga' },
    { id: '10', multiplier: 500, weight: 0.18, probability: 0.018, isJackpot: true, isGlobalBroadcast: true, label: 'جائزة أسطورية (500X)', svgaUrl: 'assets/svga/ar500.svga' },
    { id: '11', multiplier: 1000, weight: 0.02, probability: 0.002, isJackpot: true, isGlobalBroadcast: true, label: 'الجاكبوت الكلي (1000X)', svgaUrl: 'assets/svga/ar1000.svga' },
  ]);

  // نسبة المكسب الإجمالية (%) المباشرة (0 = خسارة مؤكدة 100%, 10 = مكسب 10% وخسارة 90%, 30 = مكسب 30% وخسارة 70%, 40 = مكسب 40% وخسارة 60%)
  const [winRate, setWinRate] = useState<number>(35.0);

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

  // نسبة دخول هدايا الحظ في تارجت وماسات المستلم (%)
  const [targetPercentage, setTargetPercentage] = useState<number>(10.0);

  useEffect(() => {
    loadSettings();
  }, []);

  const loadSettings = async () => {
    try {
      let cfg: any = null;
      const { data, error } = await supabase
        .from('app_config')
        .select('value')
        .eq('key', 'lucky_box_config')
        .maybeSingle();

      if (!error && data?.value) {
        cfg = typeof data.value === 'string' ? JSON.parse(data.value) : data.value;
      }

      if (cfg) {
        setVisuals(prev => ({
          ...prev,
          coverUrl: cfg.coverUrl ?? prev.coverUrl,
          backBgUrl: cfg.backBgUrl ?? prev.backBgUrl,
          themeStyle: cfg.themeStyle ?? prev.themeStyle,
          flipDurationMs: cfg.flipDurationMs ?? prev.flipDurationMs,
          cooldownMs: cfg.cooldownMs ?? prev.cooldownMs,
          comboTimeoutMs: cfg.comboTimeoutMs ?? prev.comboTimeoutMs,
          settlementCountdownMs: cfg.settlementCountdownMs ?? prev.settlementCountdownMs,
          maxCardsPerRound: cfg.maxCardsPerRound ?? prev.maxCardsPerRound,
          globalBroadcastMinMultiplier: cfg.globalBroadcastMinMultiplier ?? prev.globalBroadcastMinMultiplier,
          enableBurstMode: cfg.enableBurstMode ?? prev.enableBurstMode,
        }));
        if (cfg.targetPercentage !== undefined) {
          setTargetPercentage(Number(cfg.targetPercentage) || 0);
        }
        if (cfg.winRate !== undefined) {
          setWinRate(Number(cfg.winRate) || 0);
        }
        if (cfg.oddsTiers && Array.isArray(cfg.oddsTiers)) {
          // دمج قيم مسارات الـ SVGA مع القيم الحالية
          const mergedTiers = cfg.oddsTiers.map((t: any) => ({
            ...t,
            svgaUrl: t.svgaUrl ?? (
              t.multiplier === 5 ? 'assets/svga/gift_5.svga' :
              t.multiplier === 10 ? 'assets/svga/gift_10.svga' :
              t.multiplier === 20 ? 'assets/svga/gift_20.svga' :
              t.multiplier === 50 ? 'assets/svga/gift_50.svga' :
              t.multiplier === 100 ? 'assets/svga/ar100.svga' :
              t.multiplier === 250 ? 'assets/svga/ar250.svga' :
              t.multiplier === 500 ? 'assets/svga/ar500.svga' :
              t.multiplier === 1000 ? 'assets/svga/ar1000.svga' : ''
            ),
          }));
          setOddsTiers(mergedTiers);

          if (cfg.winRate === undefined) {
            const lossTier = mergedTiers.find((t: any) => t.multiplier === 0);
            if (lossTier) {
              setWinRate(Number(Math.max(0, Math.min(100, 100 - (lossTier.probability || 0))).toFixed(1)));
            }
          }
        }
        if (cfg.giftsList) setGiftsList(cfg.giftsList);
        if (cfg.svgaLibrary) setSvgaLibrary(cfg.svgaLibrary);
      }

      // 2. قراءة النسبة المباشرة إن وجدت
      const { data: directData } = await supabase
        .from('app_config')
        .select('value')
        .eq('key', 'lucky_gift_target_percentage')
        .maybeSingle();

      if (directData?.value !== undefined && directData?.value !== null) {
        const val = Number(directData.value);
        if (!isNaN(val)) {
          setTargetPercentage(val);
        }
      }
    } catch (e) {
      console.log('Settings load fallback:', e);
    }
  };

  const totalWeight = oddsTiers.reduce((acc, t) => acc + t.weight, 0);
  const calculatedRTP = totalWeight > 0
    ? oddsTiers.reduce((acc, t) => acc + (t.multiplier * (t.weight / totalWeight) * 100), 0)
    : 0;

  // دالة تطبيق نسبة المكسب والخسارة الإجمالية (مثلاً: 10% مكسب / 90% خسارة، أو 0% مكسب "يخسرو يخسرو")
  const applyWinRate = (newWinRate: number) => {
    const clampedWin = Math.max(0, Math.min(100, Number(newWinRate)));
    setWinRate(clampedWin);
    const clampedLoss = 100 - clampedWin;

    const updated = [...oddsTiers];
    const lossIndex = updated.findIndex(t => t.multiplier === 0);

    if (clampedWin === 0) {
      // وضع الخسارة التامة 100%
      updated.forEach((t, i) => {
        if (i === lossIndex || t.multiplier === 0) {
          t.weight = 1000;
          t.probability = 100.0;
        } else {
          t.weight = 0;
          t.probability = 0.0;
        }
      });
      setOddsTiers(updated);
      return;
    }

    // مجموع أوزان المضاعفات الرابحة (> 0)
    let winWeightsSum = updated.filter(t => t.multiplier > 0).reduce((acc, t) => acc + t.weight, 0);
    if (winWeightsSum <= 0) {
      // إعادة ملء الأوزان الافتراضية للفوز إن كانت مصفّرة
      updated.forEach(t => {
        if (t.multiplier === 1) t.weight = 200;
        else if (t.multiplier === 2) t.weight = 90;
        else if (t.multiplier === 5) t.weight = 40;
        else if (t.multiplier === 10) t.weight = 15;
        else if (t.multiplier === 20) t.weight = 8;
        else if (t.multiplier === 50) t.weight = 4;
        else if (t.multiplier === 100) t.weight = 0.8;
        else if (t.multiplier === 250) t.weight = 0.35;
        else if (t.multiplier === 500) t.weight = 0.18;
        else if (t.multiplier === 1000) t.weight = 0.02;
      });
      winWeightsSum = updated.filter(t => t.multiplier > 0).reduce((acc, t) => acc + t.weight, 0);
    }

    // وزن الخسارة = وزن الفوز * (نسبة الخسارة / نسبة المكسب)
    const lossWeight = Number((winWeightsSum * (clampedLoss / clampedWin)).toFixed(2));
    if (lossIndex >= 0) {
      updated[lossIndex].weight = lossWeight;
    }

    const newTotal = updated.reduce((acc, t) => acc + t.weight, 0);
    updated.forEach(t => {
      t.probability = newTotal > 0 ? Number(((t.weight / newTotal) * 100).toFixed(3)) : 0;
    });
    setOddsTiers(updated);
  };

  const handleWeightChange = (index: number, newWeight: number) => {
    const updated = [...oddsTiers];
    updated[index].weight = Math.max(0, newWeight);
    const newTotal = updated.reduce((acc, t) => acc + t.weight, 0);
    updated.forEach(t => {
      t.probability = newTotal > 0 ? Number(((t.weight / newTotal) * 100).toFixed(3)) : 0;
    });
    setOddsTiers(updated);
    // تحديث نسبة المكسب المحسوبة تلقائياً (100 - نسبة الخسارة 0X)
    const lossTier = updated.find(t => t.multiplier === 0);
    const lossProb = lossTier?.probability ?? 0;
    setWinRate(Number(Math.max(0, Math.min(100, 100 - lossProb)).toFixed(1)));
  };

  const handleSave = async () => {
    setLoading(true);
    setSavedSuccess(false);
    try {
      const payload = {
        ...visuals,
        winRate,
        lossRate: Number((100 - winRate).toFixed(1)),
        targetPercentage,
        oddsTiers,
        giftsList,
        svgaLibrary,
        updated_at: new Date().toISOString(),
      };

      // Save to Supabase
      try {
        await supabase.from('app_config').upsert({
          key: 'lucky_box_config',
          value: payload,
        }, { onConflict: 'key' });

        await supabase.from('app_config').upsert({
          key: 'lucky_gift_target_percentage',
          value: targetPercentage,
        }, { onConflict: 'key' });
      } catch (sErr) {
        console.warn('Supabase lucky_box_config save error:', sErr);
      }

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
              تم حفظ التعديلات بنجاح في Supabase!
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
          {/* كارت نسبة دخول هدايا الحظ في تارجت وماسات المستلم */}
          <div className="bg-gradient-to-r from-amber-500/10 via-orange-500/10 to-transparent border border-amber-500/30 rounded-2xl p-5 space-y-4">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
              <div className="flex items-center gap-3">
                <div className="p-3 rounded-xl bg-amber-500/20 border border-amber-500/40 text-amber-300">
                  <Flame className="w-6 h-6" />
                </div>
                <div>
                  <h3 className="text-sm font-bold text-white flex items-center gap-2">
                    <span>نسبة احتساب هدايا الحظ في تارجت وماسات المستلم</span>
                    <span className="text-xs bg-amber-500 text-black font-extrabold px-2 py-0.5 rounded-full">
                      {targetPercentage}%
                    </span>
                  </h3>
                  <p className="text-xs text-slate-300 mt-1">
                    عند إرسال هدية حظ (مثلاً بقيمة 10 كوينز)، يحصل المستلم في رصيد ماساته وتارجت الوكالة على{' '}
                    <strong className="text-amber-400">
                      {((10 * targetPercentage) / 100).toFixed(1)} ماسة
                    </strong>{' '}
                    بدلاً من القيمة الكاملة، وذلك للحفاظ على توازن واقتصادية هدايا الحظ.
                  </p>
                </div>
              </div>

              {/* أزرار سريعة لاختيار النسبة */}
              <div className="flex items-center gap-1.5 flex-wrap">
                {[0, 5, 10, 15, 20, 50, 100].map(pct => (
                  <button
                    key={pct}
                    onClick={() => setTargetPercentage(pct)}
                    className={`px-3 py-1.5 rounded-lg text-xs font-bold transition border ${
                      targetPercentage === pct
                        ? 'bg-amber-500 text-black border-amber-400 shadow-lg shadow-amber-500/20'
                        : 'bg-black/40 text-slate-300 border-white/10 hover:border-amber-500/50 hover:text-white'
                    }`}
                  >
                    {pct}%
                  </button>
                ))}
              </div>
            </div>

            {/* سلايدر وحقل إدخال يدوي */}
            <div className="grid grid-cols-1 md:grid-cols-12 gap-4 items-center pt-3 border-t border-white/5">
              <div className="md:col-span-8 flex items-center gap-3">
                <span className="text-xs text-slate-400 shrink-0">0%</span>
                <input
                  type="range"
                  min="0"
                  max="100"
                  step="1"
                  value={targetPercentage}
                  onChange={e => setTargetPercentage(Number(e.target.value))}
                  className="w-full accent-amber-500 cursor-pointer"
                />
                <span className="text-xs text-slate-400 shrink-0">100%</span>
              </div>
              <div className="md:col-span-4 flex items-center gap-2">
                <span className="text-xs text-slate-300 font-medium shrink-0">النسبة المئوية:</span>
                <div className="relative flex-1">
                  <input
                    type="number"
                    min="0"
                    max="100"
                    step="0.5"
                    value={targetPercentage}
                    onChange={e => setTargetPercentage(Math.max(0, Math.min(100, parseFloat(e.target.value) || 0)))}
                    className="w-full bg-black/50 border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white focus:border-amber-500 outline-none pr-7 font-bold text-center"
                  />
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs text-amber-400 font-bold">%</span>
                </div>
              </div>
            </div>
          </div>

          {/* كارت التحكم المباشر بالمكسب والخسارة (Win/Loss Controller) */}
          <div className="bg-gradient-to-r from-emerald-500/10 via-cyan-500/10 to-rose-500/10 border border-emerald-500/30 rounded-2xl p-5 space-y-4">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
              <div className="flex items-center gap-3">
                <div className="p-3 rounded-xl bg-emerald-500/20 border border-emerald-500/40 text-emerald-300">
                  <Sliders className="w-6 h-6" />
                </div>
                <div>
                  <h3 className="text-sm font-bold text-white flex items-center gap-2">
                    <span>التحكم المباشر في المكسب والخسارة (Win vs Loss Controller)</span>
                    <span className="text-xs bg-emerald-500 text-black font-extrabold px-2.5 py-0.5 rounded-full">
                      مكسب: {winRate}%
                    </span>
                    <span className="text-xs bg-rose-500 text-white font-extrabold px-2.5 py-0.5 rounded-full">
                      خسارة: {(100 - winRate).toFixed(1)}%
                    </span>
                  </h3>
                  <p className="text-xs text-slate-300 mt-1">
                    يمكنك تحديد نسبة فوز المستخدمين مباشرة؛ أي نسبة تختارها تصبح نسبة الخسارة (0X) هي المكمل التلقائي لـ 100%.
                    مثال: إذا اخترت <strong className="text-emerald-400">10% مكسب</strong> تصبح الخسارة <strong className="text-rose-400">90%</strong>، وإذا اخترت <strong className="text-rose-400">0%</strong> تصبح الخسارة 100% مؤكدة ("يخسرو يخسرو").
                  </p>
                </div>
              </div>

              {/* أزرار الأوضاع السريعة */}
              <div className="flex items-center gap-1.5 flex-wrap">
                {[
                  { label: '🚫 خسارة تامة (0%)', val: 0, color: 'bg-rose-600 hover:bg-rose-700 text-white' },
                  { label: '🔻 خسارة 90% (مكسب 10%)', val: 10, color: 'bg-orange-600 hover:bg-orange-700 text-white' },
                  { label: '⚖️ مكسب 30% (خسارة 70%)', val: 30, color: 'bg-amber-600 hover:bg-amber-700 text-white' },
                  { label: '🎯 مكسب 40% (خسارة 60%)', val: 40, color: 'bg-yellow-600 hover:bg-yellow-700 text-black' },
                  { label: '🎁 مكسب 50% (متوازن)', val: 50, color: 'bg-cyan-600 hover:bg-cyan-700 text-white' },
                  { label: '🌟 مكسب 70% (سخي جداً)', val: 70, color: 'bg-emerald-600 hover:bg-emerald-700 text-white' },
                ].map(mode => (
                  <button
                    key={mode.val}
                    onClick={() => applyWinRate(mode.val)}
                    className={`px-3 py-1.5 rounded-lg text-xs font-bold transition border ${
                      winRate === mode.val
                        ? `${mode.color} border-white/40 shadow-lg shadow-white/10 ring-2 ring-white/30`
                        : 'bg-black/40 text-slate-300 border-white/10 hover:border-white/30 hover:text-white'
                    }`}
                  >
                    {mode.label}
                  </button>
                ))}
              </div>
            </div>

            {/* سلايدر وحقل إدخال يدوي لنسبة المكسب */}
            <div className="grid grid-cols-1 md:grid-cols-12 gap-4 items-center pt-3 border-t border-white/5">
              <div className="md:col-span-8 flex items-center gap-3">
                <span className="text-xs text-rose-400 font-bold shrink-0">0% (خسارة 100%)</span>
                <input
                  type="range"
                  min="0"
                  max="100"
                  step="1"
                  value={winRate}
                  onChange={e => applyWinRate(Number(e.target.value))}
                  className="w-full accent-emerald-500 cursor-pointer"
                />
                <span className="text-xs text-emerald-400 font-bold shrink-0">100% (مكسب تام)</span>
              </div>
              <div className="md:col-span-4 flex items-center gap-2">
                <span className="text-xs text-slate-300 font-medium shrink-0">نسبة المكسب المحددة:</span>
                <div className="relative flex-1">
                  <input
                    type="number"
                    min="0"
                    max="100"
                    step="0.5"
                    value={winRate}
                    onChange={e => applyWinRate(Math.max(0, Math.min(100, parseFloat(e.target.value) || 0)))}
                    className="w-full bg-black/50 border border-emerald-500/40 rounded-xl px-3 py-1.5 text-xs text-emerald-300 focus:border-emerald-400 outline-none pr-7 font-bold text-center"
                  />
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs text-emerald-400 font-bold">%</span>
                </div>
              </div>
            </div>
          </div>

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
                    <th className="p-3">ملف الـ SVGA المخصص للمضاعف (الأنيميشن)</th>
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
                      <td className="p-3">
                        {tier.multiplier === 0 ? (
                          <span className="text-[11px] text-slate-500">لا يتطلب أنيميشن (خسارة)</span>
                        ) : (
                          <div className="flex items-center gap-2">
                            <input
                              type="text"
                              value={tier.svgaUrl || ''}
                              onChange={e => {
                                const updated = [...oddsTiers];
                                updated[idx].svgaUrl = e.target.value;
                                setOddsTiers(updated);
                              }}
                              placeholder="assets/svga/... أو رابط SVGA"
                              className="w-48 bg-black/50 border border-white/10 rounded-lg px-2 py-1 text-[11px] text-slate-300 outline-none focus:border-amber-500"
                            />
                            <label className="cursor-pointer flex items-center gap-1 px-2 py-1 bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/40 rounded-lg text-[10px] font-bold whitespace-nowrap transition">
                              <Upload className="w-3 h-3" />
                              <span>رفع SVGA 📁</span>
                              <input
                                type="file"
                                accept=".svga,.vap,.mp4,.json,.png"
                                className="hidden"
                                onChange={async (e) => {
                                  const file = e.target.files?.[0];
                                  if (!file) return;
                                  try {
                                    const url = await uploadGiftAnimation(file, `multiplier_${tier.multiplier}_${Date.now()}`);
                                    const updated = [...oddsTiers];
                                    updated[idx].svgaUrl = url;
                                    setOddsTiers(updated);
                                  } catch (err) {
                                    alert('فشل رفع ملف SVGA');
                                  }
                                }}
                              />
                            </label>
                          </div>
                        )}
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
