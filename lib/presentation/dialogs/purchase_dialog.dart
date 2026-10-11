import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/shamsi_dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/currency_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/warehouse_model.dart';
import '../viewmodels/purchase_cart_viewmodel.dart';
import '../viewmodels/stock_entry_viewmodel.dart';
import '../widgets/order_detail_dialog_style.dart';
import '../widgets/order_detail_info_card.dart';
import 'add_purchase_products_picker_dialog.dart';
import 'warehouse_dialog_shared.dart';

/// New / Edit Purchase — header + multi-line product cart.
class PurchaseDialog extends StatelessWidget {
  const PurchaseDialog({super.key, this.editingPurchaseId});

  final int? editingPurchaseId;

  static Future<bool?> show(BuildContext context, {int? editingPurchaseId}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x661E293B),
      builder: (_) => PurchaseDialog(editingPurchaseId: editingPurchaseId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          PurchaseCartViewModel(editingPurchaseId: editingPurchaseId)..load(),
      child: const _PurchaseDialogBody(),
    );
  }
}

class _PurchaseDialogBody extends StatefulWidget {
  const _PurchaseDialogBody();

  @override
  State<_PurchaseDialogBody> createState() => _PurchaseDialogBodyState();
}

class _PurchaseDialogBodyState extends State<_PurchaseDialogBody> {
  final _discountCtrl = TextEditingController();
  final _paidCtrl = TextEditingController();
  int? _syncedForPurchaseId;

  @override
  void dispose() {
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    super.dispose();
  }

  void _syncPaymentFields(PurchaseCartViewModel vm) {
    final key = vm.editingPurchaseId ?? -1;
    if (_syncedForPurchaseId == key && !vm.loading) return;
    if (vm.loading) return;
    _syncedForPurchaseId = key;
    _discountCtrl.text = vm.discount > 0 ? Formatters.number(vm.discount) : '';
    _paidCtrl.text =
        vm.amountPaid > 0 ? Formatters.number(vm.amountPaid) : '';
  }

