import { useState, useEffect } from 'react';
import { 
  getGamePoolConfig, 
  updateGamePoolConfig, 
  topupGamePool, 
  getGameBetRecords,
  type GamePoolConfig, 
  type GameBetRecord 
} from '../lib/db';
import { 
  Gamepad2, 
  Coins, 
  TrendingUp, 
  Sliders, 
  RefreshCw, 
  CheckCircle2, 
  AlertCircle, 
  PlusCircle, 
  History, 
  Activity,
  ArrowUpRight,
  ArrowDownRight
} from 'lucide-react';

export default function GamePoolManager() {
  const [config, setConfig] = useState<GamePoolConfig | null>(null);
  const [records, setRecords] = useState<GameBetRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [topupAmount, setTopupAmount] = useState('');
  const [showTopupModal, setShowTopupModal] = useState(false);
  const [notification, setNotification] = useState<{ message: string; type: 'success' | 'error' } | null>(null);

  // Form states
  const [winRate, setWinRate] = useState(75);
  const [minBet, setMinBet] = useState(100);
  const [maxBet, setMaxBet] = useState(50000);
  const [maxMultiplier, setMaxMultiplier] = useState(10);
  const [isActive, setIsActive] = useState(true);

  useEffect(() => {
    loadData();
  }, []);

  async function loadData() {
    setLoading(true);
    try {
      const cfg = await getGamePoolConfig('sugarrush');
      const recs = await getGameBetRecords('sugarrush', 50);
      setConfig(cfg);
      setRecords(recs);

      setWinRate(cfg.win_rate ?? 75);
      setMinBet(cfg.min_bet ?? 100);
      setMaxBet(cfg.max_bet ?? 50000);
      setMaxMultiplier(cfg.max_multiplier ?? 10);
      setIsActive(cfg.is_active ?? true);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  }

  function notify(message: string, type: 'success' | 'error' = 'success') {
    setNotification({ message, type });
    setTimeout(() => setNotification(null), 4000);
  }

  async function handleSaveSettings() {
    setSaving(true);
    try {
      const ok = await updateGamePoolConfig('sugarrush', {
        win_rate: Number(winRate),
        min_bet: Number(minBet),
        max_bet: Number(maxBet),
        max_multiplier: Number(maxMultiplier),
        is_active: isActive,
      });

      if (ok) {
        notify('تم حفظ إعدادات نسبة الفوز والخسارة بنجاح!');
        loadData();
      } else {
        notify('حدث خطأ أثناء حفظ الإعدادات', 'error');
      }
    } catch (e) {
      notify('فشل في حفظ التعديلات', 'error');
    } finally {
      setSaving(false);
    }
  }

  async function handleConfirmTopup() {
    const val = parseInt(topupAmount, 10);
    if (!val || isNaN(val) || val <= 0) {
      notify('يرجى إدخال مبلغ كوينز صحيح', 'error');
      return;
    }

    try {
      const ok = await topupGamePool('sugarrush', val);
      if (ok) {
        notify(`تم شحن خزينة اللعبة بـ ${val.toLocaleString()} كوينز بنجاح!`);
        setShowTopupModal(false);
        setTopupAmount('');
        loadData();
      } else {
        notify('فشل في شحن رصيد الخزينة', 'error');
      }
    } catch (e) {
      notify('حدث خطأ في عملية الشحن', 'error');
    }
  }

  return (
    <div className="space-y-6 pb-12">
      {/* Toast Notification */}
      {notification && (
        <div className={`fixed top-6 left-1/2 -translate-x-1/2 z-50 px-5 py-3 rounded-xl shadow-2xl flex items-center gap-3 border text-sm font-bold backdrop-blur-md transition-all ${
          notification.type === 'success' 
            ? 'bg-emerald-500/20 border-emerald-500/40 text-emerald-300' 
            : 'bg-rose-500/20 border-rose-500/40 text-rose-300'
        }`}>
          {notification.type === 'success' ? <CheckCircle2 className="w-5 h-5" /> : <AlertCircle className="w-5 h-5" />}
          {notification.message}
        </div>
      )}

      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-gradient-to-r from-purple-900/40 via-pink-900/20 to-slate-900 border border-purple-500/20 p-6 rounded-2xl">
        <div className="flex items-center gap-4">
          <div className="w-14 h-14 rounded-2xl bg-gradient-to-tr from-pink-500 to-purple-600 flex items-center justify-center shadow-lg shadow-pink-500/30">
            <Gamepad2 className="w-8 h-8 text-white" />
          </div>
          <div>
            <h1 className="text-2xl font-black text-white flex items-center gap-2">
              إدارة خزينة ولعبة Sugar Rush
              <span className="text-xs px-2.5 py-0.5 rounded-full bg-pink-500/20 text-pink-300 border border-pink-500/30">
                HTML5 Game
              </span>
            </h1>
            <p className="text-sm text-slate-400 mt-1">
              التحكم في محفظة مجمع الأرباح (Game Pool)، نسبة الفوز والخسارة، وسجل مراهنات اللاعبين
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={loadData}
            disabled={loading}
            className="p-2.5 bg-slate-800/80 hover:bg-slate-700 text-slate-300 rounded-xl border border-slate-700/60 transition-all"
            title="تحديث"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          </button>

          <button
            onClick={() => setShowTopupModal(true)}
            className="flex items-center gap-2 px-4 py-2.5 bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500 text-white font-bold text-sm rounded-xl shadow-lg shadow-emerald-500/20 transition-all"
          >
            <PlusCircle className="w-4 h-4" />
            شحن رصيد الخزينة
          </button>
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        {/* Pool Balance */}
        <div className="bg-slate-900/70 border border-slate-800 p-5 rounded-2xl relative overflow-hidden group hover:border-pink-500/40 transition-all">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-400">رصيد خزينة الجوائز المتاح</span>
            <div className="p-2 rounded-xl bg-pink-500/10 text-pink-400">
              <Coins className="w-5 h-5" />
            </div>
          </div>
          <div className="mt-3 flex items-baseline gap-2">
            <span className="text-2xl font-black text-white">
              {(config?.pool_balance || 0).toLocaleString()}
            </span>
            <span className="text-xs text-pink-400 font-bold">كوينز</span>
          </div>
          <p className="text-[11px] text-slate-500 mt-2">
            يتم الصرف منه تلقائياً عند فوز اللاعبين في الجولات
          </p>
        </div>

        {/* Win Rate */}
        <div className="bg-slate-900/70 border border-slate-800 p-5 rounded-2xl relative overflow-hidden group hover:border-purple-500/40 transition-all">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-400">نسبة الفوز الحالية (RTP)</span>
            <div className="p-2 rounded-xl bg-purple-500/10 text-purple-400">
              <TrendingUp className="w-5 h-5" />
            </div>
          </div>
          <div className="mt-3 flex items-baseline gap-2">
            <span className="text-2xl font-black text-purple-400">
              {config?.win_rate ?? 75}%
            </span>
            <span className="text-xs text-slate-400">من إجمالي الجولات</span>
          </div>
          <p className="text-[11px] text-slate-500 mt-2">
            معدل العائد للمستخدمين مضبوط برمجياً
          </p>
        </div>

        {/* Bet Limits */}
        <div className="bg-slate-900/70 border border-slate-800 p-5 rounded-2xl relative overflow-hidden group hover:border-blue-500/40 transition-all">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-400">حدود الرهان (أدنى / أقصى)</span>
            <div className="p-2 rounded-xl bg-blue-500/10 text-blue-400">
              <Sliders className="w-5 h-5" />
            </div>
          </div>
          <div className="mt-3 flex items-baseline gap-1.5">
            <span className="text-xl font-black text-white">
              {(config?.min_bet || 100).toLocaleString()}
            </span>
            <span className="text-xs text-slate-500">-</span>
            <span className="text-xl font-black text-white">
              {(config?.max_bet || 50000).toLocaleString()}
            </span>
            <span className="text-xs text-blue-400 font-bold">كوينز</span>
          </div>
          <p className="text-[11px] text-slate-500 mt-2">
            أعلى مضاعف: {config?.max_multiplier || 10}X
          </p>
        </div>

        {/* Game Status */}
        <div className="bg-slate-900/70 border border-slate-800 p-5 rounded-2xl relative overflow-hidden group hover:border-emerald-500/40 transition-all">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-400">حالة تشغيل اللعبة</span>
            <div className={`p-2 rounded-xl ${config?.is_active ? 'bg-emerald-500/10 text-emerald-400' : 'bg-rose-500/10 text-rose-400'}`}>
              <Activity className="w-5 h-5" />
            </div>
          </div>
          <div className="mt-3 flex items-center gap-2">
            <span className={`w-3 h-3 rounded-full animate-pulse ${config?.is_active ? 'bg-emerald-500' : 'bg-rose-500'}`} />
            <span className="text-xl font-black text-white">
              {config?.is_active ? 'مفعلة وتعمل' : 'معطلة مؤقتاً'}
            </span>
          </div>
          <p className="text-[11px] text-slate-500 mt-2">
            تظهر داخل الغرف الصوتية في قائمة الألعاب
          </p>
        </div>
      </div>

      {/* Main Settings Form */}
      <div className="bg-slate-900/70 border border-slate-800 rounded-2xl p-6">
        <h2 className="text-lg font-black text-white flex items-center gap-2 mb-6">
          <Sliders className="w-5 h-5 text-pink-500" />
          تحديد وضبط نسب الربح والمضاعفات
        </h2>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {/* Win Rate Slider */}
          <div className="space-y-3 bg-slate-800/40 p-4 rounded-xl border border-slate-700/50">
            <div className="flex items-center justify-between">
              <label className="text-sm font-bold text-slate-300">
                نسبة الفوز الإجمالية (RTP %)
              </label>
              <span className="text-lg font-black text-pink-400 bg-pink-500/10 px-3 py-1 rounded-lg border border-pink-500/20">
                {winRate}%
              </span>
            </div>
            <input
              type="range"
              min="10"
              max="95"
              step="1"
              value={winRate}
              onChange={(e) => setWinRate(Number(e.target.value))}
              className="w-full accent-pink-500 cursor-pointer h-2 bg-slate-700 rounded-lg"
            />
            <div className="flex justify-between text-[11px] text-slate-500">
              <span>أرباح منخفضة (10%)</span>
              <span>متوسط متزن (70-75%)</span>
              <span>فوز سخي (95%)</span>
            </div>
          </div>

          {/* Max Win Multiplier */}
          <div className="space-y-2 bg-slate-800/40 p-4 rounded-xl border border-slate-700/50">
            <label className="text-sm font-bold text-slate-300">
              الحد الأقصى لمضاعف الفوز (Max Multiplier)
            </label>
            <div className="flex items-center gap-3">
              <input
                type="number"
                value={maxMultiplier}
                onChange={(e) => setMaxMultiplier(Number(e.target.value))}
                className="w-full bg-slate-900 border border-slate-700 rounded-xl px-4 py-2.5 text-white text-sm focus:outline-none focus:border-pink-500"
              />
              <span className="text-sm text-slate-400 font-bold">ضعف (X)</span>
            </div>
            <p className="text-[11px] text-slate-500">أقصى ربح يمكن أن يحصل عليه اللاعب في الضربة الواحدة بالنسبة لرهانه</p>
          </div>

          {/* Min Bet */}
          <div className="space-y-2 bg-slate-800/40 p-4 rounded-xl border border-slate-700/50">
            <label className="text-sm font-bold text-slate-300">
              الحد الأدنى للرهان (Min Bet)
            </label>
            <input
              type="number"
              value={minBet}
              onChange={(e) => setMinBet(Number(e.target.value))}
              className="w-full bg-slate-900 border border-slate-700 rounded-xl px-4 py-2.5 text-white text-sm focus:outline-none focus:border-pink-500"
            />
          </div>

          {/* Max Bet */}
          <div className="space-y-2 bg-slate-800/40 p-4 rounded-xl border border-slate-700/50">
            <label className="text-sm font-bold text-slate-300">
              الحد الأقصى للرهان (Max Bet)
            </label>
            <input
              type="number"
              value={maxBet}
              onChange={(e) => setMaxBet(Number(e.target.value))}
              className="w-full bg-slate-900 border border-slate-700 rounded-xl px-4 py-2.5 text-white text-sm focus:outline-none focus:border-pink-500"
            />
          </div>
        </div>

        {/* Toggle Active & Save */}
        <div className="mt-6 pt-6 border-t border-slate-800 flex flex-col sm:flex-row items-center justify-between gap-4">
          <label className="flex items-center gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={isActive}
              onChange={(e) => setIsActive(e.target.checked)}
              className="w-5 h-5 accent-pink-500 rounded cursor-pointer"
            />
            <span className="text-sm font-bold text-slate-200">
              تفعيل اللعبة وإتاحتها للاعبين داخل الغرف
            </span>
          </label>

          <button
            onClick={handleSaveSettings}
            disabled={saving}
            className="w-full sm:w-auto px-8 py-3 bg-gradient-to-r from-pink-600 to-purple-600 hover:from-pink-500 hover:to-purple-500 text-white font-bold text-sm rounded-xl shadow-lg shadow-pink-500/25 transition-all flex items-center justify-center gap-2"
          >
            {saving ? <RefreshCw className="w-4 h-4 animate-spin" /> : <CheckCircle2 className="w-4 h-4" />}
            حفظ وتطبيق الإعدادات فورياً
          </button>
        </div>
      </div>

      {/* Bet Records Table */}
      <div className="bg-slate-900/70 border border-slate-800 rounded-2xl p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-black text-white flex items-center gap-2">
            <History className="w-5 h-5 text-purple-400" />
            سجل مراهنات وأرباح اللاعبين الأخيرة
          </h2>
          <span className="text-xs text-slate-500">آخر 50 عملية</span>
        </div>

        {records.length === 0 ? (
          <div className="text-center py-12 text-slate-500 text-sm border border-dashed border-slate-800 rounded-xl">
            لا توجد رهانات مسجلة حتى الآن. ستظهر العمليات هنا فور بدء لعب المستخدمين.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-right text-xs">
              <thead className="bg-slate-800/60 text-slate-400 font-bold border-b border-slate-700/60">
                <tr>
                  <th className="py-3 px-4">اللاعب</th>
                  <th className="py-3 px-4">الغرفة</th>
                  <th className="py-3 px-4">مبلغ الرهان</th>
                  <th className="py-3 px-4">مبلغ الربح</th>
                  <th className="py-3 px-4">النتيجة الصافية</th>
                  <th className="py-3 px-4">الحالة</th>
                  <th className="py-3 px-4">التاريخ والوقت</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800 text-slate-300">
                {records.map((r) => (
                  <tr key={r.id} className="hover:bg-slate-800/30 transition-colors">
                    <td className="py-3 px-4 font-bold text-white">
                      {r.user_name || r.user_id}
                    </td>
                    <td className="py-3 px-4 text-slate-400 font-mono">
                      #{r.room_id || 'عام'}
                    </td>
                    <td className="py-3 px-4 font-mono font-bold text-slate-200">
                      {r.bet_amount?.toLocaleString()} كوينز
                    </td>
                    <td className="py-3 px-4 font-mono font-bold text-emerald-400">
                      {r.win_amount > 0 ? `+${r.win_amount.toLocaleString()}` : '0'} كوينز
                    </td>
                    <td className="py-3 px-4">
                      {r.net_result > 0 ? (
                        <span className="text-emerald-400 font-bold font-mono flex items-center gap-1">
                          <ArrowUpRight className="w-3.5 h-3.5" />
                          +${r.net_result.toLocaleString()}
                        </span>
                      ) : (
                        <span className="text-rose-400 font-bold font-mono flex items-center gap-1">
                          <ArrowDownRight className="w-3.5 h-3.5" />
                          {r.net_result?.toLocaleString()}
                        </span>
                      )}
                    </td>
                    <td className="py-3 px-4">
                      {r.is_win ? (
                        <span className="px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-bold text-[10px]">
                          فوز
                        </span>
                      ) : (
                        <span className="px-2 py-0.5 rounded-full bg-slate-800 text-slate-400 font-bold text-[10px]">
                          خسارة
                        </span>
                      )}
                    </td>
                    <td className="py-3 px-4 text-slate-500 text-[11px]">
                      {new Date(r.created_at).toLocaleString('ar-EG')}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Topup Modal */}
      {showTopupModal && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-md w-full p-6 shadow-2xl space-y-4">
            <h3 className="text-lg font-black text-white flex items-center gap-2">
              <PlusCircle className="w-5 h-5 text-emerald-400" />
              شحن رصيد خزينة الجوائز
            </h3>
            <p className="text-xs text-slate-400">
              قم بإضافة كوينز إلى رصيد الخزينة لتمكين اللاعبين من سحب وجني أرباح اللعبة بسلاسة
            </p>

            <div className="space-y-2">
              <label className="text-xs font-bold text-slate-300">مبلغ الكوينز للشحن</label>
              <input
                type="number"
                placeholder="مثال: 500000"
                value={topupAmount}
                onChange={(e) => setTopupAmount(e.target.value)}
                className="w-full bg-slate-800 border border-slate-700 rounded-xl px-4 py-3 text-white text-sm focus:outline-none focus:border-emerald-500 font-mono"
              />
            </div>

            <div className="flex gap-2">
              {[100000, 500000, 1000000, 5000000].map((amt) => (
                <button
                  key={amt}
                  type="button"
                  onClick={() => setTopupAmount(amt.toString())}
                  className="flex-1 py-1.5 bg-slate-800 hover:bg-slate-700 border border-slate-700 text-slate-300 text-[11px] font-bold rounded-lg transition-all"
                >
                  {(amt / 1000).toLocaleString()}K
                </button>
              ))}
            </div>

            <div className="flex items-center gap-3 pt-3">
              <button
                type="button"
                onClick={() => setShowTopupModal(false)}
                className="flex-1 py-2.5 bg-slate-800 hover:bg-slate-700 text-slate-300 text-sm font-bold rounded-xl transition-all"
              >
                إلغاء
              </button>
              <button
                type="button"
                onClick={handleConfirmTopup}
                className="flex-1 py-2.5 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-bold rounded-xl shadow-lg shadow-emerald-500/25 transition-all"
              >
                تأكيد الشحن
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
