import 'dart:io';
import 'package:flutter/material.dart';
import '../../../config/r.dart';
import 'svga_player.dart';
import 'vap_player.dart';

// ═══════════════════════════════════════════════════════════
// SvgaFrame — يُشغّل ملف SVGA حقيقي
// على Android: يستخدم SvgaNativePlayer (SVGAImageView Native) ✅
// على غير Android: يستخدم SvgaPlayer (Flutter Canvas)
// ═══════════════════════════════════════════════════════════

class SvgaFrame extends StatelessWidget {
  final String svgaPath;
  final double size;
  final bool visible;
  final BoxFit fit;

  const SvgaFrame({
    super.key,
    required this.svgaPath,
    required this.size,
    this.visible = true,
    this.fit = BoxFit.fill,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible || svgaPath.isEmpty) return const SizedBox.shrink();

    Widget player;
    if (isImageType(svgaPath)) {
      player = R.loadImage(svgaPath, width: size, height: size, fit: fit);
    } else if (isVideoType(svgaPath)) {
      player = VapPlayer(url: svgaPath, width: size, height: size, loops: true, fit: fit);
    } else {
      player = RepaintBoundary(
        child: SvgaPlayer(
          assetPath: svgaPath,
          width: size,
          height: size,
          loops: true,
          fit: fit,
        ),
      );
    }

    // الإطار عنصر جمالي ديكوري ولا يجب أن يعترض نقرات المستخدم على الصورة أو المقعد إطلاقاً
    return IgnorePointer(child: player);
  }
}
