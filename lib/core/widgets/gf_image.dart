import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

class GfImage extends StatelessWidget {
  const GfImage({
    super.key,
    this.path,
    this.width = 40,
    this.height = 40,
    this.borderRadius = AppRadius.md,
    this.fit = BoxFit.cover,
  });

  final String? path;
  final double width;
  final double height;
  final double borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final hasFile = path != null && path!.isNotEmpty && File(path!).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: width,
        height: height,
        color: AppColors.input,
        child: hasFile
            ? Image.file(File(path!), width: width, height: height, fit: fit)
            : Icon(Icons.layers_outlined, color: AppColors.textMuted, size: 20),
      ),
    );
  }
}
