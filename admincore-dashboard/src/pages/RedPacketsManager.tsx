import React, { useState, useEffect } from 'react';
import {
  Gift,
  Coins,
  Settings,
  Clock,
  Sliders,
  Save,
  RotateCcw,
  CheckCircle,
  AlertCircle,
  Eye,
  Trash2,
  Users,
  Sparkles,
  Flame,
  Award
} from 'lucide-react';
import { supabase } from '../lib/supabase';
import { uploadAppAsset } from '../lib/storage';

interface RedPacketConfig {
  enabled: boolean;
  ttl_seconds: number;
  min_coins: number;
  max_coins: number;
  min_shares: number;
  max_shares: number;
  max_bags_per_send: number;
  max_active_per_room: number;
  amount_presets: number[];
  shares_presets: number[];
  duration_presets: number[];
  greetings: string[];
  bag_image: string;
  panel_background: string;
  primary_color: string;
  secondary_color: string;
  countdown_color: string;
}

interface LuckyBagClaimRow {
  claimerId?: string;
  claimerName?: string;
  claimer_name?: string;
  amount?: number;
}

interface LuckyBagClaimsMeta {
  type?: string;
  scope?: string;
  distribution?: string;
  greeting?: string;
}

interface ActiveBag {
  id: string;
  room_id: string;
  sender_name: string;
  sender_photo: string;
  total_value: number;
  remaining_value: number;
  total_count: number;
  remaining_count: number;
  status: string;
  created_at: string;
  expires_at: string;
  claims?: { meta?: LuckyBagClaimsMeta; list?: LuckyBagClaimRow[] } | LuckyBagClaimRow[];
}

const defaultConfig: RedPacketConfig = {
  enabled: true,
  ttl_seconds: 30,
  min_coins: 100,
  max_coins: 1000000,
  min_shares: 2,
  max_shares: 200,
  max_bags_per_send: 200,
  max_active_per_room: 3,
  amount_presets: [500, 1000, 2000, 5000, 10000, 20000],
  shares_presets: [5, 10, 15, 20, 30, 50],
  duration_presets: [10, 30, 240, 600],
  greetings: [
    'حظ سعيد للجميع ✨',
    'مبروك وموفقين 🎁',
    'كل عام وأنتم بخير 🌙',
  ],
  bag_image: '',
  panel_background: '',
  primary_color: '#FFF295',
  secondary_color: '#134015',
  countdown_color: '#000000',
};

const claimMeta = (bag: ActiveBag): LuckyBagClaimsMeta => {
  if (!bag.claims || Array.isArray(bag.claims)) return {};
  return bag.claims.meta || {};
};

const claimList = (bag: ActiveBag): LuckyBagClaimRow[] => {
  if (!bag.claims) return [];
  return Array.isArray(bag.claims) ? bag.claims : (bag.claims.list || []);
};

const luckiestClaim = (bag: ActiveBag): LuckyBagClaimRow | null => {
  const list = claimList(bag);
  if (list.length === 0) return null;
  return list.reduce((best, c) =>
    (c.amount || 0) > (best.amount || 0) ? c : best, list[0]);
};

const statusLabel = (status: string) => {
  if (status === 'active') return '🟢 نشط';
  if (status === 'claimed') return '✅ مكتمل';
  return '⏰ منتهي';
};

const toColorInput = (value: string) => {
  const cleaned = (value || '').replace('#', '').trim();
  if (cleaned.length >= 6) return `#${cleaned.slice(0, 6)}`;
  return '#ffffff';
};

