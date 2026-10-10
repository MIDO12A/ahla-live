import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/gift_banner_config_model.dart';
import 'supabase_service.dart';
import 'supabase_data_service.dart';

/// خدمة إدارة لافتات الهدايا وبانرات فوز الحظ على مستوى التطبيق بالكامل (GlobalBannerService)
/// تضمن ظهور البانرات فوق أي شاشة (خارج الغرف وداخلها) بلحظية 0ms
class GlobalBannerService extends ChangeNotifier {
  static final GlobalBannerService instance = GlobalBannerService._();
  GlobalBannerService._();

  List<GiftBannerConfig> _bannerConfigs = [];
  List<GiftBannerConfig> get bannerConfigs => _bannerConfigs;

  Map<String, dynamic>? activeGiftBanner;
  Map<String, dynamic>? activeBigWin;
  Map<String, dynamic>? activeMarquee;

  final Set<String> _seenBroadcastIds = <String>{};
  Timer? _giftBannerHideTimer;
  Timer? _bigWinHideTimer;
  Timer? _marqueeHideTimer;

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
      final isFresh = bTs == 0 || (nowMs - bTs).abs() < 90000;
      if (!isFresh) continue;

      final bId = b['id']?.toString() ?? '${bTs}_${b['sender_uid']}';
      if (_seenBroadcastIds.contains(bId)) continue;
      _seenBroadcastIds.add(bId);

      final isLucky = b['is_lucky'] == true || b['type'] == 'lucky_gift';
      final multiplier = (b['multiplier'] as num?)?.toInt() ?? 0;

      // ── أ) عرض شريط الإعلان الماركي لجميع الغرف ──
      showMarquee(b);

      // ── ب) إذا كان فوز حظ كبير (50X فما فوق أو 100X) ──
      if (isLucky && (multiplier >= 50 || b['is_big_win'] == true)) {
        showBigWin({
          'senderName': b['sender_name']?.toString() ?? 'مستخدم',
          'senderAvatar': b['sender_photo_url']?.toString() ?? '',
          'giftName': b['gift_name']?.toString() ?? '',
          'multiplier': multiplier > 0 ? multiplier : 100,
          'totalWon': (b['won_coins'] as num?)?.toInt() ?? (b['coins'] as num?)?.toInt() ?? 0,
        });
      }

      // ── ج) فحص لافتة الهدية المخصصة SVGA (Gift Banner Config) ──
      if (!isLucky || multiplier <= 1) {
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
        } else if (totalCost >= 500) {
          // الشريطة الافتراضية للهدايا الكبيرة
          showGiftBanner({
            'animationAsset': 'assets/svga/gift_banner_strip.svga',
            'senderPhotoUrl': b['sender_photo_url']?.toString(),
            'receiverPhotoUrl': b['receiver_photo_url']?.toString(),
            'defaultImage': b['default_image']?.toString() ?? b['gift_icon']?.toString(),
            'giftCount': giftCount,
            'userRKey': 'user_r',
            'userLKey': 'user_l',
            'numberKey': 'number',
            'giftKey': 'gift',
          });
        }
      }
    }
  }

  void _handleIncomingBigWin(Map<String, dynamic> winData) {
    final mult = (winData['multiplier'] as num?)?.toInt() ?? 0;
    if (mult < 50) return;
    showBigWin({
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

  /// إظهار لافتة الهدية SVGA
  void showGiftBanner(Map<String, dynamic> data) {
    activeGiftBanner = data;
    notifyListeners();

    _giftBannerHideTimer?.cancel();
    _giftBannerHideTimer = Timer(const Duration(seconds: 8), () {
      dismissGiftBanner();
    });
  }

  void dismissGiftBanner() {
    _giftBannerHideTimer?.cancel();
    if (activeGiftBanner != null) {
      activeGiftBanner = null;
      notifyListeners();
    }
  }

  /// إظهار بانر فوز الحظ الأسطوري
  void showBigWin(Map<String, dynamic> data) {
    activeBigWin = data;
    notifyListeners();

    _bigWinHideTimer?.cancel();
    _bigWinHideTimer = Timer(const Duration(milliseconds: 4800), () {
      dismissBigWin();
    });
  }

  void dismissBigWin() {
    _bigWinHideTimer?.cancel();
    if (activeBigWin != null) {
      activeBigWin = null;
      notifyListeners();
    }
  }

  /// إظهار شريط الإعلان الماركي
  void showMarquee(Map<String, dynamic> data) {
    activeMarquee = data;
    notifyListeners();

    _marqueeHideTimer?.cancel();
    _marqueeHideTimer = Timer(const Duration(seconds: 6), () {
      dismissMarquee();
    });
  }

  void dismissMarquee() {
    _marqueeHideTimer?.cancel();
    if (activeMarquee != null) {
      activeMarquee = null;
      notifyListeners();
    }
  }

  /// تفعيل محلي فوري عند الإرسال من قبل المستخدم لمنع أي انتظار
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

  @override
  void dispose() {
    _giftBannerHideTimer?.cancel();
    _bigWinHideTimer?.cancel();
    _marqueeHideTimer?.cancel();
    _broadcastSub?.cancel();
    _bannerConfigSub?.cancel();
    _bigWinSub?.cancel();
    super.dispose();
  }
}