  Future<void> _save(BuildContext context, PurchaseCartViewModel vm) async {
    final err = await vm.save();
    if (!context.mounted) return;
    if (err != null) {
      GfToast.error(context, err);
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _addProducts(
    BuildContext context,
    PurchaseCartViewModel vm,
  ) async {
    final picked = await AddPurchaseProductsPickerDialog.show(
      context,
      products: vm.products,
      currencies: vm.currencies,
      defaultCurrency: vm.selectedCurrency,
    );
    if (picked != null && picked.isNotEmpty) {
      vm.addProductsFromPicker(picked);
    }
  }

  Future<void> _editLine(
    BuildContext context,
    PurchaseCartViewModel vm,
    PurchaseCartLine existing,
  ) async {
    final line = await _PurchaseLineDialog.show(
      context,
      products: vm.products,
      currencies: vm.currencies,
      warehouses: vm.warehouses,
      defaultCurrency: vm.selectedCurrency,
      defaultWarehouse: vm.selectedWarehouse,
      existing: existing,
    );
    if (line != null) vm.addOrUpdateLine(line);
  }

  void _applyPaymentFromFields(PurchaseCartViewModel vm) {
    vm.setDiscount(Formatters.parse(_discountCtrl.text) ?? 0);
    vm.setAmountPaid(Formatters.parse(_paidCtrl.text) ?? 0);
  }

  String _codeFor(PurchaseCartViewModel vm, int? currencyId) {
    return vm.selectedCurrency?.code ?? 'AFN';
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PurchaseCartViewModel>();
    final currencyCode = vm.selectedCurrency?.code ?? 'AFN';
    _syncPaymentFields(vm);

    final title = vm.isEditing
        ? 'purchases.editTitle'.tr()
        : 'purchases.newPurchase'.tr();

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
        child: vm.loading
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
                          vm.isEditing
                              ? Icons.edit_document
                              : Icons.local_shipping_outlined,
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
                              title,
                              style: AppTypography.sectionTitle.copyWith(
                                color: OrderDetailDialogStyle.navy,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'purchases.newSubtitle'.tr(),
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
                          onPressed: vm.saving
                              ? null
                              : () => _addProducts(context, vm),
                          icon: Icon(Icons.add_rounded, size: 16),
                          label: Text('purchases.addProduct'.tr()),
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
                  Divider(
                    height: 1,
                    color: OrderDetailDialogStyle.border,
                  ),
                  OrderDetailDialogStyle.sectionSpace,
                  if (vm.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        vm.error!,
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
                                  title: 'purchases.supplier'.tr(),
                                  child: GfDropdown<TradingPartnerOption>(
                                    value: vm.selectedCompany,
                                    height:
                                        OrderDetailDialogStyle.fieldHeight,
                                    items: vm.companies,
                                    prefixIcon: Icons.business_outlined,
                                    labelBuilder: (c) => c.name,
                                    onChanged: vm.selectCompany,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OrderDetailInfoCard(
                                  title: 'orders.payment'.tr(),
                                  child: GfDropdown<CurrencyModel>(
                                    value: vm.selectedCurrency,
                                    height:
                                        OrderDetailDialogStyle.fieldHeight,
                                    items: vm.currencies,
                                    prefixIcon:
                                        Icons.attach_money_rounded,
                                    labelBuilder: (c) =>
                                        '${Formatters.currencyName(c.code)} (${c.code})',
                                    onChanged: vm.selectCurrency,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          OrderDetailDialogStyle.sectionSpace,
                          DialogResponsiveRow(
                            children: [
                              _DateField(vm: vm),
                              GfDropdown<WarehouseModel>(
                                label: 'stockEntry.warehouseLocation'.tr(),
                                value: vm.selectedWarehouse,
                                items: vm.warehouses,
                                labelBuilder: (w) => w.name,
                                onChanged: vm.selectWarehouse,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          GfTextField(
                            key: ValueKey(
                              'notes-${vm.editingPurchaseId ?? 'new'}',
                            ),
                            label: 'stockEntry.notes'.tr(),
                            initialValue: vm.notes,
                            onChanged: vm.setNotes,
                            minLines: 1,
                            maxLines: 2,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'purchases.driverSection'.tr(),
                            style: AppTypography.caption.copyWith(
                              color: OrderDetailDialogStyle.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DialogResponsiveRow(
                            children: [
                              GfTextField(
                                key: ValueKey(
                                  'driver-${vm.editingPurchaseId ?? 'new'}',
                                ),
                                label: 'stockEntry.driver'.tr(),
                                initialValue: vm.driver,
                                onChanged: vm.setDriver,
                              ),
                              GfTextField(
                                key: ValueKey(
                                  'vehicle-${vm.editingPurchaseId ?? 'new'}',
                                ),
                                label: 'stockEntry.vehicle'.tr(),
                                initialValue: vm.vehicle,
                                onChanged: vm.setVehicle,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          GfTextField(
                            key: ValueKey(
                              'driver-desc-${vm.editingPurchaseId ?? 'new'}',
                            ),
                            label: 'stockEntry.driverDescription'.tr(),
                            hint: 'stockEntry.driverDescriptionHint'.tr(),
                            initialValue: vm.driverDescription,
                            onChanged: vm.setDriverDescription,
                            minLines: 1,
                            maxLines: 2,
                          ),
                          OrderDetailDialogStyle.sectionSpace,
                          _PurchaseLinesTable(
                            lines: vm.lines,
                            codeFor: (id) => _codeFor(vm, id),
                            onEdit: (line) => _editLine(context, vm, line),
                            onDelete: (line) => vm.removeLine(line.id),
                          ),
                          OrderDetailDialogStyle.sectionSpace,
                          OrderDetailEditablePaymentSummary(
                            currency: currencyCode,
                            discountCtrl: _discountCtrl,
                            paidCtrl: _paidCtrl,
                            total: vm.total,
                            remaining: vm.remaining,
                            paidLabel: 'purchases.amountPaid'.tr(),
                            onChanged: () {
                              _applyPaymentFromFields(vm);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                footer: [
                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: OrderDetailDialogStyle.border,
                  ),
                  const SizedBox(height: 14),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        const Spacer(),
                        SizedBox(
                          height: OrderDetailDialogStyle.fieldHeight,
                          child: OutlinedButton(
                            onPressed: vm.saving
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
                            onPressed: vm.loading || vm.saving
                                ? null
                                : () {
                                    _applyPaymentFromFields(vm);
                                    _save(context, vm);
                                  },
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
                              vm.saving
                                  ? 'common.loading'.tr()
                                  : 'common.save'.tr(),
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

class _PurchaseLinesTable extends StatelessWidget {
  const _PurchaseLinesTable({
    required this.lines,
    required this.codeFor,
    required this.onEdit,
    required this.onDelete,
  });

  final List<PurchaseCartLine> lines;
  final String Function(int? currencyId) codeFor;
  final ValueChanged<PurchaseCartLine> onEdit;
  final ValueChanged<PurchaseCartLine> onDelete;

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
                _h('common.qty'.tr(), width: 44, align: TextAlign.center),
                const SizedBox(width: 6),
                _h(
                  'inboundOutbound.unitPrice'.tr(),
                  width: 88,
                  align: TextAlign.end,
                ),
                const SizedBox(width: 56),
              ],
            ),
          ),
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'purchases.linesHint'.tr(),
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
              _PurchaseLineRow(
                index: i + 1,
                line: lines[i],
                buyCode: codeFor(lines[i].currencyId),
                onEdit: () => onEdit(lines[i]),
                onDelete: () => onDelete(lines[i]),
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

class _PurchaseLineRow extends StatelessWidget {
  const _PurchaseLineRow({
    required this.index,
    required this.line,
    required this.buyCode,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final PurchaseCartLine line;
  final String buyCode;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$index',
              style: AppTypography.caption.copyWith(
                color: OrderDetailDialogStyle.muted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              line.product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: OrderDetailDialogStyle.navy,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              Formatters.number(line.quantity),
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: OrderDetailDialogStyle.muted,
                fontSize: 12,
              ),
            ),
          ),
          OrderDetailDialogStyle.inlineGap,
          SizedBox(
            width: 88,
            child: Text(
              Formatters.money(line.unitPrice, currency: buyCode),
              textAlign: TextAlign.end,
              style: AppTypography.body.copyWith(
                color: OrderDetailDialogStyle.muted,
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: IconButton(
              onPressed: onEdit,
              icon: Icon(
                Icons.edit_outlined,
                size: 16,
                color: OrderDetailDialogStyle.accent,
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ),
          SizedBox(
            width: 28,
            child: IconButton(
              onPressed: onDelete,
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
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.vm});

  final PurchaseCartViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'stockEntry.transactionDate'.tr(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(
            color: OrderDetailDialogStyle.muted,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: AppColors.input,
          borderRadius: OrderDetailDialogStyle.controlBorderRadius,
          child: InkWell(
            onTap: () async {
              final picked = await ShamsiDates.pickDate(
                context,
                initial: vm.transactionDate,
              );
              if (picked != null) vm.setTransactionDate(picked);
            },
            borderRadius: OrderDetailDialogStyle.controlBorderRadius,
            child: Container(
              height: OrderDetailDialogStyle.fieldHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: OrderDetailDialogStyle.controlBorderRadius,
                border: Border.all(
                  color: OrderDetailDialogStyle.border,
                  width: OrderDetailDialogStyle.borderWidth,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ShamsiDates.formatDate(vm.transactionDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        color: OrderDetailDialogStyle.navy,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: OrderDetailDialogStyle.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Add / edit a single purchase line (inbound-style fields).
class _PurchaseLineDialog extends StatefulWidget {
  const _PurchaseLineDialog({
    required this.products,
    required this.currencies,
    required this.warehouses,
    this.defaultCurrency,
    this.defaultWarehouse,
    this.existing,
  });

  final List<ProductModel> products;
  final List<CurrencyModel> currencies;
  final List<WarehouseModel> warehouses;
  final CurrencyModel? defaultCurrency;
  final WarehouseModel? defaultWarehouse;
  final PurchaseCartLine? existing;

  static Future<PurchaseCartLine?> show(
    BuildContext context, {
    required List<ProductModel> products,
    required List<CurrencyModel> currencies,
    required List<WarehouseModel> warehouses,
    CurrencyModel? defaultCurrency,
    WarehouseModel? defaultWarehouse,
    PurchaseCartLine? existing,
  }) {
    return showDialog<PurchaseCartLine>(
      context: context,
      builder: (_) => _PurchaseLineDialog(
        products: products,
        currencies: currencies,
        warehouses: warehouses,
        defaultCurrency: defaultCurrency,
        defaultWarehouse: defaultWarehouse,
        existing: existing,
      ),
    );
  }

  @override
  State<_PurchaseLineDialog> createState() => _PurchaseLineDialogState();
}

class _PurchaseLineDialogState extends State<_PurchaseLineDialog> {
  ProductModel? _product;
  CurrencyModel? _purchaseCurrency;
  CurrencyModel? _sellingCurrency;
  WarehouseModel? _warehouse;
  String _dimensionUnit = 'm';
  late final TextEditingController _qty;
  late final TextEditingController _price;
  late final TextEditingController _sellPrice;
  late final TextEditingController _paid;
  late final TextEditingController _length;
  late final TextEditingController _width;
  late final TextEditingController _thickness;
  String? _error;

  CurrencyModel? _currencyById(int? id) {
    if (id == null) return null;
    return widget.currencies.where((c) => c.id == id).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _product = e?.product;
    _purchaseCurrency = _currencyById(e?.currencyId) ??
        _currencyById(e?.product.costCurrencyId) ??
        widget.defaultCurrency ??
        widget.currencies.firstOrNull;
    _sellingCurrency = _currencyById(e?.sellingCurrencyId) ??
        _currencyById(e?.product.currencyId) ??
        widget.defaultCurrency ??
        widget.currencies.firstOrNull;
    _warehouse =
        widget.warehouses.where((w) => w.id == e?.warehouseId).firstOrNull ??
        widget.defaultWarehouse;
    _dimensionUnit = e?.dimensionUnit ?? 'm';
    _qty = TextEditingController(
      text: e == null ? '1' : Formatters.number(e.quantity),
    );
    _price = TextEditingController(
      text: e == null || e.unitPrice <= 0 ? '' : Formatters.number(e.unitPrice),
    );
    final sell = e?.effectiveSellingPrice ?? e?.product.sellingPrice ?? 0;
    _sellPrice = TextEditingController(
      text: sell <= 0 ? '' : Formatters.number(sell),
    );
    _paid = TextEditingController(
      text: e == null || e.paidAmount <= 0
          ? ''
          : Formatters.number(e.paidAmount),
    );
    _length = TextEditingController(
      text: dimToDisplay(e?.lengthM, unit: _dimensionUnit),
    );
    _width = TextEditingController(
      text: dimToDisplay(e?.widthM, unit: _dimensionUnit),
    );
    _thickness = TextEditingController(
      text: e?.thickness == null ? '' : Formatters.number(e!.thickness!),
    );
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    _sellPrice.dispose();
    _paid.dispose();
    _length.dispose();
    _width.dispose();
    _thickness.dispose();
    super.dispose();
  }

  void _applyProduct(ProductModel? p) {
    setState(() {
      _product = p;
      if (p == null) return;
      if (p.costPrice > 0 && _price.text.trim().isEmpty) {
        _price.text = Formatters.number(p.costPrice);
      }
      if (p.sellingPrice > 0 && _sellPrice.text.trim().isEmpty) {
        _sellPrice.text = Formatters.number(p.sellingPrice);
      }
      // Purchase currency follows invoice/payment currency by default.
      _purchaseCurrency = widget.defaultCurrency ??
          _currencyById(p.costCurrencyId) ??
          _purchaseCurrency;
      // Selling currency is independent — from the product catalog.
      _sellingCurrency = _currencyById(p.currencyId) ??
          widget.defaultCurrency ??
          _sellingCurrency;
      if (_length.text.isEmpty) {
        _length.text = dimToDisplay(p.standardHeight, unit: _dimensionUnit);
      }
      if (_width.text.isEmpty) {
        _width.text = dimToDisplay(p.standardWidth, unit: _dimensionUnit);
      }
      if (p.thickness != null && _thickness.text.isEmpty) {
        _thickness.text = Formatters.number(p.thickness!);
      }
      if (p.warehouseId != null) {
        _warehouse =
            widget.warehouses.where((w) => w.id == p.warehouseId).firstOrNull ??
            _warehouse;
      }
    });
  }

  void _submit() {
    if (_product == null) {
      setState(() => _error = 'stockEntry.required'.tr());
      return;
    }
    final qty = Formatters.parse(_qty.text) ?? 0;
    if (qty <= 0) {
      setState(() => _error = 'stockEntry.required'.tr());
      return;
    }
    if (_purchaseCurrency == null || _sellingCurrency == null) {
      setState(() => _error = 'purchases.currencyRequired'.tr());
      return;
    }
    final price = Formatters.parse(_price.text) ?? 0;
    final sell = Formatters.parse(_sellPrice.text) ?? 0;
    final paid = Formatters.parse(_paid.text) ?? 0;
    if (price > 0 && paid > price * qty + 0.0001) {
      setState(() => _error = 'stockEntry.paidExceedsTotal'.tr());
      return;
    }
    Navigator.of(context).pop(
      PurchaseCartLine(
        id:
            widget.existing?.id ??
            'line-${DateTime.now().microsecondsSinceEpoch}',
        product: _product!.copyWith(
          costPrice: price,
          sellingPrice: sell > 0 ? sell : _product!.sellingPrice,
          costCurrencyId: _purchaseCurrency!.id,
          currencyId: _sellingCurrency!.id,
          costCurrencyCode: _purchaseCurrency!.code,
          currencyCode: _sellingCurrency!.code,
        ),
        quantity: qty,
        unitPrice: price,
        sellingPrice: sell,
        lengthM: null,
        widthM: null,
        dimensionUnit: _dimensionUnit,
        paidAmount: paid,
        currencyId: _purchaseCurrency!.id,
        sellingCurrencyId: _sellingCurrency!.id,
        warehouseId: _warehouse?.id,
        thickness: null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.add_box_outlined,
      title: widget.existing == null
          ? 'purchases.addProduct'.tr()
          : 'purchases.editLine'.tr(),
      primaryLabel: 'common.apply'.tr(),
      onCancel: () => Navigator.of(context).pop(),
      onPrimary: _submit,
      maxWidth: 520,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: AppTypography.body.copyWith(color: AppColors.error),
              ),
            ),
          GfDropdown<ProductModel>(
            label: 'stockEntry.product'.tr(),
            required: true,
            value: _product,
            items: widget.products,
            labelBuilder: (p) => p.name,
            onChanged: _applyProduct,
          ),
          const SizedBox(height: 12),
          DialogResponsiveRow(
            children: [
              GfTextField(
                label: 'stockEntry.quantity'.tr(),
                required: true,
                controller: _qty,
                numberMode: true,
                onChanged: (_) => setState(() {}),
              ),
              GfDropdown<WarehouseModel>(
                label: 'stockEntry.warehouseLocation'.tr(),
                value: _warehouse,
                items: widget.warehouses,
                labelBuilder: (w) => w.name,
                onChanged: (w) => setState(() => _warehouse = w),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DialogResponsiveRow(
            children: [
              GfTextField(
                label: 'purchases.purchasePrice'.tr(),
                controller: _price,
                numberMode: true,
                onChanged: (_) => setState(() {}),
              ),
              GfDropdown<CurrencyModel>(
                label: 'purchases.purchaseCurrency'.tr(),
                required: true,
                items: widget.currencies,
                value: _purchaseCurrency,
                hint: 'purchases.selectCurrency'.tr(),
                prefixIcon: Icons.attach_money_rounded,
                labelBuilder: (c) =>
                    '${Formatters.currencyName(c.code)} (${c.code})',
                onChanged: (c) => setState(() => _purchaseCurrency = c),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DialogResponsiveRow(
            children: [
              GfTextField(
                label: 'purchases.sellingPrice'.tr(),
                controller: _sellPrice,
                numberMode: true,
                onChanged: (_) => setState(() {}),
              ),
              GfDropdown<CurrencyModel>(
                label: 'purchases.sellingCurrency'.tr(),
                required: true,
                items: widget.currencies,
                value: _sellingCurrency,
                hint: 'purchases.selectCurrency'.tr(),
                prefixIcon: Icons.sell_outlined,
                labelBuilder: (c) =>
                    '${Formatters.currencyName(c.code)} (${c.code})',
                onChanged: (c) => setState(() => _sellingCurrency = c),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
