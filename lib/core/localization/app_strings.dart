import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

class AppStrings {
  static bool isArabic(BuildContext context) {
    return Localizations.maybeLocaleOf(context)?.languageCode != 'en';
  }

  static String tr(BuildContext context, String ar, String en) {
    return isArabic(context) ? ar : en;
  }

  /// Direction-aware back icon: points right (East) in RTL, points left (West) in LTR
  static IconData backIcon(BuildContext context) {
    return isArabic(context) ? Icons.arrow_forward_ios : Icons.arrow_back_ios_new;
  }

  /// Direction-aware forward / chevron icon: points left in RTL, points right in LTR
  static IconData forwardIcon(BuildContext context) {
    return isArabic(context) ? Icons.arrow_back_ios_new : Icons.arrow_forward_ios;
  }

  static final Map<String, String> _dict = {
    // Navigation / Tabs
    'استكشاف': 'Discover',
    'الرسائل': 'Messages',
    'أنا': 'Profile',
    'حسابي': 'My Profile',
    'الغرف': 'Rooms',
    'متابعة': 'Following',
    'المتابعين': 'Followers',
    'المتابعون': 'Followers',
    'الزوار': 'Visitors',
    'المزيد': 'More',
    'الكل': 'All',
    'الرئيسية': 'Home',
    'شائع': 'Popular',
    'الأحدث': 'Latest',

    // Agency & Unions Hub
    'مركز الوكالات': 'Agency Center',
    'وكالة المضيفين': 'Host Agency',
    'وكالة المضيف': 'Host Agency',
    'وكالة الشحن': 'Recharge Agency',
    'وكالة الشحن والرواتب': 'Recharge & Salary Agency',
    'مركز BD': 'BD Center',
    'مركز تطوير الأعمال (BD Center)': 'Business Development Center (BD Center)',
    'إدارة الوكالة': 'Manage Agency',
    'بيانات الوكالة': 'Agency Details',
    'طلب فتح وكالة': 'Open Agency Application',
    'طلب فتح وكالة مضيفين جديد': 'New Host Agency Request',
    'اسم الوكالة': 'Agency Name',
    'اسم الوكالة *': 'Agency Name *',
    'معرف الوكالة': 'Agency ID',
    'آيدي الوكالة': 'Agency ID',
    'شعار الوكالة': 'Agency Logo',
    'وصف الوكالة': 'Agency Description',
    'وصف الوكالة (اختياري)': 'Agency Description (Optional)',
    'وكالة مضيفين معتمدة': 'Certified Host Agency',
    'آيدي المشرف أو مسؤول الـ BD *': 'Supervisor / BD ID *',
    'المشرف المعتمد': 'Certified Supervisor',
    'جاري التحقق من هوية المشرف...': 'Verifying supervisor identity...',
    'رقم الهاتف / واتساب (اختياري)': 'Phone / WhatsApp (Optional)',
    'تأكيد إنشاء الوكالة': 'Confirm Create Agency',
    'قيد المراجعة': 'Pending Review',
    'مقبول': 'Approved',
    'مرفوض': 'Rejected',
    'أعضاء الوكالة': 'Agency Members',
    'قائمة المضيفين': 'Hosts List',
    'إضافة مضيف': 'Add Host',
    'دعوة مضيف': 'Invite Host',
    'سحب أرباح': 'Withdraw Earnings',
    'محفظة الوكالة': 'Agency Wallet',
    'التارجت الشهري': 'Monthly Target',
    'المراحل والتارجت': 'Milestones & Targets',
    'أرباح الوكالة': 'Agency Profits',
    'عمولة الوكالة': 'Agency Commission',
    'عمولة المضيف': 'Host Share',
    'عمولة المشرف': 'Supervisor Share',

    // Room & Audio
    'صوت الغرفة': 'Room Volume',
    'كتم صوت الغرفة': 'Mute Room',
    'كتم صوت الغرفة بالكامل': 'Deafen Room Audio',
    'إلغاء كتم المايك': 'Unmute Mic',
    'كتم المايك': 'Mute Mic',
    'صعود المايك': 'Take Mic',
    'إنزال من المايك': 'Kick Off Mic',
    'دعوة للمايك': 'Invite to Mic',
    'قفل المقعد': 'Lock Seat',
    'إلغاء قفل المقعد': 'Unlock Seat',
    'طرد من الغرفة': 'Kick Out',
    'تعيين كمسؤول': 'Set as Admin',
    'إلغاء تعيين مسؤول': 'Remove Admin',
    'إضافة للقائمة السوداء': 'Blacklist',
    'إلغاء الحظر': 'Unban',
    'رسالة خاصة': 'Private Message',
    'معلومات المستخدم': 'User Details',
    'صاحب الغرفة': 'Room Owner',
    'شكل المقاعد': 'Seat Style',
    'عدد المقاعد': 'Seat Count',
    'كلاسيكي': 'Classic',
    'لعبة': 'Game',
    'تم قفل الدردشة من قبل الإدارة': 'Chat is locked by admins',
    'مغادرة الغرفة': 'Leave Room',
    'أدخل الغرفة': 'Join Room',
    'إنشاء غرفة': 'Create Room',
    'اسم الغرفة': 'Room Name',
    'كلمة المرور': 'Password',
    'قفل الغرفة': 'Lock Room',

    // Gifts, Store & VIP
    'إرسال هدية': 'Send Gift',
    'صندوق الهدايا': 'Gift Box',
    'إرسال إلى:': 'Send to:',
    'إرسال': 'Send',
    'فاخر': 'Luxury',
    'الحظ': 'Lucky',
    'الارتباط': 'CP',
    'الحقيبة': 'Backpack',
    'متجر': 'Mall',
    'المتجر': 'Mall',
    'المحفظة': 'Wallet',
    'شراء': 'Buy',
    'كوينز': 'Coins',
    'ماس': 'Diamonds',
    'ألماس': 'Diamonds',
    'رصيد': 'Balance',
    'رصيد العملات': 'Coins Balance',
    'رصيد الألماس': 'Diamonds Balance',
    'شحن': 'Recharge',
    'اشحن الآن': 'Recharge Now',
    'سجل الشحن': 'Recharge History',
    'المستوى': 'Level',
    'مستوى الثراء': 'Wealth Level',
    'مستوى الشحن': 'Recharge Level',
    'مستوى الجواهر': 'Gems Level',
    'الشارات': 'Badges',
    'القلائد': 'Necklaces',
    'إطارات': 'Frames',
    'السيارات': 'Cars',
    'الفقاعات': 'Bubbles',
    'المدخل': 'Entrance Effects',
    'القبعات': 'Headwear',
    'VIP': 'VIP',
    'ترقية VIP': 'Upgrade VIP',
    'مميزات VIP': 'VIP Benefits',

    // Countries
    'اختر الدولة': 'Select Country',
    'الدولة': 'Country',
    'عالمي': 'Global',
    'مصر': 'Egypt',
    'السعودية': 'Saudi Arabia',
    'المملكة العربية السعودية': 'Saudi Arabia',
    'الإمارات': 'UAE',
    'الامارات': 'UAE',
    'الإمارات العربية المتحدة': 'UAE',
    'الكويت': 'Kuwait',
    'العراق': 'Iraq',
    'قطر': 'Qatar',
    'البحرين': 'Bahrain',
    'عمان': 'Oman',
    'عُمان': 'Oman',
    'الأردن': 'Jordan',
    'المغرب': 'Morocco',
    'الجزائر': 'Algeria',
    'تونس': 'Tunisia',
    'السودان': 'Sudan',
    'اليمن': 'Yemen',
    'سوريا': 'Syria',
    'لبنان': 'Lebanon',
    'فلسطين': 'Palestine',
    'ليبيا': 'Libya',
    'تركيا': 'Turkey',
    'الولايات المتحدة الأمريكية': 'USA',
    'المملكة المتحدة': 'UK',

    // General Actions & Dialogs
    'تأكيد': 'Confirm',
    'إلغاء': 'Cancel',
    'حفظ': 'Save',
    'تعديل': 'Edit',
    'حذف': 'Delete',
    'إغلاق': 'Close',
    'بحث': 'Search',
    'تم': 'Done',
    'نجاح': 'Success',
    'خطأ': 'Error',
    'تنبيه': 'Notice',
    'الوصف': 'Description',
    'الإعدادات': 'Settings',
    'تسجيل الخروج': 'Log Out',
    'اللغة': 'Language',
    'العربية': 'Arabic',
    'الإنجليزية': 'English',
    'الآيدي': 'ID',
    'تعديل الملف الشخصي': 'Edit Profile',
    'تغيير الصورة': 'Change Photo',
    'الاسم': 'Name',
    'اسم المستخدم': 'Username',
    'النبذة الشخصية': 'Bio',
    'النوع': 'Gender',
    'ذكر': 'Male',
    'أنثى': 'Female',
    'العمر': 'Age',
    'تحديث': 'Update',
    'تحديث الآن': 'Update Now',
    'تثبيت': 'Install',
    'لاحقاً': 'Later',
    'جاري التنزيل...': 'Downloading...',
    'تم التنزيل — اضغط للتثبيت': 'Downloaded — Tap to Install',
  };

  static String auto(BuildContext context, String text) {
    if (isArabic(context)) return text;
    return _dict[text] ?? text;
  }
}

extension AppLocalizationExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  bool get isAr => AppStrings.isArabic(this);
  String tr(String ar, String en) => AppStrings.tr(this, ar, en);
  String trAuto(String text) => AppStrings.auto(this, text);
  IconData get backIcon => AppStrings.backIcon(this);
  IconData get forwardIcon => AppStrings.forwardIcon(this);
}

