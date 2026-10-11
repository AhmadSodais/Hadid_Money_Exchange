import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/accounting/account.dart';
import '../../domain/money/currency.dart';
import '../../domain/security/permissions.dart';
import 'schema_v1.dart';

/// A versioned schema migration applied inside a single transaction.
final class SchemaMigration {
  const SchemaMigration(this.version, this.name, this.up);

  final int version;
  final String name;
  final Future<void> Function(Transaction txn) up;
}

/// Opens and migrates the single operational database.
///
/// Replaces the legacy three-database layout (`customers.db`, `balance.db`,
/// `removed_data.db`) with one relational, transactional store.
abstract final class ExchangeDatabase {
  static const String fileName = 'hadid_exchange.db';

  static final List<SchemaMigration> migrations = [
    SchemaMigration(1, 'initial_exchange_schema', (txn) async {
      for (final sql in schemaV1) {
        await txn.execute(sql);
      }
      await _seed(txn);
    }),
  ];

  static int get latestVersion => migrations.last.version;

  static bool _ffiReady = false;

  static DatabaseFactory get factory {
    if (!_ffiReady) {
      sqfliteFfiInit();
      _ffiReady = true;
    }
    return databaseFactoryFfi;
  }

  /// Opens [path], enables integrity pragmas, and applies pending migrations.
  static Future<Database> open(String path, {bool readOnly = false}) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        readOnly: readOnly,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          if (!readOnly) {
            await db.rawQuery('PRAGMA journal_mode = WAL');
            await db.execute('PRAGMA synchronous = FULL');
          }
          await db.execute('PRAGMA busy_timeout = 5000');
        },
      ),
    );
    if (!readOnly) await migrate(db);
    return db;
  }

  static Future<int> schemaVersion(DatabaseExecutor db) async {
    final exists = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='schema_migrations'",
    );
    if (exists.isEmpty) return 0;
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations',
    );
    return rows.first['v'] as int;
  }

  static Future<void> migrate(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        applied_at TEXT NOT NULL
      )
    ''');
    final current = await schemaVersion(db);
    if (current > latestVersion) {
      throw StateError(
        'Database schema v$current is newer than this application (v$latestVersion).',
      );
    }
    for (final m in migrations.where((m) => m.version > current)) {
      await db.transaction((txn) async {
        await m.up(txn);
        await txn.insert('schema_migrations', {
          'version': m.version,
          'name': m.name,
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        });
      });
    }
  }

  static Future<void> _seed(Transaction txn) async {
    final now = DateTime.now().toUtc().toIso8601String();

    for (final c in SeedCurrencies.all) {
      await txn.insert('currencies', {
        'code': c.code,
        'name_fa': c.nameFa,
        'symbol': c.symbol,
        'precision': c.precision,
        'rate_scale': c.rateScale,
        'rounding': c.rounding.name,
        'is_active': 1,
        'sort_order': c.sortOrder,
        'created_at': now,
        'updated_at': now,
      });
    }

    for (final p in Permissions.all.entries) {
      await txn.insert('permissions', {'code': p.key, 'description_fa': p.value});
    }
    const roleNames = {
      'admin': 'مدیر',
      'cashier': 'صندوقدار',
      'accountant': 'محاسب',
      'auditor': 'ممیز',
    };
    final roleIds = <String, int>{};
    for (final r in roleNames.entries) {
      roleIds[r.key] = await txn.insert('roles', {
        'code': r.key,
        'name_fa': r.value,
        'is_system': 1,
      });
      for (final perm in Permissions.roleDefaults[r.key]!) {
        await txn.insert('role_permissions', {
          'role_id': roleIds[r.key],
          'permission_code': perm,
        });
      }
    }
    // Owner account for the single-user deployment. It has no password; the
    // device is protected by the app lock until staff logins are enabled.
    await txn.insert('users', {
      'id': 1,
      'username': 'owner',
      'display_name': 'مالک',
      'role_id': roleIds['admin'],
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });

    await txn.insert('cash_drawers', {
      'id': 1,
      'code': 'MAIN',
      'name_fa': 'صندوق اصلی',
      'is_active': 1,
      'created_at': now,
    });

    await txn.insert('customers', {
      'id': 1,
      'code': 'WALK-IN',
      'name': 'مشتری متفرقه',
      'status': 'active',
      'is_walk_in': 1,
      'created_at': now,
      'updated_at': now,
    });

    Future<int> account(
      String code,
      String name,
      AccountType type,
      NormalSide side,
      AccountRole role, {
      int? parentId,
      int? customerId,
      int? drawerId,
    }) =>
        txn.insert('accounts', {
          'code': code,
          'name_fa': name,
          'type': type.name,
          'normal_side': side.name,
          'role': role.name,
          'parent_id': parentId,
          'customer_id': customerId,
          'drawer_id': drawerId,
          'is_active': 1,
          'is_system': 1,
          'created_at': now,
        });

    const d = NormalSide.debit;
    const c = NormalSide.credit;
    final assets = await account('1000', 'دارایی‌ها', AccountType.asset, d, AccountRole.control);
    final cash = await account('1100', 'صندوق‌ها', AccountType.asset, d, AccountRole.control,
        parentId: assets);
    await account('1101', 'صندوق اصلی', AccountType.asset, d, AccountRole.cash,
        parentId: cash, drawerId: 1);
    final liabilities =
        await account('2000', 'بدهی‌ها', AccountType.liability, c, AccountRole.control);
    final customers = await account(
        '2100', 'حسابات مشتریان', AccountType.liability, c, AccountRole.control,
        parentId: liabilities);
    await account('2100-000001', 'مشتری متفرقه', AccountType.liability, c,
        AccountRole.customer, parentId: customers, customerId: 1);
    final equity = await account('3000', 'سرمایه', AccountType.equity, c, AccountRole.control);
    await account('3100', 'سرمایه و بیلانس افتتاحیه', AccountType.equity, c,
        AccountRole.openingEquity, parentId: equity);
    await account('3200', 'اصلاحات مالی مجاز', AccountType.equity, c,
        AccountRole.adjustment, parentId: equity);
    await account('3300', 'موقعیت ارزی (حساب تبادله)', AccountType.clearing, c,
        AccountRole.exchangePosition, parentId: equity);
    final revenue = await account('4000', 'عواید', AccountType.revenue, c, AccountRole.control);
    await account('4100', 'کمیشن و فیس تبادله', AccountType.revenue, c,
        AccountRole.feeRevenue, parentId: revenue);
    await account('4200', 'عواید تفاوت نرخ (رزرو)', AccountType.revenue, c,
        AccountRole.spreadRevenue, parentId: revenue);
    final expense = await account('5000', 'مصارف', AccountType.expense, d, AccountRole.control);
    await account('5100', 'مصارف عملیاتی', AccountType.expense, d,
        AccountRole.operatingExpense, parentId: expense);
    await account('5200', 'کسر و اضافه صندوق', AccountType.expense, d,
        AccountRole.cashOverShort, parentId: expense);

    const settings = {
      'business.name': 'صرافی حدید',
      'posting.lock_reconciled_days': '1',
      'posting.max_backdate_days': '31',
      'posting.allow_negative_cash': '0',
      'reporting.currency': 'AFN',
      'backup.auto_enabled': '1',
      'backup.auto_interval_hours': '24',
      'backup.retention_count': '30',
    };
    for (final s in settings.entries) {
      await txn.insert('application_settings', {
        'key': s.key,
        'value': s.value,
        'updated_at': now,
      });
    }
  }
}
