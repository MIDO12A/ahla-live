import 'package:flutter/material.dart';

import '../../../config/r.dart';
import '../../../screens/room/widgets/svga_player.dart';
import '../../../screens/room/widgets/vap_player.dart';

/// مشغّل موحّد لملفات الأنيميشن القادمة من لوحة التحكم (app_assets).
/// يدعم svga / vap / mp4 / صورة عادية حسب امتداد الرابط —
/// ويمرّر مفاتيح النصوص والصور إلى المشغّلات التي تدعمها.
class DashboardAnimPlayer extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final bool loops;
  final BoxFit fit;
  final VoidCallback? onFinished;
  final Map<String, String>? textReplacement;
  final Map<String, String>? imageReplacement;
  final String? defaultImageUrl;

  const DashboardAnimPlayer({
    super.key,
    required this.url,
    this.width = 320,
    this.height = 320,
    this.loops = false,
    this.fit = BoxFit.contain,
    this.onFinished,
    this.textReplacement,
    this.imageReplacement,
    this.defaultImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.shrink();
    final type = detectAssetType(url);

    if (type == AssetType.svga) {
      return SvgaPlayer(
        assetPath: url,
        width: width,
        height: height,
        fit: fit,
        loops: loops,
        onFinished: onFinished,
        textReplacement: textReplacement,
        imageReplacement: imageReplacement,
        defaultImageUrl: defaultImageUrl,
      );
    }

    if (type == AssetType.vap || type == AssetType.mp4) {
      return VapPlayer(
        url: url,
        width: width,
        height: height,
        fit: fit,
        loops: loops,
        onFinished: onFinished,
        textReplacement: textReplacement,
        imageReplacement: imageReplacement,
        defaultImageUrl: defaultImageUrl,
      );
    }

    // صورة عادية / webp / gif — بدون onFinished (المؤقت الخارجي يغلق العارض)
    return Image(
      image: R.cachedImage(url),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
