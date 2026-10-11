/// Schema version 2: links an edited transaction to the reversal that
/// neutralized it and to the corrected transaction that replaced it.
///
/// Editing never changes a posted row. One correction = the original is
/// reversed on its own date and a replacement is posted, atomically; this
/// table records that trio so the history reads "edited" rather than
/// "deleted + new".
library;

const List<String> schemaV2 = [
  '''
  CREATE TABLE transaction_corrections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    original_transaction_id INTEGER NOT NULL UNIQUE REFERENCES transactions(id),
    reversal_transaction_id INTEGER NOT NULL UNIQUE REFERENCES transactions(id),
    replacement_transaction_id INTEGER NOT NULL UNIQUE REFERENCES transactions(id),
    reason TEXT NOT NULL CHECK (length(trim(reason)) > 0),
    created_by INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TRIGGER trg_corrections_no_update BEFORE UPDATE ON transaction_corrections
  BEGIN SELECT RAISE(ABORT, 'transaction corrections are immutable'); END
  ''',
  '''
  CREATE TRIGGER trg_corrections_no_delete BEFORE DELETE ON transaction_corrections
  BEGIN SELECT RAISE(ABORT, 'transaction corrections cannot be deleted'); END
  ''',
];
