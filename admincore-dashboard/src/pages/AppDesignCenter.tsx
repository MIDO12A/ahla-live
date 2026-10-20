import { useState, useEffect, useContext, useRef } from 'react';
import { useSearchParams } from 'react-router-dom';
import { I18nContext } from '../lib/i18n';
import { getAppConfig, updateAppConfig } from '../lib/db';
import { uploadAppAsset } from '../lib/storage';
import {
  Palette, Smartphone, SlidersHorizontal, Image as ImageIcon, Sparkles,
  Type, Save, RotateCcw, Search, Plus, Trash2, CheckCircle, RefreshCw,
  Eye, EyeOff, Check, Layers, AlertCircle, ArrowRightLeft, Target, Shield, LayoutGrid,
  Upload, X, ImagePlus, CheckCircle2, ChevronRight, Sliders, ExternalLink,
  Move, ArrowUp, ArrowDown, ArrowLeft, ArrowRight, Circle, Square, Maximize2
} from 'lucide-react';

// Sub-components
import VisualManager from './VisualManager';
import AppVisualDesigner from './AppVisualDesigner';
import ScreenCustomizationPage from './ScreenCustomization';
import AppAssets from './AppAssets';
import GiftBannerConfigs from './GiftBannerConfigs';

export default function AppDesignCenter() {
  const { t, lang } = useContext(I18nContext);
  const isAr = lang === 'ar';
  const [searchParams, setSearchParams] = useSearchParams();

  // Active Tab
  const tabParam = searchParams.get('tab') || 'texts_colors';
  const [activeTab, setActiveTab] = useState<string>(tabParam);
  const [activeSection, setActiveSection] = useState<string>('all');

  useEffect(() => {
    const tParam = searchParams.get('tab');
    if (tParam && tParam !== activeTab) {
      setActiveTab(tParam);
    }
  }, [searchParams]);

  const handleTabChange = (key: string) => {
    setActiveTab(key);
    setSearchParams({ tab: key });
  };

  // State
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saveSuccess, setSaveSuccess] = useState(false);
  const [searchQ, setSearchQ] = useState('');
  const [uploadingFieldId, setUploadingFieldId] = useState<string | null>(null);

  // App Config Storage Maps
  const [screenVisuals, setScreenVisuals] = useState<Record<string, any>>({});
  const [customStrings, setCustomStrings] = useState<Record<string, string>>({});
  const [screenTitles, setScreenTitles] = useState<Record<string, string>>({});
  const [visualManagerConfig, setVisualManagerConfig] = useState<Record<string, any>>({});

  // Dynamic Custom Key-Value Strings
  const [customKeyValues, setCustomKeyValues] = useState<Array<{ key: string; value: string }>>([]);
  const [newCustomKey, setNewCustomKey] = useState('');
  const [newCustomVal, setNewCustomVal] = useState('');

  // Reusable file input reference
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [pendingUploadTarget, setPendingUploadTarget] = useState<{
    screenKey: string;
    imageKey: string;
    fieldId: string;
  } | null>(null);

  // 14 Comprehensive Screen Categories
  const categories = [
    { id: 'all', labelAr: '🌟 الكل (جميع الشاشات)', labelEn: 'All Screens', icon: '🌟' },
    { id: 'agency', labelAr: '🎯 مستهدف الوكالات والمضيفين والرواتب', labelEn: 'Agency & Host Targets', icon: '🎯' },
    { id: 'profile', labelAr: '👤 البروفايل وحسابي والملف الشخصي', labelEn: 'Profile & User Details', icon: '👤' },
    { id: 'room', labelAr: '🎙️ الغرف الصوتية والمقاعد والمحادثة', labelEn: 'Rooms & Voice Seats', icon: '🎙️' },
    { id: 'wallet', labelAr: '💳 المحفظة والشحن والتحويل', labelEn: 'Wallet & Recharge', icon: '💳' },
    { id: 'store', labelAr: '🛍️ المتجر والحقيبة و VIP', labelEn: 'Store & VIP Center', icon: '🛍️' },
    { id: 'cp', labelAr: '💑 مساحة الارتباط والعلاقات CP', labelEn: 'CP Space & Relationship', icon: '💑' },
    { id: 'signin', labelAr: '📅 تسجيل الدخول اليومي والمكافآت', labelEn: 'Daily Sign-In & Rewards', icon: '📅' },
    { id: 'unions', labelAr: '🏰 العائلات والنقابات', labelEn: 'Unions & Families', icon: '🏰' },
    { id: 'rankings', labelAr: '🏆 المتصدرون وقوائم الترتيب', labelEn: 'Leaderboards & Rankings', icon: '🏆' },
    { id: 'badges', labelAr: '🎖️ الشارات والأوسمة والقلادات', labelEn: 'Badges & Necklaces', icon: '🎖️' },
    { id: 'chat', labelAr: '💬 المحادثات الفردية والرسائل', labelEn: '1-on-1 Messages & Chat', icon: '💬' },
    { id: 'settings', labelAr: '⚙️ شاشة الإعدادات والأمان والنظام', labelEn: 'Settings & Security', icon: '⚙️' },
    { id: 'gift_banners', labelAr: '🎁 بانرات ولافتات الهدايا', labelEn: 'Gift Banners & Alerts', icon: '🎁' },
    { id: 'global', labelAr: '🌐 النصوص والألوان العامة وشريط التنقل', labelEn: 'Global App & Bottom Nav', icon: '🌐' },
  ];

  // Load configs on mount
  useEffect(() => {
    async function loadData() {
      setLoading(true);
      try {
        const [svRes, csRes, stRes, vcRes] = await Promise.all([
          getAppConfig('screen_visuals'),
          getAppConfig('custom_strings'),
          getAppConfig('screenTitles'),
          getAppConfig('visual_manager_config'),
        ]);

        const sv = svRes || {};
        const cs = csRes || {};
        const st = stRes || {};
        const vc = vcRes || {};

        setScreenVisuals(sv);
        setCustomStrings(cs);
        setScreenTitles(st);
        setVisualManagerConfig(vc);

        // Populate custom dynamic strings
        const knownKeys = new Set([
          'curTargetTitle', 'curBalanceTitle', 'nextTargetTitle', 'nextRemainingTitle',
          'agencyTargetTitle', 'myTargetTitle', 'agencyBalanceTitle', 'myBalanceTitle',
          'targetStatsTitle', 'firstHalfTitle', 'secondHalfTitle', 'hoursTitle', 'salaryTitle',
          'addMemberButtonText', 'targetPolicyText', 'coinsBalanceTitle', 'diamondsBalanceTitle',
          'transferTitle', 'confirmTransferText', 'exchangeTitle', 'sendBtnText', 'chatPlaceholder',
          'micSeatsTitle', 'leaveRoomText', 'luckyBoxText', 'discoverTitle', 'messageTitle',
          'profileTitle', 'roomsTitle', 'storeTitle', 'vipTitle', 'walletTitle',
          'rechargeAgentTitle', 'hostAgencyTitle', 'cpTitle', 'textPrimary', 'textSecondary',
          'buttonTextColor', 'buttonColor', 'cardTextColor', 'headerColor'
        ]);

        const customItems: Array<{ key: string; value: string }> = [];
        for (const [k, v] of Object.entries(cs)) {
          if (!knownKeys.has(k) && typeof v === 'string') {
            customItems.push({ key: k, value: v });
          }
        }
        setCustomKeyValues(customItems);
      } catch (err) {
        console.error('Error loading design texts & colors:', err);
      } finally {
        setLoading(false);
      }
    }
    loadData();
  }, []);

  // Safe getter for screen visual value
  const getVal = (screen: string, key: string, fallback: string = ''): string => {
    const s = screenVisuals[screen];
    if (s && s[key] !== undefined && s[key] !== null && String(s[key]).trim() !== '') {
      return String(s[key]);
    }
    if (screen === 'hostAgency' && screenVisuals.agency && screenVisuals.agency[key]) {
      return String(screenVisuals.agency[key]);
    }
    if (customStrings[key]) return customStrings[key];
    if (screenTitles[key]) return screenTitles[key];
    if (visualManagerConfig[key]) return String(visualManagerConfig[key]);
    return fallback;
  };

  // Safe updater for screen visual / text / color / image
  const setVal = (screen: string, key: string, value: string) => {
    setScreenVisuals(prev => {
      const next = { ...prev };
      next[screen] = { ...(next[screen] || {}), [key]: value };
      // Also mirror between hostAgency and agency for backwards-compatibility
      if (screen === 'hostAgency') {
        next.agency = { ...(next.agency || {}), [key]: value };
      } else if (screen === 'agency') {
        next.hostAgency = { ...(next.hostAgency || {}), [key]: value };
      }
      return next;
    });

    // Also mirror to customStrings if it's a text title or label
    if (!key.toLowerCase().includes('color') && !key.toLowerCase().includes('image') && !key.toLowerCase().includes('bg')) {
      setCustomStrings(prev => ({ ...prev, [key]: value }));
    }
    if (screenTitles[key] !== undefined) {
      setScreenTitles(prev => ({ ...prev, [key]: value }));
    }
  };

  // Handle uploading device image for ANY element
  const triggerImageUpload = (screenKey: string, imageKey: string, fieldId: string) => {
    setPendingUploadTarget({ screenKey, imageKey, fieldId });
    if (fileInputRef.current) {
      fileInputRef.current.value = '';
      fileInputRef.current.click();
    }
  };

  const handleFileSelected = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !pendingUploadTarget) return;

    const { screenKey, imageKey, fieldId } = pendingUploadTarget;
    setUploadingFieldId(fieldId);

    try {
      const uploadedUrl = await uploadAppAsset(file, 'screen_customization');
      setVal(screenKey, imageKey, uploadedUrl);
    } catch (err: any) {
      alert(isAr ? 'فشل رفع الصورة: ' + (err?.message || err) : 'Upload failed: ' + (err?.message || err));
    } finally {
      setUploadingFieldId(null);
      setPendingUploadTarget(null);
    }
  };

  // Save All
  const handleSaveAll = async () => {
    setSaving(true);
    setSaveSuccess(false);
    try {
      // 1. Build consolidated custom strings
      const mergedCustomStrings: Record<string, string> = { ...customStrings };
      for (const item of customKeyValues) {
        if (item.key.trim()) {
          mergedCustomStrings[item.key.trim()] = item.value;
        }
      }

      // 2. Build consolidated visual config
      const mergedVc = {
        ...visualManagerConfig,
        primaryBg: getVal('global', 'primaryBg', '#FFFFFF'),
        textPrimary: getVal('global', 'textPrimary', '#16151A'),
        textSecondary: getVal('global', 'textSecondary', '#9BA1B6'),
        buttonColor: getVal('global', 'buttonColor', '#6366F1'),
        buttonTextColor: getVal('global', 'buttonTextColor', '#FFFFFF'),
        headerColor: getVal('global', 'headerColor', '#FFFFFF'),
        goldColor: getVal('global', 'goldColor', '#DE880F'),
      };

      // 3. Persist to app_config table
      await Promise.all([
        updateAppConfig('screen_visuals', screenVisuals),
        updateAppConfig('custom_strings', mergedCustomStrings),
        updateAppConfig('screenTitles', screenTitles),
        updateAppConfig('visual_manager_config', mergedVc),
      ]);

      setSaveSuccess(true);
      setTimeout(() => setSaveSuccess(false), 4500);
    } catch (err: any) {
      alert(isAr ? 'حدث خطأ أثناء حفظ التعديلات: ' + (err?.message || err) : 'Error saving changes: ' + (err?.message || err));
    } finally {
      setSaving(false);
    }
  };

  // Main navigation tabs for the Design Center
  const tabs = [
    { key: 'texts_colors', label: isAr ? '✍️ محرر نصوص التطبيق والشاشات والألوان والصور' : '✍️ App Texts, Colors & Images', icon: Type },
    { key: 'visual_manager', label: isAr ? '🎨 المظهر الشامل والألوان' : '🎨 Visual Manager', icon: Palette },
    { key: 'app_visual_designer', label: isAr ? '📱 مصمم الواجهات والأيقونات' : '📱 Screen Designer & Icons', icon: Smartphone },
    { key: 'screen_customization', label: isAr ? '🛠️ تخصيص الشاشات والخلفيات' : '🛠️ Screen Customization', icon: SlidersHorizontal },
    { key: 'app_assets', label: isAr ? '🖼️ مكتبة أصول التطبيق' : '🖼️ App Assets', icon: ImageIcon },
    { key: 'gift_banners', label: isAr ? '🎁 بانرات ولافتات الهدايا' : '🎁 Gift Banners', icon: Sparkles },
  ];

  const toValidHex = (colorStr: string, fallback = '#1A1A1E'): string => {
    if (!colorStr || typeof colorStr !== 'string') return fallback;
    const s = colorStr.trim();
    if (/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(s)) {
      if (s.length === 4) {
        return `#${s[1]}${s[1]}${s[2]}${s[2]}${s[3]}${s[3]}`;
      }
      return s;
    }
    return fallback;
  };

  // Reusable Master Element Editor with Hide/Show, Directional Movements, Shape, Size & Dual-mode Background/Image
  const renderElementEditor = (params: {
    id: string;
    category: string;
    screen: string;
    labelAr: string;
    labelEn: string;
    // Text customization
    hasText?: boolean;
    textKey?: string;
    defaultText?: string;
    textPlaceholder?: string;
    textColorKey?: string;
    defaultTextColor?: string;
    // Color customization
    hasColor?: boolean;
    colorKey?: string;
    defaultColor?: string;
    // Image customization (uploaded from device)
    hasImage?: boolean;
    imageKey?: string;
    imageHint?: string;
    // Icon customization (uploaded from device)
    hasIcon?: boolean;
    iconKey?: string;
  }) => {
    const textVal = params.textKey ? getVal(params.screen, params.textKey, params.defaultText || '') : '';
    const textColorVal = params.textColorKey ? getVal(params.screen, params.textColorKey, params.defaultTextColor || '#FFFFFF') : '';
    const colorVal = params.colorKey ? getVal(params.screen, params.colorKey, params.defaultColor || '#1A1A1E') : '';
    const imageVal = params.imageKey ? getVal(params.screen, params.imageKey, '') : '';
    const iconVal = params.iconKey ? getVal(params.screen, params.iconKey, '') : '';
    const isUploadingBg = uploadingFieldId === `${params.id}_bg`;
    const isUploadingIcon = uploadingFieldId === `${params.id}_icon`;

    // Visibility toggle (إخفاء / إظهار من التطبيق)
    const isHidden = getVal(params.screen, `${params.id}_hidden`, 'false') === 'true';

    // Position / Arrow movements (يمين، شمال، فوق، تحت)
    const offsetX = parseInt(getVal(params.screen, `${params.id}_offset_x`, '0')) || 0;
    const offsetY = parseInt(getVal(params.screen, `${params.id}_offset_y`, '0')) || 0;

    // Shape & Size (الشكل والحجم)
    const width = getVal(params.screen, `${params.id}_width`, '');
    const height = getVal(params.screen, `${params.id}_height`, '');
    const radius = getVal(params.screen, `${params.id}_radius`, '');

    // Filter by search query
    if (searchQ.trim()) {
      const q = searchQ.toLowerCase();
      const matchLabel = params.labelAr.toLowerCase().includes(q) || params.labelEn.toLowerCase().includes(q);
      const matchText = textVal.toLowerCase().includes(q);
      const matchKey = (params.textKey || '').toLowerCase().includes(q) || (params.colorKey || '').toLowerCase().includes(q) || (params.imageKey || '').toLowerCase().includes(q);
      if (!matchLabel && !matchText && !matchKey) return null;
    }

    return (
      <div
        key={params.id}
        className={`bg-[#16171B] border transition-all rounded-xl p-4 space-y-3.5 shadow-md flex flex-col justify-between ${
          isHidden ? 'border-rose-500/40 bg-[#171214]' : 'border-white/10 hover:border-purple-500/40'
        }`}
      >
        <div>
          {/* Header Title + Badges + Hide Toggle Button */}
          <div className="flex items-center justify-between gap-2 mb-2 flex-wrap">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-xs font-bold text-slate-100 flex items-center gap-1.5">
                {isAr ? params.labelAr : params.labelEn}
              </span>
              {isHidden ? (
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-rose-500/20 text-rose-400 border border-rose-500/30 flex items-center gap-1 font-bold">
                  <EyeOff className="w-3 h-3" /> {isAr ? 'مخفي بالتطبيق' : 'Hidden'}
                </span>
              ) : (
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 flex items-center gap-1 font-semibold">
                  <Eye className="w-3 h-3" /> {isAr ? 'ظاهر' : 'Visible'}
                </span>
              )}
              {params.imageKey && imageVal && (
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-cyan-500/20 text-cyan-400 border border-cyan-500/30 flex items-center gap-1 font-semibold">
                  <Check className="w-3 h-3" /> {isAr ? 'صورة خلفية' : 'Image Bg'}
                </span>
              )}
              {params.iconKey && iconVal && (
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-indigo-500/20 text-indigo-400 border border-indigo-500/30 flex items-center gap-1 font-semibold">
                  <Check className="w-3 h-3" /> {isAr ? 'أيقونة مخصصة' : 'Custom Icon'}
                </span>
              )}
            </div>

            {/* Quick Hide/Show Toggle Button */}
            <button
              type="button"
              onClick={() => setVal(params.screen, `${params.id}_hidden`, isHidden ? 'false' : 'true')}
              className={`px-2.5 py-1 rounded-lg text-[11px] font-bold flex items-center gap-1.5 transition-all cursor-pointer ${
                isHidden
                  ? 'bg-rose-500/20 hover:bg-rose-500/30 text-rose-300 border border-rose-500/40'
                  : 'bg-white/5 hover:bg-white/10 text-slate-300 border border-white/10'
              }`}
              title={isAr ? 'إخفاء أو إظهار هذا العنصر في التطبيق' : 'Toggle visibility in mobile app'}
            >
              {isHidden ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
              <span>{isHidden ? (isAr ? 'إظهار بالتطبيق' : 'Unhide') : (isAr ? 'إخفاء من التطبيق' : 'Hide')}</span>
            </button>
          </div>

          {/* Text Input (if applicable) */}
          {params.hasText && params.textKey && (
            <div className="space-y-1.5 mb-2.5">
              <label className="text-[11px] text-slate-400 flex items-center justify-between">
                <span>{isAr ? 'النص المعروض داخل العنصر:' : 'Displayed Text:'}</span>
                {params.textColorKey && (
                  <div className="flex items-center gap-1.5 cursor-pointer">
                    <span className="text-[10px] text-slate-400">{isAr ? 'لون الخط:' : 'Font Color:'}</span>
                    <input
                      type="color"
                      value={toValidHex(textColorVal, '#FFFFFF')}
                      onChange={e => setVal(params.screen, params.textColorKey!, e.target.value)}
                      className="w-5 h-5 rounded border-none cursor-pointer bg-transparent"
                    />
                  </div>
                )}
              </label>
              <input
                type="text"
                value={textVal}
                onChange={e => setVal(params.screen, params.textKey!, e.target.value)}
                placeholder={params.textPlaceholder || (isAr ? 'اكتب النص المطلوب...' : 'Enter text...')}
                className="w-full bg-[#1F2026] border border-white/10 rounded-lg px-3 py-1.5 text-white text-xs focus:outline-none focus:border-purple-500"
              />
            </div>
          )}
        </div>

        {/* Middle Section: Background Color or Device Image Upload */}
        <div className="pt-2 border-t border-white/5 space-y-2.5">
          <div className="flex items-center justify-between gap-2 flex-wrap">
            {params.hasColor && params.colorKey && (
              <div className="flex items-center gap-1.5">
                <span className="text-[10px] text-slate-400">{isAr ? 'اللون:' : 'Color:'}</span>
                <input
                  type="color"
                  value={toValidHex(colorVal, '#1A1A1E')}
                  onChange={e => setVal(params.screen, params.colorKey!, e.target.value)}
                  className="w-6 h-6 rounded border-none cursor-pointer bg-transparent"
                  title={isAr ? 'اختر اللون' : 'Pick Color'}
                />
                <span className="text-[11px] font-mono text-slate-300">{colorVal}</span>
              </div>
            )}

            <div className="flex items-center gap-1.5 flex-wrap">
              {/* Upload Background Image Button */}
              {params.hasImage && params.imageKey && (
                <button
                  type="button"
                  onClick={() => triggerImageUpload(params.screen, params.imageKey!, `${params.id}_bg`)}
                  disabled={isUploadingBg}
                  className="px-2.5 py-1.5 rounded-lg bg-purple-600/20 hover:bg-purple-600/30 text-purple-300 border border-purple-500/30 text-[11px] font-semibold flex items-center gap-1.5 cursor-pointer transition-all disabled:opacity-50"
                >
                  {isUploadingBg ? <RefreshCw className="w-3.5 h-3.5 animate-spin" /> : <Upload className="w-3.5 h-3.5" />}
                  <span>{isUploadingBg ? (isAr ? 'جارٍ الرفع...' : 'Uploading...') : (isAr ? 'تبديل لصورة من الجهاز' : 'Upload Image')}</span>
                </button>
              )}

              {/* Upload Icon Button (if applicable) */}
              {params.hasIcon && params.iconKey && (
                <button
                  type="button"
                  onClick={() => triggerImageUpload(params.screen, params.iconKey!, `${params.id}_icon`)}
                  disabled={isUploadingIcon}
                  className="px-2.5 py-1.5 rounded-lg bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-300 border border-indigo-500/30 text-[11px] font-semibold flex items-center gap-1.5 cursor-pointer transition-all disabled:opacity-50"
                >
                  {isUploadingIcon ? <RefreshCw className="w-3.5 h-3.5 animate-spin" /> : <ImageIcon className="w-3.5 h-3.5" />}
                  <span>{isUploadingIcon ? (isAr ? 'جارٍ الرفع...' : 'Uploading...') : (isAr ? 'رفع أيقونة بديلة' : 'Upload Icon')}</span>
                </button>
              )}
            </div>
          </div>

          {/* Background Image Thumbnail & Clear Button */}
          {params.hasImage && params.imageKey && imageVal && (
            <div className="bg-[#121316] border border-cyan-500/30 rounded-lg p-2 flex items-center justify-between gap-2 animate-fade-in">
              <div className="flex items-center gap-2 overflow-hidden">
                <img
                  src={imageVal}
                  alt="bg visual"
                  className="w-9 h-9 rounded object-cover border border-white/10 flex-shrink-0 bg-black/40"
                  onError={(e) => { (e.target as any).style.display = 'none'; }}
                />
                <div className="overflow-hidden">
                  <span className="text-[10px] text-cyan-400 font-bold block truncate">
                    {isAr ? 'صورة الخلفية مفعّلة' : 'Custom Image Active'}
                  </span>
                  <span className="text-[9px] text-slate-500 truncate block font-mono" title={imageVal}>
                    {imageVal}
                  </span>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setVal(params.screen, params.imageKey!, '')}
                className="p-1 text-rose-400 hover:bg-rose-500/20 rounded transition-all cursor-pointer flex-shrink-0"
                title={isAr ? 'حذف واسترجاع اللون الصافي' : 'Revert to solid color'}
              >
                <X className="w-4 h-4" />
              </button>
            </div>
          )}

          {/* Icon Thumbnail & Clear Button */}
          {params.hasIcon && params.iconKey && iconVal && (
            <div className="bg-[#121316] border border-indigo-500/30 rounded-lg p-2 flex items-center justify-between gap-2 animate-fade-in">
              <div className="flex items-center gap-2 overflow-hidden">
                <img
                  src={iconVal}
                  alt="icon visual"
                  className="w-9 h-9 rounded object-contain border border-white/10 flex-shrink-0 bg-black/40"
                  onError={(e) => { (e.target as any).style.display = 'none'; }}
                />
                <div className="overflow-hidden">
                  <span className="text-[10px] text-indigo-400 font-bold block truncate">
                    {isAr ? 'أيقونة مخصصة من الجهاز' : 'Custom Icon Active'}
                  </span>
                  <span className="text-[9px] text-slate-500 truncate block font-mono" title={iconVal}>
                    {iconVal}
                  </span>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setVal(params.screen, params.iconKey!, '')}
                className="p-1 text-rose-400 hover:bg-rose-500/20 rounded transition-all cursor-pointer flex-shrink-0"
                title={isAr ? 'حذف الأيقونة' : 'Remove icon'}
              >
                <X className="w-4 h-4" />
              </button>
            </div>
          )}

          {/* Advanced Controls: Movement with Arrows (يمين، شمال، فوق، تحت) */}
          <div className="bg-black/40 border border-white/5 rounded-lg p-2.5 space-y-2">
            <div className="flex items-center justify-between text-[11px] text-slate-300">
              <span className="font-semibold flex items-center gap-1 text-slate-300">
                <Move className="w-3.5 h-3.5 text-indigo-400" />
                {isAr ? 'تحريك الموضع بالأسهم:' : 'Position & Arrows:'}
              </span>
              <span className="text-[10px] font-mono text-indigo-300 bg-indigo-500/10 px-2 py-0.5 rounded border border-indigo-500/20">
                X: {offsetX}px | Y: {offsetY}px
              </span>
            </div>

            <div className="flex items-center justify-between gap-2 flex-wrap">
              {/* Arrow pad */}
              <div className="flex items-center gap-1">
                <button
                  type="button"
                  onClick={() => setVal(params.screen, `${params.id}_offset_x`, String(offsetX - 2))}
                  className="p-1.5 bg-white/5 hover:bg-white/15 text-slate-200 rounded border border-white/10 text-xs font-bold transition-all"
                  title={isAr ? 'تحريك يسار (2px-)' : 'Move Left'}
                >
                  <ArrowLeft className="w-3.5 h-3.5" />
                </button>
                <button
                  type="button"
                  onClick={() => setVal(params.screen, `${params.id}_offset_y`, String(offsetY - 2))}
                  className="p-1.5 bg-white/5 hover:bg-white/15 text-slate-200 rounded border border-white/10 text-xs font-bold transition-all"
                  title={isAr ? 'تحريك لأعلى (2px-)' : 'Move Up'}
                >
                  <ArrowUp className="w-3.5 h-3.5" />
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setVal(params.screen, `${params.id}_offset_x`, '0');
                    setVal(params.screen, `${params.id}_offset_y`, '0');
                  }}
                  className="px-2 py-1 bg-white/5 hover:bg-white/15 text-[10px] text-amber-400 rounded border border-white/10 font-bold transition-all"
                  title={isAr ? 'إعادة ضبط الموضع للوسط' : 'Reset to Center'}
                >
                  0
                </button>
                <button
                  type="button"
                  onClick={() => setVal(params.screen, `${params.id}_offset_y`, String(offsetY + 2))}
                  className="p-1.5 bg-white/5 hover:bg-white/15 text-slate-200 rounded border border-white/10 text-xs font-bold transition-all"
                  title={isAr ? 'تحريك لأسفل (2px+)' : 'Move Down'}
                >
                  <ArrowDown className="w-3.5 h-3.5" />
                </button>
                <button
                  type="button"
                  onClick={() => setVal(params.screen, `${params.id}_offset_x`, String(offsetX + 2))}
                  className="p-1.5 bg-white/5 hover:bg-white/15 text-slate-200 rounded border border-white/10 text-xs font-bold transition-all"
                  title={isAr ? 'تحريك يمين (2px+)' : 'Move Right'}
                >
                  <ArrowRight className="w-3.5 h-3.5" />
                </button>
              </div>

              {/* Shape Presets */}
              <div className="flex items-center gap-1">
                <button
                  type="button"
                  onClick={() => setVal(params.screen, `${params.id}_radius`, '999')}
                  className="px-2 py-1 rounded text-[10px] bg-white/5 hover:bg-purple-600/30 text-purple-300 border border-white/10"
                  title={isAr ? 'دائري' : 'Circle'}
                >
                  ⚪ دائري
                </button>
                <button
                  type="button"
                  onClick={() => setVal(params.screen, `${params.id}_radius`, '16')}
                  className="px-2 py-1 rounded text-[10px] bg-white/5 hover:bg-purple-600/30 text-purple-300 border border-white/10"
                  title={isAr ? 'حواف ناعمة' : 'Soft Rounded'}
                >
                  🔲 ناعم
                </button>
                <button
                  type="button"
                  onClick={() => setVal(params.screen, `${params.id}_radius`, '0')}
                  className="px-2 py-1 rounded text-[10px] bg-white/5 hover:bg-purple-600/30 text-purple-300 border border-white/10"
                  title={isAr ? 'مربع' : 'Square'}
                >
                  ▫️ مربع
                </button>
              </div>
            </div>

            {/* Custom dimensions */}
            <div className="grid grid-cols-3 gap-2 pt-1 border-t border-white/5 text-[10px]">
              <div>
                <label className="text-slate-500 block mb-0.5">{isAr ? 'العرض W' : 'Width'}</label>
                <input
                  type="number"
                  placeholder="تلقائي"
                  value={width}
                  onChange={e => setVal(params.screen, `${params.id}_width`, e.target.value)}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded px-2 py-1 text-white text-[11px]"
                />
              </div>
              <div>
                <label className="text-slate-500 block mb-0.5">{isAr ? 'الارتفاع H' : 'Height'}</label>
                <input
                  type="number"
                  placeholder="تلقائي"
                  value={height}
                  onChange={e => setVal(params.screen, `${params.id}_height`, e.target.value)}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded px-2 py-1 text-white text-[11px]"
                />
              </div>
              <div>
                <label className="text-slate-500 block mb-0.5">{isAr ? 'استدارة R' : 'Radius'}</label>
                <input
                  type="number"
                  placeholder="0"
                  value={radius}
                  onChange={e => setVal(params.screen, `${params.id}_radius`, e.target.value)}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded px-2 py-1 text-white text-[11px]"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  };

  // Alias for backward compatibility
  const renderDualField = renderElementEditor;

  return (
    <div className="space-y-6">
      {/* Hidden File Input for Device Uploads */}
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        onChange={handleFileSelected}
        className="hidden"
      />

      {/* Main Top Hero Banner */}
      <div className="bg-gradient-to-r from-purple-900/60 via-indigo-900/40 to-slate-900 border border-purple-500/30 rounded-2xl p-6 shadow-2xl relative overflow-hidden backdrop-blur-md">
        <div className="absolute top-0 right-0 w-96 h-96 bg-purple-500/10 rounded-full blur-3xl pointer-events-none" />
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 relative z-10">
          <div className="flex items-center gap-4">
            <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-purple-600 via-indigo-600 to-pink-500 flex items-center justify-center text-3xl shadow-lg shadow-purple-500/30">
              🎨
            </div>
            <div>
              <h1 className="text-2xl font-black text-white flex items-center gap-3">
                {isAr ? 'مركز التصميم والمظهر الشامل' : 'Unified Design & Customization Center'}
                <span className="text-xs px-3 py-1 rounded-full bg-purple-500/20 text-purple-300 border border-purple-500/40 font-semibold">
                  {isAr ? 'القسم الموحد' : 'All-in-One'}
                </span>
              </h1>
              <p className="text-slate-400 text-xs mt-1 max-w-3xl leading-relaxed">
                {isAr
                  ? 'تحكم كامل وشامل بجميع شاشات ونصوص وكتابات التطبيق بالكامل، مع إمكانية تعديل الألوان أو استبدال أي لون بصورة مرفوعة مباشرة من جهازك لجميع الكروت والخلفيات والأزرار.'
                  : 'Manage all app visuals, customize all texts & strings across all screens, edit dynamic colors or replace any color with an uploaded device image for any card or background.'}
              </p>
            </div>
          </div>

          {activeTab === 'texts_colors' && (
            <button
              onClick={handleSaveAll}
              disabled={saving}
              className="px-6 py-3 rounded-xl bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500 text-white font-bold text-sm shadow-lg shadow-emerald-600/30 flex items-center justify-center gap-2 cursor-pointer transition-all disabled:opacity-50 whitespace-nowrap self-start md:self-auto"
            >
              {saving ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
              <span>{saving ? (isAr ? 'جارٍ الحفظ والتطبيق...' : 'Saving...') : (isAr ? 'حفظ النصوص والألوان والصور' : 'Save Texts, Colors & Images')}</span>
            </button>
          )}
        </div>

        {/* Tab Navigation Buttons */}
        <div className="flex items-center gap-2 mt-6 overflow-x-auto pb-1 scrollbar-thin border-t border-white/10 pt-4">
          {tabs.map(t => {
            const Icon = t.icon;
            const isSelected = activeTab === t.key;
            return (
              <button
                key={t.key}
                onClick={() => handleTabChange(t.key)}
                className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-bold transition-all whitespace-nowrap cursor-pointer ${
                  isSelected
                    ? 'bg-purple-600 text-white shadow-lg shadow-purple-600/30 border border-purple-400/30'
                    : 'bg-white/5 hover:bg-white/10 text-slate-300 border border-white/5'
                }`}
              >
                <Icon className="w-4 h-4" />
                <span>{t.label}</span>
              </button>
            );
          })}
        </div>
      </div>

      {saveSuccess && (
        <div className="bg-emerald-500/15 border border-emerald-500/40 rounded-xl p-4 flex items-center gap-3 text-emerald-400 text-sm animate-fade-in shadow-lg">
          <CheckCircle2 className="w-5 h-5 flex-shrink-0" />
          <span className="font-semibold">
            {isAr
              ? '✓ تم حفظ وتحديث جميع النصوص وتدرجات الألوان والصور المرفوعة بنجاح! تم التفعيل الفوري في التطبيق.'
              : '✓ All texts, dynamic colors, and custom images saved successfully!'}
          </span>
        </div>
      )}

      {/* ========================================================================= */}
      {/* TAB 1: ALL TEXTS, COLORS & DEVICE IMAGE UPLOADER FOR ALL SCREENS         */}
      {/* ========================================================================= */}
      {activeTab === 'texts_colors' && (
        <div className="space-y-8 animate-fade-in">
          {/* Live Interactive Target Preview Bar */}
          <div className="bg-[#121316] border border-white/10 rounded-2xl p-5 shadow-xl">
            <h3 className="text-white text-sm font-bold flex items-center justify-between mb-3">
              <span className="flex items-center gap-2">
                <Eye className="w-4 h-4 text-cyan-400" />
                <span>{isAr ? 'معاينة حية لكروت المستهدف والإنتاج (كما تظهر للمستخدم داخل التطبيق):' : 'Live Preview of Agency Target Cards:'}</span>
              </span>
              <span className="text-[11px] text-slate-400">
                {isAr ? 'تدعم اللون الصافي أو الصورة المرفوعة من الجهاز' : 'Supports solid color or device uploaded image'}
              </span>
            </h3>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              {/* Card 1: Current Target */}
              <div
                className="p-4 rounded-xl border border-white/10 shadow-sm transition-all bg-cover bg-center relative overflow-hidden"
                style={{
                  backgroundColor: getVal('hostAgency', 'targetCardBg', '#F9FAFB'),
                  backgroundImage: getVal('hostAgency', 'targetCardBgImage') ? `url(${getVal('hostAgency', 'targetCardBgImage')})` : undefined,
                }}
              >
                <span className="text-[11px] font-semibold block mb-1 drop-shadow" style={{ color: getVal('hostAgency', 'targetCardValColor', '#1F2937') }}>
                  {getVal('hostAgency', 'curTargetTitle', 'المستهدف الحالي')}
                </span>
                <span className="text-lg font-black block drop-shadow" style={{ color: getVal('hostAgency', 'targetCardValColor', '#1F2937') }}>
                  150,000 💎
                </span>
              </div>

              {/* Card 2: Current Balance */}
              <div
                className="p-4 rounded-xl border border-white/10 shadow-sm transition-all bg-cover bg-center relative overflow-hidden"
                style={{
                  backgroundColor: getVal('hostAgency', 'balanceCardBg', '#ECFDF5'),
                  backgroundImage: getVal('hostAgency', 'balanceCardBgImage') ? `url(${getVal('hostAgency', 'balanceCardBgImage')})` : undefined,
                }}
              >
                <span className="text-[11px] font-semibold block mb-1 drop-shadow" style={{ color: getVal('hostAgency', 'balanceCardValColor', '#059669') }}>
                  {getVal('hostAgency', 'curBalanceTitle', 'الرصيد المحقق')}
                </span>
                <span className="text-lg font-black block drop-shadow" style={{ color: getVal('hostAgency', 'balanceCardValColor', '#059669') }}>
                  125,400 💎
                </span>
              </div>

              {/* Card 3: Next Target */}
              <div
                className="p-4 rounded-xl border border-dashed border-white/20 shadow-sm transition-all bg-cover bg-center relative overflow-hidden"
                style={{
                  backgroundColor: getVal('hostAgency', 'nextTargetCardBg', '#F9FAFB'),
                  backgroundImage: getVal('hostAgency', 'nextTargetCardBgImage') ? `url(${getVal('hostAgency', 'nextTargetCardBgImage')})` : undefined,
                }}
              >
                <span className="text-[11px] font-semibold block mb-1 drop-shadow" style={{ color: getVal('hostAgency', 'nextTargetCardValColor', '#6B7280') }}>
                  {getVal('hostAgency', 'nextTargetTitle', 'المستهدف القادم')}
                </span>
                <span className="text-lg font-black block drop-shadow" style={{ color: getVal('hostAgency', 'nextTargetCardValColor', '#6B7280') }}>
                  300,000 💎
                </span>
              </div>

              {/* Card 4: Next Remaining */}
              <div
                className="p-4 rounded-xl border border-dashed border-white/20 shadow-sm transition-all bg-cover bg-center relative overflow-hidden"
                style={{
                  backgroundColor: getVal('hostAgency', 'nextRemainingCardBg', '#FFFBEB'),
                  backgroundImage: getVal('hostAgency', 'nextRemainingCardBgImage') ? `url(${getVal('hostAgency', 'nextRemainingCardBgImage')})` : undefined,
                }}
              >
                <span className="text-[11px] font-semibold block mb-1 drop-shadow" style={{ color: getVal('hostAgency', 'nextRemainingCardValColor', '#D97706') }}>
                  {getVal('hostAgency', 'nextRemainingTitle', 'المتبقي للهدف القادم')}
                </span>
                <span className="text-lg font-black block drop-shadow" style={{ color: getVal('hostAgency', 'nextRemainingCardValColor', '#D97706') }}>
                  174,600 💎
                </span>
              </div>
            </div>
          </div>

          {/* Quick Filter Categories Bar */}
          <div className="bg-[#121316] border border-white/10 rounded-2xl p-4 shadow-xl space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs text-slate-300 font-bold flex items-center gap-2">
                <Sliders className="w-4 h-4 text-purple-400" />
                {isAr ? 'فلترة حسب شاشة التطبيق:' : 'Filter by App Screen:'}
              </span>
              <span className="text-[11px] text-slate-400">
                {isAr ? 'اضغط على الشاشة للوصول السريع لجميع نصوصها وألوانها وصورها' : 'Click a screen to jump directly'}
              </span>
            </div>

            <div className="flex items-center gap-2 overflow-x-auto pb-1 scrollbar-thin">
              {categories.map(c => (
                <button
                  key={c.id}
                  onClick={() => setActiveSection(c.id)}
                  className={`px-3.5 py-2 rounded-xl text-xs font-bold transition-all whitespace-nowrap cursor-pointer flex items-center gap-1.5 ${
                    activeSection === c.id
                      ? 'bg-purple-600 text-white shadow-lg shadow-purple-600/30'
                      : 'bg-white/5 hover:bg-white/10 text-slate-300 border border-white/5'
                  }`}
                >
                  <span>{c.icon}</span>
                  <span>{isAr ? c.labelAr : c.labelEn}</span>
                </button>
              ))}
            </div>
          </div>

          {/* Search Box */}
          <div className="relative">
            <Search className="w-4 h-4 absolute top-1/2 -translate-y-1/2 right-4 text-slate-400" />
            <input
              type="text"
              value={searchQ}
              onChange={e => setSearchQ(e.target.value)}
              placeholder={isAr ? 'بحث عن أي كلمة، نص، عنوان، كارت، أو عنصر في جميع الشاشات...' : 'Search for any word, label, title, card, or element across all screens...'}
              className="w-full bg-[#121316] border border-white/10 rounded-xl px-11 py-3 text-white text-sm focus:outline-none focus:border-purple-500 placeholder-slate-500"
            />
          </div>

          {/* ================================================================= */}
          {/* SECTION 1: AGENCY & TARGETS                                      */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'agency') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center justify-between border-b border-white/10 pb-4">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-xl bg-amber-500/20 text-amber-400 flex items-center justify-center font-bold text-lg">
                    🎯
                  </div>
                  <div>
                    <h3 className="text-base font-bold text-white">
                      {isAr ? '1. مستهدف الوكالات والمضيفين ونصوص الأهداف والرواتب' : '1. Agency & Host Targets, Salaries & Cards'}
                    </h3>
                    <p className="text-slate-400 text-xs">
                      {isAr
                        ? 'تعديل جميع نصوص كروت التارجت والأرباح والرواتب، مع إمكانية تعديل اللون أو استبداله بصورة مرفوعة من الجهاز'
                        : 'Customize target texts, salaries, and edit background color or upload an image for each card'}
                    </p>
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'curTarget',
                  category: 'agency',
                  screen: 'hostAgency',
                  labelAr: 'كارت المستهدف الحالي',
                  labelEn: 'Current Target Card',
                  hasText: true,
                  textKey: 'curTargetTitle',
                  defaultText: 'المستهدف الحالي',
                  textColorKey: 'targetCardValColor',
                  defaultTextColor: '#1F2937',
                  hasColor: true,
                  colorKey: 'targetCardBg',
                  defaultColor: '#F9FAFB',
                  hasImage: true,
                  imageKey: 'targetCardBgImage',
                })}

                {renderDualField({
                  id: 'curBalance',
                  category: 'agency',
                  screen: 'hostAgency',
                  labelAr: 'كارت الرصيد المحقق',
                  labelEn: 'Current Balance Card',
                  hasText: true,
                  textKey: 'curBalanceTitle',
                  defaultText: 'الرصيد المحقق',
                  textColorKey: 'balanceCardValColor',
                  defaultTextColor: '#059669',
                  hasColor: true,
                  colorKey: 'balanceCardBg',
                  defaultColor: '#ECFDF5',
                  hasImage: true,
                  imageKey: 'balanceCardBgImage',
                })}

                {renderDualField({
                  id: 'nextTarget',
                  category: 'agency',
                  screen: 'hostAgency',
                  labelAr: 'كارت المستهدف القادم',
                  labelEn: 'Next Target Card',
                  hasText: true,
                  textKey: 'nextTargetTitle',
                  defaultText: 'المستهدف القادم',
                  textColorKey: 'nextTargetCardValColor',
                  defaultTextColor: '#6B7280',
                  hasColor: true,
                  colorKey: 'nextTargetCardBg',
                  defaultColor: '#F9FAFB',
                  hasImage: true,
                  imageKey: 'nextTargetCardBgImage',
                })}

                {renderDualField({
                  id: 'nextRemaining',
                  category: 'agency',
                  screen: 'hostAgency',
                  labelAr: 'كارت المتبقي للهدف القادم',
                  labelEn: 'Next Remaining Card',
                  hasText: true,
                  textKey: 'nextRemainingTitle',
                  defaultText: 'المتبقي للهدف القادم',
                  textColorKey: 'nextRemainingCardValColor',
                  defaultTextColor: '#D97706',
                  hasColor: true,
                  colorKey: 'nextRemainingCardBg',
                  defaultColor: '#FFFBEB',
                  hasImage: true,
                  imageKey: 'nextRemainingCardBgImage',
                })}

                {renderDualField({
                  id: 'agencyDiamondTarget',
                  category: 'agency',
                  screen: 'hostAgency',
                  labelAr: 'عنوان مستهدف ألماس الوكالة',
                  labelEn: 'Agency Diamond Target',
                  hasText: true,
                  textKey: 'agencyTargetTitle',
                  defaultText: 'مستهدف ألماس الوكالة',
                  hasColor: true,
                  colorKey: 'diamondCardBgImage',
                  hasImage: true,
                  imageKey: 'diamondCardBgImage',
                })}

                {renderDualField({
                  id: 'myDiamondTarget',
                  category: 'agency',
                  screen: 'hostAgency',
                  labelAr: 'عنوان مستهدف ألماسي الحالي',
                  labelEn: 'My Diamond Target',
                  hasText: true,
                  textKey: 'myTargetTitle',
                  defaultText: 'مستهدف ألماسي الحالي',
                  hasColor: true,
                  colorKey: 'cardColor',
                  defaultColor: '#00B5B3',
                  hasImage: true,
                  imageKey: 'levelCardBgImage',
                })}

                {renderDualField({
                  id: 'agencyBalanceTitle',
                  category: 'agency',
                  screen: 'hostAgency',
                  labelAr: 'عنوان إنتاج ألماس الوكالة',
                  labelEn: 'Agency Diamond Production',
                  hasText: true,
                  textKey: 'agencyBalanceTitle',
                  defaultText: 'إنتاج ألماس الوكالة',
                })}

                {renderDualField({
                  id: 'myBalanceTitle',
                  category: 'agency',
                  screen: 'hostAgency',
                  labelAr: 'عنوان رصيدي المحقق حالياً',
                  labelEn: 'My Current Balance',
                  hasText: true,
                  textKey: 'myBalanceTitle',
                  defaultText: 'رصيدي المحقق حالياً',
                })}

                {renderDualField({
                  id: 'hoursCard',
                  category: 'agency',
                  screen: 'hostAgency',
                  labelAr: 'كارت ساعات البث المعتمدة',
                  labelEn: 'Broadcast Hours Card',
                  hasText: true,
                  textKey: 'hoursTitle',
                  defaultText: 'ساعات البث المعتمدة',
                  hasColor: true,
                  colorKey: 'cardColor',
                  defaultColor: '#16151A',
                  hasImage: true,
                  imageKey: 'hoursCardBgImage',
                })}

                {renderDualField({
                  id: 'salaryCard',
                  category: 'agency',
                  screen: 'hostAgency',
                  labelAr: 'كارت أرباح وراتب الوكالة',
                  labelEn: 'Agency Salary Card',
                  hasText: true,
                  textKey: 'salaryTitle',
                  defaultText: 'أرباح وراتب الوكالة',
                  hasColor: true,
                  colorKey: 'cardColor',
                  defaultColor: '#00B5B3',
                  hasImage: true,
                  imageKey: 'salaryCardBgImage',
                })}

                {renderDualField({
                  id: 'addMemberBtn',
                  category: 'agency',
                  screen: 'hostAgency',
                  labelAr: 'زر إضافة عضو للوكالة',
                  labelEn: 'Add Member Button',
                  hasText: true,
                  textKey: 'addMemberButtonText',
                  defaultText: 'إضافة عضو',
                  hasImage: true,
                  imageKey: 'addMemberButtonImage',
                })}

                {renderDualField({
                  id: 'agencyBg',
                  category: 'agency',
                  screen: 'hostAgency',
                  labelAr: 'خلفية وهيدر شاشة الوكالة والمضيفين',
                  labelEn: 'Host Agency Background & Header',
                  hasColor: true,
                  colorKey: 'headerColor',
                  defaultColor: '#16151A',
                  hasImage: true,
                  imageKey: 'backgroundImage',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 2: PROFILE & USER PROFILE                                */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'profile') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-blue-500/20 text-blue-400 flex items-center justify-center font-bold text-lg">
                  👤
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '2. شاشة حسابي والملف الشخصي والبروفايل' : '2. Profile & User Profile Screens'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'تعديل نصوص المتابعين، الزوار، الهدايا، وكروت البروفايل وخلفياتها بالصور أو الألوان' : 'Customize profile metrics, labels, cards, and backgrounds'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'profileScreenTitle',
                  category: 'profile',
                  screen: 'profile',
                  labelAr: 'عنوان شاشة حسابي (البروفايل)',
                  labelEn: 'Profile Screen Title',
                  hasText: true,
                  textKey: 'profileTitle',
                  defaultText: 'حسابي',
                  hasColor: true,
                  colorKey: 'backgroundColor',
                  defaultColor: '#F6F7F9',
                  hasImage: true,
                  imageKey: 'backgroundImage',
                })}

                {renderDualField({
                  id: 'profileCard',
                  category: 'profile',
                  screen: 'profile',
                  labelAr: 'كروت وبطاقات البروفايل',
                  labelEn: 'Profile Cards Background',
                  hasColor: true,
                  colorKey: 'cardBgColor',
                  defaultColor: '#FFFFFF',
                  textColorKey: 'textColor',
                  defaultTextColor: '#000000',
                  hasImage: true,
                  imageKey: 'cardBgImage',
                })}

                {renderDualField({
                  id: 'followersTitle',
                  category: 'profile',
                  screen: 'userProfile',
                  labelAr: 'كارت وخانة المتابعين',
                  labelEn: 'Followers Metric Card',
                  hasText: true,
                  textKey: 'followersTitle',
                  defaultText: 'المتابعون',
                  hasImage: true,
                  imageKey: 'followersImage',
                })}

                {renderDualField({
                  id: 'visitorsTitle',
                  category: 'profile',
                  screen: 'userProfile',
                  labelAr: 'كارت وخانة الزوار',
                  labelEn: 'Visitors Metric Card',
                  hasText: true,
                  textKey: 'visitorsTitle',
                  defaultText: 'الزوار',
                  hasImage: true,
                  imageKey: 'visitorsImage',
                })}

                {renderDualField({
                  id: 'giftWallCard',
                  category: 'profile',
                  screen: 'userProfile',
                  labelAr: 'كارت جدار الهدايا بالبروفايل',
                  labelEn: 'Gift Wall Profile Card',
                  hasText: true,
                  textKey: 'giftWallTitle',
                  defaultText: 'جدار الهدايا',
                  hasColor: true,
                  colorKey: 'giftWallCardBorder',
                  defaultColor: '#1AFFFFFF',
                  hasImage: true,
                  imageKey: 'giftWallCardBg',
                })}

                {renderDualField({
                  id: 'vehicleCard',
                  category: 'profile',
                  screen: 'userProfile',
                  labelAr: 'كارت المركبة والدخول بالبروفايل',
                  labelEn: 'Vehicle Card Background',
                  hasText: true,
                  textKey: 'vehicleTitle',
                  defaultText: 'المركبة',
                  hasImage: true,
                  imageKey: 'vehicleCardBg',
                })}

                {renderDualField({
                  id: 'frameCard',
                  category: 'profile',
                  screen: 'userProfile',
                  labelAr: 'كارت إطار الأفاتار بالبروفايل',
                  labelEn: 'Avatar Frame Card Background',
                  hasText: true,
                  textKey: 'frameTitle',
                  defaultText: 'الإطار',
                  hasImage: true,
                  imageKey: 'frameCardBg',
                })}

                {renderDualField({
                  id: 'supportersBanner',
                  category: 'profile',
                  screen: 'userProfile',
                  labelAr: 'بانر الداعمين بالملف الشخصي',
                  labelEn: 'Supporters Banner',
                  hasText: true,
                  textKey: 'supportersTitle',
                  defaultText: 'أبرز الداعمين',
                  hasImage: true,
                  imageKey: 'supportersBanner',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 3: ROOMS, SEATS & CHAT                                   */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'room') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-emerald-500/20 text-emerald-400 flex items-center justify-center font-bold text-lg">
                  🎙️
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '3. الغرف الصوتية، المقاعد، والمحادثة المباشرة' : '3. Audio Rooms, Voice Seats & Live Chat'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'تعديل نصوص المقاعد، الشات، كارت المستخدم، وشكل المايكات والخلفيات بالصور والألوان' : 'Customize voice seats, chat placeholder, user cards, and mic shapes'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'roomsScreenTitle',
                  category: 'room',
                  screen: 'room',
                  labelAr: 'عنوان شاشة الغرف وخلفية الغرفة',
                  labelEn: 'Rooms Screen Title & Room Background',
                  hasText: true,
                  textKey: 'roomsTitle',
                  defaultText: 'الغرف الصوتية',
                  hasColor: true,
                  colorKey: 'headerBgColor',
                  defaultColor: '#121316',
                  hasImage: true,
                  imageKey: 'backgroundImage',
                })}

                {renderDualField({
                  id: 'micSeatsTitle',
                  category: 'room',
                  screen: 'room',
                  labelAr: 'عنوان المقاعد الصوتية',
                  labelEn: 'Mic Seats Title',
                  hasText: true,
                  textKey: 'micSeatsTitle',
                  defaultText: 'المقاعد الصوتية',
                  hasImage: true,
                  imageKey: 'seatDefaultCircleImage',
                })}

                {renderDualField({
                  id: 'seatLockCircle',
                  category: 'room',
                  screen: 'room',
                  labelAr: 'صورة المقعد المقفل (Lock)',
                  labelEn: 'Seat Locked Circle Image',
                  hasImage: true,
                  imageKey: 'seatLockCircleImage',
                })}

                {renderDualField({
                  id: 'roomChatPlaceholder',
                  category: 'room',
                  screen: 'room',
                  labelAr: 'تلميح حقل كتابة الرسائل بالغرفة',
                  labelEn: 'Room Chat Input Placeholder',
                  hasText: true,
                  textKey: 'chatPlaceholder',
                  defaultText: 'اكتب رسالة جميلة...',
                })}

                {renderDualField({
                  id: 'roomSendBtnText',
                  category: 'room',
                  screen: 'room',
                  labelAr: 'نص زر إرسال الرسالة',
                  labelEn: 'Send Message Button Text',
                  hasText: true,
                  textKey: 'sendBtnText',
                  defaultText: 'إرسال',
                })}

                {renderDualField({
                  id: 'leaveRoomText',
                  category: 'room',
                  screen: 'room',
                  labelAr: 'نص زر مغادرة الغرفة',
                  labelEn: 'Leave Room Button Text',
                  hasText: true,
                  textKey: 'leaveRoomText',
                  defaultText: 'مغادرة الغرفة',
                  hasColor: true,
                  colorKey: 'exitSheetBgColor',
                  defaultColor: '#16151A',
                })}

                {renderDualField({
                  id: 'userCardRoom',
                  category: 'room',
                  screen: 'room',
                  labelAr: 'كارت المستخدم عند الضغط على المايك',
                  labelEn: 'User Sheet Card in Room',
                  hasColor: true,
                  colorKey: 'userCardBgColor',
                  defaultColor: '#16151A',
                  hasImage: true,
                  imageKey: 'userCardBgImage',
                })}

                {renderDualField({
                  id: 'luckyBoxText',
                  category: 'room',
                  screen: 'room',
                  labelAr: 'نص ولافته صندوق الحظ',
                  labelEn: 'Lucky Box Title & Banner',
                  hasText: true,
                  textKey: 'luckyBoxText',
                  defaultText: 'صندوق الحظ 🎁',
                })}

                {renderDualField({
                  id: 'gameBarRoom',
                  category: 'room',
                  screen: 'room',
                  labelAr: 'شريط الألعاب والفعاليات بالغرفة',
                  labelEn: 'Room Game Bar Background',
                  hasColor: true,
                  colorKey: 'gameBarBgColor',
                  defaultColor: '#1AFFFFFF',
                  textColorKey: 'gameBarTextColor',
                  defaultTextColor: '#FFFFFF',
                  hasImage: true,
                  imageKey: 'gameIconImage',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 4: WALLET & RECHARGE                                     */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'wallet') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-cyan-500/20 text-cyan-400 flex items-center justify-center font-bold text-lg">
                  💳
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '4. المحفظة وبوابة شحن الوكلاء وتبديل العملات' : '4. Wallet, Recharge & Exchange Screens'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'تعديل نصوص رصيد الكوينز والألماس، كروت الشحن، أزرار التأكيد والصور الخاصة بها' : 'Customize wallet balances, recharge cards, exchange titles, and button images'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'walletScreenTitle',
                  category: 'wallet',
                  screen: 'wallet',
                  labelAr: 'شاشة المحفظة الرئيسية',
                  labelEn: 'Wallet Screen Background & Title',
                  hasText: true,
                  textKey: 'walletTitle',
                  defaultText: 'محفظتي',
                  hasColor: true,
                  colorKey: 'cardBgColor',
                  defaultColor: '#16151A',
                  hasImage: true,
                  imageKey: 'backgroundImage',
                })}

                {renderDualField({
                  id: 'coinsBalanceCard',
                  category: 'wallet',
                  screen: 'agentRecharge',
                  labelAr: 'كارت رصيد الكوينز',
                  labelEn: 'Coins Balance Card',
                  hasText: true,
                  textKey: 'coinsBalanceTitle',
                  defaultText: 'رصيد الكوينز',
                  textColorKey: 'coinsTextColor',
                  defaultTextColor: '#FDE638',
                  hasImage: true,
                  imageKey: 'coinsBgImage',
                })}

                {renderDualField({
                  id: 'diamondsBalanceCard',
                  category: 'wallet',
                  screen: 'agentRecharge',
                  labelAr: 'كارت رصيد الألماس',
                  labelEn: 'Diamonds Balance Card',
                  hasText: true,
                  textKey: 'diamondsBalanceTitle',
                  defaultText: 'رصيد الألماس',
                  hasImage: true,
                  imageKey: 'diamondsBgImage',
                })}

                {renderDualField({
                  id: 'transferCard',
                  category: 'wallet',
                  screen: 'agentRecharge',
                  labelAr: 'كارت نموذج التحويل والشحن',
                  labelEn: 'Transfer Form Card',
                  hasText: true,
                  textKey: 'transferTitle',
                  defaultText: 'تحويل الكوينز',
                  hasColor: true,
                  colorKey: 'cardColor',
                  defaultColor: '#141C24',
                  hasImage: true,
                  imageKey: 'transferCardBgImage',
                })}

                {renderDualField({
                  id: 'confirmTransferBtn',
                  category: 'wallet',
                  screen: 'agentRecharge',
                  labelAr: 'زر تأكيد الشحن والتحويل',
                  labelEn: 'Confirm Transfer Button',
                  hasText: true,
                  textKey: 'confirmTransferText',
                  defaultText: 'تأكيد الشحن والتحويل',
                  hasColor: true,
                  colorKey: 'accentColor',
                  defaultColor: '#3ED78A',
                  hasImage: true,
                  imageKey: 'confirmButtonImage',
                })}

                {renderDualField({
                  id: 'exchangeTitle',
                  category: 'wallet',
                  screen: 'wallet',
                  labelAr: 'عنوان تبديل الألماس إلى كوينز',
                  labelEn: 'Diamond to Coin Exchange Title',
                  hasText: true,
                  textKey: 'exchangeTitle',
                  defaultText: 'تبديل الألماس إلى كوينز',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 5: STORE & VIP                                           */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'store') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-pink-500/20 text-pink-400 flex items-center justify-center font-bold text-lg">
                  🛍️
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '5. المتجر، الحقيبة، ومركز VIP' : '5. Store, Backpack & VIP Center'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'تعديل نصوص المتجر والحقيبة، كروت الاشتراكات، أزرار الشراء، وخلفيات VIP' : 'Customize store items, backpack tabs, VIP card, and purchase buttons'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'storeScreenTitle',
                  category: 'store',
                  screen: 'store',
                  labelAr: 'شاشة المتجر الرئيسية',
                  labelEn: 'Store Screen Title & Background',
                  hasText: true,
                  textKey: 'storeTitle',
                  defaultText: 'المتجر',
                  hasColor: true,
                  colorKey: 'headerBgColor',
                  defaultColor: '#1A1A2E',
                  hasImage: true,
                  imageKey: 'backgroundImage',
                })}

                {renderDualField({
                  id: 'vipScreenCard',
                  category: 'store',
                  screen: 'vip',
                  labelAr: 'كارت وخلفية مركز VIP',
                  labelEn: 'VIP Center Screen Card & Title',
                  hasText: true,
                  textKey: 'vipTitle',
                  defaultText: 'مركز VIP',
                  hasColor: true,
                  colorKey: 'vipCardBgColor',
                  defaultColor: '#1A3D1A',
                  hasImage: true,
                  imageKey: 'vipCardBgImgUrl',
                })}

                {renderDualField({
                  id: 'vipBuyBtn',
                  category: 'store',
                  screen: 'vip',
                  labelAr: 'زر شراء وتجديد اشتراك VIP',
                  labelEn: 'VIP Purchase / Subscribe Button',
                  hasText: true,
                  textKey: 'vipBuyBtnText',
                  defaultText: 'ترقية إلى VIP 👑',
                  hasImage: true,
                  imageKey: 'vipBuyBtnImgUrl',
                })}

                {renderDualField({
                  id: 'backpackCard',
                  category: 'store',
                  screen: 'backpack',
                  labelAr: 'شاشة وكروت الحقيبة الشخصية',
                  labelEn: 'Backpack Screen Cards',
                  hasColor: true,
                  colorKey: 'cardBgColor',
                  defaultColor: '#16151A',
                  hasImage: true,
                  imageKey: 'backgroundImage',
                })}

                {renderDualField({
                  id: 'storeItemsCard',
                  category: 'store',
                  screen: 'store',
                  labelAr: 'كروت عناصر المتجر (الإطارات والدخوليات)',
                  labelEn: 'Store Item Card Background',
                  hasColor: true,
                  colorKey: 'cardBgColor',
                  defaultColor: '#16151A',
                  hasImage: true,
                  imageKey: 'cardBgImage',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 6: CP SPACE                                             */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'cp') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-rose-500/20 text-rose-400 flex items-center justify-center font-bold text-lg">
                  💑
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '6. مساحة الارتباط والعلاقات CP' : '6. CP Space & Relationship Screens'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'تعديل نصوص علاقة CP، بطاقة الشريكين، كابينة CP، أزرار الدعوة، وإطارات الحب' : 'Customize CP relationship title, partner card, love points, and cabin backgrounds'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'cpScreenTitle',
                  category: 'cp',
                  screen: 'cp',
                  labelAr: 'شاشة علاقة CP وخلفيتها بالكامل',
                  labelEn: 'CP Space Title & Full Screen Background',
                  hasText: true,
                  textKey: 'cpTitle',
                  defaultText: 'مساحة CP',
                  hasColor: true,
                  colorKey: 'headerBgColor',
                  defaultColor: '#E91E8C',
                  hasImage: true,
                  imageKey: 'fullScreenBg',
                })}

                {renderDualField({
                  id: 'cpCabinCard',
                  category: 'cp',
                  screen: 'cp',
                  labelAr: 'خلفية كابينة العشاق (Cabin)',
                  labelEn: 'CP Cabin Background Image',
                  hasImage: true,
                  imageKey: 'cabinBg',
                })}

                {renderDualField({
                  id: 'cpPartnerCard',
                  category: 'cp',
                  screen: 'cp',
                  labelAr: 'كارت معلومات وبيانات الشريكين',
                  labelEn: 'CP Partner Card Background',
                  hasColor: true,
                  colorKey: 'cardBgColor',
                  defaultColor: '#FFFFFF',
                  textColorKey: 'textColor',
                  defaultTextColor: '#5D1A3A',
                  hasImage: true,
                  imageKey: 'cardBgImage',
                })}

                {renderDualField({
                  id: 'cpHeartImage',
                  category: 'cp',
                  screen: 'cp',
                  labelAr: 'صورة وأيقونة قلب الارتباط',
                  labelEn: 'CP Relationship Heart Image',
                  hasImage: true,
                  imageKey: 'heartImage',
                })}

                {renderDualField({
                  id: 'cpButton',
                  category: 'cp',
                  screen: 'cp',
                  labelAr: 'زر إرسال دعوة الارتباط',
                  labelEn: 'Send CP Invitation Button',
                  hasColor: true,
                  colorKey: 'buttonColor',
                  defaultColor: '#E91E8C',
                  textColorKey: 'buttonTextColor',
                  defaultTextColor: '#FFFFFF',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 7: DAILY SIGN-IN                                         */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'signin') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-amber-500/20 text-amber-400 flex items-center justify-center font-bold text-lg">
                  📅
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '7. تسجيل الدخول اليومي والمكافآت' : '7. Daily Sign-In & Rewards'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'تعديل نصوص التسجيل اليومي، خلايا الأيام، زر الاستلام، وخلفية شاشة المكافآت' : 'Customize daily sign-in texts, day cells, claim button, and rewards background'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'signinScreen',
                  category: 'signin',
                  screen: 'signin',
                  labelAr: 'خلفية وهيدر تسجيل الدخول اليومي',
                  labelEn: 'Daily Sign-In Header & Background',
                  hasColor: true,
                  colorKey: 'headerBgColor',
                  defaultColor: '#2E0D15',
                  hasImage: true,
                  imageKey: 'backgroundImage',
                })}

                {renderDualField({
                  id: 'signinCard',
                  category: 'signin',
                  screen: 'signin',
                  labelAr: 'كارت جدول أيام الأسبوع',
                  labelEn: 'Days Table Card Background',
                  hasColor: true,
                  colorKey: 'cardBgColor',
                  defaultColor: '#3D1520',
                  hasImage: true,
                  imageKey: 'cardBgImage',
                })}

                {renderDualField({
                  id: 'signinClaimBtn',
                  category: 'signin',
                  screen: 'signin',
                  labelAr: 'زر استلام المكافأة اليومية',
                  labelEn: 'Claim Daily Reward Button',
                  hasColor: true,
                  colorKey: 'buttonColor',
                  defaultColor: '#DE880F',
                  textColorKey: 'buttonTextColor',
                  defaultTextColor: '#FFFFFF',
                  hasImage: true,
                  imageKey: 'buttonImage',
                })}

                {renderDualField({
                  id: 'dayActiveColor',
                  category: 'signin',
                  screen: 'signin',
                  labelAr: 'لون خلية اليوم الحالي (المتاح)',
                  labelEn: 'Current Day Cell Color',
                  hasColor: true,
                  colorKey: 'dayActiveColor',
                  defaultColor: '#5A2030',
                })}

                {renderDualField({
                  id: 'dayClaimedColor',
                  category: 'signin',
                  screen: 'signin',
                  labelAr: 'لون الخلية المستلمة (تم التسجيل)',
                  labelEn: 'Claimed Day Cell Color',
                  hasColor: true,
                  colorKey: 'dayClaimedColor',
                  defaultColor: '#1A4A1A',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 8: RANKINGS & LEADERBOARDS                               */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'rankings') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-yellow-500/20 text-yellow-400 flex items-center justify-center font-bold text-lg">
                  🏆
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '8. شاشة الترتيب وقوائم المتصدرين' : '8. Rankings & Leaderboards'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'تعديل خلفية شاشة الترتيب، رايات وإطارات المراكز الثلاثة الأولى، وألوان المراكز' : 'Customize rankings background, rank 1/2/3 frames and banners'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'rankBgImage',
                  category: 'rankings',
                  screen: 'rank',
                  labelAr: 'خلفية شاشة الترتيب بالكامل',
                  labelEn: 'Rankings Full Screen Background',
                  hasImage: true,
                  imageKey: 'bgImage',
                })}

                {renderDualField({
                  id: 'rankListBgImage',
                  category: 'rankings',
                  screen: 'rank',
                  labelAr: 'خلفية قائمة المتصدرين (من المركز 4 فما فوق)',
                  labelEn: 'Rankings List Background (Rank 4+)',
                  hasColor: true,
                  colorKey: 'cardBgColor',
                  defaultColor: '#16213E',
                  hasImage: true,
                  imageKey: 'listBgImage',
                })}

                {renderDualField({
                  id: 'rank1Decor',
                  category: 'rankings',
                  screen: 'rank',
                  labelAr: 'إطار المركز الأول 🥇 (Rank 1 Frame)',
                  labelEn: 'Rank 1 Frame Image',
                  hasImage: true,
                  imageKey: 'rank1Frame',
                })}

                {renderDualField({
                  id: 'rank1Banner',
                  category: 'rankings',
                  screen: 'rank',
                  labelAr: 'راية المركز الأول 🥇 (Rank 1 Banner)',
                  labelEn: 'Rank 1 Banner Image',
                  hasImage: true,
                  imageKey: 'rank1Banner',
                })}

                {renderDualField({
                  id: 'rank2Decor',
                  category: 'rankings',
                  screen: 'rank',
                  labelAr: 'إطار المركز الثاني 🥈 (Rank 2 Frame)',
                  labelEn: 'Rank 2 Frame Image',
                  hasImage: true,
                  imageKey: 'rank2Frame',
                })}

                {renderDualField({
                  id: 'rank3Decor',
                  category: 'rankings',
                  screen: 'rank',
                  labelAr: 'إطار المركز الثالث 🥉 (Rank 3 Frame)',
                  labelEn: 'Rank 3 Frame Image',
                  hasImage: true,
                  imageKey: 'rank3Frame',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 9: BADGES & NECKLACES                                    */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'badges') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-indigo-500/20 text-indigo-400 flex items-center justify-center font-bold text-lg">
                  🎖️
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '9. الشارات، الأوسمة، والقلادات' : '9. Badges & Necklaces Screens'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'تعديل كروت الشارات والقلادات، الحدود، وخلفيات الشاشات بالصور أو الألوان' : 'Customize badge cards, necklace frames, and backgrounds'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'badgesBg',
                  category: 'badges',
                  screen: 'badges',
                  labelAr: 'خلفية وهيدر شاشة الشارات',
                  labelEn: 'Badges Screen Header & Background',
                  hasColor: true,
                  colorKey: 'headerBgColor',
                  defaultColor: '#1A1A2E',
                  hasImage: true,
                  imageKey: 'backgroundImage',
                })}

                {renderDualField({
                  id: 'badgeCard',
                  category: 'badges',
                  screen: 'badges',
                  labelAr: 'كارت الشارة وخلفيتها',
                  labelEn: 'Badge Card Background',
                  hasColor: true,
                  colorKey: 'badgeBgColor',
                  defaultColor: '#1A1A2E',
                  hasImage: true,
                  imageKey: 'badgeBgImage',
                })}

                {renderDualField({
                  id: 'badgeBorder',
                  category: 'badges',
                  screen: 'badges',
                  labelAr: 'حدود وإطار الشارة',
                  labelEn: 'Badge Border Image or Color',
                  hasColor: true,
                  colorKey: 'badgeBorderColor',
                  defaultColor: '#F0C724',
                  hasImage: true,
                  imageKey: 'badgeBorderImage',
                })}

                {renderDualField({
                  id: 'necklacesBg',
                  category: 'badges',
                  screen: 'necklaces',
                  labelAr: 'خلفية وهيدر شاشة القلادات',
                  labelEn: 'Necklaces Screen Header & Background',
                  hasColor: true,
                  colorKey: 'headerBgColor',
                  defaultColor: '#1A1A2E',
                  hasImage: true,
                  imageKey: 'backgroundImage',
                })}

                {renderDualField({
                  id: 'necklaceCard',
                  category: 'badges',
                  screen: 'necklaces',
                  labelAr: 'كارت القلادة وخلفيتها',
                  labelEn: 'Necklace Card Background',
                  hasColor: true,
                  colorKey: 'necklaceBgColor',
                  defaultColor: '#1A1A2E',
                  hasImage: true,
                  imageKey: 'necklaceBgImage',
                })}

                {renderDualField({
                  id: 'necklaceBorder',
                  category: 'badges',
                  screen: 'necklaces',
                  labelAr: 'حدود وإطار القلادة',
                  labelEn: 'Necklace Border Image or Color',
                  hasColor: true,
                  colorKey: 'necklaceBorderColor',
                  defaultColor: '#E94560',
                  hasImage: true,
                  imageKey: 'necklaceBorderImage',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 10: CHAT & MESSAGES                                      */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'chat') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-purple-500/20 text-purple-400 flex items-center justify-center font-bold text-lg">
                  💬
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '10. المحادثات والرسائل الفردية' : '10. 1-on-1 Messages & Chat'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'تعديل نصوص شاشة الرسائل، خلفيات فقاعات المحادثة (المرسلة والمستلمة) والألوان' : 'Customize messages screen, chat bubble colors, and backgrounds'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'messageScreenTitle',
                  category: 'chat',
                  screen: 'message',
                  labelAr: 'شاشة الرسائل والمحادثات',
                  labelEn: 'Messages Screen Title & Background',
                  hasText: true,
                  textKey: 'messageTitle',
                  defaultText: 'الرسائل',
                  hasColor: true,
                  colorKey: 'backgroundColor',
                  defaultColor: '#FFFFFF',
                  hasImage: true,
                  imageKey: 'backgroundImage',
                })}

                {renderDualField({
                  id: 'bubbleSelf',
                  category: 'chat',
                  screen: 'chat',
                  labelAr: 'فقاعة رسائل المستخدم (أنا)',
                  labelEn: 'Self Chat Message Bubble Color',
                  hasColor: true,
                  colorKey: 'bubbleSelfBgColor',
                  defaultColor: '#FFE082',
                })}

                {renderDualField({
                  id: 'bubbleOther',
                  category: 'chat',
                  screen: 'chat',
                  labelAr: 'فقاعة رسائل الطرف الآخر (المستلمة)',
                  labelEn: 'Other Chat Message Bubble Color',
                  hasColor: true,
                  colorKey: 'bubbleOtherBgColor',
                  defaultColor: '#FFFFFF',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 11: UNIONS & FAMILIES SCREEN                              */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'unions') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-amber-500/20 text-amber-400 flex items-center justify-center font-bold text-lg">
                  🏰
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '11. شاشة العائلات والنقابات' : '11. Unions & Families Screen'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'تخصيص نصوص وألوان وخلفيات وكروت نقابات وعائلات التطبيق' : 'Customize union headers, creation buttons, rank cards, and member badges'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'unionsMainBg',
                  category: 'unions',
                  screen: 'unions',
                  labelAr: 'خلفية شاشة النقابات بالكامل',
                  labelEn: 'Unions Screen Background',
                  hasColor: true,
                  colorKey: 'backgroundColor',
                  defaultColor: '#0F172A',
                  hasImage: true,
                  imageKey: 'backgroundImage',
                })}

                {renderDualField({
                  id: 'unionsHeaderTitle',
                  category: 'unions',
                  screen: 'unions',
                  labelAr: 'عنوان شاشة النقابات',
                  labelEn: 'Unions Screen Title',
                  hasText: true,
                  textKey: 'titleText',
                  defaultText: 'نقابات وعائلات التطبيق',
                  textColorKey: 'titleTextColor',
                  defaultTextColor: '#FFFFFF',
                })}

                {renderDualField({
                  id: 'unionsCreateBtn',
                  category: 'unions',
                  screen: 'unions',
                  labelAr: 'زر إنشاء نقابة جديدة',
                  labelEn: 'Create Union Button',
                  hasText: true,
                  textKey: 'createBtnText',
                  defaultText: 'إنشاء نقابة جديدة',
                  textColorKey: 'createBtnTextColor',
                  defaultTextColor: '#FFFFFF',
                  hasColor: true,
                  colorKey: 'createBtnBg',
                  defaultColor: '#6366F1',
                  hasImage: true,
                  imageKey: 'createBtnBgImage',
                })}

                {renderDualField({
                  id: 'unionsCardBg',
                  category: 'unions',
                  screen: 'unions',
                  labelAr: 'كارت تفاصيل النقابة',
                  labelEn: 'Union Info Card Background',
                  hasColor: true,
                  colorKey: 'cardBgColor',
                  defaultColor: '#1E293B',
                  hasImage: true,
                  imageKey: 'cardBgImage',
                })}

                {renderDualField({
                  id: 'unionsRankingCard',
                  category: 'unions',
                  screen: 'unions',
                  labelAr: 'كارت قائمة ترتيب النقابات',
                  labelEn: 'Union Rankings Card Background',
                  hasColor: true,
                  colorKey: 'rankingCardBg',
                  defaultColor: '#1E293B',
                  hasImage: true,
                  imageKey: 'rankingCardBgImage',
                })}

                {renderDualField({
                  id: 'unionsMembersLabel',
                  category: 'unions',
                  screen: 'unions',
                  labelAr: 'نص وألوان عداد الأعضاء',
                  labelEn: 'Members Count Label',
                  hasText: true,
                  textKey: 'membersLabelText',
                  defaultText: 'الأعضاء النشطين',
                  textColorKey: 'membersLabelColor',
                  defaultTextColor: '#94A3B8',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 12: SETTINGS & SECURITY SCREEN                            */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'settings') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-slate-500/20 text-slate-300 flex items-center justify-center font-bold text-lg">
                  ⚙️
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '12. شاشة الإعدادات والأمان والنظام' : '12. Settings & Security Screen'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'تخصيص نصوص وألوان وخلفيات شاشة الإعدادات والحساب ومركز الأمان' : 'Customize settings rows, backgrounds, and titles'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'settingsMainBg',
                  category: 'settings',
                  screen: 'settings',
                  labelAr: 'خلفية شاشة الإعدادات بالكامل',
                  labelEn: 'Settings Screen Background',
                  hasColor: true,
                  colorKey: 'backgroundColor',
                  defaultColor: '#121316',
                  hasImage: true,
                  imageKey: 'backgroundImage',
                })}

                {renderDualField({
                  id: 'settingsTitle',
                  category: 'settings',
                  screen: 'settings',
                  labelAr: 'عنوان شاشة الإعدادات',
                  labelEn: 'Settings Title',
                  hasText: true,
                  textKey: 'settingsTitle',
                  defaultText: 'الإعدادات العامة',
                  textColorKey: 'titleColor',
                  defaultTextColor: '#FFFFFF',
                })}

                {renderDualField({
                  id: 'settingsAccountSecurity',
                  category: 'settings',
                  screen: 'settings',
                  labelAr: 'كارت الحساب والأمان',
                  labelEn: 'Account & Security Row',
                  hasText: true,
                  textKey: 'securityTitle',
                  defaultText: 'الحساب والأمان',
                  hasColor: true,
                  colorKey: 'cardBgColor',
                  defaultColor: '#1F2026',
                  hasImage: true,
                  imageKey: 'cardBgImage',
                })}

                {renderDualField({
                  id: 'settingsLanguage',
                  category: 'settings',
                  screen: 'settings',
                  labelAr: 'كارت لغة التطبيق',
                  labelEn: 'App Language Row',
                  hasText: true,
                  textKey: 'languageTitle',
                  defaultText: 'لغة التطبيق',
                  hasColor: true,
                  colorKey: 'langCardBgColor',
                  defaultColor: '#1F2026',
                })}

                {renderDualField({
                  id: 'settingsPrivacy',
                  category: 'settings',
                  screen: 'settings',
                  labelAr: 'كارت سياسة الخصوصية والشروط',
                  labelEn: 'Privacy & Terms Row',
                  hasText: true,
                  textKey: 'privacyTitle',
                  defaultText: 'الخصوصية وشروط الاستخدام',
                  hasColor: true,
                  colorKey: 'privacyCardBgColor',
                  defaultColor: '#1F2026',
                })}

                {renderDualField({
                  id: 'settingsLogoutBtn',
                  category: 'settings',
                  screen: 'settings',
                  labelAr: 'زر تسجيل الخروج',
                  labelEn: 'Logout Button',
                  hasText: true,
                  textKey: 'logoutText',
                  defaultText: 'تسجيل الخروج من الحساب',
                  textColorKey: 'logoutTextColor',
                  defaultTextColor: '#F87171',
                  hasColor: true,
                  colorKey: 'logoutBtnBg',
                  defaultColor: '#2D1515',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 13: GIFT BANNERS & VISUAL ALERTS                          */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'gift_banners') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-pink-500/20 text-pink-400 flex items-center justify-center font-bold text-lg">
                  🎁
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '13. بانرات ولافتات إرسال الهدايا والتنبيهات' : '13. Gift Banners & Visual Alerts'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'تخصيص لافتات إرسال الهدايا، بطاقات الإشعار في الغرفة، وألوان نصوص التهاني' : 'Customize gift announcement banners, notification cards, and congratulations'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'giftBannerBar',
                  category: 'gift_banners',
                  screen: 'giftBanner',
                  labelAr: 'شريط لافتة الهدية العريض في الروم',
                  labelEn: 'Room Gift Banner Bar',
                  hasColor: true,
                  colorKey: 'bannerBgColor',
                  defaultColor: '#2A0845',
                  hasImage: true,
                  imageKey: 'bannerBgImage',
                })}

                {renderDualField({
                  id: 'giftBannerCongratText',
                  category: 'gift_banners',
                  screen: 'giftBanner',
                  labelAr: 'نص التهنئة والإهداء الافتراضي',
                  labelEn: 'Gift Banner Congratulations Text',
                  hasText: true,
                  textKey: 'congratText',
                  defaultText: 'أرسل هدية فاخرة إلى',
                  textColorKey: 'congratTextColor',
                  defaultTextColor: '#FDE047',
                })}

                {renderDualField({
                  id: 'giftComboBadge',
                  category: 'gift_banners',
                  screen: 'giftBanner',
                  labelAr: 'شارة مضاعف الهدية (Combo x10/x100)',
                  labelEn: 'Gift Combo Multiplier Badge',
                  hasText: true,
                  textKey: 'comboText',
                  defaultText: 'COMBO',
                  textColorKey: 'comboTextColor',
                  defaultTextColor: '#FFFFFF',
                  hasColor: true,
                  colorKey: 'comboBadgeColor',
                  defaultColor: '#E11D48',
                  hasImage: true,
                  imageKey: 'comboBadgeImage',
                })}

                {renderDualField({
                  id: 'giftNotificationCard',
                  category: 'gift_banners',
                  screen: 'giftBanner',
                  labelAr: 'كارت إشعار الهدية في شات الغرفة',
                  labelEn: 'Room Chat Gift Notification Card',
                  hasColor: true,
                  colorKey: 'chatAlertCardBg',
                  defaultColor: '#1E1B4B',
                  hasImage: true,
                  imageKey: 'chatAlertCardBgImage',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 14: GLOBAL COLORS & BOTTOM NAVIGATION                     */}
          {/* ================================================================= */}
          {(activeSection === 'all' || activeSection === 'global') && (
            <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
              <div className="flex items-center gap-3 border-b border-white/10 pb-4">
                <div className="w-10 h-10 rounded-xl bg-teal-500/20 text-teal-400 flex items-center justify-center font-bold text-lg">
                  🌐
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '14. ألوان ونصوص النظام العامة والشريط السفلي' : '14. Global App System Colors & Navigation'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr ? 'التحكم العام بألوان الخط الأساسي، الخط الثانوي، الأزرار، الترويسة، وتبويبات الشريط السفلي' : 'Change global font colors, buttons, header, and bottom navigation bar'}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {renderDualField({
                  id: 'globalAppName',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'اسم التطبيق في شاشة البداية (Splash)',
                  labelEn: 'Splash Screen App Name',
                  hasText: true,
                  textKey: 'appName',
                  defaultText: 'Ahla Live',
                  hasColor: true,
                  colorKey: 'splashNameColor',
                  defaultColor: '#16151A',
                })}

                {renderDualField({
                  id: 'globalTextPrimary',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'لون النص الرئيسي في التطبيق',
                  labelEn: 'Primary Text Color',
                  hasColor: true,
                  colorKey: 'textPrimary',
                  defaultColor: '#16151A',
                })}

                {renderDualField({
                  id: 'globalTextSecondary',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'لون النص الثانوي في التطبيق',
                  labelEn: 'Secondary Text Color',
                  hasColor: true,
                  colorKey: 'textSecondary',
                  defaultColor: '#9BA1B6',
                })}

                {renderDualField({
                  id: 'globalButtonColor',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'خلفية ولون نص الأزرار العامة',
                  labelEn: 'Global Button Background & Text Color',
                  hasColor: true,
                  colorKey: 'buttonColor',
                  defaultColor: '#6366F1',
                  textColorKey: 'buttonTextColor',
                  defaultTextColor: '#FFFFFF',
                })}

                {renderDualField({
                  id: 'globalHeaderColor',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'لون الشريط العلوي العام (Header)',
                  labelEn: 'Global Header Background Color',
                  hasColor: true,
                  colorKey: 'headerColor',
                  defaultColor: '#FFFFFF',
                })}

                {renderDualField({
                  id: 'globalGoldColor',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'اللون الذهبي للتمييز والعملات',
                  labelEn: 'Global Gold Highlight Color',
                  hasColor: true,
                  colorKey: 'goldColor',
                  defaultColor: '#DE880F',
                })}

                {renderDualField({
                  id: 'bottomNavBg',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'خلفية الشريط السفلي للتنقل (Bottom Nav)',
                  labelEn: 'Bottom Navigation Bar Background',
                  hasColor: true,
                  colorKey: 'bottomNavBgColor',
                  defaultColor: '#121316',
                  hasImage: true,
                  imageKey: 'bottomNavBgImage',
                })}

                {renderDualField({
                  id: 'bottomNavActiveColor',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'لون الأيقونة والنص المختار في الشريط السفلي',
                  labelEn: 'Bottom Nav Active Tab Color',
                  hasColor: true,
                  colorKey: 'bottomNavActiveColor',
                  defaultColor: '#8B5CF6',
                })}

                {renderDualField({
                  id: 'bottomNavInactiveColor',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'لون الأيقونة والنص غير المختار في الشريط السفلي',
                  labelEn: 'Bottom Nav Inactive Tab Color',
                  hasColor: true,
                  colorKey: 'bottomNavInactiveColor',
                  defaultColor: '#64748B',
                })}

                {renderDualField({
                  id: 'bottomNavHome',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'تبويب الرئيسية في الشريط السفلي',
                  labelEn: 'Bottom Nav: Home Tab',
                  hasText: true,
                  textKey: 'navHomeText',
                  defaultText: 'الرئيسية',
                  textColorKey: 'navHomeTextColor',
                  defaultTextColor: '#FFFFFF',
                  hasIcon: true,
                  iconKey: 'navHomeIcon',
                })}

                {renderDualField({
                  id: 'bottomNavRooms',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'تبويب الغرف الصوتية في الشريط السفلي',
                  labelEn: 'Bottom Nav: Rooms Tab',
                  hasText: true,
                  textKey: 'navRoomsText',
                  defaultText: 'الغرف',
                  textColorKey: 'navRoomsTextColor',
                  defaultTextColor: '#FFFFFF',
                  hasIcon: true,
                  iconKey: 'navRoomsIcon',
                })}

                {renderDualField({
                  id: 'bottomNavMessages',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'تبويب الرسائل في الشريط السفلي',
                  labelEn: 'Bottom Nav: Messages Tab',
                  hasText: true,
                  textKey: 'navMessagesText',
                  defaultText: 'الرسائل',
                  textColorKey: 'navMessagesTextColor',
                  defaultTextColor: '#FFFFFF',
                  hasIcon: true,
                  iconKey: 'navMessagesIcon',
                })}

                {renderDualField({
                  id: 'bottomNavStore',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'تبويب المتجر في الشريط السفلي',
                  labelEn: 'Bottom Nav: Store Tab',
                  hasText: true,
                  textKey: 'navStoreText',
                  defaultText: 'المتجر',
                  textColorKey: 'navStoreTextColor',
                  defaultTextColor: '#FFFFFF',
                  hasIcon: true,
                  iconKey: 'navStoreIcon',
                })}

                {renderDualField({
                  id: 'bottomNavProfile',
                  category: 'global',
                  screen: 'global',
                  labelAr: 'تبويب حسابي / ملفي في الشريط السفلي',
                  labelEn: 'Bottom Nav: Profile Tab',
                  hasText: true,
                  textKey: 'navProfileText',
                  defaultText: 'حسابي',
                  textColorKey: 'navProfileTextColor',
                  defaultTextColor: '#FFFFFF',
                  hasIcon: true,
                  iconKey: 'navProfileIcon',
                })}
              </div>
            </div>
          )}

          {/* ================================================================= */}
          {/* SECTION 15: UNLIMITED CUSTOM DYNAMIC STRINGS                      */}
          {/* ================================================================= */}
          <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
            <div className="flex items-center justify-between border-b border-white/10 pb-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-emerald-500/20 text-emerald-400 flex items-center justify-center font-bold text-lg">
                  ➕
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? '15. إضافة أي نص أو كلمة مخصصة جديدة للتطبيق (Custom Dynamic Strings)' : '15. Custom Dynamic Strings (Add Any Key)'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr
                      ? 'يمكنك إضافة أي مفتاح نصي وقيمته ليتم قراءته وتطبيقه في أي شاشة أو بطاقة بالتطبيق فورياً وبدون قيود'
                      : 'Add any custom key and text value to dynamically override anywhere in the app'}
                  </p>
                </div>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-3 bg-white/5 p-4 rounded-xl border border-white/5">
              <input
                type="text"
                placeholder={isAr ? 'المفتاح البرمجي (مثال: welcomeTitle)' : 'Key name (e.g. welcomeTitle)'}
                value={newCustomKey}
                onChange={e => setNewCustomKey(e.target.value)}
                className="bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
              />
              <input
                type="text"
                placeholder={isAr ? 'النص المطلوب ظهوره في التطبيق' : 'Text to display in app'}
                value={newCustomVal}
                onChange={e => setNewCustomVal(e.target.value)}
                className="bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
              />
              <button
                type="button"
                onClick={() => {
                  if (!newCustomKey.trim()) return;
                  setCustomKeyValues(prev => [...prev, { key: newCustomKey.trim(), value: newCustomVal }]);
                  setNewCustomKey('');
                  setNewCustomVal('');
                }}
                className="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-xs font-bold flex items-center justify-center gap-2 cursor-pointer transition-all"
              >
                <Plus className="w-4 h-4" />
                <span>{isAr ? 'إضافة النص للقائمة' : 'Add Custom Text'}</span>
              </button>
            </div>

            {customKeyValues.length > 0 && (
              <div className="space-y-2 pt-2">
                {customKeyValues.map((item, idx) => (
                  <div key={idx} className="flex items-center justify-between bg-white/5 border border-white/5 p-3 rounded-xl gap-3">
                    <span className="font-mono text-cyan-400 text-xs font-semibold">{item.key}</span>
                    <input
                      type="text"
                      value={item.value}
                      onChange={e => {
                        const next = [...customKeyValues];
                        next[idx].value = e.target.value;
                        setCustomKeyValues(next);
                      }}
                      className="flex-1 bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-1.5 text-white text-xs"
                    />
                    <button
                      type="button"
                      onClick={() => setCustomKeyValues(prev => prev.filter((_, i) => i !== idx))}
                      className="p-2 text-rose-400 hover:bg-rose-500/20 rounded-lg transition-all cursor-pointer"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Sticky Bottom Save Bar */}
          <div className="flex items-center justify-between sticky bottom-4 bg-[#121316]/95 border border-purple-500/30 p-4 rounded-2xl shadow-2xl backdrop-blur-md">
            <span className="text-xs text-slate-300 font-medium hidden md:inline">
              {isAr ? '💾 يتم حفظ جميع النصوص والألوان والصور المرفوعة وتحديث التطبيق فورياً' : '💾 All texts, colors, and uploaded images are saved & synced instantly.'}
            </span>

            <button
              onClick={handleSaveAll}
              disabled={saving}
              className="px-8 py-3.5 rounded-xl bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500 text-white font-bold text-sm shadow-lg shadow-emerald-600/30 flex items-center justify-center gap-2 cursor-pointer transition-all disabled:opacity-50"
            >
              {saving ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
              <span>{saving ? (isAr ? 'جارٍ الحفظ والتطبيق الفوري...' : 'Saving...') : (isAr ? 'حفظ وتطبيق كافة النصوص والألوان والصور' : 'Save All Changes')}</span>
            </button>
          </div>
        </div>
      )}

      {/* ========================================================================= */}
      {/* OTHER TABS: DIRECT ACCESS TO SUITE                                       */}
      {/* ========================================================================= */}
      {activeTab === 'visual_manager' && (
        <div className="animate-fade-in">
          <VisualManager />
        </div>
      )}

      {activeTab === 'app_visual_designer' && (
        <div className="animate-fade-in">
          <AppVisualDesigner />
        </div>
      )}

      {activeTab === 'screen_customization' && (
        <div className="animate-fade-in">
          <ScreenCustomizationPage />
        </div>
      )}

      {activeTab === 'app_assets' && (
        <div className="animate-fade-in">
          <AppAssets />
        </div>
      )}

      {activeTab === 'gift_banners' && (
        <div className="animate-fade-in">
          <GiftBannerConfigs />
        </div>
      )}
    </div>
  );
}
