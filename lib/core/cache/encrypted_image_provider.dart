import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class EncryptedImageProvider extends ImageProvider<EncryptedImageProvider> {
  final String url;
  static const int _maxMemoryEntries = 200;
  static final Map<String, Uint8List> _memoryCache = {};
  static final List<String> _memoryCacheOrder = [];
  static final Map<String, Completer<Uint8List>> _pendingCompleters = {};
  static enc.Key? _aesKey;
  static Directory? _cacheDir;
  static Future<void>? _initFuture;

  const EncryptedImageProvider(this.url);

  static Future<void> _init() async {
    if (_initFuture != null) return _initFuture!;
    _initFuture = _doInit();
    return _initFuture!;
  }

  static Future<void> _doInit() async {
    final hash = sha256.convert(utf8.encode('enc_img_cache_default'));
    _aesKey = enc.Key(Uint8List.fromList(hash.bytes.sublist(0, 32)));
    final appDir = await getApplicationCacheDirectory();
    _cacheDir = Directory('${appDir.path}/.enc_img_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
  }

  String get _key => sha256.convert(utf8.encode(url)).toString();

  File get _encryptedFile => File('${_cacheDir!.path}/$_key.enc');

  static Uint8List _encryptBytes(Uint8List data) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(_aesKey!));
    final encrypted = encrypter.encryptBytes(data, iv: iv);
    final result = Uint8List(16 + encrypted.bytes.length);
    result.setRange(0, 16, iv.bytes);
    result.setRange(16, result.length, encrypted.bytes);
    return result;
  }

  static Uint8List? _decryptBytes(Uint8List data) {
    if (data.length < 16) return null;
    final iv = enc.IV(Uint8List.sublistView(data, 0, 16));
    final encryptedBytes = Uint8List.sublistView(data, 16);
    try {
      final encrypter = enc.Encrypter(enc.AES(_aesKey!));
      final encrypted = enc.Encrypted(encryptedBytes);
      final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
      return Uint8List.fromList(decrypted);
    } catch (_) {
      return null;
    }
  }

  static void _storeInMemory(String key, Uint8List bytes) {
    _memoryCache[key] = bytes;
    _memoryCacheOrder.add(key);
    if (_memoryCacheOrder.length > _maxMemoryEntries) {
      final removed = _memoryCacheOrder.removeAt(0);
      _memoryCache.remove(removed);
    }
  }

  Future<Uint8List> _fetchBytes() async {
    await _init();

    if (_memoryCache.containsKey(_key)) {
      return _memoryCache[_key]!;
    }

    if (await _encryptedFile.exists()) {
      try {
        final raw = await _encryptedFile.readAsBytes();
        final decrypted = _decryptBytes(Uint8List.fromList(raw));
        if (decrypted != null) {
          _storeInMemory(_key, decrypted);
          return decrypted;
        }
        await _encryptedFile.delete();
      } catch (_) {
        try { await _encryptedFile.delete(); } catch (_) {}
      }
    }

    final existing = _pendingCompleters[_key];
    if (existing != null) {
      return existing.future;
    }

    final completer = Completer<Uint8List>();
    _pendingCompleters[_key] = completer;

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        },
      );
      if (response.statusCode != 200) {
        throw HttpException('Failed to load $url: ${response.statusCode}');
      }
      final bytes = response.bodyBytes;
      final encrypted = _encryptBytes(Uint8List.fromList(bytes));
      await _encryptedFile.writeAsBytes(encrypted);

      final uint8Bytes = Uint8List.fromList(bytes);
      _storeInMemory(_key, uint8Bytes);
      completer.complete(uint8Bytes);
      return uint8Bytes;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _pendingCompleters.remove(_key);
    }
  }

  @override
  Future<EncryptedImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
      EncryptedImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<EncryptedImageProvider>('Image key', key),
      ],
    );
  }

  static final Uint8List _transparent1x1Png = Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
    0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5,
    0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130
  ]);

  Future<ui.Codec> _loadAsync(
      EncryptedImageProvider key, ImageDecoderCallback decode) async {
    final lower = key.url.toLowerCase();
    if (lower.contains('.mp4') || lower.contains('.svga') || lower.contains('assettype=vap') || lower.contains('assettype=svga')) {
      final transparentBuffer = await ui.ImmutableBuffer.fromUint8List(_transparent1x1Png);
      return await decode(transparentBuffer);
    }
    try {
      final bytes = await key._fetchBytes();
      if (bytes.isNotEmpty) {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        return await decode(buffer);
      }
    } catch (e) {
      debugPrint('EncryptedImageProvider error loading ${key.url}: $e');
      rethrow;
    }
    final transparentBuffer = await ui.ImmutableBuffer.fromUint8List(_transparent1x1Png);
    return await decode(transparentBuffer);
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is EncryptedImageProvider && other.url == url;
  }

  @override
  int get hashCode => Object.hash(runtimeType, url);

  @override
  String toString() => '$runtimeType($url)';

  /// Downloads and stores [url] into the disk + memory cache without decoding.
  /// Safe to call in background for pre-fetching gift icons / images.
  static Future<bool> prefetch(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) return false;
    try {
      final provider = EncryptedImageProvider(url);
      await provider._fetchBytes();
      return true;
    } catch (e) {
      debugPrint('EncryptedImageProvider prefetch error $url: $e');
      return false;
    }
  }

  static Future<void> clearMemoryCache() async {
    _memoryCache.clear();
    _memoryCacheOrder.clear();
  }

  static Future<void> clearDiskCache() async {
    await _init();
    if (_cacheDir != null && await _cacheDir!.exists()) {
      await _cacheDir!.delete(recursive: true);
      await _cacheDir!.create(recursive: true);
    }
    _memoryCache.clear();
    _memoryCacheOrder.clear();
  }
}
