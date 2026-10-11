import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/shamsi_dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/currency_model.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/warehouse_model.dart';
import '../viewmodels/stock_entry_viewmodel.dart';
import '../widgets/permission_gate.dart';
import 'warehouse_dialog_shared.dart';

/// Inbound dialog — trading companies / suppliers supply goods.
class InboundStockDialog extends StatelessWidget {
  const InboundStockDialog({super.key, this.product});

  final ProductModel? product;

  static Future<bool?> show(BuildContext context, {ProductModel? product}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InboundStockDialog(product: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => StockEntryViewModel(
        mode: StockEntryMode.inbound,
        existingProduct: product,
      )..load(),
      child: const _InboundBody(),
    );
  }
}

class _InboundBody extends StatelessWidget {
  const _InboundBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StockEntryViewModel>();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context, false),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            _save(context, vm),
      },
      child: WarehouseDialogShell(
        icon: Icons.inventory_2_outlined,
        iconColor: AppColors.primary,
        title: 'stockEntry.inboundTitle'.tr(),
        subtitle: 'stockEntry.inboundSubtitle'.tr(),
        saving: vm.saving,
        primaryLabel: 'stockEntry.saveInbound'.tr(),
        primaryIcon: Icons.save_outlined,
        onCancel: () => Navigator.pop(context, false),
        onPrimary: () => _save(context, vm),
        body: vm.loading
            ? const SizedBox(height: 160, child: GfPageLoader())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (vm.formError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        vm.formError!.startsWith('stockEntry.')
                            ? vm.formError!.tr()
                            : vm.formError!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  if (vm.products.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'stockEntry.addProductFirst'.tr(),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  DialogResponsiveRow(
                    children: [
                      _DateField(vm: vm),
                      _CompanyField(vm: vm),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _EmployeeField(vm: vm),
                  const SizedBox(height: 14),
                  GfDropdown<ProductModel>(
                    label: 'stockEntry.product'.tr(),
                    required: true,
                    searchable: true,
                    searchHint: 'common.search'.tr(),
                    items: vm.products,
                    value: vm.selectedProduct,
                    hint: 'stockEntry.selectItem'.tr(),
                    prefixIcon: Icons.layers_outlined,
                    labelBuilder: (p) => p.displayName,
                    errorText: vm.visibleError('product') != null
                        ? 'stockEntry.required'.tr()
                        : null,
                    onChanged: vm.selectProduct,
                  ),
                  if (vm.selectedProduct != null) ...[
                    const SizedBox(height: 12),
                    DialogProductCard(product: vm.selectedProduct!),
                  ],
                  const SizedBox(height: 14),
                  GfTextField(
                    controller: vm.quantityController,
                    focusNode: vm.quantityFocus,
                    label: 'stockEntry.quantity'.tr(),
                    required: true,
                    hint: 'stockEntry.quantityHint'.tr(),
                    numberMode: true,
                    onSubmitted: (_) => vm.onQuantityEditingComplete(),
                    errorText: vm.visibleError('quantity') != null
                        ? 'stockEntry.required'.tr()
                        : null,
                  ),
                  const SizedBox(height: 14),
                  GfTextField(
                    controller: vm.notesController,
                    label: 'stockEntry.notes'.tr(),
                    hint: 'stockEntry.notesHint'.tr(),
                    prefixIcon: Icons.notes_outlined,
                    minLines: 1,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  PurchaseDataGate(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DialogResponsiveRow(
                          children: [
                            GfTextField(
                              controller: vm.priceController,
                              label: 'stockEntry.inboundPrice'.tr(),
                              hint: 'stockEntry.priceHint'.tr(),
                              numberMode: true,
                              prefixIcon: Icons.payments_outlined,
                              errorText: vm.visibleError('price') != null
                                  ? 'stockEntry.required'.tr()
                                  : null,
                            ),
                            GfDropdown<CurrencyModel>(
                              label: 'stockEntry.currency'.tr(),
                              items: vm.currencies,
                              value: vm.selectedCurrency,
                              hint: 'stockEntry.selectCurrency'.tr(),
                              prefixIcon: Icons.attach_money_rounded,
                              labelBuilder: (c) =>
                                  Formatters.currencyName(c.code),
                              errorText: vm.visibleError('currency') != null
                                  ? 'stockEntry.required'.tr()
                                  : null,
                              onChanged: vm.selectCurrency,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        GfTextField(
                          key: ValueKey('total-${vm.lineTotalDisplay}'),
                          label: 'stockEntry.lineTotal'.tr(),
                          initialValue: vm.lineTotalDisplay,
                          readOnly: true,
                          enabled: false,
                          prefixIcon: Icons.calculate_outlined,
                        ),
                        const SizedBox(height: 14),
                        DialogResponsiveRow(
                          children: [
                            GfTextField(
                              controller: vm.paidController,
                              label: 'stockEntry.paidAmount'.tr(),
                              hint: 'stockEntry.paidHint'.tr(),
                              numberMode: true,
                              prefixIcon:
                                  Icons.account_balance_wallet_outlined,
                              errorText: vm.visibleError('paid') == null
                                  ? null
                                  : (vm.visibleError('paid') == 'over'
                                        ? 'stockEntry.paidExceedsTotal'.tr()
                                        : 'stockEntry.invalidPaid'.tr()),
                            ),
                            GfTextField(
                              key: ValueKey('due-${vm.outstandingDisplay}'),
                              label: 'stockEntry.outstanding'.tr(),
                              initialValue: vm.outstandingDisplay,
                              readOnly: true,
                              enabled: false,
                              prefixIcon: Icons.pending_actions_outlined,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                  _DriverDetailsSection(
                    vm: vm,
                    nameLabel: 'stockEntry.driver'.tr(),
                    sectionTitle: 'stockEntry.driverSection'.tr(),
                  ),
                  const SizedBox(height: 14),
                  _LocationField(vm: vm),
                  const SizedBox(height: 14),
                  DialogInfoBanner(message: 'stockEntry.inboundInfo'.tr()),
                ],
              ),
      ),
    );
  }

  Future<void> _save(BuildContext context, StockEntryViewModel vm) async {
    final err = await vm.save();
    if (!context.mounted) return;
    if (err == null) Navigator.pop(context, true);
  }
}

/// Outbound dialog — customers receive / buy goods.
class OutboundStockDialog extends StatelessWidget {
  const OutboundStockDialog({super.key, this.product});

  final ProductModel? product;

  static Future<bool?> show(BuildContext context, {ProductModel? product}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OutboundStockDialog(product: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => StockEntryViewModel(
        mode: StockEntryMode.outbound,
        existingProduct: product,
      )..load(),
      child: const _OutboundBody(),
    );
  }
}

class _OutboundBody extends StatelessWidget {
  const _OutboundBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StockEntryViewModel>();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context, false),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            _save(context, vm),
      },
      child: WarehouseDialogShell(
        icon: Icons.north_east_rounded,
        iconColor: AppColors.error,
        title: 'stockEntry.outboundTitle'.tr(),
        subtitle: 'stockEntry.outboundSubtitle'.tr(),
        saving: vm.saving,
        primaryLabel: 'stockEntry.saveOutbound'.tr(),
        primaryIcon: Icons.local_shipping_outlined,
        onCancel: () => Navigator.pop(context, false),
        onPrimary: () => _save(context, vm),
        body: vm.loading
            ? const SizedBox(height: 160, child: GfPageLoader())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (vm.formError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        vm.formError!.startsWith('stockEntry.')
                            ? vm.formError!.tr()
                            : vm.formError!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  if (vm.products.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'stockEntry.addProductFirst'.tr(),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  DialogResponsiveRow(
                    children: [
                      _DateField(vm: vm),
                      _CompanyField(vm: vm),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _EmployeeField(vm: vm),
                  const SizedBox(height: 14),
                  GfDropdown<ProductModel>(
                    label: 'stockEntry.product'.tr(),
                    required: true,
                    searchable: true,
                    searchHint: 'common.search'.tr(),
                    items: vm.products,
                    value: vm.selectedProduct,
                    hint: 'stockEntry.selectItem'.tr(),
                    prefixIcon: Icons.layers_outlined,
                    labelBuilder: (p) {
                      return '${p.displayName} (${formatDimNum(p.currentStock)})';
                    },
                    errorText: vm.visibleError('product') != null
                        ? 'stockEntry.required'.tr()
                        : null,
                    onChanged: vm.selectProduct,
                  ),
                  if (vm.selectedProduct != null) ...[
                    const SizedBox(height: 12),
                    DialogProductCard(
                      product: vm.selectedProduct!,
                      showStock: true,
                      afterStock: vm.afterStock,
                    ),
                  ],
                  const SizedBox(height: 14),
                  GfTextField(
                    controller: vm.quantityController,
                    focusNode: vm.quantityFocus,
                    label: 'stockEntry.quantity'.tr(),
                    required: true,
                    hint: 'stockEntry.quantityHint'.tr(),
                    numberMode: true,
                    onSubmitted: (_) => vm.onQuantityEditingComplete(),
                    errorText: vm.visibleError('quantity') != null
                        ? (vm.visibleError('quantity') == 'stock'
                              ? 'stockEntry.notEnoughStock'.tr()
                              : 'stockEntry.required'.tr())
                        : null,
                  ),
                  const SizedBox(height: 14),
                  GfTextField(
                    controller: vm.notesController,
                    label: 'stockEntry.notes'.tr(),
                    hint: 'stockEntry.notesHint'.tr(),
                    prefixIcon: Icons.notes_outlined,
                    minLines: 1,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  DialogResponsiveRow(
                    children: [
                      GfTextField(
                        controller: vm.priceController,
                        label: 'stockEntry.outboundPrice'.tr(),
                        hint: 'stockEntry.priceHint'.tr(),
                        numberMode: true,
                        prefixIcon: Icons.payments_outlined,
                        errorText: vm.visibleError('price') != null
                            ? 'stockEntry.required'.tr()
                            : null,
                      ),
                      GfDropdown<CurrencyModel>(
                        label: 'stockEntry.currency'.tr(),
                        items: vm.currencies,
                        value: vm.selectedCurrency,
                        hint: 'stockEntry.selectCurrency'.tr(),
                        prefixIcon: Icons.attach_money_rounded,
                        labelBuilder: (c) => Formatters.currencyName(c.code),
                        errorText: vm.visibleError('currency') != null
                            ? 'stockEntry.required'.tr()
                            : null,
                        onChanged: vm.selectCurrency,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  GfTextField(
                    key: ValueKey('total-out-${vm.lineTotalDisplay}'),
                    label: 'stockEntry.lineTotal'.tr(),
                    initialValue: vm.lineTotalDisplay,
                    readOnly: true,
                    enabled: false,
                    prefixIcon: Icons.calculate_outlined,
                  ),
                  const SizedBox(height: 14),
                  DialogResponsiveRow(
                    children: [
                      GfTextField(
                        controller: vm.paidController,
                        label: 'stockEntry.paidAmount'.tr(),
                        hint: 'stockEntry.paidHint'.tr(),
                        numberMode: true,
                        prefixIcon: Icons.account_balance_wallet_outlined,
                        errorText: vm.visibleError('paid') == null
                            ? null
                            : (vm.visibleError('paid') == 'over'
                                  ? 'stockEntry.paidExceedsTotal'.tr()
                                  : 'stockEntry.invalidPaid'.tr()),
                      ),
                      GfTextField(
                        key: ValueKey('due-out-${vm.outstandingDisplay}'),
                        label: 'stockEntry.outstanding'.tr(),
                        initialValue: vm.outstandingDisplay,
                        readOnly: true,
                        enabled: false,
                        prefixIcon: Icons.pending_actions_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _DriverDetailsSection(
                    vm: vm,
                    nameLabel: 'stockEntry.receiver'.tr(),
                    sectionTitle: 'stockEntry.receiverSection'.tr(),
                  ),
                  const SizedBox(height: 14),
                  _LocationField(vm: vm),
                  const SizedBox(height: 14),
                  DialogInfoBanner(message: 'stockEntry.outboundInfo'.tr()),
                ],
              ),
      ),
    );
  }

  Future<void> _save(BuildContext context, StockEntryViewModel vm) async {
    final err = await vm.save();
    if (!context.mounted) return;
    if (err == null) Navigator.pop(context, true);
  }
}

class _CompanyField extends StatelessWidget {
  const _CompanyField({required this.vm});

  final StockEntryViewModel vm;

  @override
  Widget build(BuildContext context) {
    final isInbound = vm.isInbound;
    return GfDropdown<TradingPartnerOption>(
      label: isInbound
          ? 'stockEntry.company'.tr()
          : 'stockEntry.customer'.tr(),
      required: true,
      searchable: true,
      searchHint: 'common.search'.tr(),
      items: vm.companies,
      value: vm.selectedCompany,
      hint: isInbound
          ? 'stockEntry.selectCompany'.tr()
          : 'stockEntry.selectCustomer'.tr(),
      labelBuilder: (c) => c.name,
      prefixIcon: isInbound
          ? Icons.apartment_outlined
          : Icons.person_outline_rounded,
      errorText: vm.visibleError('partner') != null
          ? (isInbound
                ? 'stockEntry.companyRequired'.tr()
                : 'stockEntry.customerRequired'.tr())
          : null,
      onChanged: vm.selectCompany,
    );
  }
}

class _EmployeeField extends StatelessWidget {
  const _EmployeeField({required this.vm});

  final StockEntryViewModel vm;

  @override
  Widget build(BuildContext context) {
    return GfDropdown<EmployeeModel>(
      label: 'stockEntry.employee'.tr(),
      searchable: true,
      searchHint: 'common.search'.tr(),
      items: vm.employees,
      value: vm.selectedEmployee,
      hint: 'stockEntry.selectEmployee'.tr(),
      prefixIcon: Icons.badge_outlined,
      labelBuilder: (e) {
        final role = (e.role ?? '').trim();
        return role.isEmpty ? e.fullName : '${e.fullName} · $role';
      },
      onChanged: vm.selectEmployee,
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.vm});

  final StockEntryViewModel vm;

  @override
  Widget build(BuildContext context) {
    final label = ShamsiDates.formatDate(vm.transactionDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: 'stockEntry.transactionDate'.tr(),
            style: AppTypography.label,
            children: [
              TextSpan(
                text: ' *',
                style: AppTypography.label.copyWith(color: AppColors.error),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        InkWell(
          onTap: () async {
            final picked = await ShamsiDates.pickDate(
              context,
              initial: vm.transactionDate,
            );
            if (picked != null) vm.setTransactionDate(picked);
          },
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: AppSpacing.controlHeight,
            child: InputDecorator(
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                prefixIcon: Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  // borderSide: const BorderSide(color: kDialogBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(label, style: AppTypography.body),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationField extends StatelessWidget {
  const _LocationField({required this.vm});

  final StockEntryViewModel vm;

  @override
  Widget build(BuildContext context) {
    return GfDropdown<WarehouseModel>(
      label: 'stockEntry.warehouseLocation'.tr(),
      required: true,
      searchable: true,
      searchHint: 'common.search'.tr(),
      hint: 'stockEntry.selectLocation'.tr(),
      items: vm.warehouses,
      value: vm.selectedWarehouse,
      labelBuilder: (w) => w.name,
      prefixIcon: Icons.location_on_outlined,
      errorText: vm.visibleError('location') != null
          ? 'stockEntry.required'.tr()
          : null,
      onChanged: vm.selectWarehouse,
    );
  }
}

class _DriverDetailsSection extends StatelessWidget {
  const _DriverDetailsSection({
    required this.vm,
    required this.nameLabel,
    required this.sectionTitle,
  });

  final StockEntryViewModel vm;
  final String nameLabel;
  final String sectionTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kDialogSoftBlue,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kDialogBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.badge_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(sectionTitle, style: AppTypography.bodySemiBold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'stockEntry.driverSectionHint'.tr(),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          DialogResponsiveRow(
            children: [
              GfTextField(
                controller: vm.driverController,
                label: nameLabel,
                prefixIcon: Icons.person_outline,
              ),
              GfTextField(
                controller: vm.vehicleController,
                label: 'stockEntry.vehicle'.tr(),
                prefixIcon: Icons.local_shipping_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          GfTextField(
            controller: vm.driverDescriptionController,
            label: 'stockEntry.driverDescription'.tr(),
            hint: 'stockEntry.driverDescriptionHint'.tr(),
            prefixIcon: Icons.description_outlined,
            minLines: 1,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
