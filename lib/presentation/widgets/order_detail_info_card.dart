import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';
import '../../core/widgets/gf_data_table.dart';
import 'exchange_ui.dart';
import 'order_detail_dialog_style.dart';

/// Read-only detail dialog frame: icon header with close, scrolling body,
/// fixed footer, in the [OrderDetailDialogStyle] look.
class OrderDetailDialogFrame extends StatelessWidget {
  const OrderDetailDialogFrame({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.subtitle,
    this.headerTrailing,
    this.summary,
    this.footerStart = const [],
    this.closeLabel = 'بستن',
    this.maxWidth = OrderDetailDialogStyle.maxWidth,
    this.minHeight = OrderDetailDialogStyle.minHeight,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? headerTrailing;
  final Widget body;
  final Widget? summary;
  final List<Widget> footerStart;
  final String closeLabel;
  final double maxWidth;
  final double minHeight;

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: const Color(0x661E293B),
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).pop();
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          minHeight: minHeight,
          maxHeight: OrderDetailDialogStyle.maxHeight,
        ),
        decoration: OrderDetailDialogStyle.container,
        padding: OrderDetailDialogStyle.framePadding,
        child: OrderDetailDialogStyle.scrollLayout(
          header: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: OrderDetailDialogStyle.fieldHeight,
                  height: OrderDetailDialogStyle.fieldHeight,
                  decoration: BoxDecoration(
                    color: OrderDetailDialogStyle.iconBg,
                    borderRadius: OrderDetailDialogStyle.controlBorderRadius,
                  ),
                  child: Icon(icon, color: OrderDetailDialogStyle.accent, size: 22),
                ),
                OrderDetailDialogStyle.rowGap,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.sectionTitle.copyWith(
                          color: OrderDetailDialogStyle.navy,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: AppTypography.caption.copyWith(
                            color: OrderDetailDialogStyle.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (headerTrailing != null) ...[
                  OrderDetailDialogStyle.inlineGap,
                  headerTrailing!,
                ],
                IconButton(
                  onPressed: close,
                  icon: Icon(
                    Icons.close_rounded,
                    color: OrderDetailDialogStyle.muted,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: OrderDetailDialogStyle.border),
            OrderDetailDialogStyle.sectionSpace,
          ],
          body: body,
          footer: [
            if (summary != null) ...[
              OrderDetailDialogStyle.sectionSpace,
              summary!,
            ],
            const SizedBox(height: 16),
            Divider(height: 1, color: OrderDetailDialogStyle.border),
            const SizedBox(height: 14),
            Row(
              children: [
                ...footerStart,
                const Spacer(),
                OutlinedButton(
                  onPressed: close,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: OrderDetailDialogStyle.navy,
                    side: OrderDetailDialogStyle.borderSide,
                    backgroundColor: OrderDetailDialogStyle.surface,
                    minimumSize: const Size(0, OrderDetailDialogStyle.fieldHeight),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: OrderDetailDialogStyle.controlBorderRadius,
                    ),
                  ),
                  child: Text(
                    closeLabel,
                    style: AppTypography.bodyMedium.copyWith(
                      color: OrderDetailDialogStyle.navy,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Footer text action in the detail dialog (e.g. edit / reverse).
class OrderDetailFooterAction extends StatelessWidget {
  const OrderDetailFooterAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor:
            danger ? OrderDetailDialogStyle.danger : OrderDetailDialogStyle.accent,
      ),
    );
  }
}

class OrderDetailInfoCard extends StatelessWidget {
  const OrderDetailInfoCard({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: OrderDetailDialogStyle.cardPadding,
      decoration: OrderDetailDialogStyle.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.caption.copyWith(
              color: OrderDetailDialogStyle.muted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Icon + single line value inside an [OrderDetailInfoCard].
class OrderDetailInfoValue extends StatelessWidget {
  const OrderDetailInfoValue({
    super.key,
    required this.icon,
    required this.value,
    this.ltr = false,
  });

  final IconData icon;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: OrderDetailDialogStyle.navy),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: ltr ? TextDirection.ltr : null,
            textAlign: TextAlign.start,
            style: AppTypography.bodyMedium.copyWith(
              color: OrderDetailDialogStyle.navy,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

/// Dot + label status pill in the detail dialog style.
class OrderDetailStatusBadge extends StatelessWidget {
  const OrderDetailStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.background,
  });

  final String label;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class OrderDetailSummaryRow extends StatelessWidget {
  const OrderDetailSummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
    this.mutedValue = false,
    this.dense = false,
    this.valueColor,
    this.ltrValue = false,
  });

  final String label;
  final String value;
  final bool highlight;
  final bool mutedValue;
  final bool dense;
  final Color? valueColor;
  final bool ltrValue;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: dense ? 5 : 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.body.copyWith(
                color: OrderDetailDialogStyle.navy,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                fontSize: dense ? 12 : 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textDirection: ltrValue ? TextDirection.ltr : null,
              textAlign: TextAlign.end,
              style: AppTypography.bodyMedium.copyWith(
                color: valueColor ??
                    (highlight
                        ? OrderDetailDialogStyle.accent
                        : (mutedValue
                            ? OrderDetailDialogStyle.muted
                            : OrderDetailDialogStyle.navy)),
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                fontSize: highlight ? (dense ? 13 : 14) : (dense ? 12 : 13),
              ),
            ),
          ),
        ],
      ),
    );

    if (!highlight) return row;
    return ColoredBox(
      color: OrderDetailDialogStyle.totalHighlight,
      child: row,
    );
  }
}

/// Bordered card stacking [OrderDetailSummaryRow]s with dividers.
class OrderDetailSummaryCard extends StatelessWidget {
  const OrderDetailSummaryCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: OrderDetailDialogStyle.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: OrderDetailDialogStyle.border),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Label/value pairs side by side, with an optional highlighted total strip,
/// matching the original read-only payment summary.
class OrderDetailStatPanel extends StatelessWidget {
  const OrderDetailStatPanel({
    super.key,
    required this.stats,
    this.highlights = const [],
  });

