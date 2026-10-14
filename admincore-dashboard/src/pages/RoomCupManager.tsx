import { useEffect, useState } from 'react';
import { getAppConfig, updateAppConfig, sendSystemNotification, getRooms } from '../lib/db';
import { supabase } from '../lib/supabase';
import { uploadAppAsset } from '../lib/storage';
import { 
  Trophy, Save, Sparkles, Upload, RefreshCw, CheckCircle2, 
  Crown, Coins, Calendar, Clock, Layers, Award,
  PlayCircle, UserCheck, Percent, HelpCircle
} from 'lucide-react';

export interface MilestoneTier {
  id: string;
  minCoins: number;
  percentage: number;
  label: string;
}

export interface OwnerCupPeriodConfig {
  enabled: boolean;
  basePercentage: number; // e.g. 10 = 10%
  useMilestones: boolean;
  minRoomCoinsToQualify: number;
  svgaFrame: string;
  badgeIcon: string;
  daysValid: number;
  milestones: MilestoneTier[];
}

export interface RoomOwnerCupConfig {
  daily: OwnerCupPeriodConfig;
  weekly: OwnerCupPeriodConfig;
}

const DEFAULT_CONFIG: RoomOwnerCupConfig = {
  daily: {
    enabled: true,
    basePercentage: 10,
    useMilestones: false,
    minRoomCoinsToQualify: 10000,
    svgaFrame: 'assets/svga/kojuyee_room_rank_border1.svga',
    badgeIcon: 'assets/images/rank_top_avatar_1.webp',
    daysValid: 1,
    milestones: [
      { id: 'd1', minCoins: 50000, percentage: 5, label: 'كأس اليوم البرونزي' },
      { id: 'd2', minCoins: 200000, percentage: 10, label: 'كأس اليوم الفضي' },
      { id: 'd3', minCoins: 1000000, percentage: 15, label: 'كأس اليوم الذهبي' },
    ],
  },
  weekly: {
    enabled: true,
    basePercentage: 15,
    useMilestones: false,
    minRoomCoinsToQualify: 50000,
    svgaFrame: 'assets/svga/kojuyee_room_rank_border1.svga',
    badgeIcon: 'assets/images/rank_top_avatar_1.webp',
    daysValid: 7,
    milestones: [
      { id: 'w1', minCoins: 200000, percentage: 8, label: 'كأس الأسبوع البرونزي' },
      { id: 'w2', minCoins: 1000000, percentage: 12, label: 'كأس الأسبوع الفضي' },
      { id: 'w3', minCoins: 5000000, percentage: 18, label: 'كأس الأسبوع الذهبي الملكي' },
    ],
  },
};

