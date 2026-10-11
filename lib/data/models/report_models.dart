import 'package:equatable/equatable.dart';

class PaginatedResult<T> extends Equatable {
  const PaginatedResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;

  int get totalPages => pageSize == 0 ? 0 : (total / pageSize).ceil();
  bool get hasMore => page < totalPages;

  @override
  List<Object?> get props => [items, total, page, pageSize];
}

class CategoryShare extends Equatable {
  const CategoryShare({
    required this.name,
    required this.count,
    required this.percent,
    this.color,
  });

  final String name;
  final int count;
  final double percent;
  final String? color;

  @override
  List<Object?> get props => [name, count, percent];
}

class SalesTrendPoint extends Equatable {
  const SalesTrendPoint({
    required this.date,
    this.total = 0,
    this.inbound = 0,
    this.outbound = 0,
  });

  final DateTime date;
  final double total;
  final double inbound;
  final double outbound;

  @override
  List<Object?> get props => [date, total, inbound, outbound];
}

class TopProductStat extends Equatable {
  const TopProductStat({
    required this.productId,
    required this.name,
    this.categoryName,
    this.imagePath,
    required this.unitsSold,
    this.revenue = 0,
  });

  final int productId;
  final String name;
  final String? categoryName;
  final String? imagePath;
  final double unitsSold;
  final double revenue;

  @override
  List<Object?> get props => [productId, unitsSold];
}

class InventoryAlert extends Equatable {
  const InventoryAlert({
    required this.productId,
    required this.name,
    required this.currentStock,
    required this.minimumStock,
    required this.status,
    this.sku,
    this.barcode,
    this.brand,
    this.expirationDate,
    this.categoryName,
  });

  final int productId;
  final String name;
  final double currentStock;
  final double minimumStock;
  /// `outOfStock` | `lowStock` | `expiringSoon` | `expired`
  final String status;
  final String? sku;
  final String? barcode;
  final String? brand;
  final DateTime? expirationDate;
  final String? categoryName;

  bool get isStockAlert => status == 'outOfStock' || status == 'lowStock' ||
      status == 'Out of Stock' || status == 'Low Stock';
  bool get isExpiryAlert => status == 'expiringSoon' || status == 'expired';

  @override
  List<Object?> get props => [productId, currentStock, status, expirationDate];
}

class OverviewStats extends Equatable {
  const OverviewStats({
    this.todayInbound = 0,
    this.todayOutbound = 0,
    this.weekInbound = 0,
    this.weekOutbound = 0,
    this.salesByCurrency = const [],
    this.purchasesByCurrency = const [],
    this.expensesByCurrency = const [],
    this.monthSalesTotal = 0,
    this.monthPurchaseTotal = 0,
    this.monthExpensesTotal = 0,
    this.orderCount = 0,
    this.purchaseCount = 0,
    this.employeeLiabilities = 0,
    this.employeeLiabilitiesByCurrency = const [],
    this.employeeWithdrawals = 0,
    this.employeeWithdrawalsByCurrency = const [],
    this.totalProducts = 0,
    this.lowStock = 0,
    this.outOfStock = 0,
    this.warehouseCount = 0,
    this.companyCount = 0,
    this.inventoryValue = 0,
    this.receivableOutstanding = const [],
    this.payableOutstanding = const [],
    this.customerLoans = const [],
    this.customerCount = 0,
    this.movementTrend = const [],
    this.categoryShares = const [],
    this.recentActivity = const [],
    this.recentOrders = const [],
    this.recentPurchases = const [],
    this.alerts = const [],
    this.topProducts = const [],
    this.todaySales = 0,
    this.pendingOrders = 0,
    this.totalSales = 0,
    this.monthlyRevenue = 0,
    this.salesTrend = const [],
  });

