import 'dart:async';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/supabase_data_service.dart';
import '../services/room_audio_service.dart';

/// Global service to track minimized room state and keep audio/seat presence active
class MinimizedRoomService extends ChangeNotifier {
  static final MinimizedRoomService _instance = MinimizedRoomService._();
  factory MinimizedRoomService() => _instance;
  MinimizedRoomService._();

  bool _isActive = false;
  String? _roomId;
  String? _roomName;
  String? _hostName;
  String? _roomPassword;
  String? _hotValue;
  String? _gameDesc;
  String? _roomPhoto;
  String? _userId;
  int? _seatIndex;
  bool _isOnSeat = false;
  bool _isMicMuted = false;
  Timer? _presencePingTimer;

  bool get isActive => _isActive;
  String? get roomId => _roomId;
  String? get roomName => _roomName;
  String? get hostName => _hostName;
  String? get roomPassword => _roomPassword;
  String? get hotValue => _hotValue;
  String? get gameDesc => _gameDesc;
  String? get roomPhoto => _roomPhoto;
  String? get userId => _userId;
  int? get seatIndex => _seatIndex;
  bool get isOnSeat => _isOnSeat;
  bool get isMicMuted => _isMicMuted;

  bool isActiveFor(String id) => _isActive && _roomId == id;

  void activate({
    required String roomId,
    required String roomName,
    String? hostName,
    String? roomPassword,
    String? hotValue,
    String? gameDesc,
    String? roomPhoto,
    String? userId,
    int? seatIndex,
    bool isOnSeat = false,
    bool isMicMuted = false,
    RoomAudioService? audioService,
  }) {
    _isActive = true;
    _roomId = roomId;
    _roomName = roomName;
    _hostName = hostName;
    _roomPassword = roomPassword;
    _hotValue = hotValue;
    _gameDesc = gameDesc;
    _roomPhoto = roomPhoto;
    _userId = userId;
    _seatIndex = seatIndex;
    _isOnSeat = isOnSeat;
    _isMicMuted = isMicMuted;

    // Start background presence ping so zombie cleaner never removes minimized user
    _startPresencePing();
    notifyListeners();
  }

  void _startPresencePing() {
    _presencePingTimer?.cancel();
    _sendPing();
    _presencePingTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _sendPing();
    });
  }

  void _sendPing() {
    final rid = _roomId;
    final uid = _userId;
    if (rid == null || uid == null || !_isActive) return;
    try {
      SupabaseDataService().sendPresencePing(rid, uid).catchError((_) {});
    } catch (_) {}
  }

  Future<void> toggleMic() async {
    if (!_isOnSeat) return;
    final newMuted = !_isMicMuted;
    _isMicMuted = newMuted;
    await RoomAudioService().toggleMic(!newMuted);
    final rid = _roomId;
    final sIdx = _seatIndex;
    if (rid != null && sIdx != null) {
      try {
        await SupabaseService().toggleMute(rid, sIdx, newMuted);
      } catch (_) {}
    }
    notifyListeners();
  }

  void deactivate() {
    _presencePingTimer?.cancel();
    _presencePingTimer = null;
    _isActive = false;
    _roomId = null;
    _roomName = null;
    _hostName = null;
    _roomPassword = null;
    _hotValue = null;
    _gameDesc = null;
    _roomPhoto = null;
    _userId = null;
    _seatIndex = null;
    _isOnSeat = false;
    _isMicMuted = false;
    notifyListeners();
  }

  /// Clean up room completely from Firestore, Supabase, and Zego audio
  Future<void> exitRoom(String userId) async {
    final oldRoomId = _roomId;
    deactivate();
    if (oldRoomId != null) {
      try {
        await SupabaseService().leaveSeatForUser(oldRoomId, userId);
      } catch (_) {}
      try {
        await SupabaseService().leaveRoom(oldRoomId, userId);
      } catch (_) {}
      try {
        await RoomAudioService().leaveChannel();
      } catch (_) {}
    }
  }
}
