import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/shared/business_date.dart';
import '../domain/transactions/financial_command.dart';
import 'read_models.dart';

/// Composable journal search. Every condition is ANDed; none overrides
/// another, and searching never modifies data.
final class JournalFilter {
  const JournalFilter({
    this.from,
    this.to,
    this.customerId,
    this.currency,
    this.types,
    this.status,
    this.activeOnly = false,
    this.text,
    this.minAmountMinor,
    this.maxAmountMinor,
  });

  final BusinessDate? from;
  final BusinessDate? to;
  final int? customerId;
  final String? currency;
  final Set<TransactionType>? types;
  final TransactionStatus? status;

  /// Only transactions that still affect balances: excludes deleted/edited
  /// originals and the reversal documents that neutralized them.
  final bool activeOnly;

  /// Matches reference number, description, or customer name.
  final String? text;

  /// Amount range in minor units of [currency] (ignored without a currency).
  final int? minAmountMinor;
  final int? maxAmountMinor;

  (String, List<Object?>) toSql() {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('t.effective_date >= ?');
      args.add(from!.iso);
    }
    if (to != null) {
      where.add('t.effective_date <= ?');
      args.add(to!.iso);
    }
    if (customerId != null) {
      where.add('t.customer_id = ?');
      args.add(customerId);
    }
    if (currency != null) {
      where.add('(t.source_currency = ? OR t.dest_currency = ? OR t.fee_currency = ?)');
      args.addAll([currency, currency, currency]);
      if (minAmountMinor != null || maxAmountMinor != null) {
        final lo = minAmountMinor ?? 0;
        final hi = maxAmountMinor ?? 9223372036854775807;
        where.add('((t.source_currency = ? AND t.source_amount_minor BETWEEN ? AND ?)'
            ' OR (t.dest_currency = ? AND t.dest_amount_minor BETWEEN ? AND ?))');
        args.addAll([currency, lo, hi, currency, lo, hi]);
      }
    }
    if (types != null && types!.isNotEmpty) {
      where.add('t.type IN (${List.filled(types!.length, '?').join(',')})');
      args.addAll(types!.map((t) => t.name));
    }
    if (status != null) {
      where.add('t.status = ?');
      args.add(status!.name);
    }
    if (activeOnly) {
      where.add("t.status = 'posted' AND t.type <> 'reversal'");
    }
    final q = text?.trim();
    if (q != null && q.isNotEmpty) {
      where.add('(t.reference_no LIKE ? OR t.document_no LIKE ? OR t.description LIKE ? OR c.name LIKE ?)');
      args.addAll(['%$q%', '%$q%', '%$q%', '%$q%']);
    }
    return (where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}', args);
  }
}

/// Read-only financial queries. Every balance is derived from posted journal
/// lines — there are no stored running totals that could diverge.
final class LedgerQueries {
  LedgerQueries(this._db);

  final DatabaseExecutor _db;

  // ------------------------------------------------------------------ cash

  /// Cash per currency as of [asOf] (inclusive). Future-dated lines are
  /// excluded automatically by the date condition.
  Future<Map<String, int>> cashBalances({BusinessDate? asOf, int? drawerId}) async {
    final rows = await _db.rawQuery('''
      SELECT l.currency_code AS cur, SUM(l.debit_minor - l.credit_minor) AS bal
      FROM journal_lines l JOIN accounts a ON a.id = l.account_id
      WHERE a.role = 'cash'
        ${drawerId == null ? '' : 'AND a.drawer_id = ?'}
        ${asOf == null ? '' : 'AND l.effective_date <= ?'}
      GROUP BY l.currency_code
    ''', [?drawerId, ?asOf?.iso]);
    return {for (final r in rows) r['cur'] as String: r['bal'] as int};
  }

  Future<int> cashBalance(String currency, {BusinessDate? asOf, int? drawerId}) async =>
      (await cashBalances(asOf: asOf, drawerId: drawerId))[currency] ?? 0;

