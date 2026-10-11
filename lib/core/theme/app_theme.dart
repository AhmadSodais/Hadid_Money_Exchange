import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// GlassFlow Material theme built from design tokens.
abstract final class AppDarkTheme {
  static ThemeData get dark => darkForLanguage('en');

  /// Dark UI in the active [AppColors.darkPalette].
  static ThemeData darkForLanguage(String langCode) {
    AppColors.applyBrightness(Brightness.dark);
    AppTypography.applyLanguage(langCode);
    final p = AppColors.darkPalette;
    final fontFamily = AppTypography.fontFamilyByLanguage(langCode);
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: p.background,
      colorScheme: ColorScheme.dark(
        primary: p.primary,
        onPrimary: p.onPrimary,
        secondary: p.success,
        surface: p.card,
        onSurface: p.textPrimary,
        error: p.error,
        outline: p.border,
      ),
    );

    return _applyControlFonts(
      base.copyWith(
        textTheme: base.textTheme.apply(
          fontFamily: fontFamily,
          bodyColor: p.textPrimary,
          displayColor: p.textPrimary,
        ),
        dividerColor: p.divider,
        dividerTheme: DividerThemeData(
          color: p.divider,
          thickness: 1,
          space: 1,
        ),
        cardTheme: CardThemeData(
          color: p.card,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
          margin: EdgeInsets.zero,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: p.modal,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.modal),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: p.modal,
          surfaceTintColor: Colors.transparent,
          textStyle: AppTypography.body.copyWith(color: p.textPrimary),
          labelTextStyle: WidgetStatePropertyAll(
            AppTypography.body.copyWith(color: p.textPrimary),
          ),
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.input,
            side: BorderSide(color: p.border),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: p.modal,
          contentTextStyle: AppTypography.body.copyWith(color: p.textPrimary),
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.input),
        ),
        tooltipTheme: TooltipThemeData(
          waitDuration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            color: p.modal,
            borderRadius: AppRadius.input,
            border: Border.all(color: p.border),
          ),
          textStyle: AppTypography.caption.copyWith(color: p.textPrimary),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: p.input,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: AppRadius.input,
            borderSide: BorderSide(color: p.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.input,
            borderSide: BorderSide(color: p.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.input,
            borderSide: BorderSide(color: p.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: AppRadius.input,
            borderSide: BorderSide(color: p.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: AppRadius.input,
            borderSide: BorderSide(color: p.error, width: 1.5),
          ),
          hintStyle: AppTypography.body.copyWith(color: p.textMuted),
          labelStyle: AppTypography.label.copyWith(color: p.textSecondary),
          errorStyle: AppTypography.caption.copyWith(color: p.error),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: p.primary,
            foregroundColor: p.onPrimary,
            elevation: 0,
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
            textStyle: AppTypography.button,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: p.textPrimary,
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            side: BorderSide(color: p.border),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
            textStyle: AppTypography.button,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: p.textSecondary,
            textStyle: AppTypography.button,
          ),
        ),
        iconTheme: IconThemeData(color: p.textSecondary, size: 20),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(
            p.textMuted.withValues(alpha: 0.5),
          ),
          radius: const Radius.circular(8),
          thickness: WidgetStateProperty.all(6),
        ),
      ),
      fontFamily,
      brightness: Brightness.dark,
    );
  }
}

abstract final class AppLightTheme {
  static ThemeData get light => lightForLanguage('en');

  /// GlassFlow Violet Dusk light UI.
  static ThemeData lightForLanguage(String langCode) {
    AppColors.applyBrightness(Brightness.light);
    AppTypography.applyLanguage(langCode);
    final fontFamily = AppTypography.fontFamilyByLanguage(langCode);
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightPrimary,
        onPrimary: AppColors.lightOnPrimary,
        secondary: AppColors.lightAccent,
        surface: AppColors.lightCard,
        onSurface: AppColors.lightTextPrimary,
        error: AppColors.lightError,
        outline: AppColors.lightBorder,
      ),
    );

    return _applyControlFonts(
      base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        bodyColor: AppColors.lightTextPrimary,
        displayColor: AppColors.lightTextPrimary,
      ),
      dividerColor: AppColors.lightDivider,
      dividerTheme: const DividerThemeData(
        color: AppColors.lightDivider,
        thickness: 1,
        space: 1,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.lightCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.lightModal,
        elevation: 12,
        shadowColor: Color(0x26502D55),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.modal),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.lightModal,
        surfaceTintColor: Colors.transparent,
        textStyle:
            AppTypography.body.copyWith(color: AppColors.lightTextPrimary),
        labelTextStyle: WidgetStatePropertyAll(
          AppTypography.body.copyWith(color: AppColors.lightTextPrimary),
        ),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.input,
          side: const BorderSide(color: AppColors.lightBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightInput,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: AppColors.lightInputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: AppColors.lightInputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide:
              const BorderSide(color: AppColors.lightPrimary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: AppColors.lightError),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide:
              const BorderSide(color: AppColors.lightError, width: 1.5),
        ),
        hintStyle:
            AppTypography.body.copyWith(color: AppColors.lightTextMuted),
        labelStyle:
            AppTypography.label.copyWith(color: AppColors.lightTextSecondary),
        errorStyle:
            AppTypography.caption.copyWith(color: AppColors.lightError),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.lightPrimary,
          foregroundColor: AppColors.lightOnPrimary,
          elevation: 0,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle: AppTypography.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.lightPrimary900,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: const BorderSide(color: AppColors.lightSecondaryBorder),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle: AppTypography.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.lightPrimary,
          textStyle: AppTypography.button,
        ),
      ),
      iconTheme: const IconThemeData(
        color: AppColors.lightIcon,
        size: 20,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: AppColors.lightTextPrimary,
          borderRadius: AppRadius.input,
        ),
        textStyle: AppTypography.caption.copyWith(color: Colors.white),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.lightTextPrimary,
        behavior: SnackBarBehavior.floating,
        contentTextStyle: AppTypography.body.copyWith(color: Colors.white),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.input),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(
          AppColors.lightTextMuted.withValues(alpha: 0.55),
        ),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(6),
      ),
      ),
      fontFamily,
      brightness: Brightness.light,
    );
  }
}

