import { useState, useEffect } from 'react';
import { 
  Coins, Diamond, CreditCard, Save, RefreshCw, Plus, Trash2, 
  CheckCircle2, ArrowRightLeft, Sparkles, Smartphone, Globe, 
  ShieldCheck, Clock, Check, X, Building2, User, ExternalLink
} from 'lucide-react';
import { 
  getAppConfig, updateAppConfig, getRechargeRequests, 
  approveRechargeRequest, rejectRechargeRequest 
} from '../lib/db';
import type { RechargeRequestModel } from '../types';

interface RechargePlan {
  id: number | string;
  amount: number;
  price: number;
  bonus: number;
  currency: 'coins' | 'diamonds';
  tag?: string;
  isActive?: boolean;
}

interface DiamondExchangeConfig {
  coinsPerDiamond: number;
  minDiamonds: number;
  enabled: boolean;
}

interface RechargeGateways {
  googlePlayEnabled: boolean;
  vodafoneCashEnabled: boolean;
  vodafoneCashNumber: string;
  vodafoneCashName: string;
  vodafoneCashInstructions: string;
  binanceEnabled: boolean;
  binanceId: string;
  binanceAddress: string;
  binanceInstructions: string;
  instapayEnabled: boolean;
  instapayAddress: string;
  instapayAccountName: string;
  instapayInstructions: string;
  orangeCashEnabled: boolean;
  orangeCashNumber: string;
  etisalatCashEnabled: boolean;
  etisalatCashNumber: string;
  wePayEnabled: boolean;
  wePayNumber: string;
}

