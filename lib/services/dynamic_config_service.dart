import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart' show Restart;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../models/app_asset_model.dart';
import '../config/app_config.dart';

class DynamicConfigService extends ChangeNotifier {
  static final DynamicConfigService _instance = DynamicConfigService._();
  static DynamicConfigService get instance => _instance;
  factory DynamicConfigService() => _instance;
  DynamicConfigService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription? _authSub;
  
  // App Configurations
  String _appName = 'Zero';
  String _logoUrl = '';
  String _splashUrl = '';
  bool _splashEnabled = false;
  String _splashImageUrl = '';
  String _splashSvgaUrl = '';
  int _splashDurationSeconds = 3;
  Color _splashNameColor = const Color(0xFF16151A);
  String _splashActionType = '';
  String _splashActionValue = '';

  // Mini Profile overrides
  String _miniProfileFollowIcon = '';
  String _miniProfileMessageIcon = '';

  // VIP global asset overrides
  String _vipCardBgImgUrl = '';
  String _vipPurchaseBarImgUrl = '';
  String _vipCoinImgUrl = '';
  String _vipBuyBtnImgUrl = '';
  
  // Theme colors
  Color _primaryBg = const Color(0xFFFFFFFF);
  Color _textPrimary = const Color(0xFF16151A);
  Color _textSecondary = const Color(0xFF9BA1B6);
  Color _goldColor = const Color(0xFFDE880F);
  Color _buttonColor = const Color(0xFF6366F1);
  Color _buttonTextColor = const Color(0xFFFFFFFF);
  Color _headerColor = const Color(0xFFFFFFFF);
  Color _tabBarColor = const Color(0xFFFFFFFF);
  
  // Bottom Navigation Bar
  String _bottomNavBgImage = '';
  Color _bottomNavGradientStart = const Color(0xFFF4DDA9);
  Color _bottomNavGradientEnd = const Color(0xFFFFFFFF);
  Color _bottomNavActiveTextColor = const Color(0xFF894916);
  Color _bottomNavInactiveTextColor = const Color(0xFF894916);
  
  // Gift Panel Overrides
  String _giftPanelBgImage = '';
  String _giftPanelHeaderBgImage = '';
  Color _giftPanelBgColor = const Color(0xF51D1111);
  Color _giftPanelTabColor = const Color(0xFFDE880F);

  // Typography & Shape
  String _fontFamily = 'system';
  int _borderRadius = 8;
  
  // Tab/Page names
  String _discoverTitle = 'استكشاف';
  String _messageTitle = 'الرسائل';
  String _profileTitle = 'حسابي';
  Map<String, String> _screenTitles = {};
  
  // CP WebView URL
  String _cpWebUrl = 'https://app.ayomet.com/cp.html';

  // Audio configurations
  String _audioCompany = 'agora'; // Updated to use Agora
  final int _zegoAppId = 1614503125;
  final String _agoraAppId = 'eb1f5fe3800f430582a3e07140c27143';
  final String _agoraToken = '';
  
  // Easemob (Chat) configurations
  final String _easemobAppKey = '61200033730#200046947';
  final String _easemobOrgName = '61200033730';
  final String _easemobAppName = '200046947';
  final String _easemobWsUrl = 'msync-api-61.chat.agora.io';
  final String _easemobRestUrl = 'a61.chat.agora.io';
  final String _easemobPrimaryCert = '164d7c36fcd2494ca22a64539be1afb8';
  final String _easemobSecondaryCert = 'd40ad1b7130241c9968b17e776cd4642';

  // Assets override map (from app_config)
  Map<String, String> _assetsOverride = {};

  // App assets from app_assets table (primary source for remote_url)
  Map<String, AppAssetModel> _appAssets = {};

  // Assets size overrides: { "assets_mipmap-xxhdpi_xxx_webp": {"width": 100, "height": 200} }
  Map<String, Map<String, dynamic>> _assetSizes = {};

  // Raw config map for dynamic access
  final Map<String, dynamic> _rawConfig = {};

  // Last System message
  Map<String, dynamic> _lastSystemMessage = {};

  // VIP card colors
  Color _vipCardBgColor = const Color(0xFF1A3D1A);
  Color _vipCardBorderColor = const Color(0xFFC9A84C);

  // Level config
  int _coinsPerRechargeXp = 10;

  // Diamond-to-coin exchange rate (e.g. 2 means 2 diamonds = 1 coin)
  int _diamondToCoinRate = 2;
  int _roomBgPrice = 100;

  // Room theme gradients (from app_config.roomGradients)
  Map<String, List<Color>> _roomGradients = {};
  Map<String, String> _roomBgImages = {};
  Map<String, String> _globalImages = {};

  // Chat bubble colors (from app_config.chatColors)
  Color _chatBubbleSelf = const Color(0x33FFC525);
  Color _chatBubbleOther = const Color(0x1AFFFFFF);
  Color _chatBubbleSelfBorder = const Color(0x33FFC525);
  Color _chatBubbleOtherBorder = const Color(0x1AFFFFFF);
  Color _chatBubbleSelfText = const Color(0xFFFFC525);
  Color _chatBubbleOtherText = const Color(0xFFFFFFFF);

  // Screen visuals config (from app_config.screenVisuals)
  Map<String, dynamic> _screenVisuals = {};

  // Icon overrides: { "Icons.close": "https://cloudinary.url/close.svga", ... }
  Map<String, String> _iconOverrides = {};

  // Ranking screen config
  String get globalRankBg => _screenStr('rank', 'bgImage', '');
  String get globalRank1Frame => _screenStr('rank', 'rank1Frame', '');
  String get globalRank2Frame => _screenStr('rank', 'rank2Frame', '');
  String get globalRank3Frame => _screenStr('rank', 'rank3Frame', '');
  String get globalRank1Banner => _screenStr('rank', 'rank1Banner', '');
  String get globalRank2Banner => _screenStr('rank', 'rank2Banner', '');
  String get globalRank3Banner => _screenStr('rank', 'rank3Banner', '');
  String get globalRankListBg => _screenStr('rank', 'listBgImage', '');
  String get globalRankMainTabBg => _screenStr('rank', 'mainTabBgImage', '');
  String get globalRankMainTabIndicator => _screenStr('rank', 'mainTabIndicatorImage', '');
  Color get globalRankMainTabTextColor => _screenColor('rank', 'mainTabTextColor', const Color(0xFFFFD54F));
  String get globalRankSubTabBg => _screenStr('rank', 'subTabBgImage', '');
  String get globalRankSubTabIndicator => _screenStr('rank', 'subTabIndicatorImage', '');
  Color get globalRankSubTabTextColor => _screenColor('rank', 'subTabTextColor', const Color(0xFF000000));
  String _rankBg = '';
  String _rankGoldColor = '#FFD700';
  String _rankSilverColor = '#C0C0C0';
  String _rankBronzeColor = '#CD7F32';
  String _rankPointsColor = '#FFD700';
  String _rankTrophyIcon = 'emoji_events';
  String _rankEmptyText = 'No rankings yet';
  String _rankTextColor = '#FFFFFF';
  String _rankSubTextColor = '#FFFFFF99';

  // Per-category ranking configs
  final Map<String, Map<String, String>> _rankCategoryConfigs = {};

  Color rankGoldColorFor(String category) {
    final cat = _rankCategoryConfigs[category];
    if (cat != null && cat['goldColor'] != null) return _parseColor(cat['goldColor']!, const Color(0xFFFFD700));
    return _parseColor(_rankGoldColor, const Color(0xFFFFD700));
  }
  Color rankSilverColorFor(String category) {
    final cat = _rankCategoryConfigs[category];
    if (cat != null && cat['silverColor'] != null) return _parseColor(cat['silverColor']!, const Color(0xFFC0C0C0));
    return _parseColor(_rankSilverColor, const Color(0xFFC0C0C0));
  }
  Color rankBronzeColorFor(String category) {
    final cat = _rankCategoryConfigs[category];
    if (cat != null && cat['bronzeColor'] != null) return _parseColor(cat['bronzeColor']!, const Color(0xFFCD7F32));
    return _parseColor(_rankBronzeColor, const Color(0xFFCD7F32));
  }
  Color rankPointsColorFor(String category) {
    final cat = _rankCategoryConfigs[category];
    if (cat != null && cat['pointsColor'] != null) return _parseColor(cat['pointsColor']!, const Color(0xFFFFD700));
    return _parseColor(_rankPointsColor, const Color(0xFFFFD700));
  }
  Color rankTextColorFor(String category) {
    final cat = _rankCategoryConfigs[category];
    if (cat != null && cat['textColor'] != null) return _parseColor(cat['textColor']!, Colors.white);
    return _parseColor(_rankTextColor, Colors.white);
  }
  Color rankSubTextColorFor(String category) {
    final cat = _rankCategoryConfigs[category];
    if (cat != null && cat['subTextColor'] != null) return _parseColor(cat['subTextColor']!, Colors.white60);
    return _parseColor(_rankSubTextColor, Colors.white60);
  }
  String rankBgFor(String category) {
    final cat = _rankCategoryConfigs[category];
    if (cat != null && cat['bg'] != null && cat['bg']!.isNotEmpty) return cat['bg']!;
    return _rankBg;
  }

  // Getters (kept for backwards compatibility)
  String get rankBg => _rankBg;
  Color get rankGoldColor => _parseColor(_rankGoldColor, const Color(0xFFFFD700));
  Color get rankSilverColor => _parseColor(_rankSilverColor, const Color(0xFFC0C0C0));
  Color get rankBronzeColor => _parseColor(_rankBronzeColor, const Color(0xFFCD7F32));
  Color get rankPointsColor => _parseColor(_rankPointsColor, const Color(0xFFFFD700));
  String get rankTrophyIcon => _rankTrophyIcon;
  String get rankEmptyText => _rankEmptyText;
  Color get rankTextColor => _parseColor(_rankTextColor, Colors.white);
  Color get rankSubTextColor => _parseColor(_rankSubTextColor, Colors.white60);

  // Mini Profile Visuals
  String get miniprofileBgImage => _screenStr('userProfile', 'backgroundImage', _rawConfig['userProfile']?['backgroundImage']?.toString() ?? '');
  String get miniprofileCardFrameImg => _screenStr('userProfile', 'cardFrameImg', _rawConfig['userProfile']?['cardFrameImg']?.toString() ?? '');
  Color get miniprofileBgColor => _screenColor('userProfile', 'backgroundColor', const Color(0xFF16141D));
  Color get miniprofileBorderColor => _screenColor('userProfile', 'borderColor', const Color(0xFF382F24));
  Color get miniprofileTextColor => _screenColor('userProfile', 'textColor', Colors.white);
  Color get miniprofileSubTextColor => _screenColor('userProfile', 'subTextColor', const Color(0xFF9BA1B6));
  Color get miniprofileButtonColor => _screenColor('userProfile', 'buttonColor', const Color(0xFFE8BD56));
  String get miniprofileGiftBarBg => _screenStr('userProfile', 'giftBarBg', _rawConfig['userProfile']?['giftBarBg']?.toString() ?? '');
  String get miniprofileGiftBarBorderImg => _screenStr('userProfile', 'giftBarBorderImg', _rawConfig['userProfile']?['giftBarBorderImg']?.toString() ?? '');
  Color get miniprofileGiftBarBorder => _screenColor('userProfile', 'giftBarBorder', const Color(0xFF5E4321));
  String get miniprofileHostBadgeImg => _screenStr('userProfile', 'hostBadgeImg', _rawConfig['userProfile']?['hostBadgeImg']?.toString() ?? '');
  Color get miniprofileHostBadgeBg => _screenColor('userProfile', 'hostBadgeBg', const Color(0xFF1E5BB5));
  String get miniprofileAgentBadgeImg => _screenStr('userProfile', 'agentBadgeImg', _rawConfig['userProfile']?['agentBadgeImg']?.toString() ?? '');
  Color get miniprofileAgentBadgeBg => _screenColor('userProfile', 'agentBadgeBg', const Color(0xFF8E24AA));
  String get miniprofileIntimateCardBg => _screenStr('userProfile', 'intimateCardBg', _rawConfig['userProfile']?['intimateCardBg']?.toString() ?? '');
  String get miniprofileFamilyCardBg => _screenStr('userProfile', 'familyCardBg', _rawConfig['userProfile']?['familyCardBg']?.toString() ?? '');
  String get miniprofileSupportersBanner => _screenStr('userProfile', 'supportersBanner', _rawConfig['userProfile']?['supportersBanner']?.toString() ?? '');
  String get miniprofileSupporterSlot => _screenStr('userProfile', 'supporterSlot', _rawConfig['userProfile']?['supporterSlot']?.toString() ?? '');
  String get miniprofileGoldCrown => _screenStr('userProfile', 'goldCrown', _rawConfig['userProfile']?['goldCrown']?.toString() ?? '');
  String get miniprofileSilverCrown => _screenStr('userProfile', 'silverCrown', _rawConfig['userProfile']?['silverCrown']?.toString() ?? '');
  String get miniprofileBronzeCrown => _screenStr('userProfile', 'bronzeCrown', _rawConfig['userProfile']?['bronzeCrown']?.toString() ?? '');
  String get miniprofileIdentityTitleImg => _screenStr('userProfile', 'identityTitleImg', _rawConfig['userProfile']?['identityTitleImg']?.toString() ?? '');
  String get miniprofileBadgesTitleImg => _screenStr('userProfile', 'badgesTitleImg', _rawConfig['userProfile']?['badgesTitleImg']?.toString() ?? '');
  String get miniprofileAchievementsTitleImg => _screenStr('userProfile', 'achievementsTitleImg', _rawConfig['userProfile']?['achievementsTitleImg']?.toString() ?? '');
  
