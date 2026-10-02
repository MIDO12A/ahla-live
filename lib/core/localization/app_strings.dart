import 'package:flutter/material.dart';

class AppStrings {
  static bool isArabic(BuildContext context) {
    return Localizations.maybeLocaleOf(context)?.languageCode != 'en';
  }

  static String tr(BuildContext context, String ar, String en) {
    return isArabic(context) ? ar : en;
  }

  static final Map<String, String> _dict = {
    // Navigation / Tabs
    'استكشاف': 'Discover',
    'الرسائل': 'Messages',
    'أنا': 'Profile',
    'الغرف': 'Rooms',
    'متابعة': 'Following',
    'المتابعين': 'Followers',
    'المتابعون': 'Followers',
    'الزوار': 'Visitors',
    'المزيد': 'More',
    'الكل': 'All',

    // Room & Seats
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

    // Gifts & Store
    'إرسال هدية': 'Send Gift',
    'صندوق الهدايا': 'Gift Box',
    'إرسال إلى:': 'Send to:',
    'إرسال': 'Send',
    'شائع': 'Popular',
    'فاخر': 'Luxury',
    'الحظ': 'Lucky',
    'الارتباط': 'CP',
    'الحقيبة': 'Backpack',
    'متجر': 'Mall',
    'المحفظة': 'Wallet',
    'شراء': 'Buy',
    'كوينز': 'Coins',
    'رصيد': 'Balance',
    'شحن': 'Recharge',

    // Countries
    'اختر الدولة': 'Select Country',
    'الدولة': 'Country',
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
    'إنشاء غرفة': 'Create Room',
    'اسم الغرفة': 'Room Name',
    'الوصف': 'Description',
    'كلمة المرور': 'Password',
    'قفل الغرفة': 'Lock Room',
    'الإعدادات': 'Settings',
    'تسجيل الخروج': 'Log Out',
    'اللغة': 'Language',
    'العربية': 'Arabic',
    'الإنجليزية': 'English',
    'المستوى': 'Level',
    'الآيدي': 'ID',
    'تعديل الملف الشخصي': 'Edit Profile',
    'تغيير الصورة': 'Change Photo',
    'الاسم': 'Name',
    'النبذة الشخصية': 'Bio',
    'النوع': 'Gender',
    'ذكر': 'Male',
    'أنثى': 'Female',
  };

  static String auto(BuildContext context, String text) {
    if (isArabic(context)) return text;
    return _dict[text] ?? text;
  }
}

extension AppLocalizationExtension on BuildContext {
  bool get isAr => AppStrings.isArabic(this);
  String tr(String ar, String en) => AppStrings.tr(this, ar, en);
  String trAuto(String text) => AppStrings.auto(this, text);
}
