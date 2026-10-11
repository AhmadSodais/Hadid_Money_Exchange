import '../../core/errors/result.dart';
import '../../data/models/purchase_model.dart';
import '../../data/models/report_models.dart';

abstract class PurchaseRepository {
  /// Lists purchases. By default skips loading line items (uses [PurchaseModel.lineCount]).
  Future<Result<PaginatedResult<PurchaseModel>>> list({
    String? search,
    DateTime? from,
    DateTime? to,
    String? paymentStatus,
    String? partnerType,
    int? partnerId,
    String? partnerName,
    int page = 1,
    int pageSize = 50,
    bool includeItems = false,
  });

  Future<Result<PurchaseModel>> getById(int id);

  /// Creates a purchase invoice, posts inbound stock movements, and links them.
  Future<Result<PurchaseModel>> createPurchase({
    required List<PurchaseLineInput> lines,
    required String invoiceNumber,
    String? partnerType,
    int? partnerId,
    String? partnerName,
    int? currencyId,
    String? currencyCode,
    double discount = 0,
    required double amountPaid,
    String? notes,
    DateTime? createdAt,
  });

  /// Replaces a purchase invoice's lines (stock reverse + rewrite).
  Future<Result<PurchaseModel>> replacePurchase({
    required int purchaseId,
    required List<PurchaseLineInput> lines,
    required String invoiceNumber,
    String? partnerType,
    int? partnerId,
    String? partnerName,
    int? currencyId,
    String? currencyCode,
    double discount = 0,
    required double amountPaid,
    String? notes,
    DateTime? createdAt,
  });

  /// Deletes the purchase and reverses linked stock movements.
  Future<Result<void>> deletePurchase(int purchaseId);
}
