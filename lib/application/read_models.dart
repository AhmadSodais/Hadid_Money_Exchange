import '../domain/shared/business_date.dart';
import '../domain/transactions/financial_command.dart';

/// Status of a business transaction.
enum TransactionStatus {
  posted,
  reversed;

  static TransactionStatus parse(String raw) =>
      TransactionStatus.values.firstWhere((s) => s.name == raw);
}

/// A posted business transaction as shown in the journal.
final class PostedTransaction {
  const PostedTransaction({
    required this.id,
    required this.uuid,
    required this.referenceNo,
    required this.type,
    required this.status,
    required this.effectiveDate,
    required this.createdAt,
    required this.createdBy,
    this.createdByName,
    this.customerId,
    this.customerName,
    this.drawerId,
    this.description,
    this.sourceCurrency,
    this.sourceAmountMinor,
    this.destCurrency,
    this.destAmountMinor,
    this.rate,
    this.sourceSettlement,
    this.destSettlement,
    this.feeCurrency,
    this.feeAmountMinor,
    this.feeSettlement,
    this.signedAmountMinor,
    this.reversesTransactionId,
    this.reversedByTransactionId,
    this.replacesTransactionId,
    this.replacedByTransactionId,
    this.reason,
    this.lines = const [],
  });

  factory PostedTransaction.fromRow(Map<String, Object?> r,
          {List<JournalLineView> lines = const []}) =>
      PostedTransaction(
        id: r['id'] as int,
        uuid: r['uuid'] as String,
        referenceNo: r['reference_no'] as String,
        type: TransactionType.parse(r['type'] as String),
        status: TransactionStatus.parse(r['status'] as String),
        effectiveDate: BusinessDate.parse(r['effective_date'] as String),
        createdAt: DateTime.parse(r['created_at'] as String),
        createdBy: r['created_by'] as int,
        createdByName: r['created_by_name'] as String?,
        customerId: r['customer_id'] as int?,
        customerName: r['customer_name'] as String?,
        drawerId: r['drawer_id'] as int?,
        description: r['description'] as String?,
        sourceCurrency: r['source_currency'] as String?,
        sourceAmountMinor: r['source_amount_minor'] as int?,
        destCurrency: r['dest_currency'] as String?,
        destAmountMinor: r['dest_amount_minor'] as int?,
        rate: r['rate'] as String?,
        sourceSettlement: r['source_settlement'] as String?,
        destSettlement: r['dest_settlement'] as String?,
        feeCurrency: r['fee_currency'] as String?,
        feeAmountMinor: r['fee_amount_minor'] as int?,
        feeSettlement: r['fee_settlement'] as String?,
        signedAmountMinor: r['signed_amount_minor'] as int?,
        reversesTransactionId: r['reverses_transaction_id'] as int?,
        reversedByTransactionId: r['reversed_by_transaction_id'] as int?,
        replacesTransactionId: r['replaces_id'] as int?,
        replacedByTransactionId: r['replaced_by_id'] as int?,
        reason: r['reason'] as String?,
        lines: lines,
      );

  final int id;
  final String uuid;
  final String referenceNo;
  final TransactionType type;
  final TransactionStatus status;
  final BusinessDate effectiveDate;
  final DateTime createdAt;
  final int createdBy;
  final String? createdByName;
  final int? customerId;
  final String? customerName;
  final int? drawerId;
  final String? description;

  /// For buy/sell: base (traded) currency and quantity.
  /// For single-currency types: the currency and absolute amount.
  final String? sourceCurrency;
  final int? sourceAmountMinor;

  /// For buy/sell: quote (counter) currency and computed amount.
  final String? destCurrency;
  final int? destAmountMinor;
  final String? rate;
  final String? sourceSettlement;
  final String? destSettlement;
  final String? feeCurrency;
  final int? feeAmountMinor;
  final String? feeSettlement;

  /// Signed amount for adjustments / customer opening balances.
  final int? signedAmountMinor;
  final int? reversesTransactionId;
  final int? reversedByTransactionId;

  /// Set when this transaction is the corrected version of an edited one.
  final int? replacesTransactionId;

