import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/pdf_report_helper.dart';
import '../../core/utils/shamsi_dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/order_model.dart';
import '../../data/models/stock_movement_model.dart';
import '../dialogs/edit_invoice_dialog.dart';
import '../widgets/app_shell.dart';
import '../widgets/order_detail_dialog_style.dart';
import '../widgets/order_detail_info_card.dart';

enum _PaymentFilter { all, paid, partial, unpaid }

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final _search = TextEditingController();
  DateFilterValue _dateFilter = DateFilterValue.today();
  _PaymentFilter _paymentFilter = _PaymentFilter.all;
  List<OrderModel> _items = const [];
  int _page = 1;
  int _pageSize = 50;
  int _total = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String? get _paymentStatusParam => switch (_paymentFilter) {
    _PaymentFilter.all => null,
    _PaymentFilter.paid => 'paid',
    _PaymentFilter.partial => 'partial',
    _PaymentFilter.unpaid => 'unpaid',
  };

  Future<void> _load({int? page}) async {
    final nextPage = page ?? _page;
    setState(() => _loading = true);
    final result = await ServiceLocator.instance.orders.list(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      from: _dateFilter.from,
      to: _dateFilter.to,
      paymentStatus: _paymentStatusParam,
      page: nextPage,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    result.when(
      success: (paged) => setState(() {
        _items = paged.items;
        _total = paged.total;
        _page = paged.page;
        _pageSize = paged.pageSize;
        _loading = false;
      }),
      failure: (f) {
        setState(() {
          _items = const [];
          _total = 0;
          _loading = false;
        });
        GfToast.error(context, f.message);
      },
    );
  }

  void _resetAndLoad() {
    _page = 1;
    _load(page: 1);
  }

  Future<void> _view(OrderModel order) async {
    final full = await ServiceLocator.instance.orders.getById(order.id);
    if (!mounted) return;
    full.when(
      success: (o) => OrderDetailDialog.show(
        context,
        o,
        onChanged: _load,
        onEdit: () => _edit(o),
      ),
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _edit(OrderModel order) async {
    final full = await ServiceLocator.instance.orders.getById(order.id);
    if (!mounted) return;
    final o = full.when(
      success: (order) => order,
      failure: (f) {
        GfToast.error(context, f.message);
        return null;
      },
    );
    if (o == null || !mounted) return;
    final saved = await EditInvoiceDialog.show(context, o);
    if (!mounted) return;
    if (saved == true) {
      GfToast.success(context, 'orders.updated'.tr());
    }
    await _load();
  }

  Future<void> _delete(OrderModel order) async {
    final ok = await GfConfirmDialog.show(
      context,
      title: 'orders.deleteTitle'.tr(),
      message: 'orders.deleteMessage'.tr(
        namedArgs: {'invoice': order.invoiceNumber},
      ),
      confirmLabel: 'common.delete'.tr(),
      danger: true,
    );
    if (ok != true || !mounted) return;
    final result = await ServiceLocator.instance.orders.deleteOrder(order.id);
    if (!mounted) return;
    result.when(
      success: (_) {
        GfToast.success(context, 'orders.deleted'.tr());
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _print(OrderModel order) async {
    final full = await ServiceLocator.instance.orders.getById(order.id);
    if (!mounted) return;
    await full.when(
      success: (o) async {
        final movements = [
          for (final item in o.items)
            StockMovementModel(
              id: item.movementId ?? item.id,
              productId: item.productId,
              productName: item.productName,
              productImagePath: item.productImagePath,
              movementType: StockMovementType.sale,
              quantity: -item.quantity.abs(),
              balanceAfter: 0,
              referenceType: o.partnerType,
              referenceId: o.partnerId,
              partnerName: o.partnerName,
              lengthM: item.lengthM,
              widthM: item.widthM,
              unitPrice: item.unitPrice,
              paidAmount: item.paidAmount,
              currencyId: item.currencyId ?? o.currencyId,
              currencyCode: o.currencyCode,
              warehouseId: item.warehouseId,
              createdAt: o.createdAt,
            ),
        ];
        final bytes = await PdfReportHelper.buildMovementsInvoice(
          context,
          periodLabel: ShamsiDates.formatDate(o.createdAt),
          kind: PdfMovementExportKind.outbound,
          movements: movements,
        );
        if (!mounted) return;
        await PdfReportHelper.printPdf(
          context,
          bytes: bytes,
          fileName:
              'glassflow_${o.invoiceNumber}_${PdfReportHelper.stamp()}.pdf',
        );
      },
      failure: (f) async => GfToast.error(context, f.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'orders.title'.tr(),
      subtitle: 'orders.pageSubtitle'.tr(),
      searchController: _search,
      searchHint: 'orders.searchHint'.tr(),
      onSearch: (_) => _resetAndLoad(),
      actions: [
        GfDateFilter(
          value: _dateFilter,
          onChanged: (v) {
            setState(() => _dateFilter = v);
            _resetAndLoad();
          },
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GfCountBox(
                label: 'orders.totalCount'.tr(),
                count: _total,
                icon: AppAssets.ordersFilled,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in _PaymentFilter.values) ...[
                        if (f != _PaymentFilter.values.first)
                          const SizedBox(width: 8),
                        _FilterChip(
                          label: switch (f) {
                            _PaymentFilter.all => 'orders.all'.tr(),
                            _PaymentFilter.paid => 'orders.paid'.tr(),
                            _PaymentFilter.partial => 'orders.partial'.tr(),
                            _PaymentFilter.unpaid => 'orders.unpaid'.tr(),
                          },
                          selected: _paymentFilter == f,
                          onTap: () {
                            setState(() => _paymentFilter = f);
                            _resetAndLoad();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: GfDataTable(
              title: 'orders.tableTitle'.tr(),
              isLoading: _loading,
              minWidth: gfTableMinWidth(context, preferred: 1000),
              columns: [
                GfTableColumn(label: 'orders.invoice'.tr(), flex: 2),
                GfTableColumn(label: 'orders.customer'.tr(), flex: 2),
                GfTableColumn(label: 'orders.items'.tr(), flex: 1),
                GfTableColumn(label: 'orders.total'.tr(), flex: 2),
                GfTableColumn(label: 'orders.payment'.tr(), flex: 1),
                GfTableColumn(label: 'orders.date'.tr(), flex: 2),
                const GfTableColumn(label: '', width: 48),
              ],
              rowCount: _items.length,
              total: _total,
              page: _page,
              pageSize: _pageSize,
              autoPageSize: true,
              onPageChanged: (p) => _load(page: p),
              onPageSizeChanged: (size) {
                if (size == _pageSize) return;
                setState(() {
                  _pageSize = size;
                  _page = 1;
                });
                _load(page: 1);
              },
              itemLabel: 'common.records'.tr(),
              empty: GfEmptyState(
                title: 'orders.empty'.tr(),
                subtitle: 'orders.emptyHint'.tr(),
                compact: true,
              ),
              rowBuilder: (context, i) {
                final o = _items[i];
                final currency = o.currencyCode ?? 'AFN';
                return GfTableRow(
                  onTap: () => _view(o),
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        o.invoiceNumber,
                        style: AppTypography.bodyMedium,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        o.partnerName?.trim().isNotEmpty == true
                            ? o.partnerName!
                            : 'sales.walkInCustomer'.tr(),
                        style: AppTypography.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${o.displayLineCount}',
                        style: AppTypography.body,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        Formatters.money(o.total, currency: currency),
                        style: AppTypography.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _PaymentBadge(status: o.paymentStatus),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        Formatters.date(o.createdAt),
                        style: AppTypography.body,
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18),
                        color: AppColors.modal,
                        onSelected: (action) async {
                          switch (action) {
                            case 'view':
                              await _view(o);
                            case 'edit':
                              await _edit(o);
                            case 'print':
                              await _print(o);
                            case 'delete':
                              await _delete(o);
                          }
                        },
                        itemBuilder: (_) => [
                          gfPopupMenuItem(
                            value: 'view',
                            label: 'common.view'.tr(),
                          ),
                          gfPopupMenuItem(
                            value: 'edit',
                            label: 'common.edit'.tr(),
                          ),
                          if (AppConstants.enablePrint)
                            gfPopupMenuItem(
                              value: 'print',
                              label: 'common.print'.tr(),
                            ),
                          gfPopupMenuItem(
                            value: 'delete',
                            label: 'common.delete'.tr(),
                            danger: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.label.copyWith(
              color: selected ? AppColors.onPrimary : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'paid' => ('orders.paid'.tr(), AppColors.success),
      'partial' => ('orders.partial'.tr(), AppColors.warning),
      _ => ('orders.unpaid'.tr(), AppColors.error),
    };
    return Text(
      label,
      style: AppTypography.caption.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class OrderDetailDialog {
  static Future<void> show(
    BuildContext context,
    OrderModel order, {
    VoidCallback? onChanged,
    VoidCallback? onEdit,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: const Color(0x661E293B),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: OrderDetailDialogStyle.maxWidth,
              minHeight: OrderDetailDialogStyle.minHeight,
              maxHeight: OrderDetailDialogStyle.maxHeight,
            ),
            decoration: OrderDetailDialogStyle.container,
            padding: OrderDetailDialogStyle.framePadding,
            child: _OrderDetailContent(
              order: order,
              onClose: () => Navigator.of(ctx).pop(),
              onEdit: onEdit == null
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      onEdit();
                    },
            ),
          ),
        );
      },
    );
  }
}

class _OrderDetailContent extends StatelessWidget {
  const _OrderDetailContent({
    required this.order,
    required this.onClose,
    this.onEdit,
  });

  final OrderModel order;
  final VoidCallback onClose;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final currency = order.currencyCode ?? 'AFN';
    final remaining = order.total - order.amountPaid;
    final remainingClamped = remaining > 0 ? remaining : 0.0;
    final customer = order.partnerName?.trim().isNotEmpty == true
        ? order.partnerName!
        : 'sales.walkInCustomer'.tr();
    final invoiceTitle = 'orders.invoiceTitle'.tr(
      namedArgs: {'invoice': order.invoiceNumber},
    );

    return OrderDetailDialogStyle.scrollLayout(
      header: [
        // Header
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
              child: Icon(
                Icons.receipt_long_outlined,
                color: OrderDetailDialogStyle.accent,
                size: 22,
              ),
            ),
            OrderDetailDialogStyle.rowGap,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoiceTitle,
                    style: AppTypography.sectionTitle.copyWith(
                      color: OrderDetailDialogStyle.navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Formatters.dateTime(order.createdAt),
                    style: AppTypography.caption.copyWith(
                      color: OrderDetailDialogStyle.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onClose,
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: OrderDetailInfoCard(
                  title: 'orders.customer'.tr(),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 18,
                        color: OrderDetailDialogStyle.navy,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          customer,
                          maxLines: 1,
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
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OrderDetailInfoCard(
                  title: 'orders.payment'.tr(),
                  child: Row(
                    children: [
                      OrderDetailPaymentBadge(status: order.paymentStatus),
                      const Spacer(),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: OrderDetailDialogStyle.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          OrderDetailDialogStyle.sectionSpace,
          OrderDetailProductTable.fromOrderItems(
            items: order.items,
            currency: currency,
          ),
        ],
      ),
      footer: [
        OrderDetailDialogStyle.sectionSpace,
        OrderDetailReadonlyPaymentSummary(
          currency: currency,
          discount: order.discount,
          amountPaid: order.amountPaid,
          total: order.total,
          remaining: remainingClamped,
        ),
        const SizedBox(height: 16),
        Divider(height: 1, color: OrderDetailDialogStyle.border),
        const SizedBox(height: 14),
        Row(
          children: [
            if (onEdit != null) ...[
              TextButton.icon(
                onPressed: onEdit,
                icon: Icon(Icons.edit_outlined, size: 16),
                label: Text('common.edit'.tr()),
                style: TextButton.styleFrom(
                  foregroundColor: OrderDetailDialogStyle.accent,
                ),
              ),
            ],
            const Spacer(),
            OutlinedButton(
              onPressed: onClose,
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
                'common.close'.tr(),
                style: AppTypography.bodyMedium.copyWith(
                  color: OrderDetailDialogStyle.navy,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
