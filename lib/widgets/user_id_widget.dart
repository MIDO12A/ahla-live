import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ويدجت عرض معرف المستخدم (User ID) المطابق تماماً للأصل مع دعم التأثير اللوني والمتحرك
/// يدعم:
/// 1. المعرف المميز / الجذاب (Beauty / Lucky ID):
///    - خلفية برتقالية كهرمانية مضيئة (#1ADE880F) مع حواف دائرية 11dp
///    - نص ملون متحرك بانسيابية (Animated Flowing Gradient / Shimmer)
///    - دعم ملفات ومؤثرات GIF وخلفيات متحركة
///    - أيقونة شارة المعرف الأصلية (common_user_id_ic.webp)
///    - أيقونة النسخ الذهبية (common_id_copy_2_ic.webp)
/// 2. المعرف العادي (Normal ID):
///    - خلفية داكنة نصف شفافة (#4D000000) مع حواف دائرية 11dp
///    - لون الخط #CCFFFFFF
///    - أيقونة النسخ الرمادية (common_id_copy_ic.webp)
class UserIdWidget extends StatefulWidget {
  final String idText;
  final bool isBeauty;
  final bool showCopy;
  final String? countryCode;
  final double fontSize;
  final VoidCallback? onCopied;
  final String? colorEffect; // e.g. 'golden', 'rainbow', 'neon', 'fire'
  final String? gifUrl;      // Optional GIF badge/effect url

  const UserIdWidget({
    super.key,
    required this.idText,
    this.isBeauty = false,
    this.showCopy = true,
    this.countryCode,
    this.fontSize = 12.0,
    this.onCopied,
    this.colorEffect,
    this.gifUrl,
  });

  static String resolveCountryCode(String? raw) {
    if (raw == null || raw.isEmpty) return 'eg';
    final s = raw.trim();
    if (s == 'مصر' || s == 'Egypt') return 'eg';
    if (s == 'السعودية' || s == 'Saudi Arabia') return 'sa';
    if (s == 'الإمارات' || s == 'UAE') return 'ae';
    if (s == 'الكويت' || s == 'Kuwait') return 'kw';
    if (s == 'قطر' || s == 'Qatar') return 'qa';
    if (s == 'البحرين' || s == 'Bahrain') return 'bh';
    if (s == 'عمان' || s == 'Oman') return 'om';
    if (s == 'العراق' || s == 'Iraq') return 'iq';
    if (s == 'سوريا' || s == 'Syria') return 'sy';
    if (s == 'لبنان' || s == 'Lebanon') return 'lb';
    if (s == 'الأردن' || s == 'Jordan') return 'jo';
    if (s == 'فلسطين' || s == 'Palestine') return 'ps';
    if (s == 'اليمن' || s == 'Yemen') return 'ye';
    if (s == 'الجزائر' || s == 'Algeria') return 'dz';
    if (s == 'المغرب' || s == 'Morocco') return 'ma';
    if (s == 'تونس' || s == 'Tunisia') return 'tn';
    if (s == 'ليبيا' || s == 'Libya') return 'ly';
    if (s == 'السودان' || s == 'Sudan') return 'sd';
    if (s.length == 2 && RegExp(r'^[a-zA-Z]{2}$').hasMatch(s)) {
      return s.toLowerCase();
    }
    return 'eg';
  }

  static String countryCodeToEmoji(String code) {
    if (code.length == 2) {
      final upper = code.toUpperCase();
      return String.fromCharCode(0x1F1E6 + upper.codeUnitAt(0) - 65) +
          String.fromCharCode(0x1F1E6 + upper.codeUnitAt(1) - 65);
    }
    return '🇪🇬';
  }

  static bool isSpecialId(String? idText, {bool isBeauty = false, String? colorEffect, String? gifUrl}) {
    if (isBeauty) return true;
    if (colorEffect != null && colorEffect.isNotEmpty) return true;
    if (gifUrl != null && gifUrl.isNotEmpty) return true;
    if (idText == null || idText.trim().isEmpty) return false;
    final clean = idText.trim();
    final numVal = int.tryParse(clean);
    if (numVal != null && clean.length <= 6) return true;
    return false;
  }

