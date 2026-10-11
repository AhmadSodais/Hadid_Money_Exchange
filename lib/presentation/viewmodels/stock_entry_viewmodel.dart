// ignore_for_file: unused_field

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/service_locator.dart';
import '../../core/errors/result.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/glass_cut_helper.dart';
import '../../data/models/currency_model.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/stock_movement_model.dart';
import '../../data/models/warehouse_model.dart';
import '../../domain/repositories/customer_repository.dart';
import '../../domain/repositories/employee_repository.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../domain/repositories/lookup_repository.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../../domain/repositories/warehouse_repository.dart';
import '../dialogs/warehouse_dialog_shared.dart';

enum StockEntryMode { inbound, outbound }

/// Partner option for stock entry / carts (`supplier` or `customer` table).
class TradingPartnerOption {
  const TradingPartnerOption({
    required this.key,
    required this.id,
    required this.name,
    required this.source,
    this.createdAt,
  });

  /// Unique key across supplier + customer tables.
  final String key;
  final int id;
  final String name;

  /// `supplier` (purchases/inbound) or `customer` (sales/outbound).
  final String source;
  final DateTime? createdAt;
}

/// Inbound or outbound movement against an existing warehouse product.
class StockEntryViewModel extends ChangeNotifier {
  StockEntryViewModel({
    required this.mode,
    this.existingProduct,
    InventoryRepository? inventory,
    ProductRepository? products,
    SupplierRepository? suppliers,
    CustomerRepository? customers,
    LookupRepository? lookups,
    WarehouseRepository? warehouses,
    EmployeeRepository? employees,
  })  : _inventory = inventory ?? ServiceLocator.instance.inventory,
        _products = products ?? ServiceLocator.instance.products,
        _suppliers = suppliers ?? ServiceLocator.instance.suppliers,
        _customers = customers ?? ServiceLocator.instance.customers,
        _lookups = lookups ?? ServiceLocator.instance.lookups,
        _warehouses = warehouses ?? ServiceLocator.instance.warehouses,
        _employees = employees ?? ServiceLocator.instance.employees {
    thicknessController.addListener(_onFieldChanged);
    lengthController.addListener(_onFieldChanged);
    widthController.addListener(_onFieldChanged);
    quantityController.addListener(_onFieldChanged);
    priceController.addListener(_onFieldChanged);
    paidController.addListener(_onFieldChanged);
    quantityFocus.addListener(_onQuantityFocusChange);

    if (existingProduct != null) {
      selectedProduct = existingProduct;
      _applyProduct(existingProduct!);
    }
  }

  final StockEntryMode mode;
  final ProductModel? existingProduct;
  final InventoryRepository _inventory;
  final ProductRepository _products;
  final SupplierRepository _suppliers;
  final CustomerRepository _customers;
  final LookupRepository _lookups;
  final WarehouseRepository _warehouses;
  final EmployeeRepository _employees;

  bool get isInbound => mode == StockEntryMode.inbound;

  bool _disposed = false;
  bool loading = true;
  bool saving = false;
  /// Required-field errors are shown only after the user tries to save.
  bool submitted = false;
  /// Insufficient-stock error is shown after quantity editing completes.
  bool stockChecked = false;
  /// From Settings → Limit to stock (default true).
  bool limitToStock = true;
  String? formError;
  Map<String, String> fieldErrors = {};

  final quantityFocus = FocusNode();

  ProductModel? selectedProduct;
  List<ProductModel> products = const [];
  List<TradingPartnerOption> companies = const [];
  TradingPartnerOption? selectedCompany;
  List<CurrencyModel> currencies = const [];
  CurrencyModel? selectedCurrency;
  List<WarehouseModel> warehouses = const [];
  WarehouseModel? selectedWarehouse;
  List<EmployeeModel> employees = const [];
  EmployeeModel? selectedEmployee;

  final thicknessController = TextEditingController();
  final lengthController = TextEditingController();
  final widthController = TextEditingController();
  final quantityController = TextEditingController();
  final priceController = TextEditingController();
  final paidController = TextEditingController();
  final notesController = TextEditingController();
  final driverController = TextEditingController();
  final vehicleController = TextEditingController();
  final driverDescriptionController = TextEditingController();