  // Profile Icons & Button Backgrounds
  String get miniprofileFollowIcon => _screenStr('userProfile', 'profileFollowIcon', _rawConfig['userProfile']?['profileFollowIcon']?.toString() ?? '');
  String get miniprofileChatIcon => _screenStr('userProfile', 'profileChatIcon', _rawConfig['userProfile']?['profileChatIcon']?.toString() ?? '');
  String get miniprofileGiftIcon => _screenStr('userProfile', 'profileGiftIcon', _rawConfig['userProfile']?['profileGiftIcon']?.toString() ?? '');
  String get miniprofileReportIcon => _screenStr('userProfile', 'profileReportIcon', _rawConfig['userProfile']?['profileReportIcon']?.toString() ?? '');
  String get miniprofileEditIcon => _screenStr('userProfile', 'profileEditIcon', _rawConfig['userProfile']?['profileEditIcon']?.toString() ?? '');
  String get miniprofileMentionIcon => _screenStr('userProfile', 'profileMentionIcon', _rawConfig['userProfile']?['profileMentionIcon']?.toString() ?? '');
  String get miniprofileMoreIcon => _screenStr('userProfile', 'profileMoreIcon', _rawConfig['userProfile']?['profileMoreIcon']?.toString() ?? '');
  String get miniprofileGiftBtnBg => _screenStr('userProfile', 'giftBtnBg', _rawConfig['userProfile']?['giftBtnBg']?.toString() ?? '');
  String get miniprofileMentionBtnBg => _screenStr('userProfile', 'mentionBtnBg', _rawConfig['userProfile']?['mentionBtnBg']?.toString() ?? '');
  String get miniprofileChatBtnBg => _screenStr('userProfile', 'chatBtnBg', _rawConfig['userProfile']?['chatBtnBg']?.toString() ?? '');
  String get miniprofileFollowBtnBg => _screenStr('userProfile', 'followBtnBg', _rawConfig['userProfile']?['followBtnBg']?.toString() ?? '');

  // Full User Profile Screen Visuals (from Admin Dashboard)
  String get fullProfileBgImage => _screenStr('fullProfile', 'backgroundImage', miniprofileBgImage);
  Color get fullProfileBgColor => _screenColor('fullProfile', 'backgroundColor', const Color(0xFF16151A));
  Color get fullProfileTextColor => _screenColor('fullProfile', 'textColor', Colors.white);
  Color get fullProfileSubTextColor => _screenColor('fullProfile', 'subTextColor', const Color(0xFF9BA1B6));
  String get fullProfileIntimateCardBg => _screenStr('fullProfile', 'intimateCardBg', miniprofileIntimateCardBg);
  String get fullProfileFamilyCardBg => _screenStr('fullProfile', 'familyCardBg', miniprofileFamilyCardBg);
  String get fullProfileSupportersBanner => _screenStr('fullProfile', 'supportersBanner', miniprofileSupportersBanner);
  String get fullProfileSupporterSlot => _screenStr('fullProfile', 'supporterSlot', miniprofileSupporterSlot);
  String get fullProfileGoldCrown => _screenStr('fullProfile', 'goldCrown', miniprofileGoldCrown);
  String get fullProfileSilverCrown => _screenStr('fullProfile', 'silverCrown', miniprofileSilverCrown);
  String get fullProfileBronzeCrown => _screenStr('fullProfile', 'bronzeCrown', miniprofileBronzeCrown);
  String get fullProfileIdentityTitleImg => _screenStr('fullProfile', 'identityTitleImg', miniprofileIdentityTitleImg);
  String get fullProfileBadgesTitleImg => _screenStr('fullProfile', 'badgesTitleImg', miniprofileBadgesTitleImg);
  String get fullProfileAchievementsTitleImg => _screenStr('fullProfile', 'achievementsTitleImg', miniprofileAchievementsTitleImg);
  String get fullProfileFollowIcon => _screenStr('fullProfile', 'profileFollowIcon', miniprofileFollowIcon);
  String get fullProfileChatIcon => _screenStr('fullProfile', 'profileChatIcon', miniprofileChatIcon);
  String get fullProfileGiftIcon => _screenStr('fullProfile', 'profileGiftIcon', miniprofileGiftIcon);
  String get fullProfileReportIcon => _screenStr('fullProfile', 'profileReportIcon', miniprofileReportIcon);
  String get fullProfileEditIcon => _screenStr('fullProfile', 'profileEditIcon', miniprofileEditIcon);

  // Achievements Cards (جدار الهدايا، مركبة، إطار)
  String get fullProfileGiftWallCardBg => _screenStr('fullProfile', 'giftWallCardBg', _screenStr('userProfile', 'giftWallCardBg', ''));
  Color get fullProfileGiftWallCardBorder => _screenColor('fullProfile', 'giftWallCardBorder', const Color(0x1AFFFFFF));
  String get fullProfileGiftWallIcon => _screenStr('fullProfile', 'giftWallIcon', _screenStr('userProfile', 'giftWallIcon', ''));

  String get fullProfileVehicleCardBg => _screenStr('fullProfile', 'vehicleCardBg', _screenStr('userProfile', 'vehicleCardBg', ''));
  Color get fullProfileVehicleCardBorder => _screenColor('fullProfile', 'vehicleCardBorder', const Color(0x1AFFFFFF));
  String get fullProfileVehicleIcon => _screenStr('fullProfile', 'vehicleIcon', _screenStr('userProfile', 'vehicleIcon', ''));

  String get fullProfileFrameCardBg => _screenStr('fullProfile', 'frameCardBg', _screenStr('userProfile', 'frameCardBg', ''));
  Color get fullProfileFrameCardBorder => _screenColor('fullProfile', 'frameCardBorder', const Color(0x1AFFFFFF));
  String get fullProfileFrameIcon => _screenStr('fullProfile', 'frameIcon', _screenStr('userProfile', 'frameIcon', ''));

  // ── Full Profile: Data Panel & Stats (الزوار، المعجبون، المتابعون، الهدايا، المرسلة) ──
  String get fullProfileDataPanelBg => _screenStr('fullProfile', 'dataPanelBg', _screenStr('userProfile', 'dataPanelBg', ''));
  String get fullProfileDataPanelDivider => _screenStr('fullProfile', 'dataPanelDivider', _screenStr('userProfile', 'dataPanelDivider', ''));
  Color get fullProfileDataCountColor => _screenColor('fullProfile', 'dataCountColor', Colors.white);
  Color get fullProfileDataLabelColor => _screenColor('fullProfile', 'dataLabelColor', const Color(0xFF6DE5FF));
  String get fullProfileVisitorsImage => _screenStr('fullProfile', 'visitorsImage', '');
  String get fullProfileFansImage => _screenStr('fullProfile', 'fansImage', '');
  String get fullProfileFollowersImage => _screenStr('fullProfile', 'followersImage', '');
  String get fullProfileGiftsImage => _screenStr('fullProfile', 'giftsImage', '');
  String get fullProfileSentGiftsImage => _screenStr('fullProfile', 'sentGiftsImage', '');

  // ── Full Profile: CP Card & Relationship (كرت الارتباط وخواتم الـ SVGA) ──
  String get fullProfileCpCardBg => _screenStr('fullProfile', 'cpCardBg', _screenStr('userProfile', 'cpCardBg', ''));
  Color get fullProfileCpCardBorder => _screenColor('fullProfile', 'cpCardBorder', const Color(0xFFDE880F));
  String get fullProfileCpRingSvga => _screenStr('fullProfile', 'cpRingSvga', _screenStr('userProfile', 'cpRingSvga', ''));
  String get fullProfileCpRing2Svga => _screenStr('fullProfile', 'cpRing2Svga', _screenStr('userProfile', 'cpRing2Svga', ''));
  String get fullProfileCpRing3Svga => _screenStr('fullProfile', 'cpRing3Svga', _screenStr('userProfile', 'cpRing3Svga', ''));
  String get fullProfileCpMidDecorImage => _screenStr('fullProfile', 'cpMidDecorImage', _screenStr('userProfile', 'cpMidDecorImage', ''));
  String get fullProfileCpDaysBg => _screenStr('fullProfile', 'cpDaysBg', _screenStr('userProfile', 'cpDaysBg', ''));
  String get fullProfileCpAddIcon => _screenStr('fullProfile', 'cpAddIcon', _screenStr('userProfile', 'cpAddIcon', ''));

  // ── Full Profile: Medals & Tabs ──
  String get fullProfileMedalsCardBg => _screenStr('fullProfile', 'medalsCardBg', _screenStr('userProfile', 'medalsCardBg', ''));
  Color get fullProfileMedalsCardBorder => _screenColor('fullProfile', 'medalsCardBorder', const Color(0x26DE880F));
  Color get fullProfileTabActiveColor => _screenColor('fullProfile', 'tabActiveColor', const Color(0xFF00E5C9));
  Color get fullProfileTabInactiveColor => _screenColor('fullProfile', 'tabInactiveColor', Colors.white60);

  // Agency & Host SVGA Necklaces (Comprehensive multi-key fallback from control panel)
  String get agencyLeaderNecklaceSvga {
    final v = _screenStr('agency', 'leaderNecklaceSvga',
        _screenStr('agency', 'agentNecklaceSvga',
            _screenStr('necklaces', 'leaderNecklaceSvga',
                _screenStr('necklaces', 'agentNecklaceSvga',
                    _screenStr('miniprofile', 'agentBadgeSvga',
                        _screenStr('userProfile', 'agentBadgeSvga', ''))))));
    if (v.isNotEmpty) return v;
    return _rawConfig['agency']?['leaderNecklaceSvga']?.toString() ??
        _rawConfig['agency']?['agentNecklaceSvga']?.toString() ??
        _rawConfig['agencyLeaderNecklaceSvga']?.toString() ??
        _rawConfig['agentNecklaceSvga']?.toString() ??
        _rawConfig['leaderNecklaceSvga']?.toString() ??
        _rawConfig['agent_necklace_svga']?.toString() ??
        _rawConfig['leader_necklace_svga']?.toString() ??
        _rawConfig['agentBadgeSvga']?.toString() ??
        '';
  }

  String get agencyLeaderNecklaceImg {
    final v = _screenStr('agency', 'leaderNecklaceImg',
        _screenStr('agency', 'agentNecklaceImg',
            _screenStr('necklaces', 'leaderNecklaceImg',
                _screenStr('necklaces', 'agentNecklaceImg',
                    _screenStr('miniprofile', 'agentBadgeImg',
                        _screenStr('userProfile', 'agentBadgeImg', ''))))));
    if (v.isNotEmpty) return v;
    return _rawConfig['agency']?['leaderNecklaceImg']?.toString() ??
        _rawConfig['agency']?['agentNecklaceImg']?.toString() ??
        _rawConfig['agencyLeaderNecklaceImg']?.toString() ??
        _rawConfig['agentNecklaceImg']?.toString() ??
        _rawConfig['leaderNecklaceImg']?.toString() ??
        _rawConfig['agent_necklace_img']?.toString() ??
        _rawConfig['leader_necklace_img']?.toString() ??
        _rawConfig['agentBadgeImg']?.toString() ??
        '';
  }

