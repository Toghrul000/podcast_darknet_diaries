import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:io';

class ImageItem extends StatelessWidget {
  final String imageLink;
  final double height;
  final double width;

  const ImageItem({
    required this.imageLink,
    required this.height,
    required this.width,
    super.key,
  });

  bool _isLocalFile(String path) {
    return File(path).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    String path = imageLink;
    if (path.startsWith('file://')) {
      path = path.replaceFirst('file://', '');
    }
    if (_isLocalFile(path)) {
      return Image.file(
        File(path),
        height: height,
        width: width,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
      );
    } else {
      return CachedNetworkImage(
        imageUrl: imageLink,
        placeholder: (context, url) => const CircularProgressIndicator(color: Colors.red),
        errorWidget: (context, url, error) => const Icon(Icons.error),
        height: height,
        width: width,
        fit: BoxFit.cover,
      );
    }
  }
}