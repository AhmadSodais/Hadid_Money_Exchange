import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../constants/app_constants.dart';
import '../errors/app_failure.dart';
import 'migrations/migration_v1.dart';
import 'migrations/migration_v2.dart';
import 'migrations/migration_v3.dart';
import 'migrations/migration_v4.dart';
import 'migrations/migration_v5.dart';
import 'migrations/migration_v6.dart';
import 'migrations/migration_v7.dart';
import 'migrations/migration_v8.dart';
import 'migrations/migration_v9.dart';
import 'migrations/migration_v10.dart';
import 'migrations/migration_v11.dart';
import 'migrations/migration_v12.dart';
import 'migrations/migration_v13.dart';
import 'migrations/migration_v14.dart';
import 'migrations/migration_v15.dart';
import 'migrations/migration_v16.dart';
import 'migrations/migration_v17.dart';
import 'migrations/migration_v18.dart';
import 'migrations/migration_v19.dart';
import 'migrations/migration_v20.dart';
import 'migrations/migration_v21.dart';
import 'migrations/migration_v22.dart';
import 'migrations/migration_v23.dart';
import 'migrations/migration_v24.dart';
import 'migrations/migration_v25.dart';
import 'migrations/migration_v26.dart';
import 'migrations/migration_v27.dart';
import 'migrations/migration_v28.dart';
import 'migrations/migration_v29.dart';
import 'migrations/migration_v30.dart';

/// Local SQLite database manager for GlassFlow.
class AppDatabase {
  AppDatabase._();

  static Database? _db;
  static Directory? _appSupportDir;

  static Database get instance {
    final db = _db;
    if (db == null) {
      throw const DatabaseFailure('Database has not been initialized.');
    }
    return db;
  }

  static Directory get appSupportDir {
    final dir = _appSupportDir;
    if (dir == null) {
      throw const DatabaseFailure('App support directory is not ready.');
    }
    return dir;
  }

  static Directory get imagesDir =>
      Directory(p.join(appSupportDir.path, 'product_images'));

  static Directory get receiptsDir =>
      Directory(p.join(appSupportDir.path, 'receipts'));

  static Directory get backupsDir =>
      Directory(p.join(appSupportDir.path, 'backups'));

  static String get databasePath =>
      p.join(appSupportDir.path, AppConstants.databaseName);

