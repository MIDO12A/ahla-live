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
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  // Legacy compatibility getters
  String get tabDiscover;
  String get tabMessage;
  String get tabProfile;
  String get profileUserName;
  String profileUserId(String id);
  String get profileFollowing;
  String get profileFollowers;
  String get profileVisitors;
  String get profileWallet;
  String get profileRecharge;
  String get profileLevel;
  String get profileMall;
  String get profileBackpack;
  String get profileFeedback;
  String get profileSetting;
  String get profileUnion;
  String get levelTitle;
  String levelExperience(int current, int max);
  String get levelNext;
  String get levelUnlockReward;
  String get mallTitle;
  String get mallHeadwear;
  String get mallBubble;
  String get mallCar;
  String get mallEntrance;
  String get mallBuy;
  String get walletTitle;
  String get walletCoinBalance;
  String get walletItems;

  // --- GENERAL ---
  String get app_name;
  String get loading;
  String get error_occurred;
  String get no_data;
  String get cancel;
  String get confirm;
  String get close;
  String get search;
  String get save;
  String get delete;
  String get edit;

  // --- AUTH ---
  String get login;
  String get register;
  String get phone_number;
  String get sms_code;
  String get send_code;
  String get password;
  String get forgot_password;
  String get agree_to_terms;
  String get privacy_policy;
  String get terms_of_service;

  // --- NAVIGATION ---
  String get tab_discover;
  String get tab_message;
  String get tab_profile;
  String get tab_room;
  String get tab_agency;

  // --- PROFILE ---
  String get edit_profile;
  String get change_avatar;
  String get change_nickname;
  String get personal_signature;
  String get gender;
  String get birthday;

  // --- WALLET & MALL ---
  String get wallet_diamond_balance;
  String get recharge;
  String get recharge_now;
  String get recharge_history;
  String get insufficient_balance;
  String get transaction_success;

  // --- ROOM & MIC ---
  String get room_title;
  String get room_manager;
  String room_members(int count);
  String get mic_up;
  String get mic_down;
  String get lock_mic_seat;
  String get unlock_mic_seat;
  String get kick_user;
  String get mute_user;
  String get unmute_user;
  String get room_settings;
  String get room_password;
  String get enter_room;
  String get room_is_full;
  String get apply_for_mic;
  String get mic_application;
  String get turn_off_mic;
  String get room_black_list;

  // --- GIFTS ---
  String get send_gift;
  String gift_sent_success(String name);
  String get lucky_bag;
  String get treasure_box;
  String get open_box;

  // --- VIP & AGENCY ---
  String get vip;
  String get svip;
  String get vip_privileges;
  String get svip_privileges;
  String get activate_vip;
  String get renew_vip;
  String vip_level(int level);
  String get exclusive_reward;
  String get union;
  String get agency;
  String get join_agency;
  String get create_agency;
  String get agency_leader;
  String get agency_members;
  String get agency_rules;

  // --- SETTINGS ---
  String get change_language;
  String get arabic;
  String get english;
  String get clear_cache;
  String get logout;
  String get delete_account;
  String get block_user;
  String get unblock_user;
  String get report_user;
  String get blacklist;

  // --- CHAT ---
  String get chat;
  String get send_message;
  String get type_message;
  String get voice_message;
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
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale".');
}
