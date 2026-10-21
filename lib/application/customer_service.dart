import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/errors/domain_errors.dart';
import '../domain/money/decimal.dart';
import '../domain/security/permissions.dart';
import '../domain/shared/ids.dart';
import 'audit_writer.dart';
import 'ledger_events.dart';
import 'read_models.dart';

final class CustomerInput {
  const CustomerInput({
    required this.name,
    this.phone,
    this.idDocument,
    this.address,
    this.notes,
  });

  final String name;
  final String? phone;
  final String? idDocument;
  final String? address;
  final String? notes;
}

/// Customer master data. Each customer gets exactly one multi-currency ledger
/// account (linked by foreign key) at creation time. Customers are never
/// deleted; they are deactivated or anonymized while history is preserved.
final class CustomerService {
  CustomerService(this._db, this._events);

  final Database _db;
  final LedgerEvents _events;

  Future<CustomerRecord> create(CustomerInput input, Actor actor, {String? legacyId}) async {
    _require(actor);
    final clean = validate(input);
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await _db.transaction((txn) async {
      final id = (await txn.rawQuery('SELECT COALESCE(MAX(id), 0) + 1 AS n FROM customers')).first['n'] as int;
      await txn.insert('customers', {
        ...clean,
        'id': id,
        'code': Ids.customer(id),
        'status': 'active',
        'is_walk_in': 0,
        'legacy_id': legacyId,
        'created_at': now,
        'updated_at': now,
      });
      await createLedgerAccount(txn, id, clean['name']! as String, now);
      await AuditWriter.write(txn,
          actor: actor,
          action: 'customer.create',
          entityType: 'customer',
          entityId: '$id',
          after: {'name': clean['name'], 'phone': clean['phone']});
      return id;
    });
    _events.notify(LedgerChange.customer);
    return (await byId(id))!;
  }

  static Future<void> createLedgerAccount(
      DatabaseExecutor txn, int customerId, String name, String now) async {
    final parent = await txn.query('accounts',
        columns: ['id'], where: 'code = ?', whereArgs: [Ids.customerAccountParent], limit: 1);
    await txn.insert('accounts', {
      'code': Ids.customerAccount(customerId),
      'name_fa': name,
      'type': 'liability',
      'normal_side': 'credit',
      'role': 'customer',
      'parent_id': parent.first['id'],
      'customer_id': customerId,
      'is_active': 1,
      'is_system': 0,
      'created_at': now,
    });
  }

  Future<CustomerRecord> update(int id, CustomerInput input, Actor actor) async {
    _require(actor);
    final clean = validate(input);
    await _db.transaction((txn) async {
      final before = await _row(txn, id);
      if (before['is_walk_in'] == 1) {
        throw const BusinessRuleError('customer.walkInFixed', 'مشتری متفرقه قابل ویرایش نیست.');
      }
      if (before['status'] == 'anonymized') {
        throw const BusinessRuleError('customer.anonymized', 'مشتری ناشناس‌شده قابل ویرایش نیست.');
      }
      await txn.update('customers',
          {...clean, 'updated_at': DateTime.now().toUtc().toIso8601String()},
          where: 'id = ?', whereArgs: [id]);
      await txn.update('accounts', {'name_fa': clean['name']},
          where: 'customer_id = ?', whereArgs: [id]);
      await AuditWriter.write(txn,
          actor: actor,
          action: 'customer.update',
          entityType: 'customer',
          entityId: '$id',
          before: {'name': before['name'], 'phone': before['phone']},
          after: {'name': clean['name'], 'phone': clean['phone']});
    });
    _events.notify(LedgerChange.customer);
    return (await byId(id))!;
  }

