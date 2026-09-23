import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svga/flutter_svga.dart';

import '../../../services/media_cache_service.dart';
import '../../../services/performance_monitor.dart';



// ═══════════════════════════════════════════════════════════════════════════
// SvgaNativePlayer — يُشغّل SVGA بمكتبة SVGAPlayer-Android الأصلية
// عبر AndroidView (PlatformView) بدلاً من Flutter Canvas.
// النتيجة: نفس سرعة التطبيق الأصلي تماماً على Android.
// ═══════════════════════════════════════════════════════════════════════════
class SvgaNativePlayer extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final bool loops;
  final VoidCallback? onReady;
  final VoidCallback? onError;

  const SvgaNativePlayer({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.loops = true,
    this.onReady,
    this.onError,
  });

  @override
  State<SvgaNativePlayer> createState() => _SvgaNativePlayerState();
}

class _SvgaNativePlayerState extends State<SvgaNativePlayer> {
  MethodChannel? _channel;

  @override
  Widget build(BuildContext context) {
    final w = widget.width ?? 200.0;
    final h = widget.height ?? 200.0;
    return RepaintBoundary(
      child: SizedBox(
        width: w,
        height: h,
        child: AndroidView(
          viewType: 'svga_native_view',
          creationParams: <String, dynamic>{
            'url': widget.url,
            'loops': widget.loops,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: (int viewId) {
            _channel = MethodChannel('svga_native_view_$viewId');
            _channel!.setMethodCallHandler((call) async {
              switch (call.method) {
                case 'onReady':
                  widget.onReady?.call();
                  break;
                case 'onError':
                  widget.onError?.call();
                  break;
              }
            });
          },
        ),
      ),
    );
  }

  /// أوامر خارجية: تشغيل / إيقاف / مسح
  Future<void> play()  => _channel?.invokeMethod('play')  ?? Future.value();
  Future<void> stop()  => _channel?.invokeMethod('stop')  ?? Future.value();
  Future<void> clear() => _channel?.invokeMethod('clear') ?? Future.value();

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}

class SvgaPlayer extends StatefulWidget {
  final String assetPath;
  final double? width;
  final double? height;
  final bool loops;
  final VoidCallback? onFinished;
  final BoxFit fit;
  final Map<String, String>? textReplacement; // SVGA layer key -> user text
  final Map<String, String>? imageReplacement; // SVGA layer key -> image URL
  final String? defaultImageUrl; // fallback image if user has no photo

  const SvgaPlayer({
    super.key,
    required this.assetPath,
    this.width,
    this.height,
    this.loops = true,
    this.onFinished,
    this.fit = BoxFit.contain,
    this.textReplacement,
    this.imageReplacement,
    this.defaultImageUrl,
  });

  // ── طبقة ذاكرة محدودة (LRU) للبايتات — تحتفظ بالبايتات الخام فقط لتفادي تسريب الذاكرة
  //    بدون تخزين كائنات MovieEntity التي تحتوي على مراجع للرسم ويؤدي تشاركها لتوقف الأنيميشن
  static final LinkedHashMap<String, Uint8List> _bytesCache = LinkedHashMap();
  static int _bytesTotal = 0;
  static const int _maxBytesTotal = 32 * 1024 * 1024; // 32MB with cap