  /// The unified main-cashbox balance per currency: the total cash in
  /// the single shared fund, pooling the exchange's own capital and
  /// customer funds (every cash account together). This total is the
  /// withdrawal limit — no payment, expense, exchange payout, or
  /// client-debt opening may exceed it in its currency.
  Future<Map<String, int>> cashboxBalances({BusinessDate? asOf}) => cashBalances(asOf: asOf);

  Future<int> cashboxBalance(String currency, {BusinessDate? asOf}) async =>
      (await cashboxBalances(asOf: asOf))[currency] ?? 0;

  /// Cashbox composition per currency. These are *derived* views of the
  /// same journal, never stored separately:
  /// - `physicalMinor`: the cashbox total (all cash in the main fund);
  /// - `reservedMinor`: the part of it that belongs to customers (total
  ///   customer liabilities held in the fund, informational);
  /// - `availableMinor`: the withdrawable balance = the cashbox total
  ///   itself, because own and customer funds are pooled in one fund;
  /// - `receivablesMinor`: what customers owe the exchange (not cash yet).
  Future<Map<String, ({int physicalMinor, int reservedMinor, int availableMinor, int receivablesMinor})>>
      cashAvailability({BusinessDate? asOf, int? drawerId}) async {
    final cash = await cashBalances(asOf: asOf, drawerId: drawerId);
    final totals = await customerTotals(asOf: asOf);
    final codes = {...cash.keys, ...totals.keys};
    return {
      for (final code in codes)
        code: (
          physicalMinor: cash[code] ?? 0,
          reservedMinor: totals[code]?.liabilities ?? 0,
          availableMinor: cash[code] ?? 0,
          receivablesMinor: totals[code]?.receivables ?? 0,
        ),
    };
  }

  /// Opening (before [from]), inflows, outflows for each currency in range.
  Future<List<CashMovement>> cashMovement(BusinessDate from, BusinessDate to,
      {int? drawerId}) async {
    final rows = await _db.rawQuery('''
      SELECT l.currency_code AS cur,
        SUM(CASE WHEN l.effective_date < ? THEN l.debit_minor - l.credit_minor ELSE 0 END) AS opening,
        SUM(CASE WHEN l.effective_date BETWEEN ? AND ? THEN l.debit_minor ELSE 0 END) AS inflow,
        SUM(CASE WHEN l.effective_date BETWEEN ? AND ? THEN l.credit_minor ELSE 0 END) AS outflow
      FROM journal_lines l JOIN accounts a ON a.id = l.account_id
      JOIN currencies c ON c.code = l.currency_code
      WHERE a.role = 'cash' AND l.effective_date <= ?
        ${drawerId == null ? '' : 'AND a.drawer_id = ?'}
      GROUP BY l.currency_code ORDER BY MIN(c.sort_order)
    ''', [from.iso, from.iso, to.iso, from.iso, to.iso, to.iso, ?drawerId]);
    return [
      for (final r in rows)
        CashMovement(
          currency: r['cur'] as String,
          openingMinor: r['opening'] as int,
          inflowMinor: r['inflow'] as int,
          outflowMinor: r['outflow'] as int,
        ),
    ];
  }

  // ------------------------------------------------------------- customers

  Future<List<CustomerBalance>> customerBalances(int customerId, {BusinessDate? asOf}) async {
    final rows = await _db.rawQuery('''
      SELECT l.currency_code AS cur, SUM(l.credit_minor - l.debit_minor) AS pos
      FROM journal_lines l JOIN accounts a ON a.id = l.account_id
      JOIN currencies c ON c.code = l.currency_code
      WHERE a.customer_id = ? ${asOf == null ? '' : 'AND l.effective_date <= ?'}
      GROUP BY l.currency_code ORDER BY MIN(c.sort_order)
    ''', [customerId, ?asOf?.iso]);
    return [
      for (final r in rows) CustomerBalance(customerId, r['cur'] as String, r['pos'] as int),
    ];
  }

