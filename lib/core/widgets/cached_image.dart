import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../cache/encrypted_image_provider.dart';
import '../../config/r.dart';
import '../../screens/room/widgets/svga_player.dart';

ImageProvider cachedNetworkImageProvider(String url) {
  if (url.isEmpty) return R.transparentImage();
  if (url.startsWith('http://') || url.startsWith('https://')) {
    if (detectAssetType(url) == AssetType.svga) {
      return MemoryImage(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]));
    }
    return EncryptedImageProvider(url);
  }
  if (url.startsWith('/') || url.startsWith('file://')) {
    final filePath = url.startsWith('file://') ? url.replaceFirst('file://', '') : url;
    return FileImage(File(filePath));
  }
  if (url.startsWith('assets/')) {
    return AssetImage(url);
  }
  return R.transparentImage();
}

class CachedNetImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Color? color;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, Object, StackTrace?)? error;

  const CachedNetImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.color,
    this.placeholder,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Image(image: R.transparentImage(), width: width, height: height, fit: fit);
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      if (detectAssetType(url) == AssetType.svga) {
        return SvgaPlayer(assetPath: url, width: width ?? 100, height: height ?? 100, fit: fit);
      }
      return Image(
        image: EncryptedImageProvider(url),
        width: width,
        height: height,
        fit: fit,
        color: color,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          if (frame == null && placeholder != null) {
            return placeholder!(context, url);
          }
          return child;
        },
        errorBuilder: error,
      );
    }
    if (url.startsWith('/') || url.startsWith('file://')) {
      final filePath = url.startsWith('file://') ? url.replaceFirst('file://', '') : url;
      return Image.file(
        File(filePath),
        width: width,
        height: height,
        fit: fit,
        color: color,
        errorBuilder: (context, err, stack) {
          if (error != null) return error!(context, err, stack);
          return const SizedBox();
        },
      );
    }
    if (detectAssetType(url) == AssetType.svga) {
      return SvgaPlayer(assetPath: url, width: width ?? 100, height: height ?? 100, fit: fit);
    }
    return Image.asset(url, width: width, height: height, fit: fit, color: color);
  }
}

ImageProvider cachedImgProvider(String url) {
  return cachedNetworkImageProvider(url);
}

class CachedImg extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? error;

  const CachedImg(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Image(image: R.transparentImage(), width: width, height: height, fit: fit);
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      if (detectAssetType(url) == AssetType.svga) {
        return SvgaPlayer(assetPath: url, width: width ?? 100, height: height ?? 100, fit: fit);
      }
      return Image(
        image: EncryptedImageProvider(url),
        width: width,
        height: height,
        fit: fit,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          if (frame == null && placeholder != null) {
            return placeholder!(context, url);
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) {
          if (this.error != null) return this.error!(context, url, error);
          return const SizedBox();
        },
      );
    }
    if (url.startsWith('/') || url.startsWith('file://')) {
      final filePath = url.startsWith('file://') ? url.replaceFirst('file://', '') : url;
      return Image.file(
        File(filePath),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, err, stack) {
          if (error != null) return error!(context, url, err);
          return const SizedBox();
        },
      );
    }
    if (detectAssetType(url) == AssetType.svga) {
      return SvgaPlayer(assetPath: url, width: width ?? 100, height: height ?? 100, fit: fit);
    }
    return Image.asset(url, width: width, height: height, fit: fit);
  }
}
