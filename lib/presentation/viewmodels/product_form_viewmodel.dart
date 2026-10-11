import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../core/database/app_database.dart';
import '../../core/di/service_locator.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/file_helpers.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/category_model.dart';
import '../../data/models/currency_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/warehouse_model.dart';
import '../../domain/repositories/lookup_repository.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../../domain/repositories/warehouse_repository.dart';
import '../dialogs/warehouse_dialog_shared.dart';

/// General-store product catalog form.
class ProductFormViewModel extends ChangeNotifier {
  ProductFormViewModel({
    this.existing,
    this.storeType = 'general',
    this.allowCostPrice = true,
    ProductRepository? products,
    LookupRepository? lookups,
    WarehouseRepository? warehouses,
    SupplierRepository? suppliers,
  }) : _products = products ?? ServiceLocator.instance.products,
       _lookups = lookups ?? ServiceLocator.instance.lookups,
       _warehouses = warehouses ?? ServiceLocator.instance.warehouses,
       _suppliers = suppliers ?? ServiceLocator.instance.suppliers {
    if (existing != null) {
      name = existing!.name;
      sku = existing!.sku;
      barcode = existing!.barcode ?? '';
      brand = existing!.brand ?? '';
      description = existing!.description ?? '';
      categoryId = existing!.categoryId;
      supplierId = existing!.supplierId;
      unitOfMeasure = normalizeProductUnit(existing!.unitOfMeasure);
      unitWeight = existing!.unitWeight != null
          ? Formatters.number(existing!.unitWeight!)
          : '';
      weightUnit = normalizeWeightUnit(existing!.weightUnit);
      minStock = existing!.minimumStockAlert > 0
          ? Formatters.number(existing!.minimumStockAlert)
          : '10';
      costPrice = existing!.costPrice > 0
          ? Formatters.number(existing!.costPrice)
          : '';
      sellingPrice = existing!.sellingPrice > 0
          ? Formatters.number(existing!.sellingPrice)
          : '';
      currencyId = existing!.currencyId;
      costCurrencyId = existing!.costCurrencyId ?? existing!.currencyId;
      warehouseId = existing!.warehouseId;
      notes = existing!.notes ?? '';
      imagePath = existing!.imagePath;
      isActive = existing!.isActive;
      if (existing!.expirationDate != null) {
        expirationDate = existing!.expirationDate;
      }
      expiryAlertValue = existing!.expiryAlertValue > 0
          ? '${existing!.expiryAlertValue}'
          : '1';
      expiryAlertUnit = normalizeExpiryAlertUnit(existing!.expiryAlertUnit);
    } else {
      unitOfMeasure = 'pcs';
      weightUnit = 'kg';
      minStock = '10';
      expiryAlertValue = '1';
      expiryAlertUnit = 'month';
    }
  }

  final ProductModel? existing;
  final String storeType;

  /// When false, cost/purchase price fields are hidden and existing values are preserved.
  final bool allowCostPrice;
  final ProductRepository _products;
  final LookupRepository _lookups;
  final WarehouseRepository _warehouses;
  final SupplierRepository _suppliers;

  bool get isEdit => existing != null;
  bool get showExpiry => storeType == 'supplement' || storeType == 'general';
  bool get emphasizeBrand =>
      storeType == 'clothing' || storeType == 'supplement';

  String name = '';
  String sku = '';
  String barcode = '';
  String brand = '';
  String description = '';
  int? categoryId;
  int? supplierId;
  String? unitOfMeasure;
  String unitWeight = '';
  String weightUnit = 'kg';
  String minStock = '10';
  String costPrice = '';
  String sellingPrice = '';
  String notes = '';
  int? warehouseId;
  String? imagePath;
  bool isActive = true;
  DateTime? expirationDate;
  String expiryAlertValue = '1';
  String expiryAlertUnit = 'month';

  bool loadingLookups = true;
  bool saving = false;
  bool dirty = false;
  bool submitted = false;
  Map<String, String> fieldErrors = {};
  String? formError;

