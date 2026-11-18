import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../config/supabase_config.dart';
import 'safe_http.dart';
import 'supabase_data_service.dart';

/// جودة الاتصال الحالية كما يقيسها البينج الدوري على خادم Supabase.
enum NetworkQuality { unknown, excellent, good, fair, poor, offline }

/// لقطة حالة الشبكة التي تبثّها [NetworkStatusService.state].
class NetworkPingInfo {
  final NetworkQuality quality;

  /// زمن ذهاب وعودة آخر فحص ناجح بالمللي ثانية، أو -1 عند الانقطاع.
  final int pingMs;

  /// فرق ساعة الجهاز عن وقت السيرفر (سالب = الجهاز متأخر)، أو null.
  final int? serverOffsetMs;

  /// آخر فحص ناجح — null إن لم ينجح أي فحص بعد.
  final DateTime? lastSuccessAt;

  const NetworkPingInfo({
    this.quality = NetworkQuality.unknown,
    this.pingMs = -1,
    this.serverOffsetMs,
    this.lastSuccessAt,
  });

  bool get isOnline => quality != NetworkQuality.offline &&
      quality != NetworkQuality.unknown;

  @override
  bool operator ==(Object other) =>
      other is NetworkPingInfo &&
      other.quality == quality &&
      other.pingMs == pingMs &&
      other.serverOffsetMs == serverOffsetMs;

  @override
  int get hashCode => Object.hash(quality, pingMs, serverOffsetMs);
}

/// خدمة استقرار الشبكة والمزامنة اللحظية:
///
/// * تفحص الاتصال بخادم Supabase دورياً (بينج HTTP HEAD) وتقيس زمنه.
/// * تكشف الانقطاع بعد [offlineThresholdFailures] فشلات متتالية —
///   تبث الحالة عبر [state] ليعرضها أي ويدجت (مثل نقطة تحت أيقونة
///   المتصلين في الغرفة).
/// * تزامن وقت السيرفر دورياً ([serverOffsetMs]) لتعويض فرق ساعة
///   الجهاز حتى تبقى الطوابع الزمنية والعدادات متسقة بين الأجهزة.
///
/// كل الفترات والعتبات تُقرأ من `assets/config/network_sync.json`
/// مع قيم افتراضية عند غياب الملف أو تلفه.
class NetworkStatusService extends ChangeNotifier {
  NetworkStatusService._();
  static final NetworkStatusService _instance = NetworkStatusService._();
  factory NetworkStatusService() => _instance;

  /// حالة الشبكة الحالية — تستمع لها الواجهات عبر ValueListenableBuilder.
  final ValueNotifier<NetworkPingInfo> state =
      ValueNotifier(const NetworkPingInfo());

  // ── الإعدادات (من network_sync.json أو الافتراضيات) ──────────────────
  Duration _probeInterval = const Duration(seconds: 5);
  Duration _probeTimeout = const Duration(seconds: 4);
  int _offlineThreshold = 2;
  int _excellentMs = 150;
  int _goodMs = 350;
  int _fairMs = 700;
  Duration _serverSyncInterval = const Duration(seconds: 60);

  Timer? _probeTimer;
  Timer? _serverSyncTimer;
  bool _probing = false;
  int _consecutiveFailures = 0;
  int? _serverOffsetMs;
  bool _configLoaded = false;

  bool get isRunning => _probeTimer != null;

  /// يحمّل الإعدادات من JSON ثم يبدأ الفحص الدوري. آمن للاستدعاء
  /// المتكرر — يعمل مرة واحدة فقط.
  Future<void> init() async {
    if (_configLoaded) return;
    _configLoaded = true;
    await _loadConfig();
    start();
  }