  String? unitOfMeasure;
  /// Length/width input unit. Default meters. Thickness is always mm.
  String dimensionUnit = 'm';
  DateTime transactionDate = DateTime.now();

  String get thickness => thicknessController.text;
  String get lengthMm => lengthController.text;
  String get widthMm => widthController.text;
  String get quantity => quantityController.text;
  String get unitPrice => priceController.text;
  String get paidAmountText => paidController.text;
  String get notes => notesController.text;
  String get driver => driverController.text;
  String get vehicle => vehicleController.text;
  String get driverDescription => driverDescriptionController.text;

  double get lineTotal {
    final p = Formatters.parse(unitPrice) ?? 0;
    final q = quantityValue;
    if (p <= 0 || q <= 0) return 0;
    return p * q;
  }

  String get lineTotalDisplay {
    if (lineTotal <= 0) return '—';
    final money = formatMoney(lineTotal);
    final code = selectedCurrency?.code;
    if (code == null || code.isEmpty) return money;
    return '$money $code';
  }

  double get paidAmountValue {
    final p = Formatters.parse(paidAmountText);
    if (p == null || p < 0) return 0;
    return p;
  }

  double get outstandingAmount {
    final o = lineTotal - paidAmountValue;
    return o < 0 ? 0 : o;
  }

  String get outstandingDisplay {
    if (lineTotal <= 0) return '—';
    final money = formatMoney(outstandingAmount);
    final code = selectedCurrency?.code;
    if (code == null || code.isEmpty) return money;
    return '$money $code';
  }

  void selectCurrency(CurrencyModel? currency) {
    selectedCurrency = currency;
    markDirty();
  }

  void setDimensionUnit(String? unit) {
    final next = normalizeDimensionUnit(unit);
    if (next == dimensionUnit) return;
    final prev = dimensionUnit;
    final l = parseMm(lengthController.text);
    final w = parseMm(widthController.text);
    dimensionUnit = next;
    if (l != null) {
      final meters = dimensionToMeters(l, prev);
      lengthController.text =
          Formatters.number(metersToDimension(meters, dimensionUnit));
    }
    if (w != null) {
      final meters = dimensionToMeters(w, prev);
      widthController.text =
          Formatters.number(metersToDimension(meters, dimensionUnit));
    }
    markDirty();
  }

  /// Total area in m² = length × width × quantity.
  double get calculatedArea {
    final l = parseMm(lengthMm) ?? 0;
    final w = parseMm(widthMm) ?? 0;
    final q = quantityValue;
    return areaM2FromUi(
      length: l,
      width: w,
      unit: dimensionUnit,
      quantity: q > 0 ? q : 1,
    );
  }

  String get areaDisplay {
    final a = calculatedArea;
    if (a <= 0) return '—';
    return '${formatArea(a)} m²';
  }

  double get calculatedWeight {
    final p = selectedProduct;
    if (p == null) return 0;
    final q = Formatters.parse(quantity) ?? 0;
    final qty = q > 0 ? q : 1;
    final pieceW = _cutPieceUnitWeight(p);
    if (pieceW == null || pieceW <= 0) return 0;
    return pieceW * qty;
  }

  String get weightDisplay {
    final p = selectedProduct;
    if (p == null) return '—';
    final q = Formatters.parse(quantity) ?? 0;
    return formatProductWeight(
      _cutPieceUnitWeight(p),
      p.weightUnit,
      quantity: q > 0 ? q : 1,
    );
  }

  /// Area-scaled unit weight for the current cut size (outbound), else sheet weight.
  double? _cutPieceUnitWeight(ProductModel p) {
    if (isInbound) return p.unitWeight;
    final lengthRaw = Formatters.parse(lengthMm);
    final widthRaw = Formatters.parse(widthMm);
    if (lengthRaw == null || widthRaw == null) return p.unitWeight;
    return p.weightForPiece(
      length: dimensionToMeters(lengthRaw, dimensionUnit),
      width: dimensionToMeters(widthRaw, dimensionUnit),
    );
  }

  double get quantityValue => Formatters.parse(quantity) ?? 0;

  double? get afterStock {
    if (selectedProduct == null || quantityValue <= 0) return null;
    final current = selectedProduct!.currentStock;
    return isInbound ? current + quantityValue : current - quantityValue;
  }