  /// Non-zero positions of every customer: customerId → currency → position.
  Future<Map<int, Map<String, int>>> allCustomerPositions({BusinessDate? asOf}) async {
    final rows = await _db.rawQuery('''
      SELECT a.customer_id AS cid, l.currency_code AS cur,
             SUM(l.credit_minor - l.debit_minor) AS pos
      FROM journal_lines l JOIN accounts a ON a.id = l.account_id
      WHERE a.role = 'customer' ${asOf == null ? '' : 'AND l.effective_date <= ?'}
      GROUP BY a.customer_id, l.currency_code HAVING pos <> 0
    ''', [?asOf?.iso]);
    final out = <int, Map<String, int>>{};
    for (final r in rows) {
      out.putIfAbsent(r['cid'] as int, () => {})[r['cur'] as String] = r['pos'] as int;
    }
    return out;
  }

  /// Per currency: total owed to customers (liabilities, positive positions)
  /// and total owed by customers (receivables, negative positions).
  Future<Map<String, ({int liabilities, int receivables})>> customerTotals(
      {BusinessDate? asOf}) async {
    final positions = await allCustomerPositions(asOf: asOf);
    final out = <String, ({int liabilities, int receivables})>{};
    for (final byCur in positions.values) {
      for (final e in byCur.entries) {
        final cur = out[e.key] ?? (liabilities: 0, receivables: 0);
        out[e.key] = e.value > 0
            ? (liabilities: cur.liabilities + e.value, receivables: cur.receivables)
            : (liabilities: cur.liabilities, receivables: cur.receivables - e.value);
      }
    }
    return out;
  }

  Future<CustomerStatement> customerStatement(
    CustomerRecord customer,
    String currency, {
    BusinessDate? from,
    BusinessDate? to,
    Set<TransactionType>? types,
  }) async {
    var opening = 0;
    if (from != null) {
      final r = await _db.rawQuery('''
        SELECT COALESCE(SUM(l.credit_minor - l.debit_minor), 0) AS pos
        FROM journal_lines l JOIN accounts a ON a.id = l.account_id
        WHERE a.customer_id = ? AND l.currency_code = ? AND l.effective_date < ?
      ''', [customer.id, currency, from.iso]);
      opening = r.first['pos'] as int;
    }
    final where = <String>['a.customer_id = ?', 'l.currency_code = ?'];
    final args = <Object?>[customer.id, currency];
    if (from != null) {
      where.add('l.effective_date >= ?');
      args.add(from.iso);
    }
    if (to != null) {
      where.add('l.effective_date <= ?');
      args.add(to.iso);
    }
    if (types != null && types.isNotEmpty) {
      where.add('t.type IN (${List.filled(types.length, '?').join(',')})');
      args.addAll(types.map((t) => t.name));
    }
    final rows = await _db.rawQuery('''
      SELECT t.id, COALESCE(t.document_no, t.reference_no) AS reference_no, t.type, t.status,
             t.description, l.effective_date,
             l.debit_minor, l.credit_minor
      FROM journal_lines l
      JOIN accounts a ON a.id = l.account_id
      JOIN journal_entries e ON e.id = l.journal_entry_id
      JOIN transactions t ON t.id = e.transaction_id
      WHERE ${where.join(' AND ')}
      ORDER BY l.effective_date, t.id, l.line_no
    ''', args);
    var running = opening;
    final lines = <StatementLine>[];
    for (final r in rows) {
      final debit = r['debit_minor'] as int;
      final credit = r['credit_minor'] as int;
      running += credit - debit;
      lines.add(StatementLine(
        transactionId: r['id'] as int,
        referenceNo: r['reference_no'] as String,
        type: TransactionType.parse(r['type'] as String),
        status: TransactionStatus.parse(r['status'] as String),
        effectiveDate: BusinessDate.parse(r['effective_date'] as String),
        currency: currency,
        debitMinor: debit,
        creditMinor: credit,
        runningPositionMinor: running,
        description: r['description'] as String?,
      ));
    }
    return CustomerStatement(
        customer: customer, currency: currency, openingPositionMinor: opening, lines: lines);
  }

