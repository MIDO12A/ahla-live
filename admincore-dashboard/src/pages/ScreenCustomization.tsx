import { useEffect, useState, useContext } from 'react';
import { I18nContext } from '../lib/i18n';
import { getAppConfig, updateAppConfig } from '../lib/db';
import { uploadAppAsset } from '../lib/storage';
import { Save, RotateCcw, Upload, Check, Image, Type, Layers } from 'lucide-react';
import { to6Hex } from '../lib/colors';

interface ScreenVisuals {
  agency: Record<string, string>;
  badges: Record<string, string>;
  necklaces: Record<string, string>;
  rank: Record<string, string>;
  checkbox: Record<string, string>;
  store: Record<string, string>;
  backpack: Record<string, string>;
  giftPanel: Record<string, string>;
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
  eventInfo: Record<string, string>;
  rechargeEvent: Record<string, string>;
  notifications: Record<string, string>;
  miniprofile: Record<string, string>;
}

const defaultVisuals: ScreenVisuals = {
  agency: {
    backgroundImage: '',
    headerBgColor: '#1a1a2e',
    headerTextColor: '#ffffff',
    cardBgColor: '#16213e',
    cardBorderColor: '#0f3460',
    textColor: '#ffffff',
    subTextColor: '#a0a0b0',
    accentColor: '#e94560',
    checkboxCheckedImage: '',
    checkboxUncheckedImage: '',
    tabActiveColor: '#e94560',
    tabInactiveColor: '#555',
    coinIcon: '',
    diamondIcon: '',
    rankIcon: '',
    memberAvatarBorder: '#e94560',
  },
  badges: {
    backgroundImage: '',
    headerBgColor: '#1a1a2e',
    headerBgImage: '',
    headerTextColor: '#ffffff',
    headerTextImage: '',
    cardBgColor: '#16213e',
    cardBgImage: '',
    cardBorderColor: '#0f3460',
    cardBorderImage: '',
    textColor: '#ffffff',
    textImage: '',
    subTextColor: '#a0a0b0',
    subTextImage: '',
    accentColor: '#f0c724',
    accentImage: '',
    sectionBgColor: '#0d0d12',
    sectionBgImage: '',
    badgeBorderColor: '#f0c724',
    badgeBorderImage: '',
    badgeBgColor: '#1a1a2e',
    badgeBgImage: '',
    lockImage: '',
  },
  necklaces: {
    backgroundImage: '',
    headerBgColor: '#1a1a2e',
    headerBgImage: '',
    headerTextColor: '#ffffff',
    headerTextImage: '',
    cardBgColor: '#16213e',
    cardBgImage: '',
    cardBorderColor: '#0f3460',
    cardBorderImage: '',
    textColor: '#ffffff',
    textImage: '',
    subTextColor: '#a0a0b0',
    subTextImage: '',
    accentColor: '#e94560',
    accentImage: '',
    sectionBgColor: '#0d0d12',
    sectionBgImage: '',
    necklaceBorderColor: '#e94560',
    necklaceBorderImage: '',
    necklaceBgColor: '#1a1a2e',
    necklaceBgImage: '',
    lockImage: '',
  },
  rank: {
    backgroundImage: '',
    headerBgColor: '#1a1a2e',
    headerBgImage: '',
    headerTextColor: '#ffffff',
    headerTextImage: '',
    cardBgColor: '#16213e',
    cardBgImage: '',
    cardBorderColor: '#0f3460',
    cardBorderImage: '',
    textColor: '#ffffff',
    textImage: '',
    subTextColor: '#a0a0b0',
    subTextImage: '',
    accentColor: '#ffd700',
    accentImage: '',
    goldColor: '#FFD700',
    silverColor: '#C0C0C0',
    bronzeColor: '#CD7F32',
    pointsColor: '#FFD700',
    trophyIcon: 'emoji_events',
    crownIcon: '',
    rankBgImage: '',
    bgImage: '',
    listBgImage: '',
    rank1Frame: '',
    rank2Frame: '',
    rank3Frame: '',
    rank1Banner: '',
    rank2Banner: '',
    rank3Banner: '',
  },
  checkbox: {
    checkedImage: '',
    uncheckedImage: '',
  },
  store: {
    backgroundImage: '',
    headerBgColor: '#1a1a2e',
    headerBgImage: '',
    headerTextColor: '#ffffff',
    headerTextImage: '',
    cardBgColor: '#16151A',
    cardBgImage: '',
    cardBorderColor: '#ffffff',
    cardBorderImage: '',
    textColor: '#ffffff',
    textImage: '',
    subTextColor: '#9BA1B6',
    subTextImage: '',
    accentColor: '#DE880F',
    accentImage: '',
    lockImage: '',
    sectionBgColor: '#0d0d12',
    sectionBgImage: '',
  },
  backpack: {
    backgroundImage: '',
    headerBgColor: '#1a1a2e',
    headerBgImage: '',
    headerTextColor: '#ffffff',
    headerTextImage: '',
    tabBgColor: '#16151A',
    tabActiveColor: '#ffffff',
    tabInactiveColor: '#9BA1B6',
    cardBgColor: '#16151A',
    cardBgImage: '',
    cardBorderColor: '#ffffff',
    cardBorderImage: '',
    textColor: '#ffffff',
    textImage: '',
    subTextColor: '#9BA1B6',
    subTextImage: '',
    accentColor: '#DE880F',
    accentImage: '',
    lockImage: '',
    sectionBgColor: '#0d0d12',
    sectionBgImage: '',
  },
  giftPanel: {
    backgroundImage: '',
    backgroundColor: '#16151A',
    headerBgColor: 'transparent',
    headerBgImage: '',
    headerTextColor: '#ffffff',
    tabBgColor: '#22222E',
    tabActiveColor: '#FFD700',
    tabInactiveColor: '#9BA1B6',
    cardBgColor: '#1A1A24',
    cardBgImage: '',
    cardBorderColor: '#2A2A3A',
    cardSelectedBorderColor: '#FFD700',
    textColor: '#ffffff',
    subTextColor: '#FFD856',
    accentColor: '#DE880F',
    sendBtnColor: '#DE880F',
    sendBtnGradientStart: '#FFD700',
    sendBtnGradientEnd: '#DE880F',
    sendBtnTextColor: '#ffffff',
    countBtnBgColor: '#22222E',
    countBtnTextColor: '#ffffff',
    coinsTextColor: '#ffffff',
    comboIdleImage: '',
    comboFireImage: '',
    durationBadgeBg: '#E91E63',
    luckyBadgeImage: '',
    starBadgeImage: '',
  },
  wallet: {
    backgroundImage: '',
    headerBgColor: '#1a1a2e',
    headerBgImage: '',
    headerTextColor: '#ffffff',
    headerTextImage: '',
    cardBgColor: '#16151A',
    cardBgImage: '',
    cardBorderColor: '#ffffff',
    cardBorderImage: '',
    textColor: '#ffffff',
    textImage: '',
    subTextColor: '#9BA1B6',
    subTextImage: '',
    accentColor: '#DE880F',
    accentImage: '',
    lockImage: '',
    sectionBgColor: '#0d0d12',
    sectionBgImage: '',
  },
  level: {
    backgroundImage: '',
    headerBgColor: '#1a1a2e',
    headerBgImage: '',
    headerTextColor: '#ffffff',
    headerTextImage: '',
    cardBgColor: '#1a1a2e',
    cardBgImage: '',
    cardBorderColor: '#0f3460',
    cardBorderImage: '',
    textColor: '#ffffff',
    textImage: '',
    subTextColor: '#a0a0b0',
    subTextImage: '',
    accentColor: '#f0c724',
    accentImage: '',
    lockImage: '',
    sectionBgColor: '#0d0d12',
    sectionBgImage: '',
  },
  cp: {
    backgroundImage: '',
    headerBgColor: '#E91E8C',
    headerBgImage: '',
    headerTextColor: '#ffffff',
    headerTextImage: '',
    cardBgColor: '#ffffff',
    cardBgImage: '',
    cardBorderColor: '#E91E8C',
    cardBorderImage: '',
    textColor: '#5D1A3A',
    textImage: '',
    subTextColor: '#a0a0b0',
    subTextImage: '',
    accentColor: '#FF4FA3',
    accentImage: '',
    primaryColor: '#E91E8C',
    gradientStart: '#E91E8C',
    gradientEnd: '#FF4FA3',
    goldColor: '#FFD700',
    silverColor: '#C0C0C0',
    bronzeColor: '#CD7F32',
    sectionBgColor: '#FCE4EC',
    sectionBgImage: '',
    lockImage: '',
    fullScreenBg: '',
    cabinBg: '',
    cabinDefaultBg: '',
    leftFrame: '',
    rightFrame: '',
    heartImage: '',
    noCpHeartSvg: '',
    tokenBg: '',
    mineBg: '',
    countdownDaySvg: '',
    countdownHourSvg: '',
    countdownMinSvg: '',
    countdownSecSvg: '',
    rankTagGoldSvg: '',
    rankTagSilverSvg: '',
    rankTagBronzeSvg: '',
    historyCardSvg: '',
    giftsBannerSvg: '',
    rankBgImage: '',
    tabActiveColor: '#E91E8C',
    tabInactiveColor: '#ffffff',
    tabBgColor: '#E91E8C',
    tabBgImage: '',
    countdownTextColor: '#E91E8C',
    countdownLabelColor: '#000000',
    invitationBgColor: '#ffffff',
    invitationBgImage: '',
    buttonColor: '#E91E8C',
    buttonTextColor: '#ffffff',
    buttonOutlineColor: '#E91E8C',
    giftButtonGradientStart: '#FF4FA3',
    giftButtonGradientEnd: '#E91E8C',
    sectionHeaderColor: '#E91E8C',
    avatarBorderColor: '#E91E8C',
    scoreTokenColor: '#FFD700',
    scoreTokenLabelColor: '#ffffff',
    scoreTokenBgColor: '#E91E8C',
    podiumBgStart: '#FCE4EC',
    podiumBgEnd: '#ffffff',
    periodButtonActiveBg: '#E91E8C',
    periodButtonActiveText: '#ffffff',
    periodButtonInactiveBg: '#0000000D',
    periodButtonInactiveText: '#00000073',
    rankItemBg: '#ffffff',
    rankShadowColor: '#E91E8C',
    myRankPillGradientStart: '#FF4FA3',
    myRankPillGradientEnd: '#E91E8C',
    myRankPillText: '#ffffff',
    myRankScoreColor: '#FFD700',
    // Profile CP card colors (user_profile_screen CP section)
    profileDaysBadgeBg: '#260105',
    profileDaysBadgeBorder: '#81050f',
    profileDaysBadgeBg2: '#a40b25',
    profileDaysBadgeBorder2: '#e73d46',
    profileDaysText: '#b3b3b3',
    profileDaysTogetherText: '#cccccc',
    profileLevelGradientStart: '#fff19f',
    profileLevelGradientEnd: '#ffb565',
    profileHeartIcon: 'assets/cp/ic_cp_val_heart.png',
    profileLevelBg: 'assets/cp/ic_rs_lv_bg_cp.png',
    profileNameFrame: 'assets/cp/ic_send_invitation_name_frame.png',
    profileTopBgSvga: 'assets/svga/relationship_act_top_bg.svga',
  },
  miniprofile: {
    backgroundImage: '',
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
  },
  signin: {
    backgroundImage: '',
    headerBgColor: '#2e0d15',
    headerBgImage: '',
    headerTextColor: '#FFD700',
    headerTextImage: '',
    cardBgColor: '#3d1520',
    cardBgImage: '',
    cardBorderColor: '#DE880F',
    cardBorderImage: '',
    textColor: '#ffffff',
    textImage: '',
    subTextColor: '#B8A88A',
    subTextImage: '',
    accentColor: '#FFD700',
    accentImage: '',
    goldColor: '#FFD700',
    buttonColor: '#DE880F',
    buttonTextColor: '#ffffff',
    buttonGradientStart: '#FFD700',
    buttonGradientEnd: '#DE880F',
    dayBgColor: '#3d1520',
    dayActiveColor: '#5a2030',
    dayClaimedColor: '#1a4a1a',
    dayLockedColor: '#2a1018',
    dayBorderColor: '#DE880F',
    dayClaimedBorderColor: '#4CAF50',
    checkmarkImage: '',
    lockImage: '',
    streakIcon: '',
    topBgSvga: '',
    buttonImage: '',
    sectionBgColor: '#2e0d15',
    sectionBgImage: '',
  },
  room: {
    backgroundImage: '',
    headerBgColor: 'transparent',
    headerTextColor: '#ffffff',
    gameBarBgColor: '#1AFFFFFF',
    gameBarTextColor: '#ffffff',
    gameBarDescColor: '#80ffffff',
    gameIconImage: '',
    exitIconImage: '',
    onlineCapsuleBgImage: '',
    giftIconImage: '',
    chatIconImage: '',
    emojiIconImage: '',
    micOnIconImage: '',
    micOffIconImage: '',
    musicIconImage: '',
    msgIconImage: '',
    functionIconImage: '',
    seatDefaultCircleImage: '',
    seatLockCircleImage: '',
    seatDefaultClassicImage: '',
    seatLockClassicImage: '',
    seatDefaultVipImage: '',
    seatLockVipImage: '',
    userCardBgColor: '#16151A',
    userCardBgImage: '',
    userGiftBgImage: '',
    userFollowIconImage: '',
    userChatIconImage: '',
    userAtIconImage: '',
    userGiftBtnImage: '',
    userMicDownIconImage: '',
    userMicMuteIconImage: '',
    exitSheetBgColor: '#16151A',
    volumePanelBgColor: '#16151A',
    functionsPanelBgColor: '#16151A',
    seatPanelBgColor: '#F51D1111',
    seatPanelTopBg: '',
    seatRadioCheckedBg: '',
    seatRadioUncheckedBg: '',
    seatGameIcon: '',
    seatClassicIcon: '',
    seatVipIcon: '',
    seatPreviewFrame: '',
    seatConfirmBtnStart: '#FFFCCE5E',
    seatConfirmBtnEnd: '#FFD19C3B',
    seatConfirmBtnTextColor: '#FFFFFF',
    funcMixerIcon: '',
    funcSettingsIcon: '',
    funcSeatStyleIcon: '',
    funcBgIcon: '',
    funcReportIcon: '',
    funcEffectIcon: '',
    funcVolumeIcon: '',
    funcGiftValIcon: '',
    settingsHeaderBg: '',
    settingsLabelIcon: '',
    settingsCameraIcon: '',
    settingsConfirmBtnStart: '#FFFCCE5E',
    settingsConfirmBtnEnd: '#FFD19C3B',
  },
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
    backgroundColor: '#16151A',
    textColor: '#ffffff',
    subTextColor: '#9BA1B6',
    buttonColor: '#FFE082',
    coverHeight: '',
    coverAspectRatio: '',
  },
  eventInfo: {
    backgroundImage: '',
    backgroundColor: '#ffffff',
    textColor: '#000000',
    subTextColor: '#888888',
  },
  rechargeEvent: {
    backgroundImage: '',
    headerBgImage: '',
    headerTextImage: '',
    headerBgColor: '#FF5722',
    bannerBgGradientStart: '#FF9800',
    bannerBgGradientMid: '#FF5722',
    bannerBgGradientEnd: '#E91E63',
    bannerTextColor: '#FFFFFF',
    badgeBgColor: '#FFFFFF',
    badgeTextColor: '#D81B60',
    cardBgColor: '#1A1A24',
    cardBorderColor: '#3B3224',
    cardBgImage: '',
    textColor: '#FFFFFF',
    textImage: '',
    subTextColor: '#B0B0C0',
    subTextImage: '',
    accentColor: '#FFD700',
    accentImage: '',
    progressFillStart: '#FFD700',
    progressFillEnd: '#FF9100',
    countdownDaySvg: '',
    countdownHourSvg: '',
    countdownMinSvg: '',
    countdownSecSvg: '',
  },
  notifications: {
    backgroundImage: '',
    backgroundColor: '#211211',
    textColor: '#ffffff',
    subTextColor: '#b3b3b3',
    cardBgColor: '#301c1a',
  },
};

