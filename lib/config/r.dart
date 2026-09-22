import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/dynamic_config_service.dart';
import '../screens/room/widgets/svga_player.dart';
import '../screens/room/widgets/vap_player.dart';
import '../core/cache/encrypted_image_provider.dart';
import '../core/widgets/cached_image.dart';

enum AssetType { svga, vap, mp4, webp, gif, png, other }

AssetType detectAssetType(String url) {
  if (url.isEmpty) return AssetType.other;
  final match = RegExp(r'[?&]assetType=(\w+)', caseSensitive: false).firstMatch(url);
  if (match != null) {
    switch (match.group(1)!.toLowerCase()) {
      case 'svga': return AssetType.svga;
      case 'vap': return AssetType.vap;
      case 'mp4': return AssetType.mp4;
      case 'webp': return AssetType.webp;
      case 'gif': return AssetType.gif;
      case 'apng': return AssetType.gif;
      case 'png': return AssetType.png;
    }
  }
  final clean = url.split('?')[0].split('#')[0].toLowerCase();
  if (clean.endsWith('.svga')) return AssetType.svga;
  if (clean.endsWith('.vap')) return AssetType.vap;
  if (clean.endsWith('.mp4')) return AssetType.mp4;
  if (clean.endsWith('.webp')) return AssetType.webp;
  if (clean.endsWith('.gif')) return AssetType.gif;
  if (clean.endsWith('.apng')) return AssetType.gif;
  if (clean.endsWith('.png')) return AssetType.png;
  if (clean.endsWith('.jpg') || clean.endsWith('.jpeg')) return AssetType.png;
  if (clean.contains('.svga')) return AssetType.svga;
  if (clean.contains('.vap')) return AssetType.vap;
  if (clean.contains('.mp4')) return AssetType.mp4;
  return AssetType.other;
}

bool isVideoType(String? url) {
  if (url == null || url.isEmpty) return false;
  final t = detectAssetType(url);
  return t == AssetType.vap || t == AssetType.mp4;
}

bool isImageType(String? url) {
  if (url == null || url.isEmpty) return false;
  final t = detectAssetType(url);
  return t == AssetType.webp || t == AssetType.gif || t == AssetType.png;
}

class R {
  static const String _m = 'assets/mipmap-xxhdpi';

