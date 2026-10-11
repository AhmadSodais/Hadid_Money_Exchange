import 'dart:math' as math;

import '../theme/app_spacing.dart';

/// Shared pagination math and layout metrics.
abstract final class GfPagination {
  static const double footerMinHeight = 64;
  static const double footerVerticalPadding = 16;
  static const double footerHorizontalPadding = 24;

  static const double tableHeaderHeight = 56;
  static const double cardPadding = AppSpacing.md;

  /// Soft preference when plenty of space exists — never forced above what fits.
  static const int preferredMinRows = 3;
  static const int maxRowsPerPage = 100;

  @Deprecated('Use preferredMinRows')
  static const int minRowsPerPage = preferredMinRows;

  /// How many **full** rows fit in [bodyHeight].
  ///
  /// Never returns more rows than physically fit (avoids RenderFlex overflow).
  static int rowsPerPageFromHeight({
    required double bodyHeight,
    double rowHeight = AppSpacing.tableRowHeight,
    int maxRows = maxRowsPerPage,
  }) {
    if (bodyHeight <= 0 || rowHeight <= 0) return 0;
    final rows = (bodyHeight / rowHeight).floor();
    return rows.clamp(0, maxRows);
  }

  /// Available body height after subtracting fixed chrome from [containerHeight].
  static double availableBodyHeight({
    required double containerHeight,
    double headerHeight = 0,
    double toolbarHeight = 0,
    double tableHeaderHeight = 0,
    double footerHeight = 0,
    double verticalPadding = 0,
  }) {
    return containerHeight -
        headerHeight -
        toolbarHeight -
        tableHeaderHeight -
        footerHeight -
        verticalPadding;
  }

  static int totalPages({required int totalItems, required int pageSize}) {
    if (totalItems <= 0 || pageSize <= 0) return 1;
    return (totalItems / pageSize).ceil().clamp(1, 999999);
  }

  static int clampPage(int page, int totalPages) {
    if (totalPages < 1) return 1;
    return page.clamp(1, totalPages);
  }

  static ({int from, int to}) itemRange({
    required int page,
    required int pageSize,
    required int totalItems,
  }) {
    if (totalItems == 0) return (from: 0, to: 0);
    final from = ((page - 1) * pageSize) + 1;
    final to = math.min(page * pageSize, totalItems);
    return (from: from, to: to);
  }

  /// Page numbers to render; `null` means an ellipsis gap.
  static List<int?> pageButtons({
    required int currentPage,
    required int totalPages,
    int maxNumericButtons = 7,
  }) {
    if (totalPages <= 1) return [1];
    if (totalPages <= maxNumericButtons) {
      return List.generate(totalPages, (i) => i + 1);
    }

    final pages = <int>{1, totalPages};
    for (var i = currentPage - 1; i <= currentPage + 1; i++) {
      if (i >= 1 && i <= totalPages) pages.add(i);
    }

    final sorted = pages.toList()..sort();
    final result = <int?>[];
    var prev = 0;
    for (final p in sorted) {
      if (prev != 0 && p - prev > 1) result.add(null);
      result.add(p);
      prev = p;
    }
    return result;
  }

  /// Fixed height for overview list panels from viewport.
  static double overviewListPanelHeight(double viewportHeight) {
    return (viewportHeight * 0.28).clamp(260.0, 420.0);
  }

  static double overviewChartPanelHeight(double viewportHeight) {
    return overviewListPanelHeight(viewportHeight);
  }

  /// Height for tables embedded inside a scrolling page body.
  static double embeddedTableHeight(double viewportHeight) {
    return (viewportHeight * 0.48).clamp(340.0, 620.0);
  }
}
