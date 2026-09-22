import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/widgets/cached_image.dart';

class NinePatchImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget Function(BuildContext, String)? errorWidget;

  const NinePatchImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.fill,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final ImageProvider provider = imageUrl.startsWith('assets/')
        ? AssetImage(imageUrl) as ImageProvider
        : cachedNetworkImageProvider(imageUrl);
    return _NinePatchImage(
      imageProvider: provider,
      fit: fit,
      errorWidget: errorWidget,
      imageUrl: imageUrl,
    );
  }
}

class _NinePatchImage extends StatefulWidget {
  final ImageProvider imageProvider;
  final BoxFit fit;
  final Widget Function(BuildContext, String)? errorWidget;
  final String imageUrl;

  const _NinePatchImage({
    required this.imageProvider,
    required this.fit,
    this.errorWidget,
    required this.imageUrl,
  });

  @override
  State<_NinePatchImage> createState() => _NinePatchImageState();
}

class _NinePatchImageState extends State<_NinePatchImage> {
  ui.Image? _image;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(_NinePatchImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final stream = widget.imageProvider.resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image?>();
    stream.addListener(
      ImageStreamListener(
        (imageInfo, _) {
          completer.complete(imageInfo.image);
        },
        onError: (_, __) => completer.complete(null),
      ),
    );
    final image = await completer.future;
    if (mounted) setState(() { _image = image; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _image == null) {
      if (widget.errorWidget != null) return widget.errorWidget!(context, widget.imageUrl);
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = _image!.width.toDouble();
        final h = _image!.height.toDouble();

        final srcRect = Rect.fromLTWH(0, 0, w, h);

        final dstRect = Offset.zero & Size(constraints.maxWidth, constraints.maxHeight);

        return CustomPaint(
          size: dstRect.size,
          painter: _ImagePainter(_image!, srcRect, dstRect),
        );
      },
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  final Rect srcRect;
  final Rect dstRect;

  _ImagePainter(this.image, this.srcRect, this.dstRect);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.srcRect != srcRect ||
      oldDelegate.dstRect != dstRect;
}