  // --------------------------------------------------------------- journal

  Future<List<PostedTransaction>> journal(JournalFilter filter,
      {int limit = 50, int offset = 0, bool newestFirst = true}) async {
    final (where, args) = filter.toSql();
    final order = newestFirst ? 'DESC' : 'ASC';
    final rows = await _db.rawQuery('''
      SELECT t.*, c.name AS customer_name, u.display_name AS created_by_name,
        $kCorrectionLinkColumns
      FROM transactions t
      LEFT JOIN customers c ON c.id = t.customer_id
      LEFT JOIN users u ON u.id = t.created_by
      $where
      ORDER BY t.effective_date $order, t.id $order
      LIMIT ? OFFSET ?
    ''', [...args, limit, offset]);
    return rows.map((r) => PostedTransaction.fromRow(r)).toList();
  }

  Future<int> journalCount(JournalFilter filter) async {
    final (where, args) = filter.toSql();
    final rows = await _db.rawQuery('''
      SELECT COUNT(*) AS n FROM transactions t
      LEFT JOIN customers c ON c.id = t.customer_id $where
    ''', args);
    return rows.first['n'] as int;
  }

  // ------------------------------------------------------------ accounting

  /// Trial balance per account and currency as of [asOf]. For each currency
  /// the debit and credit totals are equal when the ledger is consistent.
  Future<List<TrialBalanceRow>> trialBalance({BusinessDate? asOf}) async {
    final rows = await _db.rawQuery('''
      SELECT a.id, a.code, a.name_fa, a.type, l.currency_code AS cur,
             SUM(l.debit_minor) AS dr, SUM(l.credit_minor) AS cr
      FROM journal_lines l JOIN accounts a ON a.id = l.account_id
      JOIN currencies c ON c.code = l.currency_code
      ${asOf == null ? '' : 'WHERE l.effective_date <= ?'}
      GROUP BY a.id, l.currency_code
      ORDER BY MIN(c.sort_order), a.code
    ''', [?asOf?.iso]);
    return [
      for (final r in rows)
        TrialBalanceRow(
          accountId: r['id'] as int,
          accountCode: r['code'] as String,
          accountName: r['name_fa'] as String,
          accountType: r['type'] as String,
          currency: r['cur'] as String,
          debitMinor: r['dr'] as int,
          creditMinor: r['cr'] as int,
        ),
    ];
  }

  /// General-ledger lines of one account in one currency, with a
  /// debit-positive running balance.
  Future<List<({PostedTransaction tx, int debit, int credit, int running})>> accountLedger(
    int accountId,
    String currency, {
    BusinessDate? from,
    BusinessDate? to,
  }) async {
    var running = 0;
    if (from != null) {
      final r = await _db.rawQuery('''
        SELECT COALESCE(SUM(debit_minor - credit_minor), 0) AS b FROM journal_lines
        WHERE account_id = ? AND currency_code = ? AND effective_date < ?
      ''', [accountId, currency, from.iso]);
      running = r.first['b'] as int;
    }
    final rows = await _db.rawQuery('''
      SELECT t.*, c.name AS customer_name, l.debit_minor AS l_dr, l.credit_minor AS l_cr
      FROM journal_lines l
      JOIN journal_entries e ON e.id = l.journal_entry_id
      JOIN transactions t ON t.id = e.transaction_id
      LEFT JOIN customers c ON c.id = t.customer_id
      WHERE l.account_id = ? AND l.currency_code = ?
        ${from == null ? '' : 'AND l.effective_date >= ?'}
        ${to == null ? '' : 'AND l.effective_date <= ?'}
      ORDER BY l.effective_date, t.id, l.line_no
    ''', [accountId, currency, ?from?.iso, ?to?.iso]);
    final out = <({PostedTransaction tx, int debit, int credit, int running})>[];
    for (final r in rows) {
      final dr = r['l_dr'] as int;
      final cr = r['l_cr'] as int;
      running += dr - cr;
      out.add((tx: PostedTransaction.fromRow(r), debit: dr, credit: cr, running: running));
    }
    return out;
  }

