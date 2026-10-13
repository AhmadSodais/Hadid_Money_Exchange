/// Schema version 5: short identifiers in the `PREFIX-NNNN` convention of
/// [Ids].
///
/// Rewrites customer, drawer, account, and transaction codes and the
/// transaction keys created by earlier versions (e.g. `RCP-000042` →
/// `RCP-0042`, `WALK-IN` → `C-0001`, 36-character UUIDs → 12-character keys).
/// Numbers are kept, so a printed old reference still identifies the same
/// document. Values already in the new form are left untouched, which makes
/// [normalizeIdentifiers] safe to run again, e.g. after importing an Excel
/// workbook exported by an older version. Audit logs stay as recorded.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/shared/ids.dart';
import '../../domain/transactions/financial_command.dart';

/// Triggers protecting the rewritten columns; dropped and recreated around
/// the rewrite inside the caller's transaction.
const _guards = [
  'trg_transactions_only_reverse',
  'trg_accounts_identity',
  'trg_journal_entries_no_update',
];

final _uuidKey = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
final _editReversalKey = RegExp(r'^(.+):reversal$');
final _reconciliationKey = RegExp(r'^reconciliation-adjust-(\d+)-(\d+)$');
final _legacyKey = RegExp(r'^legacy-([0-9a-f]{16})-(?:(cash)|c(.+))-([A-Z]+)$');
final _referenceToken = RegExp(r'\b[A-Z]{3}-\d+\b');
final _trailingNumber = RegExp(r'(\d+)$');

Future<void> normalizeIdentifiers(Transaction txn) async {
  final guards = <String>[];
  for (final name in _guards) {
    final rows = await txn.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = ?", [name]);
    if (rows.isEmpty) continue;
    guards.add(rows.first['sql'] as String);
    await txn.execute('DROP TRIGGER $name');
  }

  await _rewrite(txn, 'customers', 'code', {
    for (final r in await txn.query('customers', columns: ['id']))
      r['id'] as int: Ids.customer(r['id'] as int),
  });
  await _rewrite(txn, 'cash_drawers', 'code', {
    for (final r in await txn.query('cash_drawers', columns: ['id']))
      r['id'] as int: Ids.drawer(r['id'] as int),
  });
  await _rewrite(txn, 'accounts', 'code', {
    for (final r in await txn.query('accounts',
        columns: ['id', 'customer_id', 'drawer_id'], where: "role IN ('customer', 'cash')"))
      r['id'] as int: r['customer_id'] != null
          ? Ids.customerAccount(r['customer_id'] as int)
          : Ids.cashAccount(r['drawer_id'] as int),
  });
  await _rewriteTransactions(txn);

  for (final sql in guards) {
    await txn.execute(sql);
  }
}

Future<void> _rewriteTransactions(Transaction txn) async {
  final rows = await txn.query('transactions',
      columns: ['id', 'type', 'reference_no', 'uuid', 'idempotency_key', 'description']);

  final references = <int, String>{};
  final renamed = <String, String>{};
  for (final r in rows) {
    final old = r['reference_no'] as String;
    final number = _trailingNumber.firstMatch(old);
    if (number == null) continue;
    final next = Ids.reference(TransactionType.parse(r['type'] as String), int.parse(number[1]!));
    references[r['id'] as int] = next;
    if (next != old) renamed[old] = next;
  }

  final taken = <String>{
    for (final r in rows) r['uuid'] as String,
    for (final r in rows) r['idempotency_key'] as String,
  };
  String fresh() {
    var k = Ids.key();
    while (!taken.add(k)) {
      k = Ids.key();
    }
    return k;
  }

  final shortened = <String, String>{};
  String shorten(String uuid) => shortened.putIfAbsent(uuid, fresh);
  String key(String old) {
    if (_uuidKey.hasMatch(old)) return shorten(old);
    if (_editReversalKey.firstMatch(old) case final m?) {
      return Ids.editReversalKey(_uuidKey.hasMatch(m[1]!) ? shorten(m[1]!) : m[1]!);
    }
    if (_reconciliationKey.firstMatch(old) case final m?) {
      return '${Ids.reconciliationKeyPrefix(int.parse(m[1]!))}${m[2]}';
    }
    if (_legacyKey.firstMatch(old) case final m?) {
      final party = m[2] != null ? 'CASH' : 'C${m[3]}';
      return '${Ids.legacyKeyPrefix(m[1]!)}-$party-${m[4]}';
    }
    return old;
  }

  await _rewrite(txn, 'transactions', 'reference_no', references);
  await _rewrite(txn, 'transactions', 'uuid', {
    for (final r in rows)
      if (!Ids.keyPattern.hasMatch(r['uuid'] as String)) r['id'] as int: fresh(),
  });
  await _rewrite(txn, 'transactions', 'idempotency_key', {
    for (final r in rows) r['id'] as int: key(r['idempotency_key'] as String),
  });

  if (renamed.isEmpty) return;
  String relabel(String text) => text.replaceAllMapped(_referenceToken, (m) => renamed[m[0]] ?? m[0]!);
  final batch = txn.batch();
  for (final table in ['transactions', 'journal_entries']) {
    final idColumn = table == 'transactions' ? 'id' : 'transaction_id';
    for (final r in await txn.query(table,
        columns: [idColumn, 'description'], where: 'description IS NOT NULL')) {
      final old = r['description'] as String;
      final next = relabel(old);
      if (next != old) {
        batch.update(table, {'description': next}, where: '$idColumn = ?', whereArgs: [r[idColumn]]);
      }
    }
  }
  await batch.commit(noResult: true);
}

/// Sets [column] of each row id in [values]. Changed rows first get a unique
/// placeholder so no intermediate state collides with a UNIQUE constraint.
Future<void> _rewrite(Transaction txn, String table, String column, Map<int, String> values) async {
  final current = {
    for (final r in await txn.query(table, columns: ['id', column])) r['id'] as int: r[column],
  };
  final changed = {
    for (final e in values.entries)
      if (current[e.key] != e.value) e.key: e.value,
  };
  if (changed.isEmpty) return;
  final batch = txn.batch();
  for (final id in changed.keys) {
    batch.update(table, {column: '~$id'}, where: 'id = ?', whereArgs: [id]);
  }
  for (final e in changed.entries) {
    batch.update(table, {column: e.value}, where: 'id = ?', whereArgs: [e.key]);
  }
  await batch.commit(noResult: true);
}