  final List<OrderDetailStat> stats;
  final List<OrderDetailStat> highlights;

  @override
  Widget build(BuildContext context) {
    Widget strip(List<OrderDetailStat> items, {required bool emphasize}) {
      return Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: OrderDetailDialogStyle.border,
              ),
            Expanded(child: _stat(items[i], emphasize: emphasize)),
          ],
        ],
      );
    }

    return Container(
      decoration: OrderDetailDialogStyle.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: strip(stats, emphasize: false),
            ),
          if (highlights.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: OrderDetailDialogStyle.totalHighlight,
              child: strip(highlights, emphasize: true),
            ),
        ],
      ),
    );
  }

  Widget _stat(OrderDetailStat stat, {required bool emphasize}) {
    final valueColor = stat.color ??
        (emphasize ? OrderDetailDialogStyle.accent : OrderDetailDialogStyle.navy);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          stat.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(
            color: OrderDetailDialogStyle.muted,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          stat.value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyMedium.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w700,
            fontSize: emphasize ? 15 : 13,
          ),
        ),
      ],
    );
  }
}

class OrderDetailStat {
  const OrderDetailStat(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;
}

/// Lines table in the detail dialog style (header strip + divided rows),
/// using the same [LedgerColumn] widths and cell padding as page tables.
class OrderDetailLinesTable extends StatelessWidget {
  const OrderDetailLinesTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyText = 'موردی نیست',
    this.showIndex = true,
  });

  final List<LedgerColumn> columns;
  final List<List<Widget>> rows;
  final String emptyText;
  final bool showIndex;

  static const _rowPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 10);

  @override
  Widget build(BuildContext context) {
    Widget index(String text, TextStyle style) => SizedBox(
          width: GfColumnWidth.rowNumber,
          child: Text(text, textAlign: TextAlign.center, style: style),
        );

    return Container(
      decoration: OrderDetailDialogStyle.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: OrderDetailDialogStyle.tableHeaderBg,
            padding: _rowPadding,
            child: Row(
              children: [
                if (showIndex) index('common.rowNumber'.tr(), _headerStyle),
                for (final c in columns)
                  c.cell(Text(c.label, textAlign: c.numeric ? TextAlign.end : TextAlign.start, style: _headerStyle)),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                emptyText,
                style: AppTypography.caption.copyWith(
                  color: OrderDetailDialogStyle.muted,
                ),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: OrderDetailDialogStyle.border,
                ),
              Padding(
                padding: _rowPadding,
                child: Row(
                  children: [
                    if (showIndex)
                      index(
                        '${i + 1}',
                        AppTypography.caption.copyWith(color: OrderDetailDialogStyle.muted),
                      ),
                    for (var c = 0; c < columns.length; c++)
                      columns[c].cell(
                        DefaultTextStyle.merge(
                          style: AppTypography.body.copyWith(
                            color: OrderDetailDialogStyle.navy,
                            fontSize: 13,
                          ),
                          child: c < rows[i].length ? rows[i][c] : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  static TextStyle get _headerStyle => AppTypography.caption.copyWith(
        color: OrderDetailDialogStyle.muted,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      );
}
