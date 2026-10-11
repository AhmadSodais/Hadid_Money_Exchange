import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/gf_scroll_behavior.dart';

/// Shared visual tokens for invoice view + edit dialogs (ERP SaaS style).
///
/// Colors follow [AppColors] so light/dark mode stay consistent.
abstract final class OrderDetailDialogStyle {
  static const double maxWidth = 550;
  static const double minHeight = 600;
  static const double maxHeight = 700;

  /// Dialog shell corner radius.
  static const double radius = 8;

  /// Shared radius for cards, inputs, chips, and buttons inside dialogs.
  static const double controlRadius = 8;
  static const double cardRadius = controlRadius;

  /// Standard form / filter / footer control height (matches [AppSpacing.controlHeight]).
  static const double fieldHeight = AppSpacing.controlHeight;

  /// Compact inline inputs — same height so rows stay aligned with dropdowns.
  static const double inlineFieldHeight = AppSpacing.controlHeight;

  static const double borderWidth = 1;

  static const EdgeInsets padding = EdgeInsets.fromLTRB(24, 20, 24, 20);

  /// Frame padding for dialogs with a [scrollBody]: the sides are left to
  /// [sidePadding] so the scroll area can span the full dialog width.
  static const EdgeInsets framePadding = EdgeInsets.symmetric(vertical: 20);

  /// Horizontal inset for the fixed header / footer around a [scrollBody].
  static const EdgeInsets sidePadding = EdgeInsets.symmetric(horizontal: 24);

  /// Scroll area between a dialog's fixed header and footer (use with
  /// [framePadding]). The side padding is inside the scroll view, so content
  /// scrolls to the dialog edges and the scrollbar sits in the margin.
  static Widget scrollBody({
    ScrollController? controller,
    required Widget child,
  }) {
    return ScrollConfiguration(
      behavior: const GfScrollBehavior(reserveGutter: false),
      child: SingleChildScrollView(
        controller: controller,
        padding: sidePadding,
        child: ScrollConfiguration(
          behavior: const GfScrollBehavior(),
          child: child,
        ),
      ),
    );
  }

  /// Fixed [header], [scrollBody] filling the remaining height, fixed
  /// [footer]. Use with [framePadding].
  static Widget scrollLayout({
    required List<Widget> header,
    required Widget body,
    List<Widget> footer = const [],
    ScrollController? controller,
  }) {
    Widget fixed(List<Widget> children) => Padding(
          padding: sidePadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fixed(header),
        Expanded(child: scrollBody(controller: controller, child: body)),
        if (footer.isNotEmpty) fixed(footer),
      ],
    );
  }

  static Color get surface => AppColors.modal;
  static Color get navy => AppColors.textPrimary;
  static Color get muted => AppColors.textMuted;
  static Color get border => AppColors.border;
  static Color get tableHeaderBg => AppColors.tableHeader;
  static Color get iconBg => AppColors.primarySoft;
  static Color get accent => AppColors.primary;
  /// Text/icon color on [accent] fills (dark on lime in dark mode).
  static Color get onAccent => AppColors.onPrimary;
  static Color get totalHighlight => AppColors.primarySoft;
  static Color get success => AppColors.success;
  static Color get successBg => AppColors.successBg;
  static Color get danger => AppColors.error;
  static Color get paleBlue => AppColors.primarySoft;

  static const EdgeInsets cardPadding = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 12,
  );

  static const SizedBox sectionSpace = SizedBox(height: 16);
  static const SizedBox smallSpace = SizedBox(height: 8);
  static const SizedBox rowGap = SizedBox(width: 12);
  static const SizedBox inlineGap = SizedBox(width: 8);

  static BorderSide get borderSide =>
      BorderSide(color: border, width: borderWidth);

  static BorderSide get focusBorderSide =>
      BorderSide(color: accent, width: borderWidth);

  static BorderRadius get controlBorderRadius =>
      BorderRadius.circular(controlRadius);

  static OutlineInputBorder get outlineBorder => OutlineInputBorder(
        borderRadius: controlBorderRadius,
        borderSide: borderSide,
      );

  static OutlineInputBorder get outlineFocusBorder => OutlineInputBorder(
        borderRadius: controlBorderRadius,
        borderSide: focusBorderSide,
      );

  static BoxDecoration get container => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppColors.isLight ? 0.08 : 0.4),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      );

  static BoxDecoration get card => BoxDecoration(
        color: surface,
        borderRadius: controlBorderRadius,
        border: Border.all(color: border, width: borderWidth),
      );

  static BoxDecoration get chip => BoxDecoration(
        color: tableHeaderBg,
        borderRadius: controlBorderRadius,
        border: Border.all(color: border, width: borderWidth),
      );

  static InputDecoration fieldDecoration({
    String? hint,
    IconData? prefixIcon,
    bool dense = false,
  }) {
    final h = dense ? inlineFieldHeight : fieldHeight;
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: dense ? tableHeaderBg : surface,
      contentPadding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 12,
        vertical: dense ? 10 : 11,
      ),
      hintStyle: AppTypography.localize(
        AppTypography.body.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: muted,
        ),
      ),
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, size: 18, color: muted),
      prefixIconConstraints: prefixIcon == null
          ? null
          : BoxConstraints(minWidth: 40, minHeight: h - 2),
      border: outlineBorder,
      enabledBorder: outlineBorder,
      focusedBorder: outlineFocusBorder,
      disabledBorder: outlineBorder,
    );
  }

  /// Use inside a parent with fixed [fieldHeight] / [inlineFieldHeight].
  static InputDecoration fieldDecorationConstrained({
    String? hint,
    IconData? prefixIcon,
    bool dense = false,
  }) {
    return fieldDecoration(
      hint: hint,
      prefixIcon: prefixIcon,
      dense: dense,
    ).copyWith(
      contentPadding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 12,
        vertical: 0,
      ),
    );
  }
}