  Future<void> _loadConfig() async {
    try {
      final raw = await rootBundle
          .loadString('assets/config/network_sync.json')
          .timeout(const Duration(seconds: 2));
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _probeInterval = Duration(
          milliseconds: (json['probe_interval_ms'] as num?)?.toInt() ?? 5000);
      _probeTimeout = Duration(
          milliseconds: (json['probe_timeout_ms'] as num?)?.toInt() ?? 4000);
      _offlineThreshold =
          (json['offline_threshold_failures'] as num?)?.toInt() ?? 2;
      final qt = json['quality_thresholds_ms'];
      if (qt is Map) {
        _excellentMs = (qt['excellent'] as num?)?.toInt() ?? 150;
        _goodMs = (qt['good'] as num?)?.toInt() ?? 350;
        _fairMs = (qt['fair'] as num?)?.toInt() ?? 700;
      }
      _serverSyncInterval = Duration(
          milliseconds:
              (json['server_time_sync_interval_ms'] as num?)?.toInt() ?? 60000);
    } catch (_) {
      // الملف غير موجود أو تالف — نبقى على الافتراضيات.
    }
  }

  void start() {
    if (_probeTimer != null) return;
    _probeTimer =
        Timer.periodic(_probeInterval, (_) => unawaited(_probe()));
    _serverSyncTimer = Timer.periodic(_serverSyncInterval,
        (_) => unawaited(_syncServerTime()));
    unawaited(_probe());
    unawaited(_syncServerTime());
  }

  void stop() {
    _probeTimer?.cancel();
    _probeTimer = null;
    _serverSyncTimer?.cancel();
    _serverSyncTimer = null;
    _probing = false;
  }

  NetworkQuality _qualityFor(int pingMs) {
    if (pingMs <= _excellentMs) return NetworkQuality.excellent;
    if (pingMs <= _goodMs) return NetworkQuality.good;
    if (pingMs <= _fairMs) return NetworkQuality.fair;
    return NetworkQuality.poor;
  }

  Future<void> _probe() async {
    if (_probing) return;
    _probing = true;
    try {
      final sw = Stopwatch()..start();
      var ok = false;
      try {
        final res = await SafeHttp.head(
          Uri.parse('${SupabaseConfig.projectUrl}/rest/v1/'),
          headers: {'apikey': SupabaseConfig.anonKey},
        ).timeout(_probeTimeout);
        ok = res.statusCode > 0;
      } catch (_) {}
      sw.stop();

      if (ok) {
        _consecutiveFailures = 0;
        final ping = sw.elapsedMilliseconds;
        state.value = NetworkPingInfo(
          quality: _qualityFor(ping),
          pingMs: ping,
          serverOffsetMs: _serverOffsetMs,
          lastSuccessAt: DateTime.now(),
        );
      } else {
        _consecutiveFailures++;
        if (_consecutiveFailures >= _offlineThreshold) {
          state.value = NetworkPingInfo(
            quality: NetworkQuality.offline,
            pingMs: -1,
            serverOffsetMs: _serverOffsetMs,
            lastSuccessAt: state.value.lastSuccessAt,
          );
        }
      }
    } finally {
      _probing = false;
    }
  }

  /// يزامن وقت السيرفر ويحسب فرق الساعة — يُستخدم لتصحيح الطوابع
  /// الزمنية المحلية (مثل توقيتات الرسائل والعد التنازلي).
  Future<void> _syncServerTime() async {
    try {
      final before = DateTime.now().millisecondsSinceEpoch;
      final serverMs = await SupabaseDataService().fetchServerTimeMs();
      if (serverMs == null) return;
      final after = DateTime.now().millisecondsSinceEpoch;
      final localMid = (before + after) ~/ 2;
      _serverOffsetMs = serverMs - localMid;
      final cur = state.value;
      if (cur.quality != NetworkQuality.offline) {
        state.value = NetworkPingInfo(
          quality: cur.quality,
          pingMs: cur.pingMs,
          serverOffsetMs: _serverOffsetMs,
          lastSuccessAt: cur.lastSuccessAt,
        );
      }
    } catch (_) {}
  }

  /// فرق ساعة الجهاز عن السيرفر بالمللي ثانية (سالب = الجهاز متأخر).
  int? get serverOffsetMs => _serverOffsetMs;

  /// الوقت المحلي المُصحَّح بفرق السيرفر — بديل آمن لـ
  /// DateTime.now() في الطوابع التي تُقارن بسجلات السيرفر.
  DateTime get serverSyncedNow =>
      DateTime.now().add(Duration(milliseconds: _serverOffsetMs ?? 0));
}
