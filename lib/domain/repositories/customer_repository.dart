import '../../core/errors/result.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/report_models.dart';

abstract class CustomerRepository {
  Future<Result<PaginatedResult<CustomerModel>>> query({
    String? search,
    int page = 1,
    int pageSize = 20,
    bool includeArchived = false,
  });

  Future<Result<CustomerModel>> getById(int id);
  Future<Result<CustomerModel>> create(CustomerModel customer);
  Future<Result<CustomerModel>> update(CustomerModel customer);
  Future<Result<void>> archive(int id);
  Future<Result<void>> restore(int id);
  Future<Result<void>> delete(int id);
}
