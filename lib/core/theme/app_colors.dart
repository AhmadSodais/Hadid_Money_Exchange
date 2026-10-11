import 'package:flutter/material.dart';

/// User-selectable app theme. Both dark variants share [ThemeMode.dark] and
/// differ only in their [AppDarkPalette].
enum AppThemeVariant {
  light,
  dark,
  hadid;

  static AppThemeVariant parse(String? key) => AppThemeVariant.values
      .firstWhere((v) => v.name == key, orElse: () => AppThemeVariant.light);

  bool get isLight => this == AppThemeVariant.light;

  Brightness get brightness => isLight ? Brightness.light : Brightness.dark;

  ThemeMode get themeMode => isLight ? ThemeMode.light : ThemeMode.dark;

  AppDarkPalette get darkPalette => this == AppThemeVariant.hadid
      ? AppDarkPalette.hadid
      : AppDarkPalette.lime;
}

/// Color set used while the app is dark.
@immutable
class AppDarkPalette {
  const AppDarkPalette({
    required this.background,
    required this.sidebar,
    required this.card,
    required this.modal,
    required this.input,
    required this.softSurface,
    required this.primary,
    required this.onPrimary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.divider,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.hover,
    required this.activeGlow,
    required this.focusRing,
  });

  final Color background;
  final Color sidebar;
  final Color card;
  final Color modal;
  final Color input;
  final Color softSurface;
  final Color primary;
  final Color onPrimary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color divider;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color hover;
  final Color activeGlow;
  final Color focusRing;

  /// Charcoal + lime (original dark theme).
  static const lime = AppDarkPalette(
    background: AppColors.darkBackground,
    sidebar: AppColors.darkSidebar,
    card: AppColors.darkCard,
    modal: AppColors.darkModal,
    input: AppColors.darkInput,
    softSurface: AppColors.darkSoftSurface,
    primary: AppColors.darkPrimary,
    onPrimary: AppColors.darkOnPrimary,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textMuted: AppColors.darkTextMuted,
    border: AppColors.darkBorder,
    divider: AppColors.darkDivider,
    success: AppColors.darkSuccess,
    warning: AppColors.darkWarning,
    error: AppColors.darkError,
    info: AppColors.darkInfo,
    hover: AppColors.darkHover,
    activeGlow: AppColors.darkActiveGlow,
    focusRing: AppColors.darkFocusRing,
  );

  /// Deep navy + cyan / mint, taken from the Hadid logo and About page.
  static const hadid = AppDarkPalette(
    background: Color(0xFF061826),
    sidebar: Color(0xFF071C2D),
    card: Color(0xFF0A2336),
    modal: Color(0xFF0F2C42),
    input: Color(0xFF081E2F),
    softSurface: Color(0xFF0D283C),
    primary: Color(0xFF2FD6D8),
    onPrimary: Color(0xFF04212C),
    textPrimary: Color(0xFFEAF7F7),
    textSecondary: Color(0xFF93ADBA),
    textMuted: Color(0xFF68848F),
    border: Color(0x1F8EF0C4),
    divider: Color(0x148EF0C4),
    success: Color(0xFF5EE3A6),
    warning: Color(0xFFF6BE7A),
    error: Color(0xFFFF5D6C),
    info: Color(0xFF5DB8F5),
    hover: Color(0x1A27D3DD),
    activeGlow: Color(0x3327D3DD),
    focusRing: Color(0x6627D3DD),
  );
}

/// GlassFlow design color tokens — Violet Dusk (light) + a dark palette
/// (charcoal lime or Hadid navy).
///
/// Semantic getters (`background`, `primary`, …) follow the active brightness
/// set via [applyBrightness] and the palette set via [applyVariant]. Use
/// `light*` consts / [darkPalette] when building [ThemeData].
abstract final class AppColors {
  static bool _isLight = true;
  static AppDarkPalette _dark = AppDarkPalette.lime;

  /// Call from [MaterialApp.builder] whenever the theme brightness changes.
  static void applyBrightness(Brightness brightness) {
    _isLight = brightness == Brightness.light;
  }

  /// Applies both brightness and dark palette for [variant].
  static void applyVariant(AppThemeVariant variant) {
    _isLight = variant.isLight;
    _dark = variant.darkPalette;
  }

  static void applyDarkPalette(AppDarkPalette palette) {
    _dark = palette;
  }

