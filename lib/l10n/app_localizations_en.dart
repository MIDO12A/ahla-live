// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get tabDiscover => 'Discover';

  @override
  String get tabMessage => 'Message';

  @override
  String get tabProfile => 'Profile';

  @override
  String get profileUserName => 'User Name';

  @override
  String profileUserId(String id) => 'ID: $id';

  @override
  String get profileFollowing => 'Following';

  @override
  String get profileFollowers => 'Followers';

  @override
  String get profileVisitors => 'Visitors';

  @override
  String get profileWallet => 'Wallet';

  @override
  String get profileRecharge => 'Recharge now';

  @override
  String get profileLevel => 'Level';

  @override
  String get profileMall => 'Mall';

  @override
  String get profileBackpack => 'Backpack';

  @override
  String get profileFeedback => 'Feedback';

  @override
  String get profileSetting => 'Setting';

  @override
  String get profileUnion => 'Union';

  @override
  String get levelTitle => 'Level';

  @override
  String levelExperience(int current, int max) => 'Experience: $current/$max';

  @override
  String get levelNext => 'Next Levels';

  @override
  String get levelUnlockReward => 'Unlock reward';

  @override
  String get mallTitle => 'Mall';

  @override
  String get mallHeadwear => 'Headwear';

  @override
  String get mallBubble => 'Bubble';

  @override
  String get mallCar => 'Car';

  @override
  String get mallEntrance => 'Entrance';

  @override
  String get mallBuy => 'Buy';

  @override
  String get walletTitle => 'Wallet';

  @override
  String get walletCoinBalance => 'Coin Balance';

  @override
  String get walletItems => 'Wallet items';

  // --- GENERAL ---
  @override
  String get app_name => 'Ahla Live';

  @override
  String get loading => 'Loading...';

  @override
  String get error_occurred => 'An error occurred, please try again';

  @override
  String get no_data => 'No data available';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get close => 'Close';

  @override
  String get search => 'Search';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  // --- AUTH ---
  @override
  String get login => 'Login';

  @override
  String get register => 'Register';

  @override
  String get phone_number => 'Phone Number';

  @override
  String get sms_code => 'SMS Code';

  @override
  String get send_code => 'Send Code';

  @override
  String get password => 'Password';

  @override
  String get forgot_password => 'Forgot Password?';

  @override
  String get agree_to_terms => 'I agree to the Terms of Service and Privacy Policy';

  @override
  String get privacy_policy => 'Privacy Policy';

  @override
  String get terms_of_service => 'Terms of Service';

  // --- NAVIGATION ---
  @override
  String get tab_discover => 'Discover';

  @override
  String get tab_message => 'Messages';

  @override
  String get tab_profile => 'Profile';

  @override
  String get tab_room => 'Rooms';

  @override
  String get tab_agency => 'Agency';

  // --- PROFILE ---
  @override
  String get edit_profile => 'Edit Profile';

  @override
  String get change_avatar => 'Change Avatar';

  @override
  String get change_nickname => 'Change Nickname';

  @override
  String get personal_signature => 'Bio';

  @override
  String get gender => 'Gender';

  @override
  String get birthday => 'Birthday';

  // --- WALLET & MALL ---
  @override
  String get wallet_diamond_balance => 'Diamonds Balance';

  @override
  String get recharge => 'Recharge';

  @override
  String get recharge_now => 'Recharge Now';

  @override
  String get recharge_history => 'Recharge History';

  @override
  String get insufficient_balance => 'Insufficient balance, please recharge';

  @override
  String get transaction_success => 'Transaction completed successfully';

  // --- ROOM & MIC ---
  @override
  String get room_title => 'Voice Room';

  @override
  String get room_manager => 'Room Admin';

  @override
  String room_members(int count) => 'Audience ($count)';

  @override
  String get mic_up => 'Take Mic';

  @override
  String get mic_down => 'Leave Mic';

  @override
  String get lock_mic_seat => 'Lock Mic Seat';

  @override
  String get unlock_mic_seat => 'Unlock Mic Seat';

  @override
  String get kick_user => 'Kick Out';

  @override
  String get mute_user => 'Mute User';

  @override
  String get unmute_user => 'Unmute User';

  @override
  String get room_settings => 'Room Settings';

  @override
  String get room_password => 'Room Password';

  @override
  String get enter_room => 'Join Room';

  @override
  String get room_is_full => 'The room is full';

  @override
  String get apply_for_mic => 'Request Mic';

  @override
  String get mic_application => 'Mic Requests';

  @override
  String get turn_off_mic => 'Mute My Mic';

  @override
  String get room_black_list => 'Room Blacklist';

  // --- GIFTS ---
  @override
  String get send_gift => 'Send Gift';

  @override
  String gift_sent_success(String name) => 'Gift sent successfully to $name';

  @override
  String get lucky_bag => 'Lucky Bag';

  @override
  String get treasure_box => 'Treasure Box';

  @override
  String get open_box => 'Open Box';

  // --- VIP & AGENCY ---
  @override
  String get vip => 'VIP';

  @override
  String get svip => 'SVIP';

  @override
  String get vip_privileges => 'VIP Privileges';

  @override
  String get svip_privileges => 'SVIP Privileges';

  @override
  String get activate_vip => 'Activate VIP';

  @override
  String get renew_vip => 'Renew VIP';

  @override
  String vip_level(int level) => 'VIP Level $level';

  @override
  String get exclusive_reward => 'Exclusive Reward';

  @override
  String get union => 'Union';

  @override
  String get agency => 'Agency';

  @override
  String get join_agency => 'Join Agency';

  @override
  String get create_agency => 'Create Agency';

  @override
  String get agency_leader => 'Agency Owner';

  @override
  String get agency_members => 'Agency Hosts';

  @override
  String get agency_rules => 'Agency Rules';

  // --- SETTINGS ---
  @override
  String get change_language => 'Language';

  @override
  String get arabic => 'العربية';

  @override
  String get english => 'English';

  @override
  String get clear_cache => 'Clear Cache';

  @override
  String get logout => 'Log Out';

  @override
  String get delete_account => 'Delete Account';

  @override
  String get block_user => 'Block User';

  @override
  String get unblock_user => 'Unblock User';

  @override
  String get report_user => 'Report User';

  @override
  String get blacklist => 'Blocked Accounts';

  // --- CHAT ---
  @override
  String get chat => 'Chat';

  @override
  String get send_message => 'Send';

  @override
  String get type_message => 'Say something...';

  @override
  String get voice_message => 'Voice Message';

  @override
  String get no_messages_yet => 'No messages yet, start chatting!';
}