const screenTabs = ['rechargeEvent', 'agency', 'badges', 'necklaces', 'rank', 'checkbox', 'store', 'backpack', 'giftPanel', 'wallet', 'level', 'cp', 'miniprofile', 'signin', 'room', 'discover', 'message', 'profile', 'chat', 'userProfile', 'eventInfo', 'notifications'] as const;

const screenLabels: Record<string, Record<string, string>> = {
  rechargeEvent: { ar: '⚡ شاشة حدث الشحن الأسطوري', en: '⚡ Recharge Event Screen' },
  agency: { ar: 'شاشة الوكالة', en: 'Agency Screen' },
  badges: { ar: 'شاشة الشارات', en: 'Badges Screen' },
  necklaces: { ar: 'شاشة القلائد', en: 'Necklaces Screen' },
  rank: { ar: 'شاشة الترتيب', en: 'Rank Screen' },
  checkbox: { ar: 'صور الاختيار', en: 'Checkbox Images' },
  store: { ar: 'شاشة المتجر', en: 'Store Screen' },
  backpack: { ar: '🎒 شاشة الحقيبة (في كلمة أنا)', en: '🎒 Profile Backpack Screen' },
  giftPanel: { ar: '🎁 صندوق الهدايا (داخل الغرفة)', en: '🎁 Room Gift Box / Panel' },
  wallet: { ar: 'شاشة المحفظة', en: 'Wallet Screen' },
  level: { ar: 'شاشة المستويات', en: 'Levels Screen' },
  cp: { ar: '💑 شاشة CP', en: '💑 CP Screen' },
  miniprofile: { ar: 'الميني بروفايل', en: 'Mini Profile' },
  signin: { ar: '📅 تسجيل الدخول اليومي', en: '📅 Weekly Sign-In' },
  room: { ar: '🎙 شاشة الغرفة', en: '🎙 Room Screen' },
  discover: { ar: '🔍 شاشة الاستكشاف', en: '🔍 Discover Screen' },
  message: { ar: '💬 شاشة الرسائل', en: '💬 Messages Screen' },
  profile: { ar: '👤 شاشة حسابي', en: '👤 Me/Profile Screen' },
  chat: { ar: '✉️ شاشة المحادثة الخاصة', en: '✉️ Private Chat Screen' },
  userProfile: { ar: '🏷️ بطاقة المستخدم المصغرة', en: '🏷️ User Mini Profile Card' },
  eventInfo: { ar: '📅 تفاصيل الحدث من الداخل', en: '📅 Event Details Screen' },
  notifications: { ar: '🔔 إشعارات النظام', en: '🔔 System Notifications' },
};

