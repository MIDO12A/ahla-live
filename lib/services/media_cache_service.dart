import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'performance_monitor.dart';

/// إدخال قرص في [MediaCacheService._diskIndex] مع آخر وقت استخدام
/// لتطبيق LRU على مستوى القرص.
class _DiskEntry {
  final String key;
  final String path;
  int size;
  int lastAccess;
  _DiskEntry(this.key, this.path, this.size)
      : lastAccess = DateTime.now().millisecondsSinceEpoch;
}

/// طبقتا تخزين لجميع ملفات الوسائط (SVGA / VAP / MP4 / صور):
///   - RAM: LRU في الذاكرة بحد [maxMemoryBytes] (افتراضياً 48MB).
///   - Disk: LRU على القرص بحد [maxDiskBytes] (افتراضياً 500MB).
///
/// مقارنة بالنسخة السابقة التي كانت تنشئ `Dio` جديداً لكل تحميل:
///   - `Dio` واحد مشترك → إعادة استخدام الاتصال (keep-alive).
///   - التحميل الثقيل يُنفَّذ خارج Isolate الرئيسي عبر [`compute`].
///   - إخلاء حقيقي عند تجاوز الحد + تنظيف ملفات قديمة لا تخصّنا.
class MediaCacheService {
  static final MediaCacheService _instance = MediaCacheService._();
  factory MediaCacheService() => _instance;
  MediaCacheService._();

  static const String _cacheDirName = 'media_cache';
  static const String _indexFileName = 'cache_index.json';

  /// حدود الذاكرة (RAM) والقرص — القرص 500MB كما طُلب، والذاكرة 48MB.
  static const int maxMemoryBytes = 48 * 1024 * 1024; // 48MB RAM
  static const int maxDiskBytes = 500 * 1024 * 1024; // 500MB disk

  // RAM layer.
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();
  int _memoryBytes = 0;

  Directory? _cacheDir;
  final Map<String, _DiskEntry> _diskIndex = {};
  Future<void>? _initFuture;
  bool _indexDirty = false;
  Timer? _indexSaveDebounce;

  // يمنع التحميل المزدوج لنفس الرابط (طلبات متزامنة تتشارك نفس الـ Future).
  final Map<String, Completer<Uint8List>> _pending = {};

