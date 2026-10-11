import '../../core/errors/result.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/stock_movement_model.dart';

abstract class EmployeeRepository {
  Future<Result<List<EmployeeModel>>> list({
    bool includeInactive = false,
    String? search,
    DateTime? from,
    DateTime? to,
  });

  Future<Result<EmployeeModel>> getById(
    int id, {
    DateTime? from,
    DateTime? to,
  });

  Future<Result<EmployeeModel>> create(EmployeeModel employee);

  Future<Result<EmployeeModel>> update(EmployeeModel employee);

  Future<Result<void>> delete(int id);

  Future<Result<List<StockMovementModel>>> getMovements(
    int employeeId, {
    DateTime? from,
    DateTime? to,
    int limit = 500,
  });

  Future<Result<List<EmployeeWithdrawalModel>>> getWithdrawals(int employeeId);

  Future<Result<EmployeeWithdrawalModel>> addWithdrawal(
    EmployeeWithdrawalModel withdrawal,
  );

  Future<Result<void>> deleteWithdrawal(int withdrawalId);
}
