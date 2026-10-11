import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/purchase_model.dart';
import '../dialogs/purchase_dialog.dart';
import '../widgets/app_shell.dart';
import '../widgets/order_detail_dialog_style.dart';
import '../widgets/order_detail_info_card.dart';

enum _PaymentFilter { all, paid, partial, unpaid }

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _search = TextEditingController();
  DateFilterValue _dateFilter = DateFilterValue.today();
  _PaymentFilter _paymentFilter = _PaymentFilter.all;
  List<PurchaseModel> _items = const [];
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
    final result = await ServiceLocator.instance.purchases.list(
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

  Future<void> _newPurchase() async {
    final saved = await PurchaseDialog.show(context);
    if (saved == true && mounted) {
      GfToast.success(context, 'purchases.created'.tr());
      await _load();
    }
  }

  Future<void> _edit(PurchaseModel purchase) async {
    final saved = await PurchaseDialog.show(
      context,
      editingPurchaseId: purchase.id,
    );
    if (saved == true && mounted) {
      GfToast.success(context, 'purchases.updated'.tr());
      await _load();
    }
  }

  Future<void> _view(PurchaseModel purchase) async {
    final full = await ServiceLocator.instance.purchases.getById(purchase.id);
    if (!mounted) return;
    full.when(
      success: (p) =>
          PurchaseDetailDialog.show(context, p, onEdit: () => _edit(p)),
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _delete(PurchaseModel purchase) async {
    final ok = await GfConfirmDialog.show(
      context,
      title: 'purchases.deleteTitle'.tr(),
      message: 'purchases.deleteMessage'.tr(
        namedArgs: {'invoice': purchase.invoiceNumber},
      ),
      confirmLabel: 'common.delete'.tr(),
      danger: true,
    );
    if (ok != true || !mounted) return;
    final result = await ServiceLocator.instance.purchases.deletePurchase(
      purchase.id,
    );
    if (!mounted) return;
    result.when(
      success: (_) {
        GfToast.success(context, 'purchases.deleted'.tr());
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'purchases.title'.tr(),
      subtitle: 'purchases.pageSubtitle'.tr(),
      searchController: _search,
      searchHint: 'purchases.searchHint'.tr(),
      onSearch: (_) => _resetAndLoad(),
      actions: [
        GfDateFilter(
          value: _dateFilter,
          onChanged: (v) {
            setState(() => _dateFilter = v);
            _resetAndLoad();
          },
        ),
        GfPrimaryButton(
          label: 'purchases.newPurchase'.tr(),
          icon: Icons.add_rounded,
          onPressed: _newPurchase,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GfCountBox(
                label: 'purchases.totalCount'.tr(),
                count: _total,
                icon: AppAssets.inventoryFilled,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in _PaymentFilter.values)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: _FilterChip(
                            label: switch (f) {
                              _PaymentFilter.all => 'purchases.all'.tr(),
                              _PaymentFilter.paid => 'purchases.paid'.tr(),
                              _PaymentFilter.partial =>
                                'purchases.partial'.tr(),
                              _PaymentFilter.unpaid => 'purchases.unpaid'.tr(),
                            },
                            selected: _paymentFilter == f,
                            onTap: () {
                              setState(() => _paymentFilter = f);
                              _resetAndLoad();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: GfDataTable(
              title: 'purchases.tableTitle'.tr(),
              isLoading: _loading,
              minWidth: gfTableMinWidth(context, preferred: 1000),
              columns: [
                GfTableColumn(label: 'purchases.invoice'.tr(), flex: 2),
                GfTableColumn(label: 'purchases.supplier'.tr(), flex: 2),
                GfTableColumn(label: 'purchases.items'.tr(), flex: 1),
                GfTableColumn(label: 'purchases.total'.tr(), flex: 2),
                GfTableColumn(label: 'purchases.payment'.tr(), flex: 1),
                GfTableColumn(label: 'purchases.date'.tr(), flex: 2),
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
                title: 'purchases.empty'.tr(),
                subtitle: 'purchases.emptyHint'.tr(),
                compact: true,
              ),
              rowBuilder: (context, index) {
                final p = _items[index];
                final currency = p.currencyCode ?? 'AFN';
                return GfTableRow(
                  onTap: () => _view(p),
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        p.invoiceNumber,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        p.partnerName?.trim().isNotEmpty == true
                            ? p.partnerName!
                            : '—',
                        style: AppTypography.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${p.displayLineCount}',
                        style: AppTypography.bodyMedium,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        Formatters.money(p.total, currency: currency),
                        style: AppTypography.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _PaymentBadge(status: p.paymentStatus),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        Formatters.date(p.createdAt),
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
                              await _view(p);
                            case 'edit':
                              await _edit(p);
                            case 'delete':
                              await _delete(p);
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: selected ? AppColors.onPrimary : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
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
    final label = switch (status) {
      'paid' => 'purchases.paid'.tr(),
      'partial' => 'purchases.partial'.tr(),
      _ => 'purchases.unpaid'.tr(),
    };
    final color = switch (status) {
      'paid' => AppColors.success,
      'partial' => AppColors.warning,
      _ => AppColors.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class PurchaseDetailDialog {
  static Future<void> show(
    BuildContext context,
    PurchaseModel purchase, {
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
            child: _PurchaseDetailContent(
              purchase: purchase,
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

class _PurchaseDetailContent extends StatelessWidget {
  const _PurchaseDetailContent({
    required this.purchase,
    required this.onClose,
    this.onEdit,
  });

  final PurchaseModel purchase;
  final VoidCallback onClose;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final currency = purchase.currencyCode ?? 'AFN';
    final remaining = purchase.total - purchase.amountPaid;
    final remainingClamped = remaining > 0 ? remaining : 0.0;
    final supplier = purchase.partnerName?.trim().isNotEmpty == true
        ? purchase.partnerName!
        : '—';
    final invoiceTitle = '${'common.invoice'.tr()} #${purchase.invoiceNumber}';

    return OrderDetailDialogStyle.scrollLayout(
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
                    Formatters.dateTime(purchase.createdAt),
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
                  title: 'purchases.supplier'.tr(),
                  child: Row(
                    children: [
                      Icon(
                        Icons.business_outlined,
                        size: 18,
                        color: OrderDetailDialogStyle.navy,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          supplier,
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
                      OrderDetailPaymentBadge(status: purchase.paymentStatus),
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
          OrderDetailProductTable.fromPurchaseItems(
            items: purchase.items,
            currency: currency,
          ),
        ],
      ),
      footer: [
        OrderDetailDialogStyle.sectionSpace,
        OrderDetailReadonlyPaymentSummary(
          currency: currency,
          discount: purchase.discount,
          amountPaid: purchase.amountPaid,
          total: purchase.total,
          remaining: remainingClamped,
          paidLabel: 'purchases.amountPaid'.tr(),
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
