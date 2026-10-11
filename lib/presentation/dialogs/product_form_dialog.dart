import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/category_model.dart';
import '../../data/models/currency_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/warehouse_model.dart';
import '../providers/app_settings_provider.dart';
import '../providers/auth_provider.dart';
import '../viewmodels/product_form_viewmodel.dart';
import 'warehouse_dialog_shared.dart';

class ProductFormDialog extends StatelessWidget {
  const ProductFormDialog({super.key, this.product});

  final ProductModel? product;

  static Future<bool?> show(BuildContext context, {ProductModel? product}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductFormDialog(product: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeType = context.read<AppSettingsProvider>().storeType;
    final allowCostPrice = context.read<AuthProvider>().canViewPurchaseData;
    return ChangeNotifierProvider(
      create: (_) => ProductFormViewModel(
        existing: product,
        storeType: storeType,
        allowCostPrice: allowCostPrice,
      )..loadLookups(),
      child: const _ProductFormBody(),
    );
  }
}

class _ProductFormBody extends StatefulWidget {
  const _ProductFormBody();

  @override
  State<_ProductFormBody> createState() => _ProductFormBodyState();
}

class _ProductFormBodyState extends State<_ProductFormBody> {
  static const _textFields = [
    'name',
    'sku',
    'barcode',
    'costPrice',
    'sellingPrice',
    'minStock',
    'unitWeight',
  ];
  static const _otherFields = [
    'category',
    'location',
    'costCurrency',
    'sellingCurrency',
    'expiryAlert',
  ];

  final Map<String, GlobalKey> _fieldKeys = {
    for (final f in [..._textFields, ..._otherFields])
      f: GlobalKey(debugLabel: 'product.$f'),
  };
  final Map<String, FocusNode> _focusNodes = {
    for (final f in _textFields) f: FocusNode(debugLabel: 'product.$f'),
  };

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  String? _errorText(ProductFormViewModel vm, String field) {
    return switch (vm.errorOf(field)) {
      null => null,
      'duplicate' => 'errors.duplicateValue'.tr(),
      'positive' || 'invalid' => 'products.add.validation.positive'.tr(),
      'negative' => 'products.add.validation.nonNegative'.tr(),
      _ when field == 'costCurrency' || field == 'sellingCurrency' =>
        'products.add.validation.currency'.tr(),
      _ => 'stockEntry.required'.tr(),
    };
  }

