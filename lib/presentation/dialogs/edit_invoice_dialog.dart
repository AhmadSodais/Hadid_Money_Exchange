import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/currency_model.dart';
import '../../data/models/order_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/warehouse_model.dart';
import '../viewmodels/stock_entry_viewmodel.dart';
import '../widgets/order_detail_dialog_style.dart';
import '../widgets/order_detail_info_card.dart';
import 'add_product_picker_dialog.dart';

/// Edit Invoice — same chrome / widgets as [OrderDetailDialog] (view).
class EditInvoiceDialog extends StatefulWidget {
  const EditInvoiceDialog({super.key, required this.order});

  final OrderModel order;

  static Future<bool?> show(BuildContext context, OrderModel order) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x661E293B),
      builder: (_) => EditInvoiceDialog(order: order),
    );
  }

  @override
  State<EditInvoiceDialog> createState() => _EditInvoiceDialogState();
}

class _EditLine {
  _EditLine({
    required this.key,
    required this.productId,
    required this.productName,
    required this.imagePath,
    required this.quantity,
    required this.unitPrice,
    this.lengthM,
    this.widthM,
    this.currencyId,
    this.warehouseId,
    this.availableStock = 0,
  });

  final String key;
  final int productId;
  final String productName;
  final String? imagePath;
  double quantity;
  double unitPrice;
  final double? lengthM;
  final double? widthM;
  int? currencyId;
  int? warehouseId;
  double availableStock;

  double get lineTotal => quantity.abs() * unitPrice;
}

class _EditInvoiceDialogState extends State<EditInvoiceDialog> {
  late final TextEditingController _discountCtrl;
  late final TextEditingController _paidCtrl;

  final List<_EditLine> _lines = [];
  List<TradingPartnerOption> _companies = const [];
  List<ProductModel> _products = const [];
  List<CurrencyModel> _currencies = const [];
  List<WarehouseModel> _warehouses = const [];
  TradingPartnerOption? _customer;
  CurrencyModel? _selectedCurrency;
  WarehouseModel? _selectedWarehouse;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final Map<int, double> _stockCredit = {};

  @override
  void initState() {
    super.initState();
    final o = widget.order;
    _discountCtrl = TextEditingController(
      text: o.discount > 0 ? Formatters.number(o.discount) : '',
    );
    _paidCtrl = TextEditingController(
      text: o.amountPaid > 0 ? Formatters.number(o.amountPaid) : '',
    );
    for (final item in o.items) {
      _stockCredit[item.productId] =
          (_stockCredit[item.productId] ?? 0) + item.quantity.abs();
      _lines.add(
        _EditLine(
          key: 'line-${item.id}',
          productId: item.productId,
          productName: item.productName,
          imagePath: item.productImagePath,
          quantity: item.quantity.abs(),
          unitPrice: item.unitPrice,
          lengthM: item.lengthM,
          widthM: item.widthM,
          currencyId: item.currencyId ?? o.currencyId,
          warehouseId: item.warehouseId,
        ),
      );
    }
    _bootstrap();
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    super.dispose();
  }

  String get _currencyCode =>
      _selectedCurrency?.code ?? widget.order.currencyCode ?? 'AFN';

  double get _subtotal => _lines.fold<double>(0, (s, l) => s + l.lineTotal);

  double get _discount {
    final v = Formatters.parse(_discountCtrl.text) ?? 0;
    return v < 0 ? 0 : v;
  }

  double get _total {
    final t = _subtotal - _discount;
    return t < 0 ? 0 : t;
  }

  double get _amountPaid {
    final v = Formatters.parse(_paidCtrl.text) ?? 0;
    return v < 0 ? 0 : v;
  }

  double get _remaining {
    final r = _total - _amountPaid;
    return r < 0 ? 0 : r;
  }

  String get _paymentStatus {
    final paid = _amountPaid;
    final total = _total;
    if (paid + 0.0001 >= total && total > 0) return 'paid';
    if (paid > 0) return 'partial';
    return 'unpaid';
  }