  /// Set when this transaction was edited; points to its corrected version.
  final int? replacedByTransactionId;
  final String? reason;
  final List<JournalLineView> lines;

  bool get isExchange => type == TransactionType.buy || type == TransactionType.sell;

  /// Still affects balances: posted and not itself a reversal document.
  bool get isActive => status == TransactionStatus.posted && type != TransactionType.reversal;

  /// Reversed as part of an edit (as opposed to a plain delete).
  bool get wasEdited => status == TransactionStatus.reversed && replacedByTransactionId != null;
}

/// SQL selecting the correction links of `transactions t` as `replaces_id`
/// and `replaced_by_id` (read by [PostedTransaction.fromRow]).
const String kCorrectionLinkColumns = '''
  (SELECT original_transaction_id FROM transaction_corrections
     WHERE replacement_transaction_id = t.id) AS replaces_id,
  (SELECT replacement_transaction_id FROM transaction_corrections
     WHERE original_transaction_id = t.id) AS replaced_by_id''';

final class JournalLineView {
  const JournalLineView({
    required this.lineNo,
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.currency,
    required this.debitMinor,
    required this.creditMinor,
    this.memo,
  });

  factory JournalLineView.fromRow(Map<String, Object?> r) => JournalLineView(
        lineNo: r['line_no'] as int,
        accountId: r['account_id'] as int,
        accountCode: r['account_code'] as String,
        accountName: r['account_name'] as String,
        currency: r['currency_code'] as String,
        debitMinor: r['debit_minor'] as int,
        creditMinor: r['credit_minor'] as int,
        memo: r['memo'] as String?,
      );

  final int lineNo;
  final int accountId;
  final String accountCode;
  final String accountName;
  final String currency;
  final int debitMinor;
  final int creditMinor;
  final String? memo;
}

final class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.isWalkIn,
    required this.createdAt,
    this.phone,
    this.idDocument,
    this.address,
    this.notes,
  });

  factory CustomerRecord.fromRow(Map<String, Object?> r) => CustomerRecord(
        id: r['id'] as int,
        code: r['code'] as String,
        name: r['name'] as String,
        status: r['status'] as String,
        isWalkIn: (r['is_walk_in'] as int) == 1,
        createdAt: DateTime.parse(r['created_at'] as String),
        phone: r['phone'] as String?,
        idDocument: r['id_document'] as String?,
        address: r['address'] as String?,
        notes: r['notes'] as String?,
      );

  final int id;
  final String code;
  final String name;
  final String status;
  final bool isWalkIn;
  final DateTime createdAt;
  final String? phone;
  final String? idDocument;
  final String? address;
  final String? notes;

  bool get isActive => status == 'active';
}

/// Customer position per currency. Positive = exchange owes the customer
/// (credit balance); negative = customer owes the exchange (debit balance).
final class CustomerBalance {
  const CustomerBalance(this.customerId, this.currency, this.positionMinor);

  final int customerId;
  final String currency;
  final int positionMinor;
}

/// Cash movement of one drawer/currency over a date range.
final class CashMovement {
  const CashMovement({
    required this.currency,
    required this.openingMinor,
    required this.inflowMinor,
    required this.outflowMinor,
  });

  final String currency;
  final int openingMinor;
  final int inflowMinor;
  final int outflowMinor;

  int get closingMinor => openingMinor + inflowMinor - outflowMinor;
}

final class TrialBalanceRow {
  const TrialBalanceRow({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.currency,
    required this.debitMinor,
    required this.creditMinor,
  });

  final int accountId;
  final String accountCode;
  final String accountName;
  final String accountType;
  final String currency;
  final int debitMinor;
  final int creditMinor;

  int get netMinor => debitMinor - creditMinor;
}

final class StatementLine {
  const StatementLine({
    required this.transactionId,
    required this.referenceNo,
    required this.type,
    required this.status,
    required this.effectiveDate,
    required this.currency,
    required this.debitMinor,
    required this.creditMinor,
    required this.runningPositionMinor,
    this.description,
  });

  final int transactionId;
  final String referenceNo;
  final TransactionType type;
  final TransactionStatus status;
  final BusinessDate effectiveDate;
  final String currency;
  final int debitMinor;
  final int creditMinor;

