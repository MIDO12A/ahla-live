import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zego_express_engine/zego_express_engine.dart';
import '../config/app_config.dart';
import '../services/dynamic_config_service.dart';

class RoomAudioService {
  static final RoomAudioService _instance = RoomAudioService._();
  factory RoomAudioService() => _instance;
  RoomAudioService._();

  bool _initialized = false;
  bool _micEnabled = true;
  bool _isPublishing = false;
  String? _currentRoomId;
  String? _currentUid;

  // Serialize engine lifecycle: never allow two createEngineWithProfile /
  // destroyEngine calls to overlap (overlapping calls crash natively inside
  // libZegoExpressEngine.so -> zego_express_engine_init with SIGSEGV).
  Future<bool>? _initFuture;
  Future<void>? _disposeFuture;

  bool get isInitialized => _initialized;
  bool get isMicEnabled => _micEnabled;
  bool get isPublishing => _isPublishing;
  bool _isRoomDeafened = false;
  int _roomVolume = 100;

  bool get isRoomDeafened => _isRoomDeafened;
  int get roomVolume => _roomVolume;
  final ValueNotifier<bool> roomDeafenedNotifier = ValueNotifier<bool>(false);

  final ValueNotifier<Set<String>> speakingUsersNotifier = ValueNotifier<Set<String>>({});

  int get effectiveAppId {
    final id = DynamicConfigService().zegoAppId;
    return id != 0 ? id : AppConfig.zegoAppId;
  }

  String get effectiveAppSign {
    final sign = DynamicConfigService().zegoAppSign;
    return sign.isNotEmpty ? sign : AppConfig.zegoAppSign;
  }

  Future<void> setRoomVolume(int volume) async {
    _roomVolume = volume.clamp(0, 100);
    if (!_initialized || effectiveAppSign.isEmpty) return;
    try {
      await ZegoExpressEngine.instance.setAllPlayStreamVolume(_roomVolume);
      debugPrint('[RoomAudioService] Set room playback volume: $_roomVolume');
    } catch (e) {
      debugPrint('[RoomAudioService] setRoomVolume failed: $e');
    }
  }

  Future<void> toggleRoomDeafen([bool? deafen]) async {
    _isRoomDeafened = deafen ?? !_isRoomDeafened;
    roomDeafenedNotifier.value = _isRoomDeafened;
    if (!_initialized || effectiveAppSign.isEmpty) return;
    try {
      await ZegoExpressEngine.instance.muteAllPlayStreamAudio(_isRoomDeafened);
      debugPrint('[RoomAudioService] Room deafen toggled to: $_isRoomDeafened');
    } catch (e) {
      debugPrint('[RoomAudioService] toggleRoomDeafen failed: $e');
    }
  }

  void _onRoomStreamUpdate(String roomID, ZegoUpdateType updateType,
      List<ZegoStream> streamList, Map<String, dynamic> extendedData) {
    if (!_initialized || effectiveAppSign.isEmpty) return;
    try {
      final engine = ZegoExpressEngine.instance;
      for (final stream in streamList) {
        if (updateType == ZegoUpdateType.Add) {
          engine.startPlayingStream(stream.streamID).catchError((e) {
            debugPrint('[ZegoAudio] startPlayingStream error: $e');
          });
          if (_isRoomDeafened) {
            engine.mutePlayStreamAudio(stream.streamID, true).catchError((_) {});
          }
          debugPrint('[ZegoAudio] Started playing stream: ${stream.streamID}');
        } else {
          engine.stopPlayingStream(stream.streamID).catchError((e) {
            debugPrint('[ZegoAudio] stopPlayingStream error: $e');
          });
          debugPrint('[ZegoAudio] Stopped playing stream: ${stream.streamID}');
        }
      }
    } catch (e) {
      debugPrint('[RoomAudioService] _onRoomStreamUpdate error: $e');
    }
  }

  Future<bool> initialize() {
    if (_initialized) return Future<bool>.value(true);
    // Reuse the in-flight init so concurrent callers (double room push,
    // rapid enter/exit) share one createEngineWithProfile call.
    return _initFuture ??= _doInitialize().whenComplete(() => _initFuture = null);
  }