  bool get insufficientStock =>
      limitToStock &&
      !isInbound &&
      selectedProduct != null &&
      quantityValue > selectedProduct!.currentStock;

  /// Live cut-to-size note for outbound when dimensions are smaller than parent.
  String? get remnantHint {
    if (isInbound) return null;
    final p = selectedProduct;
    if (p == null) return null;
    final lengthRaw = Formatters.parse(lengthMm);
    final widthRaw = Formatters.parse(widthMm);
    if (lengthRaw == null || widthRaw == null) return null;
    final cut = GlassCutHelper.plan(
      parentLength: p.standardHeight,
      parentWidth: p.standardWidth,
      cutLength: dimensionToMeters(lengthRaw, dimensionUnit),
      cutWidth: dimensionToMeters(widthRaw, dimensionUnit),
      quantity: quantityValue <= 0 ? 1 : quantityValue,
      trackStockBySheet: p.trackStockBySheet,
    );
    if (!cut.isPartialCut) return null;
    if (cut.hasRemnant) {
      return 'stockEntry.remnantHint'.tr(
        namedArgs: {
          'length': GlassCutHelper.formatDim(cut.remnantLengthM!),
          'width': GlassCutHelper.formatDim(cut.remnantWidthM!),
        },
      );
    }
    if (cut.waste) return 'stockEntry.remnantWasteHint'.tr();
    return null;
  }

  /// UI-facing field error. Required fields only after [submitted];
  /// insufficient stock after [stockChecked] or [submitted].
  String? visibleError(String key) {
    final err = fieldErrors[key];
    if (err == null) return null;
    if (key == 'quantity' && err == 'stock') {
      return (stockChecked || submitted) ? err : null;
    }
    return submitted ? err : null;
  }

  void _notify({bool silent = false}) {
    if (_disposed || silent) return;
    notifyListeners();
  }

  void _onFieldChanged() {
    if (submitted || stockChecked) {
      validate(silent: true);
      if (submitted &&
          fieldErrors.isEmpty &&
          !(stockChecked && insufficientStock)) {
        formError = null;
      }
    }
    _notify();
  }

  void _onQuantityFocusChange() {
    if (_disposed) return;
    if (!quantityFocus.hasFocus) {
      onQuantityEditingComplete();
    }
  }

  /// Called when the user finishes editing quantity (blur / submit).
  void onQuantityEditingComplete() {
    if (_disposed || isInbound) return;
    stockChecked = true;
    validate(silent: true);
    if (!insufficientStock &&
        formError == 'stockEntry.notEnoughStock' &&
        !submitted) {
      formError = null;
    }
    _notify();
  }

  void _applyProduct(ProductModel p) {
    thicknessController.text =
        p.thickness != null ? Formatters.number(p.thickness!) : '';
    lengthController.text = dimToDisplay(p.standardHeight, unit: dimensionUnit);
    widthController.text = dimToDisplay(p.standardWidth, unit: dimensionUnit);
    unitOfMeasure = normalizeProductUnit(p.unitOfMeasure);
    if (p.warehouseId != null) {
      selectedWarehouse =
          warehouses.where((w) => w.id == p.warehouseId).firstOrNull ??
              selectedWarehouse;
    } else {
      final split = splitLocationNotes(p.notes);
      if (split.$1 != null) {
        selectedWarehouse = warehouses
                .where(
                  (w) =>
                      w.name.trim().toLowerCase() ==
                      split.$1!.trim().toLowerCase(),
                )
                .firstOrNull ??
            selectedWarehouse;
      }
    }
    selectedWarehouse ??= warehouses.firstOrNull;
    final seedPrice = isInbound ? p.costPrice : p.sellingPrice;
    if (seedPrice > 0) {
      priceController.text = Formatters.number(seedPrice);
    } else if (priceController.text.isEmpty) {
      priceController.clear();
    }
    if (p.currencyId != null && currencies.isNotEmpty) {
      selectedCurrency =
          currencies.where((c) => c.id == p.currencyId).firstOrNull ??
              selectedCurrency;
    } else if (p.currencyCode != null && currencies.isNotEmpty) {
      selectedCurrency =
          currencies.where((c) => c.code == p.currencyCode).firstOrNull ??
              selectedCurrency;
    }
  }

