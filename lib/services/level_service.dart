import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';
import 'supabase_data_service.dart';
import 'supabase_realtime_service.dart';

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

  final SupabaseService _supabaseService = SupabaseService();
  bool _initialized = false;

  final Map<String, List<LevelConfig>> _cachedLevels = {};
  Map<String, List<LevelConfig>> get cachedLevels => _cachedLevels;

  /// آخر جلب ناجح من جدول level_config — تُستخدم لتحديث الصور تلقائياً
  /// عند فتح أي شاشة تعرض مستويات دون الحاجة لشاشة المستويات.
  DateTime? _lastLoadedAt;
  DateTime? _lastAttemptAt;
  Future<void>? _loadInFlight;
  bool _realtimeHooked = false;

  /// مدة اعتبار الكاش «طازجاً» — بعدها يعيد أي استدعاء ensureLoaded
  /// الجلب من لوحة التحكم في الخلفية.
  static const Duration _freshFor = Duration(seconds: 90);

  /// أدنى فاصل بين محاولتين فاشلتين حتى لا تتكرر الطلبات مع كل rebuild.
  static const Duration _retryAfter = Duration(seconds: 10);

  void init() {
    if (_initialized) return;
    _initialized = true;
    unawaited(loadAllLevels());
    _hookRealtime();
  }

  /// أي تعديل على level_config من لوحة التحكم يُحدّث الكاش فوراً
  /// ويُعلِم كل الشاشات المشتركة (ListenableBuilder) لإعادة البناء.
  void _hookRealtime() {
    if (_realtimeHooked) return;
    _realtimeHooked = true;
    final rt = SupabaseRealtimeService.instance;
    rt.subscribeTable(
      table: 'level_config',
      topic: 'level_config:all',
      events: const ['INSERT', 'UPDATE', 'DELETE'],
    );
    rt.changes.listen((change) {
      if (change.table == 'level_config') {
        unawaited(loadAllLevels());
      }
    });
  }


  Stream<List<LevelConfig>> levelsStream(String type) async* {
    if (_cachedLevels[type] != null && _cachedLevels[type]!.isNotEmpty) {
      yield _cachedLevels[type]!;
    }
    try {
      final sbConfigs = await SupabaseDataService().getLevelConfigs(type: type);
      if (sbConfigs.isNotEmpty) {
        final configs = sbConfigs.map((e) => LevelConfig.fromMap(e)).toList();
        configs.sort((a, b) => a.level.compareTo(b.level));
        _cachedLevels[type] = configs;
        yield configs;
      }
    } catch (_) {}
  }

  /// يطلب واحداً فقط في كل مرة — النداءات المتزامنة من شاشات متعددة
  /// (البروفايل، بروفايل المستخدم، ترتيب الغرفة…) تتشارك نفس الجلب.
  Future<void> loadAllLevels() {
    return _loadInFlight ??=
        _fetchAllLevels().whenComplete(() => _loadInFlight = null);
  }

  Future<void> _fetchAllLevels() async {
    try {
      final configs = await SupabaseDataService().getLevelConfigs();
      // لا نُسجّل وقت «التحميل» إلا عند وجود بيانات فعلية — النتيجة
      // الفارغة قد تعني فشل الشبكة أو أن اللوحة لم تُضِف مستويات بعد،
      // وعندها يُسمح لإعادة المحاولة بعد [_retryAfter] بدل انتظار
      // دورة [_freshFor] كاملة.
      if (configs.isEmpty) return;
      _lastLoadedAt = DateTime.now();
      var changed = false;
      for (final type in ['wealth', 'recharge', 'gems']) {
        final list = configs
            .map((e) => LevelConfig.fromMap(e))
            .where((e) => e.type == type)
            .toList();
        list.sort((a, b) => a.level.compareTo(b.level));
        if (list.isNotEmpty) {
          _cachedLevels[type] = list;
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } catch (_) {}
  }

  /// يعيد تحميل المستويات من لوحة التحكم عند الحاجة:
  /// - [force]: تجاهل الكاش تماماً.
  /// - تلقائياً: إن كان الكاش فارغاً/أقدم من [_freshFor] أو فشلت آخر
  ///   محاولة منذ أقل من [_retryAfter].
  /// تستدعيه أي شاشة تعرض صور/بيانات المستويات — لا حاجة لفتح
  /// شاشة المستويات أولاً.
  Future<void> ensureLoaded({bool force = false}) async {
    if (!force) {
      final inFlight = _loadInFlight;
      if (inFlight != null) return inFlight;
      final now = DateTime.now();
      final fresh = _lastLoadedAt != null &&
          now.difference(_lastLoadedAt!) < _freshFor;
      if (fresh) return;
      final lastAttempt = _lastAttemptAt;
      if (lastAttempt != null &&
          now.difference(lastAttempt) < _retryAfter) {
        return;
      }
    }
    _lastAttemptAt = DateTime.now();
    return loadAllLevels();
  }

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

  /// يحمّل مستويات كل الأنواع إن لم تكن محمّلة بعد.
  /// تستدعيه الشاشات التي تعرض المستويات حتى تظهر الصور مباشرةً
  /// دون الحاجة لفتح شاشة المستويات أولاً.
  /// (مُستبدَلة بـ [ensureLoaded] التي تدعم التحديث التلقائي —
  ///   تُبقي للتوافق مع الاستدعاءات القديمة.)
  @Deprecated('Use ensureLoaded() which refreshes stale cache')
  Future<void> ensureLevelsLoaded() => ensureLoaded();

  /// يعيد إعداد المستوى الفعلي، وإن لم يوجد للمستوى المطلوب يعود
  /// لأقرب مستوى أدنى متاح (حتى لا تبقى الشاشة بلا بيانات).
  LevelConfig? configFor(String type, int level) {
    final exact = getLevelConfig(type, level);
    if (exact != null) return exact;
    final list = _cachedLevels[type];
    if (list == null || list.isEmpty) return null;
    LevelConfig? best;
    for (final c in list) {
      if (c.level > level) break;
      best = c;
    }
    return best;
  }

  /// صورة المستوى (الأيقونة الكبيرة). إن لم يملك المستوى المطلوب صورة
  /// يعود لأقرب مستوى أدنى يملك صورة — بدل إظهار أيقونة بديلة عامة.
  String? imageUrlFor(String type, int level) {
    final exact = getLevelConfig(type, level);
    if (exact?.imageUrl?.isNotEmpty == true) return exact!.imageUrl;
    final list = _cachedLevels[type];
    if (list == null || list.isEmpty) return null;
    String? best;
    for (final c in list) {
      if (c.level > level) break;
      if (c.imageUrl?.isNotEmpty == true) best = c.imageUrl;
    }
    return best;
  }

  /// شارة المستوى (الأيقونة الصغيرة) بنفس منطق الرجوع للمستوى الأدنى.
  String? badgeUrlFor(String type, int level) {
    final exact = getLevelConfig(type, level);
    if (exact?.badgeUrl?.isNotEmpty == true) return exact!.badgeUrl;
    final list = _cachedLevels[type];
    if (list == null || list.isEmpty) return null;
    String? best;
    for (final c in list) {
      if (c.level > level) break;
      if (c.badgeUrl?.isNotEmpty == true) best = c.badgeUrl;
    }
    return best;
  }

  /// أفضل تمثيل بصري للمستوى: الصورة الكبيرة أولاً ثم الشارة.
  String? visualFor(String type, int level) =>
      imageUrlFor(type, level) ?? badgeUrlFor(type, level);

  Future<LevelUpResult?> addExp({
    required String uid,
    required String type,
    required int amount,
  }) async {
    if (amount <= 0) return null;

    // ✅ المسار الذرّي: add_user_exp على السيرفر — يحسب الصعود
    //    والمكافآت في transaction واحد ويعمل لأي uid (مرسل/مستلم)
    //    بدون race. عند غياب الدالة نكمل بالمسار القديم.
    try {
      final rpc = await SupabaseDataService()
          .addUserExp(uid, type, amount)
          .timeout(const Duration(seconds: 8));
      if (rpc != null && rpc['status'] == 'ok') {
        final oldLevel = (rpc['old_level'] as num?)?.toInt() ?? 1;
        final newLevel = (rpc['new_level'] as num?)?.toInt() ?? oldLevel;
        return LevelUpResult(
          type: type,
          oldLevel: oldLevel,
          newLevel: newLevel,
          rewardCoins: (rpc['reward_coins'] as num?)?.toInt() ?? 0,
          rewardDiamonds: (rpc['reward_diamonds'] as num?)?.toInt() ?? 0,
          newFrames: (rpc['new_frames'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
          newBadges: (rpc['new_badges'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
        );
      }
    } catch (_) {}

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

    await _supabaseService.updateUser(uid, updates);

    // مكافآت المستوى تُضاف عبر طابور الرصيد المتسلسل حتى لا تطمس خصم هدية
    // حدث في نفس اللحظة (كانت الكتابة بالقيمة القديمة تُرجع الكوينز المخصومة).
    if (totalCoins > 0 || totalDiamonds > 0) {
      await _supabaseService.adjustUserBalance(
        uid,
        coinsDelta: totalCoins,
        diamondsDelta: totalDiamonds,
      );
    }

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
