import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/r.dart';
import '../core/cache/encrypted_image_provider.dart';
import '../models/gift_model.dart';
import '../models/store_item_model.dart';
import '../screens/room/widgets/svga_player.dart';
import '../screens/room/widgets/vap_player.dart';
import 'dynamic_config_service.dart';
import 'media_cache_service.dart';
import 'supabase_data_service.dart';
import 'supabase_service.dart';

/// Pre-downloads gift icons + SVGA/VAP animations into their persistent
/// caches right after they arrive from the server, so playback is instant
/// and mobile data consumption drops on later sessions.
class MediaPrefetchService {
  MediaPrefetchService._();
  static final MediaPrefetchService _instance = MediaPrefetchService._();
  factory MediaPrefetchService() => _instance;

  static const int _maxConcurrent = 3;
  static const String _knownUrlsPrefsKey = 'media_asset_urls_v1';

  final Set<String> _handled = {};
  final Queue<String> _pending = Queue<String>();
  final List<Future<void>> _running = [];
  bool _warmedUp = false;

  /// Warms every remote asset (dashboard images, gifts, store items, SVGA/VAP)
  /// into the persistent caches at startup. When a remote URL changed since the
  /// previous run, the stale copy is evicted first so the fresh file is pulled.
  Future<void> warmup({bool force = false}) async {
    if (_warmedUp && !force) return;
    _warmedUp = true;
    try {
      final urls = <String>{};
      try {
        urls.addAll(DynamicConfigService().collectRemoteMediaUrls());
      } catch (_) {}
      try {
        final gifts = await SupabaseDataService().getGifts();
        for (final g in gifts) {
          _add(urls, g.iconAsset);
          _add(urls, g.animationAsset);
          _add(urls, g.defaultImage);
        }
      } catch (_) {}
      try {
        await SupabaseDataService().getGiftCategories();
      } catch (_) {}
      try {
        final items = await SupabaseService().getStoreItems();
        for (final it in items) {
          _add(urls, it.iconAsset);
          _add(urls, it.svgaAsset);
          _add(urls, it.videoAsset);
          _add(urls, it.defaultImage);
        }
      } catch (_) {}
      if (urls.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final previous = <String>{};
      final raw = prefs.getString(_knownUrlsPrefsKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            previous.addAll(decoded.map((e) => e.toString()));
          }
        } catch (_) {}
      }

      final changed = urls.difference(previous);
      final removed = previous.difference(urls);
      for (final url in changed) {
        await _evict(url);
      }
      for (final url in removed) {
        await _evict(url);
      }
      await prefs.setString(_knownUrlsPrefsKey, jsonEncode(urls.toList()));
      prefetchUrls(urls);
    } catch (e) {
      debugPrint('MediaPrefetchService warmup error: $e');
    }
  }

  void _add(Set<String> urls, String? value) {
    final v = value?.trim() ?? '';
    if (v.startsWith('http://') || v.startsWith('https://')) urls.add(v);
  }

  Future<void> _evict(String url) async {
    SvgaPlayer.evictMemory(url);
    try {
      await MediaCacheService().evict(url);
    } catch (_) {}
    try {
      await EncryptedImageProvider.evictCached(url);
    } catch (_) {}
  }

  /// Queues prefetch of every network asset referenced by [gifts]
  /// (icon image, SVGA/VAP animation, fallback image).
  void prefetchGifts(List<GiftModel> gifts) {
    for (final g in gifts) {
      prefetchUrls(<String>[g.iconAsset, g.animationAsset ?? '', g.defaultImage ?? '']);
    }
  }

  /// Queues prefetch of store items (frames, cars, bubbles, entrances).
  void prefetchStoreItems(Iterable<StoreItemModel> items) {
    for (final it in items) {
      prefetchUrls(<String>[
        it.iconAsset,
        it.svgaAsset ?? '',
        it.videoAsset ?? '',
        it.defaultImage ?? '',
      ]);
    }
  }

  /// Generic prefetch for CP gifts/cars/rewards maps that may use any of
  /// the common key names for image/SVGA/MP4 assets.
  void prefetchMaps(Iterable<Map<String, dynamic>> items) {
    for (final item in items) {
      final urls = <String>[
        if (item['icon'] is String) item['icon'] as String,
        if (item['icon_asset'] is String) item['icon_asset'] as String,
        if (item['icon_url'] is String) item['icon_url'] as String,
        if (item['image'] is String) item['image'] as String,
        if (item['svga_url'] is String) item['svga_url'] as String,
        if (item['svga'] is String) item['svga'] as String,
        if (item['animation_asset'] is String) item['animation_asset'] as String,
        if (item['mp4_url'] is String) item['mp4_url'] as String,
      ];
      prefetchUrls(urls);
    }
  }

  void prefetchUrls(Iterable<String> urls) {
    for (final raw in urls) {
      final url = raw.trim();
      if (url.isEmpty) continue;
      if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
      if (_handled.contains(url)) continue;
      _handled.add(url);
      _pending.add(url);
    }
    _tick();
  }

  void _tick() {
    while (_running.length < _maxConcurrent && _pending.isNotEmpty) {
      final url = _pending.removeFirst();
      _start(url);
    }
  }

  void _start(String url) {
    late final Future<void> future;
    future = _prefetchOne(url).whenComplete(() {
      _running.remove(future);
      _tick();
    });
    _running.add(future);
  }

  Future<void> _prefetchOne(String url) async {
    try {
      switch (detectAssetType(url)) {
        case AssetType.svga:
          await SvgaPlayer.prefetch(url);
        case AssetType.vap:
        case AssetType.mp4:
          await VapPlayer.prefetch(url);
        case AssetType.webp:
        case AssetType.gif:
        case AssetType.png:
        case AssetType.other:
          await EncryptedImageProvider.prefetch(url);
      }
    } catch (e) {
      debugPrint('MediaPrefetchService error ($url): $e');
    }
  }
}