  Future<void> load() async {
    if (_disposed) return;
    loading = true;
    _notify();

    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    limitToStock = prefs.getBool(AppConstants.prefLimitToStock) ?? true;

    final stock = await _inventory.listStock(
      const InventoryStockQuery(pageSize: 500),
    );
    if (_disposed) return;
    stock.when(
      success: (v) {
        products = v.items;
        if (selectedProduct != null) {
          selectedProduct = products
              .where((p) => p.id == selectedProduct!.id)
              .firstOrNull;
          if (selectedProduct != null) {
            _applyProduct(selectedProduct!);
          }
        }
      },
      failure: (_) {},
    );

    // Inbound → companies/suppliers; outbound → customers.
    final merged = <TradingPartnerOption>[];
    final seenNames = <String>{};

    if (isInbound) {
      final sups = await _suppliers.query(pageSize: 500);
      if (_disposed) return;
      if (sups is Success) {
        for (final s in (sups as Success).value.items) {
          final key = s.name.trim().toLowerCase();
          if (key.isEmpty || seenNames.contains(key)) continue;
          seenNames.add(key);
          merged.add(
            TradingPartnerOption(
              key: 's-${s.id}',
              id: s.id,
              name: s.name,
              source: 'supplier',
              createdAt: s.createdAt,
            ),
          );
        }
      }
    } else {
      final buys = await _customers.query(pageSize: 500);
      if (_disposed) return;
      if (buys is Success) {
        for (final c in (buys as Success).value.items) {
          if (c.name.toLowerCase() == 'walk-in customer') continue;
          final key = c.name.trim().toLowerCase();
          if (key.isEmpty || seenNames.contains(key)) continue;
          seenNames.add(key);
          merged.add(
            TradingPartnerOption(
              key: 'c-${c.id}',
              id: c.id,
              name: c.name,
              source: 'customer',
              createdAt: c.createdAt,
            ),
          );
        }
      }
    }

    merged.sort((a, b) {
      final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final byDate = bAt.compareTo(aAt);
      if (byDate != 0) return byDate;
      return b.id.compareTo(a.id);
    });
    companies = merged;
    if (selectedCompany != null) {
      selectedCompany =
          companies.where((c) => c.key == selectedCompany!.key).firstOrNull;
    }

    final curs = await _lookups.getCurrencies();
    if (_disposed) return;
    curs.when(
      success: (list) {
        currencies = list.where((c) => c.isActive).toList();
        if (currencies.isEmpty) currencies = list;
        selectedCurrency ??= currencies.where((c) => c.isBase).firstOrNull ??
            currencies.firstOrNull;
      },
      failure: (_) {},
    );

    final whs = await _warehouses.list();
    if (_disposed) return;
    whs.when(
      success: (list) {
        warehouses = list;
        selectedWarehouse ??= list.firstOrNull;
      },
      failure: (_) {},
    );

    final emps = await _employees.list();
    if (_disposed) return;
    emps.when(
      success: (list) {
        employees = list;
        if (selectedEmployee != null) {
          selectedEmployee =
              list.where((e) => e.id == selectedEmployee!.id).firstOrNull;
        }
      },
      failure: (_) {},
    );

    if (selectedProduct != null) {
      _applyProduct(selectedProduct!);
    }

    loading = false;
    _notify();
  }

  void selectProduct(ProductModel? p) {
    selectedProduct = p;
    if (p != null) {
      _applyProduct(p);
    } else {
      thicknessController.clear();
      lengthController.clear();
      widthController.clear();
      unitOfMeasure = 'sheet';
      selectedWarehouse = warehouses.firstOrNull;
    }
    markDirty();
  }

  void selectWarehouse(WarehouseModel? warehouse) {
    selectedWarehouse = warehouse;
    markDirty();
  }

  void selectEmployee(EmployeeModel? employee) {
    selectedEmployee = employee;
    markDirty();
  }

  void selectCompany(TradingPartnerOption? company) {
    selectedCompany = company;
    markDirty();
  }

  void setTransactionDate(DateTime date) {
    transactionDate = date;
    markDirty();
  }

  void markDirty() {
    if (submitted || stockChecked) {
      validate(silent: true);
      if (submitted && fieldErrors.isEmpty) formError = null;
    }
    _notify();
  }