  final double todayInbound;
  final double todayOutbound;
  final double weekInbound;
  final double weekOutbound;
  final List<CurrencyMoneyTotal> salesByCurrency;
  final List<CurrencyMoneyTotal> purchasesByCurrency;
  final List<CurrencyMoneyTotal> expensesByCurrency;
  /// Sum across currencies (legacy / sparkline helpers).
  final double monthSalesTotal;
  final double monthPurchaseTotal;
  final double monthExpensesTotal;
  final int orderCount;
  final int purchaseCount;
  final double employeeLiabilities;
  final List<CurrencyMoneyTotal> employeeLiabilitiesByCurrency;
  final double employeeWithdrawals;
  final List<CurrencyMoneyTotal> employeeWithdrawalsByCurrency;
  final int totalProducts;
  final int lowStock;
  final int outOfStock;
  final int warehouseCount;
  final int companyCount;
  final double inventoryValue;
  final List<CurrencyMoneyTotal> receivableOutstanding;
  final List<CurrencyMoneyTotal> payableOutstanding;
  /// Customers with unpaid sales balances (loan / receivable accounts).
  final List<OverviewCustomerLoan> customerLoans;
  final int customerCount;
  final List<SalesTrendPoint> movementTrend;
  final List<CategoryShare> categoryShares;
  final List<AuditLogModelStub> recentActivity;
  final List<OverviewInvoiceStub> recentOrders;
  final List<OverviewInvoiceStub> recentPurchases;
  final List<InventoryAlert> alerts;
  final List<TopProductStat> topProducts;

  final double todaySales;
  final int pendingOrders;
  final double totalSales;
  final double monthlyRevenue;
  final List<SalesTrendPoint> salesTrend;

  @override
  List<Object?> get props => [
        salesByCurrency,
        purchasesByCurrency,
        expensesByCurrency,
        orderCount,
        purchaseCount,
        employeeLiabilities,
        employeeWithdrawals,
        receivableOutstanding,
        payableOutstanding,
        customerLoans,
        customerCount,
      ];
}

/// One customer with outstanding sales balance (loan / receivable).
class OverviewCustomerLoan extends Equatable {
  const OverviewCustomerLoan({
    required this.customerId,
    required this.name,
    required this.outstanding,
    this.phone,
  });

  final int? customerId;
  final String name;
  final List<CurrencyMoneyTotal> outstanding;
  final String? phone;

  double get outstandingTotal =>
      outstanding.fold<double>(0, (s, t) => s + t.amount);

  @override
  List<Object?> get props => [customerId, name, outstanding, phone];
}

/// Amount in a single currency (used for multi-currency totals).
class CurrencyMoneyTotal extends Equatable {
  const CurrencyMoneyTotal({
    required this.currencyCode,
    required this.amount,
  });

  final String currencyCode;
  final double amount;

  @override
  List<Object?> get props => [currencyCode, amount];
}

/// Recent order / purchase row for overview lists.
class OverviewInvoiceStub extends Equatable {
  const OverviewInvoiceStub({
    required this.id,
    required this.invoiceNumber,
    this.partnerName,
    required this.total,
    this.currencyCode,
    required this.createdAt,
  });

  final int id;
  final String invoiceNumber;
  final String? partnerName;
  final double total;
  final String? currencyCode;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, invoiceNumber, total, createdAt];
}

/// Invoice-based AR/AP and turnover for one trading company key (`source:id` or `name:…`).
class CompanyPartnerBalances extends Equatable {
  const CompanyPartnerBalances({
    this.receivable = const [],
    this.payable = const [],
    this.purchases = const [],
    this.sales = const [],
  });

  /// Outstanding on sales (they owe us).
  final List<CurrencyMoneyTotal> receivable;

  /// Outstanding on purchases (we owe them).
  final List<CurrencyMoneyTotal> payable;

  /// Lifetime purchase invoice totals.
  final List<CurrencyMoneyTotal> purchases;

  /// Lifetime sales invoice totals.
  final List<CurrencyMoneyTotal> sales;

  double get receivableTotal =>
      receivable.fold<double>(0, (s, t) => s + t.amount);
  double get payableTotal =>
      payable.fold<double>(0, (s, t) => s + t.amount);
  double get purchasesTotal =>
      purchases.fold<double>(0, (s, t) => s + t.amount);
  double get salesTotal => sales.fold<double>(0, (s, t) => s + t.amount);

  @override
  List<Object?> get props => [receivable, payable, purchases, sales];
}

/// Lightweight activity item to avoid circular imports in overview stats.
class AuditLogModelStub extends Equatable {
  const AuditLogModelStub({
    required this.summary,
    required this.action,
    required this.createdAt,
  });

  final String summary;
  final String action;
  final DateTime createdAt;

  @override
  List<Object?> get props => [summary, action, createdAt];
}
