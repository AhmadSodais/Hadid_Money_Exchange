import '../../core/errors/result.dart';
import '../../core/utils/overview_chart_period.dart';
import '../../data/models/company_payment_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/report_models.dart';
import '../../data/models/stock_movement_model.dart';

class StockSummary {
  const StockSummary({
    this.totalValue = 0,
    this.sheetCount = 0,
    this.lowStock = 0,
    this.wasteThisMonth = 0,
  });

  final double totalValue;
  final int sheetCount;
  final int lowStock;
  final double wasteThisMonth;
}

class WarehouseCapacity {
  const WarehouseCapacity({
    this.used = 0,
    this.capacity = 0,
    this.unit = 'sheets',
  });

  final double used;
  final double capacity;
  final String unit;

  double get percentUsed => capacity <= 0 ? 0 : (used / capacity) * 100;
}

class InventoryStockQuery {
  const InventoryStockQuery({
    this.search,
    this.categoryId,
    this.brand,
    this.supplierId,
    this.status,
    this.remnantsOnly,
    this.page = 1,
    this.pageSize = 20,
  });

  final String? search;
  final int? categoryId;
  final String? brand;
  final int? supplierId;
  final ProductStockStatus? status;

  /// Legacy glass filter — unused in general-store UI.
  final bool? remnantsOnly;
  final int page;
  final int pageSize;

  int get offset => (page - 1) * pageSize;
}

abstract class InventoryRepository {
  Future<Result<StockSummary>> getStockSummary();
  Future<Result<PaginatedResult<ProductModel>>> listStock(InventoryStockQuery query);
  Future<Result<List<StockMovementModel>>> getMovements({
    int? productId,
    StockMovementType? type,
    DateTime? from,
    DateTime? to,
    int limit = 100,
    int offset = 0,
    /// When true, hide movements that belong to a sales invoice (shown on Orders).
    bool excludeOrderLinked = true,
    /// When true, hide movements that belong to a purchase invoice (shown on Purchases).
    bool excludePurchaseLinked = true,
    String? partnerType,
    int? partnerId,
    String? partnerName,
  });
  Future<Result<ProductModel>> recordMovement({
    required int productId,
    required StockMovementType type,
    required double quantity,
    String? notes,
    String? referenceType,
    int? referenceId,
    String? partnerName,
    double? lengthM,
    double? widthM,
    double brokenQty = 0,
    double? unitPrice,
    double paidAmount = 0,
    int? currencyId,
    int? warehouseId,
    int? employeeId,
    DateTime? createdAt,
  });
  Future<Result<void>> deleteMovement(int movementId);
  Future<Result<StockMovementModel>> updateMovement({
    required int movementId,
    required double quantity,
    String? notes,
    String? partnerName,
    double? lengthM,
    double? widthM,
    double brokenQty = 0,
    double? unitPrice,
    double? paidAmount,
    int? currencyId,
    int? warehouseId,
    int? employeeId,
    DateTime? createdAt,
  });
  Future<Result<List<StockMovementModel>>> getWasteRemnants({
    DateTime? from,
    DateTime? to,
  });
  Future<Result<WarehouseCapacity>> getWarehouseCapacity();
  Future<Result<OverviewStats>> getOverviewStats({
    DateTime? from,
    DateTime? to,
  });

  /// Outstanding receivable/payable and purchase/sales totals by company key
  /// (`source:id` / `name:…`).
  ///
  /// Receivable = unpaid sales orders; payable = unpaid purchases.
  Future<Result<Map<String, CompanyPartnerBalances>>> getCompanyBalances();

  Future<Result<List<CompanyPaymentModel>>> getCompanyPayments({
    required String partnerType,
    required int partnerId,
  });

  /// Records a settlement and FIFO-allocates it to unpaid invoices
  /// (payable → purchases, receivable → sales orders), then syncs linked movements.
  Future<Result<CompanyPaymentModel>> addCompanyPayment({
    required String partnerType,
    required int partnerId,
    String? partnerName,
    required double amount,
    required String currency,
    required DateTime paidAt,
    required PaymentSettlementSide settlementSide,
    String? notes,
  });

  /// Updates a payment (re-allocates outstanding after reversing the old one).
  Future<Result<CompanyPaymentModel>> updateCompanyPayment({
    required int paymentId,
    required double amount,
    required String currency,
    required DateTime paidAt,
    required PaymentSettlementSide settlementSide,
    String? notes,
  });

  /// Deletes a payment and reverses its invoice / movement allocations.
  Future<Result<void>> deleteCompanyPayment(int paymentId);

  /// Stock-movement totals for the overview line chart.
  ///
  /// - [OverviewChartPeriod.weekly]: Saturday → Friday (current Shamsi week)
  /// - [OverviewChartPeriod.monthly]: Farvardin → current Shamsi month (zeros filled)
  /// - [OverviewChartPeriod.yearly]: first year with data → current Shamsi year
  Future<Result<List<SalesTrendPoint>>> getMovementChartTrend(
    OverviewChartPeriod period,
  );
}
