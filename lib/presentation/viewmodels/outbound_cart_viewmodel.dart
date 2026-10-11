import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/service_locator.dart';
import '../../core/errors/result.dart';
import '../../data/models/category_model.dart';
import '../../data/models/currency_model.dart';
import '../../data/models/order_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/stock_movement_model.dart';
import '../../domain/repositories/customer_repository.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../domain/repositories/lookup_repository.dart';
import '../../domain/repositories/order_repository.dart';
import '../../domain/repositories/product_repository.dart';
import '../dialogs/warehouse_dialog_shared.dart';
import 'stock_entry_viewmodel.dart';

/// One line in the outbound Create Order cart.
class OutboundCartLine {
  OutboundCartLine({
    required this.id,
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.lengthM,
    this.widthM,
    this.dimensionUnit = 'm',
    this.currencyId,
    this.currencyCode,
  });

  final String id;
  final ProductModel product;
  double quantity;
  double unitPrice;
  double? lengthM;
  double? widthM;
  /// Display/input unit for length & width (`m`, `mm`, `cm`).
  String dimensionUnit;
  int? currencyId;
  String? currencyCode;

  double get lineTotal => unitPrice * quantity.abs();

  String get currencyLabel {
    final code = (currencyCode ?? '').trim();
    return code.isEmpty ? AppConstants.defaultCurrencyCode : code;
  }
}

/// Outbound-only POS cart: catalog + cash checkout.
class OutboundCartViewModel extends ChangeNotifier {
  OutboundCartViewModel({
    this.editingOrderId,
    InventoryRepository? inventory,
    LookupRepository? lookups,
    CustomerRepository? customers,
    OrderRepository? orders,
    ProductRepository? productsRepo,
  })  : _inventory = inventory ?? ServiceLocator.instance.inventory,
        _lookups = lookups ?? ServiceLocator.instance.lookups,
        _customers = customers ?? ServiceLocator.instance.customers,
        _orders = orders ?? ServiceLocator.instance.orders,
        _productsRepo = productsRepo ?? ServiceLocator.instance.products;

  /// When set, [save] updates this invoice instead of creating a new one.
  final int? editingOrderId;

  final InventoryRepository _inventory;
  final LookupRepository _lookups;
  final CustomerRepository _customers;
  final OrderRepository _orders;
  final ProductRepository _productsRepo;

  bool get isEditing => editingOrderId != null;

  /// Invoice number while editing (display only).
  String? editingInvoiceNumber;

  /// Stock credit while editing: qty already sold on this invoice (per product).
  final Map<int, double> _editingStockCredit = {};

  bool _disposed = false;
  bool loading = true;
  bool saving = false;
  String? error;

  /// From Settings → Limit to stock (default true).
  bool limitToStock = true;

  String search = '';
  int? categoryId;
  /// Catalog filter for cut/remnant products (like an All sub-section).
  bool remnantsOnly = false;
  List<ProductModel> products = const [];
  List<CategoryModel> categories = const [];
  List<TradingPartnerOption> companies = const [];
  TradingPartnerOption? selectedCompany;
  List<CurrencyModel> currencies = const [];
  CurrencyModel? orderCurrency;

  final List<OutboundCartLine> lines = [];
  /// Raw amount typed in payment details (ignored unless [applyCustomPayment]).
  double amountReceived = 0;
  /// Order-level discount (subtracted from subtotal).
  double discount = 0;
  /// When false (default), the order is treated as fully paid.
  bool applyCustomPayment = false;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  double get subtotal =>
      lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

  double get total {
    final t = subtotal - discount;
    return t < 0 ? 0 : t;
  }

  /// Cash applied to the order (full total unless custom payment is set).
  double get effectivePaid {
    if (!applyCustomPayment) return total;
    return amountReceived < 0 ? 0 : amountReceived;
  }

  double get change {
    final c = effectivePaid - total;
    return c > 0 ? c : 0;
  }

  double get remaining {
    final r = total - effectivePaid;
    return r > 0 ? r : 0;
  }

  Future<void> load() async {
    if (_disposed) return;
    loading = true;
    error = null;
    _notify();

    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    limitToStock = prefs.getBool(AppConstants.prefLimitToStock) ?? true;

    final cats = await _lookups.getCategories();
    if (_disposed) return;
    cats.when(success: (v) => categories = v, failure: (_) {});

    final curs = await _lookups.getCurrencies();
    if (_disposed) return;
    curs.when(
      success: (list) {
        currencies = list.where((c) => c.isActive).toList();
        if (currencies.isEmpty) currencies = list;
        orderCurrency ??=
            currencies.where((c) => c.isBase).firstOrNull ??
                currencies.firstOrNull;
      },
      failure: (_) {},
    );

    await _loadCompanies();
    if (_disposed) return;

    if (editingOrderId != null) {
      await _hydrateFromOrder(editingOrderId!);
      if (_disposed) return;
    }

    await _loadProducts();
    if (_disposed) return;

    loading = false;
    _notify();
  }

