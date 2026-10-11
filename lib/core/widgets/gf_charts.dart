import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';
import '../theme/gf_color_scheme.dart';
import '../utils/formatters.dart';
import '../utils/gf_breakpoints.dart';
import '../utils/overview_chart_period.dart';
import '../utils/shamsi_dates.dart';
import 'gf_dropdown.dart';

/// One plotted value on [GfLineChart], keyed by calendar date for axis labels.
typedef GfLineChartPoint = ({DateTime date, double value});

class GfDonutSlice {
  const GfDonutSlice({
    required this.label,
    required this.value,
    required this.color,
    this.count,
  });

  final String label;
  final double value;
  final Color color;
  final int? count;
}

class GfDonutChart extends StatelessWidget {
  const GfDonutChart({
    super.key,
    required this.slices,
    this.centerLabel,
    this.centerValue,
    this.size = 140,
  });

  final List<GfDonutSlice> slices;
  final String? centerLabel;
  final String? centerValue;
  final double size;

  @override
  Widget build(BuildContext context) {
    final gf = context.gf;

    if (slices.isEmpty) {
      return SizedBox(
        height: size,
        child: Center(
          child: Text(
            'common.noData'.tr(),
            style: AppTypography.subtitle.copyWith(color: gf.textSecondary),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : size * 2;
        final stack = maxW < size + 120;
        final donutSize = stack
            ? math.min(size, maxW.clamp(72.0, size))
            : math.min(size, maxW * 0.45);

        final donut = SizedBox(
          width: donutSize,
          height: donutSize,
          child: CustomPaint(
            painter: _DonutPainter(slices),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (centerValue != null)
                    Text(
                      centerValue!,
                      style: AppTypography.bodySemiBold.copyWith(
                        color: gf.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (centerLabel != null)
                    Text(
                      centerLabel!,
                      style: AppTypography.caption.copyWith(
                        color: gf.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
        );

        final legend = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: slices.map((s) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(
                      s.label,
                      style: AppTypography.caption.copyWith(
                        color: gf.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 2,
                    child: Text(
                      s.count != null
                          ? '${Formatters.number(s.count!)} · ${Formatters.number(s.value, decimals: 1)}%'
                          : '${Formatters.number(s.value, decimals: 1)}%',
                      style: AppTypography.caption.copyWith(
                        color: gf.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              donut,
              const SizedBox(height: 12),
              legend,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            donut,
            const SizedBox(width: 12),
            Expanded(child: legend),
          ],
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.slices);

  final List<GfDonutSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.value);

    if (total <= 0) return;

    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final strokeWidth = size.width * 0.18;
    final chartRadius = radius - strokeWidth / 2;
    if (chartRadius <= 0) return;

    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;

    canvas.drawCircle(center, chartRadius, backgroundPaint);

    const gap = 0.035;
    var startAngle = -math.pi / 2;

    for (final slice in slices) {
      final percentage = slice.value / total;
      final sweepAngle = percentage * math.pi * 2;
      final visibleSweep = math.max(0.0, sweepAngle - gap);

      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: chartRadius),
        startAngle + gap / 2,
        visibleSweep,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    if (oldDelegate.slices.length != slices.length) {
      return true;
    }

    for (var i = 0; i < slices.length; i++) {
      final oldSlice = oldDelegate.slices[i];
      final newSlice = slices[i];

      if (oldSlice.value != newSlice.value ||
          oldSlice.color != newSlice.color ||
          oldSlice.label != newSlice.label ||
          oldSlice.count != newSlice.count) {
        return true;
      }
    }

    return false;
  }
}

/// Time window shown in the analytics line-chart header.
typedef GfLineChartPeriod = OverviewChartPeriod;

/// Modern GlassFlow analytics line chart with card chrome, period selector,
/// gradient fill, interactive tooltip, and loading / empty / error states.
class GfLineChart extends StatefulWidget {
  const GfLineChart({
    super.key,
    required this.points,
    this.secondaryPoints,
    this.title,
    this.subtitle,
    this.tooltipMetricLabel,
    this.height,
    this.period = GfLineChartPeriod.weekly,
    this.onPeriodChanged,
    this.showPeriodSelector = true,
    this.showCard = true,
    this.showHeader = true,
    this.loading = false,
    this.error,
    this.onRetry,
    this.yLabelBuilder,
    this.hideYAxisLabels = false,
    this.xLabelBuilder,
    this.valueFormatter,
    this.primaryLegend,
    this.secondaryLegend,
    this.secondaryColor,
  });

  final List<GfLineChartPoint> points;
  final List<GfLineChartPoint>? secondaryPoints;
  final String? title;
  final String? subtitle;
  final String? tooltipMetricLabel;
  final double? height;
  final GfLineChartPeriod period;
  final ValueChanged<GfLineChartPeriod>? onPeriodChanged;
  final bool showPeriodSelector;
  final bool showCard;
  final bool showHeader;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final String Function(double value)? yLabelBuilder;
  /// Hides abbreviated axis ticks (`1K`, `13K`, …) so the line shows growth only.
  final bool hideYAxisLabels;
  /// Overrides period-based Shamsi axis labels when provided.
  final String Function(DateTime date, GfLineChartPeriod period)? xLabelBuilder;
  final String Function(double value)? valueFormatter;
  final String? primaryLegend;
  final String? secondaryLegend;
  final Color? secondaryColor;

  static double responsiveHeight(BuildContext context) {
    switch (GfBreakpoints.of(context)) {
      case GfLayoutSize.mobile:
        return 220;
      case GfLayoutSize.tablet:
        return 260;
      case GfLayoutSize.desktop:
        return 300;
    }
  }

  @override
  State<GfLineChart> createState() => _GfLineChartState();
}

class _GfLineChartState extends State<GfLineChart> {
  late GfLineChartPeriod _period;
  int? _selectedIndex;
  List<Offset> _plotted = const [];

  @override
  void initState() {
    super.initState();
    _period = widget.period;
  }

  @override
  void didUpdateWidget(covariant GfLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _period = widget.period;
    }
    if (oldWidget.points != widget.points) {
      _selectedIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gf = context.gf;
    final chartHeight = widget.height ?? GfLineChart.responsiveHeight(context);
    final title = widget.title ?? 'chart.salesOverview'.tr();
    final subtitle = widget.subtitle ?? 'chart.businessPerformance'.tr();

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          _ChartHeader(
            title: title,
            subtitle: subtitle,
            period: _period,
            showPeriodSelector: widget.showPeriodSelector,
            onPeriodChanged: (period) {
              setState(() {
                _period = period;
                _selectedIndex = null;
              });
              widget.onPeriodChanged?.call(period);
            },
          ),
          const SizedBox(height: 20),
        ],
        SizedBox(
          height: chartHeight,
          width: double.infinity,
          child: _buildChartBody(context, gf),
        ),
      ],
    );

    if (!widget.showCard) return body;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: gf.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: gf.border.withValues(alpha: 0.9)),
        boxShadow: AppShadows.card,
      ),
      child: body,
    );
  }

  Widget _buildChartBody(BuildContext context, GfColorScheme gf) {
    if (widget.loading) {
      return const _ChartSkeleton();
    }

    if (widget.error != null) {
      return _ChartErrorState(
        message: widget.error!,
        onRetry: widget.onRetry,
      );
    }

    if (widget.points.isEmpty) {
      return _ChartEmptyState(message: 'chart.noData'.tr());
    }

    final labeledPoints = _toLabeledPoints(widget.points);
    final labeledSecondary = widget.secondaryPoints == null
        ? null
        : _toLabeledPoints(widget.secondaryPoints!);
    final showLegend =
        (widget.primaryLegend != null && widget.primaryLegend!.isNotEmpty) ||
            (widget.secondaryLegend != null &&
                widget.secondaryLegend!.isNotEmpty &&
                labeledSecondary != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLegend)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                if (widget.primaryLegend != null &&
                    widget.primaryLegend!.isNotEmpty)
                  _LegendDot(color: gf.primary, label: widget.primaryLegend!),
                if (labeledSecondary != null &&
                    widget.secondaryLegend != null &&
                    widget.secondaryLegend!.isNotEmpty)
                  _LegendDot(
                    color: widget.secondaryColor ?? const Color(0xFFD99A32),
                    label: widget.secondaryLegend!,
                  ),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chartSize =
                  Size(constraints.maxWidth, constraints.maxHeight);
              if (chartSize.width < 60 || chartSize.height < 60) {
                return const SizedBox.shrink();
              }
              final plotted = _computePlottedPoints(
                labeledPoints,
                chartSize,
                labeledSecondary,
                hideYAxisLabels: widget.hideYAxisLabels,
              );

              // Keep hit-test anchors in sync without setState during paint.
              _plotted = plotted;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _onTapDown(details.localPosition),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      size: chartSize,
                      painter: _LinePainter(
                        points: labeledPoints,
                        secondaryPoints: labeledSecondary,
                        selectedIndex: _selectedIndex,
                        plotted: plotted,
                        yLabelBuilder: widget.hideYAxisLabels
                            ? (_) => ''
                            : (widget.yLabelBuilder ?? _compactAxisLabel),
                        hideYAxisLabels: widget.hideYAxisLabels,
                        xLabelBuilder: (label) => label,
                        primary: gf.primary,
                        secondary:
                            widget.secondaryColor ?? const Color(0xFFD99A32),
                        gridColor: gf.divider.withValues(alpha: 0.55),
                        labelStyle: AppTypography.localize(
                          AppTypography.caption.copyWith(
                            color: gf.textSecondary,
                            fontSize: 12,
                          ),
                          context: context,
                        ),
                      ),
                    ),
                    if (_selectedIndex != null &&
                        _selectedIndex! < plotted.length)
                      _ChartTooltip(
                        point: labeledPoints[_selectedIndex!],
                        anchor: plotted[_selectedIndex!],
                        chartSize: chartSize,
                        metricLabel: widget.tooltipMetricLabel ??
                            'chart.salesMetric'.tr(),
                        valueText: (widget.valueFormatter ??
                            Formatters.money)(
                          labeledPoints[_selectedIndex!].value,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<({String label, double value})> _toLabeledPoints(
    List<GfLineChartPoint> points,
  ) {
    return [
      for (final p in points)
        (label: _axisLabelFor(p.date), value: p.value),
    ];
  }

  String _axisLabelFor(DateTime date) {
    if (widget.xLabelBuilder != null) {
      return widget.xLabelBuilder!(date, _period);
    }
    switch (_period) {
      case OverviewChartPeriod.weekly:
        return ShamsiDates.weekdayName(date);
      case OverviewChartPeriod.monthly:
        return ShamsiDates.monthName(date);
      case OverviewChartPeriod.yearly:
        return ShamsiDates.formatYear(date);
    }
  }

  void _onTapDown(Offset local) {
    if (_plotted.isEmpty) return;

    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < _plotted.length; i++) {
      final distance = (_plotted[i] - local).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    if (bestDistance > 36) {
      setState(() => _selectedIndex = null);
      return;
    }

    setState(() {
      _selectedIndex = _selectedIndex == bestIndex ? null : bestIndex;
    });
  }
}

/// Chart inset used by both hit-testing and painting.
const _chartInset = EdgeInsets.fromLTRB(40, 20, 12, 30);
const _chartInsetNoYLabels = EdgeInsets.fromLTRB(12, 20, 12, 30);

List<Offset> _computePlottedPoints(
  List<({String label, double value})> points,
  Size size,
  List<({String label, double value})>? secondaryPoints, {
  bool hideYAxisLabels = false,
}) {
  if (points.isEmpty || size.width <= 0 || size.height <= 0) {
    return const [];
  }

  final inset = hideYAxisLabels ? _chartInsetNoYLabels : _chartInset;
  final chart = Rect.fromLTRB(
    inset.left,
    inset.top,
    size.width - inset.right,
    size.height - inset.bottom,
  );
  if (chart.width <= 0 || chart.height <= 0) {
    return const [];
  }

  var maxValue = points.fold<double>(
    0,
    (value, point) => math.max(value, point.value),
  );
  if (secondaryPoints != null) {
    for (final p in secondaryPoints) {
      maxValue = math.max(maxValue, p.value);
    }
  }
  final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.15;

  final plotted = <Offset>[];
  for (var i = 0; i < points.length; i++) {
    final x = points.length == 1
        ? chart.left + chart.width / 2
        : chart.left + chart.width * i / (points.length - 1);
    final y = chart.bottom - chart.height * (points[i].value / maxY);
    plotted.add(Offset(x, y));
  }
  return plotted;
}

String _compactAxisLabel(double value) {
  final abs = value.abs();
  if (abs >= 1000000) {
    return '${Formatters.number(value / 1000000, decimals: 1)}M';
  }
  if (abs >= 1000) {
    return '${Formatters.number(value / 1000, decimals: abs >= 10000 ? 0 : 1)}K';
  }
  return Formatters.number(value, decimals: value == value.roundToDouble() ? 0 : 1);
}

class _ChartHeader extends StatelessWidget {
  const _ChartHeader({
    required this.title,
    required this.subtitle,
    required this.period,
    required this.showPeriodSelector,
    required this.onPeriodChanged,
  });

  final String title;
  final String subtitle;
  final GfLineChartPeriod period;
  final bool showPeriodSelector;
  final ValueChanged<GfLineChartPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final gf = context.gf;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = !constraints.maxWidth.isFinite ||
            constraints.maxWidth < 420;

        final titles = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.localize(
                AppTypography.sectionTitle.copyWith(
                  fontSize: narrow ? 17 : 20,
                  fontWeight: FontWeight.w700,
                  color: gf.textPrimary,
                  height: 1.2,
                ),
                context: context,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: AppTypography.localize(
                AppTypography.body.copyWith(
                  fontSize: 14,
                  color: gf.textSecondary,
                ),
                context: context,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );

        if (!showPeriodSelector) return titles;

        final period = _PeriodDropdown(
          value: this.period,
          onChanged: onPeriodChanged,
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titles,
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: period,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titles),
            const SizedBox(width: 12),
            period,
          ],
        );
      },
    );
  }
}

class _PeriodDropdown extends StatelessWidget {
  const _PeriodDropdown({
    required this.value,
    required this.onChanged,
  });

  final GfLineChartPeriod value;
  final ValueChanged<GfLineChartPeriod> onChanged;

  String _label(OverviewChartPeriod period) {
    switch (period) {
      case OverviewChartPeriod.weekly:
        return 'chart.periodWeekly'.tr();
      case OverviewChartPeriod.monthly:
        return 'chart.periodMonthly'.tr();
      case OverviewChartPeriod.yearly:
        return 'chart.periodYearly'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 40,
      child: GfDropdown<OverviewChartPeriod>(
        items: OverviewChartPeriod.values,
        value: value,
        height: 40,
        width: 120,
        prefixIcon: Icons.calendar_today_rounded,
        labelBuilder: _label,
        onChanged: (period) {
          if (period != null) onChanged(period);
        },
      ),
    );
  }
}

class _ChartTooltip extends StatelessWidget {
  const _ChartTooltip({
    required this.point,
    required this.anchor,
    required this.chartSize,
    required this.metricLabel,
    required this.valueText,
  });

  final ({String label, double value}) point;
  final Offset anchor;
  final Size chartSize;
  final String metricLabel;
  final String valueText;

  @override
  Widget build(BuildContext context) {
    final gf = context.gf;
    const tooltipWidth = 150.0;
    const tooltipHeight = 78.0;

    var left = anchor.dx - tooltipWidth / 2;
    left = left.clamp(8.0, math.max(8.0, chartSize.width - tooltipWidth - 8));
    var top = anchor.dy - tooltipHeight - 16;
    if (top < 4) top = anchor.dy + 16;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: tooltipWidth,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: gf.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: gf.border),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                point.label,
                style: AppTypography.localize(
                  AppTypography.caption.copyWith(
                    color: gf.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  context: context,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                metricLabel,
                style: AppTypography.localize(
                  AppTypography.caption.copyWith(color: gf.textMuted),
                  context: context,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                valueText,
                style: AppTypography.localize(
                  AppTypography.bodySemiBold.copyWith(
                    color: gf.textPrimary,
                    fontSize: 14,
                  ),
                  context: context,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartEmptyState extends StatelessWidget {
  const _ChartEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final gf = context.gf;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.show_chart_rounded, size: 36, color: gf.textMuted),
          const SizedBox(height: 10),
          Text(
            message,
            style: AppTypography.localize(
              AppTypography.subtitle.copyWith(color: gf.textSecondary),
              context: context,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ChartErrorState extends StatelessWidget {
  const _ChartErrorState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final gf = context.gf;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 36, color: gf.warning),
          const SizedBox(height: 10),
          Text(
            message.isEmpty ? 'chart.loadFailed'.tr() : message,
            style: AppTypography.localize(
              AppTypography.subtitle.copyWith(color: gf.textSecondary),
              context: context,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('common.retry'.tr()),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartSkeleton extends StatefulWidget {
  const _ChartSkeleton();

  @override
  State<_ChartSkeleton> createState() => _ChartSkeletonState();
}

class _ChartSkeletonState extends State<_ChartSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gf = context.gf;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = 0.35 + (_controller.value * 0.35);
        final fill = gf.divider.withValues(alpha: t);
        return CustomPaint(
          painter: _SkeletonPainter(color: fill, lineColor: gf.primary.withValues(alpha: t)),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  const _SkeletonPainter({required this.color, required this.lineColor});

  final Color color;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTRB(
      _chartInset.left,
      _chartInset.top,
      size.width - _chartInset.right,
      size.height - _chartInset.bottom,
    );

    final gridPaint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = chart.bottom - chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    final points = <Offset>[
      Offset(chart.left, chart.bottom - chart.height * 0.35),
      Offset(chart.left + chart.width * 0.25, chart.bottom - chart.height * 0.55),
      Offset(chart.left + chart.width * 0.5, chart.bottom - chart.height * 0.42),
      Offset(chart.left + chart.width * 0.75, chart.bottom - chart.height * 0.72),
      Offset(chart.right, chart.bottom - chart.height * 0.58),
    ];
    final path = _buildSmoothPath(points);
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    for (final block in [
      Rect.fromLTWH(8, chart.top, 24, 10),
      Rect.fromLTWH(8, chart.top + chart.height * 0.33, 24, 10),
      Rect.fromLTWH(8, chart.top + chart.height * 0.66, 24, 10),
      Rect.fromLTWH(8, chart.bottom - 5, 24, 10),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(block, const Radius.circular(8)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SkeletonPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.lineColor != lineColor;
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTypography.localize(
            AppTypography.caption.copyWith(color: context.gf.textSecondary),
            context: context,
          ),
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.plotted,
    required this.yLabelBuilder,
    required this.xLabelBuilder,
    required this.primary,
    required this.secondary,
    required this.gridColor,
    required this.labelStyle,
    this.secondaryPoints,
    this.selectedIndex,
    this.hideYAxisLabels = false,
  });

  final List<({String label, double value})> points;
  final List<({String label, double value})>? secondaryPoints;
  final List<Offset> plotted;
  final int? selectedIndex;
  final String Function(double value) yLabelBuilder;
  final String Function(String label) xLabelBuilder;
  final Color primary;
  final Color secondary;
  final Color gridColor;
  final TextStyle labelStyle;
  final bool hideYAxisLabels;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    final inset = hideYAxisLabels ? _chartInsetNoYLabels : _chartInset;
    final chart = Rect.fromLTRB(
      inset.left,
      inset.top,
      size.width - inset.right,
      size.height - inset.bottom,
    );
    if (chart.width <= 0 || chart.height <= 0) return;

    var maxValue = points.fold<double>(
      0,
      (value, point) => math.max(value, point.value),
    );
    final secondarySeries = secondaryPoints;
    if (secondarySeries != null) {
      for (final p in secondarySeries) {
        maxValue = math.max(maxValue, p.value);
      }
    }

    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.15;
    final textPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.right,
    );

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = chart.bottom - chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);

      if (!hideYAxisLabels) {
        textPainter.text = TextSpan(
          text: yLabelBuilder(maxY * i / 4),
          style: labelStyle,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(chart.left - textPainter.width - 8, y - textPainter.height / 2),
        );
      }
    }

    List<Offset> plot(List<({String label, double value})> series) {
      final result = <Offset>[];
      for (var i = 0; i < series.length; i++) {
        final x = series.length == 1
            ? chart.left + chart.width / 2
            : chart.left + chart.width * i / (series.length - 1);
        final y = chart.bottom - chart.height * (series[i].value / maxY);
        result.add(Offset(x, y));
      }
      return result;
    }

    void drawSeries(
      List<({String label, double value})> series,
      List<Offset> seriesPlotted,
      Color color, {
      bool fill = false,
      bool drawXLabels = false,
      int? highlightIndex,
    }) {
      if (seriesPlotted.isEmpty) return;

      if (seriesPlotted.length == 1) {
        _drawPoint(
          canvas,
          seriesPlotted.first,
          color,
          selected: highlightIndex == 0,
        );
      } else {
        final linePath = _buildSmoothPath(seriesPlotted);
        if (fill) {
          final fillPath = Path.from(linePath)
            ..lineTo(seriesPlotted.last.dx, chart.bottom)
            ..lineTo(seriesPlotted.first.dx, chart.bottom)
            ..close();
          canvas.drawPath(
            fillPath,
            Paint()
              ..shader = ui.Gradient.linear(
                Offset(0, chart.top),
                Offset(0, chart.bottom),
                [
                  color.withValues(alpha: 0.30),
                  color.withValues(alpha: 0.0),
                ],
              ),
          );
        }

        canvas.drawPath(
          linePath,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true,
        );

        for (var i = 0; i < seriesPlotted.length; i++) {
          _drawPoint(
            canvas,
            seriesPlotted[i],
            color,
            selected: highlightIndex == i,
          );
        }
      }

      if (drawXLabels) {
        for (var i = 0; i < seriesPlotted.length; i++) {
          textPainter.text = TextSpan(
            text: xLabelBuilder(series[i].label),
            style: labelStyle,
          );
          textPainter.layout(
            maxWidth: chart.width / math.max(1, series.length),
          );
          textPainter.paint(
            canvas,
            Offset(
              seriesPlotted[i].dx - textPainter.width / 2,
              chart.bottom + 10,
            ),
          );
        }
      }
    }

    drawSeries(
      points,
      plotted,
      primary,
      fill: true,
      drawXLabels: true,
      highlightIndex: selectedIndex,
    );

    if (secondarySeries != null && secondarySeries.isNotEmpty) {
      drawSeries(secondarySeries, plot(secondarySeries), secondary);
    }
  }

  void _drawPoint(
    Canvas canvas,
    Offset point,
    Color color, {
    required bool selected,
  }) {
    if (selected) {
      canvas.drawCircle(
        point,
        10,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(point, 6.5, Paint()..color = color);
      canvas.drawCircle(point, 3.2, Paint()..color = Colors.white);
      return;
    }

    canvas.drawCircle(point, 3.5, Paint()..color = color);
    canvas.drawCircle(point, 1.8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.secondaryPoints != secondaryPoints ||
        oldDelegate.plotted != plotted ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.hideYAxisLabels != hideYAxisLabels;
  }
}

Path _buildSmoothPath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;

  path.moveTo(points.first.dx, points.first.dy);
  for (var i = 0; i < points.length - 1; i++) {
    final current = points[i];
    final next = points[i + 1];
    final middleX = (current.dx + next.dx) / 2;
    path.cubicTo(middleX, current.dy, middleX, next.dy, next.dx, next.dy);
  }
  return path;
}