  static bool _isNetwork(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  /// Pre-downloads an SVGA [url] into the shared cache so future plays are instant.
  /// التحميل خارج الـ Isolate الرئيسي (لا يوقف الـ UI).
  static Future<String?> prefetch(String url) async {
    if (!_isNetwork(url)) return null;
    try {
      if (_bytesCache.containsKey(url)) return url;
      final cached = await MediaCacheService().getCachedBytes(url);
      if (cached != null) return url;
      final bytes = await MediaCacheService().downloadToBytesBackground(url);
      SvgaPlayer._writeBytes(url, bytes);
      return url;
    } catch (e) {
      debugPrint('SVGA prefetch error: $e');
      return null;
    }
  }

  static Uint8List? _readBytes(String url) {
    final bytes = _bytesCache.remove(url);
    if (bytes == null) return null;
    _bytesCache[url] = bytes; // تصبح الأحدث (LRU)
    return bytes;
  }

  static void _writeBytes(String url, Uint8List bytes) {
    if (_bytesCache.containsKey(url)) return;
    _bytesCache[url] = bytes;
    _bytesTotal += bytes.length;
    while (_bytesTotal > _maxBytesTotal && _bytesCache.isNotEmpty) {
      final first = _bytesCache.keys.first;
      final removed = _bytesCache.remove(first);
      if (removed != null) _bytesTotal -= removed.length;
    }
  }

  /// يفرّغ طبقة الذاكرة لـ SVGA (يُستدعى عند الخروج من الغرفة).
  static void trimMemoryCache({int keepBytes = 8 * 1024 * 1024}) {
    while (_bytesTotal > keepBytes && _bytesCache.isNotEmpty) {
      final first = _bytesCache.keys.first;
      final removed = _bytesCache.remove(first);
      if (removed != null) _bytesTotal -= removed.length;
    }
  }

  static void evictMemory(String url) {
    final removed = _bytesCache.remove(url);
    if (removed != null) _bytesTotal -= removed.length;
  }

  @override
  State<SvgaPlayer> createState() => _SvgaPlayerState();
}

class _SvgaPlayerState extends State<SvgaPlayer> with SingleTickerProviderStateMixin {
  SVGAAnimationController? animationController;
  bool isLoading = true;
  bool hasError = false;
  Timer? _loadTimeout;
  bool _finishedOnce = false;
  String? _activeUrl;
  Uint8List? _fallbackImageBytes;

  static bool _isImageMagicBytes(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    // GIF: 47 49 46
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
    // WEBP: 52 49 46 46 (RIFF)
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) return true;
    return false;
  }

  static bool _isVideoMagicBytes(Uint8List bytes) {
    if (bytes.length < 12) return false;
    // ftyp (mp4 / m4v / mov)
    if (bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) return true;
    return false;
  }

