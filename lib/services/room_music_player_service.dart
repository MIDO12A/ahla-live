import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';

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
      isPlayingNotifier.value = state.playing;
      if (state.processingState == ProcessingState.completed) {
        _onTrackCompleted();
      }
    });

    _player!.positionStream.listen((pos) {
      positionNotifier.value = pos;
    });

    _player!.durationStream.listen((dur) {
      if (dur != null) {
        durationNotifier.value = dur;
      }
    });

    _player!.setVolume(volumeNotifier.value);
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

    try {
      _player ??= AudioPlayer();
      if (track.isLocal) {
        await _player!.setFilePath(track.path);
      } else {
        await _player!.setUrl(track.path);
      }
      await _player!.play();
    } catch (e) {
      debugPrint('[RoomMusicPlayerService] playTrack error: $e');
    }
  }

  Future<void> play() async {
    if (_currentIndex == -1 && _playlist.isNotEmpty) {
      await playTrack(0);
      return;
    }
    await _player?.play();
  }

  Future<void> pause() async {
    await _player?.pause();
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
    await _player?.seek(position);
  }

  Future<void> setVolume(double vol) async {
    final v = vol.clamp(0.0, 1.0);
    volumeNotifier.value = v;
    await _player?.setVolume(v);
  }

  void toggleLoopMode() {
    final current = loopModeNotifier.value;
    if (current == LoopMode.all) {
      loopModeNotifier.value = LoopMode.one;
      _player?.setLoopMode(LoopMode.one);
    } else if (current == LoopMode.one) {
      loopModeNotifier.value = LoopMode.off;
      _player?.setLoopMode(LoopMode.off);
    } else {
      loopModeNotifier.value = LoopMode.all;
      _player?.setLoopMode(LoopMode.all);
    }
  }

  Future<void> stop() async {
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
}
