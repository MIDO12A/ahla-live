import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:zego_express_engine/zego_express_engine.dart';
import 'room_audio_service.dart';

class RoomMusicTrack {
  final String id;
  final String title;
  final String artist;
  final String path;
  final bool isLocal;
  final Duration? duration;

  const RoomMusicTrack({
    required this.id,
    required this.title,
    this.artist = '',
    required this.path,
    this.isLocal = true,
    this.duration,
  });
}

class RoomMusicPlayerService {
  static final RoomMusicPlayerService _instance = RoomMusicPlayerService._();
  factory RoomMusicPlayerService() => _instance;
  RoomMusicPlayerService._() {
    _init();
  }

  AudioPlayer? _player;
  ZegoMediaPlayer? _zegoPlayer;
  bool _useZego = false;
  final List<RoomMusicTrack> _playlist = [];
  int _currentIndex = -1;

  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<RoomMusicTrack?> currentTrackNotifier = ValueNotifier<RoomMusicTrack?>(null);
  final ValueNotifier<List<RoomMusicTrack>> playlistNotifier = ValueNotifier<List<RoomMusicTrack>>([]);
  final ValueNotifier<Duration> positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> durationNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<double> volumeNotifier = ValueNotifier<double>(0.8);
  final ValueNotifier<LoopMode> loopModeNotifier = ValueNotifier<LoopMode>(LoopMode.all);

  bool get isPlaying => isPlayingNotifier.value;
  RoomMusicTrack? get currentTrack => currentTrackNotifier.value;
  List<RoomMusicTrack> get playlist => List.unmodifiable(_playlist);
  int get currentIndex => _currentIndex;

  void _init() {
    _player = AudioPlayer();

    _player!.playerStateStream.listen((state) {
      if (!_useZego) {
        isPlayingNotifier.value = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _onTrackCompleted();
        }
      }
    });

    _player!.positionStream.listen((pos) {
      if (!_useZego) {
        positionNotifier.value = pos;
      }
    });

    _player!.durationStream.listen((dur) {
      if (!_useZego && dur != null) {
        durationNotifier.value = dur;
      }
    });

