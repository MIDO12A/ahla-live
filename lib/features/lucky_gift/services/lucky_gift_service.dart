import 'dart:async';
import 'package:flutter/material.dart';
import '../models/lucky_gift_model.dart';
import '../widgets/lucky_card_flip_layout.dart';
import '../widgets/big_win_banner.dart';
import '../widgets/lucky_combo_svga_overlay.dart';
import '../widgets/lucky_room_win_svga_overlay.dart';
import '../widgets/gift_seat_flight_overlay.dart';

/// خدمة إدارة وتنسيق هدايا الحظ في الغرفة (LuckyGiftService)
/// تقوم باستقبال أحداث السيرفر اللحظية، وتنسيق طابور العرض لضمان عدم حدوث تداخل (Queue Manager)
class LuckyGiftService {
  static final LuckyGiftService _instance = LuckyGiftService._internal();
  factory LuckyGiftService() => _instance;
  LuckyGiftService._internal();

  // طابور الرسائل والأحداث
  final List<LuckyGiftBroadcastData> _broadcastQueue = [];
  bool _isPlayingAnim = false;
  Timer? _queueWatchdog;
  OverlayEntry? _currentOverlay;
  OverlayEntry? _bannerOverlay;

  /// إضافة حدث هدية حظ إلى طابور العرض
  void enqueueLuckyGift(BuildContext context, LuckyGiftBroadcastData data) {
    // إذا تراكم الطابور بسبب النقر السريع، نتخلص من الأحداث الصغيرة القديمة لمنع التأخر
    if (_broadcastQueue.length > 2) {
      _broadcastQueue.removeWhere((item) => item.maxMultiplier < 50);
    }
    _broadcastQueue.add(data);
    if (!_isPlayingAnim) {
      _processNextInQueue(context);
    }
  }

  /// معالجة الحدث التالي في الطابور
  void _processNextInQueue(BuildContext context) {
    if (_broadcastQueue.isEmpty) {
      _isPlayingAnim = false;
      _queueWatchdog?.cancel();
      return;
    }

    _isPlayingAnim = true;
    final nextData = _broadcastQueue.removeAt(0);

    // مهلة أمان قصوى لمنع التعليق
    _queueWatchdog?.cancel();
    _queueWatchdog = Timer(const Duration(seconds: 10), () {
      if (_isPlayingAnim && !_broadcastQueue.isEmpty) {
        _processNextInQueue(context);
      } else if (_isPlayingAnim) {
        _isPlayingAnim = false;
      }
    });

    // 1. إذا كان هناك فوز بمضاعف (5X فما فوق)، نشغل أنيميشن مكسب الحظ في الروم فقط لمنع تشغيل اثنين SVGA معاً
    final bool hasWin = LuckyRoomWinSvgaOverlay.hasWinSvga(nextData.maxMultiplier);
    if (hasWin) {
      showRoomWinSvgaOverlay(
        context,
        multiplier: nextData.maxMultiplier,
        wonCoins: nextData.totalWonCoins,
        giftName: nextData.gift.giftNameAr.isNotEmpty ? nextData.gift.giftNameAr : nextData.gift.giftName,
        senderName: nextData.senderName,
        senderAvatar: nextData.senderAvatar,
      );
    } else if (LuckyComboSvgaOverlay.hasSvgaForCount(nextData.comboCount)) {
      // نشغل أنيميشن رقم الكومبو فقط إذا لم يكن هناك فوز مضاعف تجنباً لتشنج الـ GPU
      showComboSvgaOverlay(context, nextData.comboCount);
    }

    // 2. إذا كان فوزاً كبيراً بمضاعف 100X فما فوق، نعرض بانر الفوز العام الأسطوري لكافة الغرف
    if (nextData.isBigWin && nextData.maxMultiplier >= 100) {
      showBigWinBanner(
        context,
        senderName: nextData.senderName,
        senderAvatar: nextData.senderAvatar,
        giftName: nextData.gift.giftNameAr,
        multiplier: nextData.maxMultiplier,
        totalWon: nextData.totalWonCoins,
      );
    }

    // 3. مهلة عرض الأنيميشن قبل تمرير الطابور للحدث التالي
    int waitMs = 0;
    if (hasWin) {
      waitMs = 2800;
    } else if (LuckyComboSvgaOverlay.hasSvgaForCount(nextData.comboCount)) {
      waitMs = 1500;
    }

    if (waitMs > 0) {
      Timer(Duration(milliseconds: waitMs), () {
        _isPlayingAnim = false;
        _queueWatchdog?.cancel();
        if (context.mounted) {
          _processNextInQueue(context);
        } else {
          _isPlayingAnim = false;
        }
      });
    } else {
      _isPlayingAnim = false;
      _queueWatchdog?.cancel();
      _processNextInQueue(context);
    }
  }

  OverlayEntry? _roomWinOverlay;
  void showRoomWinSvgaOverlay(
    BuildContext context, {
    required int multiplier,
    required int wonCoins,
    required String giftName,
    required String senderName,
    String senderAvatar = '',
  }) {
    _roomWinOverlay?.remove();
    if (!context.mounted) return; // FIX: لا تُنشئ overlay فوق context مفصول
    final overlay = Overlay.of(context, rootOverlay: true);
    _roomWinOverlay = OverlayEntry(
      builder: (ctx) => LuckyRoomWinSvgaOverlay(
        multiplier: multiplier,
        wonCoins: wonCoins,
        giftName: giftName,
        senderName: senderName,
        senderAvatar: senderAvatar,
        onFinished: () {
          _roomWinOverlay?.remove();
          _roomWinOverlay = null;
        },
      ),
    );

    overlay.insert(_roomWinOverlay!);
  }

