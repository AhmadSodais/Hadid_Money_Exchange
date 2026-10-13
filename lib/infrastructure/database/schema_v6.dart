/// Schema version 6: `transactions.document_no`, the number a deal is known
/// by.
///
/// `reference_no` stays unique per row, so an edit still gets a fresh one for
/// its replacement row. The replacement inherits the original's
/// `document_no`, so an edited receipt, payment, buy, or sell keeps the number
/// it was first given. Reversal documents keep their own number.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _guardName = 'trg_transactions_only_reverse';

/// The v1 immutability guard, extended to the new column.
const _guard = '''
  CREATE TRIGGER trg_transactions_only_reverse BEFORE UPDATE ON transactions
  WHEN NOT (
    OLD.status = 'posted' AND NEW.status = 'reversed'
    AND OLD.reversed_by_transaction_id IS NULL
    AND NEW.reversed_by_transaction_id IS NOT NULL
    AND NEW.id = OLD.id AND NEW.uuid = OLD.uuid
    AND NEW.reference_no = OLD.reference_no AND NEW.type = OLD.type
    AND NEW.document_no IS OLD.document_no
    AND NEW.customer_id IS OLD.customer_id AND NEW.drawer_id IS OLD.drawer_id
    AND NEW.effective_date = OLD.effective_date
    AND NEW.created_at = OLD.created_at AND NEW.posted_at = OLD.posted_at
    AND NEW.created_by = OLD.created_by AND NEW.description IS OLD.description
    AND NEW.source_currency IS OLD.source_currency
    AND NEW.source_amount_minor IS OLD.source_amount_minor
    AND NEW.dest_currency IS OLD.dest_currency
    AND NEW.dest_amount_minor IS OLD.dest_amount_minor
    AND NEW.rate IS OLD.rate
    AND NEW.fee_currency IS OLD.fee_currency
    AND NEW.fee_amount_minor IS OLD.fee_amount_minor
    AND NEW.signed_amount_minor IS OLD.signed_amount_minor
    AND NEW.reverses_transaction_id IS OLD.reverses_transaction_id
    AND NEW.idempotency_key = OLD.idempotency_key
  )
  BEGIN SELECT RAISE(ABORT, 'posted transactions are immutable'); END
''';

Future<void> addDocumentNumbers(Transaction txn) async {
  await txn.execute('ALTER TABLE transactions ADD COLUMN document_no TEXT');
  await txn.execute('CREATE INDEX idx_transactions_document_no ON transactions(document_no)');
  await txn.execute('DROP TRIGGER IF EXISTS $_guardName');
  await _assign(txn);
  await txn.execute(_guard);
}

/// Recomputes every document number from `reference_no` and the correction
/// links, e.g. after an import that renumbered references or came from a
/// workbook without the column. Safe to run again.
Future<void> assignDocumentNumbers(Transaction txn) async {
  final guard = await txn.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = ?", [_guardName]);
  if (guard.isNotEmpty) await txn.execute('DROP TRIGGER $_guardName');
  await _assign(txn);
  if (guard.isNotEmpty) await txn.execute(guard.first['sql'] as String);
}

Future<void> _assign(Transaction txn) async {
  await txn.execute('UPDATE transactions SET document_no = reference_no WHERE document_no IS NOT reference_no');
  // Ascending, so an edit of an edit inherits the number its original already took.
  final links = await txn.query('transaction_corrections',
      columns: ['original_transaction_id', 'replacement_transaction_id'],
      orderBy: 'replacement_transaction_id');
  for (final l in links) {
    await txn.rawUpdate(
      'UPDATE transactions SET document_no = (SELECT document_no FROM transactions WHERE id = ?) WHERE id = ?',
      [l['original_transaction_id'], l['replacement_transaction_id']],
    );
  }
}
