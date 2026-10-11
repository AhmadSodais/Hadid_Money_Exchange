import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../domain/accounting/account.dart';
import '../domain/accounting/journal.dart';
import '../domain/accounting/posting_rules.dart';
import '../domain/errors/domain_errors.dart';
import '../domain/exchange/exchange_rate.dart';
import '../domain/security/permissions.dart';
import '../domain/shared/business_date.dart';
import '../domain/transactions/financial_command.dart';
import 'audit_writer.dart';
import 'catalog_service.dart';
import 'ledger_events.dart';
import 'read_models.dart';

/// The single entry point that writes financial records.
///
/// For every command it: authorizes, validates, builds a balanced journal via
/// [PostingRules], then inside **one** database transaction inserts the
/// business transaction, every journal line, supporting workflow rows, and the
/// audit event. Any failure rolls the whole operation back. Listeners are
/// notified only after the commit succeeds.
final class PostingService {
  PostingService(this._db, this._catalog, this._events, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final CatalogService _catalog;
  final LedgerEvents _events;
  final DateTime Function() _clock;

  static const _uuid = Uuid();

  /// Creates a fresh idempotency key for a form submission.
  static String newIdempotencyKey() => _uuid.v4();

  // ------------------------------------------------------------------ post

  Future<PostedTransaction> post(FinancialCommand command, Actor actor) async {
    _authorize(command, actor);
    final existing = await _byIdempotencyKey(_db, command.idempotencyKey);
    if (existing != null) return _sameOrConflict(existing, command.type);

    final int txId;
    try {
      final currencies = await _catalog.currencies();
      final walkIn = await _catalog.walkInCustomerId();
      final plan = PostingRules(currencies, walkInCustomerId: walkIn).plan(command);
      await _validateDate(command.effectiveDate);

      txId = await _db.transaction((txn) async {
        final raced = await _byIdempotencyKey(txn, command.idempotencyKey);
        if (raced != null) return raced.id;

        await _checkParties(txn, command);
        await _checkClosedDays(txn, plan.journal, command.effectiveDate);
        await _checkNegativeCash(txn, plan.journal, command.effectiveDate);
        if (command is OpeningCashCommand || command is OpeningCustomerCommand) {
          await _checkOpeningUnique(txn, command);
        }

        final id = await _insertTransaction(txn, command, plan, actor);
        await _insertJournal(txn, id, command.effectiveDate, command.description,
            plan.journal);
        await _afterInsert(txn, id, command);
        await AuditWriter.write(txn,
            actor: actor,
            action: 'transaction.post',
            entityType: 'transaction',
            entityId: '$id',
            transactionId: id,
            reason: _reasonOf(command),
            after: {'type': command.type.name, 'lines': plan.journal.lines.length});
        return id;
      });
    } on DomainError catch (e) {
      await _auditFailure(actor, 'transaction.post', command.type.name, e.message);
      rethrow;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError('transactions.idempotency_key')) {
        final again = await _byIdempotencyKey(_db, command.idempotencyKey);
        if (again != null) return again;
      }
      await _auditFailure(actor, 'transaction.post', command.type.name, '$e');
      throw PersistenceError('db.write', _friendlyDbError(e), cause: e);
    }

    _events.notify(LedgerChange.posting);
    return (await transactionById(txId))!;
  }

  // --------------------------------------------------------------- reverse

