import 'package:flutter/material.dart';
import '../../../../screens/room/widgets/svga_player.dart';

/// بانر الفوز الأسطوري العالمي عبر SVGA (Global Big Win Broadcast)
/// يدعم استبدال النص والصورة ديناميكياً:
/// - مفتاح الصورة: 'Avatar' (صورة المستخدم)
/// - مفتاح النص: 'test' (اسم المستخدم ومقدار الكوينز المربوحة)
class BigWinBanner extends StatefulWidget {
  final String senderName;
  final String senderAvatar;
  final String giftName;
  final int multiplier;
  final int totalWon;
  final String lang; // 'ar' أو 'en'
  final String? customSvgaUrl;
  final VoidCallback onDismiss;

  const BigWinBanner({
    Key? key,
    required this.senderName,
    this.senderAvatar = '',
    required this.giftName,
    required this.multiplier,
    required this.totalWon,
    this.lang = 'ar',
    this.customSvgaUrl,
    required this.onDismiss,
  }) : super(key: key);

  /// تحديد ملف الـ SVGA المناسب بناءً على المضاعف واللغة أو الرابط المخصص
  static String getSvgaAssetPath(int multiplier, String lang, {String? customUrl}) {
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    }
    final prefix = lang == 'en' ? 'en' : 'ar';
    if (multiplier >= 1000) {
      return 'assets/svga/${prefix}1000.svga';
    } else if (multiplier >= 500) {
      return 'assets/svga/${prefix}500.svga';
    } else if (multiplier >= 250) {
      return 'assets/svga/${prefix}250.svga';
    } else {
      return 'assets/svga/${prefix}100.svga';
    }
  }

  @override
  State<BigWinBanner> createState() => _BigWinBannerState();
}

class _BigWinBannerState extends State<BigWinBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();

    // إغلاق البانر تلقائياً بعد 4.5 ثوانٍ
    Future.delayed(const Duration(milliseconds: 4500), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svgaPath = BigWinBanner.getSvgaAssetPath(
      widget.multiplier,
      widget.lang,
      customUrl: widget.customSvgaUrl,
    );
    
    // نص الاستبدال لمفتاح 'test'
    final displayText = widget.lang == 'ar'
        ? '${widget.senderName} فاز بـ ${widget.totalWon}'
        : '${widget.senderName} won ${widget.totalWon}';

    return IgnorePointer(
      child: SlideTransition(
        position: _slideAnim,
        child: SafeArea(
          child: Container(
            width: double.infinity,
            height: 140,
            alignment: Alignment.topCenter,
            child: SvgaPlayer(
              assetPath: svgaPath,
              loops: false,
              fit: BoxFit.contain,
              textReplacement: {
                'test': displayText,
              },
              imageReplacement: widget.senderAvatar.isNotEmpty
                  ? {
                      'Avatar': widget.senderAvatar,
                    }
                  : null,
              onFinished: () {
                if (mounted) {
                  _controller.reverse().then((_) => widget.onDismiss());
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
