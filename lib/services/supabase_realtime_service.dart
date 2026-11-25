import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/supabase_config.dart';

/// تغيير واحد وصل من قناة Postgres Changes اللحظية.
class RealtimeChange {
  final String table;
  final String type; // INSERT / UPDATE / DELETE
  final Map<String, dynamic> record;
  final Map<String, dynamic> oldRecord;

  const RealtimeChange({
    required this.table,
    required this.type,
    required this.record,
    this.oldRecord = const {},
  });

  @override
  String toString() => '[SupabaseRealtime] $type $table';
}

/// اشتراك واحد (قناة واحدة) على جدول.
class _RealtimeSub {
  final String topic;
  final String table;
  final String? filter;
  final List<String> events;
  final bool broadcast;
  int refCount = 1;

  _RealtimeSub({
    required this.topic,
    required this.table,
    this.filter,
    required this.events,
    this.broadcast = false,
  });
}

/// عميل Realtime حقيقي لبروتوكول Supabase (Phoenix Channels عبر WebSocket).
///
/// يدعم الآن عدة جداول على نفس الاتصال (بدل room_messages فقط):
///   * room_messages  → رسائل الدردشة + نص فوز الحظ
///   * sent_gifts     → الهدايا وأنيميشنها
///   * room_seats     → المقاعد الحيّة
///   * room_members   → الأعضاء/العدد الأونلاين
///   * rooms          → بيانات الغرفة وقائمة الغرف
///   * lucky_bags     → أكياس الحظ
///
/// واجهتان:
///   * [events]  : بصيغة {@code {'event': 'room_message', 'data': row}} —
///                 متوافقة مع المستهلك القديم في شاشة الغرفة.
///   * [changes] : كل التغييرات بصيغة موحّدة [RealtimeChange].
///
/// ويساعد طبقة الـ streams على تقليل الاستعلامات: [waitForTableChange]
/// ينتظر تغييراً حقيقياً (أو مهلة أمان) بدل طلب REST كل 150ms.
///
/// يتطلب: تفعيل الجداول في Database > Replication (supabase_realtime) —
/// وإن لم يكن الجدول مفعّلاً يبقى الـ polling العادي هو المسار المستخدم.
class SupabaseRealtimeService {
  static final SupabaseRealtimeService _instance =
      SupabaseRealtimeService._internal();
  static SupabaseRealtimeService get instance => _instance;
  factory SupabaseRealtimeService() => _instance;
  SupabaseRealtimeService._internal();

  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  bool _connecting = false;
  bool _socketOpen = false;
  bool _joinedAny = false;
  int _refSeq = 0;
  int _hbSeq = 0;
  Timer? _hbTimer;
  Timer? _reconnectTimer;
  Timer? _rejoinTimer;

  final Map<String, _RealtimeSub> _subs = <String, _RealtimeSub>{};
  final Set<String> _activeTopics = <String>{};
  final Set<String> _liveTopics = <String>{};
  final Map<String, String> _pendingJoins = <String, String>{};

  String? _lastRoomId;

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<RealtimeChange> _changes =
      StreamController<RealtimeChange>.broadcast();
  final StreamController<Map<String, dynamic>> _broadcasts =
      StreamController<Map<String, dynamic>>.broadcast();

  /// أحداث realtime بصيغة موحّدة: {'event': 'room_message', 'data': row}
  /// (متوافق مع الكود القديم في شاشة الغرفة).
  Stream<Map<String, dynamic>> get events => _controller.stream;

  /// كل تغييرات الجداول المشتركة.
  Stream<RealtimeChange> get changes => _changes.stream;

  /// أحداث broadcast (بما فيها الحمولات الثنائية للهدايا).
  /// الشكل: {'event': String, 'topic': String, 'data': Map}
  Stream<Map<String, dynamic>> get broadcasts => _broadcasts.stream;

  /// متصل ومُنضمّ لقناة واحدة على الأقل.
  bool get isConnected => _socketOpen && _joinedAny;

  /// هل هذا الاشتراك حيّ فعلياً (تم phx_join بنجاح)؟
  bool isTopicLive(String topic) => _liveTopics.contains(topic);

  String get _wsUrl {
    final host = Uri.parse(SupabaseConfig.projectUrl).host;
    return 'wss://$host/realtime/v1/websocket'
        '?apikey=${SupabaseConfig.anonKey}&vsn=1.0.0';
  }

