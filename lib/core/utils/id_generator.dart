import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../services/supabase_data_service.dart';
import '../../services/supabase_service.dart';

/// خدمة توليد أرقام تعريف المستخدمين (User ID Generator)
/// توليد أرقام فريدة آمنة ومتسقة (6-7 أرقام)
class UserIdGenerator {
  static final Random _random = Random.secure();
  static final UserIdGenerator _instance = UserIdGenerator._internal();
  factory UserIdGenerator() => _instance;
  UserIdGenerator._internal();

  /// توليد رقم تعريف جديد فريد (6-7 أرقام)
  Future<String> generateUniqueId({
    int minDigits = 6,
    int maxDigits = 7,
    int maxRetries = 10,
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      // توليد رقم عشوائي
      final customId = _generateRandomId(minDigits, maxDigits);
      
      // التحقق من عدم وجود الرقم في قاعدة البيانات
      final isUnique = await checkIdUniqueness(customId);
      
      if (isUnique) {
        return customId;
      }
      
      // إذا لم يكن فريداً، حاول مرة أخرى
      await Future.delayed(Duration(milliseconds: 100 * (attempt + 1)));
    }
    
    // في حالة فشل المحاولات، استخدم رقم عشوائي فريد يبدأ من 111111 فما فوق
    final ts = (DateTime.now().millisecondsSinceEpoch % 888888) + 111111;
    return ts.toString();
  }

  /// توليد رقم عشوائي (بدون التحقق من التفرد) - يبدأ من 111111 فما فوق
  String _generateRandomId(int minDigits, int maxDigits) {
    final digits = (minDigits + _random.nextInt(maxDigits - minDigits + 1)).clamp(6, 7);
    final min = digits == 6 ? 111111 : 1000000;
    final max = digits == 6 ? 999999 : 9999999;
    return (min + _random.nextInt(max - min + 1)).toString();
  }

  /// التحقق من تفرد الرقم في Supabase و Firestore
  /// أصبحت عامة للاستخدام من خدمات أخرى (مثل الهجرة)
  Future<bool> checkIdUniqueness(String customId) async {
    try {
      // 1. التحقق من Supabase (مستخدمين وغرف)
      try {
        final existing = await SupabaseDataService().findUserByIdOrCustomId(customId);
        if (existing != null) {
          return false; // الرقم موجود بالفعل في Supabase
        }
        final existingRoom = await SupabaseDataService().getRoom(customId);
        if (existingRoom != null) {
          return false; // الرقم مستخدم كـ ID غرفة بالفعل
        }
      } catch (e) {
        debugPrint('UserIdGenerator: Supabase check error: $e');
      }

      return true; // الرقم فريد
    } catch (e) {
      debugPrint('UserIdGenerator: Uniqueness check failed: $e');
      return true;
    }
  }


  /// توليد رقم تعريف مؤقت للاستخدام المحلي
  /// TODO: استخدام للأغراض المؤقتة فقط
  String generateTempId() {
    return 'temp_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// التحقق من صحة تنسيق الـ ID (أرقام فقط 6-7 خانات)
  static bool isValidCustomId(String customId) {
    if (customId.trim().isEmpty) return false;
    
    // يجب أن يكون أرقام فقط
    if (!RegExp(r'^[0-9]+$').hasMatch(customId)) return false;
    
    // التحقق من الطول (6-7 أرقام فقط)
    if (customId.length < 6 || customId.length > 7) return false;
    
    // التحقق من أنه رقم صحيح
    final value = int.tryParse(customId);
    return value != null && value >= 111111;
  }

  /// تنظيف وتطبيع الـ ID - يزيل الحروف ويحتفظ بالأرقام فقط
  /// إذا كان الناتج أقل من 6 أرقام، يولد رقم جديد
  static String normalizeCustomId(String customId) {
    if (customId.isEmpty) return '';
    
    // إزالة أي رموز غير رقمية
    final cleaned = customId.replaceAll(RegExp(r'[^0-9]'), '');
    
    // إذا كان الناتج صالحاً (6-7 أرقام)، أرجعه
    if (isValidCustomId(cleaned)) return cleaned;
    
    // وإلا، أرجع سلسلة فارغة ليتم توليد رقم جديد
    return '';
  }

  /// تحويل ID الأبجدية الرقمية إلى رقم رقمي بحت (6-7 أرقام)
  /// يستخدم للمستخدمين الحاليين الذين لديهم IDs أبجدية رقمية
  static String migrateToNumericId(String alphanumericId) {
    if (alphanumericId.isEmpty) return '';
    
    // إذا كان بالفعل رقمي صالح، أرجعه كما هو
    if (isValidCustomId(alphanumericId)) return alphanumericId;
    
    // استخراج الأرقام فقط
    final digitsOnly = alphanumericId.replaceAll(RegExp(r'[^0-9]'), '');
    
    // إذا كانت الأرقام المستخرجة صالحة، استخدمها
    if (isValidCustomId(digitsOnly)) return digitsOnly;
    
    // وإلا، استخدم hash code لتوليد رقم جديد ثابت للمستخدم نفسه
    final hash = alphanumericId.hashCode.abs();
    final numericId = ((hash % 8888888) + 1111111).toString();
    
    // تأكد من أنه 6-7 أرقام
    if (numericId.length > 7) {
      return numericId.substring(0, 7);
    }
    return numericId;
  }

  /// توليد batch من الأرقام الفريدة
  /// TODO: استخدام للاختبار أو التخطيط المستقبلي
  Future<List<String>> generateBatch({
    int count = 10,
    int minDigits = 6,
    int maxDigits = 10,
  }) async {
    final List<String> ids = [];
    final Set<String> usedIds = {};

    while (ids.length < count) {
      final id = _generateRandomId(minDigits, maxDigits);
      
      if (!usedIds.contains(id)) {
        final isUnique = await checkIdUniqueness(id);
        if (isUnique) {
          ids.add(id);
          usedIds.add(id);
        }
      }
    }

    return ids;
  }

  /// تحويل رقم إلى تنسيق آمن للعرض
  /// TODO: استخدام لتنسيق الـ ID للعرض
  static String formatForDisplay(String customId, {bool showHash = true}) {
    final normalized = normalizeCustomId(customId);
    if (normalized.isEmpty) return '------';
    return showHash ? '#$normalized' : normalized;
  }

  /// استخراج الـ ID من UID (لأغراض الاحتياط)
  /// TODO: استخدام كحل احتياطي إذا فشل توليد الـ ID
  static String extractIdFromUid(String uid) {
    if (uid.isEmpty) return '';
    
    // إزالة أي شرطات
    final cleaned = uid.replaceAll('-', '');
    
    // أخذ أول 6 أو 7 أرقام إذا كانت رقمية بالكامل وقيمتها >= 111111
    final digitsOnly = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length >= 6) {
      final sub = digitsOnly.substring(0, 7);
      final val = int.tryParse(sub) ?? 0;
      if (val >= 111111) return val.toString();
    }
    
    // استخدام hash code كحل احتياطي يبدأ من 111111
    final hash = cleaned.hashCode.abs();
    return ((hash % 888888) + 111111).toString();
  }
}

/// دالة مساعدة لتوليد رقم تعريف سريع (بدون التحقق من التفرد) - أرقام فقط بين 111111 و 9999999
String generateQuickCustomId({int digits = 6}) {
  final d = digits.clamp(6, 7);
  final random = Random.secure();
  final min = d == 6 ? 111111 : 1000000;
  final max = d == 6 ? 999999 : 9999999;
  return (min + random.nextInt(max - min + 1)).toString();
}