  /// Brings the top-most invalid field into view, and focuses it when it
  /// is a text field.
  void _revealFirstError(ProductFormViewModel vm) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      String? target;
      BuildContext? targetContext;
      double? targetTop;
      for (final entry in _fieldKeys.entries) {
        if (vm.errorOf(entry.key) == null) continue;
        final ctx = entry.value.currentContext;
        final box = ctx?.findRenderObject();
        if (ctx == null || box is! RenderBox || !box.attached) continue;
        final top = box.localToGlobal(Offset.zero).dy;
        if (targetTop == null || top < targetTop) {
          target = entry.key;
          targetContext = ctx;
          targetTop = top;
        }
      }
      if (targetContext == null) return;
      final focus = _focusNodes[target];
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.2,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ).then((_) {
        if (mounted) focus?.requestFocus();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductFormViewModel>();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _tryClose(context, vm),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            _save(context, vm),
      },
      child: WarehouseDialogShell(
        icon: Icons.inventory_2_outlined,
        iconColor: AppColors.primary,
        title: vm.isEdit
            ? 'products.add.editTitle'.tr()
            : 'products.add.title'.tr(),
        subtitle: 'products.add.warehouseSubtitle'.tr(),
        saving: vm.saving,
        primaryLabel: 'products.add.actions.save'.tr(),
        primaryIcon: Icons.save_outlined,
        onCancel: () => _tryClose(context, vm),
        onPrimary: () => _save(context, vm),
        maxWidth: 560,
        body: vm.loadingLookups
            ? const SizedBox(height: 160, child: GfPageLoader())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // if (vm.formError != null)
                  //   Padding(
                  //     padding: const EdgeInsets.only(bottom: 10),
                  //     child: Text(
                  //       vm.formError!,
                  //       style: AppTypography.caption.copyWith(
                  //         color: AppColors.error,
                  //       ),
                  //     ),
                  //   ),
                  DialogImagePicker(
                    imagePath: vm.imagePath,
                    onPick: vm.pickImage,
                    onClear: vm.clearImage,
                  ),
                  const SizedBox(height: 14),
                  DialogResponsiveRow(
                    breakpoint: 400,
                    children: [
                      GfTextField(
                        key: _fieldKeys['name'],
                        focusNode: _focusNodes['name'],
                        label: 'products.add.fields.productName'.tr(),
                        required: true,
                        hint: 'products.add.fields.productNameHint'.tr(),
                        initialValue: vm.name,
                        prefixIcon: Icons.inventory_2_outlined,
                        autofocus: true,
                        errorText: _errorText(vm, 'name'),
                        onChanged: (v) {
                          vm.name = v;
                          vm.markDirty();
                        },
                      ),
                      GfTextField(
                        key: _fieldKeys['sku'],
                        focusNode: _focusNodes['sku'],
                        label: 'products.add.fields.sku'.tr(),
                        hint: 'products.add.fields.skuHint'.tr(),
                        initialValue: vm.sku,
                        prefixIcon: Icons.qr_code_2_outlined,
                        errorText: _errorText(vm, 'sku'),
                        onChanged: (v) {
                          vm.sku = v;
                          vm.markDirty();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DialogResponsiveRow(
                    breakpoint: 400,
                    children: [
                      GfTextField(
                        key: _fieldKeys['barcode'],
                        focusNode: _focusNodes['barcode'],
                        label: 'products.add.fields.barcode'.tr(),
                        hint: 'products.add.fields.barcodeHint'.tr(),
                        initialValue: vm.barcode,
                        prefixIcon: Icons.qr_code_scanner_outlined,
                        errorText: _errorText(vm, 'barcode'),
                        onChanged: (v) {
                          vm.barcode = v;
                          vm.markDirty();
                        },
                      ),
                      GfTextField(
                        label: 'products.add.fields.brand'.tr(),
                        hint: 'products.add.fields.brandHint'.tr(),
                        initialValue: vm.brand,
                        prefixIcon: Icons.branding_watermark_outlined,
                        onChanged: (v) {
                          vm.brand = v;
                          vm.markDirty();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  GfDropdown<CategoryModel>(
                    key: _fieldKeys['category'],
                    label: 'products.add.fields.category'.tr(),
                    required: true,
                    hint: 'products.add.fields.selectCategory'.tr(),
                    searchable: true,
                    searchHint: 'common.search'.tr(),
                    items: vm.categories,
                    value: vm.categories
                        .where((c) => c.id == vm.categoryId)
                        .firstOrNull,
                    labelBuilder: (c) => c.name,
                    prefixIcon: Icons.category_outlined,
                    errorText: _errorText(vm, 'category'),
                    onChanged: (c) {
                      vm.categoryId = c?.id;
                      vm.markDirty();
                    },
                  ),
                  const SizedBox(height: 14),
                  DialogResponsiveRow(
                    breakpoint: 400,
                    children: [
                      GfDropdown<WarehouseModel>(
                        key: _fieldKeys['location'],
                        label: 'stockEntry.warehouseLocation'.tr(),
                        required: true,
                        searchable: true,
                        searchHint: 'common.search'.tr(),
                        hint: 'stockEntry.selectLocation'.tr(),
                        items: vm.warehouses,
                        value: vm.selectedWarehouse,
                        labelBuilder: (w) => w.name,
                        prefixIcon: Icons.location_on_outlined,
                        errorText: _errorText(vm, 'location'),
                        onChanged: (w) {
                          vm.warehouseId = w?.id;
                          vm.markDirty();
                        },
                      ),
                      GfDropdown<String>(
                        label: 'products.add.fields.unitOfMeasure'.tr(),
                        required: true,
                        items: kProductUnits,
                        value: vm.unitOfMeasure == null
                            ? null
                            : normalizeProductUnit(vm.unitOfMeasure),
                        hint: 'products.add.fields.selectUnit'.tr(),
                        labelBuilder: productUnitLabel,
                        onChanged: (u) {
                          vm.unitOfMeasure = u == null
                              ? null
                              : normalizeProductUnit(u);
                          vm.markDirty();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Text(
                  //   'products.add.pricingSection'.tr(),
                  //   style: AppTypography.caption.copyWith(
                  //     color: AppColors.textMuted,
                  //     fontWeight: FontWeight.w600,
                  //   ),
                  // ),
                  const SizedBox(height: 8),
                  if (vm.allowCostPrice) ...[
                    DialogResponsiveRow(
                      breakpoint: 400,
                      children: [
                        GfTextField(
                          key: _fieldKeys['costPrice'],
                          focusNode: _focusNodes['costPrice'],
                          label: 'products.add.fields.costPrice'.tr(),
                          hint: 'products.add.fields.costPriceHint'.tr(),
                          initialValue: vm.costPrice,
                          numberMode: true,
                          prefixIcon: Icons.shopping_cart_outlined,
                          errorText: _errorText(vm, 'costPrice'),
                          onChanged: (v) {
                            vm.costPrice = v;
                            vm.markDirty();
                          },
                        ),
                        GfDropdown<CurrencyModel>(
                          key: _fieldKeys['costCurrency'],
                          label: 'purchases.purchaseCurrency'.tr(),
                          items: vm.currencies,
                          value: vm.selectedCostCurrency,
                          hint: 'purchases.selectCurrency'.tr(),
                          prefixIcon: Icons.attach_money_rounded,
                          errorText: _errorText(vm, 'costCurrency'),
                          labelBuilder: (c) =>
                              '${Formatters.currencyName(c.code)} (${c.code})',
                          onChanged: (c) {
                            vm.costCurrencyId = c?.id;
                            vm.markDirty();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  DialogResponsiveRow(
                    breakpoint: 400,
                    children: [
                      GfTextField(
                        key: _fieldKeys['sellingPrice'],
                        focusNode: _focusNodes['sellingPrice'],
                        label: 'products.add.fields.sellingPrice'.tr(),
                        hint: 'products.add.fields.sellingPriceHint'.tr(),
                        initialValue: vm.sellingPrice,
                        numberMode: true,
                        prefixIcon: Icons.sell_outlined,
                        errorText: _errorText(vm, 'sellingPrice'),
                        onChanged: (v) {
                          vm.sellingPrice = v;
                          vm.markDirty();
                        },
                      ),
                      GfDropdown<CurrencyModel>(
                        key: _fieldKeys['sellingCurrency'],
                        label: 'purchases.sellingCurrency'.tr(),
                        items: vm.currencies,
                        value: vm.selectedSellingCurrency,
                        hint: 'purchases.selectCurrency'.tr(),
                        prefixIcon: Icons.attach_money_rounded,
                        errorText: _errorText(vm, 'sellingCurrency'),
                        labelBuilder: (c) =>
                            '${Formatters.currencyName(c.code)} (${c.code})',
                        onChanged: (c) {
                          vm.currencyId = c?.id;
                          vm.markDirty();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DialogResponsiveRow(
                    breakpoint: 400,
                    children: [
                      GfTextField(
                        key: _fieldKeys['minStock'],
                        focusNode: _focusNodes['minStock'],
                        label: 'products.add.fields.minimumStock'.tr(),
                        hint: 'products.add.fields.minimumStockHint'.tr(),
                        initialValue: vm.minStock,
                        numberMode: true,
                        errorText: _errorText(vm, 'minStock'),
                        onChanged: (v) {
                          vm.minStock = v;
                          vm.markDirty();
                        },
                      ),
                      if (vm.showExpiry)
                        GfShamsiDateField(
                          label: 'products.add.fields.expiration'.tr(),
                          hint: 'products.add.fields.expirationHint'.tr(),
                          value: vm.expirationDate,
                          onChanged: vm.setExpirationDate,
                        )
                      else
                        GfTextField(
                          key: _fieldKeys['unitWeight'],
                          focusNode: _focusNodes['unitWeight'],
                          label: 'products.add.fields.unitWeight'.tr(),
                          hint: 'products.add.fields.unitWeightHint'.tr(),
                          initialValue: vm.unitWeight,
                          numberMode: true,
                          prefixIcon: Icons.scale_outlined,
                          errorText: _errorText(vm, 'unitWeight'),
                          onChanged: (v) {
                            vm.unitWeight = v;
                            vm.markDirty();
                          },
                        ),
                    ],
                  ),
                  if (vm.showExpiry) ...[
                    if (vm.expirationDate != null) ...[
                      const SizedBox(height: 14),
                      _ExpiryAlertField(
                        key: _fieldKeys['expiryAlert'],
                        value: vm.expiryAlertValue,
                        unit: vm.expiryAlertUnit,
                        errorText: _errorText(vm, 'expiryAlert'),
                        onValueChanged: (v) {
                          vm.expiryAlertValue = v;
                          vm.markDirty();
                        },
                        onUnitChanged: vm.setExpiryAlertUnit,
                      ),
                    ],
                    const SizedBox(height: 14),
                    DialogResponsiveRow(
                      breakpoint: 400,
                      children: [
                        GfTextField(
                          key: _fieldKeys['unitWeight'],
                          focusNode: _focusNodes['unitWeight'],
                          label: 'products.add.fields.unitWeight'.tr(),
                          hint: 'products.add.fields.unitWeightHint'.tr(),
                          initialValue: vm.unitWeight,
                          numberMode: true,
                          prefixIcon: Icons.scale_outlined,
                          errorText: _errorText(vm, 'unitWeight'),
                          onChanged: (v) {
                            vm.unitWeight = v;
                            vm.markDirty();
                          },
                        ),
                        GfDropdown<String>(
                          label: 'products.add.fields.weightUnit'.tr(),
                          items: kWeightUnits,
                          value: normalizeWeightUnit(vm.weightUnit),
                          labelBuilder: weightUnitLabel,
                          onChanged: (u) {
                            if (u == null) return;
                            vm.weightUnit = normalizeWeightUnit(u);
                            vm.markDirty();
                          },
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  GfTextField(
                    label: 'stockEntry.notes'.tr(),
                    hint: 'products.add.notesHint'.tr(),
                    initialValue: vm.notes,
                    prefixIcon: Icons.sticky_note_2_outlined,
                    minLines: 1,
                    maxLines: 2,
                    onChanged: (v) {
                      vm.notes = v;
                      vm.markDirty();
                    },
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _tryClose(BuildContext context, ProductFormViewModel vm) async {
    if (!vm.dirty) {
      Navigator.pop(context, false);
      return;
    }
    final discard = await GfConfirmDialog.show(
      context,
      title: 'products.add.messages.discardTitle'.tr(),
      message: 'products.add.messages.discardBody'.tr(),
      confirmLabel: 'common.discard'.tr(),
      cancelLabel: 'common.keepEditing'.tr(),
      danger: true,
    );
    if (discard == true && context.mounted) {
      Navigator.pop(context, false);
    }
  }

  Future<void> _save(BuildContext context, ProductFormViewModel vm) async {
    if (vm.saving) return;
    final err = await vm.save();
    if (!context.mounted) return;
    if (err != null) {
      _revealFirstError(vm);
      return;
    }
    GfToast.show(
      context,
      title: 'products.add.messages.saved'.tr(),
      message: 'sync.queuedHint'.tr(),
      type: GfToastType.success,
    );
    Navigator.pop(context, true);
  }
}

/// Number + unit control: unit dropdown stays on the physical left.
class _ExpiryAlertField extends StatelessWidget {
  const _ExpiryAlertField({
    super.key,
    required this.value,
    required this.unit,
    required this.onValueChanged,
    required this.onUnitChanged,
    this.errorText,
  });

  final String value;
  final String unit;
  final ValueChanged<String> onValueChanged;
  final ValueChanged<String?> onUnitChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final controlH = AppSpacing.controlHeight;
    final borderColor = errorText != null ? AppColors.error : AppColors.border;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'products.add.fields.expiryAlert'.tr(),
          style: AppTypography.label,
        ),
        const SizedBox(height: AppSpacing.xs),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: AppRadius.input,
            border: Border.all(color: borderColor),
          ),
          child: SizedBox(
            height: controlH,
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: normalizeExpiryAlertUnit(unit),
                      isDense: true,
                      borderRadius: AppRadius.input,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      items: [
                        for (final u in kExpiryAlertUnits)
                          DropdownMenuItem(
                            value: u,
                            child: Text(expiryAlertUnitLabel(u)),
                          ),
                      ],
                      onChanged: onUnitChanged,
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: controlH - 12,
                  color: AppColors.border,
                ),
                Expanded(
                  child: GfTextField(
                    borderless: true,
                    numberMode: true,
                    initialValue: value,
                    hint: 'products.add.fields.expiryAlertHint'.tr(),
                    textAlign: TextAlign.start,
                    onChanged: onValueChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'products.add.fields.expiryAlertHelp'.tr(),
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            errorText!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}