  Future<List<Map<String, Object?>>> accounts() => _db.rawQuery('''
        SELECT a.*, p.code AS parent_code FROM accounts a
        LEFT JOIN accounts p ON p.id = a.parent_id
        WHERE a.role <> 'customer' ORDER BY a.code
      ''');

  /// Net balance of the exchange position account per currency (credit
  /// positive = currency delivered out exceeds currency taken in).
  Future<Map<String, int>> exchangePosition({BusinessDate? asOf}) async {
    final rows = await _db.rawQuery('''
      SELECT l.currency_code AS cur, SUM(l.credit_minor - l.debit_minor) AS bal
      FROM journal_lines l JOIN accounts a ON a.id = l.account_id
      WHERE a.role = 'exchangePosition' ${asOf == null ? '' : 'AND l.effective_date <= ?'}
      GROUP BY l.currency_code
    ''', [?asOf?.iso]);
    return {for (final r in rows) r['cur'] as String: r['bal'] as int};
  }

  /// Revenue/expense totals per currency over a period (fees, expenses,
  /// cash over/short). Not converted between currencies.
  Future<List<TrialBalanceRow>> incomeAndExpense(BusinessDate from, BusinessDate to) async {
    final rows = await _db.rawQuery('''
      SELECT a.id, a.code, a.name_fa, a.type, l.currency_code AS cur,
             SUM(l.debit_minor) AS dr, SUM(l.credit_minor) AS cr
      FROM journal_lines l JOIN accounts a ON a.id = l.account_id
      WHERE a.type IN ('revenue','expense') AND l.effective_date BETWEEN ? AND ?
      GROUP BY a.id, l.currency_code ORDER BY a.code, l.currency_code
    ''', [from.iso, to.iso]);
    return [
      for (final r in rows)
        TrialBalanceRow(
          accountId: r['id'] as int,
          accountCode: r['code'] as String,
          accountName: r['name_fa'] as String,
          accountType: r['type'] as String,
          currency: r['cur'] as String,
          debitMinor: r['dr'] as int,
          creditMinor: r['cr'] as int,
        ),
    ];
  }

  // -------------------------------------------------------------- activity

  Future<List<ExchangeActivityRow>> exchangeActivity(BusinessDate from, BusinessDate to) async {
    final rows = await _db.rawQuery('''
      SELECT type, source_currency AS base, dest_currency AS quote, COUNT(*) AS n,
             SUM(source_amount_minor) AS base_total, SUM(dest_amount_minor) AS quote_total,
             GROUP_CONCAT(rate, '|') AS rates
      FROM transactions
      WHERE type IN ('buy','sell') AND status = 'posted'
        AND effective_date BETWEEN ? AND ?
      GROUP BY type, source_currency, dest_currency
      ORDER BY source_currency, dest_currency, type
    ''', [from.iso, to.iso]);
    return [
      for (final r in rows) _activityRow(r),
    ];
  }

  ExchangeActivityRow _activityRow(Map<String, Object?> r) {
    final rates = (r['rates'] as String).split('|');
    String pick(bool max) => rates.reduce((a, b) {
          final cmp = _cmpDecimalText(a, b);
          return (max ? cmp >= 0 : cmp <= 0) ? a : b;
        });
    return ExchangeActivityRow(
      type: TransactionType.parse(r['type'] as String),
      baseCurrency: r['base'] as String,
      quoteCurrency: r['quote'] as String,
      count: r['n'] as int,
      baseTotalMinor: r['base_total'] as int,
      quoteTotalMinor: r['quote_total'] as int,
      minRate: pick(false),
      maxRate: pick(true),
    );
  }

