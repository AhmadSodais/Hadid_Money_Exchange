/// Chart-of-accounts primitives.
library;

enum AccountType { asset, liability, equity, revenue, expense, clearing }

enum NormalSide { debit, credit }

/// Functional role of an account. The posting engine addresses accounts by
/// role (plus drawer / customer), never by name.
enum AccountRole {
  /// Group/parent account; never posted to directly.
  control,

  /// Physical cash of one drawer (multi-currency ledger).
  cash,

  /// One account per customer (multi-currency ledger).
  /// Credit balance = exchange owes the customer (liability).
  /// Debit balance = customer owes the exchange (receivable).
  customer,

  /// Opening capital / opening balances counter-account.
  openingEquity,

  /// Currency trading (position) account used by buy/sell. Keeps every
  /// currency balanced on its own; see docs/ACCOUNTING_POLICY.md.
  exchangePosition,

  feeRevenue,

  /// Reserved for realized spread once a cost-basis policy is approved.
  spreadRevenue,

  operatingExpense,

  /// Cash surplus (credit) / shortage (debit) found at reconciliation.
  cashOverShort,

  /// Counter-account for authorized customer-balance adjustments.
  adjustment;

  static AccountRole parse(String raw) =>
      AccountRole.values.firstWhere((r) => r.name == raw);
}

/// A reference to the account a journal line posts to, resolved to a
/// database id inside the posting transaction.
sealed class AccountRef {
  const AccountRef();
}

final class CashAccountRef extends AccountRef {
  const CashAccountRef(this.drawerId);
  final int drawerId;

  @override
  bool operator ==(Object o) => o is CashAccountRef && o.drawerId == drawerId;
  @override
  int get hashCode => Object.hash('cash', drawerId);
  @override
  String toString() => 'cash#$drawerId';
}

final class CustomerAccountRef extends AccountRef {
  const CustomerAccountRef(this.customerId);
  final int customerId;

  @override
  bool operator ==(Object o) =>
      o is CustomerAccountRef && o.customerId == customerId;
  @override
  int get hashCode => Object.hash('customer', customerId);
  @override
  String toString() => 'customer#$customerId';
}

/// One of the singleton system accounts (opening equity, position, fees...).
final class SystemAccountRef extends AccountRef {
  const SystemAccountRef(this.role);
  final AccountRole role;

  @override
  bool operator ==(Object o) => o is SystemAccountRef && o.role == role;
  @override
  int get hashCode => Object.hash('system', role);
  @override
  String toString() => 'system:${role.name}';
}

/// Already-resolved account id (used when reversing stored lines).
final class ResolvedAccountRef extends AccountRef {
  const ResolvedAccountRef(this.accountId);
  final int accountId;

  @override
  bool operator ==(Object o) =>
      o is ResolvedAccountRef && o.accountId == accountId;
  @override
  int get hashCode => Object.hash('id', accountId);
  @override
  String toString() => 'account#$accountId';
}
