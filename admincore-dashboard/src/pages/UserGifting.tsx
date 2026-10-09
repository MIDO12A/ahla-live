import { useEffect, useState, useMemo } from 'react';
import {
  searchUserProfile,
  getStoreItems,
  getStoreCategories,
  getVIPConfig,
  getBadges,
  getNecklaces,
  getUnifiedGiftedItems,
  sendUnifiedGift,
  revokeUnifiedGift,
  checkCustomIdAvailable,
} from '../lib/db';
import type {
  StoreItemModel,
  StoreCategory,
  VIPConfig,
  BadgeConfig,
  NecklaceConfig,
  GiftedItemModel,
} from '../types';
import {
  Gift,
  Search,
  Sparkles,
  Crown,
  Award,
  Clock,
  User,
  ShieldAlert,
  Calendar,
  CheckCircle2,
  AlertCircle,
  X,
  RefreshCw,
  ShoppingBag,
  Hash,
  Copy,
  Trash2,
  Layers,
  ArrowRightLeft,
  ChevronRight,
} from 'lucide-react';

interface FoundUser {
  id: string;
  uid: string;
  name: string;
  custom_id: string;
  original_custom_id?: string;
  is_special_id?: boolean;
  photo_url: string;
  coins: number;
  diamonds?: number;
}

const DURATION_PRESETS = [
  { label: '7 أيام', days: 7 },
  { label: '15 يوماً', days: 15 },
  { label: '30 يوماً (شهر)', days: 30 },
  { label: '90 يوماً (3 أشهر)', days: 90 },
  { label: '180 يوماً (6 أشهر)', days: 180 },
  { label: '365 يوماً (سنة)', days: 365 },
  { label: 'دائم ♾️', days: 0 },
];