  Future<bool> _doInitialize() async {
    try {
      final cfg = DynamicConfigService();
      final appId = effectiveAppId;
      final appSign = effectiveAppSign;

      if (!cfg.zegoAudioEnabled) {
        debugPrint('[RoomAudioService] Zego audio is disabled in control panel');
        return false;
      }

      if (appSign.isEmpty) {
        debugPrint('[RoomAudioService] Zego appSign missing — configure in Control Panel or build with --dart-define=ZEGO_APP_SIGN');
        return false;
      }
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        debugPrint('[RoomAudioService] Microphone permission denied');
        return false;
      }
      // If a destroy is still running from a previous room, wait for it.
      await _disposeFuture;

      ZegoScenario scenario;
      switch (cfg.zegoScenario) {
        case 1:
          scenario = ZegoScenario.StandardVoiceCall;
          break;
        case 2:
          scenario = ZegoScenario.HighQualityChatroom;
          break;
        default:
          scenario = ZegoScenario.Default;
      }

      await ZegoExpressEngine.createEngineWithProfile(ZegoEngineProfile(
        appId, scenario, appSign: appSign,
      ));
      ZegoExpressEngine.onRoomStreamUpdate = _onRoomStreamUpdate;

      // Monitor captured mic and remote streams to trigger speaking wave animations
      ZegoExpressEngine.onCapturedSoundLevelUpdate = (double soundLevel) {
        if (!_isPublishing || !_micEnabled || _currentUid == null) {
          _removeSpeaker(_currentUid);
          return;
        }
        if (soundLevel > 5.0) {
          _addSpeaker(_currentUid!);
        } else {
          _removeSpeaker(_currentUid);
        }
      };

      ZegoExpressEngine.onRemoteSoundLevelUpdate = (Map<String, double> soundLevels) {
        soundLevels.forEach((streamID, level) {
          final uid = _extractUidFromStream(streamID);
          if (uid != null) {
            if (level > 5.0) {
              _addSpeaker(uid);
            } else {
              _removeSpeaker(uid);
            }
          }
        });
      };

      try {
        await ZegoExpressEngine.instance.startSoundLevelMonitor(
          config: ZegoSoundLevelConfig(100, true),
        );
      } catch (e) {
        debugPrint('[RoomAudioService] startSoundLevelMonitor failed: $e');
      }

      _initialized = true;
      debugPrint('[RoomAudioService] Zego engine initialized successfully (appId=$appId, scenario=$scenario)');
      return true;
    } catch (e) {
      debugPrint('[RoomAudioService] Init failed: $e');
      _initialized = false;
      return false;
    }
  }

  Future<void> joinChannel(String channelName, String uid) async {
    if (!_initialized || effectiveAppSign.isEmpty) {
      debugPrint('[RoomAudioService] Cannot join: not initialized');
      return;
    }
    try {
      await leaveChannel();
      _currentRoomId = channelName;
      _currentUid = uid;

      if (!_initialized || effectiveAppSign.isEmpty) {
        debugPrint('[RoomAudioService] Engine not initialized');
        return;
      }
      final engine = ZegoExpressEngine.instance;
      final user = ZegoUser(uid, uid);
      await engine.loginRoom(channelName, user, config: ZegoRoomConfig(0, true, ''));
      debugPrint('[RoomAudioService] Logged into room: $channelName');

      _micEnabled = true;
    } catch (e) {
      debugPrint('[RoomAudioService] joinChannel failed: $e');
    }
  }

  Future<void> startPublishing() async {
    if (!_initialized || _isPublishing || _currentRoomId == null || _currentUid == null || effectiveAppSign.isEmpty) return;
    try {
      final engine = ZegoExpressEngine.instance;
      final streamId = 'audio_${_currentUid}_$_currentRoomId';
      await engine.startPublishingStream(streamId);
      await engine.enableCamera(false);
      _isPublishing = true;
      debugPrint('[RoomAudioService] Started publishing stream: $streamId');
    } catch (e) {
      debugPrint('[RoomAudioService] startPublishing failed: $e');
    }
  }

  Future<void> leaveChannel() async {
    if (_currentRoomId == null) return;
    if (_initialized && effectiveAppSign.isNotEmpty) {
      try {
        final engine = ZegoExpressEngine.instance;
        await engine.stopPublishingStream();
        await engine.logoutRoom(_currentRoomId!);
      } catch (e) {
        debugPrint('[RoomAudioService] leaveChannel failed: $e');
      }
    }
    _currentRoomId = null;
    _isPublishing = false;
    _isRoomDeafened = false;
    roomDeafenedNotifier.value = false;
    speakingUsersNotifier.value = {};
  }

  Future<bool> toggleMic(bool on) async {
    if (!_initialized || !_isPublishing || effectiveAppSign.isEmpty) {
      _micEnabled = on;
      return true;
    }
    try {
      final engine = ZegoExpressEngine.instance;
      await engine.mutePublishStreamAudio(!on);
      _micEnabled = on;
      return true;
    } catch (e) {
      debugPrint('[RoomAudioService] toggleMic failed: $e');
      _micEnabled = on;
      return false;
    }
  }

  void muteRemoteAudio(String uid, String channelName, bool muted) async {
    if (!_initialized || effectiveAppSign.isEmpty) return;
    try {
      final engine = ZegoExpressEngine.instance;
      final streamId = 'audio_${uid}_$channelName';
      await engine.mutePlayStreamAudio(streamId, muted);
      debugPrint('[RoomAudioService] ${muted ? "Muted" : "Unmuted"} remote stream: $streamId');
    } catch (e) {
      debugPrint('[RoomAudioService] muteRemoteAudio failed: $e');
    }
  }

  void resetPublishingState() {
    _isPublishing = false;
    _micEnabled = true;
    debugPrint('[RoomAudioService] Publishing state reset');
  }

  /// إيقاف البث فقط لو كان مفعّلاً فعلاً — يمنع نداء native على محرك
  /// Zego غير المُهيأ (null object reference) حين يخرج المستخدم من المقعد.
  void stopPublishingIfActive() async {
    if (!_isPublishing || !_initialized || effectiveAppSign.isEmpty) {
      _isPublishing = false;
      return;
    }
    try {
      await ZegoExpressEngine.instance.stopPublishingStream();
    } catch (e) {
      debugPrint('[RoomAudioService] stopPublishingIfActive failed: $e');
    }
    _isPublishing = false;
  }

  /// Pause mic publishing when the app goes to the background to save battery
  /// and avoid Zego SIGSEGV on some devices. Remote audio (listening) keeps
  /// running so the minimized room stays audible.
  void pauseForBackground() async {
    if (!_isPublishing || !_initialized || effectiveAppSign.isEmpty) return;
    try {
      final engine = ZegoExpressEngine.instance;
      await engine.stopPublishingStream();
      _isPublishing = false;
      debugPrint('[RoomAudioService] Publishing paused for background');
    } catch (e) {
      debugPrint('[RoomAudioService] pauseForBackground failed: $e');
    }
  }

  /// Restore mic publishing when the app returns to the foreground.
  Future<void> resumeFromBackground() async {
    if (!_initialized || _currentRoomId == null || _currentUid == null || _isPublishing || effectiveAppSign.isEmpty) return;
    try {
      final engine = ZegoExpressEngine.instance;
      final streamId = 'audio_${_currentUid}_$_currentRoomId';
      await engine.startPublishingStream(streamId);
      _isPublishing = true;
      debugPrint('[RoomAudioService] Publishing resumed from background');
    } catch (e) {
      debugPrint('[RoomAudioService] resumeFromBackground failed: $e');
    }
  }

  void stopRemoteStream(String uid, String channelName) async {
    if (!_initialized || effectiveAppSign.isEmpty) return;
    try {
      final engine = ZegoExpressEngine.instance;
      final streamId = 'audio_${uid}_$channelName';
      await engine.stopPlayingStream(streamId);
      debugPrint('[RoomAudioService] Stopped remote stream: $streamId');
    } catch (e) {
      debugPrint('[RoomAudioService] stopRemoteStream failed: $e');
    }
  }

  Future<void> dispose() {
    if (!_initialized && _disposeFuture == null) return Future<void>.value();
    // Serialize destroys too: a createEngine must never overlap a destroy.
    return _disposeFuture ??= _doDispose().whenComplete(() => _disposeFuture = null);
  }

  Future<void> _doDispose() async {
    // Wait for any in-flight init to finish before destroying.
    await _initFuture;
    await leaveChannel();
    if (_initialized && effectiveAppSign.isNotEmpty) {
      try {
        await ZegoExpressEngine.destroyEngine();
      } catch (e) {
        debugPrint('[RoomAudioService] destroy failed: $e');
      }
    }
    _initialized = false;
    _micEnabled = true;
    speakingUsersNotifier.value = {};
    debugPrint('[RoomAudioService] Disposed');
  }

  String? _extractUidFromStream(String streamId) {
    if (!streamId.startsWith('audio_')) return null;
    final rest = streamId.substring(6);
    final lastUnder = rest.lastIndexOf('_');
    if (lastUnder > 0) {
      return rest.substring(0, lastUnder);
    }
    return rest;
  }

  void _addSpeaker(String uid) {
    if (!speakingUsersNotifier.value.contains(uid)) {
      speakingUsersNotifier.value = Set<String>.from(speakingUsersNotifier.value)..add(uid);
    }
  }

  void _removeSpeaker(String? uid) {
    if (uid == null) return;
    if (speakingUsersNotifier.value.contains(uid)) {
      speakingUsersNotifier.value = Set<String>.from(speakingUsersNotifier.value)..remove(uid);
    }
  }
}
