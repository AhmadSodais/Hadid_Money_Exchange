import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/application/posting_service.dart';
import 'package:hadid_exchange/domain/shared/ids.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';
import 'package:hadid_exchange/infrastructure/database/schema_v5.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/harness.dart';

void main() {
  late Harness h;

  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  Future<String> keyOf(int transactionId) async => (await h.app.db.query('transactions',
          columns: ['idempotency_key'], where: 'id = ?', whereArgs: [transactionId]))
      .single['idempotency_key'] as String;

  Future<Set<Object?>> ledgerAccountCodes() async => {
        for (final r in await h.app.db.query('accounts',
            columns: ['code'], where: "role IN ('cash', 'customer')"))
          r['code'],
      };

  ReceiptCommand receipt(int customerId, String key) => ReceiptCommand(
        idempotencyKey: key,
        effectiveDate: Harness.d('2026-10-06'),
        customerId: customerId,
        drawerId: 1,
        currency: 'AFN',
        amountMinor: afn(20),
      );

  test('new records get PREFIX-NNNN codes and 12-character keys', () async {
    expect((await h.app.customers.walkIn()).code, 'C-0001');
    final ali = await h.customer('Ali');
    expect(ali.code, 'C-0002');
    expect((await h.app.catalog.drawers()).single.code, 'D-0001');
    expect((await h.app.catalog.addDrawer('Second', h.owner)).code, 'D-0002');
    expect(await ledgerAccountCodes(), {'1100-0001', '1100-0002', '2100-0001', '2100-0002'});

    final key = PostingService.newIdempotencyKey();
    expect(key, matches(Ids.keyPattern));
    final original = await h.receipt(ali.id, 'AFN', afn(10));
    expect(original.referenceNo, 'RCP-0001');
    expect(original.uuid, matches(Ids.keyPattern));

    final edited = await h.app.posting
        .correct(transactionId: original.id, replacement: receipt(ali.id, key), reason: 'typo', actor: h.owner);
    expect(edited.referenceNo, 'RCP-0001', reason: 'an edited deal keeps its number');
    final internal = await h.app.db
        .query('transactions', columns: ['reference_no'], where: 'id = ?', whereArgs: [edited.id]);
    expect(internal.single['reference_no'], 'RCP-0002');
    final reversalId = (await h.app.posting.transactionById(original.id))!.reversedByTransactionId!;
    expect((await h.app.posting.transactionById(reversalId))!.referenceNo, 'REV-0001');
    expect(await keyOf(reversalId), '$key-R');

    final editedAgain = await h.app.posting.correct(
        transactionId: edited.id, replacement: receipt(ali.id, h.key()), reason: 'again', actor: h.owner);
    expect(editedAgain.referenceNo, 'RCP-0001');
  });

  test('older formats are converted, keeping numbers and links', () async {
    final ali = await h.customer('Ali');
    final original = await h.receipt(ali.id, 'AFN', afn(10));
    final edited = await h.app.posting.correct(
        transactionId: original.id, replacement: receipt(ali.id, h.key()), reason: 'typo', actor: h.owner);
    final reversalId = (await h.app.posting.transactionById(original.id))!.reversedByTransactionId!;
    final opening = await h.app.posting.post(
      OpeningCustomerCommand(
        idempotencyKey: h.key(),
        effectiveDate: Harness.d('2026-10-01'),
        customerId: ali.id,
        currency: 'USD',
        signedMinor: usd(5),
        drawerId: 1,
      ),
      h.owner,
    );

    const editKey = '3f2b8c1e-9a4d-4c6b-8e2f-1a2b3c4d5e6f';
    final db = h.app.db;
    await db.transaction((t) async {
      final guards = await t.rawQuery("SELECT name, sql FROM sqlite_master WHERE type = 'trigger' "
          "AND name IN ('trg_transactions_only_reverse', 'trg_accounts_identity', 'trg_journal_entries_no_update')");
      for (final g in guards) {
        await t.execute('DROP TRIGGER ${g['name']}');
      }
      Future<void> set(String table, Map<String, Object?> values, String where, List<Object?> args) =>
          t.update(table, values, where: where, whereArgs: args);
      await set('customers', {'code': 'WALK-IN'}, 'id = ?', [1]);
      await set('customers', {'code': 'C-00002'}, 'id = ?', [ali.id]);
      await set('cash_drawers', {'code': 'MAIN'}, 'id = ?', [1]);
      await set('accounts', {'code': '1101'}, 'drawer_id = ?', [1]);
      await set('accounts', {'code': '2100-000002'}, 'customer_id = ?', [ali.id]);
      await set('transactions', {
        'reference_no': 'RCP-000001',
        'uuid': '0e8f6a2c-5b7d-4e1f-9a3c-2d4b6f8a0c1e',
        'idempotency_key': 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d',
      }, 'id = ?', [original.id]);
      await set('transactions', {'reference_no': 'RCP-000002', 'idempotency_key': editKey}, 'id = ?', [edited.id]);
      await set('transactions', {
        'reference_no': 'REV-000001',
        'idempotency_key': '$editKey:reversal',
        'description': 'ویرایش RCP-000001',
      }, 'id = ?', [reversalId]);
      await set('journal_entries', {'description': 'ویرایش RCP-000001'}, 'transaction_id = ?', [reversalId]);
      await set('transactions', {
        'reference_no': 'OPB-000001',
        'idempotency_key': 'legacy-0123456789abcdef-c7-USD',
      }, 'id = ?', [opening.id]);
      for (final g in guards) {
        await t.execute(g['sql'] as String);
      }
    });

    await db.transaction(normalizeIdentifiers);

    expect((await h.app.customers.walkIn()).code, 'C-0001');
    expect((await h.app.customers.byId(ali.id))!.code, 'C-0002');
    expect((await h.app.catalog.drawers()).single.code, 'D-0001');
    expect(await ledgerAccountCodes(), {'1100-0001', '2100-0001', '2100-0002'});

    final tx = h.app.posting.transactionById;
    expect((await tx(original.id))!.referenceNo, 'RCP-0001');
    expect((await tx(original.id))!.uuid, matches(Ids.keyPattern));
    expect(await keyOf(original.id), matches(Ids.keyPattern));
    expect((await tx(edited.id))!.referenceNo, 'RCP-0001');
    final newEditKey = await keyOf(edited.id);
    expect(newEditKey, matches(Ids.keyPattern));
    final reversal = (await tx(reversalId))!;
    expect(reversal.referenceNo, 'REV-0001');
    expect(reversal.description, 'ویرایش RCP-0001');
    expect(await keyOf(reversalId), '$newEditKey-R');
    final entry = await db.query('journal_entries', where: 'transaction_id = ?', whereArgs: [reversalId]);
    expect(entry.single['description'], 'ویرایش RCP-0001');
    expect((await tx(opening.id))!.referenceNo, 'OPA-0001');
    expect(await keyOf(opening.id), 'LEG-01234567-C7-USD');

    final before = await db.query('transactions', orderBy: 'id');
    await db.transaction(normalizeIdentifiers);
    expect(await db.query('transactions', orderBy: 'id'), before, reason: 'a second run changes nothing');

    await expectLater(
      db.update('transactions', {'reference_no': 'X'}, where: 'id = ?', whereArgs: [original.id]),
      throwsA(isA<DatabaseException>()),
      reason: 'immutability triggers are restored',
    );
  });
}
