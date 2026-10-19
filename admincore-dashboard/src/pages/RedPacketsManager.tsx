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
import { firestoreDb } from '../lib/firebase';
import { doc, getDoc, setDoc, collection, getDocs, query, orderBy, limit } from 'firebase/firestore';

interface RedPacketConfig {
  enabled: boolean;
  ttl_seconds: number;
  min_coins: number;
  max_coins: number;
  min_shares: number;
  max_shares: number;
  amount_presets: number[];
  shares_presets: number[];
  greetings: string[];
}

interface ActiveBag {
  id: string;
  room_id: string;
  owner_name: string;
  owner_photo: string;
  type: string;
  scope: string;
  is_super: boolean;
  total_value: number;
  remaining_value: number;
  total_shares: number;
  claimed_shares: number;
  luckiest_name?: string;
  luckiest_amount?: number;
  status: string;
  created_at: string;
  expires_at: string;
}

const defaultConfig: RedPacketConfig = {
  enabled: true,
  ttl_seconds: 90,
  min_coins: 100,
  max_coins: 1000000,
  min_shares: 2,
  max_shares: 200,
  amount_presets: [500, 1000, 2000, 5000, 10000, 20000, 50000, 100000],
  shares_presets: [5, 10, 20, 30, 50, 100],
  greetings: [
    'مبروك وموفقين ✨',
    'كل عام وأنتم بخير 🌙',
    'ألف مبروك للفائزين 🎁',
    'تحياتي للجميع ❤️',
  ],
};

export default function RedPacketsManager() {
  const [config, setConfig] = useState<RedPacketConfig>(defaultConfig);
  const [activeBags, setActiveBags] = useState<ActiveBag[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');
  const [errorMsg, setErrorMsg] = useState('');

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    setLoading(true);
    try {
      if (firestoreDb) {
        const cfgDoc = await getDoc(doc(firestoreDb, 'app_config', 'lucky_bag_config'));
        if (cfgDoc.exists()) {
          setConfig({ ...defaultConfig, ...(cfgDoc.data() as RedPacketConfig) });
        }

        const q = query(collection(firestoreDb, 'lucky_bags'), orderBy('created_at', 'desc'), limit(30));
        const snap = await getDocs(q);
        const bags: ActiveBag[] = [];
        snap.forEach((d) => {
          bags.push({ id: d.id, ...(d.data() as any) });
        });
        setActiveBags(bags);
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
      if (firestoreDb) {
        await setDoc(doc(firestoreDb, 'app_config', 'lucky_bag_config'), config, { merge: true });
        setSuccessMsg('تم حفظ إعدادات المظاريف الحمراء بنجاح ✅');
        setTimeout(() => setSuccessMsg(''), 4000);
      }
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
                onChange={(e) => setConfig({ ...config, ttl_seconds: parseInt(e.target.value) || 90 })}
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
                activeBags.map((bag) => (
                  <tr key={bag.id} className="hover:bg-neutral-800/40 transition">
                    <td className="p-3">
                      <div className="flex items-center space-x-2 space-x-reverse">
                        <div className="w-7 h-7 rounded-full bg-neutral-800 flex items-center justify-center overflow-hidden border border-neutral-700">
                          {bag.owner_photo ? (
                            <img src={bag.owner_photo} alt="" className="w-full h-full object-cover" />
                          ) : (
                            <span>👤</span>
                          )}
                        </div>
                        <span className="font-semibold text-white">{bag.owner_name || 'مستخدم'}</span>
                      </div>
                    </td>
                    <td className="p-3 text-neutral-300 font-mono">{bag.room_id}</td>
                    <td className="p-3">
                      <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                        bag.is_super ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40' : 'bg-red-500/20 text-red-300 border border-red-500/40'
                      }`}>
                        {bag.is_super ? '👑 سوبر' : '🧧 عادي'} · {bag.scope === 'mic' ? 'المايك' : 'الغرفة'}
                      </span>
                    </td>
                    <td className="p-3 text-amber-400 font-bold">{bag.total_value?.toLocaleString()} 🪙</td>
                    <td className="p-3 text-neutral-300">{bag.remaining_value?.toLocaleString()} 🪙</td>
                    <td className="p-3 text-neutral-300">
                      {bag.claimed_shares || 0} / {bag.total_shares || 0}
                    </td>
                    <td className="p-3">
                      {bag.luckiest_name ? (
                        <span className="text-amber-300 font-semibold flex items-center space-x-1 space-x-reverse">
                          <span>👑 {bag.luckiest_name}</span>
                          <span className="text-[10px] text-neutral-400">({bag.luckiest_amount} 🪙)</span>
                        </span>
                      ) : (
                        <span className="text-neutral-500">-</span>
                      )}
                    </td>
                    <td className="p-3">
                      <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                        bag.status === 'active' ? 'bg-emerald-500/20 text-emerald-300' : 'bg-neutral-800 text-neutral-400'
                      }`}>
                        {bag.status === 'active' ? '🟢 نشط' : 'منتهي'}
                      </span>
                    </td>
                    <td className="p-3 text-neutral-400 text-[10px]">
                      {bag.created_at ? new Date(bag.created_at).toLocaleTimeString('ar-EG') : '-'}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
