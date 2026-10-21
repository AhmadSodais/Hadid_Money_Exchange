import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/domain/accounting/account.dart';
import 'package:hadid_exchange/domain/accounting/journal.dart';
import 'package:hadid_exchange/domain/accounting/posting_rules.dart';
import 'package:hadid_exchange/domain/errors/domain_errors.dart';
import 'package:hadid_exchange/domain/money/currency.dart';
import 'package:hadid_exchange/domain/money/decimal.dart';
import 'package:hadid_exchange/domain/shared/business_date.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';

void main() {
  final rules = PostingRules(
    {for (final c in SeedCurrencies.all) c.code: c},
    walkInCustomerId: 1,
  );
  final date = BusinessDate(2026, 10, 5);
  const cash = CashAccountRef(1);
  const position = SystemAccountRef(AccountRole.exchangePosition);

  Map<String, int> netBy(JournalDraft j, AccountRef acc) {
    final out = <String, int>{};
    for (final l in j.lines.where((l) => l.account == acc)) {
      out.update(l.currency, (v) => v + l.net, ifAbsent: () => l.net);
    }
    return out;
  }

  group('JournalDraft invariants', () {
    test('balanced per currency passes', () {
      JournalDraft([
        JournalLineDraft.debit(cash, 'USD', 100),
        JournalLineDraft.credit(position, 'USD', 100),
      ]).validate();
    });

    test('cross-currency "balance" by nominal numbers is rejected', () {
      expect(
        () => JournalDraft([
          JournalLineDraft.debit(cash, 'USD', 100),
          JournalLineDraft.credit(cash, 'AFN', 100),
        ]).validate(),
        throwsA(isA<InvariantViolation>().having((e) => e.code, 'code', 'journal.unbalanced')),
      );
    });

    test('zero, negative, or two-sided lines are rejected', () {
      for (final bad in [
        const JournalLineDraft(account: cash, currency: 'AFN'),
        const JournalLineDraft(account: cash, currency: 'AFN', debitMinor: -5),
        const JournalLineDraft(account: cash, currency: 'AFN', debitMinor: 5, creditMinor: 5),
      ]) {
        expect(
            () => JournalDraft([bad, JournalLineDraft.credit(position, 'AFN', 5)]).validate(),
            throwsA(isA<InvariantViolation>()));
      }
    });

    test('reversed journal mirrors every line and nets to zero', () {
      final j = JournalDraft([
        JournalLineDraft.debit(cash, 'USD', 100),
        JournalLineDraft.credit(position, 'USD', 100),
      ]);
      final r = j.reversed();
      r.validate();
      for (var i = 0; i < j.lines.length; i++) {
        expect(j.lines[i].net + r.lines[i].net, 0);
      }
    });
  });

  group('Posting rules', () {
    test('receipt: Dr cash / Cr customer', () {
      final p = rules.plan(ReceiptCommand(
          idempotencyKey: 'k',
          effectiveDate: date,
          customerId: 7,
          drawerId: 1,
          currency: 'AFN',
          amountMinor: 100000));
      expect(netBy(p.journal, cash), {'AFN': 100000});
      expect(netBy(p.journal, const CustomerAccountRef(7)), {'AFN': -100000});
    });

    test('payment: Dr customer / Cr cash', () {
      final p = rules.plan(PaymentCommand(
          idempotencyKey: 'k',
          effectiveDate: date,
          customerId: 7,
          drawerId: 1,
          currency: 'AFN',
          amountMinor: 20000));
      expect(netBy(p.journal, cash), {'AFN': -20000});
      expect(netBy(p.journal, const CustomerAccountRef(7)), {'AFN': 20000});
    });

    test('receipt/payment with walk-in customer is rejected', () {
      expect(
          () => rules.plan(ReceiptCommand(
              idempotencyKey: 'k',
              effectiveDate: date,
              customerId: 1,
              drawerId: 1,
              currency: 'AFN',
              amountMinor: 1)),
          throwsA(isA<BusinessRuleError>()));
    });

    test('buy 100 USD at 70: USD cash +100, AFN cash −7,000, each currency balanced', () {
      final p = rules.plan(ExchangeCommand(
        idempotencyKey: 'k',
        effectiveDate: date,
        direction: ExchangeDirection.buy,
        customerId: 1,
        drawerId: 1,
        baseCurrency: 'USD',
        quoteCurrency: 'AFN',
        baseAmountMinor: 10000,
        rate: Decimal.parse('70'),
      ));
      expect(p.quoteAmountMinor, 700000);
      expect(netBy(p.journal, cash), {'USD': 10000, 'AFN': -700000});
      expect(netBy(p.journal, position), {'USD': -10000, 'AFN': 700000});
    });

    test('sell 100 USD at 71: USD cash −100, AFN cash +7,100', () {
      final p = rules.plan(ExchangeCommand(
        idempotencyKey: 'k',
        effectiveDate: date,
        direction: ExchangeDirection.sell,
        customerId: 1,
        drawerId: 1,
        baseCurrency: 'USD',
        quoteCurrency: 'AFN',
        baseAmountMinor: 10000,
        rate: Decimal.parse('71'),
      ));
      expect(netBy(p.journal, cash), {'USD': -10000, 'AFN': 710000});
    });

    test('exchange settled through the customer account', () {
      final p = rules.plan(ExchangeCommand(
        idempotencyKey: 'k',
        effectiveDate: date,
        direction: ExchangeDirection.buy,
        customerId: 9,
        drawerId: 1,
        baseCurrency: 'USD',
        quoteCurrency: 'AFN',
        baseAmountMinor: 10000,
        rate: Decimal.parse('70'),
        quoteSettlement: Settlement.customer,
      ));
      expect(netBy(p.journal, cash), {'USD': 10000});
      expect(netBy(p.journal, const CustomerAccountRef(9)), {'AFN': -700000});
    });

    test('walk-in customer cannot settle through an account', () {
      expect(
        () => rules.plan(ExchangeCommand(
          idempotencyKey: 'k',
          effectiveDate: date,
          direction: ExchangeDirection.buy,
          customerId: 1,
          drawerId: 1,
          baseCurrency: 'USD',
          quoteCurrency: 'AFN',
          baseAmountMinor: 10000,
          rate: Decimal.parse('70'),
          quoteSettlement: Settlement.customer,
        )),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    test('fee posts to fee revenue in its own currency', () {
      final p = rules.plan(ExchangeCommand(
        idempotencyKey: 'k',
        effectiveDate: date,
        direction: ExchangeDirection.buy,
        customerId: 1,
        drawerId: 1,
        baseCurrency: 'USD',
        quoteCurrency: 'AFN',
        baseAmountMinor: 10000,
        rate: Decimal.parse('70'),
        fee: const ExchangeFee(currency: 'AFN', amountMinor: 5000),
      ));
      expect(netBy(p.journal, const SystemAccountRef(AccountRole.feeRevenue)), {'AFN': -5000});
      expect(netBy(p.journal, cash), {'USD': 10000, 'AFN': -695000});
    });

    test('opening customer balance: posts against vault cash, never initial capital', () {
      // Debt (customer owes the exchange): funds paid out of the vault —
      // Dr customer / Cr cash; account 3100 is untouched.
      final owes = rules.plan(OpeningCustomerCommand(
          idempotencyKey: 'k',
          effectiveDate: date,
          customerId: 5,
          currency: 'AFN',
          signedMinor: -80000,
          drawerId: 1));
      expect(netBy(owes.journal, const CustomerAccountRef(5)), {'AFN': 80000}); // debit
      expect(netBy(owes.journal, cash), {'AFN': -80000});
      expect(netBy(owes.journal, const SystemAccountRef(AccountRole.openingEquity)), isEmpty);
      // Liability (exchange owes the customer): the customer's funds in the
      // vault — Dr cash / Cr customer; initial capital is untouched.
      final owed = rules.plan(OpeningCustomerCommand(
          idempotencyKey: 'k',
          effectiveDate: date,
          customerId: 5,
          currency: 'AFN',
          signedMinor: 80000,
          drawerId: 1));
      expect(netBy(owed.journal, const CustomerAccountRef(5)), {'AFN': -80000}); // credit
      expect(netBy(owed.journal, cash), {'AFN': 80000});
      expect(netBy(owed.journal, const SystemAccountRef(AccountRole.openingEquity)), isEmpty);
      // A drawer is always required: an opening balance is the customer's
      // share of one specific vault.
      expect(
          () => rules.plan(OpeningCustomerCommand(
              idempotencyKey: 'k',
              effectiveDate: date,
              customerId: 5,
              currency: 'AFN',
              signedMinor: 80000)),
          throwsA(isA<ValidationError>()));
      expect(
          () => rules.plan(OpeningCustomerCommand(
              idempotencyKey: 'k',
              effectiveDate: date,
              customerId: 5,
              currency: 'AFN',
              signedMinor: -80000)),
          throwsA(isA<ValidationError>()));
    });

    test('adjustments require a reason; zero amounts rejected', () {
      expect(
          () => rules.plan(CashAdjustmentCommand(
              idempotencyKey: 'k',
              effectiveDate: date,
              drawerId: 1,
              currency: 'AFN',
              signedMinor: 100,
              reason: ' ')),
          throwsA(isA<ValidationError>()));
      expect(
          () => rules.plan(CashAdjustmentCommand(
              idempotencyKey: 'k',
              effectiveDate: date,
              drawerId: 1,
              currency: 'AFN',
              signedMinor: 0,
              reason: 'x')),
          throwsA(isA<ValidationError>()));
    });

    test('unknown currency and non-positive amounts rejected', () {
      expect(
          () => rules.plan(ReceiptCommand(
              idempotencyKey: 'k',
              effectiveDate: date,
              customerId: 7,
              drawerId: 1,
              currency: 'GBP',
              amountMinor: 1)),
          throwsA(isA<ValidationError>()));
      expect(
          () => rules.plan(ReceiptCommand(
              idempotencyKey: 'k',
              effectiveDate: date,
              customerId: 7,
              drawerId: 1,
              currency: 'AFN',
              amountMinor: 0)),
          throwsA(isA<ValidationError>()));
    });
  });

  group('BusinessDate', () {
    test('validates calendar dates and sorts lexically', () {
      expect(() => BusinessDate(2026, 2, 30), throwsA(isA<ValidationError>()));
      expect(BusinessDate(2024, 2, 29).iso, '2024-02-29');
      expect(BusinessDate.parse('2026-10-05').isBefore(BusinessDate.parse('2026-10-10')), isTrue);
      expect(BusinessDate(2026, 12, 31).addDays(1).iso, '2027-01-01');
    });
  });
}
