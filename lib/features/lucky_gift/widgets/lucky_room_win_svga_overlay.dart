import 'package:flutter/material.dart';
import '../../../../screens/room/widgets/svga_player.dart';

/// عارض أنيميشن مكسب الحظ الداخلي في الغرفة بصيغة SVGA (In-Room Win Animation)
/// يتم تشغيله لجميع المتواجدين في نفس الغرفة عند فوز المستخدم بمضاعف (5X, 10X, 20X, 50X, 100X, 250X, 500X, 1000X)
/// يدعم استبدال النصوص الديناميكية:
/// - مفتاح 'test-b': اسم الهدية
/// - مفتاح 'test-a': عدد العملات التي اكتسبها المستخدم
class LuckyRoomWinSvgaOverlay extends StatefulWidget {
  final int multiplier;
  final int wonCoins;
  final String giftName;
  final String senderName;
  final String senderAvatar;
  final String? customSvgaUrl;
  final VoidCallback onFinished;

  const LuckyRoomWinSvgaOverlay({
    Key? key,
    required this.multiplier,
    required this.wonCoins,
    required this.giftName,
    required this.senderName,
    this.senderAvatar = '',
    this.customSvgaUrl,
    required this.onFinished,
  }) : super(key: key);

  /// فحص ما إذا كان المضاعف يستحق تشغيل أنيميشن الـ SVGA في الروم
  static bool hasWinSvga(int multiplier, {String? customUrl}) {
    return (customUrl != null && customUrl.isNotEmpty) || multiplier >= 5;
  }

  /// إرجاع مسار الـ SVGA الأنسب لقيمة المضاعف
  static String? getWinSvgaPath(int multiplier, {bool isArabic = true, String? customUrl}) {
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    }
    if (multiplier >= 1000) {
      return 'assets/svga/gift_1000.svga';
    } else if (multiplier >= 500) {
      return 'assets/svga/gift_500.svga';
    } else if (multiplier >= 250) {
      return 'assets/svga/gift_250.svga';
    } else if (multiplier >= 100) {
      return 'assets/svga/gift_100.svga';
    } else if (multiplier >= 50) {
      return 'assets/svga/gift_50.svga';
    } else if (multiplier >= 20) {
      return 'assets/svga/gift_20.svga';
    } else if (multiplier >= 10) {
      return 'assets/svga/gift_10.svga';
    } else if (multiplier >= 5) {
      return 'assets/svga/gift_5.svga';
    }
    return null;
  }

  @override
  State<LuckyRoomWinSvgaOverlay> createState() => _LuckyRoomWinSvgaOverlayState();
}

class _LuckyRoomWinSvgaOverlayState extends State<LuckyRoomWinSvgaOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutBack,
    );

    _fadeController.forward();

    // إغلاق العارض تلقائياً بعد 3.2 ثوانٍ
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) {
        _fadeController.reverse().then((_) => widget.onFinished());
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';
    final svgaPath = LuckyRoomWinSvgaOverlay.getWinSvgaPath(
      widget.multiplier,
      isArabic: isAr,
      customUrl: widget.customSvgaUrl,
    );

    if (svgaPath == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Center(
        child: ScaleTransition(
          scale: _scaleAnim,
          child: SizedBox(
            width: 360,
            height: 360,
            child: SvgaPlayer(
              assetPath: svgaPath,
              loops: false,
              fit: BoxFit.contain,
              textReplacement: {
                'test-b': widget.giftName, // اسم الهدية
                'test-a': '+${widget.wonCoins}', // عدد العملات المكتسبة
                'test': '${widget.senderName} +${widget.wonCoins}',
                'coins': '+${widget.wonCoins}',
                'name': widget.senderName,
              },
              imageReplacement: widget.senderAvatar.isNotEmpty
                  ? {
                      'Avatar': widget.senderAvatar,
                    }
                  : null,
              onFinished: () {
                if (mounted) {
                  _fadeController.reverse().then((_) => widget.onFinished());
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