  String get agencyLeaderNecklaceName => _screenStr('agency', 'leaderNecklaceName', _rawConfig['agency']?['leaderNecklaceName']?.toString() ?? 'قلادة الوكيل');

  String get agencyHostNecklaceSvga {
    final v = _screenStr('agency', 'hostNecklaceSvga',
        _screenStr('necklaces', 'hostNecklaceSvga',
            _screenStr('miniprofile', 'hostBadgeSvga',
                _screenStr('userProfile', 'hostBadgeSvga', ''))));
    if (v.isNotEmpty) return v;
    return _rawConfig['agency']?['hostNecklaceSvga']?.toString() ??
        _rawConfig['agencyHostNecklaceSvga']?.toString() ??
        _rawConfig['hostNecklaceSvga']?.toString() ??
        _rawConfig['host_necklace_svga']?.toString() ??
        _rawConfig['hostBadgeSvga']?.toString() ??
        '';
  }

  String get agencyHostNecklaceImg {
    final v = _screenStr('agency', 'hostNecklaceImg',
        _screenStr('necklaces', 'hostNecklaceImg',
            _screenStr('miniprofile', 'hostBadgeImg',
                _screenStr('userProfile', 'hostBadgeImg', ''))));
    if (v.isNotEmpty) return v;
    return _rawConfig['agency']?['hostNecklaceImg']?.toString() ??
        _rawConfig['agencyHostNecklaceImg']?.toString() ??
        _rawConfig['hostNecklaceImg']?.toString() ??
        _rawConfig['host_necklace_img']?.toString() ??
        _rawConfig['hostBadgeImg']?.toString() ??
        '';
  }

  String get agencyHostNecklaceName => _screenStr('agency', 'hostNecklaceName', _rawConfig['agency']?['hostNecklaceName']?.toString() ?? 'قلادة المضيف');

  // ── Agent Recharge Screen Customization (من لوحة التحكم) ──
  String get agentRechargeBgImage => _screenStr('agentRecharge', 'backgroundImage', '');
  String get agentRechargeHeaderBgImage => _screenStr('agentRecharge', 'headerBgImage', '');
  Color get agentRechargeHeaderColor => _screenColor('agentRecharge', 'headerColor', const Color(0xFF16151A));
  Color get agentRechargeTextColor => _screenColor('agentRecharge', 'textColor', Colors.white);
  Color get agentRechargeCardColor => _screenColor('agentRecharge', 'cardColor', Colors.white);
  Color get agentRechargeAccentColor => _screenColor('agentRecharge', 'accentColor', const Color(0xFFFFD700));
  String get agentRechargeBannerImage => _screenStr('agentRecharge', 'bannerImage', '');

  // ── Host Agency & Hosts Screens Customization (من لوحة التحكم) ──
  String get hostAgencyBgImage => _screenStr('hostAgency', 'backgroundImage', '');
  String get hostAgencyHeaderBgImage => _screenStr('hostAgency', 'headerBgImage', '');
  Color get hostAgencyHeaderColor => _screenColor('hostAgency', 'headerColor', const Color(0xFF16151A));
  Color get hostAgencyTextColor => _screenColor('hostAgency', 'textColor', Colors.white);
  Color get hostAgencyCardColor => _screenColor('hostAgency', 'cardColor', Colors.white);
  String get hostAgencyBannerImage => _screenStr('hostAgency', 'bannerImage', '');

  String get hostsBgImage => _screenStr('hosts', 'backgroundImage', hostAgencyBgImage);
  Color get hostsHeaderColor => _screenColor('hosts', 'headerColor', hostAgencyHeaderColor);
  Color get hostsTextColor => _screenColor('hosts', 'textColor', hostAgencyTextColor);

  // ── CP Space Screen Customization (من لوحة التحكم) ──
  String get cpSpaceBgImage => _screenStr('cp', 'backgroundImage', _screenStr('cpSpace', 'backgroundImage', ''));
  String get cpSpaceBannerImage => _screenStr('cp', 'bannerImage', _screenStr('cpSpace', 'bannerImage', ''));
  String get cpSpaceTitle => _screenStr('cp', 'title', 'علاقة CP');
  Color get cpSpaceTextColor => _screenColor('cp', 'textColor', Colors.white);
  Color get cpSpaceCardColor => _screenColor('cp', 'cardColor', const Color(0xFF1E1D24));

  // ── Profile Screen Icons Customization (من لوحة التحكم) ──
  String get profileCpIcon => _screenStr('profile', 'cpIcon',
      _assetsOverride['assets/mipmap-xxhdpi/mine_cp_ic.webp'] ??
      _assetsOverride['mine_cp_ic'] ??
      'assets/mipmap-xxhdpi/mine_cp_ic.webp');

  String get profileRechargeAgentIcon => _screenStr('profile', 'rechargeAgentIcon',
      _assetsOverride['assets/images/profile/ic_coinseller_entrance.png'] ??
      _assetsOverride['ic_coinseller_entrance'] ??
      'assets/images/profile/ic_coinseller_entrance.png');

  String get profileHostAgencyIcon => _screenStr('profile', 'hostAgencyIcon',
      _assetsOverride['assets/mipmap-xxhdpi/mine_union_ic.webp'] ??
      _assetsOverride['mine_union_ic'] ??
      'assets/mipmap-xxhdpi/mine_union_ic.webp');

  // Getters
  String get appName => _appName;
  String get logoUrl => _logoUrl;
  String get splashUrl => _splashUrl;
  bool get splashEnabled => _splashEnabled;
  String get splashImageUrl => _splashImageUrl;
  String get splashSvgaUrl => _splashSvgaUrl;
  int get splashDurationSeconds => _splashDurationSeconds;
  Color get splashNameColor => _splashNameColor;
  String get splashActionType => _splashActionType;
  String get splashActionValue => _splashActionValue;
  String get miniProfileFollowIcon => _miniProfileFollowIcon;
  String get miniProfileMessageIcon => _miniProfileMessageIcon;
  Color get primaryBg => _primaryBg;
  Color get textPrimary => _textPrimary;
  Color get textSecondary => _textSecondary;
  Color get goldColor => _goldColor;
  Color get buttonColor => _buttonColor;
  Color get buttonTextColor => _buttonTextColor;
  Color get headerColor => _headerColor;
  Color get tabBarColor => _tabBarColor;

  String get bottomNavBgImage => _bottomNavBgImage;
  Color get bottomNavGradientStart => _bottomNavGradientStart;
  Color get bottomNavGradientEnd => _bottomNavGradientEnd;
  Color get bottomNavActiveTextColor => _bottomNavActiveTextColor;
  Color get bottomNavInactiveTextColor => _bottomNavInactiveTextColor;

  String get giftPanelBgImage => _screenStr('giftPanel', 'backgroundImage', _giftPanelBgImage);
  Color get giftPanelBgColor => _screenColor('giftPanel', 'backgroundColor', _screenColor('giftPanel', 'cardBgColor', _giftPanelBgColor));
  Color get giftPanelTabColor => _screenColor('giftPanel', 'tabActiveColor', _giftPanelTabColor);

  String get fontFamily => _fontFamily;
  int get borderRadius => _borderRadius;
  String get discoverTitle => _discoverTitle;
  String get messageTitle => _messageTitle;
  String get profileTitle => _profileTitle;
  Map<String, String> get screenTitles => _screenTitles;
  String getScreenTitle(String key, String fallback) => _screenTitles[key] ?? fallback;
  String get cpWebUrl => _cpWebUrl;
  String get audioCompany => _audioCompany;
  String get agoraAppId => _agoraAppId;
  String get agoraToken => _agoraToken;
  String get easemobAppKey => _easemobAppKey;
  String get easemobOrgName => _easemobOrgName;
  String get easemobAppName => _easemobAppName;
  String get easemobWsUrl => _easemobWsUrl;
  String get easemobRestUrl => _easemobRestUrl;
  String get easemobPrimaryCert => _easemobPrimaryCert;
  String get easemobSecondaryCert => _easemobSecondaryCert;
  Map<String, String> get assetsOverride => _assetsOverride;
  Map<String, AppAssetModel> get appAssets => _appAssets;
  Map<String, Map<String, dynamic>> get assetSizes => _assetSizes;
  Map<String, dynamic> get lastSystemMessage => _lastSystemMessage;
  Color get vipCardBgColor => _vipCardBgColor;
  Color get vipCardBorderColor => _vipCardBorderColor;
  String get vipCardBgImgUrl => _vipCardBgImgUrl;
  String get vipPurchaseBarImgUrl => _vipPurchaseBarImgUrl;
  String get vipCoinImgUrl => _vipCoinImgUrl;
  String get vipBuyBtnImgUrl => _vipBuyBtnImgUrl;
  int get coinsPerRechargeXp => _coinsPerRechargeXp;
  int get diamondToCoinRate => _diamondToCoinRate;
  int get roomBgPrice => _roomBgPrice;

  // Room gradient getter (returns gradient if found, null otherwise)
  List<Color>? getRoomGradient(String key) => _roomGradients[key];
  
  // Room background image getter (returns image url if found, null otherwise)
  String? getRoomBgImage(String key) => _roomBgImages[key];

  // Global images getter
  String? getGlobalImage(String key) => _globalImages[key];

  // Chat bubble color getters
  Color get chatBubbleSelf => _chatBubbleSelf;
  Color get chatBubbleOther => _chatBubbleOther;
  Color get chatBubbleSelfBorder => _chatBubbleSelfBorder;
  Color get chatBubbleOtherBorder => _chatBubbleOtherBorder;
  Color get chatBubbleSelfText => _chatBubbleSelfText;
  Color get chatBubbleOtherText => _chatBubbleOtherText;

  // Screen visuals getter
  Map<String, dynamic> get screenVisuals => _screenVisuals;

  // Icon override getter + lookup
  Map<String, String> get iconOverrides => _iconOverrides;
  String? getIconOverride(String iconKey) => _iconOverrides[iconKey];

