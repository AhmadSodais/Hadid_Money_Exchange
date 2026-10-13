import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/errors/domain_errors.dart';
import '../domain/security/permissions.dart';
import '../domain/shared/business_date.dart';
import '../domain/shared/ids.dart';
import '../domain/transactions/financial_command.dart';
import 'audit_writer.dart';
import 'ledger_events.dart';
import 'posting_service.dart';
import 'read_models.dart';

/// Ledger-derived expectation for one drawer, currency, and business date.
final class ReconciliationSnapshot {
  const ReconciliationSnapshot({
    required this.drawerId,
    required this.currency,
    required this.date,
    required this.openingMinor,
    required this.inflowMinor,
    required this.outflowMinor,
  });

  final int drawerId;
  final String currency;
  final BusinessDate date;

  /// Cash balance from every posted line dated **before** [date] for this
  /// drawer and currency — never "the latest saved day" across currencies.
  final int openingMinor;
  final int inflowMinor;
  final int outflowMinor;

  int get expectedMinor => openingMinor + inflowMinor - outflowMinor;
}

/// Daily cash reconciliation (اخذ بیلانس روزانه).
///
/// * Expected closing = opening + net posted cash movements of the day.
/// * Difference = physical count − expected. The count never overwrites the
///   ledger; a discrepancy is kept as an explicit result and can be corrected
///   only by an authorized cash-adjustment transaction.
/// * Closing a day locks postings to that drawer/currency on or before the
///   date (setting `posting.lock_reconciled_days`). Reopening requires the
///   `reconciliation.reopen` permission and a reason.
final class ReconciliationService {
  ReconciliationService(this._db, this._posting, this._events);

  final Database _db;
  final PostingService _posting;
  final LedgerEvents _events;

