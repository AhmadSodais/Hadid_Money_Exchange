import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'gf_scale.dart';

/// Layout sizes for dashboard chrome and widget grids.
enum GfLayoutSize { mobile, tablet, desktop }

/// Breakpoints and spacing used by the dashboard shell and overview widgets.
///
/// Measured against the **available content width** (window minus sidebar when
/// present), not always the full screen:
///
/// - Mobile: below 768
/// - Tablet: 768–1199
/// - Desktop: 1200+
abstract final class GfBreakpoints {
  static const double mobileMax = 768;
  static const double tabletMax = 1200;

  /// Auto-collapse the rail sidebar below this window width.
  static const double sidebarAutoCollapse = 1180;

  /// Hide the permanent sidebar and use a drawer below this width.
  static const double sidebarAsDrawer = 900;

  static GfLayoutSize ofWidth(double width) {
    if (width < mobileMax) return GfLayoutSize.mobile;
    if (width < tabletMax) return GfLayoutSize.tablet;
    return GfLayoutSize.desktop;
  }

  static GfLayoutSize of(BuildContext context) {
    return ofWidth(MediaQuery.sizeOf(context).width);
  }

  static GfLayoutMetrics metricsFor(
    GfLayoutSize size, {
    double uiScale = 1.0,
  }) =>
      GfLayoutMetrics(size, uiScale: uiScale);

  static GfLayoutMetrics metricsOf(BuildContext context) {
    final scope = GfLayoutScope.maybeOf(context);
    if (scope != null) return scope.metrics;
    return GfLayoutMetrics(of(context), uiScale: GfScale.of(context));
  }

  /// KPI columns for a given available width (content area).
  static int kpiColumnsForWidth(double width, {int itemCount = 4}) {
    final n = itemCount.clamp(1, 8);
    if (width >= 1100) return math.min(4, n);
    if (width >= 900) return math.min(3, n);
    if (width >= 560) return math.min(2, n);
    return 1;
  }

  /// Dialog max width clamped to the viewport.
  static double dialogMaxWidth(BuildContext context, {double preferred = 440}) {
    final w = MediaQuery.sizeOf(context).width;
    return math.min(preferred, w - 32).clamp(280.0, preferred);
  }

  /// Dialog max height clamped to the viewport.
  static double dialogMaxHeight(BuildContext context, {double preferred = 720}) {
    final h = MediaQuery.sizeOf(context).height;
    return math.min(preferred, h - 48).clamp(320.0, preferred);
  }
}

/// Spacing, columns, and split behavior for a [GfLayoutSize].
class GfLayoutMetrics {
  const GfLayoutMetrics(this.size, {this.uiScale = 1.0});

  final GfLayoutSize size;

  /// Window UI scale from [GfScale] (≤ 1 on smaller screens).
  final double uiScale;

  bool get isMobile => size == GfLayoutSize.mobile;
  bool get isTablet => size == GfLayoutSize.tablet;
  bool get isDesktop => size == GfLayoutSize.desktop;

  /// Main content padding.
  double get pagePadding =>
      uiScale *
      switch (size) {
        GfLayoutSize.desktop => 28,
        GfLayoutSize.tablet => 20,
        GfLayoutSize.mobile => 14,
      };

  /// Top padding above the page header and bottom padding below the page body.
  double get pageVerticalPadding =>
      uiScale *
      switch (size) {
        GfLayoutSize.desktop => 14,
        GfLayoutSize.tablet => 12,
        GfLayoutSize.mobile => 10,
      };

  /// Gap between dashboard widgets.
  double get gridGap =>
      uiScale *
      switch (size) {
        GfLayoutSize.desktop => 20,
        GfLayoutSize.tablet => 16,
        GfLayoutSize.mobile => 12,
      };

  double get sectionGap => gridGap;

  int get kpiColumns => switch (size) {
        GfLayoutSize.desktop => 4,
        GfLayoutSize.tablet => 2,
        GfLayoutSize.mobile => 1,
      };

  /// Two-column charts / table+alerts only on large screens.
  bool get twoColumnDashboard => isDesktop;

  /// Stack top-bar title / search / actions vertically.
  bool get stackTopBar => !isDesktop;

  /// Compact action buttons (icon-only when labels would overflow).
  bool get compactActions => isMobile;

  /// Full data table vs reduced columns vs stacked cards.
  bool get showFullTable => isDesktop;
  bool get showCompactTable => isTablet;
  bool get showTableCards => isMobile;

  /// Primary share of a 65/35 split.
  int get primaryFlex => 13;
  int get secondaryFlex => 7;

  double get chartMinHeight => (isMobile ? 220 : 260) * uiScale;
  double get stackedChartHeight => (isMobile ? 240 : 280) * uiScale;
}

/// Provides layout size and optional mobile drawer control to descendants.
class GfLayoutScope extends InheritedWidget {
  const GfLayoutScope({
    super.key,
    required this.size,
    required this.metrics,
    this.contentWidth = 0,
    this.openDrawer,
    required super.child,
  });

  final GfLayoutSize size;
  final GfLayoutMetrics metrics;
  final double contentWidth;
  final VoidCallback? openDrawer;

  static GfLayoutScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GfLayoutScope>();
  }

  static GfLayoutScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'GfLayoutScope not found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(GfLayoutScope oldWidget) {
    return size != oldWidget.size ||
        openDrawer != oldWidget.openDrawer ||
        contentWidth != oldWidget.contentWidth ||
        metrics.uiScale != oldWidget.metrics.uiScale;
  }
}
