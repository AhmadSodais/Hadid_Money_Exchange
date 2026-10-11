import '../errors/domain_errors.dart';
import '../exchange/exchange_rate.dart';
import '../money/currency.dart';
import '../transactions/financial_command.dart';
import 'account.dart';
import 'journal.dart';

/// Result of applying the posting rules to a command.
final class PostingPlan {
  const PostingPlan({
    required this.journal,
    this.quoteAmountMinor,
  });

  final JournalDraft journal;

  /// Computed counter amount of an exchange (null for other types).
  final int? quoteAmountMinor;
}

/// Pure, deterministic translation of business commands into balanced
/// journal entries. No database or Flutter dependencies.
///
/// Customer sign convention: a **credit** on a customer account increases the
/// customer's position (exchange owes the customer more); a **debit**
/// decreases it.
final class PostingRules {
  PostingRules(this.currencies, {required this.walkInCustomerId});

  final Map<String, Currency> currencies;
  final int walkInCustomerId;

  static const _position = SystemAccountRef(AccountRole.exchangePosition);
  static const _openingEquity = SystemAccountRef(AccountRole.openingEquity);
  static const _feeRevenue = SystemAccountRef(AccountRole.feeRevenue);
  static const _expense = SystemAccountRef(AccountRole.operatingExpense);
  static const _overShort = SystemAccountRef(AccountRole.cashOverShort);
  static const _adjustment = SystemAccountRef(AccountRole.adjustment);

  PostingPlan plan(FinancialCommand command) {
    final plan = switch (command) {
      ReceiptCommand c => _receipt(c),
      PaymentCommand c => _payment(c),
      ExchangeCommand c => _exchange(c),
      OpeningCashCommand c => _openingCash(c),
      OpeningCustomerCommand c => _openingCustomer(c),
      CashAdjustmentCommand c => _cashAdjustment(c),
      CustomerAdjustmentCommand c => _customerAdjustment(c),
      ExpenseCommand c => _expenseCmd(c),
    };
    plan.journal.validate();
    return plan;
  }

  Currency currency(String code) {
    final c = currencies[code];
    if (c == null) {
      throw ValidationError('currency.unknown', 'ارز ناشناخته: $code',
          field: 'currency');
    }
    if (!c.isActive) {
      throw ValidationError('currency.inactive', 'ارز $code غیرفعال است.',
          field: 'currency');
    }
    return c;
  }

  void _positive(int minor, String field) {
    if (minor <= 0) {
      throw ValidationError('amount.notPositive', 'مبلغ باید بزرگتر از صفر باشد.',
          field: field);
    }
  }

  void _nonZero(int minor, String field) {
    if (minor == 0) {
      throw ValidationError('amount.zero', 'مبلغ نمی‌تواند صفر باشد.',
          field: field);
    }
  }

  void _namedCustomer(int customerId, String purpose) {
    if (customerId == walkInCustomerId) {
      throw BusinessRuleError('customer.walkInNotAllowed',
          'برای $purpose باید یک مشتری ثبت‌شده انتخاب شود (نه مشتری متفرقه).');
    }
  }

  void _reason(String reason) {
    if (reason.trim().isEmpty) {
      throw const ValidationError('reason.required', 'ذکر دلیل اصلاح الزامی است.',
          field: 'reason');
    }
  }

  PostingPlan _receipt(ReceiptCommand c) {
    currency(c.currency);
    _positive(c.amountMinor, 'amount');
    _namedCustomer(c.customerId, 'رسید');
    return PostingPlan(
      journal: JournalDraft([
        JournalLineDraft.debit(CashAccountRef(c.drawerId), c.currency, c.amountMinor),
        JournalLineDraft.credit(
            CustomerAccountRef(c.customerId), c.currency, c.amountMinor),
      ]),
    );
  }

  PostingPlan _payment(PaymentCommand c) {
    currency(c.currency);
    _positive(c.amountMinor, 'amount');
    _namedCustomer(c.customerId, 'برد');
    return PostingPlan(
      journal: JournalDraft([
        JournalLineDraft.debit(
            CustomerAccountRef(c.customerId), c.currency, c.amountMinor),
        JournalLineDraft.credit(CashAccountRef(c.drawerId), c.currency, c.amountMinor),
      ]),
    );
  }

  AccountRef _settlementAccount(Settlement s, ExchangeCommand c) {
    if (s == Settlement.customer) {
      _namedCustomer(c.customerId, 'تسویه از طریق حساب');
      return CustomerAccountRef(c.customerId);
    }
    return CashAccountRef(c.drawerId);
  }

