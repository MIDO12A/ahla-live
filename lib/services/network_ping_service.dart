import 'dart:async';

import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import 'safe_http.dart';

/// قياس حقيقي لسرعة/جودة الشبكة عبر زمن الرحلة الكامل (RTT)
/// لطلب HTTP خفيف على نفس باك إند التطبيق (Supabase).
///
/// القيمة المعروضة هي زمن الاستجابة الحقيقي بالمللي ثانية —
/// وليست تقديراً. عند انقطاع الاتصال تُرجع null.
class NetworkPingService extends ChangeNotifier {
  NetworkPingService._();
  static final NetworkPingService instance = NetworkPingService._();

  /// آخر زمن استجابة مقاس بالمللي ثانية (null = لا اتصال/فشل القياس)
  final ValueNotifier<int?> pingMs = ValueNotifier<int?>(null);

  Timer? _timer;
  bool _running = false;

  static const Duration _interval = Duration(seconds: 5);
  static const Duration _timeout = Duration(seconds: 4);

  void start() {
    if (_running) return;
    _running = true;
    _measure();
    _timer = Timer.periodic(_interval, (_) => _measure());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _measure() async {
    final sw = Stopwatch()..start();
    var ok = false;
    try {
      // طلب خفيف جداً على REST API — نفس البنية التحتية التي يستخدمها التطبيق
      final res = await SafeHttp.get(
        Uri.parse(
          '${SupabaseConfig.projectUrl}/rest/v1/app_config?select=key&limit=1',
        ),
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
        },
      ).timeout(_timeout);
      ok = res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {}
    sw.stop();
    // نفشل الطلب = شبكة ضعيفة جداً/منقطعة → null
    pingMs.value = ok ? sw.elapsedMilliseconds : null;
  }

  /// جودة الشبكة بناءً على زمن الاستجابة الحقيقي
  /// excellent < 150 | good < 400 | weak < 800 | bad >= 800 | offline = null
  static int qualityOf(int? ms) {
    if (ms == null) return 0;
    if (ms < 150) return 3;
    if (ms < 400) return 2;
    if (ms < 800) return 1;
    return 0;
  }

  static Color qualityColor(int? ms) {
    switch (qualityOf(ms)) {
      case 3:
        return const Color(0xFF4ADE80); // أخضر — ممتاز
      case 2:
        return const Color(0xFFA3E635); // أخضر فاتح — جيد
      case 1:
        return const Color(0xFFFBBF24); // برتقالي — ضعيف
      default:
        return const Color(0xFFEF4444); // أحمر — سيء/منقطع
    }
  }

  static String qualityLabel(int? ms, {bool isAr = true}) {
    if (ms == null) return isAr ? 'منقطع' : 'Offline';
    if (ms < 150) return isAr ? 'ممتاز' : 'Excellent';
    if (ms < 400) return isAr ? 'جيد' : 'Good';
    if (ms < 800) return isAr ? 'ضعيف' : 'Weak';
    return isAr ? 'سيء' : 'Bad';
  }
}