  static bool get isLight => _isLight;

  /// Active dark palette (used whenever the app is dark).
  static AppDarkPalette get darkPalette => _dark;

  static Color backgroundFor(AppThemeVariant variant) =>
      variant.isLight ? lightBackground : variant.darkPalette.background;

  // ── Dark palette (lime / charcoal) ─────────────────────────────────────
  static const Color darkBackground = Color(0xFF061114);
  static const Color darkSidebar = Color(0xFF07161A);
  static const Color darkCard = Color(0xFF0B171A);
  static const Color darkModal = Color(0xFF111B1E);
  static const Color darkInput = Color(0xFF0B1316);
  static const Color darkPrimary = Color(0xFFC8FF00);
  static const Color darkOnPrimary = Color(0xFF101500);
  static const Color darkTextPrimary = Color(0xFFF4F7F5);
  static const Color darkTextSecondary = Color(0xFF8F9A9C);
  static const Color darkTextMuted = Color(0xFF687477);
  static const Color darkBorder = Color(0x1AFFFFFF);
  static const Color darkDivider = Color(0x14FFFFFF);
  static const Color darkSuccess = Color(0xFF78D64B);
  static const Color darkWarning = Color(0xFFF5B700);
  static const Color darkError = Color(0xFFFF4D3D);
  static const Color darkInfo = Color(0xFF56B4E9);
  static const Color darkHover = Color(0x14FFFFFF);
  static const Color darkActiveGlow = Color(0x33C8FF00);
  static const Color darkFocusRing = Color(0x66C8FF00);
  static const Color darkSoftSurface = Color(0xFF0E1A1E);

  // ── Light palette — Violet Dusk ────────────────────────────────────────
  // Primary scale
  static const Color lightPrimary900 = Color(0xFF502D55);
  static const Color lightPrimary800 = Color(0xFF643765);
  static const Color lightPrimary700 = Color(0xFF7A4477);
  static const Color lightPrimary600 = Color(0xFF935073);
  static const Color lightPrimary500 = Color(0xFFA95D82);

