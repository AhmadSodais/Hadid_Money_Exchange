import 'package:flutter/widgets.dart';

import '../utils/gf_scale.dart';

/// GlassFlow spacing tokens.
///
/// Base values are design pixels at [GfScale.referenceWidth] ×
/// [GfScale.referenceHeight]. Prefer the `*Of(context)` helpers for control
/// heights, table rows, and sidebar widths so they track window scale.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  static const double pagePadding = 24;
  static const double sectionGap = 20;
  static const double cardGap = 16;

  /// Default height for text fields, dropdowns, search, and primary buttons.
  /// Keep dialog and page form controls on this single value.
  static const double controlHeight = 40;
  static const double tableRowHeight = 56;

  static const double sidebarExpanded = 260;
  static const double sidebarCollapsed = 76;

  /// Gap between the docked sidebar and the window edges / page content.
  static const double sidebarInset = 10;

  /// Soft minimum for desktop window chrome; UI still adapts below this.
  static const double minWindowWidth = 900;
  static const double minWindowHeight = 640;

  static const double dropdownMaxHeight = 280;
  static const double drawerWidth = 420;

  static double controlHeightOf(BuildContext context) =>
      GfScale.s(context, controlHeight);

  static double tableRowHeightOf(BuildContext context) =>
      GfScale.s(context, tableRowHeight);

  /// Sidebar widths stay fixed — do not scale (collapsed logo/padding floor).
  static double sidebarExpandedOf(BuildContext context) => sidebarExpanded;

  static double sidebarCollapsedOf(BuildContext context) => sidebarCollapsed;
}