  /// Loads invoice lines into the cart. Stock availability includes quantities
  /// already sold on this invoice so the user can keep or raise those amounts.
  Future<void> _hydrateFromOrder(int orderId) async {
    final result = await _orders.getById(orderId);
    if (_disposed) return;
    await result.when(
      success: (order) async {
        editingInvoiceNumber = order.invoiceNumber;
        discount = order.discount < 0 ? 0 : order.discount;
        amountReceived = order.amountPaid < 0 ? 0 : order.amountPaid;
        applyCustomPayment = true;

        if (order.currencyId != null ||
            (order.currencyCode ?? '').trim().isNotEmpty) {
          orderCurrency = currencies
                  .where(
                    (c) =>
                        c.id == order.currencyId ||
                        c.code == order.currencyCode,
                  )
                  .firstOrNull ??
              orderCurrency;
        }

        if (order.partnerId != null &&
            (order.partnerType ?? '').isNotEmpty) {
          selectedCompany = companies
              .where(
                (c) =>
                    c.id == order.partnerId &&
                    c.source == order.partnerType,
              )
              .firstOrNull;
          if (selectedCompany == null &&
              (order.partnerName ?? '').trim().isNotEmpty) {
            selectedCompany = TradingPartnerOption(
              key: '${order.partnerType}-${order.partnerId}',
              id: order.partnerId!,
              name: order.partnerName!,
              source: order.partnerType!,
            );
          }
        }

        // Sum reserved qty per product so multi-line same product is correct.
        _editingStockCredit.clear();
        for (final item in order.items) {
          _editingStockCredit[item.productId] =
              (_editingStockCredit[item.productId] ?? 0) + item.quantity.abs();
        }

        final productCache = <int, ProductModel>{};
        for (final item in order.items) {
          var product = productCache[item.productId];
          if (product == null) {
            final loaded = await _productsRepo.getById(item.productId);
            if (_disposed) return;
            product = loaded.when(
              success: (p) => p,
              failure: (_) => null,
            );
            if (product != null) {
              final reserved = _editingStockCredit[item.productId] ?? 0;
              product = product.copyWith(
                currentStock: product.currentStock + reserved,
              );
              productCache[item.productId] = product;
            }
          }
          if (product == null) {
            // Fallback stub so the line remains editable if product was archived.
            product = ProductModel(
              id: item.productId,
              name: item.productName,
              sku: '',
              currentStock: item.quantity.abs(),
              sellingPrice: item.unitPrice,
              imagePath: item.productImagePath,
              warehouseId: item.warehouseId,
              currencyId: item.currencyId ?? order.currencyId,
              currencyCode: order.currencyCode,
              standardHeight: item.lengthM,
              standardWidth: item.widthM,
              createdAt: order.createdAt,
              updatedAt: order.updatedAt,
            );
          }

          lines.add(
            OutboundCartLine(
              id: 'edit-${item.id}',
              product: product,
              quantity: item.quantity.abs(),
              unitPrice: item.unitPrice,
              lengthM: item.lengthM,
              widthM: item.widthM,
              dimensionUnit: 'm',
              currencyId: item.currencyId ?? order.currencyId,
              currencyCode: order.currencyCode ??
                  product.currencyCode ??
                  AppConstants.defaultCurrencyCode,
            ),
          );
        }
      },
      failure: (f) {
        error = f.message;
      },
    );
  }

  Future<void> _loadCompanies() async {
    // Orders / sales are placed by customers only (not trading companies).
    final merged = <TradingPartnerOption>[];
    final seenNames = <String>{};

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

    merged.sort((a, b) {
      final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final byDate = bAt.compareTo(aAt);
      if (byDate != 0) return byDate;
      return b.id.compareTo(a.id);
    });
    companies = merged;
  }

  Future<void> _loadProducts() async {
    final list = await _inventory.listStock(
      InventoryStockQuery(
        search: search.trim().isEmpty ? null : search.trim(),
        categoryId: categoryId,
        remnantsOnly: null,
        page: 1,
        pageSize: 400,
      ),
    );
    if (_disposed) return;
    list.when(
      success: (page) {
        products = [
          for (final p in page.items)
            () {
              final credit = _editingStockCredit[p.id] ?? 0;
              if (credit <= 0) return p;
              return p.copyWith(currentStock: p.currentStock + credit);
            }(),
        ];
      },
      failure: (f) => error = f.message,
    );
  }

  void setSearch(String value) {
    search = value;
    _loadProducts().then((_) => _notify());
  }

