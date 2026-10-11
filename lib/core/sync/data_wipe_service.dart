import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'firebase_rtdb_client.dart';
import 'firebase_sync_service.dart';
import 'sync_models.dart';
import 'sync_queue_repository.dart';

/// Clears the account's server data and/or local business data.
/// Basic settings (currencies, units, app settings) are always kept.
class DataWipeService {
  DataWipeService({FirebaseRtdbClient? client})
      : _client = client ?? FirebaseRtdbClient();

  final FirebaseRtdbClient _client;

  /// Deletes this account's app root on the server.
  Future<String?> clearServerData() =>
      FirebaseSyncService.runExclusive(() async {
        final pingErr = await _client.pingError();
        if (pingErr != null) return pingErr;
        try {
          for (final entity in [
            ...SyncEntityTypes.allBusiness,
            'sync_logs',
          ]) {
            try {
              await _client.delete(entity);
            } catch (e) {
              debugPrint('[Wipe] delete $entity: $e');
            }
          }
          await _client.deleteRoot();
          // The server no longer holds any previously sent snapshot.
          await SyncQueueRepository().clearRecordState();
          return null;
        } catch (e, st) {
          debugPrint('[Wipe] server failed: $e\n$st');
          return e.toString();
        }
      });

  /// Clears local business tables. Keeps currencies, units, app_settings
  /// and this installation's device id.
  Future<String?> clearOfflineData() =>
      FirebaseSyncService.runExclusive(() async {
        try {
          final db = AppDatabase.instance;
          await db.execute('PRAGMA foreign_keys = OFF');
          try {
            await db.transaction((txn) async {
              const tables = <String>[
                'sale_items',
                'sales',
                'order_items',
                'orders',
                'purchase_items',
                'purchases',
                'cutting_jobs',
                'stock_movements',
                'company_payment_allocations',
                'company_payments',
                'employee_salaries',
                'employees',
                'expenses',
                'products',
                'customers',
                'suppliers',
                'categories',
                'warehouses',
                'audit_logs',
                'sync_queue',
                'sync_record_state',
              ];
              for (final table in tables) {
                try {
                  await txn.delete(table);
                } catch (e) {
                  debugPrint('[Wipe] skip table $table: $e');
                }
              }
              await txn.delete(
                'sync_meta',
                where: 'key != ?',
                whereArgs: [SyncQueueRepository.deviceIdKey],
              );
              // sqlite_sequence is kept so new records never reuse an id
              // that may still exist on the server.
            });
          } finally {
            await db.execute('PRAGMA foreign_keys = ON');
          }
          return null;
        } catch (e, st) {
          debugPrint('[Wipe] offline failed: $e\n$st');
          return e.toString();
        }
      });
}
