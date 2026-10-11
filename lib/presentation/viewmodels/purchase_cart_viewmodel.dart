import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

import '../../core/di/service_locator.dart';
import '../../core/errors/result.dart';
import '../../data/models/currency_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/purchase_model.dart';
import '../../data/models/warehouse_model.dart';
import '../../domain/repositories/lookup_repository.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../../domain/repositories/warehouse_repository.dart';
import '../dialogs/add_purchase_products_picker_dialog.dart';
import '../dialogs/warehouse_dialog_shared.dart';
import 'stock_entry_viewmodel.dart';

/// One draft line in the New Purchase dialog.
class PurchaseCartLine {
  PurchaseCartLine({
    required this.id,
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.sellingPrice,
    this.lengthM,
    this.widthM,
    this.dimensionUnit = 'm',
    this.paidAmount = 0,
    this.currencyId,
    this.sellingCurrencyId,
    this.warehouseId,
    this.unitOfMeasure,
    this.thickness,
  });

  final String id;
  ProductModel product;
  double quantity;
  double unitPrice;
  /// Catalog selling price to write back to the product on save.
  double? sellingPrice;
  double? lengthM;
  double? widthM;
  String dimensionUnit;
  double paidAmount;
  /// Purchase / cost price currency for this line.
  int? currencyId;
  /// Selling price currency for this line (product catalog).
  int? sellingCurrencyId;
  int? warehouseId;
  String? unitOfMeasure;
  double? thickness;

  double get lineTotal => unitPrice * quantity.abs();
  double get outstanding {
    final o = lineTotal - paidAmount;
    return o > 0 ? o : 0;
  }

  double get effectiveSellingPrice =>
      sellingPrice ?? product.sellingPrice;
}

/// Multi-line purchase cart for New / Edit Purchase dialog.
class PurchaseCartViewModel extends ChangeNotifier {
  PurchaseCartViewModel({
    this.editingPurchaseId,
    PurchaseRepository? purchases,
    ProductRepository? products,
    SupplierRepository? suppliers,
    LookupRepository? lookups,
    WarehouseRepository? warehouses,
  })  : _purchases = purchases ?? ServiceLocator.instance.purchases,
        _products = products ?? ServiceLocator.instance.products,
        _suppliers = suppliers ?? ServiceLocator.instance.suppliers,
        _lookups = lookups ?? ServiceLocator.instance.lookups,
        _warehouses = warehouses ?? ServiceLocator.instance.warehouses;

  final int? editingPurchaseId;
  final PurchaseRepository _purchases;
  final ProductRepository _products;
  final SupplierRepository _suppliers;
  final LookupRepository _lookups;
  final WarehouseRepository _warehouses;

  bool loading = true;
  bool saving = false;
  String? error;

  DateTime transactionDate = DateTime.now();
  String invoiceNumber = '';
  TradingPartnerOption? selectedCompany;
  CurrencyModel? selectedCurrency;
  WarehouseModel? selectedWarehouse;
  String notes = '';
  String driver = '';
  String vehicle = '';
  String driverDescription = '';
  double discount = 0;
  double amountPaid = 0;

  List<TradingPartnerOption> companies = const [];
  List<ProductModel> products = const [];
  List<CurrencyModel> currencies = const [];
  List<WarehouseModel> warehouses = const [];
  final List<PurchaseCartLine> lines = [];

  bool get isEditing => editingPurchaseId != null;

  double get subtotal =>
      lines.fold<double>(0, (s, l) => s + l.lineTotal);

  double get total {
    final t = subtotal - (discount < 0 ? 0 : discount);
    return t < 0 ? 0 : t;
  }

  double get remaining {
    final paid = amountPaid < 0 ? 0 : amountPaid;
    final r = total - paid;
    return r < 0 ? 0 : r;
  }

  double get effectivePaid {
    final p = amountPaid < 0 ? 0.0 : amountPaid;
    return p;
  }

  /// Distribute header [amountPaid] across lines (mirrors outbound cart).
  double _paidForLine(int index) {
    final sub = subtotal;
    if (sub <= 0) return 0;
    final t = total;
    var remainingCash = effectivePaid;
    for (var i = 0; i < lines.length; i++) {
      final due = t <= 0 ? 0.0 : lines[i].lineTotal * (t / sub);
      final paid = remainingCash >= due ? due : remainingCash.clamp(0.0, due);
      remainingCash -= paid;
      if (i == index) return paid.toDouble();
    }
    return 0;
  }

  void _notify() {
    if (!hasListeners) return;
    notifyListeners();
  }

