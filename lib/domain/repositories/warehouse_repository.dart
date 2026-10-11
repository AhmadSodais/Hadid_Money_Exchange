import '../../core/errors/result.dart';
import '../../data/models/product_model.dart';
import '../../data/models/stock_movement_model.dart';
import '../../data/models/warehouse_model.dart';

abstract class WarehouseRepository {
  Future<Result<List<WarehouseModel>>> list({
    bool includeInactive = false,
    String? search,
    DateTime? from,
    DateTime? to,
  });

  Future<Result<WarehouseModel>> getById(
    int id, {
    DateTime? from,
    DateTime? to,
  });

  Future<Result<WarehouseModel>> create(WarehouseModel warehouse);

  Future<Result<WarehouseModel>> update(WarehouseModel warehouse);

  Future<Result<void>> delete(int id);

  Future<Result<List<StockMovementModel>>> getMovements(
    int warehouseId, {
    DateTime? from,
    DateTime? to,
    int limit = 200,
    int offset = 0,
    /// `inbound` (purchase/return_in), `outbound` (sale/return_out), or null = all.
    String? direction,
  });

  Future<Result<int>> countMovements(
    int warehouseId, {
    DateTime? from,
    DateTime? to,
    String? direction,
  });

  Future<Result<List<ProductModel>>> getProducts(
    int warehouseId, {
    int limit = 500,
  });
}