export default function RoomCupManager() {
  const [activeTab, setActiveTab] = useState<'daily' | 'weekly' | 'settlement'>('daily');
  const [config, setConfig] = useState<RoomOwnerCupConfig>(DEFAULT_CONFIG);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [uploadingField, setUploadingField] = useState<string | null>(null);

  // Settlement states
  const [rooms, setRooms] = useState<Array<{ roomId: string; name: string; hostUid?: string; hostName?: string }>>([]);
  const [selectedRoomId, setSelectedRoomId] = useState<string>('all');
  const [settlementPeriod, setSettlementPeriod] = useState<'daily' | 'weekly'>('daily');
  const [runningSettlement, setRunningSettlement] = useState(false);
  const [settlementLogs, setSettlementLogs] = useState<string[]>([]);
  const [settledOwners, setSettledOwners] = useState<any[]>([]);

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    setLoading(true);
    try {
      const cfg = await getAppConfig<RoomOwnerCupConfig>('room_cup_rewards');
      if (cfg && cfg.daily && cfg.weekly) {
        setConfig(cfg);
      }
      const roomList = await getRooms();
      setRooms(roomList.map(r => ({
        roomId: r.roomId,
        name: r.name,
        hostUid: r.hostUid,
        hostName: r.hostName,
      })));
    } catch (e) {
      console.error('Failed to load room cup config:', e);
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      await updateAppConfig('room_cup_rewards', config);
      alert('تم حفظ إعدادات ونسب أرباح كأس الغرفة لمالك الغرفة بنجاح! 🏆');
    } catch (e) {
      alert('فشل حفظ الإعدادات: ' + (e as Error).message);
    } finally {
      setSaving(false);
    }
  };

  const handleFileUpload = (period: 'daily' | 'weekly', field: 'svgaFrame' | 'badgeIcon') => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = field === 'svgaFrame' ? '.svga,.vap,.mp4,.webp,.png' : '.png,.webp,.jpg,.svg';
    input.onchange = async () => {
      const file = input.files?.[0];
      if (!file) return;
      const key = `${period}_${field}`;
      setUploadingField(key);
      try {
        const url = await uploadAppAsset(file, 'room_cup');
        const updated = { ...config };
        updated[period][field] = url;
        setConfig(updated);
      } catch (err) {
        alert('فشل رفع الملف: ' + (err as Error).message);
      } finally {
        setUploadingField(null);
      }
    };
    input.click();
  };

  // Run instant manual settlement for ROOM OWNERS
  const handleExecuteSettlement = async () => {
    if (!confirm(`هل أنت متأكد من صرف أرباح ${settlementPeriod === 'daily' ? 'كأس اليوم' : 'كأس الأسبوع'} لـ ملاك الغرف المؤهلة الآن؟`)) {
      return;
    }

    setRunningSettlement(true);
    setSettlementLogs([]);
    setSettledOwners([]);
    const logs: string[] = [];
    const ownersList: any[] = [];

    const log = (msg: string) => {
      logs.push(`[${new Date().toLocaleTimeString('ar-EG')}] ${msg}`);
      setSettlementLogs([...logs]);
    };

    try {
      log(`بدء تسوية وصرف أرباح ${settlementPeriod === 'daily' ? 'كأس الغرفة اليومي' : 'كأس الغرفة الأسبوعي'} لملاك الغرف...`);
      const targetConfig = settlementPeriod === 'daily' ? config.daily : config.weekly;

      if (!targetConfig.enabled) {
        log(`⚠️ نظام الكأس لهذه الفترة معطل حالياً من الإعدادات.`);
        setRunningSettlement(false);
        return;
      }

      // Calculate cutoff
      const now = new Date();
      const cutoff = new Date(now.getTime() - (settlementPeriod === 'daily' ? 24 * 3600 * 1000 : 7 * 24 * 3600 * 1000));
      
      const targetRooms = selectedRoomId === 'all' 
        ? rooms 
        : rooms.filter(r => r.roomId === selectedRoomId);

      log(`عدد الغرف المستهدفة بالفحص والتسوية: ${targetRooms.length}`);

      for (const room of targetRooms) {
        log(`فحص الغرفة: ${room.name} (ID: ${room.roomId})...`);

        // Check room owner (hostUid)
        const ownerUid = room.hostUid;
        if (!ownerUid) {
          log(`⚠️ الغرفة لا تملك معرف مالك (hostUid غير محدد)، تخطي.`);
          continue;
        }

        // Query sent_gifts in the room within the timeframe
        const { data: gifts, error: giftErr } = await supabase
          .from('sent_gifts')
          .select('count, value')
          .eq('room_id', room.roomId)
          .gte('created_at', cutoff.toISOString());

        if (giftErr || !gifts || gifts.length === 0) {
          log(`لا توجد هدايا مسجلة للغرفة خلال هذه الفترة.`);
          continue;
        }

        // Sum gifts total
        let roomTotalCoins = 0;
        for (const g of gifts) {
          const val = (Number(g.value) || 0) * (Number(g.count) || 1);
          roomTotalCoins += val;
        }

        if (roomTotalCoins < targetConfig.minRoomCoinsToQualify) {
          log(`إجمالي دعم الغرفة (${roomTotalCoins.toLocaleString()} كوينز) أقل من الحد الأدنى المؤهل للصرف (${targetConfig.minRoomCoinsToQualify.toLocaleString()} كوينز).`);
          continue;
        }

        // Determine percentage to pay owner
        let appliedPercentage = targetConfig.basePercentage;
        let appliedLabel = `${appliedPercentage}% من دخل الغرفة`;

        if (targetConfig.useMilestones && targetConfig.milestones.length > 0) {
          // Sort descending and find highest matched milestone
          const sortedMilestones = [...targetConfig.milestones].sort((a, b) => b.minCoins - a.minCoins);
          const matched = sortedMilestones.find(m => roomTotalCoins >= m.minCoins);
          if (matched) {
            appliedPercentage = matched.percentage;
            appliedLabel = `${matched.label} (${matched.percentage}%)`;
          }
        }

        // Calculate owner profit in coins
        const ownerProfitCoins = Math.round((roomTotalCoins * appliedPercentage) / 100);

        if (ownerProfitCoins <= 0) {
          log(`نسبة الأرباح المحسوبة صفر، تخطي.`);
          continue;
        }

        // 1. Credit coins directly to the Room Owner's balance
        const { data: uData } = await supabase.from('users').select('name, coins').or(`uid.eq.${ownerUid},id.eq.${ownerUid}`).maybeSingle();
        const curCoins = Number(uData?.coins) || 0;
        const ownerName = uData?.name || room.hostName || 'مالك الغرفة';

        await supabase.from('users').update({ coins: curCoins + ownerProfitCoins }).or(`uid.eq.${ownerUid},id.eq.${ownerUid}`);

        // 2. Deliver trophy frame / badge to Room Owner's backpack
        if (targetConfig.svgaFrame || targetConfig.badgeIcon) {
          const expiresAt = new Date(Date.now() + targetConfig.daysValid * 24 * 3600 * 1000).toISOString();
          await supabase.from('user_backpack').insert({
            user_id: ownerUid,
            item_id: `owner_cup_${settlementPeriod}_${Date.now()}`,
            item_name: `كأس الغرفة ${settlementPeriod === 'daily' ? 'اليومي' : 'الأسبوعي'} - ${room.name}`,
            item_type: targetConfig.svgaFrame ? 'frame' : 'badge',
            item_icon: targetConfig.badgeIcon || '',
            item_svga: targetConfig.svgaFrame || '',
            duration_days: targetConfig.daysValid,
            expires_at: expiresAt,
            created_at: new Date().toISOString(),
            is_equipped: true,
            source: `owner_room_cup_${settlementPeriod}`,
          });
        }

        // 3. Send official system notification to Room Owner
        await sendSystemNotification({
          userId: ownerUid,
          title: `🏆 مبروك! أرباح ${settlementPeriod === 'daily' ? 'كأس الغرفة اليومي' : 'كأس الغرفة الأسبوعي'} لغرفتك`,
          body: `تهانينا لمالك غرفة "${room.name}"! تم تجميع إجمالي دعم الغرفة (${roomTotalCoins.toLocaleString()} كوينز)، وصرف أرباح الكأس بنسبة ${appliedPercentage}% بإجمالي: +${ownerProfitCoins.toLocaleString()} كوينز في محفظتك بنجاح 🎁!`,
          type: 'room_cup_award',
        });

        log(`✅ تم صرف أرباح الكأس لمالك الغرفة (${ownerName}) - إجمالي الدخل: ${roomTotalCoins.toLocaleString()} كوينز ➔ الأرباح المودعة: +${ownerProfitCoins.toLocaleString()} كوينز (${appliedPercentage}%).`);

        ownersList.push({
          roomName: room.name,
          roomId: room.roomId,
          ownerName,
          ownerUid,
          roomTotalCoins,
          appliedPercentage,
          ownerProfitCoins,
          label: appliedLabel,
        });
      }

      log(`🎉 اكتملت تسوية وصرف أرباح كأس الغرفة لجميع الملاك بنجاح!`);
      setSettledOwners(ownersList);
    } catch (err) {
      log(`❌ خطأ أثناء التسوية: ${(err as Error).message}`);
    } finally {
      setRunningSettlement(false);
    }
  };

  if (loading) {
    return (
      <div className="min-h-[400px] flex items-center justify-center">
        <RefreshCw className="w-6 h-6 text-indigo-400 animate-spin" />
      </div>
    );
  }

  const currentCfg = config[activeTab === 'settlement' ? 'daily' : activeTab];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 bg-[#121215] border border-white/5 p-6 rounded-2xl">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-amber-500 to-amber-700 flex items-center justify-center shadow-lg shadow-amber-500/20 text-white">
            <Trophy className="w-6 h-6" />
          </div>
          <div>
            <h1 className="text-white font-bold text-lg flex items-center gap-2">
              نظام أرباح وكأس الغرفة لمالك الغرفة (Room Owner Cup & Profits)
              <span className="px-2 py-0.5 text-[10px] rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                أرباح المالك
              </span>
            </h1>
            <p className="text-slate-400 text-xs mt-1">
              تحديد النسبة المئوية التي يحصدها صاحب الغرفة من إجمالي الكوينز المطلقة داخل غرفته يومياً أو أسبوعياً
            </p>
          </div>
        </div>

        <button
          onClick={handleSave}
          disabled={saving}
          className="flex items-center gap-2 px-6 py-2.5 rounded-xl bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-600 hover:to-amber-700 text-white font-semibold text-xs shadow-lg shadow-amber-500/25 transition-all disabled:opacity-50"
        >
          {saving ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
          <span>حفظ التعديلات</span>
        </button>
      </div>

      {/* Concept Notice Box */}
      <div className="bg-gradient-to-r from-amber-500/10 via-amber-600/5 to-transparent border border-amber-500/20 rounded-2xl p-4 flex items-start gap-3">
        <HelpCircle className="w-5 h-5 text-amber-400 shrink-0 mt-0.5" />
        <div className="text-xs text-slate-300 space-y-1">
          <p className="font-bold text-white">📌 كيف يعمل نظام كأس الغرفة؟</p>
          <p>
            يتم تجميع كافة الكوينز والهدايا التي تم إرسالها داخل الغرفة الصوتية (مثلاً مليون كوينز)، وعند حلول موعد التسوية (في منتصف الليل لليومي، أو نهاية الأسبوع للأسبوعي)، يقوم النظام تلقائياً باحتساب <strong>نسبة الربح المحددة هنا (مثل 5% أو 10% أو 15%)</strong> وإيداعها مباشرة في رصيد <strong>مالك الغرفة (Room Owner)</strong> مع إرسال إشعار فوري له بأرباح غرفته وتقديم وسام وإطار الكأس الفاخر له!
          </p>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-2 border-b border-white/10 pb-1">
        <button
          onClick={() => setActiveTab('daily')}
          className={`flex items-center gap-2 px-5 py-2.5 rounded-xl text-xs font-bold transition-all ${
            activeTab === 'daily'
              ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40 shadow-lg'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Calendar className="w-4 h-4" />
          <span>كأس الغرفة اليومي (Daily Cup - منتصف الليل)</span>
        </button>

        <button
          onClick={() => setActiveTab('weekly')}
          className={`flex items-center gap-2 px-5 py-2.5 rounded-xl text-xs font-bold transition-all ${
            activeTab === 'weekly'
              ? 'bg-purple-500/20 text-purple-300 border border-purple-500/40 shadow-lg'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <Crown className="w-4 h-4 text-amber-400" />
          <span>كأس الغرفة الأسبوعي (Weekly Cup - كل إثنين)</span>
        </button>

        <button
          onClick={() => setActiveTab('settlement')}
          className={`flex items-center gap-2 px-5 py-2.5 rounded-xl text-xs font-bold transition-all ${
            activeTab === 'settlement'
              ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/40 shadow-lg'
              : 'text-slate-400 hover:text-white hover:bg-white/5'
          }`}
        >
          <PlayCircle className="w-4 h-4" />
          <span>صرف أرباح الملاك فورياً والتجربة ⚡</span>
        </button>
      </div>

      {/* Daily or Weekly Tab Content */}
      {activeTab !== 'settlement' && (
        <div className="space-y-6">
          {/* Main Profit Percentage Card */}
          <div className="bg-[#121215] border border-white/5 rounded-2xl p-6 space-y-6">
            <h2 className="text-white font-bold text-sm flex items-center justify-between">
              <span className="flex items-center gap-2">
                <Percent className="w-4 h-4 text-amber-400" />
                نسبة ربح صاحب الغرفة من {activeTab === 'daily' ? 'كأس اليوم' : 'كأس الأسبوع'}
              </span>
              <div className="flex items-center gap-2">
                <span className="text-xs text-slate-400">تفعيل الصرف الدوري:</span>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={config[activeTab].enabled}
                    onChange={e => {
                      const updated = { ...config };
                      updated[activeTab].enabled = e.target.checked;
                      setConfig(updated);
                    }}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-amber-500"></div>
                </label>
              </div>
            </h2>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* Primary Percentage */}
              <div className="bg-[#18181C] border border-white/5 rounded-2xl p-5 space-y-2">
                <label className="block text-xs font-bold text-white flex items-center gap-2">
                  <Coins className="w-4 h-4 text-amber-400" />
                  نسبة أرباح مالك الغرفة (%) من إجمالي كوينز الغرفة
                </label>
                <p className="text-[11px] text-slate-400">
                  مثلاً إذا تم تحديد 10% وحققت الغرفة مليون كوينز، ينزل لصاحب الغرفة 100,000 كوينز أرباح كأس.
                </p>
                <div className="relative pt-2">
                  <input
                    type="number"
                    step="0.5"
                    min="0"
                    max="100"
                    value={config[activeTab].basePercentage}
                    onChange={e => {
                      const updated = { ...config };
                      updated[activeTab].basePercentage = Number(e.target.value);
                      setConfig(updated);
                    }}
                    className="w-full bg-[#121215] border border-amber-500/30 rounded-xl px-4 py-3 text-amber-300 text-lg font-bold focus:border-amber-500 font-mono"
                  />
                  <span className="absolute left-4 top-5 text-amber-400 font-bold text-base">%</span>
                </div>
              </div>

              {/* Minimum Room Target Coins */}
              <div className="bg-[#18181C] border border-white/5 rounded-2xl p-5 space-y-2">
                <label className="block text-xs font-bold text-white flex items-center gap-2">
                  <Layers className="w-4 h-4 text-cyan-400" />
                  الحد الأدنى لدخل الغرفة لتأهيل المالك لصرف الأرباح
                </label>
                <p className="text-[11px] text-slate-400">
                  لن تصرف أرباح الكأس لصاحب الغرفة إلا إذا وصلت كوينز الغرفة لهذا الرقم على الأقل.
                </p>
                <div className="relative pt-2">
                  <input
                    type="number"
                    value={config[activeTab].minRoomCoinsToQualify}
                    onChange={e => {
                      const updated = { ...config };
                      updated[activeTab].minRoomCoinsToQualify = Number(e.target.value);
                      setConfig(updated);
                    }}
                    className="w-full bg-[#121215] border border-white/10 rounded-xl px-4 py-3 text-white text-base font-bold focus:border-indigo-500 font-mono"
                  />
                  <span className="absolute left-4 top-5 text-slate-400 text-xs">كوينز</span>
                </div>
              </div>
            </div>

            {/* Owner Reward Items (Frame & Badge) */}
            <div className="border-t border-white/5 pt-5 space-y-4">
              <h3 className="text-white font-bold text-xs flex items-center gap-2">
                <Award className="w-4 h-4 text-purple-400" />
                المكافآت التقديرية الممنوحة لصاحب الغرفة مع الأرباح (إطار SVGA ووسام الكأس)
              </h3>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                {/* SVGA Frame */}
                <div>
                  <label className="block text-xs text-slate-400 mb-1.5 flex items-center gap-1.5">
                    <Sparkles className="w-3.5 h-3.5 text-purple-400" />
                    إطار الـ SVGA الملكي لصاحب الغرفة
                  </label>
                  <div className="flex gap-2">
                    <input
                      type="text"
                      placeholder="رابط أو مسار SVGA"
                      value={config[activeTab].svgaFrame}
                      onChange={e => {
                        const updated = { ...config };
                        updated[activeTab].svgaFrame = e.target.value;
                        setConfig(updated);
                      }}
                      className="flex-1 bg-[#18181C] border border-white/10 rounded-xl px-3 py-2 text-white text-xs focus:border-indigo-500 font-mono"
                    />
                    <button
                      onClick={() => handleFileUpload(activeTab, 'svgaFrame')}
                      disabled={uploadingField === `${activeTab}_svgaFrame`}
                      className="px-3 py-2 bg-purple-600/20 hover:bg-purple-600/30 text-purple-300 rounded-xl text-xs border border-purple-500/30 flex items-center gap-1 transition-all"
                      title="رفع ملف SVGA من الجهاز"
                    >
                      <Upload className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>

                {/* Badge Icon */}
                <div>
                  <label className="block text-xs text-slate-400 mb-1.5 flex items-center gap-1.5">
                    <Award className="w-3.5 h-3.5 text-amber-400" />
                    صورة وسام كأس الغرفة للبروفايل
                  </label>
                  <div className="flex gap-2">
                    <input
                      type="text"
                      placeholder="رابط أو مسار الوسام"
                      value={config[activeTab].badgeIcon}
                      onChange={e => {
                        const updated = { ...config };
                        updated[activeTab].badgeIcon = e.target.value;
                        setConfig(updated);
                      }}
                      className="flex-1 bg-[#18181C] border border-white/10 rounded-xl px-3 py-2 text-white text-xs focus:border-indigo-500 font-mono"
                    />
                    <button
                      onClick={() => handleFileUpload(activeTab, 'badgeIcon')}
                      disabled={uploadingField === `${activeTab}_badgeIcon`}
                      className="px-3 py-2 bg-amber-600/20 hover:bg-amber-600/30 text-amber-300 rounded-xl text-xs border border-amber-500/30 flex items-center gap-1 transition-all"
                      title="رفع صورة الوسام"
                    >
                      <Upload className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>

                {/* Days Valid */}
                <div>
                  <label className="block text-xs text-slate-400 mb-1.5 flex items-center gap-1.5">
                    <Clock className="w-3.5 h-3.5 text-cyan-400" />
                    مدة صلاحية الإطار والوسام في الحقيبة
                  </label>
                  <input
                    type="number"
                    value={config[activeTab].daysValid}
                    onChange={e => {
                      const updated = { ...config };
                      updated[activeTab].daysValid = Number(e.target.value);
                      setConfig(updated);
                    }}
                    className="w-full bg-[#18181C] border border-white/10 rounded-xl px-3 py-2 text-white text-xs focus:border-indigo-500 font-mono"
                  />
                </div>
              </div>
            </div>

            {/* Progressive Milestones Toggle */}
            <div className="border-t border-white/5 pt-5 space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <span className="text-white text-xs font-bold block">شرائح الدخل التصاعدية (اختياري)</span>
                  <span className="text-[11px] text-slate-400">
                    زيادة نسبة ربح المالك كلما ارتفع إجمالي دخل الغرفة أكثر
                  </span>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={config[activeTab].useMilestones}
                    onChange={e => {
                      const updated = { ...config };
                      updated[activeTab].useMilestones = e.target.checked;
                      setConfig(updated);
                    }}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-500"></div>
                </label>
              </div>

              {config[activeTab].useMilestones && (
                <div className="space-y-3 pt-2">
                  {config[activeTab].milestones.map((m, idx) => (
                    <div key={m.id} className="grid grid-cols-1 md:grid-cols-3 gap-3 p-3 bg-[#18181C] rounded-xl border border-white/5 items-center">
                      <div>
                        <label className="text-[10px] text-slate-400 block mb-1">اسم الشريحة</label>
                        <input
                          type="text"
                          value={m.label}
                          onChange={e => {
                            const updated = { ...config };
                            updated[activeTab].milestones[idx].label = e.target.value;
                            setConfig(updated);
                          }}
                          className="w-full bg-[#121215] border border-white/10 rounded-lg px-2.5 py-1.5 text-white text-xs"
                        />
                      </div>
                      <div>
                        <label className="text-[10px] text-slate-400 block mb-1">الحد الأدنى لدخل الغرفة (كوينز)</label>
                        <input
                          type="number"
                          value={m.minCoins}
                          onChange={e => {
                            const updated = { ...config };
                            updated[activeTab].milestones[idx].minCoins = Number(e.target.value);
                            setConfig(updated);
                          }}
                          className="w-full bg-[#121215] border border-white/10 rounded-lg px-2.5 py-1.5 text-white text-xs font-mono"
                        />
                      </div>
                      <div>
                        <label className="text-[10px] text-slate-400 block mb-1">نسبة الربح لمالك الغرفة (%)</label>
                        <div className="relative">
                          <input
                            type="number"
                            step="0.5"
                            value={m.percentage}
                            onChange={e => {
                              const updated = { ...config };
                              updated[activeTab].milestones[idx].percentage = Number(e.target.value);
                              setConfig(updated);
                            }}
                            className="w-full bg-[#121215] border border-white/10 rounded-lg px-2.5 py-1.5 text-amber-300 text-xs font-bold font-mono"
                          />
                          <span className="absolute left-2.5 top-1.5 text-slate-400 text-xs">%</span>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Instant Settlement Tab */}
      {activeTab === 'settlement' && (
        <div className="space-y-6">
          <div className="bg-[#121215] border border-white/5 rounded-2xl p-6 space-y-5">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                <PlayCircle className="w-5 h-5" />
              </div>
              <div>
                <h3 className="text-white font-bold text-sm">التسوية وصرف أرباح كأس الغرفة لملاك الغرف يدوياً</h3>
                <p className="text-slate-400 text-xs mt-0.5">
                  حساب إجمالي الكوينز المطلقة في الغرف وإيداع حصة مالك الغرفة في حسابه فوراً مع إرسال إشعار النظام
                </p>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 pt-2">
              <div>
                <label className="block text-xs text-slate-400 mb-1.5">فترة الكأس المراد تسويته</label>
                <select
                  value={settlementPeriod}
                  onChange={e => setSettlementPeriod(e.target.value as 'daily' | 'weekly')}
                  className="w-full bg-[#18181C] border border-white/10 rounded-xl px-3 py-2.5 text-white text-xs"
                >
                  <option value="daily">كأس اليوم (آخر 24 ساعة)</option>
                  <option value="weekly">كأس الأسبوع (آخر 7 أيام)</option>
                </select>
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1.5">الغرفة المستهدفة</label>
                <select
                  value={selectedRoomId}
                  onChange={e => setSelectedRoomId(e.target.value)}
                  className="w-full bg-[#18181C] border border-white/10 rounded-xl px-3 py-2.5 text-white text-xs"
                >
                  <option value="all">جميع الغرف الصوتية المؤهلة ({rooms.length})</option>
                  {rooms.map(r => (
                    <option key={r.roomId} value={r.roomId}>
                      {r.name} (المالك: {r.hostName || r.hostUid || 'غير محدد'})
                    </option>
                  ))}
                </select>
              </div>

              <div className="flex items-end">
                <button
                  onClick={handleExecuteSettlement}
                  disabled={runningSettlement}
                  className="w-full py-2.5 px-4 rounded-xl bg-gradient-to-r from-emerald-500 to-teal-600 hover:from-emerald-600 hover:to-teal-700 text-white font-bold text-xs flex items-center justify-center gap-2 shadow-lg shadow-emerald-500/20 disabled:opacity-50 transition-all"
                >
                  {runningSettlement ? <RefreshCw className="w-4 h-4 animate-spin" /> : <PlayCircle className="w-4 h-4" />}
                  <span>صرف أرباح الكأس للملاك الآن 💰</span>
                </button>
              </div>
            </div>

            {/* Execution logs */}
            {settlementLogs.length > 0 && (
              <div className="mt-4 p-4 bg-black/50 border border-white/5 rounded-xl font-mono text-[11px] text-slate-300 max-h-60 overflow-y-auto space-y-1">
                {settlementLogs.map((lg, i) => (
                  <div key={i}>{lg}</div>
                ))}
              </div>
            )}
          </div>

          {/* Settled Owners Table */}
          {settledOwners.length > 0 && (
            <div className="bg-[#121215] border border-white/5 rounded-2xl p-6 space-y-4">
              <h3 className="text-white font-bold text-sm flex items-center gap-2">
                <CheckCircle2 className="w-4 h-4 text-emerald-400" />
                سجل الملاك الذين تم إيداع أرباح كأس الغرفة في حساباتهم ({settledOwners.length})
              </h3>
              <div className="overflow-x-auto">
                <table className="w-full text-right text-xs text-slate-300">
                  <thead className="bg-white/5 text-slate-400">
                    <tr>
                      <th className="p-3">الغرفة</th>
                      <th className="p-3">مالك الغرفة (Owner)</th>
                      <th className="p-3">إجمالي دخل الغرفة</th>
                      <th className="p-3">النسبة المطبقة</th>
                      <th className="p-3">الأرباح المودعة في حسابه</th>
                      <th className="p-3">ملاحظات</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-white/5">
                    {settledOwners.map((w, i) => (
                      <tr key={i} className="hover:bg-white/5">
                        <td className="p-3 font-semibold text-white">{w.roomName}</td>
                        <td className="p-3 flex items-center gap-2">
                          <UserCheck className="w-3.5 h-3.5 text-emerald-400" />
                          <span>{w.ownerName}</span>
                          <span className="text-[10px] text-slate-500 font-mono">({w.ownerUid.substring(0, 8)})</span>
                        </td>
                        <td className="p-3 font-mono text-amber-300 font-bold">{w.roomTotalCoins.toLocaleString()} كوينز</td>
                        <td className="p-3 font-mono text-cyan-300 font-bold">{w.appliedPercentage}%</td>
                        <td className="p-3 font-mono text-emerald-300 font-bold">+{w.ownerProfitCoins.toLocaleString()} كوينز</td>
                        <td className="p-3 text-slate-400">{w.label}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
