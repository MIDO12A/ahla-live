import 'package:flutter/material.dart';
import '../../../../screens/room/widgets/svga_player.dart';

/// عارض أرقام الكومبو الحصرية بصيغة SVGA في منتصف شاشة الغرفة
/// يقوم بتشغيل أنيميشن الرقم (10، 20، 30، 50، 66، 88، 100، ... حتى 10000)
class LuckyComboSvgaOverlay extends StatefulWidget {
  final int count;
  final VoidCallback onFinished;

  const LuckyComboSvgaOverlay({
    Key? key,
    required this.count,
    required this.onFinished,
  }) : super(key: key);

  /// فحص ما إذا كان الرقم المحدد له ملف SVGA مخصص
  static bool hasSvgaForCount(int count) {
    const availableNumbers = [
      10, 20, 30, 50, 66, 88, 100, 200, 300, 400, 500,
      666, 777, 888, 1000, 2000, 3000, 4000, 5000, 6000,
      7000, 8000, 9000, 10000
    ];
    return availableNumbers.contains(count);
  }

  /// إرجاع مسار ملف الـ SVGA المطابق للرقم
  static String? getSvgaPathForCount(int count) {
    if (hasSvgaForCount(count)) {
      return 'assets/svga/chates_gift_number_$count.svga';
    }
    return null;
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
    final svgaPath = LuckyComboSvgaOverlay.getSvgaPathForCount(widget.count);

    if (svgaPath == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Center(
        child: ScaleTransition(
          scale: _scaleAnim,
          child: SizedBox(
            width: 320,
            height: 320,
            child: SvgaPlayer(
              assetPath: svgaPath,
              loops: false,
              fit: BoxFit.contain,
              onFinished: widget.onFinished,
            ),
          ),
        ),
      ),
    );
  }
}
