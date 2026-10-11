import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/application/customer_service.dart';
import 'package:hadid_exchange/application/ledger_queries.dart';
import 'package:hadid_exchange/domain/errors/domain_errors.dart';
import 'package:hadid_exchange/domain/money/currency.dart';
import 'package:hadid_exchange/domain/money/decimal.dart';
import 'package:hadid_exchange/domain/security/permissions.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/harness.dart';

void main() {
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  group('Atomicity and rollback', () {
    test('failure after the transaction row is inserted leaves nothing behind', () async {
      await h.openingCash('USD', usd(1000));
      final txBefore = await h.count('transactions');
      final linesBefore = await h.count('journal_lines');
      // Deactivate the position account so resolving it fails mid-transaction.
      await h.app.db.rawUpdate("UPDATE accounts SET is_active = 0 WHERE role = 'exchangePosition'");
      await expectLater(
        h.exchange(
            direction: ExchangeDirection.buy, base: 'USD', quote: 'AFN', baseMinor: usd(1), rate: '70'),
        throwsA(isA<BusinessRuleError>()),
      );
      expect(await h.count('transactions'), txBefore);
      expect(await h.count('journal_lines'), linesBefore);
      expect(await h.count('journal_entries'), txBefore);
      final failures = await h.app.db
          .rawQuery("SELECT COUNT(*) AS n FROM audit_logs WHERE outcome = 'failure'");
      expect(failures.first['n'], 1);
    });

    test('every ordered pair posts a balanced buy and sell atomically', () async {
      for (final c in SeedCurrencies.all) {
        await h.openingCash(c.code, Decimal.fromInt(1000000).toMinor(c.precision));
      }
      var expectedTx = await h.count('transactions');
      for (final base in SeedCurrencies.all) {
        for (final quote in SeedCurrencies.all) {
          if (base == quote) continue;
          final before = await h.app.queries.cashBalances();
          final buy = await h.exchange(
              direction: ExchangeDirection.buy,
              base: base.code,
              quote: quote.code,
              baseMinor: Decimal.fromInt(10).toMinor(base.precision),
              rate: '2');
          final sell = await h.exchange(
              direction: ExchangeDirection.sell,
              base: base.code,
              quote: quote.code,
              baseMinor: Decimal.fromInt(10).toMinor(base.precision),
              rate: '3');
          expectedTx += 2;
          expect(buy.lines, hasLength(4));
          expect(sell.lines, hasLength(4));
          final after = await h.app.queries.cashBalances();
          // Net: base unchanged; quote +10 (received 30, paid 20).
          expect(after[base.code], before[base.code], reason: '${base.code}/${quote.code}');
          expect(after[quote.code]! - before[quote.code]!,
              Decimal.fromInt(10).toMinor(quote.precision));
        }
      }
      expect(await h.count('transactions'), expectedTx);
      expect(await h.app.queries.integrityProblems(), isEmpty);
    });
  });

  group('Idempotency and duplicates', () {
    test('re-submitting the same key returns the same transaction', () async {
      final k = await h.customer('Ali');
      final cmd = ReceiptCommand(
        idempotencyKey: 'form-123',
        effectiveDate: Harness.d('2026-10-06'),
        customerId: k.id,
        drawerId: 1,
        currency: 'AFN',
        amountMinor: afn(500),
      );
      final a = await h.app.posting.post(cmd, h.owner);
      final b = await h.app.posting.post(cmd, h.owner);
      final results = await Future.wait([
        h.app.posting.post(cmd, h.owner),
        h.app.posting.post(cmd, h.owner),
      ]);
      expect(b.id, a.id);
      expect(results.map((r) => r.id).toSet(), {a.id});
      expect(await h.count('transactions'), 1);
    });

    test('opening capital can be posted only once per drawer and currency', () async {
      await h.openingCash('AFN', afn(100000));
      await expectLater(h.openingCash('AFN', afn(5)),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'opening.duplicate')));
      expect(await h.app.queries.cashBalance('AFN'), afn(100000));
    });

    test('a reversed opening balance can be re-entered', () async {
      final first = await h.openingCash('AFN', afn(100));
      await h.reverse(first.id);
      await h.openingCash('AFN', afn(150));
      expect(await h.app.queries.cashBalance('AFN'), afn(150));
    });
  });

  group('Immutability', () {
    test('posted journal lines and transactions cannot be edited or deleted', () async {
      final t = await h.openingCash('AFN', afn(100));
      Future<void> fails(String sql) =>
          expectLater(h.app.db.execute(sql), throwsA(isA<DatabaseException>()));
      await fails('UPDATE journal_lines SET debit_minor = 1');
      await fails('DELETE FROM journal_lines');
      await fails('UPDATE journal_entries SET effective_date = \'2020-01-01\'');
      await fails('DELETE FROM transactions');
      await fails('UPDATE transactions SET source_amount_minor = 5 WHERE id = ${t.id}');
      await fails("UPDATE transactions SET status = 'reversed' WHERE id = ${t.id}");
      await fails('DELETE FROM audit_logs');
      await fails('DELETE FROM customers');
    });

    test('a transaction can be reversed only once and reversals cannot be reversed', () async {
      final t = await h.openingCash('AFN', afn(100));
      final r = await h.reverse(t.id);
      await expectLater(h.reverse(t.id),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'reversal.repeated')));
      await expectLater(h.reverse(r.id),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'reversal.ofReversal')));
    });

    test('reversing a multi-leg exchange reverses every currency leg', () async {
      await h.openingCash('AFN', afn(10000));
      await h.openingCash('USD', usd(100));
      final before = await h.app.queries.cashBalances();
      final t = await h.exchange(
          direction: ExchangeDirection.buy,
          base: 'USD',
          quote: 'AFN',
          baseMinor: usd(10),
          rate: '70',
          fee: const ExchangeFee(currency: 'AFN', amountMinor: 1000));
      await h.reverse(t.id);
      expect(await h.app.queries.cashBalances(), before);
      final position = await h.app.queries.exchangePosition();
      expect(position.values.every((v) => v == 0), isTrue);
    });
  });

  group('Validation and policy', () {
    test('future dates and dates beyond the backdating window are rejected', () async {
      final k = await h.customer('Ali');
      await expectLater(h.receipt(k.id, 'AFN', 100, date: '2026-10-12'),
          throwsA(isA<ValidationError>().having((e) => e.code, 'code', 'date.future')));
      await expectLater(h.receipt(k.id, 'AFN', 100, date: '2026-08-01'),
          throwsA(isA<ValidationError>().having((e) => e.code, 'code', 'date.tooOld')));
      expect(await h.count('transactions'), 0);
    });

    test('cash may not go negative, including on later dates for backdated outflows', () async {
      final k = await h.customer('Ali');
      await h.openingCash('AFN', afn(100), date: '2026-10-01');
      await expectLater(h.payment(k.id, 'AFN', afn(101), date: '2026-10-02'),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'cash.insufficient')));
      await h.payment(k.id, 'AFN', afn(80), date: '2026-10-05');
      // 10-03 itself would still be 40, but 10-05 would become −40.
      await expectLater(h.payment(k.id, 'AFN', afn(60), date: '2026-10-03'),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'cash.insufficient')));
      await h.payment(k.id, 'AFN', afn(20), date: '2026-10-03');
      expect(await h.app.queries.cashBalance('AFN'), 0);
    });

    test('inactive customers cannot transact; history is preserved', () async {
      final k = await h.customer('Ali');
      await h.receipt(k.id, 'AFN', afn(10));
      await h.app.customers.setActive(k.id, false, h.owner);
      await expectLater(h.receipt(k.id, 'AFN', afn(10)),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'customer.inactive')));
      final balances = await h.app.queries.customerBalances(k.id);
      expect(balances.single.positionMinor, afn(10));
    });

    test('actors without permission are refused', () async {
      final cashier = Actor(
          userId: 1,
          displayName: 'cashier',
          permissions: Permissions.roleDefaults['cashier']!.toSet());
      final t = await h.openingCash('AFN', afn(100));
      await expectLater(
          h.app.posting.reverse(
              transactionId: t.id, reason: 'x', actor: cashier, idempotencyKey: 'r1'),
          throwsA(isA<AuthorizationError>()));
      await expectLater(
          h.app.posting.post(
              CashAdjustmentCommand(
                  idempotencyKey: 'a1',
                  effectiveDate: Harness.d('2026-10-05'),
                  drawerId: 1,
                  currency: 'AFN',
                  signedMinor: 5,
                  reason: 'x'),
              cashier),
          throwsA(isA<AuthorizationError>()));
    });

    test('foreign keys are enforced', () async {
      await expectLater(
        h.app.db.insert('journal_lines', {
          'journal_entry_id': 999,
          'line_no': 1,
          'account_id': 999,
          'currency_code': 'AFN',
          'debit_minor': 1,
          'effective_date': '2026-10-01',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('Customers', () {
    test('per-currency balances, statement filters, opening and closing', () async {
      final k = await h.customer('Ali');
      await h.receipt(k.id, 'AFN', afn(1000), date: '2026-10-02');
      await h.receipt(k.id, 'USD', usd(50), date: '2026-10-03');
      await h.payment(k.id, 'AFN', afn(300), date: '2026-10-04');
      await h.exchange(
          direction: ExchangeDirection.sell,
          base: 'USD',
          quote: 'AFN',
          baseMinor: usd(10),
          rate: '70',
          customerId: k.id,
          baseSettlement: Settlement.cash,
          quoteSettlement: Settlement.customer,
          date: '2026-10-05');

      final balances = {
        for (final b in await h.app.queries.customerBalances(k.id)) b.currency: b.positionMinor
      };
      // AFN: +1000 −300 −700 (sale paid from the customer's AFN account) = 0
      expect(balances, {'AFN': 0, 'USD': usd(50)});

      final st = await h.app.queries.customerStatement(k, 'AFN',
          from: Harness.d('2026-10-03'), to: Harness.d('2026-10-05'));
      expect(st.openingPositionMinor, afn(1000));
      expect(st.lines, hasLength(2));
      expect(st.closingPositionMinor, 0);

      final onlyPayments = await h.app.queries
          .customerStatement(k, 'AFN', types: {TransactionType.payment});
      expect(onlyPayments.lines.single.debitMinor, afn(300));

      final totals = await h.app.queries.customerTotals();
      expect(totals['USD']!.liabilities, usd(50));
    });

    test('search by name, phone, code; walk-in excluded by default', () async {
      await h.app.customers
          .create(const CustomerInput(name: 'Ahmad Shah', phone: '0700 123 456'), h.owner);
      expect((await h.app.customers.search('ahmad')).single.name, 'Ahmad Shah');
      expect((await h.app.customers.search('۰۷۰۰')).single.name, 'Ahmad Shah');
      expect((await h.app.customers.search('C-0000')), hasLength(1));
      expect(await h.app.customers.search('متفرقه'), isEmpty);
      expect(await h.app.customers.search('متفرقه', includeWalkIn: true), hasLength(1));
    });

    test('anonymize requires zero balance and keeps ledger history', () async {
      final k = await h.customer('Ali');
      await h.receipt(k.id, 'AFN', afn(10));
      await expectLater(h.app.customers.anonymize(k.id, h.owner, reason: 'request'),
          throwsA(isA<BusinessRuleError>()));
      await h.payment(k.id, 'AFN', afn(10));
      await h.app.customers.anonymize(k.id, h.owner, reason: 'request');
      final rec = (await h.app.customers.byId(k.id))!;
      expect(rec.status, 'anonymized');
      expect(rec.phone, isNull);
      final journal = await h.app.queries.journal(JournalFilter(customerId: k.id));
      expect(journal, hasLength(2));
    });
  });

  group('Journal search', () {
    test('filters compose instead of overriding each other', () async {
      final a = await h.customer('Ali');
      final b = await h.customer('Bashir');
      await h.receipt(a.id, 'AFN', afn(100), date: '2026-10-02');
      await h.receipt(a.id, 'USD', usd(5), date: '2026-10-03');
      await h.receipt(b.id, 'AFN', afn(100), date: '2026-10-03');
      await h.payment(a.id, 'AFN', afn(40), date: '2026-10-04');

      Future<int> n(JournalFilter f) => h.app.queries.journalCount(f);
      expect(await n(JournalFilter(customerId: a.id)), 3);
      expect(await n(JournalFilter(customerId: a.id, currency: 'AFN')), 2);
      expect(
          await n(JournalFilter(
              customerId: a.id,
              currency: 'AFN',
              from: Harness.d('2026-10-03'),
              to: Harness.d('2026-10-04'))),
          1);
      expect(await n(const JournalFilter(text: 'Bashir')), 1);
      expect(await n(const JournalFilter(text: 'PAY-')), 1);
      expect(
          await n(JournalFilter(currency: 'AFN', minAmountMinor: afn(50))), 2);
      expect(await n(const JournalFilter(types: {TransactionType.payment})), 1);
    });
  });
}