  OverlayEntry? _comboSvgaOverlay;
  void showComboSvgaOverlay(BuildContext context, int count) {
    _comboSvgaOverlay?.remove();
    if (!context.mounted) return; // FIX: لا تُنشئ overlay فوق context مفصول
    final overlay = Overlay.of(context, rootOverlay: true);
    _comboSvgaOverlay = OverlayEntry(
      builder: (ctx) => LuckyComboSvgaOverlay(
        count: count,
        onFinished: () {
          _comboSvgaOverlay?.remove();
          _comboSvgaOverlay = null;
        },
      ),
    );

    overlay.insert(_comboSvgaOverlay!);
  }

  void _showCardFlipOverlay(BuildContext context, LuckyGiftBroadcastData data) {
    if (!context.mounted) return; // FIX: لا تُنشئ overlay فوق context مفصول
    final overlay = Overlay.of(context, rootOverlay: true);
    _currentOverlay?.remove();
    _currentOverlay = OverlayEntry(
      builder: (ctx) => LuckyCardFlipLayout(
        data: data,
        onFinished: () {
          _currentOverlay?.remove();
          _currentOverlay = null;
          _queueWatchdog?.cancel();
          _processNextInQueue(context);
        },
      ),
    );

    overlay.insert(_currentOverlay!);
  }

  /// إظهار بانر الفوز الكبير في أعلى الشاشة
  void showBigWinBanner(
    BuildContext context, {
    required String senderName,
    String senderAvatar = '',
    required String giftName,
    required int multiplier,
    required int totalWon,
  }) {
    if (multiplier < 100) return; // حصراً 100X فما فوق
    _bannerOverlay?.remove();
    if (!context.mounted) return; // FIX: لا تُنشئ overlay فوق context مفصول
    final overlay = Overlay.of(context, rootOverlay: true);
    _bannerOverlay = OverlayEntry(
      builder: (ctx) => BigWinBanner(
        senderName: senderName,
        senderAvatar: senderAvatar,
        giftName: giftName,
        multiplier: multiplier,
        totalWon: totalWon,
        onDismiss: () {
          _bannerOverlay?.remove();
          _bannerOverlay = null;
        },
      ),
    );

    overlay.insert(_bannerOverlay!);
  }

  /// الاستماع التلقائي للبث العام لجميع الغرف في التطبيق
  StreamSubscription? _globalSub;
  void listenToGlobalBigWins(BuildContext context, Stream<Map<String, dynamic>> globalStream) {
    _globalSub?.cancel();
    _globalSub = globalStream.listen((data) {
      final mult = data['multiplier'] is int ? data['multiplier'] as int : int.tryParse(data['multiplier']?.toString() ?? '0') ?? 0;
      if (mult < 100) return; // البانر العام يظهر فقط لـ 100X فما فوق
      if (context.mounted) {
        showBigWinBanner(
          context,
          senderName: data['sender_name'] ?? '',
          senderAvatar: data['sender_avatar'] ?? '',
          giftName: data['gift_name'] ?? '',
          multiplier: mult,
          totalWon: data['total_won'] ?? 0,
        );
      }
    });
  }

  /// إطلاق تأثير طيران الهدية إلى مقعد أو مقاعد المستلمين
  OverlayEntry? _flightOverlay;
  void showGiftFlightToSeats(
    BuildContext context, {
    required String giftIconUrl,
    String? giftAnimAsset,
    String type = 'image',
    required Offset startOffset,
    required List<Offset> targetOffsets,
    VoidCallback? onFinished,
  }) {
    _flightOverlay?.remove();
    if (!context.mounted) return; // FIX: لا تُنشئ overlay فوق context مفصول
    final overlay = Overlay.of(context);
    _flightOverlay = OverlayEntry(
      builder: (ctx) => GiftSeatFlightOverlay(
        giftIconUrl: giftIconUrl,
        giftAnimAsset: giftAnimAsset,
        type: type,
        startOffset: startOffset,
        targetOffsets: targetOffsets,
        onFinished: () {
          _flightOverlay?.remove();
          _flightOverlay = null;
          if (onFinished != null) onFinished();
        },
      ),
    );

    overlay.insert(_flightOverlay!);
  }

  /// FIX: تنظيف شامل لكل طبقات الحظ عند الخروج من الغرفة.
  /// - يزيل جميع الـ overlays النشطة (كومبو/مكسب/بانر/كروت/طيران).
  /// - يمسح طابور البث المعلّق بحيث لا تظهر مضاعفات الحظ في شاشات أخرى.
  /// - يلغي مؤقّت الأمان ويعيد حالة التشغيل إلى الوضع الطبيعي.
  void disposeAllOverlays() {
    _queueWatchdog?.cancel();
    _broadcastQueue.clear();
    _isPlayingAnim = false;

    _currentOverlay?.remove();
    _bannerOverlay?.remove();
    _comboSvgaOverlay?.remove();
    _roomWinOverlay?.remove();
    _flightOverlay?.remove();

    _currentOverlay = null;
    _bannerOverlay = null;
    _comboSvgaOverlay = null;
    _roomWinOverlay = null;
    _flightOverlay = null;
    _globalSub?.cancel();
    _globalSub = null;
  }

  void dispose() {
    disposeAllOverlays();
  }
}