  static int _cmpDecimalText(String a, String b) {
    List<String> split(String s) {
      final parts = s.split('.');
      return [parts[0], parts.length > 1 ? parts[1] : ''];
    }

    final pa = split(a), pb = split(b);
    final ia = BigInt.parse(pa[0]), ib = BigInt.parse(pb[0]);
    if (ia != ib) return ia.compareTo(ib);
    final len = pa[1].length > pb[1].length ? pa[1].length : pb[1].length;
    return pa[1].padRight(len, '0').compareTo(pb[1].padRight(len, '0'));
  }

  /// Count and totals by type and currency (the traded / single currency).
  /// Reversals appear as their own type so totals reconcile with the ledger.
  Future<List<DailyTypeSummary>> typeSummary(BusinessDate from, BusinessDate to) async {
    final rows = await _db.rawQuery('''
      SELECT type, source_currency AS cur, COUNT(*) AS n, SUM(source_amount_minor) AS total
      FROM transactions WHERE effective_date BETWEEN ? AND ?
      GROUP BY type, source_currency ORDER BY type, source_currency
    ''', [from.iso, to.iso]);
    return [
      for (final r in rows)
        DailyTypeSummary(TransactionType.parse(r['type'] as String),
            r['cur'] as String? ?? '', r['n'] as int, (r['total'] as int?) ?? 0),
    ];
  }

  // ------------------------------------------------------------- integrity

  /// Re-verifies the accounting invariants directly from stored rows.
  /// Returns human-readable problems; an empty list means consistent.
  Future<List<String>> integrityProblems() async {
    final problems = <String>[];
    final unbalanced = await _db.rawQuery('''
      SELECT e.transaction_id AS tid, l.currency_code AS cur,
             SUM(l.debit_minor) - SUM(l.credit_minor) AS diff
      FROM journal_lines l JOIN journal_entries e ON e.id = l.journal_entry_id
      GROUP BY e.id, l.currency_code HAVING diff <> 0
    ''');
    for (final r in unbalanced) {
      problems.add('سند معامله ${r['tid']} در ${r['cur']} تراز نیست (${r['diff']}).');
    }
    final orphan = await _db.rawQuery('''
      SELECT t.id FROM transactions t
      LEFT JOIN journal_entries e ON e.transaction_id = t.id WHERE e.id IS NULL
    ''');
    for (final r in orphan) {
      problems.add('معامله ${r['id']} سند حسابداری ندارد.');
    }
    final badReversal = await _db.rawQuery('''
      SELECT t.id FROM transactions t
      WHERE (t.status = 'reversed') <> (t.reversed_by_transaction_id IS NOT NULL)
    ''');
    for (final r in badReversal) {
      problems.add('وضعیت برگشت معامله ${r['id']} ناسازگار است.');
    }
    final fk = await _db.rawQuery('PRAGMA foreign_key_check');
    if (fk.isNotEmpty) problems.add('${fk.length} ارجاع خارجی نامعتبر یافت شد.');
    return problems;
  }

  /// Deterministic fingerprint of the ledger used to compare a restored
  /// backup with its manifest.
  Future<Map<String, Object?>> ledgerFingerprint() async {
    final counts = await _db.rawQuery('''
      SELECT (SELECT COUNT(*) FROM transactions) AS tx,
             (SELECT COUNT(*) FROM journal_lines) AS lines,
             (SELECT COUNT(*) FROM customers) AS customers
    ''');
    final totals = await _db.rawQuery('''
      SELECT currency_code AS cur, SUM(debit_minor) AS dr, SUM(credit_minor) AS cr
      FROM journal_lines GROUP BY currency_code ORDER BY currency_code
    ''');
    return {
      'transactions': counts.first['tx'],
      'journal_lines': counts.first['lines'],
      'customers': counts.first['customers'],
      'totals': {
        for (final r in totals) r['cur'] as String: {'debit': r['dr'], 'credit': r['cr']},
      },
    };
  }
}
