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
    // Check if the path is a local file path
    return File(path).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocalFile(imageLink)) {
      return Image.file(
        File(imageLink),
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