  // Room assets (verified existing)
  static const String roomBgFriend = '$_m/room_bg_friend.webp';
  static const String roomSetMusicIc = '$_m/room_set_music_ic.webp';
  static const String roomMicCharmMaleIc = '$_m/room_mic_charm_male_ic.webp';
  static const String roomGiftPanelSelectOwnerIc =
      '$_m/room_gift_panel_select_owner_ic.webp';
  static const String roomGiftLuckyIntroduceBg =
      '$_m/room_gift_lucky_introduce_bg.webp';
  static const String roomBgSeatPre = '$_m/room_bg_seat_pre.webp';
  static const String roomMicphoneIc = '$_m/room_micphone_ic.webp';
  static const String roomMicphoneCloseIc = '$_m/room_micphone_close_ic.webp';
  static const String roomGiftIc = '$_m/room_gift_ic.webp';
  static const String roomEmojIc = '$_m/room_emoj_ic.webp';
  static const String roomChatIc = '$_m/room_chat_ic.webp';
  static const String roomFunctionIc = '$_m/room_function_ic.webp';
  static const String roomMsgIc = '$_m/room_msg_ic.webp';
  static const String roomExitIc = '$_m/room_exit_ic.webp';
  static const String roomGameIc = '$_m/room_game_ic.webp';
  static const String roomGameBg = '$_m/room_game_bg.webp';
  static const String roomGameTopBg = '$_m/room_game_top_bg.webp';
  static const String roomGameTitleIc = '$_m/room_game_title_ic.webp';
  static const String roomGameBroadcastBg = '$_m/room_game_broadcast_bg.webp';
  static const String roomGameBroadcastIc = '$_m/room_game_broadcast_ic.webp';
  static const String roomGameCloseIc = '$_m/room_game_close_ic.webp';
  static const String roomMusicEmptyIc = '$_m/room_music_empty_ic.webp';
  static const String roomMicOn = '$_m/room_mic_on.webp';
  static const String roomMicOff = '$_m/room_mic_off.webp';
  static const String roomMicDown = '$_m/room_mic_down.webp';
  static const String roomMicSeatDefaultIc =
      '$_m/room_mic_seat_default_ic.webp';
  static const String roomMicSeatBigIc = '$_m/room_mic_seat_big_ic.webp';
  static const String roomMicSeatLockIc = '$_m/room_mic_seat_lock_ic.webp';
  static const String roomMicSeatDefaultCircle = 'assets/mipmap-xxhdpi/room_mic_seat_default_circle.png';
  static const String roomMicSeatLockCircle = 'assets/mipmap-xxhdpi/room_mic_seat_lock_circle.png';
  static const String roomMicSeatMuteIc = '$_m/room_mic_seat_mute_ic.webp';
  static const String roomLockStateIc = '$_m/room_lock_state_ic.webp';
  static const String roomPwdLockOffIc = '$_m/room_pwd_lock_off_ic.webp';
  static const String roomPwdLockOpen = '$_m/room_pwd_lock_open.webp';
  static const String roomHotLogoIc = '$_m/room_hot_logo_ic.webp';
  static const String roomCreateRoomBg = '$_m/room_create_room_bg.webp';
  static const String roomCreateLabelIc = '$_m/room_create_label_ic.webp';
  static const String roomCameraLogoIc = '$_m/room_camera_logo_ic.webp';
  static const String next2Ic = '$_m/next_2_ic.webp';
  static const String icGoJiantou = '$_m/ic_go_jiantou.webp';
  static const String roomNoticeBg = '$_m/room_gift_notice_bg.webp';
  static const String roomGiftImgPre = '$_m/room_gift_img_pre.webp';
  static const String roomWindowFloatBg = '$_m/room_window_float_bg.webp';
  static const String roomMicSeatStyleTopBg = 'assets/mipmap-xxhdpi/room_mic_seat_style_top_bg.9.png';
  static const String roomSeatStylePre = '$_m/room_seat_style_pre.webp';
  static const String roomSeatStyleNor = '$_m/room_seat_style_nor.webp';
  static const String roomMicSeatStyleDefaultIc = '$_m/room_mic_seat_style_default_ic.webp';
  static const String roomMicSeatDefaultVip2Ic = '$_m/room_mic_seat_default_vip_2_ic.webp';
  static const String commonCloseIc2 = '$_m/common_close_ic_2.webp';

  // Union & Agency assets (matching union_activity_my_agency.xml & union_activity_agency_item_detail.xml)
  static const String unionMyAgencyBg = 'assets/mipmap-xxhdpi/union_my_agency_bg.png';
  static const String unionMyAgencyAvatarBg = '$_m/union_my_agency_avatar_bg.webp';
  static const String unionAgencyAvatarHeaderIc = '$_m/union_agency_avatar_heder_ic.webp';
  static const String unionAvatarBorderIc = 'assets/mipmap-xxhdpi/union_avatar_border_ic.9.png';
  static const String unionSubAgentInviteBg = '$_m/union_sub_agent_invite_bg.webp';
  static const String unionSubAgentInviteIc = '$_m/union_sub_agent_invite_ic.webp';
  static const String unionAgencyRank1Ic = '$_m/union_agency_rank_1_ic.webp';
  static const String unionAgencyMemberIc = '$_m/union_agency_member_ic.webp';
  static const String unionSubAgentIc = '$_m/union_sub_agent_ic.webp';
  static const String unionNoticeIc = '$_m/union_notice_ic.webp';
  static const String unionIdIc = '$_m/union_id_ic.webp';
  static const String unionRuleIc = '$_m/union_rule_ic.webp';
  static const String unionEditIc = '$_m/union_edit_ic.webp';
  static const String unionTabBg = '$_m/union_tab_bg.webp';
  static const String unionAgencyItemBg = '$_m/union_agency_item_bg.webp';
  static const String unionRate1Ic = '$_m/union_rate_1_ic.webp';
  static const String commonDiamondIc = '$_m/common_diamond_ic.webp';
  static const String commonNext3Ic = '$_m/common_next_3_ic.webp';
  static const String commonNext5 = '$_m/common_next_5.webp';
  static const String backWhite2 = '$_m/back_white_2.webp';

