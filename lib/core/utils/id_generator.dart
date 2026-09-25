import 'package:firebase_core/firebase_core.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// خدمة توليد أرقام تعريف المستخدمين (User ID Generator)
/// توليد أرقام فريدة آمنة ومتسقة (6-10 أرقام)
class UserIdGenerator {
  static final Random _random = Random.secure();
  static final UserIdGenerator _instance = UserIdGenerator._internal();
  factory UserIdGenerator() => _instance;
  UserIdGenerator._internal();

  /// توليد رقم تعريف جديد فريد (6-10 أرقام)
  /// TODO: استخدام هذه الدالة لضمان عدم تكرار الـ IDs
  Future<String> generateUniqueId({
    int minDigits = 6,
    int maxDigits = 10,
    int maxRetries = 10,
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      // توليد رقم عشوائي
      final customId = _generateRandomId(minDigits, maxDigits);
      
      // التحقق من عدم وجود الرقم في قاعدة البيانات
      final isUnique = await _checkIdUniqueness(customId);
      
      if (isUnique) {
        return customId;
      }
      
      // إذا لم يكن فريداً، حاول مرة أخرى
      await Future.delayed(Duration(milliseconds: 100 * (attempt + 1)));
    }
    
    // في حالة فشل جميع المحاولات، استخدم الرقم مع timestamp لضمان التفرد
    final timestamp = DateTime.now().millisecondsSinceEpoch % 1000000;
    return '${_generateRandomId(minDigits, maxDigits - 3)}$timestamp';
  }

  /// توليد رقم عشوائي (بدون التحقق من التفرد)
  /// FIX: توليد رقم آمن وواضح من أرقام فقط
  String _generateRandomId(int minDigits, int maxDigits) {
    final digits = minDigits + _random.nextInt(maxDigits - minDigits + 1);
    final min = pow(10, digits - 1).toInt();
    final max = pow(10, digits).toInt() - 1;
    return (min + _random.nextInt(max - min + 1)).toString();
  }

  /// التحقق من تفرد الرقم في Firestore
  Future<bool> _checkIdUniqueness(String customId) async {
    try {
      // التحقق من Firestore
      final firestoreCheck = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
          .collection('users')
          .where('custom_id', isEqualTo: customId)
          .limit(1)
          .get();
      
      if (firestoreCheck.docs.isNotEmpty) {
        return false; // الرقم موجود بالفعل
      }

      return true; // الرقم فريد
    } catch (e) {
      debugPrint('UserIdGenerator: Uniqueness check failed: $e');
      // في حالة الخطأ، افترض أن الرقم فريد (fallback)
      return true;
    }
  }

  /// توليد رقم تعريف مؤقت للاستخدام المحلي
  /// TODO: استخدام للأغراض المؤقتة فقط
  String generateTempId() {
    return 'temp_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// التحقق من صحة تنسيق الـ ID
  /// FIX: التحقق من أن الـ ID يحتوي على أرقام فقط
  static bool isValidCustomId(String customId) {
    if (customId.isEmpty) return false;
    
    // إزالة أي مسافات أو رموز
    final cleaned = customId.replaceAll(RegExp(r'[^0-9]'), '');
    
    // التحقق من الطول (6-10 أرقام)
    if (cleaned.length < 6 || cleaned.length > 10) return false;
    
    // التحقق من أنه أرقام فقط
    return int.tryParse(cleaned) != null;
  }

  /// تنظيف وتطبيع الـ ID
  /// TODO: استخدام لتنظيف البيانات القديمة
  static String normalizeCustomId(String customId) {
    if (customId.isEmpty) return '';
    
    // إزالة أي رموز غير رقمية
    final cleaned = customId.replaceAll(RegExp(r'[^0-9]'), '');
    
    // التحقق من الصحة
    if (!isValidCustomId(cleaned)) return '';
    
    return cleaned;
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
        final isUnique = await _checkIdUniqueness(id);
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
    
    // أخذ آخر 8 أرقام إذا كانت رقمية
    if (cleaned.length >= 8) {
      final last8 = cleaned.substring(cleaned.length - 8);
      if (int.tryParse(last8) != null) {
        return last8;
      }
    }
    
    // استخدام hash code كحل احتياطي
    final hash = cleaned.hashCode.abs();
    return (hash % 9000000 + 1000000).toString();
  }
}

/// دالة مساعدة لتوليد رقم تعريف سريع (بدون التحقق من التفرد)
/// TODO: استخدام فقط للحالات التي لا تتطلب تفرد فوري
String generateQuickCustomId({int digits = 8}) {
  final random = Random.secure();
  final min = pow(10, digits - 1).toInt();
  final max = pow(10, digits).toInt() - 1;
  return (min + random.nextInt(max - min + 1)).toString();
}