  String? errorOf(String key) => submitted ? fieldErrors[key] : null;

  List<CategoryModel> categories = const [];
  List<CurrencyModel> currencies = const [];
  List<WarehouseModel> warehouses = const [];
  List<SupplierModel> suppliers = const [];
  int? currencyId;
  int? costCurrencyId;

  CurrencyModel? get selectedSellingCurrency {
    if (currencyId == null) return null;
    return currencies.where((c) => c.id == currencyId).firstOrNull;
  }

  CurrencyModel? get selectedCostCurrency {
    if (costCurrencyId == null) return null;
    return currencies.where((c) => c.id == costCurrencyId).firstOrNull;
  }

  WarehouseModel? get selectedWarehouse {
    if (warehouseId == null) return null;
    return warehouses.where((w) => w.id == warehouseId).firstOrNull;
  }

  SupplierModel? get selectedSupplier {
    if (supplierId == null) return null;
    return suppliers.where((s) => s.id == supplierId).firstOrNull;
  }

  bool get isValid =>
      name.trim().isNotEmpty &&
      categoryId != null &&
      warehouseId != null &&
      fieldErrors.isEmpty;

  Future<void> loadLookups() async {
    loadingLookups = true;
    notifyListeners();
    final cats = await _lookups.getCategories();
    final curs = await _lookups.getCurrencies();
    final whs = await _warehouses.list();
    final sups = await _suppliers.query(pageSize: 500);

    cats.when(success: (v) => categories = v, failure: (_) {});
    curs.when(
      success: (v) {
        final active = v.where((c) => c.isActive).toList();
        currencies = active.isEmpty ? v : active;
        final fallback =
            currencies.where((c) => c.isBase).firstOrNull?.id ??
            currencies.firstOrNull?.id;
        currencyId ??= fallback;
        costCurrencyId ??= currencyId ?? fallback;
      },
      failure: (_) {},
    );
    whs.when(
      success: (v) {
        warehouses = v;
        warehouseId ??= v.firstOrNull?.id;
      },
      failure: (_) {},
    );
    sups.when(success: (v) => suppliers = v.items, failure: (_) {});
    loadingLookups = false;
    notifyListeners();
  }

