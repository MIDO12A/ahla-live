// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get tabDiscover => 'استكشاف';

  @override
  String get tabMessage => 'الرسائل';

  @override
  String get tabProfile => 'حسابي';

  @override
  String get profileUserName => 'اسم المستخدم';

  @override
  String profileUserId(String id) {
    return 'الآيدي: $id';
  }

  @override
  String get profileFollowing => 'متابع';

  @override
  String get profileFollowers => 'المتابعين';

  @override
  String get profileVisitors => 'الزوار';

  @override
  String get profileWallet => 'الحقيبة';

  @override
  String get profileRecharge => 'اشحن الآن';

  @override
  String get profileLevel => 'المستوى';

  @override
  String get profileMall => 'المتجر';

  @override
  String get profileBackpack => 'الحقيبة';

  @override
  String get profileFeedback => 'الملاحظات';

  @override
  String get profileSetting => 'الإعدادات';

  @override
  String get profileUnion => 'النقابة';

  @override
  String get levelTitle => 'المستوى';

  @override
  String levelExperience(int current, int max) {
    return 'الخبرة: $current/$max';
  }

  @override
  String get levelNext => 'المستويات القادمة';

  @override
  String get levelUnlockReward => 'فتح الجائزة';

  @override
  String get mallTitle => 'المتجر';

  @override
  String get mallHeadwear => 'القبعات';

  @override
  String get mallBubble => 'الفقاعات';

  @override
  String get mallCar => 'السيارات';

  @override
  String get mallEntrance => 'المدخل';

  @override
  String get mallBuy => 'شراء';

  @override
  String get walletTitle => 'الحقيبة';

  @override
  String get walletCoinBalance => 'رصيد العملات';

  @override
  String get walletItems => 'عناصر الحقيبة';

  @override
  String get app_name => 'أحلى لايف';

  @override
  String get loading => 'جاري التحميل...';

  @override
  String get error_occurred => 'حدث خطأ، يرجى المحاولة مرة أخرى';

  @override
  String get no_data => 'لا توجد بيانات متاحة';

  @override
  String get cancel => 'إلغاء';

  @override
  String get confirm => 'تأكيد';

  @override
  String get close => 'إغلاق';

  @override
  String get search => 'بحث';

  @override
  String get save => 'حفظ';

  @override
  String get delete => 'حذف';

  @override
  String get edit => 'تعديل';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get register => 'إنشاء حساب جديد';

  @override
  String get phone_number => 'رقم الهاتف';

  @override
  String get sms_code => 'رمز التحقق';

  @override
  String get send_code => 'إرسال الرمز';

  @override
  String get password => 'كلمة المرور';

  @override
  String get forgot_password => 'نسيت كلمة المرور؟';

  @override
  String get agree_to_terms => 'أوافق على شروط الخدمة وسياسة الخصوصية';

  @override
  String get privacy_policy => 'سياسة الخصوصية';

  @override
  String get terms_of_service => 'شروط الخدمة';

  @override
  String get tab_discover => 'استكشاف';

  @override
  String get tab_message => 'الرسائل';

  @override
  String get tab_profile => 'حسابي';

  @override
  String get tab_room => 'الغرف';

  @override
  String get tab_agency => 'الوكالة';

  @override
  String get profile_user_name => 'اسم المستخدم';

  @override
  String profile_user_id(Object id) {
    return 'الآيدي: $id';
  }

  @override
  String get profile_following => 'متابع';

  @override
  String get profile_followers => 'المتابعين';

  @override
  String get profile_visitors => 'الزوار';

  @override
  String get edit_profile => 'تعديل الملف الشخصي';

  @override
  String get change_avatar => 'تغيير الصورة الشخصية';

  @override
  String get change_nickname => 'تعديل الاسم المستعار';

  @override
  String get personal_signature => 'النبذة الشخصية';

  @override
  String get gender => 'الجنس';

  @override
  String get birthday => 'تاريخ الميلاد';

  @override
  String get wallet_title => 'المحفظة';

  @override
  String get wallet_coin_balance => 'رصيد الكوينز';

  @override
  String get wallet_diamond_balance => 'رصيد الألماس';

  @override
  String get recharge => 'شحن الرصيد';

  @override
  String get recharge_now => 'اشحن الآن';

  @override
  String get recharge_history => 'سجل الشحن';

  @override
  String get insufficient_balance => 'الرصيد غير كافٍ، يرجى الشحن أولاً';

  @override
  String get transaction_success => 'تمت العملية بنجاح';

  @override
  String get mall_title => 'المتجر';

  @override
  String get mall_headwear => 'إطارات الرأس';

  @override
  String get mall_bubble => 'فقاعات الدردشة';

  @override
  String get mall_car => 'مركبات الدخول';

  @override
  String get mall_entrance => 'مؤثرات الدخول الفاخرة';

  @override
  String get mall_buy => 'شراء';

  @override
  String get room_title => 'غرفة صوتية';

  @override
  String get room_manager => 'مدير الغرفة';

  @override
  String room_members(int count) {
    return 'المستمعين ($count)';
  }

  @override
  String get mic_up => 'صعود المايك';

  @override
  String get mic_down => 'إنزال من المايك';

  @override
  String get lock_mic_seat => 'قفل المقعد';

  @override
  String get unlock_mic_seat => 'فتح المقعد';

  @override
  String get kick_user => 'طرد من الغرفة';

  @override
  String get mute_user => 'كتم المايك';

  @override
  String get unmute_user => 'إلغاء كتم المايك';

  @override
  String get room_settings => 'إعدادات الغرفة';

  @override
  String get room_password => 'كلمة مرور الغرفة';

  @override
  String get enter_room => 'دخول الغرفة';

  @override
  String get room_is_full => 'الغرفة ممتلئة بالكامل';

  @override
  String get apply_for_mic => 'طلب صعود المايك';

  @override
  String get mic_application => 'طلبات المايك';

  @override
  String get turn_off_mic => 'إغلاق مايكي';

  @override
  String get room_black_list => 'القائمة السوداء للغرفة';

  @override
  String get send_gift => 'إرسال هدية';

  @override
  String gift_sent_success(String name) {
    return 'تم إرسال الهدية بنجاح إلى $name';
  }

  @override
  String get lucky_bag => 'حقيبة الحظ';

  @override
  String get treasure_box => 'صندوق الكنز';

  @override
  String get open_box => 'فتح الصندوق';

  @override
  String get vip => 'VIP';

  @override
  String get svip => 'SVIP';

  @override
  String get vip_privileges => 'مميزات VIP';

  @override
  String get svip_privileges => 'مميزات SVIP الخارقة';

  @override
  String get activate_vip => 'تفعيل VIP';

  @override
  String get renew_vip => 'تجديد اشتراك VIP';

  @override
  String vip_level(int level) {
    return 'مستوى VIP $level';
  }

  @override
  String get exclusive_reward => 'مكافأة حصرية';

  @override
  String get union => 'النقابة';

  @override
  String get agency => 'الوكالة';

  @override
  String get join_agency => 'الانضمام لوكالة';

  @override
  String get create_agency => 'تأسيس وكالة';

  @override
  String get agency_leader => 'صاحب الوكالة';

  @override
  String get agency_members => 'مضيفو الوكالة';

  @override
  String get agency_rules => 'قوانين وتارجت الوكالة';

  @override
  String get profile_setting => 'الإعدادات';

  @override
  String get change_language => 'لغة التطبيق';

  @override
  String get arabic => 'العربية';

  @override
  String get english => 'English';

  @override
  String get clear_cache => 'مسح الذاكرة المؤقتة';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get delete_account => 'حذف الحساب نهائياً';

  @override
  String get block_user => 'حظر المستخدم';

  @override
  String get unblock_user => 'إلغاء الحظر';

  @override
  String get report_user => 'إبلاغ عن إساءة';

  @override
  String get blacklist => 'قائمة الحظر العامة';

  @override
  String get chat => 'الدردشة';

  @override
  String get send_message => 'إرسال';

  @override
  String get type_message => 'اكتب رسالة هنا...';

  @override
  String get voice_message => 'رسالة صوتية';

  @override
  String get no_messages_yet => 'لا توجد رسائل بعد، ابدأ المحادثة الآن!';
}
