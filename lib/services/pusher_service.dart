import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import '../config/pusher_config.dart';

/// خدمة اشتراك فوري في قنوات Pusher.
/// - القناة العامة `global-banners`: broadcast (لافتات الهدايا + نص الحظ)،
///   big_win (فوز أسطوري)، banner_config (تحديث إعدادات اللافتات).
/// - قناة الغرفة `room-<roomId>`: room_message (رسائل دردشة الغرفة فوراً).
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
  PusherChannelsFlutter? _pusher;
  Future<void>? _ready;

  /// كل القنوات المشترك بها حالياً (العامة + غرف).
  final Set<String> _channels = <String>{PusherConfig.channelName};

  void start() {
    if (_started) return;
    _started = true;
    _ready = _init();
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
        onConnectionStateChange: _handleConnectionStateChange,
      );
      _pusher = pusher;
      for (final channel in _channels.toList()) {
        try {
          await pusher.subscribe(channelName: channel);
        } catch (_) {}
      }
      await pusher.connect();
      debugPrint('[Pusher] subscribed to ${_channels.join(', ')}');
    } catch (e) {
      // المنصات غير المدعومة أو غياب السكربت على الويب لا توقف التطبيق
      debugPrint('[Pusher] init failed (non-fatal): $e');
    }
  }

  /// أسماء قنوات Pusher المسموح بها: حروف/أرقام و _ - = @ , . ;
  static String _sanitize(String raw) =>
      raw.replaceAll(RegExp(r'[^A-Za-z0-9_\-=@,.;]'), '_');

  /// JOIN غرفة: الاشتراك في قناتها الخاصة حتى لا تُبث رسائل كل الغرف للجميع.
  Future<void> subscribeRoom(String roomId) async {
    if (roomId.isEmpty) return;
    final channel = 'room-${_sanitize(roomId)}';
    final isNew = _channels.add(channel);
    start();
    await _ready;
    final pusher = _pusher;
    if (!isNew || pusher == null) return;
    try {
      await pusher.subscribe(channelName: channel);
    } catch (e) {
      debugPrint('[Pusher] subscribe $channel failed: $e');
    }
  }

  /// LEAVE غرفة: إلغاء الاشتراك في قناتها.
  Future<void> unsubscribeRoom(String roomId) async {
    if (roomId.isEmpty) return;
    final channel = 'room-${_sanitize(roomId)}';
    if (!_channels.remove(channel)) return;
    final pusher = _pusher;
    if (pusher == null) return;
    try {
      await pusher.unsubscribe(channelName: channel);
    } catch (e) {
      debugPrint('[Pusher] unsubscribe $channel failed: $e');
    }
  }

  void _handleConnectionStateChange(String current, String previous) async {
    debugPrint('[Pusher] connection: $previous -> $current');
    // بعد إعادة الاتصال نعيد الاشتراك بكل القنوات (Pusher يفقدها عند الانقطاع).
    if (current == 'connected' && previous != 'connected') {
      final pusher = _pusher;
      if (pusher == null) return;
      for (final channel in _channels.toList()) {
        try {
          await pusher.subscribe(channelName: channel);
        } catch (_) {}
      }
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
