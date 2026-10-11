import '../../core/errors/result.dart';
import '../../data/models/order_model.dart';
import '../../data/models/report_models.dart';

abstract class OrderRepository {
  /// Lists orders. By default skips loading line items (uses [OrderModel.lineCount]).
  Future<Result<PaginatedResult<OrderModel>>> list({
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

  Future<Result<OrderModel>> getById(int id);

  /// Creates an outbound invoice, posts stock movements, and links them.
  Future<Result<OrderModel>> createOutboundOrder({
    required List<OutboundOrderLineInput> lines,
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

  Future<Result<OrderModel>> updateOrder({
    required int orderId,
    String? partnerType,
    int? partnerId,
    String? partnerName,
    double? discount,
    double? amountPaid,
    String? notes,
  });

  /// Replaces an outbound invoice's lines (stock reverse + rewrite).
  /// Keeps the same invoice number and created_at.
  Future<Result<OrderModel>> replaceOutboundOrder({
    required int orderId,
    required List<OutboundOrderLineInput> lines,
    String? partnerType,
    int? partnerId,
    String? partnerName,
    int? currencyId,
    String? currencyCode,
    double discount = 0,
    required double amountPaid,
    String? notes,
  });

  /// Deletes the invoice and reverses linked stock movements.
  Future<Result<void>> deleteOrder(int orderId);
}