  PostingPlan _exchange(ExchangeCommand c) {
    final base = currency(c.baseCurrency);
    final quote = currency(c.quoteCurrency);
    _positive(c.baseAmountMinor, 'amount');
    final rate = ExchangeRate.of(base, quote, c.rate);
    final quoteMinor = rate.convert(c.baseAmountMinor);
    if (quoteMinor <= 0) {
      throw const ValidationError('amount.convertedZero',
          'مبلغ معادل پس از گرد کردن صفر می‌شود.', field: 'amount');
    }

    final baseAcc = _settlementAccount(c.baseSettlement, c);
    final quoteAcc = _settlementAccount(c.quoteSettlement, c);
    final lines = <JournalLineDraft>[];
    if (c.direction == ExchangeDirection.buy) {
      // Exchange receives base, delivers quote.
      lines
        ..add(JournalLineDraft.debit(baseAcc, base.code, c.baseAmountMinor))
        ..add(JournalLineDraft.credit(_position, base.code, c.baseAmountMinor))
        ..add(JournalLineDraft.debit(_position, quote.code, quoteMinor))
        ..add(JournalLineDraft.credit(quoteAcc, quote.code, quoteMinor));
    } else {
      // Exchange delivers base, receives quote.
      lines
        ..add(JournalLineDraft.debit(_position, base.code, c.baseAmountMinor))
        ..add(JournalLineDraft.credit(baseAcc, base.code, c.baseAmountMinor))
        ..add(JournalLineDraft.debit(quoteAcc, quote.code, quoteMinor))
        ..add(JournalLineDraft.credit(_position, quote.code, quoteMinor));
    }

    final fee = c.fee;
    if (fee != null && fee.amountMinor != 0) {
      currency(fee.currency);
      _positive(fee.amountMinor, 'fee');
      final feeAcc = _settlementAccount(fee.settlement, c);
      lines
        ..add(JournalLineDraft.debit(feeAcc, fee.currency, fee.amountMinor,
            memo: 'کمیشن'))
        ..add(JournalLineDraft.credit(_feeRevenue, fee.currency, fee.amountMinor,
            memo: 'کمیشن'));
    }
    return PostingPlan(journal: JournalDraft(lines), quoteAmountMinor: quoteMinor);
  }

  PostingPlan _openingCash(OpeningCashCommand c) {
    currency(c.currency);
    _positive(c.amountMinor, 'amount');
    return PostingPlan(
      journal: JournalDraft([
        JournalLineDraft.debit(CashAccountRef(c.drawerId), c.currency, c.amountMinor),
        JournalLineDraft.credit(_openingEquity, c.currency, c.amountMinor),
      ]),
    );
  }

  PostingPlan _openingCustomer(OpeningCustomerCommand c) {
    currency(c.currency);
    _nonZero(c.signedMinor, 'amount');
    _namedCustomer(c.customerId, 'بیلانس افتتاحیه');
    final amount = c.signedMinor.abs();
    final customer = CustomerAccountRef(c.customerId);
    return PostingPlan(
      journal: JournalDraft(c.signedMinor > 0
          ? [
              JournalLineDraft.debit(_openingEquity, c.currency, amount),
              JournalLineDraft.credit(customer, c.currency, amount),
            ]
          : [
              JournalLineDraft.debit(customer, c.currency, amount),
              JournalLineDraft.credit(_openingEquity, c.currency, amount),
            ]),
    );
  }

  PostingPlan _cashAdjustment(CashAdjustmentCommand c) {
    currency(c.currency);
    _nonZero(c.signedMinor, 'amount');
    _reason(c.reason);
    final amount = c.signedMinor.abs();
    final cash = CashAccountRef(c.drawerId);
    return PostingPlan(
      journal: JournalDraft(c.signedMinor > 0
          ? [
              JournalLineDraft.debit(cash, c.currency, amount),
              JournalLineDraft.credit(_overShort, c.currency, amount),
            ]
          : [
              JournalLineDraft.debit(_overShort, c.currency, amount),
              JournalLineDraft.credit(cash, c.currency, amount),
            ]),
    );
  }

  PostingPlan _customerAdjustment(CustomerAdjustmentCommand c) {
    currency(c.currency);
    _nonZero(c.signedMinor, 'amount');
    _reason(c.reason);
    _namedCustomer(c.customerId, 'اصلاح حساب');
    final amount = c.signedMinor.abs();
    final customer = CustomerAccountRef(c.customerId);
    return PostingPlan(
      journal: JournalDraft(c.signedMinor > 0
          ? [
              JournalLineDraft.debit(_adjustment, c.currency, amount),
              JournalLineDraft.credit(customer, c.currency, amount),
            ]
          : [
              JournalLineDraft.debit(customer, c.currency, amount),
              JournalLineDraft.credit(_adjustment, c.currency, amount),
            ]),
    );
  }

  PostingPlan _expenseCmd(ExpenseCommand c) {
    currency(c.currency);
    _positive(c.amountMinor, 'amount');
    if ((c.description ?? '').trim().isEmpty) {
      throw const ValidationError(
          'description.required', 'شرح مصرف الزامی است.', field: 'description');
    }
    return PostingPlan(
      journal: JournalDraft([
        JournalLineDraft.debit(_expense, c.currency, c.amountMinor),
        JournalLineDraft.credit(CashAccountRef(c.drawerId), c.currency, c.amountMinor),
      ]),
    );
  }
}
