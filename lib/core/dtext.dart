import 'package:flutter/material.dart';

import '../services/dynamic_config_service.dart';

/// نص قابل للتخصيص من لوحة التحكم.
///
/// يستبدل `Text` في كل التطبيق: يمرّر النص الأصلي كما هو من الكود، ثم:
/// 1) يبحث عن ترجمة/تسمية مخصّصة بنفس النص الأصلي في `custom_strings`.
/// 2) يبحث عن لون مخصّص للنص في `custom_text_colors`.
/// إن لم يوجد أي تخصيص يبقى السلوك مطابقاً لـ `Text` تماماً.
class DText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final double? textScaleFactor;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final String? semanticsIdentifier;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  const DText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = DynamicConfigService();
    return Text(
      cfg.resolveText(data),
      style: _resolvedStyle(cfg, data),
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaleFactor: textScaleFactor,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      semanticsIdentifier: semanticsIdentifier,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }

  TextStyle? _resolvedStyle(DynamicConfigService cfg, String original) {
    final override = cfg.textColorOverride(original);
    if (override == null) return style;
    return (style ?? const TextStyle()).copyWith(color: override);
  }
}

/// نسخة غنية (RichText) — تبقى كما هي مع دعم اللون المخصّص للنص الكامل.
class DRichText extends StatelessWidget {
  final InlineSpan textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final double? textScaleFactor;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final String? semanticsIdentifier;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  const DRichText(
    this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = DynamicConfigService();
    final original = textSpan is TextSpan ? (textSpan as TextSpan).text : null;
    final override = cfg.textColorOverride(original);
    return Text.rich(
      textSpan,
      style: override == null
          ? style
          : (style ?? const TextStyle()).copyWith(color: override),
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaleFactor: textScaleFactor,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      semanticsIdentifier: semanticsIdentifier,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
