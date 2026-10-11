import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Popup menu item with start-edge text alignment (LTR left / RTL right).
PopupMenuItem<T> gfPopupMenuItem<T>({
  required T value,
  required String label,
  TextStyle? style,
  bool enabled = true,
  bool danger = false,
}) {
  final color = danger ? AppColors.error : AppColors.textPrimary;
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        label,
        textAlign: TextAlign.start,
        style: (style ?? AppTypography.body).copyWith(color: color),
      ),
    ),
  );
}
