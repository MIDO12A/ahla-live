import { useEffect, useState } from 'react';
import { BannerConfig } from '../types';
import { supabase } from '../lib/supabase';
import { uploadBanner, uploadSplash } from '../lib/storage';
import { getAppConfig, updateAppConfig } from '../lib/db';
import ImageUpload from '../components/ImageUpload';
import { Plus, Save, X, Trash2, Layers, Sparkles, Smartphone, CheckCircle2, ArrowRight } from 'lucide-react';

const SCREEN_ACTIONS = [
  { value: 'none', label: 'بدون إجراء (عرض فقط)' },
  { value: '/recharge_event', label: '⚡ حدث الشحن الملكي الأسطوري (Recharge Event)' },
  { value: '/mall', label: '🛍️ المتجر العام (Store / Mall)' },
  { value: '/cp_ranking', label: '🏆 مساحة الترتيب والمكافآت (CP Ranking & Rewards)' },
  { value: '/cp_space', label: '💑 مساحة الـ CP والارتباط (CP Space)' },
  { value: '/vip', label: '👑 متجر وباقات الـ VIP' },
  { value: '/wallet', label: '💰 المحفظة والشحن (Wallet)' },
  { value: '/tasks', label: '📋 المهام اليومية (Daily Tasks)' },
  { value: '/levels', label: '⭐ المستويات والرتب (Levels)' },
  { value: '/signin', label: '📅 تسجيل الدخول الأسبوعي (Sign-in)' },
  { value: '/agency', label: '🏢 مركز الوكالة والمضيفين (Agency)' },
  { value: '/rank', label: '🏆 لوحة الترتيب العام (Leaderboard)' },
  { value: '/backpack', label: '🎒 حقيبة المستخدم (Backpack)' },
  { value: 'room', label: '🎙️ دخول غرفة محددة (Specific Room ID)' },
  { value: 'url', label: '🌐 فتح رابط خارجي (Web URL)' },
];