    _player!.setVolume(volumeNotifier.value);
  }

  Future<void> _ensureZegoPlayer() async {
    final roomAudio = RoomAudioService();
    if (!roomAudio.isInitialized) return;
    if (_zegoPlayer != null) return;

    try {
      _zegoPlayer = await ZegoExpressEngine.instance.createMediaPlayer();
      if (_zegoPlayer != null) {
        await _zegoPlayer!.enableAux(true);
        await _zegoPlayer!.setVolume((volumeNotifier.value * 100).toInt());

        _zegoPlayer!.onMediaPlayerStateUpdate = (player, state, errorCode) {
          if (_useZego) {
            if (state == ZegoMediaPlayerState.Playing) {
              isPlayingNotifier.value = true;
            } else if (state == ZegoMediaPlayerState.Paused) {
              isPlayingNotifier.value = false;
            } else if (state == ZegoMediaPlayerState.NoPlay) {
              isPlayingNotifier.value = false;
              if (errorCode == 0) {
                _onTrackCompleted();
              }
            }
          }
        };

        _zegoPlayer!.onMediaPlayerPlayingProgress = (player, millisecond) {
          if (_useZego) {
            positionNotifier.value = Duration(milliseconds: millisecond);
          }
        };
      }
    } catch (e) {
      debugPrint('[RoomMusicPlayerService] createMediaPlayer error: $e');
    }
  }

  void _onTrackCompleted() {
    final mode = loopModeNotifier.value;
    if (mode == LoopMode.one) {
      seek(Duration.zero);
      play();
    } else if (mode == LoopMode.all) {
      next();
    } else {
      if (_currentIndex < _playlist.length - 1) {
        next();
      } else {
        stop();
      }
    }
  }

  Future<int> pickLocalAudioFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return 0;

      int addedCount = 0;
      for (final f in result.files) {
        final filePath = f.path;
        if (filePath != null && filePath.isNotEmpty) {
          final fileName = f.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
          final track = RoomMusicTrack(
            id: 'local_${DateTime.now().millisecondsSinceEpoch}_${addedCount}',
            title: fileName.isNotEmpty ? fileName : 'ملف صوتي',
            path: filePath,
            isLocal: true,
          );
          _playlist.add(track);
          addedCount++;
        }
      }

      playlistNotifier.value = List.from(_playlist);

      if (_currentIndex == -1 && _playlist.isNotEmpty) {
        await playTrack(_playlist.length - addedCount);
      }

      return addedCount;
    } catch (e) {
      debugPrint('[RoomMusicPlayerService] pickLocalAudioFiles error: $e');
      return 0;
    }
  }

  Future<void> addTrack(RoomMusicTrack track, {bool playImmediately = false}) async {
    _playlist.add(track);
    playlistNotifier.value = List.from(_playlist);
    if (playImmediately || _currentIndex == -1) {
      await playTrack(_playlist.length - 1);
    }
  }

  Future<void> playTrack(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    _currentIndex = index;
    final track = _playlist[index];
    currentTrackNotifier.value = track;

    final roomAudio = RoomAudioService();
    if (roomAudio.isInitialized && !roomAudio.isPublishing) {
      unawaited(roomAudio.startPublishing());
    }

    await _ensureZegoPlayer();

    if (_zegoPlayer != null) {
      _useZego = true;
      try {
        await _player?.stop();
        await _zegoPlayer!.stop();
        final res = await _zegoPlayer!.loadResource(track.path);
        if (res.errorCode == 0) {
          final totalMs = await _zegoPlayer!.getTotalDuration();
          if (totalMs > 0) {
            durationNotifier.value = Duration(milliseconds: totalMs);
          }
          await _zegoPlayer!.enableAux(true);
          await _zegoPlayer!.setVolume((volumeNotifier.value * 100).toInt());
          await _zegoPlayer!.start();
          isPlayingNotifier.value = true;
          return;
        } else {
          debugPrint('[RoomMusicPlayerService] zego loadResource failed code: ${res.errorCode}, falling back to just_audio');
        }
      } catch (e) {
        debugPrint('[RoomMusicPlayerService] zego play error: $e, falling back to just_audio');
      }
    }

    _useZego = false;
    try {
      _player ??= AudioPlayer();
      if (track.isLocal) {
        await _player!.setFilePath(track.path);
      } else {
        await _player!.setUrl(track.path);
      }
      await _player!.play();
      isPlayingNotifier.value = true;
    } catch (e) {
      debugPrint('[RoomMusicPlayerService] playTrack fallback error: $e');
    }
  }

  Future<void> play() async {
    if (_currentIndex == -1 && _playlist.isNotEmpty) {
      await playTrack(0);
      return;
    }
    if (_useZego && _zegoPlayer != null) {
      await _zegoPlayer!.resume();
      isPlayingNotifier.value = true;
    } else {
      await _player?.play();
      isPlayingNotifier.value = true;
    }
  }

  Future<void> pause() async {
    if (_useZego && _zegoPlayer != null) {
      await _zegoPlayer!.pause();
      isPlayingNotifier.value = false;
    } else {
      await _player?.pause();
      isPlayingNotifier.value = false;
    }
  }

  Future<void> togglePlay() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> next() async {
    if (_playlist.isEmpty) return;
    int nextIdx = _currentIndex + 1;
    if (nextIdx >= _playlist.length) {
      nextIdx = 0;
    }
    await playTrack(nextIdx);
  }

  Future<void> previous() async {
    if (_playlist.isEmpty) return;
    int prevIdx = _currentIndex - 1;
    if (prevIdx < 0) {
      prevIdx = _playlist.length - 1;
    }
    await playTrack(prevIdx);
  }

  Future<void> seek(Duration position) async {
    positionNotifier.value = position;
    if (_useZego && _zegoPlayer != null) {
      await _zegoPlayer!.seekTo(position.inMilliseconds);
    } else {
      await _player?.seek(position);
    }
  }

  Future<void> setVolume(double vol) async {
    final v = vol.clamp(0.0, 1.0);
    volumeNotifier.value = v;
    if (_zegoPlayer != null) {
      await _zegoPlayer!.setVolume((v * 100).toInt());
    }
    await _player?.setVolume(v);
  }

  void toggleLoopMode() {
    final current = loopModeNotifier.value;
    if (current == LoopMode.all) {
      loopModeNotifier.value = LoopMode.one;
      _zegoPlayer?.enableRepeat(true);
      _player?.setLoopMode(LoopMode.one);
    } else if (current == LoopMode.one) {
      loopModeNotifier.value = LoopMode.off;
      _zegoPlayer?.enableRepeat(false);
      _player?.setLoopMode(LoopMode.off);
    } else {
      loopModeNotifier.value = LoopMode.all;
      _zegoPlayer?.enableRepeat(false);
      _player?.setLoopMode(LoopMode.all);
    }
  }

  Future<void> stop() async {
    if (_zegoPlayer != null) {
      await _zegoPlayer!.stop();
    }
    await _player?.stop();
    isPlayingNotifier.value = false;
  }

  void clearPlaylist() {
    stop();
    _playlist.clear();
    _currentIndex = -1;
    currentTrackNotifier.value = null;
    playlistNotifier.value = [];
  }

  void release() {
    stop();
    if (_zegoPlayer != null) {
      ZegoExpressEngine.instance.destroyMediaPlayer(_zegoPlayer!);
      _zegoPlayer = null;
    }
    _useZego = false;
  }
}