  // Helper: get a value from a specific screen in screenVisuals or rawConfig
  String _screenStr(String screen, String field, String fallback) {
    final s = _screenVisuals[screen];
    if (s is Map) {
      final v = s[field];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    // Also check root rawConfig if not in screenVisuals
    final root = _rawConfig[field];
    if (root != null && root.toString().trim().isNotEmpty) return root.toString().trim();
    final screenMap = _rawConfig[screen];
    if (screenMap is Map) {
      final sv = screenMap[field];
      if (sv != null && sv.toString().trim().isNotEmpty) return sv.toString().trim();
    }
    // Cross check screenVisuals fullProfile or userProfile
    if (screen != 'fullProfile' && _screenVisuals['fullProfile'] is Map) {
      final fp = _screenVisuals['fullProfile'][field];
      if (fp != null && fp.toString().trim().isNotEmpty) return fp.toString().trim();
    }
    if (screen != 'userProfile' && _screenVisuals['userProfile'] is Map) {
      final up = _screenVisuals['userProfile'][field];
      if (up != null && up.toString().trim().isNotEmpty) return up.toString().trim();
    }
    return fallback;
  }

  Color _screenColor(String screen, String field, Color fallback) {
    final s = _screenVisuals[screen];
    if (s is Map) {
      final v = s[field];
      if (v != null && v.toString().trim().isNotEmpty) return _parseColor(v.toString().trim(), fallback);
    }
    final root = _rawConfig[field];
    if (root != null && root.toString().trim().isNotEmpty) return _parseColor(root.toString().trim(), fallback);
    final screenMap = _rawConfig[screen];
    if (screenMap is Map) {
      final sv = screenMap[field];
      if (sv != null && sv.toString().trim().isNotEmpty) return _parseColor(sv.toString().trim(), fallback);
    }
    if (screen != 'fullProfile' && _screenVisuals['fullProfile'] is Map) {
      final fp = _screenVisuals['fullProfile'][field];
      if (fp != null && fp.toString().trim().isNotEmpty) return _parseColor(fp.toString().trim(), fallback);
    }
    if (screen != 'userProfile' && _screenVisuals['userProfile'] is Map) {
      final up = _screenVisuals['userProfile'][field];
      if (up != null && up.toString().trim().isNotEmpty) return _parseColor(up.toString().trim(), fallback);
    }
    return fallback;
  }

  // Agency screen visuals
  Color get agencyHeaderBg => _screenColor('agency', 'headerBgColor', const Color(0xFF1a1a2e));
  Color get agencyHeaderText => _screenColor('agency', 'headerTextColor', Colors.white);
  Color get agencyCardBg => _screenColor('agency', 'cardBgColor', const Color(0xFF16213e));
  Color get agencyCardBorder => _screenColor('agency', 'cardBorderColor', const Color(0xFF0f3460));
  Color get agencyTextColor => _screenColor('agency', 'textColor', Colors.white);
  Color get agencySubText => _screenColor('agency', 'subTextColor', const Color(0xFFa0a0b0));
  Color get agencyAccent => _screenColor('agency', 'accentColor', const Color(0xFFe94560));
  String get agencyBackgroundImage => _screenStr('agency', 'backgroundImage', '');
  String get agencyCheckboxChecked => _screenStr('agency', 'checkboxCheckedImage', '');
  String get agencyCheckboxUnchecked => _screenStr('agency', 'checkboxUncheckedImage', '');
  String get agencyCoinIcon => _screenStr('agency', 'coinIcon', '');
  String get agencyDiamondIcon => _screenStr('agency', 'diamondIcon', '');
  String get agencyRankIcon => _screenStr('agency', 'rankIcon', '');
  Color get agencyTabActive => _screenColor('agency', 'tabActiveColor', const Color(0xFFe94560));
  Color get agencyTabInactive => _screenColor('agency', 'tabInactiveColor', const Color(0xFF555555));

  // Room screen visuals
  String get roomBackgroundImage => _screenStr('room', 'backgroundImage', '');
  Color get roomHeaderBg => _screenColor('room', 'headerBgColor', Colors.transparent);
  Color get roomHeaderTextColor => _screenColor('room', 'headerTextColor', Colors.white);
  Color get roomGameBarBgColor => _screenColor('room', 'gameBarBgColor', const Color(0x1AFFFFFF));
  Color get roomGameBarTextColor => _screenColor('room', 'gameBarTextColor', Colors.white);
  Color get roomGameBarDescColor => _screenColor('room', 'gameBarDescColor', const Color(0x80FFFFFF));
  String get roomGameIcon => _screenStr('room', 'gameIconImage', '');
  String get roomExitIcon => _screenStr('room', 'exitIconImage', '');
  String get roomOnlineCapsuleBg => _screenStr('room', 'onlineCapsuleBgImage', '');
  String get roomGiftIcon => _screenStr('room', 'giftIconImage', '');
  String get roomChatIcon => _screenStr('room', 'chatIconImage', '');
  String get roomEmojiIcon => _screenStr('room', 'emojiIconImage', '');
  String get roomMicOnIcon => _screenStr('room', 'micOnIconImage', '');
  String get roomMicOffIcon => _screenStr('room', 'micOffIconImage', '');
  String get roomMusicIcon => _screenStr('room', 'musicIconImage', '');
  String get roomMsgIcon => _screenStr('room', 'msgIconImage', '');
  String get roomFunctionIcon => _screenStr('room', 'functionIconImage', '');
  String get roomSeatDefaultCircle => _screenStr('room', 'seatDefaultCircleImage', '');
  String get roomSeatLockCircle => _screenStr('room', 'seatLockCircleImage', '');
  String get roomSeatDefaultClassic => _screenStr('room', 'seatDefaultClassicImage', '');
  String get roomSeatLockClassic => _screenStr('room', 'seatLockClassicImage', '');
  String get roomSeatDefaultVip => _screenStr('room', 'seatDefaultVipImage', '');
  String get roomSeatLockVip => _screenStr('room', 'seatLockVipImage', '');
  Color get roomUserCardBgColor => _screenColor('room', 'userCardBgColor', const Color(0xFF16151A));
  String get roomUserCardBgImage => _screenStr('room', 'userCardBgImage', '');
  String get roomUserGiftBgImage => _screenStr('room', 'userGiftBgImage', '');
  String get roomUserFollowIcon => _screenStr('room', 'userFollowIconImage', '');
  String get roomUserChatIcon => _screenStr('room', 'userChatIconImage', '');
  String get roomUserAtIcon => _screenStr('room', 'userAtIconImage', '');
  String get roomUserGiftBtn => _screenStr('room', 'userGiftBtnImage', '');
  String get roomUserMicDownIcon => _screenStr('room', 'userMicDownIconImage', '');
  String get roomUserMicMuteIcon => _screenStr('room', 'userMicMuteIconImage', '');
  Color get roomExitSheetBgColor => _screenColor('room', 'exitSheetBgColor', const Color(0xFF16151A));
  Color get roomVolumePanelBgColor => _screenColor('room', 'volumePanelBgColor', const Color(0xFF16151A));
  Color get roomFunctionsPanelBgColor => _screenColor('room', 'functionsPanelBgColor', const Color(0xFF16151A));

  // Seat Style Panel
  Color get roomSeatPanelBgColor => _screenColor('room', 'seatPanelBgColor', const Color(0xF51D1111));
  String get roomSeatPanelTopBg => _screenStr('room', 'seatPanelTopBg', '');
  String get roomSeatRadioCheckedBg => _screenStr('room', 'seatRadioCheckedBg', '');
  String get roomSeatRadioUncheckedBg => _screenStr('room', 'seatRadioUncheckedBg', '');
  String get roomSeatGameIcon => _screenStr('room', 'seatGameIcon', '');
  String get roomSeatClassicIcon => _screenStr('room', 'seatClassicIcon', '');
  String get roomSeatVipIcon => _screenStr('room', 'seatVipIcon', '');
  String get roomSeatPreviewFrame => _screenStr('room', 'seatPreviewFrame', '');
  Color get roomSeatConfirmBtnStart => _screenColor('room', 'seatConfirmBtnStart', const Color(0xFFFCCE5E));
  Color get roomSeatConfirmBtnEnd => _screenColor('room', 'seatConfirmBtnEnd', const Color(0xFFD19C3B));
  Color get roomSeatConfirmBtnTextColor => _screenColor('room', 'seatConfirmBtnTextColor', Colors.white);

  // Functions Panel Icons
  String get roomFuncMixerIcon => _screenStr('room', 'funcMixerIcon', '');
  String get roomFuncSettingsIcon => _screenStr('room', 'funcSettingsIcon', '');
  String get roomFuncSeatStyleIcon => _screenStr('room', 'funcSeatStyleIcon', '');
  String get roomFuncBgIcon => _screenStr('room', 'funcBgIcon', '');
  String get roomFuncReportIcon => _screenStr('room', 'funcReportIcon', '');
  String get roomFuncEffectIcon => _screenStr('room', 'funcEffectIcon', '');
  String get roomFuncVolumeIcon => _screenStr('room', 'funcVolumeIcon', '');
  String get roomFuncGiftValIcon => _screenStr('room', 'funcGiftValIcon', '');

  // Room Settings Screen Visuals
  String get roomSettingsHeaderBg => _screenStr('room', 'settingsHeaderBg', '');
  String get roomSettingsLabelIcon => _screenStr('room', 'settingsLabelIcon', '');
  String get roomSettingsCameraIcon => _screenStr('room', 'settingsCameraIcon', '');
  Color get roomSettingsConfirmBtnStart => _screenColor('room', 'settingsConfirmBtnStart', const Color(0xFFFCCE5E));
  Color get roomSettingsConfirmBtnEnd => _screenColor('room', 'settingsConfirmBtnEnd', const Color(0xFFD19C3B));

  // Discover screen visuals
  String get discoverBackgroundImage => _screenStr('discover', 'backgroundImage', '');
  Color get discoverBackgroundColor => _screenColor('discover', 'backgroundColor', const Color(0xFFFFFFFF));
  Color get discoverTextColor => _screenColor('discover', 'textColor', const Color(0xFF16151A));
  Color get discoverSubTextColor => _screenColor('discover', 'subTextColor', const Color(0xFF9BA1B6));
  Color get discoverCardBgColor => _screenColor('discover', 'cardBgColor', const Color(0xFFF7F7F8));

  // Message screen visuals
  String get messageBackgroundImage => _screenStr('message', 'backgroundImage', '');
  Color get messageBackgroundColor => _screenColor('message', 'backgroundColor', const Color(0xFFFFFFFF));
  Color get messageTextColor => _screenColor('message', 'textColor', const Color(0xFF16151A));
  Color get messageSubTextColor => _screenColor('message', 'subTextColor', const Color(0xFF9BA1B6));
  Color get messageCardBgColor => _screenColor('message', 'cardBgColor', const Color(0xFFF7F7F8));

  // Profile screen visuals
  String get profileBackgroundImage => _screenStr('profile', 'backgroundImage', '');
  Color get profileBackgroundColor => _screenColor('profile', 'backgroundColor', const Color(0xFFF6F7F9));
  Color get profileTextColor => _screenColor('profile', 'textColor', const Color(0xFF000000));
  Color get profileSubTextColor => _screenColor('profile', 'subTextColor', const Color(0xFF888888));
  Color get profileCardBg => _screenColor('profile', 'cardBgColor', const Color(0xFFFFFFFF));

  // Chat screen visuals
  String get chatBackgroundImage => _screenStr('chat', 'backgroundImage', '');
  Color get chatBackgroundColor => _screenColor('chat', 'backgroundColor', const Color(0xFFF2F3F5));
  Color get chatTextColor => _screenColor('chat', 'textColor', const Color(0xFF000000));
  Color get chatBubbleSelfBg => _screenColor('chat', 'bubbleSelfBgColor', const Color(0xFFFFE082));
  Color get chatBubbleOtherBg => _screenColor('chat', 'bubbleOtherBgColor', const Color(0xFFFFFFFF));

  // UserProfile screen visuals (Mini profile card)
  String get userProfileBackgroundImage => _screenStr('userProfile', 'backgroundImage', '');
  Color get userProfileBackgroundColor => _screenColor('userProfile', 'backgroundColor', const Color(0xFF16151A));
  Color get userProfileTextColor => _screenColor('userProfile', 'textColor', const Color(0xFFFFFFFF));
  Color get userProfileSubTextColor => _screenColor('userProfile', 'subTextColor', const Color(0xFF9BA1B6));
  Color get userProfileButtonColor => _screenColor('userProfile', 'buttonColor', const Color(0xFFFFE082));

  // EventInfo screen visuals
  String get eventInfoBackgroundImage => _screenStr('eventInfo', 'backgroundImage', '');
  Color get eventInfoBackgroundColor => _screenColor('eventInfo', 'backgroundColor', const Color(0xFFFFFFFF));
  Color get eventInfoTextColor => _screenColor('eventInfo', 'textColor', const Color(0xFF000000));
  Color get eventInfoSubTextColor => _screenColor('eventInfo', 'subTextColor', const Color(0xFF888888));

  // Notifications screen visuals
  String get notificationsBackgroundImage => _screenStr('notifications', 'backgroundImage', '');
  Color get notificationsBackgroundColor => _screenColor('notifications', 'backgroundColor', const Color(0xFF211211));
  Color get notificationsTextColor => _screenColor('notifications', 'textColor', const Color(0xFFFFFFFF));
  Color get notificationsSubTextColor => _screenColor('notifications', 'subTextColor', const Color(0xFFB3B3B3));
  Color get notificationsCardBg => _screenColor('notifications', 'cardBgColor', const Color(0xFF301C1A));

  // Badges screen visuals
  Color get badgesHeaderBg => _screenColor('badges', 'headerBgColor', const Color(0xFF1a1a2e));
  String get badgesHeaderBgImage => _screenStr('badges', 'headerBgImage', '');
  Color get badgesHeaderText => _screenColor('badges', 'headerTextColor', Colors.white);
  String get badgesHeaderTextImage => _screenStr('badges', 'headerTextImage', '');
  Color get badgesCardBg => _screenColor('badges', 'cardBgColor', const Color(0xFF16213e));
  String get badgesCardBgImage => _screenStr('badges', 'cardBgImage', '');
  Color get badgesCardBorder => _screenColor('badges', 'cardBorderColor', const Color(0xFF0f3460));
  String get badgesCardBorderImage => _screenStr('badges', 'cardBorderImage', '');
  Color get badgesTextColor => _screenColor('badges', 'textColor', Colors.white);
  String get badgesTextImage => _screenStr('badges', 'textImage', '');
  Color get badgesSubText => _screenColor('badges', 'subTextColor', const Color(0xFFa0a0b0));
  String get badgesSubTextImage => _screenStr('badges', 'subTextImage', '');
  Color get badgesAccent => _screenColor('badges', 'accentColor', const Color(0xFFf0c724));
  String get badgesAccentImage => _screenStr('badges', 'accentImage', '');
  String get badgesBackgroundImage => _screenStr('badges', 'backgroundImage', '');
  Color get badgesSectionBg => _screenColor('badges', 'sectionBgColor', const Color(0xFF0d0d12));
  String get badgesSectionBgImage => _screenStr('badges', 'sectionBgImage', '');
  Color get badgesBorderColor => _screenColor('badges', 'badgeBorderColor', const Color(0xFFf0c724));
  String get badgesBorderImage => _screenStr('badges', 'badgeBorderImage', '');
  Color get badgesItemBg => _screenColor('badges', 'badgeBgColor', const Color(0xFF1a1a2e));
  String get badgesItemBgImage => _screenStr('badges', 'badgeBgImage', '');
  String get badgesLockImage => _screenStr('badges', 'lockImage', '');

  // Necklaces screen visuals
  Color get necklacesHeaderBg => _screenColor('necklaces', 'headerBgColor', const Color(0xFF1a1a2e));
  String get necklacesHeaderBgImage => _screenStr('necklaces', 'headerBgImage', '');
  Color get necklacesHeaderText => _screenColor('necklaces', 'headerTextColor', Colors.white);
  String get necklacesHeaderTextImage => _screenStr('necklaces', 'headerTextImage', '');
  Color get necklacesCardBg => _screenColor('necklaces', 'cardBgColor', const Color(0xFF16213e));
  String get necklacesCardBgImage => _screenStr('necklaces', 'cardBgImage', '');
  Color get necklacesCardBorder => _screenColor('necklaces', 'cardBorderColor', const Color(0xFF0f3460));
  String get necklacesCardBorderImage => _screenStr('necklaces', 'cardBorderImage', '');
  Color get necklacesTextColor => _screenColor('necklaces', 'textColor', Colors.white);
  String get necklacesTextImage => _screenStr('necklaces', 'textImage', '');
  Color get necklacesSubText => _screenColor('necklaces', 'subTextColor', const Color(0xFFa0a0b0));
  String get necklacesSubTextImage => _screenStr('necklaces', 'subTextImage', '');
  Color get necklacesAccent => _screenColor('necklaces', 'accentColor', const Color(0xFFe94560));
  String get necklacesAccentImage => _screenStr('necklaces', 'accentImage', '');
  String get necklacesBackgroundImage => _screenStr('necklaces', 'backgroundImage', '');
  Color get necklacesSectionBg => _screenColor('necklaces', 'sectionBgColor', const Color(0xFF0d0d12));
  String get necklacesSectionBgImage => _screenStr('necklaces', 'sectionBgImage', '');
  Color get necklacesBorderColor => _screenColor('necklaces', 'necklaceBorderColor', const Color(0xFFe94560));
  String get necklacesBorderImage => _screenStr('necklaces', 'necklaceBorderImage', '');
  Color get necklacesItemBg => _screenColor('necklaces', 'necklaceBgColor', const Color(0xFF1a1a2e));
  String get necklacesItemBgImage => _screenStr('necklaces', 'necklaceBgImage', '');
  String get necklacesLockImage => _screenStr('necklaces', 'lockImage', '');

  // CP screen visuals
  Color get cpPrimaryColor => _screenColor('cp', 'primaryColor', const Color(0xFFE91E8C));
  Color get cpGradientStart => _screenColor('cp', 'gradientStart', const Color(0xFFE91E8C));
  Color get cpGradientEnd => _screenColor('cp', 'gradientEnd', const Color(0xFFFF4FA3));
  Color get cpHeaderBg => _screenColor('cp', 'headerBgColor', const Color(0xFFE91E8C));
  Color get cpHeaderText => _screenColor('cp', 'headerTextColor', Colors.white);
  Color get cpCardBg => _screenColor('cp', 'cardBgColor', Colors.white);
  Color get cpCardBorder => _screenColor('cp', 'cardBorderColor', const Color(0xFFE91E8C));
  Color get cpTextColor => _screenColor('cp', 'textColor', const Color(0xFF5D1A3A));
  Color get cpSubText => _screenColor('cp', 'subTextColor', const Color(0xFFa0a0b0));
  Color get cpAccent => _screenColor('cp', 'accentColor', const Color(0xFFFF4FA3));
  Color get cpGold => _screenColor('cp', 'goldColor', const Color(0xFFFFD700));
  Color get cpSilver => _screenColor('cp', 'silverColor', const Color(0xFFC0C0C0));
  Color get cpBronze => _screenColor('cp', 'bronzeColor', const Color(0xFFCD7F32));
  Color get cpSectionBg => _screenColor('cp', 'sectionBgColor', const Color(0xFFFCE4EC));
  Color get cpTabActiveColor => _screenColor('cp', 'tabActiveColor', const Color(0xFFE91E8C));
  Color get cpTabInactiveColor => _screenColor('cp', 'tabInactiveColor', const Color(0xFFFFFFFF));
  Color get cpTabBgColor => _screenColor('cp', 'tabBgColor', const Color(0xFFE91E8C));
  String get cpTabBgImage => _screenStr('cp', 'tabBgImage', '');
  Color get cpCountdownTextColor => _screenColor('cp', 'countdownTextColor', const Color(0xFFE91E8C));
  Color get cpCountdownLabelColor => _screenColor('cp', 'countdownLabelColor', const Color(0xFF000000));
  Color get cpInvitationBgColor => _screenColor('cp', 'invitationBgColor', Colors.white);
  Color get cpButtonColor => _screenColor('cp', 'buttonColor', const Color(0xFFE91E8C));
  Color get cpButtonTextColor => _screenColor('cp', 'buttonTextColor', Colors.white);
  Color get cpButtonOutlineColor => _screenColor('cp', 'buttonOutlineColor', const Color(0xFFE91E8C));
  Color get cpGiftGradientStart => _screenColor('cp', 'giftButtonGradientStart', const Color(0xFFFF4FA3));
  Color get cpGiftGradientEnd => _screenColor('cp', 'giftButtonGradientEnd', const Color(0xFFE91E8C));
  Color get cpSectionHeaderColor => _screenColor('cp', 'sectionHeaderColor', const Color(0xFFE91E8C));
  Color get cpAvatarBorderColor => _screenColor('cp', 'avatarBorderColor', const Color(0xFFE91E8C));
  Color get cpScoreTokenColor => _screenColor('cp', 'scoreTokenColor', const Color(0xFFFFD700));
  Color get cpScoreTokenLabelColor => _screenColor('cp', 'scoreTokenLabelColor', Colors.white70);
  Color get cpScoreTokenBgColor => _screenColor('cp', 'scoreTokenBgColor', const Color(0xFFE91E8C));
  Color get cpPodiumBgStart => _screenColor('cp', 'podiumBgStart', const Color(0xFFFCE4EC));
  Color get cpPodiumBgEnd => _screenColor('cp', 'podiumBgEnd', Colors.white);
  Color get cpPeriodButtonActiveBg => _screenColor('cp', 'periodButtonActiveBg', const Color(0xFFE91E8C));
  Color get cpPeriodButtonActiveText => _screenColor('cp', 'periodButtonActiveText', Colors.white);
  Color get cpPeriodButtonInactiveBg => _screenColor('cp', 'periodButtonInactiveBg', const Color(0xFF00000D));
  Color get cpPeriodButtonInactiveText => _screenColor('cp', 'periodButtonInactiveText', const Color(0x73000000));
  Color get cpRankItemBg => _screenColor('cp', 'rankItemBg', Colors.white);
  Color get cpRankShadowColor => _screenColor('cp', 'rankShadowColor', const Color(0xFFE91E8C));
  Color get cpMyRankPillGradientStart => _screenColor('cp', 'myRankPillGradientStart', const Color(0xFFFF4FA3));
  Color get cpMyRankPillGradientEnd => _screenColor('cp', 'myRankPillGradientEnd', const Color(0xFFE91E8C));
  Color get cpMyRankPillText => _screenColor('cp', 'myRankPillText', Colors.white70);
  Color get cpMyRankScoreColor => _screenColor('cp', 'myRankScoreColor', const Color(0xFFFFD700));
  String get cpBackgroundImage => _screenStr('cp', 'backgroundImage', '');
  String get cpCabinBg => _screenStr('cp', 'cabinBg', '');
  String get cpCabinDefaultBg => _screenStr('cp', 'cabinDefaultBg', '');
  String get cpLeftFrame => _screenStr('cp', 'leftFrame', '');
  String get cpRightFrame => _screenStr('cp', 'rightFrame', '');
  String get cpHeartImage => _screenStr('cp', 'heartImage', '');
  String get cpNoCpHeartSvg => _screenStr('cp', 'noCpHeartSvg', '');
  String get cpTokenBg => _screenStr('cp', 'tokenBg', '');
  String get cpMineBg => _screenStr('cp', 'mineBg', '');
  String get cpCountdownDaySvg => _screenStr('cp', 'countdownDaySvg', '');
  String get cpCountdownHourSvg => _screenStr('cp', 'countdownHourSvg', '');
  String get cpCountdownMinSvg => _screenStr('cp', 'countdownMinSvg', '');
  String get cpCountdownSecSvg => _screenStr('cp', 'countdownSecSvg', '');
  String get cpRankTagGoldSvg => _screenStr('cp', 'rankTagGoldSvg', '');
  String get cpRankTagSilverSvg => _screenStr('cp', 'rankTagSilverSvg', '');
  String get cpRankTagBronzeSvg => _screenStr('cp', 'rankTagBronzeSvg', '');
  String get cpHistoryCardSvg => _screenStr('cp', 'historyCardSvg', '');
  String get cpGiftsBannerSvg => _screenStr('cp', 'giftsBannerSvg', '');
  String get cpInvitationBgImage => _screenStr('cp', 'invitationBgImage', '');
  String get cpFullScreenBg => _screenStr('cp', 'fullScreenBg', '');
  String get cpHeaderBgImage => _screenStr('cp', 'headerBgImage', '');
  // Profile CP card colors (used in user_profile_screen CP section)
  Color get cpProfileDaysBadgeBg => _screenColor('cp', 'profileDaysBadgeBg', const Color(0xFF260105));
  Color get cpProfileDaysBadgeBorder => _screenColor('cp', 'profileDaysBadgeBorder', const Color(0xFF81050f));
  Color get cpProfileDaysBadgeBg2 => _screenColor('cp', 'profileDaysBadgeBg2', const Color(0xFFa40b25));
  Color get cpProfileDaysBadgeBorder2 => _screenColor('cp', 'profileDaysBadgeBorder2', const Color(0xFFe73d46));
  Color get cpProfileDaysText => _screenColor('cp', 'profileDaysText', const Color(0xFFb3b3b3));
  Color get cpProfileDaysTogetherText => _screenColor('cp', 'profileDaysTogetherText', const Color(0xFFcccccc));
  Color get cpProfileLevelGradientStart => _screenColor('cp', 'profileLevelGradientStart', const Color(0xFFfff19f));
  Color get cpProfileLevelGradientEnd => _screenColor('cp', 'profileLevelGradientEnd', const Color(0xFFffb565));
  String get cpProfileHeartIcon => _screenStr('cp', 'profileHeartIcon', 'assets/cp/ic_cp_val_heart.png');
  String get cpProfileLevelBg => _screenStr('cp', 'profileLevelBg', 'assets/cp/ic_rs_lv_bg_cp.png');
  String get cpProfileNameFrame => _screenStr('cp', 'profileNameFrame', 'assets/cp/ic_send_invitation_name_frame.png');
  String get cpProfileTopBgSvga => _screenStr('cp', 'profileTopBgSvga', 'assets/svga/relationship_act_top_bg.svga');

  // Sign-in screen visuals
  String get signinBackgroundImage => _screenStr('signin', 'backgroundImage', '');
  Color get signinHeaderBgColor => _screenColor('signin', 'headerBgColor', const Color(0xFF2e0d15));
  String get signinHeaderBgImage => _screenStr('signin', 'headerBgImage', '');
  Color get signinHeaderTextColor => _screenColor('signin', 'headerTextColor', const Color(0xFFFFD700));
  String get signinHeaderTextImage => _screenStr('signin', 'headerTextImage', '');
  Color get signinCardBgColor => _screenColor('signin', 'cardBgColor', const Color(0xFF3d1520));
  String get signinCardBgImage => _screenStr('signin', 'cardBgImage', '');
  Color get signinCardBorderColor => _screenColor('signin', 'cardBorderColor', const Color(0xFFDE880F));
  String get signinCardBorderImage => _screenStr('signin', 'cardBorderImage', '');
  Color get signinTextColor => _screenColor('signin', 'textColor', const Color(0xFFFFFFFF));
  String get signinTextImage => _screenStr('signin', 'textImage', '');
  Color get signinSubTextColor => _screenColor('signin', 'subTextColor', const Color(0xFFB8A88A));
  String get signinSubTextImage => _screenStr('signin', 'subTextImage', '');
  Color get signinAccentColor => _screenColor('signin', 'accentColor', const Color(0xFFFFD700));
  String get signinAccentImage => _screenStr('signin', 'accentImage', '');
  Color get signinGoldColor => _screenColor('signin', 'goldColor', const Color(0xFFFFD700));
  Color get signinButtonColor => _screenColor('signin', 'buttonColor', const Color(0xFFDE880F));
  Color get signinButtonTextColor => _screenColor('signin', 'buttonTextColor', const Color(0xFFFFFFFF));
  Color get signinButtonGradientStart => _screenColor('signin', 'buttonGradientStart', const Color(0xFFFFD700));
  Color get signinButtonGradientEnd => _screenColor('signin', 'buttonGradientEnd', const Color(0xFFDE880F));
  Color get signinDayBgColor => _screenColor('signin', 'dayBgColor', const Color(0xFF3d1520));
  Color get signinDayActiveColor => _screenColor('signin', 'dayActiveColor', const Color(0xFF5a2030));
  Color get signinDayClaimedColor => _screenColor('signin', 'dayClaimedColor', const Color(0xFF1a4a1a));
  Color get signinDayLockedColor => _screenColor('signin', 'dayLockedColor', const Color(0xFF2a1018));
  Color get signinDayBorderColor => _screenColor('signin', 'dayBorderColor', const Color(0xFFDE880F));
  Color get signinDayClaimedBorderColor => _screenColor('signin', 'dayClaimedBorderColor', const Color(0xFF4CAF50));
  String get signinCheckmarkImage => _screenStr('signin', 'checkmarkImage', '');
  String get signinLockImage => _screenStr('signin', 'lockImage', '');
  String get signinStreakIcon => _screenStr('signin', 'streakIcon', '');
  String get signinTopBgSvga => _screenStr('signin', 'topBgSvga', '');
  String get signinButtonImage => _screenStr('signin', 'buttonImage', '');
  Color get signinSectionBgColor => _screenColor('signin', 'sectionBgColor', const Color(0xFF2e0d15));
  String get signinSectionBgImage => _screenStr('signin', 'sectionBgImage', '');

  // Rank screen visuals

  // Checkbox images
  String get checkboxChecked => _screenStr('checkbox', 'checkedImage', '');
  String get checkboxUnchecked => _screenStr('checkbox', 'uncheckedImage', '');

  // Store screen visuals
  String get storeBackgroundImage => _screenStr('store', 'backgroundImage', '');
  Color get storeHeaderBgColor => _screenColor('store', 'headerBgColor', const Color(0xFF1a1a2e));
  String get storeHeaderBgImage => _screenStr('store', 'headerBgImage', '');
  Color get storeHeaderTextColor => _screenColor('store', 'headerTextColor', Colors.white);
  String get storeHeaderTextImage => _screenStr('store', 'headerTextImage', '');
  Color get storeCardBgColor => _screenColor('store', 'cardBgColor', const Color(0xFF16151A));
  String get storeCardBgImage => _screenStr('store', 'cardBgImage', '');
  Color get storeCardBorderColor => _screenColor('store', 'cardBorderColor', Colors.white);
  String get storeCardBorderImage => _screenStr('store', 'cardBorderImage', '');
  Color get storeTextColor => _screenColor('store', 'textColor', Colors.white);
  String get storeTextImage => _screenStr('store', 'textImage', '');
  Color get storeSubTextColor => _screenColor('store', 'subTextColor', const Color(0xFF9BA1B6));
  String get storeSubTextImage => _screenStr('store', 'subTextImage', '');
  Color get storeAccentColor => _screenColor('store', 'accentColor', const Color(0xFFDE880F));
  String get storeAccentImage => _screenStr('store', 'accentImage', '');
  String get storeLockImage => _screenStr('store', 'lockImage', '');
  Color get storeSectionBgColor => _screenColor('store', 'sectionBgColor', const Color(0xFF0d0d12));
  String get storeSectionBgImage => _screenStr('store', 'sectionBgImage', '');

  // Backpack screen visuals
  String get backpackBackgroundImage => _screenStr('backpack', 'backgroundImage', '');
  Color get backpackHeaderBgColor => _screenColor('backpack', 'headerBgColor', const Color(0xFF1a1a2e));
  String get backpackHeaderBgImage => _screenStr('backpack', 'headerBgImage', '');
  Color get backpackHeaderTextColor => _screenColor('backpack', 'headerTextColor', Colors.white);
  String get backpackHeaderTextImage => _screenStr('backpack', 'headerTextImage', '');
  Color get backpackTabBgColor => _screenColor('backpack', 'tabBgColor', const Color(0x14FFFFFF));
  Color get backpackTabActiveColor => _screenColor('backpack', 'tabActiveColor', Colors.white);
  Color get backpackTabInactiveColor => _screenColor('backpack', 'tabInactiveColor', Colors.white70);
  Color get backpackCardBgColor => _screenColor('backpack', 'cardBgColor', const Color(0xFF16151A));
  String get backpackCardBgImage => _screenStr('backpack', 'cardBgImage', '');
  Color get backpackCardBorderColor => _screenColor('backpack', 'cardBorderColor', Colors.white);
  String get backpackCardBorderImage => _screenStr('backpack', 'cardBorderImage', '');
  Color get backpackTextColor => _screenColor('backpack', 'textColor', Colors.white);
  String get backpackTextImage => _screenStr('backpack', 'textImage', '');
  Color get backpackSubTextColor => _screenColor('backpack', 'subTextColor', const Color(0xFF9BA1B6));
  String get backpackSubTextImage => _screenStr('backpack', 'subTextImage', '');
  Color get backpackAccentColor => _screenColor('backpack', 'accentColor', const Color(0xFFDE880F));
  String get backpackAccentImage => _screenStr('backpack', 'accentImage', '');
  String get backpackLockImage => _screenStr('backpack', 'lockImage', '');
  Color get backpackSectionBgColor => _screenColor('backpack', 'sectionBgColor', const Color(0xFF0d0d12));
  String get backpackSectionBgImage => _screenStr('backpack', 'sectionBgImage', '');

  // Gift Panel (Room Gift Box) screen visuals
  String get giftPanelBackgroundImage => _screenStr('giftPanel', 'backgroundImage', _giftPanelBgImage);
  Color get giftPanelBackgroundColor => _screenColor('giftPanel', 'backgroundColor', const Color(0xFF16151A));
  Color get giftPanelHeaderBgColor => _screenColor('giftPanel', 'headerBgColor', Colors.transparent);
  String get giftPanelHeaderBgImage => _screenStr('giftPanel', 'headerBgImage', '');
  Color get giftPanelTabActiveColor => _screenColor('giftPanel', 'tabActiveColor', const Color(0xFFFFD700));
  Color get giftPanelTabInactiveColor => _screenColor('giftPanel', 'tabInactiveColor', Colors.white70);
  Color get giftPanelTabBgColor => _screenColor('giftPanel', 'tabBgColor', const Color(0x1AFFFFFF));
  String get giftPanelCardBgImage => _screenStr('giftPanel', 'cardBgImage', '');
  Color get giftPanelCardBgColor => _screenColor('giftPanel', 'cardBgColor', const Color(0x0DFFFFFF));
  Color get giftPanelCardBorderColor => _screenColor('giftPanel', 'cardBorderColor', Colors.transparent);
  Color get giftPanelCardSelectedBorderColor => _screenColor('giftPanel', 'cardSelectedBorderColor', const Color(0xFFFFD700));
  Color get giftPanelTextColor => _screenColor('giftPanel', 'textColor', Colors.white);
  Color get giftPanelSubTextColor => _screenColor('giftPanel', 'subTextColor', const Color(0xFFFFD856));
  Color get giftPanelSendBtnColor => _screenColor('giftPanel', 'sendBtnColor', const Color(0xFFDE880F));
  Color get giftPanelSendBtnGradientStart => _screenColor('giftPanel', 'sendBtnGradientStart', const Color(0xFFFFD700));
  Color get giftPanelSendBtnGradientEnd => _screenColor('giftPanel', 'sendBtnGradientEnd', const Color(0xFFDE880F));
  Color get giftPanelSendBtnTextColor => _screenColor('giftPanel', 'sendBtnTextColor', Colors.white);
  Color get giftPanelCountBtnBgColor => _screenColor('giftPanel', 'countBtnBgColor', const Color(0x1AFFFFFF));
  Color get giftPanelCountBtnTextColor => _screenColor('giftPanel', 'countBtnTextColor', Colors.white);
  Color get giftPanelCoinsTextColor => _screenColor('giftPanel', 'coinsTextColor', Colors.white);
  String get giftPanelComboIdleImage => _screenStr('giftPanel', 'comboIdleImage', '');
  String get giftPanelComboFireImage => _screenStr('giftPanel', 'comboFireImage', '');
  Color get giftPanelDurationBadgeBg => _screenColor('giftPanel', 'durationBadgeBg', const Color(0xFFE91E63));
  String get giftPanelLuckyBadgeImage => _screenStr('giftPanel', 'luckyBadgeImage', '');
  String get giftPanelStarBadgeImage => _screenStr('giftPanel', 'starBadgeImage', '');

  // Wallet screen visuals
  String get walletBackgroundImage => _screenStr('wallet', 'backgroundImage', '');
  Color get walletHeaderBgColor => _screenColor('wallet', 'headerBgColor', const Color(0xFF1a1a2e));
  String get walletHeaderBgImage => _screenStr('wallet', 'headerBgImage', '');
  Color get walletHeaderTextColor => _screenColor('wallet', 'headerTextColor', Colors.white);
  String get walletHeaderTextImage => _screenStr('wallet', 'headerTextImage', '');
  Color get walletCardBgColor => _screenColor('wallet', 'cardBgColor', const Color(0xFF16151A));
  String get walletCardBgImage => _screenStr('wallet', 'cardBgImage', '');
  Color get walletCardBorderColor => _screenColor('wallet', 'cardBorderColor', Colors.white);
  String get walletCardBorderImage => _screenStr('wallet', 'cardBorderImage', '');
  Color get walletTextColor => _screenColor('wallet', 'textColor', Colors.white);
  String get walletTextImage => _screenStr('wallet', 'textImage', '');
  Color get walletSubTextColor => _screenColor('wallet', 'subTextColor', const Color(0xFF9BA1B6));
  String get walletSubTextImage => _screenStr('wallet', 'subTextImage', '');
  Color get walletAccentColor => _screenColor('wallet', 'accentColor', const Color(0xFFDE880F));
  String get walletAccentImage => _screenStr('wallet', 'accentImage', '');
  String get walletLockImage => _screenStr('wallet', 'lockImage', '');
  Color get walletSectionBgColor => _screenColor('wallet', 'sectionBgColor', const Color(0xFF0d0d12));
  String get walletSectionBgImage => _screenStr('wallet', 'sectionBgImage', '');

  // Level screen visuals
  String get levelBackgroundImage => _screenStr('level', 'backgroundImage', '');
  Color get levelHeaderBgColor => _screenColor('level', 'headerBgColor', const Color(0xFF1a1a2e));
  String get levelHeaderBgImage => _screenStr('level', 'headerBgImage', '');
  Color get levelHeaderTextColor => _screenColor('level', 'headerTextColor', Colors.white);
  String get levelHeaderTextImage => _screenStr('level', 'headerTextImage', '');
  Color get levelCardBgColor => _screenColor('level', 'cardBgColor', const Color(0xFF1a1a2e));
  String get levelCardBgImage => _screenStr('level', 'cardBgImage', '');
  Color get levelCardBorderColor => _screenColor('level', 'cardBorderColor', const Color(0xFF0f3460));
  String get levelCardBorderImage => _screenStr('level', 'cardBorderImage', '');
  Color get levelTextColor => _screenColor('level', 'textColor', Colors.white);
  String get levelTextImage => _screenStr('level', 'textImage', '');
  Color get levelSubTextColor => _screenColor('level', 'subTextColor', const Color(0xFFa0a0b0));
  String get levelSubTextImage => _screenStr('level', 'subTextImage', '');
  Color get levelAccentColor => _screenColor('level', 'accentColor', const Color(0xFFf0c724));
  String get levelAccentImage => _screenStr('level', 'accentImage', '');
  String get levelLockImage => _screenStr('level', 'lockImage', '');
  Color get levelSectionBgColor => _screenColor('level', 'sectionBgColor', const Color(0xFF0d0d12));
  String get levelSectionBgImage => _screenStr('level', 'sectionBgImage', '');

  // Room Rocket & Treasure Box visuals
  String get roomRocketIcon => _screenStr('rocket', 'rocketIcon', 'assets/images/icon_crysatal_rocket.png');
  String get roomRocketSvga => _screenStr('rocket', 'rocketSvga', '');
  String get roomRocketExplosionSvga => _screenStr('rocket', 'rocketExplosionSvga', '');
  int get roomRocketTarget => int.tryParse(_screenStr('rocket', 'rocketTarget', '')) ?? 10000;
  String get roomRocketBanner => _screenStr('rocket', 'rocketBanner', '');
  Color get roomRocketCardColor => _screenColor('rocket', 'cardColor', const Color(0xFF1A1A2E));
  Color get roomRocketHeaderColor => _screenColor('rocket', 'headerColor', const Color(0xFF0F3460));
  Color get roomRocketTextColor => _screenColor('rocket', 'textColor', Colors.white);
  Color get roomRocketAccentColor => _screenColor('rocket', 'accentColor', const Color(0xFFFFD700));

  int _assetVersion = 0;
  int get assetVersion => _assetVersion;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _configSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _appAssetsSub;
  Completer<void>? _initCompleter;
  Completer<void>? _initAssetsCompleter;

  bool get hasValidSession => _auth.currentUser != null;

  // Initialize and listen to app_config
  Future<void> init() async {
    _initCompleter = Completer<void>();
    // Cancel any existing subscriptions (safety for hot restart)
    _configSub?.cancel();
    _appAssetsSub?.cancel();
    _authSub?.cancel();
    // Re-subscribe when auth state changes (Firestore streams handle their own auth)
    _authSub = _auth.authStateChanges().listen((user) {
      if (user == null) {
        debugPrint('DynamicConfigService: signed out, cancelling subscriptions');
        _configSub?.cancel();
        _appAssetsSub?.cancel();
      } else {
        debugPrint('DynamicConfigService: signed in, reconnecting subscriptions...');
        _configSub?.cancel();
        _appAssetsSub?.cancel();
        _setupConfigStream();
        _setupAppAssetsStream();
      }
    });

    _setupConfigStream();
    _initAssetsCompleter = Completer<void>();
    _setupAppAssetsStream();

    // Only block startup on first data when there is a real session. When
    // signed out, Firestore streams won't emit (permission denied) and we do
    // NOT want to stall the app at the login screen for the full timeout.
    if (!hasValidSession) {
      _initCompleter?.complete();
      _initAssetsCompleter?.complete();
      debugPrint('DynamicConfigService: no session, continuing immediately with defaults');
      return;
    }

    // Wait for both config and assets first data, or timeout after 10s.
    // Never throw here: a timeout (offline / signed-out) must not block startup.
    try {
      await Future.any([
        _initCompleter!.future.timeout(const Duration(seconds: 10)),
        _initAssetsCompleter!.future.timeout(const Duration(seconds: 10)),
      ]);
    } catch (e) {
      debugPrint('DynamicConfigService: init timed out, continuing with defaults: $e');
    }
  }

  void _setupAppAssetsStream() {
    _appAssetsSub = _db.collection('app_assets').snapshots().listen((snap) {
      final assets = <String, AppAssetModel>{};
      for (final doc in snap.docs) {
        final row = doc.data();
        if (row['is_active'] != false) {
          final asset = AppAssetModel.fromJson(row);
          if (asset.key.isNotEmpty) {
            assets[asset.key] = asset;
            final old = _appAssets[asset.key];
            if (old != null && old.remoteUrl != null) {
              final oldUrl = old.remoteUrl!;
              final newUrl = asset.remoteUrl ?? '';
              if (oldUrl != newUrl && newUrl.isNotEmpty) {
                imageCache.evict(CachedNetworkImageProvider(oldUrl));
                DefaultCacheManager().removeFile(oldUrl);
                debugPrint('DynamicConfigService: evicted cache for ${asset.key}');
              }
            }
          }
        }
      }
      _appAssets = assets;
      _assetVersion++;
      if (_initAssetsCompleter != null && !_initAssetsCompleter!.isCompleted) {
        _initAssetsCompleter!.complete();
      }
      notifyListeners();
    }, onError: (error) {
      debugPrint('DynamicConfigService: app_assets stream error: $error');
      if (_initAssetsCompleter != null && !_initAssetsCompleter!.isCompleted) {
        _initAssetsCompleter!.complete();
      }
      final errorStr = error.toString();
      if (errorStr.contains('permission-denied') || errorStr.contains('Unauthenticated')) {
        debugPrint('DynamicConfigService: permissions error detected, stopping retry. Waiting for sign-in...');
        return;
      }
      Future.delayed(const Duration(seconds: 5), () {
        debugPrint('DynamicConfigService: reconnecting app_assets stream...');
        _appAssetsSub?.cancel();
        _setupAppAssetsStream();
      });
    });
  }

  void _setupConfigStream() {
    _configSub = _db.collection('app_config').snapshots().listen((snap) {
      final config = <String, dynamic>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final k = doc.id;
        final v = data['value'];
        if (v is String) {
          final parsed = _tryParseJson(v);
          config[k] = parsed ?? v;
        } else {
          config[k] = v;
        }
      }

      _rawConfig.clear();
      _rawConfig.addAll(config);

      _appName = config['appName'] as String? ?? _appName;
      _logoUrl = config['logoUrl'] as String? ?? _logoUrl;
      _splashEnabled = config['splash_enabled'] == true || config['splash_enabled'] == 'true' || config['splashEnabled'] == true || config['splashEnabled'] == 'true';
      _splashImageUrl = config['splash_image_url'] as String? ?? config['splashImageUrl'] as String? ?? config['splashGifUrl'] as String? ?? '';
      _splashSvgaUrl = config['splash_svga_url'] as String? ?? config['splashSvgaUrl'] as String? ?? '';
      _splashDurationSeconds = (config['splash_duration_seconds'] as num?)?.toInt() ?? (config['splashDurationSeconds'] as num?)?.toInt() ?? 3;
      _splashActionType = config['splash_action_type'] as String? ?? config['splashActionType'] as String? ?? '';
      _splashActionValue = config['splash_action_value'] as String? ?? config['splashActionValue'] as String? ?? '';
      _splashUrl = _splashImageUrl.isNotEmpty ? _splashImageUrl : (config['splashGifUrl'] as String? ?? _splashUrl);
      _splashNameColor = _parseColor(config['splashNameColor'], _splashNameColor);

      _primaryBg = _parseColor(config['primaryBg'], _primaryBg);
      _textPrimary = _parseColor(config['textPrimary'], _textPrimary);
      _textSecondary = _parseColor(config['textSecondary'], _textSecondary);
      _goldColor = _parseColor(config['goldColor'], _goldColor);
      _buttonColor = _parseColor(config['buttonColor'], _buttonColor);
      _buttonTextColor = _parseColor(config['buttonTextColor'], _buttonTextColor);
      _headerColor = _parseColor(config['headerColor'], _headerColor);
      _tabBarColor = _parseColor(config['tabBarColor'], _tabBarColor);

      _bottomNavBgImage = config['bottomNavBgImage'] as String? ?? _bottomNavBgImage;
      _bottomNavGradientStart = _parseColor(config['bottomNavGradientStart'], _bottomNavGradientStart);
      _bottomNavGradientEnd = _parseColor(config['bottomNavGradientEnd'], _bottomNavGradientEnd);
      _bottomNavActiveTextColor = _parseColor(config['bottomNavActiveTextColor'], _bottomNavActiveTextColor);
      _bottomNavInactiveTextColor = _parseColor(config['bottomNavInactiveTextColor'], _bottomNavInactiveTextColor);

      _giftPanelBgImage = config['giftPanelBgImage'] as String? ?? config['gift_panel_bg_image'] as String? ?? _giftPanelBgImage;
      _giftPanelHeaderBgImage = config['giftPanelHeaderBgImage'] as String? ?? config['gift_panel_header_bg_image'] as String? ?? _giftPanelHeaderBgImage;
      _giftPanelBgColor = _parseColor(config['giftPanelBgColor'] ?? config['gift_panel_bg_color'], _giftPanelBgColor);
      _giftPanelTabColor = _parseColor(config['giftPanelTabColor'] ?? config['gift_panel_tab_color'], _giftPanelTabColor);

      _fontFamily = config['fontFamily'] as String? ?? _fontFamily;
      _borderRadius = (config['borderRadius'] as num?)?.toInt() ?? _borderRadius;

      _vipCardBgColor = _parseColor(config['vipCardBgColor'], _vipCardBgColor);
      _vipCardBorderColor = _parseColor(config['vipCardBorderColor'], _vipCardBorderColor);

      _vipCardBgImgUrl = config['vipCardBgImgUrl'] as String? ?? _vipCardBgImgUrl;
      _vipPurchaseBarImgUrl = config['vipPurchaseBarImgUrl'] as String? ?? _vipPurchaseBarImgUrl;
      _vipCoinImgUrl = config['vipCoinImgUrl'] as String? ?? _vipCoinImgUrl;
      _vipBuyBtnImgUrl = config['vipBuyBtnImgUrl'] as String? ?? _vipBuyBtnImgUrl;

      _discoverTitle = config['discoverTitle'] as String? ?? _discoverTitle;
      _messageTitle = config['messageTitle'] as String? ?? _messageTitle;
      _profileTitle = config['profileTitle'] as String? ?? _profileTitle;
      final titles = config['screenTitles'];
      if (titles is Map) {
        _screenTitles = titles.map((k, v) => MapEntry(k.toString(), v.toString()));
      }

      _cpWebUrl = config['cpWebUrl'] as String? ?? _cpWebUrl;
      _audioCompany = config['audioProvider'] as String? ?? _audioCompany;

      final overrides = config['assetsOverrides'];
      if (overrides is Map) {
        _assetsOverride = overrides.map((k, v) => MapEntry(k.toString(), v.toString()));
      }

      final sizes = config['assetSizes'];
      if (sizes is Map) {
        _assetSizes = sizes.map((k, v) {
          final entry = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
          return MapEntry(k.toString(), entry);
        });
      }

      final msg = config['lastSystemMessage'];
      if (msg is Map) {
        _lastSystemMessage = msg.cast<String, dynamic>();
      }

      _coinsPerRechargeXp = (config['coinsPerRechargeXp'] ?? 10).toInt();
      _diamondToCoinRate = (config['diamondToCoinRate'] ?? 2).toInt();
      _roomBgPrice = (config['roomBgPrice'] ?? 100).toInt();

      final rc = config['rankConfig'];
      if (rc is Map) {
        _rankBg = rc['bg']?.toString() ?? _rankBg;
        _rankGoldColor = rc['goldColor']?.toString() ?? _rankGoldColor;
        _rankSilverColor = rc['silverColor']?.toString() ?? _rankSilverColor;
        _rankBronzeColor = rc['bronzeColor']?.toString() ?? _rankBronzeColor;
        _rankPointsColor = rc['pointsColor']?.toString() ?? _rankPointsColor;
        _rankTrophyIcon = rc['trophyIcon']?.toString() ?? _rankTrophyIcon;
        _rankEmptyText = rc['emptyText']?.toString() ?? _rankEmptyText;
        _rankTextColor = rc['textColor']?.toString() ?? _rankTextColor;
        _rankSubTextColor = rc['subTextColor']?.toString() ?? _rankSubTextColor;

        for (final cat in ['wealth', 'charm', 'room']) {
          final catCfg = <String, String>{};
          final bgKey = '${cat}_bg';
          if (rc[bgKey] != null) catCfg['bg'] = rc[bgKey].toString();
          for (final field in ['goldColor', 'silverColor', 'bronzeColor', 'pointsColor', 'textColor', 'subTextColor']) {
            final key = '${cat}_$field';
            if (rc[key] != null) catCfg[field] = rc[key].toString();
          }
          if (catCfg.isNotEmpty) _rankCategoryConfigs[cat] = catCfg;
        }
      }

      final rgs = config['roomGradients'];
      if (rgs is Map) {
        _roomGradients = rgs.map((k, v) {
          final colors = <Color>[];
          if (v is List) {
            for (final c in v) {
              colors.add(_parseColor(c.toString(), Colors.transparent));
            }
          }
          return MapEntry(k.toString(), colors);
        });
      }

      final rbi = config['roomBgImages'];
      if (rbi is Map) {
        _roomBgImages = rbi.map((k, v) => MapEntry(k.toString(), v.toString()));
      }

      final gi = config['globalImages'];
      if (gi is Map) {
        _globalImages = gi.map((k, v) => MapEntry(k.toString(), v.toString()));
      }

      final cc = config['chatColors'];
      if (cc is Map) {
        _chatBubbleSelf = _parseColor(cc['bubbleSelf'], _chatBubbleSelf);
        _chatBubbleOther = _parseColor(cc['bubbleOther'], _chatBubbleOther);
        _chatBubbleSelfBorder = _parseColor(cc['bubbleSelfBorder'], _chatBubbleSelfBorder);
        _chatBubbleOtherBorder = _parseColor(cc['bubbleOtherBorder'], _chatBubbleOtherBorder);
        _chatBubbleSelfText = _parseColor(cc['bubbleSelfText'], _chatBubbleSelfText);
        _chatBubbleOtherText = _parseColor(cc['bubbleOtherText'], _chatBubbleOtherText);
      }

      final sv = config['screenVisuals'];
      if (sv is Map) {
        _screenVisuals = sv.map((k, v) => MapEntry(k.toString(), v));
      }

      final io = config['iconOverrides'];
      if (io is Map) {
        _iconOverrides = io.map((k, v) => MapEntry(k.toString(), v.toString()));
      }

      final restartFlag = config['restartApp'];
      if (restartFlag == true || restartFlag == 'true') {
        debugPrint('DynamicConfigService: restartApp flag detected, restarting...');
        _db.collection('app_config').doc('restartApp').set({'value': false}, SetOptions(merge: true));
        Restart.restartApp();
      }

      _assetVersion++;
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
      notifyListeners();
    }, onError: (error) {
      debugPrint('DynamicConfigService: error loading config: $error');
      final errorStr = error.toString();
      if (errorStr.contains('JWT expired') || errorStr.contains('PGRST303') || errorStr.contains('Unauthorized')) {
      }
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
    });
  }

