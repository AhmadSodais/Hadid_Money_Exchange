import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/domain/errors/domain_errors.dart';
import 'package:hadid_exchange/domain/security/permissions.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';

import '../support/harness.dart';

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

  test('a new drawer gets its own cash account and keeps its cash separate', () async {
    final second = await h.app.catalog.addDrawer('  صندوق دوم ', h.owner);
    expect(second.nameFa, 'صندوق دوم');
    expect((await h.app.catalog.drawers()).map((d) => d.id), [1, second.id]);
    final account = await h.app.db.query('accounts', where: "role = 'cash' AND drawer_id = ?", whereArgs: [second.id]);
    expect(account.single['code'], '1100-0002');

    await h.openingCash('USD', usd(100));
    await openingCash(second.id, 'USD', usd(40));
    expect(await h.app.queries.cashBalances(drawerId: 1), {'USD': usd(100)});
    expect(await h.app.queries.cashBalances(drawerId: second.id), {'USD': usd(40)});
    expect(await h.app.queries.cashBalances(), {'USD': usd(140)});
    expect(await h.app.queries.integrityProblems(), isEmpty);
  });

  test('drawer names are unique', () async {
    await expectLater(h.app.catalog.addDrawer('صندوق اصلی', h.owner), throwsA(isA<BusinessRuleError>()));
    await expectLater(h.app.catalog.addDrawer('  ', h.owner), throwsA(isA<ValidationError>()));
    final second = await h.app.catalog.addDrawer('صندوق دوم', h.owner);
    await expectLater(
      h.app.catalog.updateDrawer(second.id, name: 'صندوق اصلی', isActive: true, actor: h.owner),
      throwsA(isA<BusinessRuleError>()),
    );
    await h.app.catalog.updateDrawer(second.id, name: 'صندوق بازار', isActive: true, actor: h.owner);
    final account = await h.app.db.query('accounts', where: 'drawer_id = ?', whereArgs: [second.id]);
    expect(account.single['name_fa'], 'صندوق بازار');
  });

  test('deactivation needs a zero balance and another active drawer', () async {
    final second = await h.app.catalog.addDrawer('صندوق دوم', h.owner);
    await openingCash(second.id, 'AFN', afn(500));
    await expectLater(
      h.app.catalog.updateDrawer(second.id, name: 'صندوق دوم', isActive: false, actor: h.owner),
      throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'drawer.openBalance')),
    );

    final third = await h.app.catalog.addDrawer('صندوق سوم', h.owner);
    await h.app.catalog.updateDrawer(third.id, name: 'صندوق سوم', isActive: false, actor: h.owner);
    await expectLater(openingCash(third.id, 'AFN', afn(1)), throwsA(isA<BusinessRuleError>()));

    final fresh = await Harness.create();
    addTearDown(fresh.dispose);
    await expectLater(
      fresh.app.catalog.updateDrawer(1, name: 'صندوق اصلی', isActive: false, actor: fresh.owner),
      throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'drawer.lastActive')),
    );

    await h.app.catalog.updateDrawer(third.id, name: 'صندوق سوم', isActive: true, actor: h.owner);
    await openingCash(third.id, 'AFN', afn(1));
    expect(await h.app.queries.integrityProblems(), isEmpty);
  });

  test('managing drawers requires the settings permission', () async {
    final cashier = Actor(userId: 1, displayName: 'c', permissions: Permissions.roleDefaults['cashier']!.toSet());
    await expectLater(h.app.catalog.addDrawer('x', cashier), throwsA(isA<AuthorizationError>()));
    await expectLater(
      h.app.catalog.updateDrawer(1, name: 'x', isActive: true, actor: cashier),
      throwsA(isA<AuthorizationError>()),
    );
  });
}
