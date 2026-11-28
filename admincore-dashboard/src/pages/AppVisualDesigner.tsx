import { useEffect, useState, useContext } from 'react';
import { I18nContext } from '../lib/i18n';
import { getAppConfig, updateAppConfig, getAppAssets, upsertAppAsset, deleteAppAsset, supabase } from '../lib/db';
import { uploadAppAsset } from '../lib/storage';
import { iconRegistry, IconRegistryEntry } from '../lib/iconRegistry';
import { SCREEN_ASSETS, SCREEN_ORDER } from '../lib/screenAssets';
import { to6Hex } from '../lib/colors';
import { 
  Save, RotateCcw, Upload, Phone, ChevronRight, MessageSquare, 
  User, Info, Bell, Search, Compass, Send, Copy, Plus, 
  Palette, Image, Sparkles, LayoutDashboard, Sliders, Play, Trash2,
  ListFilter, Grid, Award, SlidersHorizontal, Settings
} from 'lucide-react';

interface AppAssetRecord {
  id: string;
  key: string;
  name: string;
  type: 'image' | 'video' | 'svga' | 'vap' | 'lottie';
  category: string;
  subcategory: string;
  localPath: string;
  remoteUrl: string;
  defaultValue: string;
  mimeType: string;
  fileSize: number;
  width: number | null;
  height: number | null;
  sortOrder: number;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

interface ScreenVisuals {
  agency: Record<string, string>;
  badges: Record<string, string>;
  necklaces: Record<string, string>;
  rank: Record<string, string>;
  checkbox: Record<string, string>;
  store: Record<string, string>;
  backpack: Record<string, string>;
  wallet: Record<string, string>;
  level: Record<string, string>;
  cp: Record<string, string>;
  signin: Record<string, string>;
  room: Record<string, string>;
  discover: Record<string, string>;
  message: Record<string, string>;
  profile: Record<string, string>;
  chat: Record<string, string>;
  userProfile: Record<string, string>;
  fullProfile: Record<string, string>;
  eventInfo: Record<string, string>;
  notifications: Record<string, string>;
}

const defaultVisuals: ScreenVisuals = {
  agency: {}, badges: {}, necklaces: {}, rank: {}, checkbox: {}, store: {}, backpack: {}, wallet: {}, level: {}, cp: {}, signin: {}, room: {},
  discover: {
    backgroundImage: '',
    backgroundColor: '#ffffff',
    textColor: '#16151a',
    subTextColor: '#9ba1b6',
    cardBgColor: '#f7f7f8',
  },
  message: {
    backgroundImage: '',
    backgroundColor: '#ffffff',
    textColor: '#16151a',
    subTextColor: '#9ba1b6',
    cardBgColor: '#f7f7f8',
  },
  profile: {
    backgroundImage: '',
    backgroundColor: '#f6f7f9',
    textColor: '#000000',
    subTextColor: '#888888',
    cardBgColor: '#ffffff',
  },
  chat: {
    backgroundImage: '',
    backgroundColor: '#f2f3f5',
    textColor: '#000000',
    bubbleSelfBgColor: '#ffe082',
    bubbleOtherBgColor: '#ffffff',
  },
  userProfile: {
    backgroundImage: '',
    cardFrameImg: '',
    backgroundColor: '#16141D',
    borderColor: '#382F24',
    textColor: '#ffffff',
    subTextColor: '#9BA1B6',
    buttonColor: '#E8BD56',
    hostBadgeImg: '',
    hostBadgeBg: '#1E5BB5',
    giftBarBg: '',
    giftBarBorderImg: '',
    giftBarBorder: '#5E4321',
    intimateCardBg: '',
    familyCardBg: '',
    supportersBanner: '',
    supporterSlot: '',
    goldCrown: '',
    silverCrown: '',
    bronzeCrown: '',
    identityTitleImg: '',
    badgesTitleImg: '',
    achievementsTitleImg: '',
    profileFollowIcon: '',
    profileChatIcon: '',
    profileGiftIcon: '',
    profileMentionIcon: '',
    profileMoreIcon: '',
    profileReportIcon: '',
    profileEditIcon: '',
    giftWallCardBg: '',
    giftWallCardBorder: '#382F24',
    giftWallIcon: '',
    vehicleCardBg: '',
    vehicleCardBorder: '#382F24',
    vehicleIcon: '',
    frameCardBg: '',
    frameCardBorder: '#382F24',
    frameIcon: '',
  },
  fullProfile: {
    backgroundImage: '',
    backgroundColor: '#16151A',
    textColor: '#ffffff',
    subTextColor: '#9BA1B6',
    coverImage: '',
    intimateCardBg: '',
    familyCardBg: '',
    supportersBanner: '',
    supporterSlot: '',
    goldCrown: '',
    silverCrown: '',
    bronzeCrown: '',
    identityTitleImg: '',
    badgesTitleImg: '',
    achievementsTitleImg: '',
    profileEditIcon: '',
    giftWallCardBg: '',
    giftWallCardBorder: '#382F24',
    giftWallIcon: '',
    vehicleCardBg: '',
    vehicleCardBorder: '#382F24',
    vehicleIcon: '',
    frameCardBg: '',
    frameCardBorder: '#382F24',
    frameIcon: '',
  },
  eventInfo: {
    backgroundImage: '',
    backgroundColor: '#ffffff',
    textColor: '#000000',
    subTextColor: '#888888',
  },
  notifications: {
    backgroundImage: '',
    backgroundColor: '#211211',
    textColor: '#ffffff',
    subTextColor: '#b3b3b3',
    cardBgColor: '#301c1a',
  },
};

const screens = [
  { id: 'discover', labelAr: '🔍 شاشة الاستكشاف', labelEn: '🔍 Discover Screen' },
  { id: 'message', labelAr: '💬 شاشة الرسائل', labelEn: '💬 Messages Screen' },
  { id: 'profile', labelAr: '👤 شاشة حسابي (أنا)', labelEn: '👤 Profile Screen' },
  { id: 'chat', labelAr: '✉️ شاشة المحادثة الخاصة', labelEn: '✉️ Private Chat' },
  { id: 'userProfile', labelAr: '🏷️ بطاقة المستخدم المصغرة', labelEn: '🏷️ User Card' },
  { id: 'fullProfile', labelAr: '👤 شاشة بروفايل المستخدم الكاملة', labelEn: '👤 Full User Profile' },
  { id: 'eventInfo', labelAr: '📅 تفاصيل الحدث من الداخل', labelEn: '📅 Event Info' },
  { id: 'notifications', labelAr: '🔔 إشعارات النظام', labelEn: '🔔 System Notifications' },
] as const;

type ScreenId = typeof screens[number]['id'];

const designerTabs = [
  { id: 'screens', labelAr: '📱 مصمم الشاشات التفاعلي', labelEn: '📱 Screen Designer' },
  { id: 'colors', labelAr: '🎨 ألوان وتدرجات التطبيق', labelEn: '🎨 Colors & Gradients' },
  { id: 'settings', labelAr: '⚙️ صور وإعدادات التطبيق', labelEn: '⚙️ General Assets' },
  { id: 'icons', labelAr: '✨ أيقونات التطبيق', labelEn: '✨ App Icons' },
  { id: 'assets', labelAr: '📁 أصول الشاشات (Default Assets)', labelEn: '📁 Screen Assets' },
  { id: 'ranks', labelAr: '🏆 خلفيات وإطارات الرتب', labelEn: '🏆 Rank Frames & BGs' },
] as const;

type DesignerTab = typeof designerTabs[number]['id'];

const defaultColors = {
  primaryBg: '#FFFFFF',
  textPrimary: '#16151A',
  splashNameColor: '#16151A',
  textSecondary: '#9BA1B6',
  goldColor: '#DE880F',
  buttonColor: '#6366F1',
  buttonTextColor: '#FFFFFF',
  headerColor: '#FFFFFF',
  tabBarColor: '#FFFFFF',
  bottomNavGradientStart: '#F4DDA9',
  bottomNavGradientEnd: '#FFFFFF',
  bottomNavActiveTextColor: '#894916',
  bottomNavInactiveTextColor: '#894916',
  vipCardBgColor: '#1A3D1A',
  vipCardBorderColor: '#C9A84C',
};

const defaultRoomGradients: Record<string, [string, string]> = {
  themeFriend: ['#E447E7', '#A136FF'],
  themeChat: ['#24D5C3', '#03DF99'],
  themeMusic: ['#3697FF', '#B534FF'],
  themeGame: ['#DB9C16', '#F0C724'],
  themeParty: ['#3590FF', '#294BF7'],
  themeHobby: ['#26C889', '#86BC1B'],
};

const defaultChatColors = {
  bubbleSelf: '#33FFC525',
  bubbleOther: '#1AFFFFFF',
  bubbleSelfBorder: '#33FFC525',
  bubbleOtherBorder: '#1AFFFFFF',
  bubbleSelfText: '#FFC525',
  bubbleOtherText: '#FFFFFF',
};

const rankCategories = ['wealth', 'charm', 'room'] as const;
const rankCategoryLabels: Record<string, string> = {
  wealth: '💰 الثروة (Wealth)',
  charm: '💎 الجاذبية (Charm)',
  room: '🏠 الغرفة (Room)',
};

// Words helper for Arabic descriptions
const _wordMap: Record<string, string> = {
  room: 'غرفة', bg: 'خلفية', ic: 'أيقونة', pre: 'محدد', nor: 'عادي',
  mic: 'مايك', seat: 'مقعد', gift: 'هدية', create: 'إنشاء', chat: 'محادثة',
  emoj: 'إيموجي', exit: 'خروج', follow: 'متابعة', function: 'وظائف',
  game: 'لعبة', hot: 'نشط', lock: 'قفل', notice: 'إشعار', online: 'متصل',
  owner: 'مالك', photo: 'صورة', pwd: 'كلمة سر', set: 'إعدادات',
  user: 'مستخدم', window: 'نافذة', discover: 'استكشاف', search: 'بحث',
  item: 'عنصر', tab: 'تبويب', mine: 'حسابي', wallet: 'محفظة',
  level: 'مستوى', backpack: 'حقيبة', mall: 'متجر', setting: 'إعدادات',
  feedback: 'اقتراح', report: 'بلاغ', phone: 'هاتف', camera: 'كاميرا',
  avatar: 'صورة شخصية', edit: 'تعديل', delete: 'حذف', black: 'أسود',
  close: 'إغلاق', back: 'رجوع', next: 'التالي', common: 'عام',
  gold: 'ذهبي', diamond: 'ألماسة', sex: 'جنس', male: 'ذكر', female: 'أنثى',
  super: 'مشرف', frame: 'إطار', giftAnim: 'هدية متحركة', speaking: 'متحدث',
  wave: 'موجة', miao: 'مياو', rank: 'ترتيب', border: 'حدود',
  splash: 'شاشة البداية', logo: 'شعار', social: 'تواصل', sharing: 'مشاركة',
  country: 'دولة', more: 'المزيد', header: 'رأس', indicator: 'مؤشر',
  recent: 'الأخيرة', teaming: 'فريق', music: 'موسيقى', hobby: 'هواية',
  party: 'حفلة', friend: 'صديق', label: 'تصنيف', star: 'نجمة',
  lucky: 'محظوظ', combo: 'كومبو', time: 'وقت', numOpen: 'فتح الرقم',
  bag: 'حقيبة', select: 'اختيار', panel: 'لوحة', member: 'عضو',
  float: 'عائم', cancel: 'إلغاء', volume: 'صوت', mixer: 'خلاط',
  effect: 'تأثير', style: 'نمط', info: 'معلومات', operate: 'تحكم',
  onlineInfo: 'معلومات الاتصال', package: 'حزمة', windowFloat: 'نافذة عائمة',
  followNor: 'متابعة عادي', followPre: 'متابعة محدد',
  allSelectNor: 'اختيار الكل عادي', allSelectPre: 'اختيار الكل محدد',
  luckyGiftAnim: 'رسوم هدية محظوظة', luckyGiftCoin: 'عملة الهدية المحظوظة',
  luckyGiftBg: 'خلفية الهدية المحظوظة',
  comboTime: 'وقت الكومبو', comboLuckyNor: 'كومبو محظوظ عادي',
  comboLuckyPre: 'كومبو محظوظ محدد',
  starLabel: 'تصنيف نجمة', musicLabel: 'تصنيف موسيقى',
  luckyLabel: 'تصنيف محظوظ',
  micCharmMale: 'مايك جاذبية ذكر', micSeatDefault: 'مقعد مايك افتراضي',
  micSeatBig: 'مقعد مايك كبير', micSeatLock: 'مقعد مايك مقفول',
  micSeatMute: 'مقعد مايك كتم', micphone: 'مايكروفون',
  btnDian: 'زر ديان', next2: 'التالي 2', next3: 'التالي 3', next4: 'التالي 4',
  back2: 'رجوع 2', backWhite: 'رجوع أبيض', nextBlack: 'التالي أسود',
  nextWhite: 'التالي أبيض',
  userId: 'معرف المستخدم', idCopy: 'نسخ المعرف',
  btnEdit: 'زر تعديل', photoAdd: 'إضافة صورة',
  phoneDown: 'تنزيل الهاتف', googlePay: 'Google Pay',
  vipCenter: 'مركز VIP', vipLabel: 'تصنيف VIP', vipGo: 'الذهاب إلى VIP',
  tabVip: 'تبويب VIP',
  coinBag: 'كيس العملات', detail: 'التفاصيل', filter: 'تصفية',
  walletHeader: 'رأس المحفظة',
  roomItem: 'عنصر الغرفة', itemChat: 'عنصر المحادثة',
  itemMusic: 'عنصر الموسيقى', itemGame: 'عنصر اللعبة',
  itemHobby: 'عنصر الهواية', itemParty: 'عنصر الحفلة',
  itemFriend: 'عنصر الصديق', itemRoom: 'عنصر الغرفة',
  countryMore: 'دولة المزيد', roomHot: 'غرفة نشطة',
  tabFollow: 'تبويب متابعة', tabRecent: 'تبويب الأخيرة',
  tabIndicator: 'مؤشر التبويب',
  superAdmin: 'مشرف',
  fmWave: 'موجة FM', speakingWave: 'موجة متحدث',
  rankBorder: 'حدود الترتيب',
  imgLogo: 'شعار', imgPre: 'الصورة المبدئية',
  introduceBg: 'خلفية التعريف',
  headerMember: 'رأس العضو', selectNum: 'اختيار الرقم',
  lockState: 'حالة القفل', pwdLockOff: 'قفل كلمة السر مغلق',
  pwdLockOpen: 'قفل كلمة السر مفتوح',
  micDown: 'مايك لأسفل', micOn: 'مايك شغال', micOff: 'مايك طافي',
  micOperate: 'تشغيل المايك',
  userinfo: 'معلومات المستخدم', userInfo: 'معلومات المستخدم',
  menu: 'قائمة', popup: 'منبثق', options: 'خيارات',
  banner: 'لافتة', top: 'أعلى', bottom: 'أسفل', center: 'وسط',
  notification: 'إشعار', message: 'رسالة', system: 'نظام',
  information: 'معلومات',
  placeholder: 'مكان',
  bd: 'مدير', cp: 'منسق', agency: 'وكالة', union: 'نقابة',
};

function constantToArabic(constant: string): string {
  let name = constant;
  name = name.replace(/(Ic|Pre|Nor|Bg|Img|Svga|Webp|Png|Gif|Jpg|Jpeg)$/g, '');
  const parts = name.split(/(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])/g);
  const mapped = parts.map(p => {
    const lower = p.toLowerCase();
    return _wordMap[lower] || lower;
  });
  return mapped.join(' ');
}

