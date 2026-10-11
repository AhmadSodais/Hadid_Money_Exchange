import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/domain/errors/domain_errors.dart';
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

  final rec = () => h.app.reconciliation;

  test('normal daily close with no difference', () async {
    await h.receipt(k, 'AFN', afn(200), date: '2026-10-02');
    await h.payment(k, 'AFN', afn(50), date: '2026-10-02');
    final snap = await rec().compute(1, 'AFN', Harness.d('2026-10-02'));
    expect(snap.openingMinor, afn(1000));
    expect(snap.inflowMinor, afn(200));
    expect(snap.outflowMinor, afn(50));
    expect(snap.expectedMinor, afn(1150));

    final r = await rec().saveCount(
        drawerId: 1, currency: 'AFN', date: Harness.d('2026-10-02'), countedMinor: afn(1150), actor: h.owner);
    expect(r.differenceMinor, 0);
    final closed = await rec().close(r.id, h.owner);
    expect(closed.status, 'closed');
  });

  test('shortage is kept as a result and corrected only by an adjustment', () async {
    final date = Harness.d('2026-10-02');
    final r = await rec().saveCount(
        drawerId: 1, currency: 'AFN', date: date, countedMinor: afn(990), actor: h.owner);
    expect(r.differenceMinor, -afn(10));
    // Count does not change the ledger.
    expect(await h.app.queries.cashBalance('AFN'), afn(1000));

    final adjusted = await rec().postAdjustment(r.id, 'missing note', h.owner);
    expect(adjusted.adjustmentTransactionId, isNotNull);
    expect(await h.app.queries.cashBalance('AFN'), afn(990));
    final closed = await rec().close(r.id, h.owner);
    expect(closed.differenceMinor, -afn(10), reason: 'discrepancy remains on record');
  });

  test('surplus posts to cash over/short', () async {
    final r = await rec().saveCount(
        drawerId: 1, currency: 'USD', date: Harness.d('2026-10-02'), countedMinor: usd(105), actor: h.owner);
    expect(r.differenceMinor, usd(5));
    await rec().postAdjustment(r.id, 'extra found', h.owner);
    expect(await h.app.queries.cashBalance('USD'), usd(105));
    final tb = await h.app.queries.trialBalance();
    final overShort = tb.firstWhere((t) => t.accountCode == '5200' && t.currency == 'USD');
    expect(overShort.creditMinor, usd(5));
  });

  test('close is refused when transactions changed after the count', () async {
    final date = Harness.d('2026-10-03');
    final r = await rec().saveCount(
        drawerId: 1, currency: 'AFN', date: date, countedMinor: afn(1000), actor: h.owner);
    await h.receipt(k, 'AFN', afn(5), date: '2026-10-03');
    await expectLater(rec().close(r.id, h.owner),
        throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'reconciliation.stale')));
    final recount = await rec().saveCount(
        drawerId: 1, currency: 'AFN', date: date, countedMinor: afn(1005), actor: h.owner);
    expect(recount.id, r.id, reason: 'no duplicate record for the same scope');
    await rec().close(r.id, h.owner);
  });

  test('closed day locks backdating per currency; other currencies unaffected', () async {
    final r = await rec().saveCount(
        drawerId: 1, currency: 'AFN', date: Harness.d('2026-10-04'), countedMinor: afn(1000), actor: h.owner);
    await rec().close(r.id, h.owner);

    await expectLater(h.receipt(k, 'AFN', afn(1), date: '2026-10-03'),
        throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'day.closed')));
    // USD has a different (no) latest reconciliation date.
    await h.receipt(k, 'USD', usd(1), date: '2026-10-03');
    // After the closed date AFN is open again.
    await h.receipt(k, 'AFN', afn(1), date: '2026-10-05');
    // An exchange touching closed AFN cash on 10-04 is also refused as a whole.
    await expectLater(
        h.exchange(
            direction: ExchangeDirection.buy,
            base: 'USD',
            quote: 'AFN',
            baseMinor: usd(1),
            rate: '70',
            date: '2026-10-04'),
        throwsA(isA<BusinessRuleError>()));
  });

  test('reopen needs a reason and permission, then backdating is allowed', () async {
    final r = await rec().saveCount(
        drawerId: 1, currency: 'AFN', date: Harness.d('2026-10-04'), countedMinor: afn(1000), actor: h.owner);
    await rec().close(r.id, h.owner);
    await expectLater(rec().reopen(r.id, ' ', h.owner), throwsA(isA<ValidationError>()));
    await rec().reopen(r.id, 'late receipt', h.owner);
    await h.receipt(k, 'AFN', afn(1), date: '2026-10-03');
  });

  test('opening of a day ignores later and future-dated lines', () async {
    await h.receipt(k, 'AFN', afn(10), date: '2026-10-05');
    final snap = await rec().compute(1, 'AFN', Harness.d('2026-10-03'));
    expect(snap.openingMinor, afn(1000));
    expect(snap.expectedMinor, afn(1000));
    final asOf = await h.app.queries.cashBalance('AFN', asOf: Harness.d('2026-10-04'));
    expect(asOf, afn(1000));
  });

  test('previous balance is per currency, not the globally latest saved day', () async {
    // USD reconciled on 10-05, AFN only on 10-02.
    await h.receipt(k, 'AFN', afn(100), date: '2026-10-03');
    final usdRec = await rec().saveCount(
        drawerId: 1, currency: 'USD', date: Harness.d('2026-10-05'), countedMinor: usd(100), actor: h.owner);
    await rec().close(usdRec.id, h.owner);
    final afnRec = await rec().saveCount(
        drawerId: 1, currency: 'AFN', date: Harness.d('2026-10-02'), countedMinor: afn(1000), actor: h.owner);
    await rec().close(afnRec.id, h.owner);

    final snap = await rec().compute(1, 'AFN', Harness.d('2026-10-06'));
    expect(snap.openingMinor, afn(1100));
  });
}
