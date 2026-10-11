import '../../core/errors/result.dart';
import '../../data/models/product_model.dart';
import '../../data/models/report_models.dart';
import '../../data/models/stock_movement_model.dart';

abstract class ProductRepository {
  Future<Result<PaginatedResult<ProductModel>>> query(ProductQuery query);
  Future<Result<ProductModel>> getById(int id);
  Future<Result<ProductModel?>> getBySku(String sku);
  Future<Result<ProductStats>> getStats();
  Future<Result<ProductModel>> create(ProductModel product);
  Future<Result<ProductModel>> update(ProductModel product);
  Future<Result<ProductModel>> duplicate(int id);
  Future<Result<void>> archive(int id);
  Future<Result<void>> restore(int id);
  Future<Result<void>> delete(int id);
  Future<Result<ProductModel>> adjustStock({
    required int productId,
    required double quantityDelta,
    required StockMovementType type,
    String? notes,
    String? referenceType,
    int? referenceId,
  });
  Future<Result<List<StockMovementModel>>> getMovements(int productId);
  Future<Result<List<InventoryAlert>>> getAlerts({int limit = 20});
  Future<Result<List<CategoryShare>>> getCategoryShares();
  Future<Result<bool>> isSkuAvailable(String sku, {int? excludeId});
  Future<Result<List<ProductModel>>> searchForPos(String query, {int? categoryId});
}
