import '../../core/errors/result.dart';
import '../../data/models/report_models.dart';
import '../../data/models/supplier_model.dart';

abstract class SupplierRepository {
  Future<Result<PaginatedResult<SupplierModel>>> query({
    String? search,
    int page = 1,
    int pageSize = 20,
    bool includeArchived = false,
  });

  Future<Result<SupplierModel>> getById(int id);
  Future<Result<SupplierModel>> create(SupplierModel supplier);
  Future<Result<SupplierModel>> update(SupplierModel supplier);
  Future<Result<void>> archive(int id);
  Future<Result<void>> restore(int id);
  Future<Result<void>> delete(int id);
}