  Future<void> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.size > 5 * 1024 * 1024) {
      formError = 'errors.imageTooLarge'.tr();
      notifyListeners();
      return;
    }
    if (file.path == null) return;
    try {
      imagePath = await FileHelpers.copyImageToAppStorage(
        source: File(file.path!),
        imagesDir: AppDatabase.imagesDir,
      );
      formError = null;
      markDirty();
    } catch (e) {
      formError = e.toString();
      notifyListeners();
    }
  }

  void clearImage() {
    imagePath = null;
    markDirty();
  }

  void setExpirationDate(DateTime? date) {
    expirationDate = date;
    markDirty();
  }

  void setExpiryAlertUnit(String? unit) {
    expiryAlertUnit = normalizeExpiryAlertUnit(unit);
    markDirty();
  }

  void markDirty() {
    dirty = true;
    if (submitted) {
      validate(silent: true);
      if (fieldErrors.isEmpty) formError = null;
    }
    notifyListeners();
  }

  void validate({bool silent = false}) {
    final errors = <String, String>{};
    if (name.trim().isEmpty) errors['name'] = 'required';
    if (categoryId == null) errors['category'] = 'required';
    if (warehouseId == null) errors['location'] = 'required';

    double? parseNum(String v, String key, {bool allowEmpty = false}) {
      if (v.trim().isEmpty) {
        if (!allowEmpty) errors[key] = 'required';
        return null;
      }
      final n = Formatters.parse(v);
      if (n == null) {
        errors[key] = 'invalid';
        return null;
      }
      if (n < 0) errors[key] = 'negative';
      return n;
    }

    final uw = parseNum(unitWeight, 'unitWeight', allowEmpty: true);
    if (uw != null && uw <= 0) errors['unitWeight'] = 'positive';
    parseNum(minStock, 'minStock', allowEmpty: true);
    if (showExpiry && expirationDate != null) {
      final alert = parseNum(expiryAlertValue, 'expiryAlert', allowEmpty: true);
      if (alert != null && alert < 1) errors['expiryAlert'] = 'positive';
    }
    if (allowCostPrice) {
      final cost = parseNum(costPrice, 'costPrice', allowEmpty: true);
      if (cost != null && cost < 0) errors['costPrice'] = 'negative';
      if (costCurrencyId == null && costPrice.trim().isNotEmpty) {
        errors['costCurrency'] = 'required';
      }
    }
    final sell = parseNum(sellingPrice, 'sellingPrice', allowEmpty: true);
    if (sell != null && sell < 0) errors['sellingPrice'] = 'negative';
    if (currencyId == null && sellingPrice.trim().isNotEmpty) {
      errors['sellingCurrency'] = 'required';
    }
    if (storeType == 'supplement' && expirationDate == null && !isEdit) {
      // Soft requirement — warn via optional field, not hard block.
    }

    fieldErrors = errors;
    if (!silent) notifyListeners();
  }

  Future<String?> save() async {
    if (saving) return 'errors.saveInProgress'.tr();
    submitted = true;
    validate();
    if (fieldErrors.isNotEmpty) {
      formError = 'errors.formFixFields'.tr();
      notifyListeners();
      return formError;
    }

    saving = true;
    formError = null;
    notifyListeners();

    final finalSku = sku.trim().toUpperCase();

    final now = DateTime.now();
    final model = ProductModel(
      id: existing?.id ?? 0,
      name: name.trim(),
      sku: finalSku,
      barcode: barcode.trim().isEmpty ? null : barcode.trim(),
      brand: brand.trim().isEmpty ? null : brand.trim(),
      description: description.trim().isEmpty ? null : description.trim(),
      expirationDate: expirationDate,
      expiryAlertValue: () {
        final n = Formatters.parse(expiryAlertValue)?.round() ?? 1;
        return n < 1 ? 1 : n;
      }(),
      expiryAlertUnit: normalizeExpiryAlertUnit(expiryAlertUnit),
      categoryId: categoryId,
      unitOfMeasure: normalizeProductUnit(unitOfMeasure),
      unitWeight: Formatters.parse(unitWeight),
      weightUnit: normalizeWeightUnit(weightUnit),
      initialStock: isEdit ? (existing?.initialStock ?? 0.0) : 0.0,
      currentStock: isEdit ? (existing?.currentStock ?? 0) : 0,
      minimumStockAlert: Formatters.parse(minStock) ?? 0,
      costPrice: allowCostPrice
          ? (Formatters.parse(costPrice) ?? 0)
          : (existing?.costPrice ?? 0),
      sellingPrice: Formatters.parse(sellingPrice) ?? 0,
      currencyId: currencyId ?? existing?.currencyId,
      costCurrencyId: allowCostPrice
          ? (costCurrencyId ?? existing?.costCurrencyId)
          : existing?.costCurrencyId,
      supplierId: supplierId,
      supplierName: selectedSupplier?.name,
      warehouseId: warehouseId,
      warehouseName: selectedWarehouse?.name,
      notes: notes.trim().isEmpty ? null : notes.trim(),
      imagePath: imagePath,
      trackStockBySheet: false,
      thickness: existing?.thickness,
      standardWidth: existing?.standardWidth,
      standardHeight: existing?.standardHeight,
      isActive: isActive,
      isArchived: existing?.isArchived ?? false,
      parentProductId: existing?.parentProductId,
      isRemnant: existing?.isRemnant ?? false,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final result = isEdit
        ? await _products.update(model)
        : await _products.create(model);
    saving = false;
    return result.when(
      success: (_) {
        dirty = false;
        notifyListeners();
        return null;
      },
      failure: (f) {
        formError = f.message;
        if (f is ValidationFailure) {
          fieldErrors = {...fieldErrors, ...f.fieldErrors};
        }
        notifyListeners();
        return f.message;
      },
    );
  }
}
