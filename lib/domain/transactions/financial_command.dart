import '../money/decimal.dart';
import '../shared/business_date.dart';

/// Business transaction types. Persisted by [name].
///
/// [prefix] starts the reference number (`RCP-0042`). Openings and
/// adjustments read action + target: `OP`/`AD` then `C` (cash drawer) or
/// `A` (customer account).
enum TransactionType {
  /// رسید — cash physically received from a customer.
  receipt('RCP', 'رسید'),

  /// برد — cash physically paid to a customer.
  payment('PAY', 'برد'),

  /// خرید — the exchange buys a currency from a customer.
  buy('BUY', 'خرید'),

  /// فروش — the exchange sells a currency to a customer.
  sell('SEL', 'فروش'),

  /// Cash capital put into a drawer in one currency: the initial capital and
  /// any later capital injection.
  openingCash('OPC', 'سرمایه صندوق'),

  /// Opening balance of a customer in one currency (posted once).
  openingCustomer('OPA', 'بیلانس افتتاحیه'),

  /// Authorized cash correction (e.g. reconciliation discrepancy).
  cashAdjustment('ADC', 'اصلاح صندوق'),

  /// Authorized correction of a customer balance.
  customerAdjustment('ADA', 'اصلاح حساب مشتری'),

  /// Operating expense paid from cash.
  expense('EXP', 'مصرف'),

  /// Full reversal of an earlier posted transaction.
  reversal('REV', 'برگشت');

  const TransactionType(this.prefix, this.labelFa);

  final String prefix;
  final String labelFa;

  static TransactionType parse(String raw) =>
      TransactionType.values.firstWhere((t) => t.name == raw);
}

/// How one side of an exchange is settled.
enum Settlement {
  /// Physical cash in the selected drawer.
  cash,

  /// Debited/credited to the (named) customer's account.
  customer;

  static Settlement parse(String raw) =>
      Settlement.values.firstWhere((s) => s.name == raw);
}

enum ExchangeDirection { buy, sell }

/// Fields shared by every posting command.
sealed class FinancialCommand {
  const FinancialCommand({
    required this.idempotencyKey,
    required this.effectiveDate,
    this.description,
  });

  /// Client-generated unique key. Re-submitting the same key returns the
  /// already-posted transaction instead of creating a duplicate.
  final String idempotencyKey;
  final BusinessDate effectiveDate;
  final String? description;

  TransactionType get type;
}

/// رسید: Dr Cash(drawer) / Cr Customer.
final class ReceiptCommand extends FinancialCommand {
  const ReceiptCommand({
    required super.idempotencyKey,
    required super.effectiveDate,
    super.description,
    required this.customerId,
    required this.drawerId,
    required this.currency,
    required this.amountMinor,
  });

  final int customerId;
  final int drawerId;
  final String currency;
  final int amountMinor;

  @override
  TransactionType get type => TransactionType.receipt;
}

/// برد: Dr Customer / Cr Cash(drawer).
final class PaymentCommand extends FinancialCommand {
  const PaymentCommand({
    required super.idempotencyKey,
    required super.effectiveDate,
    super.description,
    required this.customerId,
    required this.drawerId,
    required this.currency,
    required this.amountMinor,
  });

  final int customerId;
  final int drawerId;
  final String currency;
  final int amountMinor;

  @override
  TransactionType get type => TransactionType.payment;
}

/// Optional commission charged on an exchange, collected in addition to the
/// exchanged amounts.
final class ExchangeFee {
  const ExchangeFee({
    required this.currency,
    required this.amountMinor,
    this.settlement = Settlement.cash,
  });

  final String currency;
  final int amountMinor;
  final Settlement settlement;
}

