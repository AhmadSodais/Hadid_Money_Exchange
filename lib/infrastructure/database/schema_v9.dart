import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/shared/ids.dart';

/// Schema version 9: consolidate every cash drawer into the single
/// shared main cashbox.
///
/// Earlier versions allowed several drawers, each with its own cash
/// account. Under the unified-cashbox model all cash — the exchange's
/// own capital and customer funds — lives in one main fund (the first
/// drawer). For each other drawer, its balance per currency is moved to
/// the main cash account with a dated consolidation transaction (the
/// journal itself stays append-only; nothing is rewritten), and the
/// drawer and its cash account are deactivated. On a fresh database —
/// or one that only ever had the main cashbox — this is a no-op.
Future<void> consolidateToSingleCashbox(Transaction txn) async {
  final drawers = await txn.query('cash_drawers', orderBy: 'id');
  if (drawers.length <= 1) return;
  final main = drawers.first;
  final mainId = main['id'] as int;
  await txn.update('cash_drawers', {'is_active': 1}, where: 'id = ?', whereArgs: [mainId]);

  Future<int?> cashAccountId(int drawerId) async {
    final rows = await txn.query('accounts',
        columns: ['id'], where: "role = 'cash' AND drawer_id = ?", whereArgs: [drawerId]);
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  final mainAccount = await cashAccountId(mainId);
  if (mainAccount == null) return;
  final users = await txn.query('users', columns: ['id'], orderBy: 'id', limit: 1);
  final actorId = users.isEmpty ? null : users.first['id'] as int;
  final now = DateTime.now().toUtc();
  final today =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final stamp = now.toIso8601String();
  var seq = 0;

  for (final drawer in drawers.skip(1)) {
    final drawerId = drawer['id'] as int;
    final otherAccount = await cashAccountId(drawerId);
    if (otherAccount != null && actorId != null) {
      final balances = await txn.rawQuery('''
        SELECT currency_code AS cur, SUM(debit_minor - credit_minor) AS bal
        FROM journal_lines WHERE account_id = ? GROUP BY currency_code HAVING bal <> 0
      ''', [otherAccount]);
      for (final row in balances) {
        final currency = row['cur'] as String;
        final balance = row['bal'] as int;
        final amount = balance.abs();
        seq++;
        const description = 'تجمیع موجودی در صندوق اصلی مشترک (مدل تک‌صندوقی)';
        final txId = await txn.insert('transactions', {
          'uuid': Ids.key(),
          'reference_no': 'CBX-${seq.toString().padLeft(4, '0')}',
          'document_no': 'CBX-${seq.toString().padLeft(4, '0')}',
          'type': 'cashAdjustment',
          'status': 'posted',
          'drawer_id': mainId,
          'effective_date': today,
          'created_at': stamp,
          'posted_at': stamp,
          'created_by': actorId,
          'description': description,
          'source_currency': currency,
          'source_amount_minor': amount,
          'signed_amount_minor': 0,
          'reason': description,
          'idempotency_key': 'cashbox-v9-$drawerId-$currency',
        });
        final entryId = await txn.insert('journal_entries', {
          'transaction_id': txId,
          'effective_date': today,
          'posted_at': stamp,
          'description': description,
        });
        // Positive balance: Dr main / Cr other. Negative (overdrawn):
        // Dr other / Cr main, so the pooled total lands in the main fund.
        await txn.insert('journal_lines', {
          'journal_entry_id': entryId,
          'line_no': 1,
          'account_id': balance > 0 ? mainAccount : otherAccount,
          'currency_code': currency,
          'debit_minor': amount,
          'credit_minor': 0,
          'effective_date': today,
        });
        await txn.insert('journal_lines', {
          'journal_entry_id': entryId,
          'line_no': 2,
          'account_id': balance > 0 ? otherAccount : mainAccount,
          'currency_code': currency,
          'debit_minor': 0,
          'credit_minor': amount,
          'effective_date': today,
        });
      }
    }
    await txn.update('cash_drawers', {'is_active': 0}, where: 'id = ?', whereArgs: [drawerId]);
    await txn.update('accounts', {'is_active': 0},
        where: "role = 'cash' AND drawer_id = ?", whereArgs: [drawerId]);
  }
}