  Future<ReconciliationSnapshot> compute(int drawerId, String currency, BusinessDate date,
      {DatabaseExecutor? using}) async {
    final rows = await (using ?? _db).rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN l.effective_date < ? THEN l.debit_minor - l.credit_minor END), 0) AS opening,
        COALESCE(SUM(CASE WHEN l.effective_date = ? THEN l.debit_minor END), 0) AS inflow,
        COALESCE(SUM(CASE WHEN l.effective_date = ? THEN l.credit_minor END), 0) AS outflow
      FROM journal_lines l JOIN accounts a ON a.id = l.account_id
      WHERE a.role = 'cash' AND a.drawer_id = ? AND l.currency_code = ?
        AND l.effective_date <= ?
    ''', [date.iso, date.iso, date.iso, drawerId, currency, date.iso]);
    final r = rows.first;
    return ReconciliationSnapshot(
      drawerId: drawerId,
      currency: currency,
      date: date,
      openingMinor: r['opening'] as int,
      inflowMinor: r['inflow'] as int,
      outflowMinor: r['outflow'] as int,
    );
  }

  Future<ReconciliationRecord?> active(int drawerId, String currency, BusinessDate date) async {
    final rows = await _db.query('reconciliation_records',
        where: "drawer_id = ? AND currency_code = ? AND business_date = ? AND status <> 'void'",
        whereArgs: [drawerId, currency, date.iso]);
    return rows.isEmpty ? null : ReconciliationRecord.fromRow(rows.first);
  }

  /// Records (or re-records) the physical count for an open day.
  Future<ReconciliationRecord> saveCount({
    required int drawerId,
    required String currency,
    required BusinessDate date,
    required int countedMinor,
    required Actor actor,
    String? notes,
  }) async {
    _require(actor, Permissions.reconciliationPerform);
    if (countedMinor < 0) {
      throw const ValidationError('count.negative', 'مقدار شمارش نمی‌تواند منفی باشد.',
          field: 'counted');
    }
    if (date.isAfter(BusinessDate.today())) {
      throw const ValidationError('date.future', 'بیلانس روز آینده قابل اخذ نیست.', field: 'date');
    }
    final id = await _db.transaction((txn) async {
      final snap = await compute(drawerId, currency, date, using: txn);
      final existing = await txn.query('reconciliation_records',
          where: "drawer_id = ? AND currency_code = ? AND business_date = ? AND status <> 'void'",
          whereArgs: [drawerId, currency, date.iso]);
      final values = {
        'opening_minor': snap.openingMinor,
        'inflow_minor': snap.inflowMinor,
        'outflow_minor': snap.outflowMinor,
        'expected_minor': snap.expectedMinor,
        'counted_minor': countedMinor,
        'difference_minor': countedMinor - snap.expectedMinor,
        'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
      };
      final int id;
      if (existing.isEmpty) {
        id = await txn.insert('reconciliation_records', {
          ...values,
          'drawer_id': drawerId,
          'currency_code': currency,
          'business_date': date.iso,
          'status': 'open',
          'created_by': actor.userId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        final row = existing.first;
        id = row['id'] as int;
        if (row['status'] == 'closed') {
          throw const BusinessRuleError('reconciliation.closed',
              'بیلانس این روز بسته شده است؛ برای شمارش مجدد ابتدا آن را باز کنید.');
        }
        final adjustmentId = row['adjustment_transaction_id'] as int?;
        if (adjustmentId != null) {
          final adj = await txn.query('transactions',
              columns: ['status'], where: 'id = ?', whereArgs: [adjustmentId]);
          if (adj.first['status'] == 'posted') {
            throw const BusinessRuleError('reconciliation.adjusted',
                'برای این روز اصلاح صندوق ثبت شده است؛ برای شمارش مجدد ابتدا اصلاح را برگشت کنید.');
          }
        }
        await txn.update(
            'reconciliation_records', {...values, 'adjustment_transaction_id': null},
            where: 'id = ?', whereArgs: [id]);
      }
      await AuditWriter.write(txn,
          actor: actor,
          action: 'reconciliation.count',
          entityType: 'reconciliation',
          entityId: '$id',
          after: {
            'currency': currency,
            'date': date.iso,
            'expected': snap.expectedMinor,
            'counted': countedMinor,
          });
      return id;
    });
    _events.notify(LedgerChange.reconciliation);
    return (await byId(id))!;
  }

  /// Posts an authorized cash adjustment equal to the recorded difference,
  /// dated on the reconciled business date, and links it to the record.
  Future<ReconciliationRecord> postAdjustment(int recordId, String reason, Actor actor) async {
    final rec = await byId(recordId);
    if (rec == null) throw const NotFoundError('reconciliation.notFound', 'رکورد پیدا نشد.');
    if (rec.status != 'open') {
      throw const BusinessRuleError('reconciliation.notOpen', 'فقط روزهای باز قابل اصلاح هستند.');
    }
    if (rec.adjustmentTransactionId != null) {
      throw const BusinessRuleError('reconciliation.adjusted', 'اصلاح قبلاً ثبت شده است.');
    }
    if (rec.differenceMinor == 0) {
      throw const BusinessRuleError('reconciliation.noDifference', 'اختلافی برای اصلاح وجود ندارد.');
    }
    final current = await compute(rec.drawerId, rec.currency, rec.businessDate);
    if (current.expectedMinor != rec.expectedMinor) {
      throw const BusinessRuleError('reconciliation.stale',
          'پس از شمارش، معاملات جدید ثبت شده است؛ ابتدا دوباره شمارش کنید.');
    }
    // A posted adjustment for this record that is not linked (the link write
    // failed after the posting committed) is re-linked, never duplicated.
    final keyPrefix = Ids.reconciliationKeyPrefix(recordId);
    final unlinked = await _db.rawQuery(
        "SELECT id FROM transactions WHERE idempotency_key LIKE ? AND status = 'posted' "
        'ORDER BY id DESC LIMIT 1',
        ['$keyPrefix%']);
    if (unlinked.isNotEmpty) {
      await _db.update('reconciliation_records',
          {'adjustment_transaction_id': unlinked.first['id']},
          where: 'id = ?', whereArgs: [recordId]);
      _events.notify(LedgerChange.reconciliation);
      return (await byId(recordId))!;
    }
    final prior = await _db.rawQuery(
        'SELECT COUNT(*) AS n FROM transactions WHERE idempotency_key LIKE ?',
        ['$keyPrefix%']);
    final tx = await _posting.post(
      CashAdjustmentCommand(
        idempotencyKey: '$keyPrefix${prior.first['n']}',
        effectiveDate: rec.businessDate,
        drawerId: rec.drawerId,
        currency: rec.currency,
        signedMinor: rec.differenceMinor,
        reason: reason,
        description: 'اصلاح اختلاف بیلانس ${rec.businessDate.iso}',
      ),
      actor,
    );
    await _db.update('reconciliation_records', {'adjustment_transaction_id': tx.id},
        where: 'id = ?', whereArgs: [recordId]);
    _events.notify(LedgerChange.reconciliation);
    return (await byId(recordId))!;
  }

  /// Closes the day. Fails if the ledger changed after the count.
  Future<ReconciliationRecord> close(int recordId, Actor actor) async {
    _require(actor, Permissions.reconciliationPerform);
    await _db.transaction((txn) async {
      final rows = await txn.query('reconciliation_records', where: 'id = ?', whereArgs: [recordId]);
      if (rows.isEmpty) throw const NotFoundError('reconciliation.notFound', 'رکورد پیدا نشد.');
      final rec = ReconciliationRecord.fromRow(rows.first);
      if (rec.status != 'open') {
        throw const BusinessRuleError('reconciliation.notOpen', 'این روز باز نیست.');
      }
      var adjustment = 0;
      if (rec.adjustmentTransactionId != null) {
        final adj = await txn.query('transactions',
            columns: ['signed_amount_minor', 'status'],
            where: 'id = ?',
            whereArgs: [rec.adjustmentTransactionId]);
        if (adj.first['status'] == 'posted') adjustment = adj.first['signed_amount_minor'] as int;
      }
      final current = await compute(rec.drawerId, rec.currency, rec.businessDate, using: txn);
      if (current.expectedMinor != rec.expectedMinor + adjustment) {
        throw const BusinessRuleError('reconciliation.stale',
            'پس از شمارش، معاملات این روز تغییر کرده است؛ ابتدا دوباره شمارش کنید.');
      }
      await txn.update('reconciliation_records', {
        'status': 'closed',
        'closed_by': actor.userId,
        'closed_at': DateTime.now().toUtc().toIso8601String(),
      }, where: 'id = ?', whereArgs: [recordId]);
      await AuditWriter.write(txn,
          actor: actor,
          action: 'reconciliation.close',
          entityType: 'reconciliation',
          entityId: '$recordId',
          after: {'difference': rec.differenceMinor, 'adjusted': adjustment != 0});
    });
    _events.notify(LedgerChange.reconciliation);
    return (await byId(recordId))!;
  }

  Future<ReconciliationRecord> reopen(int recordId, String reason, Actor actor) async {
    _require(actor, Permissions.reconciliationReopen);
    if (reason.trim().isEmpty) {
      throw const ValidationError('reason.required', 'ذکر دلیل بازگشایی الزامی است.',
          field: 'reason');
    }
    await _db.transaction((txn) async {
      final rows = await txn.query('reconciliation_records', where: 'id = ?', whereArgs: [recordId]);
      if (rows.isEmpty) throw const NotFoundError('reconciliation.notFound', 'رکورد پیدا نشد.');
      if (rows.first['status'] != 'closed') {
        throw const BusinessRuleError('reconciliation.notClosed', 'این روز بسته نیست.');
      }
      await txn.update('reconciliation_records', {'status': 'open'},
          where: 'id = ?', whereArgs: [recordId]);
      await AuditWriter.write(txn,
          actor: actor,
          action: 'reconciliation.reopen',
          entityType: 'reconciliation',
          entityId: '$recordId',
          reason: reason.trim(),
          before: {'status': 'closed'},
          after: {'status': 'open'});
    });
    _events.notify(LedgerChange.reconciliation);
    return (await byId(recordId))!;
  }

  /// Removes a mistaken count of an open day (status `void`; the row is kept
  /// for the audit trail). Not allowed after the day is closed or while a
  /// posted adjustment depends on the count.
  Future<void> voidCount(int recordId, String reason, Actor actor) async {
    _require(actor, Permissions.reconciliationPerform);
    if (reason.trim().isEmpty) {
      throw const ValidationError('reason.required', 'ذکر دلیل حذف شمارش الزامی است.',
          field: 'reason');
    }
    await _db.transaction((txn) async {
      final rows = await txn.query('reconciliation_records', where: 'id = ?', whereArgs: [recordId]);
      if (rows.isEmpty) throw const NotFoundError('reconciliation.notFound', 'رکورد پیدا نشد.');
      final rec = ReconciliationRecord.fromRow(rows.first);
      if (rec.status == 'closed') {
        throw const BusinessRuleError('reconciliation.closed',
            'بیلانس این روز بسته شده است؛ برای حذف شمارش ابتدا آن را باز کنید.');
      }
      if (rec.status == 'void') return;
      final adjustmentId = rec.adjustmentTransactionId;
      if (adjustmentId != null) {
        final adj = await txn.query('transactions',
            columns: ['status'], where: 'id = ?', whereArgs: [adjustmentId]);
        if (adj.isNotEmpty && adj.first['status'] == 'posted') {
          throw const BusinessRuleError('reconciliation.adjusted',
              'برای این شمارش اصلاح صندوق ثبت شده است؛ ابتدا سند اصلاح را از روزنامچه حذف کنید.');
        }
      }
      await txn.update('reconciliation_records', {'status': 'void'},
          where: 'id = ?', whereArgs: [recordId]);
      await AuditWriter.write(txn,
          actor: actor,
          action: 'reconciliation.void',
          entityType: 'reconciliation',
          entityId: '$recordId',
          reason: reason.trim(),
          before: {'status': rec.status, 'counted': rec.countedMinor},
          after: {'status': 'void'});
    });
    _events.notify(LedgerChange.reconciliation);
  }

  /// Days in [from]..[to] on which an active transaction moved cash of a
  /// currency in [drawerId] but no balance (count) was recorded for that
  /// currency — e.g. a day the operator forgot. Newest first.
  ///
  /// Deleted/edited originals and their same-day reversals cancel out and do
  /// not make a day "active"; a reversal dated on another day does.
  Future<List<({BusinessDate date, String currency})>> missingCounts(
    int drawerId, {
    required BusinessDate from,
    required BusinessDate to,
  }) async {
    final rows = await _db.rawQuery('''
      SELECT l.effective_date AS d, l.currency_code AS cur
      FROM journal_lines l
      JOIN accounts a ON a.id = l.account_id
      JOIN journal_entries e ON e.id = l.journal_entry_id
      JOIN transactions t ON t.id = e.transaction_id
      JOIN currencies c ON c.code = l.currency_code
      WHERE a.role = 'cash' AND a.drawer_id = ? AND c.is_active = 1
        AND l.effective_date BETWEEN ? AND ?
        AND (
          (t.status = 'posted' AND t.type <> 'reversal')
          OR (t.status = 'reversed' AND t.effective_date <>
                (SELECT r.effective_date FROM transactions r WHERE r.id = t.reversed_by_transaction_id))
          OR (t.type = 'reversal' AND t.effective_date <>
                (SELECT o.effective_date FROM transactions o WHERE o.id = t.reverses_transaction_id))
        )
        AND NOT EXISTS (
          SELECT 1 FROM reconciliation_records rr
          WHERE rr.drawer_id = a.drawer_id AND rr.currency_code = l.currency_code
            AND rr.business_date = l.effective_date AND rr.status <> 'void')
      GROUP BY l.effective_date, l.currency_code
      ORDER BY l.effective_date DESC, MIN(c.sort_order)
    ''', [drawerId, from.iso, to.iso]);
    return [
      for (final r in rows)
        (date: BusinessDate.parse(r['d'] as String), currency: r['cur'] as String),
    ];
  }

  Future<ReconciliationRecord?> byId(int id) async {
    final rows = await _db.query('reconciliation_records', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : ReconciliationRecord.fromRow(rows.first);
  }

  Future<List<ReconciliationRecord>> records({
    BusinessDate? from,
    BusinessDate? to,
    int? drawerId,
    String? currency,
    bool includeVoid = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('business_date >= ?');
      args.add(from.iso);
    }
    if (to != null) {
      where.add('business_date <= ?');
      args.add(to.iso);
    }
    if (drawerId != null) {
      where.add('drawer_id = ?');
      args.add(drawerId);
    }
    if (currency != null) {
      where.add('currency_code = ?');
      args.add(currency);
    }
    if (!includeVoid) where.add("status <> 'void'");
    final rows = await _db.query('reconciliation_records',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'business_date DESC, currency_code');
    return rows.map(ReconciliationRecord.fromRow).toList();
  }

  static void _require(Actor actor, String permission) {
    if (!actor.can(permission)) {
      throw AuthorizationError('auth.denied', 'اجازه این عملیات را ندارید ($permission).');
    }
  }
}
