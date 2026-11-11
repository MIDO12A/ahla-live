import 'package:flutter/material.dart';

import '../../../../services/dynamic_config_service.dart';
import 'dashboard_anim_player.dart';

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

  /// المستويات المتاحة (من الأكبر للأصغر) — تُحلّ من لوحة التحكم فقط
  static const List<int> _tiers = [1000, 500, 250, 100, 50, 20, 10, 5];

  static String _assetKeyForTier(int tier) => 'assets/svga/gift_$tier.svga';

  /// فحص ما إذا كان المضاعف يستحق تشغيل أنيميشن في الروم
  static bool hasWinSvga(int multiplier, {String? customUrl}) {
    return (customUrl != null && customUrl.isNotEmpty) ||
        getWinSvgaPath(multiplier, customUrl: customUrl) != null;
  }

  /// إرجاع رابط الأنيميشن من لوحة التحكم (svga/vap/mp4/صورة) أو null.
  /// ✅ لا ملفات محلية — يختار أول مستوى متاح أصغر من أو يساوي المضاعف.
  static String? getWinSvgaPath(int multiplier, {bool isArabic = true, String? customUrl}) {
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    }
    if (multiplier < 5) return null;
    final config = DynamicConfigService();
    for (final tier in _tiers) {
      if (multiplier < tier) continue;
      final url = config.getAssetOverride(_assetKeyForTier(tier));
      if (url != null && url.isNotEmpty) return url;
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
            child: DashboardAnimPlayer(
              url: svgaPath,
              width: 360,
              height: 360,
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
