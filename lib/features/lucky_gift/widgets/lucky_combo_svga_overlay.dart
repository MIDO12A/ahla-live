import 'package:flutter/material.dart';

import '../../../../services/dynamic_config_service.dart';
import 'dashboard_anim_player.dart';

/// عارض أرقام الكومبو في منتصف شاشة الغرفة.
/// ✅ المصدر الوحيد: لوحة التحكم (app_assets) — لا ملفات محلية.
/// يدعم أي امتداد (svga / vap / mp4 / صورة) عبر DashboardAnimPlayer.
class LuckyComboSvgaOverlay extends StatefulWidget {
  final int count;
  final VoidCallback onFinished;

  const LuckyComboSvgaOverlay({
    Key? key,
    required this.count,
    required this.onFinished,
  }) : super(key: key);

  /// المسار الافتراضي الذي يُستخدم كمفتاح بحث في app_assets
  static String _assetKeyForCount(int count) =>
      'assets/svga/chates_gift_number_$count.svga';

  /// فحص ما إذا كان للرقم ملف مخصص مرفوع من لوحة التحكم
  static bool hasSvgaForCount(int count) {
    if (count <= 0) return false;
    final url = DynamicConfigService().getAssetOverride(_assetKeyForCount(count));
    return url != null && url.isNotEmpty;
  }

  /// إرجاع رابط الأنيميشن من لوحة التحكم (svga/vap/mp4/صورة) أو null
  static String? getSvgaPathForCount(int count) {
    if (!hasSvgaForCount(count)) return null;
    return DynamicConfigService().getAssetOverride(_assetKeyForCount(count));
  }

  @override
  State<LuckyComboSvgaOverlay> createState() => _LuckyComboSvgaOverlayState();
}

class _LuckyComboSvgaOverlayState extends State<LuckyComboSvgaOverlay>
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

    // إغلاق العارض تلقائياً بعد ثانيتين و نصف
    Future.delayed(const Duration(milliseconds: 2600), () {
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
    final assetUrl = LuckyComboSvgaOverlay.getSvgaPathForCount(widget.count);

    if (assetUrl == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Center(
        child: ScaleTransition(
          scale: _scaleAnim,
          child: SizedBox(
            width: 320,
            height: 320,
            child: DashboardAnimPlayer(
              url: assetUrl,
              width: 320,
              height: 320,
              loops: false,
              onFinished: widget.onFinished,
            ),
          ),
        ),
      ),
    );
  }
}
