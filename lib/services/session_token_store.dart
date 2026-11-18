import 'package:shared_preferences/shared_preferences.dart';

/// مخزن توكن جلسة المستخدم (user_sessions على السيرفر).
///
/// يُصدر من السيرفر بعد إثبات الهوية (OTP/PIN/Google) ويُخزَّن محلياً،
/// ثم يُرسل في header «x-session-token» مع كل طلبات PostgREST حتى
/// يستطيع حارس الكتابة على السيرفر التحقق أن الطالب يملك الحساب.
/// الجدول نفسه مقيد بـ RLS — لا يمكن قراءة التوكنات من العميل.
class SessionTokenStore {
  SessionTokenStore._();

  static const String _prefKey = 'supabase_auth_token';
  static String? _token;

  /// التوكن الحالي في الذاكرة — متاح بشكل متزامن لـ _headers.
  static String? get token => _token;

  /// تهيئة من SharedPreferences — تُستدعى مرة عند بدء التطبيق.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final t = prefs.getString(_prefKey);
      _token = (t != null && t.isNotEmpty) ? t : null;
    } catch (_) {}
  }

  /// حفظ التوكن في الذاكرة و SharedPreferences.
  static Future<void> set(String? value) async {
    _token = (value != null && value.isNotEmpty) ? value : null;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_token == null) {
        await prefs.remove(_prefKey);
      } else {
        await prefs.setString(_prefKey, _token!);
      }
    } catch (_) {}
  }

  static void clear() {
    _token = null;
  }
}