  List<AppAssetModel> getAssetsByCategory(String category) {
    return _appAssets.values.where((a) => a.category == category && a.isActive).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  // Parse color from string (e.g. #FFFFFF or 0xFFFFFFFF or color name)
  Color _parseColor(dynamic val, Color fallback) {
    if (val == null) return fallback;
    String str = val.toString().trim().replaceAll('#', '');
    if (str.startsWith('0x')) {
      str = str.substring(2);
    }
    if (str.length == 6) {
      str = 'FF$str'; // Add alpha
    }
    final intValue = int.tryParse(str, radix: 16);
    if (intValue != null) {
      return Color(intValue);
    }
    return fallback;
  }

  // Try parsing a string as JSON, return parsed value or null
  dynamic _tryParseJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map || decoded is List) return decoded;
    } catch (_) {}
    return null;
  }

  // Dynamic config accessors (for profile etc.)
  String get profileBgType => _rawConfig['profileBgType'] as String? ?? 'solid';
  Color get profileSolidColor => _parseColor(_rawConfig['profileSolidColor'], const Color(0xFF03030A));
  List<Color> get profileGradientColors {
    final hexList = _rawConfig['profileGradientColors'] as List?;
    if (hexList != null && hexList.length >= 2) {
      return hexList.map((e) => _parseColor(e.toString(), const Color(0xFF03030A))).toList();
    }
    return [const Color(0xFF1E1E2C), const Color(0xFF03030A)];
  }
  String get customProfileBgImage => _rawConfig['profileBackgroundImage'] as String? ?? '';
  String get profileBgSvga => _rawConfig['profileBgSvga'] as String? ?? '';
  double get miniprofileCoverHeight => double.tryParse(_screenStr('userProfile', 'coverHeight', '')) ?? 0;
  double get miniprofileCoverAspectRatio => double.tryParse(_screenStr('userProfile', 'coverAspectRatio', '')) ?? (750 / 1666);
  String get profileSettingsIcon => _rawConfig['profileSettingsIcon'] as String? ?? '';
  String get profileEditIcon => _rawConfig['profileEditIcon'] as String? ?? '';
  String get profileShareIcon => _rawConfig['profileShareIcon'] as String? ?? '';
  bool get profileShowSignature => _rawConfig['profileShowSignature'] as bool? ?? true;
  bool get profileShowId => _rawConfig['profileShowId'] as bool? ?? true;
  bool get profileShowLevel => _rawConfig['profileShowLevel'] as bool? ?? true;
  String get buttonStyle => _rawConfig['buttonStyle'] as String? ?? 'modern';
  String get roomSendMessageImage => _rawConfig['roomSendMessageImage'] as String? ?? '';
  dynamic getConfig(String key) => _rawConfig[key];

  Color? getColorConfig(String key) {
    final val = _rawConfig[key];
    if (val == null) return null;
    return _parseColor(val, Colors.transparent);
  }

  // ─── Audio & Zego Configurations ──────────────────────────────────────
  int get zegoAppId {
    final v = _rawConfig['zego_app_id'] ?? _rawConfig['zegoAppId'];
    if (v is int) return v;
    if (v != null) return int.tryParse(v.toString()) ?? AppConfig.zegoAppId;
    return AppConfig.zegoAppId;
  }

  String get zegoAppSign {
    final v = _rawConfig['zego_app_sign'] ?? _rawConfig['zegoAppSign'];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    return AppConfig.zegoAppSign;
  }

  String get audioProvider => _rawConfig['audio_provider'] as String? ?? _rawConfig['audioProvider'] as String? ?? _audioCompany;

  bool get zegoAudioEnabled => _rawConfig['zego_audio_enabled'] != false && _rawConfig['zegoAudioEnabled'] != false;

  int get zegoScenario {
    final v = _rawConfig['zego_scenario'] ?? _rawConfig['zegoScenario'];
    if (v is int) return v;
    if (v != null) return int.tryParse(v.toString()) ?? 0;
    return 0; // 0 = Default, 1 = StandardVoiceCall, 2 = HighQualityChatroom
  }

  /// Update Zego & Audio configurations in Firestore dynamically
  Future<void> updateAudioConfig({
    required int appId,
    required String appSign,
    String? provider,
    bool? audioEnabled,
    int? scenario,
  }) async {
    final batch = _db.batch();
    batch.set(_db.collection('app_config').doc('zego_app_id'), {'value': appId}, SetOptions(merge: true));
    batch.set(_db.collection('app_config').doc('zego_app_sign'), {'value': appSign.trim()}, SetOptions(merge: true));
    if (provider != null) {
      batch.set(_db.collection('app_config').doc('audio_provider'), {'value': provider}, SetOptions(merge: true));
    }
    if (audioEnabled != null) {
      batch.set(_db.collection('app_config').doc('zego_audio_enabled'), {'value': audioEnabled}, SetOptions(merge: true));
    }
    if (scenario != null) {
      batch.set(_db.collection('app_config').doc('zego_scenario'), {'value': scenario}, SetOptions(merge: true));
    }
    await batch.commit();

    _rawConfig['zego_app_id'] = appId;
    _rawConfig['zego_app_sign'] = appSign.trim();
    if (provider != null) _rawConfig['audio_provider'] = provider;
    if (audioEnabled != null) _rawConfig['zego_audio_enabled'] = audioEnabled;
    if (scenario != null) _rawConfig['zego_scenario'] = scenario;
    notifyListeners();
  }

  String _normalizeKey(String path) {
    return path.replaceAll('/', '_').replaceAll('.', '_');
  }

  // Helper to resolve network asset override
  // Priority: app_assets.remote_url > app_config.assetsOverrides
  // Tries multiple key formats:
  //   - fullKey:  assets_mipmap-xxhdpi_file_webp  (hyphens preserved)
  //   - shortKey: file_webp
  //   - legacyKey: mipmap-xxhdpi_file_webp
  //   - undFullKey: assets_mipmap_xxhdpi_file_webp (hyphens→underscores for legacy DB entries)
  String? getAssetOverride(String assetPath) {
    if (assetPath == 'assets/mipmap-xxhdpi/room_mic_seat_default_circle.png') {
      final override = roomSeatDefaultCircle;
      if (override.isNotEmpty) return override;
    }
    if (assetPath == 'assets/mipmap-xxhdpi/room_mic_seat_lock_circle.png') {
      final override = roomSeatLockCircle;
      if (override.isNotEmpty) return override;
    }
    if (assetPath == 'assets/mipmap-xxhdpi/room_mic_seat_default_ic.webp') {
      final override = roomSeatDefaultClassic;
      if (override.isNotEmpty) return override;
    }
    if (assetPath == 'assets/mipmap-xxhdpi/room_mic_seat_lock_ic.webp') {
      final override = roomSeatLockClassic;
      if (override.isNotEmpty) return override;
    }
    if (assetPath.contains('room_mic_seat_default_vip_2_ic')) {
      final override = roomSeatDefaultVip;
      if (override.isNotEmpty) return override;
    }
    if (assetPath == 'assets/mipmap-xxhdpi/room_bg_friend.webp') {
      final override = roomBackgroundImage;
      if (override.isNotEmpty) return override;
    }

    final fullKey = _normalizeKey(assetPath);
    final shortKey = assetPath.split('/').last.replaceAll('.', '_');
    final legacyKey = fullKey.startsWith('assets_') ? fullKey.substring(7) : null;
    final undFullKey = fullKey.replaceAll('-', '_');
    final undLegacyKey = legacyKey?.replaceAll('-', '_');
    final appAsset = _appAssets[fullKey] ?? _appAssets[shortKey] ?? 
        (legacyKey != null ? _appAssets[legacyKey] : null) ??
        _appAssets[undFullKey] ?? (undLegacyKey != null ? _appAssets[undLegacyKey] : null);
    if (appAsset != null && appAsset.remoteUrl != null && appAsset.remoteUrl!.isNotEmpty) {
      return appAsset.remoteUrl;
    }
    return _assetsOverride[fullKey] ?? _assetsOverride[shortKey] ?? _assetsOverride[undFullKey];
  }

  // Lookup remote URL directly by asset key
  String? getAssetUrl(String key) {
    final asset = _appAssets[key];
    if (asset != null && asset.remoteUrl != null && asset.remoteUrl!.isNotEmpty) {
      return asset.remoteUrl;
    }
    return _assetsOverride[key];
  }

  // Helper to get asset size override, returns Size if both width and height are set
  // Priority: app_assets width/height > app_config assetSizes
  Size? getAssetSize(String assetPath) {
    final fullKey = _normalizeKey(assetPath);
    final shortKey = assetPath.split('/').last.replaceAll('.', '_');
    final undFullKey = fullKey.replaceAll('-', '_');
    final appAsset = _appAssets[fullKey] ?? _appAssets[shortKey] ?? _appAssets[undFullKey];
    if (appAsset != null && appAsset.width != null && appAsset.height != null) {
      return Size(appAsset.width!.toDouble(), appAsset.height!.toDouble());
    }
    final entry = _assetSizes[fullKey] ?? _assetSizes[shortKey] ?? _assetSizes[undFullKey];
    if (entry == null) return null;
    final w = entry['width'];
    final h = entry['height'];
    if (w is num && h is num) {
      return Size(w.toDouble(), h.toDouble());
    }
    return null;
  }
}