  Dio? _dio;
  Dio get _sharedDio {
    final existing = _dio;
    if (existing != null) return existing;
    final created = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.bytes,
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    ));
    _dio = created;
    return created;
  }

  /// إجمالي البايت الموجود فعلياً على القرص (يحدّث العداد).
  Future<int> get diskBytes async {
    final dir = await cacheDirectory;
    int total = 0;
    try {
      await for (final f in dir.list(recursive: true)) {
        if (f is File) {
          try {
            total += await f.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// بايتات RAM المحجوزة حالياً.
  int get memoryBytes => _memoryBytes;

  String _keyFor(String url) => sha256.convert(utf8.encode(url)).toString();

  bool _isNetwork(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  String _extensionFromUrl(String url) {
    try {
      final path = Uri.parse(url).path;
      final dot = path.lastIndexOf('.');
      if (dot == -1) return '.cache';
      final ext = path.substring(dot);
      return (ext.length > 8) ? '.cache' : ext;
    } catch (_) {
      return '.cache';
    }
  }

  // ── تهيئة / فهرس ─────────────────────────────────────────────

  /// يُهيَّأ الكاش مبكراً (يُستدعى من main() قبل أي تحميل وسائط).
  /// يحمّل فهرس القرص بحيث تكون جميع الملفات المُخزَّنة سابقاً جاهزة فوراً.
  Future<void> init() => cacheDirectory.then((_) {});

  Future<Directory> get cacheDirectory async {
    if (_cacheDir != null) return _cacheDir!;
    final future = _initFuture;
    if (future != null) {
      await future;
      return _cacheDir!;
    }
    final completer = Completer<Directory>();
    _initFuture = completer.future.then((_) {});
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_cacheDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    await _loadIndex();
    completer.complete(dir);
    return dir;
  }

  Future<void> _loadIndex() async {
    try {
      final dir = _cacheDir!;
      final indexFile = File('${dir.path}/$_indexFileName');
      if (!await indexFile.exists()) return;
      final content = await indexFile.readAsString();
      if (content.trim().isEmpty) return;
      final decoded = json.decode(content) as Map<String, dynamic>;
      decoded.forEach((key, value) {
        final v = value as Map<String, dynamic>;
        _diskIndex[key] = _DiskEntry(
          key,
          v['path'] as String? ?? '',
          (v['size'] as num?)?.toInt() ?? 0,
        )..lastAccess = (v['lastAccess'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
      });
    } catch (_) {
      _diskIndex.clear();
    }
  }

  void _markIndexDirty() {
    if (_indexDirty) return;
    _indexDirty = true;
    _indexSaveDebounce?.cancel();
    _indexSaveDebounce = Timer(const Duration(milliseconds: 1200), () {
      _indexDirty = false;
      _persistIndex();
    });
  }

  Future<void> _persistIndex() async {
    try {
      final dir = _cacheDir!;
      final indexFile = File('${dir.path}/$_indexFileName');
      await indexFile.writeAsString(json.encode({
        for (final e in _diskIndex.entries)
          e.key: {
            'path': e.value.path,
            'size': e.value.size,
            'lastAccess': e.value.lastAccess,
          }
      }));
    } catch (_) {}
  }

  /// تعيين فهرس فارغ (يُستخدم بعد [clearCache]).
  void clearIndex() {
    _indexDirty = false;
    _indexSaveDebounce?.cancel();
    _diskIndex.clear();
    _memory.clear();
    _memoryBytes = 0;
  }

  // ── RAM layer ─────────────────────────────────────────────────

  Uint8List? _readMemory(String key) {
    final bytes = _memory.remove(key);
    if (bytes == null) return null;
    _memory[key] = bytes; // إعادة الإدراج = تصبح الأحدث (LRU)
    return bytes;
  }

  void _writeMemory(String key, Uint8List bytes) {
    if (_memory.containsKey(key)) return;
    _memory[key] = bytes;
    _memoryBytes += bytes.length;
    _evictMemoryTo(maxMemoryBytes);
  }

  void _evictMemoryTo(int targetBytes) {
    final it = _memory.keys.iterator;
    while (_memoryBytes > targetBytes && it.moveNext()) {
      final removed = _memory.remove(it.current);
      if (removed != null) _memoryBytes -= removed.length;
    }
  }

  /// يفرّغ جزءاً من طبقة RAM (يُستدعى عند إغلاق الغرفة / انخفاض الذاكرة).
  Future<void> trimMemory({int? keepBytes}) async {
    _evictMemoryTo(keepBytes ?? (maxMemoryBytes ~/ 4));
  }

  // ── قراءة ─────────────────────────────────────────────────────

  void _hit({required String cat, required String url, required int bytes, required String source}) {
    final t = PerformanceMonitor.instance.begin(cat, url)..sw.stop();
    PerformanceMonitor.instance.ok(t, bytes: bytes, source: source);
  }

  Future<void> _touchDisk(String key) {
    final entry = _diskIndex[key];
    if (entry == null) return Future.value();
    entry.lastAccess = DateTime.now().millisecondsSinceEpoch;
    _markIndexDirty();
    return Future.value();
  }

  /// بايتات [url] من RAM أو القرص (بدون تحميل شبكة)، أو null.
  Future<Uint8List?> getCachedBytes(String url) async {
    if (!_isNetwork(url)) return null;
    final key = _keyFor(url);

    final fromMemory = _readMemory(key);
    if (fromMemory != null) {
      _hit(cat: PerformanceMonitor.catDownload, url: url, bytes: fromMemory.length, source: 'memory');
      return fromMemory;
    }

    final entry = _diskIndex[key];
    if (entry != null) {
      final file = File(entry.path);
      if (await file.exists()) {
        entry.lastAccess = DateTime.now().millisecondsSinceEpoch;
        _markIndexDirty();
        try {
          final bytes = Uint8List.fromList(await file.readAsBytes());
          _writeMemory(key, bytes);
          _hit(cat: PerformanceMonitor.catDownload, url: url, bytes: bytes.length, source: 'disk');
          return bytes;
        } catch (_) {}
      } else {
        _diskIndex.remove(key);
        _markIndexDirty();
      }
    }
    return null;
  }

  /// مسار ملف [url] على القرص إن كان موجوداً (لا يحمّل من الشبكة).
  Future<String?> getCachedPath(String url) async {
    if (!_isNetwork(url)) return null;
    final key = _keyFor(url);
    final entry = _diskIndex[key];
    if (entry != null && await _exists(entry.path)) {
      await _touchDisk(key);
      return entry.path;
    }
    if (entry != null) {
      _diskIndex.remove(key);
      _markIndexDirty();
    }
    return null;
  }

  /// المسار المتوقع للملف المحلي لـ [url] (قد لا يكون موجوداً بعد).
  /// يستخدمه مشغّل VAP المحلي (يحتاج مسار ملف واحد).
  Future<String> pathFor(String url) async {
    final key = _keyFor(url);
    final entry = _diskIndex[key];
    if (entry != null && await _exists(entry.path)) return entry.path;
    final dir = await cacheDirectory;
    return '${dir.path}/$key${_extensionFromUrl(url)}';
  }

  Future<bool> _exists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  // ── تحميل ─────────────────────────────────────────────────────

  Future<Uint8List> downloadToBytes(String url, {bool force = false}) async {
    if (!_isNetwork(url)) {
      throw ArgumentError('MediaCacheService expects an http(s) url: $url');
    }
    if (!force) {
      final cached = await getCachedBytes(url);
      if (cached != null) return cached;
    }
    final pending = _pending[url];
    if (pending != null) return pending.future;

    final completer = Completer<Uint8List>();
    _pending[url] = completer;
    final t = PerformanceMonitor.instance.begin(PerformanceMonitor.catDownload, url);
    try {
      final bytes = await _networkBytes(url);
      if (bytes.isEmpty) throw HttpException('Empty response for $url');
      final key = _keyFor(url);
      await _storeBytes(url, key, bytes);
      PerformanceMonitor.instance.ok(t, bytes: bytes.length, source: 'network');
      completer.complete(bytes);
      return bytes;
    } catch (e) {
      PerformanceMonitor.instance.err(t, e);
      completer.completeError(e);
      rethrow;
    } finally {
      _pending.remove(url);
    }
  }

  /// تحميل مع إزاحة HTTP+IO بعيداً عن Isolate الرئيسي (يستخدمه الـ prefetch).
  Future<Uint8List> downloadToBytesBackground(String url) async {
    if (!_isNetwork(url)) {
      throw ArgumentError('MediaCacheService expects an http(s) url: $url');
    }
    // تحقق مخبّأ سريع أولاً.
    final cached = await getCachedBytes(url);
    if (cached != null) return cached;
    final pending = _pending[url];
    if (pending != null) return pending.future;

    final completer = Completer<Uint8List>();
    _pending[url] = completer;
    final t = PerformanceMonitor.instance.begin(PerformanceMonitor.catDownload, url);
    try {
      final bytes = await compute(_networkBytesIsolate, url);
      if (bytes.isEmpty) throw HttpException('Empty response for $url');
      final key = _keyFor(url);
      await _storeBytes(url, key, bytes);
      PerformanceMonitor.instance.ok(t, bytes: bytes.length, source: 'network');
      completer.complete(bytes);
      return bytes;
    } catch (e) {
      PerformanceMonitor.instance.err(t, e);
      completer.completeError(e);
      rethrow;
    } finally {
      _pending.remove(url);
    }
  }

  Future<Uint8List> _networkBytes(String url) async {
    final response = await _sharedDio.get<Uint8List>(url);
    if (response.statusCode != 200 || response.data == null) {
      throw HttpException('HTTP ${response.statusCode ?? 'null'} for $url');
    }
    return response.data!;
  }

  /// API متوافق مع النسخة السابقة: يعيد مسار ملف محلي
  /// (بعد التحميل عند الحاجة).
  Future<String> download(String url, {bool force = false}) async {
    await downloadToBytes(url, force: force);
    return pathFor(url);
  }

  Future<void> _storeBytes(String url, String key, Uint8List bytes) async {
    final dir = await cacheDirectory;
    final path = '${dir.path}/$key${_extensionFromUrl(url)}';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    _diskIndex[key] = _DiskEntry(key, path, bytes.length);
    _writeMemory(key, bytes);
    _markIndexDirty();
    await _enforceDiskCap();
  }

  Future<void> _enforceDiskCap() async {
    if (_diskIndex.length <= 1) return;
    var total = _diskIndex.values.fold<int>(0, (s, e) => s + e.size);
    if (total <= maxDiskBytes) return;
    final sorted = _diskIndex.values.toList()
      ..sort((a, b) => a.lastAccess.compareTo(b.lastAccess));
    for (final entry in sorted) {
      if (total <= maxDiskBytes) break;
      try {
        final file = File(entry.path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      _diskIndex.remove(entry.key);
      total -= entry.size;
    }
    _markIndexDirty();
  }

  // ── صيانة / تنظيف ─────────────────────────────────────────────

  /// يحذف نسخة [url] من RAM والقرص (وفهرس القرص) حتى يُعاد تحميلها لاحقاً.
  Future<void> evict(String url) async {
    if (!_isNetwork(url)) return;
    final key = _keyFor(url);
    final fromMemory = _memory.remove(key);
    if (fromMemory != null) _memoryBytes -= fromMemory.length;
    _pending.remove(url);
    final entry = _diskIndex.remove(key);
    if (entry != null) {
      try {
        final file = File(entry.path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      _markIndexDirty();
    }
  }

  /// (اختياري) يحذف ملفات قديمة داخل دليلنا غير مسجلة في الفهرس
  /// (من إصدارات سابقة / ملقّات قرص أخرى). لا يمسّ الملفات الحديثة
  /// حتى لا يقطع تشغيلاً قائماً.
  Future<void> sweepStaleFiles({Duration olderThan = const Duration(days: 7)}) async {
    try {
      final dir = await cacheDirectory;
      final cutoff = DateTime.now().subtract(olderThan);
      await for (final f in dir.list(recursive: true)) {
        if (f is! File) continue;
        if (f.path.endsWith('$_indexFileName')) continue;
        final key = _diskIndex.keys.cast<String?>().firstWhere(
              (k) => _diskIndex[k]!.path == f.path,
              orElse: () => null,
            );
        if (key != null) continue; // ملفنا المُدار → يخرج عبر LRU.
        try {
          final stat = await f.stat();
          if (stat.modified.isBefore(cutoff)) {
            await f.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// يحذف القرص وطبقة RAM بالكامل.
  Future<void> clearCache() async {
    try {
      final dir = await cacheDirectory;
      await dir.delete(recursive: true);
      _cacheDir = null;
      clearIndex();
    } catch (e) {
      debugPrint('MediaCacheService clear error: $e');
    }
  }

  /// إجمالي بايتات القرص (متوافق مع النسخة السابقة).
  Future<int> getCacheSize() => diskBytes;
}

/// HTTP download داخل Isolate عمّالي — لا يلمس أي كائن مشترك.
/// [`compute`] يتطلب دالة على مستوى ملف (top-level) أو static.
@pragma('vm:entry-point')
Future<Uint8List> _networkBytesIsolate(String url) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    responseType: ResponseType.bytes,
    validateStatus: (s) => s != null && s >= 200 && s < 300,
  ));
  try {
    final response = await dio.get<Uint8List>(url);
    if (response.statusCode != 200 || response.data == null) {
      throw HttpException('HTTP ${response.statusCode ?? 'null'} for $url');
    }
    return response.data!;
  } finally {
    dio.close(force: true);
  }
}