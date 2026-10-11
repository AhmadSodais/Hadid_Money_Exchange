import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Sync queue + sync meta for offline-first Firebase synchronization.
abstract final class MigrationV7 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT NOT NULL UNIQUE,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_entity '
      'ON sync_queue(entity_type, entity_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.insert(
      'sync_meta',
      {'key': 'last_sync_at', 'value': ''},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