  /// Must be called before [runApp].
  static Future<void> initialize({
    @visibleForTesting Directory? supportDir,
  }) async {
    if (_db != null) return;

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    _appSupportDir = supportDir ?? await getApplicationSupportDirectory();
    await imagesDir.create(recursive: true);
    await receiptsDir.create(recursive: true);
    await backupsDir.create(recursive: true);

    try {
      _db = await databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: AppConstants.databaseVersion,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async {
            await MigrationV1.up(db);
            if (version >= 2) await MigrationV2.up(db);
            if (version >= 3) await MigrationV3.up(db);
            if (version >= 4) await MigrationV4.up(db);
            if (version >= 5) await MigrationV5.up(db);
            if (version >= 6) await MigrationV6.up(db);
            if (version >= 7) await MigrationV7.up(db);
            if (version >= 8) await MigrationV8.up(db);
            if (version >= 9) await MigrationV9.up(db);
            if (version >= 10) await MigrationV10.up(db);
            if (version >= 11) await MigrationV11.up(db);
            if (version >= 12) await MigrationV12.up(db);
            if (version >= 13) await MigrationV13.up(db);
            if (version >= 14) await MigrationV14.up(db);
            if (version >= 15) await MigrationV15.up(db);
            if (version >= 16) await MigrationV16.up(db);
            if (version >= 17) await MigrationV17.up(db);
            if (version >= 18) await MigrationV18.up(db);
            if (version >= 19) await MigrationV19.up(db);
            if (version >= 20) await MigrationV20.up(db);
            if (version >= 21) await MigrationV21.up(db);
            if (version >= 22) await MigrationV22.up(db);
            if (version >= 23) await MigrationV23.up(db);
            if (version >= 24) await MigrationV24.up(db);
            if (version >= 25) await MigrationV25.up(db);
            if (version >= 26) await MigrationV26.up(db);
            if (version >= 27) await MigrationV27.up(db);
            if (version >= 28) await MigrationV28.up(db);
            if (version >= 29) await MigrationV29.up(db);
            if (version >= 30) await MigrationV30.up(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) await MigrationV2.up(db);
            if (oldVersion < 3) await MigrationV3.up(db);
            if (oldVersion < 4) await MigrationV4.up(db);
            if (oldVersion < 5) await MigrationV5.up(db);
            if (oldVersion < 6) await MigrationV6.up(db);
            if (oldVersion < 7) await MigrationV7.up(db);
            if (oldVersion < 8) await MigrationV8.up(db);
            if (oldVersion < 9) await MigrationV9.up(db);
            if (oldVersion < 10) await MigrationV10.up(db);
            if (oldVersion < 11) await MigrationV11.up(db);
            if (oldVersion < 12) await MigrationV12.up(db);
            if (oldVersion < 13) await MigrationV13.up(db);
            if (oldVersion < 14) await MigrationV14.up(db);
            if (oldVersion < 15) await MigrationV15.up(db);
            if (oldVersion < 16) await MigrationV16.up(db);
            if (oldVersion < 17) await MigrationV17.up(db);
            if (oldVersion < 18) await MigrationV18.up(db);
            if (oldVersion < 19) await MigrationV19.up(db);
            if (oldVersion < 20) await MigrationV20.up(db);
            if (oldVersion < 21) await MigrationV21.up(db);
            if (oldVersion < 22) await MigrationV22.up(db);
            if (oldVersion < 23) await MigrationV23.up(db);
            if (oldVersion < 24) await MigrationV24.up(db);
            if (oldVersion < 25) await MigrationV25.up(db);
            if (oldVersion < 26) await MigrationV26.up(db);
            if (oldVersion < 27) await MigrationV27.up(db);
            if (oldVersion < 28) await MigrationV28.up(db);
            if (oldVersion < 29) await MigrationV29.up(db);
            if (oldVersion < 30) await MigrationV30.up(db);
          },
          onOpen: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
        ),
      );
    } catch (e, st) {
      throw DatabaseFailure(
        'Failed to open database: $e',
        cause: st,
      );
    }
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Creates a timestamped backup copy. Never overwrites existing backups.
  static Future<File> backup() async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return backupTo(p.join(backupsDir.path, 'glassflow_backup_$stamp.db'));
  }

  /// Copies the live SQLite file to [destPath] after a WAL checkpoint.
  static Future<File> backupTo(String destPath) async {
    final db = instance;
    await db.execute('PRAGMA wal_checkpoint(FULL)');

    var dest = File(destPath);
    final ext = p.extension(dest.path).toLowerCase();
    if (ext != '.db' && ext != '.sqlite') {
      dest = File('${dest.path}.db');
    }
    if (p.equals(dest.path, databasePath)) {
      throw const FileFailure('Choose a different location than the live database.');
    }
    await dest.parent.create(recursive: true);
    if (await dest.exists()) {
      await dest.delete();
    }
    await File(databasePath).copy(dest.path);
    return dest;
  }

  /// Restores from [backupFile]. Validates SQLite header before replacing.
  static Future<void> restore(File backupFile) async {
    if (!await backupFile.exists()) {
      throw const FileFailure('Backup file does not exist.');
    }
    final bytes = await backupFile.openRead(0, 16).first;
    final header = String.fromCharCodes(bytes.take(15));
    if (!header.startsWith('SQLite format')) {
      throw const FileFailure('Selected file is not a valid SQLite database.');
    }

    await close();
    final current = File(databasePath);
    if (await current.exists()) {
      final safety = File(
        p.join(
          backupsDir.path,
          'pre_restore_${DateTime.now().millisecondsSinceEpoch}.db',
        ),
      );
      await current.copy(safety.path);
    }
    await backupFile.copy(databasePath);
    await initialize();
  }
}
