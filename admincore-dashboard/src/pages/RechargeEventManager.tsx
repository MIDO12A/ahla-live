import { useEffect, useState } from 'react';
import { getAppConfig, updateAppConfig } from '../lib/db';
import { uploadAppAsset } from '../lib/storage';
import { firestoreDb } from '../lib/firebase';
import { doc, setDoc, getDocs, collection, query, where, orderBy, limit, increment } from 'firebase/firestore';
import { 
  Save, Upload, Eye, Plus, Trash2, Edit2, Palette, CheckCircle2, 
  Sparkles, Image as ImageIcon, Smartphone, Layers, Crown, Coins,
  Trophy, Users, Search, RefreshCw, Send, Gift
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

export interface LeaderboardEntry {
  userId: string;
  name: string;
  photoUrl: string;
  customId: string;
  totalRechargedCoins: number;
  claimedTiers: string[];
  claimedCounts?: Record<string, number>;
  updatedAt?: string;
}

export default function RechargeEventManager() {
  const [tiers, setTiers] = useState<RechargeTier[]>(DEFAULT_TIERS);
  const [activeTab, setActiveTab] = useState<'tiers' | 'design' | 'preview' | 'ranking'>('tiers');
  const [previewMode, setPreviewMode] = useState<'screen' | 'dialog'>('screen');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState('');
  const [previewTier, setPreviewTier] = useState<RechargeTier | null>(null);

  // Settings matching D:40 layout & customizations
  const [title, setTitle] = useState('اشحن واحصل على مكافآت ملكية فورية');
  const [titleColor, setTitleColor] = useState('#FFFFFF');
  const [headerTextImage, setHeaderTextImage] = useState('');
  const [allowRepeatClaims, setAllowRepeatClaims] = useState(true);
  
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

  // Ranking & Leaderboard State
  const [leaderboard, setLeaderboard] = useState<LeaderboardEntry[]>([]);
  const [loadingRank, setLoadingRank] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [quickRechargeUid, setQuickRechargeUid] = useState('');
  const [quickRechargeAmount, setQuickRechargeAmount] = useState('100000');
  const [showQuickRechargeModal, setShowQuickRechargeModal] = useState(false);
  const [processingRecharge, setProcessingRecharge] = useState(false);

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
          if (s.allowRepeatClaims !== undefined) setAllowRepeatClaims(Boolean(s.allowRepeatClaims));
        }
      } catch (e) {
        console.warn(e);
      } finally {
        setLoading(false);
      }
    })();
    loadLeaderboard();
  }, []);

  const loadLeaderboard = async () => {
    setLoadingRank(true);
    try {
      const now = new Date();
      const eventId = `recharge_${now.getFullYear()}_${String(now.getMonth() + 1).padStart(2, '0')}`;
      const q = query(
        collection(firestoreDb, 'recharge_event_progress'),
        where('event_id', '==', eventId),
        orderBy('total_recharged_coins', 'desc'),
        limit(50)
      );
      const snap = await getDocs(q);
      const entries: LeaderboardEntry[] = [];
      for (const docSnap of snap.docs) {
        const d = docSnap.data();
        const uid = d.user_id || docSnap.id.replace(`${eventId}_`, '');
        let name = 'مستخدم';
        let photoUrl = '';
        let customId = '';
        try {
          const userDoc = await getDocs(query(collection(firestoreDb, 'users'), where('uid', '==', uid), limit(1)));
          if (userDoc && !userDoc.empty) {
            const ud = userDoc.docs[0].data();
            name = ud.name || ud.displayName || 'مستخدم';
            photoUrl = ud.photo_url || ud.photoUrl || '';
            customId = ud.custom_id || ud.customId || '';
          }
        } catch (_) {}

        entries.push({
          userId: uid,
          name,
          photoUrl,
          customId,
          totalRechargedCoins: Number(d.total_recharged_coins || 0),
          claimedTiers: Array.isArray(d.claimed_tiers) ? d.claimed_tiers : [],
          claimedCounts: d.claimed_counts || {},
          updatedAt: d.updated_at,
        });
      }
      setLeaderboard(entries);
    } catch (err) {
      console.warn('loadLeaderboard error:', err);
    } finally {
      setLoadingRank(false);
    }
  };

  const handleQuickRecharge = async () => {
    if (!quickRechargeUid || !quickRechargeAmount) return;
    const amount = parseInt(quickRechargeAmount) || 0;
    if (amount <= 0) return;

    setProcessingRecharge(true);
    try {
      const now = new Date();
      const eventId = `recharge_${now.getFullYear()}_${String(now.getMonth() + 1).padStart(2, '0')}`;

      // 1. تحديث في Firestore users
      const userRef = doc(firestoreDb, 'users', quickRechargeUid);
      await setDoc(userRef, {
        coins: increment(amount),
        recharged_coins: increment(amount),
        total_recharge: increment(amount),
      }, { merge: true });

      // 2. تحديث في recharge_event_progress
      const progressRef = doc(firestoreDb, 'recharge_event_progress', `${eventId}_${quickRechargeUid}`);
      await setDoc(progressRef, {
        event_id: eventId,
        user_id: quickRechargeUid,
        total_recharged_coins: increment(amount),
        updated_at: now.toISOString(),
      }, { merge: true });

      showNotification(`🎉 تم شحن ${amount.toLocaleString()} كوينز للمستخدم وتحديث تقدم الحدث فوراً!`);
      setShowQuickRechargeModal(false);
      setQuickRechargeUid('');
      loadLeaderboard();
    } catch (e: any) {
      alert(`خطأ أثناء الشحن: ${e?.message || e}`);
    } finally {
      setProcessingRecharge(false);
    }
  };

  const showNotification = (text: string) => {
    setMsg(text);
    setTimeout(() => setMsg(''), 3500);
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      const configPayload = {
        recharge_event_tiers: tiers,
        recharge_event_settings: {
          title, titleColor, headerTextImage,
          dialogBgImage, itemBgImage, tagImage, coinsImage, btnImage, closeBtnImage,
          btnText, btnTextColor, tagTextColor, itemLabelColor, overlayBgColor,
          allowRepeatClaims
        }
      };

      // 1. تحديث Supabase
      await updateAppConfig(configPayload as any);

      // 2. تحديث Firestore المباشر لمزامنة التطبيق فوراً
      try {
        await setDoc(doc(firestoreDb, 'app_config', 'general'), configPayload, { merge: true });
      } catch (err) {
        console.warn('Firestore sync warning:', err);
      }

      showNotification('✅ تم حفظ إعدادات وحدث الشحن ومزامنتها مع التطبيق فوراً بنجاح!');
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

        <button
          onClick={() => { setActiveTab('ranking'); loadLeaderboard(); }}
          className={`px-5 py-2.5 text-xs font-bold rounded-xl transition flex items-center gap-2 ${activeTab === 'ranking' ? 'bg-amber-500 text-black shadow-lg shadow-amber-500/30' : 'text-slate-400 hover:bg-white/5 hover:text-white'}`}
        >
          <Trophy className="w-4 h-4" />
          <span>ترتيب كبار الشاحنين والمتصدرين ({leaderboard.length})</span>
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

              {/* Allow repeat claims switch */}
              <div className="p-4 bg-slate-900/60 rounded-2xl border border-white/5 flex items-center justify-between">
                <div>
                  <p className="text-xs font-bold text-white">السماح بتكرار استلام المكافآت لنفس المستوى عند مضاعفة الشحن</p>
                  <p className="text-[10px] text-slate-400 mt-0.5">
                    عند التفعيل، إذا شحن المستخدم مبالغ تغطي تارجت المستوى أكثر من مرة (مثلاً 500K لمستوى 100K)، سيتاح له استلام الجائزة عدة مرات متكررة.
                  </p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={allowRepeatClaims}
                    onChange={(e) => setAllowRepeatClaims(e.target.checked)}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-slate-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-amber-500"></div>
                </label>
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

      {/* ─── PREVIEW TAB: DUAL MODE (FULL-SCREEN EVENT & AUTHENTIC D:40 DIALOG) ─── */}
      {activeTab === 'preview' && (
        <div className="bg-[#0b0b0e] border border-amber-500/30 rounded-3xl p-6 flex flex-col items-center justify-center relative min-h-[640px]">
          {/* Header Controls: Switch between Screen & Dialog */}
          <div className="w-full flex flex-col sm:flex-row items-center justify-between gap-4 mb-6 pb-4 border-b border-white/10">
            <div className="text-xs text-amber-400 font-bold flex items-center gap-1.5">
              <Smartphone className="w-4 h-4" />
              <span>معاينة حية دقيقة للمستخدم النهائي (تطابق أصل D:40)</span>
            </div>

            <div className="flex items-center gap-2 bg-[#161618] p-1.5 rounded-2xl border border-white/10">
              <button
                type="button"
                onClick={() => setPreviewMode('screen')}
                className={`px-4 py-1.5 rounded-xl text-xs font-bold transition flex items-center gap-1.5 ${
                  previewMode === 'screen'
                    ? 'bg-amber-500 text-black shadow-lg shadow-amber-500/20'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                <Smartphone className="w-3.5 h-3.5" />
                📱 شاشة الحدث الكاملة (Event Screen)
              </button>
              <button
                type="button"
                onClick={() => setPreviewMode('dialog')}
                className={`px-4 py-1.5 rounded-xl text-xs font-bold transition flex items-center gap-1.5 ${
                  previewMode === 'dialog'
                    ? 'bg-amber-500 text-black shadow-lg shadow-amber-500/20'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                <Layers className="w-3.5 h-3.5" />
                🪟 النافذة المنبثقة (D:40 Dialog)
              </button>
            </div>
          </div>

          {/* ══════════════════════════════════════════════════════════════ */}
          {/* 1. FULL SCREEN MOBILE EVENT VIEW */}
          {/* ══════════════════════════════════════════════════════════════ */}
          {previewMode === 'screen' && (
            <div className="relative w-[360px] h-[720px] bg-[#0C0A14] rounded-[40px] border-4 border-[#2A2338] shadow-2xl overflow-hidden flex flex-col select-none">
              {/* Phone Speaker Notch */}
              <div className="absolute top-2 left-1/2 -translate-x-1/2 w-24 h-4 bg-[#1a1622] rounded-full z-40 flex items-center justify-center">
                <div className="w-8 h-1 bg-white/20 rounded-full" />
              </div>

              {/* Scrollable Event Content */}
              <div className="flex-1 overflow-y-auto pb-24 relative text-white">
                {/* Header Royal Arch Banner */}
                <div className="relative w-full h-[230px] flex flex-col items-center justify-between pt-7 px-4">
                  <img
                    src={dialogBgImage}
                    alt="Arch"
                    className="absolute top-0 left-0 w-full h-full object-fill pointer-events-none z-0"
                    onError={e => { (e.target as HTMLImageElement).src = 'assets/recharge_event/recharge_remind_dialog_bg.webp'; }}
                  />

                  {/* Top Bar (Back, Title, Rules) */}
                  <div className="relative z-10 w-full flex items-center justify-between">
                    <button className="w-8 h-8 rounded-full bg-black/50 border border-white/20 flex items-center justify-center text-xs">
                      ‹
                    </button>
                    {headerTextImage ? (
                      <img src={headerTextImage} alt="Header" className="max-h-8 object-contain mx-auto" />
                    ) : (
                      <span className="text-xs font-black text-amber-400 drop-shadow">⚡ حدث الشحن الملكي الأسطوري</span>
                    )}
                    <button className="w-8 h-8 rounded-full bg-black/50 border border-white/20 flex items-center justify-center text-amber-300 text-xs font-bold">
                      ℹ
                    </button>
                  </div>

                  {/* Countdown Timer Badge */}
                  <div className="relative z-10 -mt-2 flex flex-col items-center">
                    <div className="bg-black/75 border border-amber-400/60 rounded-full px-3 py-1 flex items-center gap-1.5 shadow-md">
                      <span className="text-amber-400 text-[10px]">⏱ ينتهي خلال: 15 يوم 12:45:30</span>
                    </div>
                    <p className="text-[10px] font-bold mt-1 text-center drop-shadow px-4" style={{ color: titleColor }}>
                      {title}
                    </p>
                  </div>

                  {/* User Progress Card */}
                  <div className="relative z-20 w-full bg-gradient-to-r from-[#2C1F10] to-[#1B1428] border border-amber-500/50 rounded-2xl p-3 shadow-xl mt-2">
                    <div className="flex items-center justify-between text-[11px]">
                      <div>
                        <div className="text-slate-300 text-[10px]">شحنك التراكمي هذا الشهر:</div>
                        <div className="text-amber-300 font-black text-base flex items-center gap-1">
                          <span>1,250,000</span>
                          <span className="text-[10px] text-amber-400">🪙 كوينز</span>
                        </div>
                      </div>
                      <div className="bg-amber-500/15 border border-amber-500/30 rounded-xl px-2 py-1 text-right">
                        <div className="text-amber-300 font-bold text-[10px]">الهدف القادم: 5M</div>
                        <div className="text-white/60 text-[9px]">متبقي: 3,750,000</div>
                      </div>
                    </div>
                    {/* Golden Progress Bar */}
                    <div className="w-full h-2 bg-white/10 rounded-full mt-2 overflow-hidden">
                      <div className="h-full bg-gradient-to-r from-amber-600 to-amber-300 rounded-full" style={{ width: '25%' }} />
                    </div>
                  </div>
                </div>

                {/* Section Title */}
                <div className="px-4 mt-6 mb-2 flex items-center gap-1.5 text-xs font-bold text-amber-300">
                  <Sparkles className="w-3.5 h-3.5" />
                  <span>مكافآت مستويات الشحن (14 مستوى ملكي)</span>
                </div>

                {/* 14 Tiers 3-Column Grid */}
                <div className="px-3 grid grid-cols-3 gap-2">
                  {tiers.map((t) => (
                    <div
                      key={t.tier}
                      onClick={() => setPreviewTier(t)}
                      className="flex flex-col items-center cursor-pointer transition hover:scale-105 active:scale-95 group bg-[#161324]/80 border border-white/5 rounded-2xl p-1.5 shadow"
                    >
                      {/* Frame Card */}
                      <div className="relative w-[78px] h-[86px] flex items-center justify-center">
                        <img
                          src={itemBgImage}
                          alt=""
                          className="absolute inset-0 w-full h-full object-contain pointer-events-none"
                        />
                        {/* Tag */}
                        <div className="absolute top-[6px] right-[2px] w-[32px] h-[20px] flex items-center justify-center">
                          <img src={tagImage} alt="" className="absolute inset-0 w-full h-full object-contain" />
                          <span
                            className="relative z-10 text-[8px] font-black leading-none drop-shadow"
                            style={{ color: tagTextColor }}
                          >
                            {t.tagText || t.rewardLabel}
                          </span>
                        </div>
                        {/* Icon */}
                        <div className="relative z-10 w-[44px] h-[36px] flex items-center justify-center pt-1">
                          <img
                            src={t.icon || `assets/recharge_event/${t.rewardLabel}.png`}
                            alt={t.rewardLabel}
                            className="max-w-full max-h-full object-contain"
                            onError={e => { (e.target as HTMLElement).style.display = 'none'; }}
                          />
                        </div>
                      </div>

                      {/* Label & Target */}
                      <span
                        className="text-[10px] font-black mt-0.5 drop-shadow text-center"
                        style={{ color: itemLabelColor }}
                      >
                        {t.rewardLabel}
                      </span>
                      <span className="text-[8px] text-white/50 text-center font-mono">
                        {t.requiredCoins >= 1000000 ? `${(t.requiredCoins / 1000000).toFixed(0)}M` : `${(t.requiredCoins / 1000).toFixed(0)}K`} 🪙
                      </span>

                      {/* Claim / Locked Pill */}
                      <div className="mt-1 w-full text-center">
                        {t.requiredCoins <= 1250000 ? (
                          <span className="block text-[8px] font-black bg-green-600 text-white rounded-md py-0.5 px-1 shadow">
                            جاهز للاستلام
                          </span>
                        ) : (
                          <span className="block text-[8px] font-bold bg-white/10 text-white/60 rounded-md py-0.5 px-1">
                            قيد التقدم
                          </span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Floating Bottom Action Bar */}
              <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-[#090710] via-[#090710]/95 to-transparent pt-4 pb-3 px-4 flex items-center justify-between border-t border-white/5 z-30">
                {/* Coins pile */}
                <div className="w-[100px] h-[38px]">
                  <img src={coinsImage} alt="Coins" className="w-full h-full object-contain" />
                </div>
                {/* Golden Button */}
                <button
                  onClick={() => alert('محاكاة زر اشحن الآن: سيتم الانتقال لشاشة باقات شحن المحفظة')}
                  className="relative w-[130px] h-[44px] flex items-center justify-center cursor-pointer transition hover:brightness-110 active:scale-95 shrink-0"
                >
                  <img src={btnImage} alt="Button" className="absolute inset-0 w-full h-full object-contain drop-shadow" />
                  <span
                    className="relative z-10 font-black text-base tracking-wide drop-shadow"
                    style={{ color: btnTextColor }}
                  >
                    {btnText}
                  </span>
                </button>
              </div>
            </div>
          )}

          {/* ══════════════════════════════════════════════════════════════ */}
          {/* 2. AUTHENTIC D:40 COMPACT DIALOG VIEW */}
          {/* ══════════════════════════════════════════════════════════════ */}
          {previewMode === 'dialog' && (
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
          )}
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

      {/* ─── RANKING & PARTICIPANTS TAB ─── */}
      {activeTab === 'ranking' && (
        <div className="space-y-6">
          {/* Stats Bar */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="bg-[#141417] border border-white/5 p-5 rounded-2xl flex items-center gap-4">
              <div className="w-12 h-12 rounded-xl bg-amber-500/10 flex items-center justify-center text-amber-400">
                <Users className="w-6 h-6" />
              </div>
              <div>
                <p className="text-xs text-slate-400">إجمالي المشاركين هذا الشهر</p>
                <h3 className="text-xl font-bold text-white mt-0.5">{leaderboard.length} مستخدم</h3>
              </div>
            </div>

            <div className="bg-[#141417] border border-white/5 p-5 rounded-2xl flex items-center gap-4">
              <div className="w-12 h-12 rounded-xl bg-emerald-500/10 flex items-center justify-center text-emerald-400">
                <Coins className="w-6 h-6" />
              </div>
              <div>
                <p className="text-xs text-slate-400">مجموع شحن الحدث الحالي</p>
                <h3 className="text-xl font-bold text-amber-400 mt-0.5">
                  {leaderboard.reduce((acc, curr) => acc + curr.totalRechargedCoins, 0).toLocaleString()} 🪙
                </h3>
              </div>
            </div>

            <div className="bg-[#141417] border border-white/5 p-5 rounded-2xl flex items-center justify-between">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 rounded-xl bg-yellow-500/10 flex items-center justify-center text-yellow-400">
                  <Trophy className="w-6 h-6" />
                </div>
                <div>
                  <p className="text-xs text-slate-400">متصدر الترتيب الأول</p>
                  <h3 className="text-base font-bold text-white mt-0.5">
                    {leaderboard[0]?.name || 'لا يوجد بعد'}
                  </h3>
                </div>
              </div>
              <button
                onClick={() => {
                  setQuickRechargeUid('');
                  setShowQuickRechargeModal(true);
                }}
                className="px-3.5 py-2 bg-gradient-to-r from-amber-500 to-amber-600 text-black text-xs font-bold rounded-xl shadow-md hover:from-amber-600 hover:to-amber-700 transition flex items-center gap-1.5"
              >
                <Plus className="w-3.5 h-3.5" />
                <span>شحن لمستخدم</span>
              </button>
            </div>
          </div>

          {/* Search & Refresh */}
          <div className="flex items-center justify-between gap-4 bg-[#141417] border border-white/5 p-4 rounded-2xl">
            <div className="relative flex-1 max-w-md">
              <Search className="w-4 h-4 text-slate-400 absolute right-3 top-3 pointer-events-none" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="البحث باسم المستخدم أو المعرف أو الـ UID..."
                className="w-full bg-slate-900/80 border border-white/10 rounded-xl pr-9 pl-4 py-2 text-xs text-white placeholder-slate-500"
              />
            </div>
            <button
              onClick={loadLeaderboard}
              disabled={loadingRank}
              className="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs font-semibold rounded-xl transition flex items-center gap-1.5"
            >
              <RefreshCw className={`w-3.5 h-3.5 ${loadingRank ? 'animate-spin' : ''}`} />
              <span>تحديث القائمة</span>
            </button>
          </div>

          {/* Leaderboard Table */}
          <div className="bg-[#141417] border border-white/5 rounded-2xl overflow-hidden shadow-xl">
            <div className="overflow-x-auto">
              <table className="w-full text-right">
                <thead>
                  <tr className="border-b border-white/5 bg-slate-900/40 text-[11px] text-slate-400 uppercase">
                    <th className="p-4 w-16 text-center">المركز</th>
                    <th className="p-4">المستخدم</th>
                    <th className="p-4">إجمالي الشحن هذا الشهر</th>
                    <th className="p-4">أعلى مستوى محقق</th>
                    <th className="p-4">المكافآت المستلمة</th>
                    <th className="p-4 text-center">إجراءات</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5 text-xs">
                  {loadingRank ? (
                    <tr>
                      <td colSpan={6} className="p-8 text-center text-slate-400">
                        <RefreshCw className="w-6 h-6 animate-spin mx-auto mb-2 text-amber-500" />
                        جارٍ تحميل ترتيب الشاحنين والمتصدرين...
                      </td>
                    </tr>
                  ) : leaderboard.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="p-8 text-center text-slate-400">
                        <Trophy className="w-8 h-8 mx-auto mb-2 text-slate-600" />
                        لم يتم تسجيل أي عمليات شحن في حدث هذا الشهر حتى الآن.
                      </td>
                    </tr>
                  ) : (
                    leaderboard
                      .filter(
                        (u) =>
                          u.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          u.userId.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          u.customId.toLowerCase().includes(searchQuery.toLowerCase())
                      )
                      .map((u, idx) => {
                        const highestTier = [...tiers]
                          .reverse()
                          .find((t) => u.totalRechargedCoins >= t.requiredCoins);
                        const totalClaims = Object.values(u.claimedCounts || {}).reduce((a, b) => a + b, 0) || u.claimedTiers.length;

                        return (
                          <tr key={u.userId} className="hover:bg-white/[0.02] transition">
                            <td className="p-4 text-center">
                              {idx === 0 ? (
                                <span className="inline-flex items-center justify-center w-7 h-7 rounded-full bg-amber-500/20 text-amber-400 font-bold border border-amber-500/40">
                                  👑 1
                                </span>
                              ) : idx === 1 ? (
                                <span className="inline-flex items-center justify-center w-7 h-7 rounded-full bg-slate-400/20 text-slate-300 font-bold border border-slate-400/40">
                                  🥈 2
                                </span>
                              ) : idx === 2 ? (
                                <span className="inline-flex items-center justify-center w-7 h-7 rounded-full bg-amber-700/20 text-amber-600 font-bold border border-amber-700/40">
                                  🥉 3
                                </span>
                              ) : (
                                <span className="text-slate-500 font-semibold font-mono">#{idx + 1}</span>
                              )}
                            </td>
                            <td className="p-4">
                              <div className="flex items-center gap-3">
                                {u.photoUrl ? (
                                  <img
                                    src={u.photoUrl}
                                    className="w-10 h-10 rounded-full object-cover border border-white/10"
                                    onError={(e) => {
                                      (e.target as HTMLImageElement).style.display = 'none';
                                    }}
                                  />
                                ) : (
                                  <div className="w-10 h-10 rounded-full bg-amber-500/20 text-amber-400 font-bold flex items-center justify-center">
                                    {u.name?.[0] || 'U'}
                                  </div>
                                )}
                                <div>
                                  <p className="font-bold text-white text-xs">{u.name}</p>
                                  <p className="text-[10px] text-slate-400 font-mono">
                                    {u.customId ? `ID: ${u.customId}` : u.userId.slice(0, 10)}
                                  </p>
                                </div>
                              </div>
                            </td>
                            <td className="p-4">
                              <span className="font-bold text-amber-400 text-sm">
                                {u.totalRechargedCoins.toLocaleString()} 🪙
                              </span>
                            </td>
                            <td className="p-4">
                              {highestTier ? (
                                <span className="px-2.5 py-1 rounded-lg bg-amber-500/10 text-amber-300 border border-amber-500/20 font-bold text-[11px]">
                                  {highestTier.rewardLabel}
                                </span>
                              ) : (
                                <span className="text-slate-500 text-[11px]">لم يصل لمستوى بعد</span>
                              )}
                            </td>
                            <td className="p-4">
                              <span className="text-slate-300 font-medium">
                                {totalClaims > 0 ? `${totalClaims} مكافآت مستلمة` : 'لم يستلم بعد'}
                              </span>
                            </td>
                            <td className="p-4 text-center">
                              <button
                                onClick={() => {
                                  setQuickRechargeUid(u.userId);
                                  setShowQuickRechargeModal(true);
                                }}
                                className="px-3 py-1.5 bg-amber-500/10 hover:bg-amber-500/20 text-amber-400 border border-amber-500/30 rounded-lg text-xs font-semibold transition"
                              >
                                شحن رصيد + تارجت
                              </button>
                            </td>
                          </tr>
                        );
                      })
                  )}
                </tbody>
              </table>
            </div>
          </div>

          {/* Quick Recharge Modal */}
          {showQuickRechargeModal && (
            <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
              <div className="bg-[#141417] border border-amber-500/30 rounded-2xl w-full max-w-md p-6 space-y-4 text-right shadow-2xl">
                <div className="flex items-center justify-between border-b border-white/5 pb-3">
                  <h3 className="font-bold text-white text-sm">شحن رصيد وتفعيل تارجت الحدث مباشرة</h3>
                  <button
                    onClick={() => setShowQuickRechargeModal(false)}
                    className="text-slate-400 hover:text-white text-xs"
                  >
                    ✕
                  </button>
                </div>

                <div>
                  <label className="block text-[11px] text-slate-400 mb-1">معرّف المستخدم (UID أو Custom ID):</label>
                  <input
                    type="text"
                    value={quickRechargeUid}
                    onChange={(e) => setQuickRechargeUid(e.target.value)}
                    placeholder="أدخل الـ UID..."
                    className="w-full bg-slate-900 border border-white/10 rounded-xl px-3 py-2 text-xs text-white font-mono"
                  />
                </div>

                <div>
                  <label className="block text-[11px] text-slate-400 mb-1">كمية الكوينز المراد شحنها:</label>
                  <input
                    type="number"
                    value={quickRechargeAmount}
                    onChange={(e) => setQuickRechargeAmount(e.target.value)}
                    placeholder="100000"
                    className="w-full bg-slate-900 border border-white/10 rounded-xl px-3 py-2 text-xs text-amber-400 font-bold"
                  />
                  <div className="flex gap-1.5 mt-2">
                    {[100000, 500000, 1000000, 5000000, 10000000].map((val) => (
                      <button
                        key={val}
                        onClick={() => setQuickRechargeAmount(String(val))}
                        className="px-2 py-1 bg-white/5 hover:bg-white/10 text-slate-300 rounded text-[10px]"
                      >
                        +{val >= 1000000 ? `${val / 1000000}M` : `${val / 1000}K`}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="bg-amber-500/10 border border-amber-500/20 p-3 rounded-xl text-[11px] text-amber-300 space-y-1">
                  <p>⚡ <strong>ملاحظة:</strong> سيتم تزويد رصيد المستخدم بالكوينز، واحتساب الشحن ضمن حدث الشحن الشهري فوراً ليتمكن من استلام الجوائز مباشرة من داخل التطبيق!</p>
                </div>

                <div className="flex gap-2 pt-2">
                  <button
                    onClick={() => setShowQuickRechargeModal(false)}
                    className="flex-1 py-2.5 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded-xl text-xs font-semibold"
                  >
                    إلغاء
                  </button>
                  <button
                    onClick={handleQuickRecharge}
                    disabled={processingRecharge}
                    className="flex-1 py-2.5 bg-amber-500 hover:bg-amber-600 text-black rounded-xl text-xs font-bold transition flex items-center justify-center gap-1.5"
                  >
                    <Send className="w-3.5 h-3.5" />
                    <span>{processingRecharge ? 'جارٍ الشحن...' : 'تأكيد الشحن الفوري'}</span>
                  </button>
                </div>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
