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

  /// The single shared main cashbox: the first (seeded) drawer. All cash —
  /// the exchange's own capital and customer funds alike — is pooled in
  /// this one fund; there are no separate cash drawers anymore.
  Future<CashDrawer?> mainCashbox() async {
    final all = await drawers();
    return all.isEmpty ? null : all.first;
  }

  /// Adds a cash drawer together with its cash account under 1100.
  ///
  /// Disabled under the single-cashbox model: every amount lives in the
  /// main cashbox, so creating a separate drawer is rejected.
  Future<CashDrawer> addDrawer(String name, Actor actor) async {
    _require(actor, Permissions.settingsManage);
    throw const BusinessRuleError('cashbox.single',
        'در مدل تک‌صندوقی، همه وجوه در صندوق اصلی مشترک نگهداری می‌شود و ساخت صندوق جداگانه ممکن نیست.');
  }

  /// Renames or (de)activates a drawer. A drawer can be deactivated only
  /// while its cash is zero in every currency, and never the last active one.
  Future<void> updateDrawer(int id, {required String name, required bool isActive, required Actor actor}) async {
    _require(actor, Permissions.settingsManage);
    final clean = name.trim();
    if (clean.isEmpty) throw const ValidationError('drawer.name', 'نام صندوق الزامی است.');
    await _db.transaction((txn) async {
      final rows = await txn.query('cash_drawers', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw const BusinessRuleError('drawer.missing', 'صندوق پیدا نشد.');
      final before = rows.first;
      // Single-cashbox model: only the main (first) cashbox may be active.
      // Legacy extra drawers may be renamed or deactivated for cleanup,
      // but never (re)activated, and the main cashbox never deactivates.
      final mainId = (await txn.rawQuery('SELECT MIN(id) AS n FROM cash_drawers')).first['n'] as int?;
      if (isActive && mainId != null && id != mainId) {
        throw const BusinessRuleError('cashbox.single',
            'در مدل تک‌صندوقی فقط صندوق اصلی مشترک فعال است و صندوق دیگری فعال نمی‌شود.');
      }
      if (!isActive && mainId != null && id == mainId) {
        throw const BusinessRuleError(
            'cashbox.mainRequired', 'صندوق اصلی مشترک تنها صندوق سیستم است و غیرفعال نمی‌شود.');
      }
      await _requireUniqueDrawerName(txn, clean, exceptId: id);
      if (!isActive && before['is_active'] == 1) {
        final others = await txn.rawQuery(
            'SELECT COUNT(*) AS n FROM cash_drawers WHERE is_active = 1 AND id <> ?', [id]);
        if ((others.first['n'] as int) == 0) {
          throw const BusinessRuleError('drawer.lastActive', 'دست‌کم یک صندوق باید فعال بماند.');
        }
        final open = await txn.rawQuery('''
          SELECT l.currency_code FROM journal_lines l JOIN accounts a ON a.id = l.account_id
          WHERE a.role = 'cash' AND a.drawer_id = ?
          GROUP BY l.currency_code HAVING SUM(l.debit_minor - l.credit_minor) <> 0
        ''', [id]);
        if (open.isNotEmpty) {
          throw BusinessRuleError('drawer.openBalance',
              'تا زمانی که موجودی صندوق صفر نشده، غیرفعال کردن آن مجاز نیست '
              '(${open.map((r) => r['currency_code']).join('، ')}).');
        }
      }
      await txn.update('cash_drawers', {'name_fa': clean, 'is_active': isActive ? 1 : 0},
          where: 'id = ?', whereArgs: [id]);
      await txn.update('accounts', {'name_fa': clean, 'is_active': isActive ? 1 : 0},
          where: "role = 'cash' AND drawer_id = ?", whereArgs: [id]);
      await AuditWriter.write(txn,
          actor: actor,
          action: 'drawer.update',
          entityType: 'drawer',
          entityId: '$id',
          before: {'name': before['name_fa'], 'active': before['is_active'] == 1},
          after: {'name': clean, 'active': isActive});
    });
    _events.notify(LedgerChange.reference);
  }

  static Future<void> _requireUniqueDrawerName(DatabaseExecutor txn, String name, {int? exceptId}) async {
    final dup = await txn.rawQuery(
      'SELECT 1 FROM cash_drawers WHERE lower(trim(name_fa)) = lower(?) ${exceptId == null ? '' : 'AND id <> ?'} LIMIT 1',
      [name, ?exceptId],
    );
    if (dup.isNotEmpty) throw BusinessRuleError('drawer.exists', 'صندوقی با نام «$name» از قبل وجود دارد.');
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
