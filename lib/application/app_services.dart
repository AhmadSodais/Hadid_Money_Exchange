import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../infrastructure/backup/backup_service.dart';
import '../infrastructure/database/exchange_database.dart';
import '../infrastructure/transfer/data_transfer_service.dart';
import 'catalog_service.dart';
import 'customer_service.dart';
import 'legacy_migration_service.dart';
import 'ledger_events.dart';
import 'ledger_queries.dart';
import 'posting_service.dart';
import 'rate_service.dart';
import 'reconciliation_service.dart';
import 'security_service.dart';

/// Composition root: one database connection and every service built on it.
final class AppServices {
  AppServices._(this.db, this.databasePath, this.backupDirectory, this.events,
      {DateTime Function()? clock})
      : _clock = clock {
    rebind(db);
    backups = BackupService(this);
    legacy = LegacyMigrationService(this);
    transfer = DataTransferService(this);
  }

  final DateTime Function()? _clock;

  /// Opens (and migrates) the database at [databasePath].
  static Future<AppServices> open({
    required String databasePath,
    required String backupDirectory,
    DateTime Function()? clock,
  }) async {
    final db = await ExchangeDatabase.open(databasePath);
    return AppServices._(db, databasePath, backupDirectory, LedgerEvents(), clock: clock);
  }

  Database db;
  final String databasePath;
  final String backupDirectory;
  final LedgerEvents events;

  late CatalogService catalog;
  late PostingService posting;
  late CustomerService customers;
  late RateService rates;
  late LedgerQueries queries;
  late ReconciliationService reconciliation;
  late SecurityService security;
  late BackupService backups;
  late LegacyMigrationService legacy;
  late DataTransferService transfer;

  DateTime now() => (_clock ?? DateTime.now)();

  /// Re-binds every service to a newly opened connection (after restore).
  void rebind(Database newDb) {
    db = newDb;
    catalog = CatalogService(db, events);
    posting = PostingService(db, catalog, events, clock: _clock);
    customers = CustomerService(db, events);
    rates = RateService(db, catalog, events);
    queries = LedgerQueries(db);
    reconciliation = ReconciliationService(db, posting, events);
    security = SecurityService(db);
  }

  Future<void> close() async {
    await db.close();
  }
}