  void start() {
    _ensureSocket();
  }

  void stop() {
    _hbTimer?.cancel();
    _reconnectTimer?.cancel();
    _rejoinTimer?.cancel();
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.sink.close();
    _ws = null;
    _socketOpen = false;
    _joinedAny = false;
    _activeTopics.clear();
    _liveTopics.clear();
    _pendingJoins.clear();
  }

  // ── اتصال ────────────────────────────────────────────────────────────────

  void _ensureSocket() {
    if (_ws != null || _connecting) return;
    _connecting = true;
    try {
      _ws = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _wsSub = _ws!.stream.listen(
        _onMessage,
        onDone: _onSocketClosed,
        onError: (_) => _onSocketClosed(),
        cancelOnError: true,
      );
      _socketOpen = true;
      _connecting = false;
      _hbTimer?.cancel();
      _hbTimer =
          Timer.periodic(const Duration(seconds: 25), (_) => _sendHeartbeat());
      // إعادة محاولة القنوات التي فشل انضمامها (بدون انتظار إعادة اتصال).
      _rejoinTimer?.cancel();
      _rejoinTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (!_socketOpen) return;
        for (final sub in _subs.values) {
          if (_liveTopics.contains(sub.topic)) continue;
          if (_activeTopics.contains(sub.topic)) continue;
          _join(sub);
        }
      });
      debugPrint('[SupabaseRealtime] websocket connecting: $_wsUrl');
      // أعد الانضمام لكل الاشتراكات المسجّلة (بعد انقطاع الشبكة).
      _activeTopics.clear();
      _liveTopics.clear();
      _pendingJoins.clear();
      for (final sub in _subs.values) {
        _join(sub);
      }
    } catch (e) {
      _connecting = false;
      debugPrint('[SupabaseRealtime] connect error: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _ensureSocket);
  }

  void _onSocketClosed() {
    _socketOpen = false;
    _joinedAny = false;
    _wsSub?.cancel();
    _wsSub = null;
    _ws = null;
    _activeTopics.clear();
    _liveTopics.clear();
    _pendingJoins.clear();
    _hbTimer?.cancel();
    _hbTimer = null;
    _rejoinTimer?.cancel();
    _rejoinTimer = null;
    _scheduleReconnect();
  }

  void _sendHeartbeat() {
    _sendRaw({
      'topic': 'phoenix',
      'event': 'heartbeat',
      'payload': <String, dynamic>{},
      'ref': 'hb_${++_hbSeq}',
    });
  }

  void _sendRaw(Map<String, dynamic> msg) {
    final ws = _ws;
    if (ws == null || !_socketOpen) return;
    try {
      ws.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  // ── اشتراكات ─────────────────────────────────────────────────────────────

  /// الاشتراك في جدول room_messages لغرفة محددة.
  void subscribeRoom(String roomId) {
    if (roomId.isEmpty) return;
    _lastRoomId = roomId;
    subscribeTable(
      table: 'room_messages',
      topic: 'room_messages:$roomId',
      filter: 'room_id=eq.$roomId',
      events: const ['INSERT', 'UPDATE'],
    );
  }

  /// عكس [subscribeRoom] — ينقص عدّاد المرجع فقط.
  void unsubscribeRoom([String? roomId]) {
    final rid = roomId ?? _lastRoomId;
    if (rid == null) return;
    unsubscribeTopic('room_messages:$rid');
  }

  /// قناة broadcast خاصة بالغرفة لنقل الحمولات الثنائية (Protobuf).
  /// `self: true` ضروري ليستقبل المُرسِل حدثه هو أيضاً.
  void subscribeGiftPush(String roomId) {
    if (roomId.isEmpty) return;
    subscribeTable(
      table: 'gift_push',
      topic: 'gift_push:$roomId',
      events: const [],
      broadcast: true,
    );
  }

  void unsubscribeGiftPush(String roomId) {
    if (roomId.isEmpty) return;
    unsubscribeTopic('gift_push:$roomId');
  }

  /// إرسال حدث broadcast على قناة منضمّ إليها. ينتظر الـ phx_join أولاً
  /// (السيرفر يتجاهل الأحداث المرسلة قبل الانضمام).
  Future<bool> sendBroadcast({
    required String roomId,
    required String event,
    required Map<String, dynamic> payload,
    String channelPrefix = 'gift_push',
  }) async {
    start();
    final topic = '$channelPrefix:$roomId';
    if (!_liveTopics.contains(topic)) {
      subscribeTable(
        table: channelPrefix,
        topic: topic,
        broadcast: true,
      );
      for (var i = 0; i < 40 && !_liveTopics.contains(topic); i++) {
        await Future.delayed(const Duration(milliseconds: 25));
      }
      if (!_liveTopics.contains(topic)) return false;
    }
    _sendRaw({
      'topic': 'realtime:$topic',
      'event': 'broadcast',
      'payload': {
        'event': event,
        'payload': payload,
      },
      'ref': 'bc_${++_refSeq}',
    });
    return true;
  }

  /// بث حدث مقعد فوري (أخذ مقعد / مغادرة / كتم) لجميع الموجودين بالغرفة لحظياً
  Future<bool> broadcastSeatChange({
    required String roomId,
    required String action, // 'take' | 'leave' | 'mute'
    required int seatIndex,
    Map<String, dynamic>? userData,
    bool isMuted = false,
  }) async {
    return sendBroadcast(
      roomId: roomId,
      event: 'seat_change',
      channelPrefix: 'gift_push',
      payload: {
        'action': action,
        'seat_index': seatIndex,
        'user': userData,
        'is_muted': isMuted,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// الاشتراك بجدول (أو نفس الجدول بفلتر/قناة مختلفة).
  void subscribeTable({
    required String table,
    required String topic,
    String? filter,
    List<String> events = const ['INSERT', 'UPDATE', 'DELETE'],
    bool broadcast = false,
  }) {
    final existing = _subs[topic];
    if (existing != null) {
      existing.refCount++;
      _ensureSocket();
      if (_socketOpen && !_activeTopics.contains(topic)) _join(existing);
      return;
    }
    final sub = _RealtimeSub(
      topic: topic,
      table: table,
      filter: filter,
      events: events,
      broadcast: broadcast,
    );
    _subs[topic] = sub;
    _ensureSocket();
    if (_socketOpen) _join(sub);
  }

  /// ينقص عدّاد المرجع لاشتراك، ويغادره فعلياً عند وصوله للصفر.
  void unsubscribeTopic(String topic) {
    final sub = _subs[topic];
    if (sub == null) return;
    sub.refCount--;
    if (sub.refCount > 0) return;
    _subs.remove(topic);
    _leave(sub);
  }

  void _join(_RealtimeSub sub) {
    if (!_socketOpen) return;
    final ref = 'join_${++_refSeq}';
    _pendingJoins[ref] = sub.topic;
    _activeTopics.add(sub.topic);
    // ملاحظة مهمة: مفتاح النشر (sb_publishable_...) ليس JWT، وإرساله في
    // access_token يجعل السيرفر يرفض الانضمام (invalid token) فتفشل القناة
    // بصمت. لذلك نرسل access_token فقط إن كان المفتاح JWT فعلياً، وإلا
    // يعتمد Realtime على apikey في رابط الاتصال (وهو المسار الصحيح
    // لمفاتيح publishable الجديدة).
    final token = SupabaseConfig.anonKey;
    final isJwt = token.split('.').length == 3;
    _sendRaw({
      'topic': 'realtime:${sub.topic}',
      'event': 'phx_join',
      'payload': {
        'config': sub.broadcast
            ? <String, dynamic>{
                'broadcast': <String, dynamic>{'self': true},
              }
            : <String, dynamic>{
                'postgres_changes': sub.events
                    .map((e) => <String, dynamic>{
                          'event': e,
                          'schema': 'public',
                          'table': sub.table,
                          if (sub.filter != null) 'filter': sub.filter,
                        })
                    .toList(),
              },
        if (isJwt) 'access_token': token,
      },
      'ref': ref,
    });
    debugPrint('[SupabaseRealtime] join ${sub.topic} '
        '(${sub.events.join(",")}${sub.filter == null ? '' : ' • ${sub.filter}'})');
  }

  void _leave(_RealtimeSub sub) {
    if (!_activeTopics.remove(sub.topic)) return;
    _liveTopics.remove(sub.topic);
    _sendRaw({
      'topic': 'realtime:${sub.topic}',
      'event': 'phx_leave',
      'payload': <String, dynamic>{},
      'ref': 'leave_${++_refSeq}',
    });
  }

  // ── استقبال ──────────────────────────────────────────────────────────────

  void _onMessage(dynamic raw) {
    try {
      if (raw is! String) return;
      final msg = jsonDecode(raw);
      if (msg is! Map) return;
      final event = msg['event']?.toString() ?? '';

      if (event == 'broadcast') {
        final payload = msg['payload'];
        if (payload is! Map) return;
        final data = payload['payload'];
        if (data is! Map) return;
        final bcEvent = payload['event']?.toString() ?? '';
        final bcData = {
          'event': bcEvent,
          'topic': (msg['topic']?.toString() ?? '')
              .replaceFirst('realtime:', ''),
          'data': Map<String, dynamic>.from(data),
        };
        _broadcasts.add(bcData);
        _controller.add(bcData);
        return;
      }

      if (event == 'postgres_changes') {
        final payload = msg['payload'];
        if (payload is! Map) return;
        final data = payload['data'];
        if (data is! Map) return;
        final record = data['record'];
        final oldRecord = data['old_record'];
        final type = data['type']?.toString() ?? 'INSERT';
        final table = data['table']?.toString() ?? '';
        final recMap = record is Map ? Map<String, dynamic>.from(record) : <String, dynamic>{};
        final oldMap = oldRecord is Map ? Map<String, dynamic>.from(oldRecord) : <String, dynamic>{};
        final row = recMap.isNotEmpty ? recMap : oldMap;

        if (table == 'room_messages') {
          // نفس شكل حدث Pusher: room_message + الصف كاملاً
          _controller.add({
            'event': 'room_message',
            'data': row,
            'changeType': type,
          });
        }
        _changes.add(RealtimeChange(table: table, type: type, record: row, oldRecord: oldMap));
        return;
      }

      if (event == 'phx_reply') {
        final payload = msg['payload'];
        final status = payload is Map ? payload['status']?.toString() : null;
        final ref = msg['ref']?.toString() ?? '';
        final topic = _pendingJoins.remove(ref);
        if (status == 'ok') {
          _joinedAny = true;
          if (topic != null) _liveTopics.add(topic);
        } else if (topic != null) {
          _liveTopics.remove(topic);
          // اسمح بمحاولة انضمام جديدة لاحقاً (عند إعادة subscribe)
          _activeTopics.remove(topic);
          debugPrint('[SupabaseRealtime] join failed: $topic → $payload');
        } else if (status != 'ok') {
          debugPrint('[SupabaseRealtime] phx_reply status=$status ref=$ref');
        }
        return;
      }

      if (event == 'phx_error' || event == 'phx_close') {
        final topic = (msg['topic']?.toString() ?? '')
            .replaceFirst('realtime:', '');
        if (topic.isNotEmpty) {
          _liveTopics.remove(topic);
          _activeTopics.remove(topic);
          _pendingJoins.removeWhere((_, t) => t == topic);
          debugPrint('[SupabaseRealtime] channel $event: $topic');
        }
      }
    } catch (e) {
      debugPrint('[SupabaseRealtime] message parse error: $e');
    }
  }

  // ── مساعد الاستهلاك ──────────────────────────────────────────────────────

  /// ينتظر تغييراً واحداً على أي جدول من [tables]، أو مهلة أمان.
  ///
  /// - إن كان الاشتراك [topic] حيّاً: ننتظر حتى [safety] كحد أقصى (شبكة أمان)
  ///   ويصل التحديث فوراً عند أي تغيير حقيقي.
  /// - إن لم يكن حيّاً (جدول غير مفعّل/لا اتصال): ننتظر [fallback] فقط
  ///   فتبقى دورات الـ polling القديمة كما هي.
  Future<void> waitForTableChange({
    required String topic,
    required Set<String> tables,
    required Duration fallback,
    Duration safety = const Duration(seconds: 8),
  }) async {
    if (!isTopicLive(topic)) {
      await Future.delayed(fallback);
      return;
    }
    try {
      await _changes.stream
          .firstWhere((c) => tables.contains(c.table))
          .timeout(safety);
    } catch (_) {
      // مهلة أمان — دورية عادية
    }
  }
}