const fieldLabels: Record<string, Record<string, string>> = {
  backgroundImage: { ar: 'صورة الخلفية', en: 'Background Image' },
  backgroundColor: { ar: 'لون الخلفية', en: 'Background Color' },
  cardSelectedBorderColor: { ar: 'لون إطار العنصر/الهدية المحددة', en: 'Selected Item Border Color' },
  sendBtnColor: { ar: 'لون زر الإرسال', en: 'Send Button Color' },
  sendBtnGradientStart: { ar: 'بداية تدرج زر الإرسال', en: 'Send Button Gradient Start' },
  sendBtnGradientEnd: { ar: 'نهاية تدرج زر الإرسال', en: 'Send Button Gradient End' },
  sendBtnTextColor: { ar: 'لون نص زر الإرسال', en: 'Send Button Text Color' },
  countBtnBgColor: { ar: 'لون خلفية زر تحديد العدد', en: 'Count Button Background' },
  countBtnTextColor: { ar: 'لون نص تحديد العدد', en: 'Count Button Text Color' },
  coinsTextColor: { ar: 'لون نص رصيد العملات', en: 'Coins Text Color' },
  comboIdleImage: { ar: 'صورة زر الكومبو (وضع الاستعداد والعداد 10s)', en: 'Combo Idle Button Image' },
  comboFireImage: { ar: 'صورة زر الكومبو (وضع الإطلاق والضغط)', en: 'Combo Fire Button Image' },
  durationBadgeBg: { ar: 'لون شارة مدة الـ CP (مثل 7d, 24h)', en: 'CP Duration Badge Color' },
  luckyBadgeImage: { ar: 'شارة هدية الحظ', en: 'Lucky Gift Badge' },
  starBadgeImage: { ar: 'شارة هدية النجوم', en: 'Star Gift Badge' },
  bubbleSelfBgColor: { ar: 'لون فقاعة رسائلي', en: 'Self Bubble Background Color' },
  bubbleOtherBgColor: { ar: 'لون فقاعة رسائل الطرف الآخر', en: 'Other Bubble Background Color' },
  seatDefaultCircleImage: { ar: 'صورة المقعد الدائري المفتوح', en: 'Circular Open Seat Image' },
  seatLockCircleImage: { ar: 'صورة المقعد الدائري المقفل', en: 'Circular Locked Seat Image' },
  seatDefaultClassicImage: { ar: 'صورة المقعد الكلاسيك المفتوح', en: 'Classic Open Seat Image' },
  seatLockClassicImage: { ar: 'صورة المقعد الكلاسيك المقفل', en: 'Classic Locked Seat Image' },
  seatDefaultVipImage: { ar: 'صورة مقعد الـ VIP المفتوح', en: 'VIP Open Seat Image' },
  seatLockVipImage: { ar: 'صورة مقعد الـ VIP المقفل', en: 'VIP Locked Seat Image' },
  gameBarBgColor: { ar: 'لون شريط اللعبة/الموضوع', en: 'Game/Theme Bar Background' },
  gameBarTextColor: { ar: 'لون نوع اللعبة/الموضوع', en: 'Game Type Text Color' },
  gameBarDescColor: { ar: 'لون نص إعلان الغرفة', en: 'Room Notice Text Color' },
  gameIconImage: { ar: 'أيقونة اللعبة/الموضوع', en: 'Game/Theme Icon Image' },
  exitIconImage: { ar: 'أيقونة زر إغلاق الغرفة', en: 'Room Exit Icon Image' },
  onlineCapsuleBgImage: { ar: 'خلفية كبسولة المتواجدين', en: 'Online Capsule Background Image' },
  giftIconImage: { ar: 'أيقونة زر الهدية بالأسفل', en: 'Bottom Gift Icon' },
  chatIconImage: { ar: 'أيقونة زر الشات بالأسفل', en: 'Bottom Chat Icon' },
  emojiIconImage: { ar: 'أيقونة زر الإيموجي بالأسفل', en: 'Bottom Emoji Icon' },
  micOnIconImage: { ar: 'أيقونة المايك المفتوح', en: 'Mic On Icon' },
  micOffIconImage: { ar: 'أيقونة المايك المغلق', en: 'Mic Off Icon' },
  musicIconImage: { ar: 'أيقونة زر الموسيقى', en: 'Music Icon' },
  msgIconImage: { ar: 'أيقونة زر الرسائل', en: 'Messages Icon' },
  functionIconImage: { ar: 'أيقونة زر الوظائف والمزيد', en: 'Function/More Icon' },
  userCardBgColor: { ar: 'لون خلفية بطاقة المستخدم', en: 'User Card Background Color' },
  userCardBgImage: { ar: 'صورة خلفية بطاقة المستخدم', en: 'User Card Background Image' },
  userGiftBgImage: { ar: 'خلفية شريط الهدايا المستلمة', en: 'Received Gifts Background Image' },
  userFollowIconImage: { ar: 'أيقونة زر متابعة المستخدم', en: 'User Follow Icon' },
  userChatIconImage: { ar: 'أيقونة زر محادثة المستخدم', en: 'User Chat Icon' },
  userAtIconImage: { ar: 'أيقونة زر الإشارة @ للمستخدم', en: 'User Mention @ Icon' },
  userGiftBtnImage: { ar: 'أيقونة/زر إرسال هدية للمستخدم', en: 'User Send Gift Button Image' },
  userMicDownIconImage: { ar: 'أيقونة إنزال المستخدم من المايك', en: 'Kick Down Mic Icon' },
  userMicMuteIconImage: { ar: 'أيقونة كتم مايك المستخدم', en: 'Mute User Mic Icon' },
  exitSheetBgColor: { ar: 'لون خلفية شريحة الخروج', en: 'Exit Sheet Background Color' },
  functionsPanelBgColor: { ar: 'لون لوحة الوظائف والإعدادات', en: 'Functions Panel Background Color' },
  seatPanelBgColor: { ar: 'لون خلفية لوحة شكل المقاعد', en: 'Seat Style Panel Background Color' },
  seatPanelTopBg: { ar: 'صورة الديكور العلوي للوحة المقاعد', en: 'Seat Style Panel Top Decor Image' },
  seatRadioCheckedBg: { ar: 'خلفية تبويب المقعد (محدد)', en: 'Seat Style Tab BG (Selected)' },
  seatRadioUncheckedBg: { ar: 'خلفية تبويب المقعد (غير محدد)', en: 'Seat Style Tab BG (Unselected)' },
  seatGameIcon: { ar: 'أيقونة مقاعد اللعبة', en: 'Game Seats Icon' },
  seatClassicIcon: { ar: 'أيقونة المقاعد الكلاسيكية', en: 'Classic Seats Icon' },
  seatVipIcon: { ar: 'أيقونة مقاعد VIP', en: 'VIP Seats Icon' },
  seatPreviewFrame: { ar: 'إطار معاينة المقاعد', en: 'Seat Preview Frame' },
  seatConfirmBtnStart: { ar: 'بداية تدرج زر تأكيد المقاعد', en: 'Seat Confirm Button Gradient Start' },
  seatConfirmBtnEnd: { ar: 'نهاية تدرج زر تأكيد المقاعد', en: 'Seat Confirm Button Gradient End' },
  seatConfirmBtnTextColor: { ar: 'لون نص زر تأكيد المقاعد', en: 'Seat Confirm Button Text Color' },
  funcMixerIcon: { ar: 'أيقونة الميكسر (لوحة الوظائف)', en: 'Mixer Icon (Function Panel)' },
  funcSettingsIcon: { ar: 'أيقونة إعدادات الغرفة (لوحة الوظائف)', en: 'Settings Icon (Function Panel)' },
  funcSeatStyleIcon: { ar: 'أيقونة شكل المقاعد (لوحة الوظائف)', en: 'Seat Style Icon (Function Panel)' },
  funcBgIcon: { ar: 'أيقونة خلفية الغرفة (لوحة الوظائف)', en: 'Room Background Icon (Function Panel)' },
  funcReportIcon: { ar: 'أيقونة الإبلاغ (لوحة الوظائف)', en: 'Report Icon (Function Panel)' },
  funcEffectIcon: { ar: 'أيقونة إعدادات التأثيرات (لوحة الوظائف)', en: 'Effect Settings Icon (Function Panel)' },
  funcVolumeIcon: { ar: 'أيقونة صوت الغرفة (لوحة الوظائف)', en: 'Room Volume Icon (Function Panel)' },
  funcGiftValIcon: { ar: 'أيقونة قيمة الهدية (لوحة الوظائف)', en: 'Gift Value Icon (Function Panel)' },
  settingsHeaderBg: { ar: 'خلفية هيدر إعدادات الغرفة', en: 'Room Settings Header Background' },
  settingsLabelIcon: { ar: 'أيقونة عنوان إعدادات الغرفة', en: 'Room Settings Label Icon' },
  settingsCameraIcon: { ar: 'أيقونة كاميرا صورة الغرفة', en: 'Room Camera Overlay Icon' },
  settingsConfirmBtnStart: { ar: 'بداية تدرج زر حفظ إعدادات الغرفة', en: 'Settings Confirm Button Gradient Start' },
  settingsConfirmBtnEnd: { ar: 'نهاية تدرج زر حفظ إعدادات الغرفة', en: 'Settings Confirm Button Gradient End' },
  headerBgColor: { ar: 'لون خلفية الرأس', en: 'Header Background' },
  headerBgImage: { ar: 'صورة خلفية الرأس', en: 'Header Background Image' },
  headerTextColor: { ar: 'لون نص الرأس', en: 'Header Text Color' },
  headerTextImage: { ar: 'صورة نص الرأس', en: 'Header Text Image' },
  cardBgColor: { ar: 'لون خلفية البطاقة', en: 'Card Background' },
  cardBgImage: { ar: 'صورة خلفية البطاقة', en: 'Card Background Image' },
  cardBorderColor: { ar: 'لون حدود البطاقة', en: 'Card Border Color' },
  coverHeight: { ar: 'ارتفاع غلاف المستخدم (dp - اتركه فارغاً للاتوماتيكي)', en: 'User Cover Height (dp - empty for auto)' },
  coverAspectRatio: { ar: 'نسبة عرض:ارتفاع الغلاف (افتراضي 0.45)', en: 'Cover Width:Height Ratio (default 0.45)' },
  cardBorderImage: { ar: 'صورة حدود البطاقة', en: 'Card Border Image' },
  textColor: { ar: 'لون النص', en: 'Text Color' },
  textImage: { ar: 'صورة النص', en: 'Text Image' },
  subTextColor: { ar: 'لون النص الثانوي', en: 'Sub Text Color' },
  subTextImage: { ar: 'صورة النص الثانوي', en: 'Sub Text Image' },
  accentColor: { ar: 'لون التمييز', en: 'Accent Color' },
  accentImage: { ar: 'صورة التمييز', en: 'Accent Image' },
  checkboxCheckedImage: { ar: 'صورة الاختيار (محدد)', en: 'Checked Image' },
  checkboxUncheckedImage: { ar: 'صورة الاختيار (غير محدد)', en: 'Unchecked Image' },
  tabActiveColor: { ar: 'لون التبويب النشط', en: 'Tab Active Color' },
  tabInactiveColor: { ar: 'لون التبويب غير النشط', en: 'Tab Inactive Color' },
  coinIcon: { ar: 'أيقونة العملة', en: 'Coin Icon' },
  diamondIcon: { ar: 'أيقونة الماس', en: 'Diamond Icon' },
  rankIcon: { ar: 'أيقونة الترتيب', en: 'Rank Icon' },
  memberAvatarBorder: { ar: 'حدود الصورة الرمزية', en: 'Avatar Border' },
  sectionBgColor: { ar: 'لون خلفية القسم', en: 'Section Background' },
  sectionBgImage: { ar: 'صورة خلفية القسم', en: 'Section Background Image' },
  badgeBorderColor: { ar: 'لون حدود الشارة', en: 'Badge Border Color' },
  badgeBorderImage: { ar: 'صورة حدود الشارة', en: 'Badge Border Image' },
  badgeBgColor: { ar: 'لون خلفية الشارة', en: 'Badge Background' },
  badgeBgImage: { ar: 'صورة خلفية الشارة', en: 'Badge Background Image' },
  necklaceBorderColor: { ar: 'لون حدود القلادة', en: 'Necklace Border Color' },
  necklaceBorderImage: { ar: 'صورة حدود القلادة', en: 'Necklace Border Image' },
  necklaceBgColor: { ar: 'لون خلفية القلادة', en: 'Necklace Background' },
  necklaceBgImage: { ar: 'صورة خلفية القلادة', en: 'Necklace Background Image' },
  goldColor: { ar: 'الذهبية', en: 'Gold Color' },
  silverColor: { ar: 'الفضية', en: 'Silver Color' },
  bronzeColor: { ar: 'البرونزية', en: 'Bronze Color' },
  pointsColor: { ar: 'لون النقاط', en: 'Points Color' },
  trophyIcon: { ar: 'أيقونة الكأس', en: 'Trophy Icon' },
  crownIcon: { ar: 'أيقونة التاج', en: 'Crown Icon' },
  rankBgImage: { ar: 'صورة خلفية الترتيب', en: 'Rank Background' },
  bgImage: { ar: 'صورة خلفية الشاشة بالكامل', en: 'Full Screen Background' },
  listBgImage: { ar: 'صورة خلفية القائمة (من المركز 4 فما فوق)', en: 'List Background (Rank 4+)' },
  rank1Frame: { ar: 'إطار المركز الأول', en: 'Rank 1 Frame' },
  rank2Frame: { ar: 'إطار المركز الثاني', en: 'Rank 2 Frame' },
  rank3Frame: { ar: 'إطار المركز الثالث', en: 'Rank 3 Frame' },
  rank1Banner: { ar: 'راية المركز الأول', en: 'Rank 1 Banner' },
  rank2Banner: { ar: 'راية المركز الثاني', en: 'Rank 2 Banner' },
  rank3Banner: { ar: 'راية المركز الثالث', en: 'Rank 3 Banner' },
  checkedImage: { ar: 'صورة محدد', en: 'Checked Image' },
  uncheckedImage: { ar: 'صورة غير محدد', en: 'Unchecked Image' },
  lockImage: { ar: 'صورة القفل (لم تحصل عليه)', en: 'Lock Image (Not Owned)' },
  primaryColor: { ar: 'اللون الأساسي', en: 'Primary Color' },
  gradientStart: { ar: 'بداية التدرج', en: 'Gradient Start' },
  gradientEnd: { ar: 'نهاية التدرج', en: 'Gradient End' },
  fullScreenBg: { ar: 'صورة خلفية كاملة (شاشة الكل)', en: 'Full Screen Background Image' },
  cabinBg: { ar: 'خلفية الكابينة (SVG/URL)', en: 'Cabin Background (SVG/URL)' },
  cabinDefaultBg: { ar: 'خلفية الكابينة الافتراضية (SVG)', en: 'Cabin Default Background (SVG)' },
  leftFrame: { ar: 'إطار الأفاتار الأيسر (SVG)', en: 'Left Avatar Frame (SVG)' },
  rightFrame: { ar: 'إطار الأفاتار الأيمن (SVG)', en: 'Right Avatar Frame (SVG)' },
  heartImage: { ar: 'صورة القلب في البانر (SVG/URL)', en: 'Banner Heart Image (SVG/URL)' },
  noCpHeartSvg: { ar: 'صورة القلب (بدون شريك) (SVG)', en: 'No-CP Heart Image (SVG)' },
  tokenBg: { ar: 'خلفية النقاط (SVG)', en: 'Token Background (SVG)' },
  mineBg: { ar: 'خلفية My CP (SVG)', en: 'My CP Background (SVG)' },
  countdownDaySvg: { ar: 'أيقونة الأيام (SVG)', en: 'Days Icon (SVG)' },
  countdownHourSvg: { ar: 'أيقونة الساعات (SVG)', en: 'Hours Icon (SVG)' },
  countdownMinSvg: { ar: 'أيقونة الدقائق (SVG)', en: 'Minutes Icon (SVG)' },
  countdownSecSvg: { ar: 'أيقونة الثواني (SVG)', en: 'Seconds Icon (SVG)' },
  rankTagGoldSvg: { ar: 'وسام الذهبية (SVG)', en: 'Gold Rank Tag (SVG)' },
  rankTagSilverSvg: { ar: 'وسام الفضية (SVG)', en: 'Silver Rank Tag (SVG)' },
  rankTagBronzeSvg: { ar: 'وسام البرونزية (SVG)', en: 'Bronze Rank Tag (SVG)' },
  historyCardSvg: { ar: 'خلفية بطاقة التاريخ (SVG)', en: 'History Card BG (SVG)' },
  giftsBannerSvg: { ar: 'خلفية هدايا CP (SVG)', en: 'CP Gifts Banner BG (SVG)' },
  tabBgColor: { ar: 'لون خلفية التبويب', en: 'Tab Background Color' },
  tabBgImage: { ar: 'صورة خلفية التبويب', en: 'Tab Background Image' },
  countdownTextColor: { ar: 'لون نص العد التنازلي', en: 'Countdown Text Color' },
  countdownLabelColor: { ar: 'لون تسمية العد التنازلي', en: 'Countdown Label Color' },
  invitationBgColor: { ar: 'لون خلفية دعوة CP', en: 'Invitation Background Color' },
  invitationBgImage: { ar: 'صورة خلفية دعوة CP', en: 'Invitation Background Image' },
  buttonColor: { ar: 'لون الأزرار', en: 'Button Color' },
  buttonTextColor: { ar: 'لون نص الأزرار', en: 'Button Text Color' },
  buttonOutlineColor: { ar: 'لون حدود الأزرار', en: 'Button Outline Color' },
  giftButtonGradientStart: { ar: 'بداية تدرج زر الهدية', en: 'Gift Button Gradient Start' },
  giftButtonGradientEnd: { ar: 'نهاية تدرج زر الهدية', en: 'Gift Button Gradient End' },
  sectionHeaderColor: { ar: 'لون عنوان القسم', en: 'Section Header Color' },
  avatarBorderColor: { ar: 'لون حدود الصورة الرمزية', en: 'Avatar Border Color' },
  scoreTokenColor: { ar: 'لون نص النقاط', en: 'Score Token Color' },
  scoreTokenLabelColor: { ar: 'لون تسمية النقاط', en: 'Score Token Label Color' },
  scoreTokenBgColor: { ar: 'لون خلفية النقاط', en: 'Score Token BG Color' },
  podiumBgStart: { ar: 'بداية خلفية المنصة', en: 'Podium Background Start' },
  podiumBgEnd: { ar: 'نهاية خلفية المنصة', en: 'Podium Background End' },
  periodButtonActiveBg: { ar: 'لون زر الفترة النشط', en: 'Period Button Active BG' },
  periodButtonActiveText: { ar: 'لون نص زر الفترة النشط', en: 'Period Button Active Text' },
  periodButtonInactiveBg: { ar: 'لون زر الفترة غير النشط', en: 'Period Button Inactive BG' },
  periodButtonInactiveText: { ar: 'لون نص زر الفترة غير النشط', en: 'Period Button Inactive Text' },
  rankItemBg: { ar: 'لون خلفية عنصر الترتيب', en: 'Rank Item Background' },
  rankShadowColor: { ar: 'لون ظل الترتيب', en: 'Rank Shadow Color' },
  myRankPillGradientStart: { ar: 'بداية تدرج ترتيبي', en: 'My Rank Gradient Start' },
  myRankPillGradientEnd: { ar: 'نهاية تدرج ترتيبي', en: 'My Rank Gradient End' },
  myRankPillText: { ar: 'لون نص ترتيبي', en: 'My Rank Text Color' },
  myRankScoreColor: { ar: 'لون نقاط ترتيبي', en: 'My Rank Score Color' },
  // Profile CP card fields
  profileDaysBadgeBg: { ar: 'لون خلفية شارة الأيام (البروفايل)', en: 'Profile Days Badge Background' },
  profileDaysBadgeBorder: { ar: 'لون حدود شارة الأيام (البروفايل)', en: 'Profile Days Badge Border' },
  profileDaysBadgeBg2: { ar: 'لون خلفية شارة الأيام 2 (البروفايل)', en: 'Profile Days Badge BG 2' },
  profileDaysBadgeBorder2: { ar: 'لون حدود شارة الأيام 2 (البروفايل)', en: 'Profile Days Badge Border 2' },
  profileDaysText: { ar: 'لون نص الأيام (البروفايل)', en: 'Profile Days Text Color' },
  profileDaysTogetherText: { ar: 'لون نص معاً منذ (البروفايل)', en: 'Profile "Together Since" Text' },
  profileLevelGradientStart: { ar: 'بداية تدرج مستوى CP (البروفايل)', en: 'Profile CP Level Gradient Start' },
  profileLevelGradientEnd: { ar: 'نهاية تدرج مستوى CP (البروفايل)', en: 'Profile CP Level Gradient End' },
  profileHeartIcon: { ar: 'أيقونة قلب CP (البروفايل)', en: 'Profile CP Heart Icon' },
  profileLevelBg: { ar: 'خلفية مستوى CP (البروفايل)', en: 'Profile CP Level Background' },
  profileNameFrame: { ar: 'إطار اسم CP (البروفايل)', en: 'Profile CP Name Frame' },
  profileTopBgSvga: { ar: 'SVGA خلفية CP العلوية (البروفايل)', en: 'Profile CP Top BG SVGA' },
  buttonGradientStart: { ar: 'بداية تدرج الزر', en: 'Button Gradient Start' },
  buttonGradientEnd: { ar: 'نهاية تدرج الزر', en: 'Button Gradient End' },
  dayBgColor: { ar: 'لون خلفية الخلية (متاح)', en: 'Day Cell BG (Available)' },
  dayActiveColor: { ar: 'لون خلفية الخلية (اليوم)', en: 'Day Cell BG (Today)' },
  dayClaimedColor: { ar: 'لون خلفية الخلية (تم)', en: 'Day Cell BG (Claimed)' },
  dayLockedColor: { ar: 'لون خلفية الخلية (مقفل)', en: 'Day Cell BG (Locked)' },
  dayBorderColor: { ar: 'لون حدود الخلية', en: 'Day Cell Border Color' },
  dayClaimedBorderColor: { ar: 'لون حدود الخلية (تم)', en: 'Day Cell Border (Claimed)' },
  checkmarkImage: { ar: 'صورة علامة التسجيل', en: 'Checkmark Image' },
  streakIcon: { ar: 'أيقونة السلسلة', en: 'Streak Icon' },
  topBgSvga: { ar: 'SVGA الخلفية العلوية', en: 'Top BG SVGA' },
  buttonImage: { ar: 'صورة زر التسجيل', en: 'Sign-In Button Image' },
  bannerBgGradientStart: { ar: 'بداية تدرج لون البانر', en: 'Banner Gradient Start' },
  bannerBgGradientMid: { ar: 'منتصف تدرج لون البانر', en: 'Banner Gradient Mid' },
  bannerBgGradientEnd: { ar: 'نهاية تدرج لون البانر', en: 'Banner Gradient End' },
  bannerTextColor: { ar: 'لون نصوص البانر', en: 'Banner Text Color' },
  badgeTextColor: { ar: 'لون نص وسام الحدث', en: 'Event Badge Text Color' },
  progressFillStart: { ar: 'بداية لون شريط التقدم', en: 'Progress Bar Fill Start' },
  progressFillEnd: { ar: 'نهاية لون شريط التقدم', en: 'Progress Bar Fill End' },
};

