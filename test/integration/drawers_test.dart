import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/domain/errors/domain_errors.dart';
import 'package:hadid_exchange/domain/security/permissions.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';
import 'package:hadid_exchange/infrastructure/database/schema_v9.dart';

import '../support/harness.dart';

/// Single shared cashbox model: there is exactly one main cashbox.
/// Creating a separate drawer is rejected, the main cashbox can never be
/// deactivated, and cash postings naming any other drawer are refused so
/// every amount stays pooled in the one fund.
void main() {
  late Harness h;

  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  Future<void> openingCash(int drawerId, String cur, int minor) => h.app.posting.post(
        OpeningCashCommand(
          idempotencyKey: h.key(),
          effectiveDate: Harness.d('2026-10-01'),
          drawerId: drawerId,
          currency: cur,
          amountMinor: minor,
        ),
        h.owner,
      );

  test('only the main cashbox exists and no separate drawer can be created', () async {
    expect((await h.app.catalog.drawers()).map((d) => d.id), [1]);
    expect((await h.app.catalog.mainCashbox())!.id, 1);
    expect((await h.app.catalog.mainCashbox())!.nameFa, 'صندوق اصلی');
    await expectLater(
      h.app.catalog.addDrawer('صندوق دوم', h.owner),
      throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'cashbox.single')),
    );
    expect((await h.app.catalog.drawers()).length, 1);
  });

  test('the main cashbox can be renamed but never deactivated', () async {
    await h.app.catalog.updateDrawer(1, name: 'صندوق اصلی مشترک', isActive: true, actor: h.owner);
    expect((await h.app.catalog.mainCashbox())!.nameFa, 'صندوق اصلی مشترک');
    await expectLater(
      h.app.catalog.updateDrawer(1, name: 'صندوق اصلی مشترک', isActive: false, actor: h.owner),
      throwsA(isA<BusinessRuleError>()),
    );
    expect((await h.app.catalog.mainCashbox())!.isActive, isTrue);
  });

  test('all cash pools in the main cashbox; other drawers refuse postings', () async {
    // A legacy-style second drawer row inserted directly (as schema v9
    // would have found it) is neither offered nor postable: the posting
    // service rejects it so funds cannot leave the shared fund.
    await h.app.db.insert('cash_drawers', {
      'id': 2,
      'code': 'D-0002',
      'name_fa': 'صندوق قدیمی',
      'is_active': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await expectLater(
      openingCash(2, 'AFN', afn(100)),
      throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'cashbox.nonMainDrawer')),
    );

    await h.openingCash('USD', usd(100));
    await h.openingCash('AFN', afn(500));
    expect(await h.app.queries.cashboxBalances(), {'USD': usd(100), 'AFN': afn(500)});
    expect(await h.app.queries.cashboxBalance('AFN'), afn(500));
    expect(await h.app.queries.integrityProblems(), isEmpty);
  });

  test('schema v9 consolidation moves a legacy second drawer into the main cashbox', () async {
    // Build the pre-v9 state directly: a second drawer with its own cash
    // account holding AFN 700, while the main cashbox holds AFN 500.
    await h.openingCash('AFN', afn(500));
    final now = DateTime.now().toUtc().toIso8601String();
    await h.app.db.insert('cash_drawers', {
      'id': 2, 'code': 'D-0002', 'name_fa': 'صندوق دوم', 'is_active': 1, 'created_at': now,
    });
    final parent = await h.app.db.query('accounts', columns: ['id'], where: "code = '1100'");
    final otherAccount = await h.app.db.insert('accounts', {
      'code': '1100-0002', 'name_fa': 'صندوق دوم', 'type': 'asset', 'normal_side': 'debit',
      'role': 'cash', 'parent_id': parent.single['id'], 'drawer_id': 2,
      'is_active': 1, 'is_system': 0, 'created_at': now,
    });
    final txId = await h.app.db.insert('transactions', {
      'uuid': 'LEGACY000001', 'reference_no': 'OPC-9001', 'type': 'openingCash', 'status': 'posted',
      'drawer_id': 2, 'effective_date': '2026-10-01', 'created_at': now, 'posted_at': now,
      'created_by': 1, 'source_currency': 'AFN', 'source_amount_minor': afn(700),
      'idempotency_key': 'legacy-second-drawer-cash',
    });
    final entryId = await h.app.db.insert('journal_entries', {
      'transaction_id': txId, 'effective_date': '2026-10-01', 'posted_at': now,
    });
    final equity = await h.app.db.query('accounts', columns: ['id'], where: "code = '3100'");
    await h.app.db.insert('journal_lines', {
      'journal_entry_id': entryId, 'line_no': 1, 'account_id': otherAccount,
      'currency_code': 'AFN', 'debit_minor': afn(700), 'credit_minor': 0, 'effective_date': '2026-10-01',
    });
    await h.app.db.insert('journal_lines', {
      'journal_entry_id': entryId, 'line_no': 2, 'account_id': equity.single['id'],
      'currency_code': 'AFN', 'debit_minor': 0, 'credit_minor': afn(700), 'effective_date': '2026-10-01',
    });
    expect(await h.app.queries.cashBalances(drawerId: 2), {'AFN': afn(700)});

    await h.app.db.transaction(consolidateToSingleCashbox);

    // Everything is pooled in the main cashbox; the extra drawer and its
    // account are inactive and hold nothing.
    expect(await h.app.queries.cashboxBalance('AFN'), afn(1200));
    expect(await h.app.queries.cashBalances(drawerId: 1), {'AFN': afn(1200)});
    expect(await h.app.queries.cashBalances(drawerId: 2), {'AFN': 0});
    final drawer2 = await h.app.db.query('cash_drawers', where: 'id = 2');
    expect(drawer2.single['is_active'], 0);
    expect(await h.app.queries.integrityProblems(), isEmpty);
  });

  test('managing the cashbox requires the settings permission', () async {
    final cashier = Actor(userId: 1, displayName: 'c', permissions: Permissions.roleDefaults['cashier']!.toSet());
    await expectLater(h.app.catalog.addDrawer('x', cashier), throwsA(isA<AuthorizationError>()));
    await expectLater(
      h.app.catalog.updateDrawer(1, name: 'x', isActive: true, actor: cashier),
      throwsA(isA<AuthorizationError>()),
    );
  });
}
