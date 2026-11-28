import { useEffect, useState } from 'react';
import { LevelConfig, LevelType, BadgeConfig, StoreItemModel, LevelRewardItem } from '../types';
import { getLevels, updateLevel, getAppConfig, updateAppConfig, getBadges, getStoreItems } from '../lib/db';
import { uploadLevelImage } from '../lib/storage';
import DataTable from '../components/DataTable';
import ImageUpload from '../components/ImageUpload';
import { Save, X, Plus, Trash2, Upload, Gift, Sparkles, Coins, ShoppingBag, Award, Layers } from 'lucide-react';
import { to6Hex } from '../lib/colors';

const LEVEL_TYPES: LevelType[] = [
  { id: 'wealth', name: 'Wealth', icon: '💰', color: 'text-amber-400' },
  { id: 'recharge', name: 'Recharge', icon: '⚡', color: 'text-cyan-400' },
  { id: 'gems', name: 'Gems', icon: '💎', color: 'text-rose-400' },
];

export default function LevelsPage() {
  const [levels, setLevels] = useState<Record<string, LevelConfig[]>>({ wealth: [], recharge: [], gems: [] });
  const [badges, setBadges] = useState<BadgeConfig[]>([]);
  const [storeItems, setStoreItems] = useState<StoreItemModel[]>([]);
  const [activeType, setActiveType] = useState<'wealth' | 'recharge' | 'gems'>('wealth');
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<LevelConfig | null>(null);
  const [coinsPerXp, setCoinsPerXp] = useState(10);
  const [applyToRange, setApplyToRange] = useState(false);
  const [rangeFrom, setRangeFrom] = useState(1);
  const [rangeTo, setRangeTo] = useState(9);

  const [form, setForm] = useState<{
    title: string;
    minExp: number;
    maxExp: number;
    imageUrl: string;
    frameUrl: string;
    badgeUrl: string;
    boxImageUrl: string;
    progressColor: string;
    rewardItems: LevelRewardItem[];
  }>({
    title: '',
    minExp: 0,
    maxExp: 0,
    imageUrl: '',
    frameUrl: '',
    badgeUrl: '',
    boxImageUrl: '',
    progressColor: '',
    rewardItems: [],
  });

  const loadAll = async () => {
    try {
      const [wealth, recharge, gems, config, badgeList, sItems] = await Promise.all([
        getLevels('wealth'),
        getLevels('recharge'),
        getLevels('gems'),
        getAppConfig(),
        getBadges(),
        getStoreItems().catch(() => []),
      ]);
      setLevels({ wealth, recharge, gems });
      setBadges(badgeList || []);
      setStoreItems(sItems || []);
      if (config?.coinsPerRechargeXp) setCoinsPerXp(config.coinsPerRechargeXp);
    } catch (err) {
      console.error('Failed to load levels:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadAll();
  }, []);

  const resetForm = () => {
    setForm({
      title: '',
      minExp: 0,
      maxExp: 0,
      imageUrl: '',
      frameUrl: '',
      badgeUrl: '',
      boxImageUrl: '',
      progressColor: '',
      rewardItems: [],
    });
  };

  const handleEdit = (l: LevelConfig) => {
    setEditing(l);

    // بناء قائمة المكافآت ديناميكياً
    const items: LevelRewardItem[] = [];
    const rawItems = (l.rewards?.items || l.rewards?.privileges || []) as LevelRewardItem[];

    if (Array.isArray(rawItems) && rawItems.length > 0) {
      items.push(...rawItems);
    } else {
      // التوافق مع البيانات القديمة
      if (l.rewards?.coins && l.rewards.coins > 0) {
        items.push({
          id: 'c_' + Date.now(),
          type: 'coins',
          title: 'مكافأة كوينز',
          subtitle: `${l.rewards.coins} كوينز عند الوصول للمستوى`,
          amount: l.rewards.coins,
          icon: '',
        });
      }
      if (l.rewards?.diamonds && l.rewards.diamonds > 0) {
        items.push({
          id: 'd_' + Date.now(),
          type: 'diamonds',
          title: 'مكافأة ألماس',
          subtitle: `${l.rewards.diamonds} ألماسة عند الوصول للمستوى`,
          amount: l.rewards.diamonds,
          icon: '',
        });
      }
      if (l.rewards?.frame) {
        items.push({
          id: 'f_' + Date.now(),
          type: 'frame',
          title: 'إطار المستوى',
          subtitle: 'إطار ملف شخصي حصري',
          icon: l.frameUrl || '',
          itemId: l.rewards.frame,
        });
      }
      if (l.rewards?.badge) {
        items.push({
          id: 'b_' + Date.now(),
          type: 'badge',
          title: 'شارة المستوى',
          subtitle: 'وسام شرف المستوى',
          icon: l.badgeUrl || '',
          itemId: l.rewards.badge,
        });
      }
    }

    const tierBase = Math.floor(l.level / 10) * 10;
    const defFrom = l.level < 10 ? 1 : tierBase;
    const defTo = l.level < 10 ? 9 : (l.level >= 100 ? 100 : tierBase + 9);
    setRangeFrom(defFrom);
    setRangeTo(defTo);
    setApplyToRange(false);

    setForm({
      title: l.title || `Level ${l.level}`,
      minExp: l.minExp || 0,
      maxExp: l.maxExp || 1000,
      imageUrl: l.imageUrl || '',
      frameUrl: l.frameUrl || '',
      badgeUrl: l.badgeUrl || '',
      boxImageUrl: l.boxImageUrl || '',
      progressColor: l.progressColor || '',
      rewardItems: items,
    });
  };

  const handleAddReward = () => {
    const newItem: LevelRewardItem = {
      id: 'rew_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7),
      type: 'store_item',
      title: 'مأثر دخول جديد',
      subtitle: 'يُرسل لحقيبة المستخدم فوراً عند الترقية',
      icon: '',
      amount: 1,
    };
    setForm(prev => ({
      ...prev,
      rewardItems: [...prev.rewardItems, newItem],
    }));
  };

  const handleRemoveReward = (index: number) => {
    setForm(prev => ({
      ...prev,
      rewardItems: prev.rewardItems.filter((_, i) => i !== index),
    }));
  };

  const handleUpdateReward = (index: number, updates: Partial<LevelRewardItem>) => {
    setForm(prev => {
      const next = [...prev.rewardItems];
      next[index] = { ...next[index], ...updates };
      return { ...prev, rewardItems: next };
    });
  };

  const handleRewardTypeChange = (index: number, type: LevelRewardItem['type']) => {
    let title = 'مكافأة جديدة';
    let subtitle = 'مكافأة المستوى';
    let icon = '';
    let amount = 0;

    if (type === 'coins') {
      title = 'مكافأة كوينز';
      subtitle = 'عملات ذهبية هدية الترقية';
      amount = 500;
    } else if (type === 'diamonds') {
      title = 'مكافأة ألماس';
      subtitle = 'ألماس هدية الترقية';
      amount = 100;
    } else if (type === 'store_item') {
      title = 'مأثر الدخول';
      subtitle = 'عنصر مميز يُرسل للحقيبة';
    } else if (type === 'badge') {
      title = 'شارة الشرف';
      subtitle = 'شارة حصرية للمستوى';
    } else if (type === 'frame') {
      title = 'إطار ملكي';
      subtitle = 'إطار فاخر للبروفايل';
      icon = form.frameUrl || '';
    } else if (type === 'custom') {
      title = 'ميزة إضافية';
      subtitle = 'صلاحية خاصة في الغرفة';
    }

    handleUpdateReward(index, { type, title, subtitle, icon, amount });
  };

  const handleStoreItemSelect = (index: number, itemId: string) => {
    const item = storeItems.find(s => s.itemId === itemId);
    if (!item) return;

    handleUpdateReward(index, {
      itemId: item.itemId,
      title: item.name,
      subtitle: item.category ? `عنصر ${item.category} يُرسل للحقيبة` : 'عنصر يُرسل للحقيبة',
      icon: item.iconAsset || item.svgaAsset || '',
    });
  };

  const handleBadgeSelect = (index: number, badgeId: string) => {
    const badge = badges.find(b => b.id === badgeId);
    if (!badge) return;

    handleUpdateReward(index, {
      itemId: badge.id,
      title: badge.name,
      subtitle: 'وسام شرف يُمنح عند الترقية',
      icon: badge.iconAsset || '',
    });
  };

  const handleSave = async () => {
    if (!editing) return;
    try {
      // استخراج الكوينز والألماس الإجمالي
      let totalCoins = 0;
      let totalDiamonds = 0;
      let frameId = '';
      let badgeId = '';

      form.rewardItems.forEach(item => {
        if (item.type === 'coins' && item.amount) {
          totalCoins += Number(item.amount);
        } else if (item.type === 'diamonds' && item.amount) {
          totalDiamonds += Number(item.amount);
        } else if (item.type === 'frame' && item.itemId) {
          frameId = item.itemId;
        } else if (item.type === 'badge' && item.itemId) {
          badgeId = item.itemId;
        }
      });

      const rewards: Record<string, unknown> = {
        items: form.rewardItems,
        privileges: form.rewardItems,
      };
      if (totalCoins > 0) rewards.coins = totalCoins;
      if (totalDiamonds > 0) rewards.diamonds = totalDiamonds;
      if (frameId) rewards.frame = frameId;
      if (badgeId) rewards.badge = badgeId;

      if (applyToRange && rangeFrom <= rangeTo) {
        // تطبيق الشارة والصور والإعدادات على جميع المستويات ضمن النطاق المحدد (مثلاً 40 إلى 49)
        for (let lvl = rangeFrom; lvl <= rangeTo; lvl++) {
          const existingLevel = levels[activeType].find(x => x.level === lvl);
          await updateLevel(activeType, lvl, {
            title: existingLevel?.title || `Level ${lvl}`,
            minExp: existingLevel?.minExp ?? (lvl * 1000),
            maxExp: existingLevel?.maxExp ?? ((lvl + 1) * 1000),
            type: activeType,
            imageUrl: form.imageUrl || existingLevel?.imageUrl || null,
            frameUrl: form.frameUrl || existingLevel?.frameUrl || null,
            badgeUrl: form.badgeUrl || null,
            progressColor: form.progressColor || existingLevel?.progressColor || null,
            boxImageUrl: form.boxImageUrl || existingLevel?.boxImageUrl || null,
            rewards,
          });
        }
      } else {
        await updateLevel(activeType, editing.level, {
          title: form.title,
          minExp: form.minExp,
          maxExp: form.maxExp,
          type: activeType,
          imageUrl: form.imageUrl || null,
          frameUrl: form.frameUrl || null,
          badgeUrl: form.badgeUrl || null,
          progressColor: form.progressColor || null,
          boxImageUrl: form.boxImageUrl || null,
          rewards,
        });
      }

      setEditing(null);
      resetForm();
      await loadAll();
    } catch (err) {
      alert('فشل الحفظ: ' + (err as Error).message);
    }
  };

  const handleAddNew = async () => {
    try {
      const list = levels[activeType];
      const lastLevel = list.length > 0 ? Math.max(...list.map(l => l.level)) : 0;
      const newLevel = lastLevel + 1;
      await updateLevel(activeType, newLevel, {
        level: newLevel,
        type: activeType,
        title: `Level ${newLevel}`,
        minExp: newLevel * 1000,
        maxExp: (newLevel + 1) * 1000,
        rewards: {},
      });
      await loadAll();
    } catch (err) {
      alert('فشل الإضافة: ' + (err as Error).message);
    }
  };

  const handleCoinsPerXpSave = async () => {
    await updateAppConfig({ coinsPerRechargeXp: coinsPerXp });
    alert('تم حفظ إعداد النقاط بنجاح');
  };

  const typeIcon = (id: string) => {
    const t = LEVEL_TYPES.find(t => t.id === id);
    return t ? `${t.icon} ${t.name}` : id;
  };

  return (
    <div className="space-y-6">
      {/* Top Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-white text-lg font-semibold">إدارة نظام المستويات والمكافآت (Level System)</h2>
          <p className="text-slate-500 text-xs mt-0.5">
            {levels[activeType].length} مستوى في تصنيف {activeType}
          </p>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={handleAddNew}
            className="px-3.5 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1.5 shadow-lg shadow-indigo-600/20"
          >
            <Plus className="w-3.5 h-3.5" /> إضافة مستوى جديد
          </button>
        </div>
      </div>

      {/* Level Type Tabs */}
      <div className="flex gap-2">
        {LEVEL_TYPES.map(t => (
          <button
            key={t.id}
            onClick={() => {
              setActiveType(t.id);
              setEditing(null);
            }}
            className={`px-4 py-2 rounded-lg text-xs font-semibold transition-all flex items-center gap-2 ${
              activeType === t.id
                ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-600/20'
                : 'bg-[#141417] text-slate-400 hover:text-white'
            }`}
          >
            <span>{t.icon}</span> {t.name}
          </button>
        ))}
      </div>

      {/* Coins Per Recharge XP Config */}
      <div className="bg-[#141417] rounded-2xl border border-cyan-500/20 p-4 flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <span className="text-xs text-slate-300 font-bold">معدل تحويل الكوينز لكل نقطة شحن (Coins per XP):</span>
          <input
            type="number"
            value={coinsPerXp}
            onChange={e => setCoinsPerXp(Number(e.target.value))}
            className="w-24 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
          />
        </div>
        <button
          onClick={handleCoinsPerXpSave}
          className="px-3 py-1.5 bg-cyan-600 hover:bg-cyan-700 text-xs text-white font-semibold rounded-lg"
        >
          حفظ الإعداد
        </button>
      </div>

      {/* Edit Form Modal/Panel */}
      {editing && (
        <div className="bg-[#141417] rounded-2xl border border-indigo-500/30 p-6 space-y-6 shadow-2xl">
          {/* Header */}
          <div className="flex items-center justify-between pb-3 border-b border-white/10">
            <div className="flex items-center gap-2">
              <span className="text-base">{typeIcon(activeType)}</span>
              <h3 className="text-white font-bold text-sm">
                تعديل إعدادات المستوى {editing.level} ({editing.title})
              </h3>
            </div>
            <button
              onClick={() => {
                setEditing(null);
                resetForm();
              }}
              className="text-slate-400 hover:text-white p-1 rounded-lg hover:bg-white/5"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Basic Info */}
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div>
              <label className="block text-[11px] uppercase text-slate-400 font-bold mb-1.5">عنوان المستوى (Title)</label>
              <input
                type="text"
                value={form.title}
                onChange={e => setForm(p => ({ ...p, title: e.target.value }))}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white focus:border-indigo-500 outline-none"
              />
            </div>
            <div>
              <label className="block text-[11px] uppercase text-slate-400 font-bold mb-1.5">أدنى نقاط (Min EXP)</label>
              <input
                type="number"
                value={form.minExp}
                onChange={e => setForm(p => ({ ...p, minExp: Number(e.target.value) }))}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white focus:border-indigo-500 outline-none"
              />
            </div>
            <div>
              <label className="block text-[11px] uppercase text-slate-400 font-bold mb-1.5">أقصى نقاط (Max EXP)</label>
              <input
                type="number"
                value={form.maxExp}
                onChange={e => setForm(p => ({ ...p, maxExp: Number(e.target.value) }))}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white focus:border-indigo-500 outline-none"
              />
            </div>
            <div>
              <label className="block text-[11px] uppercase text-amber-400 font-bold mb-1.5">لون شريط التقدم (Color)</label>
              <div className="flex gap-2 items-center">
                <input
                  type="color"
                  value={to6Hex(form.progressColor || '#DE880F')}
                  onChange={e => setForm(p => ({ ...p, progressColor: e.target.value }))}
                  className="w-10 h-8 rounded border border-white/10 bg-transparent cursor-pointer"
                />
                <input
                  type="text"
                  value={form.progressColor}
                  onChange={e => setForm(p => ({ ...p, progressColor: e.target.value }))}
                  className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono"
                  placeholder="#DE880F"
                />
              </div>
            </div>
          </div>

          {/* الشريط المخصص للصور والشارات (Level Image & Badge) */}
          <div className="bg-[#18181c] rounded-xl p-4 border border-white/5 space-y-3">
            <div className="flex items-center gap-2 text-slate-300 text-xs font-bold pb-2 border-b border-white/5">
              <Layers className="w-4 h-4 text-indigo-400" />
              <span>صور ووسام المستوى (Level Visuals & Badges)</span>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4">
              {/* صورة المستوى للبروفايل */}
              <div className="bg-[#131316] p-3 rounded-lg border border-white/5">
                <ImageUpload
                  currentUrl={form.imageUrl}
                  onUpload={file => uploadLevelImage(file, activeType, editing.level)}
                  onUrlChange={url => setForm(p => ({ ...p, imageUrl: url }))}
                  label="صورة المستوى (Level Image)"
                />
                <p className="text-[10px] text-slate-400 mt-1">تظهر في كروت شاشة المستوى والملف الشخصي</p>
              </div>

              {/* شارة ووسام المستوى فوق المنصة */}
              <div className="bg-[#131316] p-3 rounded-lg border border-indigo-500/20">
                <ImageUpload
                  currentUrl={form.badgeUrl}
                  onUpload={file => uploadLevelImage(file, `${activeType}_badge`, editing.level)}
                  onUrlChange={url => setForm(p => ({ ...p, badgeUrl: url }))}
                  label="شارة ووسام المستوى (Level Badge)"
                  accept=".webp,.png,.svga"
                />
                <p className="text-[10px] text-indigo-300 mt-1">تظهر فوق المنصة 3D في شاشة المستويات</p>
              </div>

              {/* إطار المستوى SVGA */}
              <div className="bg-[#131316] p-3 rounded-lg border border-white/5">
                <ImageUpload
                  currentUrl={form.frameUrl}
                  onUpload={file => uploadLevelImage(file, `${activeType}_frame`, editing.level)}
                  onUrlChange={url => setForm(p => ({ ...p, frameUrl: url }))}
                  label="إطار الملف الشخصي (Frame)"
                  accept=".svga,.webp,.png,.mp4,.vap"
                />
                <p className="text-[10px] text-slate-400 mt-1">إطار SVGA يُمنح للمستخدم</p>
              </div>

              {/* خلفية الصندوق */}
              <div className="bg-[#131316] p-3 rounded-lg border border-white/5">
                <ImageUpload
                  currentUrl={form.boxImageUrl}
                  onUpload={file => uploadLevelImage(file, `${activeType}_box`, editing.level)}
                  onUrlChange={url => setForm(p => ({ ...p, boxImageUrl: url }))}
                  label="خلفية الصندوق (Box BG)"
                  accept=".webp,.png,.jpg"
                />
                <p className="text-[10px] text-slate-400 mt-1">خلفية الكرت الخاص بالمستوى</p>
              </div>
            </div>

            {/* ميزة تطبيق الشارة والصور على نطاق كامل (مثلاً: من 40 إلى 49) */}
            <div className="bg-[#121215] border border-indigo-500/30 rounded-xl p-3.5 space-y-2.5">
              <div className="flex items-center justify-between">
                <label className="flex items-center gap-2.5 cursor-pointer text-xs font-bold text-indigo-300">
                  <input
                    type="checkbox"
                    checked={applyToRange}
                    onChange={e => setApplyToRange(e.target.checked)}
                    className="w-4 h-4 rounded text-indigo-600 focus:ring-0 bg-[#161618] border-white/20 cursor-pointer"
                  />
                  <span>تطبيق هذه الشارة/الوسام على فئة المستويات كاملة (مثلاً: من 40 إلى 49)</span>
                </label>
                {applyToRange && (
                  <button
                    type="button"
                    onClick={() => {
                      const tierBase = Math.floor(editing.level / 10) * 10;
                      const defFrom = editing.level < 10 ? 1 : tierBase;
                      const defTo = editing.level < 10 ? 9 : (editing.level >= 100 ? 100 : tierBase + 9);
                      setRangeFrom(defFrom);
                      setRangeTo(defTo);
                    }}
                    className="px-2.5 py-1 bg-indigo-600/40 hover:bg-indigo-600 text-[11px] text-white rounded-md transition-colors"
                  >
                    تحديد فئة المستوى تلقائياً
                  </button>
                )}
              </div>

              {applyToRange && (
                <div className="flex flex-wrap items-center gap-3 pt-1 text-xs">
                  <span className="text-slate-400">من المستوى:</span>
                  <input
                    type="number"
                    value={rangeFrom}
                    onChange={e => setRangeFrom(Number(e.target.value))}
                    className="w-16 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-white text-center font-bold"
                  />
                  <span className="text-slate-400">إلى المستوى:</span>
                  <input
                    type="number"
                    value={rangeTo}
                    onChange={e => setRangeTo(Number(e.target.value))}
                    className="w-16 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-white text-center font-bold"
                  />
                  <span className="text-[11px] text-emerald-400 font-semibold">
                    ✓ سيتم حفظ الشارة والوسام والصور لجميع المستويات الـ 9 الأخرى في الفئة ({rangeFrom} إلى {rangeTo}) بضغطة واحدة
                  </span>
                </div>
              )}
            </div>
          </div>

          {/* قسم مكافآت المستوى الديناميكية (Add & Manage Rewards) */}
          <div className="bg-[#18181c] rounded-xl p-4 border border-white/5 space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-white/5">
              <div className="flex items-center gap-2">
                <Gift className="w-4 h-4 text-emerald-400" />
                <span className="text-xs font-bold text-white">مكافآت الترقية للمستوى (تُرسل للحقيبة وتظهر في قوالب الشاشة)</span>
                <span className="text-[11px] text-slate-500">({form.rewardItems.length} مكافأة)</span>
              </div>
              <button
                type="button"
                onClick={handleAddReward}
                className="px-3 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1.5 shadow-md shadow-emerald-600/20"
              >
                <Plus className="w-3.5 h-3.5" /> إضافة مكافأة للمستوى
              </button>
            </div>

            {form.rewardItems.length === 0 ? (
              <div className="text-center py-6 border border-dashed border-white/10 rounded-lg">
                <Gift className="w-8 h-8 text-slate-600 mx-auto mb-2" />
                <p className="text-xs text-slate-400">لا توجد مكافآت مضافة لهذا المستوى حتى الآن.</p>
                <button
                  type="button"
                  onClick={handleAddReward}
                  className="mt-2 text-xs text-emerald-400 hover:underline inline-flex items-center gap-1"
                >
                  <Plus className="w-3 h-3" /> اضغط هنا لإضافة أول مكافأة (متجر، كوينز، شارة...)
                </button>
              </div>
            ) : (
              <div className="space-y-3">
                {form.rewardItems.map((rew, idx) => (
                  <div
                    key={rew.id || idx}
                    className="bg-[#121215] border border-white/10 rounded-xl p-3.5 flex flex-col md:flex-row gap-3 items-start md:items-center justify-between"
                  >
                    {/* نوع المكافأة */}
                    <div className="w-full md:w-36">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">نوع المكافأة</label>
                      <select
                        value={rew.type}
                        onChange={e => handleRewardTypeChange(idx, e.target.value as LevelRewardItem['type'])}
                        className="w-full bg-[#18181c] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                      >
                        <option value="store_item">🛍️ عنصر من المتجر</option>
                        <option value="coins">💰 عملات كوينز</option>
                        <option value="diamonds">💎 ألماس</option>
                        <option value="badge">🎖️ شارة خاصة</option>
                        <option value="frame">🖼️ إطار مخصص</option>
                        <option value="custom">✨ ميزة / مخصص</option>
                      </select>
                    </div>

                    {/* إذا كان عنصر متجر: قائمة اختيار العنصر */}
                    {rew.type === 'store_item' && (
                      <div className="w-full md:w-48">
                        <label className="block text-[10px] uppercase text-emerald-400 font-bold mb-1">اختر من المتجر</label>
                        <select
                          value={rew.itemId || ''}
                          onChange={e => handleStoreItemSelect(idx, e.target.value)}
                          className="w-full bg-[#18181c] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white truncate"
                        >
                          <option value="">-- اختر عنصر --</option>
                          {storeItems.map(s => (
                            <option key={s.itemId} value={s.itemId}>
                              {s.name} ({s.category || 'عام'})
                            </option>
                          ))}
                        </select>
                      </div>
                    )}

                    {/* إذا كان شارة: قائمة اختيار الشارة */}
                    {rew.type === 'badge' && (
                      <div className="w-full md:w-48">
                        <label className="block text-[10px] uppercase text-amber-400 font-bold mb-1">اختر الشارة</label>
                        <select
                          value={rew.itemId || ''}
                          onChange={e => handleBadgeSelect(idx, e.target.value)}
                          className="w-full bg-[#18181c] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white truncate"
                        >
                          <option value="">-- اختر شارة --</option>
                          {badges.map(b => (
                            <option key={b.id} value={b.id}>
                              {b.name}
                            </option>
                          ))}
                        </select>
                      </div>
                    )}

                    {/* إذا كان كوينز أو ألماس: الكمية */}
                    {(rew.type === 'coins' || rew.type === 'diamonds') && (
                      <div className="w-full md:w-28">
                        <label className="block text-[10px] uppercase text-amber-400 font-bold mb-1">الكمية</label>
                        <input
                          type="number"
                          value={rew.amount || 0}
                          onChange={e => handleUpdateReward(idx, { amount: Number(e.target.value) })}
                          className="w-full bg-[#18181c] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                        />
                      </div>
                    )}

                    {/* عنوان المكافأة (الذي يظهر في القالب في شاشة التطبيق) */}
                    <div className="flex-1 w-full">
                      <label className="block text-[10px] uppercase text-slate-300 font-bold mb-1">
                        تسمية المكافأة (تظهر في كرت المستوى)
                      </label>
                      <input
                        type="text"
                        value={rew.title}
                        onChange={e => handleUpdateReward(idx, { title: e.target.value })}
                        placeholder="مثل: مأثر الدخول الأسطوري"
                        className="w-full bg-[#18181c] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                      />
                    </div>

                    {/* الوصف */}
                    <div className="w-full md:w-44">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">الوصف الفرعي</label>
                      <input
                        type="text"
                        value={rew.subtitle || ''}
                        onChange={e => handleUpdateReward(idx, { subtitle: e.target.value })}
                        placeholder="صالحة لمدة 7 أيام"
                        className="w-full bg-[#18181c] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                      />
                    </div>

                    {/* صورة أو أيقونة المكافأة */}
                    <div className="w-full md:w-56">
                      <div className="flex items-center justify-between mb-1">
                        <label className="block text-[10px] uppercase text-slate-400 font-bold">صورة / أيقونة المكافأة</label>
                        <label className="cursor-pointer text-[10px] font-semibold text-indigo-400 hover:text-indigo-300 flex items-center gap-1 bg-indigo-500/10 hover:bg-indigo-500/20 px-2 py-0.5 rounded border border-indigo-500/20 transition-all">
                          <Upload className="w-3 h-3" />
                          <span>رفع من الجهاز</span>
                          <input
                            type="file"
                            accept="image/*,.svga,.webp,.png,.jpg,.jpeg,.gif"
                            className="hidden"
                            onChange={async (e) => {
                              const file = e.target.files?.[0];
                              if (!file) return;
                              try {
                                const url = await uploadLevelImage(file, 'reward_icon', editing.level);
                                handleUpdateReward(idx, { icon: url });
                              } catch (err) {
                                alert('فشل رفع الصورة: ' + (err as Error).message);
                              }
                            }}
                          />
                        </label>
                      </div>
                      <input
                        type="text"
                        value={rew.icon || ''}
                        onChange={e => handleUpdateReward(idx, { icon: e.target.value })}
                        placeholder="رابط الصورة أو ارفع من الجهاز 📁"
                        className="w-full bg-[#18181c] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono text-[10px]"
                      />
                    </div>

                    {/* معاينة وزر الحذف */}
                    <div className="flex items-center gap-2 pt-2 md:pt-4 self-end md:self-center">
                      {rew.icon ? (
                        <img
                          src={rew.icon}
                          className="w-8 h-8 rounded object-contain bg-black/40 border border-white/10 p-0.5"
                          onError={e => {
                            (e.target as HTMLImageElement).style.display = 'none';
                          }}
                        />
                      ) : (
                        <div className="w-8 h-8 rounded bg-white/5 border border-white/10 flex items-center justify-center text-xs">
                          {rew.type === 'coins' ? '💰' : rew.type === 'diamonds' ? '💎' : '✨'}
                        </div>
                      )}
                      <button
                        type="button"
                        onClick={() => handleRemoveReward(idx)}
                        className="p-1.5 text-rose-400 hover:text-rose-300 hover:bg-rose-500/10 rounded-lg transition-colors"
                        title="حذف المكافأة"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Action Buttons */}
          <div className="flex gap-2 pt-2">
            <button
              onClick={handleSave}
              className="px-5 py-2 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1.5 shadow-lg shadow-emerald-600/20"
            >
              <Save className="w-4 h-4" /> حفظ التعديلات للمستوى
            </button>
            <button
              onClick={() => {
                setEditing(null);
                resetForm();
              }}
              className="px-4 py-2 border border-white/10 text-xs text-slate-400 hover:text-white rounded-lg hover:bg-white/5"
            >
              إلغاء
            </button>
          </div>
        </div>
      )}

      {/* Levels Table */}
      <DataTable
        loading={loading}
        columns={[
          { key: 'level', label: 'المستوى', sortable: true, width: '70px' },
          {
            key: 'imageUrl',
            label: 'صورة المستوى',
            width: '90px',
            render: (l: LevelConfig) =>
              l.imageUrl ? (
                <img
                  src={l.imageUrl}
                  className="w-8 h-8 object-contain rounded"
                  onError={e => {
                    (e.target as HTMLImageElement).style.display = 'none';
                  }}
                />
              ) : (
                <div className="w-8 h-8 rounded bg-slate-800 flex items-center justify-center text-xs text-slate-600">-</div>
              ),
          },
          {
            key: 'badgeUrl',
            label: 'الشارة والوسام',
            width: '90px',
            render: (l: LevelConfig) =>
              l.badgeUrl ? (
                <img
                  src={l.badgeUrl}
                  className="w-8 h-8 object-contain rounded"
                  onError={e => {
                    (e.target as HTMLImageElement).style.display = 'none';
                  }}
                />
              ) : (
                <div className="w-8 h-8 rounded bg-slate-800 flex items-center justify-center text-xs text-slate-600">-</div>
              ),
          },
          { key: 'title', label: 'العنوان', sortable: true },
          { key: 'minExp', label: 'أدنى نقاط (Min EXP)', sortable: true },
          { key: 'maxExp', label: 'أقصى نقاط (Max EXP)', sortable: true },
          {
            key: 'rewards',
            label: 'المكافآت المحددة',
            render: (l: LevelConfig) => {
              const r = l.rewards;
              if (!r) return <span className="text-slate-600 text-[10px]">لا توجد مكافآت</span>;
              const rawItems = (r.items || r.privileges) as LevelRewardItem[] | undefined;
              if (Array.isArray(rawItems) && rawItems.length > 0) {
                return (
                  <div className="flex flex-wrap gap-1">
                    {rawItems.map((it, i) => (
                      <span
                        key={i}
                        className="px-2 py-0.5 rounded text-[10px] font-medium bg-indigo-500/10 text-indigo-300 border border-indigo-500/20"
                      >
                        {it.title || (it.type === 'diamonds' ? `💎 ${it.amount} ألماس` : it.type)}
                      </span>
                    ))}
                  </div>
                );
              }
              const parts: string[] = [];
              if (r.diamonds) parts.push(`💎 ${r.diamonds} ألماس`);
              if (r.frame) parts.push(`🖼️ إطار`);
              if (r.badge) parts.push(`🎖️ شارة`);
              return parts.length ? (
                <div className="flex flex-wrap gap-1">
                  {parts.map((p, i) => (
                    <span key={i} className="px-2 py-0.5 rounded text-[10px] bg-amber-500/10 text-amber-300 border border-amber-500/20">
                      {p}
                    </span>
                  ))}
                </div>
              ) : <span className="text-slate-600 text-[10px]">لا توجد مكافآت</span>;
            },
          },
          {
            key: 'frameUrl',
            label: 'الإطار',
            width: '70px',
            render: (l: LevelConfig) =>
              l.frameUrl ? (
                <img
                  src={l.frameUrl}
                  className="w-8 h-8 object-contain rounded"
                  onError={e => {
                    (e.target as HTMLImageElement).style.display = 'none';
                  }}
                />
              ) : (
                '-'
              ),
          },
        ]}
        data={levels[activeType]}
        onEdit={handleEdit}
        searchKeys={['title']}
      />
    </div>
  );
}