  void validate({bool silent = false}) {
    final errors = <String, String>{};

    if (selectedProduct == null) {
      errors['product'] = 'required';
    }

    double? parsePos(String v, String key, {bool allowEmpty = false}) {
      if (v.trim().isEmpty) {
        if (!allowEmpty) errors[key] = 'required';
        return null;
      }
      final n = Formatters.parse(v);
      if (n == null) {
        errors[key] = 'invalid';
        return null;
      }
      if (n <= 0) {
        errors[key] = 'positive';
        return null;
      }
      return n;
    }

    parsePos(thickness, 'thickness', allowEmpty: true);
    parsePos(lengthMm, 'length', allowEmpty: true);
    parsePos(widthMm, 'width', allowEmpty: true);
    parsePos(quantity, 'quantity');
    parsePos(unitPrice, 'price', allowEmpty: true);
    final paid = Formatters.parse(paidAmountText);
    if (paidAmountText.trim().isNotEmpty && (paid == null || paid < 0)) {
      errors['paid'] = 'invalid';
    }
    if (paid != null && lineTotal > 0 && paid > lineTotal + 0.0001) {
      errors['paid'] = 'over';
    }

    if (selectedCompany == null) {
      errors['partner'] = 'required';
    }
    // Currency is required only when a unit price is entered.
    if (unitPrice.trim().isNotEmpty && selectedCurrency == null) {
      errors['currency'] = 'required';
    }
    if (selectedWarehouse == null) {
      errors['location'] = 'required';
    }
    if (insufficientStock) {
      errors['quantity'] = 'stock';
    }

    fieldErrors = errors;
    if (!silent) _notify();
  }

  Future<String?> save() async {
    submitted = true;
    validate();
    if (fieldErrors.isNotEmpty) {
      formError = insufficientStock
          ? 'stockEntry.notEnoughStock'
          : 'Please fix the highlighted fields.';
      _notify();
      return formError;
    }

    saving = true;
    formError = null;
    _notify();

    final lengthRaw = parseMm(lengthMm);
    final widthRaw = parseMm(widthMm);
    final lengthM = lengthRaw == null
        ? null
        : dimensionToMeters(lengthRaw, dimensionUnit);
    final widthM =
        widthRaw == null ? null : dimensionToMeters(widthRaw, dimensionUnit);
    final qty = Formatters.parse(quantity)!;
    final price = Formatters.parse(unitPrice);
    final paid = paidAmountValue;
    final product = selectedProduct!;
    final company = selectedCompany!;

    final logistics = buildMovementLogistics(
      inbound: isInbound,
      person: driver,
      vehicle: vehicle,
      details: driverDescription,
    );
    final combinedNotes = composeMovementNotes(
      remarks: notes,
      logistics: logistics,
    );

    try {
      final result = await _inventory.recordMovement(
        productId: product.id,
        type: isInbound ? StockMovementType.purchase : StockMovementType.sale,
        quantity: qty,
        notes: combinedNotes,
        referenceType: company.source,
        referenceId: company.id,
        partnerName: company.name,
        lengthM: lengthM,
        widthM: widthM,
        brokenQty: 0,
        unitPrice: price,
        paidAmount: price == null ? 0 : paid,
        currencyId: price == null ? null : selectedCurrency?.id,
        warehouseId: selectedWarehouse?.id,
        employeeId: selectedEmployee?.id,
        createdAt: transactionDate,
      );

      saving = false;
      return result.when(
        success: (_) {
          _notify();
          return null;
        },
        failure: (f) {
          formError = f.message;
          _notify();
          return f.message;
        },
      );
    } catch (e) {
      saving = false;
      formError = e.toString();
      _notify();
      return formError;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    quantityFocus.removeListener(_onQuantityFocusChange);
    thicknessController.removeListener(_onFieldChanged);
    lengthController.removeListener(_onFieldChanged);
    widthController.removeListener(_onFieldChanged);
    quantityController.removeListener(_onFieldChanged);
    priceController.removeListener(_onFieldChanged);
    paidController.removeListener(_onFieldChanged);
    quantityFocus.dispose();
    thicknessController.dispose();
    lengthController.dispose();
    widthController.dispose();
    quantityController.dispose();
    priceController.dispose();
    paidController.dispose();
    notesController.dispose();
    driverController.dispose();
    vehicleController.dispose();
    driverDescriptionController.dispose();
    super.dispose();
  }
}
