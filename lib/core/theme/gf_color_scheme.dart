import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Simple helper to mimic project's earlier `withValues(alpha: ...)` API.
extension ColorValues on Color {
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    return withAlpha((alpha * 255).clamp(0, 255).toInt());
  }
}

class GfColorScheme {
  const GfColorScheme({
    required this.primary,
    required this.onPrimary,
    required this.primarySoft,
    required this.input,
    required this.card,
    required this.modal,
    required this.surface,
    required this.background,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.divider,
    required this.hover,
    required this.activeGlow,
    required this.focusRing,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  final Color primary;
  final Color onPrimary;
  final Color primarySoft;
  final Color input;
  final Color card;
  final Color modal;
  final Color surface;
  final Color background;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color divider;
  final Color hover;
  final Color activeGlow;
  final Color focusRing;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  factory GfColorScheme.fromTheme(Brightness brightness) {
    final light = brightness == Brightness.light;
    final d = AppColors.darkPalette;
    return GfColorScheme(
      primary: light ? AppColors.lightPrimary : d.primary,
      onPrimary: light ? AppColors.lightOnPrimary : d.onPrimary,
      primarySoft: light ? AppColors.lightPrimarySoft : d.activeGlow,
      input: light ? AppColors.lightInput : d.input,
      card: light ? AppColors.lightCard : d.card,
      modal: light ? AppColors.lightModal : d.modal,
      surface: light ? AppColors.lightSurface : d.softSurface,
      background: light ? AppColors.lightBackground : d.background,
      textPrimary: light ? AppColors.lightTextPrimary : d.textPrimary,
      textSecondary: light ? AppColors.lightTextSecondary : d.textSecondary,
      textMuted: light ? AppColors.lightTextMuted : d.textMuted,
      border: light ? AppColors.lightBorder : d.border,
      divider: light ? AppColors.lightDivider : d.divider,
      hover: light ? AppColors.lightHover : d.hover,
      activeGlow: light ? AppColors.lightActiveGlow : d.activeGlow,
      focusRing: light ? AppColors.lightFocusRing : d.focusRing,
      success: light ? AppColors.lightSuccess : d.success,
      warning: light ? AppColors.lightWarning : d.warning,
      error: light ? AppColors.lightError : d.error,
      info: light ? AppColors.lightInfo : d.info,
    );
  }
}

extension GfThemeExtension on BuildContext {
  GfColorScheme get gf => GfColorScheme.fromTheme(Theme.of(this).brightness);
}