  @override
  void initState() {
    super.initState();
    animationController = SVGAAnimationController(vsync: this);
    _activeUrl = _networkUrlOrNull();
    // مهلة أمان: لو تعطل التحميل/الحقن الديناميكي لا تبقى الشاشة على الـ spinner
    // إلى الأبد مع إعطاء وقت كافٍ لتحميل الملفات الكبيرة والشبكات البطيئة (15 ثانية)
    _loadTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted && isLoading) {
        _finishOrFallback();
      }
    });
    _loadAnimation();
  }

  String? _networkUrlOrNull() => SvgaPlayer._isNetwork(widget.assetPath)
      ? widget.assetPath
      : null;

  @override
  void didUpdateWidget(SvgaPlayer old) {
    super.didUpdateWidget(old);
    // Compare replacement maps by CONTENT, not identity: parent screens pass
    // freshly-allocated maps on every build, and identity comparison made the
    // player reload/restart the animation constantly so it never finished.
    if (old.assetPath != widget.assetPath ||
        !mapEquals(old.textReplacement, widget.textReplacement) ||
        !mapEquals(old.imageReplacement, widget.imageReplacement)) {
      try {
        animationController?.stop();
        animationController?.reset();
      } catch (_) {}
      _activeUrl = _networkUrlOrNull();
      setState(() {
        isLoading = true;
        hasError = false;
        _finishedOnce = false;
      });
      _loadTimeout?.cancel();
      _loadTimeout = Timer(const Duration(seconds: 15), () {
        if (mounted && isLoading) {
          _finishOrFallback();
        }
      });
      _loadAnimation();
    }
  }

  void _finishOnce() {
    if (_finishedOnce) return;
    _finishedOnce = true;
    _loadTimeout?.cancel();
    widget.onFinished?.call();
  }

  void _finishOrFallback() {
    if (!mounted) return;
    _loadTimeout?.cancel();
    if (isLoading) {
      // تحميل عالق: نعرض خطأ بدلاً من spinner دائم، ثم نكمل.
      setState(() {
        isLoading = false;
        hasError = true;
      });
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) _finishOnce();
      });
    } else {
      _finishOnce();
    }
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    animationController?.dispose();
    animationController = null;
    super.dispose();
  }

  Future<void> _loadAnimation() async {
    final perf = PerformanceMonitor.instance;
    final token = perf.begin(PerformanceMonitor.catSvga, widget.assetPath);
    try {
      final isNetwork = _activeUrl != null;
      final videoItem = isNetwork
          ? await _loadFromUrl(_activeUrl!)
          : await _loadFromAsset(widget.assetPath);
      
      if (videoItem == null) {
        // تم معالجته كصورة بديلة (Image fallback)
        if (mounted) {
          _loadTimeout?.cancel();
          setState(() {
            isLoading = false;
            hasError = false;
          });
          if (!widget.loops) {
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) _finishOnce();
            });
          }
        }
        return;
      }

      if (mounted) {
        perf.ok(token, bytes: 0, source: 'cache');
        _loadTimeout?.cancel();
        setState(() {
          isLoading = false;
          try {
            animationController?.reset();
          } catch (_) {}
          animationController?.videoItem = videoItem;
          if (widget.loops) {
            animationController?.repeat();
          } else {
            animationController?.forward().then((_) {
              _finishOnce();
            });
          }
        });
      }
      unawaited(_injectDynamicContent(videoItem));
    } catch (e) {
      perf.err(token, e);
      debugPrint('SVGA error for ${widget.assetPath}: $e');
      if (mounted) {
        final bytes = SvgaPlayer._readBytes(widget.assetPath);
        if (bytes != null && bytes.isNotEmpty && _isImageMagicBytes(bytes)) {
          setState(() {
            _fallbackImageBytes = bytes;
            isLoading = false;
            hasError = false;
          });
          if (!widget.loops) {
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) _finishOnce();
            });
          }
          return;
        }
        setState(() {
          isLoading = false;
          hasError = true;
        });
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _finishOnce();
        });
      }
    }
  }

  Future<MovieEntity?> _loadFromAsset(String path) async {
    var cleanPath = path;
    if (cleanPath.startsWith('file://')) {
      final file = File(cleanPath.replaceFirst('file://', ''));
      final bytes = await file.readAsBytes();
      if (_isImageMagicBytes(bytes) || _isVideoMagicBytes(bytes) || cleanPath.toLowerCase().endsWith('.png') || cleanPath.toLowerCase().endsWith('.jpg') || cleanPath.toLowerCase().endsWith('.mp4')) {
        _fallbackImageBytes = bytes;
        return null;
      }
      return await SVGAParser.shared.decodeFromBuffer(bytes);
    }
    if (cleanPath.startsWith('/')) {
      cleanPath = cleanPath.substring(1);
    }
    try {
      return await SVGAParser.shared.decodeFromAssets(cleanPath);
    } catch (e) {
      debugPrint('[SvgaPlayer] decodeFromAssets failed ($e), trying rootBundle directly for $cleanPath');
      try {
        final byteData = await rootBundle.load(cleanPath);
        final bytes = byteData.buffer.asUint8List();
        if (_isImageMagicBytes(bytes) || _isVideoMagicBytes(bytes) || cleanPath.toLowerCase().endsWith('.png') || cleanPath.toLowerCase().endsWith('.jpg') || cleanPath.toLowerCase().endsWith('.mp4')) {
          _fallbackImageBytes = bytes;
          return null;
        }
        return await SVGAParser.shared.decodeFromBuffer(bytes);
      } catch (e2) {
        if (!cleanPath.startsWith('assets/')) {
          try {
            final byteData = await rootBundle.load('assets/$cleanPath');
            final bytes = byteData.buffer.asUint8List();
            if (_isImageMagicBytes(bytes) || _isVideoMagicBytes(bytes) || cleanPath.toLowerCase().endsWith('.png') || cleanPath.toLowerCase().endsWith('.jpg') || cleanPath.toLowerCase().endsWith('.mp4')) {
              _fallbackImageBytes = bytes;
              return null;
            }
            return await SVGAParser.shared.decodeFromBuffer(bytes);
          } catch (_) {}
        }
        rethrow;
      }
    }
  }

  void _setSvgText(dynamic dynamicItem, TextPainter painter, String rawKey) {
    final cleanKey = rawKey.replaceAll(RegExp(r'[\[\]\(\)]'), '').trim();
    if (cleanKey.isEmpty) return;
    dynamicItem.setText(painter, rawKey);
    dynamicItem.setText(painter, cleanKey);
    dynamicItem.setText(painter, '[$cleanKey]');
  }

  void _setSvgImage(dynamic dynamicItem, ui.Image image, String rawKey) {
    final cleanKey = rawKey.replaceAll(RegExp(r'[\[\]\(\)]'), '').trim();
    if (cleanKey.isEmpty) return;
    dynamicItem.setImage(image, rawKey);
    dynamicItem.setImage(image, cleanKey);
    dynamicItem.setImage(image, '[$cleanKey]');
  }

  Future<void> _injectDynamicContent(MovieEntity videoItem) async {
    if (widget.textReplacement == null && widget.imageReplacement == null) return;
    try {
      final dynamicItem = videoItem.dynamicItem;
      if (widget.textReplacement != null) {
        for (final entry in widget.textReplacement!.entries) {
          if (entry.key.isEmpty || entry.value.isEmpty) continue;
          final painter = TextPainter(
            text: TextSpan(
              text: entry.value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: _isArabic(entry.value)
                ? TextDirection.rtl
                : TextDirection.ltr,
          )..layout();
          _setSvgText(dynamicItem, painter, entry.key);
        }
      }
      if (widget.imageReplacement != null) {
        for (final entry in widget.imageReplacement!.entries) {
          if (entry.key.isEmpty || entry.value.isEmpty) continue;
          try {
            Uint8List? cachedBytes;
            if (entry.value.startsWith('assets/')) {
              final bd = await rootBundle.load(entry.value);
              cachedBytes = bd.buffer.asUint8List();
            } else if (entry.value.startsWith('file://') || entry.value.startsWith('/')) {
              cachedBytes = await File(entry.value.replaceFirst('file://', '')).readAsBytes();
            } else {
              cachedBytes = await MediaCacheService().getCachedBytes(entry.value);
            }
            if (cachedBytes != null && cachedBytes.isNotEmpty) {
              final codec = await ui.instantiateImageCodec(cachedBytes, targetWidth: 120, targetHeight: 120);
              final frame = await codec.getNextFrame();
              _setSvgImage(dynamicItem, frame.image, entry.key);
            } else {
              try {
                final dlBytes = await MediaCacheService()
                    .downloadToBytes(entry.value)
                    .timeout(const Duration(milliseconds: 1200));
                final codec = await ui.instantiateImageCodec(dlBytes, targetWidth: 120, targetHeight: 120);
                final frame = await codec.getNextFrame();
                _setSvgImage(dynamicItem, frame.image, entry.key);
              } catch (_) {
                await dynamicItem.setImageWithUrl(entry.value, entry.key)
                    .timeout(const Duration(milliseconds: 600));
              }
            }
          } catch (e) {
            if (widget.defaultImageUrl != null && widget.defaultImageUrl!.isNotEmpty) {
              try {
                final defBytes = await MediaCacheService().getCachedBytes(widget.defaultImageUrl!);
                if (defBytes != null && defBytes.isNotEmpty) {
                  final codec = await ui.instantiateImageCodec(defBytes, targetWidth: 120, targetHeight: 120);
                  final frame = await codec.getNextFrame();
                  _setSvgImage(dynamicItem, frame.image, entry.key);
                } else {
                  await dynamicItem.setImageWithUrl(widget.defaultImageUrl!, entry.key)
                      .timeout(const Duration(milliseconds: 400));
                }
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('SVGA dynamic injection error (non-fatal): $e');
    }
  }

  /// تحميل + فك ترميز ملف الشبكة مع تقاسم كل الطبقات:
  ///   1) متبثّت Decoded (نفس الملف غير الديناميكي).
  ///   2) بايتات LRU المحدودة.
  ///   3) قرص MediaCacheService.
  ///   4) شبكة عبر Dio مشترك ثم فك في نفس الوقت.
  Future<MovieEntity?> _loadFromUrl(String url) async {
    var bytes = SvgaPlayer._readBytes(url);
    if (bytes == null) {
      bytes = await MediaCacheService().getCachedBytes(url);
    }
    if (bytes == null) {
      bytes = await MediaCacheService().downloadToBytesBackground(url);
    }
    SvgaPlayer._writeBytes(url, bytes);

    if (_isImageMagicBytes(bytes) ||
        _isVideoMagicBytes(bytes) ||
        url.toLowerCase().contains('.png') ||
        url.toLowerCase().contains('.jpg') ||
        url.toLowerCase().contains('.webp') ||
        url.toLowerCase().contains('.gif') ||
        url.toLowerCase().contains('.mp4')) {
      _fallbackImageBytes = bytes;
      return null;
    }

    final t = PerformanceMonitor.instance.begin('svga_decode', url);
    try {
      final movie = await SVGAParser.shared.decodeFromBuffer(bytes);
      PerformanceMonitor.instance.ok(t, bytes: bytes.length, source: 'cache');
      return movie;
    } catch (e) {
      PerformanceMonitor.instance.err(t, e);
      if (bytes.isNotEmpty && _isImageMagicBytes(bytes)) {
        _fallbackImageBytes = bytes;
        return null;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width ?? 200;
    final h = widget.height ?? 200;
    if (_fallbackImageBytes != null) {
      return RepaintBoundary(
        child: SizedBox(
          width: w,
          height: h,
          child: Image.memory(
            _fallbackImageBytes!,
            fit: widget.fit,
            width: w,
            height: h,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: SizedBox(
        width: w,
        height: h,
        child: isLoading
            ? ((w <= 80 || h <= 80)
                ? const SizedBox.shrink()
                : const Center(child: CircularProgressIndicator(strokeWidth: 2)))
            : hasError
                ? (widget.defaultImageUrl != null && widget.defaultImageUrl!.isNotEmpty
                    ? Image.network(widget.defaultImageUrl!, width: w, height: h, fit: widget.fit,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink())
                    : const SizedBox.shrink())
                : animationController?.videoItem != null
                    ? RepaintBoundary(
                        child: SVGAImage(
                          animationController!,
                          fit: widget.fit,
                          preferredSize: Size(w, h),
                        ),
                      )
                    : const SizedBox.shrink(),
      ),
    );
  }
}

/// True when [text] contains Arabic script so text inside SVGA layers is
/// shaped/rendered right-to-left instead of scrambled LTR.
bool _isArabic(String text) {
  for (final rune in text.runes) {
    if ((rune >= 0x0600 && rune <= 0x06FF) || // Arabic
        (rune >= 0x0750 && rune <= 0x077F) || // Arabic Supplement
        (rune >= 0x08A0 && rune <= 0x08FF) || // Arabic Extended-A
        (rune >= 0xFB50 && rune <= 0xFDFF) || // Presentation Forms-A
        (rune >= 0xFE70 && rune <= 0xFEFF)) {
      // Presentation Forms-B
      return true;
    }
  }
  return false;
}