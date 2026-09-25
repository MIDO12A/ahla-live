import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class ErrorReportingService {
  static final ErrorReportingService _instance = ErrorReportingService._();
  factory ErrorReportingService() => _instance;
  ErrorReportingService._();

  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'default',
  );

  void init() {
    // 1. Intercept Flutter UI layout / rendering errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('*** ORIGINAL ERROR: ${details.exceptionAsString()}');
      _reportError(
        error: details.exceptionAsString(),
        stackTrace: details.stack?.toString() ?? '',
        type: 'UI / Layout',
      );
    };

    // 2. Intercept asynchronous / Dart thread exceptions
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      debugPrint('*** ORIGINAL ERROR: $error');
      _reportError(
        error: error.toString(),
        stackTrace: stack.toString(),
        type: 'Code / Logic',
      );
      return true; // Mark as handled
    };
  }

  Future<void> _reportError({
    required String error,
    required String stackTrace,
    required String type,
  }) async {
    try {
      final String os = kIsWeb ? 'Web' : Platform.operatingSystem;
      final String version = kIsWeb ? 'Browser' : Platform.operatingSystemVersion;

      await _db.collection('bug_reports').add({
        'error': error,
        'stack_trace': stackTrace.substring(0, stackTrace.length > 1500 ? 1500 : stackTrace.length),
        'device_info': '$os ($version)',
        'type': type,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Prevent infinite loop if logging itself fails
      debugPrint('Failed to log error to Firebase: $e');
    }
  }
}