  // Drawable shapes (XML shape drawables – used as widget equivalents in code)
  static const String roomPackageGiftBg = 'assets/drawable/room_package_gift_bg.xml';
  static const String roomGiftPanelHeaderMemberPre = 'assets/drawable/room_gift_panel_header_member_pre.xml';
  static const String roomGiftPanelHeaderMemberNor = 'assets/drawable/room_gift_panel_header_member_nor.xml';
  static const String roomGiftPanelHeaderMemberSelectNumBg = 'assets/drawable/room_gift_panel_header_member_select_num_bg.xml';

  // Gift panel images (matching dialog_gift_panel.xml)
  static const String roomGiftTabBagIc = '$_m/room_gift_tab_bag_ic.webp';
  static const String roomGiftAllSelectNor =
      '$_m/room_gift_all_select_nor.webp';
  static const String roomGiftAllSelectPre =
      '$_m/room_gift_all_select_pre.webp';
  static const String roomGiftNumOpenIc = '$_m/room_gift_num_open_ic.webp';
  static const String commonGoldIc1 = '$_m/common_gold_ic_1.webp';
  static const String commonGoldIc4 = '$_m/common_gold_ic_4.webp';

  // Gift notice / combo
  static const String comboFire = '$_m/combo_fire.webp';
  static const String comboIdle = '$_m/combo_idle.webp';
  static const String roomGiftNoticeBg2 = '$_m/room_gift_notice_bg.webp';
  static const String roomGiftLuckyBg = '$_m/room_gift_lucky_bg.webp';
  static const String roomGiftComboTimeIc = '$_m/room_gift_combo_time_ic.webp';
  static const String roomGiftComboLuckyPre =
      '$_m/room_gift_combo_lucky_pre.webp';
  static const String roomGiftComboLuckyNor =
      '$_m/room_gift_combo_lucky_nor.webp';
  static const String roomGiftLuckyLabelIc =
      '$_m/room_gift_lucky_label_ic.webp';
  static const String roomGiftStarLabelIc = '$_m/room_gift_star_label_ic.webp';
  static const String roomGiftMusicLabelIc =
      '$_m/room_gift_music_label_ic.webp';

  // Lucky gift
  static const String roomLuckyGiftAnimBg = '$_m/room_lucky_gift_anim_bg.webp';
  static const String roomLuckyGiftCoinIc = '$_m/room_lucky_gift_coin_ic.webp';
  static const String roomLuckyGiftBg2 = '$_m/room_lucky_gift_bg_2.webp';

  // Room set icons
  static const String roomSetVolumeIc = '$_m/room_set_volume_ic.webp';
  static const String roomSetVolumeCloseIc =
      '$_m/room_set_volume_close_ic.webp';
  static const String roomSetSetIc = '$_m/room_set_set_ic.webp';
  static const String roomSetSeatStyle = '$_m/room_set_seat_style.webp';
  static const String roomSetReportIc = '$_m/room_set_report_ic.webp';
  static const String roomSetMixerIc = '$_m/room_set_mixer_ic.webp';
  static const String roomSetGiftIc = '$_m/room_set_gift_ic.webp';
  static const String roomSetEffectIc = '$_m/room_set_effect_ic.webp';

