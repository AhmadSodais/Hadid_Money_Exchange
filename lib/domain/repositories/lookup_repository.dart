import '../../core/errors/result.dart';
import '../../data/models/category_model.dart';
import '../../data/models/currency_model.dart';

class UnitOfMeasureModel {
  const UnitOfMeasureModel({
    required this.id,
    required this.name,
    required this.abbreviation,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String abbreviation;
  final bool isActive;

  factory UnitOfMeasureModel.fromMap(Map<String, Object?> map) {
    return UnitOfMeasureModel(
      id: map['id'] as int,
      name: map['name'] as String,
      abbreviation: map['abbreviation'] as String,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }
}

abstract class LookupRepository {
  Future<Result<List<CategoryModel>>> getCategories({bool includeInactive = false});
  Future<Result<CategoryModel>> createCategory(String name);
  Future<Result<CategoryModel>> updateCategory(int id, String name);
  Future<Result<void>> deleteCategory(int id);

  Future<Result<List<CurrencyModel>>> getCurrencies();
  Future<Result<CurrencyModel>> updateExchangeRate(int id, double rate);

  Future<Result<List<UnitOfMeasureModel>>> getUnitsOfMeasure();

  Future<Result<String?>> getSetting(String key);
  Future<Result<void>> setSetting(String key, String value);
  Future<Result<Map<String, String>>> getAllSettings();

  /// Static payment methods for POS checkout.
  Future<Result<List<String>>> getPaymentMethods();
}
