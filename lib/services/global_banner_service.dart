import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/gift_banner_config_model.dart';
import 'supabase_service.dart';
import 'supabase_data_service.dart';

/// أنواع لافتات الهدايا المدعومة في الطابور الموحد
enum GlobalBannerType {
  bigWin,      // فوز الحظ الكبرى
  giftBanner,  // لافتة الهدية المخصصة SVGA / VAP
  marquee,     // شريط الإعلان الماركي لجميع الغرف
}

/// عنصر البانر في الطابور الموحد
class QueuedBannerItem {
  final String id;
  final GlobalBannerType type;
  final Map<String, dynamic> data;
  final Duration duration;

  QueuedBannerItem({
    required this.id,
    required this.type,
    required this.data,
    this.duration = const Duration(milliseconds: 5200),
  });
}

/// خدمة إدارة لافتات الهدايا وبانرات فوز الحظ على مستوى التطبيق بالكامل (GlobalBannerService)
/// تضمن نظام طابور متتابع (FIFO) يعرض البانرات واحداً تلو الآخر بانتظام من اليمين إلى اليسار
/// دون أي تكرار أو تداخل أو تراكم فوق بعضها.
class GlobalBannerService extends ChangeNotifier {
  static final GlobalBannerService instance = GlobalBannerService._();
  GlobalBannerService._();

  List<GiftBannerConfig> _bannerConfigs = [];
  List<GiftBannerConfig> get bannerConfigs => _bannerConfigs;

  // ── طابور البانرات الموحد والبانر النشط حالياً ─────────────────
  QueuedBannerItem? currentBanner;
  final List<QueuedBannerItem> _queue = [];
  bool _isPlaying = false;
  Timer? _currentBannerTimer;

  // لمنع تكرار نفس البانر أو إعادة تشغيله
  final Set<String> _seenBroadcastIds = <String>{};
  final Set<String> _seenFingerprints = <String>{};
  final int _sessionStartTime = DateTime.now().millisecondsSinceEpoch;

  // الحقول المتوافقة مع الكود القديم
  Map<String, dynamic>? get activeGiftBanner =>
      currentBanner?.type == GlobalBannerType.giftBanner ? currentBanner?.data : null;

  Map<String, dynamic>? get activeBigWin =>
      currentBanner?.type == GlobalBannerType.bigWin ? currentBanner?.data : null;

  Map<String, dynamic>? get activeMarquee =>
      currentBanner?.type == GlobalBannerType.marquee ? currentBanner?.data : null;

  StreamSubscription? _broadcastSub;
  StreamSubscription? _bannerConfigSub;
  StreamSubscription? _bigWinSub;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    // 1. تحميل إعدادات لافتات الهدايا من Supabase و Firestore
    SupabaseDataService().getGiftBannerConfigs().then((configs) {
      if (configs.isNotEmpty) {
        _bannerConfigs = configs.where((c) => c.isActive).toList();
        notifyListeners();
      }
    }).catchError((_) {});

    _bannerConfigSub?.cancel();
    _bannerConfigSub = FirebaseService().giftBannerConfigsStream().listen((configs) {
      _bannerConfigs = configs.where((c) => c.isActive).toList();
      notifyListeners();
    }, onError: (_) {});

    // 2. الاستماع للبث العام (الهدايا الكبيرة وهدايا الحظ)
    _broadcastSub?.cancel();
    _broadcastSub = FirebaseService().globalBroadcastStream().listen((broadcasts) {
      _handleIncomingBroadcasts(broadcasts);
    }, onError: (e) {
      debugPrint('[GlobalBannerService] broadcast stream error: $e');
    });

