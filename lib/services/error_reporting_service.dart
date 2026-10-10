import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'supabase_data_service.dart';

class ErrorReportingService {
  static final ErrorReportingService _instance = ErrorReportingService._();
  factory ErrorReportingService() => _instance;
  ErrorReportingService._();

  void init() {
    // 1. Intercept Flutter UI layout / rendering errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('*** ORIGINAL ERROR: ${details.exceptionAsString()}');
      debugPrint('*** STACKTRACE: ${details.stack}');
      _reportError(
        error: details.exceptionAsString(),
        stackTrace: details.stack?.toString() ?? '',
        type: 'UI / Layout',
      );
    };

    // 2. Intercept asynchronous / Dart thread exceptions
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      debugPrint('*** ORIGINAL ERROR: $error');
      debugPrint('*** STACKTRACE: $stack');
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
    final String os = kIsWeb ? 'Web' : Platform.operatingSystem;
    final cleanStack = stackTrace.substring(0, stackTrace.length > 1500 ? 1500 : stackTrace.length);
    // Report directly and strictly to Supabase
    try {
      await SupabaseDataService().submitBugReport({
        'error': error,
        'stack_trace': cleanStack,
        'device_info': '$os ($version)',
        'type': type,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }
}