const imageFields = ['bgImage', 'listBgImage', 'rank1Frame', 'rank2Frame', 'rank3Frame', 'rank1Banner', 'rank2Banner', 'rank3Banner', 'backgroundImage', 'checkboxCheckedImage', 'checkboxUncheckedImage', 'coinIcon', 'diamondIcon', 'rankIcon', 'crownIcon', 'rankBgImage', 'checkedImage', 'uncheckedImage', 'cardBgImage', 'sectionBgImage', 'badgeBgImage', 'necklaceBgImage', 'headerBgImage', 'headerTextImage', 'cardBorderImage', 'textImage', 'subTextImage', 'accentImage', 'badgeBorderImage', 'necklaceBorderImage', 'lockImage', 'fullScreenBg', 'cabinBg', 'cabinDefaultBg', 'leftFrame', 'rightFrame', 'heartImage', 'noCpHeartSvg', 'tokenBg', 'mineBg', 'tabBgImage', 'invitationBgImage', 'countdownDaySvg', 'countdownHourSvg', 'countdownMinSvg', 'countdownSecSvg', 'rankTagGoldSvg', 'rankTagSilverSvg', 'rankTagBronzeSvg', 'historyCardSvg', 'giftsBannerSvg', 'profileHeartIcon', 'profileLevelBg', 'profileNameFrame', 'profileTopBgSvga', 'checkmarkImage', 'streakIcon', 'topBgSvga', 'buttonImage', 'seatDefaultCircleImage', 'seatLockCircleImage', 'seatDefaultClassicImage', 'seatLockClassicImage', 'seatDefaultVipImage', 'seatLockVipImage', 'gameIconImage', 'exitIconImage', 'onlineCapsuleBgImage', 'giftIconImage', 'chatIconImage', 'emojiIconImage', 'micOnIconImage', 'micOffIconImage', 'musicIconImage', 'msgIconImage', 'functionIconImage', 'userCardBgImage', 'userGiftBgImage', 'userFollowIconImage', 'userChatIconImage', 'userAtIconImage', 'userGiftBtnImage', 'userMicDownIconImage', 'userMicMuteIconImage', 'seatPanelTopBg', 'seatRadioCheckedBg', 'seatRadioUncheckedBg', 'seatGameIcon', 'seatClassicIcon', 'seatVipIcon', 'seatPreviewFrame', 'funcMixerIcon', 'funcSettingsIcon', 'funcSeatStyleIcon', 'funcBgIcon', 'funcReportIcon', 'funcEffectIcon', 'funcVolumeIcon', 'funcGiftValIcon', 'settingsHeaderBg', 'settingsLabelIcon', 'settingsCameraIcon'];

