import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Outbox v2: per-job record change time, FIFO index, and last-sent
/// snapshot fingerprints (used to skip identical re-uploads).
abstract final class MigrationV29 {
  static Future<void> up(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(sync_queue)');
    final names = {for (final r in cols) r['name'] as String};
    if (!names.contains('changed_at')) {
      await db.execute('ALTER TABLE sync_queue ADD COLUMN changed_at TEXT');
      await db.execute('UPDATE sync_queue SET changed_at = updated_at');
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status_id '
      'ON sync_queue(status, id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_record_state (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        payload_hash TEXT NOT NULL,
        synced_at TEXT NOT NULL,
        PRIMARY KEY (entity_type, entity_id)
      )
    ''');
  }
}