export default function RechargeSettings() {
  const [activeTab, setActiveTab] = useState<'exchange' | 'plans' | 'gateways' | 'requests'>('exchange');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saveSuccess, setSaveSuccess] = useState(false);

  // 1. Diamond Exchange State
  const [exchangeConfig, setExchangeConfig] = useState<DiamondExchangeConfig>({
    coinsPerDiamond: 1.0,
    minDiamonds: 10,
    enabled: true,
  });
  const [calcDiamonds, setCalcDiamonds] = useState<number>(100);

  // 2. Recharge Plans State
  const [plans, setPlans] = useState<RechargePlan[]>([]);
  const [plansCurrencyTab, setPlansCurrencyTab] = useState<'coins' | 'diamonds'>('coins');

  // 3. Gateways State
  const [gateways, setGateways] = useState<RechargeGateways>({
    googlePlayEnabled: true,
    vodafoneCashEnabled: true,
    vodafoneCashNumber: '01000000000',
    vodafoneCashName: 'الإدارة الرسمية',
    vodafoneCashInstructions: 'قم بتحويل المبلغ لرقم فودافون كاش الموضح ثم أدخل رقمك ورقم العملية للتأكيد.',
    binanceEnabled: true,
    binanceId: '84920193',
    binanceAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    binanceInstructions: 'أرسل USDT (TRC-20) للعنوان الموضح أو أرسل عبر Binance Pay ID، ثم أدخل رقم المعاملة TXID.',
    instapayEnabled: true,
    instapayAddress: 'payment@instapay',
    instapayAccountName: 'حساب التطبيق الرسمي',
    instapayInstructions: 'حول عبر تطبيق انستاباي ثم ادخل الرقم المرجعي للتحويل.',
    orangeCashEnabled: false,
    orangeCashNumber: '',
    etisalatCashEnabled: false,
    etisalatCashNumber: '',
    wePayEnabled: false,
    wePayNumber: '',
  });

  // 4. Recharge Requests State
  const [requests, setRequests] = useState<RechargeRequestModel[]>([]);
  const [reqFilter, setReqFilter] = useState<'all' | 'pending' | 'approved' | 'rejected'>('pending');
  const [reqProcessingId, setReqProcessingId] = useState<string | null>(null);

  useEffect(() => {
    loadConfig();
  }, []);

  const loadConfig = async () => {
    setLoading(true);
    try {
      const cfg: any = await getAppConfig();
      if (cfg) {
        if (cfg.diamond_exchange_config) {
          setExchangeConfig({
            coinsPerDiamond: Number(cfg.diamond_exchange_config.coinsPerDiamond ?? 1.0),
            minDiamonds: Number(cfg.diamond_exchange_config.minDiamonds ?? 10),
            enabled: cfg.diamond_exchange_config.enabled ?? true,
          });
        } else if (cfg.diamondToCoinRate !== undefined) {
          const legacyRate = Number(cfg.diamondToCoinRate);
          setExchangeConfig({
            coinsPerDiamond: legacyRate === 1 ? 1.0 : (legacyRate > 0 ? 1.0 / legacyRate : 1.0),
            minDiamonds: 10,
            enabled: true,
          });
        }

        if (cfg.recharge_plans) {
          let parsedPlans = cfg.recharge_plans;
          if (typeof parsedPlans === 'string') {
            try { parsedPlans = JSON.parse(parsedPlans); } catch (_) {}
          }
          if (Array.isArray(parsedPlans) && parsedPlans.length > 0) {
            setPlans(parsedPlans);
          } else {
            setDefaultFallbackPlans();
          }
        } else {
          setDefaultFallbackPlans();
        }

        if (cfg.recharge_gateways) {
          let parsedGw = cfg.recharge_gateways;
          if (typeof parsedGw === 'string') {
            try { parsedGw = JSON.parse(parsedGw); } catch (_) {}
          }
          if (parsedGw && typeof parsedGw === 'object') {
            setGateways(prev => ({ ...prev, ...parsedGw }));
          }
        }
      } else {
        setDefaultFallbackPlans();
      }

      // Load recharge requests
      try {
        const reqs = await getRechargeRequests();
        setRequests(reqs);
      } catch (_) {}
    } catch (e) {
      console.error('Failed to load recharge config:', e);
      setDefaultFallbackPlans();
    } finally {
      setLoading(false);
    }
  };

  const handleApproveRequest = async (req: RechargeRequestModel) => {
    if (!confirm(`هل أنت متأكد من اعتماد طلب الشحن وإضافة ${req.amount.toLocaleString()} ${req.currency} لحساب ${req.userName}؟`)) return;
    setReqProcessingId(req.id);
    try {
      await approveRechargeRequest(req);
      setRequests(prev => prev.map(r => r.id === req.id ? { ...r, status: 'approved' } : r));
      alert('تم اعتماد طلب الشحن وإضافة الرصيد للمستخدم بنجاح!');
    } catch (e) {
      alert('حدث خطأ أثناء اعتماد الطلب');
    } finally {
      setReqProcessingId(null);
    }
  };

  const handleRejectRequest = async (req: RechargeRequestModel) => {
    const reason = prompt('يرجى كتابة سبب رفض طلب الشحن:', 'بيانات التحويل غير متطابقة مع الرصيد المحول');
    if (reason === null) return;
    setReqProcessingId(req.id);
    try {
      await rejectRechargeRequest(req, reason);
      setRequests(prev => prev.map(r => r.id === req.id ? { ...r, status: 'rejected', rejectionReason: reason } : r));
      alert('تم رفض طلب الشحن وإشعار المستخدم');
    } catch (e) {
      alert('حدث خطأ أثناء رفض الطلب');
    } finally {
      setReqProcessingId(null);
    }
  };

  const setDefaultFallbackPlans = () => {
    setPlans([
      { id: 1, amount: 1000, price: 1.0, bonus: 0, currency: 'coins', tag: 'POPULAR', isActive: true },
      { id: 2, amount: 5000, price: 5.0, bonus: 200, currency: 'coins', tag: 'HOT', isActive: true },
      { id: 3, amount: 10000, price: 10.0, bonus: 500, currency: 'coins', tag: 'BEST VALUE', isActive: true },
      { id: 4, amount: 50000, price: 50.0, bonus: 3000, currency: 'coins', tag: 'VIP', isActive: true },
      { id: 5, amount: 100000, price: 100.0, bonus: 8000, currency: 'coins', tag: 'KING', isActive: true },
      { id: 101, amount: 1000, price: 1.0, bonus: 0, currency: 'diamonds', tag: 'STARTER', isActive: true },
      { id: 102, amount: 5000, price: 5.0, bonus: 250, currency: 'diamonds', tag: 'HOT', isActive: true },
      { id: 103, amount: 10000, price: 10.0, bonus: 700, currency: 'diamonds', tag: 'ROYAL', isActive: true },
    ]);
  };

  const handleSaveAll = async () => {
    setSaving(true);
    setSaveSuccess(false);
    try {
      const legacyRate = exchangeConfig.coinsPerDiamond > 0 ? (1 / exchangeConfig.coinsPerDiamond) : 1;
      const roundedLegacy = Number.isInteger(legacyRate) ? legacyRate : 1;

      await updateAppConfig({
        diamond_exchange_config: exchangeConfig,
        diamondToCoinRate: roundedLegacy,
        recharge_plans: plans,
        recharge_gateways: gateways,
      });

      setSaveSuccess(true);
      setTimeout(() => setSaveSuccess(false), 3000);
    } catch (e) {
      console.error('Error saving recharge config:', e);
      alert('حدث خطأ أثناء حفظ الإعدادات');
    } finally {
      setSaving(false);
    }
  };

  const addPlan = () => {
    const newId = Date.now();
    setPlans([
      ...plans,
      {
        id: newId,
        amount: 1000,
        price: 1.0,
        bonus: 0,
        currency: plansCurrencyTab,
        tag: '',
        isActive: true,
      }
    ]);
  };

  const updatePlan = (id: number | string, field: keyof RechargePlan, value: any) => {
    setPlans(plans.map(p => p.id === id ? { ...p, [field]: value } : p));
  };

  const removePlan = (id: number | string) => {
    setPlans(plans.filter(p => p.id !== id));
  };

  const filteredPlans = plans.filter(p => p.currency === plansCurrencyTab);

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="flex flex-col items-center gap-3">
          <RefreshCw className="w-8 h-8 text-indigo-500 animate-spin" />
          <span className="text-slate-400 font-medium">جاري تحميل إعدادات الشحن وتحويل الألماس...</span>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-6xl mx-auto space-y-6 pb-20">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-slate-900/60 p-5 rounded-2xl border border-white/5 backdrop-blur-sm">
        <div className="flex items-center gap-4">
          <div className="w-12 h-12 rounded-xl bg-gradient-to-tr from-amber-500 to-indigo-600 flex items-center justify-center text-white shadow-lg shadow-indigo-500/20">
            <Coins className="w-6 h-6" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-white flex items-center gap-2">
              إعدادات الشحن وتحويل الألماس
              <span className="text-xs px-2.5 py-0.5 rounded-full bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">تحكم فوري</span>
            </h1>
            <p className="text-xs text-slate-400 mt-0.5">
              تحكم كامل في نسبة تحويل الألماس إلى كوينز، تعبئة باقات الشحن، وطرق الدفع
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={loadConfig}
            className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-white/5 hover:bg-white/10 text-slate-300 text-xs font-medium border border-white/10 transition-colors"
          >
            <RefreshCw className="w-4 h-4" />
            <span>تحديث</span>
          </button>

          <button
            onClick={handleSaveAll}
            disabled={saving}
            className={`flex items-center gap-2 px-5 py-2 rounded-xl text-xs font-bold text-white shadow-lg transition-all ${
              saveSuccess 
                ? 'bg-emerald-600 shadow-emerald-600/30' 
                : 'bg-indigo-600 hover:bg-indigo-500 shadow-indigo-600/30'
            }`}
          >
            {saving ? (
              <>
                <RefreshCw className="w-4 h-4 animate-spin" />
                <span>جاري الحفظ...</span>
              </>
            ) : saveSuccess ? (
              <>
                <CheckCircle2 className="w-4 h-4" />
                <span>تم الحفظ بنجاح!</span>
              </>
            ) : (
              <>
                <Save className="w-4 h-4" />
                <span>حفظ التعديلات</span>
              </>
            )}
          </button>
        </div>
      </div>

      <div className="flex items-center gap-2 border-b border-white/5 pb-2">
        <button
          onClick={() => setActiveTab('exchange')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-semibold transition-all ${
            activeTab === 'exchange'
              ? 'bg-amber-500/15 text-amber-400 border border-amber-500/30 shadow-lg shadow-amber-500/10'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <ArrowRightLeft className="w-4 h-4" />
          <span>تحويل الألماس إلى كوينز 💎 ⇄ 🪙</span>
        </button>

        <button
          onClick={() => setActiveTab('plans')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-semibold transition-all ${
            activeTab === 'plans'
              ? 'bg-indigo-500/15 text-indigo-400 border border-indigo-500/30 shadow-lg shadow-indigo-500/10'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Sparkles className="w-4 h-4" />
          <span>باقات شاشات الشحن (Coins & Diamonds)</span>
        </button>

        <button
          onClick={() => setActiveTab('gateways')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-semibold transition-all ${
            activeTab === 'gateways'
              ? 'bg-emerald-500/15 text-emerald-400 border border-emerald-500/30 shadow-lg shadow-emerald-500/10'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <CreditCard className="w-4 h-4" />
          <span>بوابات الدفع والتحويل المعتمدة</span>
        </button>

        <button
          onClick={() => setActiveTab('requests')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-semibold transition-all ${
            activeTab === 'requests'
              ? 'bg-amber-500/15 text-amber-400 border border-amber-500/30 shadow-lg shadow-amber-500/10'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Clock className="w-4 h-4" />
          <span>طلبات الشحن والمعاملات</span>
          {requests.filter(r => r.status === 'pending').length > 0 && (
            <span className="px-2 py-0.5 rounded-full bg-red-500 text-white text-[10px] font-bold">
              {requests.filter(r => r.status === 'pending').length}
            </span>
          )}
        </button>
      </div>

      {activeTab === 'exchange' && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2 space-y-6">
            <div className="bg-slate-900/60 rounded-2xl p-6 border border-white/5 space-y-6">
              <div className="flex items-center justify-between border-b border-white/5 pb-4">
                <div>
                  <h3 className="text-base font-bold text-white flex items-center gap-2">
                    <Diamond className="w-5 h-5 text-cyan-400" />
                    معادلة تبديل الألماس إلى كوينز
                  </h3>
                  <p className="text-xs text-slate-400 mt-1">
                    حدد كم كوينز يحصل عليه المستخدم مقابل كل 1 ألماسة يستبدلها
                  </p>
                </div>

                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={exchangeConfig.enabled}
                    onChange={(e) => setExchangeConfig({ ...exchangeConfig, enabled: e.target.checked })}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-emerald-500"></div>
                  <span className="mr-3 text-xs font-medium text-slate-300">
                    {exchangeConfig.enabled ? 'التبديل مفعّل' : 'التبديل معطّل'}
                  </span>
                </label>
              </div>

              <div className="space-y-2">
                <label className="text-xs text-slate-400 font-medium">النسب السريعة الجاهزة (Presets):</label>
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2.5">
                  {[
                    { label: '1 ألماسة = 1 كوينز (1:1)', val: 1.0, color: 'border-emerald-500/50 bg-emerald-500/10 text-emerald-300' },
                    { label: '1 ألماسة = 2 كوينز (1:2)', val: 2.0, color: 'border-indigo-500/50 bg-indigo-500/10 text-indigo-300' },
                    { label: '1 ألماسة = 5 كوينز (1:5)', val: 5.0, color: 'border-amber-500/50 bg-amber-500/10 text-amber-300' },
                    { label: '1 ألماسة = 10 كوينز (1:10)', val: 10.0, color: 'border-purple-500/50 bg-purple-500/10 text-purple-300' },
                    { label: '2 ألماسة = 1 كوين (0.5)', val: 0.5, color: 'border-slate-500/50 bg-slate-500/10 text-slate-300' },
                    { label: '10 ألماسة = 1 كوين (0.1)', val: 0.1, color: 'border-rose-500/50 bg-rose-500/10 text-rose-300' },
                  ].map((p, idx) => (
                    <button
                      key={idx}
                      type="button"
                      onClick={() => setExchangeConfig({ ...exchangeConfig, coinsPerDiamond: p.val })}
                      className={`p-3 rounded-xl border text-xs font-bold text-center transition-all ${
                        exchangeConfig.coinsPerDiamond === p.val 
                          ? `${p.color} ring-2 ring-indigo-500 shadow-md` 
                          : 'border-white/5 bg-white/5 text-slate-300 hover:bg-white/10'
                      }`}
                    >
                      {p.label}
                    </button>
                  ))}
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2">
                <div>
                  <label className="block text-xs font-semibold text-slate-300 mb-1.5">
                    عدد الكوينز لكل 1 ألماسة (Coins Per 1 Diamond):
                  </label>
                  <div className="relative">
                    <input
                      type="number"
                      step="0.01"
                      min="0.01"
                      value={exchangeConfig.coinsPerDiamond}
                      onChange={(e) => setExchangeConfig({ ...exchangeConfig, coinsPerDiamond: parseFloat(e.target.value) || 0 })}
                      className="w-full bg-black/40 border border-white/10 rounded-xl px-4 py-2.5 text-white text-sm focus:border-amber-500 focus:outline-none"
                    />
                    <span className="absolute left-3 top-2.5 text-xs text-amber-400 font-bold">كوينز / ألماسة</span>
                  </div>
                  <p className="text-[11px] text-slate-500 mt-1">
                    لو كتبت 1 تصبح 1 ماسة = 1 كوينز. ولو كتبت 2 تصبح 1 ماسة = 2 كوينز.
                  </p>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-300 mb-1.5">
                    الحد الأدنى للألماس في عملية التبديل:
                  </label>
                  <div className="relative">
                    <input
                      type="number"
                      min="1"
                      value={exchangeConfig.minDiamonds}
                      onChange={(e) => setExchangeConfig({ ...exchangeConfig, minDiamonds: parseInt(e.target.value) || 1 })}
                      className="w-full bg-black/40 border border-white/10 rounded-xl px-4 py-2.5 text-white text-sm focus:border-indigo-500 focus:outline-none"
                    />
                    <span className="absolute left-3 top-2.5 text-xs text-cyan-400 font-bold">ألماسة</span>
                  </div>
                  <p className="text-[11px] text-slate-500 mt-1">
                    أقل كمية ألماس يمكن للمستخدم كتابتها للتبديل.
                  </p>
                </div>
              </div>
            </div>
          </div>

          <div className="space-y-6">
            <div className="bg-gradient-to-b from-indigo-950/40 via-slate-900/60 to-slate-900/80 rounded-2xl p-6 border border-indigo-500/20 relative overflow-hidden">
              <h3 className="text-sm font-bold text-white flex items-center gap-2 mb-4">
                <Sparkles className="w-4 h-4 text-amber-400" />
                حاسبة المحاكاة الحية (Live Preview)
              </h3>

              <div className="space-y-4">
                <div>
                  <label className="text-[11px] text-slate-400 block mb-1">جرّب إدخال عدد ألماس لاختبار الناتج:</label>
                  <input
                    type="number"
                    value={calcDiamonds}
                    onChange={(e) => setCalcDiamonds(parseInt(e.target.value) || 0)}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white text-sm focus:border-indigo-500 focus:outline-none"
                  />
                </div>

                <div className="p-4 rounded-xl bg-black/30 border border-white/5 space-y-3">
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-slate-400">الألماس المدخل:</span>
                    <span className="font-bold text-cyan-400 flex items-center gap-1">
                      {calcDiamonds.toLocaleString()} 💎
                    </span>
                  </div>

                  <div className="flex items-center justify-between text-xs">
                    <span className="text-slate-400">المعدل المطبق:</span>
                    <span className="font-bold text-amber-400">
                      1 💎 = {exchangeConfig.coinsPerDiamond} 🪙
                    </span>
                  </div>

                  <div className="h-px bg-white/5 my-1" />

                  <div className="flex items-center justify-between text-sm">
                    <span className="font-semibold text-white">الكوينز المستلم:</span>
                    <span className="font-extrabold text-emerald-400 text-base flex items-center gap-1">
                      {Math.floor(calcDiamonds * exchangeConfig.coinsPerDiamond).toLocaleString()} 🪙
                    </span>
                  </div>
                </div>

                <div className="text-[11px] text-slate-400 bg-white/5 p-3 rounded-xl border border-white/5 space-y-1">
                  <div className="flex items-center gap-1.5 text-indigo-300 font-medium">
                    <ShieldCheck className="w-3.5 h-3.5" />
                    <span>ملاحظة:</span>
                  </div>
                  <p>
                    هذه النسبة يتم حفظها في app_config وتنعكس فوراً على تطبيق المستخدم.
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'plans' && (
        <div className="space-y-6">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 bg-slate-900/60 p-1.5 rounded-xl border border-white/5">
              <button
                type="button"
                onClick={() => setPlansCurrencyTab('coins')}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-bold transition-all ${
                  plansCurrencyTab === 'coins'
                    ? 'bg-amber-500 text-black shadow-md'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                <Coins className="w-4 h-4" />
                <span>باقات الكوينز ({plans.filter(p => p.currency === 'coins').length})</span>
              </button>

              <button
                type="button"
                onClick={() => setPlansCurrencyTab('diamonds')}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-bold transition-all ${
                  plansCurrencyTab === 'diamonds'
                    ? 'bg-cyan-500 text-black shadow-md'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                <Diamond className="w-4 h-4" />
                <span>باقات الألماس ({plans.filter(p => p.currency === 'diamonds').length})</span>
              </button>
            </div>

            <button
              type="button"
              onClick={addPlan}
              className="flex items-center gap-2 px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold shadow-lg shadow-indigo-600/20 transition-all"
            >
              <Plus className="w-4 h-4" />
              <span>إضافة باقة شحن جديدة</span>
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {filteredPlans.map((plan, idx) => (
              <div 
                key={plan.id}
                className="bg-slate-900/60 rounded-2xl p-5 border border-white/5 space-y-4 hover:border-white/10 transition-all relative overflow-hidden"
              >
                <div className="flex items-center justify-between border-b border-white/5 pb-3">
                  <div className="flex items-center gap-2">
                    <span className="w-6 h-6 rounded-full bg-white/10 text-slate-300 text-xs font-bold flex items-center justify-center">
                      {idx + 1}
                    </span>
                    <span className="text-xs font-bold text-white">
                      باقة #{plan.id}
                    </span>
                  </div>

                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => updatePlan(plan.id, 'isActive', !plan.isActive)}
                      className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${
                        plan.isActive !== false 
                          ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' 
                          : 'bg-rose-500/10 text-rose-400 border-rose-500/30'
                      }`}
                    >
                      {plan.isActive !== false ? 'مفعلة' : 'معطلة'}
                    </button>

                    <button
                      type="button"
                      onClick={() => removePlan(plan.id)}
                      className="p-1 rounded-lg text-slate-500 hover:text-rose-400 hover:bg-rose-500/10 transition-colors"
                      title="حذف الباقة"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="text-[11px] text-slate-400 block mb-1">
                      الكمية ({plan.currency === 'coins' ? 'كوينز' : 'ألماس'}):
                    </label>
                    <input
                      type="number"
                      value={plan.amount}
                      onChange={(e) => updatePlan(plan.id, 'amount', parseInt(e.target.value) || 0)}
                      className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white text-xs font-bold focus:border-indigo-500 focus:outline-none"
                    />
                  </div>

                  <div>
                    <label className="text-[11px] text-slate-400 block mb-1">السعر ($ USD):</label>
                    <input
                      type="number"
                      step="0.01"
                      value={plan.price}
                      onChange={(e) => updatePlan(plan.id, 'price', parseFloat(e.target.value) || 0)}
                      className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-emerald-400 text-xs font-bold focus:border-indigo-500 focus:outline-none"
                    />
                  </div>

                  <div>
                    <label className="text-[11px] text-slate-400 block mb-1">البونص الإضافي (Bonus):</label>
                    <input
                      type="number"
                      value={plan.bonus}
                      onChange={(e) => updatePlan(plan.id, 'bonus', parseInt(e.target.value) || 0)}
                      className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-amber-400 text-xs font-bold focus:border-indigo-500 focus:outline-none"
                    />
                  </div>

                  <div>
                    <label className="text-[11px] text-slate-400 block mb-1">شارة ترويجية (Tag):</label>
                    <input
                      type="text"
                      placeholder="HOT / VIP / BEST"
                      value={plan.tag ?? ''}
                      onChange={(e) => updatePlan(plan.id, 'tag', e.target.value)}
                      className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white text-xs focus:border-indigo-500 focus:outline-none"
                    />
                  </div>
                </div>

                <div className="pt-2">
                  <div className="bg-black/30 rounded-xl p-3 border border-white/5 flex items-center justify-between">
                    <div className="flex items-center gap-2.5">
                      <div className={`w-8 h-8 rounded-lg flex items-center justify-center ${
                        plan.currency === 'coins' ? 'bg-amber-500/20 text-amber-400' : 'bg-cyan-500/20 text-cyan-400'
                      }`}>
                        {plan.currency === 'coins' ? <Coins className="w-4 h-4" /> : <Diamond className="w-4 h-4" />}
                      </div>
                      <div>
                        <div className="text-xs font-bold text-white flex items-center gap-1.5">
                          {plan.amount.toLocaleString()} {plan.currency === 'coins' ? 'كوينز' : 'ألماس'}
                          {plan.tag && (
                            <span className="text-[9px] bg-red-500/20 text-red-400 px-1.5 py-0.2 rounded border border-red-500/30">
                              {plan.tag}
                            </span>
                          )}
                        </div>
                        {plan.bonus > 0 && (
                          <div className="text-[10px] text-amber-400">
                            + {plan.bonus.toLocaleString()} إضافي مجاناً
                          </div>
                        )}
                      </div>
                    </div>
                    <div className="text-xs font-extrabold text-emerald-400">
                      ${plan.price}
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {activeTab === 'gateways' && (
        <div className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Google Play In-App Purchase */}
            <div className="bg-slate-900/60 rounded-2xl p-6 border border-white/5 space-y-4">
              <div className="flex items-center justify-between border-b border-white/5 pb-3">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-xl bg-blue-500/20 text-blue-400 flex items-center justify-center font-black">
                    <CreditCard className="w-5 h-5" />
                  </div>
                  <div>
                    <h3 className="text-sm font-bold text-white">متجر جوجل بلاي (Google Play Billing)</h3>
                    <p className="text-[11px] text-slate-400">الشراء المباشر من داخل التطبيق (In-App Purchase)</p>
                  </div>
                </div>

                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={gateways.googlePlayEnabled}
                    onChange={(e) => setGateways({ ...gateways, googlePlayEnabled: e.target.checked })}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
                </label>
              </div>

              <div className="p-3 rounded-xl bg-blue-500/10 border border-blue-500/20 text-xs text-blue-300 leading-relaxed">
                ⚠️ يتم ربط هذه البوابة بحساب Google Play Console المعتمد للتطبيق. لا يتم إيداع الكوينز إلا بعد تأكيد إيصال الشراء الرقمي الرسمي منعاً لأي شحن مجاني أو غير موثق.
              </div>
            </div>

            {/* Vodafone Cash */}
            <div className="bg-slate-900/60 rounded-2xl p-6 border border-white/5 space-y-4">
              <div className="flex items-center justify-between border-b border-white/5 pb-3">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-xl bg-rose-500/20 text-rose-400 flex items-center justify-center font-black">
                    <Smartphone className="w-5 h-5" />
                  </div>
                  <div>
                    <h3 className="text-sm font-bold text-white">فودافون كاش (Vodafone Cash)</h3>
                    <p className="text-[11px] text-slate-400">محفظة التحويل بالجنيه المصري EGP</p>
                  </div>
                </div>

                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={gateways.vodafoneCashEnabled}
                    onChange={(e) => setGateways({ ...gateways, vodafoneCashEnabled: e.target.checked })}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-rose-600"></div>
                </label>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-slate-300 mb-1">رقم المحفظة:</label>
                  <input
                    type="text"
                    value={gateways.vodafoneCashNumber}
                    onChange={(e) => setGateways({ ...gateways, vodafoneCashNumber: e.target.value })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white text-xs font-mono focus:border-rose-500 focus:outline-none"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-300 mb-1">اسم صاحب المحفظة:</label>
                  <input
                    type="text"
                    value={gateways.vodafoneCashName}
                    onChange={(e) => setGateways({ ...gateways, vodafoneCashName: e.target.value })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white text-xs focus:border-rose-500 focus:outline-none"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-300 mb-1">تعليمات التحويل للمستخدم:</label>
                <textarea
                  rows={2}
                  value={gateways.vodafoneCashInstructions}
                  onChange={(e) => setGateways({ ...gateways, vodafoneCashInstructions: e.target.value })}
                  className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-1.5 text-white text-xs focus:border-rose-500 focus:outline-none"
                />
              </div>
            </div>

            {/* Binance Pay / Crypto */}
            <div className="bg-slate-900/60 rounded-2xl p-6 border border-white/5 space-y-4">
              <div className="flex items-center justify-between border-b border-white/5 pb-3">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-xl bg-amber-500/20 text-amber-400 flex items-center justify-center font-black">
                    <Globe className="w-5 h-5" />
                  </div>
                  <div>
                    <h3 className="text-sm font-bold text-white">بينانس باي & كريبتو (Binance Pay / USDT)</h3>
                    <p className="text-[11px] text-slate-400">شحن العملات الرقمية بالدولار الأمريكي USD</p>
                  </div>
                </div>

                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={gateways.binanceEnabled}
                    onChange={(e) => setGateways({ ...gateways, binanceEnabled: e.target.checked })}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-amber-500"></div>
                </label>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-slate-300 mb-1">معرف Binance Pay ID:</label>
                  <input
                    type="text"
                    value={gateways.binanceId}
                    onChange={(e) => setGateways({ ...gateways, binanceId: e.target.value })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white text-xs font-mono focus:border-amber-500 focus:outline-none"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-300 mb-1">عنوان محفظة USDT (TRC-20):</label>
                  <input
                    type="text"
                    value={gateways.binanceAddress}
                    onChange={(e) => setGateways({ ...gateways, binanceAddress: e.target.value })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white text-xs font-mono focus:border-amber-500 focus:outline-none"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-300 mb-1">تعليمات التحويل للمستخدم:</label>
                <textarea
                  rows={2}
                  value={gateways.binanceInstructions}
                  onChange={(e) => setGateways({ ...gateways, binanceInstructions: e.target.value })}
                  className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-1.5 text-white text-xs focus:border-amber-500 focus:outline-none"
                />
              </div>
            </div>

            {/* Instapay / Bank */}
            <div className="bg-slate-900/60 rounded-2xl p-6 border border-white/5 space-y-4">
              <div className="flex items-center justify-between border-b border-white/5 pb-3">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-xl bg-purple-500/20 text-purple-400 flex items-center justify-center font-black">
                    <Building2 className="w-5 h-5" />
                  </div>
                  <div>
                    <h3 className="text-sm font-bold text-white">انستاباي / تحويل بنكي (Instapay)</h3>
                    <p className="text-[11px] text-slate-400">التحويل اللحظي عبر الشبكة القومية للمدفوعات</p>
                  </div>
                </div>

                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={gateways.instapayEnabled}
                    onChange={(e) => setGateways({ ...gateways, instapayEnabled: e.target.checked })}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-purple-600"></div>
                </label>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-slate-300 mb-1">عنوان الدفع اللحظي (IPA):</label>
                  <input
                    type="text"
                    value={gateways.instapayAddress}
                    onChange={(e) => setGateways({ ...gateways, instapayAddress: e.target.value })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white text-xs font-mono focus:border-purple-500 focus:outline-none"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-300 mb-1">اسم الحساب البنكي:</label>
                  <input
                    type="text"
                    value={gateways.instapayAccountName}
                    onChange={(e) => setGateways({ ...gateways, instapayAccountName: e.target.value })}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-white text-xs focus:border-purple-500 focus:outline-none"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-300 mb-1">تعليمات التحويل عبر انستاباي:</label>
                <textarea
                  rows={2}
                  value={gateways.instapayInstructions}
                  onChange={(e) => setGateways({ ...gateways, instapayInstructions: e.target.value })}
                  className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-1.5 text-white text-xs focus:border-purple-500 focus:outline-none"
                />
              </div>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'requests' && (
        <div className="bg-slate-900/60 rounded-2xl p-6 border border-white/5 space-y-6">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-white/5 pb-4">
            <div>
              <h3 className="text-base font-bold text-white flex items-center gap-2">
                <Clock className="w-5 h-5 text-amber-400" />
                سجل طلبات الشحن والتحويلات
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">
                راجع إثباتات الدفع وأرقام التحويلات واعتمد وصول الكوينز للمستخدم فور التأكد
              </p>
            </div>

            <div className="flex items-center gap-2">
              {(['all', 'pending', 'approved', 'rejected'] as const).map(f => (
                <button
                  key={f}
                  onClick={() => setReqFilter(f)}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                    reqFilter === f
                      ? 'bg-amber-500 text-black font-bold'
                      : 'bg-white/5 text-slate-400 hover:text-white'
                  }`}
                >
                  {f === 'all' ? 'الكل' : f === 'pending' ? 'قيد المراجعة' : f === 'approved' ? 'المعتمدة' : 'المرفوضة'}
                </button>
              ))}
            </div>
          </div>

          {requests.filter(r => reqFilter === 'all' || r.status === reqFilter).length === 0 ? (
            <div className="text-center py-12 text-slate-500 text-xs">
              لا توجد طلبات شحن مطابقة حالياً
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-right text-xs">
                <thead>
                  <tr className="text-slate-400 border-b border-white/10 pb-2">
                    <th className="py-2.5 px-3 font-semibold">المستخدم</th>
                    <th className="py-2.5 px-3 font-semibold">الباقة والمبلغ</th>
                    <th className="py-2.5 px-3 font-semibold">طريقة الدفع</th>
                    <th className="py-2.5 px-3 font-semibold">بيانات العملية / TXID</th>
                    <th className="py-2.5 px-3 font-semibold">التاريخ</th>
                    <th className="py-2.5 px-3 font-semibold">الحالة</th>
                    <th className="py-2.5 px-3 font-semibold text-center">الإجراء</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5">
                  {requests
                    .filter(r => reqFilter === 'all' || r.status === reqFilter)
                    .map(r => (
                      <tr key={r.id} className="hover:bg-white/5 transition-colors">
                        <td className="py-3 px-3">
                          <div className="flex items-center gap-2.5">
                            <img
                              src={r.userAvatar || `https://ui-avatars.com/api/?name=${encodeURIComponent(r.userName || 'User')}`}
                              className="w-8 h-8 rounded-full object-cover border border-white/10"
                            />
                            <div>
                              <div className="font-bold text-white">{r.userName || 'مستخدم'}</div>
                              <div className="text-[10px] text-slate-400 font-mono">ID: {r.customId || r.userId.slice(0, 8)}</div>
                            </div>
                          </div>
                        </td>

                        <td className="py-3 px-3">
                          <div className="font-bold text-amber-400">
                            {r.amount.toLocaleString()} {r.currency === 'coins' ? '🪙 كوينز' : '💎 ماسة'}
                          </div>
                          <div className="text-[11px] text-emerald-400 font-bold">${r.price} USD</div>
                        </td>

                        <td className="py-3 px-3">
                          <span className="px-2 py-0.5 rounded-md bg-white/5 text-slate-300 font-medium">
                            {r.gateway === 'vodafone_cash' ? 'فودافون كاش' : r.gateway === 'binance_pay' ? 'Binance Pay' : r.gateway === 'instapay' ? 'انستاباي' : r.gateway}
                          </span>
                        </td>

                        <td className="py-3 px-3 font-mono text-[11px] text-slate-300">
                          {r.senderPhone && <div>الهاتف: {r.senderPhone}</div>}
                          {r.txid && <div className="text-indigo-400">TXID: {r.txid}</div>}
                          {r.proofUrl && (
                            <a href={r.proofUrl} target="_blank" rel="noreferrer" className="text-cyan-400 flex items-center gap-1 mt-0.5 hover:underline">
                              <span>عرض الإشعار</span>
                              <ExternalLink className="w-3 h-3" />
                            </a>
                          )}
                        </td>

                        <td className="py-3 px-3 text-slate-400 text-[11px]">
                          {new Date(r.createdAt).toLocaleDateString('ar-EG', { hour: '2-digit', minute: '2-digit' })}
                        </td>

                        <td className="py-3 px-3">
                          <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${
                            r.status === 'approved'
                              ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
                              : r.status === 'rejected'
                              ? 'bg-rose-500/20 text-rose-400 border border-rose-500/30'
                              : 'bg-amber-500/20 text-amber-400 border border-amber-500/30'
                          }`}>
                            {r.status === 'approved' ? 'معتمد' : r.status === 'rejected' ? 'مرفوض' : 'قيد المراجعة'}
                          </span>
                          {r.rejectionReason && (
                            <div className="text-[10px] text-rose-400 mt-1 max-w-[120px] truncate" title={r.rejectionReason}>
                              {r.rejectionReason}
                            </div>
                          )}
                        </td>

                        <td className="py-3 px-3 text-center">
                          {r.status === 'pending' ? (
                            <div className="flex items-center justify-center gap-1.5">
                              <button
                                onClick={() => handleApproveRequest(r)}
                                disabled={reqProcessingId === r.id}
                                className="px-2.5 py-1 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-[11px] flex items-center gap-1 transition-all"
                              >
                                <Check className="w-3.5 h-3.5" />
                                <span>اعتماد</span>
                              </button>
                              <button
                                onClick={() => handleRejectRequest(r)}
                                disabled={reqProcessingId === r.id}
                                className="px-2.5 py-1 rounded-lg bg-rose-600 hover:bg-rose-500 text-white font-bold text-[11px] flex items-center gap-1 transition-all"
                              >
                                <X className="w-3.5 h-3.5" />
                                <span>رفض</span>
                              </button>
                            </div>
                          ) : (
                            <span className="text-[10px] text-slate-500">
                              {r.reviewedBy ? `بواسطة: ${r.reviewedBy}` : 'مكتمل'}
                            </span>
                          )}
                        </td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
