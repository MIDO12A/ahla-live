import 'package:flutter/material.dart';

abstract final class KayanInAppToast {
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static void _show(String message, Color bgColor) {
    messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white)),
      backgroundColor: bgColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  static void success(String msg) => _show(msg, const Color(0xFF2E7D32));
  static void info(String msg) => _show(msg, const Color(0xFF1565C0));
  static void warning(String msg) => _show(msg, const Color(0xFFE65100));
  static void error(String msg) => _show(msg, const Color(0xFFC62828));
  static void agency(String msg) => _show(msg, const Color(0xFF6A1B9A));
  static void diamond(String msg) => _show(msg, const Color(0xFF00BCD4));
}
