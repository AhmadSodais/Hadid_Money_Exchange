import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/gf_text_field.dart';
import '../../data/models/order_model.dart';
import '../../data/models/purchase_model.dart';
import 'order_detail_dialog_style.dart';

/// Shared row model so order + purchase view/edit tables use one widget.
class InvoiceProductLine {
  const InvoiceProductLine({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.productImagePath,
  });

  final String productName;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final String? productImagePath;

  factory InvoiceProductLine.fromOrderItem(OrderItemModel item) {
    return InvoiceProductLine(
      productName: item.productName,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      lineTotal: item.lineTotal,
      productImagePath: item.productImagePath,
    );
  }

  factory InvoiceProductLine.fromPurchaseItem(PurchaseItemModel item) {
    return InvoiceProductLine(
      productName: item.productName,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      lineTotal: item.lineTotal,
      productImagePath: item.productImagePath,
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

class OrderDetailPaymentBadge extends StatelessWidget {
  const OrderDetailPaymentBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status) {
      'paid' => (
          'orders.paid'.tr(),
          OrderDetailDialogStyle.success,
          OrderDetailDialogStyle.successBg,
        ),
      'partial' => (
          'orders.partial'.tr(),
          const Color(0xFFD97706),
          const Color(0xFFFEF3C7),
        ),
      _ => (
          'orders.unpaid'.tr(),
          const Color(0xFFDC2626),
          const Color(0xFFFEE2E2),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
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
  });

  final String label;
  final String value;
  final bool highlight;
  final bool mutedValue;
  final bool dense;

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
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: highlight
                  ? OrderDetailDialogStyle.accent
                  : (mutedValue
                      ? OrderDetailDialogStyle.muted
                      : OrderDetailDialogStyle.navy),
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              fontSize: highlight ? (dense ? 13 : 14) : (dense ? 12 : 13),
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

/// Compact editable payment summary (discount / paid + total / remaining).
class OrderDetailEditablePaymentSummary extends StatelessWidget {
  const OrderDetailEditablePaymentSummary({
    super.key,
    required this.currency,
    required this.discountCtrl,
    required this.paidCtrl,
    required this.total,
    required this.remaining,
    required this.onChanged,
    this.paidLabel,
  });

  final String currency;
  final TextEditingController discountCtrl;
  final TextEditingController paidCtrl;
  final double total;
  final double remaining;
  final VoidCallback onChanged;
  final String? paidLabel;

  static const double _fieldH = 36;

  bool get _hasRemaining => remaining > 0.0001;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: OrderDetailDialogStyle.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _labeledField(
                    label: 'sales.discount'.tr(),
                    controller: discountCtrl,
                  ),
                ),
                Container(
                  width: 1,
                  height: 52,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: OrderDetailDialogStyle.border,
                ),
                Expanded(
                  child: _labeledField(
                    label: paidLabel ?? 'sales.amountReceived'.tr(),
                    controller: paidCtrl,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: OrderDetailDialogStyle.totalHighlight,
            child: Row(
              children: [
                Expanded(
                  child: _stat(
                    label: 'sales.total'.tr(),
                    value: Formatters.money(total, currency: currency),
                    emphasize: true,
                  ),
                ),
                if (_hasRemaining) ...[
                  Container(
                    width: 1,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: OrderDetailDialogStyle.border,
                  ),
                  Expanded(
                    child: _stat(
                      label: 'sales.remaining'.tr(),
                      value: Formatters.money(remaining, currency: currency),
                      danger: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(
            color: OrderDetailDialogStyle.muted,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        GfTextField(
          controller: controller,
          numberMode: true,
          textAlign: TextAlign.end,
          height: _fieldH,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }

  Widget _stat({
    required String label,
    required String value,
    bool emphasize = false,
    bool danger = false,
  }) {
    final valueColor = danger
        ? OrderDetailDialogStyle.danger
        : (emphasize
              ? OrderDetailDialogStyle.accent
              : OrderDetailDialogStyle.navy);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
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
          value,
          maxLines: 1,
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

/// Compact read-only payment summary for invoice view dialogs.
class OrderDetailReadonlyPaymentSummary extends StatelessWidget {
  const OrderDetailReadonlyPaymentSummary({
    super.key,
    required this.currency,
    required this.total,
    required this.amountPaid,
    required this.remaining,
    this.discount = 0,
    this.paidLabel,
  });

  final String currency;
  final double total;
  final double amountPaid;
  final double remaining;
  final double discount;
  final String? paidLabel;

  bool get _hasDiscount => discount > 0.0001;
  bool get _hasRemaining => remaining > 0.0001;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: OrderDetailDialogStyle.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                if (_hasDiscount) ...[
                  Expanded(
                    child: _stat(
                      label: 'sales.discount'.tr(),
                      value:
                          '- ${Formatters.money(discount, currency: currency)}',
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: OrderDetailDialogStyle.border,
                  ),
                ],
                Expanded(
                  child: _stat(
                    label: paidLabel ?? 'sales.amountReceived'.tr(),
                    value: Formatters.money(amountPaid, currency: currency),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: OrderDetailDialogStyle.totalHighlight,
            child: Row(
              children: [
                Expanded(
                  child: _stat(
                    label: 'sales.total'.tr(),
                    value: Formatters.money(total, currency: currency),
                    emphasize: true,
                  ),
                ),
                if (_hasRemaining) ...[
                  Container(
                    width: 1,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: OrderDetailDialogStyle.border,
                  ),
                  Expanded(
                    child: _stat(
                      label: 'sales.remaining'.tr(),
                      value: Formatters.money(remaining, currency: currency),
                      danger: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required String label,
    required String value,
    bool emphasize = false,
    bool danger = false,
  }) {
    final valueColor = danger
        ? OrderDetailDialogStyle.danger
        : (emphasize
              ? OrderDetailDialogStyle.accent
              : OrderDetailDialogStyle.navy);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
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
          value,
          maxLines: 1,
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

class OrderDetailProductTable extends StatelessWidget {
  const OrderDetailProductTable({
    super.key,
    required this.lines,
    required this.currency,
  });

  final List<InvoiceProductLine> lines;
  final String currency;

  /// Convenience for order invoices.
  factory OrderDetailProductTable.fromOrderItems({
    Key? key,
    required List<OrderItemModel> items,
    required String currency,
  }) {
    return OrderDetailProductTable(
      key: key,
      lines: items.map(InvoiceProductLine.fromOrderItem).toList(),
      currency: currency,
    );
  }

  /// Convenience for purchase invoices.
  factory OrderDetailProductTable.fromPurchaseItems({
    Key? key,
    required List<PurchaseItemModel> items,
    required String currency,
  }) {
    return OrderDetailProductTable(
      key: key,
      lines: items.map(InvoiceProductLine.fromPurchaseItem).toList(),
      currency: currency,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: OrderDetailDialogStyle.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: OrderDetailDialogStyle.tableHeaderBg,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _h('#', width: 28),
                Expanded(flex: 4, child: _h('common.product'.tr())),
                _h('common.qty'.tr(), width: 44, align: TextAlign.center),
                Expanded(
                  flex: 2,
                  child: _h(
                    'inboundOutbound.unitPrice'.tr(),
                    align: TextAlign.end,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _h('orders.total'.tr(), align: TextAlign.end),
                ),
              ],
            ),
          ),
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'common.noData'.tr(),
                style: AppTypography.caption.copyWith(
                  color: OrderDetailDialogStyle.muted,
                ),
              ),
            )
          else
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: OrderDetailDialogStyle.border,
                ),
              _ProductRow(
                index: i + 1,
                line: lines[i],
                currency: currency,
              ),
            ],
        ],
      ),
    );
  }

  Widget _h(String text, {double? width, TextAlign align = TextAlign.start}) {
    final child = Text(
      text,
      textAlign: align,
      style: AppTypography.caption.copyWith(
        color: OrderDetailDialogStyle.muted,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );
    if (width != null) return SizedBox(width: width, child: child);
    return child;
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.index,
    required this.line,
    required this.currency,
  });

  final int index;
  final InvoiceProductLine line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$index',
              style: AppTypography.caption.copyWith(
                color: OrderDetailDialogStyle.muted,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                _Thumb(path: line.productImagePath),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      color: OrderDetailDialogStyle.navy,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              Formatters.number(line.quantity),
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: OrderDetailDialogStyle.muted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              Formatters.money(line.unitPrice, currency: currency),
              textAlign: TextAlign.end,
              style: AppTypography.body.copyWith(
                color: OrderDetailDialogStyle.muted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              Formatters.money(line.lineTotal, currency: currency),
              textAlign: TextAlign.end,
              style: AppTypography.bodyMedium.copyWith(
                color: OrderDetailDialogStyle.navy,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final p = (path ?? '').trim();
    Widget child = ColoredBox(
      color: OrderDetailDialogStyle.tableHeaderBg,
      child: Icon(
        Icons.image_outlined,
        size: 16,
        color: OrderDetailDialogStyle.muted,
      ),
    );
    if (p.isNotEmpty) {
      final file = File(p);
      if (file.existsSync()) {
        child = Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => child,
        );
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 32, height: 32, child: child),
    );
  }
}