  // .9.png / .png drawables
  static const String roomOnlineInfoBg = '$_m/room_online_info_bg.9.png';
  static const String roomWindowFloatCancel =
      '$_m/room_window_float_cancel_ic.png';

  // User info
  static const String roomUserInfoGiftIc = '$_m/room_user_info_gift_ic.webp';
  static const String icSocialSharing = '$_m/ic_social_sharing.webp';
  static const String commonBtnDianNor = '$_m/common_btn_dian_nor.webp';
  static const String commonBtnDianPre = '$_m/common_btn_dian_pre.webp';
  static const String nextWhiteIc = '$_m/next_white_ic.webp';
  static const String roomUserFollowNorIc = '$_m/room_user_follow_nor_ic.webp';
  static const String roomUserFollowPreIc = '$_m/room_user_follow_pre_ic.webp';
  static const String roomUserChatIc = '$_m/room_user_chat_ic.webp';
  static const String roomMicOperateAtSign =
      '$_m/room_mic_operate_at_sign.webp';
  static const String roomUserinfoMoreIc = '$_m/room_userinfo_more_ic.webp';
  static const String roomFollowNor = '$_m/room_follow_nor.webp';
  static const String roomFollowPre = '$_m/room_follow_pre.webp';
  static const String nextBlack = '$_m/next_black.webp';
  static const String roomOwnerInfoRoomBg = '$_m/room_owner_info_room_bg.9.png';

  // Chat
  static const String chatMessageSystemBg = '$_m/chat_message_system_bg.webp';
  static const String chatMessageInformationBg =
      '$_m/chat_message_information_bg.webp';

  // Tab assets
  static const String tabDiscoverNor = '$_m/tab_discover_nor.webp';
  static const String tabDiscoverPre = '$_m/tab_discover_pre.webp';
  static const String tabRankingNor = '$_m/tab_discover_nor.webp';
  static const String tabRankingPre = '$_m/tab_discover_pre.webp';
  static const String tabMessageNor = '$_m/tab_message_nor.webp';
  static const String tabMessagePre = '$_m/tab_message_pre.webp';
  static const String tabMineNor = '$_m/tab_mine_nor.webp';
  static const String tabMinePre = '$_m/tab_mine_pre.webp';

  // Discover screen assets
  static const String discoverHeaderBg = '$_m/discover_header_bg.webp';
  static const String discoverSearchIc = '$_m/discover_search_ic.webp';
  static const String discoverRoomIc = '$_m/discover_room_ic.webp';
  static const String discoverTabFollowIc = '$_m/discover_tab_follow_ic.webp';
  static const String discoverTabRecentIc = '$_m/discover_tab_recent_ic.webp';
  static const String discoverTabIndicatorIc = '$_m/discover_tab_indicator_ic.webp';
  static const String discoverRoomItemInfoBg = '$_m/discover_room_item_info_bg.webp';
  static const String discoverRoomItem1 = '$_m/discover_room_item_1.webp';
  static const String discoverItemRoom2 = '$_m/discover_item_room_2.webp';
  static const String discoverItemRoom3 = '$_m/discover_item_room_3.webp';
  static const String discoverGameTeamingIc = '$_m/discover_game_teaming_ic.webp';

  // Room category backgrounds
  static const String discoverItemChatBg = '$_m/discover_item_chat_bg.webp';
  static const String discoverItemMusicBg = '$_m/discover_item_music_bg.webp';
  static const String discoverItemGameBg = '$_m/discover_item_game_bg.webp';
  static const String discoverItemHobbyBg = '$_m/discover_item_hobby_bg.webp';
  static const String discoverItemPartyBg = '$_m/discover_item_party_bg.webp';
  static const String discoverItemFriendBg = '$_m/discover_item_friend_bg.webp';