  Future<void> _bootstrap() async {
    final sl = ServiceLocator.instance;
    final companies = <TradingPartnerOption>[];
    final seen = <String>{};

    final currenciesResult = await sl.lookups.getCurrencies();
    currenciesResult.when(
      success: (list) {
        _currencies = list.where((c) => c.isActive).toList();
        if (_currencies.isEmpty) _currencies = list;
      },
      failure: (_) {},
    );

    final whResult = await sl.warehouses.list();
    whResult.when(
      success: (list) {
        _warehouses = list.where((w) => w.isActive).toList();
        if (_warehouses.isEmpty) _warehouses = list;
      },
      failure: (_) {},
    );

    // Order invoices are tied to customers only.
    final customers = await sl.customers.query(pageSize: 500);
    customers.when(
      success: (page) {
        for (final c in page.items) {
          if (c.name.toLowerCase() == 'walk-in customer') continue;
          final key = 'customer-${c.id}';
          if (seen.add(key)) {
            companies.add(
              TradingPartnerOption(
                key: key,
                id: c.id,
                name: c.name,
                source: 'customer',
              ),
            );
          }
        }
      },
      failure: (_) {},
    );
    companies.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    final order = widget.order;
    TradingPartnerOption? selected;
    if (order.partnerId != null && (order.partnerType ?? '').isNotEmpty) {
      selected = companies
          .where(
            (c) => c.id == order.partnerId && c.source == order.partnerType,
          )
          .firstOrNull;
      if (selected == null && (order.partnerName ?? '').trim().isNotEmpty) {
        selected = TradingPartnerOption(
          key: '${order.partnerType}-${order.partnerId}',
          id: order.partnerId!,
          name: order.partnerName!,
          source: order.partnerType!,
        );
        companies.insert(0, selected);
      }
    }

    CurrencyModel? currency = _currencies
        .where((c) => c.id == order.currencyId || c.code == order.currencyCode)
        .firstOrNull;
    currency ??=
        _currencies.where((c) => c.isBase).firstOrNull ??
        _currencies.firstOrNull;

    final firstWhId = _lines
        .map((l) => l.warehouseId)
        .whereType<int>()
        .firstOrNull;
    WarehouseModel? warehouse = firstWhId == null
        ? null
        : _warehouses.where((w) => w.id == firstWhId).firstOrNull;
    warehouse ??= _warehouses.firstOrNull;

    final productsResult = await sl.products.query(
      const ProductQuery(pageSize: 500, sortBy: 'name', ascending: true),
    );
    final products = productsResult.when(
      success: (page) => page.items,
      failure: (_) => <ProductModel>[],
    );

    final productById = {for (final p in products) p.id: p};
    for (final line in _lines) {
      final p = productById[line.productId];
      final credit = _stockCredit[line.productId] ?? 0;
      line.availableStock = (p?.currentStock ?? 0) + credit;
      line.currencyId ??= currency?.id;
      line.warehouseId ??= warehouse?.id;
    }

    if (!mounted) return;
    setState(() {
      _companies = companies;
      _products = products;
      _customer = selected;
      _selectedCurrency = currency;
      _selectedWarehouse = warehouse;
      _loading = false;
    });
  }

