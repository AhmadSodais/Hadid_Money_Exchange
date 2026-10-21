import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/application/ledger_queries.dart';
import 'package:hadid_exchange/application/read_models.dart';
import 'package:hadid_exchange/domain/shared/business_date.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';

import '../support/harness.dart';

/// Mandatory scenario (master prompt §24).
///
/// Opening: 100,000 AFN and 2,000 USD.
/// A: buy 100 USD, pay 7,000 AFN.     B: sell 50 USD, receive 3,550 AFN.
/// C: receive 1,000 AFN from customer K.  D: pay 200 AFN to customer K.
///
/// Customer K is defined with an opening position of −800 AFN (K owes the
/// exchange 800 — the 800 was paid out of the vault when the debt arose,
/// so opening AFN cash drops from 100,000 to 99,200). C settles that
/// debt and leaves +200 owed to K; D pays the 200 out, so K ends at 0.
void main() {
  late Harness h;
  late int customerK;
  late PostedTransaction txB;

  setUp(() async {
    h = await Harness.create();
    await h.openingCash('AFN', afn(100000));
    await h.openingCash('USD', usd(2000));
    final k = await h.customer('کریم');
    customerK = k.id;
    await h.app.posting.post(
      OpeningCustomerCommand(
        idempotencyKey: h.key(),
        effectiveDate: Harness.d('2026-10-01'),
        customerId: customerK,
        currency: 'AFN',
        signedMinor: -afn(800),
        drawerId: 1,
      ),
      h.owner,
    );

    await h.exchange(
        direction: ExchangeDirection.buy, base: 'USD', quote: 'AFN', baseMinor: usd(100), rate: '70');
    txB = await h.exchange(
        direction: ExchangeDirection.sell, base: 'USD', quote: 'AFN', baseMinor: usd(50), rate: '71');
    await h.receipt(customerK, 'AFN', afn(1000));
    await h.payment(customerK, 'AFN', afn(200));
  });

  tearDown(() => h.dispose());

  Future<void> expectCashEverywhere({required int afnMinor, required int usdMinor}) async {
    final q = h.app.queries;
    final asOf = BusinessDate.parse('2026-10-11');

    // 1. Cash balance screen.
    final cash = await q.cashBalances();
    expect(cash['AFN'], afnMinor, reason: 'cash screen AFN');
    expect(cash['USD'], usdMinor, reason: 'cash screen USD');

    // 2. Currency position report (opening + in − out).
    final movement = {
      for (final m in await q.cashMovement(BusinessDate.parse('2026-10-01'), asOf)) m.currency: m
    };
    expect(movement['AFN']!.closingMinor, afnMinor, reason: 'currency report AFN');
    expect(movement['USD']!.closingMinor, usdMinor, reason: 'currency report USD');

    // 3. Journal-derived cash account (trial balance).
    final tb = await q.trialBalance(asOf: asOf);
    int cashNet(String cur) => tb
        .where((r) => r.accountCode == '1100-0001' && r.currency == cur)
        .fold(0, (s, r) => s + r.netMinor);
    expect(cashNet('AFN'), afnMinor, reason: 'trial balance AFN');
    expect(cashNet('USD'), usdMinor, reason: 'trial balance USD');

    // 4. Daily reconciliation expected closing.
    final recAfn = await h.app.reconciliation.compute(1, 'AFN', asOf);
    final recUsd = await h.app.reconciliation.compute(1, 'USD', asOf);
    expect(recAfn.expectedMinor, afnMinor, reason: 'reconciliation AFN');
    expect(recUsd.expectedMinor, usdMinor, reason: 'reconciliation USD');

    // 5. Historical account statement (general ledger running balance).
    final cashAccountId = tb.firstWhere((r) => r.accountCode == '1100-0001').accountId;
    final ledgerAfn = await q.accountLedger(cashAccountId, 'AFN');
    final ledgerUsd = await q.accountLedger(cashAccountId, 'USD');
    expect(ledgerAfn.last.running, afnMinor, reason: 'account statement AFN');
    expect(ledgerUsd.last.running, usdMinor, reason: 'account statement USD');
  }

  test('balances agree across every view: AFN 96,550 and USD 2,050', () async {
    await expectCashEverywhere(afnMinor: afn(96550), usdMinor: usd(2050));
  });

  test('customer K consequences follow the settlement purpose', () async {
    final k = (await h.app.customers.byId(customerK))!;
    final statement = await h.app.queries.customerStatement(k, 'AFN');
    expect(statement.lines.map((l) => l.runningPositionMinor).toList(),
        [-afn(800), afn(200), 0]);
    final balances = await h.app.queries.customerBalances(customerK);
    expect(balances.single.positionMinor, 0);
  });

  test('B appears as one logical transaction with four legs', () async {
    final journal = await h.app.queries.journal(
        const JournalFilter(types: {TransactionType.sell}));
    expect(journal, hasLength(1));
    final detail = (await h.app.posting.transactionById(journal.single.id))!;
    expect(detail.lines, hasLength(4));
    expect(detail.sourceAmountMinor, usd(50));
    expect(detail.destAmountMinor, afn(3550));
    expect(detail.rate, '71');
  });

  test('reversing B gives AFN 93,000 and USD 2,100 everywhere', () async {
    final rev = await h.reverse(txB.id);
    expect(rev.type, TransactionType.reversal);
    expect(rev.reversesTransactionId, txB.id);
    final original = (await h.app.posting.transactionById(txB.id))!;
    expect(original.status, TransactionStatus.reversed);
    expect(original.reversedByTransactionId, rev.id);

    await expectCashEverywhere(afnMinor: afn(93000), usdMinor: usd(2100));
    expect(await h.app.queries.integrityProblems(), isEmpty);
  });

  test('no profit is derived from the rate difference', () async {
    final income = await h.app.queries
        .incomeAndExpense(BusinessDate.parse('2026-10-01'), BusinessDate.parse('2026-10-11'));
    expect(income, isEmpty, reason: 'no fees or expenses were posted');
  });
}