  void setCategory(int? id) {
    categoryId = id;
    remnantsOnly = false;
    _loadProducts().then((_) => _notify());
  }

  void setRemnantsOnly(bool value) {
    remnantsOnly = value;
    if (value) categoryId = null;
    _loadProducts().then((_) => _notify());
  }

  void selectCompany(TradingPartnerOption? company) {
    selectedCompany = company;
    _notify();
  }

  void selectOrderCurrency(CurrencyModel? currency) {
    orderCurrency = currency;
    if (currency != null) {
      for (final line in lines) {
        line.currencyId = currency.id;
        line.currencyCode = currency.code;
      }
    }
    _notify();
  }

  void setAmountReceived(double value) {
    amountReceived = value < 0 ? 0 : value;
    applyCustomPayment = true;
    _notify();
  }

  void setDiscount(double value) {
    discount = value < 0 ? 0 : value;
    _notify();
  }

  /// Clears custom amount — order is treated as fully paid again.
  void clearCustomPayment() {
    amountReceived = 0;
    applyCustomPayment = false;
    _notify();
  }

  /// Returns false when [limitToStock] blocks the add (no stock left).
  bool addProduct(ProductModel product) {
    final existingIndex =
        lines.indexWhere((l) => l.product.id == product.id);
    if (existingIndex >= 0) {
      final existing = lines[existingIndex];
      final next = existing.quantity + 1;
      final stockCap = existing.product.currentStock > product.currentStock
          ? existing.product.currentStock
          : product.currentStock;
      if (limitToStock && next > stockCap + 0.0001) {
        return false;
      }
      existing.quantity = next;
      // Bring the updated line to the top so the user sees the change.
      if (existingIndex != 0) {
        lines.removeAt(existingIndex);
        lines.insert(0, existing);
      }
      error = null;
      _focusLine(existing.id);
      return true;
    }

    if (limitToStock && product.currentStock < 1) {
      return false;
    }

    final currency = orderCurrency;
    final line = OutboundCartLine(
      id: '${product.id}-${DateTime.now().microsecondsSinceEpoch}',
      product: product,
      quantity: 1,
      unitPrice: product.sellingPrice,
      lengthM: null,
      widthM: null,
      dimensionUnit: 'm',
      currencyId: currency?.id ?? product.currencyId,
      currencyCode: currency?.code ??
          product.currencyCode ??
          AppConstants.defaultCurrencyCode,
    );
    lines.insert(0, line);
    error = null;
    _focusLine(line.id);
    return true;
  }

  /// Line that should be scrolled into view / highlighted in the cart.
  String? focusedLineId;
  int focusGeneration = 0;

  void focusLine(String lineId) => _focusLine(lineId);

  void _focusLine(String lineId) {
    focusedLineId = lineId;
    focusGeneration++;
    _notify();
  }

  void clearLineFocus() {
    if (focusedLineId == null) return;
    focusedLineId = null;
    _notify();
  }

  void setLineQuantity(String lineId, double quantity) {
    final line = lines.where((l) => l.id == lineId).firstOrNull;
    if (line == null) return;
    if (quantity <= 0) {
      lines.removeWhere((l) => l.id == lineId);
      _notify();
      return;
    }
    if (limitToStock && quantity > line.product.currentStock + 0.0001) {
      error = 'stockEntry.notEnoughStock'.tr();
      _notify();
      return;
    }
    line.quantity = quantity;
    error = null;
    _notify();
  }

  void setLineUnitPrice(String lineId, double unitPrice) {
    final line = lines.where((l) => l.id == lineId).firstOrNull;
    if (line == null) return;
    if (unitPrice < 0) return;
    line.unitPrice = unitPrice;
    error = null;
    _notify();
  }

  void updateLineDimensions({
    required String lineId,
    double? lengthM,
    double? widthM,
    double? unitPrice,
    String? dimensionUnit,
  }) {
    final line = lines.where((l) => l.id == lineId).firstOrNull;
    if (line == null) return;
    if (lengthM != null) line.lengthM = lengthM;
    if (widthM != null) line.widthM = widthM;
    if (unitPrice != null && unitPrice >= 0) line.unitPrice = unitPrice;
    if (dimensionUnit != null) {
      line.dimensionUnit = normalizeDimensionUnit(dimensionUnit);
    }
    _notify();
  }

  void removeLine(String lineId) {
    lines.removeWhere((l) => l.id == lineId);
    _notify();
  }

  void clearCart() {
    lines.clear();
    amountReceived = 0;
    discount = 0;
    applyCustomPayment = false;
    focusedLineId = null;
    error = null;
    _notify();
  }

