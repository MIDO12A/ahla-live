import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';

/// Watches internet connectivity while the user is inside a room.
///
/// When the connection stays down for [timeout] the owner-provided callback is
/// invoked exactly once so the room can be left and the app can be closed.
class NetworkWatchdogService {
  NetworkWatchdogService._();
  static final NetworkWatchdogService _instance = NetworkWatchdogService._();
  factory NetworkWatchdogService() => _instance;

  static const Duration probeInterval = Duration(seconds: 2);
  static const Duration probeTimeout = Duration(seconds: 4);

  Timer? _timer;
  DateTime? _offlineSince;
  int _consecutiveFailures = 0;
  bool _fired = false;
  bool _probing = false;
  Future<void> Function()? _onOffline;

  bool get isRunning => _timer != null;

  void start({
    required Future<void> Function() onOffline,
    Duration timeout = const Duration(seconds: 10),
  }) {
    _onOffline = onOffline;
    _offlineSince = null;
    _consecutiveFailures = 0;
    _fired = false;
    _timer?.cancel();
    _timer = Timer.periodic(probeInterval, (_) => _probe(timeout));
    _probe(timeout);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _onOffline = null;
    _offlineSince = null;
    _consecutiveFailures = 0;
    _probing = false;
  }

  Future<void> _probe(Duration timeout) async {
    if (_fired || _probing) return;
    _probing = true;
    final online = await checkNow();
    _probing = false;
    if (_fired) return;
    if (online) {
      _offlineSince = null;
      _consecutiveFailures = 0;
      return;
    }
    _consecutiveFailures++;
    _offlineSince ??= DateTime.now();
    if (_consecutiveFailures >= 2 &&
        DateTime.now().difference(_offlineSince!) >= timeout) {
      _fired = true;
      _timer?.cancel();
      _timer = null;
      try {
        await _onOffline?.call();
      } catch (e) {
        debugPrint('NetworkWatchdogService onOffline error: $e');
      }
    }
  }

  /// Returns true when at least one connectivity probe succeeds.
  Future<bool> checkNow() async {
    if (await _httpProbe('https://www.google.com/generate_204')) return true;
    if (await _httpProbe('https://www.cloudflare.com/cdn-cgi/trace')) return true;
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(probeTimeout);
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) return true;
    } catch (_) {}
    try {
      final result =
          await InternetAddress.lookup('supabase.co').timeout(probeTimeout);
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) return true;
    } catch (_) {}
    return _httpProbe('${SupabaseConfig.projectUrl}/rest/v1/');
  }

  Future<bool> _httpProbe(String url) async {
    try {
      final res = await http.head(Uri.parse(url), headers: {
        'apikey': SupabaseConfig.anonKey,
      }).timeout(probeTimeout);
      return res.statusCode > 0;
    } catch (_) {
      return false;
    }
  }
}