  // Room category icons
  static const String discoverRoomChatIc = '$_m/discover_room_chat_ic.webp';
  static const String discoverRoomMusicIc = '$_m/discover_room_enjoy_music.webp';
  static const String discoverRoomGameTeamIc = '$_m/discover_room_game_team_ic.webp';
  static const String discoverRoomHobbyIc = '$_m/discover_room_hobby_ic.webp';
  static const String discoverRoomPartyIc = '$_m/discover_room_party_ic.webp';
  static const String discoverCountryMoreIc = '$_m/discover_country_more_ic.webp';
  static const String discoverRoomHotLabelIc = '$_m/discover_room_hot_label_ic.webp';
  static const String placeholderResBannerIc = '$_m/placeholder_res_banner_ic.webp';

  // Wallet assets
  static const String mineWalletHeaderBg = '$_m/mine_wallet_header_bg.webp';
  static const String backWhite = '$_m/back_white.webp';
  static const String mineWalletCoinBagIc = '$_m/mine_wallet_coin_bag_ic.webp';
  static const String commonGoldIc3 = '$_m/common_gold_ic_3.webp';
  static const String mineWalletDetailIc = '$_m/mine_wallet_detail_ic.webp';
  static const String mineWalletFilterIc = '$_m/mine_wallet_filter_ic.webp';

  // Common
  static const String backIc = '$_m/back_ic.webp';
  static const String commonCloseIc = '$_m/common_close_ic.webp';
  static const String commonGoldIc2 = '$_m/common_gold_ic_2.webp';
  static const String commonBack2 = '$_m/common_back_2.webp';
  static const String splashImgLogo = '$_m/splash_img_logo.webp';

  // Mine / Profile icons
  static const String mineFacebookIc = '$_m/mine_facebook_ic.webp';
  static const String mineFeedbackIc = '$_m/mine_feedback_ic.webp';
  static const String mineReportIc = '$_m/mine_report_ic.webp';
  static const String mineSettingIc = '$_m/mine_setting_ic.webp';
  static const String minePhotoAddIc = '$_m/mine_photo_add_ic.webp';
  static const String mineUnionIc = '$_m/mine_union_ic.webp';
  static const String minePhoneIc = '$_m/mine_phone_ic.webp';
  static const String mineGoogleIc = '$_m/mine_google_ic.webp';
  static const String mineFollowNorIc = '$_m/mine_follow_nor_ic.webp';

  // Union / Agency assets
  static const String unionsTitleIc = '$_m/unions_title_ic.webp';
  static const String unionsSearchIc = '$_m/unions_search_ic.webp';
  static const String unionCreateGuild = '$_m/union_create_guild.webp';
  static const String unionMyAgency = '$_m/union_my_agency.webp';
  static const String unionRank1Bg = '$_m/union_rank_1_bg.webp';
  static const String unionRank2Bg = '$_m/union_rank_2_bg.webp';
  static const String unionRank3Bg = '$_m/union_rank_3_bg.webp';
  static const String unionAgencyTop1 = '$_m/union_agency_top_1.webp';
  static const String unionAgencyTop2 = '$_m/union_agency_top_2.webp';
  static const String unionAgencyTop3 = '$_m/union_agency_top_3.webp';
  static const String mineFollowPreIc = '$_m/mine_follow_pre_ic.webp';
  static const String mineLevelIc = '$_m/mine_level_ic.webp';
  static const String mineBackpackIc = '$_m/mine_backpack_ic.webp';
  static const String mineMallIc = '$_m/mine_mall_ic.webp';
  static const String mineUserEditIc = '$_m/mine_user_edit_ic.webp';
  static const String mineDeleteIc = '$_m/mine_delete_ic.webp';
  static const String mineBlackIc = '$_m/mine_black_ic.webp';
  static const String mineCloseIc = '$_m/mine_close_ic.webp';
  static const String mineCameraIc = '$_m/mine_camera_ic.webp';
  static const String mineAvatarIc = '$_m/mine_avatar_ic.webp';
  static const String minePhoneDownIc = '$_m/mine_phone_down_ic.webp';
  static const String mineGooglePayIc = '$_m/mine_google_ic.webp';
  static const String commonNext4Ic = '$_m/common_next_4_ic.webp';
  static const String nextBlackIc = '$_m/next_black_ic.webp';
  static const String mineTopBg = '$_m/mine_top_bg.webp';
  static const String levelTopBg = '$_m/level_top_bg.webp';
  static const String mineBtnEditIc = '$_m/mine_btn_edit_ic.webp';
  static const String icSexGirl = '$_m/ic_sex_girl.webp';
  static const String icSexBoy = '$_m/ic_sex_boy.webp';
  static const String commonUserIdIc = '$_m/common_user_id_ic.webp';
  static const String commonIdCopyIc = '$_m/common_id_copy_ic.webp';
  static const String mineWalletIc = '$_m/mine_wallet_ic.webp';
  static const String mineVipCenterBg = '$_m/mine_vip_center_bg.webp';
  static const String mineMallTabVipIc = '$_m/mine_mall_tab_vip_ic.webp';
  static const String mineVipLabelIc = '$_m/mine_vip_label_ic.webp';
  static const String mineVipGo = '$_m/mine_vip_go.webp';
  static const String mineCpIc = '$_m/mine_cp_ic.webp';

