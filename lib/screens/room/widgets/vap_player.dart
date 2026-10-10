import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_vap_plugin/flutter_vap_plugin.dart';
import 'package:just_audio/just_audio.dart';

import '../../../services/media_cache_service.dart';

/// Rock-solid VAP Player supporting alpha transparency (Tencent VAP)
/// and Injected Dynamic Parameters (VAP المحقون: dynamic text and avatar replacement).
class VapPlayer extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final bool loops;
  final VoidCallback? onFinished;
  final BoxFit fit;
  final Map<String, String>? textReplacement;
  final Map<String, String>? imageReplacement;
  final String? defaultImageUrl;

  const VapPlayer({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.loops = true,
    this.onFinished,
    this.fit = BoxFit.contain,
    this.textReplacement,
    this.imageReplacement,
    this.defaultImageUrl,
  });

  /// Pre-downloads a VAP/MP4 [url] to persistent disk cache
  /// so the first play is instant. Returns the local path or null on failure.
  static Future<String?> prefetch(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) return null;
    try {
      final cachedPath = await MediaCacheService().getCachedPath(url);
      if (cachedPath != null) return cachedPath;
      return await MediaCacheService().download(url);
    } catch (e) {
      debugPrint('VapPlayer prefetch error for $url: $e');
      return null;
    }
  }

  static Future<String> _cachePathFor(String url) async {
    return await MediaCacheService().pathFor(url);
  }

  @override
  State<VapPlayer> createState() => _VapPlayerState();
}

class _VapPlayerState extends State<VapPlayer> with SingleTickerProviderStateMixin {
  final FlutterVapController _controller = FlutterVapController();
  String? _localPath;
  bool _ready = false;
  bool _hasError = false;
  bool _isViewCreated = false;
  bool _finishedOnce = false;
  Timer? _safetyTimer;
  late AnimationController _fadeController;
  AudioPlayer? _audioPlayer;
  late int _sessionKey;

  @override
  void initState() {
    super.initState();
    _sessionKey = DateTime.now().millisecondsSinceEpoch;
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    // مهلة أمان قصوى لمنع تجميد الشاشة أو بقاء الهدية عالقة إذا تعطل محرك الـ VAP الأصلي
    if (!widget.loops) {
      _safetyTimer = Timer(const Duration(seconds: 12), () {
        if (mounted && !_finishedOnce) {
          _finishSafely(forceStop: true);
        }
      });
    }

    _resolveSource();
  }

  void _finishSafely({bool forceStop = false}) {
    if (_finishedOnce) return;
    _finishedOnce = true;
    _safetyTimer?.cancel();
    _safetyTimer = null;
    final p = _audioPlayer;
    _audioPlayer = null;
    if (p != null) {
      try {
        p.dispose();
      } catch (_) {}
    }
    if (forceStop) {
      try {
        _controller.stop();
      } catch (_) {}
    }
    widget.onFinished?.call();
  }

  @override
  void didUpdateWidget(VapPlayer old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _controller.stop();
      _safetyTimer?.cancel();
      final p = _audioPlayer;
      _audioPlayer = null;
      if (p != null) {
        try {
          p.dispose();
        } catch (_) {}
      }
      _finishedOnce = false;
      _isViewCreated = false;
      _localPath = null;
      _ready = false;
      _hasError = false;
      _sessionKey = DateTime.now().millisecondsSinceEpoch;
      if (!widget.loops) {
        _safetyTimer = Timer(const Duration(seconds: 12), () {
          if (mounted && !_finishedOnce) {
            _finishSafely(forceStop: true);
          }
        });
      }
      _resolveSource();
    }
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    _safetyTimer = null;
    final p = _audioPlayer;
    _audioPlayer = null;
    if (p != null) {
      try {
        p.dispose();
      } catch (_) {}
    }
    if (!_finishedOnce) {
      try {
        _controller.stop();
      } catch (_) {}
    }
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _resolveSource() async {
    try {
      final url = widget.url;
      if (url.startsWith('http://') || url.startsWith('https://')) {
        final path = await MediaCacheService().getCachedPath(url);
        if (path != null && await File(path).exists() && await File(path).length() > 0) {
          _localPath = path;
        } else {
          _localPath = await MediaCacheService().download(url);
        }
      } else if (url.startsWith('assets/')) {
        final path = await MediaCacheService().pathFor(url);
        final file = File(path);
        if (!await file.exists() || await file.length() == 0) {
          final byteData = await rootBundle.load(url);
          await file.writeAsBytes(
            byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
            flush: true,
          );
        }
        _localPath = file.path;
      } else {
        _localPath = url;
      }
      if (mounted) {
        setState(() => _ready = true);
        if (_isViewCreated) {
          _playCurrent();
        }
      }
    } catch (e) {
      debugPrint('*** VapPlayer download error for ${widget.url}: $e');
      if (mounted) {
        setState(() => _hasError = true);
        _finishSafely();
      }
    }
  }

  void _playCurrent() {
    if (_localPath == null) return;
    try {
      _controller.play(
        path: _localPath!,
        sourceType: VapSourceType.file,
        repeatCount: widget.loops ? -1 : 1,
        deleteOnEnd: false,
        textReplacement: widget.textReplacement,
        imageReplacement: widget.imageReplacement,
      );
      _playAudioTrackIfNeeded();
    } catch (e) {
      debugPrint('*** VapPlayer play error: $e');
    }
  }

  void _playAudioTrackIfNeeded() {
    if (_localPath == null) return;
    try {
      final file = File(_localPath!);
      if (!file.existsSync()) return;
      _audioPlayer ??= AudioPlayer();
      _audioPlayer!.setFilePath(_localPath!).then((_) {
        if (!mounted || _finishedOnce) return;
        _audioPlayer!.setVolume(1.0);
        if (widget.loops) {
          _audioPlayer!.setLoopMode(LoopMode.one);
        }
        _audioPlayer!.play();
      }).catchError((e) {
        // Silently ignore if file has no audio stream
        debugPrint('[VapPlayer] Audio track notice: $e');
      });
    } catch (_) {}
  }

  VapScaleType _mapFit() {
    switch (widget.fit) {
      case BoxFit.fill:
        return VapScaleType.fitXY;
      case BoxFit.cover:
        return VapScaleType.centerCrop;
      default:
        return VapScaleType.fitCenter;
    }
  }

  Widget _buildFallback(double w, double h) {
    if (widget.defaultImageUrl != null && widget.defaultImageUrl!.isNotEmpty) {
      return Image.network(
        widget.defaultImageUrl!,
        width: w,
        height: h,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = widget.height;

    if (_hasError || (_ready && _localPath == null)) {
      return _buildFallback(w ?? 0, h ?? 0);
    }

    if (!_ready) {
      if (widget.defaultImageUrl != null && widget.defaultImageUrl!.isNotEmpty) {
        return _buildFallback(w ?? 0, h ?? 0);
      }
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: w,
      height: h,
      child: RepaintBoundary(
        child: FlutterVapView(
          key: ValueKey<String>('vap_${widget.url}_$_sessionKey'),
          controller: _controller,
          scaleType: _mapFit(),
          onVideoFinish: () {
            if (!widget.loops) {
              _finishSafely();
            }
          },
          onFailed: (errCode, errMsg) {
            debugPrint('FlutterVapView onFailed: code=$errCode, msg=$errMsg');
            if (mounted) {
              setState(() => _hasError = true);
              _finishSafely();
            }
          },
          onCreateView: () {
            _isViewCreated = true;
            _playCurrent();
          },
        ),
      ),
    );
  }
}

