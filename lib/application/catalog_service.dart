import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/errors/domain_errors.dart';
import '../domain/money/currency.dart';
import '../domain/money/decimal.dart';
import '../domain/security/permissions.dart';
import 'audit_writer.dart';
import 'ledger_events.dart';

final class CashDrawer {
  const CashDrawer(this.id, this.code, this.nameFa, this.isActive);
  final int id;
  final String code;
  final String nameFa;
  final bool isActive;
}

/// Currency catalog, drawers, and application settings.
final class CatalogService {
  CatalogService(this._db, this._events);

  final Database _db;
  final LedgerEvents _events;

  Future<Map<String, Currency>> currencies({DatabaseExecutor? using}) async {
    final rows = await (using ?? _db).query('currencies', orderBy: 'sort_order, code');
    return {for (final r in rows) r['code'] as String: _currencyFromRow(r)};
  }

  Future<List<Currency>> activeCurrencies() async =>
      (await currencies()).values.where((c) => c.isActive).toList();

  static Currency _currencyFromRow(Map<String, Object?> r) => Currency(
        code: r['code'] as String,
        nameFa: r['name_fa'] as String,
        symbol: r['symbol'] as String,
        precision: r['precision'] as int,
        rateScale: r['rate_scale'] as int,
        rounding: RoundingMode.parse(r['rounding'] as String),
        isActive: (r['is_active'] as int) == 1,
        sortOrder: r['sort_order'] as int,
      );

  /// Adds a new currency to the catalog. Existing financial records are
  /// unaffected; accounts are multi-currency so no new accounts are needed.
  Future<void> addCurrency(Currency c, Actor actor) async {
    _require(actor, Permissions.settingsManage);
    final code = c.code.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3,8}$').hasMatch(code)) {
      throw const ValidationError('currency.code', 'کد ارز باید ۳ تا ۸ حرف لاتین باشد.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      final exists = await txn.query('currencies', where: 'code = ?', whereArgs: [code]);
      if (exists.isNotEmpty) {
        throw BusinessRuleError('currency.exists', 'ارز $code از قبل وجود دارد.');
      }
      await txn.insert('currencies', {
        'code': code,
        'name_fa': c.nameFa.trim(),
        'symbol': c.symbol.trim(),
        'precision': c.precision,
        'rate_scale': c.rateScale,
        'rounding': c.rounding.name,
        'is_active': 1,
        'sort_order': c.sortOrder,
        'created_at': now,
        'updated_at': now,
      });
      await AuditWriter.write(txn,
          actor: actor, action: 'currency.add', entityType: 'currency', entityId: code);
    });
    _events.notify(LedgerChange.reference);
  }

  /// Updates display attributes. Precision is protected by a trigger once
  /// postings exist in the currency.
  Future<void> updateCurrency(Currency c, Actor actor) async {
    _require(actor, Permissions.settingsManage);
    await _db.transaction((txn) async {
      await txn.update(
        'currencies',
        {
          'name_fa': c.nameFa.trim(),
          'symbol': c.symbol.trim(),
          'precision': c.precision,
          'rate_scale': c.rateScale,
          'rounding': c.rounding.name,
          'is_active': c.isActive ? 1 : 0,
          'sort_order': c.sortOrder,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'code = ?',
        whereArgs: [c.code],
      );
      await AuditWriter.write(txn,
          actor: actor, action: 'currency.update', entityType: 'currency', entityId: c.code);
    });
    _events.notify(LedgerChange.reference);
  }

  Future<List<CashDrawer>> drawers() async {
    final rows = await _db.query('cash_drawers', orderBy: 'id');
    return [
      for (final r in rows)
        CashDrawer(r['id'] as int, r['code'] as String, r['name_fa'] as String,
            (r['is_active'] as int) == 1),
    ];
  }

  Future<int> walkInCustomerId({DatabaseExecutor? using}) async {
    final rows = await (using ?? _db)
        .query('customers', columns: ['id'], where: 'is_walk_in = 1', limit: 1);
    if (rows.isEmpty) {
      throw const InvariantViolation('customer.walkInMissing', 'مشتری متفرقه تعریف نشده است.');
    }
    return rows.first['id'] as int;
  }

  Future<String?> setting(String key, {DatabaseExecutor? using}) async {
    final rows = await (using ?? _db)
        .query('application_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> putSetting(String key, String value, Actor actor) async {
    _require(actor, Permissions.settingsManage);
    await _db.transaction((txn) async {
      final before = await setting(key, using: txn);
      await txn.insert(
        'application_settings',
        {'key': key, 'value': value, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await AuditWriter.write(txn,
          actor: actor,
          action: 'setting.update',
          entityType: 'setting',
          entityId: key,
          before: {'value': before},
          after: {'value': value});
    });
    _events.notify(LedgerChange.reference);
  }

  static void _require(Actor actor, String permission) {
    if (!actor.can(permission)) {
      throw AuthorizationError('auth.denied', 'اجازه این عملیات را ندارید ($permission).');
    }
  }
}