  // Sex icons
  static const String sexMaleIc = '$_m/sex_male_ic.webp';
  static const String sexFemaleIc = '$_m/sex_female_ic.webp';

  // Avatar
  static const String avaBoy = '$_m/ava_boy.webp';
  static const String avaGirl = '$_m/ava_girl.webp';

  // Sign-in assets
  static const String signGiftBg = '$_m/sign_gift_bg.png';
  static const String signGift = '$_m/sign_gift.png';
  static const String signCoinTop = '$_m/sign_coin_top.png';
  static const String signCoinBgCoin = '$_m/sign_coin_bg_coin.png';
  static const String icCheckinGift = '$_m/ic_checkin_gift.png';
  static const String icCheckinGiftHalf = '$_m/ic_checkin_gift_half.png';
  static const String icHaveCheckedIn = '$_m/ic_have_checked_in.png';
  static const String icHaveNotCheckedIn = '$_m/ic_have_not_checked_in.png';
  static const String icSigningWaitingClock = '$_m/ic_signing_waiting_clock.png';
  static const String icSigningTopBg = '$_m/ic_signing_top_bg.png';
  static const String icSigningOk = '$_m/ic_signing_ok.png';
  static const String icSigningClock = '$_m/ic_signing_clock.png';
  static const String bgDialogTask = '$_m/bg_dialog_task.png';
  static const String dialogCoins = '$_m/dialog_coins.png';
  static const String giveCoinIcon = '$_m/give_coin_icon.png';
  static const String miniCoins = '$_m/mini_coins.png';
  static const String icMinCoins = '$_m/ic_min_coins.png';
  static const String bgGetTaskCoin = '$_m/bg_get_task_coin.png';

  // SVGA frames & animations
  static const String superAdminFrame = 'assets/svga/super_admin_frame.svga';
  static const String giftAnimSvga = 'assets/svga/gift_anim.svga';
  static const String superAdmin = 'assets/svga/super_admin.svga';
  static const String gift = 'assets/svga/gift.svga';
  static const String miaoSvga = 'assets/svga/miao.svga';
  static const String roomFmWaveMale = 'assets/svga/room_fm_wave_male.svga';
  static const String roomFmWaveFemale = 'assets/svga/room_fm_wave_female.svga';
  static const String roomSpeakingWaveMale = 'assets/room_speaking_wave_male.svga';
  static const String roomSpeakingWaveFemale = 'assets/room_speaking_wave_female.svga';
  static const String roomRankBorder1 = 'assets/svga/kojuyee_room_rank_border1.svga';
  static const String roomRankBorder2 = 'assets/svga/kojuyee_room_rank_border2.svga';
  static const String roomRankBorder3 = 'assets/svga/kojuyee_room_rank_border3.svga';

