import 'package:flutter/material.dart';

import 'app_colors.dart';

/// GlassFlow elevation / shadow tokens — Violet Dusk soft premium shadows.
abstract final class AppShadows {
  static List<BoxShadow> get card => AppColors.isLight
      ? const [
          BoxShadow(
            color: Color(0x14502D55), // rgba(80,45,85,0.08)
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ];

  static List<BoxShadow> get modal => AppColors.isLight
      ? const [
          BoxShadow(
            color: Color(0x26502D55), // rgba(80,45,85,0.15)
            blurRadius: 50,
            offset: Offset(0, 20),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 40,
            offset: Offset(0, 16),
          ),
        ];

  static List<BoxShadow> get activeGlow => [
        BoxShadow(
          color: AppColors.activeGlow,
          blurRadius: 16,
          offset: Offset.zero,
        ),
      ];

  static List<BoxShadow> get dropdown => AppColors.isLight
      ? const [
          BoxShadow(
            color: Color(0x1A502D55),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ];

  static List<BoxShadow> get focus => AppColors.isLight
      ? const [
          BoxShadow(
            color: Color(0x26935073), // rgba(147,80,115,0.15)
            blurRadius: 0,
            spreadRadius: 3,
          ),
        ]
      : [
          BoxShadow(
            color: AppColors.focusRing,
            blurRadius: 0,
            spreadRadius: 2,
          ),
        ];
}
