import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_routes.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/company_share_helper.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/pdf_report_helper.dart';
import '../../core/utils/shamsi_dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/company_payment_model.dart';
import '../../data/models/order_model.dart';
import '../../data/models/purchase_model.dart';
import '../../data/models/stock_movement_model.dart';
import '../dialogs/edit_invoice_dialog.dart';
import '../dialogs/purchase_dialog.dart';
import '../dialogs/warehouse_dialog_shared.dart';
import '../providers/app_settings_provider.dart';
import '../widgets/app_shell.dart';
import 'orders_page.dart';
import 'purchases_page.dart';

/// Args passed when opening a company's purchase/sales activity screen.
class TradingCompanyArgs {
  const TradingCompanyArgs({
    required this.id,
    required this.name,
    required this.source,
    this.phone,
    this.address,
  });

  final int id;
  final String name;
  final String source; // supplier | customer
  final String? phone;
  final String? address;

  bool matchesMovement(StockMovementModel m) {
    final byRef =
        m.referenceType == source && m.referenceId != null && m.referenceId == id;
    final partner = (m.partnerName ?? '').trim().toLowerCase();
    final byName = partner.isNotEmpty && partner == name.trim().toLowerCase();
    return byRef || byName;
  }
}

/// Full-screen purchase / sales / payment history for one trading company.
class TradingCompanyActivityPage extends StatefulWidget {
  const TradingCompanyActivityPage({super.key, required this.company});

  final TradingCompanyArgs company;

  @override
  State<TradingCompanyActivityPage> createState() =>
      _TradingCompanyActivityPageState();
}

enum _CompanyTab { purchases, sales, payments }

