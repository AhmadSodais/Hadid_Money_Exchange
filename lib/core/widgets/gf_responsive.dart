import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../utils/gf_breakpoints.dart';

/// Equal-height KPI (or similar) cards in a responsive column grid.
///
/// When [columns] is null, columns are chosen from the available width
/// (content area), so the grid adapts beside a sidebar and on resize.
class GfKpiGrid extends StatelessWidget {
  const GfKpiGrid({
    super.key,
    required this.children,
    this.columns,
    this.gap,
  });

  final List<Widget> children;

  /// Fixed column count. Null = auto from width.
  final int? columns;
  final double? gap;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = GfBreakpoints.metricsOf(context);
        final resolvedGap = gap ?? metrics.gridGap;
        final cols = (columns ??
                GfBreakpoints.kpiColumnsForWidth(
                  constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : MediaQuery.sizeOf(context).width,
                  itemCount: children.length,
                ))
            .clamp(1, children.length);

        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          final end = (i + cols).clamp(0, children.length);
          final slice = children.sublist(i, end);
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < slice.length; j++) ...[
                    if (j > 0) SizedBox(width: resolvedGap),
                    Expanded(child: slice[j]),
                  ],
                  for (var j = slice.length; j < cols; j++) ...[
                    SizedBox(width: resolvedGap),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          );
          if (end < children.length) {
            rows.add(SizedBox(height: resolvedGap));
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

/// Two-pane dashboard split that stacks below the desktop breakpoint (or when
/// [stacked] is true / content width is narrow).
///
/// Defaults to [CrossAxisAlignment.start] so it is safe inside scroll views.
/// Use [CrossAxisAlignment.stretch] only when the parent provides a finite height.
class GfResponsiveSplit extends StatelessWidget {
  const GfResponsiveSplit({
    super.key,
    required this.start,
    required this.end,
    this.stacked,
    this.gap,
    this.startFlex = 13,
    this.endFlex = 7,
    this.stackBelow = GfBreakpoints.tabletMax,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final Widget start;
  final Widget end;

  /// Force stacked layout. Null = decide from width / [GfLayoutMetrics].
  final bool? stacked;
  final double? gap;
  final int startFlex;
  final int endFlex;
  final double stackBelow;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = GfBreakpoints.metricsOf(context);
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final shouldStack =
            stacked ?? (!metrics.twoColumnDashboard || width < stackBelow);
        final resolvedGap = gap ?? metrics.gridGap;

        if (shouldStack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              start,
              SizedBox(height: resolvedGap),
              end,
            ],
          );
        }

        return Row(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            Expanded(flex: startFlex, child: start),
            SizedBox(width: resolvedGap),
            Expanded(flex: endFlex, child: end),
          ],
        );
      },
    );
  }
}

/// Wraps page action buttons so they flow onto multiple lines on narrow widths.
class GfActionBar extends StatelessWidget {
  const GfActionBar({
    super.key,
    required this.children,
    this.spacing = 8,
    this.runSpacing = 8,
    this.alignment = WrapAlignment.end,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: alignment,
      spacing: spacing,
      runSpacing: runSpacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/// Horizontal scroll host for filter chips / tab strips.
class GfScrollableRow extends StatelessWidget {
  const GfScrollableRow({
    super.key,
    required this.children,
    this.spacing = 8,
    this.padding,
  });

  final List<Widget> children;
  final double spacing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Applies [GfLayoutMetrics.pagePadding] when a page is not inside [PageScaffold].
class GfResponsivePadding extends StatelessWidget {
  const GfResponsivePadding({
    super.key,
    required this.child,
    this.top = true,
    this.bottom = true,
    this.horizontal = true,
  });

  final Widget child;
  final bool top;
  final bool bottom;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final pad = GfBreakpoints.metricsOf(context).pagePadding;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontal ? pad : 0,
        top ? pad : 0,
        horizontal ? pad : 0,
        bottom ? pad : 0,
      ),
      child: child,
    );
  }
}

/// Preferred table [minWidth] that still scrolls on small screens.
double gfTableMinWidth(BuildContext context, {required double preferred}) {
  // Keep preferred width so columns stay readable; GfDataTable scrolls
  // horizontally when the viewport is narrower. Never clamp with a lower
  // bound above [preferred] (invalidates clamp when preferred is smaller).
  if (preferred <= 0) return 0;
  return preferred;
}

/// Section gap matching current layout metrics (fallback: [AppSpacing.sectionGap]).
double gfSectionGap(BuildContext context) {
  final scope = GfLayoutScope.maybeOf(context);
  return scope?.metrics.sectionGap ?? AppSpacing.sectionGap;
}