const colorRegex = /^(bg|header|text|card|border|accent|tab|gold|silver|bronze|points|section|badge|necklace|member|primary|gradient|countdown|invitation|button|avatar|score|period|rank|shadow|Color)/i;

function isColorField(field: string): boolean {
  return colorRegex.test(field) && !imageFields.includes(field);
}

export default function ScreenCustomizationPage() {
  const { t, lang } = useContext(I18nContext);
  const [activeTab, setActiveTab] = useState<string>('agency');
  const [visuals, setVisuals] = useState<ScreenVisuals>(defaultVisuals);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState('');

  useEffect(() => {
    (async () => {
      try {
        const cfg = await getAppConfig();
        const stored = cfg?.screenVisuals;
        if (stored && typeof stored === 'object') {
          const merged: ScreenVisuals = { ...defaultVisuals };
          for (const screen of screenTabs) {
            if (stored[screen] && typeof stored[screen] === 'object') {
              merged[screen] = { ...defaultVisuals[screen], ...stored[screen] };
            }
          }
          setVisuals(merged);
        }
      } catch (e) { console.warn(e); }
      setLoading(false);
    })();
  }, []);

  const showMsg = (text: string) => { setMsg(text); setTimeout(() => setMsg(''), 3000); };

  const updateField = (screen: string, field: string, value: string) => {
    setVisuals(prev => ({
      ...prev,
      [screen]: { ...prev[screen as keyof ScreenVisuals], [field]: value },
    }));
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      const clean: ScreenVisuals = { ...defaultVisuals };
      for (const screen of screenTabs) {
        clean[screen] = {};
        for (const [key, val] of Object.entries(visuals[screen])) {
          if (val && val.trim()) clean[screen][key] = val.trim();
        }
      }
      await updateAppConfig({ screenVisuals: clean } as any);
      showMsg(lang === 'ar' ? 'تم الحفظ!' : 'Saved!');
    } catch (e) {
      showMsg(lang === 'ar' ? 'فشل الحفظ' : 'Save failed');
      console.warn(e);
    }
    setSaving(false);
  };

  const handleReset = () => {
    if (confirm(lang === 'ar' ? 'إعادة تعيين جميع الإعدادات؟' : 'Reset all visuals?')) {
      setVisuals(defaultVisuals);
      handleSave();
    }
  };

  const handleImageUpload = async (file: File, screen: string, field: string) => {
    try {
      const path = `screen_visuals/${screen}_${field}_${Date.now()}`;
      const url = await uploadAppAsset(file, path);
      if (url) updateField(screen, field, url);
    } catch (e) {
      showMsg(lang === 'ar' ? 'فشل رفع الصورة' : 'Upload failed');
    }
  };

  if (loading) return <div className="text-slate-400 text-sm p-6">{t('loading')}</div>;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-white text-lg font-semibold">
          {lang === 'ar' ? 'تخصيص الشاشات' : 'Screen Customization'}
        </h2>
        <div className="flex gap-2">
          <button onClick={handleReset} className="px-3 py-1.5 bg-rose-600/20 hover:bg-rose-600/30 text-rose-400 text-xs font-semibold rounded-lg flex items-center gap-1">
            <RotateCcw className="w-3.5 h-3.5" /> {lang === 'ar' ? 'إعادة تعيين' : 'Reset'}
          </button>
          <button onClick={handleSave} disabled={saving} className="px-3 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1">
            <Save className="w-3.5 h-3.5" /> {saving ? t('saving') : t('save')}
          </button>
        </div>
      </div>

      {msg && <div className="bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs px-4 py-2 rounded-lg">{msg}</div>}

      <div className="flex gap-1 border-b border-white/5 overflow-x-auto">
        {screenTabs.map(s => (
          <button
            key={s}
            onClick={() => setActiveTab(s)}
            className={`px-3 py-2 text-xs font-medium whitespace-nowrap border-b-2 transition-all ${
              activeTab === s
                ? 'text-indigo-300 border-indigo-500'
                : 'text-slate-400 border-transparent hover:text-white'
            }`}
          >
            {lang === 'ar' ? screenLabels[s].ar : screenLabels[s].en}
          </button>
        ))}
      </div>

      <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-4">
        {Object.entries(visuals[activeTab as keyof ScreenVisuals] || {}).map(([field, value]) => {
          const label = fieldLabels[field]?.[lang === 'ar' ? 'ar' : 'en'] || field;
          const isImg = imageFields.includes(field);
          const isColor = isColorField(field);

          return (
            <div key={field}>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{label}</label>
              <div className="flex gap-2 items-start">
                <input
                  type={isColor ? 'color' : 'text'}
                  value={isColor ? to6Hex(value || '') : value || ''}
                  onChange={e => updateField(activeTab, field, e.target.value)}
                  className={`${isColor ? 'w-10 h-10 p-0.5' : 'flex-1'} bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white`}
                />
                {isImg && (
                  <label className="cursor-pointer px-2 py-1.5 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-400 rounded-lg">
                    <Upload className="w-3.5 h-3.5" />
                    <input type="file" accept="image/*,.svga,.mp4,.gif,.vap,.json,.webp,.mp3,.wav,.lottie" className="hidden" onChange={e => {
                      const file = e.target.files?.[0];
                      if (file) handleImageUpload(file, activeTab, field);
                    }} />
                  </label>
                )}
              </div>
              {isImg && value && (
                value.endsWith('.mp4') || value.endsWith('.webm') ? (
                  <video src={value} className="mt-1 w-16 h-16 object-contain rounded border border-white/5" controls />
                ) : value.endsWith('.mp3') || value.endsWith('.wav') ? (
                  <audio src={value} className="mt-1 w-full h-8" controls />
                ) : (
                  <img src={value} alt={label} className="mt-1 w-16 h-16 object-contain rounded border border-white/5" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} />
                )
              )}
            </div>
          );
        })}
      </div>

      {/* Preview */}
      <div className="bg-[#141417] rounded-2xl border border-white/5 p-6">
        <h3 className="text-white text-sm font-semibold mb-3">{lang === 'ar' ? 'معاينة' : 'Preview'}</h3>
        <div
          className="rounded-xl p-4 space-y-3"
          style={{
            background: visuals[activeTab as keyof ScreenVisuals]?.backgroundImage
              ? `url(${visuals[activeTab as keyof ScreenVisuals]?.backgroundImage}) center/cover no-repeat`
              : visuals[activeTab as keyof ScreenVisuals]?.headerBgColor || '#1a1a2e',
            color: visuals[activeTab as keyof ScreenVisuals]?.textColor || '#fff',
          }}
        >
          <div
            className="rounded-lg p-3"
            style={{
              background: visuals[activeTab as keyof ScreenVisuals]?.cardBgColor || '#16213e',
              border: `1px solid ${visuals[activeTab as keyof ScreenVisuals]?.cardBorderColor || '#0f3460'}`,
            }}
          >
            <p style={{ color: visuals[activeTab as keyof ScreenVisuals]?.accentColor || '#e94560' }}>
              {activeTab === 'rechargeEvent' ? (lang === 'ar' ? '⚡ حدث الشحن الأسطوري' : '⚡ Recharge Event') :
               activeTab === 'badges' ? (lang === 'ar' ? 'الشارات' : 'Badges') :
               activeTab === 'necklaces' ? (lang === 'ar' ? 'القلائد' : 'Necklaces') :
               activeTab === 'rank' ? (lang === 'ar' ? 'الترتيب' : 'Rank') :
               activeTab === 'checkbox' ? (lang === 'ar' ? 'الاختيار' : 'Checkbox') :
               activeTab === 'store' ? (lang === 'ar' ? 'المتجر' : 'Store') :
               activeTab === 'backpack' ? (lang === 'ar' ? 'الحقيبة' : 'Backpack') :
               activeTab === 'wallet' ? (lang === 'ar' ? 'المحفظة' : 'Wallet') :
               activeTab === 'level' ? (lang === 'ar' ? 'المستويات' : 'Levels') :
               activeTab === 'cp' ? (lang === 'ar' ? '💑 CP' : '💑 CP') :
               activeTab === 'miniprofile' ? (lang === 'ar' ? 'الميني بروفايل' : 'Mini Profile') :
               activeTab === 'signin' ? (lang === 'ar' ? '📅 تسجيل الدخول' : '📅 Weekly Sign-In') :
                (lang === 'ar' ? 'الوكالة' : 'Agency')}
            </p>
            <p className="text-xs mt-1" style={{ color: visuals[activeTab as keyof ScreenVisuals]?.subTextColor || '#a0a0b0' }}>
              {lang === 'ar' ? 'نموذج توضيحي للمعاينة' : 'Sample preview text'}
            </p>
          </div>
          <div className="flex items-center gap-2 mt-2">
            <div className="w-5 h-5 rounded border flex items-center justify-center text-[8px] bg-white/10">✓</div>
            <span className="text-xs">{lang === 'ar' ? 'محدد' : 'Checked'}</span>
            <div className="w-5 h-5 rounded border flex items-center justify-center text-[8px] bg-white/5"></div>
            <span className="text-xs">{lang === 'ar' ? 'غير محدد' : 'Unchecked'}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