  /// Reverses the **whole** posted transaction (every currency leg) with an
  /// equal and opposite journal. The original stays in the ledger, marked
  /// `reversed`, and both records reference each other.
  Future<PostedTransaction> reverse({
    required int transactionId,
    required String reason,
    required Actor actor,
    required String idempotencyKey,
    BusinessDate? effectiveDate,
  }) async {
    if (!actor.can(Permissions.transactionsReverse)) {
      throw const AuthorizationError('auth.denied', 'اجازه برگشت معامله را ندارید.');
    }
    if (reason.trim().isEmpty) {
      throw const ValidationError('reason.required', 'ذکر دلیل برگشت الزامی است.',
          field: 'reason');
    }
    final existing = await _byIdempotencyKey(_db, idempotencyKey);
    if (existing != null) return _sameOrConflict(existing, TransactionType.reversal);

    final date = effectiveDate ?? BusinessDate.today(_clock());
    final int revId;
    try {
      await _validateDate(date);
      revId = await _db.transaction((txn) async {
        final rows = await txn.query('transactions', where: 'id = ?', whereArgs: [transactionId]);
        if (rows.isEmpty) {
          throw const NotFoundError('transaction.notFound', 'معامله پیدا نشد.');
        }
        final original = rows.first;
        if (original['type'] == TransactionType.reversal.name) {
          throw const BusinessRuleError('reversal.ofReversal',
              'سند برگشت قابل برگشت نیست؛ معامله صحیح را دوباره ثبت کنید.');
        }
        if (original['status'] != TransactionStatus.posted.name) {
          throw const BusinessRuleError('reversal.repeated', 'این معامله قبلاً برگشت شده است.');
        }

        final lineRows = await txn.rawQuery('''
          SELECT l.account_id, l.currency_code, l.debit_minor, l.credit_minor, l.memo
          FROM journal_lines l JOIN journal_entries e ON e.id = l.journal_entry_id
          WHERE e.transaction_id = ? ORDER BY l.line_no
        ''', [transactionId]);
        final journal = JournalDraft([
          for (final l in lineRows)
            JournalLineDraft(
              account: ResolvedAccountRef(l['account_id'] as int),
              currency: l['currency_code'] as String,
              debitMinor: l['debit_minor'] as int,
              creditMinor: l['credit_minor'] as int,
              memo: l['memo'] as String?,
            ),
        ]).reversed();
        journal.validate();
        await _checkClosedDays(txn, journal, date);
        await _checkNegativeCash(txn, journal, date);

        final now = _clock().toUtc().toIso8601String();
        final type = TransactionType.reversal;
        final id = await txn.insert('transactions', {
          'uuid': _uuid.v4(),
          'reference_no': await _nextReference(txn, type),
          'type': type.name,
          'status': TransactionStatus.posted.name,
          'customer_id': original['customer_id'],
          'drawer_id': original['drawer_id'],
          'effective_date': date.iso,
          'created_at': now,
          'posted_at': now,
          'created_by': actor.userId,
          'description': 'برگشت ${original['reference_no']}',
          'source_currency': original['source_currency'],
          'source_amount_minor': original['source_amount_minor'],
          'dest_currency': original['dest_currency'],
          'dest_amount_minor': original['dest_amount_minor'],
          'rate': original['rate'],
          'rate_convention': original['rate_convention'],
          'signed_amount_minor': original['signed_amount_minor'],
          'reverses_transaction_id': transactionId,
          'reason': reason.trim(),
          'idempotency_key': idempotencyKey,
        });
        await _insertJournal(txn, id, date, 'برگشت ${original['reference_no']}', journal);
        await txn.update(
          'transactions',
          {'status': TransactionStatus.reversed.name, 'reversed_by_transaction_id': id},
          where: 'id = ?',
          whereArgs: [transactionId],
        );
        await txn.update('opening_balances', {'is_active': 0},
            where: 'transaction_id = ?', whereArgs: [transactionId]);
        await AuditWriter.write(txn,
            actor: actor,
            action: 'transaction.reverse',
            entityType: 'transaction',
            entityId: '$transactionId',
            transactionId: id,
            reason: reason.trim(),
            before: {'status': 'posted'},
            after: {'status': 'reversed', 'reversal_id': id});
        return id;
      });
    } on DomainError catch (e) {
      await _auditFailure(actor, 'transaction.reverse', '$transactionId', e.message);
      rethrow;
    } on DatabaseException catch (e) {
      await _auditFailure(actor, 'transaction.reverse', '$transactionId', '$e');
      throw PersistenceError('db.write', _friendlyDbError(e), cause: e);
    }

    _events.notify(LedgerChange.posting);
    return (await transactionById(revId))!;
  }

  // ----------------------------------------------------------------- reads

