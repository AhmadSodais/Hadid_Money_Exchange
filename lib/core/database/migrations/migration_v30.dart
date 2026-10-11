import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Outbox v3: jobs of one business action share a group id (sent together,
/// never split), and each synced record remembers its server version.
abstract final class MigrationV30 {
  static Future<void> up(Database db) async {
    final queueCols = await db.rawQuery('PRAGMA table_info(sync_queue)');
    final queueNames = {for (final r in queueCols) r['name'] as String};
    if (!queueNames.contains('group_id')) {
      await db.execute('ALTER TABLE sync_queue ADD COLUMN group_id TEXT');
    }

    final stateCols = await db.rawQuery('PRAGMA table_info(sync_record_state)');
    final stateNames = {for (final r in stateCols) r['name'] as String};
    if (!stateNames.contains('version')) {
      await db.execute(
        'ALTER TABLE sync_record_state ADD COLUMN version INTEGER',
      );
    }
  }
}