  @override
  State<UserIdWidget> createState() => _UserIdWidgetState();
}

class _UserIdWidgetState extends State<UserIdWidget> with SingleTickerProviderStateMixin {
  AnimationController? _animCtrl;

  @override
  void initState() {
    super.initState();
    _initAnimationIfNeeded();
  }

  @override
  void didUpdateWidget(UserIdWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initAnimationIfNeeded();
  }

  void _initAnimationIfNeeded() {
    final bool isSpecial = widget.isBeauty ||
        (widget.idText.isNotEmpty && widget.idText.length <= 6 && int.tryParse(widget.idText) != null) ||
        (widget.colorEffect != null && widget.colorEffect!.isNotEmpty) ||
        (widget.gifUrl != null && widget.gifUrl!.isNotEmpty);

    if (isSpecial && _animCtrl == null) {
      _animCtrl = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 3),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _animCtrl?.dispose();
    super.dispose();
  }

  Widget _buildAnimatedText(bool effectiveBeauty) {
    if (!effectiveBeauty || _animCtrl == null) {
      return Text(
        widget.idText,
        style: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: effectiveBeauty ? FontWeight.bold : FontWeight.w500,
          color: effectiveBeauty ? const Color(0xFFFFD98B) : const Color(0xCCFFFFFF),
          height: 1.1,
          letterSpacing: 0.3,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animCtrl!,
      builder: (context, child) {
        final value = _animCtrl!.value;
        List<Color> colors;
        if (widget.colorEffect == 'rainbow') {
          colors = const [
            Color(0xFFFF0055),
            Color(0xFFFFAA00),
            Color(0xFF00FFCC),
            Color(0xFF0088FF),
            Color(0xFFFF00CC),
            Color(0xFFFF0055),
          ];
        } else if (widget.colorEffect == 'neon' || widget.colorEffect == 'cyan') {
          colors = const [
            Color(0xFF00E5FF),
            Color(0xFF76FF03),
            Color(0xFF00E5FF),
          ];
        } else if (widget.colorEffect == 'fire') {
          colors = const [
            Color(0xFFFF1744),
            Color(0xFFFF9100),
            Color(0xFFFFEA00),
            Color(0xFFFF1744),
          ];
        } else {
          // Default Golden Shimmer
          colors = const [
            Color(0xFFFFD700),
            Color(0xFFFFF8DC),
            Color(0xFFFFA500),
            Color(0xFFFFD700),
          ];
        }

        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: colors,
              transform: _SlidingGradientTransform(slidePercent: value),
            ).createShader(bounds);
          },
          child: Text(
            widget.idText,
            style: TextStyle(
              fontSize: widget.fontSize,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.1,
              letterSpacing: 0.4,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.idText.isEmpty) return const SizedBox.shrink();

    // التحقق التلقائي إذا كان المعرف مميزاً (مثلاً: 6 خانات أو أقل، أو محدد كـ isBeauty)
    final bool effectiveBeauty = widget.isBeauty ||
        (widget.idText.length <= 6 && int.tryParse(widget.idText) != null) ||
        (widget.colorEffect != null && widget.colorEffect!.isNotEmpty) ||
        (widget.gifUrl != null && widget.gifUrl!.isNotEmpty);

    final String cleanCountry = UserIdWidget.resolveCountryCode(widget.countryCode);
    final String flagEmoji = UserIdWidget.countryCodeToEmoji(cleanCountry);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // رمز علم الدولة مع بديل إيموجي فوري
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Image.network(
            'https://flagcdn.com/w40/$cleanCountry.png',
            width: 18,
            height: 12,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Text(flagEmoji, style: const TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(width: 5),

        // كبسولة المعرف
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: widget.idText));
            if (widget.onCopied != null) {
              widget.onCopied!();
            } else {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text('تم نسخ المعرف بنجاح'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: effectiveBeauty ? const Color(0x26DE880F) : const Color(0x4D000000),
              borderRadius: BorderRadius.circular(11),
              border: effectiveBeauty ? Border.all(color: const Color(0x80FFD98B), width: 0.8) : null,
              boxShadow: effectiveBeauty
                  ? [
                      BoxShadow(
                        color: const Color(0xFFDE880F).withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // أيقونة شارة ID المميزة الأصلية أو GIF مخصص
                if (widget.gifUrl != null && widget.gifUrl!.isNotEmpty) ...[
                  Image.network(
                    widget.gifUrl!,
                    width: 18,
                    height: 18,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/mipmap-xxhdpi/common_user_id_ic.webp',
                      width: 18,
                      height: 18,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 3),
                ] else if (effectiveBeauty) ...[
                  Image.asset(
                    'assets/mipmap-xxhdpi/common_user_id_ic.webp',
                    width: 18,
                    height: 18,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 3),
                ],

                // رقم المعرف الملون والمتحرك
                _buildAnimatedText(effectiveBeauty),

                // أيقونة النسخ
                if (widget.showCopy) ...[
                  const SizedBox(width: 4),
                  Image.asset(
                    effectiveBeauty
                        ? 'assets/mipmap-xxhdpi/common_id_copy_2_ic.webp'
                        : 'assets/mipmap-xxhdpi/common_id_copy_ic.webp',
                    width: 13,
                    height: 13,
                    fit: BoxFit.contain,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (slidePercent * 2 - 1), 0.0, 0.0);
  }
}

class SpecialTextWidget extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool isSpecial;
  final String? colorEffect;
  final int maxLines;
  final TextOverflow overflow;

  const SpecialTextWidget({
    super.key,
    required this.text,
    required this.style,
    this.isSpecial = true,
    this.colorEffect,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  State<SpecialTextWidget> createState() => _SpecialTextWidgetState();
}

class _SpecialTextWidgetState extends State<SpecialTextWidget> with SingleTickerProviderStateMixin {
  AnimationController? _animCtrl;

  @override
  void initState() {
    super.initState();
    if (widget.isSpecial) {
      _animCtrl = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 3),
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(SpecialTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpecial && _animCtrl == null) {
      _animCtrl = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 3),
      )..repeat();
    } else if (!widget.isSpecial && _animCtrl != null) {
      _animCtrl?.dispose();
      _animCtrl = null;
    }
  }

  @override
  void dispose() {
    _animCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSpecial || _animCtrl == null) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    return AnimatedBuilder(
      animation: _animCtrl!,
      builder: (context, child) {
        final value = _animCtrl!.value;
        List<Color> colors;
        if (widget.colorEffect == 'rainbow') {
          colors = const [
            Color(0xFFFF0055),
            Color(0xFFFFAA00),
            Color(0xFF00FFCC),
            Color(0xFF0088FF),
            Color(0xFFFF00CC),
            Color(0xFFFF0055),
          ];
        } else if (widget.colorEffect == 'neon') {
          colors = const [
            Color(0xFF00F0FF),
            Color(0xFF7000FF),
            Color(0xFFFF007B),
            Color(0xFF00F0FF),
          ];
        } else if (widget.colorEffect == 'fire') {
          colors = const [
            Color(0xFFFF3300),
            Color(0xFFFF9900),
            Color(0xFFFFDD00),
            Color(0xFFFF3300),
          ];
        } else {
          // Default: Golden shimmer
          colors = const [
            Color(0xFFE5A642),
            Color(0xFFFFF3A8),
            Color(0xFFFFD700),
            Color(0xFFFFC043),
            Color(0xFFE5A642),
          ];
        }

        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: colors,
              transform: _SlidingGradientTransform(slidePercent: value),
            ).createShader(bounds);
          },
          child: Text(
            widget.text,
            style: widget.style.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            maxLines: widget.maxLines,
            overflow: widget.overflow,
          ),
        );
      },
    );
  }
}