  /// Customer position after this line (credit-positive convention).
  final int runningPositionMinor;
  final String? description;
}

final class CustomerStatement {
  const CustomerStatement({
    required this.customer,
    required this.currency,
    required this.openingPositionMinor,
    required this.lines,
  });

  final CustomerRecord customer;
  final String currency;
  final int openingPositionMinor;
  final List<StatementLine> lines;

  int get closingPositionMinor =>
      lines.isEmpty ? openingPositionMinor : lines.last.runningPositionMinor;
}

final class ExchangeActivityRow {
  const ExchangeActivityRow({
    required this.type,
    required this.baseCurrency,
    required this.quoteCurrency,
    required this.count,
    required this.baseTotalMinor,
    required this.quoteTotalMinor,
    required this.minRate,
    required this.maxRate,
  });

  final TransactionType type;
  final String baseCurrency;
  final String quoteCurrency;
  final int count;
  final int baseTotalMinor;
  final int quoteTotalMinor;
  final String minRate;
  final String maxRate;
}

final class DailyTypeSummary {
  const DailyTypeSummary(this.type, this.currency, this.count, this.totalMinor);

  final TransactionType type;
  final String currency;
  final int count;
  final int totalMinor;
}

final class ReconciliationRecord {
  const ReconciliationRecord({
    required this.id,
    required this.drawerId,
    required this.currency,
    required this.businessDate,
    required this.openingMinor,
    required this.inflowMinor,
    required this.outflowMinor,
    required this.expectedMinor,
    required this.countedMinor,
    required this.differenceMinor,
    required this.status,
    required this.createdAt,
    required this.createdBy,
    this.adjustmentTransactionId,
    this.notes,
    this.closedAt,
  });

  factory ReconciliationRecord.fromRow(Map<String, Object?> r) =>
      ReconciliationRecord(
        id: r['id'] as int,
        drawerId: r['drawer_id'] as int,
        currency: r['currency_code'] as String,
        businessDate: BusinessDate.parse(r['business_date'] as String),
        openingMinor: r['opening_minor'] as int,
        inflowMinor: r['inflow_minor'] as int,
        outflowMinor: r['outflow_minor'] as int,
        expectedMinor: r['expected_minor'] as int,
        countedMinor: r['counted_minor'] as int,
        differenceMinor: r['difference_minor'] as int,
        status: r['status'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        createdBy: r['created_by'] as int,
        adjustmentTransactionId: r['adjustment_transaction_id'] as int?,
        notes: r['notes'] as String?,
        closedAt: r['closed_at'] == null
            ? null
            : DateTime.parse(r['closed_at'] as String),
      );

  final int id;
  final int drawerId;
  final String currency;
  final BusinessDate businessDate;
  final int openingMinor;
  final int inflowMinor;
  final int outflowMinor;
  final int expectedMinor;
  final int countedMinor;
  final int differenceMinor;
  final String status;
  final DateTime createdAt;
  final int createdBy;
  final int? adjustmentTransactionId;
  final String? notes;
  final DateTime? closedAt;
}

final class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.occurredAt,
    required this.action,
    required this.entityType,
    required this.outcome,
    this.actorName,
    this.entityId,
    this.transactionId,
    this.reason,
    this.message,
    this.beforeJson,
    this.afterJson,
  });

  factory AuditEntry.fromRow(Map<String, Object?> r) => AuditEntry(
        id: r['id'] as int,
        occurredAt: DateTime.parse(r['occurred_at'] as String),
        action: r['action'] as String,
        entityType: r['entity_type'] as String,
        outcome: r['outcome'] as String,
        actorName: r['actor_name'] as String?,
        entityId: r['entity_id'] as String?,
        transactionId: r['transaction_id'] as int?,
        reason: r['reason'] as String?,
        message: r['message'] as String?,
        beforeJson: r['before_json'] as String?,
        afterJson: r['after_json'] as String?,
      );

  final int id;
  final DateTime occurredAt;
  final String action;
  final String entityType;
  final String outcome;
  final String? actorName;
  final String? entityId;
  final int? transactionId;
  final String? reason;
  final String? message;
  final String? beforeJson;
  final String? afterJson;
}