  Future<void> _addProducts() async {
    if (_products.isEmpty) {
      GfToast.error(context, 'orders.noProducts'.tr());
      return;
    }
    final picked = await AddProductPickerDialog.show(
      context,
      products: _products,
      currencies: _currencies,
      defaultCurrency: _selectedCurrency,
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    setState(() {
      for (final item in picked) {
        final product = item.product;
        final addQty = item.quantity > 0 ? item.quantity : 1;
        final existingIndex = _lines.indexWhere(
          (l) => l.productId == product.id,
        );
        if (existingIndex >= 0) {
          _lines[existingIndex].quantity += addQty;
          if (item.unitPrice > 0) {
            _lines[existingIndex].unitPrice = item.unitPrice;
          }
          if (item.currencyId != null) {
            _lines[existingIndex].currencyId = item.currencyId;
          }
        } else {
          final credit = _stockCredit[product.id] ?? 0;
          _lines.add(
            _EditLine(
              key: 'new-${product.id}-${DateTime.now().microsecondsSinceEpoch}',
              productId: product.id,
              productName: product.name,
              imagePath: product.imagePath,
              quantity: addQty.toDouble(),
              unitPrice: item.unitPrice > 0
                  ? item.unitPrice
                  : product.sellingPrice,
              lengthM: product.standardHeight,
              widthM: product.standardWidth,
              currencyId:
                  item.currencyId ??
                  product.currencyId ??
                  _selectedCurrency?.id ??
                  widget.order.currencyId,
              warehouseId: product.warehouseId ?? _selectedWarehouse?.id,
              availableStock: product.currentStock + credit,
            ),
          );
        }
      }
    });
  }

  void _setPaymentStatus(String status) {
    setState(() {
      switch (status) {
        case 'paid':
          _paidCtrl.text = Formatters.number(_total);
        case 'unpaid':
          _paidCtrl.text = '';
        case 'partial':
          if (_amountPaid <= 0 || _amountPaid + 0.0001 >= _total) {
            final half = (_total / 2).clamp(0, _total);
            _paidCtrl.text = Formatters.number(half);
          }
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_lines.isEmpty) {
      GfToast.error(context, 'orders.linesRequired'.tr());
      return;
    }
    for (final line in _lines) {
      if (line.quantity <= 0) {
        GfToast.error(context, 'inventory.enterValidQty'.tr());
        return;
      }
      final used = _lines
          .where((l) => l.productId == line.productId)
          .fold<double>(0, (s, l) => s + l.quantity);
      final credit = _stockCredit[line.productId] ?? 0;
      final product = _products
          .where((p) => p.id == line.productId)
          .firstOrNull;
      final available = (product?.currentStock ?? line.availableStock) + credit;
      if (used > available + 0.0001) {
        GfToast.error(context, 'stockEntry.notEnoughStock'.tr());
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final paid = _amountPaid;
    final total = _total;
    final currencyId = _selectedCurrency?.id ?? widget.order.currencyId;
    final currencyCode = _currencyCode;
    final lineInputs = <OutboundOrderLineInput>[];
    for (final line in _lines) {
      final share = total <= 0
          ? 0.0
          : (paid * (line.lineTotal / total)).clamp(0.0, paid);
      lineInputs.add(
        OutboundOrderLineInput(
          productId: line.productId,
          productName: line.productName,
          quantity: line.quantity.abs(),
          unitPrice: line.unitPrice,
          lineTotal: line.lineTotal,
          paidAmount: share,
          lengthM: line.lengthM,
          widthM: line.widthM,
          currencyId: line.currencyId ?? currencyId,
          warehouseId: line.warehouseId ?? _selectedWarehouse?.id,
        ),
      );
    }

    final partnerName = _customer?.name ?? 'sales.walkInCustomer'.tr();
    final result = await ServiceLocator.instance.orders.replaceOutboundOrder(
      orderId: widget.order.id,
      lines: lineInputs,
      partnerType: _customer?.source,
      partnerId: _customer?.id,
      partnerName: partnerName,
      currencyId: currencyId,
      currencyCode: currencyCode,
      discount: _discount,
      amountPaid: paid,
      notes: widget.order.notes,
    );

    if (!mounted) return;
    result.when(
      success: (_) => Navigator.of(context).pop(true),
      failure: (f) => setState(() {
        _saving = false;
        _error = f.message;
        GfToast.error(context, f.message);
      }),
    );
  }

  String get _invoiceTitle => 'orders.invoiceTitle'.tr(
    namedArgs: {'invoice': widget.order.invoiceNumber},
  );

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final currency = _currencyCode;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: OrderDetailDialogStyle.maxWidth,
          minHeight: OrderDetailDialogStyle.minHeight,
          maxHeight: OrderDetailDialogStyle.maxHeight,
        ),
        decoration: OrderDetailDialogStyle.container,
        padding: OrderDetailDialogStyle.framePadding,
        child: _loading
            ? const SizedBox(height: 280, child: Center(child: GfPageLoader()))
            : OrderDetailDialogStyle.scrollLayout(
                header: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: OrderDetailDialogStyle.fieldHeight,
                        height: OrderDetailDialogStyle.fieldHeight,
                        decoration: BoxDecoration(
                          color: OrderDetailDialogStyle.iconBg,
                          borderRadius:
                              OrderDetailDialogStyle.controlBorderRadius,
                        ),
                        child: Icon(
                          Icons.edit_document,
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
                              _invoiceTitle,
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
                      SizedBox(
                        height: OrderDetailDialogStyle.fieldHeight,
                        child: TextButton.icon(
                          onPressed: _saving ? null : _addProducts,
                          icon: Icon(Icons.add_rounded, size: 16),
                          label: Text('orders.addProduct'.tr()),
                          style: TextButton.styleFrom(
                            foregroundColor: OrderDetailDialogStyle.accent,
                            backgroundColor: OrderDetailDialogStyle.paleBlue,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  OrderDetailDialogStyle.controlBorderRadius,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(height: 1, color: OrderDetailDialogStyle.border),
                  OrderDetailDialogStyle.sectionSpace,
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        style: AppTypography.caption.copyWith(
                          color: OrderDetailDialogStyle.danger,
                        ),
                      ),
                    ),
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
                                  child: GfDropdown<TradingPartnerOption?>(
                                    value: _customer,
                                    height: OrderDetailDialogStyle.fieldHeight,
                                    items: <TradingPartnerOption?>[
                                      null,
                                      ..._companies,
                                    ],
                                    prefixIcon: Icons.person_outline_rounded,
                                    labelBuilder: (c) => c == null
                                        ? 'sales.walkInCustomer'.tr()
                                        : c.name,
                                    onChanged: (c) =>
                                        setState(() => _customer = c),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OrderDetailInfoCard(
                                  title: 'orders.payment'.tr(),
                                  child: GfDropdown<String>(
                                    value: _paymentStatus,
                                    height: OrderDetailDialogStyle.fieldHeight,
                                    items: const ['paid', 'partial', 'unpaid'],
                                    labelBuilder: (s) => switch (s) {
                                      'paid' => 'orders.paid'.tr(),
                                      'partial' => 'orders.partial'.tr(),
                                      _ => 'orders.unpaid'.tr(),
                                    },
                                    onChanged: (s) {
                                      if (s != null) {
                                        _setPaymentStatus(s);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          OrderDetailDialogStyle.sectionSpace,
                          _EditableProductTable(
                            lines: _lines,
                            currency: currency,
                            onQtyChanged: (i, v) => setState(() {
                              _lines[i].quantity = v;
                            }),
                            onPriceChanged: (i, v) => setState(() {
                              _lines[i].unitPrice = v;
                            }),
                            onDelete: (i) => setState(() {
                              _lines.removeAt(i);
                            }),
                          ),
                          OrderDetailDialogStyle.sectionSpace,
                          OrderDetailEditablePaymentSummary(
                            currency: currency,
                            discountCtrl: _discountCtrl,
                            paidCtrl: _paidCtrl,
                            total: _total,
                            remaining: _remaining,
                            onChanged: () => setState(() {}),
                          ),
                        ],
                      ),
                footer: [
                  const SizedBox(height: 16),
                  Divider(height: 1, color: OrderDetailDialogStyle.border),
                  const SizedBox(height: 14),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        const Spacer(),
                        SizedBox(
                          height: OrderDetailDialogStyle.fieldHeight,
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: OrderDetailDialogStyle.navy,
                              side: OrderDetailDialogStyle.borderSide,
                              backgroundColor: OrderDetailDialogStyle.surface,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: OrderDetailDialogStyle
                                    .controlBorderRadius,
                              ),
                            ),
                            child: Text(
                              'common.cancel'.tr(),
                              style: AppTypography.bodyMedium.copyWith(
                                color: OrderDetailDialogStyle.navy,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        OrderDetailDialogStyle.inlineGap,
                        SizedBox(
                          height: OrderDetailDialogStyle.fieldHeight,
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: OrderDetailDialogStyle.accent,
                              foregroundColor: OrderDetailDialogStyle.onAccent,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: OrderDetailDialogStyle
                                    .controlBorderRadius,
                              ),
                            ),
                            child: Text(
                              _saving
                                  ? 'common.loading'.tr()
                                  : 'orders.saveChanges'.tr(),
                              style: AppTypography.bodyMedium.copyWith(
                                color: OrderDetailDialogStyle.onAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _EditableProductTable extends StatelessWidget {
  const _EditableProductTable({
    required this.lines,
    required this.currency,
    required this.onQtyChanged,
    required this.onPriceChanged,
    required this.onDelete,
  });

  final List<_EditLine> lines;
  final String currency;
  final void Function(int index, double value) onQtyChanged;
  final void Function(int index, double value) onPriceChanged;
  final void Function(int index) onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: OrderDetailDialogStyle.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: OrderDetailDialogStyle.tableHeaderBg,
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            child: Row(
              children: [
                _h('#', width: 22),
                Expanded(child: _h('common.product'.tr())),
                _h('common.qty'.tr(), width: 56, align: TextAlign.center),
                const SizedBox(width: 6),
                _h(
                  'inboundOutbound.unitPrice'.tr(),
                  width: 72,
                  align: TextAlign.center,
                ),
                // const SizedBox(width: 6),
                // _h('orders.total'.tr(), width: 70, align: TextAlign.end),
                // const SizedBox(width: 28),
              ],
            ),
          ),
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'orders.linesHint'.tr(),
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
              _EditProductRow(
                index: i + 1,
                line: lines[i],
                currency: currency,
                onQtyChanged: (v) => onQtyChanged(i, v),
                onPriceChanged: (v) => onPriceChanged(i, v),
                onDelete: () => onDelete(i),
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
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.caption.copyWith(
        color: OrderDetailDialogStyle.muted,
        fontWeight: FontWeight.w600,
        fontSize: 11,
      ),
    );
    if (width != null) return SizedBox(width: width, child: child);
    return child;
  }
}

class _EditProductRow extends StatefulWidget {
  const _EditProductRow({
    required this.index,
    required this.line,
    required this.currency,
    required this.onQtyChanged,
    required this.onPriceChanged,
    required this.onDelete,
  });

  final int index;
  final _EditLine line;
  final String currency;
  final ValueChanged<double> onQtyChanged;
  final ValueChanged<double> onPriceChanged;
  final VoidCallback onDelete;

  @override
  State<_EditProductRow> createState() => _EditProductRowState();
}

class _EditProductRowState extends State<_EditProductRow> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(
      text: Formatters.number(widget.line.quantity),
    );
    _priceCtrl = TextEditingController(
      text: Formatters.number(widget.line.unitPrice),
    );
  }

  @override
  void didUpdateWidget(covariant _EditProductRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.key != widget.line.key) {
      _qtyCtrl.text = Formatters.number(widget.line.quantity);
      _priceCtrl.text = Formatters.number(widget.line.unitPrice);
    } else {
      if (oldWidget.line.quantity != widget.line.quantity) {
        final next = Formatters.number(widget.line.quantity);
        if (_qtyCtrl.text != next) _qtyCtrl.text = next;
      }
      if (oldWidget.line.unitPrice != widget.line.unitPrice) {
        final next = Formatters.number(widget.line.unitPrice);
        if (_priceCtrl.text != next) _priceCtrl.text = next;
      }
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final h = OrderDetailDialogStyle.inlineFieldHeight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      child: SizedBox(
        height: h,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '${widget.index}',
                style: AppTypography.caption.copyWith(
                  color: OrderDetailDialogStyle.muted,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  _Thumb(path: line.imagePath),
                  OrderDetailDialogStyle.inlineGap,
                  Expanded(
                    child: Text(
                      line.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: OrderDetailDialogStyle.navy,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 56,
              height: h,
              child: GfTextField(
                controller: _qtyCtrl,
                numberMode: true,
                textAlign: TextAlign.center,
                borderless: true,
                onChanged: (v) => widget.onQtyChanged(Formatters.parse(v) ?? 0),
              ),
            ),
            OrderDetailDialogStyle.inlineGap,
            SizedBox(
              width: 72,
              height: h,
              child: GfTextField(
                controller: _priceCtrl,
                numberMode: true,
                textAlign: TextAlign.center,
                onChanged: (v) =>
                    widget.onPriceChanged(Formatters.parse(v) ?? 0),
              ),
            ),
            OrderDetailDialogStyle.inlineGap,
            SizedBox(
              width: 70,
              child: Text(
                Formatters.money(line.lineTotal, currency: widget.currency),
                textAlign: TextAlign.end,
                style: AppTypography.bodyMedium.copyWith(
                  color: OrderDetailDialogStyle.navy,
                  fontSize: 12,
                ),
              ),
            ),
            SizedBox(
              width: 28,
              child: IconButton(
                onPressed: widget.onDelete,
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: OrderDetailDialogStyle.danger,
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
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
