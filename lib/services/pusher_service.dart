import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import '../config/pusher_config.dart';

/// خدمة اشتراك فوري في قناة Pusher العامة `global-banners`.
/// تستقبل أحداث: broadcast (لافتات الهدايا + نص الحظ)، big_win (فوز أسطوري)،
/// banner_config (تحديث إعدادات اللوافت).
/// تُستخدم كطبقة سرعة فوق الـ polling الموجود في SupabaseService —
/// أي حدث يصل من Pusher يمر بنفس مسار المعالجة فيتجنب التكرار تلقائياً.
class PusherRealtimeService {
  static final PusherRealtimeService instance = PusherRealtimeService._();
  PusherRealtimeService._();

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  /// بث موحّد: `{'event': String, 'channel': String?, 'data': Map}`
  Stream<Map<String, dynamic>> get events => _controller.stream;

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _init();
  }

  Future<void> _init() async {
    try {
      final pusher = PusherChannelsFlutter.getInstance();
      await pusher.init(
        apiKey: PusherConfig.apiKey,
        cluster: PusherConfig.cluster,
        onEvent: _handleEvent,
        onError: (msg, code, err) =>
            debugPrint('[Pusher] error: $msg (code=$code, err=$err)'),
        onConnectionStateChange: (current, previous) =>
            debugPrint('[Pusher] connection: $previous -> $current'),
      );
      await pusher.subscribe(channelName: PusherConfig.channelName);
      await pusher.connect();
      debugPrint('[Pusher] subscribed to ${PusherConfig.channelName}');
    } catch (e) {
      // المنصات غير المدعومة أو غياب السكربت على الويب لا توقف التطبيق
      debugPrint('[Pusher] init failed (non-fatal): $e');
    }
  }

  void _handleEvent(PusherEvent event) {
    try {
      final raw = event.data;
      Map<String, dynamic>? map;
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      } else if (raw is Map) {
        map = Map<String, dynamic>.from(raw);
      }
      if (map == null) return;
      _controller.add({
        'event': event.eventName,
        'channel': event.channelName,
        'data': map,
      });
    } catch (e) {
      debugPrint('[Pusher] event parse error: $e');
    }
  }
}
