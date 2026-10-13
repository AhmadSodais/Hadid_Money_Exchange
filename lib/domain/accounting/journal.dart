import '../errors/domain_errors.dart';
import 'account.dart';

/// One debit or credit line of a journal entry, in a single currency.
final class JournalLineDraft {
  const JournalLineDraft({
    required this.account,
    required this.currency,
    this.debitMinor = 0,
    this.creditMinor = 0,
    this.memo,
  });

  factory JournalLineDraft.debit(AccountRef account, String currency, int minor,
          {String? memo}) =>
      JournalLineDraft(
          account: account, currency: currency, debitMinor: minor, memo: memo);

  factory JournalLineDraft.credit(
          AccountRef account, String currency, int minor, {String? memo}) =>
      JournalLineDraft(
          account: account, currency: currency, creditMinor: minor, memo: memo);

  final AccountRef account;
  final String currency;
  final int debitMinor;
  final int creditMinor;
  final String? memo;

  /// Same line with debit and credit swapped (used by reversals).
  JournalLineDraft mirrored() => JournalLineDraft(
        account: account,
        currency: currency,
        debitMinor: creditMinor,
        creditMinor: debitMinor,
        memo: memo,
      );

  /// Signed effect: debit positive, credit negative.
  int get net => debitMinor - creditMinor;

  @override
  String toString() =>
      '${debitMinor > 0 ? 'Dr' : 'Cr'} $account $currency ${debitMinor > 0 ? debitMinor : creditMinor}';
}

/// An unposted journal entry. [validate] enforces the accounting invariants.
final class JournalDraft {
  JournalDraft(List<JournalLineDraft> lines) : lines = List.unmodifiable(lines);

  final List<JournalLineDraft> lines;

  Set<String> get currencies => {for (final l in lines) l.currency};

  /// Invariants:
  /// 1. At least two lines.
  /// 2. Each line has exactly one strictly positive side.
  /// 3. For **each currency separately**, total debits equal total credits.
  ///    Amounts in different currencies are never compared to each other.
  void validate() {
    if (lines.length < 2) {
      throw const InvariantViolation(
          'journal.tooFewLines', 'سند حسابداری باید حداقل دو سطر داشته باشد.');
    }
    final totals = <String, int>{};
    for (final line in lines) {
      final validSide = (line.debitMinor > 0 && line.creditMinor == 0) ||
          (line.creditMinor > 0 && line.debitMinor == 0);
      if (!validSide) {
        throw InvariantViolation('journal.badLine',
            'هر سطر باید فقط بدهکار یا فقط طلب مشتری) مثبت باشد: $line');
      }
      totals.update(line.currency, (v) => v + line.net,
          ifAbsent: () => line.net);
    }
    for (final entry in totals.entries) {
      if (entry.value != 0) {
        throw InvariantViolation('journal.unbalanced',
            'سند در ارز ${entry.key} تراز نیست (اختلاف ${entry.value}).');
      }
    }
  }

  JournalDraft reversed() =>
      JournalDraft([for (final l in lines) l.mirrored()]);
}