  Future<void> load({PurchaseModel? existing}) async {
    loading = true;
    error = null;
    _notify();

    final curs = await _lookups.getCurrencies();
    curs.when(
      success: (list) {
        currencies = list.where((c) => c.isActive).toList();
        if (currencies.isEmpty) currencies = list;
        // New purchase dialog: default payment currency to USD.
        // Edit mode keeps the invoice currency via [_hydrate].
        if (editingPurchaseId == null && existing == null) {
          selectedCurrency ??=
              currencies
                  .where((c) => c.code.toUpperCase() == 'USD')
                  .firstOrNull ??
              currencies.where((c) => c.isBase).firstOrNull ??
              currencies.firstOrNull;
        } else {
          selectedCurrency ??=
              currencies.where((c) => c.isBase).firstOrNull ??
              currencies.firstOrNull;
        }
      },
      failure: (_) {},
    );

    final wh = await _warehouses.list();
    wh.when(
      success: (list) {
        warehouses = list.where((w) => w.isActive).toList();
        if (warehouses.isEmpty) warehouses = list;
        selectedWarehouse ??= warehouses.firstOrNull;
      },
      failure: (_) {},
    );

    await _loadCompanies();
    await _loadProducts();

    if (existing != null) {
      _hydrate(existing);
    } else if (editingPurchaseId != null) {
      final res = await _purchases.getById(editingPurchaseId!);
      res.when(
        success: _hydrate,
        failure: (f) => error = f.message,
      );
    } else {
      // Assigned on save as the next integer (1, 2, 3…).
      invoiceNumber = '';
    }

    loading = false;
    _notify();
  }

  void _hydrate(PurchaseModel p) {
    invoiceNumber = p.invoiceNumber;
    transactionDate = p.createdAt;
    notes = movementRemarksOnly(p.notes);
    final logistics = parseMovementLogistics(p.notes);
    driver = logistics.person;
    vehicle = logistics.vehicle;
    driverDescription = logistics.details;
    discount = p.discount < 0 ? 0 : p.discount;
    amountPaid = p.amountPaid < 0 ? 0 : p.amountPaid;
    if (p.currencyId != null || (p.currencyCode ?? '').isNotEmpty) {
      selectedCurrency = currencies
              .where(
                (c) => c.id == p.currencyId || c.code == p.currencyCode,
              )
              .firstOrNull ??
          selectedCurrency;
    }
    if (p.partnerId != null && (p.partnerType ?? '').isNotEmpty) {
      selectedCompany = companies
          .where(
            (c) => c.id == p.partnerId && c.source == p.partnerType,
          )
          .firstOrNull;
    }
    lines.clear();
    for (final item in p.items) {
      final product = products.where((x) => x.id == item.productId).firstOrNull;
      lines.add(
        PurchaseCartLine(
          id: 'edit-${item.id}',
          product: product ??
              ProductModel(
                id: item.productId,
                name: item.productName,
                sku: '',
                sellingPrice: item.unitPrice,
                costPrice: item.unitPrice,
                imagePath: item.productImagePath,
                warehouseId: item.warehouseId,
                currencyId: item.currencyId,
                standardHeight: item.lengthM,
                standardWidth: item.widthM,
                createdAt: p.createdAt,
                updatedAt: p.updatedAt,
              ),
          quantity: item.quantity.abs(),
          unitPrice: item.unitPrice,
          sellingPrice: item.sellingPrice ?? product?.sellingPrice,
          lengthM: item.lengthM,
          widthM: item.widthM,
          paidAmount: item.paidAmount,
          currencyId: item.currencyId ??
              product?.costCurrencyId ??
              p.currencyId,
          sellingCurrencyId:
              item.sellingCurrencyId ?? product?.currencyId,
          warehouseId: item.warehouseId,
        ),
      );
    }
  }

