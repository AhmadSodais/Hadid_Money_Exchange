import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

enum GfKpiTone { normal, warning, error }

/// One currency line inside a [GfKpiCard] multi-currency value.
///
/// [amountText] is already formatted by the caller so money never passes
/// through floating point here.
class GfKpiCurrencyLine {
  const GfKpiCurrencyLine({
    required this.amountText,
    required this.currencyLabel,
    this.color,
  });

  final String amountText;
  final String currencyLabel;
  final Color? color;
}

/// KPI metric card with optional trend, sparkline, and icon.
class GfKpiCard extends StatelessWidget {
  const GfKpiCard({
    super.key,
    required this.title,
    this.value = '',
    this.currencies,
    this.trendPercent,
    this.sparkline,
    this.icon,
    this.tone = GfKpiTone.normal,
    this.onTap,
  });

  final String title;
  /// Single-line value (counts, plain totals). Ignored when [currencies] is set.
  final String value;
  /// Multi-currency totals rendered as stacked amount + currency rows.
  final List<GfKpiCurrencyLine>? currencies;
  final double? trendPercent;
  final List<double>? sparkline;
  final String? icon;
  final GfKpiTone tone;
  final VoidCallback? onTap;

  Color get _accent {
    return switch (tone) {
      GfKpiTone.warning => AppColors.warning,
      GfKpiTone.error => AppColors.error,
      GfKpiTone.normal => AppColors.primary,
    };
  }

  Color get _surfaceTint {
    return switch (tone) {
      GfKpiTone.warning => AppColors.warning.withValues(alpha: 0.06),
      GfKpiTone.error => AppColors.error.withValues(alpha: 0.06),
      GfKpiTone.normal => Colors.transparent,
    };
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(_surfaceTint, AppColors.card),
        borderRadius: AppRadius.card,
        border: Border.all(
          color: tone == GfKpiTone.normal
              ? AppColors.border
              : _accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.label.copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      borderRadius: AppRadius.input,
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        icon!,
                        width: 18,
                        height: 18,
                        colorFilter:
                            ColorFilter.mode(_accent, BlendMode.srcIn),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (currencies != null)
            _CurrencyValueBlock(lines: currencies!, accent: _accent)
          else
            Text(
              value,
              style: AppTypography.kpiValue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (trendPercent != null ||
              (sparkline != null && sparkline!.isNotEmpty)) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                if (trendPercent != null) _TrendChip(percent: trendPercent!),
                if (trendPercent != null &&
                    sparkline != null &&
                    sparkline!.isNotEmpty)
                  const SizedBox(width: AppSpacing.xs),
                if (sparkline != null && sparkline!.isNotEmpty)
                  Expanded(
                    child: SizedBox(
                      height: 22,
                      child: CustomPaint(
                        painter: _SparklinePainter(
                          values: sparkline!,
                          color: _accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        hoverColor: AppColors.hover,
        child: card,
      ),
    );
  }
}

class _CurrencyValueBlock extends StatelessWidget {
  const _CurrencyValueBlock({
    required this.lines,
    required this.accent,
  });

  final List<GfKpiCurrencyLine> lines;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final rows = lines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 6),
            Divider(
              height: 1,
              thickness: 1,
              color: AppColors.border.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  rows[i].amountText,
                  style: AppTypography.kpiValue
                      .copyWith(fontSize: 18, color: rows[i].color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.end,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: AppRadius.pill,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.22),
                  ),
                ),
                child: Text(
                  rows[i].currencyLabel,
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final up = percent >= 0;
    final color = up ? AppColors.success : AppColors.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(1)}%',
          style: AppTypography.caption.copyWith(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 0.0001 ? 1.0 : (maxV - minV);

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - ((values[i] - minV) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
