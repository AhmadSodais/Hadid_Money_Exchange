import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/application/ledger_queries.dart';
import 'package:hadid_exchange/application/posting_service.dart';
import 'package:hadid_exchange/application/read_models.dart';
import 'package:hadid_exchange/domain/errors/domain_errors.dart';
import 'package:hadid_exchange/domain/money/decimal.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';

import '../support/harness.dart';

void main() {
  late Harness h;
  late int k;

  setUp(() async {
    h = await Harness.create();
    await h.openingCash('AFN', afn(1000), date: '2026-10-01');
    await h.openingCash('USD', usd(100), date: '2026-10-01');
    k = (await h.customer('Ali')).id;
  });
  tearDown(() => h.dispose());

  Future<int> position(String cur) async {
    for (final b in await h.app.queries.customerBalances(k)) {
      if (b.currency == cur) return b.positionMinor;
    }
    return 0;
  }

  ReceiptCommand receiptCmd(int minor, {String date = '2026-10-02', int? customerId}) =>
      ReceiptCommand(
        idempotencyKey: h.key(),
        effectiveDate: Harness.d(date),
        customerId: customerId ?? k,
        drawerId: 1,
        currency: 'AFN',
        amountMinor: minor,
      );

  Future<PostedTransaction> edit(int id, FinancialCommand replacement) => h.app.posting.correct(
        transactionId: id,
        replacement: replacement,
        reason: 'typo',
        actor: h.owner,
      );

  Future<PostedTransaction> delete(int id) => h.app.posting.delete(
        transactionId: id,
        reason: 'entered by mistake',
        actor: h.owner,
        idempotencyKey: PostingService.newIdempotencyKey(),
      );

  group('Delete', () {
    test('neutralizes the transaction on its own date and keeps the history', () async {
      final tx = await h.receipt(k, 'AFN', afn(200), date: '2026-10-02');
      final rev = await delete(tx.id);

      expect(rev.effectiveDate, Harness.d('2026-10-02'), reason: 'dated on the original day');
      expect(await h.app.queries.cashBalance('AFN'), afn(1000));
      expect(await position('AFN'), 0);
      final day = await h.app.reconciliation.compute(1, 'AFN', Harness.d('2026-10-02'));
      expect(day.expectedMinor, afn(1000));

      final original = (await h.app.posting.transactionById(tx.id))!;
      expect(original.status, TransactionStatus.reversed);
      expect(original.wasEdited, isFalse);
      final active = await h.app.queries.journal(const JournalFilter(activeOnly: true));
      expect(active.map((t) => t.id), isNot(contains(tx.id)));
      expect(active.where((t) => t.type == TransactionType.reversal), isEmpty);
      expect(await h.app.queries.integrityProblems(), isEmpty);
    });

    test('is refused when it would make cash negative on a later day', () async {
      final tx = await h.receipt(k, 'AFN', afn(500), date: '2026-10-02');
      await h.payment(k, 'AFN', afn(1500), date: '2026-10-03');
      await expectLater(delete(tx.id),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'cash.insufficient')));
      expect((await h.app.posting.transactionById(tx.id))!.status, TransactionStatus.posted);
    });

    test('is refused on a closed day', () async {
      final tx = await h.receipt(k, 'AFN', afn(200), date: '2026-10-02');
      final rec = await h.app.reconciliation.saveCount(
          drawerId: 1, currency: 'AFN', date: Harness.d('2026-10-02'), countedMinor: afn(1200), actor: h.owner);
      await h.app.reconciliation.close(rec.id, h.owner);
      await expectLater(delete(tx.id),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'day.closed')));
    });
  });

  group('Edit', () {
    test('changes the amount atomically and links old and new versions', () async {
      final tx = await h.receipt(k, 'AFN', afn(200), date: '2026-10-02');
      final txBefore = await h.count('transactions');
      final fixed = await edit(tx.id, receiptCmd(afn(250)));

      expect(fixed.sourceAmountMinor, afn(250));
      expect(fixed.replacesTransactionId, tx.id);
      expect(await h.count('transactions'), txBefore + 2, reason: 'one reversal + one replacement');
      expect(await h.app.queries.cashBalance('AFN'), afn(1250));
      expect(await position('AFN'), afn(250));
      final day = await h.app.reconciliation.compute(1, 'AFN', Harness.d('2026-10-02'));
      expect(day.expectedMinor, afn(1250));

      final original = (await h.app.posting.transactionById(tx.id))!;
      expect(original.wasEdited, isTrue);
      expect(original.replacedByTransactionId, fixed.id);
      final active = await h.app.queries.journal(const JournalFilter(activeOnly: true));
      expect(active.where((t) => t.customerId == k).map((t) => t.id), [fixed.id]);
      expect(await h.app.queries.integrityProblems(), isEmpty);
    });

    test('is judged by its net effect: increasing an inflow works when cash was spent', () async {
      final tx = await h.receipt(k, 'AFN', afn(500), date: '2026-10-02');
      await h.payment(k, 'AFN', afn(1500), date: '2026-10-03');
      // Reversing 500 alone would make 10-03 negative; +600 instead is fine.
      final fixed = await edit(tx.id, receiptCmd(afn(600)));
      expect(await h.app.queries.cashBalance('AFN'), afn(100));

      final txCount = await h.count('transactions');
      final lines = await h.count('journal_lines');
      await expectLater(edit(fixed.id, receiptCmd(afn(400))),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'cash.insufficient')));
      expect(await h.count('transactions'), txCount, reason: 'nothing half-applied');
      expect(await h.count('journal_lines'), lines);
      expect(await h.count('transaction_corrections'), 1);
      expect((await h.app.posting.transactionById(fixed.id))!.status, TransactionStatus.posted);
    });

    test('can move the date and change customer; both days are recomputed', () async {
      final tx = await h.receipt(k, 'AFN', afn(200), date: '2026-10-02');
      final other = (await h.customer('Reza')).id;
      await edit(tx.id, receiptCmd(afn(200), date: '2026-10-04', customerId: other));

      expect(await position('AFN'), 0);
      final d2 = await h.app.reconciliation.compute(1, 'AFN', Harness.d('2026-10-02'));
      final d4 = await h.app.reconciliation.compute(1, 'AFN', Harness.d('2026-10-04'));
      expect(d2.expectedMinor, afn(1000));
      expect(d4.inflowMinor, afn(200));
      expect(d4.expectedMinor, afn(1200));
    });

    test('receipt may become payment, but not an expense', () async {
      final tx = await h.receipt(k, 'AFN', afn(200), date: '2026-10-02');
      await expectLater(
          edit(
              tx.id,
              ExpenseCommand(
                  idempotencyKey: h.key(),
                  effectiveDate: Harness.d('2026-10-02'),
                  description: 'rent',
                  drawerId: 1,
                  currency: 'AFN',
                  amountMinor: afn(200))),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'correction.typeNotAllowed')));
      await edit(
          tx.id,
          PaymentCommand(
              idempotencyKey: h.key(),
              effectiveDate: Harness.d('2026-10-02'),
              customerId: k,
              drawerId: 1,
              currency: 'AFN',
              amountMinor: afn(200)));
      expect(await position('AFN'), -afn(200));
      expect(await h.app.queries.cashBalance('AFN'), afn(800));
    });

    test('buy can be edited into a sell at another rate (every leg replaced)', () async {
      final buy = await h.exchange(
          direction: ExchangeDirection.buy, base: 'USD', quote: 'AFN', baseMinor: usd(10), rate: '70');
      expect(await h.app.queries.cashBalance('USD'), usd(110));
      await edit(
          buy.id,
          ExchangeCommand(
            idempotencyKey: h.key(),
            effectiveDate: Harness.d('2026-10-05'),
            direction: ExchangeDirection.sell,
            customerId: await h.walkInId(),
            drawerId: 1,
            baseCurrency: 'USD',
            quoteCurrency: 'AFN',
            baseAmountMinor: usd(10),
            rate: Decimal.parse('71'),
          ));
      expect(await h.app.queries.cashBalance('USD'), usd(90));
      expect(await h.app.queries.cashBalance('AFN'), afn(1000 + 710));
      expect(await h.app.queries.integrityProblems(), isEmpty);
    });

    test('opening cash can be edited (the one-per-currency rule still holds)', () async {
      final opening = (await h.app.queries.journal(
              const JournalFilter(types: {TransactionType.openingCash}, currency: 'AFN')))
          .single;
      await edit(
          opening.id,
          OpeningCashCommand(
              idempotencyKey: h.key(),
              effectiveDate: Harness.d('2026-10-01'),
              drawerId: 1,
              currency: 'AFN',
              amountMinor: afn(1500)));
      expect(await h.app.queries.cashBalance('AFN'), afn(1500));
      await expectLater(h.openingCash('AFN', afn(1)),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'opening.duplicate')));
    });

    test('resubmitting the same edit does not edit twice', () async {
      final tx = await h.receipt(k, 'AFN', afn(200), date: '2026-10-02');
      final cmd = receiptCmd(afn(300));
      final first = await edit(tx.id, cmd);
      final second = await edit(tx.id, cmd);
      expect(second.id, first.id);
      expect(await h.count('transaction_corrections'), 1);
      expect(await position('AFN'), afn(300));
    });

    test('an already edited or deleted original cannot be edited again', () async {
      final tx = await h.receipt(k, 'AFN', afn(200), date: '2026-10-02');
      await edit(tx.id, receiptCmd(afn(300)));
      await expectLater(edit(tx.id, receiptCmd(afn(400))),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'reversal.repeated')));
    });

    test('is refused when either the old or the new day is closed', () async {
      final tx = await h.receipt(k, 'AFN', afn(200), date: '2026-10-04');
      final rec = await h.app.reconciliation.saveCount(
          drawerId: 1, currency: 'AFN', date: Harness.d('2026-10-03'), countedMinor: afn(1000), actor: h.owner);
      await h.app.reconciliation.close(rec.id, h.owner);
      await expectLater(edit(tx.id, receiptCmd(afn(200), date: '2026-10-03')),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'day.closed')));
      expect((await h.app.posting.transactionById(tx.id))!.status, TransactionStatus.posted);
    });

    test('a transaction older than the backdating window cannot be edited', () async {
      await h.app.db.rawUpdate(
          "UPDATE application_settings SET value = '0' WHERE key = 'posting.max_backdate_days'");
      final old = await h.receipt(k, 'AFN', afn(10), date: '2026-08-01');
      await h.app.db.rawUpdate(
          "UPDATE application_settings SET value = '31' WHERE key = 'posting.max_backdate_days'");
      await expectLater(edit(old.id, receiptCmd(afn(20))),
          throwsA(isA<ValidationError>().having((e) => e.code, 'code', 'date.tooOld')));
    });
  });

  group('Daily balance', () {
    final from = Harness.d('2026-10-01');
    final to = Harness.d('2026-10-10');

    test('days with cash movement but no count are listed until a balance is added', () async {
      await h.receipt(k, 'AFN', afn(10), date: '2026-10-03');
      await h.receipt(k, 'USD', usd(1), date: '2026-10-03');
      final missing = await h.app.reconciliation.missingCounts(1, from: from, to: to);
      expect(missing.map((m) => '${m.date.iso} ${m.currency}'),
          containsAll(['2026-10-03 AFN', '2026-10-03 USD', '2026-10-01 AFN']));

      await h.app.reconciliation.saveCount(
          drawerId: 1, currency: 'AFN', date: Harness.d('2026-10-03'), countedMinor: afn(1010), actor: h.owner);
      final after = await h.app.reconciliation.missingCounts(1, from: from, to: to);
      expect(after.map((m) => '${m.date.iso} ${m.currency}'), isNot(contains('2026-10-03 AFN')));
      expect(after.map((m) => '${m.date.iso} ${m.currency}'), contains('2026-10-03 USD'));
    });

    test('a transaction deleted on its own day does not make that day missing', () async {
      final tx = await h.receipt(k, 'AFN', afn(10), date: '2026-10-04');
      await delete(tx.id);
      final missing = await h.app.reconciliation.missingCounts(1, from: from, to: to);
      expect(missing.where((m) => m.date.iso == '2026-10-04'), isEmpty);
    });

    test('a mistaken open count can be removed and re-entered; a closed one cannot', () async {
      final date = Harness.d('2026-10-02');
      final rec = await h.app.reconciliation.saveCount(
          drawerId: 1, currency: 'AFN', date: date, countedMinor: afn(5), actor: h.owner);
      await h.app.reconciliation.voidCount(rec.id, 'wrong currency', h.owner);
      expect(await h.app.reconciliation.active(1, 'AFN', date), isNull);

      final again = await h.app.reconciliation.saveCount(
          drawerId: 1, currency: 'AFN', date: date, countedMinor: afn(1000), actor: h.owner);
      await h.app.reconciliation.close(again.id, h.owner);
      await expectLater(h.app.reconciliation.voidCount(again.id, 'x', h.owner),
          throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'reconciliation.closed')));
    });
  });
}