ThemeData _applyControlFonts(
  ThemeData theme,
  String fontFamily, {
  required Brightness brightness,
}) {
  final isDark = brightness == Brightness.dark;
  final p = AppColors.darkPalette;
  final textPrimary = isDark ? p.textPrimary : AppColors.lightTextPrimary;
  final textSecondary =
      isDark ? p.textSecondary : AppColors.lightTextSecondary;
  final textMuted = isDark ? p.textMuted : AppColors.lightTextMuted;
  final modal = isDark ? p.modal : AppColors.lightModal;
  final border = isDark ? p.border : AppColors.lightBorder;

  final button = AppTypography.button.copyWith(fontFamily: fontFamily);
  final body = AppTypography.body.copyWith(
    fontFamily: fontFamily,
    color: textPrimary,
  );
  final caption = AppTypography.caption.copyWith(
    fontFamily: fontFamily,
    color: textMuted,
  );
  final label = AppTypography.label.copyWith(
    fontFamily: fontFamily,
    color: textSecondary,
  );
  final section = AppTypography.sectionTitle.copyWith(
    fontFamily: fontFamily,
    color: textPrimary,
  );
  final subtitle = AppTypography.subtitle.copyWith(
    fontFamily: fontFamily,
    color: textSecondary,
  );
  final textTheme = theme.textTheme.apply(
    fontFamily: fontFamily,
    bodyColor: textPrimary,
    displayColor: textPrimary,
  );
  final primaryTextTheme = theme.primaryTextTheme.apply(
    fontFamily: fontFamily,
    bodyColor: textPrimary,
    displayColor: textPrimary,
  );

  final existingPopup = theme.popupMenuTheme;

  return theme.copyWith(
    textTheme: textTheme,
    primaryTextTheme: primaryTextTheme,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(textStyle: button),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll(button),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: (theme.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll(button),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (theme.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll(button),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(button),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: existingPopup.color ?? modal,
      surfaceTintColor: Colors.transparent,
      textStyle: body,
      labelTextStyle: WidgetStatePropertyAll(body),
      position: PopupMenuPosition.under,
      shape: existingPopup.shape ??
          RoundedRectangleBorder(
            borderRadius: AppRadius.input,
            side: BorderSide(color: border),
          ),
    ),
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: caption.copyWith(color: textSecondary),
      secondaryLabelStyle: caption,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: body,
      subtitleTextStyle: caption,
      leadingAndTrailingTextStyle: caption,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(textStyle: body),
    menuButtonTheme: MenuButtonThemeData(
      style: MenuItemButton.styleFrom(textStyle: body),
    ),
    navigationRailTheme: NavigationRailThemeData(
      selectedLabelTextStyle: label.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: caption,
    ),
    appBarTheme: AppBarTheme(
      titleTextStyle: section,
      toolbarTextStyle: body,
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: body.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: body,
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      titleTextStyle: section,
      contentTextStyle: subtitle,
    ),
    tooltipTheme: theme.tooltipTheme.copyWith(
      textStyle: (theme.tooltipTheme.textStyle ?? caption)
          .copyWith(fontFamily: fontFamily),
    ),
    snackBarTheme: theme.snackBarTheme.copyWith(
      contentTextStyle: (theme.snackBarTheme.contentTextStyle ?? body)
          .copyWith(fontFamily: fontFamily),
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      hintStyle: (theme.inputDecorationTheme.hintStyle ?? body)
          .copyWith(fontFamily: fontFamily),
      labelStyle: (theme.inputDecorationTheme.labelStyle ?? label)
          .copyWith(fontFamily: fontFamily),
      errorStyle: (theme.inputDecorationTheme.errorStyle ?? caption)
          .copyWith(fontFamily: fontFamily),
      helperStyle: caption.copyWith(fontFamily: fontFamily),
      floatingLabelStyle: label.copyWith(fontFamily: fontFamily),
      prefixStyle: body.copyWith(fontFamily: fontFamily),
      suffixStyle: body.copyWith(fontFamily: fontFamily),
      counterStyle: caption.copyWith(fontFamily: fontFamily),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: label.copyWith(fontWeight: FontWeight.w600),
      dataTextStyle: body,
    ),
  );
}

