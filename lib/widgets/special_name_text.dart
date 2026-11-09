import 'package:flutter/material.dart';

import '../core/dtext.dart';
import '../services/special_id_service.dart';

/// اسم مستخدم ملوّن تلقائياً إذا كان صاحب الحساب يستخدم آيدي مميزاً.
/// يعتمد على سجل [SpecialIdService] ولا يقوم بأي طلب شبكة بنفسه.
class SpecialNameText extends StatelessWidget {
  final String text;
  final String? customId;
  final String? colorEffect;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool animate;

  const SpecialNameText({
    super.key,
    required this.text,
    required this.style,
    this.customId,
    this.colorEffect,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: SpecialIdService.instance,
      builder: (context, _) {
        final item = SpecialIdService.instance.styleFor(customId);
        final effect = (colorEffect != null && colorEffect!.trim().isNotEmpty)
            ? colorEffect
            : item?.effectiveColorEffect;
        if (effect == null || effect.trim().isEmpty) {
          return DText(
            text,
            style: style,
            maxLines: maxLines,
            overflow: overflow,
            textAlign: textAlign,
          );
        }

        final preset = SpecialIdService.instance.presetFor(effect);
        if (animate && preset.animated) {
          return _AnimatedGradientName(
            text: text,
            style: style,
            colors: preset.colors,
            maxLines: maxLines,
            overflow: overflow,
            textAlign: textAlign,
          );
        }
        return _GradientName(
          text: text,
          style: style,
          colors: preset.colors,
          maxLines: maxLines,
          overflow: overflow,
          textAlign: textAlign,
        );
      },
    );
  }
}

class _GradientName extends StatelessWidget {
  final String text;
  final TextStyle style;
  final List<Color> colors;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const _GradientName({
    required this.text,
    required this.style,
    required this.colors,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        colors: colors,
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(bounds),
      child: DText(
        text,
        style: style.copyWith(color: Colors.white),
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      ),
    );
  }
}

class _AnimatedGradientName extends StatefulWidget {
  final String text;
  final TextStyle style;
  final List<Color> colors;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const _AnimatedGradientName({
    required this.text,
    required this.style,
    required this.colors,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  State<_AnimatedGradientName> createState() => _AnimatedGradientNameState();
}

class _AnimatedGradientNameState extends State<_AnimatedGradientName>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: widget.colors,
            transform: _SlidingTransform(percent: _controller.value),
          ).createShader(bounds),
          child: DText(
            widget.text,
            style: widget.style.copyWith(
              color: Colors.white,
              fontWeight: widget.style.fontWeight ?? FontWeight.bold,
            ),
            maxLines: widget.maxLines,
            overflow: widget.overflow,
            textAlign: widget.textAlign,
          ),
        );
      },
    );
  }
}

class _SlidingTransform extends GradientTransform {
  final double percent;
  const _SlidingTransform({required this.percent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (percent * 2 - 1),
      0.0,
      0.0,
    );
  }
}
