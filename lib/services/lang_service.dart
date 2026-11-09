import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// خدمة الترجمة — تقرأ ملفات JSON في assets/lang:
/// - en.json : { "النص العربي": "English text" }  (يُستخدم عند اللغة الإنجليزية)
/// - ar.json : { "English text": "النص العربي" }  (يُستخدم عند اللغة العربية)
/// إن لم توجد ترجمة يُرجع النص الأصلي كما هو.
class LangService {
  LangService._();
  static final LangService instance = LangService._();

  Map<String, String> _en = {};
  Map<String, String> _ar = {};
  bool _loaded = false;
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final enRaw = await rootBundle.loadString('assets/lang/en.json');
      _en = (jsonDecode(enRaw) as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {}
    try {
      final arRaw = await rootBundle.loadString('assets/lang/ar.json');
      // ar.json الحالي منظم بمفاتيح إنجليزية/رموز — ندعمه كخريطة نصية عامة
      final decoded = jsonDecode(arRaw);
      if (decoded is Map) {
        _ar = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    _loaded = true;
  }

  /// ترجمة نص according للغة الحالية.
  /// lang: 'en' | 'ar' | غيره
  String translate(String? text, String lang) {
    if (text == null || text.isEmpty) return text ?? '';
    if (lang == 'en') {
      final v = _en[text] ?? _en[text.trim()];
      return (v != null && v.isNotEmpty) ? v : text;
    }
    if (lang == 'ar') {
      //Arabic literals are already Arabic — only translate if an explicit override exists
      final v = _ar[text] ?? _ar[text.trim()];
      return (v != null && v.isNotEmpty) ? v : text;
    }
    return text;
  }
}
