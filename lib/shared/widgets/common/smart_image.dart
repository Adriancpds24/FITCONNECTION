import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/utils/url_utils.dart';

Uint8List? _decodeDataImage(String imageUrl) {
  if (!imageUrl.startsWith('data:image/')) {
    return null;
  }

  final commaIndex = imageUrl.indexOf(',');
  if (commaIndex == -1 || commaIndex >= imageUrl.length - 1) {
    return null;
  }

  try {
    return base64Decode(imageUrl.substring(commaIndex + 1));
  } catch (_) {
    return null;
  }
}

class SmartImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;

  const SmartImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = imageUrl.trim();
    if (normalizedUrl.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: errorWidget ??
            const Center(child: Icon(Icons.person, color: Colors.grey)),
      );
    }

    final bytes = _decodeDataImage(imageUrl);
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (ctx, err, st) =>
            errorWidget ??
            const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
      );
    }

    final fullUrl = UrlUtils.resolveFullUrl(imageUrl);

    if (fullUrl.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: errorWidget ??
            const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
      );
    }

    return CachedNetworkImage(
      imageUrl: fullUrl,
      fit: fit,
      width: width,
      height: height,
      placeholder: (context, url) =>
          placeholder ??
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorWidget: (context, url, error) =>
          errorWidget ??
          const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
    );
  }
}
