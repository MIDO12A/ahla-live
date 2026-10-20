import { useState, useEffect, useContext } from 'react';
import { useSearchParams } from 'react-router-dom';
import { I18nContext } from '../lib/i18n';
import { getAppConfig, updateAppConfig } from '../lib/db';
import {
  Palette, Smartphone, SlidersHorizontal, Image as ImageIcon, Sparkles,
  Type, Save, RotateCcw, Search, Plus, Trash2, CheckCircle, RefreshCw,
  Eye, Check, Layers, AlertCircle, ArrowRightLeft, Target, Shield, LayoutGrid
} from 'lucide-react';

// Sub-components
import VisualManager from './VisualManager';
import AppVisualDesigner from './AppVisualDesigner';
import ScreenCustomizationPage from './ScreenCustomization';
import AppAssets from './AppAssets';
import GiftBannerConfigs from './GiftBannerConfigs';

interface TargetTextGroup {
  curTargetTitle: string;
  curBalanceTitle: string;
  nextTargetTitle: string;
  nextRemainingTitle: string;
  agencyTargetTitle: string;
  myTargetTitle: string;
  agencyBalanceTitle: string;
  myBalanceTitle: string;
  targetStatsTitle: string;
  firstHalfTitle: string;
  secondHalfTitle: string;
  hoursTitle: string;
  salaryTitle: string;
  addMemberButtonText: string;
  targetPolicyText: string;
}

interface TargetColorsGroup {
  targetCardBg: string;
  targetCardValColor: string;
  balanceCardBg: string;
  balanceCardValColor: string;
  nextTargetCardBg: string;
  nextTargetCardValColor: string;
  nextRemainingCardBg: string;
  nextRemainingCardValColor: string;
  targetCardTextColor: string;
}

interface GlobalTextColorsGroup {
  textPrimary: string;
  textSecondary: string;
  buttonTextColor: string;
  buttonColor: string;
  cardTextColor: string;
  headerColor: string;
  bottomNavActiveTextColor: string;
  bottomNavInactiveTextColor: string;
  splashNameColor: string;
  goldColor: string;
}

interface ScreenTitlesGroup {
  discoverTitle: string;
  messageTitle: string;
  profileTitle: string;
  roomsTitle: string;
  storeTitle: string;
  vipTitle: string;
  walletTitle: string;
  rechargeAgentTitle: string;
  hostAgencyTitle: string;
  cpTitle: string;
}

interface WalletChatTextsGroup {
  coinsBalanceTitle: string;
  diamondsBalanceTitle: string;
  transferTitle: string;
  confirmTransferText: string;
  exchangeTitle: string;
  sendBtnText: string;
  chatPlaceholder: string;
  micSeatsTitle: string;
  leaveRoomText: string;
  luckyBoxText: string;
}