  static const Color lightBackground = Color(0xFFF8F4E9);
  static const Color lightBackgroundEnd = Color(0xFFF6E8EF);
  static const Color lightSidebar = Color(0xFFFFF9F2);
  static const Color lightCard = Color(0xFFFFF9F2);
  static const Color lightSurface = Color(0xFFF6E8EF);
  static const Color lightModal = Color(0xFFFFF9F2);
  static const Color lightInput = Color(0xFFFFF9F2);
  static const Color lightPrimary = lightPrimary600;
  static const Color lightPrimaryHover = lightPrimary700;
  static const Color lightAccent = lightPrimary500;
  static const Color lightPrimarySoft = Color(0xFFF6E8EF);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF2D1933);
  static const Color lightTextSecondary = Color(0xFF6F6073);
  static const Color lightTextMuted = Color(0xFFA89CA8);
  static const Color lightBorder = Color(0xFFE6D9E1);
  static const Color lightInputBorder = Color(0xFFE6D9E1);
  static const Color lightBorderActive = lightPrimary600;
  static const Color lightSecondaryBorder = Color(0xFFDCC9D7);
  static const Color lightDivider = Color(0xFFEFE5DD);
  static const Color lightSuccess = Color(0xFF218739);
  static const Color lightSuccessBg = Color(0xFFDDF3E4);
  static const Color lightWarning = Color(0xFFB76A00);
  static const Color lightWarningBg = Color(0xFFFFF1D8);
  static const Color lightError = Color(0xFFC43D55);
  static const Color lightErrorBg = Color(0xFFFCE3E7);
  static const Color lightInfo = Color(0xFF643765);
  static const Color lightInfoBg = Color(0xFFE8E1F4);
  static const Color lightHover = Color(0x26A95D82);
  static const Color lightActiveGlow = Color(0x26935073);
  static const Color lightFocusRing = Color(0x26935073);
  static const Color lightTableHeader = Color(0xFFF6E8EF);
  static const Color lightRowHover = Color(0xFFF8EEF3);
  static const Color lightUploadBg = Color(0xFFF6E8EF);
  static const Color lightUploadBorder = Color(0xFFDCC9D7);
  static const Color lightDangerZoneBg = Color(0xFFFCEBEC);
  static const Color lightDangerZoneBorder = Color(0xFFF1B8C2);
  static const Color lightIcon = Color(0xFF6F6073);

  // Legacy aliases used by ThemeData builders
  static const Color lightPrimaryDark = lightPrimaryHover;

  // ── Semantic (theme-aware) ─────────────────────────────────────────────
  static Color get background => _isLight ? lightBackground : _dark.background;
  static Color get backgroundEnd =>
      _isLight ? lightBackgroundEnd : _dark.background;
  static Color get sidebar => _isLight ? lightSidebar : _dark.sidebar;
  static Color get card => _isLight ? lightCard : _dark.card;
  static Color get modal => _isLight ? lightModal : _dark.modal;
  static Color get input => _isLight ? lightInput : _dark.input;
  static Color get surface => _isLight ? lightSurface : _dark.softSurface;

  static Color get primary => _isLight ? lightPrimary : _dark.primary;
  static Color get primaryHover => _isLight
      ? lightPrimaryHover
      : Color.lerp(_dark.primary, Colors.black, 0.12)!;
  static Color get accent => _isLight ? lightAccent : _dark.primary;
  static Color get primarySoft =>
      _isLight ? lightPrimarySoft : _dark.primary.withValues(alpha: 0.18);

  /// Text/icon color on primary-filled controls.
  static Color get primaryDarkText =>
      _isLight ? lightOnPrimary : _dark.onPrimary;
  static Color get onPrimary => primaryDarkText;

  static Color get textPrimary =>
      _isLight ? lightTextPrimary : _dark.textPrimary;
  static Color get textSecondary =>
      _isLight ? lightTextSecondary : _dark.textSecondary;
  static Color get textMuted => _isLight ? lightTextMuted : _dark.textMuted;

  static Color get border => _isLight ? lightBorder : _dark.border;
  static Color get inputBorder => _isLight ? lightInputBorder : _dark.border;
  static Color get borderActive => _isLight ? lightBorderActive : _dark.primary;
  static Color get secondaryBorder =>
      _isLight ? lightSecondaryBorder : _dark.border;
  static Color get divider => _isLight ? lightDivider : _dark.divider;

  static Color get success => _isLight ? lightSuccess : _dark.success;
  static Color get warning => _isLight ? lightWarning : _dark.warning;
  static Color get error => _isLight ? lightError : _dark.error;
  static Color get info => _isLight ? lightInfo : _dark.info;

  static Color get successBg =>
      _isLight ? lightSuccessBg : _dark.success.withValues(alpha: 0.16);
  static Color get warningBg =>
      _isLight ? lightWarningBg : _dark.warning.withValues(alpha: 0.16);
  static Color get errorBg =>
      _isLight ? lightErrorBg : _dark.error.withValues(alpha: 0.16);
  static Color get infoBg =>
      _isLight ? lightInfoBg : _dark.info.withValues(alpha: 0.16);

  static Color get hover => _isLight ? lightHover : _dark.hover;
  static Color get activeGlow => _isLight ? lightActiveGlow : _dark.activeGlow;
  static Color get focusRing => _isLight ? lightFocusRing : _dark.focusRing;

  static Color get tableHeader => _isLight ? lightTableHeader : _dark.input;
  static Color get rowHover => _isLight ? lightRowHover : _dark.hover;
  static Color get uploadBg => _isLight ? lightUploadBg : _dark.input;
  static Color get uploadBorder => _isLight ? lightUploadBorder : _dark.border;
  static Color get dangerZoneBg =>
      _isLight ? lightDangerZoneBg : _dark.error.withValues(alpha: 0.08);
  static Color get dangerZoneBorder =>
      _isLight ? lightDangerZoneBorder : _dark.error.withValues(alpha: 0.35);
  static Color get icon => _isLight ? lightIcon : _dark.textSecondary;

  // Charts — Violet Dusk accents
  static const Color chartPurple = Color(0xFF935073);
  static const Color chartPink = Color(0xFFA95D82);
  static const Color chartBlue = Color(0xFF643765);
  static const Color chartYellow = Color(0xFFD99A32);
  static const Color chartOlive = Color(0xFF4E9F65);
  static const Color chartLightSecondary = Color(0xFF502D55);
  static const Color chartLightSuccess = Color(0xFF4E9F65);
}