export default function RedPacketsManager() {
  const [config, setConfig] = useState<RedPacketConfig>(defaultConfig);
  const [activeBags, setActiveBags] = useState<ActiveBag[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [uploadingField, setUploadingField] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState('');
  const [errorMsg, setErrorMsg] = useState('');

  const handleUpload = async (file: File, field: 'bag_image' | 'panel_background') => {
    setUploadingField(field);
    setErrorMsg('');
    try {
      const url = await uploadAppAsset(file, `lucky_bag_${field}`);
      setConfig((prev) => ({ ...prev, [field]: url }));
      setSuccessMsg('تم رفع الصورة بنجاح ✅');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error('upload failed', err);
      setErrorMsg('فشل رفع الصورة، حاول مرة أخرى');
    } finally {
      setUploadingField(null);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    setLoading(true);
    try {
      const { data: cfgRow } = await supabase
        .from('app_config')
        .select('value')
        .eq('key', 'lucky_bag_config')
        .maybeSingle();

      if (cfgRow?.value) {
        const val = typeof cfgRow.value === 'string' ? JSON.parse(cfgRow.value) : cfgRow.value;
        setConfig({ ...defaultConfig, ...val });
      }

      const { data: bagsData } = await supabase
        .from('lucky_bags')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(30);

      if (bagsData) {
        setActiveBags(bagsData as ActiveBag[]);
      }
    } catch (err: any) {
      console.error('Failed to fetch red packet config:', err);
      setErrorMsg('فشل جلب إعدادات المظاريف الحمراء');
    } finally {
      setLoading(false);
    }
  };

  const handleSaveConfig = async () => {
    setSaving(true);
    setSuccessMsg('');
    setErrorMsg('');
    try {
      const { error } = await supabase.from('app_config').upsert({
        key: 'lucky_bag_config',
        value: config,
      }, { onConflict: 'key' });

      if (error) throw error;
      setSuccessMsg('تم حفظ إعدادات المظاريف الحمراء بنجاح في Supabase ✅');
      setTimeout(() => setSuccessMsg(''), 4000);
    } catch (err: any) {
      console.error('Failed to save config:', err);
      setErrorMsg('حدث خطأ أثناء حفظ الإعدادات');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6 text-white" dir="rtl">
      {/* Header */}
      <div className="flex items-center justify-between bg-gradient-to-r from-red-900/60 via-red-800/40 to-neutral-900 p-6 rounded-2xl border border-red-500/30 backdrop-blur-md">
        <div className="flex items-center space-x-4 space-x-reverse">
          <div className="w-14 h-14 bg-gradient-to-br from-amber-400 to-red-600 rounded-2xl flex items-center justify-center shadow-lg shadow-red-500/30 text-3xl">
            🧧
          </div>
          <div>
            <h1 className="text-2xl font-black text-amber-300">إدارة المظاريف الحمراء وصناديق الحظ</h1>
            <p className="text-neutral-300 text-sm mt-1">
              التحكم الكامل في إعدادات، مبالغ، وأنصبة توزيع العملات في الغرف (Red Envelopes / Lucky Bags)
            </p>
          </div>
        </div>

        <button
          onClick={handleSaveConfig}
          disabled={saving}
          className="flex items-center space-x-2 space-x-reverse bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-400 hover:to-amber-500 text-black px-6 py-2.5 rounded-xl font-bold transition shadow-lg shadow-amber-500/20 disabled:opacity-50"
        >
          <Save className="w-5 h-5" />
          <span>{saving ? 'جارٍ الحفظ...' : 'حفظ التغييرات'}</span>
        </button>
      </div>

      {/* Alerts */}
      {successMsg && (
        <div className="flex items-center space-x-2 space-x-reverse bg-emerald-500/20 border border-emerald-500/40 text-emerald-300 p-4 rounded-xl">
          <CheckCircle className="w-5 h-5 flex-shrink-0" />
          <span>{successMsg}</span>
        </div>
      )}
      {errorMsg && (
        <div className="flex items-center space-x-2 space-x-reverse bg-red-500/20 border border-red-500/40 text-red-300 p-4 rounded-xl">
          <AlertCircle className="w-5 h-5 flex-shrink-0" />
          <span>{errorMsg}</span>
        </div>
      )}

      {/* Main Settings Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* System & Limits Configuration */}
        <div className="bg-neutral-900/80 rounded-2xl p-6 border border-neutral-800 space-y-5">
          <div className="flex items-center space-x-2 space-x-reverse text-amber-400 font-bold text-lg border-b border-neutral-800 pb-3">
            <Sliders className="w-5 h-5" />
            <span>الإعدادات العامة والحدود</span>
          </div>

          <div className="flex items-center justify-between p-4 bg-neutral-950/60 rounded-xl border border-neutral-800">
            <div>
              <div className="font-semibold text-white">تفعيل نظام المظاريف الحمراء</div>
              <div className="text-xs text-neutral-400">إتاحة إرسال وفتح المظاريف داخل الغرف الصوتية</div>
            </div>
            <label className="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                checked={config.enabled}
                onChange={(e) => setConfig({ ...config, enabled: e.target.checked })}
                className="sr-only peer"
              />
              <div className="w-11 h-6 bg-neutral-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-neutral-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-amber-500"></div>
            </label>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold text-neutral-400 mb-1">
                صلاحية المظروف (بالثواني)
              </label>
              <input
                type="number"
                value={config.ttl_seconds}
                onChange={(e) => setConfig({ ...config, ttl_seconds: parseInt(e.target.value) || 30 })}
                className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-white font-mono focus:border-amber-500 outline-none"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-neutral-400 mb-1">
                أقصى عدد أنصبة (فائزين)
              </label>
              <input
                type="number"
                value={config.max_shares}
                onChange={(e) => setConfig({ ...config, max_shares: parseInt(e.target.value) || 200 })}
                className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-white font-mono focus:border-amber-500 outline-none"
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold text-neutral-400 mb-1">
                أقصى عدد حقائب في الإرسال الواحد
              </label>
              <input
                type="number"
                value={config.max_bags_per_send}
                onChange={(e) => setConfig({ ...config, max_bags_per_send: parseInt(e.target.value) || 200 })}
                className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-white font-mono focus:border-amber-500 outline-none"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-neutral-400 mb-1">
                أقصى عدد حقائب نشطة في الغرفة
              </label>
              <input
                type="number"
                value={config.max_active_per_room}
                onChange={(e) => setConfig({ ...config, max_active_per_room: parseInt(e.target.value) || 0 })}
                className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-white font-mono focus:border-amber-500 outline-none"
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold text-neutral-400 mb-1">
                الحد الأدنى للعملات (🪙)
              </label>
              <input
                type="number"
                value={config.min_coins}
                onChange={(e) => setConfig({ ...config, min_coins: parseInt(e.target.value) || 100 })}
                className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-white font-mono focus:border-amber-500 outline-none"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-neutral-400 mb-1">
                الحد الأقصى للعملات (🪙)
              </label>
              <input
                type="number"
                value={config.max_coins}
                onChange={(e) => setConfig({ ...config, max_coins: parseInt(e.target.value) || 1000000 })}
                className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-white font-mono focus:border-amber-500 outline-none"
              />
            </div>
          </div>
        </div>

        {/* Presets Configuration */}
        <div className="bg-neutral-900/80 rounded-2xl p-6 border border-neutral-800 space-y-5">
          <div className="flex items-center space-x-2 space-x-reverse text-amber-400 font-bold text-lg border-b border-neutral-800 pb-3">
            <Coins className="w-5 h-5" />
            <span>خيارات ومبالغ الإرسال السريعة</span>
          </div>

          <div>
            <label className="block text-xs font-semibold text-neutral-400 mb-1">
              مبالغ العملات السريعة (مفصولة بفاصلة)
            </label>
            <input
              type="text"
              value={config.amount_presets.join(', ')}
              onChange={(e) => {
                const arr = e.target.value.split(',').map((s) => parseInt(s.trim())).filter((n) => !isNaN(n));
                setConfig({ ...config, amount_presets: arr });
              }}
              className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-white font-mono focus:border-amber-500 outline-none"
            />
            <div className="flex flex-wrap gap-2 mt-2">
              {config.amount_presets.map((amt) => (
                <span key={amt} className="px-2.5 py-1 bg-amber-500/10 border border-amber-500/30 text-amber-300 rounded-lg text-xs font-bold">
                  {amt.toLocaleString()} 🪙
                </span>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-neutral-400 mb-1">
              خيارات عدد الأنصبة (مفصولة بفاصلة)
            </label>
            <input
              type="text"
              value={config.shares_presets.join(', ')}
              onChange={(e) => {
                const arr = e.target.value.split(',').map((s) => parseInt(s.trim())).filter((n) => !isNaN(n));
                setConfig({ ...config, shares_presets: arr });
              }}
              className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-white font-mono focus:border-amber-500 outline-none"
            />
            <div className="flex flex-wrap gap-2 mt-2">
              {config.shares_presets.map((cnt) => (
                <span key={cnt} className="px-2.5 py-1 bg-red-500/10 border border-red-500/30 text-red-300 rounded-lg text-xs font-bold">
                  {cnt} نصيب
                </span>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-neutral-400 mb-1">
              خيارات مدة الحقيبة بالثواني (10 / 30 / 240 / 600)
            </label>
            <input
              type="text"
              value={config.duration_presets.join(', ')}
              onChange={(e) => {
                const arr = e.target.value.split(',').map((s) => parseInt(s.trim())).filter((n) => !isNaN(n) && n > 0);
                setConfig({ ...config, duration_presets: arr });
              }}
              className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-white font-mono focus:border-amber-500 outline-none"
            />
            <div className="flex flex-wrap gap-2 mt-2">
              {config.duration_presets.map((sec) => (
                <span key={sec} className="px-2.5 py-1 bg-emerald-500/10 border border-emerald-500/30 text-emerald-300 rounded-lg text-xs font-bold">
                  {sec >= 60 ? `${Math.round(sec / 60)} دقيقة` : `${sec} ثانية`}
                </span>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-neutral-400 mb-1">
              عبارات التهنئة الافتراضية
            </label>
            <div className="space-y-2">
              {config.greetings.map((g, idx) => (
                <input
                  key={idx}
                  type="text"
                  value={g}
                  onChange={(e) => {
                    const newG = [...config.greetings];
                    newG[idx] = e.target.value;
                    setConfig({ ...config, greetings: newG });
                  }}
                  className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-1.5 text-xs text-white focus:border-amber-500 outline-none"
                />
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Appearance: images & colors (reads by Flutter via LuckyBagConfig) */}
      <div className="bg-neutral-900/80 rounded-2xl p-6 border border-neutral-800 space-y-5">
        <div className="flex items-center space-x-2 space-x-reverse text-amber-400 font-bold text-lg border-b border-neutral-800 pb-3">
          <Sparkles className="w-5 h-5" />
          <span>المظهر: الصور والألوان</span>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {/* Images */}
          <div className="space-y-4">
            {([
              { key: 'bag_image' as const, label: 'صورة الحقيبة' },
              { key: 'panel_background' as const, label: 'خلفية لوحة الإرسال' },
            ]).map(({ key, label }) => (
              <div key={key} className="p-4 bg-neutral-950/60 rounded-xl border border-neutral-800">
                <label className="block text-xs font-semibold text-neutral-400 mb-2">{label}</label>
                <div className="flex items-center gap-3">
                  <div className="w-16 h-16 rounded-xl bg-neutral-900 border border-neutral-700 flex items-center justify-center overflow-hidden">
                    {config[key] ? (
                      <img src={config[key]} alt="" className="w-full h-full object-contain" />
                    ) : (
                      <span className="text-2xl">🧧</span>
                    )}
                  </div>
                  <div className="flex-1 space-y-2">
                    <input
                      type="text"
                      value={config[key]}
                      onChange={(e) => setConfig({ ...config, [key]: e.target.value })}
                      placeholder="https://..."
                      className="w-full bg-neutral-950 border border-neutral-800 rounded-lg px-3 py-1.5 text-xs text-white font-mono focus:border-amber-500 outline-none"
                    />
                    <div className="flex items-center gap-2">
                      <label className={`cursor-pointer text-xs font-bold px-3 py-1.5 rounded-lg border ${
                        uploadingField === key
                          ? 'bg-neutral-800 text-neutral-500 border-neutral-700'
                          : 'bg-amber-500/15 text-amber-300 border-amber-500/40 hover:bg-amber-500/25'
                      }`}>
                        {uploadingField === key ? 'جارٍ الرفع...' : 'رفع صورة'}
                        <input
                          type="file"
                          accept="image/*"
                          className="hidden"
                          disabled={uploadingField === key}
                          onChange={(e) => {
                            const file = e.target.files?.[0];
                            if (file) handleUpload(file, key);
                            e.target.value = '';
                          }}
                        />
                      </label>
                      {config[key] && (
                        <button
                          onClick={() => setConfig({ ...config, [key]: '' })}
                          className="text-xs text-red-300 bg-red-500/10 border border-red-500/30 px-3 py-1.5 rounded-lg hover:bg-red-500/20"
                        >
                          مسح
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>

          {/* Colors */}
          <div className="space-y-4">
            {([
              { key: 'primary_color' as const, label: 'اللون الأساسي (الذهبي)' },
              { key: 'secondary_color' as const, label: 'اللون الثانوي (الأخضر)' },
              { key: 'countdown_color' as const, label: 'لون العدّاد التنازلي' },
            ]).map(({ key, label }) => (
              <div key={key} className="flex items-center justify-between gap-3 p-3 bg-neutral-950/60 rounded-xl border border-neutral-800">
                <div>
                  <div className="text-xs font-semibold text-neutral-300">{label}</div>
                  <div className="text-[10px] text-neutral-500 font-mono">{config[key] || '-'}</div>
                </div>
                <div className="flex items-center gap-2">
                  <input
                    type="color"
                    value={toColorInput(config[key])}
                    onChange={(e) => setConfig({ ...config, [key]: e.target.value.toUpperCase() })}
                    className="w-10 h-10 bg-transparent border border-neutral-700 rounded-lg cursor-pointer"
                  />
                  <input
                    type="text"
                    value={config[key]}
                    onChange={(e) => setConfig({ ...config, [key]: e.target.value })}
                    className="w-28 bg-neutral-950 border border-neutral-800 rounded-lg px-2 py-1.5 text-xs text-white font-mono focus:border-amber-500 outline-none"
                  />
                </div>
              </div>
            ))}
            <p className="text-[11px] text-neutral-500 leading-relaxed">
              الألوان تُطبّق على الحقيبة العائمة، حوار الفتح، وقائمة الحقائب داخل التطبيق مباشرة بعد الحفظ.
            </p>
          </div>
        </div>
      </div>

      {/* Monitoring Table of Recent / Active Red Envelopes */}
      <div className="bg-neutral-900/80 rounded-2xl p-6 border border-neutral-800 space-y-4">
        <div className="flex items-center justify-between border-b border-neutral-800 pb-4">
          <div className="flex items-center space-x-2 space-x-reverse text-amber-400 font-bold text-lg">
            <Gift className="w-5 h-5" />
            <span>سجل المظاريف الحمراء الحية والسابقة</span>
          </div>
          <button
            onClick={fetchData}
            className="text-xs text-neutral-400 hover:text-white flex items-center space-x-1 space-x-reverse bg-neutral-800 px-3 py-1.5 rounded-lg"
          >
            <RotateCcw className="w-3.5 h-3.5" />
            <span>تحديث السجل</span>
          </button>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-right text-xs">
            <thead className="bg-neutral-950 text-neutral-400 uppercase border-b border-neutral-800">
              <tr>
                <th className="p-3">المرسل</th>
                <th className="p-3">الغرفة</th>
                <th className="p-3">النوع والنطاق</th>
                <th className="p-3">إجمالي العملات</th>
                <th className="p-3">المتبقي</th>
                <th className="p-3">الأنصبة</th>
                <th className="p-3">ملك الحظ 👑</th>
                <th className="p-3">الحالة</th>
                <th className="p-3">التاريخ</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-800/60">
              {activeBags.length === 0 ? (
                <tr>
                  <td colSpan={9} className="text-center py-8 text-neutral-500">
                    لا توجد مظاريف مسجلة حتى الآن
                  </td>
                </tr>
              ) : (
                activeBags.map((bag) => {
                  const meta = claimMeta(bag);
                  const claimed = claimList(bag).length;
                  const luckiest = luckiestClaim(bag);
                  return (
                  <tr key={bag.id} className="hover:bg-neutral-800/40 transition">
                    <td className="p-3">
                      <div className="flex items-center space-x-2 space-x-reverse">
                        <div className="w-7 h-7 rounded-full bg-neutral-800 flex items-center justify-center overflow-hidden border border-neutral-700">
                          {bag.sender_photo ? (
                            <img src={bag.sender_photo} alt="" className="w-full h-full object-cover" />
                          ) : (
                            <span>👤</span>
                          )}
                        </div>
                        <span className="font-semibold text-white">{bag.sender_name || 'مستخدم'}</span>
                      </div>
                    </td>
                    <td className="p-3 text-neutral-300 font-mono">{bag.room_id}</td>
                    <td className="p-3">
                      <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                        meta.type === 'super' ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40' : 'bg-red-500/20 text-red-300 border border-red-500/40'
                      }`}>
                        {meta.type === 'super' ? '👑 سوبر' : '🧧 عادي'} · {meta.scope === 'mic' ? 'المايك' : 'الغرفة'}
                      </span>
                    </td>
                    <td className="p-3 text-amber-400 font-bold">{bag.total_value?.toLocaleString()} 🪙</td>
                    <td className="p-3 text-neutral-300">{bag.remaining_value?.toLocaleString()} 🪙</td>
                    <td className="p-3 text-neutral-300">
                      {claimed} / {bag.total_count || 0}
                      <span className="text-[10px] text-neutral-500 block">متبقي {bag.remaining_count || 0}</span>
                    </td>
                    <td className="p-3">
                      {luckiest ? (
                        <span className="text-amber-300 font-semibold flex items-center space-x-1 space-x-reverse">
                          <span>👑 {luckiest.claimerName || luckiest.claimer_name || 'مستخدم'}</span>
                          <span className="text-[10px] text-neutral-400">({luckiest.amount} 🪙)</span>
                        </span>
                      ) : (
                        <span className="text-neutral-500">-</span>
                      )}
                    </td>
                    <td className="p-3">
                      <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                        bag.status === 'active' ? 'bg-emerald-500/20 text-emerald-300' : 'bg-neutral-800 text-neutral-400'
                      }`}>
                        {statusLabel(bag.status)}
                      </span>
                    </td>
                    <td className="p-3 text-neutral-400 text-[10px]">
                      {bag.created_at ? new Date(bag.created_at).toLocaleTimeString('ar-EG') : '-'}
                    </td>
                  </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