export default function AppVisualDesigner() {
  const { lang } = useContext(I18nContext);
  const [activeDesignerTab, setActiveDesignerTab] = useState<DesignerTab>('screens');
  const [activeTab, setActiveTab] = useState<ScreenId>('discover');
  
  // App Config states
  const [appName, setAppName] = useState('');
  const [splashGifUrl, setSplashGifUrl] = useState('');
  const [bottomNavBgImage, setBottomNavBgImage] = useState('');
  const [fontFamily, setFontFamily] = useState('Cairo');
  const [borderRadius, setBorderRadius] = useState(8);
  const [globalColors, setGlobalColors] = useState<Record<string, string>>(defaultColors);
  const [roomGradients, setRoomGradients] = useState<Record<string, [string, string]>>(defaultRoomGradients);
  const [roomBgImages, setRoomBgImages] = useState<Record<string, string>>({});
  const [globalImages, setGlobalImages] = useState<Record<string, string>>({});
  const [chatColors, setChatColors] = useState<Record<string, string>>(defaultChatColors);
  const [rankConfig, setRankConfig] = useState<Record<string, any>>({});
  const [roomBgPrice, setRoomBgPrice] = useState(0);
  
  // Screen assets browser states
  const [assets, setAssets] = useState<AppAssetRecord[]>([]);
  const [selectedAssetScreen, setSelectedAssetScreen] = useState(SCREEN_ORDER[0]);
  const [assetSearch, setAssetSearch] = useState('');
  const [uploadingAssetKey, setUploadingAssetKey] = useState<string | null>(null);

  // Ranks sub-tab states
  const [activeRankSubTab, setActiveRankSubTab] = useState<'wealth' | 'charm' | 'room'>('wealth');
  const [rankFrames, setRankFrames] = useState<any[]>([]);

  // Icon overrides states
  const [iconOverrides, setIconOverrides] = useState<Record<string, string>>({});
  const [searchQuery, setSearchQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');

  // Screen visual overrides
  const [visuals, setVisuals] = useState<ScreenVisuals>(defaultVisuals);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState('');

  const showMsg = (text: string) => { setMsg(text); setTimeout(() => setMsg(''), 3000); };

  useEffect(() => {
    loadAllData();
  }, []);

  const loadAllData = async () => {
    try {
      const cfg = await getAppConfig();
      if (cfg) {
        if (cfg.appName) setAppName(cfg.appName);
        if (cfg.splashGifUrl) setSplashGifUrl(cfg.splashGifUrl);
        if (cfg.bottomNavBgImage) setBottomNavBgImage(cfg.bottomNavBgImage);
        if (cfg.fontFamily) setFontFamily(cfg.fontFamily);
        if (Number.isFinite(cfg.borderRadius)) setBorderRadius(cfg.borderRadius!);
        if (Number.isFinite(cfg.roomBgPrice)) setRoomBgPrice(cfg.roomBgPrice);
        
        const colorsCopy = { ...defaultColors };
        for (const key of Object.keys(defaultColors)) {
          if (cfg[key as keyof typeof cfg]) {
            colorsCopy[key as keyof typeof defaultColors] = String(cfg[key as keyof typeof cfg]);
          }
        }
        setGlobalColors(colorsCopy);

        if (cfg.roomGradients && typeof cfg.roomGradients === 'object') {
          const merged: Record<string, [string, string]> = { ...defaultRoomGradients };
          for (const [k, v] of Object.entries(cfg.roomGradients)) {
            if (Array.isArray(v) && v.length >= 2) {
              merged[k] = [String(v[0] || '#ffffff'), String(v[1] || '#000000')];
            }
          }
          setRoomGradients(merged);
        }
        if (cfg.roomBgImages && typeof cfg.roomBgImages === 'object') {
          setRoomBgImages(cfg.roomBgImages);
        }
        if (cfg.globalImages && typeof cfg.globalImages === 'object') {
          setGlobalImages(cfg.globalImages);
        }
        if (cfg.chatColors && typeof cfg.chatColors === 'object') {
          setChatColors({ ...defaultChatColors, ...cfg.chatColors });
        }
        if (cfg.rankConfig && typeof cfg.rankConfig === 'object') {
          setRankConfig(cfg.rankConfig);
        }
        if (cfg.iconOverrides && typeof cfg.iconOverrides === 'object') {
          setIconOverrides(cfg.iconOverrides as Record<string, string>);
        }

        const storedVisuals = cfg.screenVisuals;
        if (storedVisuals && typeof storedVisuals === 'object') {
          const merged: ScreenVisuals = { ...defaultVisuals };
          for (const s of Object.keys(defaultVisuals) as Array<keyof ScreenVisuals>) {
            if (storedVisuals[s] && typeof storedVisuals[s] === 'object') {
              merged[s] = { ...defaultVisuals[s], ...storedVisuals[s] };
            }
          }
          setVisuals(merged);
        }
      }

      // Load screen assets (R.xxx)
      const resAssets = await getAppAssets({ limit: 5000 });
      setAssets(resAssets.data || []);

      // Load ranking frames
      const { data: framesData } = await supabase.from('ranking_frames').select('*').order('category').order('rank');
      setRankFrames(framesData || []);

    } catch (e) { console.warn(e); }
    setLoading(false);
  };

  const updateField = (screen: ScreenId, field: string, value: string) => {
    setVisuals(prev => ({
      ...prev,
      [screen]: { ...prev[screen], [field]: value },
    }));
  };

  const handleSaveAll = async () => {
    setSaving(true);
    try {
      const updates = {
        appName,
        splashGifUrl,
        bottomNavBgImage,
        fontFamily,
        borderRadius,
        ...globalColors,
        roomGradients,
        roomBgImages,
        globalImages,
        chatColors,
        rankConfig,
        roomBgPrice,
        iconOverrides,
        screenVisuals: visuals,
      };
      await updateAppConfig(updates as any);
      showMsg(lang === 'ar' ? 'تم حفظ التعديلات الشاملة بنجاح!' : 'All configurations saved successfully!');
    } catch (e) {
      showMsg(lang === 'ar' ? 'فشل حفظ التعديلات' : 'Save failed');
      console.warn(e);
    }
    setSaving(false);
  };

  const handleImageUpload = async (file: File, screen: ScreenId, field: string) => {
    try {
      const path = `screen_visuals/${screen}_${field}_${Date.now()}`;
      const url = await uploadAppAsset(file, path);
      if (url) updateField(screen, field, url);
    } catch (e) {
      showMsg(lang === 'ar' ? 'فشل رفع الصورة' : 'Upload failed');
    }
  };

  const handleIconUpload = async (file: File, key: string) => {
    try {
      const path = `icon_overrides/${key.replace('.', '_')}_${Date.now()}`;
      const url = await uploadAppAsset(file, path);
      if (url) {
        setIconOverrides(prev => ({ ...prev, [key]: url }));
      }
    } catch (e) {
      showMsg(lang === 'ar' ? 'فشل رفع الأيقونة' : 'Icon upload failed');
    }
  };

  const handleSplashUpload = async (file: File) => {
    try {
      const path = `splash/${Date.now()}`;
      const url = await uploadAppAsset(file, path);
      if (url) setSplashGifUrl(url);
    } catch (e) {
      showMsg(lang === 'ar' ? 'فشل رفع الشاشة الترحيبية' : 'Splash upload failed');
    }
  };

  const handleBottomNavBgUpload = async (file: File) => {
    try {
      const path = `bottom_nav_bg/${Date.now()}`;
      const url = await uploadAppAsset(file, path);
      if (url) setBottomNavBgImage(url);
    } catch (e) {
      showMsg(lang === 'ar' ? 'فشل رفع صورة الشريط السفلي' : 'Upload failed');
    }
  };

  const handleAssetOverrideUpload = async (entry: { fullKey: string; constant: string; path: string }) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*,.svga,.mp4,.gif,.vap,.json';
    input.onchange = async () => {
      const file = input.files?.[0];
      if (!file) return;
      setUploadingAssetKey(entry.fullKey);
      try {
        const url = await uploadAppAsset(file, entry.fullKey);
        const existing = assets.find(a => a.key === entry.fullKey);
        const record: AppAssetRecord = {
          id: existing?.id || crypto.randomUUID(),
          key: entry.fullKey,
          name: entry.constant,
          type: file.name.endsWith('.svga') ? 'svga' : file.name.endsWith('.vap') ? 'vap' : file.name.endsWith('.json') ? 'lottie' : 'image',
          category: selectedAssetScreen,
          subcategory: 'R.xxx',
          localPath: entry.path,
          remoteUrl: url,
          defaultValue: '',
          mimeType: file.type || 'application/octet-stream',
          fileSize: file.size,
          width: null,
          height: null,
          sortOrder: 0,
          isActive: true,
          createdAt: existing?.createdAt || new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        };
        await upsertAppAsset(record);
        // Refresh local assets state
        const resAssets = await getAppAssets({ limit: 5000 });
        setAssets(resAssets.data || []);
        showMsg(lang === 'ar' ? 'تم رفع الأصل المخصص بنجاح!' : 'Custom asset uploaded!');
      } catch (err) {
        alert('فشل الرفع: ' + (err as Error).message);
      }
      setUploadingAssetKey(null);
    };
    input.click();
  };

  const handleAssetOverrideDelete = async (fullKey: string) => {
    const asset = assets.find(a => a.key === fullKey);
    if (!asset) return;
    if (!confirm(lang === 'ar' ? `حذف البديل المخصص لـ "${asset.name}"؟` : `Delete custom override for "${asset.name}"?`)) return;
    try {
      await deleteAppAsset(asset.id);
      const resAssets = await getAppAssets({ limit: 5000 });
      setAssets(resAssets.data || []);
      showMsg(lang === 'ar' ? 'تم حذف الأصل المخصص والعودة للوضع الافتراضي' : 'Custom asset override deleted');
    } catch {}
  };

  const handleSaveFrame = async (category: string, rank: number, assetUrl: string, assetType: string) => {
    try {
      await supabase.from('ranking_frames').upsert(
        { category, rank, asset_url: assetUrl, asset_type: assetType },
        { onConflict: 'category,rank' }
      );
      const { data } = await supabase.from('ranking_frames').select('*').order('category').order('rank');
      setRankFrames(data || []);
    } catch {}
  };

  const handleClearFrame = async (category: string, rank: number) => {
    if (!confirm(lang === 'ar' ? 'مسح هذا الإطار؟' : 'Delete this frame?')) return;
    try {
      await supabase.from('ranking_frames').delete().eq('category', category).eq('rank', rank);
      const { data } = await supabase.from('ranking_frames').select('*').order('category').order('rank');
      setRankFrames(data || []);
    } catch {}
  };

  if (loading) return <div className="text-slate-400 text-sm p-6">Loading Visual Designer Hub...</div>;

  const currentConfig = visuals[activeTab] || {};

  // Filtered icons
  const iconCategories = Array.from(new Set(iconRegistry.map(e => e.category))).sort();
  const filteredIcons = iconRegistry.filter(e => {
    if (categoryFilter && e.category !== categoryFilter) return false;
    if (searchQuery) {
      const q = searchQuery.toLowerCase();
      return e.key.toLowerCase().includes(q) || e.name.toLowerCase().includes(q);
    }
    return true;
  });

  // Filtered Screen assets (R.xxx)
  const screenCategories = SCREEN_ORDER.filter(s => {
    const data = SCREEN_ASSETS[s];
    return data && data.assets.length > 0;
  });
  const currentAssets = SCREEN_ASSETS[selectedAssetScreen]?.assets || [];
  const filteredScreenAssets = currentAssets.filter(entry => {
    if (assetSearch) {
      const q = assetSearch.toLowerCase();
      return entry.constant.toLowerCase().includes(q) || entry.path.toLowerCase().includes(q);
    }
    return true;
  });

  return (
    <div className="space-y-6" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      {/* Header Bar */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-white text-lg font-semibold flex items-center gap-2">
            <Sliders className="w-5 h-5 text-indigo-400" />
            {lang === 'ar' ? 'مركز تصميم وتخصيص مظهر التطبيق بالكامل' : 'App Designer & Visual Customizer Hub'}
          </h2>
          <p className="text-slate-400 text-xs mt-1">
            {lang === 'ar'
              ? 'صمم الألوان، الأيقونات، التدرجات، أصول الشاشات الافتراضية، وإطارات الرتب في مكان واحد.'
              : 'Design app colors, icons, gradients, screen assets, and rank frames in one master workspace.'}
          </p>
        </div>
        <div className="flex gap-2">
          <button onClick={handleSaveAll} disabled={saving} className="px-5 py-2 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-bold rounded-xl flex items-center gap-1.5 shadow-lg shadow-emerald-950/30 transition-all">
            <Save className="w-4 h-4" /> {saving ? (lang === 'ar' ? 'جاري الحفظ...' : 'Saving...') : (lang === 'ar' ? 'حفظ كافة التعديلات' : 'Save All Changes')}
          </button>
        </div>
      </div>

      {msg && <div className="bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs px-4 py-2 rounded-lg">{msg}</div>}

      {/* Main Designer Sub-Tabs Navigation */}
      <div className="flex gap-1.5 border-b border-white/5 pb-3 overflow-x-auto">
        {designerTabs.map(tab => (
          <button
            key={tab.id}
            onClick={() => setActiveDesignerTab(tab.id)}
            className={`px-4 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-2 shrink-0 ${
              activeDesignerTab === tab.id
                ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-950/20'
                : 'text-slate-400 hover:bg-white/5 hover:text-white'
            }`}
          >
            {lang === 'ar' ? tab.labelAr : tab.labelEn}
          </button>
        ))}
      </div>

      {/* Screen customization view with Mock Phone Preview */}
      {activeDesignerTab === 'screens' && (
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
          {/* Simulated iPhone (5 cols) */}
          <div className="lg:col-span-5 flex justify-center">
            <div className="w-[320px] h-[640px] rounded-[40px] border-[10px] border-slate-800 bg-[#09090b] relative overflow-hidden shadow-2xl flex flex-col">
              {/* Notch */}
              <div className="absolute top-0 left-1/2 -translate-x-1/2 w-32 h-6 bg-slate-800 rounded-b-2xl z-50 flex items-center justify-center">
                <div className="w-3 h-3 rounded-full bg-slate-900 border border-slate-700/50" />
              </div>

              {/* Simulated Screen */}
              <div
                className="flex-1 relative overflow-y-auto pt-8 flex flex-col text-right"
                style={{
                  backgroundColor: currentConfig.backgroundColor || '#111',
                  backgroundImage: currentConfig.backgroundImage ? `url(${currentConfig.backgroundImage})` : 'none',
                  backgroundSize: 'cover',
                  backgroundPosition: 'center',
                  color: currentConfig.textColor || '#fff',
                }}
              >
                {/* Discover Screen */}
                {activeTab === 'discover' && (
                  <div className="flex-1 flex flex-col px-3 py-2 space-y-4">
                    <div className="flex items-center justify-between">
                      <span className="font-bold text-sm" style={{ color: currentConfig.textColor }}>{lang === 'ar' ? 'الاستكشاف' : 'Discover'}</span>
                      <Search className="w-4 h-4" style={{ color: currentConfig.textColor }} />
                    </div>
                    <div className="flex gap-2">
                      {['دردشة', 'ألعاب', 'حفلة'].map((tab, idx) => (
                        <span key={idx} className="px-3 py-1 rounded-full text-[10px] font-medium" style={{ backgroundColor: idx === 0 ? (currentConfig.textColor + '15') : 'transparent', color: idx === 0 ? currentConfig.textColor : currentConfig.subTextColor, border: `1px solid ${idx === 0 ? currentConfig.textColor : 'transparent'}` }}>{tab}</span>
                      ))}
                    </div>
                    <div className="h-24 rounded-xl bg-gradient-to-r from-purple-500/20 to-indigo-500/20 border border-white/5 flex items-center justify-center">
                      <span className="text-[10px]" style={{ color: currentConfig.subTextColor }}>🔥 Banner Carousel</span>
                    </div>
                    <div className="grid grid-cols-2 gap-2">
                      {[1, 2].map((id) => (
                        <div key={id} className="rounded-xl p-2.5 flex flex-col space-y-2 border border-white/5" style={{ backgroundColor: currentConfig.cardBgColor || 'rgba(255,255,255,0.05)' }}>
                          <div className="w-8 h-8 rounded-lg bg-indigo-600/40 flex items-center justify-center text-xs">🎙</div>
                          <span className="text-[10px] font-semibold truncate text-right" style={{ color: currentConfig.textColor }}>{lang === 'ar' ? `غرفة رقم ${id}` : `Room #${id}`}</span>
                          <span className="text-[8px] text-right" style={{ color: currentConfig.subTextColor }}>👤 2.4k online</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Messages Screen */}
                {activeTab === 'message' && (
                  <div className="flex-1 flex flex-col px-3 py-2 space-y-4">
                    <span className="font-bold text-sm" style={{ color: currentConfig.textColor }}>{lang === 'ar' ? 'الرسائل' : 'Messages'}</span>
                    <div className="flex gap-2">
                      <div className="flex-1 p-2 rounded-xl flex items-center gap-2 border border-white/5" style={{ backgroundColor: currentConfig.cardBgColor || 'rgba(255,255,255,0.05)' }}>
                        <div className="w-6 h-6 rounded-lg bg-yellow-500/20 flex items-center justify-center text-xs">📅</div>
                        <div className="flex flex-col text-[8px] text-right">
                          <span className="font-bold" style={{ color: currentConfig.textColor }}>{lang === 'ar' ? 'الحدث' : 'Event'}</span>
                          <span style={{ color: currentConfig.subTextColor }}>2 updates</span>
                        </div>
                      </div>
                      <div className="flex-1 p-2 rounded-xl flex items-center gap-2 border border-white/5" style={{ backgroundColor: currentConfig.cardBgColor || 'rgba(255,255,255,0.05)' }}>
                        <div className="w-6 h-6 rounded-lg bg-indigo-500/20 flex items-center justify-center text-xs">🔔</div>
                        <div className="flex flex-col text-[8px] text-right">
                          <span className="font-bold" style={{ color: currentConfig.textColor }}>{lang === 'ar' ? 'النظام' : 'System'}</span>
                          <span style={{ color: currentConfig.subTextColor }}>3 updates</span>
                        </div>
                      </div>
                    </div>
                    <div className="space-y-2">
                      {[1, 2].map((id) => (
                        <div key={id} className="p-2.5 rounded-xl flex items-center gap-2 border border-white/5" style={{ backgroundColor: currentConfig.cardBgColor || 'rgba(255,255,255,0.05)' }}>
                          <div className="w-8 h-8 rounded-full bg-slate-600/30 flex items-center justify-center text-xs">👤</div>
                          <div className="flex-1 flex flex-col text-[9px] text-right">
                            <span className="font-bold" style={{ color: currentConfig.textColor }}>Ahmed Ali</span>
                            <span style={{ color: currentConfig.subTextColor }}>How is the update looking?</span>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Profile Screen */}
                {activeTab === 'profile' && (
                  <div className="flex-1 flex flex-col px-3 py-2 space-y-4">
                    <div className="flex items-center gap-3 flex-row-reverse">
                      <div className="w-12 h-12 rounded-full border-2 border-indigo-500 bg-slate-600/20 flex items-center justify-center">👤</div>
                      <div className="flex flex-col text-right">
                        <span className="font-bold text-xs" style={{ color: currentConfig.textColor }}>Legendary User</span>
                        <span className="text-[9px]" style={{ color: currentConfig.subTextColor }}>ID: 12345678</span>
                      </div>
                    </div>
                    <div className="p-3 rounded-xl flex items-center justify-between border border-white/5" style={{ backgroundColor: currentConfig.cardBgColor || 'rgba(255,255,255,0.05)' }}>
                      <span className="text-[8px] px-2 py-0.5 rounded bg-indigo-500/20 text-indigo-400">Recharge</span>
                      <span className="text-[9px]" style={{ color: currentConfig.textColor }}>💰 10,500 Coins</span>
                    </div>
                    <div className="space-y-1">
                      {['My Wallet', 'Badges Cabinet', 'VIP Center'].map((opt, idx) => (
                        <div key={idx} className="p-2.5 rounded-xl flex items-center justify-between border border-white/5" style={{ backgroundColor: currentConfig.cardBgColor || 'rgba(255,255,255,0.05)' }}>
                          <ChevronRight className="w-3.5 h-3.5 rotate-180" style={{ color: currentConfig.subTextColor }} />
                          <span className="text-[9px]" style={{ color: currentConfig.textColor }}>{opt}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Private Chat Screen */}
                {activeTab === 'chat' && (
                  <div className="flex-1 flex flex-col px-3 py-2 justify-between">
                    <div className="flex items-center justify-between border-b border-white/5 pb-2 flex-row-reverse">
                      <span className="font-bold text-xs" style={{ color: currentConfig.textColor }}>Private Chat</span>
                    </div>
                    <div className="flex-1 py-4 space-y-3 flex flex-col justify-end">
                      <div className="flex items-end gap-2 max-w-[80%] flex-row-reverse">
                        <div className="w-6 h-6 rounded-full bg-slate-600/30 flex items-center justify-center text-[10px]">👤</div>
                        <div className="p-2 rounded-2xl rounded-br-none text-[9px] text-right" style={{ backgroundColor: currentConfig.bubbleOtherBgColor || '#fff', color: currentConfig.textColor }}>Custom visual designer deployed!</div>
                      </div>
                      <div className="flex items-end gap-2 max-w-[80%] self-start flex-row-reverse">
                        <div className="p-2 rounded-2xl rounded-bl-none text-[9px] text-slate-900 text-right" style={{ backgroundColor: currentConfig.bubbleSelfBgColor || '#ffe082' }}>Looks awesome.</div>
                      </div>
                    </div>
                    <div className="flex gap-1 border-t border-white/5 pt-2 items-center">
                      <div className="flex-1 bg-white/5 border border-white/10 rounded-full px-3 py-1 flex items-center justify-between flex-row-reverse">
                        <span className="text-[9px]" style={{ color: currentConfig.subTextColor }}>Write...</span>
                      </div>
                    </div>
                  </div>
                )}

                {/* User Mini Profile Card */}
                {activeTab === 'userProfile' && (
                  <div className="flex-1 flex flex-col justify-end overflow-y-auto max-h-[500px] p-2">
                    <div
                      className="rounded-3xl p-4 pt-10 space-y-3 relative border text-center text-xs"
                      style={{
                        backgroundColor: currentConfig.backgroundColor || '#16141D',
                        borderColor: currentConfig.borderColor || '#382F24',
                        backgroundImage: currentConfig.backgroundImage ? `url(${currentConfig.backgroundImage})` : 'none',
                        backgroundSize: 'cover',
                        backgroundPosition: 'center',
                        color: currentConfig.textColor || '#fff',
                      }}
                    >
                      {/* Top Protruding Avatar */}
                      <div className="absolute -top-7 left-1/2 -translate-x-1/2">
                        <div
                          className="w-14 h-14 rounded-full border-2 bg-slate-800 flex items-center justify-center shadow-lg overflow-hidden"
                          style={{ borderColor: currentConfig.borderColor || '#382F24' }}
                        >
                          <span className="text-2xl">👤</span>
                        </div>
                      </div>

                      {/* Top Right More Button */}
                      <div className="absolute top-3 right-3">
                        <div className="w-6 h-6 rounded-full bg-white/10 flex items-center justify-center cursor-pointer">
                          {currentConfig.profileMoreIcon ? (
                            <img src={currentConfig.profileMoreIcon} className="w-3.5 h-3.5 object-contain" />
                          ) : (
                            <span className="text-white/70 text-xs">•••</span>
                          )}
                        </div>
                      </div>

                      {/* User Name & Gender & VIP */}
                      <div className="flex items-center justify-center gap-1.5 pt-1">
                        <span className="w-4 h-4 rounded-full bg-blue-500 text-white flex items-center justify-center text-[9px]">♂</span>
                        <h4 className="font-bold text-sm" style={{ color: currentConfig.textColor || '#fff' }}>
                          .مُحَمَّد
                        </h4>
                        <span className="w-4 h-4 rounded-full bg-amber-900/60 border border-amber-400 text-amber-300 flex items-center justify-center text-[8px]">👑</span>
                      </div>

                      {/* ID & Copy & Flag */}
                      <div className="flex items-center justify-center gap-1 text-[11px]" style={{ color: currentConfig.subTextColor || '#9BA1B6' }}>
                        <span>📋</span>
                        <span className="font-mono">ID: 9002990</span>
                        <span>🇪🇬</span>
                      </div>

                      {/* Host Badge */}
                      <div className="flex justify-center">
                        {currentConfig.hostBadgeImg ? (
                          <img src={currentConfig.hostBadgeImg} className="h-5 object-contain" />
                        ) : (
                          <span
                            className="text-[10px] font-bold px-3 py-0.5 rounded-full text-white border border-blue-400/50 shadow-sm"
                            style={{ backgroundColor: currentConfig.hostBadgeBg || '#1E5BB5' }}
                          >
                            مضيف
                          </span>
                        )}
                      </div>

                      {/* Received Gifts Bar */}
                      <div
                        className="h-12 rounded-xl border p-2 flex items-center justify-between relative overflow-hidden"
                        style={{
                          backgroundColor: currentConfig.giftBarBg ? 'transparent' : '#221A11',
                          backgroundImage: currentConfig.giftBarBg ? `url(${currentConfig.giftBarBg})` : 'none',
                          backgroundSize: 'cover',
                          borderColor: currentConfig.giftBarBorder || '#5E4321',
                        }}
                      >
                        {currentConfig.giftBarBorderImg && (
                          <img src={currentConfig.giftBarBorderImg} className="absolute inset-0 w-full h-full object-fill pointer-events-none" />
                        )}
                        <span className="text-[10px] text-white/50 relative z-10">〈</span>
                        <div className="flex items-center gap-1.5 relative z-10">
                          <span className="text-xs">🌙<sub className="text-[7px]">x22</sub></span>
                          <span className="text-xs">💎<sub className="text-[7px]">x38</sub></span>
                          <span className="text-xs">🍀<sub className="text-[7px]">x57</sub></span>
                        </div>
                        <div className="flex flex-col items-end relative z-10">
                          <div className="flex items-center gap-1">
                            <span className="text-[9px] font-bold text-white">استلام</span>
                            <span className="text-[10px]">🎁</span>
                          </div>
                          <span className="text-[9px] font-bold text-amber-400">2.1k</span>
                        </div>
                      </div>

                      {/* Stats Row */}
                      <div className="flex justify-around items-center text-center py-1">
                        <div>
                          <div className="font-bold text-xs" style={{ color: currentConfig.textColor || '#fff' }}>13</div>
                          <div className="text-[9px]" style={{ color: currentConfig.subTextColor || '#9BA1B6' }}>الزائر</div>
                        </div>
                        <div className="w-[1px] h-4 bg-white/10" />
                        <div>
                          <div className="font-bold text-xs" style={{ color: currentConfig.textColor || '#fff' }}>1</div>
                          <div className="text-[9px]" style={{ color: currentConfig.subTextColor || '#9BA1B6' }}>المحبون</div>
                        </div>
                        <div className="w-[1px] h-4 bg-white/10" />
                        <div>
                          <div className="font-bold text-xs" style={{ color: currentConfig.textColor || '#fff' }}>1</div>
                          <div className="text-[9px]" style={{ color: currentConfig.subTextColor || '#9BA1B6' }}>متابعون</div>
                        </div>
                      </div>

                      {/* Equipment Row */}
                      <div className="grid grid-cols-2 gap-2 text-right">
                        {/* Vehicle Card */}
                        <div className="h-[52px] rounded-xl bg-white/5 border border-white/5 p-2 flex items-center justify-between">
                          <span className="text-[8px] text-white/40">〈</span>
                          <span className="text-base text-white/30">🏎️</span>
                          <span className="text-[9px] font-bold text-white">مركبة</span>
                        </div>
                        {/* Frame Card */}
                        <div className="h-[52px] rounded-xl bg-white/5 border border-white/5 p-2 flex items-center justify-between">
                          <span className="text-[8px] text-white/40">〈</span>
                          <span className="text-base text-white/30">👑</span>
                          <span className="text-[9px] font-bold text-white">اطار</span>
                        </div>
                      </div>

                      {/* Bottom Action Bar */}
                      <div className="flex items-center gap-2 pt-1">
                        {/* Golden Gift Button */}
                        <button
                          className="flex-[3] h-9 rounded-xl font-bold text-xs text-slate-950 flex items-center justify-center gap-1 shadow-md"
                          style={{
                            background: currentConfig.buttonColor
                              ? `linear-gradient(135deg, ${currentConfig.buttonColor}, #C99427)`
                              : 'linear-gradient(135deg, #E8BD56, #C99427)',
                          }}
                        >
                          {currentConfig.profileGiftIcon ? (
                            <img src={currentConfig.profileGiftIcon} className="w-4 h-4 object-contain" />
                          ) : (
                            <span>🎁</span>
                          )}
                          <span>هدية</span>
                        </button>

                        {/* @ Mention Button */}
                        <button className="w-9 h-9 rounded-full bg-[#24202B] border border-white/10 flex items-center justify-center text-white text-xs font-bold">
                          {currentConfig.profileMentionIcon ? (
                            <img src={currentConfig.profileMentionIcon} className="w-4 h-4 object-contain" />
                          ) : (
                            <span>@</span>
                          )}
                        </button>

                        {/* Chat Button */}
                        <button className="w-9 h-9 rounded-full bg-[#24202B] border border-white/10 flex items-center justify-center text-white text-xs">
                          {currentConfig.profileChatIcon ? (
                            <img src={currentConfig.profileChatIcon} className="w-4 h-4 object-contain" />
                          ) : (
                            <span>💬</span>
                          )}
                        </button>

                        {/* Follow Button */}
                        <button className="w-9 h-9 rounded-full bg-[#24202B] border border-white/10 flex items-center justify-center text-pink-400 text-xs">
                          {currentConfig.profileFollowIcon ? (
                            <img src={currentConfig.profileFollowIcon} className="w-4 h-4 object-contain" />
                          ) : (
                            <span>🤍+</span>
                          )}
                        </button>
                      </div>
                    </div>
                  </div>
                )}

                {/* Full User Profile Screen Preview */}
                {activeTab === 'fullProfile' && (
                  <div
                    className="flex-1 flex flex-col overflow-y-auto max-h-[500px] rounded-2xl relative border border-white/10 text-right text-xs"
                    style={{
                      backgroundColor: currentConfig.backgroundColor || '#16151A',
                      backgroundImage: currentConfig.backgroundImage ? `url(${currentConfig.backgroundImage})` : 'none',
                      backgroundSize: 'cover',
                      backgroundPosition: 'center',
                      color: currentConfig.textColor || '#fff',
                    }}
                  >
                    {/* Top Title Bar */}
                    <div className="flex justify-between items-center px-3 py-2.5 z-10">
                      <div className="text-white/80 font-bold text-xs cursor-pointer">〈</div>
                      <div className="flex items-center justify-center w-6 h-6 rounded-full bg-white/10">
                        {currentConfig.profileEditIcon ? (
                          <img src={currentConfig.profileEditIcon} className="w-4 h-4 object-contain" />
                        ) : (
                          <span className="text-[10px]">✏️</span>
                        )}
                      </div>
                    </div>

                    {/* Top Cover Banner */}
                    <div className="h-28 w-full relative -mt-9 overflow-hidden">
                      {currentConfig.coverImage ? (
                        <img src={currentConfig.coverImage} className="w-full h-full object-cover" />
                      ) : (
                        <div className="w-full h-full bg-gradient-to-b from-purple-900/60 to-[#16151A]" />
                      )}
                      <div className="absolute inset-0 bg-gradient-to-t from-[#16151A] via-transparent to-transparent" />
                    </div>

                    {/* Content Container */}
                    <div className="p-3 space-y-4 -mt-6 relative z-10">
                      {/* Header with Avatar on Right and Info on Left */}
                      <div className="flex items-end justify-between gap-3 flex-row-reverse">
                        {/* Avatar on Right */}
                        <div className="relative flex-shrink-0">
                          <div className="w-16 h-16 rounded-full border-2 border-white bg-slate-700 overflow-hidden flex items-center justify-center">
                            <span className="text-2xl">👤</span>
                          </div>
                        </div>

                        {/* Name & Details on Left */}
                        <div className="flex-1 flex flex-col items-start text-left">
                          <h4 className="font-bold text-sm text-white flex items-center gap-1">
                            .مُحَمَّد
                          </h4>
                          
                          {/* ID & Gender & Country Code */}
                          <div className="flex items-center gap-1.5 mt-1 flex-wrap">
                             <span className="bg-white/15 px-1.5 py-0.5 rounded text-[8px] text-white/90">ID: 8883517</span>
                             <span className="bg-blue-500/30 text-blue-300 px-1.5 py-0.5 rounded text-[8px] flex items-center gap-0.5">
                               ♂ 28
                             </span>
                             <span className="text-xs">🇪🇬</span>
                          </div>

                          {/* Levels */}
                          <div className="flex items-center gap-1 mt-1.5">
                            <span className="bg-blue-500 text-white font-bold text-[7px] px-1 py-0.5 rounded-full">财富 13</span>
                            <span className="bg-pink-500 text-white font-bold text-[7px] px-1 py-0.5 rounded-full">魅力 1</span>
                            <span className="bg-green-500 text-white font-bold text-[7px] px-1 py-0.5 rounded-full">活跃 15</span>
                          </div>

                          {/* Signature */}
                          <p className="text-[8px] text-white/50 mt-1.5 truncate max-w-[120px] text-left">
                            أقول شيئاً لجعل الآخرين يعرفون لك .
                          </p>
                        </div>
                      </div>

                      {/* Stats Row */}
                      <div className="flex justify-between items-center text-center px-4 py-1 text-white/80">
                        <div>
                          <div className="font-bold text-[11px]" style={{ color: currentConfig.textColor || '#fff' }}>178</div>
                          <div className="text-[8px] text-white/40" style={{ color: currentConfig.subTextColor || 'rgba(255,255,255,0.4)' }}>الزائرين</div>
                        </div>
                        <div>
                          <div className="font-bold text-[11px]" style={{ color: currentConfig.textColor || '#fff' }}>35</div>
                          <div className="text-[8px] text-white/40" style={{ color: currentConfig.subTextColor || 'rgba(255,255,255,0.4)' }}>أتابعه</div>
                        </div>
                        <div>
                          <div className="font-bold text-[11px]" style={{ color: currentConfig.textColor || '#fff' }}>5</div>
                          <div className="text-[8px] text-white/40" style={{ color: currentConfig.subTextColor || 'rgba(255,255,255,0.4)' }}>تمت متابعة</div>
                        </div>
                      </div>

                      {/* Two Cards Row (RTL) */}
                      <div className="grid grid-cols-2 gap-2 flex-row-reverse text-right">
                        {/* Partner Card (Right in RTL) */}
                        <div
                          className="h-16 rounded-xl border p-2 flex items-center justify-between gap-1"
                          style={{
                            borderColor: 'rgba(245, 158, 11, 0.4)',
                            background: currentConfig.familyCardBg ? `url(${currentConfig.familyCardBg})` : 'linear-gradient(135deg, #4A4A1A 0%, #1A1A0D 100%)',
                            backgroundSize: 'cover',
                          }}
                        >
                          <span className="text-[8px] text-white/40">〈</span>
                          <div className="flex flex-col items-end">
                            <div className="flex items-center gap-1">
                              <span className="text-[9px] font-bold text-white">العائلة</span>
                              <div className="w-5 h-5 rounded-full bg-slate-600 overflow-hidden flex items-center justify-center text-[8px]">👤</div>
                            </div>
                            <span className="text-[8px] text-amber-400 font-bold mt-0.5">ID:15652</span>
                          </div>
                        </div>

                        {/* Intimate Card (Left in RTL) */}
                        <div
                          className="h-16 rounded-xl border p-2 flex items-center justify-between gap-1"
                          style={{
                            borderColor: 'rgba(236, 72, 153, 0.4)',
                            background: currentConfig.intimateCardBg ? `url(${currentConfig.intimateCardBg})` : 'linear-gradient(135deg, #5A1A4A 0%, #2A0D2A 100%)',
                            backgroundSize: 'cover',
                          }}
                        >
                          <span className="text-[8px] text-white/40">〈</span>
                          <div className="flex flex-col items-end">
                            <div className="flex items-center gap-1">
                              <span className="text-[9px] font-bold text-white">علاقة حميمة</span>
                              <span className="text-[10px]">💖</span>
                            </div>
                            <span className="text-[7px] text-white/60 mt-0.5">اربط علاقة حميمة الآن!</span>
                          </div>
                        </div>
                      </div>

                      {/* Supporters Row */}
                      <div
                        className="h-14 rounded-xl border border-white/10 relative overflow-hidden flex items-center px-3 justify-between"
                        style={{
                          background: currentConfig.supportersBanner ? `url(${currentConfig.supportersBanner})` : 'rgba(0,0,0,0.3)',
                          backgroundSize: 'cover',
                        }}
                      >
                        {!currentConfig.supportersBanner && (
                          <span className="text-[11px] font-bold italic text-amber-500 tracking-wider">SUPPORTERS</span>
                        )}
                        <div className="flex items-center gap-1.5">
                          <span className="text-[8px] text-white/40">〈</span>
                          <div className="flex gap-1">
                            <div className="w-7 h-7 rounded-full border-2 border-amber-500 bg-slate-800 flex items-center justify-center relative">
                              <span className="text-[6px]">🥇</span>
                            </div>
                            <div className="w-7 h-7 rounded-full border-2 border-slate-300 bg-slate-800 flex items-center justify-center relative">
                              <span className="text-[6px]">🥈</span>
                            </div>
                            <div className="w-7 h-7 rounded-full border-2 border-amber-700 bg-slate-800 flex items-center justify-center relative">
                              <span className="text-[6px]">🥉</span>
                            </div>
                          </div>
                        </div>
                      </div>

                      {/* Identity Section */}
                      <div className="space-y-1.5 text-right">
                        <div className="flex justify-end">
                          {currentConfig.identityTitleImg ? (
                            <img src={currentConfig.identityTitleImg} className="h-5 object-contain" />
                          ) : (
                            <span className="text-[10px] font-bold text-white">وسم الهوية</span>
                          )}
                        </div>
                        <div className="flex justify-end gap-1.5">
                          <span className="bg-gradient-to-r from-pink-500 to-purple-500 text-[8px] font-bold px-2 py-0.5 rounded text-white shadow-sm border border-white/5">Voice Host</span>
                          <span className="bg-gradient-to-r from-amber-500 to-orange-500 text-[8px] font-bold px-2 py-0.5 rounded text-white shadow-sm border border-white/5">Agency Lead</span>
                        </div>
                      </div>

                      {/* Badges Section */}
                      <div className="space-y-1.5 text-right">
                        <div className="flex justify-end">
                          {currentConfig.badgesTitleImg ? (
                            <img src={currentConfig.badgesTitleImg} className="h-5 object-contain" />
                          ) : (
                            <span className="text-[10px] font-bold text-white">شارات</span>
                          )}
                        </div>
                        <p className="text-[8px] text-center text-white/40 py-1">
                          إذهب لإضاءة أول شارة لك!
                        </p>
                      </div>

                      {/* Achievements Section */}
                      <div className="space-y-2 text-right">
                        <div className="flex justify-end">
                          {currentConfig.achievementsTitleImg ? (
                            <img src={currentConfig.achievementsTitleImg} className="h-5 object-contain" />
                          ) : (
                            <span className="text-[10px] font-bold text-white">إنجازات</span>
                          )}
                        </div>
                        <div className="grid grid-cols-2 gap-2 flex-row-reverse">
                          {/* Right: Gift Wall Card */}
                          <div
                            className="h-28 rounded-xl border p-2 flex flex-col justify-between"
                            style={{
                              backgroundColor: currentConfig.giftWallCardBg ? 'transparent' : 'rgba(255,255,255,0.05)',
                              backgroundImage: currentConfig.giftWallCardBg ? `url(${currentConfig.giftWallCardBg})` : 'none',
                              backgroundSize: 'cover',
                              borderColor: currentConfig.giftWallCardBorder || 'rgba(255,255,255,0.1)',
                            }}
                          >
                            <div className="flex justify-between items-center">
                              <span className="text-[8px] text-white/40">〈</span>
                              <span className="text-[9px] font-bold text-white">جدار الهدايا</span>
                            </div>
                            <div className="flex justify-center py-2 text-pink-400 text-xl">
                              {currentConfig.giftWallIcon ? (
                                <img src={currentConfig.giftWallIcon} className="w-8 h-8 object-contain" />
                              ) : (
                                <span>🎁</span>
                              )}
                            </div>
                            <div></div>
                          </div>

                          {/* Left: Stacked cards */}
                          <div className="flex flex-col gap-2">
                            {/* Vehicle Card */}
                            <div
                              className="h-[52px] rounded-xl border p-2 flex items-center justify-between"
                              style={{
                                backgroundColor: currentConfig.vehicleCardBg ? 'transparent' : 'rgba(255,255,255,0.05)',
                                backgroundImage: currentConfig.vehicleCardBg ? `url(${currentConfig.vehicleCardBg})` : 'none',
                                backgroundSize: 'cover',
                                borderColor: currentConfig.vehicleCardBorder || 'rgba(255,255,255,0.1)',
                              }}
                            >
                              <span className="text-[8px] text-white/40">〈</span>
                              <div className="w-6 h-6 flex items-center justify-center">
                                {currentConfig.vehicleIcon ? (
                                  <img src={currentConfig.vehicleIcon} className="w-5 h-5 object-contain" />
                                ) : (
                                  <span className="text-base text-white/30">🏎️</span>
                                )}
                              </div>
                              <span className="text-[9px] font-bold text-white">مركبة</span>
                            </div>
                            {/* Frame Card */}
                            <div
                              className="h-[52px] rounded-xl border p-2 flex items-center justify-between"
                              style={{
                                backgroundColor: currentConfig.frameCardBg ? 'transparent' : 'rgba(255,255,255,0.05)',
                                backgroundImage: currentConfig.frameCardBg ? `url(${currentConfig.frameCardBg})` : 'none',
                                backgroundSize: 'cover',
                                borderColor: currentConfig.frameCardBorder || 'rgba(255,255,255,0.1)',
                              }}
                            >
                              <span className="text-[8px] text-white/40">〈</span>
                              <div className="w-6 h-6 flex items-center justify-center">
                                {currentConfig.frameIcon ? (
                                  <img src={currentConfig.frameIcon} className="w-5 h-5 object-contain" />
                                ) : (
                                  <span className="text-base text-white/30">👑</span>
                                )}
                              </div>
                              <span className="text-[9px] font-bold text-white">اطار</span>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                )}

                {/* Event Details Screen */}
                {activeTab === 'eventInfo' && (
                  <div className="flex-1 flex flex-col px-3 py-2 space-y-4">
                    <span className="font-bold text-xs" style={{ color: currentConfig.textColor }}>Event Details</span>
                    <div className="h-28 rounded-xl bg-white/5 border border-white/10 flex flex-col items-center justify-center">
                      <span className="text-2xl">🏆</span>
                      <span className="text-[10px] font-bold" style={{ color: currentConfig.textColor }}>Summer Cup 2026</span>
                    </div>
                    <div className="p-2 rounded-lg bg-white/5 flex justify-between text-[8px] flex-row-reverse">
                      <span>🥇 1st Prize</span>
                      <span className="font-bold" style={{ color: currentConfig.textColor }}>100k Coins</span>
                    </div>
                  </div>
                )}

                {/* System Notifications Screen */}
                {activeTab === 'notifications' && (
                  <div className="flex-1 flex flex-col px-3 py-2 space-y-4">
                    <span className="font-bold text-xs text-right" style={{ color: currentConfig.textColor }}>Notifications</span>
                    <div className="p-2.5 rounded-xl border border-white/5 flex items-start gap-2 flex-row-reverse text-right" style={{ backgroundColor: currentConfig.cardBgColor || 'rgba(255,255,255,0.05)' }}>
                      <div className="w-6 h-6 rounded-full bg-indigo-500/20 flex items-center justify-center text-[10px]">🔔</div>
                      <div className="flex-1 flex flex-col text-[8px] text-right">
                        <span className="font-bold" style={{ color: currentConfig.textColor }}>System Alert</span>
                        <span style={{ color: currentConfig.subTextColor }}>App visual designer successfully deployed.</span>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Right: Screen customizer form (7 cols) */}
          <div className="lg:col-span-7 bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-6">
            <div className="flex flex-col gap-1.5">
              <label className="text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'اختر الشاشة لتعديل مظهرها:' : 'Choose App Screen to Design:'}</label>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
                {screens.map(s => (
                  <button
                    key={s.id}
                    onClick={() => setActiveTab(s.id)}
                    className={`px-3 py-2 rounded-xl text-right text-xs font-semibold border transition-all ${
                      activeTab === s.id
                        ? 'bg-indigo-600/10 border-indigo-500 text-indigo-300'
                        : 'bg-white/5 border-transparent text-slate-400 hover:bg-white/10 hover:text-white'
                    }`}
                  >
                    {lang === 'ar' ? s.labelAr : s.labelEn}
                  </button>
                ))}
              </div>
            </div>

            <hr className="border-white/5" />

            <div className="space-y-4">
              <h3 className="text-white text-xs font-bold uppercase tracking-wider flex items-center gap-2">
                <span>🎨</span> {lang === 'ar' ? 'تخصيص المظهر المختار' : 'Customize Selected Layout'}
              </h3>

              {/* Background Image */}
              <div className="space-y-1.5">
                <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'صورة الخلفية (PNG/WebP/GIF)' : 'Background Image (PNG/WebP/GIF)'}</label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    placeholder="https://example.com/image.webp"
                    value={currentConfig.backgroundImage || ''}
                    onChange={e => updateField(activeTab, 'backgroundImage', e.target.value)}
                    className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                  />
                  <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-400 rounded-lg flex items-center justify-center">
                    <Upload className="w-4 h-4" />
                    <input
                      type="file"
                      accept="image/*"
                      className="hidden"
                      onChange={e => {
                        const file = e.target.files?.[0];
                        if (file) handleImageUpload(file, activeTab, 'backgroundImage');
                      }}
                    />
                  </label>
                </div>
                {currentConfig.backgroundImage && (
                  <div className="mt-2">
                    <img src={currentConfig.backgroundImage} alt="Background preview" className="w-full h-24 object-cover rounded-lg border border-white/5 bg-black/20" onError={e => { (e.target as HTMLImageElement).src = ''; }} />
                  </div>
                )}
              </div>

              {/* Colors grid */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="space-y-1.5">
                  <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'لون الخلفية الأساسي' : 'Background Color'}</label>
                  <div className="flex gap-2">
                    <input
                      type="color"
                      value={to6Hex(currentConfig.backgroundColor || '#ffffff')}
                      onChange={e => updateField(activeTab, 'backgroundColor', e.target.value)}
                      className="w-10 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg"
                    />
                    <input
                      type="text"
                      value={currentConfig.backgroundColor || ''}
                      onChange={e => updateField(activeTab, 'backgroundColor', e.target.value)}
                      className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                    />
                  </div>
                </div>

                <div className="space-y-1.5">
                  <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'لون النصوص الرئيسي' : 'Text Color'}</label>
                  <div className="flex gap-2">
                    <input
                      type="color"
                      value={to6Hex(currentConfig.textColor || '#000000')}
                      onChange={e => updateField(activeTab, 'textColor', e.target.value)}
                      className="w-10 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg"
                    />
                    <input
                      type="text"
                      value={currentConfig.textColor || ''}
                      onChange={e => updateField(activeTab, 'textColor', e.target.value)}
                      className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                    />
                  </div>
                </div>

                {'subTextColor' in currentConfig && (
                  <div className="space-y-1.5">
                    <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'لون النصوص الفرعية' : 'Sub-Text Color'}</label>
                    <div className="flex gap-2">
                      <input
                        type="color"
                        value={to6Hex(currentConfig.subTextColor || '#888888')}
                        onChange={e => updateField(activeTab, 'subTextColor', e.target.value)}
                        className="w-10 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg"
                      />
                      <input
                        type="text"
                        value={currentConfig.subTextColor || ''}
                        onChange={e => updateField(activeTab, 'subTextColor', e.target.value)}
                        className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                      />
                    </div>
                  </div>
                )}

                {'cardBgColor' in currentConfig && (
                  <div className="space-y-1.5">
                    <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'لون خلفية البطاقات والأقسام' : 'Card/Box Background'}</label>
                    <div className="flex gap-2">
                      <input
                        type="color"
                        value={to6Hex(currentConfig.cardBgColor || '#ffffff')}
                        onChange={e => updateField(activeTab, 'cardBgColor', e.target.value)}
                        className="w-10 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg"
                      />
                      <input
                        type="text"
                        value={currentConfig.cardBgColor || ''}
                        onChange={e => updateField(activeTab, 'cardBgColor', e.target.value)}
                        className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                      />
                    </div>
                  </div>
                )}

                {'buttonColor' in currentConfig && (
                  <div className="space-y-1.5">
                    <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'لون الأزرار الرئيسي' : 'Button/Badge Color'}</label>
                    <div className="flex gap-2">
                      <input
                        type="color"
                        value={to6Hex(currentConfig.buttonColor || '#ffe082')}
                        onChange={e => updateField(activeTab, 'buttonColor', e.target.value)}
                        className="w-10 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg"
                      />
                      <input
                        type="text"
                        value={currentConfig.buttonColor || ''}
                        onChange={e => updateField(activeTab, 'buttonColor', e.target.value)}
                        className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                      />
                    </div>
                  </div>
                )}

                {'bubbleSelfBgColor' in currentConfig && (
                  <div className="space-y-1.5">
                    <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'لون خلفية فقاعتي (المرسل)' : 'My Chat Bubble Color'}</label>
                    <div className="flex gap-2">
                      <input
                        type="color"
                        value={to6Hex(currentConfig.bubbleSelfBgColor || '#ffe082')}
                        onChange={e => updateField(activeTab, 'bubbleSelfBgColor', e.target.value)}
                        className="w-10 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg"
                      />
                      <input
                        type="text"
                        value={currentConfig.bubbleSelfBgColor || ''}
                        onChange={e => updateField(activeTab, 'bubbleSelfBgColor', e.target.value)}
                        className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                      />
                    </div>
                  </div>
                )}

                {'bubbleOtherBgColor' in currentConfig && (
                  <div className="space-y-1.5">
                    <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'لون خلفية فقاعة المستلم (الآخر)' : 'Other Chat Bubble Color'}</label>
                    <div className="flex gap-2">
                      <input
                        type="color"
                        value={to6Hex(currentConfig.bubbleOtherBgColor || '#ffffff')}
                        onChange={e => updateField(activeTab, 'bubbleOtherBgColor', e.target.value)}
                        className="w-10 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg"
                      />
                      <input
                        type="text"
                        value={currentConfig.bubbleOtherBgColor || ''}
                        onChange={e => updateField(activeTab, 'bubbleOtherBgColor', e.target.value)}
                        className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                      />
                    </div>
                  </div>
                )}
              </div>

              {/* Specific fields for User Profile Mini Profile & Full Profile Screen */}
              {(activeTab === 'userProfile' || activeTab === 'fullProfile') && (
                <div className="space-y-4 pt-4 border-t border-white/5 mt-4">
                  <h4 className="text-[11px] uppercase text-indigo-400 font-bold mb-2">
                    {activeTab === 'fullProfile'
                      ? (lang === 'ar' ? 'إعدادات شاشة البروفايل الكاملة المتقدمة' : 'Advanced Full Profile Settings')
                      : (lang === 'ar' ? 'إعدادات بطاقة الميني بروفايل المتقدمة' : 'Advanced Mini Profile Settings')}
                  </h4>
                  
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {/* Top coverImage for fullProfile only */}
                    {activeTab === 'fullProfile' && (
                      <div className="space-y-1.5 md:col-span-2">
                        <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'صورة الغلاف العلوية (Cover Image)' : 'Top Cover Image'}</label>
                        <div className="flex gap-2">
                          <input type="text" value={currentConfig.coverImage || ''} onChange={e => updateField(activeTab, 'coverImage', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                          <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                            <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'coverImage')} />
                          </label>
                        </div>
                      </div>
                    )}

                    {/* intimateCardBg */}
                    <div className="space-y-1.5">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'خلفية بطاقة حميمية' : 'Intimate Card BG'}</label>
                      <div className="flex gap-2">
                        <input type="text" value={currentConfig.intimateCardBg || ''} onChange={e => updateField(activeTab, 'intimateCardBg', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                        <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                          <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'intimateCardBg')} />
                        </label>
                      </div>
                    </div>

                    {/* familyCardBg */}
                    <div className="space-y-1.5">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'خلفية بطاقة العائلة' : 'Family Card BG'}</label>
                      <div className="flex gap-2">
                        <input type="text" value={currentConfig.familyCardBg || ''} onChange={e => updateField(activeTab, 'familyCardBg', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                        <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                          <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'familyCardBg')} />
                        </label>
                      </div>
                    </div>

                    {/* supportersBanner */}
                    <div className="space-y-1.5">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'شريط الداعمين' : 'Supporters Banner'}</label>
                      <div className="flex gap-2">
                        <input type="text" value={currentConfig.supportersBanner || ''} onChange={e => updateField(activeTab, 'supportersBanner', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                        <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                          <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'supportersBanner')} />
                        </label>
                      </div>
                    </div>

                    {/* supporterSlot */}
                    <div className="space-y-1.5">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'خلفية مكان الداعم' : 'Supporter Slot BG'}</label>
                      <div className="flex gap-2">
                        <input type="text" value={currentConfig.supporterSlot || ''} onChange={e => updateField(activeTab, 'supporterSlot', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                        <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                          <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'supporterSlot')} />
                        </label>
                      </div>
                    </div>

                    {/* Crowns */}
                    <div className="space-y-1.5">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'تاج الداعم الذهبي' : 'Gold Crown'}</label>
                      <div className="flex gap-2">
                        <input type="text" value={currentConfig.goldCrown || ''} onChange={e => updateField(activeTab, 'goldCrown', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                        <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                          <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'goldCrown')} />
                        </label>
                      </div>
                    </div>
                    <div className="space-y-1.5">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'تاج الداعم الفضي' : 'Silver Crown'}</label>
                      <div className="flex gap-2">
                        <input type="text" value={currentConfig.silverCrown || ''} onChange={e => updateField(activeTab, 'silverCrown', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                        <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                          <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'silverCrown')} />
                        </label>
                      </div>
                    </div>
                    <div className="space-y-1.5">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'تاج الداعم البرونزي' : 'Bronze Crown'}</label>
                      <div className="flex gap-2">
                        <input type="text" value={currentConfig.bronzeCrown || ''} onChange={e => updateField(activeTab, 'bronzeCrown', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                        <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                          <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'bronzeCrown')} />
                        </label>
                      </div>
                    </div>
                    <div className="space-y-1.5">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'عنوان الهوية' : 'Identity Title'}</label>
                      <div className="flex gap-2">
                        <input type="text" value={currentConfig.identityTitleImg || ''} onChange={e => updateField(activeTab, 'identityTitleImg', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                        <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                          <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'identityTitleImg')} />
                        </label>
                      </div>
                    </div>
                    <div className="space-y-1.5">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'عنوان الشارات' : 'Badges Title'}</label>
                      <div className="flex gap-2">
                        <input type="text" value={currentConfig.badgesTitleImg || ''} onChange={e => updateField(activeTab, 'badgesTitleImg', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                        <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                          <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'badgesTitleImg')} />
                        </label>
                      </div>
                    </div>
                    <div className="space-y-1.5">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'عنوان الإنجازات' : 'Achievements Title'}</label>
                      <div className="flex gap-2">
                        <input type="text" value={currentConfig.achievementsTitleImg || ''} onChange={e => updateField(activeTab, 'achievementsTitleImg', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                        <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                          <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'achievementsTitleImg')} />
                        </label>
                      </div>
                    </div>

                    {/* Achievements Cards Customization */}
                    <div className="md:col-span-2 pt-6 border-t border-white/10 space-y-6 w-full">
                      <div className="flex flex-wrap items-center justify-between gap-2 bg-gradient-to-r from-amber-500/10 via-pink-500/10 to-indigo-500/10 border border-amber-500/20 p-3 rounded-2xl">
                        <div className="flex items-center gap-2">
                          <span className="text-xl">🏆</span>
                          <div>
                            <h4 className="text-xs font-bold text-amber-300">
                              {lang === 'ar' ? 'تخصيص بطاقات الإنجازات (جدار الهدايا، المركبة، الإطار)' : 'Achievements Cards Customization'}
                            </h4>
                            <p className="text-[10px] text-slate-400">
                              {lang === 'ar' ? 'تعديل وتعيين خلفيات وأيقونات وألوان إطارات بطاقات الإنجازات' : 'Configure backgrounds, icons, and borders for achievements'}
                            </p>
                          </div>
                        </div>
                        <span className="text-[10px] bg-amber-500/20 text-amber-300 border border-amber-500/30 px-2.5 py-1 rounded-full font-bold">
                          {lang === 'ar' ? '📁 رفع مباشر من الجهاز' : '📁 Direct Device Upload'}
                        </span>
                      </div>

                      {/* 1. Gift Wall Card (جدار الهدايا) */}
                      <div className="bg-[#141417] rounded-2xl border border-pink-500/30 p-5 space-y-4 shadow-lg">
                        <div className="flex items-center justify-between border-b border-white/5 pb-3">
                          <span className="text-sm font-bold text-pink-300 flex items-center gap-2">
                            <span className="text-lg">🎁</span>
                            <span>{lang === 'ar' ? 'بطاقة جدار الهدايا (Gift Wall Card)' : 'Gift Wall Card'}</span>
                          </span>
                          <span className="text-[10px] bg-pink-500/10 text-pink-400 border border-pink-500/20 px-2 py-0.5 rounded-full font-medium">
                            {lang === 'ar' ? 'بطاقة رأسية (140px)' : 'Vertical Card'}
                          </span>
                        </div>

                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                          {/* Background Image */}
                          <div className="bg-white/[0.02] p-3 rounded-xl border border-white/5 space-y-2">
                            <label className="block text-[10px] uppercase text-slate-300 font-bold flex items-center justify-between">
                              <span>{lang === 'ar' ? 'صورة خلفية جدار الهدايا' : 'Background Image'}</span>
                              {currentConfig.giftWallCardBg && <span className="text-[9px] text-emerald-400 font-normal">تم التعيين ✓</span>}
                            </label>
                            <div className="flex items-center gap-3">
                              {currentConfig.giftWallCardBg ? (
                                <div className="w-14 h-14 rounded-xl border border-white/20 overflow-hidden bg-black/50 shrink-0 relative group shadow-md">
                                  <img src={currentConfig.giftWallCardBg} className="w-full h-full object-cover" />
                                  <button onClick={() => updateField(activeTab, 'giftWallCardBg', '')} title="حذف" className="absolute inset-0 bg-black/80 opacity-0 group-hover:opacity-100 flex items-center justify-center text-rose-400 font-bold text-sm transition-opacity">✕</button>
                                </div>
                              ) : (
                                <div className="w-14 h-14 rounded-xl border-2 border-dashed border-white/10 flex flex-col items-center justify-center text-slate-500 shrink-0 text-[10px] gap-0.5 bg-black/20">
                                  <Upload className="w-4 h-4 opacity-40" />
                                  <span>خلفية</span>
                                </div>
                              )}
                              <div className="flex-1 space-y-1.5 min-w-0">
                                <label className="cursor-pointer w-full py-2 px-3 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-300 border border-indigo-500/30 rounded-xl flex items-center justify-center gap-2 text-xs font-bold transition-all shadow-sm">
                                  <Upload className="w-4 h-4" />
                                  <span>{lang === 'ar' ? 'اختيار من الجهاز' : 'Pick from Device'}</span>
                                  <input type="file" accept="image/*" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'giftWallCardBg')} />
                                </label>
                                <input type="text" placeholder={lang === 'ar' ? 'أو ألصق رابط الصورة هنا...' : 'Or paste URL here...'} value={currentConfig.giftWallCardBg || ''} onChange={e => updateField(activeTab, 'giftWallCardBg', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1 px-2.5 text-[11px] text-white focus:border-indigo-500 transition-colors" />
                              </div>
                            </div>
                          </div>

                          {/* Icon Image */}
                          <div className="bg-white/[0.02] p-3 rounded-xl border border-white/5 space-y-2">
                            <label className="block text-[10px] uppercase text-slate-300 font-bold flex items-center justify-between">
                              <span>{lang === 'ar' ? 'أيقونة جدار الهدايا' : 'Gift Wall Icon'}</span>
                              {currentConfig.giftWallIcon && <span className="text-[9px] text-emerald-400 font-normal">تم التعيين ✓</span>}
                            </label>
                            <div className="flex items-center gap-3">
                              {currentConfig.giftWallIcon ? (
                                <div className="w-14 h-14 rounded-xl border border-white/20 overflow-hidden bg-black/50 shrink-0 relative group flex items-center justify-center p-1.5 shadow-md">
                                  <img src={currentConfig.giftWallIcon} className="max-w-full max-h-full object-contain" />
                                  <button onClick={() => updateField(activeTab, 'giftWallIcon', '')} title="حذف" className="absolute inset-0 bg-black/80 opacity-0 group-hover:opacity-100 flex items-center justify-center text-rose-400 font-bold text-sm transition-opacity">✕</button>
                                </div>
                              ) : (
                                <div className="w-14 h-14 rounded-xl border-2 border-dashed border-white/10 flex items-center justify-center text-2xl shrink-0 bg-black/20">🎁</div>
                              )}
                              <div className="flex-1 space-y-1.5 min-w-0">
                                <label className="cursor-pointer w-full py-2 px-3 bg-pink-600/20 hover:bg-pink-600/30 text-pink-300 border border-pink-500/30 rounded-xl flex items-center justify-center gap-2 text-xs font-bold transition-all shadow-sm">
                                  <Upload className="w-4 h-4" />
                                  <span>{lang === 'ar' ? 'اختيار من الجهاز' : 'Pick from Device'}</span>
                                  <input type="file" accept="image/*" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'giftWallIcon')} />
                                </label>
                                <input type="text" placeholder={lang === 'ar' ? 'أو ألصق رابط الأيقونة هنا...' : 'Or paste URL here...'} value={currentConfig.giftWallIcon || ''} onChange={e => updateField(activeTab, 'giftWallIcon', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1 px-2.5 text-[11px] text-white focus:border-pink-500 transition-colors" />
                              </div>
                            </div>
                          </div>
                        </div>

                        {/* Border Color */}
                        <div className="flex items-center justify-between bg-white/[0.02] p-3 rounded-xl border border-white/5">
                          <div>
                            <label className="text-xs text-slate-300 font-bold block">{lang === 'ar' ? 'لون إطار جدار الهدايا' : 'Card Border Color'}</label>
                            <span className="text-[10px] text-slate-500">اللون الافتراضي: #382F24</span>
                          </div>
                          <div className="flex items-center gap-2">
                            <input type="color" value={to6Hex(currentConfig.giftWallCardBorder || '#382F24')} onChange={e => updateField(activeTab, 'giftWallCardBorder', e.target.value)} className="w-9 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg shrink-0 cursor-pointer" />
                            <input type="text" value={currentConfig.giftWallCardBorder || '#382F24'} onChange={e => updateField(activeTab, 'giftWallCardBorder', e.target.value)} className="w-24 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2.5 text-xs text-white font-mono text-center" />
                          </div>
                        </div>
                      </div>

                      {/* 2. Vehicle Card (بطاقة المركبة) */}
                      <div className="bg-[#141417] rounded-2xl border border-amber-500/30 p-5 space-y-4 shadow-lg">
                        <div className="flex items-center justify-between border-b border-white/5 pb-3">
                          <span className="text-sm font-bold text-amber-300 flex items-center gap-2">
                            <span className="text-lg">🏎️</span>
                            <span>{lang === 'ar' ? 'بطاقة المركبة (Vehicle Card)' : 'Vehicle Card'}</span>
                          </span>
                          <span className="text-[10px] bg-amber-500/10 text-amber-400 border border-amber-500/20 px-2 py-0.5 rounded-full font-medium">
                            {lang === 'ar' ? 'بنر عريض (64px)' : 'Horizontal Banner'}
                          </span>
                        </div>

                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                          {/* Background Image */}
                          <div className="bg-white/[0.02] p-3 rounded-xl border border-white/5 space-y-2">
                            <label className="block text-[10px] uppercase text-slate-300 font-bold flex items-center justify-between">
                              <span>{lang === 'ar' ? 'صورة خلفية بطاقة المركبة' : 'Background Image'}</span>
                              {currentConfig.vehicleCardBg && <span className="text-[9px] text-emerald-400 font-normal">تم التعيين ✓</span>}
                            </label>
                            <div className="flex items-center gap-3">
                              {currentConfig.vehicleCardBg ? (
                                <div className="w-14 h-14 rounded-xl border border-white/20 overflow-hidden bg-black/50 shrink-0 relative group shadow-md">
                                  <img src={currentConfig.vehicleCardBg} className="w-full h-full object-cover" />
                                  <button onClick={() => updateField(activeTab, 'vehicleCardBg', '')} title="حذف" className="absolute inset-0 bg-black/80 opacity-0 group-hover:opacity-100 flex items-center justify-center text-rose-400 font-bold text-sm transition-opacity">✕</button>
                                </div>
                              ) : (
                                <div className="w-14 h-14 rounded-xl border-2 border-dashed border-white/10 flex flex-col items-center justify-center text-slate-500 shrink-0 text-[10px] gap-0.5 bg-black/20">
                                  <Upload className="w-4 h-4 opacity-40" />
                                  <span>خلفية</span>
                                </div>
                              )}
                              <div className="flex-1 space-y-1.5 min-w-0">
                                <label className="cursor-pointer w-full py-2 px-3 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-300 border border-indigo-500/30 rounded-xl flex items-center justify-center gap-2 text-xs font-bold transition-all shadow-sm">
                                  <Upload className="w-4 h-4" />
                                  <span>{lang === 'ar' ? 'اختيار من الجهاز' : 'Pick from Device'}</span>
                                  <input type="file" accept="image/*" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'vehicleCardBg')} />
                                </label>
                                <input type="text" placeholder={lang === 'ar' ? 'أو ألصق رابط الصورة هنا...' : 'Or paste URL here...'} value={currentConfig.vehicleCardBg || ''} onChange={e => updateField(activeTab, 'vehicleCardBg', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1 px-2.5 text-[11px] text-white focus:border-indigo-500 transition-colors" />
                              </div>
                            </div>
                          </div>

                          {/* Icon Image */}
                          <div className="bg-white/[0.02] p-3 rounded-xl border border-white/5 space-y-2">
                            <label className="block text-[10px] uppercase text-slate-300 font-bold flex items-center justify-between">
                              <span>{lang === 'ar' ? 'أيقونة المركبة' : 'Vehicle Icon'}</span>
                              {currentConfig.vehicleIcon && <span className="text-[9px] text-emerald-400 font-normal">تم التعيين ✓</span>}
                            </label>
                            <div className="flex items-center gap-3">
                              {currentConfig.vehicleIcon ? (
                                <div className="w-14 h-14 rounded-xl border border-white/20 overflow-hidden bg-black/50 shrink-0 relative group flex items-center justify-center p-1.5 shadow-md">
                                  <img src={currentConfig.vehicleIcon} className="max-w-full max-h-full object-contain" />
                                  <button onClick={() => updateField(activeTab, 'vehicleIcon', '')} title="حذف" className="absolute inset-0 bg-black/80 opacity-0 group-hover:opacity-100 flex items-center justify-center text-rose-400 font-bold text-sm transition-opacity">✕</button>
                                </div>
                              ) : (
                                <div className="w-14 h-14 rounded-xl border-2 border-dashed border-white/10 flex items-center justify-center text-2xl shrink-0 bg-black/20">🏎️</div>
                              )}
                              <div className="flex-1 space-y-1.5 min-w-0">
                                <label className="cursor-pointer w-full py-2 px-3 bg-amber-600/20 hover:bg-amber-600/30 text-amber-300 border border-amber-500/30 rounded-xl flex items-center justify-center gap-2 text-xs font-bold transition-all shadow-sm">
                                  <Upload className="w-4 h-4" />
                                  <span>{lang === 'ar' ? 'اختيار من الجهاز' : 'Pick from Device'}</span>
                                  <input type="file" accept="image/*" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'vehicleIcon')} />
                                </label>
                                <input type="text" placeholder={lang === 'ar' ? 'أو ألصق رابط الأيقونة هنا...' : 'Or paste URL here...'} value={currentConfig.vehicleIcon || ''} onChange={e => updateField(activeTab, 'vehicleIcon', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1 px-2.5 text-[11px] text-white focus:border-amber-500 transition-colors" />
                              </div>
                            </div>
                          </div>
                        </div>

                        {/* Border Color */}
                        <div className="flex items-center justify-between bg-white/[0.02] p-3 rounded-xl border border-white/5">
                          <div>
                            <label className="text-xs text-slate-300 font-bold block">{lang === 'ar' ? 'لون إطار بطاقة المركبة' : 'Card Border Color'}</label>
                            <span className="text-[10px] text-slate-500">اللون الافتراضي: #382F24</span>
                          </div>
                          <div className="flex items-center gap-2">
                            <input type="color" value={to6Hex(currentConfig.vehicleCardBorder || '#382F24')} onChange={e => updateField(activeTab, 'vehicleCardBorder', e.target.value)} className="w-9 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg shrink-0 cursor-pointer" />
                            <input type="text" value={currentConfig.vehicleCardBorder || '#382F24'} onChange={e => updateField(activeTab, 'vehicleCardBorder', e.target.value)} className="w-24 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2.5 text-xs text-white font-mono text-center" />
                          </div>
                        </div>
                      </div>

                      {/* 3. Frame Card (بطاقة الإطار) */}
                      <div className="bg-[#141417] rounded-2xl border border-purple-500/30 p-5 space-y-4 shadow-lg">
                        <div className="flex items-center justify-between border-b border-white/5 pb-3">
                          <span className="text-sm font-bold text-purple-300 flex items-center gap-2">
                            <span className="text-lg">👑</span>
                            <span>{lang === 'ar' ? 'بطاقة الإطار (Avatar Frame Card)' : 'Frame Card'}</span>
                          </span>
                          <span className="text-[10px] bg-purple-500/10 text-purple-400 border border-purple-500/20 px-2 py-0.5 rounded-full font-medium">
                            {lang === 'ar' ? 'بنر عريض (64px)' : 'Horizontal Banner'}
                          </span>
                        </div>

                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                          {/* Background Image */}
                          <div className="bg-white/[0.02] p-3 rounded-xl border border-white/5 space-y-2">
                            <label className="block text-[10px] uppercase text-slate-300 font-bold flex items-center justify-between">
                              <span>{lang === 'ar' ? 'صورة خلفية بطاقة الإطار' : 'Background Image'}</span>
                              {currentConfig.frameCardBg && <span className="text-[9px] text-emerald-400 font-normal">تم التعيين ✓</span>}
                            </label>
                            <div className="flex items-center gap-3">
                              {currentConfig.frameCardBg ? (
                                <div className="w-14 h-14 rounded-xl border border-white/20 overflow-hidden bg-black/50 shrink-0 relative group shadow-md">
                                  <img src={currentConfig.frameCardBg} className="w-full h-full object-cover" />
                                  <button onClick={() => updateField(activeTab, 'frameCardBg', '')} title="حذف" className="absolute inset-0 bg-black/80 opacity-0 group-hover:opacity-100 flex items-center justify-center text-rose-400 font-bold text-sm transition-opacity">✕</button>
                                </div>
                              ) : (
                                <div className="w-14 h-14 rounded-xl border-2 border-dashed border-white/10 flex flex-col items-center justify-center text-slate-500 shrink-0 text-[10px] gap-0.5 bg-black/20">
                                  <Upload className="w-4 h-4 opacity-40" />
                                  <span>خلفية</span>
                                </div>
                              )}
                              <div className="flex-1 space-y-1.5 min-w-0">
                                <label className="cursor-pointer w-full py-2 px-3 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-300 border border-indigo-500/30 rounded-xl flex items-center justify-center gap-2 text-xs font-bold transition-all shadow-sm">
                                  <Upload className="w-4 h-4" />
                                  <span>{lang === 'ar' ? 'اختيار من الجهاز' : 'Pick from Device'}</span>
                                  <input type="file" accept="image/*" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'frameCardBg')} />
                                </label>
                                <input type="text" placeholder={lang === 'ar' ? 'أو ألصق رابط الصورة هنا...' : 'Or paste URL here...'} value={currentConfig.frameCardBg || ''} onChange={e => updateField(activeTab, 'frameCardBg', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1 px-2.5 text-[11px] text-white focus:border-indigo-500 transition-colors" />
                              </div>
                            </div>
                          </div>

                          {/* Icon Image */}
                          <div className="bg-white/[0.02] p-3 rounded-xl border border-white/5 space-y-2">
                            <label className="block text-[10px] uppercase text-slate-300 font-bold flex items-center justify-between">
                              <span>{lang === 'ar' ? 'أيقونة الإطار' : 'Frame Icon'}</span>
                              {currentConfig.frameIcon && <span className="text-[9px] text-emerald-400 font-normal">تم التعيين ✓</span>}
                            </label>
                            <div className="flex items-center gap-3">
                              {currentConfig.frameIcon ? (
                                <div className="w-14 h-14 rounded-xl border border-white/20 overflow-hidden bg-black/50 shrink-0 relative group flex items-center justify-center p-1.5 shadow-md">
                                  <img src={currentConfig.frameIcon} className="max-w-full max-h-full object-contain" />
                                  <button onClick={() => updateField(activeTab, 'frameIcon', '')} title="حذف" className="absolute inset-0 bg-black/80 opacity-0 group-hover:opacity-100 flex items-center justify-center text-rose-400 font-bold text-sm transition-opacity">✕</button>
                                </div>
                              ) : (
                                <div className="w-14 h-14 rounded-xl border-2 border-dashed border-white/10 flex items-center justify-center text-2xl shrink-0 bg-black/20">👑</div>
                              )}
                              <div className="flex-1 space-y-1.5 min-w-0">
                                <label className="cursor-pointer w-full py-2 px-3 bg-purple-600/20 hover:bg-purple-600/30 text-purple-300 border border-purple-500/30 rounded-xl flex items-center justify-center gap-2 text-xs font-bold transition-all shadow-sm">
                                  <Upload className="w-4 h-4" />
                                  <span>{lang === 'ar' ? 'اختيار من الجهاز' : 'Pick from Device'}</span>
                                  <input type="file" accept="image/*" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'frameIcon')} />
                                </label>
                                <input type="text" placeholder={lang === 'ar' ? 'أو ألصق رابط الأيقونة هنا...' : 'Or paste URL here...'} value={currentConfig.frameIcon || ''} onChange={e => updateField(activeTab, 'frameIcon', e.target.value)} className="w-full bg-[#161618] border border-white/10 rounded-lg py-1 px-2.5 text-[11px] text-white focus:border-purple-500 transition-colors" />
                              </div>
                            </div>
                          </div>
                        </div>

                        {/* Border Color */}
                        <div className="flex items-center justify-between bg-white/[0.02] p-3 rounded-xl border border-white/5">
                          <div>
                            <label className="text-xs text-slate-300 font-bold block">{lang === 'ar' ? 'لون إطار بطاقة الإطار' : 'Card Border Color'}</label>
                            <span className="text-[10px] text-slate-500">اللون الافتراضي: #382F24</span>
                          </div>
                          <div className="flex items-center gap-2">
                            <input type="color" value={to6Hex(currentConfig.frameCardBorder || '#382F24')} onChange={e => updateField(activeTab, 'frameCardBorder', e.target.value)} className="w-9 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg shrink-0 cursor-pointer" />
                            <input type="text" value={currentConfig.frameCardBorder || '#382F24'} onChange={e => updateField(activeTab, 'frameCardBorder', e.target.value)} className="w-24 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2.5 text-xs text-white font-mono text-center" />
                          </div>
                        </div>
                      </div>
                    </div>

                    {activeTab === 'userProfile' && (
                      <>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'صورة إطار وزخرفة البطاقة المصغرة' : 'Card Frame / Border Image'}</label>
                          <div className="flex gap-2">
                            <input type="text" value={currentConfig.cardFrameImg || ''} onChange={e => updateField(activeTab, 'cardFrameImg', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                            <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                              <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'cardFrameImg')} />
                            </label>
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'لون إطار البطاقة المصغرة' : 'Card Border Color'}</label>
                          <div className="flex gap-2">
                            <input type="color" value={to6Hex(currentConfig.borderColor || '#382F24')} onChange={e => updateField(activeTab, 'borderColor', e.target.value)} className="w-10 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg shrink-0" />
                            <input type="text" value={currentConfig.borderColor || ''} onChange={e => updateField(activeTab, 'borderColor', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'صورة شارة المضيف' : 'Host Badge Image'}</label>
                          <div className="flex gap-2">
                            <input type="text" value={currentConfig.hostBadgeImg || ''} onChange={e => updateField(activeTab, 'hostBadgeImg', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                            <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                              <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'hostBadgeImg')} />
                            </label>
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'لون شارة المضيف (افتراضي)' : 'Host Badge Color'}</label>
                          <div className="flex gap-2">
                            <input type="color" value={to6Hex(currentConfig.hostBadgeBg || '#1E5BB5')} onChange={e => updateField(activeTab, 'hostBadgeBg', e.target.value)} className="w-10 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg shrink-0" />
                            <input type="text" value={currentConfig.hostBadgeBg || ''} onChange={e => updateField(activeTab, 'hostBadgeBg', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'خلفية شريط استلام الهدايا (صورة)' : 'Gift Bar Background Image'}</label>
                          <div className="flex gap-2">
                            <input type="text" value={currentConfig.giftBarBg || ''} onChange={e => updateField(activeTab, 'giftBarBg', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                            <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                              <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'giftBarBg')} />
                            </label>
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'صورة إطار شريط الهدايا' : 'Gift Bar Frame Image'}</label>
                          <div className="flex gap-2">
                            <input type="text" value={currentConfig.giftBarBorderImg || ''} onChange={e => updateField(activeTab, 'giftBarBorderImg', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                            <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                              <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'giftBarBorderImg')} />
                            </label>
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'لون إطار شريط الهدايا' : 'Gift Bar Border Color'}</label>
                          <div className="flex gap-2">
                            <input type="color" value={to6Hex(currentConfig.giftBarBorder || '#5E4321')} onChange={e => updateField(activeTab, 'giftBarBorder', e.target.value)} className="w-10 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg shrink-0" />
                            <input type="text" value={currentConfig.giftBarBorder || ''} onChange={e => updateField(activeTab, 'giftBarBorder', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'أيقونة زر الهدية (الذهبي)' : 'Gift Button Icon'}</label>
                          <div className="flex gap-2">
                            <input type="text" value={currentConfig.profileGiftIcon || ''} onChange={e => updateField(activeTab, 'profileGiftIcon', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                            <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                              <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'profileGiftIcon')} />
                            </label>
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'أيقونة المحادثة والرسائل' : 'Chat & Messages Icon'}</label>
                          <div className="flex gap-2">
                            <input type="text" value={currentConfig.profileChatIcon || ''} onChange={e => updateField(activeTab, 'profileChatIcon', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                            <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                              <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'profileChatIcon')} />
                            </label>
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'أيقونة الإشارة / المنشن (@)' : 'Mention Icon'}</label>
                          <div className="flex gap-2">
                            <input type="text" value={currentConfig.profileMentionIcon || ''} onChange={e => updateField(activeTab, 'profileMentionIcon', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                            <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                              <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'profileMentionIcon')} />
                            </label>
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'أيقونة المتابعة' : 'Follow Icon'}</label>
                          <div className="flex gap-2">
                            <input type="text" value={currentConfig.profileFollowIcon || ''} onChange={e => updateField(activeTab, 'profileFollowIcon', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                            <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                              <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'profileFollowIcon')} />
                            </label>
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'أيقونة الخيارات (•••)' : 'More Options Icon'}</label>
                          <div className="flex gap-2">
                            <input type="text" value={currentConfig.profileMoreIcon || ''} onChange={e => updateField(activeTab, 'profileMoreIcon', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                            <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                              <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'profileMoreIcon')} />
                            </label>
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'أيقونة الإبلاغ' : 'Report Icon'}</label>
                          <div className="flex gap-2">
                            <input type="text" value={currentConfig.profileReportIcon || ''} onChange={e => updateField(activeTab, 'profileReportIcon', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                            <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                              <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'profileReportIcon')} />
                            </label>
                          </div>
                        </div>
                      </>
                    )}
                    <div className="space-y-1.5">
                      <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'أيقونة التعديل' : 'Edit Icon'}</label>
                      <div className="flex gap-2">
                        <input type="text" value={currentConfig.profileEditIcon || ''} onChange={e => updateField(activeTab, 'profileEditIcon', e.target.value)} className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white" />
                        <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded-lg flex items-center justify-center">
                          <Upload className="w-4 h-4" /><input type="file" className="hidden" onChange={e => e.target.files?.[0] && handleImageUpload(e.target.files[0], activeTab, 'profileEditIcon')} />
                        </label>
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Colors & Gradients & Chat Bubbles tab view */}
      {activeDesignerTab === 'colors' && (
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-8">
          {/* General Colors */}
          <div className="space-y-4">
            <h3 className="text-white text-sm font-semibold flex items-center gap-2">
              <Palette className="w-4 h-4 text-indigo-400" />
              {lang === 'ar' ? 'ألوان التطبيق العامة' : 'General App Colors'}
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {Object.entries(globalColors).map(([field, value]) => {
                const label = field === 'primaryBg' ? (lang === 'ar' ? 'خلفية التطبيق العامة' : 'Global Background') :
                              field === 'textPrimary' ? (lang === 'ar' ? 'النصوص الرئيسية' : 'Primary Text') :
                              field === 'textSecondary' ? (lang === 'ar' ? 'النصوص الفرعية' : 'Secondary Text') :
                              field === 'goldColor' ? (lang === 'ar' ? 'لون التمييز / الذهبي' : 'Accent / Gold Color') :
                              field === 'buttonColor' ? (lang === 'ar' ? 'لون الأزرار العامة' : 'Global Button Color') :
                              field === 'buttonTextColor' ? (lang === 'ar' ? 'لون نصوص الأزرار' : 'Button Text Color') :
                              field === 'headerColor' ? (lang === 'ar' ? 'خلفية شريط العنوان' : 'Header Bar Background') :
                              field === 'tabBarColor' ? (lang === 'ar' ? 'خلفية شريط التبويبات العلوي' : 'Top Tab Bar Background') :
                              field === 'bottomNavGradientStart' ? (lang === 'ar' ? 'بداية تدرج الشريط السفلي' : 'Bottom Nav Gradient Start') :
                              field === 'bottomNavGradientEnd' ? (lang === 'ar' ? 'نهاية تدرج الشريط السفلي' : 'Bottom Nav Gradient End') :
                              field === 'bottomNavActiveTextColor' ? (lang === 'ar' ? 'لون التبويب السفلي النشط' : 'Bottom Nav Active Text') :
                              field === 'bottomNavInactiveTextColor' ? (lang === 'ar' ? 'لون التبويب السفلي غير النشط' : 'Bottom Nav Inactive Text') :
                              field === 'vipCardBgColor' ? (lang === 'ar' ? 'لون خلفية بطاقة VIP' : 'VIP Card Background') :
                              field === 'vipCardBorderColor' ? (lang === 'ar' ? 'لون إطار بطاقة VIP' : 'VIP Card Border') :
                              field === 'splashNameColor' ? (lang === 'ar' ? 'لون نص الشاشة الترحيبية' : 'Splash Text Color') : field;

                return (
                  <div key={field} className="space-y-1.5">
                    <label className="block text-[10px] uppercase text-slate-400 font-bold">{label}</label>
                    <div className="flex gap-2">
                      <input
                        type="color"
                        value={to6Hex(value)}
                        onChange={e => setGlobalColors(p => ({ ...p, [field]: e.target.value }))}
                        className="w-10 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg shrink-0"
                      />
                      <input
                        type="text"
                        value={value}
                        onChange={e => setGlobalColors(p => ({ ...p, [field]: e.target.value }))}
                        className="w-24 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                      />
                      <input
                        type="text"
                        placeholder={lang === 'ar' ? 'أو رابط صورة...' : 'Or image URL...'}
                        value={globalImages[field] || ''}
                        onChange={e => setGlobalImages(p => ({ ...p, [field]: e.target.value }))}
                        className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                      />
                      <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-400 rounded-lg flex items-center justify-center shrink-0">
                        <Upload className="w-4 h-4" />
                        <input
                          type="file"
                          accept="image/*"
                          className="hidden"
                          onChange={async e => {
                            const file = e.target.files?.[0];
                            if (file) {
                              try {
                                const url = await uploadAppAsset(file, `globals/${field}`);
                                setGlobalImages(p => ({ ...p, [field]: url }));
                              } catch (err: any) {
                                alert('Upload failed: ' + err.message);
                              }
                            }
                          }}
                        />
                      </label>
                    </div>
                    {globalImages[field] && (
                      <div className="mt-2">
                        <img src={globalImages[field]} alt="Preview" className="w-full h-12 object-cover rounded-lg border border-white/5 bg-black/20" onError={e => { (e.target as HTMLImageElement).src = ''; }} />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          <hr className="border-white/5" />

          {/* Room Gradients */}
          <div className="space-y-4">
            <h3 className="text-white text-sm font-semibold flex items-center gap-2">
              <Sparkles className="w-4 h-4 text-purple-400" />
              {lang === 'ar' ? 'ألوان تدرجات شاشات الغرف' : 'Room Category Gradients'}
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {Object.entries(roomGradients).map(([key, rawVal]) => {
                const val = Array.isArray(rawVal) && rawVal.length >= 2 ? rawVal : (defaultRoomGradients[key] || ['#ffffff', '#000000']);
                const color0 = val?.[0] || '#ffffff';
                const color1 = val?.[1] || '#000000';
                const label = key === 'themeFriend' ? (lang === 'ar' ? 'تدرج شاشة الصداقة (Friend)' : 'Friend Theme') :
                              key === 'themeChat' ? (lang === 'ar' ? 'تدرج شاشة الشات (Chat)' : 'Chat Theme') :
                              key === 'themeMusic' ? (lang === 'ar' ? 'تدرج شاشة الموسيقى (Music)' : 'Music Theme') :
                              key === 'themeGame' ? (lang === 'ar' ? 'تدرج شاشة الألعاب (Game)' : 'Game Theme') :
                              key === 'themeParty' ? (lang === 'ar' ? 'تدرج شاشة الحفلات (Party)' : 'Party Theme') :
                              key === 'themeHobby' ? (lang === 'ar' ? 'تدرج شاشة الهوايات (Hobby)' : 'Hobby Theme') : key;
                return (
                  <div key={key} className="space-y-1.5">
                    <label className="block text-[10px] uppercase text-slate-400 font-bold">{label}</label>
                    <div className="flex gap-2">
                      <div className="flex items-center gap-1">
                        <input
                          type="color"
                          value={to6Hex(color0)}
                          onChange={e => {
                            const copy = { ...roomGradients };
                            copy[key] = [e.target.value, color1];
                            setRoomGradients(copy);
                          }}
                          className="w-8 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg"
                        />
                        <input
                          type="color"
                          value={to6Hex(color1)}
                          onChange={e => {
                            const copy = { ...roomGradients };
                            copy[key] = [color0, e.target.value];
                            setRoomGradients(copy);
                          }}
                          className="w-8 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg"
                        />
                      </div>
                      <div className="flex-1 flex gap-1 items-center">
                        <input
                          type="text"
                          value={color0}
                          onChange={e => {
                            const copy = { ...roomGradients };
                            copy[key] = [e.target.value, color1];
                            setRoomGradients(copy);
                          }}
                          className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-[10px] text-white font-mono"
                        />
                        <span className="text-slate-600">→</span>
                        <input
                          type="text"
                          value={color1}
                          onChange={e => {
                            const copy = { ...roomGradients };
                            copy[key] = [color0, e.target.value];
                            setRoomGradients(copy);
                          }}
                          className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-[10px] text-white font-mono"
                        />
                      </div>
                    </div>
                    {/* Add Image Uploader below the gradient inputs */}
                    <div className="flex gap-2 mt-2">
                      <input
                        type="text"
                        placeholder={lang === 'ar' ? 'أو رابط صورة كخلفية...' : 'Or bg image URL...'}
                        value={roomBgImages[key] || ''}
                        onChange={e => setRoomBgImages(p => ({ ...p, [key]: e.target.value }))}
                        className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                      />
                      <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-400 rounded-lg flex items-center justify-center shrink-0">
                        <Upload className="w-4 h-4" />
                        <input
                          type="file"
                          accept="image/*"
                          className="hidden"
                          onChange={async e => {
                            const file = e.target.files?.[0];
                            if (file) {
                              try {
                                const url = await uploadAppAsset(file, `rooms/${key}`);
                                setRoomBgImages(p => ({ ...p, [key]: url }));
                              } catch (err: any) {
                                alert('Upload failed: ' + err.message);
                              }
                            }
                          }}
                        />
                      </label>
                    </div>
                    {roomBgImages[key] && (
                      <div className="mt-2">
                        <img src={roomBgImages[key]} alt="Preview" className="w-full h-12 object-cover rounded-lg border border-white/5 bg-black/20" onError={e => { (e.target as HTMLImageElement).src = ''; }} />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          <hr className="border-white/5" />

          {/* Chat bubble colors */}
          <div className="space-y-4">
            <h3 className="text-white text-sm font-semibold flex items-center gap-2">
              <MessageSquare className="w-4 h-4 text-emerald-400" />
              {lang === 'ar' ? 'ألوان فقاعات دردشة الغرف' : 'Room Chat Bubbles Layout'}
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {Object.entries(chatColors).map(([field, value]) => {
                const label = field === 'bubbleSelf' ? (lang === 'ar' ? 'خلفية فقاعة المرسل' : 'My Bubble BG') :
                              field === 'bubbleOther' ? (lang === 'ar' ? 'خلفية فقاعة المستلم' : 'Other Bubble BG') :
                              field === 'bubbleSelfBorder' ? (lang === 'ar' ? 'حدود فقاعة المرسل' : 'My Bubble Border') :
                              field === 'bubbleOtherBorder' ? (lang === 'ar' ? 'حدود فقاعة المستلم' : 'Other Bubble Border') :
                              field === 'bubbleSelfText' ? (lang === 'ar' ? 'نص فقاعة المرسل' : 'My Bubble Text') :
                              field === 'bubbleOtherText' ? (lang === 'ar' ? 'نص فقاعة المستلم' : 'Other Bubble Text') : field;

                return (
                  <div key={field} className="space-y-1.5">
                    <label className="block text-[10px] uppercase text-slate-400 font-bold">{label}</label>
                    <div className="flex gap-2">
                      <input
                        type="color"
                        value={to6Hex(value)}
                        onChange={e => setChatColors(p => ({ ...p, [field]: e.target.value }))}
                        className="w-10 h-8 p-0.5 bg-[#161618] border border-white/10 rounded-lg"
                      />
                      <input
                        type="text"
                        value={value}
                        onChange={e => setChatColors(p => ({ ...p, [field]: e.target.value }))}
                        className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {/* App General settings tab view */}
      {activeDesignerTab === 'settings' && (
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-6">
          <h3 className="text-white text-sm font-semibold">{lang === 'ar' ? 'إعدادات وأصول التطبيق العامة' : 'General App Assets & Configs'}</h3>
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="space-y-1.5">
              <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'اسم التطبيق' : 'Application Display Name'}</label>
              <input
                type="text"
                value={appName}
                onChange={e => setAppName(e.target.value)}
                placeholder="Zero App"
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white"
              />
            </div>

            <div className="space-y-1.5">
              <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'خط التطبيق الرئيسي' : 'Font Family'}</label>
              <select
                value={fontFamily}
                onChange={e => setFontFamily(e.target.value)}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white"
              >
                <option value="system">System Default</option>
                <option value="Cairo">Cairo (Arabic standard)</option>
                <option value="Noto Sans Arabic">Noto Sans Arabic</option>
                <option value="Tajawal">Tajawal</option>
                <option value="Almarai">Almarai</option>
              </select>
            </div>

            <div className="space-y-1.5">
              <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'درجة انحناء زوايا العناصر' : 'Border Radius (Roundedness)'}</label>
              <input
                type="range"
                min="0"
                max="24"
                value={borderRadius}
                onChange={e => setBorderRadius(Number(e.target.value))}
                className="w-full accent-indigo-500"
              />
              <div className="flex justify-between text-[9px] text-slate-500">
                <span>0px (الحاد)</span>
                <span className="text-white font-mono">{borderRadius}px</span>
                <span>24px (الدائري)</span>
              </div>
            </div>

            <div className="space-y-1.5">
              <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'سعر تغيير خلفية الغرفة (بالعملات)' : 'Custom Room Background Price'}</label>
              <input
                type="number"
                min="0"
                value={roomBgPrice}
                onChange={e => setRoomBgPrice(Number(e.target.value))}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white"
              />
            </div>

            <div className="space-y-1.5">
              <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'صورة الشاشة الترحيبية (GIF/PNG)' : 'Splash Screen GIF/Image'}</label>
              <div className="flex gap-2">
                <input
                  type="text"
                  placeholder="https://example.com/splash.gif"
                  value={splashGifUrl}
                  onChange={e => setSplashGifUrl(e.target.value)}
                  className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                />
                <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-400 rounded-lg flex items-center justify-center">
                  <Upload className="w-4 h-4" />
                  <input
                    type="file"
                    accept="image/*"
                    className="hidden"
                    onChange={e => {
                      const file = e.target.files?.[0];
                      if (file) handleSplashUpload(file);
                    }}
                  />
                </label>
              </div>
              {splashGifUrl && (
                <div className="mt-2">
                  <img src={splashGifUrl} alt="Splash screen preview" className="w-24 h-24 object-contain rounded-lg border border-white/5 bg-black/20" />
                </div>
              )}
            </div>
            
            <div className="space-y-1.5">
              <label className="block text-[10px] uppercase text-slate-400 font-bold">{lang === 'ar' ? 'صورة الشريط السفلي للملاحة' : 'Bottom Nav Background Image'}</label>
              <div className="flex gap-2">
                <input
                  type="text"
                  placeholder="https://example.com/bottom_nav.png"
                  value={bottomNavBgImage}
                  onChange={e => setBottomNavBgImage(e.target.value)}
                  className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white"
                />
                <label className="cursor-pointer px-3 py-1.5 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-400 rounded-lg flex items-center justify-center">
                  <Upload className="w-4 h-4" />
                  <input
                    type="file"
                    accept="image/*"
                    className="hidden"
                    onChange={e => {
                      const file = e.target.files?.[0];
                      if (file) handleBottomNavBgUpload(file);
                    }}
                  />
                </label>
              </div>
              {bottomNavBgImage && (
                <div className="mt-2">
                  <img src={bottomNavBgImage} alt="Bottom Nav bg preview" className="w-full h-12 object-cover rounded-lg border border-white/5 bg-black/20" />
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* App Icons tab view */}
      {activeDesignerTab === 'icons' && (
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-6">
          <div className="flex items-center justify-between flex-wrap gap-4 flex-row-reverse">
            <h3 className="text-white text-sm font-semibold">{lang === 'ar' ? 'استبدال أيقونات التطبيق' : 'App Icon Overrides'}</h3>
            
            <div className="flex gap-3 flex-wrap items-center">
              <div className="relative w-48">
                <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-500" />
                <input
                  value={searchQuery}
                  onChange={e => setSearchQuery(e.target.value)}
                  placeholder={lang === 'ar' ? 'بحث عن أيقونة...' : 'Search icon...'}
                  className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 pl-8 pr-3 text-xs text-white focus:outline-none focus:border-indigo-500 placeholder:text-slate-600"
                />
              </div>

              <select
                value={categoryFilter}
                onChange={e => setCategoryFilter(e.target.value)}
                className="bg-[#161618] border border-white/10 rounded-lg py-1.5 px-3 text-xs text-white focus:outline-none"
              >
                <option value="">{lang === 'ar' ? 'كل التصنيفات' : 'All Categories'}</option>
                {iconCategories.map(cat => (
                  <option key={cat} value={cat}>{cat}</option>
                ))}
              </select>

              <button onClick={() => {
                if (confirm(lang === 'ar' ? 'إلغاء كافة استبدالات الأيقونات المخصصة؟' : 'Clear all custom icon overrides?')) {
                  setIconOverrides({});
                }
              }} className="px-2.5 py-1.5 bg-rose-500/10 hover:bg-rose-500/20 text-[10px] text-rose-400 rounded-lg flex items-center gap-1">
                <Trash2 className="w-3 h-3" /> Reset Overrides
              </button>
            </div>
          </div>

          <div className="overflow-x-auto border border-white/5 rounded-xl">
            <table className="w-full text-left text-xs border-collapse">
              <thead>
                <tr className="border-b border-white/5 bg-white/2">
                  <th className="p-3 text-slate-400 font-bold">{lang === 'ar' ? 'رمز الأيقونة' : 'Icon Key'}</th>
                  <th className="p-3 text-slate-400 font-bold">{lang === 'ar' ? 'التصنيف' : 'Category'}</th>
                  <th className="p-3 text-slate-400 font-bold">{lang === 'ar' ? 'الأيقونة الحالية' : 'Current Asset'}</th>
                  <th className="p-3 text-slate-400 font-bold">{lang === 'ar' ? 'التحكم' : 'Action'}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/5">
                {filteredIcons.map(entry => {
                  const customUrl = iconOverrides[entry.key];
                  return (
                    <tr key={entry.key} className="hover:bg-white/2">
                      <td className="p-3 font-mono text-indigo-300">{entry.key}</td>
                      <td className="p-3"><span className="px-2 py-0.5 bg-slate-800 text-slate-300 rounded text-[9px]">{entry.category}</span></td>
                      <td className="p-3">
                        {customUrl ? (
                          <div className="flex items-center gap-2">
                            {customUrl.match(/\.(mp4|webm)$/i) ? (
                              <video src={customUrl} className="w-8 h-8 rounded border border-white/10" muted loop autoPlay />
                            ) : (
                              <img src={customUrl} alt="custom icon preview" className="w-8 h-8 object-contain rounded border border-white/10" onError={e => { (e.target as HTMLImageElement).src = ''; }} />
                            )}
                            <button onClick={() => {
                              const copy = { ...iconOverrides };
                              delete copy[entry.key];
                              setIconOverrides(copy);
                            }} className="text-[9px] text-rose-400 hover:underline">Clear</button>
                          </div>
                        ) : (
                          <span className="text-slate-500 italic">{lang === 'ar' ? 'الافتراضي للتطبيق' : 'App Default'}</span>
                        )}
                      </td>
                      <td className="p-3">
                        <label className="cursor-pointer px-2.5 py-1 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-400 rounded-lg flex items-center gap-1.5 w-max">
                          <Upload className="w-3.5 h-3.5" />
                          <span>{lang === 'ar' ? 'استبدال الأيقونة' : 'Upload Icon'}</span>
                          <input
                            type="file"
                            className="hidden"
                            onChange={e => {
                              const file = e.target.files?.[0];
                              if (file) handleIconUpload(file, entry.key);
                            }}
                          />
                        </label>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Screen Assets (Default Assets grid browser) */}
      {activeDesignerTab === 'assets' && (
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-6">
          <div className="flex justify-between items-center flex-wrap gap-4 flex-row-reverse">
            <div>
              <h3 className="text-white text-sm font-semibold">{lang === 'ar' ? '📁 أصول الشاشات الافتراضية والتعديل عليها' : '📁 Screen Assets Browser'}</h3>
              <p className="text-slate-500 text-[10px] mt-0.5">{lang === 'ar' ? 'اختر شاشة لرؤية الصور الافتراضية واستبدالها مخصصاً' : 'Browse default assets by screen category and upload custom replacements'}</p>
            </div>
            
            <div className="flex gap-2">
              <div className="relative w-44">
                <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-500" />
                <input
                  value={assetSearch}
                  onChange={e => setAssetSearch(e.target.value)}
                  placeholder={lang === 'ar' ? 'بحث عن أصل...' : 'Search asset...'}
                  className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 pl-8 pr-3 text-xs text-white focus:outline-none"
                />
              </div>
            </div>
          </div>

          {/* Screen Tabs filter */}
          <div className="flex gap-1.5 overflow-x-auto pb-1">
            {screenCategories.map(s => {
              const isActive = selectedAssetScreen === s;
              return (
                <button key={s} onClick={() => setSelectedAssetScreen(s)}
                  className={`shrink-0 px-3 py-1.5 text-[10px] font-semibold rounded-lg transition-colors ${
                    isActive ? 'bg-indigo-600 text-white shadow-md shadow-indigo-950/20' : 'bg-[#161618] text-slate-400 border border-white/10 hover:bg-white/5'
                  }`}>
                  {SCREEN_ASSETS[s]?.label || s}
                </button>
              );
            })}
          </div>

          {/* Grid list of assets */}
          {filteredScreenAssets.length === 0 ? (
            <div className="text-slate-500 text-xs py-10 text-center">لا توجد أصول مطابقة للبحث</div>
          ) : (
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
              {filteredScreenAssets.map(entry => {
                const asset = assets.find(a => a.key === entry.fullKey);
                const isSvg = entry.fullKey.endsWith('_svga');
                const isJson = entry.fullKey.endsWith('_json');
                
                return (
                  <div key={entry.fullKey} className="bg-[#18181b] rounded-xl border border-white/5 overflow-hidden group flex flex-col justify-between">
                    {/* Preview Area */}
                    {asset?.remoteUrl ? (
                      <div className="relative">
                        {isSvg ? (
                          <div className="w-full h-24 flex items-center justify-center bg-black/30 text-[9px] text-emerald-400 font-medium">SVGA Animation</div>
                        ) : isJson ? (
                          <div className="w-full h-24 flex items-center justify-center bg-black/30 text-[9px] text-yellow-400 font-medium">Lottie JSON</div>
                        ) : (
                          <img src={asset.remoteUrl} className="w-full h-24 object-contain bg-black/30" onError={e => { (e.target as HTMLImageElement).src = ''; }} />
                        )}
                        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-all flex items-center justify-center opacity-0 group-hover:opacity-100">
                          <button onClick={() => handleAssetOverrideUpload(entry)} className="text-[9px] px-2.5 py-1 rounded bg-white/10 text-white hover:bg-white/20">تغيير</button>
                        </div>
                      </div>
                    ) : (
                      <div className="relative group/nooverride">
                        {isSvg ? (
                          <div className="w-full h-24 flex items-center justify-center bg-black/20 text-[9px] text-slate-500 font-bold">SVGA Default</div>
                        ) : isJson ? (
                          <div className="w-full h-24 flex items-center justify-center bg-black/20 text-[9px] text-slate-500 font-bold">Lottie Default</div>
                        ) : !entry.path.endsWith('.xml') ? (
                          <img src={`/${entry.path}`} className="w-full h-24 object-contain bg-black/20" onError={e => { (e.target as HTMLImageElement).src = ''; }} />
                        ) : (
                          <div className="w-full h-24 flex items-center justify-center bg-black/20 text-[9px] text-slate-500 font-bold">XML Vector</div>
                        )}
                        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/45 transition-all flex items-center justify-center opacity-0 group-hover:opacity-100">
                          <button onClick={() => handleAssetOverrideUpload(entry)} className="text-[9px] px-2.5 py-1.5 rounded bg-indigo-600 text-white font-bold shadow-md hover:bg-indigo-700">رفع بديل</button>
                        </div>
                      </div>
                    )}

                    {/* Metadata Card */}
                    <div className="p-3 space-y-1 border-t border-white/5">
                      <div className="text-[10px] text-white font-bold truncate" title={entry.constant}>{constantToArabic(entry.constant)}</div>
                      <div className="text-[8px] text-slate-500 font-mono truncate" dir="ltr" title={entry.constant}>{entry.constant}</div>
                      
                      {asset?.remoteUrl && (
                        <div className="flex gap-1 pt-1.5 justify-end">
                          <button onClick={() => window.open(asset.remoteUrl, '_blank')} className="text-[8px] px-2 py-0.5 rounded border border-white/10 text-slate-400 hover:text-white hover:bg-white/5">🔗</button>
                          <button onClick={() => handleAssetOverrideDelete(entry.fullKey)} className="text-[8px] px-2 py-0.5 rounded border border-rose-500/20 text-rose-400/80 hover:text-rose-400 hover:bg-rose-500/10">🗑</button>
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* Ranks frames and visuals tab view (from VisualManager) */}
      {activeDesignerTab === 'ranks' && (
        <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-6">
          <div className="flex justify-between items-center flex-wrap gap-4 flex-row-reverse">
            <div>
              <h3 className="text-white text-sm font-semibold">{lang === 'ar' ? '🏆 خلفيات وإطارات لوحة الترتيب' : '🏆 Rank Frames & Backgrounds'}</h3>
              <p className="text-slate-500 text-[10px] mt-0.5">{lang === 'ar' ? 'خصص خلفيات وإطارات الرتب الذهبية، الفضية، والبرونزية' : 'Configure rank backgrounds and SVGA/video frames'}</p>
            </div>

            {/* Rank Sub-tabs */}
            <div className="flex gap-1">
              {(Object.keys(rankCategoryLabels) as Array<keyof typeof rankCategoryLabels>).map(sub => (
                <button
                  key={sub}
                  onClick={() => setActiveRankSubTab(sub)}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold border transition-all ${
                    activeRankSubTab === sub
                      ? 'bg-amber-600/10 border-amber-500 text-amber-300'
                      : 'bg-white/5 border-transparent text-slate-400 hover:bg-white/10'
                  }`}
                >
                  {rankCategoryLabels[sub]}
                </button>
              ))}
            </div>
          </div>

          <hr className="border-white/5" />

          {/* Background customization */}
          <div className="space-y-4 max-w-xl">
            <div>
              <label className="block text-[10px] text-slate-400 font-bold mb-1.5">{lang === 'ar' ? 'رابط أو مفتاح خلفية الترتيب' : 'Rank BG Key/URL'}</label>
              <input
                type="text"
                value={rankConfig[`${activeRankSubTab}_bg`] || ''}
                onChange={e => setRankConfig(p => ({ ...p, [`${activeRankSubTab}_bg`]: e.target.value }))}
                placeholder="assets_mipmap-xxhdpi_xxx"
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white font-mono"
              />
            </div>
            
            <RankAssetUpload
              assetKey={`${activeRankSubTab}_bgAssetKey`}
              label={lang === 'ar' ? 'ارفع صورة خلفية مخصصة' : 'Upload custom background'}
              accept="image/*,.svga,.mp4,.gif"
              config={{ rankConfig }}
              updateField={(f, v) => setRankConfig(v as any)}
              assets={assets}
            />
          </div>

          {/* New Rank UI Config fields */}
          <div className="space-y-4 max-w-xl mt-6 p-4 border border-indigo-500/30 rounded-xl bg-indigo-500/5">
             <h4 className="text-indigo-400 font-bold mb-3">{lang === 'ar' ? '🎨 صور وإطارات الترتيب العام (التصميم الجديد)' : 'Global Rank UI Config'}</h4>
             {[
               {key: 'bgImage', labelAr: 'خلفية الشاشة بالكامل'},
               {key: 'listBgImage', labelAr: 'خلفية القائمة (المركز 4 فما فوق)'},
               {key: 'rank1Frame', labelAr: 'إطار المركز الأول'},
               {key: 'rank2Frame', labelAr: 'إطار المركز الثاني'},
               {key: 'rank3Frame', labelAr: 'إطار المركز الثالث'},
               {key: 'rank1Banner', labelAr: 'راية المركز الأول'},
               {key: 'rank2Banner', labelAr: 'راية المركز الثاني'},
               {key: 'rank3Banner', labelAr: 'راية المركز الثالث'}
             ].map(f => (
               <div key={f.key} className="flex flex-col gap-1.5 mb-4">
                 <label className="text-xs text-white font-semibold">{f.labelAr} ({f.key})</label>
                 <div className="flex gap-2 items-center">
                   <input type="text" value={visuals.rank?.[f.key] || ''} onChange={e => updateField('rank', f.key, e.target.value)} className="flex-1 bg-black/40 border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" placeholder="URL..." />
                   <label className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 rounded-lg text-xs font-bold cursor-pointer text-white flex items-center gap-1">
                     <Upload className="w-3 h-3" /> {lang === 'ar' ? 'رفع' : 'Upload'}
                     <input type="file" className="hidden" accept="image/*" onChange={async (e) => {
                       const file = e.target.files?.[0];
                       if(!file) return;
                       try {
                         const url = await uploadAppAsset(file, `global_rank_${f.key}`);
                         updateField('rank', f.key, url);
                         showMsg(lang === 'ar' ? 'تم الرفع' : 'Uploaded');
                       } catch(err) {
                         alert(lang === 'ar' ? 'فشل' : 'Failed');
                       }
                     }} />
                   </label>
                 </div>
                 {visuals.rank?.[f.key] && (
                   <img src={visuals.rank[f.key]} className="h-20 w-max object-contain rounded-lg border border-white/10 mt-1 bg-black/50" />
                 )}
               </div>
             ))}

             <hr className="border-white/10 my-4" />
             <h4 className="text-indigo-400 font-bold mb-3">{lang === 'ar' ? '🔘 تبويبات شاشة الترتيب (الرئيسية والفرعية)' : 'Global Rank Tabs Config'}</h4>
             
             {[
               {key: 'mainTabBgImage', labelAr: 'خلفية تبويب (الثروة / السحر / الغرف)', isColor: false},
               {key: 'mainTabIndicatorImage', labelAr: 'صورة مؤشر التبويب الرئيسي', isColor: false},
               {key: 'mainTabTextColor', labelAr: 'لون نص التبويب الرئيسي (HEX)', isColor: true},
               {key: 'subTabBgImage', labelAr: 'خلفية تبويب (يومي / أسبوعي / شهري)', isColor: false},
               {key: 'subTabIndicatorImage', labelAr: 'صورة مؤشر التبويب الفرعي', isColor: false},
               {key: 'subTabTextColor', labelAr: 'لون نص التبويب الفرعي (HEX)', isColor: true},
             ].map(f => (
               <div key={f.key} className="flex flex-col gap-1.5 mb-4">
                 <label className="text-xs text-white font-semibold">{f.labelAr} ({f.key})</label>
                 <div className="flex gap-2 items-center">
                   <input 
                     type="text" 
                     value={visuals.rank?.[f.key] || ''} 
                     onChange={e => updateField('rank', f.key, e.target.value)} 
                     className="flex-1 bg-black/40 border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono" 
                     placeholder={f.isColor ? "#FFFFFF" : "URL..."} 
                   />
                   
                   {!f.isColor && (
                     <label className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 rounded-lg text-xs font-bold cursor-pointer text-white flex items-center gap-1">
                       <Upload className="w-3 h-3" /> {lang === 'ar' ? 'رفع' : 'Upload'}
                       <input type="file" className="hidden" accept="image/*" onChange={async (e) => {
                         const file = e.target.files?.[0];
                         if(!file) return;
                         try {
                           const url = await uploadAppAsset(file, `global_rank_${f.key}`);
                           updateField('rank', f.key, url);
                           showMsg(lang === 'ar' ? 'تم الرفع' : 'Uploaded');
                         } catch(err) {
                           alert(lang === 'ar' ? 'فشل' : 'Failed');
                         }
                       }} />
                     </label>
                   )}
                   
                   {f.isColor && visuals.rank?.[f.key] && (
                     <div className="w-8 h-8 rounded-lg border border-white/20" style={{ backgroundColor: visuals.rank[f.key] }}></div>
                   )}
                 </div>
                 {!f.isColor && visuals.rank?.[f.key] && (
                   <img src={visuals.rank[f.key]} className="h-10 w-max object-contain rounded-lg border border-white/10 mt-1 bg-black/50" />
                 )}
               </div>
             ))}
          </div>

          <hr className="border-white/5 mt-6" />

          {/* Ranks frames uploads */}
          <div className="space-y-4">
            <div>
              <h4 className="text-xs text-amber-300 font-semibold mb-1">{lang === 'ar' ? '🎞 إطارات الرتب المتحركة' : '🎞 Animated Rank Frames'}</h4>
              <p className="text-[9px] text-slate-500">{lang === 'ar' ? 'ارفع ملفات (SVGA / VAP / MP4 / GIF) لكل رتبة من الثلاثة الأوائل' : 'Upload SVGA, VAP, MP4, or GIF frames for top 3 ranks'}</p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              {[1, 2, 3].map(rank => {
                const existing = rankFrames.find((f: any) => f.category === activeRankSubTab && f.rank === rank);
                const rankLabel = rank === 1 ? (lang === 'ar' ? '🥇 المركز الأول (الذهبي)' : '🥇 Gold Rank') :
                                  rank === 2 ? (lang === 'ar' ? '🥈 المركز الثاني (الفضي)' : '🥈 Silver Rank') :
                                               (lang === 'ar' ? '🥉 المركز الثالث (البرونزي)' : '🥉 Bronze Rank');
                const isVideo = existing?.asset_url?.match(/\.(mp4|webm)$/i);
                const isImage = existing?.asset_url?.match(/\.(png|jpg|jpeg|gif|webp)$/i);

                return (
                  <div key={rank} className="p-4 bg-[#18181b] rounded-xl border border-white/5 space-y-3 flex flex-col justify-between">
                    <div>
                      <span className="text-[10px] text-slate-400 font-bold block mb-2">{rankLabel}</span>
                      
                      {existing ? (
                        <div className="space-y-2">
                          <div className="w-full h-24 bg-black/30 rounded-lg flex items-center justify-center border border-white/5 overflow-hidden">
                            {isVideo ? (
                              <video src={existing.asset_url} className="w-full h-full object-contain" muted loop autoPlay />
                            ) : isImage ? (
                              <img src={existing.asset_url} className="w-full h-full object-contain" onError={e => { (e.target as HTMLImageElement).src = ''; }} />
                            ) : existing.asset_type === 'svga' ? (
                              <span className="text-[10px] text-emerald-400 font-bold">SVGA Animation</span>
                            ) : existing.asset_type === 'vap' ? (
                              <span className="text-[10px] text-emerald-400 font-bold">VAP Video</span>
                            ) : (
                              <span className="text-[10px] text-slate-500">File Asset</span>
                            )}
                          </div>
                          <span className="text-[8px] text-slate-500 font-mono block truncate" dir="ltr" title={existing.asset_url}>{existing.asset_url}</span>
                        </div>
                      ) : (
                        <div className="w-full h-24 rounded-lg border border-dashed border-white/5 bg-black/10 flex items-center justify-center text-[9px] text-slate-600">
                          {lang === 'ar' ? 'لا يوجد إطار حالياً' : 'No Frame uploaded'}
                        </div>
                      )}
                    </div>

                    <div className="flex gap-2 pt-2">
                      <label className="flex-1 cursor-pointer py-1.5 bg-indigo-600 hover:bg-indigo-700 text-white font-bold rounded-lg flex items-center justify-center gap-1 text-[9px] shadow-md shadow-indigo-950/20">
                        <Upload className="w-3 h-3" /> {lang === 'ar' ? 'رفع إطار' : 'Upload Frame'}
                        <input
                          type="file"
                          accept="image/*,.svga,.mp4,.gif,.vap"
                          className="hidden"
                          onChange={async e => {
                            const file = e.target.files?.[0];
                            if (!file) return;
                            try {
                              const url = await uploadAppAsset(file, `rank_frame_${activeRankSubTab}_${rank}`);
                              const type = file.name.endsWith('.svga') ? 'svga' : file.name.endsWith('.vap') ? 'vap' : 'webp';
                              await handleSaveFrame(activeRankSubTab, rank, url, type);
                              showMsg(lang === 'ar' ? 'تم حفظ الإطار بنجاح!' : 'Frame saved!');
                            } catch (err) {
                              alert('فشل الرفع: ' + (err as Error).message);
                            }
                          }}
                        />
                      </label>
                      
                      {existing && (
                        <button
                          onClick={() => handleClearFrame(activeRankSubTab, rank)}
                          className="px-2.5 py-1.5 rounded-lg border border-rose-500/20 text-rose-400 hover:bg-rose-500/10 text-[9px]"
                        >
                          ✕
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// Re-implemented helper to display rank background upload assets
function RankAssetUpload({ assetKey, label, accept = 'image/*,.svga,.mp4,.gif,.vap,.json', config, updateField, assets }: {
  assetKey: string; label: string; accept?: string;
  config: any; updateField: (field: string, value: unknown) => void;
  assets?: AppAssetRecord[];
}) {
  const [uploading, setUploading] = useState(false);
  const rc = config.rankConfig || {};
  const currentKey = rc[assetKey as keyof typeof rc] as string || '';
  
  const asset = assets?.find(a => a.key === currentKey);
  const url = asset?.remoteUrl || (currentKey.startsWith('http') ? currentKey : '');
  const isVideo = url.match(/\.(mp4|webm)$/i);
  const isImage = url.match(/\.(png|jpg|jpeg|gif|webp)$/i);

  return (
    <div className="border-t border-white/5 pt-2 mt-2">
      <label className="block text-[9px] text-slate-400 font-bold mb-1">{label}</label>
      <div className="flex gap-2 items-center">
        {url ? (
          <div className="flex items-center gap-2 flex-1 min-w-0">
            {isVideo ? (
              <video src={url} className="w-8 h-8 object-contain rounded border border-white/10" muted loop autoPlay />
            ) : isImage ? (
              <img src={url} className="w-8 h-8 object-contain rounded border border-white/10" onError={e => { (e.target as HTMLImageElement).src = ''; }} />
            ) : url.endsWith('.svga') ? (
              <div className="w-8 h-8 flex items-center justify-center bg-black/30 text-[7px] text-emerald-400 font-bold rounded border border-white/10">SVGA</div>
            ) : url.endsWith('.vap') ? (
              <div className="w-8 h-8 flex items-center justify-center bg-black/30 text-[7px] text-emerald-400 font-bold rounded border border-white/10">VAP</div>
            ) : (
              <div className="w-8 h-8 flex items-center justify-center bg-black/30 text-[7px] text-slate-500 rounded border border-white/10">FILE</div>
            )}
            <span className="text-[8px] text-emerald-400 font-mono truncate flex-1">{currentKey}</span>
          </div>
        ) : (
          <span className="text-[8px] text-slate-600 flex-1">لا يوجد أصل مخصص</span>
        )}
        <label className="flex items-center gap-1 text-[8px] px-2 py-1 rounded border border-white/10 hover:bg-white/5 cursor-pointer shrink-0">
          <Upload className="w-2 h-2" />
          {uploading ? 'جاري...' : 'رفع'}
          <input type="file" accept={accept} disabled={uploading} className="hidden" onChange={async e => {
            const file = e.target.files?.[0]; if (!file) return;
            setUploading(true);
            try {
              const url = await uploadAppAsset(file, `rank_${assetKey}`);
              const record: AppAssetRecord = {
                id: crypto.randomUUID(), key: `rank_${assetKey}`, name: label,
                type: file.name.endsWith('.svga') ? 'svga' : file.name.endsWith('.vap') ? 'vap' : file.name.endsWith('.json') ? 'lottie' : 'image',
                category: 'الترتيب', subcategory: 'خلفيات الترتيب', localPath: '', remoteUrl: url,
                defaultValue: '', mimeType: file.type || 'application/octet-stream', fileSize: file.size,
                width: null, height: null, sortOrder: 0, isActive: true,
                createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
              };
              await upsertAppAsset(record);
              updateField('rankConfig', { ...rc, [assetKey]: `rank_${assetKey}` });
            } catch (err) { alert('فشل الرفع: ' + (err as Error).message); }
            setUploading(false);
          }} />
        </label>
        {currentKey && (
          <button onClick={() => updateField('rankConfig', { ...rc, [assetKey]: '' })}
            className="text-[8px] px-2 py-1 rounded border border-rose-500/20 text-rose-400 hover:bg-rose-500/10 shrink-0">مسح</button>
        )}
      </div>
    </div>
  );
}