  // Lottie animations
  static const String lottie3 = 'assets/lottie/3.json';
  static const String lottie4 = 'assets/lottie/4.json';
  static const String lottie25 = 'assets/lottie/25.json';

  // Custom gift item image (gift.png)
  static const String giftItemPng = '$_m/gift_item.png';

  /// 1x1 transparent PNG (no alpha data) used as a safe placeholder for
  /// missing/empty assets so no "Unable to load asset: ''" errors are thrown.
  static final Uint8List _transparentPng = Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
    0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
  ]);

  /// Returns a transparent 1x1 [MemoryImage] — safe for empty/missing paths.
  static ImageProvider transparentImage() => MemoryImage(_transparentPng);

  /// Returns an [EncryptedImageProvider] for network URLs, cached locally with AES encryption.
  /// Returns a transparent 1x1 PNG for SVGA URLs to prevent decode errors.
  static ImageProvider cachedImage(String url) {
    if (url.isEmpty) return transparentImage();
    if (detectAssetType(url) == AssetType.svga) {
      return MemoryImage(_transparentPng);
    }
    return EncryptedImageProvider(url);
  }

  // Constructor helpers
  static String mipmap(String name, {String ext = 'webp'}) => '$_m/$name.$ext';
  static String drawable(String name, {String ext = 'webp'}) =>
      'assets/drawable-xxhdpi/$name.$ext';

  /// Returns true if [path] is a network URL
  static bool isNetworkUrl(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  /// Returns the appropriate Image widget for either a network URL or local asset path.
  static Widget loadImage(
    String path, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    Color? color,
    bool loops = true,
    VoidCallback? onFinished,
  }) {
    if (path.isEmpty) {
      return Image(image: transparentImage(), width: width, height: height, fit: fit);
    }
    final size = _getSizeOverride(path);
    width ??= size?.width;
    height ??= size?.height;
    final type = detectAssetType(path);
    if (type == AssetType.svga) {
      return SvgaPlayer(assetPath: path, width: width, height: height, fit: fit, loops: loops, onFinished: onFinished);
    }
    if (type == AssetType.vap || type == AssetType.mp4) {
      return VapPlayer(url: path, width: width, height: height, fit: fit, loops: loops, onFinished: onFinished);
    }
    if (isNetworkUrl(path)) {
      return Image(
        image: EncryptedImageProvider(path),
        width: width,
        height: height,
        fit: fit,
        color: color,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38),
      );
    }
    if (path.startsWith('file://')) {
      return Image.file(
        File(path.replaceFirst('file://', '')),
        width: width,
        height: height,
        fit: fit,
        color: color,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38),
      );
    }
    return image(
      path,
      width: width,
      height: height,
      fit: fit,
      color: color,
    );
  }

  static Size? _getSizeOverride(String assetPath) {
    try {
      return DynamicConfigService().getAssetSize(assetPath);
    } catch (_) {
      return null;
    }
  }

  /// Returns either an Image widget or an SvgaPlayer based on the override URL type.
  /// If the override URL ends with .svga, renders an SVGA animation.
  /// Otherwise, renders a regular image with override or local fallback.
  static Widget loadAsset(
    String assetPath, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    Color? color,
    bool loops = true,
    VoidCallback? onSvgaFinished,
  }) {
    if (assetPath.isEmpty) {
      return Image(image: transparentImage(), width: width, height: height, fit: fit);
    }
    final size = _getSizeOverride(assetPath);
    width ??= size?.width;
    height ??= size?.height;

    if (assetPath.startsWith('http://') || assetPath.startsWith('https://')) {
      if (detectAssetType(assetPath) == AssetType.svga) {
        return SvgaPlayer(
          assetPath: assetPath,
          width: width,
          height: height,
          fit: fit,
          loops: loops,
          onFinished: onSvgaFinished,
        );
      }
      return CachedNetImage(
        assetPath,
        width: width,
        height: height,
        fit: fit,
        color: color,
      );
    }

    final overrideUrl = DynamicConfigService().getAssetOverride(assetPath);
    if (overrideUrl != null && overrideUrl.isNotEmpty) {
      if (detectAssetType(overrideUrl) == AssetType.svga) {
        return SvgaPlayer(
          assetPath: overrideUrl,
          width: width,
          height: height,
          fit: fit,
          loops: loops,
          onFinished: onSvgaFinished,
        );
      }
      return CachedNetImage(
        overrideUrl,
        width: width,
        height: height,
        fit: fit,
        color: color,
        error: (context, url, err) => Image.asset(
          assetPath,
          width: width,
          height: height,
          fit: fit,
          color: color,
        ),
      );
    }
    final localType = detectAssetType(assetPath);
    if (localType == AssetType.svga) {
      return SvgaPlayer(
        assetPath: assetPath,
        width: width,
        height: height,
        fit: fit,
        loops: loops,
        onFinished: onSvgaFinished,
      );
    }
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      color: color,
    );
  }

  /// Convenience helper to load a dynamic asset if set, otherwise fallback to local asset.
  static Widget loadAssetOr(
    String dynamicPath,
    String fallbackPath, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    Color? color,
  }) {
    final path = dynamicPath.isNotEmpty ? dynamicPath : fallbackPath;
    return loadAsset(path, width: width, height: height, fit: fit, color: color);
  }

  // Dynamic Image widget builder that intercepts asset loading
  static Widget image(
    String assetPath, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    Color? color,
  }) {
    if (assetPath.isEmpty) {
      return Image(image: transparentImage(), width: width, height: height, fit: fit);
    }
    final size = _getSizeOverride(assetPath);
    width ??= size?.width;
    height ??= size?.height;

    final type = detectAssetType(assetPath);
    if (type == AssetType.svga) {
      return SvgaPlayer(
        assetPath: assetPath,
        width: width,
        height: height,
        fit: fit,
      );
    }

    if (assetPath.startsWith('http://') || assetPath.startsWith('https://')) {
      return CachedNetImage(
        assetPath,
        width: width,
        height: height,
        fit: fit,
        color: color,
      );
    }

    final overrideUrl = DynamicConfigService().getAssetOverride(assetPath);
    if (overrideUrl != null && overrideUrl.isNotEmpty) {
      if (detectAssetType(overrideUrl) == AssetType.svga) {
        return SvgaPlayer(
          assetPath: overrideUrl,
          width: width,
          height: height,
          fit: fit,
        );
      }
      return CachedNetImage(
        overrideUrl,
        width: width,
        height: height,
        fit: fit,
        color: color,
        error: (context, url, err) => Image.asset(
          assetPath,
          width: width,
          height: height,
          fit: fit,
          color: color,
        ),
      );
    }
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      color: color,
    );
  }

  /// Compact number formatter: 1000 -> 1K, 1500000 -> 1.5M, 10000000 -> 10M, 1000000000 -> 1B
  static String formatCoins(num amount) {
    final abs = amount.abs();
    if (abs >= 1000000000) {
      final v = amount / 1000000000;
      return v == v.roundToDouble() ? '${v.toInt()}B' : '${v.toStringAsFixed(1)}B';
    }
    if (abs >= 1000000) {
      final v = amount / 1000000;
      return v == v.roundToDouble() ? '${v.toInt()}M' : '${v.toStringAsFixed(1)}M';
    }
    if (abs >= 1000) {
      final v = amount / 1000;
      return v == v.roundToDouble() ? '${v.toInt()}K' : '${v.toStringAsFixed(1)}K';
    }
    return amount.toInt().toString();
  }
}