/// خرید / فروش.
///
/// [baseCurrency] is the currency being bought or sold (the traded quantity),
/// [quoteCurrency] is the counter currency. Rate convention:
/// `1 base = rate quote`, so `quoteAmount = baseAmount × rate`.
///
/// * buy:  exchange receives `baseAmount` and delivers `quoteAmount`.
/// * sell: exchange delivers `baseAmount` and receives `quoteAmount`.
final class ExchangeCommand extends FinancialCommand {
  const ExchangeCommand({
    required super.idempotencyKey,
    required super.effectiveDate,
    super.description,
    required this.direction,
    required this.customerId,
    required this.drawerId,
    required this.baseCurrency,
    required this.quoteCurrency,
    required this.baseAmountMinor,
    required this.rate,
    this.baseSettlement = Settlement.cash,
    this.quoteSettlement = Settlement.cash,
    this.fee,
  });

  final ExchangeDirection direction;
  final int customerId;
  final int drawerId;
  final String baseCurrency;
  final String quoteCurrency;
  final int baseAmountMinor;
  final Decimal rate;
  final Settlement baseSettlement;
  final Settlement quoteSettlement;
  final ExchangeFee? fee;

  @override
  TransactionType get type =>
      direction == ExchangeDirection.buy ? TransactionType.buy : TransactionType.sell;
}

/// Capital put into a drawer in one currency: Dr Cash / Cr capital equity.
/// The first one per drawer and currency is the initial capital; later ones
/// are capital injections.
final class OpeningCashCommand extends FinancialCommand {
  const OpeningCashCommand({
    required super.idempotencyKey,
    required super.effectiveDate,
    super.description,
    required this.drawerId,
    required this.currency,
    required this.amountMinor,
  });

  final int drawerId;
  final String currency;
  final int amountMinor;

  @override
  TransactionType get type => TransactionType.openingCash;
}

/// Opening balance of a customer. Sign follows the customer-position
/// convention: positive = exchange owes the customer (طلب مشتری) and the
/// funds are treated as cash already in [drawerId]; negative = the customer
/// owes the exchange (بدهی مشتری) and is offset against opening equity.
final class OpeningCustomerCommand extends FinancialCommand {
  const OpeningCustomerCommand({
    required super.idempotencyKey,
    required super.effectiveDate,
    super.description,
    required this.customerId,
    required this.currency,
    required this.signedMinor,
    this.drawerId,
  });

  final int customerId;
  final String currency;
  final int signedMinor;

  /// Required when [signedMinor] is positive (cash vault increases).
  final int? drawerId;

  @override
  TransactionType get type => TransactionType.openingCustomer;
}

/// Authorized cash correction. Positive = cash surplus (cash increases).
final class CashAdjustmentCommand extends FinancialCommand {
  const CashAdjustmentCommand({
    required super.idempotencyKey,
    required super.effectiveDate,
    super.description,
    required this.drawerId,
    required this.currency,
    required this.signedMinor,
    required this.reason,
  });

  final int drawerId;
  final String currency;
  final int signedMinor;
  final String reason;

  @override
  TransactionType get type => TransactionType.cashAdjustment;
}

/// Authorized customer-balance correction. Positive = customer position
/// increases (exchange owes more / customer owes less).
final class CustomerAdjustmentCommand extends FinancialCommand {
  const CustomerAdjustmentCommand({
    required super.idempotencyKey,
    required super.effectiveDate,
    super.description,
    required this.customerId,
    required this.currency,
    required this.signedMinor,
    required this.reason,
  });

  final int customerId;
  final String currency;
  final int signedMinor;
  final String reason;

  @override
  TransactionType get type => TransactionType.customerAdjustment;
}

/// Operating expense paid from a drawer.
final class ExpenseCommand extends FinancialCommand {
  const ExpenseCommand({
    required super.idempotencyKey,
    required super.effectiveDate,
    required String super.description,
    required this.drawerId,
    required this.currency,
    required this.amountMinor,
  });

  final int drawerId;
  final String currency;
  final int amountMinor;

  @override
  TransactionType get type => TransactionType.expense;
}