    // 3. الاستماع لبث فوز الحظ الأسطوري
    _bigWinSub?.cancel();
    _bigWinSub = FirebaseService().globalBigWinStream().listen((winData) {
      _handleIncomingBigWin(winData);
    }, onError: (_) {});
  }

  void _handleIncomingBroadcasts(List<Map<String, dynamic>> broadcasts) {
    if (broadcasts.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    for (final b in broadcasts) {
      final bTs = (b['timestamp'] as num?)?.toInt() ??
          (DateTime.tryParse(b['created_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0);
      // تجاهل أي بث تم إنشاؤه قبل فتح التطبيق أو قديم جداً
      if (bTs == 0 || bTs < _sessionStartTime - 10000) continue;
      final isFresh = (nowMs - bTs).abs() < 60000;
      if (!isFresh) continue;

      final bId = b['id']?.toString() ?? '${bTs}_${b['sender_uid']}_${b['gift_name']}';
      if (_seenBroadcastIds.contains(bId)) continue;
      _seenBroadcastIds.add(bId);

      final isLuckyBag = b['type'] == 'lucky_bag' || b['is_lucky_bag'] == true;
      if (isLuckyBag) {
        triggerLuckyBagBanner(b);
        continue;
      }

      final isLucky = b['is_lucky'] == true || b['type'] == 'lucky_gift';
      final multiplier = (b['multiplier'] as num?)?.toInt() ?? 0;

      // ── أولوية العرض الذكية لمنع التكرار والتراكم ──
      // 1. إذا كان فوز حظ كبير (50X فما فوق أو 100X) -> نظهر بانر الفوز الأسطوري فقط
      if (isLucky && (multiplier >= 50 || b['is_big_win'] == true)) {
        showBigWin({
          'id': bId,
          'senderName': b['sender_name']?.toString() ?? 'مستخدم',
          'senderAvatar': b['sender_photo_url']?.toString() ?? '',
          'giftName': b['gift_name']?.toString() ?? '',
          'multiplier': multiplier > 0 ? multiplier : 100,
          'totalWon': (b['won_coins'] as num?)?.toInt() ?? (b['coins'] as num?)?.toInt() ?? 0,
        });
      } else {
        // 2. فحص لافتة الهدية المخصصة SVGA (Gift Banner Config)
        final totalCost = (b['total_cost'] as num?)?.toInt() ??
            (((b['value'] as num?)?.toInt() ?? 0) * ((b['count'] as num?)?.toInt() ?? 1));
        final categoryId = b['category_id']?.toString();
        final giftCount = (b['count'] as num?)?.toInt() ?? 1;

        GiftBannerConfig? matchingConfig = _findMatchingConfig(
          totalCost: totalCost,
          categoryId: categoryId,
        );

        if (matchingConfig != null) {
          showGiftBanner({
            'id': bId,
            'animationAsset': matchingConfig.svgaUrl,
            'senderPhotoUrl': b['sender_photo_url']?.toString(),
            'receiverPhotoUrl': b['receiver_photo_url']?.toString(),
            'defaultImage': b['default_image']?.toString() ?? b['gift_icon']?.toString(),
            'giftCount': giftCount,
            'userRKey': matchingConfig.userRKey,
            'userLKey': matchingConfig.userLKey,
            'numberKey': matchingConfig.numberKey,
            'giftKey': matchingConfig.giftKey,
          });
        } else {
          // 3. شريط إعلان ماركي عام للغرف
          showMarquee(b);
        }
      }
    }
  }

  void _handleIncomingBigWin(Map<String, dynamic> winData) {
    final winTs = (winData['timestamp'] as num?)?.toInt() ??
        (DateTime.tryParse(winData['created_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0);
    if (winTs != 0 && winTs < _sessionStartTime - 10000) return;
    final mult = (winData['multiplier'] as num?)?.toInt() ?? 0;
    if (mult < 50) return;

    final winId = winData['id']?.toString() ?? '${winTs}_${winData['sender_name']}_$mult';
    if (_seenBroadcastIds.contains(winId)) return;
    _seenBroadcastIds.add(winId);

    showBigWin({
      'id': winId,
      'senderName': winData['sender_name']?.toString() ?? '',
      'senderAvatar': winData['sender_avatar']?.toString() ?? '',
      'giftName': winData['gift_name']?.toString() ?? '',
      'multiplier': mult,
      'totalWon': (winData['total_won'] as num?)?.toInt() ?? 0,
    });
  }

  GiftBannerConfig? _findMatchingConfig({required int totalCost, String? categoryId}) {
    if (_bannerConfigs.isEmpty) return null;

    // 1. مطابقة التصنيف بدقة مع تجاوز الحد الأدنى
    if (categoryId != null && categoryId.isNotEmpty) {
      final catMatch = _bannerConfigs
          .where((c) => c.isActive && c.categoryId == categoryId && totalCost >= c.thresholdCoins)
          .firstOrNull;
      if (catMatch != null) return catMatch;
    }

    // 2. مطابقة إعداد عام (بدون تصنيف محدد أو فارغ)
    final globalMatch = _bannerConfigs
        .where((c) => c.isActive && (c.categoryId == null || c.categoryId!.isEmpty) && totalCost >= c.thresholdCoins)
        .firstOrNull;
    if (globalMatch != null) return globalMatch;

    // 3. أي إعداد نشط تجاوز حده الأدنى
    return _bannerConfigs
        .where((c) => c.isActive && totalCost >= c.thresholdCoins)
        .firstOrNull;
  }

  // ── إدارة الطابور المتتابع (Unified Sequential FIFO Queue) ────────

  String _buildFingerprint(GlobalBannerType type, Map<String, dynamic> data) {
    if (data['id'] != null && data['id'].toString().isNotEmpty) {
      return '${type.name}_${data['id']}';
    }
    final sender = (data['sender_name'] ?? data['senderName'] ?? data['sender_uid'] ?? '').toString();
    final receiver = (data['receiver_name'] ?? data['receiverPhotoUrl'] ?? '').toString();
    final gift = (data['gift_name'] ?? data['giftName'] ?? data['animationAsset'] ?? '').toString();
    final mult = (data['multiplier'] ?? 0).toString();
    final cost = (data['total_cost'] ?? data['totalWon'] ?? data['won_coins'] ?? data['coins'] ?? 0).toString();
    final timeBucket = DateTime.now().millisecondsSinceEpoch ~/ 4000;
    return '${type.name}_${sender}_${receiver}_${gift}_${mult}_${cost}_$timeBucket';
  }

  void _enqueue(QueuedBannerItem item) {
    final fp = _buildFingerprint(item.type, item.data);

    // منع التكرار الصارم
    if (_seenFingerprints.contains(fp) || _seenFingerprints.contains(item.id)) {
      return;
    }
    if (_queue.any((q) => q.id == item.id || _buildFingerprint(q.type, q.data) == fp)) {
      return;
    }
    if (currentBanner != null && (currentBanner!.id == item.id || _buildFingerprint(currentBanner!.type, currentBanner!.data) == fp)) {
      return;
    }

    _seenFingerprints.add(fp);
    _seenFingerprints.add(item.id);
    if (_seenFingerprints.length > 500) {
      _seenFingerprints.remove(_seenFingerprints.first);
    }

    _queue.add(item);
    if (!_isPlaying) {
      _playNext();
    }
  }

  void _playNext() {
    if (_queue.isEmpty) {
      currentBanner = null;
      _isPlaying = false;
      notifyListeners();
      return;
    }

    _isPlaying = true;
    currentBanner = _queue.removeAt(0);
    notifyListeners();

    _currentBannerTimer?.cancel();
    _currentBannerTimer = Timer(currentBanner!.duration, () {
      nextBanner();
    });
  }

  /// الانتقال إلى البانر التالي في الطابور بعد إتمام الحركة
  void nextBanner() {
    _currentBannerTimer?.cancel();
    currentBanner = null;
    notifyListeners();

    // فاصل زمني بسيط (350ms) لإتمام خروج البانر نحو اليسار قبل دخول البانر الجديد من اليمين
    Future.delayed(const Duration(milliseconds: 350), () {
      _playNext();
    });
  }

  void dismissCurrentBanner() => nextBanner();
  void dismissGiftBanner() => nextBanner();
  void dismissBigWin() => nextBanner();
  void dismissMarquee() => nextBanner();

  /// إظهار لافتة الهدية SVGA في الطابور
  void showGiftBanner(Map<String, dynamic> data) {
    final id = data['id']?.toString() ?? '${DateTime.now().millisecondsSinceEpoch}_gift';
    _enqueue(QueuedBannerItem(
      id: id,
      type: GlobalBannerType.giftBanner,
      data: data,
      duration: const Duration(milliseconds: 5500),
    ));
  }

  /// إظهار بانر فوز الحظ الأسطوري في الطابور
  void showBigWin(Map<String, dynamic> data) {
    final id = data['id']?.toString() ?? '${DateTime.now().millisecondsSinceEpoch}_bigwin';
    _enqueue(QueuedBannerItem(
      id: id,
      type: GlobalBannerType.bigWin,
      data: data,
      duration: const Duration(milliseconds: 4800),
    ));
  }

  /// إظهار شريط الإعلان الماركي في الطابور
  void showMarquee(Map<String, dynamic> data) {
    final id = data['id']?.toString() ?? '${DateTime.now().millisecondsSinceEpoch}_marquee';
    _enqueue(QueuedBannerItem(
      id: id,
      type: GlobalBannerType.marquee,
      data: data,
      duration: const Duration(milliseconds: 5000),
    ));
  }

  /// تفعيل محلي فوري عند الإرسال من قبل المستخدم
  void triggerGiftBannerLocally(Map<String, dynamic> data) {
    final giftValue = (data['giftValue'] as num?)?.toInt() ?? 0;
    final giftCount = (data['giftCount'] as num?)?.toInt() ?? 1;
    final categoryId = data['categoryId']?.toString();
    final totalCost = giftValue * giftCount;

    GiftBannerConfig? config = _findMatchingConfig(totalCost: totalCost, categoryId: categoryId);
    if (config != null) {
      showGiftBanner({
        'animationAsset': config.svgaUrl,
        'senderPhotoUrl': data['senderPhotoUrl']?.toString(),
        'receiverPhotoUrl': data['receiverPhotoUrl']?.toString(),
        'defaultImage': data['defaultImage']?.toString(),
        'giftCount': giftCount,
        'userRKey': config.userRKey,
        'userLKey': config.userLKey,
        'numberKey': config.numberKey,
        'giftKey': config.giftKey,
      });
    } else if (totalCost >= 500) {
      showGiftBanner({
        'animationAsset': 'assets/svga/gift_banner_strip.svga',
        'senderPhotoUrl': data['senderPhotoUrl']?.toString(),
        'receiverPhotoUrl': data['receiverPhotoUrl']?.toString(),
        'defaultImage': data['defaultImage']?.toString(),
        'giftCount': giftCount,
        'userRKey': 'user_r',
        'userLKey': 'user_l',
        'numberKey': 'number',
        'giftKey': 'gift',
      });
    }
  }

  /// إظهار لافتة حقيبة الحظ في جميع الغرف والشاشات وفق إعدادات لافتات الهدايا
  void triggerLuckyBagBanner(Map<String, dynamic> bagData) {
    final totalCoins = (bagData['total_value'] as num?)?.toInt() ??
        (bagData['totalCoins'] as num?)?.toInt() ??
        (bagData['total_cost'] as num?)?.toInt() ??
        (((bagData['value'] as num?)?.toInt() ?? 0) * ((bagData['total_bags'] as num?)?.toInt() ?? (bagData['count'] as num?)?.toInt() ?? 1));

    GiftBannerConfig? luckyBagConfig = _bannerConfigs
        .where((c) => c.isActive && c.categoryId == 'lucky_bag' && totalCoins >= c.thresholdCoins)
        .firstOrNull;

    luckyBagConfig ??= _bannerConfigs
        .where((c) => c.isActive && (c.categoryId == null || c.categoryId!.isEmpty) && totalCoins >= c.thresholdCoins)
        .firstOrNull;

    if (luckyBagConfig != null) {
      showGiftBanner({
        'animationAsset': luckyBagConfig.svgaUrl,
        'senderPhotoUrl': bagData['owner_photo']?.toString() ?? bagData['ownerAvatar']?.toString() ?? bagData['sender_photo_url']?.toString(),
        'receiverPhotoUrl': bagData['room_photo_url']?.toString() ?? '',
        'defaultImage': 'assets/images/ic_luckybag.png',
        'giftCount': (bagData['total_bags'] as num?)?.toInt() ?? (bagData['count'] as num?)?.toInt() ?? 1,
        'userRKey': luckyBagConfig.userRKey,
        'userLKey': luckyBagConfig.userLKey,
        'numberKey': luckyBagConfig.numberKey,
        'giftKey': luckyBagConfig.giftKey,
        'isLuckyBag': true,
        'roomName': bagData['room_name']?.toString() ?? '',
        'roomId': bagData['room_id']?.toString() ?? bagData['roomId']?.toString(),
      });
    } else {
      showMarquee({
        'type': 'lucky_bag',
        'sender_name': bagData['owner_name'] ?? bagData['ownerName'] ?? bagData['sender_name'] ?? 'مستخدم',
        'sender_photo_url': bagData['owner_photo'] ?? bagData['ownerAvatar'] ?? bagData['sender_photo_url'] ?? '',
        'gift_name': 'حقيبة الحظ 🧧',
        'total_cost': totalCoins,
        'text': '🧧 أطلق حقيبة حظ بقيمة $totalCoins 🪙!',
      });
    }
  }

  @override
  void dispose() {
    _currentBannerTimer?.cancel();
    _broadcastSub?.cancel();
    _bannerConfigSub?.cancel();
    _bigWinSub?.cancel();
    super.dispose();
  }
}
