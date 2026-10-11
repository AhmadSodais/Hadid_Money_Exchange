/// Schema version 3: history of automatic Excel exports.
///
/// Like `backup_history`, this describes files on this computer, so it is
/// not part of the Excel workbook and is carried over when the data is
/// replaced by an Excel input or cleared.
library;

const List<String> schemaV3 = [
  '''
  CREATE TABLE excel_export_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    created_at TEXT NOT NULL,
    outcome TEXT NOT NULL CHECK (outcome IN ('success','failure')),
    size_bytes INTEGER,
    transactions INTEGER,
    message TEXT
  )
  ''',
  'CREATE INDEX ix_excel_export_time ON excel_export_history(created_at)',
];
