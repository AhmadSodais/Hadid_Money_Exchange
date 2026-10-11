import '../../core/errors/result.dart';
import '../../data/models/expense_model.dart';

abstract class ExpenseRepository {
  Future<Result<List<ExpenseModel>>> list({
    String? search,
    DateTime? from,
    DateTime? to,
    String? category,
  });

  Future<Result<ExpenseModel>> getById(int id);

  Future<Result<ExpenseModel>> create(ExpenseModel expense);

  Future<Result<ExpenseModel>> update(ExpenseModel expense);

  Future<Result<void>> delete(int id);

  Future<Result<List<ExpenseCategoryTotal>>> totalsByCategory({
    DateTime? from,
    DateTime? to,
  });
}
