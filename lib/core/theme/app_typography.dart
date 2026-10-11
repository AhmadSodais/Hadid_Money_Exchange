import 'package:flutter/material.dart';
import 'package:pos_general/core/constants/app_font.dart';

import 'app_colors.dart';

/// GlassFlow typography tokens.
///
/// Font family follows the active locale:
/// - `fa` → [AppFontFamily.yekanBakh]
/// - `ps` → [AppFontFamily.vazirmatn]
/// - `en` (default) → [AppFontFamily.inter]
///
/// Call [applyLanguage] whenever the locale changes (done from [MaterialApp]).
abstract final class AppTypography {
  static String _activeFontFamily = AppFontFamily.inter;

  static String fontFamilyByLanguage(String langCode) {
    switch (langCode) {
      case 'fa':
        return AppFontFamily.yekanBakh;
      case 'ps':
        return AppFontFamily.vazirmatn;
      case 'en':
      default:
        return AppFontFamily.inter;
    }
  }

  static String fontFamilyOf(BuildContext context) {
    return fontFamilyByLanguage(Localizations.localeOf(context).languageCode);
  }

  /// Currently selected UI font. Kept in sync from [applyLanguage].
  static String get fontFamily => _activeFontFamily;

  static void applyLanguage(String langCode) {
    _activeFontFamily = fontFamilyByLanguage(langCode);
  }

  /// Forces the active locale font onto any [TextStyle] (Text / TextField / hints).
  static TextStyle localize(
    TextStyle style, {
    BuildContext? context,
  }) {
    final family =
        context != null ? fontFamilyOf(context) : _activeFontFamily;
    return style.copyWith(fontFamily: family);
  }

  /// Safe style for editable fields when [style] may be null or missing a family.
  static TextStyle fieldStyle({
    BuildContext? context,
    TextStyle? style,
  }) {
    final base = style ?? body;
    return localize(base, context: context);
  }

  static TextStyle _style({
    required double fontSize,
    required FontWeight fontWeight,
    Color? color,
    double height = 1.4,
  }) {
    return TextStyle(
      fontFamily: _activeFontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  static TextStyle get display => _style(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.2,
      );

  static TextStyle get pageTitle => _style(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.2,
      );

  static TextStyle get sectionTitle => _style(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get body => _style(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyMedium => _style(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodySemiBold => _style(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get subtitle => _style(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  static TextStyle get caption => _style(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
        height: 1.35,
      );

  static TextStyle get label => _style(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.35,
      );

  static TextStyle get kpiValue => _style(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.15,
      );

  static TextStyle get button => _style(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.2,
      );

  static TextStyle get brand => _style(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
        height: 1.2,
      );

  /// Full Material [TextTheme] for the given language.
  static TextTheme textThemeFor(
    String langCode, {
    required Brightness brightness,
  }) {
    final family = fontFamilyByLanguage(langCode);
    final base = brightness == Brightness.dark
        ? Typography.material2021(platform: TargetPlatform.windows).white
        : Typography.material2021(platform: TargetPlatform.windows).black;
    return base.apply(
      fontFamily: family,
      bodyColor: brightness == Brightness.dark
          ? AppColors.darkPalette.textPrimary
          : AppColors.lightTextPrimary,
      displayColor: brightness == Brightness.dark
          ? AppColors.darkPalette.textPrimary
          : AppColors.lightTextPrimary,
    );
  }
}
