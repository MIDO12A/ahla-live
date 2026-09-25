import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';

class LevelConfig {
  final int level;
  final int minExp;
  final int maxExp;
  final String title;
  final String type;
  final String? imageUrl;
  final String? frameUrl;
  final String? badgeUrl;
  final Map<String, dynamic> rewards;
  final String? progressColor;
  final String? boxImageUrl;

  const LevelConfig({
    required this.level,
    required this.minExp,
    required this.maxExp,
    required this.title,
    this.type = 'wealth',
    this.imageUrl,
    this.frameUrl,
    this.badgeUrl,
    this.rewards = const {},
    this.progressColor,
    this.boxImageUrl,
  });

  factory LevelConfig.fromMap(Map<String, dynamic> map) => LevelConfig(
        level: (map['level'] ?? 1).toInt(),
        minExp: (map['min_exp'] ?? 0).toInt(),
        maxExp: (map['max_exp'] ?? 1000).toInt(),
        title: map['title']?.toString() ?? 'Level ${map['level']}',
        type: map['type']?.toString() ?? 'wealth',
        imageUrl: map['image_url']?.toString(),
        frameUrl: map['frame_url']?.toString(),
        badgeUrl: map['badge_url']?.toString(),
        rewards: map['rewards'] is Map ? Map<String, dynamic>.from(map['rewards']) : {},
        progressColor: map['progress_color']?.toString(),
        boxImageUrl: map['box_image_url']?.toString(),
      );
}

class LevelService extends ChangeNotifier {
  static final LevelService _instance = LevelService._();
  factory LevelService() => _instance;
  LevelService._();

  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'default',
  );
  final SupabaseService _supabaseService = SupabaseService();
  final List<StreamSubscription> _subs = [];
  bool _initialized = false;

  final Map<String, List<LevelConfig>> _cachedLevels = {};
  Map<String, List<LevelConfig>> get cachedLevels => _cachedLevels;

  void init() {
    if (_initialized) return;
    _initialized = true;
    for (final type in ['wealth', 'recharge', 'gems']) {
      final sub = _db.collection('level_config').where('type', isEqualTo: type).snapshots().map((snap) {
        final configs = snap.docs.map((e) => LevelConfig.fromMap(_data(e))).toList();
        configs.sort((a, b) => a.level.compareTo(b.level));
        _cachedLevels[type] = configs;
        notifyListeners();
        return configs;
      }).listen((_) {}, onError: (e) {
        debugPrint('LevelService: level_config stream error for $type: $e');
      });
      _subs.add(sub);
    }
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    super.dispose();
  }

  Stream<List<LevelConfig>> levelsStream(String type) {
    return _db.collection('level_config').where('type', isEqualTo: type).snapshots().map((snap) {
      final configs = snap.docs.map((e) => LevelConfig.fromMap(_data(e))).toList();
      configs.sort((a, b) => a.level.compareTo(b.level));
      _cachedLevels[type] = configs;
      return configs;
    }).asBroadcastStream();
  }

  Future<void> loadAllLevels() async {
    init();
    final res = await _db.collection('level_config').get();
    for (final type in ['wealth', 'recharge', 'gems']) {
      final list = res.docs
          .map((e) => LevelConfig.fromMap(_data(e)))
          .where((e) => e.type == type)
          .toList();
      list.sort((a, b) => a.level.compareTo(b.level));
      _cachedLevels[type] = list;
    }
  }

  Map<String, dynamic> _data(DocumentSnapshot<Map<String, dynamic>> snap) =>
      snap.data() ?? {};

  LevelConfig? getLevelConfig(String type, int level) {
    final list = _cachedLevels[type];
    if (list == null) return null;
    try {
      return list.firstWhere((l) => l.level == level);
    } catch (_) {
      return null;
    }
  }

  int getMaxLevel(String type) {
    final list = _cachedLevels[type];
    if (list == null || list.isEmpty) return 1;
    return list.last.level;
  }

  Future<LevelUpResult?> addExp({
    required String uid,
    required String type,
    required int amount,
  }) async {
    if (amount <= 0) return null;

    final userSnap = await _supabaseService.getUser(uid);
    if (userSnap == null) return null;

    final user = userSnap;
    final expField = '${type}_exp';
    final levelField = '${type}_level';

    int currentLevel;
    int currentExp;

    switch (type) {
      case 'wealth':
        currentLevel = user.wealthLevel;
        currentExp = user.wealthExp;
        break;
      case 'recharge':
        currentLevel = user.rechargeLevel;
        currentExp = user.rechargeExp;
        break;
      case 'gems':
        currentLevel = user.gemsLevel;
        currentExp = user.gemsExp;
        break;
      default:
        return null;
    }

    currentExp += amount;
    int totalCoins = 0;
    int totalDiamonds = 0;
    final List<String> newFrames = [];
    final List<String> newBadges = [];

    while (true) {
      final config = getLevelConfig(type, currentLevel);
      if (config == null) break;
      if (currentExp >= config.maxExp) {
        currentExp -= config.maxExp;
        currentLevel++;
        final r = config.rewards;
        if (r['coins'] != null) totalCoins += (r['coins'] as num).toInt();
        if (r['diamonds'] != null) totalDiamonds += (r['diamonds'] as num).toInt();
        if (config.frameUrl != null) newFrames.add(config.frameUrl!);
        if (config.badgeUrl != null) newBadges.add(config.badgeUrl!);
        if (currentLevel > getMaxLevel(type)) break;
      } else {
        break;
      }
    }

    final updates = <String, dynamic>{
      expField: currentExp,
      levelField: currentLevel,
    };

    final allFrames = [...user.ownedLevelFrames, ...newFrames];
    final allBadges = [...user.ownedLevelBadges, ...newBadges];
    updates['owned_level_frames'] = allFrames;
    updates['owned_level_badges'] = allBadges;
    // Auto-equip the highest level frame as activeFrame
    if (newFrames.isNotEmpty) {
      updates['active_frame'] = newFrames.last;
    }

    if (totalCoins > 0) {
      updates['coins'] = user.coins + totalCoins;
    }
    if (totalDiamonds > 0) {
      updates['diamonds'] = user.diamonds + totalDiamonds;
    }

    await _supabaseService.updateUser(uid, updates);

    return LevelUpResult(
      type: type,
      oldLevel: currentLevel - newFrames.length,
      newLevel: currentLevel,
      rewardCoins: totalCoins,
      rewardDiamonds: totalDiamonds,
      newFrames: newFrames,
      newBadges: newBadges,
    );
  }
}

class LevelUpResult {
  final String type;
  final int oldLevel;
  final int newLevel;
  final int rewardCoins;
  final int rewardDiamonds;
  final List<String> newFrames;
  final List<String> newBadges;

  const LevelUpResult({
    required this.type,
    required this.oldLevel,
    required this.newLevel,
    this.rewardCoins = 0,
    this.rewardDiamonds = 0,
    this.newFrames = const [],
    this.newBadges = const [],
  });

  bool get didLevelUp => newLevel > oldLevel;
}
