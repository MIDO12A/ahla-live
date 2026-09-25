import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ويدجت عرض معرف المستخدم (User ID) المطابق تماماً للأصل (UserIdView.kt & layout_common_level.xml)
/// يدعم:
/// 1. المعرف المميز / الجذاب (Beauty / Lucky ID):
///    - خلفية برتقالية كهرمانية مضيئة (#1ADE880F) مع حواف دائرية 11dp
///    - أيقونة شارة المعرف الأصلية (common_user_id_ic.webp) بحجم 20x20dp
///    - لون الخط الذهبي/البرتقالي المشع #FFD98B2B بخط بارز
///    - أيقونة النسخ الذهبية (common_id_copy_2_ic.webp)
/// 2. المعرف العادي (Normal ID):
///    - خلفية داكنة نصف شفافة (#4D000000) مع حواف دائرية 11dp
///    - لون الخط #CCFFFFFF / #9BA1B6
///    - أيقونة النسخ الرمادية (common_id_copy_ic.webp)
class UserIdWidget extends StatelessWidget {
  final String idText;
  final bool isBeauty;
  final bool showCopy;
  final String? countryCode;
  final double fontSize;
  final VoidCallback? onCopied;

  const UserIdWidget({
    super.key,
    required this.idText,
    this.isBeauty = false,
    this.showCopy = true,
    this.countryCode,
    this.fontSize = 12.0,
    this.onCopied,
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

  @override
  Widget build(BuildContext context) {
    if (idText.isEmpty) return const SizedBox.shrink();

    // التحقق التلقائي إذا كان المعرف مميزاً (مثلاً: أقل من 7 خانات، أو محدد كـ isBeauty)
    final bool effectiveBeauty = isBeauty || (idText.length <= 6 && int.tryParse(idText) != null);
    final String cleanCountry = resolveCountryCode(countryCode);
    final String flagEmoji = countryCodeToEmoji(cleanCountry);

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

        // كبسولة المعرف (cl_id المطابقة للتطبيق الأصلي)
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: idText));
            if (onCopied != null) {
              onCopied!();
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
              // rank_id_beauty_shape_bg: #1ADE880F / rank_id_shape_bg: #4D000000
              color: effectiveBeauty ? const Color(0x26DE880F) : const Color(0x4D000000),
              borderRadius: BorderRadius.circular(11),
              border: effectiveBeauty ? Border.all(color: const Color(0x80FFD98B), width: 0.8) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // أيقونة شارة ID الذهبية للأصل: iv_id_label (تظهر في المعرف المميز)
                if (effectiveBeauty) ...[
                  Image.asset(
                    'assets/mipmap-xxhdpi/common_user_id_ic.webp',
                    width: 18,
                    height: 18,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 3),
                ],

                // رقم المعرف tv_id (لون #FFD98B2B في المميز / #E0E0E0 في العادي)
                Text(
                  idText,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: effectiveBeauty ? FontWeight.bold : FontWeight.w500,
                    color: effectiveBeauty ? const Color(0xFFFFD98B) : const Color(0xCCFFFFFF),
                    height: 1.1,
                    letterSpacing: 0.3,
                  ),
                ),

                // أيقونة النسخ iv_copy_ic
                if (showCopy) ...[
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
