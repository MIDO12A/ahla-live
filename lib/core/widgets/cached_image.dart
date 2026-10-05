import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/r.dart';
import '../../screens/room/widgets/svga_player.dart';

ImageProvider cachedNetworkImageProvider(String url) {
  if (url.isEmpty) return R.transparentImage();
  if (url.startsWith('http://') || url.startsWith('https://')) {
    if (detectAssetType(url) == AssetType.svga) {
      return MemoryImage(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]));
    }
    return CachedNetworkImageProvider(url);
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
    final safeUrl = url.trim();
    if (safeUrl.isEmpty) {
      return Image(image: R.transparentImage(), width: width, height: height, fit: fit);
    }
    if (safeUrl.startsWith('http://') || safeUrl.startsWith('https://')) {
      if (detectAssetType(safeUrl) == AssetType.svga) {
        return SvgaPlayer(assetPath: safeUrl, width: width ?? 100, height: height ?? 100, fit: fit);
      }
      return CachedNetworkImage(
        imageUrl: safeUrl,
        width: width,
        height: height,
        fit: fit,
        color: color,
        placeholder: placeholder != null ? (ctx, u) => placeholder!(ctx, u) : null,
        errorWidget: error != null
            ? (ctx, u, err) => error!(ctx, err, null)
            : (ctx, u, err) {
                final lower = u.toLowerCase();
                if (lower.contains('avatar') || lower.contains('user') || lower.contains('photo') || lower.contains('profile') || lower.contains('head')) {
                  return Image.asset(R.avaBoy, width: width, height: height, fit: fit);
                }
                return Container(
                  width: width,
                  height: height,
                  color: Colors.transparent,
                );
              },
      );
    }
    if (safeUrl.startsWith('/') || safeUrl.startsWith('file://')) {
      final filePath = safeUrl.startsWith('file://') ? safeUrl.replaceFirst('file://', '') : safeUrl;
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
    if (detectAssetType(safeUrl) == AssetType.svga) {
      return SvgaPlayer(assetPath: safeUrl, width: width ?? 100, height: height ?? 100, fit: fit);
    }
    final safeAsset = safeUrl.startsWith('assets/') ? safeUrl : (safeUrl.contains('/') ? 'assets/$safeUrl' : safeUrl);
    return Image.asset(
      safeAsset,
      width: width,
      height: height,
      fit: fit,
      color: color,
      errorBuilder: (context, err, stack) {
        if (error != null) return error!(context, err, stack);
        final lower = safeUrl.toLowerCase();
        if (lower.contains('avatar') || lower.contains('user') || lower.contains('photo') || lower.contains('profile') || lower.contains('head')) {
          return Image.asset(R.avaBoy, width: width, height: height, fit: fit);
        }
        return const SizedBox();
      },
    );
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
    final safeUrl = url.trim();
    if (safeUrl.isEmpty) {
      return Image(image: R.transparentImage(), width: width, height: height, fit: fit);
    }
    if (safeUrl.startsWith('http://') || safeUrl.startsWith('https://')) {
      if (detectAssetType(safeUrl) == AssetType.svga) {
        return SvgaPlayer(assetPath: safeUrl, width: width ?? 100, height: height ?? 100, fit: fit);
      }
      return CachedNetworkImage(
        imageUrl: safeUrl,
        width: width,
        height: height,
        fit: fit,
        placeholder: placeholder != null ? (ctx, u) => placeholder!(ctx, u) : null,
        errorWidget: error != null
            ? (ctx, u, err) => error!(ctx, u, err)
            : (ctx, u, err) {
                final lower = u.toLowerCase();
                if (lower.contains('avatar') || lower.contains('user') || lower.contains('photo') || lower.contains('profile') || lower.contains('head')) {
                  return Image.asset(R.avaBoy, width: width, height: height, fit: fit);
                }
                return Container(
                  width: width,
                  height: height,
                  color: Colors.transparent,
                );
              },
      );
    }
    if (safeUrl.startsWith('/') || safeUrl.startsWith('file://')) {
      final filePath = safeUrl.startsWith('file://') ? safeUrl.replaceFirst('file://', '') : safeUrl;
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
    if (detectAssetType(safeUrl) == AssetType.svga) {
      return SvgaPlayer(assetPath: safeUrl, width: width ?? 100, height: height ?? 100, fit: fit);
    }
    final safeAsset = safeUrl.startsWith('assets/') ? safeUrl : (safeUrl.contains('/') ? 'assets/$safeUrl' : safeUrl);
    return Image.asset(
      safeAsset,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, err, stack) {
        if (error != null) return error!(context, url, err);
        final lower = safeUrl.toLowerCase();
        if (lower.contains('avatar') || lower.contains('user') || lower.contains('photo') || lower.contains('profile') || lower.contains('head')) {
          return Image.asset(R.avaBoy, width: width, height: height, fit: fit);
        }
        return const SizedBox();
      },
    );
  }
}