class _TradingCompanyActivityPageState
    extends State<TradingCompanyActivityPage> {
  DateFilterValue _dateFilter = DateFilterValue.thisYear();
  List<PurchaseModel> _purchases = const [];
  List<OrderModel> _orders = const [];
  List<StockMovementModel> _movements = const [];
  List<CompanyPaymentModel> _payments = const [];
  late _CompanyTab _tab;
  bool _loading = true;
  bool _sharing = false;

  bool get _isCustomer => widget.company.source == 'customer';

  @override
  void initState() {
    super.initState();
    // Customers → sales; companies/suppliers → purchases.
    _tab = _isCustomer ? _CompanyTab.sales : _CompanyTab.purchases;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final inventory = ServiceLocator.instance.inventory;
    final c = widget.company;
    final purchasesResult = await ServiceLocator.instance.purchases.list(
      partnerType: c.source,
      partnerId: c.id,
      partnerName: c.name,
      from: _dateFilter.from,
      to: _dateFilter.to,
      page: 1,
      pageSize: 2000,
    );
    final ordersResult = await ServiceLocator.instance.orders.list(
      partnerType: c.source,
      partnerId: c.id,
      partnerName: c.name,
      from: _dateFilter.from,
      to: _dateFilter.to,
      page: 1,
      pageSize: 2000,
    );
    final movementsResult = await inventory.getMovements(
      from: _dateFilter.from,
      to: _dateFilter.to,
      limit: 1000,
      excludeOrderLinked: false,
      excludePurchaseLinked: false,
      partnerType: c.source,
      partnerId: c.id,
      partnerName: c.name,
    );
    final paymentsResult = await inventory.getCompanyPayments(
      partnerType: c.source,
      partnerId: c.id,
    );
    if (!mounted) return;
    setState(() {
      _purchases = purchasesResult.when(
        success: (paged) => paged.items,
        failure: (_) => const [],
      );
      _orders = ordersResult.when(
        success: (paged) => paged.items,
        failure: (_) => const [],
      );
      _movements = movementsResult.when(
        success: (list) => list,
        failure: (_) => const [],
      );
      _payments = paymentsResult.when(
        success: (list) => list,
        failure: (_) => const [],
      );
      _loading = false;
    });
  }

  List<PurchaseModel> get _filteredPurchases => _purchases;

  List<OrderModel> get _filteredOrders => _orders;

  List<StockMovementModel> get _filtered => _movements;

  /// Purchase-linked stock (payable side).
  bool _isPurchaseMove(StockMovementModel m) => m.quantity >= 0;

  Map<String, double> _invoiceBalances({
    required bool payable,
    required String fallbackCurrency,
  }) {
    final map = <String, double>{
      for (final code in _paymentCurrencyCodes) code: 0,
    };
    if (payable) {
      for (final p in _purchases) {
        final due = p.total - p.amountPaid;
        if (due <= 0) continue;
        final code = _normalizeCurrency(p.currencyCode, fallbackCurrency);
        map[code] = (map[code] ?? 0) + due;
      }
    } else {
      for (final o in _orders) {
        final due = o.total - o.amountPaid;
        if (due <= 0) continue;
        final code = _normalizeCurrency(o.currencyCode, fallbackCurrency);
        map[code] = (map[code] ?? 0) + due;
      }
    }
    return map;
  }

  Future<void> _shareReport(List<StockMovementModel> rows) async {
    if (_sharing) return;
    if (!_dateFilter.supportsPdfExport) {
      GfToast.error(context, 'pdfReport.pdfNotForYear'.tr());
      return;
    }
    final kind = await _pickExportKind();
    if (kind == null || !mounted) return;

    // inbound enum = purchases; outbound enum = sales (company-scoped PDF).
    final scoped = switch (kind) {
      PdfMovementExportKind.inbound => rows.where(_isPurchaseMove).toList(),
      PdfMovementExportKind.outbound =>
        rows.where((m) => !_isPurchaseMove(m)).toList(),
      PdfMovementExportKind.both => rows,
    };

    setState(() => _sharing = true);
    try {
      final bytes = await PdfReportHelper.buildCompanyReport(
        context,
        companyName: widget.company.name,
        companyPhone: widget.company.phone,
        companyAddress: widget.company.address,
        periodLabel: _dateFilter.exportPeriodLabel,
        movements: scoped,
        kind: kind,
        purchaseSubject: 'tradingCompanies.pdfPurchases'.tr(),
        salesSubject: 'tradingCompanies.pdfSales'.tr(),
      );
      if (!mounted) return;
      var safeName =
          widget.company.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
      if (safeName.length > 40) safeName = safeName.substring(0, 40);
      if (safeName.isEmpty) safeName = 'company';
      final tag = switch (kind) {
        PdfMovementExportKind.outbound => 'sales',
        PdfMovementExportKind.inbound => 'purchases',
        PdfMovementExportKind.both => 'both',
      };
      await PdfReportHelper.savePdf(
        context,
        bytes: bytes,
        fileName: 'glassflow_${safeName}_${tag}_${PdfReportHelper.stamp()}.pdf',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _sharePaymentStatement() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await PdfReportHelper.buildCompanyPaymentStatement(
        context,
        companyName: widget.company.name,
        payments: _payments,
        movements: _movements,
      );
      if (!mounted) return;
      var safeName =
          widget.company.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
      if (safeName.length > 40) safeName = safeName.substring(0, 40);
      if (safeName.isEmpty) safeName = 'company';
      await PdfReportHelper.savePdf(
        context,
        bytes: bytes,
        fileName:
            'glassflow_${safeName}_statement_${PdfReportHelper.stamp()}.pdf',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareCompanyInfo() async {
    final kind = await _pickExportKind(
      titleKey: 'tradingCompanies.shareOptionsTitle',
      subtitleKey: 'tradingCompanies.shareOptionsSubtitle',
    );
    if (kind == null || !mounted) return;

    final c = widget.company;
    final purchases = switch (kind) {
      PdfMovementExportKind.inbound || PdfMovementExportKind.both =>
        _filteredPurchases,
      PdfMovementExportKind.outbound => const <PurchaseModel>[],
    };
    final sales = switch (kind) {
      PdfMovementExportKind.outbound || PdfMovementExportKind.both =>
        _filteredOrders,
      PdfMovementExportKind.inbound => const <OrderModel>[],
    };
    final baseCurrency = context.read<AppSettingsProvider>().baseCurrency;
    final fallbackCurrency = baseCurrency.isNotEmpty
        ? baseCurrency
        : AppConstants.defaultCurrencyCode;

    String invoiceMoney(Iterable<({String? currency, double total})> rows) {
      final byCurrency = <String, double>{};
      for (final r in rows) {
        if (r.total <= 0) continue;
        final code = _normalizeCurrency(r.currency, fallbackCurrency);
        byCurrency[code] = (byCurrency[code] ?? 0) + r.total;
      }
      return Formatters.moneyByCurrency(
        byCurrency,
        fallbackCurrency: fallbackCurrency,
      );
    }

    final recent = <CompanyShareMovementLine>[
      for (final p in purchases.take(8))
        CompanyShareMovementLine(
          date: Formatters.date(p.createdAt),
          type: 'tradingCompanies.purchasesTab'.tr(),
          product: p.invoiceNumber,
          quantity: '1',
          price: Formatters.money(
            p.total,
            currency: _normalizeCurrency(p.currencyCode, fallbackCurrency),
          ),
        ),
      for (final o in sales.take(8))
        CompanyShareMovementLine(
          date: Formatters.date(o.createdAt),
          type: 'tradingCompanies.salesTab'.tr(),
          product: o.invoiceNumber,
          quantity: '1',
          price: Formatters.money(
            o.total,
            currency: _normalizeCurrency(o.currencyCode, fallbackCurrency),
          ),
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));

    final text = await CompanyShareHelper.buildProfileText(
      companyName: c.name,
      phone: c.phone,
      activity: CompanyShareActivitySummary(
        periodLabel: _dateFilter.exportPeriodLabel,
        purchasesCount: purchases.length,
        salesCount: sales.length,
        purchasesQtyLabel: Formatters.number(purchases.length.toDouble()),
        salesQtyLabel: Formatters.number(sales.length.toDouble()),
        purchasesValueLabel: invoiceMoney(
          purchases.map((p) => (currency: p.currencyCode, total: p.total)),
        ),
        salesValueLabel: invoiceMoney(
          sales.map((o) => (currency: o.currencyCode, total: o.total)),
        ),
      ),
      recentMovements: recent.take(8).toList(),
    );
    if (!mounted) return;
    await CompanyShareHelper.shareText(
      context,
      text: text,
      subject: c.name,
    );
  }

  Future<PdfMovementExportKind?> _pickExportKind({
    String titleKey = 'tradingCompanies.shareOptionsTitle',
    String subtitleKey = 'tradingCompanies.shareOptionsSubtitle',
  }) {
    return showDialog<PdfMovementExportKind>(
      context: context,
      builder: (ctx) {
        Widget option({
          required PdfMovementExportKind kind,
          required String title,
          required String hint,
          required IconData icon,
          required Color color,
        }) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(ctx).pop(kind),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: AppTypography.localize(
                                AppTypography.bodySemiBold,
                                context: ctx,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hint,
                              style: AppTypography.localize(
                                AppTypography.caption,
                                context: ctx,
                              ).copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return GfDialogShell(
          icon: Icons.receipt_long_outlined,
          title: titleKey.tr(),
          subtitle: subtitleKey.tr(),
          onCancel: () => Navigator.of(ctx).pop(),
          maxWidth: 420,
          maxHeight: 420,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(
                kind: PdfMovementExportKind.inbound,
                title: 'tradingCompanies.pdfPurchases'.tr(),
                hint: 'tradingCompanies.exportPurchasesHint'.tr(),
                icon: Icons.shopping_cart_outlined,
                color: AppColors.success,
              ),
              option(
                kind: PdfMovementExportKind.outbound,
                title: 'tradingCompanies.pdfSales'.tr(),
                hint: 'tradingCompanies.exportSalesHint'.tr(),
                icon: Icons.point_of_sale_outlined,
                color: AppColors.error,
              ),
              option(
                kind: PdfMovementExportKind.both,
                title: 'tradingCompanies.pdfBoth'.tr(),
                hint: 'tradingCompanies.exportBothHint'.tr(),
                icon: Icons.swap_vert_rounded,
                color: AppColors.primary,
              ),
            ],
          ),
        );
      },
    );
  }

  static const _paymentCurrencyCodes = ['AFN', 'USD', 'EUR'];

  Future<void> _addPayment() => _openPaymentForm();

  Future<void> _editPayment(CompanyPaymentModel payment) =>
      _openPaymentForm(existing: payment);

  String _normalizeCurrency(String? code, String fallback) {
    final c = (code ?? '').trim().toUpperCase();
    if (c.isEmpty) return fallback.toUpperCase();
    return c;
  }

  String _preferredPaymentCurrency(
    Map<String, double> outstandingByCurrency,
    String fallback,
  ) {
    // Prefer a configured currency that currently has outstanding.
    for (final code in _paymentCurrencyCodes) {
      if ((outstandingByCurrency[code] ?? 0) > 0) return code;
    }
    final fallbackCode = fallback.toUpperCase();
    if (_paymentCurrencyCodes.contains(fallbackCode)) return fallbackCode;
    return _paymentCurrencyCodes.first;
  }

  Future<void> _openPaymentForm({CompanyPaymentModel? existing}) async {
    final baseCurrency = context.read<AppSettingsProvider>().baseCurrency;
    final fallback = baseCurrency.isNotEmpty
        ? baseCurrency
        : AppConstants.defaultCurrencyCode;

    Map<String, double> balancesFor({required bool payable}) {
      return _invoiceBalances(
        payable: payable,
        fallbackCurrency: fallback,
      );
    }

    final payableByCurrency = balancesFor(payable: true);
    final receivableByCurrency = balancesFor(payable: false);

    // When editing, treat the current payment amount as available again on its side.
    if (existing != null) {
      final code = _normalizeCurrency(existing.currency, fallback);
      final target = existing.settlementSide == PaymentSettlementSide.payable
          ? payableByCurrency
          : receivableByCurrency;
      target[code] = (target[code] ?? 0) + existing.amount;
    }

    PaymentSettlementSide defaultSide() {
      if (existing != null) return existing.settlementSide;
      final payableDue =
          payableByCurrency.values.fold<double>(0, (a, b) => a + b);
      final receivableDue =
          receivableByCurrency.values.fold<double>(0, (a, b) => a + b);
      if (payableDue > 0 && receivableDue <= 0) {
        return PaymentSettlementSide.payable;
      }
      if (receivableDue > 0 && payableDue <= 0) {
        return PaymentSettlementSide.receivable;
      }
      return PaymentSettlementSide.payable;
    }

    final side = defaultSide();
    final sideOutstanding = side == PaymentSettlementSide.payable
        ? payableByCurrency
        : receivableByCurrency;

    final result = await showDialog<_PaymentFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentFormDialog(
        defaultCurrency: existing != null
            ? _normalizeCurrency(existing.currency, fallback)
            : _preferredPaymentCurrency(sideOutstanding, fallback),
        payableByCurrency: payableByCurrency,
        receivableByCurrency: receivableByCurrency,
        existing: existing,
        defaultSide: side,
      ),
    );
    if (result == null || !mounted) return;

    final inventory = ServiceLocator.instance.inventory;
    final save = existing == null
        ? await inventory.addCompanyPayment(
            partnerType: widget.company.source,
            partnerId: widget.company.id,
            partnerName: widget.company.name,
            amount: result.amount,
            currency: result.currency,
            paidAt: result.paidAt,
            settlementSide: result.settlementSide,
            notes: result.notes,
          )
        : await inventory.updateCompanyPayment(
            paymentId: existing.id,
            amount: result.amount,
            currency: result.currency,
            paidAt: result.paidAt,
            settlementSide: result.settlementSide,
            notes: result.notes,
          );
    if (!mounted) return;
    save.when(
      success: (_) {
        GfToast.success(
          context,
          existing == null
              ? 'tradingCompanies.paymentAdded'.tr()
              : 'tradingCompanies.paymentUpdated'.tr(),
        );
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _deletePayment(CompanyPaymentModel payment) async {
    final confirmed = await GfConfirmDialog.show(
      context,
      title: 'tradingCompanies.deletePaymentTitle'.tr(),
      message: 'tradingCompanies.deletePaymentMessage'.tr(),
      confirmLabel: 'common.delete'.tr(),
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    final result = await ServiceLocator.instance.inventory
        .deleteCompanyPayment(payment.id);
    if (!mounted) return;
    result.when(
      success: (_) {
        GfToast.success(context, 'tradingCompanies.paymentDeleted'.tr());
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _viewPurchase(PurchaseModel purchase) async {
    final full =
        await ServiceLocator.instance.purchases.getById(purchase.id);
    if (!mounted) return;
    full.when(
      success: (p) => PurchaseDetailDialog.show(
        context,
        p,
        onEdit: () => _editPurchase(p),
      ),
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _editPurchase(PurchaseModel purchase) async {
    final saved = await PurchaseDialog.show(
      context,
      editingPurchaseId: purchase.id,
    );
    if (!mounted) return;
    if (saved == true) {
      GfToast.success(context, 'purchases.updated'.tr());
      await _load();
    }
  }

  Future<void> _deletePurchase(PurchaseModel purchase) async {
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
    final result =
        await ServiceLocator.instance.purchases.deletePurchase(purchase.id);
    if (!mounted) return;
    result.when(
      success: (_) {
        GfToast.success(context, 'purchases.deleted'.tr());
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _printPurchase(PurchaseModel purchase) async {
    final full =
        await ServiceLocator.instance.purchases.getById(purchase.id);
    if (!mounted) return;
    await full.when(
      success: (p) async {
        final movements = [
          for (final item in p.items)
            StockMovementModel(
              id: item.movementId ?? item.id,
              productId: item.productId,
              productName: item.productName,
              productImagePath: item.productImagePath,
              movementType: StockMovementType.purchase,
              quantity: item.quantity.abs(),
              balanceAfter: 0,
              referenceType: p.partnerType,
              referenceId: p.partnerId,
              partnerName: p.partnerName,
              lengthM: item.lengthM,
              widthM: item.widthM,
              unitPrice: item.unitPrice,
              paidAmount: item.paidAmount,
              currencyId: item.currencyId ?? p.currencyId,
              currencyCode: p.currencyCode,
              warehouseId: item.warehouseId,
              createdAt: p.createdAt,
            ),
        ];
        final bytes = await PdfReportHelper.buildMovementsInvoice(
          context,
          periodLabel: ShamsiDates.formatDate(p.createdAt),
          kind: PdfMovementExportKind.inbound,
          movements: movements,
        );
        if (!mounted) return;
        await PdfReportHelper.printPdf(
          context,
          bytes: bytes,
          fileName:
              'glassflow_${p.invoiceNumber}_${PdfReportHelper.stamp()}.pdf',
        );
      },
      failure: (f) async => GfToast.error(context, f.message),
    );
  }

  Future<void> _viewSale(OrderModel order) async {
    final full = await ServiceLocator.instance.orders.getById(order.id);
    if (!mounted) return;
    full.when(
      success: (o) => OrderDetailDialog.show(
        context,
        o,
        onChanged: _load,
        onEdit: () => _editSale(o),
      ),
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _editSale(OrderModel order) async {
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

  Future<void> _deleteSale(OrderModel order) async {
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

  Future<void> _printSale(OrderModel order) async {
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

  Future<void> _printPayment(CompanyPaymentModel payment) async {
    final bytes = await PdfReportHelper.buildCompanyPaymentStatement(
      context,
      companyName: widget.company.name,
      payments: [payment],
      movements: _movements,
    );
    if (!mounted) return;
    await PdfReportHelper.printPdf(
      context,
      bytes: bytes,
      fileName:
          'glassflow_payment_${payment.id}_${PdfReportHelper.stamp()}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final company = widget.company;
    final baseCurrency = context.watch<AppSettingsProvider>().baseCurrency;
    final fallbackCurrency = baseCurrency.isNotEmpty
        ? baseCurrency
        : AppConstants.defaultCurrencyCode;
    final purchaseRows = _filteredPurchases;
    final salesRows = _filteredOrders;

    final payableByCurrency = _invoiceBalances(
      payable: true,
      fallbackCurrency: fallbackCurrency,
    );
    final receivableByCurrency = _invoiceBalances(
      payable: false,
      fallbackCurrency: fallbackCurrency,
    );

    String weOweTitle(String code) => switch (code) {
          'AFN' => 'tradingCompanies.weOweAfn'.tr(),
          'USD' => 'tradingCompanies.weOweUsd'.tr(),
          'EUR' => 'tradingCompanies.weOweEur'.tr(),
          _ => 'tradingCompanies.weOwe'.tr(namedArgs: {'currency': code}),
        };
    String theyOweTitle(String code) => switch (code) {
          'AFN' => 'tradingCompanies.theyOweAfn'.tr(),
          'USD' => 'tradingCompanies.theyOweUsd'.tr(),
          'EUR' => 'tradingCompanies.theyOweEur'.tr(),
          _ => 'tradingCompanies.theyOwe'.tr(namedArgs: {'currency': code}),
        };

    List<Widget> sideKpis(
      Map<String, double> byCurrency, {
      required String Function(String code) titleOf,
      required GfKpiTone tone,
    }) {
      return [
        for (final code in _paymentCurrencyCodes)
          if ((byCurrency[code] ?? 0) > 0.0001)
            GfKpiCard(
              title: titleOf(code),
              value: Formatters.money(byCurrency[code]!, currency: code),
              icon: AppAssets.order,
              tone: tone,
            ),
      ];
    }

    return PageScaffold(
      leading: Row(
        children: [
          GfIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'common.back'.tr(),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(
                  _isCustomer
                      ? AppRoutes.customers
                      : AppRoutes.tradingCompanies,
                );
              }
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company.name,
                  style: AppTypography.localize(
                    AppTypography.pageTitle,
                    context: context,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _isCustomer
                      ? 'customers.activitySubtitle'.tr(
                          namedArgs: {'sales': '${salesRows.length}'},
                        )
                      : 'tradingCompanies.activitySubtitle'.tr(
                          namedArgs: {
                            'purchases': '${purchaseRows.length}',
                            'sales': '${salesRows.length}',
                          },
                        ),
                  style: AppTypography.localize(
                    AppTypography.subtitle,
                    context: context,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      title: company.name,
      actions: [
        if (_tab == _CompanyTab.purchases || _tab == _CompanyTab.sales) ...[
          GfDateFilter(
            value: _dateFilter,
            onChanged: (v) => setState(() => _dateFilter = v),
          ),
          if (AppConstants.enableShare)
            GfSecondaryButton(
              label: 'common.share'.tr(),
              icon: Icons.share_outlined,
              onPressed: () => _shareCompanyInfo(),
            ),
          if (AppConstants.enablePdfExport)
            GfSecondaryButton(
              label: 'common.generatePdf'.tr(),
              icon: Icons.ios_share_rounded,
              isLoading: _sharing,
              onPressed: _sharing ||
                      _loading ||
                      !_dateFilter.supportsPdfExport
                  ? null
                  : () => _shareReport(_filtered),
            ),
        ],
        if (_tab == _CompanyTab.payments) ...[
          if (AppConstants.enablePdfExport)
            GfSecondaryButton(
              label: 'common.generatePdf'.tr(),
              icon: Icons.ios_share_rounded,
              isLoading: _sharing,
              onPressed: _sharing || _loading ? null : _sharePaymentStatement,
            ),
          GfPrimaryButton(
            label: 'tradingCompanies.addPayment'.tr(),
            icon: Icons.payments_outlined,
            onPressed: _addPayment,
          ),
        ],
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfKpiGrid(
            children: [
              if (!_isCustomer)
                GfKpiCard(
                  title: 'tradingCompanies.totalPurchases'.tr(),
                  value: Formatters.number(purchaseRows.length.toDouble()),
                  icon: AppAssets.inventory,
                ),
              if (_isCustomer)
                GfKpiCard(
                  title: 'tradingCompanies.totalSales'.tr(),
                  value: Formatters.number(salesRows.length.toDouble()),
                  icon: AppAssets.sales,
                  tone: GfKpiTone.error,
                ),
              if (!_isCustomer)
                ...sideKpis(
                  payableByCurrency,
                  titleOf: weOweTitle,
                  tone: GfKpiTone.error,
                ),
              if (_isCustomer)
                ...sideKpis(
                  receivableByCurrency,
                  titleOf: theyOweTitle,
                  tone: GfKpiTone.warning,
                ),
            ],
          ),
          SizedBox(height: gfSectionGap(context)),
          _CompanyTabBar(
            tab: _tab,
            isCustomer: _isCustomer,
            onChanged: (t) => setState(() => _tab = t),
          ),
          SizedBox(height: gfSectionGap(context)),
          Expanded(
            child: switch (_tab) {
              _CompanyTab.purchases => _InvoicesTab(
                  title: 'tradingCompanies.purchasesTab'.tr(),
                  loading: _loading,
                  emptyTitle: 'tradingCompanies.noPurchases'.tr(),
                  emptyHint: 'tradingCompanies.noPurchasesHint'.tr(),
                  rows: [
                    for (final p in purchaseRows)
                      _InvoiceRowData.purchase(p, fallbackCurrency),
                  ],
                  onView: (row) {
                    final p = row.purchase;
                    if (p != null) _viewPurchase(p);
                  },
                  onEdit: (row) {
                    final p = row.purchase;
                    if (p != null) _editPurchase(p);
                  },
                  onPrint: (row) {
                    final p = row.purchase;
                    if (p != null) _printPurchase(p);
                  },
                  onDelete: (row) {
                    final p = row.purchase;
                    if (p != null) _deletePurchase(p);
                  },
                ),
              _CompanyTab.sales => _InvoicesTab(
                  title: 'tradingCompanies.salesTab'.tr(),
                  loading: _loading,
                  emptyTitle: 'tradingCompanies.noSales'.tr(),
                  emptyHint: 'tradingCompanies.noSalesHint'.tr(),
                  rows: [
                    for (final o in salesRows)
                      _InvoiceRowData.sale(o, fallbackCurrency),
                  ],
                  onView: (row) {
                    final o = row.order;
                    if (o != null) _viewSale(o);
                  },
                  onEdit: (row) {
                    final o = row.order;
                    if (o != null) _editSale(o);
                  },
                  onPrint: (row) {
                    final o = row.order;
                    if (o != null) _printSale(o);
                  },
                  onDelete: (row) {
                    final o = row.order;
                    if (o != null) _deleteSale(o);
                  },
                ),
              _CompanyTab.payments => _PaymentsTab(
                  payments: _payments,
                  loading: _loading,
                  onView: _editPayment,
                  onEdit: _editPayment,
                  onPrint: _printPayment,
                  onDelete: _deletePayment,
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _CompanyTabBar extends StatelessWidget {
  const _CompanyTabBar({
    required this.tab,
    required this.onChanged,
    required this.isCustomer,
  });

  final _CompanyTab tab;
  final ValueChanged<_CompanyTab> onChanged;
  final bool isCustomer;

  @override
  Widget build(BuildContext context) {
    Widget chip(_CompanyTab value, String label) {
      final selected = tab == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onChanged(value),
        selectedColor: AppColors.primary.withValues(alpha: 0.15),
        labelStyle: AppTypography.label.copyWith(
          color: selected ? AppColors.primary : AppColors.textMuted,
        ),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
        backgroundColor: AppColors.card,
      );
    }

    return Wrap(
      spacing: 8,
      children: [
        if (!isCustomer)
          chip(_CompanyTab.purchases, 'tradingCompanies.tabPurchases'.tr()),
        if (isCustomer)
          chip(_CompanyTab.sales, 'tradingCompanies.tabSales'.tr()),
        chip(_CompanyTab.payments, 'tradingCompanies.tabPayments'.tr()),
      ],
    );
  }
}

class _InvoiceRowData {
  const _InvoiceRowData({
    required this.date,
    required this.invoice,
    required this.total,
    required this.paid,
    required this.currency,
    required this.status,
    this.purchase,
    this.order,
  });

  factory _InvoiceRowData.purchase(
    PurchaseModel p,
    String fallbackCurrency,
  ) {
    return _InvoiceRowData(
      date: p.createdAt,
      invoice: p.invoiceNumber,
      total: p.total,
      paid: p.amountPaid,
      currency: p.currencyCode ?? fallbackCurrency,
      status: p.paymentStatus,
      purchase: p,
    );
  }

  factory _InvoiceRowData.sale(OrderModel o, String fallbackCurrency) {
    return _InvoiceRowData(
      date: o.createdAt,
      invoice: o.invoiceNumber,
      total: o.total,
      paid: o.amountPaid,
      currency: o.currencyCode ?? fallbackCurrency,
      status: o.paymentStatus,
      order: o,
    );
  }

  final DateTime date;
  final String invoice;
  final double total;
  final double paid;
  final String currency;
  final String status;
  final PurchaseModel? purchase;
  final OrderModel? order;

  double get remaining {
    final r = total - paid;
    return r < 0 ? 0 : r;
  }
}

class _InvoicesTab extends StatelessWidget {
  const _InvoicesTab({
    required this.title,
    required this.loading,
    required this.emptyTitle,
    required this.emptyHint,
    required this.rows,
    required this.onView,
    required this.onEdit,
    required this.onPrint,
    required this.onDelete,
  });

  final String title;
  final bool loading;
  final String emptyTitle;
  final String emptyHint;
  final List<_InvoiceRowData> rows;
  final ValueChanged<_InvoiceRowData> onView;
  final ValueChanged<_InvoiceRowData> onEdit;
  final ValueChanged<_InvoiceRowData> onPrint;
  final ValueChanged<_InvoiceRowData> onDelete;

  @override
  Widget build(BuildContext context) {
    return GfDataTable(
      title: title,
      minWidth: gfTableMinWidth(context, preferred: 780),
      isLoading: loading,
      columns: [
        GfTableColumn(label: 'common.date'.tr(), flex: 2),
        GfTableColumn(label: 'purchases.invoice'.tr(), flex: 2),
        GfTableColumn(label: 'sales.total'.tr(), flex: 2),
        GfTableColumn(label: 'sales.amountReceived'.tr(), flex: 2),
        GfTableColumn(label: 'sales.remaining'.tr(), flex: 2),
        GfTableColumn(label: 'common.status'.tr(), flex: 2),
        const GfTableColumn(label: '', width: 48),
      ],
      rowCount: rows.length,
      total: rows.length,
      clientSide: true,
      itemLabel: 'common.records'.tr(),
      empty: GfEmptyState(
        title: emptyTitle,
        subtitle: emptyHint,
        compact: true,
      ),
      rowBuilder: (context, i) {
        final row = rows[i];
        final currency = row.currency;
        final statusColor = switch (row.status) {
          'paid' => AppColors.success,
          'partial' => AppColors.warning,
          _ => AppColors.error,
        };
        return GfTableRow(
          onTap: () => onView(row),
          children: [
            Expanded(
              flex: 2,
              child: Text(
                Formatters.date(row.date),
                style: AppTypography.body,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                row.invoice,
                style: AppTypography.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                Formatters.money(row.total, currency: currency),
                style: AppTypography.body,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                Formatters.money(row.paid, currency: currency),
                style: AppTypography.body,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                Formatters.money(row.remaining, currency: currency),
                style: AppTypography.bodyMedium,
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: GfStatusBadge(
                  label: 'purchases.${row.status}'.tr(),
                  color: statusColor,
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                color: AppColors.modal,
                onSelected: (action) {
                  switch (action) {
                    case 'view':
                      onView(row);
                    case 'edit':
                      onEdit(row);
                    case 'print':
                      onPrint(row);
                    case 'delete':
                      onDelete(row);
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
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({
    required this.payments,
    required this.loading,
    required this.onView,
    required this.onEdit,
    required this.onPrint,
    required this.onDelete,
  });

  final List<CompanyPaymentModel> payments;
  final bool loading;
  final ValueChanged<CompanyPaymentModel> onView;
  final ValueChanged<CompanyPaymentModel> onEdit;
  final ValueChanged<CompanyPaymentModel> onPrint;
  final ValueChanged<CompanyPaymentModel> onDelete;

  @override
  Widget build(BuildContext context) {
    return GfDataTable(
      title: 'tradingCompanies.tabPayments'.tr(),
      minWidth: gfTableMinWidth(context, preferred: 640),
      isLoading: loading,
      columns: [
        GfTableColumn(label: 'common.date'.tr(), flex: 2),
        GfTableColumn(label: 'tradingCompanies.settlementSide'.tr(), flex: 2),
        GfTableColumn(label: 'tradingCompanies.paymentAmount'.tr(), flex: 2),
        GfTableColumn(label: 'common.note'.tr(), flex: 3),
        const GfTableColumn(label: '', width: 48),
      ],
      rowCount: payments.length,
      total: payments.length,
      clientSide: true,
      itemLabel: 'common.records'.tr(),
      empty: GfEmptyState(
        title: 'tradingCompanies.noPayments'.tr(),
        subtitle: 'tradingCompanies.noPaymentsHint'.tr(),
        compact: true,
      ),
      rowBuilder: (context, i) {
        final p = payments[i];
        final sideLabel = p.settlementSide == PaymentSettlementSide.payable
            ? 'tradingCompanies.settlementPayablePurchases'.tr()
            : 'tradingCompanies.settlementReceivableSales'.tr();
        return GfTableRow(
          onTap: () => onView(p),
          children: [
            Expanded(
              flex: 2,
              child: Text(
                Formatters.date(p.paidAt),
                style: AppTypography.body,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                sideLabel,
                style: AppTypography.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                Formatters.money(p.amount, currency: p.currency),
                style: AppTypography.bodyMedium,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                (p.notes ?? '').trim().isEmpty ? '—' : p.notes!,
                style: AppTypography.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 48,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                color: AppColors.modal,
                onSelected: (action) {
                  if (action == 'view') {
                    onView(p);
                  } else if (action == 'edit') {
                    onEdit(p);
                  } else if (action == 'print') {
                    onPrint(p);
                  } else if (action == 'delete') {
                    onDelete(p);
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
    );
  }
}

class _PaymentFormResult {
  const _PaymentFormResult({
    required this.amount,
    required this.currency,
    required this.paidAt,
    required this.settlementSide,
    this.notes,
  });

  final double amount;
  final String currency;
  final DateTime paidAt;
  final PaymentSettlementSide settlementSide;
  final String? notes;
}

class _PaymentFormDialog extends StatefulWidget {
  const _PaymentFormDialog({
    required this.defaultCurrency,
    required this.payableByCurrency,
    required this.receivableByCurrency,
    required this.defaultSide,
    this.existing,
  });

  final String defaultCurrency;
  final Map<String, double> payableByCurrency;
  final Map<String, double> receivableByCurrency;
  final PaymentSettlementSide defaultSide;
  final CompanyPaymentModel? existing;

  @override
  State<_PaymentFormDialog> createState() => _PaymentFormDialogState();
}

class _PaymentFormDialogState extends State<_PaymentFormDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late String _currency;
  late DateTime _paidAt;
  late PaymentSettlementSide _side;

  static const _currencies = ['AFN', 'USD', 'EUR'];

  Map<String, double> get _dueMap =>
      _side == PaymentSettlementSide.payable
          ? widget.payableByCurrency
          : widget.receivableByCurrency;

  String _currencyLabel(String code) => Formatters.currencyName(code);

  String _sideLabel(PaymentSettlementSide side) => switch (side) {
        PaymentSettlementSide.payable =>
          'tradingCompanies.settlementPayablePurchases'.tr(),
        PaymentSettlementSide.receivable =>
          'tradingCompanies.settlementReceivableSales'.tr(),
      };

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _side = existing?.settlementSide ?? widget.defaultSide;
    final initial = (existing?.currency ?? widget.defaultCurrency)
        .trim()
        .toUpperCase();
    _currency = _currencies.contains(initial) ? initial : 'AFN';
    _paidAt = existing?.paidAt ?? DateTime.now();
    _notes = TextEditingController(text: existing?.notes ?? '');
    if (existing != null) {
      _amount = TextEditingController(text: Formatters.number(existing.amount));
    } else {
      final due = _dueMap[_currency] ?? 0;
      _amount = TextEditingController(
        text: due > 0 ? Formatters.number(due) : '',
      );
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final due = _dueMap[_currency] ?? 0;
    final editing = widget.existing != null;

    return GfDialogShell(
      icon: Icons.payments_outlined,
      iconColor: AppColors.primary,
      title: editing
          ? 'tradingCompanies.editPayment'.tr()
          : 'tradingCompanies.addPayment'.tr(),
      subtitle: due > 0
          ? 'tradingCompanies.paymentFormSubtitle'.tr(
              namedArgs: {
                'due': Formatters.money(due, currency: _currency),
              },
            )
          : 'tradingCompanies.paymentFormSubtitleNone'.tr(),
      primaryLabel: 'common.save'.tr(),
      primaryIcon: Icons.save_outlined,
      onCancel: () => Navigator.pop(context),
      onPrimary: () {
        final amount = Formatters.parse(_amount.text) ?? 0;
        if (amount <= 0) return;
        Navigator.pop(
          context,
          _PaymentFormResult(
            amount: amount,
            currency: _currency,
            paidAt: _paidAt,
            settlementSide: _side,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ),
        );
      },
      maxWidth: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfDropdown<PaymentSettlementSide>(
            label: 'tradingCompanies.settlementSide'.tr(),
            items: PaymentSettlementSide.values,
            value: _side,
            labelBuilder: _sideLabel,
            onChanged: (s) {
              if (s == null) return;
              setState(() {
                _side = s;
                if (!editing) {
                  final nextDue = _dueMap[_currency] ?? 0;
                  _amount.text =
                      nextDue > 0 ? Formatters.number(nextDue) : '';
                }
              });
            },
          ),
          const SizedBox(height: 14),
          DialogResponsiveRow(
            children: [
              GfTextField(
                controller: _amount,
                label: 'tradingCompanies.paymentAmount'.tr(),
                required: true,
                numberMode: true,
              ),
              GfDropdown<String>(
                label: 'stockEntry.currency'.tr(),
                items: _currencies,
                value: _currency,
                labelBuilder: _currencyLabel,
                onChanged: (c) {
                  if (c == null) return;
                  setState(() {
                    _currency = c;
                    if (!editing) {
                      final nextDue = _dueMap[c] ?? 0;
                      _amount.text =
                          nextDue > 0 ? Formatters.number(nextDue) : '';
                    }
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () async {
              final picked = await ShamsiDates.pickDate(
                context,
                initial: _paidAt,
              );
              if (picked != null) setState(() => _paidAt = picked);
            },
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'common.date'.tr(),
                prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                ShamsiDates.formatDate(_paidAt),
                style: AppTypography.body,
              ),
            ),
          ),
          const SizedBox(height: 14),
          GfTextField(
            controller: _notes,
            label: 'common.note'.tr(),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