export default function AppDesignCenter() {
  const { t, lang } = useContext(I18nContext);
  const isAr = lang === 'ar';
  const [searchParams, setSearchParams] = useSearchParams();

  // Active Tab
  const tabParam = searchParams.get('tab') || 'texts_colors';
  const [activeTab, setActiveTab] = useState<string>(tabParam);

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

  // State for Texts & Colors Editor
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saveSuccess, setSaveSuccess] = useState(false);
  const [searchQ, setSearchQ] = useState('');

  // 1. Agency & Target Texts
  const [targetTexts, setTargetTexts] = useState<TargetTextGroup>({
    curTargetTitle: 'المستهدف الحالي',
    curBalanceTitle: 'الرصيد المحقق',
    nextTargetTitle: 'المستهدف القادم',
    nextRemainingTitle: 'المتبقي للهدف القادم',
    agencyTargetTitle: 'مستهدف ألماس الوكالة',
    myTargetTitle: 'مستهدف ألماسي الحالي',
    agencyBalanceTitle: 'إنتاج ألماس الوكالة',
    myBalanceTitle: 'رصيدي المحقق حالياً',
    targetStatsTitle: 'إحصائيات التارجت والدخل',
    firstHalfTitle: 'النصف الأول (1-15)',
    secondHalfTitle: 'النصف الثاني (16-30)',
    hoursTitle: 'ساعات البث المعتمدة',
    salaryTitle: 'أرباح وراتب الوكالة',
    addMemberButtonText: 'إضافة عضو',
    targetPolicyText: 'سياسة فك التارجت المعتمدة',
  });

  // 2. Target Colors
  const [targetColors, setTargetColors] = useState<TargetColorsGroup>({
    targetCardBg: '#F9FAFB',
    targetCardValColor: '#1F2937',
    balanceCardBg: '#ECFDF5',
    balanceCardValColor: '#059669',
    nextTargetCardBg: '#F9FAFB',
    nextTargetCardValColor: '#6B7280',
    nextRemainingCardBg: '#FFFBEB',
    nextRemainingCardValColor: '#D97706',
    targetCardTextColor: '#FFFFFF',
  });

  // 3. Screen Titles
  const [screenTitles, setScreenTitles] = useState<ScreenTitlesGroup>({
    discoverTitle: 'استكشاف',
    messageTitle: 'الرسائل',
    profileTitle: 'حسابي',
    roomsTitle: 'الغرف الصوتية',
    storeTitle: 'المتجر',
    vipTitle: 'مركز VIP',
    walletTitle: 'محفظتي',
    rechargeAgentTitle: 'بوابة شحن الوكلاء',
    hostAgencyTitle: 'وكالة المضيفين',
    cpTitle: 'مساحة CP',
  });

  // 4. Global Text & Element Colors
  const [globalColors, setGlobalColors] = useState<GlobalTextColorsGroup>({
    textPrimary: '#16151A',
    textSecondary: '#9BA1B6',
    buttonTextColor: '#FFFFFF',
    buttonColor: '#6366F1',
    cardTextColor: '#FFFFFF',
    headerColor: '#FFFFFF',
    bottomNavActiveTextColor: '#00B5B3',
    bottomNavInactiveTextColor: '#8E8E93',
    splashNameColor: '#16151A',
    goldColor: '#DE880F',
  });

  // 5. Wallet & Chat texts
  const [walletChatTexts, setWalletChatTexts] = useState<WalletChatTextsGroup>({
    coinsBalanceTitle: 'رصيد الكوينز',
    diamondsBalanceTitle: 'رصيد الألماس',
    transferTitle: 'تحويل الكوينز',
    confirmTransferText: 'تأكيد الشحن والتحويل',
    exchangeTitle: 'تبديل الألماس إلى كوينز',
    sendBtnText: 'إرسال',
    chatPlaceholder: 'اكتب رسالة جميلة...',
    micSeatsTitle: 'المقاعد الصوتية',
    leaveRoomText: 'مغادرة الغرفة',
    luckyBoxText: 'صندوق الحظ 🎁',
  });

  // 6. Custom extra key-values
  const [customKeyValues, setCustomKeyValues] = useState<Array<{ key: string; value: string }>>([]);
  const [newCustomKey, setNewCustomKey] = useState('');
  const [newCustomVal, setNewCustomVal] = useState('');

  // Load existing values on mount
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

        const hostAgency = sv.hostAgency || {};
        const agency = sv.agency || {};

        // 1. Populate Target Texts
        setTargetTexts(prev => ({
          ...prev,
          curTargetTitle: hostAgency.curTargetTitle || agency.curTargetTitle || cs.curTargetTitle || prev.curTargetTitle,
          curBalanceTitle: hostAgency.curBalanceTitle || agency.curBalanceTitle || cs.curBalanceTitle || prev.curBalanceTitle,
          nextTargetTitle: hostAgency.nextTargetTitle || agency.nextTargetTitle || cs.nextTargetTitle || prev.nextTargetTitle,
          nextRemainingTitle: hostAgency.nextRemainingTitle || agency.nextRemainingTitle || cs.nextRemainingTitle || prev.nextRemainingTitle,
          agencyTargetTitle: hostAgency.agencyTargetTitle || agency.agencyTargetTitle || cs.agencyTargetTitle || prev.agencyTargetTitle,
          myTargetTitle: hostAgency.myTargetTitle || agency.myTargetTitle || cs.myTargetTitle || prev.myTargetTitle,
          agencyBalanceTitle: hostAgency.agencyBalanceTitle || agency.agencyBalanceTitle || cs.agencyBalanceTitle || prev.agencyBalanceTitle,
          myBalanceTitle: hostAgency.myBalanceTitle || agency.myBalanceTitle || cs.myBalanceTitle || prev.myBalanceTitle,
          targetStatsTitle: agency.targetStatsTitle || cs.targetStatsTitle || prev.targetStatsTitle,
          firstHalfTitle: agency.firstHalfTitle || cs.firstHalfTitle || prev.firstHalfTitle,
          secondHalfTitle: agency.secondHalfTitle || cs.secondHalfTitle || prev.secondHalfTitle,
          hoursTitle: hostAgency.hoursTitle || agency.hoursTitle || cs.hoursTitle || prev.hoursTitle,
          salaryTitle: hostAgency.salaryTitle || agency.salaryTitle || cs.salaryTitle || prev.salaryTitle,
          addMemberButtonText: hostAgency.addMemberButtonText || agency.addMemberButtonText || cs.addMemberButtonText || prev.addMemberButtonText,
          targetPolicyText: agency.targetPolicyText || cs.targetPolicyText || prev.targetPolicyText,
        }));

        // 2. Populate Target Colors
        setTargetColors(prev => ({
          ...prev,
          targetCardBg: hostAgency.targetCardBg || prev.targetCardBg,
          targetCardValColor: hostAgency.targetCardValColor || prev.targetCardValColor,
          balanceCardBg: hostAgency.balanceCardBg || prev.balanceCardBg,
          balanceCardValColor: hostAgency.balanceCardValColor || prev.balanceCardValColor,
          nextTargetCardBg: hostAgency.nextTargetCardBg || prev.nextTargetCardBg,
          nextTargetCardValColor: hostAgency.nextTargetCardValColor || prev.nextTargetCardValColor,
          nextRemainingCardBg: hostAgency.nextRemainingCardBg || prev.nextRemainingCardBg,
          nextRemainingCardValColor: hostAgency.nextRemainingCardValColor || prev.nextRemainingCardValColor,
          targetCardTextColor: hostAgency.targetCardTextColor || agency.targetCardTextColor || prev.targetCardTextColor,
        }));

        // 3. Screen titles
        setScreenTitles(prev => ({
          ...prev,
          discoverTitle: st.discoverTitle || cs.discoverTitle || prev.discoverTitle,
          messageTitle: st.messageTitle || cs.messageTitle || prev.messageTitle,
          profileTitle: st.profileTitle || cs.profileTitle || prev.profileTitle,
          roomsTitle: st.roomsTitle || cs.roomsTitle || prev.roomsTitle,
          storeTitle: st.storeTitle || cs.storeTitle || prev.storeTitle,
          vipTitle: st.vipTitle || cs.vipTitle || prev.vipTitle,
          walletTitle: st.walletTitle || cs.walletTitle || prev.walletTitle,
          rechargeAgentTitle: st.rechargeAgentTitle || cs.rechargeAgentTitle || prev.rechargeAgentTitle,
          hostAgencyTitle: st.hostAgencyTitle || cs.hostAgencyTitle || prev.hostAgencyTitle,
          cpTitle: st.cpTitle || cs.cpTitle || prev.cpTitle,
        }));

        // 4. Global colors
        setGlobalColors(prev => ({
          ...prev,
          textPrimary: vc.textPrimary || cs.textPrimary || prev.textPrimary,
          textSecondary: vc.textSecondary || cs.textSecondary || prev.textSecondary,
          buttonTextColor: vc.buttonTextColor || cs.buttonTextColor || prev.buttonTextColor,
          buttonColor: vc.buttonColor || cs.buttonColor || prev.buttonColor,
          cardTextColor: vc.cardTextColor || cs.cardTextColor || prev.cardTextColor,
          headerColor: vc.headerColor || cs.headerColor || prev.headerColor,
          bottomNavActiveTextColor: vc.bottomNavActiveTextColor || cs.bottomNavActiveTextColor || prev.bottomNavActiveTextColor,
          bottomNavInactiveTextColor: vc.bottomNavInactiveTextColor || cs.bottomNavInactiveTextColor || prev.bottomNavInactiveTextColor,
          splashNameColor: vc.splashNameColor || cs.splashNameColor || prev.splashNameColor,
          goldColor: vc.goldColor || cs.goldColor || prev.goldColor,
        }));

        // 5. Wallet & Chat texts
        setWalletChatTexts(prev => ({
          ...prev,
          coinsBalanceTitle: cs.coinsBalanceTitle || prev.coinsBalanceTitle,
          diamondsBalanceTitle: cs.diamondsBalanceTitle || prev.diamondsBalanceTitle,
          transferTitle: cs.transferTitle || prev.transferTitle,
          confirmTransferText: cs.confirmTransferText || prev.confirmTransferText,
          exchangeTitle: cs.exchangeTitle || prev.exchangeTitle,
          sendBtnText: cs.sendBtnText || prev.sendBtnText,
          chatPlaceholder: cs.chatPlaceholder || prev.chatPlaceholder,
          micSeatsTitle: cs.micSeatsTitle || prev.micSeatsTitle,
          leaveRoomText: cs.leaveRoomText || prev.leaveRoomText,
          luckyBoxText: cs.luckyBoxText || prev.luckyBoxText,
        }));

        // 6. Custom extra key-values
        const knownKeys = new Set([
          ...Object.keys(targetTexts),
          ...Object.keys(screenTitles),
          ...Object.keys(walletChatTexts),
          ...Object.keys(globalColors),
          ...Object.keys(targetColors),
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

  // Save All Texts & Colors
  const handleSaveTextsAndColors = async () => {
    setSaving(true);
    setSaveSuccess(false);
    try {
      // 1. Fetch current screen_visuals & visual_manager_config
      const [currentSv, currentVc] = await Promise.all([
        getAppConfig('screen_visuals') || {},
        getAppConfig('visual_manager_config') || {},
      ]);

      // 2. Build updated screen_visuals
      const updatedSv = {
        ...currentSv,
        hostAgency: {
          ...(currentSv.hostAgency || {}),
          ...targetTexts,
          ...targetColors,
        },
        agency: {
          ...(currentSv.agency || {}),
          ...targetTexts,
          ...targetColors,
        },
      };

      // 3. Build updated custom_strings
      const customMap: Record<string, string> = {
        ...targetTexts,
        ...screenTitles,
        ...walletChatTexts,
        ...globalColors,
      };
      for (const item of customKeyValues) {
        if (item.key.trim()) {
          customMap[item.key.trim()] = item.value;
        }
      }

      // 4. Build updated visual_manager_config
      const updatedVc = {
        ...currentVc,
        ...globalColors,
      };

      // 5. Persist to app_config
      await Promise.all([
        updateAppConfig('screen_visuals', updatedSv),
        updateAppConfig('custom_strings', customMap),
        updateAppConfig('screenTitles', screenTitles),
        updateAppConfig('visual_manager_config', updatedVc),
      ]);

      setSaveSuccess(true);
      setTimeout(() => setSaveSuccess(false), 4000);
    } catch (err: any) {
      alert('خطأ أثناء الحفظ: ' + (err?.message || err));
    } finally {
      setSaving(false);
    }
  };

  const handleAddCustomKey = () => {
    if (!newCustomKey.trim()) return;
    setCustomKeyValues(prev => [...prev, { key: newCustomKey.trim(), value: newCustomVal }]);
    setNewCustomKey('');
    setNewCustomVal('');
  };

  const handleRemoveCustomKey = (index: number) => {
    setCustomKeyValues(prev => prev.filter((_, i) => i !== index));
  };

  const tabs = [
    { key: 'texts_colors', label: isAr ? '✍️ محرر نصوص التطبيق ومستهدف الوكالات وألوان الخطوط' : '✍️ App Texts & Colors', icon: Type },
    { key: 'visual_manager', label: isAr ? '🎨 المظهر الشامل والألوان' : '🎨 Visual Manager', icon: Palette },
    { key: 'app_visual_designer', label: isAr ? '📱 مصمم الواجهات والأيقونات' : '📱 Screen Designer & Icons', icon: Smartphone },
    { key: 'screen_customization', label: isAr ? '🛠️ تخصيص الشاشات والخلفيات' : '🛠️ Screen Customization', icon: SlidersHorizontal },
    { key: 'app_assets', label: isAr ? '🖼️ مكتبة أصول التطبيق' : '🖼️ App Assets', icon: ImageIcon },
    { key: 'gift_banners', label: isAr ? '🎁 بانرات ولافتات الهدايا' : '🎁 Gift Banners', icon: Sparkles },
  ];

  return (
    <div className="space-y-6">
      {/* Top Banner Header */}
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
              <p className="text-slate-400 text-xs mt-1 max-w-2xl leading-relaxed">
                {isAr
                  ? 'التحكم الشامل بجميع عناصر التصميم: المظهر العام، مصمم الواجهات، تخصيص الشاشات والخلفيات، مكتبة الوسائط، لافتات الهدايا، وتعديل كافة كتابات ونصوص التطبيق ومستهدف الوكالات وألوان النصوص بالكامل.'
                  : 'Manage all app visuals, screen designer, media assets, gift banners, and customize all app strings, agency targets, and dynamic text colors.'}
              </p>
            </div>
          </div>

          {activeTab === 'texts_colors' && (
            <button
              onClick={handleSaveTextsAndColors}
              disabled={saving}
              className="px-6 py-3 rounded-xl bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500 text-white font-bold text-sm shadow-lg shadow-emerald-600/30 flex items-center justify-center gap-2 cursor-pointer transition-all disabled:opacity-50 whitespace-nowrap self-start md:self-auto"
            >
              {saving ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
              <span>{saving ? (isAr ? 'جارٍ الحفظ والتطبيق...' : 'Saving...') : (isAr ? 'حفظ النصوص والألوان' : 'Save Texts & Colors')}</span>
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
          <CheckCircle className="w-5 h-5 flex-shrink-0" />
          <span className="font-semibold">
            {isAr
              ? '✓ تم حفظ جميع النصوص والكتابات وتدرجات الألوان بنجاح! تم التحديث الفوري للتطبيق.'
              : '✓ All texts, custom labels, and dynamic colors saved successfully!'}
          </span>
        </div>
      )}

      {/* TAB 1: ALL TEXTS & TEXT COLORS EDITOR */}
      {activeTab === 'texts_colors' && (
        <div className="space-y-8 animate-fade-in">
          {/* Live Preview Bar */}
          <div className="bg-[#121316] border border-white/10 rounded-2xl p-5 shadow-xl">
            <h3 className="text-white text-sm font-bold flex items-center gap-2 mb-3">
              <Eye className="w-4 h-4 text-cyan-400" />
              <span>{isAr ? 'معاينة حية لكروت مستهدف الوكالة كما تظهر داخل التطبيق:' : 'Live Preview of Agency Target Cards:'}</span>
            </h3>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              {/* Card 1: Current Target */}
              <div
                className="p-4 rounded-xl border border-white/10 shadow-sm transition-all"
                style={{ backgroundColor: targetColors.targetCardBg }}
              >
                <span className="text-[11px] font-semibold block mb-1" style={{ color: targetColors.targetCardValColor }}>
                  {targetTexts.curTargetTitle || 'المستهدف الحالي'}
                </span>
                <span className="text-lg font-black block" style={{ color: targetColors.targetCardValColor }}>
                  150,000 💎
                </span>
              </div>

              {/* Card 2: Current Balance */}
              <div
                className="p-4 rounded-xl border border-white/10 shadow-sm transition-all"
                style={{ backgroundColor: targetColors.balanceCardBg }}
              >
                <span className="text-[11px] font-semibold block mb-1" style={{ color: targetColors.balanceCardValColor }}>
                  {targetTexts.curBalanceTitle || 'الرصيد المحقق'}
                </span>
                <span className="text-lg font-black block" style={{ color: targetColors.balanceCardValColor }}>
                  125,400 💎
                </span>
              </div>

              {/* Card 3: Next Target */}
              <div
                className="p-4 rounded-xl border border-dashed border-white/20 shadow-sm transition-all"
                style={{ backgroundColor: targetColors.nextTargetCardBg }}
              >
                <span className="text-[11px] font-semibold block mb-1" style={{ color: targetColors.nextTargetCardValColor }}>
                  {targetTexts.nextTargetTitle || 'المستهدف القادم'}
                </span>
                <span className="text-lg font-black block" style={{ color: targetColors.nextTargetCardValColor }}>
                  300,000 💎
                </span>
              </div>

              {/* Card 4: Next Remaining */}
              <div
                className="p-4 rounded-xl border border-dashed border-white/20 shadow-sm transition-all"
                style={{ backgroundColor: targetColors.nextRemainingCardBg }}
              >
                <span className="text-[11px] font-semibold block mb-1" style={{ color: targetColors.nextRemainingCardValColor }}>
                  {targetTexts.nextRemainingTitle || 'المتبقي للهدف القادم'}
                </span>
                <span className="text-lg font-black block" style={{ color: targetColors.nextRemainingCardValColor }}>
                  174,600 💎
                </span>
              </div>
            </div>
          </div>

          {/* Search Bar */}
          <div className="relative">
            <Search className="w-4 h-4 absolute top-1/2 -translate-y-1/2 right-4 text-slate-400" />
            <input
              type="text"
              value={searchQ}
              onChange={e => setSearchQ(e.target.value)}
              placeholder={isAr ? 'بحث عن أي كلمة أو نص أو عنوان تريد تعديله داخل التطبيق...' : 'Search for any word, label, or text to customize...'}
              className="w-full bg-[#121316] border border-white/10 rounded-xl px-11 py-3 text-white text-sm focus:outline-none focus:border-purple-500 placeholder-slate-500"
            />
          </div>

          {/* Section 1: Agency & Target Texts */}
          <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
            <div className="flex items-center justify-between border-b border-white/10 pb-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-amber-500/20 text-amber-400 flex items-center justify-center font-bold">
                  🎯
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? 'مستهدف الوكالات والمضيفين ونصوص الأهداف والرواتب' : 'Agency & Host Target Texts & Colors'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr
                      ? 'تعديل جميع مسميات كروت التارجت والأرباح وألوانها داخل شاشات الوكالة والمضيفين'
                      : 'Customize target cards titles, values, and color cards in agency screens'}
                  </p>
                </div>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {/* curTargetTitle */}
              <div className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                <label className="text-xs text-amber-300 font-bold block">{isAr ? 'عنوان المستهدف الحالي' : 'Current Target Title'}</label>
                <input
                  type="text"
                  value={targetTexts.curTargetTitle}
                  onChange={e => setTargetTexts({ ...targetTexts, curTargetTitle: e.target.value })}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                />
                <div className="grid grid-cols-2 gap-2 pt-1">
                  <div>
                    <span className="text-[10px] text-slate-400 block mb-1">{isAr ? 'لون البطاقة' : 'Card BG'}</span>
                    <div className="flex items-center gap-2">
                      <input
                        type="color"
                        value={targetColors.targetCardBg.slice(0, 7)}
                        onChange={e => setTargetColors({ ...targetColors, targetCardBg: e.target.value })}
                        className="w-7 h-7 rounded border-none cursor-pointer bg-transparent"
                      />
                      <span className="text-[10px] text-slate-400 font-mono">{targetColors.targetCardBg}</span>
                    </div>
                  </div>
                  <div>
                    <span className="text-[10px] text-slate-400 block mb-1">{isAr ? 'لون القيمة' : 'Text Color'}</span>
                    <div className="flex items-center gap-2">
                      <input
                        type="color"
                        value={targetColors.targetCardValColor.slice(0, 7)}
                        onChange={e => setTargetColors({ ...targetColors, targetCardValColor: e.target.value })}
                        className="w-7 h-7 rounded border-none cursor-pointer bg-transparent"
                      />
                      <span className="text-[10px] text-slate-400 font-mono">{targetColors.targetCardValColor}</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* curBalanceTitle */}
              <div className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                <label className="text-xs text-emerald-300 font-bold block">{isAr ? 'عنوان الرصيد المحقق' : 'Current Balance Title'}</label>
                <input
                  type="text"
                  value={targetTexts.curBalanceTitle}
                  onChange={e => setTargetTexts({ ...targetTexts, curBalanceTitle: e.target.value })}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                />
                <div className="grid grid-cols-2 gap-2 pt-1">
                  <div>
                    <span className="text-[10px] text-slate-400 block mb-1">{isAr ? 'لون البطاقة' : 'Card BG'}</span>
                    <div className="flex items-center gap-2">
                      <input
                        type="color"
                        value={targetColors.balanceCardBg.slice(0, 7)}
                        onChange={e => setTargetColors({ ...targetColors, balanceCardBg: e.target.value })}
                        className="w-7 h-7 rounded border-none cursor-pointer bg-transparent"
                      />
                      <span className="text-[10px] text-slate-400 font-mono">{targetColors.balanceCardBg}</span>
                    </div>
                  </div>
                  <div>
                    <span className="text-[10px] text-slate-400 block mb-1">{isAr ? 'لون القيمة' : 'Text Color'}</span>
                    <div className="flex items-center gap-2">
                      <input
                        type="color"
                        value={targetColors.balanceCardValColor.slice(0, 7)}
                        onChange={e => setTargetColors({ ...targetColors, balanceCardValColor: e.target.value })}
                        className="w-7 h-7 rounded border-none cursor-pointer bg-transparent"
                      />
                      <span className="text-[10px] text-slate-400 font-mono">{targetColors.balanceCardValColor}</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* nextTargetTitle */}
              <div className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                <label className="text-xs text-indigo-300 font-bold block">{isAr ? 'عنوان المستهدف القادم' : 'Next Target Title'}</label>
                <input
                  type="text"
                  value={targetTexts.nextTargetTitle}
                  onChange={e => setTargetTexts({ ...targetTexts, nextTargetTitle: e.target.value })}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                />
                <div className="grid grid-cols-2 gap-2 pt-1">
                  <div>
                    <span className="text-[10px] text-slate-400 block mb-1">{isAr ? 'لون البطاقة' : 'Card BG'}</span>
                    <div className="flex items-center gap-2">
                      <input
                        type="color"
                        value={targetColors.nextTargetCardBg.slice(0, 7)}
                        onChange={e => setTargetColors({ ...targetColors, nextTargetCardBg: e.target.value })}
                        className="w-7 h-7 rounded border-none cursor-pointer bg-transparent"
                      />
                      <span className="text-[10px] text-slate-400 font-mono">{targetColors.nextTargetCardBg}</span>
                    </div>
                  </div>
                  <div>
                    <span className="text-[10px] text-slate-400 block mb-1">{isAr ? 'لون القيمة' : 'Text Color'}</span>
                    <div className="flex items-center gap-2">
                      <input
                        type="color"
                        value={targetColors.nextTargetCardValColor.slice(0, 7)}
                        onChange={e => setTargetColors({ ...targetColors, nextTargetCardValColor: e.target.value })}
                        className="w-7 h-7 rounded border-none cursor-pointer bg-transparent"
                      />
                      <span className="text-[10px] text-slate-400 font-mono">{targetColors.nextTargetCardValColor}</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* nextRemainingTitle */}
              <div className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                <label className="text-xs text-rose-300 font-bold block">{isAr ? 'عنوان المتبقي للهدف القادم' : 'Next Remaining Title'}</label>
                <input
                  type="text"
                  value={targetTexts.nextRemainingTitle}
                  onChange={e => setTargetTexts({ ...targetTexts, nextRemainingTitle: e.target.value })}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                />
                <div className="grid grid-cols-2 gap-2 pt-1">
                  <div>
                    <span className="text-[10px] text-slate-400 block mb-1">{isAr ? 'لون البطاقة' : 'Card BG'}</span>
                    <div className="flex items-center gap-2">
                      <input
                        type="color"
                        value={targetColors.nextRemainingCardBg.slice(0, 7)}
                        onChange={e => setTargetColors({ ...targetColors, nextRemainingCardBg: e.target.value })}
                        className="w-7 h-7 rounded border-none cursor-pointer bg-transparent"
                      />
                      <span className="text-[10px] text-slate-400 font-mono">{targetColors.nextRemainingCardBg}</span>
                    </div>
                  </div>
                  <div>
                    <span className="text-[10px] text-slate-400 block mb-1">{isAr ? 'لون القيمة' : 'Text Color'}</span>
                    <div className="flex items-center gap-2">
                      <input
                        type="color"
                        value={targetColors.nextRemainingCardValColor.slice(0, 7)}
                        onChange={e => setTargetColors({ ...targetColors, nextRemainingCardValColor: e.target.value })}
                        className="w-7 h-7 rounded border-none cursor-pointer bg-transparent"
                      />
                      <span className="text-[10px] text-slate-400 font-mono">{targetColors.nextRemainingCardValColor}</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* targetStatsTitle */}
              <div className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                <label className="text-xs text-slate-300 font-bold block">{isAr ? 'عنوان إحصائيات التارجت والدخل' : 'Target Stats Title'}</label>
                <input
                  type="text"
                  value={targetTexts.targetStatsTitle}
                  onChange={e => setTargetTexts({ ...targetTexts, targetStatsTitle: e.target.value })}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                />
              </div>

              {/* firstHalfTitle */}
              <div className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                <label className="text-xs text-slate-300 font-bold block">{isAr ? 'عنوان النصف الأول' : 'First Half (1-15) Title'}</label>
                <input
                  type="text"
                  value={targetTexts.firstHalfTitle}
                  onChange={e => setTargetTexts({ ...targetTexts, firstHalfTitle: e.target.value })}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                />
              </div>

              {/* secondHalfTitle */}
              <div className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                <label className="text-xs text-slate-300 font-bold block">{isAr ? 'عنوان النصف الثاني' : 'Second Half (16-30) Title'}</label>
                <input
                  type="text"
                  value={targetTexts.secondHalfTitle}
                  onChange={e => setTargetTexts({ ...targetTexts, secondHalfTitle: e.target.value })}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                />
              </div>

              {/* hoursTitle */}
              <div className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                <label className="text-xs text-slate-300 font-bold block">{isAr ? 'عنوان كارت ساعات البث' : 'Broadcast Hours Card Title'}</label>
                <input
                  type="text"
                  value={targetTexts.hoursTitle}
                  onChange={e => setTargetTexts({ ...targetTexts, hoursTitle: e.target.value })}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                />
              </div>

              {/* salaryTitle */}
              <div className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                <label className="text-xs text-slate-300 font-bold block">{isAr ? 'عنوان كارت الراتب والأرباح' : 'Salary Card Title'}</label>
                <input
                  type="text"
                  value={targetTexts.salaryTitle}
                  onChange={e => setTargetTexts({ ...targetTexts, salaryTitle: e.target.value })}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                />
              </div>

              {/* addMemberButtonText */}
              <div className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                <label className="text-xs text-slate-300 font-bold block">{isAr ? 'نص زر إضافة عضو بالوكالة' : 'Add Member Button Text'}</label>
                <input
                  type="text"
                  value={targetTexts.addMemberButtonText}
                  onChange={e => setTargetTexts({ ...targetTexts, addMemberButtonText: e.target.value })}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                />
              </div>

              {/* agencyTargetTitle */}
              <div className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                <label className="text-xs text-slate-300 font-bold block">{isAr ? 'عنوان تارجت الوكالة الشامل' : 'Agency Diamond Target Title'}</label>
                <input
                  type="text"
                  value={targetTexts.agencyTargetTitle}
                  onChange={e => setTargetTexts({ ...targetTexts, agencyTargetTitle: e.target.value })}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                />
              </div>

              {/* myTargetTitle */}
              <div className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                <label className="text-xs text-slate-300 font-bold block">{isAr ? 'عنوان تارجت المضيف الفردي' : 'My Diamond Target Title'}</label>
                <input
                  type="text"
                  value={targetTexts.myTargetTitle}
                  onChange={e => setTargetTexts({ ...targetTexts, myTargetTitle: e.target.value })}
                  className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                />
              </div>
            </div>
          </div>

          {/* Section 2: Screen Titles & Navigation */}
          <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
            <div className="flex items-center gap-3 border-b border-white/10 pb-4">
              <div className="w-10 h-10 rounded-xl bg-purple-500/20 text-purple-400 flex items-center justify-center font-bold">
                📱
              </div>
              <div>
                <h3 className="text-base font-bold text-white">
                  {isAr ? 'عناوين الشاشات الرئيسية وأزرار التنقل بالتطبيق' : 'Main Screen Titles & Navigation Labels'}
                </h3>
                <p className="text-slate-400 text-xs">
                  {isAr ? 'تعديل أسماء الشاشات والتبويبات التي يراها المستخدم في الشريط السفلي وأعلى الصفحات' : 'Customize app screen titles and bottom navigation tabs'}
                </p>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {Object.entries(screenTitles).map(([k, val]) => (
                <div key={k} className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                  <label className="text-xs text-slate-300 font-bold block">
                    {k === 'discoverTitle' ? (isAr ? 'شاشة استكشاف' : 'Discover Screen') :
                     k === 'messageTitle' ? (isAr ? 'شاشة الرسائل' : 'Messages Screen') :
                     k === 'profileTitle' ? (isAr ? 'شاشة حسابي (البروفايل)' : 'Profile Screen') :
                     k === 'roomsTitle' ? (isAr ? 'شاشة الغرف الصوتية' : 'Rooms Screen') :
                     k === 'storeTitle' ? (isAr ? 'شاشة المتجر' : 'Store Screen') :
                     k === 'vipTitle' ? (isAr ? 'شاشة مركز VIP' : 'VIP Center Screen') :
                     k === 'walletTitle' ? (isAr ? 'شاشة المحفظة' : 'Wallet Screen') :
                     k === 'rechargeAgentTitle' ? (isAr ? 'شاشة وكالة الشحن' : 'Recharge Agent Screen') :
                     k === 'hostAgencyTitle' ? (isAr ? 'شاشة وكالة المضيفين' : 'Host Agency Screen') :
                     k === 'cpTitle' ? (isAr ? 'شاشة مساحة CP' : 'CP Space Screen') : k}
                  </label>
                  <input
                    type="text"
                    value={val}
                    onChange={e => setScreenTitles({ ...screenTitles, [k]: e.target.value })}
                    className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                  />
                </div>
              ))}
            </div>
          </div>

          {/* Section 3: Global Text Colors & UI Colors */}
          <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
            <div className="flex items-center gap-3 border-b border-white/10 pb-4">
              <div className="w-10 h-10 rounded-xl bg-pink-500/20 text-pink-400 flex items-center justify-center font-bold">
                🎨
              </div>
              <div>
                <h3 className="text-base font-bold text-white">
                  {isAr ? 'ألوان النصوص والكتابات العامة في التطبيق' : 'Global Text & UI Colors'}
                </h3>
                <p className="text-slate-400 text-xs">
                  {isAr ? 'التحكم المباشر في ألوان نصوص التطبيق، ألوان نصوص الأزرار، الكروت، وشريط التبويب' : 'Change global font colors, button texts, cards, and bottom bar'}
                </p>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {Object.entries(globalColors).map(([k, hex]) => (
                <div key={k} className="bg-white/5 border border-white/5 p-4 rounded-xl flex items-center justify-between gap-3">
                  <div>
                    <span className="text-xs text-white font-bold block">
                      {k === 'textPrimary' ? (isAr ? 'لون النص الرئيسي' : 'Primary Text Color') :
                       k === 'textSecondary' ? (isAr ? 'لون النص الثانوي' : 'Secondary Text Color') :
                       k === 'buttonTextColor' ? (isAr ? 'لون نصوص الأزرار' : 'Button Text Color') :
                       k === 'buttonColor' ? (isAr ? 'لون خلفية الأزرار' : 'Button Background') :
                       k === 'cardTextColor' ? (isAr ? 'لون نصوص البطاقات' : 'Card Text Color') :
                       k === 'headerColor' ? (isAr ? 'لون الشريط العلوي' : 'Header Color') :
                       k === 'bottomNavActiveTextColor' ? (isAr ? 'نص التبويب النشط' : 'Bottom Nav Active') :
                       k === 'bottomNavInactiveTextColor' ? (isAr ? 'نص التبويب غير النشط' : 'Bottom Nav Inactive') :
                       k === 'splashNameColor' ? (isAr ? 'لون اسم التطبيق بالبداية' : 'Splash Name Color') :
                       k === 'goldColor' ? (isAr ? 'اللون الذهبي للتمييز' : 'Gold Highlight Color') : k}
                    </span>
                    <span className="text-[10px] text-slate-400 font-mono">{hex}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <input
                      type="color"
                      value={hex.slice(0, 7)}
                      onChange={e => setGlobalColors({ ...globalColors, [k]: e.target.value })}
                      className="w-9 h-9 rounded-lg border-none cursor-pointer bg-transparent"
                    />
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Section 4: Wallet & Chat Texts */}
          <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
            <div className="flex items-center gap-3 border-b border-white/10 pb-4">
              <div className="w-10 h-10 rounded-xl bg-cyan-500/20 text-cyan-400 flex items-center justify-center font-bold">
                💰
              </div>
              <div>
                <h3 className="text-base font-bold text-white">
                  {isAr ? 'نصوص المحفظة، الشحن، والغرف والمحادثات' : 'Wallet, Recharge & Room Chat Texts'}
                </h3>
                <p className="text-slate-400 text-xs">
                  {isAr ? 'تعديل نصوص أرصدة العملات، أزرار التحويل والتبديل، ورسائل المحادثات' : 'Customize wallet balances, exchange labels, and room chat texts'}
                </p>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {Object.entries(walletChatTexts).map(([k, val]) => (
                <div key={k} className="bg-white/5 border border-white/5 p-4 rounded-xl space-y-2">
                  <label className="text-xs text-slate-300 font-bold block">
                    {k === 'coinsBalanceTitle' ? (isAr ? 'عنوان رصيد الكوينز' : 'Coins Balance Label') :
                     k === 'diamondsBalanceTitle' ? (isAr ? 'عنوان رصيد الألماس' : 'Diamonds Balance Label') :
                     k === 'transferTitle' ? (isAr ? 'عنوان تحويل الكوينز' : 'Transfer Title') :
                     k === 'confirmTransferText' ? (isAr ? 'نص زر تأكيد التحويل' : 'Confirm Transfer Button') :
                     k === 'exchangeTitle' ? (isAr ? 'عنوان تبديل الألماس' : 'Diamond Exchange Title') :
                     k === 'sendBtnText' ? (isAr ? 'نص زر الإرسال بالشات' : 'Send Message Button') :
                     k === 'chatPlaceholder' ? (isAr ? 'نص تلميح المحادثة' : 'Chat Input Placeholder') :
                     k === 'micSeatsTitle' ? (isAr ? 'عنوان المقاعد الصوتية' : 'Mic Seats Title') :
                     k === 'leaveRoomText' ? (isAr ? 'نص زر مغادرة الغرفة' : 'Leave Room Button') :
                     k === 'luckyBoxText' ? (isAr ? 'نص صندوق الحظ' : 'Lucky Box Label') : k}
                  </label>
                  <input
                    type="text"
                    value={val}
                    onChange={e => setWalletChatTexts({ ...walletChatTexts, [k]: e.target.value })}
                    className="w-full bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
                  />
                </div>
              ))}
            </div>
          </div>

          {/* Section 5: Add Custom Text Strings (Custom Key-Value) */}
          <div className="bg-[#121316] border border-white/10 rounded-2xl p-6 shadow-xl space-y-5">
            <div className="flex items-center justify-between border-b border-white/10 pb-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-emerald-500/20 text-emerald-400 flex items-center justify-center font-bold">
                  ➕
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">
                    {isAr ? 'إضافة نصوص وكلمات مخصصة للتطبيق (Custom Dynamic Strings)' : 'Custom Dynamic Strings'}
                  </h3>
                  <p className="text-slate-400 text-xs">
                    {isAr
                      ? 'يمكنك إضافة أي مفتاح نصي وقيمته ليتم قراءته وتطبيقه في أي شاشة بالتطبيق فورياً'
                      : 'Add any custom string key and value to dynamically override in app screens'}
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
                placeholder={isAr ? 'النص العربي المطلوب ظهوره' : 'Text to display'}
                value={newCustomVal}
                onChange={e => setNewCustomVal(e.target.value)}
                className="bg-[#1A1A1E] border border-white/10 rounded-lg px-3 py-2 text-white text-xs"
              />
              <button
                type="button"
                onClick={handleAddCustomKey}
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
                      onClick={() => handleRemoveCustomKey(idx)}
                      className="p-2 text-rose-400 hover:bg-rose-500/20 rounded-lg transition-all cursor-pointer"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Bottom Save Bar */}
          <div className="flex items-center justify-end gap-3 sticky bottom-4 bg-[#121316]/95 border border-purple-500/30 p-4 rounded-2xl shadow-2xl backdrop-blur-md">
            <button
              onClick={handleSaveTextsAndColors}
              disabled={saving}
              className="px-8 py-3.5 rounded-xl bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500 text-white font-bold text-sm shadow-lg shadow-emerald-600/30 flex items-center justify-center gap-2 cursor-pointer transition-all disabled:opacity-50"
            >
              {saving ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
              <span>{saving ? (isAr ? 'جارٍ الحفظ والتطبيق الفوري...' : 'Saving...') : (isAr ? 'حفظ وتطبيق كافة النصوص والألوان' : 'Save All Changes')}</span>
            </button>
          </div>
        </div>
      )}

      {/* TAB 2: VISUAL MANAGER */}
      {activeTab === 'visual_manager' && (
        <div className="animate-fade-in">
          <VisualManager />
        </div>
      )}

      {/* TAB 3: APP VISUAL DESIGNER */}
      {activeTab === 'app_visual_designer' && (
        <div className="animate-fade-in">
          <AppVisualDesigner />
        </div>
      )}

      {/* TAB 4: SCREEN CUSTOMIZATION */}
      {activeTab === 'screen_customization' && (
        <div className="animate-fade-in">
          <ScreenCustomizationPage />
        </div>
      )}

      {/* TAB 5: APP ASSETS */}
      {activeTab === 'app_assets' && (
        <div className="animate-fade-in">
          <AppAssets />
        </div>
      )}

      {/* TAB 6: GIFT BANNERS */}
      {activeTab === 'gift_banners' && (
        <div className="animate-fade-in">
          <GiftBannerConfigs />
        </div>
      )}
    </div>
  );
}
