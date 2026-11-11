import 'dart:async';

import 'package:flutter/material.dart';

import '../models/store_item_model.dart';
import 'dynamic_config_service.dart';
import 'supabase_data_service.dart';

/// لون/تدرج اسم الآيدي المميز. يمكن تعريفه من لوحة التحكم عبر
/// app_config.idColors = [{ id, name, colors: ['#RRGGBB', ...], animated }]
class IdColorPreset {
  final String id;
  final String name;
  final List<Color> colors;
  final bool animated;
  final bool isActive;

  const IdColorPreset({
    required this.id,
    required this.name,
    required this.colors,
    this.animated = true,
    this.isActive = true,
  });
}

/// سجل عام لكل الآيديهات المميزة المعرّفة في المتجر.
/// يسمح لأي ويدجت بمعرفة لون الاسم وملف SVGA الخاص بأي custom_id دون
/// الحاجة لعمل طلب شبكة في كل مرة.
class SpecialIdService extends ChangeNotifier {
  SpecialIdService._() {
    DynamicConfigService.instance.addListener(_onConfigChanged);
  }

  static final SpecialIdService instance = SpecialIdService._();

  final Map<String, StoreItemModel> _byCustomId = {};
  Timer? _pollTimer;
  bool _loading = false;
  bool _loadedOnce = false;
  String _signature = '';

  bool get isLoaded => _loadedOnce;

  static const List<IdColorPreset> _defaultPresets = [
    IdColorPreset(
      id: 'golden',
      name: 'ذهبي ملكي',
      colors: [
        Color(0xFFFFD700),
        Color(0xFFFFF8DC),
        Color(0xFFFFA500),
        Color(0xFFFFD700),
      ],
    ),
    IdColorPreset(
      id: 'rainbow',
      name: 'طيف متحرك',
      colors: [
        Color(0xFFFF0055),
        Color(0xFFFFAA00),
        Color(0xFF00FFCC),
        Color(0xFF0088FF),
        Color(0xFFFF00CC),
        Color(0xFFFF0055),
      ],
    ),
    IdColorPreset(
      id: 'neon',
      name: 'نيون سايبر',
      colors: [
        Color(0xFF00E5FF),
        Color(0xFF76FF03),
        Color(0xFF00E5FF),
      ],
    ),
    IdColorPreset(
      id: 'cyan',
      name: 'سماوي',
      colors: [
        Color(0xFF00E5FF),
        Color(0xFF76FF03),
        Color(0xFF00E5FF),
      ],
    ),
    IdColorPreset(
      id: 'fire',
      name: 'لهب متوهج',
      colors: [
        Color(0xFFFF1744),
        Color(0xFFFF9100),
        Color(0xFFFFEA00),
        Color(0xFFFF1744),
      ],
    ),
    IdColorPreset(
      id: 'purple',
      name: 'بنفسجي',
      colors: [
        Color(0xFF9C27B0),
        Color(0xFFE040FB),
        Color(0xFF7C4DFF),
        Color(0xFF9C27B0),
      ],
    ),
    IdColorPreset(
      id: 'ice',
      name: 'ثلجي',
      colors: [
        Color(0xFFE1F5FE),
        Color(0xFF81D4FA),
        Color(0xFF4FC3F7),
        Color(0xFFE1F5FE),
      ],
    ),
    IdColorPreset(
      id: 'emerald',
      name: 'زمردي',
      colors: [
        Color(0xFF00E676),
        Color(0xFFA7FFEB),
        Color(0xFF00BFA5),
        Color(0xFF00E676),
      ],
    ),
  ];

  List<IdColorPreset> get presets {
    final raw = DynamicConfigService.instance.idColors;
    if (raw.isEmpty) return _defaultPresets;
    final result = <IdColorPreset>[];
    for (final entry in raw) {
      final id = (entry['id'] ?? entry['key'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final colors = _parseColors(entry['colors']);
      if (colors.isEmpty) continue;
      result.add(IdColorPreset(
        id: id,
        name: (entry['name'] ?? id).toString(),
        colors: colors,
        animated: entry['animated'] != false,
        isActive: entry['isActive'] != false && entry['is_active'] != false,
      ));
    }
    return result.isEmpty ? _defaultPresets : result;
  }

  IdColorPreset presetFor(String? effectId) {
    final list = presets;
    final id = (effectId ?? '').trim();
    for (final p in list) {
      if (p.id == id) return p;
    }
    return list.first;
  }

  StoreItemModel? styleFor(String? customId) {
    final normalized = _normalize(customId);
    if (normalized == null) return null;
    // مطابقةexact فقط — إزالة الأصفار كانت تلوّن أسماء مستخدمين
    // عاديين صدفةً (مثلاً آيدي مميز '050' كان يلوّن كل مستخدم '50').
    return _byCustomId[normalized];
  }

  Future<void> ensureLoaded() async {
    if (_loading) return;
    if (!_loadedOnce) {
      await refresh();
      _pollTimer ??= Timer.periodic(const Duration(seconds: 60), (_) {
        refresh();
      });
    }
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final items = await SupabaseDataService().getSpecialIdItems();
      final map = <String, StoreItemModel>{};
      final signature = StringBuffer();
      for (final item in items) {
        if (item.category.toLowerCase() != 'special_id') continue;
        final cid = _normalize(item.effectiveCustomId);
        if (cid == null) continue;
        map[cid] = item;
        signature
          ..write(cid)
          ..write('|')
          ..write(item.effectiveColorEffect)
          ..write('|')
          ..write(item.svgaAsset)
          ..write('|')
          ..write(item.svgaTextKey)
          ..write(';');
      }
      _byCustomId
        ..clear()
        ..addAll(map);
      _loadedOnce = true;
      final newSignature = signature.toString();
      if (newSignature != _signature) {
        _signature = newSignature;
        notifyListeners();
      }
    } catch (_) {
      // الشبكة قد تكون غير متاحة — نُبقي آخر بيانات معروفة.
    } finally {
      _loading = false;
    }
  }

  void _onConfigChanged() => notifyListeners();

  @override
  void dispose() {
    DynamicConfigService.instance.removeListener(_onConfigChanged);
    _pollTimer?.cancel();
    super.dispose();
  }

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
      return null;
    }
    return trimmed;
  }

  static List<Color> _parseColors(dynamic raw) {
    if (raw is! List) return const [];
    final colors = <Color>[];
    for (final entry in raw) {
      final color = _parseColor(entry);
      if (color != null) colors.add(color);
    }
    if (colors.length == 1) colors.add(colors.first);
    return colors;
  }

  static Color? _parseColor(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    var hex = text.replaceFirst('#', '');
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}
