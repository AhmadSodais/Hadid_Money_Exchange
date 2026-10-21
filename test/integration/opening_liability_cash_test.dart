import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/application/ledger_queries.dart';
import 'package:hadid_exchange/domain/errors/domain_errors.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';

import '../support/harness.dart';

/// The unified-cashbox / initial-capital model:
///  * Initial capital (3100) is the exchange's *own* funds only and is
///    posted exclusively by opening cash; customer opening balances never
///    touch it. Before this fix, customer openings credited/debited 3100,
///    so "initial capital" silently included client money.
///  * All cash — own capital and customer funds — is pooled in one
///    single main cashbox; an opening customer balance records one
///    customer's share of it against cash.
///  * The cashbox balance is the total in the fund, and it is the
///    withdrawal limit for every outflow: a client-debt opening (funds
///    paid out of the cashbox) or any withdrawal above that total is
///    rejected — e.g. AFN 21,000 out of a AFN 20,000 cashbox is blocked.
void main() {
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  Future<void> openingCustomer(int customerId, int signed, {int? drawerId}) async {
    await h.app.posting.post(
      OpeningCustomerCommand(
        idempotencyKey: h.key(),
        effectiveDate: Harness.d('2026-10-01'),
        customerId: customerId,
        currency: 'AFN',
        signedMinor: signed,
        drawerId: drawerId,
        description: 'بیلانس افتتاحیه آزمایشی',
      ),
      h.owner,
    );
  }

  /// Net balance of account 3100 in AFN (debit − credit), i.e. minus the
  /// credit balance of the exchange's own capital.
  Future<int> initialCapitalNet() async => (await h.app.queries.trialBalance())
      .singleWhere((r) => r.accountCode == '3100' && r.currency == 'AFN')
      .netMinor;

  test('common vault: own capital 10,000 + customer funds 20,000, capital never inflated', () async {
    // Exchange's own initial capital: only its own 10,000 enters 3100.
    await h.openingCash('AFN', afn(10000));
    expect(await initialCapitalNet(), -afn(10000));

    // A customer holds 20,000 with the exchange in the same vault.
    final customer = await h.customer('کریم');
    await openingCustomer(customer.id, afn(20000), drawerId: 1);

    // Common vault physical total = 10,000 + 20,000 = 30,000 …
    expect(await h.app.queries.cashBalance('AFN'), afn(30000));
    final availability = (await h.app.queries.cashAvailability())['AFN']!;
    expect(availability.physicalMinor, afn(30000));
    // … of which the customer's 20,000 is the customers' share …
    expect(availability.reservedMinor, afn(20000));
    // … and the withdrawable cashbox balance is the pooled total itself.
    expect(availability.availableMinor, afn(30000));
    expect(await h.app.queries.cashboxBalance('AFN'), afn(30000));
    expect((await h.app.queries.customerBalances(customer.id)).single.positionMinor, afn(20000));
    // Initial capital is still exactly the exchange's own funds.
    expect(await initialCapitalNet(), -afn(10000));

    // Auditable: amount, direction, note and balances before/after + time.
    final audit = await h.app.db.rawQuery('''
      SELECT after_json, occurred_at FROM audit_logs
      WHERE action = 'transaction.post' AND after_json LIKE '%customer_liability%'
      ORDER BY id DESC LIMIT 1
    ''');
    final after = jsonDecode(audit.single['after_json'] as String) as Map<String, Object?>;
    expect(after['signed_amount_minor'], afn(20000));
    expect(after['drawer_id'], 1);
    expect((after['balances_before'] as Map)['physical_cash_minor'], afn(10000));
    expect((after['balances_after'] as Map)['physical_cash_minor'], afn(30000));
    expect((after['balances_after'] as Map)['available_cash_minor'], afn(30000));
    expect((after['balances_after'] as Map)['cashbox_balance_minor'], afn(30000));
    expect(audit.single['occurred_at'], isNotNull);

    // Payout to the customer: his 20,000 leaves the vault; the exchange's
    // own position does not change.
    await h.payment(customer.id, 'AFN', afn(20000), date: '2026-10-06');
    expect(await h.app.queries.cashBalance('AFN'), afn(10000));
    expect((await h.app.queries.cashAvailability())['AFN']!.availableMinor, afn(10000));
    expect(await initialCapitalNet(), -afn(10000));
    expect(await h.app.queries.integrityProblems(), isEmpty);
  });

  test('reversing an opening liability removes the customer share from the vault', () async {
    await h.openingCash('AFN', afn(10000));
    final customer = await h.customer('کریم');
    await openingCustomer(customer.id, afn(20000), drawerId: 1);
    final opening = (await h.app.queries
            .journal(const JournalFilter(types: {TransactionType.openingCustomer})))
        .single;
    await h.reverse(opening.id);

    final availability = (await h.app.queries.cashAvailability())['AFN']!;
    expect(availability.physicalMinor, afn(10000));
    expect(availability.reservedMinor, 0);
    expect(availability.availableMinor, afn(10000));
    expect(await initialCapitalNet(), -afn(10000));
  });

  test('client debt opening: paid out of the cashbox, capped at its total balance', () async {
    // Own capital 10,000 plus another customer's 20,000 pooled in the one
    // main cashbox: the cashbox balance — and the payout limit — is 30,000.
    await h.openingCash('AFN', afn(10000));
    final holder = await h.customer('کریم');
    await openingCustomer(holder.id, afn(20000), drawerId: 1);
    final debtor = await h.customer('فرهاد');
    expect(await h.app.queries.cashboxBalance('AFN'), afn(30000));

    // A 31,000 debt exceeds the 30,000 cashbox balance → rejected with a
    // clear error, nothing written.
    final txBefore = await h.count('transactions');
    await expectLater(
      openingCustomer(debtor.id, -afn(31000), drawerId: 1),
      throwsA(isA<BusinessRuleError>()
          .having((e) => e.code, 'code', 'opening.debtExceedsAvailableFunds')
          .having((e) => e.message, 'message', contains('نمی‌تواند از موجودی فعلی صندوق اصلی مشترک'))),
    );
    expect(await h.count('transactions'), txBefore);
    expect(await h.app.queries.customerBalances(debtor.id), isEmpty);

    // A debt inside the cashbox total pays out of the fund, exactly like
    // a payment.
    await openingCustomer(debtor.id, -afn(15000), drawerId: 1);
    expect(await h.app.queries.cashboxBalance('AFN'), afn(15000));
    expect((await h.app.queries.customerBalances(debtor.id)).single.positionMinor, -afn(15000));
    // Initial capital untouched by the customer's debt.
    expect(await initialCapitalNet(), -afn(10000));

    // When the customer pays, the cash returns to the same cashbox.
    await h.receipt(debtor.id, 'AFN', afn(15000), date: '2026-10-06');
    expect(await h.app.queries.cashboxBalance('AFN'), afn(30000));
    expect((await h.app.queries.customerBalances(debtor.id)).single.positionMinor, 0);
    expect(await h.app.queries.integrityProblems(), isEmpty);
  });

  test('withdrawal cannot exceed the cashbox balance: 20,000 blocks 21,000', () async {
    // The cashbox holds AFN 20,000 in total (own capital + customer funds).
    await h.openingCash('AFN', afn(12000));
    final holder = await h.customer('کریم');
    await openingCustomer(holder.id, afn(8000), drawerId: 1);
    expect(await h.app.queries.cashboxBalance('AFN'), afn(20000));

    // A payment (برد) of 21,000 exceeds the whole cashbox → blocked.
    final txBefore = await h.count('transactions');
    await expectLater(
      h.payment(holder.id, 'AFN', afn(21000)),
      throwsA(isA<BusinessRuleError>()
          .having((e) => e.code, 'code', 'cash.insufficient')
          .having((e) => e.message, 'message', contains('نمی‌تواند از موجودی فعلی صندوق اصلی مشترک'))),
    );
    expect(await h.count('transactions'), txBefore);
    expect(await h.app.queries.cashboxBalance('AFN'), afn(20000));

    // Exactly the cashbox total can be paid out; the fund ends empty.
    await h.payment(holder.id, 'AFN', afn(20000));
    expect(await h.app.queries.cashboxBalance('AFN'), 0);
    expect(await h.app.queries.integrityProblems(), isEmpty);
  });
}