  Future<void> _loadCompanies() async {
    // Purchases are placed with trading companies / suppliers only.
    final merged = <TradingPartnerOption>[];
    final seen = <String>{};
    final sups = await _suppliers.query(pageSize: 500);
    if (sups is Success) {
      for (final s in (sups as Success).value.items) {
        final key = s.name.trim().toLowerCase();
        if (key.isEmpty || seen.contains(key)) continue;
        seen.add(key);
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
    merged.sort((a, b) {
      final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
    companies = merged;
  }

  Future<void> _loadProducts() async {
    final list = await _products.query(
      const ProductQuery(page: 1, pageSize: 500, includeArchived: false),
    );
    list.when(
      success: (page) => products = page.items,
      failure: (_) {},
    );
  }

  void setTransactionDate(DateTime d) {
    transactionDate = d;
    _notify();
  }

  void setInvoiceNumber(String v) {
    invoiceNumber = v;
    _notify();
  }

  void selectCompany(TradingPartnerOption? c) {
    selectedCompany = c;
    _notify();
  }

  void selectCurrency(CurrencyModel? c) {
    selectedCurrency = c;
    if (c != null) {
      for (final line in lines) {
        line.currencyId = c.id;
        line.sellingCurrencyId = c.id;
      }
    }
    _notify();
  }

  void selectWarehouse(WarehouseModel? w) {
    selectedWarehouse = w;
    _notify();
  }

  void setNotes(String v) {
    notes = v;
    _notify();
  }

  void setDriver(String v) {
    driver = v;
    _notify();
  }

  void setVehicle(String v) {
    vehicle = v;
    _notify();
  }

  void setDriverDescription(String v) {
    driverDescription = v;
    _notify();
  }

  void setDiscount(double v) {
    discount = v < 0 ? 0 : v;
    _notify();
  }

  void setAmountPaid(double v) {
    amountPaid = v < 0 ? 0 : v;
    _notify();
  }

  void addProductsFromPicker(List<AddPurchaseProductPickResult> picks) {
    for (final pick in picks) {
      if (pick.quantity <= 0) continue;
      final match = lines.where((l) {
        if (l.product.id != pick.product.id) return false;
        if ((l.unitPrice - pick.unitPrice).abs() >= 0.0001) return false;
        return l.currencyId == pick.currencyId &&
            l.sellingCurrencyId == pick.sellingCurrencyId;
      }).firstOrNull;
      if (match != null) {
        match.quantity += pick.quantity;
        match.sellingPrice = pick.sellingPrice;
        match.currencyId = pick.currencyId;
        match.sellingCurrencyId = pick.sellingCurrencyId;
        match.product = match.product.copyWith(
          costPrice: pick.unitPrice,
          sellingPrice: pick.sellingPrice,
          costCurrencyId: pick.currencyId,
          currencyId: pick.sellingCurrencyId,
        );
      } else {
        lines.add(
          PurchaseCartLine(
            id: 'line-${DateTime.now().microsecondsSinceEpoch}-${pick.product.id}',
            product: pick.product.copyWith(
              costPrice: pick.unitPrice,
              sellingPrice: pick.sellingPrice,
              costCurrencyId: pick.currencyId,
              currencyId: pick.sellingCurrencyId,
            ),
            quantity: pick.quantity,
            unitPrice: pick.unitPrice,
            sellingPrice: pick.sellingPrice,
            currencyId: pick.currencyId,
            sellingCurrencyId: pick.sellingCurrencyId,
            warehouseId: selectedWarehouse?.id,
          ),
        );
      }
    }
    error = null;
    _notify();
  }

  void addOrUpdateLine(PurchaseCartLine line) {
    final i = lines.indexWhere((l) => l.id == line.id);
    if (i >= 0) {
      lines[i] = line;
    } else {
      lines.add(line);
    }
    error = null;
    _notify();
  }

  void removeLine(String id) {
    lines.removeWhere((l) => l.id == id);
    _notify();
  }

  String? validateHeader() {
    if (isEditing && invoiceNumber.trim().isEmpty) {
      return 'purchases.invoiceRequired'.tr();
    }
    if (selectedCompany == null) {
      return 'purchases.supplierRequired'.tr();
    }
    if (selectedCurrency == null) {
      return 'purchases.currencyRequired'.tr();
    }
    if (lines.isEmpty) {
      return 'purchases.linesRequired'.tr();
    }
    final missingCurrency = lines.any(
      (l) => l.currencyId == null || l.sellingCurrencyId == null,
    );
    if (missingCurrency) {
      return 'purchases.lineCurrencyRequired'.tr();
    }
    return null;
  }

  Future<String?> save() async {
    final headerErr = validateHeader();
    if (headerErr != null) return headerErr;
    if (saving) return null;

    saving = true;
    error = null;
    _notify();

    final logistics = buildMovementLogistics(
      inbound: true,
      person: driver,
      vehicle: vehicle,
      details: driverDescription,
    );
    final composedNotes = composeMovementNotes(
      remarks: notes,
      logistics: logistics,
    );

    final inputs = [
      for (var i = 0; i < lines.length; i++)
        PurchaseLineInput(
          productId: lines[i].product.id,
          productName: lines[i].product.name,
          quantity: lines[i].quantity.abs(),
          unitPrice: lines[i].unitPrice,
          lineTotal: lines[i].lineTotal,
          paidAmount: _paidForLine(i),
          sellingPrice: lines[i].effectiveSellingPrice,
          sellingCurrencyId: lines[i].sellingCurrencyId,
          lengthM: lines[i].lengthM,
          widthM: lines[i].widthM,
          currencyId: lines[i].currencyId ?? selectedCurrency?.id,
          warehouseId: lines[i].warehouseId ?? selectedWarehouse?.id,
        ),
    ];

    try {
      final result = editingPurchaseId != null
          ? await _purchases.replacePurchase(
              purchaseId: editingPurchaseId!,
              lines: inputs,
              invoiceNumber: invoiceNumber.trim(),
              partnerType: selectedCompany!.source,
              partnerId: selectedCompany!.id,
              partnerName: selectedCompany!.name,
              currencyId: selectedCurrency?.id,
              currencyCode: selectedCurrency?.code,
              discount: discount,
              amountPaid: amountPaid,
              notes: composedNotes,
              createdAt: transactionDate,
            )
          : await _purchases.createPurchase(
              lines: inputs,
              invoiceNumber: invoiceNumber.trim(),
              partnerType: selectedCompany!.source,
              partnerId: selectedCompany!.id,
              partnerName: selectedCompany!.name,
              currencyId: selectedCurrency?.id,
              currencyCode: selectedCurrency?.code,
              discount: discount,
              amountPaid: amountPaid,
              notes: composedNotes,
              createdAt: transactionDate,
            );

      saving = false;
      return result.when(
        success: (_) {
          _notify();
          return null;
        },
        failure: (f) {
          error = f.message;
          _notify();
          return error;
        },
      );
    } catch (e) {
      saving = false;
      error = e.toString();
      _notify();
      return error;
    }
  }
}