  Future<void> setActive(int id, bool active, Actor actor) async {
    _require(actor);
    await _db.transaction((txn) async {
      final before = await _row(txn, id);
      if (before['is_walk_in'] == 1) {
        throw const BusinessRuleError('customer.walkInFixed', 'مشتری متفرقه همیشه فعال است.');
      }
      if (before['status'] == 'anonymized') {
        throw const BusinessRuleError('customer.anonymized', 'مشتری ناشناس‌شده قابل فعال‌سازی نیست.');
      }
      await txn.update('customers', {
        'status': active ? 'active' : 'inactive',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, where: 'id = ?', whereArgs: [id]);
      await AuditWriter.write(txn,
          actor: actor,
          action: active ? 'customer.activate' : 'customer.deactivate',
          entityType: 'customer',
          entityId: '$id',
          before: {'status': before['status']},
          after: {'status': active ? 'active' : 'inactive'});
    });
    _events.notify(LedgerChange.customer);
  }

  /// Removes personal data while keeping the ledger intact. Only allowed when
  /// every currency position is zero.
  Future<void> anonymize(int id, Actor actor, {required String reason}) async {
    _require(actor);
    if (reason.trim().isEmpty) {
      throw const ValidationError('reason.required', 'ذکر دلیل الزامی است.', field: 'reason');
    }
    await _db.transaction((txn) async {
      final before = await _row(txn, id);
      if (before['is_walk_in'] == 1) {
        throw const BusinessRuleError('customer.walkInFixed', 'مشتری متفرقه قابل ناشناس‌سازی نیست.');
      }
      final open = await txn.rawQuery('''
        SELECT l.currency_code, SUM(l.credit_minor - l.debit_minor) AS pos
        FROM journal_lines l JOIN accounts a ON a.id = l.account_id
        WHERE a.customer_id = ? GROUP BY l.currency_code HAVING pos <> 0
      ''', [id]);
      if (open.isNotEmpty) {
        throw const BusinessRuleError('customer.openBalance',
            'تا زمانی که حساب مشتری صفر نشده، ناشناس‌سازی مجاز نیست.');
      }
      final label = 'مشتری ناشناس ${before['code']}';
      await txn.update('customers', {
        'name': label,
        'phone': null,
        'id_document': null,
        'address': null,
        'notes': null,
        'status': 'anonymized',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, where: 'id = ?', whereArgs: [id]);
      await txn.update('accounts', {'name_fa': label, 'is_active': 0},
          where: 'customer_id = ?', whereArgs: [id]);
      await AuditWriter.write(txn,
          actor: actor,
          action: 'customer.anonymize',
          entityType: 'customer',
          entityId: '$id',
          reason: reason.trim());
    });
    _events.notify(LedgerChange.customer);
  }

  Future<CustomerRecord?> byId(int id) async {
    final rows = await _db.query('customers', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : CustomerRecord.fromRow(rows.first);
  }

  Future<CustomerRecord> walkIn() async {
    final rows = await _db.query('customers', where: 'is_walk_in = 1', limit: 1);
    return CustomerRecord.fromRow(rows.first);
  }

  /// Search by name, phone, code, or numeric id. Excludes the walk-in record
  /// unless [includeWalkIn].
  ///
  /// Ordered with the walk-in (miscellaneous) customer first, then by id
  /// descending, so the most recently added customer appears at the top.
  Future<List<CustomerRecord>> search(
    String query, {
    bool includeInactive = false,
    bool includeWalkIn = false,
    int limit = 200,
    int offset = 0,
  }) async {
    final q = Decimal.normalizeDigits(query).trim();
    final where = <String>[];
    final args = <Object?>[];
    if (!includeInactive) where.add("status = 'active'");
    if (!includeWalkIn) where.add('is_walk_in = 0');
    if (q.isNotEmpty) {
      where.add('(name LIKE ? OR phone LIKE ? OR code LIKE ? OR CAST(id AS TEXT) = ?)');
      args.addAll(['%$q%', '%$q%', '%$q%', q]);
    }
    final rows = await _db.query(
      'customers',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'is_walk_in DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(CustomerRecord.fromRow).toList();
  }

  /// Normalized column values; throws [ValidationError] for invalid input.
  static Map<String, Object?> validate(CustomerInput input) {
    final name = input.name.trim();
    if (name.isEmpty) {
      throw const ValidationError('customer.name', 'نام مشتری الزامی است.', field: 'name');
    }
    if (name == 'مشتری متفرقه') {
      throw const ValidationError('customer.reservedName', 'این نام برای مشتری متفرقه رزرو است.',
          field: 'name');
    }
    String? opt(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final phone = opt(input.phone == null ? null : Decimal.normalizeDigits(input.phone!));
    if (phone != null && !RegExp(r'^\+?[0-9 \-]{6,20}$').hasMatch(phone)) {
      throw const ValidationError('customer.phone', 'شماره تماس معتبر نیست.', field: 'phone');
    }
    return {
      'name': name,
      'phone': phone,
      'id_document': opt(input.idDocument),
      'address': opt(input.address),
      'notes': opt(input.notes),
    };
  }

  Future<Map<String, Object?>> _row(DatabaseExecutor db, int id) async {
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw const NotFoundError('customer.notFound', 'مشتری پیدا نشد.');
    return rows.first;
  }

  static void _require(Actor actor) {
    if (!actor.can(Permissions.customersManage)) {
      throw const AuthorizationError('auth.denied', 'اجازه مدیریت مشتریان را ندارید.');
    }
  }
}
