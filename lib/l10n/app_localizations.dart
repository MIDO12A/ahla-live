import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @tabDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get tabDiscover;

  /// No description provided for @tabMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get tabMessage;

  /// No description provided for @tabProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get tabProfile;

  /// No description provided for @profileUserName.
  ///
  /// In en, this message translates to:
  /// **'User Name'**
  String get profileUserName;

  /// No description provided for @profileUserId.
  ///
  /// In en, this message translates to:
  /// **'ID: {id}'**
  String profileUserId(String id);

  /// No description provided for @profileFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get profileFollowing;

  /// No description provided for @profileFollowers.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get profileFollowers;

  /// No description provided for @profileVisitors.
  ///
  /// In en, this message translates to:
  /// **'Visitors'**
  String get profileVisitors;

  /// No description provided for @profileWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get profileWallet;

  /// No description provided for @profileRecharge.
  ///
  /// In en, this message translates to:
  /// **'Recharge now'**
  String get profileRecharge;

  /// No description provided for @profileLevel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get profileLevel;

  /// No description provided for @profileMall.
  ///
  /// In en, this message translates to:
  /// **'Mall'**
  String get profileMall;

  /// No description provided for @profileBackpack.
  ///
  /// In en, this message translates to:
  /// **'Backpack'**
  String get profileBackpack;

  /// No description provided for @profileFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get profileFeedback;

  /// No description provided for @profileSetting.
  ///
  /// In en, this message translates to:
  /// **'Setting'**
  String get profileSetting;

  /// No description provided for @profileUnion.
  ///
  /// In en, this message translates to:
  /// **'Union'**
  String get profileUnion;

  /// No description provided for @levelTitle.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get levelTitle;

  /// No description provided for @levelExperience.
  ///
  /// In en, this message translates to:
  /// **'Experience: {current}/{max}'**
  String levelExperience(int current, int max);

  /// No description provided for @levelNext.
  ///
  /// In en, this message translates to:
  /// **'Next Levels'**
  String get levelNext;

  /// No description provided for @levelUnlockReward.
  ///
  /// In en, this message translates to:
  /// **'Unlock reward'**
  String get levelUnlockReward;

  /// No description provided for @mallTitle.
  ///
  /// In en, this message translates to:
  /// **'Mall'**
  String get mallTitle;

  /// No description provided for @mallHeadwear.
  ///
  /// In en, this message translates to:
  /// **'Headwear'**
  String get mallHeadwear;

  /// No description provided for @mallBubble.
  ///
  /// In en, this message translates to:
  /// **'Bubble'**
  String get mallBubble;

  /// No description provided for @mallCar.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get mallCar;

  /// No description provided for @mallEntrance.
  ///
  /// In en, this message translates to:
  /// **'Entrance'**
  String get mallEntrance;

  /// No description provided for @mallBuy.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get mallBuy;

  /// No description provided for @walletTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get walletTitle;

  /// No description provided for @walletCoinBalance.
  ///
  /// In en, this message translates to:
  /// **'Coin Balance'**
  String get walletCoinBalance;

  /// No description provided for @walletItems.
  ///
  /// In en, this message translates to:
  /// **'Wallet items'**
  String get walletItems;

  /// Application display name
  ///
  /// In en, this message translates to:
  /// **'Ahla Live'**
  String get app_name;

  /// General loading indicator text
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// General error notification
  ///
  /// In en, this message translates to:
  /// **'An error occurred, please try again'**
  String get error_occurred;

  /// Placeholder when lists or views are empty
  ///
  /// In en, this message translates to:
  /// **'No data available'**
  String get no_data;

  /// Cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Confirm button label
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Close button label
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Search input label
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Save button label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Delete button label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Edit button label
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Login button/screen title
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// Register button/screen title
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// Phone number field label
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phone_number;

  /// Verification SMS code field label
  ///
  /// In en, this message translates to:
  /// **'SMS Code'**
  String get sms_code;

  /// Button to trigger SMS code dispatch
  ///
  /// In en, this message translates to:
  /// **'Send Code'**
  String get send_code;

  /// Password field label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// Password recovery prompt
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgot_password;

  /// Terms checkbox agreement prompt
  ///
  /// In en, this message translates to:
  /// **'I agree to the Terms of Service and Privacy Policy'**
  String get agree_to_terms;

  /// Privacy policy title/link
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacy_policy;

  /// Terms of service title/link
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get terms_of_service;

  /// Discover bottom navigation tab
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get tab_discover;

  /// Messages bottom navigation tab
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get tab_message;

  /// Profile bottom navigation tab
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get tab_profile;

  /// Voice rooms bottom navigation tab
  ///
  /// In en, this message translates to:
  /// **'Rooms'**
  String get tab_room;

  /// Agency bottom navigation tab
  ///
  /// In en, this message translates to:
  /// **'Agency'**
  String get tab_agency;

  /// Profile user display name label
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get profile_user_name;

  /// No description provided for @profile_user_id.
  ///
  /// In en, this message translates to:
  /// **'ID: {id}'**
  String profile_user_id(Object id);

  /// Number of users followed
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get profile_following;

  /// Number of users following current user
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get profile_followers;

  /// Recent profile visitors count/title
  ///
  /// In en, this message translates to:
  /// **'Visitors'**
  String get profile_visitors;

  /// Edit profile button/screen title
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get edit_profile;

  /// Change user avatar action
  ///
  /// In en, this message translates to:
  /// **'Change Avatar'**
  String get change_avatar;

  /// Change user nickname action
  ///
  /// In en, this message translates to:
  /// **'Change Nickname'**
  String get change_nickname;

  /// User bio or signature
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get personal_signature;

  /// User gender label
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gender;

  /// User birthday label
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get birthday;

  /// Wallet screen title
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get wallet_title;

  /// Current coins balance label
  ///
  /// In en, this message translates to:
  /// **'Coins Balance'**
  String get wallet_coin_balance;

  /// Current diamonds balance label
  ///
  /// In en, this message translates to:
  /// **'Diamonds Balance'**
  String get wallet_diamond_balance;

  /// Recharge title
  ///
  /// In en, this message translates to:
  /// **'Recharge'**
  String get recharge;

  /// Recharge action button
  ///
  /// In en, this message translates to:
  /// **'Recharge Now'**
  String get recharge_now;

  /// Recharge ledger/history title
  ///
  /// In en, this message translates to:
  /// **'Recharge History'**
  String get recharge_history;

  /// Alert displayed when user has insufficient balance
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance, please recharge'**
  String get insufficient_balance;

  /// Alert displayed upon successful purchase or transaction
  ///
  /// In en, this message translates to:
  /// **'Transaction completed successfully'**
  String get transaction_success;

  /// Virtual items mall title
  ///
  /// In en, this message translates to:
  /// **'Mall'**
  String get mall_title;

  /// Avatar headwear accessories category
  ///
  /// In en, this message translates to:
  /// **'Headwear'**
  String get mall_headwear;

  /// Chat bubble frames category
  ///
  /// In en, this message translates to:
  /// **'Chat Bubbles'**
  String get mall_bubble;

  /// Virtual car/mount rides category
  ///
  /// In en, this message translates to:
  /// **'Entrance Rides'**
  String get mall_car;

  /// Special entrance animation effects category
  ///
  /// In en, this message translates to:
  /// **'Entrance Effects'**
  String get mall_entrance;

  /// Purchase item button label
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get mall_buy;

  /// Room screen default title
  ///
  /// In en, this message translates to:
  /// **'Voice Room'**
  String get room_title;

  /// Room admin/manager role label
  ///
  /// In en, this message translates to:
  /// **'Room Admin'**
  String get room_manager;

  /// Audience member count in room
  ///
  /// In en, this message translates to:
  /// **'Audience ({count})'**
  String room_members(int count);

  /// Action to occupy a microphone seat
  ///
  /// In en, this message translates to:
  /// **'Take Mic'**
  String get mic_up;

  /// Action to step down from a microphone seat
  ///
  /// In en, this message translates to:
  /// **'Leave Mic'**
  String get mic_down;

  /// Lock mic seat action
  ///
  /// In en, this message translates to:
  /// **'Lock Mic Seat'**
  String get lock_mic_seat;

  /// Unlock mic seat action
  ///
  /// In en, this message translates to:
  /// **'Unlock Mic Seat'**
  String get unlock_mic_seat;

  /// Kick user out of room
  ///
  /// In en, this message translates to:
  /// **'Kick Out'**
  String get kick_user;

  /// Mute user mic
  ///
  /// In en, this message translates to:
  /// **'Mute User'**
  String get mute_user;

  /// Unmute user mic
  ///
  /// In en, this message translates to:
  /// **'Unmute User'**
  String get unmute_user;

  /// Room configuration menu title
  ///
  /// In en, this message translates to:
  /// **'Room Settings'**
  String get room_settings;

  /// Room entry password
  ///
  /// In en, this message translates to:
  /// **'Room Password'**
  String get room_password;

  /// Action to join a voice room
  ///
  /// In en, this message translates to:
  /// **'Join Room'**
  String get enter_room;

  /// Notice when room reaches maximum capacity
  ///
  /// In en, this message translates to:
  /// **'The room is full'**
  String get room_is_full;

  /// Request to speak on mic queue
  ///
  /// In en, this message translates to:
  /// **'Request Mic'**
  String get apply_for_mic;

  /// Queue list of pending mic requests
  ///
  /// In en, this message translates to:
  /// **'Mic Requests'**
  String get mic_application;

  /// Locally mute user mic
  ///
  /// In en, this message translates to:
  /// **'Mute My Mic'**
  String get turn_off_mic;

  /// List of users banned from entering this room
  ///
  /// In en, this message translates to:
  /// **'Room Blacklist'**
  String get room_black_list;

  /// Send gift action button
  ///
  /// In en, this message translates to:
  /// **'Send Gift'**
  String get send_gift;

  /// Confirmation when gift is sent
  ///
  /// In en, this message translates to:
  /// **'Gift sent successfully to {name}'**
  String gift_sent_success(String name);

  /// Room lucky coin bag feature
  ///
  /// In en, this message translates to:
  /// **'Lucky Bag'**
  String get lucky_bag;

  /// Interactive mystery treasure box
  ///
  /// In en, this message translates to:
  /// **'Treasure Box'**
  String get treasure_box;

  /// Action to open treasure box
  ///
  /// In en, this message translates to:
  /// **'Open Box'**
  String get open_box;

  /// VIP badge/title
  ///
  /// In en, this message translates to:
  /// **'VIP'**
  String get vip;

  /// Super VIP badge/title
  ///
  /// In en, this message translates to:
  /// **'SVIP'**
  String get svip;

  /// List of VIP privileges
  ///
  /// In en, this message translates to:
  /// **'VIP Privileges'**
  String get vip_privileges;

  /// List of Super VIP privileges
  ///
  /// In en, this message translates to:
  /// **'SVIP Privileges'**
  String get svip_privileges;

  /// Action to activate VIP membership
  ///
  /// In en, this message translates to:
  /// **'Activate VIP'**
  String get activate_vip;

  /// Action to extend VIP membership
  ///
  /// In en, this message translates to:
  /// **'Renew VIP'**
  String get renew_vip;

  /// Current VIP tier level
  ///
  /// In en, this message translates to:
  /// **'VIP Level {level}'**
  String vip_level(int level);

  /// Exclusive VIP tier reward
  ///
  /// In en, this message translates to:
  /// **'Exclusive Reward'**
  String get exclusive_reward;

  /// Union / Guild organization title
  ///
  /// In en, this message translates to:
  /// **'Union'**
  String get union;

  /// Agency organization title
  ///
  /// In en, this message translates to:
  /// **'Agency'**
  String get agency;

  /// Action to apply to an agency
  ///
  /// In en, this message translates to:
  /// **'Join Agency'**
  String get join_agency;

  /// Action to register a new agency
  ///
  /// In en, this message translates to:
  /// **'Create Agency'**
  String get create_agency;

  /// Agency leader / owner label
  ///
  /// In en, this message translates to:
  /// **'Agency Owner'**
  String get agency_leader;

  /// List of hosts in an agency
  ///
  /// In en, this message translates to:
  /// **'Agency Hosts'**
  String get agency_members;

  /// Policy and commission guidelines for agencies
  ///
  /// In en, this message translates to:
  /// **'Agency Rules'**
  String get agency_rules;

  /// Settings menu title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get profile_setting;

  /// Language selection item
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get change_language;

  /// Arabic language option
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get arabic;

  /// English language option
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// Action to clean cached files
  ///
  /// In en, this message translates to:
  /// **'Clear Cache'**
  String get clear_cache;

  /// Log out account action
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logout;

  /// Permanent account deletion option
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get delete_account;

  /// Block user action
  ///
  /// In en, this message translates to:
  /// **'Block User'**
  String get block_user;

  /// Unblock user action
  ///
  /// In en, this message translates to:
  /// **'Unblock User'**
  String get unblock_user;

  /// Report abusive user action
  ///
  /// In en, this message translates to:
  /// **'Report User'**
  String get report_user;

  /// General blacklist of blocked accounts
  ///
  /// In en, this message translates to:
  /// **'Blocked Accounts'**
  String get blacklist;

  /// Chat tab/title
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// Send message button label
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send_message;

  /// Chat input placeholder hint
  ///
  /// In en, this message translates to:
  /// **'Say something...'**
  String get type_message;

  /// Audio message title/tag
  ///
  /// In en, this message translates to:
  /// **'Voice Message'**
  String get voice_message;

  /// Empty state message for chat screen
  ///
  /// In en, this message translates to:
  /// **'No messages yet, start chatting!'**
  String get no_messages_yet;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