export default function UserGifting() {
  // Master loading & notification
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(null);

  // User Lookup State
  const [searchQuery, setSearchQuery] = useState('');
  const [searchingUser, setSearchingUser] = useState(false);
  const [selectedUser, setSelectedUser] = useState<FoundUser | null>(null);

  // Gift Type Selection
  const [giftType, setGiftType] = useState<'store' | 'special_id' | 'vip' | 'badge_necklace'>('store');

  // Store Items Data & Selection
  const [storeItems, setStoreItems] = useState<StoreItemModel[]>([]);
  const [storeCategories, setStoreCategories] = useState<StoreCategory[]>([]);
  const [selectedStoreCategory, setSelectedStoreCategory] = useState<string>('all');
  const [selectedStoreItem, setSelectedStoreItem] = useState<StoreItemModel | null>(null);

  // Special ID Data & Selection
  const [specialIdInput, setSpecialIdInput] = useState('');
  const [checkingSpecialId, setCheckingSpecialId] = useState(false);
  const [specialIdAvailability, setSpecialIdAvailability] = useState<{ available: boolean; reason?: string } | null>(null);

  // VIP Data & Selection
  const [vipConfigs, setVipConfigs] = useState<VIPConfig[]>([]);
  const [selectedVipTier, setSelectedVipTier] = useState<number>(1);

  // Badges & Necklaces Data & Selection
  const [badgeNecklaceSubTab, setBadgeNecklaceSubTab] = useState<'badge' | 'necklace'>('badge');
  const [badges, setBadges] = useState<BadgeConfig[]>([]);
  const [necklaces, setNecklaces] = useState<NecklaceConfig[]>([]);
  const [selectedBadge, setSelectedBadge] = useState<BadgeConfig | null>(null);
  const [selectedNecklace, setSelectedNecklace] = useState<NecklaceConfig | null>(null);

  // Duration State
  const [expiryDays, setExpiryDays] = useState<number>(30);
  const [customDaysInput, setCustomDaysInput] = useState<string>('30');

  // Gifted Ledger State
  const [giftedLedger, setGiftedLedger] = useState<GiftedItemModel[]>([]);
  const [ledgerFilter, setLedgerFilter] = useState<'all' | 'store' | 'special_id' | 'vip' | 'badge' | 'necklace'>('all');
  const [ledgerSearch, setLedgerSearch] = useState('');
  const [revokingId, setRevokingId] = useState<string | null>(null);

  // 1. Initial Load
  const loadData = async () => {
    setLoading(true);
    try {
      const [items, cats, vips, bList, nList, ledger] = await Promise.all([
        getStoreItems(),
        getStoreCategories(),
        getVIPConfig(),
        getBadges(),
        getNecklaces(),
        getUnifiedGiftedItems(),
      ]);
      setStoreItems(items);
      setStoreCategories(cats);
      setVipConfigs(vips);
      setBadges(bList);
      setNecklaces(nList);
      setGiftedLedger(ledger);
    } catch (err) {
      console.error('Failed to load user gifting data:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  const showToast = (type: 'success' | 'error', message: string) => {
    setFeedback({ type, message });
    setTimeout(() => setFeedback(null), 4500);
  };

  // 2. User Live Search (Debounced)
  useEffect(() => {
    const q = searchQuery.trim();
    if (!q) {
      setSelectedUser(null);
      setSearchingUser(false);
      return;
    }

    const timer = setTimeout(async () => {
      setSearchingUser(true);
      try {
        const u = await searchUserProfile(q);
        if (u) {
          setSelectedUser(u);
        } else {
          setSelectedUser(null);
        }
      } catch (err) {
        console.warn('Search user error:', err);
      } finally {
        setSearchingUser(false);
      }
    }, 400);

    return () => clearTimeout(timer);
  }, [searchQuery]);

  // 3. Special ID Availability Check (Debounced)
  useEffect(() => {
    const sid = specialIdInput.trim();
    if (!sid) {
      setSpecialIdAvailability(null);
      setCheckingSpecialId(false);
      return;
    }

    const timer = setTimeout(async () => {
      setCheckingSpecialId(true);
      try {
        const res = await checkCustomIdAvailable(sid, selectedUser?.uid);
        setSpecialIdAvailability(res);
      } catch (err) {
        console.warn('Check special id error:', err);
      } finally {
        setCheckingSpecialId(false);
      }
    }, 350);

    return () => clearTimeout(timer);
  }, [specialIdInput, selectedUser]);

  // Handle Preset Days Click
  const handleDurationPreset = (days: number) => {
    setExpiryDays(days);
    setCustomDaysInput(days === 0 ? '0' : String(days));
  };

  const handleCustomDaysChange = (val: string) => {
    setCustomDaysInput(val);
    const num = parseInt(val, 10);
    if (!isNaN(num) && num >= 0) {
      setExpiryDays(num);
    }
  };

  // 4. Send Gift Action
  const handleSendGift = async () => {
    if (!selectedUser) {
      showToast('error', 'يرجى البحث عن المستخدم وتحديده أولاً');
      return;
    }

    setActionLoading(true);
    try {
      if (giftType === 'store') {
        if (!selectedStoreItem) {
          showToast('error', 'يرجى اختيار عنصر من المتجر');
          setActionLoading(false);
          return;
        }
        const res = await sendUnifiedGift({
          uid: selectedUser.uid,
          type: 'store',
          itemId: selectedStoreItem.id,
          itemName: selectedStoreItem.name,
          itemCategory: selectedStoreItem.category,
          itemIcon: selectedStoreItem.iconAsset || selectedStoreItem.defaultImage || '',
          svgaAsset: selectedStoreItem.svgaAsset,
          videoAsset: selectedStoreItem.videoAsset,
          expiryDays,
          sentBy: 'admin',
          sentByName: 'الإدارة',
        });
        if (res.success) {
          showToast('success', res.message || 'تم إهداء مقتنى المتجر بنجاح!');
          setSelectedStoreItem(null);
        } else {
          showToast('error', res.message || 'فشل إهداء العنصر');
        }
      } else if (giftType === 'special_id') {
        const sid = specialIdInput.trim();
        if (!sid) {
          showToast('error', 'يرجى كتابة الآيدي المميز');
          setActionLoading(false);
          return;
        }
        if (specialIdAvailability && !specialIdAvailability.available) {
          showToast('error', specialIdAvailability.reason || 'هذا الآيدي غير متاح');
          setActionLoading(false);
          return;
        }
        const res = await sendUnifiedGift({
          uid: selectedUser.uid,
          type: 'special_id',
          itemId: sid,
          itemName: `آيدي مميز (${sid})`,
          itemCategory: 'special_id',
          itemIcon: 'assets/mipmap-xxhdpi/ic_id_card_prop.png',
          expiryDays,
          sentBy: 'admin',
          sentByName: 'الإدارة',
        });
        if (res.success) {
          showToast('success', res.message || 'تم إهداء الآيدي المميز والاحتفاظ بالآيدي القديم بنجاح!');
          setSpecialIdInput('');
          // Refresh user profile in view
          const updated = await searchUserProfile(sid);
          if (updated) setSelectedUser(updated);
        } else {
          showToast('error', res.message || 'فشل إهداء الآيدي المميز');
        }
      } else if (giftType === 'vip') {
        const cfg = vipConfigs.find(c => c.tier === selectedVipTier);
        const vipName = cfg?.name || `VIP ${selectedVipTier}`;
        const res = await sendUnifiedGift({
          uid: selectedUser.uid,
          type: 'vip',
          itemId: String(selectedVipTier),
          itemName: vipName,
          itemCategory: 'vip',
          itemIcon: 'assets/mipmap-xxhdpi/mine_mall_tab_vip_ic.webp',
          expiryDays,
          sentBy: 'admin',
          sentByName: 'الإدارة',
        });
        if (res.success) {
          showToast('success', res.message || `تم إهداء رتبة ${vipName} بنجاح!`);
        } else {
          showToast('error', res.message || 'فشل إهداء VIP');
        }
      } else if (giftType === 'badge_necklace') {
        if (badgeNecklaceSubTab === 'badge') {
          if (!selectedBadge) {
            showToast('error', 'يرجى اختيار الشارة المهدية');
            setActionLoading(false);
            return;
          }
          const res = await sendUnifiedGift({
            uid: selectedUser.uid,
            type: 'badge',
            itemId: selectedBadge.id,
            itemName: selectedBadge.name_ar || selectedBadge.name || 'شارة خاصة',
            itemCategory: 'badge',
            itemIcon: selectedBadge.iconAsset || selectedBadge.imageUrl || '',
            expiryDays,
            sentBy: 'admin',
            sentByName: 'الإدارة',
          });
          if (res.success) {
            showToast('success', res.message || 'تم إهداء الشارة بنجاح!');
            setSelectedBadge(null);
          } else {
            showToast('error', res.message || 'فشل إهداء الشارة');
          }
        } else {
          if (!selectedNecklace) {
            showToast('error', 'يرجى اختيار القلادة المهدية');
            setActionLoading(false);
            return;
          }
          const res = await sendUnifiedGift({
            uid: selectedUser.uid,
            type: 'necklace',
            itemId: selectedNecklace.id,
            itemName: selectedNecklace.name_ar || selectedNecklace.name || 'قلادة خاصة',
            itemCategory: 'necklace',
            itemIcon: selectedNecklace.iconAsset || selectedNecklace.imageUrl || '',
            svgaAsset: selectedNecklace.svgaUrl,
            expiryDays,
            sentBy: 'admin',
            sentByName: 'الإدارة',
          });
          if (res.success) {
            showToast('success', res.message || 'تم إهداء القلادة بنجاح!');
            setSelectedNecklace(null);
          } else {
            showToast('error', res.message || 'فشل إهداء القلادة');
          }
        }
      }

      // Refresh Gifted Ledger
      const freshLedger = await getUnifiedGiftedItems();
      setGiftedLedger(freshLedger);
    } catch (err: any) {
      console.error('Gift execution error:', err);
      showToast('error', err?.message || 'حدث خطأ أثناء إرسال الهدية');
    } finally {
      setActionLoading(false);
    }
  };

  // 5. Revoke Gift Action
  const handleRevoke = async (gift: GiftedItemModel) => {
    const isSpecialId = gift.item_category === 'special_id';
    const confirmMsg = isSpecialId
      ? `هل أنت متأكد من سحب هذا الآيدي المميز (${gift.item_id})؟ سيتم تلقائياً إرجاع المستخدم إلى آيديه القديم المحفوظ!`
      : `هل أنت متأكد من سحب الهدية (${gift.item_name}) فوراً من هذا المستخدم؟`;

    if (!window.confirm(confirmMsg)) return;

    setRevokingId(gift.id);
    try {
      const res = await revokeUnifiedGift(gift.id);
      if (res.success) {
        showToast('success', res.message || 'تم سحب الهدية بنجاح!');
        // Refresh Ledger
        const freshLedger = await getUnifiedGiftedItems();
        setGiftedLedger(freshLedger);
        // Refresh selected user if currently loaded
        if (selectedUser && selectedUser.uid === gift.uid) {
          const reloaded = await searchUserProfile(selectedUser.uid);
          if (reloaded) setSelectedUser(reloaded);
        }
      } else {
        showToast('error', res.message || 'فشل سحب الهدية');
      }
    } catch (err: any) {
      console.error('Revoke error:', err);
      showToast('error', err?.message || 'حدث خطأ أثناء سحب الهدية');
    } finally {
      setRevokingId(null);
    }
  };

  // Filter store items by category
  const filteredStoreItems = useMemo(() => {
    if (selectedStoreCategory === 'all') return storeItems;
    return storeItems.filter(item => item.category === selectedStoreCategory);
  }, [storeItems, selectedStoreCategory]);

  // Filter ledger rows
  const filteredLedger = useMemo(() => {
    return giftedLedger.filter(g => {
      // Type filter
      if (ledgerFilter !== 'all') {
        if (ledgerFilter === 'store') {
          if (['special_id', 'vip', 'badge', 'necklace'].includes(g.item_category)) return false;
        } else if (g.item_category !== ledgerFilter) {
          return false;
        }
      }
      // Search filter
      if (ledgerSearch.trim()) {
        const q = ledgerSearch.toLowerCase().trim();
        const uName = (g.user?.name || '').toLowerCase();
        const uCid = (g.user?.custom_id || '').toLowerCase();
        const uUid = (g.uid || '').toLowerCase();
        const iName = (g.item_name || '').toLowerCase();
        const iId = (g.item_id || '').toLowerCase();
        return uName.includes(q) || uCid.includes(q) || uUid.includes(q) || iName.includes(q) || iId.includes(q);
      }
      return true;
    });
  }, [giftedLedger, ledgerFilter, ledgerSearch]);

  const stats = useMemo(() => {
    const total = giftedLedger.length;
    const now = Date.now();
    const active = giftedLedger.filter(g => !g.expires_at || g.expires_at === 0 || g.expires_at > now).length;
    const expired = total - active;
    const specialIds = giftedLedger.filter(g => g.item_category === 'special_id').length;
    return { total, active, expired, specialIds };
  }, [giftedLedger]);

  return (
    <div className="space-y-6 pb-12 font-sans" dir="rtl">
      {/* Toast Notification */}
      {feedback && (
        <div
          className={`fixed top-4 left-1/2 -translate-x-1/2 z-50 flex items-center gap-2.5 px-5 py-3 rounded-xl shadow-2xl backdrop-blur-md border text-sm font-semibold transition-all animate-in fade-in slide-in-from-top-4 ${
            feedback.type === 'success'
              ? 'bg-emerald-500/20 border-emerald-500/40 text-emerald-300'
              : 'bg-rose-500/20 border-rose-500/40 text-rose-300'
          }`}
        >
          {feedback.type === 'success' ? <CheckCircle2 className="w-5 h-5 text-emerald-400" /> : <AlertCircle className="w-5 h-5 text-rose-400" />}
          <span>{feedback.message}</span>
        </div>
      )}

      {/* Page Header & Stats */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-bold text-white flex items-center gap-2.5">
            <span className="p-2 rounded-xl bg-gradient-to-tr from-amber-500 to-indigo-600 text-white shadow-lg shadow-indigo-500/20">
              <Gift className="w-6 h-6" />
            </span>
            <span>إهداء إلى المستخدمين 🎁</span>
          </h1>
          <p className="text-xs text-slate-400 mt-1">
            قسم شامل لإهداء مقتنيات المتجر، والآيديهات المميزة، وعضويات VIP، والشارات والقلائد مع إدارة مدد الانتهاء التلقائية والاحتفاظ بالآيدي القديم.
          </p>
        </div>

        <button
          onClick={loadData}
          disabled={loading}
          className="self-start md:self-auto px-3.5 py-2 rounded-xl bg-[#18181B] hover:bg-[#222226] border border-white/5 text-xs text-slate-300 hover:text-white flex items-center gap-2 transition-all"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin text-indigo-400' : ''}`} />
          <span>تحديث البيانات</span>
        </button>
      </div>

      {/* Top Metric Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div className="bg-[#141417] p-3.5 rounded-2xl border border-white/5 flex items-center gap-3">
          <div className="p-2.5 rounded-xl bg-indigo-500/10 text-indigo-400">
            <Gift className="w-5 h-5" />
          </div>
          <div>
            <div className="text-[11px] text-slate-400 font-medium">إجمالي الهدايا الممنوحة</div>
            <div className="text-lg font-bold text-white">{stats.total}</div>
          </div>
        </div>

        <div className="bg-[#141417] p-3.5 rounded-2xl border border-white/5 flex items-center gap-3">
          <div className="p-2.5 rounded-xl bg-emerald-500/10 text-emerald-400">
            <CheckCircle2 className="w-5 h-5" />
          </div>
          <div>
            <div className="text-[11px] text-slate-400 font-medium">الهدايا النشطة حالياً</div>
            <div className="text-lg font-bold text-emerald-400">{stats.active}</div>
          </div>
        </div>

        <div className="bg-[#141417] p-3.5 rounded-2xl border border-white/5 flex items-center gap-3">
          <div className="p-2.5 rounded-xl bg-amber-500/10 text-amber-400">
            <Hash className="w-5 h-5" />
          </div>
          <div>
            <div className="text-[11px] text-slate-400 font-medium">آيديهات مميزة ممنوحة</div>
            <div className="text-lg font-bold text-amber-400">{stats.specialIds}</div>
          </div>
        </div>

        <div className="bg-[#141417] p-3.5 rounded-2xl border border-white/5 flex items-center gap-3">
          <div className="p-2.5 rounded-xl bg-slate-500/10 text-slate-400">
            <Clock className="w-5 h-5" />
          </div>
          <div>
            <div className="text-[11px] text-slate-400 font-medium">هدايا منتهية الصلاحية</div>
            <div className="text-lg font-bold text-slate-400">{stats.expired}</div>
          </div>
        </div>
      </div>

      {/* Main Gifting Workbench Card */}
      <div className="bg-[#121215] rounded-3xl border border-white/10 p-5 md:p-6 space-y-6 shadow-2xl">
        {/* Step 1: User Lookup */}
        <div>
          <div className="flex items-center gap-2 mb-2">
            <span className="w-5 h-5 rounded-full bg-indigo-600/30 text-indigo-400 flex items-center justify-center text-xs font-bold border border-indigo-500/40">1</span>
            <h2 className="text-sm font-bold text-white">تحديد المستخدم المهدى إليه (البحث المباشر)</h2>
          </div>

          <div className="relative">
            <Search className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
            <input
              type="text"
              placeholder="اكتب رقم الآيدي (App ID)، أو UID، أو الاسم للبحث الفوري..."
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              className="w-full bg-[#18181C] border border-white/10 focus:border-indigo-500 rounded-2xl py-3 pr-10 pl-10 text-xs md:text-sm text-white placeholder-slate-500 outline-none transition-all shadow-inner"
            />
            {searchingUser && (
              <RefreshCw className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-indigo-400 animate-spin" />
            )}
            {searchQuery && !searchingUser && (
              <button
                onClick={() => {
                  setSearchQuery('');
                  setSelectedUser(null);
                }}
                className="absolute left-3.5 top-1/2 -translate-y-1/2 p-1 text-slate-400 hover:text-white"
              >
                <X className="w-4 h-4" />
              </button>
            )}
          </div>

          {/* User Preview Card */}
          {selectedUser && (
            <div className="mt-3 bg-gradient-to-r from-[#18181C] to-[#1F1F26] border border-indigo-500/30 rounded-2xl p-4 flex flex-col md:flex-row items-start md:items-center justify-between gap-4 animate-in fade-in slide-in-from-top-2">
              <div className="flex items-center gap-3.5">
                <div className="relative">
                  <img
                    src={selectedUser.photo_url || 'https://ui-avatars.com/api/?name=User&background=6366f1&color=fff'}
                    alt={selectedUser.name}
                    className="w-14 h-14 rounded-2xl object-cover border-2 border-indigo-500/30 shadow-md"
                  />
                  {selectedUser.is_special_id && (
                    <span className="absolute -top-1.5 -right-1.5 px-1.5 py-0.5 rounded-full bg-amber-500 text-[9px] font-black text-black shadow-lg">
                      VIP ID
                    </span>
                  )}
                </div>

                <div className="space-y-1">
                  <div className="flex items-center gap-2">
                    <span className="text-base font-bold text-white">{selectedUser.name}</span>
                    {selectedUser.is_special_id && (
                      <span className="px-2 py-0.5 rounded-lg bg-amber-500/10 border border-amber-500/30 text-amber-400 text-[10px] font-bold flex items-center gap-1">
                        <Sparkles className="w-3 h-3" /> آيدي مميز
                      </span>
                    )}
                  </div>

                  <div className="flex flex-wrap items-center gap-2 text-xs">
                    <div className="flex items-center gap-1 bg-black/30 px-2.5 py-1 rounded-lg border border-white/5 text-slate-300">
                      <Hash className="w-3.5 h-3.5 text-indigo-400" />
                      <span>المعرّف الحالي:</span>
                      <strong className="text-white font-mono">{selectedUser.custom_id}</strong>
                    </div>

                    {selectedUser.original_custom_id ? (
                      <div className="flex items-center gap-1 bg-emerald-500/10 px-2.5 py-1 rounded-lg border border-emerald-500/20 text-emerald-300">
                        <ArrowRightLeft className="w-3.5 h-3.5" />
                        <span>المعرّف الأصلي المحفوظ:</span>
                        <strong className="font-mono">{selectedUser.original_custom_id}</strong>
                      </div>
                    ) : (
                      <div className="flex items-center gap-1 bg-slate-800/40 px-2.5 py-1 rounded-lg text-slate-400 text-[11px]">
                        <span>(سيتم حفظ المعرّف الحالي {selectedUser.custom_id} كمعرف أصلي تلقائياً)</span>
                      </div>
                    )}
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-2 self-end md:self-auto text-xs">
                <div className="bg-[#101014] px-3 py-1.5 rounded-xl border border-white/5 text-slate-400 text-[11px]">
                  <span>UID: </span>
                  <span className="font-mono text-slate-300">{selectedUser.uid.slice(0, 10)}...</span>
                </div>
              </div>
            </div>
          )}

          {!selectedUser && searchQuery && !searchingUser && (
            <div className="mt-3 p-3 rounded-xl bg-amber-500/5 border border-amber-500/20 text-amber-300 text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              <span>لم يتم العثور على مستخدم يطابق البحث &quot;{searchQuery}&quot;. تأكد من رقم الآيدي أو الـ UID.</span>
            </div>
          )}
        </div>

        {/* Step 2: Choose Gift Category */}
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            <span className="w-5 h-5 rounded-full bg-indigo-600/30 text-indigo-400 flex items-center justify-center text-xs font-bold border border-indigo-500/40">2</span>
            <h2 className="text-sm font-bold text-white">اختيار نوع الهدية الممنوحة</h2>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
            <button
              onClick={() => setGiftType('store')}
              className={`p-3.5 rounded-2xl border text-right transition-all flex flex-col justify-between gap-3 ${
                giftType === 'store'
                  ? 'bg-gradient-to-br from-indigo-600/30 to-indigo-900/30 border-indigo-500 shadow-lg shadow-indigo-600/20 text-white'
                  : 'bg-[#18181C] hover:bg-[#202025] border-white/5 text-slate-400 hover:text-white'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className={`p-2 rounded-xl ${giftType === 'store' ? 'bg-indigo-600 text-white' : 'bg-white/5 text-slate-400'}`}>
                  <ShoppingBag className="w-5 h-5" />
                </span>
                {giftType === 'store' && <CheckCircle2 className="w-4 h-4 text-indigo-400" />}
              </div>
              <div>
                <div className="text-xs font-bold">مقتنيات المتجر</div>
                <div className="text-[10px] text-slate-400 mt-0.5">إطارات، مركبات، مؤثرات دخول، فقاعات</div>
              </div>
            </button>

            <button
              onClick={() => setGiftType('special_id')}
              className={`p-3.5 rounded-2xl border text-right transition-all flex flex-col justify-between gap-3 ${
                giftType === 'special_id'
                  ? 'bg-gradient-to-br from-amber-600/30 to-amber-900/30 border-amber-500 shadow-lg shadow-amber-600/20 text-white'
                  : 'bg-[#18181C] hover:bg-[#202025] border-white/5 text-slate-400 hover:text-white'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className={`p-2 rounded-xl ${giftType === 'special_id' ? 'bg-amber-600 text-black' : 'bg-white/5 text-slate-400'}`}>
                  <Hash className="w-5 h-5" />
                </span>
                {giftType === 'special_id' && <CheckCircle2 className="w-4 h-4 text-amber-400" />}
              </div>
              <div>
                <div className="text-xs font-bold">آيدي مميز (Special ID)</div>
                <div className="text-[10px] text-slate-400 mt-0.5">منح معرّف قصير/مميز مع حفظ القديم</div>
              </div>
            </button>

            <button
              onClick={() => setGiftType('vip')}
              className={`p-3.5 rounded-2xl border text-right transition-all flex flex-col justify-between gap-3 ${
                giftType === 'vip'
                  ? 'bg-gradient-to-br from-purple-600/30 to-purple-900/30 border-purple-500 shadow-lg shadow-purple-600/20 text-white'
                  : 'bg-[#18181C] hover:bg-[#202025] border-white/5 text-slate-400 hover:text-white'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className={`p-2 rounded-xl ${giftType === 'vip' ? 'bg-purple-600 text-white' : 'bg-white/5 text-slate-400'}`}>
                  <Crown className="w-5 h-5" />
                </span>
                {giftType === 'vip' && <CheckCircle2 className="w-4 h-4 text-purple-400" />}
              </div>
              <div>
                <div className="text-xs font-bold">عضويات VIP</div>
                <div className="text-[10px] text-slate-400 mt-0.5">من رتبة VIP 1 إلى VIP 6 مع الامتيازات</div>
              </div>
            </button>

            <button
              onClick={() => setGiftType('badge_necklace')}
              className={`p-3.5 rounded-2xl border text-right transition-all flex flex-col justify-between gap-3 ${
                giftType === 'badge_necklace'
                  ? 'bg-gradient-to-br from-rose-600/30 to-rose-900/30 border-rose-500 shadow-lg shadow-rose-600/20 text-white'
                  : 'bg-[#18181C] hover:bg-[#202025] border-white/5 text-slate-400 hover:text-white'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className={`p-2 rounded-xl ${giftType === 'badge_necklace' ? 'bg-rose-600 text-white' : 'bg-white/5 text-slate-400'}`}>
                  <Award className="w-5 h-5" />
                </span>
                {giftType === 'badge_necklace' && <CheckCircle2 className="w-4 h-4 text-rose-400" />}
              </div>
              <div>
                <div className="text-xs font-bold">شارات وقلائد SVGA</div>
                <div className="text-[10px] text-slate-400 mt-0.5">الأوسمة الفخرية والقلائد المتحركة</div>
              </div>
            </button>
          </div>
        </div>

        {/* Step 3: Item Selection Details */}
        <div className="bg-[#18181C] border border-white/5 rounded-2xl p-4 md:p-5 space-y-4">
          {/* TAB 1: STORE ITEMS */}
          {giftType === 'store' && (
            <div className="space-y-4">
              <div className="flex flex-wrap items-center gap-1.5 border-b border-white/5 pb-3">
                <button
                  onClick={() => setSelectedStoreCategory('all')}
                  className={`px-3 py-1.5 rounded-xl text-xs font-semibold transition-all ${
                    selectedStoreCategory === 'all'
                      ? 'bg-indigo-600 text-white'
                      : 'bg-[#121215] text-slate-400 hover:text-white'
                  }`}
                >
                  جميع الأصناف ({storeItems.length})
                </button>
                {storeCategories.map(cat => {
                  const count = storeItems.filter(i => i.category === cat.key).length;
                  return (
                    <button
                      key={cat.key || cat.id}
                      onClick={() => setSelectedStoreCategory(cat.key)}
                      className={`px-3 py-1.5 rounded-xl text-xs font-semibold transition-all ${
                        selectedStoreCategory === cat.key
                          ? 'bg-indigo-600 text-white'
                          : 'bg-[#121215] text-slate-400 hover:text-white'
                      }`}
                    >
                      {cat.name} ({count})
                    </button>
                  );
                })}
              </div>

              {filteredStoreItems.length === 0 ? (
                <div className="text-center py-8 text-xs text-slate-500">لا توجد عناصر متوفرة في هذا القسم.</div>
              ) : (
                <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-3 max-h-72 overflow-y-auto custom-scrollbar p-1">
                  {filteredStoreItems.map(item => {
                    const isSelected = selectedStoreItem?.id === item.id;
                    return (
                      <div
                        key={item.id}
                        onClick={() => setSelectedStoreItem(item)}
                        className={`cursor-pointer rounded-xl p-2.5 border text-center transition-all flex flex-col items-center justify-between gap-2 ${
                          isSelected
                            ? 'bg-indigo-600/20 border-indigo-500 shadow-md shadow-indigo-600/30'
                            : 'bg-[#141417] hover:bg-[#1C1C20] border-white/5'
                        }`}
                      >
                        <div className="w-16 h-16 rounded-lg bg-black/40 flex items-center justify-center p-1 overflow-hidden relative">
                          <img
                            src={item.iconAsset || item.defaultImage || 'https://via.placeholder.com/64'}
                            alt={item.name}
                            className="max-w-full max-h-full object-contain"
                          />
                          {item.svgaAsset && (
                            <span className="absolute bottom-1 right-1 px-1 py-0.2 rounded bg-indigo-500 text-[8px] font-bold text-white">
                              SVGA
                            </span>
                          )}
                        </div>
                        <div className="w-full">
                          <div className="text-xs font-bold text-white truncate" title={item.name}>{item.name}</div>
                          <div className="text-[10px] text-slate-400 truncate">{item.category}</div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}

              {selectedStoreItem && (
                <div className="bg-indigo-500/10 border border-indigo-500/30 rounded-xl p-3 flex items-center justify-between gap-3 text-xs">
                  <div className="flex items-center gap-2.5">
                    <img
                      src={selectedStoreItem.iconAsset || selectedStoreItem.defaultImage || ''}
                      alt={selectedStoreItem.name}
                      className="w-8 h-8 object-contain rounded bg-black/30 p-0.5"
                    />
                    <div>
                      <span className="text-slate-400">العنصر المحدد للإهداء: </span>
                      <strong className="text-white font-bold">{selectedStoreItem.name}</strong>
                      <span className="text-[11px] text-indigo-300 mr-2">({selectedStoreItem.category})</span>
                    </div>
                  </div>
                  <button onClick={() => setSelectedStoreItem(null)} className="text-slate-400 hover:text-white">
                    <X className="w-4 h-4" />
                  </button>
                </div>
              )}
            </div>
          )}

          {/* TAB 2: SPECIAL ID */}
          {giftType === 'special_id' && (
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-300 mb-1.5">
                  رقم الآيدي المميز المراد إهداؤه (مثال: 1, 777, 8888, 1000, 99999)
                </label>
                <div className="relative">
                  <Hash className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                  <input
                    type="text"
                    placeholder="أدخل المعرّف المميز الجديد..."
                    value={specialIdInput}
                    onChange={e => setSpecialIdInput(e.target.value)}
                    className="w-full bg-[#141417] border border-white/10 focus:border-amber-500 rounded-xl py-3 pr-10 pl-10 text-sm text-white font-mono placeholder-slate-500 outline-none transition-all"
                  />
                  {checkingSpecialId && (
                    <RefreshCw className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-amber-400 animate-spin" />
                  )}
                </div>

                {specialIdAvailability && !checkingSpecialId && (
                  <div className="mt-2 text-xs flex items-center gap-1.5">
                    {specialIdAvailability.available ? (
                      <span className="text-emerald-400 font-semibold flex items-center gap-1">
                        <CheckCircle2 className="w-4 h-4" /> هذا الآيدي متاح وجاهز للإهداء!
                      </span>
                    ) : (
                      <span className="text-rose-400 font-semibold flex items-center gap-1">
                        <AlertCircle className="w-4 h-4" /> {specialIdAvailability.reason || 'هذا الآيدي محجوز بالفعل لمستخدم آخر'}
                      </span>
                    )}
                  </div>
                )}
              </div>

              <div className="bg-amber-500/10 border border-amber-500/20 rounded-xl p-3.5 text-xs text-amber-200/90 leading-relaxed flex items-start gap-2.5">
                <ShieldAlert className="w-5 h-5 text-amber-400 shrink-0 mt-0.5" />
                <div>
                  <strong className="block font-bold text-amber-300 mb-0.5">ضمان الحفاظ على حساب المستخدم:</strong>
                  عند إهداء الآيدي المميز، سيتم تلقائياً حفظ الآيدي القديم للمستخدم في قاعدة البيانات. وعند انتهاء مدة الإهداء أو سحبه، سيعود حساب المستخدم فوراً وبأمان إلى آيديه الأصلي القديم دون أي فقدان للبيانات أو الغرفة.
                </div>
              </div>
            </div>
          )}

          {/* TAB 3: VIP TIERS */}
          {giftType === 'vip' && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-3">
                {[1, 2, 3, 4, 5, 6].map(tier => {
                  const cfg = vipConfigs.find(c => c.tier === tier);
                  const isSelected = selectedVipTier === tier;
                  const color = cfg?.color || (tier === 1 ? '#CD7F32' : tier === 2 ? '#C0C0C0' : tier === 3 ? '#FFD700' : tier === 4 ? '#00E5FF' : tier === 5 ? '#E040FB' : '#FF1744');

                  return (
                    <div
                      key={tier}
                      onClick={() => setSelectedVipTier(tier)}
                      className={`cursor-pointer rounded-2xl p-4 border text-center transition-all flex flex-col items-center justify-between gap-3 ${
                        isSelected
                          ? 'border-white bg-white/10 shadow-lg scale-105'
                          : 'bg-[#141417] hover:bg-[#1A1A1E] border-white/5'
                      }`}
                      style={{ borderColor: isSelected ? color : undefined }}
                    >
                      <Crown className="w-8 h-8" style={{ color }} />
                      <div>
                        <div className="text-sm font-black" style={{ color }}>{cfg?.name || `VIP ${tier}`}</div>
                        <div className="text-[10px] text-slate-400 mt-1">الرتبة {tier}</div>
                      </div>
                      {isSelected && (
                        <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-white/20 text-white">
                          محدد
                        </span>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* TAB 4: BADGES & NECKLACES */}
          {giftType === 'badge_necklace' && (
            <div className="space-y-4">
              <div className="flex gap-2 border-b border-white/5 pb-3">
                <button
                  onClick={() => setBadgeNecklaceSubTab('badge')}
                  className={`px-4 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 ${
                    badgeNecklaceSubTab === 'badge'
                      ? 'bg-rose-600 text-white'
                      : 'bg-[#121215] text-slate-400 hover:text-white'
                  }`}
                >
                  <Award className="w-4 h-4" /> الشارات والأوسمة ({badges.length})
                </button>
                <button
                  onClick={() => setBadgeNecklaceSubTab('necklace')}
                  className={`px-4 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 ${
                    badgeNecklaceSubTab === 'necklace'
                      ? 'bg-rose-600 text-white'
                      : 'bg-[#121215] text-slate-400 hover:text-white'
                  }`}
                >
                  <Crown className="w-4 h-4" /> القلائد SVGA ({necklaces.length})
                </button>
              </div>

              {badgeNecklaceSubTab === 'badge' ? (
                <div className="grid grid-cols-2 sm:grid-cols-4 md:grid-cols-6 gap-3 max-h-64 overflow-y-auto custom-scrollbar p-1">
                  {badges.map(b => {
                    const isSelected = selectedBadge?.id === b.id;
                    return (
                      <div
                        key={b.id}
                        onClick={() => setSelectedBadge(b)}
                        className={`cursor-pointer rounded-xl p-3 border text-center transition-all flex flex-col items-center justify-between gap-2 ${
                          isSelected
                            ? 'bg-rose-600/20 border-rose-500 shadow-md shadow-rose-600/30'
                            : 'bg-[#141417] hover:bg-[#1C1C20] border-white/5'
                        }`}
                      >
                        <img
                          src={b.iconAsset || b.imageUrl || 'https://via.placeholder.com/48'}
                          alt={b.name}
                          className="w-12 h-12 object-contain"
                        />
                        <div className="text-xs font-bold text-white truncate w-full" title={b.name_ar || b.name}>
                          {b.name_ar || b.name}
                        </div>
                      </div>
                    );
                  })}
                </div>
              ) : (
                <div className="grid grid-cols-2 sm:grid-cols-4 md:grid-cols-6 gap-3 max-h-64 overflow-y-auto custom-scrollbar p-1">
                  {necklaces.map(n => {
                    const isSelected = selectedNecklace?.id === n.id;
                    return (
                      <div
                        key={n.id}
                        onClick={() => setSelectedNecklace(n)}
                        className={`cursor-pointer rounded-xl p-3 border text-center transition-all flex flex-col items-center justify-between gap-2 ${
                          isSelected
                            ? 'bg-rose-600/20 border-rose-500 shadow-md shadow-rose-600/30'
                            : 'bg-[#141417] hover:bg-[#1C1C20] border-white/5'
                        }`}
                      >
                        <img
                          src={n.iconAsset || n.imageUrl || 'https://via.placeholder.com/48'}
                          alt={n.name}
                          className="w-12 h-12 object-contain"
                        />
                        <div className="text-xs font-bold text-white truncate w-full" title={n.name_ar || n.name}>
                          {n.name_ar || n.name}
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Step 4: Duration Selection */}
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            <span className="w-5 h-5 rounded-full bg-indigo-600/30 text-indigo-400 flex items-center justify-center text-xs font-bold border border-indigo-500/40">3</span>
            <h2 className="text-sm font-bold text-white">تحديد مدة الإهداء (بالأيام)</h2>
          </div>

          <div className="flex flex-wrap gap-2">
            {DURATION_PRESETS.map(preset => (
              <button
                key={preset.days}
                onClick={() => handleDurationPreset(preset.days)}
                className={`px-3.5 py-2 rounded-xl text-xs font-bold transition-all ${
                  expiryDays === preset.days
                    ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30 border border-indigo-400'
                    : 'bg-[#18181C] hover:bg-[#202025] text-slate-400 hover:text-white border border-white/5'
                }`}
              >
                {preset.label}
              </button>
            ))}
          </div>

          <div className="flex items-center gap-3 bg-[#18181C] p-3 rounded-xl border border-white/5 text-xs text-slate-300">
            <Clock className="w-4 h-4 text-indigo-400 shrink-0" />
            <span>مدة مخصصة بالأيام:</span>
            <input
              type="number"
              min="0"
              value={customDaysInput}
              onChange={e => handleCustomDaysChange(e.target.value)}
              className="w-24 bg-black/40 border border-white/10 rounded-lg px-2.5 py-1 text-center text-white font-bold outline-none"
            />
            <span className="text-slate-500 text-[11px]">
              {expiryDays === 0
                ? '(0 يعني هدية دائمة بدون تاريخ انتهاء)'
                : `(ستنتهي الهدية في: ${new Date(Date.now() + expiryDays * 86400000).toLocaleDateString('ar-EG')})`}
            </span>
          </div>
        </div>

        {/* Big Action Button */}
        <div className="pt-2 border-t border-white/5 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="text-xs text-slate-400">
            {selectedUser ? (
              <span>
                إرسال الهدية للمستخدم <strong className="text-white">{selectedUser.name}</strong> ({selectedUser.custom_id})
              </span>
            ) : (
              <span className="text-amber-400">⚠️ يرجى تحديد المستخدم أولاً لتفعيل زر الإهداء</span>
            )}
          </div>

          <button
            onClick={handleSendGift}
            disabled={!selectedUser || actionLoading}
            className={`w-full sm:w-auto px-8 py-3.5 rounded-2xl text-sm font-bold flex items-center justify-center gap-2 shadow-xl transition-all ${
              !selectedUser || actionLoading
                ? 'bg-slate-800 text-slate-500 cursor-not-allowed'
                : 'bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500 text-white shadow-emerald-600/30 active:scale-95'
            }`}
          >
            {actionLoading ? (
              <>
                <RefreshCw className="w-4 h-4 animate-spin" />
                <span>جاري معالجة الإهداء...</span>
              </>
            ) : (
              <>
                <Gift className="w-4 h-4" />
                <span>إهداء الهدية للمستخدم الآن 🎁</span>
              </>
            )}
          </button>
        </div>
      </div>

      {/* Gifted Items Ledger Table */}
      <div className="bg-[#121215] rounded-3xl border border-white/10 overflow-hidden shadow-2xl">
        <div className="p-5 border-b border-white/5 flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
          <div>
            <h3 className="text-sm font-bold text-white flex items-center gap-2">
              <Layers className="w-4 h-4 text-indigo-400" />
              <span>سجل الهدايا النشطة والمنتهية</span>
            </h3>
            <p className="text-[11px] text-slate-400 mt-0.5">
              متابعة جميع الهدايا الممنوحة مع إمكانية سحب أي هدية فورياً واسترجاع الحالة السابقة.
            </p>
          </div>

          {/* Filters & Search */}
          <div className="flex flex-wrap items-center gap-2 w-full md:w-auto">
            <div className="relative flex-1 md:w-60">
              <Search className="absolute right-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-500" />
              <input
                type="text"
                placeholder="بحث في السجل..."
                value={ledgerSearch}
                onChange={e => setLedgerSearch(e.target.value)}
                className="w-full bg-[#18181C] border border-white/5 rounded-xl py-1.5 pr-8 pl-3 text-xs text-white placeholder-slate-500 outline-none"
              />
            </div>

            <select
              value={ledgerFilter}
              onChange={e => setLedgerFilter(e.target.value as any)}
              className="bg-[#18181C] border border-white/5 rounded-xl py-1.5 px-3 text-xs text-slate-300 outline-none"
            >
              <option value="all">جميع الأنواع</option>
              <option value="store">المتجر</option>
              <option value="special_id">آيديهات مميزة</option>
              <option value="vip">رتب VIP</option>
              <option value="badge">شارات</option>
              <option value="necklace">قلائد</option>
            </select>
          </div>
        </div>

        {/* Ledger Table */}
        <div className="overflow-x-auto">
          <table className="w-full text-right text-xs">
            <thead className="bg-[#18181C] text-slate-400 text-[11px] font-bold border-b border-white/5">
              <tr>
                <th className="py-3 px-4">المستخدم المهدى إليه</th>
                <th className="py-3 px-4">نوع الهدية</th>
                <th className="py-3 px-4">تفاصيل الهدية</th>
                <th className="py-3 px-4">تاريخ الإهداء</th>
                <th className="py-3 px-4">الانتهاء / الحالة</th>
                <th className="py-3 px-4 text-center">الإجراءات</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5 text-slate-300">
              {filteredLedger.length === 0 ? (
                <tr>
                  <td colSpan={6} className="py-12 text-center text-slate-500">
                    <Gift className="w-8 h-8 text-slate-700 mx-auto mb-2" />
                    <span>لا توجد هدايا مطابقة في السجل.</span>
                  </td>
                </tr>
              ) : (
                filteredLedger.map(gift => {
                  const now = Date.now();
                  const isExpired = gift.expires_at > 0 && gift.expires_at < now;
                  const isPermanent = !gift.expires_at || gift.expires_at === 0;
                  const daysLeft = !isPermanent && !isExpired ? Math.ceil((gift.expires_at - now) / 86400000) : 0;
                  const isRevoking = revokingId === gift.id;

                  return (
                    <tr key={gift.id} className="hover:bg-white/[0.02] transition-colors">
                      {/* User */}
                      <td className="py-3.5 px-4">
                        <div className="flex items-center gap-2.5">
                          <img
                            src={gift.user?.photo_url || 'https://ui-avatars.com/api/?name=U&background=6366f1&color=fff'}
                            alt=""
                            className="w-8 h-8 rounded-full object-cover border border-white/10"
                          />
                          <div>
                            <div className="font-bold text-white">{gift.user?.name || 'مستخدم'}</div>
                            <div className="text-[10px] text-slate-400 font-mono">
                              ID: {gift.user?.custom_id || gift.uid.slice(0, 8)}
                              {gift.user?.original_custom_id && (
                                <span className="mr-1 text-emerald-400"> (أصلي: {gift.user.original_custom_id})</span>
                              )}
                            </div>
                          </div>
                        </div>
                      </td>

                      {/* Gift Category Badge */}
                      <td className="py-3.5 px-4">
                        {gift.item_category === 'special_id' ? (
                          <span className="px-2 py-0.5 rounded-md bg-amber-500/10 text-amber-400 border border-amber-500/20 text-[10px] font-bold">
                            💎 آيدي مميز
                          </span>
                        ) : gift.item_category === 'vip' ? (
                          <span className="px-2 py-0.5 rounded-md bg-purple-500/10 text-purple-400 border border-purple-500/20 text-[10px] font-bold">
                            👑 VIP
                          </span>
                        ) : gift.item_category === 'badge' ? (
                          <span className="px-2 py-0.5 rounded-md bg-rose-500/10 text-rose-400 border border-rose-500/20 text-[10px] font-bold">
                            🏅 شارة
                          </span>
                        ) : gift.item_category === 'necklace' ? (
                          <span className="px-2 py-0.5 rounded-md bg-teal-500/10 text-teal-400 border border-teal-500/20 text-[10px] font-bold">
                            📿 قلادة
                          </span>
                        ) : (
                          <span className="px-2 py-0.5 rounded-md bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 text-[10px] font-bold">
                            🛍️ {gift.item_category}
                          </span>
                        )}
                      </td>

                      {/* Gift Details */}
                      <td className="py-3.5 px-4">
                        <div className="flex items-center gap-2">
                          {gift.item_icon && (
                            <img src={gift.item_icon} alt="" className="w-6 h-6 object-contain rounded bg-black/20" />
                          )}
                          <span className="font-semibold text-white">{gift.item_name}</span>
                        </div>
                      </td>

                      {/* Sent At */}
                      <td className="py-3.5 px-4 text-slate-400 text-[11px]">
                        <div>{new Date(gift.sent_at).toLocaleDateString('ar-EG')}</div>
                        <div className="text-[10px] text-slate-500">بواسطة: {gift.sent_by_name || 'الإدارة'}</div>
                      </td>

                      {/* Expiry & Status */}
                      <td className="py-3.5 px-4">
                        {isPermanent ? (
                          <span className="px-2 py-0.5 rounded-md bg-emerald-500/10 text-emerald-400 text-[11px] font-bold">
                            دائم ♾️
                          </span>
                        ) : isExpired ? (
                          <span className="px-2 py-0.5 rounded-md bg-rose-500/10 text-rose-400 text-[11px] font-bold">
                            منتهي الصلاحية
                          </span>
                        ) : (
                          <div className="space-y-0.5">
                            <span className="px-2 py-0.5 rounded-md bg-blue-500/10 text-blue-400 text-[11px] font-bold">
                              متبقي {daysLeft} يوم
                            </span>
                            <div className="text-[10px] text-slate-500">
                              ينتهي: {new Date(gift.expires_at).toLocaleDateString('ar-EG')}
                            </div>
                          </div>
                        )}
                      </td>

                      {/* Revoke Action */}
                      <td className="py-3.5 px-4 text-center">
                        <button
                          onClick={() => handleRevoke(gift)}
                          disabled={isRevoking}
                          className="px-2.5 py-1.5 rounded-xl bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 hover:text-rose-300 border border-rose-500/20 text-[11px] font-bold flex items-center justify-center gap-1 transition-all mx-auto"
                          title="سحب الهدية فوراً واسترجاع الحالة السابقة"
                        >
                          {isRevoking ? (
                            <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                          ) : (
                            <Trash2 className="w-3.5 h-3.5" />
                          )}
                          <span>سحب</span>
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
    </div>
  );
}