  Future<PostedTransaction?> transactionById(int id, {DatabaseExecutor? using}) async {
    final db = using ?? _db;
    final rows = await db.rawQuery('''
      SELECT t.*, c.name AS customer_name, u.display_name AS created_by_name
      FROM transactions t
      LEFT JOIN customers c ON c.id = t.customer_id
      LEFT JOIN users u ON u.id = t.created_by
      WHERE t.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    final lines = await db.rawQuery('''
      SELECT l.line_no, l.account_id, a.code AS account_code, a.name_fa AS account_name,
             l.currency_code, l.debit_minor, l.credit_minor, l.memo
      FROM journal_lines l
      JOIN journal_entries e ON e.id = l.journal_entry_id
      JOIN accounts a ON a.id = l.account_id
      WHERE e.transaction_id = ? ORDER BY l.line_no
    ''', [id]);
    return PostedTransaction.fromRow(rows.first,
        lines: lines.map(JournalLineView.fromRow).toList());
  }

  // --------------------------------------------------------------- helpers

  void _authorize(FinancialCommand c, Actor actor) {
    final needed = switch (c) {
      OpeningCashCommand() || OpeningCustomerCommand() => Permissions.openingBalancesPost,
      CashAdjustmentCommand() || CustomerAdjustmentCommand() => Permissions.adjustmentsPost,
      _ => Permissions.transactionsPost,
    };
    if (!actor.can(needed)) {
      throw AuthorizationError('auth.denied', 'اجازه این عملیات را ندارید ($needed).');
    }
  }

  PostedTransaction _sameOrConflict(PostedTransaction existing, TransactionType type) {
    if (existing.type != type) {
      throw const BusinessRuleError('idempotency.conflict',
          'کلید یکتای این فرم قبلاً برای معامله دیگری استفاده شده است.');
    }
    return existing;
  }

  Future<PostedTransaction?> _byIdempotencyKey(DatabaseExecutor db, String key) async {
    final rows = await db.query('transactions',
        columns: ['id'], where: 'idempotency_key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return transactionById(rows.first['id'] as int, using: db);
  }

  Future<void> _validateDate(BusinessDate date) async {
    final today = BusinessDate.today(_clock());
    if (date.isAfter(today)) {
      throw const ValidationError('date.future', 'ثبت معامله با تاریخ آینده مجاز نیست.',
          field: 'date');
    }
    final maxBack = int.tryParse(await _catalog.setting('posting.max_backdate_days') ?? '') ?? 0;
    if (maxBack > 0 && date.daysUntil(today) > maxBack) {
      throw ValidationError('date.tooOld',
          'ثبت معامله با تاریخ بیش از $maxBack روز قبل مجاز نیست (تنظیمات).',
          field: 'date');
    }
  }

  Future<void> _checkParties(Transaction txn, FinancialCommand c) async {
    final customerId = switch (c) {
      ReceiptCommand x => x.customerId,
      PaymentCommand x => x.customerId,
      ExchangeCommand x => x.customerId,
      OpeningCustomerCommand x => x.customerId,
      CustomerAdjustmentCommand x => x.customerId,
      _ => null,
    };
    if (customerId != null) {
      final rows = await txn.query('customers',
          columns: ['status'], where: 'id = ?', whereArgs: [customerId]);
      if (rows.isEmpty) {
        throw const NotFoundError('customer.notFound', 'مشتری پیدا نشد.');
      }
      if (rows.first['status'] != 'active') {
        throw const BusinessRuleError(
            'customer.inactive', 'مشتری غیرفعال است؛ ابتدا آن را فعال کنید.');
      }
    }
    final drawerId = _drawerOf(c);
    if (drawerId != null) {
      final rows = await txn.query('cash_drawers',
          columns: ['is_active'], where: 'id = ?', whereArgs: [drawerId]);
      if (rows.isEmpty || rows.first['is_active'] != 1) {
        throw const BusinessRuleError('drawer.inactive', 'صندوق انتخاب‌شده فعال نیست.');
      }
    }
  }

  /// Rejects postings that change cash of a drawer/currency on or before a
  /// day whose reconciliation is closed (setting `posting.lock_reconciled_days`).
  Future<void> _checkClosedDays(
      Transaction txn, JournalDraft journal, BusinessDate date) async {
    final lock = await _catalog.setting('posting.lock_reconciled_days', using: txn);
    if (lock == '0') return;
    final cashScopes = <(int, String)>{};
    for (final line in journal.lines) {
      final drawerId = await _drawerForAccountRef(txn, line.account);
      if (drawerId != null) cashScopes.add((drawerId, line.currency));
    }
    for (final (drawerId, currency) in cashScopes) {
      final rows = await txn.rawQuery('''
        SELECT MAX(business_date) AS d FROM reconciliation_records
        WHERE drawer_id = ? AND currency_code = ? AND status = 'closed'
      ''', [drawerId, currency]);
      final closed = rows.first['d'] as String?;
      if (closed != null && date.iso.compareTo(closed) <= 0) {
        throw BusinessRuleError('day.closed',
            'بیلانس روز $closed برای $currency بسته شده است؛ ثبت معامله در این تاریخ یا قبل از آن مجاز نیست.');
      }
    }
  }

  /// Physical cash cannot be negative. Rejects a posting if the drawer's
  /// balance in any affected currency would drop below zero on the effective
  /// date or on any later date (backdated outflows are checked too).
  /// Disabled when `posting.allow_negative_cash` = 1.
  Future<void> _checkNegativeCash(
      Transaction txn, JournalDraft journal, BusinessDate date) async {
    if (await _catalog.setting('posting.allow_negative_cash', using: txn) == '1') return;
    final nets = <(int, String), int>{};
    for (final line in journal.lines) {
      final drawerId = await _drawerForAccountRef(txn, line.account);
      if (drawerId == null) continue;
      nets.update((drawerId, line.currency), (v) => v + line.net, ifAbsent: () => line.net);
    }
    for (final MapEntry(key: (drawerId, currency), value: net) in nets.entries) {
      if (net >= 0) continue;
      final rows = await txn.rawQuery('''
        SELECT
          (SELECT COALESCE(SUM(l.debit_minor - l.credit_minor), 0)
             FROM journal_lines l JOIN accounts a ON a.id = l.account_id
             WHERE a.drawer_id = ? AND l.currency_code = ? AND l.effective_date <= ?) AS at_date,
          (SELECT GROUP_CONCAT(d.n, ',') FROM (
             SELECT SUM(l.debit_minor - l.credit_minor) AS n
             FROM journal_lines l JOIN accounts a ON a.id = l.account_id
             WHERE a.drawer_id = ? AND l.currency_code = ? AND l.effective_date > ?
             GROUP BY l.effective_date ORDER BY l.effective_date) d) AS later
      ''', [drawerId, currency, date.iso, drawerId, currency, date.iso]);
      var running = (rows.first['at_date'] as int) + net;
      var minimum = running;
      final later = rows.first['later'] as String?;
      if (later != null) {
        for (final part in later.split(',')) {
          running += int.parse(part);
          if (running < minimum) minimum = running;
        }
      }
      if (minimum < 0) {
        throw BusinessRuleError('cash.insufficient',
            'موجودی صندوق در $currency کافی نیست؛ این معامله موجودی را منفی می‌کند.');
      }
    }
  }

  Future<int?> _drawerForAccountRef(DatabaseExecutor db, AccountRef ref) async {
    switch (ref) {
      case CashAccountRef(:final drawerId):
        return drawerId;
      case ResolvedAccountRef(:final accountId):
        final rows = await db.query('accounts',
            columns: ['drawer_id'], where: 'id = ?', whereArgs: [accountId]);
        return rows.isEmpty ? null : rows.first['drawer_id'] as int?;
      default:
        return null;
    }
  }

  Future<void> _checkOpeningUnique(Transaction txn, FinancialCommand c) async {
    final List<Map<String, Object?>> rows;
    if (c is OpeningCashCommand) {
      rows = await txn.query('opening_balances',
          where: "kind = 'cash' AND drawer_id = ? AND currency_code = ? AND is_active = 1",
          whereArgs: [c.drawerId, c.currency]);
    } else if (c is OpeningCustomerCommand) {
      rows = await txn.query('opening_balances',
          where: "kind = 'customer' AND customer_id = ? AND currency_code = ? AND is_active = 1",
          whereArgs: [c.customerId, c.currency]);
    } else {
      return;
    }
    if (rows.isNotEmpty) {
      throw const BusinessRuleError('opening.duplicate',
          'بیلانس افتتاحیه برای این ارز قبلاً ثبت شده است. برای تغییر، آن را برگشت کنید یا اصلاح مجاز ثبت کنید.');
    }
  }

  Future<int> _insertTransaction(
      Transaction txn, FinancialCommand c, PostingPlan plan, Actor actor) async {
    final now = _clock().toUtc().toIso8601String();
    final row = <String, Object?>{
      'uuid': _uuid.v4(),
      'reference_no': await _nextReference(txn, c.type),
      'type': c.type.name,
      'status': TransactionStatus.posted.name,
      'effective_date': c.effectiveDate.iso,
      'created_at': now,
      'posted_at': now,
      'created_by': actor.userId,
      'description': c.description?.trim().isEmpty ?? true ? null : c.description!.trim(),
      'idempotency_key': c.idempotencyKey,
    };
    switch (c) {
      case ReceiptCommand x:
        row.addAll({
          'customer_id': x.customerId,
          'drawer_id': x.drawerId,
          'source_currency': x.currency,
          'source_amount_minor': x.amountMinor,
        });
      case PaymentCommand x:
        row.addAll({
          'customer_id': x.customerId,
          'drawer_id': x.drawerId,
          'source_currency': x.currency,
          'source_amount_minor': x.amountMinor,
        });
      case ExchangeCommand x:
        row.addAll({
          'customer_id': x.customerId,
          'drawer_id': x.drawerId,
          'source_currency': x.baseCurrency,
          'source_amount_minor': x.baseAmountMinor,
          'dest_currency': x.quoteCurrency,
          'dest_amount_minor': plan.quoteAmountMinor,
          'rate': x.rate.toCanonical(),
          'rate_convention': kRateConvention,
          'source_settlement': x.baseSettlement.name,
          'dest_settlement': x.quoteSettlement.name,
          'fee_currency': x.fee?.currency,
          'fee_amount_minor': x.fee?.amountMinor,
          'fee_settlement': x.fee?.settlement.name,
        });
      case OpeningCashCommand x:
        row.addAll({
          'drawer_id': x.drawerId,
          'source_currency': x.currency,
          'source_amount_minor': x.amountMinor,
        });
      case OpeningCustomerCommand x:
        row.addAll({
          'customer_id': x.customerId,
          'source_currency': x.currency,
          'source_amount_minor': x.signedMinor.abs(),
          'signed_amount_minor': x.signedMinor,
        });
      case CashAdjustmentCommand x:
        row.addAll({
          'drawer_id': x.drawerId,
          'source_currency': x.currency,
          'source_amount_minor': x.signedMinor.abs(),
          'signed_amount_minor': x.signedMinor,
          'reason': x.reason.trim(),
        });
      case CustomerAdjustmentCommand x:
        row.addAll({
          'customer_id': x.customerId,
          'source_currency': x.currency,
          'source_amount_minor': x.signedMinor.abs(),
          'signed_amount_minor': x.signedMinor,
          'reason': x.reason.trim(),
        });
      case ExpenseCommand x:
        row.addAll({
          'drawer_id': x.drawerId,
          'source_currency': x.currency,
          'source_amount_minor': x.amountMinor,
        });
    }
    return txn.insert('transactions', row);
  }

  Future<void> _insertJournal(Transaction txn, int transactionId, BusinessDate date,
      String? description, JournalDraft journal) async {
    journal.validate();
    final now = _clock().toUtc().toIso8601String();
    final entryId = await txn.insert('journal_entries', {
      'transaction_id': transactionId,
      'effective_date': date.iso,
      'posted_at': now,
      'description': description,
    });
    var lineNo = 1;
    for (final line in journal.lines) {
      await txn.insert('journal_lines', {
        'journal_entry_id': entryId,
        'line_no': lineNo++,
        'account_id': await _resolve(txn, line.account),
        'currency_code': line.currency,
        'debit_minor': line.debitMinor,
        'credit_minor': line.creditMinor,
        'effective_date': date.iso,
        'memo': line.memo,
      });
    }
  }

  Future<void> _afterInsert(Transaction txn, int id, FinancialCommand c) async {
    final now = _clock().toUtc().toIso8601String();
    if (c is OpeningCashCommand) {
      await txn.insert('opening_balances', {
        'kind': 'cash',
        'drawer_id': c.drawerId,
        'currency_code': c.currency,
        'signed_amount_minor': c.amountMinor,
        'transaction_id': id,
        'is_active': 1,
        'created_at': now,
      });
    } else if (c is OpeningCustomerCommand) {
      await txn.insert('opening_balances', {
        'kind': 'customer',
        'customer_id': c.customerId,
        'currency_code': c.currency,
        'signed_amount_minor': c.signedMinor,
        'transaction_id': id,
        'is_active': 1,
        'created_at': now,
      });
    }
  }

  /// Resolves an [AccountRef] to an active account id.
  Future<int> _resolve(Transaction txn, AccountRef ref) async {
    final (String where, List<Object?> args) = switch (ref) {
      CashAccountRef(:final drawerId) => ("role = 'cash' AND drawer_id = ?", [drawerId]),
      CustomerAccountRef(:final customerId) => (
          "role = 'customer' AND customer_id = ?",
          [customerId]
        ),
      SystemAccountRef(:final role) => ('role = ?', [role.name]),
      ResolvedAccountRef(:final accountId) => ('id = ?', [accountId]),
    };
    final rows = await txn.query('accounts',
        columns: ['id', 'is_active'], where: where, whereArgs: args, limit: 1);
    if (rows.isEmpty) {
      throw InvariantViolation('account.missing', 'حساب مربوط پیدا نشد: $ref');
    }
    if (rows.first['is_active'] != 1 && ref is! ResolvedAccountRef) {
      throw BusinessRuleError('account.inactive', 'حساب $ref غیرفعال است.');
    }
    return rows.first['id'] as int;
  }

  static Future<String> _nextReference(Transaction txn, TransactionType type) async {
    final name = 'tx.${type.name}';
    await txn.rawInsert(
        'INSERT OR IGNORE INTO sequences(name, value) VALUES (?, 0)', [name]);
    await txn.rawUpdate('UPDATE sequences SET value = value + 1 WHERE name = ?', [name]);
    final rows = await txn.query('sequences', where: 'name = ?', whereArgs: [name]);
    final n = rows.first['value'] as int;
    return '${type.prefix}-${n.toString().padLeft(6, '0')}';
  }

  static int? _drawerOf(FinancialCommand c) => switch (c) {
        ReceiptCommand x => x.drawerId,
        PaymentCommand x => x.drawerId,
        ExchangeCommand x => x.drawerId,
        OpeningCashCommand x => x.drawerId,
        CashAdjustmentCommand x => x.drawerId,
        ExpenseCommand x => x.drawerId,
        _ => null,
      };

  static String? _reasonOf(FinancialCommand c) => switch (c) {
        CashAdjustmentCommand x => x.reason,
        CustomerAdjustmentCommand x => x.reason,
        _ => null,
      };

  Future<void> _auditFailure(Actor actor, String action, String entity, String msg) async {
    try {
      await AuditWriter.write(_db,
          actor: actor,
          action: action,
          entityType: 'transaction',
          entityId: entity,
          success: false,
          message: msg);
    } catch (_) {
      // The original error is rethrown by the caller; a failed failure-audit
      // must not mask it.
    }
  }

  static String _friendlyDbError(DatabaseException e) {
    final text = e.toString();
    if (text.contains('immutable') || text.contains('cannot be deleted')) {
      return 'اسناد ثبت‌شده قابل تغییر یا حذف نیستند.';
    }
    if (e.isUniqueConstraintError()) return 'رکورد تکراری؛ عملیات انجام نشد.';
    if (text.contains('FOREIGN KEY')) return 'ارجاع نامعتبر به رکورد دیگر؛ عملیات انجام نشد.';
    return 'ذخیره در پایگاه داده ناکام شد؛ هیچ تغییری ثبت نشد.';
  }
}