  /// Builds invoice movements from the last saved order, or from the cart.
  List<StockMovementModel> buildInvoiceMovements({
    required DateTime createdAt,
    OrderModel? order,
  }) {
    final source = order ?? lastSavedOrder;
    if (source != null && source.items.isNotEmpty) {
      return [
        for (var i = 0; i < source.items.length; i++)
          () {
            final item = source.items[i];
            return StockMovementModel(
              id: item.movementId ?? -(i + 1),
              productId: item.productId,
              productName: item.productName,
              productImagePath: item.productImagePath,
              movementType: StockMovementType.sale,
              quantity: -item.quantity.abs(),
              balanceAfter: 0,
              referenceType: source.partnerType,
              referenceId: source.partnerId,
              partnerName: source.partnerName,
              lengthM: item.lengthM,
              widthM: item.widthM,
              unitPrice: item.unitPrice,
              paidAmount: item.paidAmount,
              currencyId: item.currencyId ?? source.currencyId,
              currencyCode: source.currencyCode,
              warehouseId: item.warehouseId,
              createdAt: source.createdAt,
            );
          }(),
      ];
    }
    final partner = selectedCompany?.name ?? 'sales.walkInCustomer'.tr();
    return [
      for (var i = 0; i < lines.length; i++)
        () {
          final line = lines[i];
          final paidShare = _paidForLine(i);
          return StockMovementModel(
            id: -(i + 1),
            productId: line.product.id,
            productName: line.product.name,
            productImagePath: line.product.imagePath,
            productThickness: line.product.thickness,
            movementType: StockMovementType.sale,
            quantity: -line.quantity.abs(),
            balanceAfter: 0,
            referenceType: selectedCompany?.source,
            referenceId: selectedCompany?.id,
            partnerName: partner,
            lengthM: line.lengthM,
            widthM: line.widthM,
            unitPrice: line.unitPrice,
            paidAmount: paidShare,
            currencyId: line.currencyId,
            currencyCode: line.currencyLabel,
            warehouseId: line.product.warehouseId,
            warehouseName: line.product.warehouseName,
            createdAt: createdAt,
          );
        }(),
    ];
  }

  OrderModel? lastSavedOrder;

  double _paidForLine(int index) {
    // Discount is applied proportionally so line paid amounts still sum to
    // [effectivePaid] against discounted [total].
    final sub = subtotal;
    if (sub <= 0) return 0;
    var remainingCash = effectivePaid;
    for (var i = 0; i < lines.length; i++) {
      final due = lines[i].lineTotal * (total / sub);
      final paid = remainingCash >= due ? due : remainingCash.clamp(0.0, due);
      remainingCash -= paid;
      if (i == index) return paid.toDouble();
    }
    return 0;
  }

  /// Saves cart as one outbound invoice (order) with linked stock movements.
  /// Returns null on success, or an error message.
  Future<String?> save() async {
    if (lines.isEmpty) return 'sales.cartEmpty'.tr();
    if (saving) return null;

    for (final line in lines) {
      if (limitToStock &&
          line.quantity > line.product.currentStock + 0.0001) {
        return 'stockEntry.notEnoughStock'.tr();
      }
    }

    saving = true;
    error = null;
    lastSavedOrder = null;
    _notify();

    final createdAt = DateTime.now();
    final partnerName =
        selectedCompany?.name ?? 'sales.walkInCustomer'.tr();

    try {
      final lineInputs = [
        for (var i = 0; i < lines.length; i++)
          OutboundOrderLineInput(
            productId: lines[i].product.id,
            productName: lines[i].product.name,
            quantity: lines[i].quantity.abs(),
            unitPrice: lines[i].unitPrice,
            lineTotal: lines[i].lineTotal,
            paidAmount: _paidForLine(i),
            lengthM: lines[i].lengthM,
            widthM: lines[i].widthM,
            currencyId: orderCurrency?.id ?? lines[i].currencyId,
            warehouseId: lines[i].product.warehouseId,
          ),
      ];

      final result = editingOrderId != null
          ? await _orders.replaceOutboundOrder(
              orderId: editingOrderId!,
              lines: lineInputs,
              partnerType: selectedCompany?.source,
              partnerId: selectedCompany?.id,
              partnerName: partnerName,
              currencyId: orderCurrency?.id,
              currencyCode: orderCurrency?.code,
              discount: discount,
              amountPaid: effectivePaid,
            )
          : await _orders.createOutboundOrder(
              lines: lineInputs,
              partnerType: selectedCompany?.source,
              partnerId: selectedCompany?.id,
              partnerName: partnerName,
              currencyId: orderCurrency?.id,
              currencyCode: orderCurrency?.code,
              discount: discount,
              amountPaid: effectivePaid,
              createdAt: createdAt,
            );

      saving = false;
      return result.when(
        success: (order) {
          lastSavedOrder = order;
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