export default function BannersPage() {
  const [activeTab, setActiveTab] = useState<'banners' | 'splash'>('banners');

  // ── Banners State ──
  const [banners, setBanners] = useState<BannerConfig[]>([]);
  const [loadingBanners, setLoadingBanners] = useState(true);
  const [editingBanner, setEditingBanner] = useState<BannerConfig | null>(null);
  const [showAddBanner, setShowAddBanner] = useState(false);
  const [bannerForm, setBannerForm] = useState({
    imageUrl: '',
    title: '',
    sortOrder: 0,
    active: true,
    actionType: 'none',
    actionValue: '',
  });

  // ── Splash Screen State ──
  const [loadingSplash, setLoadingSplash] = useState(true);
  const [splashSaved, setSplashSaved] = useState(false);
  const [splashForm, setSplashForm] = useState({
    enabled: true,
    imageUrl: '',
    svgaUrl: '',
    durationSeconds: 3,
    actionType: 'none',
    actionValue: '',
  });

  // Load Banners
  const loadBanners = async () => {
    const { data } = await supabase.from('banners').select('*').order('sort_order');
    const toCamel = (r: Record<string, unknown>): Record<string, unknown> => {
      const c: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(r)) {
        c[k.replace(/_([a-z])/g, (_, ch) => ch.toUpperCase())] = v;
      }
      return c;
    };
    const list = (data ?? []).map(r => toCamel(r) as unknown as BannerConfig);
    list.sort((a, b) => a.sortOrder - b.sortOrder);
    setBanners(list);
    setLoadingBanners(false);
  };

  // Load Splash from app_config
  const loadSplash = async () => {
    setLoadingSplash(true);
    const cfg = await getAppConfig();
    if (cfg) {
      const raw = cfg as unknown as Record<string, unknown>;
      setSplashForm({
        enabled: raw.splash_enabled === true || raw.splash_enabled === 'true' || raw.splashEnabled === true,
        imageUrl: (raw.splash_image_url as string) || (raw.splashImageUrl as string) || (raw.splashGifUrl as string) || '',
        svgaUrl: (raw.splash_svga_url as string) || (raw.splashSvgaUrl as string) || '',
        durationSeconds: Number(raw.splash_duration_seconds || raw.splashDurationSeconds || 3),
        actionType: (raw.splash_action_type as string) || (raw.splashActionType as string) || 'none',
        actionValue: (raw.splash_action_value as string) || (raw.splashActionValue as string) || '',
      });
    }
    setLoadingSplash(false);
  };

  useEffect(() => {
    loadBanners();
    loadSplash();
  }, []);

  useEffect(() => {
    const sub = supabase.channel('banners').on('postgres_changes',
      { event: '*', schema: 'public', table: 'banners' }, () => { loadBanners(); }
    ).subscribe();
    return () => { supabase.removeChannel(sub); };
  }, []);

  // ── Banners Helpers ──
  const resetBannerForm = () => {
    setBannerForm({
      imageUrl: '',
      title: '',
      sortOrder: banners.length,
      active: true,
      actionType: 'none',
      actionValue: '',
    });
  };

  const handleEditBanner = (b: BannerConfig) => {
    setEditingBanner(b);
    let resolvedType = b.actionType || 'none';
    let resolvedVal = b.actionValue || '';

    if (!b.actionType && b.linkUrl) {
      if (b.linkUrl.startsWith('http')) {
        resolvedType = 'url';
        resolvedVal = b.linkUrl;
      } else if (b.linkUrl.startsWith('room:') || /^\d+$/.test(b.linkUrl)) {
        resolvedType = 'room';
        resolvedVal = b.linkUrl.replace('room:', '');
      } else {
        resolvedType = b.linkUrl;
        resolvedVal = b.linkUrl;
      }
    }

    setBannerForm({
      imageUrl: b.imageUrl,
      title: b.title || '',
      sortOrder: b.sortOrder,
      active: b.active,
      actionType: resolvedType,
      actionValue: resolvedVal,
    });
    setShowAddBanner(false);
  };

  const getEffectiveLink = (actionType: string, actionValue: string) => {
    if (actionType === 'none') return '';
    if (actionType === 'room') return `room:${actionValue.trim()}`;
    if (actionType === 'url') return actionValue.trim();
    return actionType;
  };

  const handleSaveBanner = async () => {
    if (!editingBanner) return;
    const effectiveLink = getEffectiveLink(bannerForm.actionType, bannerForm.actionValue);

    await supabase.from('banners').update({
      image_url: bannerForm.imageUrl,
      link_url: effectiveLink,
      action_type: bannerForm.actionType,
      action_value: bannerForm.actionValue,
      title: bannerForm.title,
      sort_order: bannerForm.sortOrder,
      active: bannerForm.active,
    }).eq('id', editingBanner.id);

    setEditingBanner(null);
    resetBannerForm();
    loadBanners();
  };

  const handleAddBanner = async () => {
    const id = `banner_${Date.now()}`;
    const effectiveLink = getEffectiveLink(bannerForm.actionType, bannerForm.actionValue);

    await supabase.from('banners').insert({
      id,
      image_url: bannerForm.imageUrl,
      link_url: effectiveLink,
      action_type: bannerForm.actionType,
      action_value: bannerForm.actionValue,
      title: bannerForm.title,
      sort_order: bannerForm.sortOrder,
      active: bannerForm.active,
    });

    setShowAddBanner(false);
    resetBannerForm();
    loadBanners();
  };

  const handleDeleteBanner = async (b: BannerConfig) => {
    if (confirm(`هل أنت متأكد من حذف البنر "${b.title || b.id}"؟`)) {
      await supabase.from('banners').delete().eq('id', b.id);
      loadBanners();
    }
  };

  // ── Save Splash ──
  const handleSaveSplash = async () => {
    await updateAppConfig({
      splash_enabled: splashForm.enabled,
      splashEnabled: splashForm.enabled,
      splash_image_url: splashForm.imageUrl,
      splashImageUrl: splashForm.imageUrl,
      splash_svga_url: splashForm.svgaUrl,
      splashSvgaUrl: splashForm.svgaUrl,
      splash_duration_seconds: splashForm.durationSeconds,
      splashDurationSeconds: splashForm.durationSeconds,
      splash_action_type: splashForm.actionType,
      splashActionType: splashForm.actionType,
      splash_action_value: splashForm.actionValue,
      splashActionValue: splashForm.actionValue,
    } as any);

    setSplashSaved(true);
    setTimeout(() => setSplashSaved(false), 3000);
  };

  const getActionLabel = (type?: string, val?: string) => {
    if (!type || type === 'none') return 'عرض فقط';
    if (type === 'room') return `🎙️ غرفة: ${val || ''}`;
    if (type === 'url') return `🌐 رابط: ${val || ''}`;
    const found = SCREEN_ACTIONS.find(a => a.value === type);
    return found ? found.label : type;
  };

  return (
    <div className="space-y-6">
      {/* Header & Tabs */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 border-b border-white/5 pb-4">
        <div>
          <h2 className="text-white text-lg font-bold flex items-center gap-2">
            <Layers className="w-5 h-5 text-indigo-400" />
            إدارة البنرات وشاشة الافتتاحية (Splash)
          </h2>
          <p className="text-slate-400 text-xs mt-1">
            التحكم في سلايدر الإعلانات وشاشة الاسبلاش الافتتاحية مع ربط التوجيه المباشر لأي شاشة أو غرفة
          </p>
        </div>

        {/* Tab Switcher */}
        <div className="flex bg-[#16161a] p-1 rounded-xl border border-white/10">
          <button
            onClick={() => setActiveTab('banners')}
            className={`px-4 py-2 rounded-lg text-xs font-semibold flex items-center gap-2 transition-all ${
              activeTab === 'banners'
                ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-600/30'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <Layers className="w-4 h-4" />
            البنرات المتحركة ({banners.length})
          </button>
          <button
            onClick={() => setActiveTab('splash')}
            className={`px-4 py-2 rounded-lg text-xs font-semibold flex items-center gap-2 transition-all ${
              activeTab === 'splash'
                ? 'bg-gradient-to-r from-amber-500 to-rose-500 text-white shadow-lg shadow-amber-500/30'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <Sparkles className="w-4 h-4" />
            شاشة الاسبلاش (Splash Screen)
          </button>
        </div>
      </div>

      {/* ══════════════════════════════════════════════════════════════ */}
      {/* TAB 1: BANNERS                                                */}
      {/* ══════════════════════════════════════════════════════════════ */}
      {activeTab === 'banners' && (
        <div className="space-y-6">
          <div className="flex items-center justify-between">
            <span className="text-xs text-slate-400">إجمالي البنرات: {banners.length}</span>
            <button
              onClick={() => {
                setShowAddBanner(!showAddBanner);
                setEditingBanner(null);
                resetBannerForm();
              }}
              className="px-4 py-2 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-bold rounded-xl flex items-center gap-1.5 transition-all shadow-md shadow-indigo-600/20"
            >
              <Plus className="w-4 h-4" /> {showAddBanner ? 'إلغاء الإضافة' : 'إضافة بنر جديد'}
            </button>
          </div>

          {/* Add / Edit Banner Form */}
          {(editingBanner || showAddBanner) && (
            <div className="bg-[#141417] rounded-2xl border border-indigo-500/30 p-6 space-y-5 shadow-xl">
              <div className="flex items-center justify-between border-b border-white/5 pb-3">
                <h3 className="text-white font-bold text-sm flex items-center gap-2">
                  <Sparkles className="w-4 h-4 text-indigo-400" />
                  {editingBanner ? `تعديل البنر: ${editingBanner.title || editingBanner.id}` : 'إضافة بنر جديد لسلايدر الاستكشاف'}
                </h3>
                <button
                  onClick={() => {
                    setEditingBanner(null);
                    setShowAddBanner(false);
                  }}
                  className="text-slate-400 hover:text-white"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <ImageUpload
                  currentUrl={bannerForm.imageUrl}
                  onUpload={file => uploadBanner(file, editingBanner?.id || `new_${Date.now()}`)}
                  onUrlChange={url => setBannerForm(p => ({ ...p, imageUrl: url }))}
                  label="صورة البنر (Banner Image)"
                />

                <div className="space-y-4">
                  <div>
                    <label className="block text-xs font-bold text-slate-300 mb-1">عنوان البنر</label>
                    <input
                      type="text"
                      placeholder="مثال: فعالية عيد الحب أو باقات الـ VIP الجديدة"
                      value={bannerForm.title}
                      onChange={e => setBannerForm(p => ({ ...p, title: e.target.value }))}
                      className="w-full bg-[#1a1a20] border border-white/10 rounded-xl py-2 px-3 text-xs text-white placeholder:text-slate-600 focus:border-indigo-500 focus:outline-none"
                    />
                  </div>

                  {/* Action Selector */}
                  <div>
                    <label className="block text-xs font-bold text-indigo-300 mb-1">
                      🎯 إجراء التوجيه عند الضغط على البنر
                    </label>
                    <select
                      value={bannerForm.actionType}
                      onChange={e => setBannerForm(p => ({ ...p, actionType: e.target.value, actionValue: '' }))}
                      className="w-full bg-[#1a1a20] border border-indigo-500/40 rounded-xl py-2 px-3 text-xs text-white focus:outline-none"
                    >
                      {SCREEN_ACTIONS.map(action => (
                        <option key={action.value} value={action.value} className="bg-[#141417]">
                          {action.label}
                        </option>
                      ))}
                    </select>
                  </div>

                  {/* Dynamic Value Input for Room or URL */}
                  {bannerForm.actionType === 'room' && (
                    <div className="p-3 bg-indigo-950/30 rounded-xl border border-indigo-500/30">
                      <label className="block text-[11px] font-bold text-amber-400 mb-1">رقم الغرفة (Room ID)</label>
                      <input
                        type="text"
                        placeholder="أدخل معرّف أو رقم الغرفة، مثال: 100425"
                        value={bannerForm.actionValue}
                        onChange={e => setBannerForm(p => ({ ...p, actionValue: e.target.value }))}
                        className="w-full bg-[#141418] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                      />
                    </div>
                  )}

                  {bannerForm.actionType === 'url' && (
                    <div className="p-3 bg-indigo-950/30 rounded-xl border border-indigo-500/30">
                      <label className="block text-[11px] font-bold text-amber-400 mb-1">رابط الويب الخارجي (URL)</label>
                      <input
                        type="text"
                        placeholder="https://example.com/event"
                        value={bannerForm.actionValue}
                        onChange={e => setBannerForm(p => ({ ...p, actionValue: e.target.value }))}
                        className="w-full bg-[#141418] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                      />
                    </div>
                  )}

                  <div className="flex items-center gap-6 pt-2">
                    <div>
                      <label className="block text-[11px] uppercase text-slate-400 font-bold mb-1">الترتيب</label>
                      <input
                        type="number"
                        value={bannerForm.sortOrder}
                        onChange={e => setBannerForm(p => ({ ...p, sortOrder: Number(e.target.value) }))}
                        className="w-20 bg-[#1a1a20] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white text-center"
                      />
                    </div>
                    <label className="flex items-center gap-2 text-xs text-slate-300 font-bold cursor-pointer mt-4">
                      <input
                        type="checkbox"
                        checked={bannerForm.active}
                        onChange={e => setBannerForm(p => ({ ...p, active: e.target.checked }))}
                        className="w-4 h-4 accent-indigo-500 rounded"
                      />
                      مفعل ونشط في السلايدر
                    </label>
                  </div>
                </div>
              </div>

              {bannerForm.imageUrl && (
                <div className="relative rounded-xl overflow-hidden border border-white/10 h-36 bg-black">
                  <img src={bannerForm.imageUrl} className="w-full h-full object-cover" />
                  <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent flex items-end p-3">
                    <span className="text-white text-xs font-bold">{bannerForm.title || 'معاينة البنر'}</span>
                  </div>
                </div>
              )}

              <div className="flex justify-end gap-3 pt-2">
                <button
                  onClick={() => {
                    setEditingBanner(null);
                    setShowAddBanner(false);
                  }}
                  className="px-4 py-2 bg-white/5 hover:bg-white/10 text-xs text-slate-300 font-bold rounded-xl"
                >
                  إلغاء
                </button>
                <button
                  onClick={editingBanner ? handleSaveBanner : handleAddBanner}
                  className="px-6 py-2 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-bold rounded-xl flex items-center gap-2 shadow-lg shadow-emerald-600/20"
                >
                  <Save className="w-4 h-4" />
                  {editingBanner ? 'حفظ التعديلات' : 'إضافة البنر'}
                </button>
              </div>
            </div>
          )}

          {/* Banners List */}
          {loadingBanners ? (
            <div className="text-center py-12 text-slate-500 text-xs">جاري تحميل البنرات...</div>
          ) : banners.length === 0 ? (
            <div className="text-center py-12 text-slate-500 text-xs bg-[#141417] rounded-2xl border border-white/5">
              لا توجد بنرات حالياً. انقر على "إضافة بنر جديد" لإنشاء أول بنر.
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {banners.map(b => (
                <div
                  key={b.id}
                  className="bg-[#141417] rounded-2xl border border-white/5 p-4 flex gap-4 hover:border-white/15 transition-all shadow-md group"
                >
                  {b.imageUrl ? (
                    <img src={b.imageUrl} className="w-32 h-20 object-cover rounded-xl border border-white/10 flex-shrink-0" />
                  ) : (
                    <div className="w-32 h-20 rounded-xl bg-slate-800 flex items-center justify-center text-[10px] text-slate-500 flex-shrink-0">
                      بدون صورة
                    </div>
                  )}

                  <div className="flex-1 min-w-0 flex flex-col justify-between">
                    <div>
                      <div className="text-white text-xs font-bold truncate">{b.title || 'بنر بدون عنوان'}</div>
                      <div className="mt-1 flex items-center gap-1.5 text-[11px] text-indigo-400 truncate">
                        <ArrowRight className="w-3 h-3 flex-shrink-0" />
                        <span className="truncate">{getActionLabel(b.actionType, b.actionValue) || b.linkUrl || 'بدون توجيه'}</span>
                      </div>
                    </div>

                    <div className="flex items-center justify-between pt-2 border-t border-white/5">
                      <div className="flex items-center gap-2">
                        <span className={`text-[10px] px-2 py-0.5 rounded-full font-bold ${b.active ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 'bg-slate-500/10 text-slate-500'}`}>
                          {b.active ? 'نشط' : 'معطل'}
                        </span>
                        <span className="text-[10px] text-slate-500">الترتيب: {b.sortOrder}</span>
                      </div>

                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => handleEditBanner(b)}
                          className="px-2.5 py-1 bg-indigo-600/20 hover:bg-indigo-600 text-indigo-300 hover:text-white rounded-lg text-[10px] font-bold transition-all"
                        >
                          تعديل
                        </button>
                        <button
                          onClick={() => handleDeleteBanner(b)}
                          className="p-1 text-rose-400 hover:text-rose-300 hover:bg-rose-500/10 rounded-lg transition-all"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ══════════════════════════════════════════════════════════════ */}
      {/* TAB 2: SPLASH SCREEN CONFIG                                   */}
      {/* ══════════════════════════════════════════════════════════════ */}
      {activeTab === 'splash' && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Settings Form (2 Columns) */}
          <div className="lg:col-span-2 bg-[#141417] rounded-2xl border border-white/10 p-6 space-y-6 shadow-xl">
            <div className="flex items-center justify-between border-b border-white/5 pb-4">
              <div>
                <h3 className="text-white font-bold text-sm flex items-center gap-2">
                  <Sparkles className="w-4 h-4 text-amber-400" />
                  إعدادات شاشة الاسبلاش الافتتاحية
                </h3>
                <p className="text-slate-400 text-xs mt-0.5">
                  تظهر عند فتح التطبيق مع مؤقت تخطي وتوجيه مباشر عند الضغط المزدوج
                </p>
              </div>

              {splashSaved && (
                <div className="flex items-center gap-1 text-emerald-400 text-xs font-bold bg-emerald-500/10 px-3 py-1.5 rounded-xl border border-emerald-500/20">
                  <CheckCircle2 className="w-4 h-4" />
                  تم الحفظ بنجاح!
                </div>
              )}
            </div>

            {loadingSplash ? (
              <div className="text-center py-12 text-slate-500 text-xs">جاري تحميل إعدادات الاسبلاش...</div>
            ) : (
              <div className="space-y-5">
                {/* Active Toggle */}
                <div className="p-4 bg-[#1a1a20] rounded-xl border border-white/5 flex items-center justify-between">
                  <div>
                    <div className="text-white text-xs font-bold">تفعيل شاشة الاسبلاش الترويجية</div>
                    <div className="text-slate-400 text-[11px] mt-0.5">
                      عرض الإعلان / صورة الافتتاحية مع مؤقت العد التنازلي قبل الانتقال للرئيسية
                    </div>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      checked={splashForm.enabled}
                      onChange={e => setSplashForm(p => ({ ...p, enabled: e.target.checked }))}
                      className="sr-only peer"
                    />
                    <div className="w-11 h-6 bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-amber-500"></div>
                  </label>
                </div>

                {/* Duration Slider */}
                <div>
                  <div className="flex justify-between items-center mb-1.5">
                    <label className="text-xs font-bold text-slate-300">مدة عرض شاشة الاسبلاش (بالثواني)</label>
                    <span className="text-xs font-bold text-amber-400 bg-amber-500/10 px-2 py-0.5 rounded-lg border border-amber-500/20">
                      {splashForm.durationSeconds} ثوانٍ
                    </span>
                  </div>
                  <input
                    type="range"
                    min={1}
                    max={10}
                    step={1}
                    value={splashForm.durationSeconds}
                    onChange={e => setSplashForm(p => ({ ...p, durationSeconds: Number(e.target.value) }))}
                    className="w-full accent-amber-500 bg-slate-800 rounded-lg h-2"
                  />
                </div>

                {/* Media Uploads */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <ImageUpload
                    currentUrl={splashForm.imageUrl}
                    onUpload={file => uploadSplash(file, `splash_${Date.now()}`)}
                    onUrlChange={url => setSplashForm(p => ({ ...p, imageUrl: url }))}
                    label="صورة الاسبلاش (Image / GIF / WebP)"
                  />

                  <div className="space-y-3">
                    <div>
                      <label className="block text-xs font-bold text-slate-300 mb-1">
                        ملف حركة SVGA للسبلاش (اختياري)
                      </label>
                      <input
                        type="text"
                        placeholder="https://.../splash.svga"
                        value={splashForm.svgaUrl}
                        onChange={e => setSplashForm(p => ({ ...p, svgaUrl: e.target.value }))}
                        className="w-full bg-[#1a1a20] border border-white/10 rounded-xl py-2 px-3 text-xs text-white placeholder:text-slate-600 focus:border-amber-500 focus:outline-none"
                      />
                      <p className="text-[10px] text-slate-500 mt-1">
                        إذا تم تحديد رابط SVGA سيعرض كأنيميشن متحرك فوق الشاشة
                      </p>
                    </div>

                    {/* Double-tap Action */}
                    <div className="p-3 bg-amber-950/20 rounded-xl border border-amber-500/20 space-y-2">
                      <label className="block text-xs font-bold text-amber-300">
                        ⚡ إجراء عند الضغط المزدوج على الاسبلاش (Double-Tap Action)
                      </label>
                      <select
                        value={splashForm.actionType}
                        onChange={e => setSplashForm(p => ({ ...p, actionType: e.target.value, actionValue: '' }))}
                        className="w-full bg-[#141418] border border-amber-500/40 rounded-xl py-2 px-3 text-xs text-white focus:outline-none"
                      >
                        {SCREEN_ACTIONS.map(action => (
                          <option key={action.value} value={action.value} className="bg-[#141417]">
                            {action.label}
                          </option>
                        ))}
                      </select>

                      {splashForm.actionType === 'room' && (
                        <div className="pt-2">
                          <label className="block text-[10px] font-bold text-slate-300 mb-1">رقم الغرفة (Room ID)</label>
                          <input
                            type="text"
                            placeholder="مثال: 100425"
                            value={splashForm.actionValue}
                            onChange={e => setSplashForm(p => ({ ...p, actionValue: e.target.value }))}
                            className="w-full bg-[#16161a] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                          />
                        </div>
                      )}

                      {splashForm.actionType === 'url' && (
                        <div className="pt-2">
                          <label className="block text-[10px] font-bold text-slate-300 mb-1">رابط الويب (URL)</label>
                          <input
                            type="text"
                            placeholder="https://example.com"
                            value={splashForm.actionValue}
                            onChange={e => setSplashForm(p => ({ ...p, actionValue: e.target.value }))}
                            className="w-full bg-[#16161a] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                          />
                        </div>
                      )}
                    </div>
                  </div>
                </div>

                <div className="flex justify-end pt-4 border-t border-white/5">
                  <button
                    onClick={handleSaveSplash}
                    className="px-8 py-2.5 bg-gradient-to-r from-amber-500 to-rose-500 hover:from-amber-600 hover:to-rose-600 text-white font-bold text-xs rounded-xl flex items-center gap-2 shadow-lg shadow-amber-500/20 transition-all"
                  >
                    <Save className="w-4 h-4" />
                    حفظ ونشر إعدادات الاسبلاش للتطبيق فوراً
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* Live Phone Mockup Preview (1 Column) */}
          <div className="bg-[#141417] rounded-2xl border border-white/10 p-6 flex flex-col items-center justify-between shadow-xl">
            <div className="w-full text-center border-b border-white/5 pb-3">
              <span className="text-xs font-bold text-slate-300 flex items-center justify-center gap-1.5">
                <Smartphone className="w-4 h-4 text-amber-400" />
                معاينة شاشة الاسبلاش على الهاتف
              </span>
            </div>

            {/* Mockup Frame */}
            <div className="my-4 relative w-[220px] h-[420px] bg-black rounded-[36px] border-4 border-slate-700 shadow-2xl overflow-hidden flex flex-col items-center justify-center">
              {/* Top notch */}
              <div className="absolute top-2 w-20 h-4 bg-slate-800 rounded-full z-20" />

              {/* Skip button mockup */}
              <div className="absolute top-8 right-3 z-20 bg-black/60 backdrop-blur-md px-2.5 py-1 rounded-full border border-white/20 flex items-center gap-1">
                <span className="text-[10px] text-white font-bold">تخطي {splashForm.durationSeconds}</span>
                <ArrowRight className="w-2.5 h-2.5 text-white" />
              </div>

              {/* Splash Media Display */}
              {splashForm.imageUrl ? (
                <img src={splashForm.imageUrl} className="w-full h-full object-cover" />
              ) : (
                <div className="text-center p-4">
                  <Sparkles className="w-10 h-10 text-amber-400 mx-auto mb-2 animate-pulse" />
                  <div className="text-white text-xs font-bold">شاشة الافتتاحية</div>
                  <div className="text-[10px] text-slate-500 mt-1">قم برفع صورة أو ملف حركة لتظهر هنا</div>
                </div>
              )}

              {/* Action Hint Bottom */}
              {splashForm.actionType !== 'none' && (
                <div className="absolute bottom-6 inset-x-3 z-20 bg-black/70 backdrop-blur-md p-2 rounded-xl border border-amber-500/30 text-center">
                  <div className="text-[9px] text-amber-300 font-bold">اضغط مرتين للدخول إلى:</div>
                  <div className="text-[10px] text-white font-bold truncate">
                    {getActionLabel(splashForm.actionType, splashForm.actionValue)}
                  </div>
                </div>
              )}
            </div>

            <div className="text-center text-[11px] text-slate-500">
              يتم تحديث الإعدادات في تطبيق المستخدمين مباشرة بدون الحاجة لإعادة رفع التطبيق.
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
