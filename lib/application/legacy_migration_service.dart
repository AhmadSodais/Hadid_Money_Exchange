import 'dart:convert';

import 'package:shamsi_date/shamsi_date.dart';

import '../domain/errors/domain_errors.dart';
import '../domain/money/currency.dart';
import '../domain/money/decimal.dart';
import '../domain/security/permissions.dart';
import '../domain/shared/business_date.dart';
import '../domain/shared/ids.dart';
import '../domain/transactions/financial_command.dart';
import '../infrastructure/backup/backup_service.dart';
import '../infrastructure/legacy/legacy_reader.dart';
import 'app_services.dart';
import 'audit_writer.dart';
import 'customer_service.dart';

enum IssueSeverity { info, warning, error }

final class MigrationIssue {
  const MigrationIssue(this.severity, this.code, this.source, this.message, {this.sourceRef, this.raw});

  final IssueSeverity severity;
  final String code;

  /// `customers.db`, `balance.db` or `removed_data.db`.
  final String source;
  final String? sourceRef;
  final String message;
  final Object? raw;

  /// Cash problems only block the import when legacy cash is being imported.
  bool blocks({required bool includeCash}) =>
      severity == IssueSeverity.error && (includeCash || !code.startsWith('cash.'));
}

/// One legacy customer as it will be created in the new ledger.
final class PlannedCustomer {
  PlannedCustomer({required this.legacyId, required this.name, required this.phone, required this.isWalkIn});

  final String legacyId;
  final String name;
  String? phone;
  final bool isWalkIn;

  /// Legacy values that cannot be stored in their own column are kept here.
  final List<String> extraNotes = [];

  CustomerInput get input => CustomerInput(
        name: name,
        phone: phone,
        notes: ['منتقل‌شده از برنامه قبلی (شناسه $legacyId)', ...extraNotes].join('\n'),
      );

  /// Net per currency in minor units (positive = customer funds held by
  /// the exchange, negative = customer debt), computed exactly like the
  /// legacy app:
  /// Σ income − Σ withdrawal. Positive = the exchange owes the customer.
  final Map<String, int> balances = {};
  int entryCount = 0;
}

final class PlannedCash {
  const PlannedCash(this.currency, this.amountMinor, this.legacyDate);

  final String currency;
  final int amountMinor;

  /// Shamsi date of the legacy daily-balance record the amount came from.
  final String legacyDate;
}

final class LegacyAnalysis {
  const LegacyAnalysis({
    required this.fingerprint,
    required this.sources,
    required this.customers,
    required this.cash,
    required this.issues,
    required this.removedCount,
  });

  final String fingerprint;
  final List<String> sources;
  final List<PlannedCustomer> customers;
  final Map<String, PlannedCash> cash;
  final List<MigrationIssue> issues;
  final int removedCount;

  List<MigrationIssue> blockingIssues({required bool includeCash}) =>
      [for (final i in issues) if (i.blocks(includeCash: includeCash)) i];

  List<MigrationIssue> get warnings => [for (final i in issues) if (i.severity == IssueSeverity.warning) i];

  /// Legacy totals per currency over all non-walk-in customers.
  Map<String, int> get customerTotals {
    final totals = <String, int>{};
    for (final c in customers) {
      if (c.isWalkIn) continue;
      c.balances.forEach((cur, v) => totals[cur] = (totals[cur] ?? 0) + v);
    }
    return totals;
  }
}

final class LegacyImportResult {
  const LegacyImportResult({
    required this.runId,
    required this.customersCreated,
    required this.balancesPosted,
    required this.cashPosted,
    required this.backupPath,
  });

  final int runId;
  final int customersCreated;
  final int balancesPosted;
  final int cashPosted;

  /// Snapshot taken immediately before the import.
  final String backupPath;
}

/// Moves data from the legacy `customers.db` / `balance.db` /
/// `removed_data.db` layout into the ledger.
///
/// * The legacy files are never modified (see [LegacyReader]).
/// * [analyze] is pure: it reproduces the balances the legacy app displayed
///   and records every discrepancy as a [MigrationIssue] instead of guessing.
/// * [import] runs only into an empty ledger, only when no blocking issue is
///   present, takes a `pre_migration` backup first, posts opening balances,
///   verifies them against the analysis, and restores the backup if anything
///   fails. A fingerprint that was already imported is rejected.
/// * The complete legacy history (customer entries, daily balances, removed
///   entries) is archived verbatim in `migration_issues.raw_json`.
final class LegacyMigrationService {
  LegacyMigrationService(this._app);

  final AppServices _app;

  static const _walkInNames = {'مشتری متفرقه'};

  /// Legacy currency labels → currency codes.
  static const legacyCurrencyCodes = {
    'افغانی': 'AFN',
    'دالر': 'USD',
    'یورو': 'EUR',
    'تومان': 'IRT',
    'کالدار': 'PKR',
  };

  static final _dashes = RegExp('[\u2010\u2011\u2012\u2013\u2014\u2212\uFE63\uFF0D\u207B\u208B]');

  Future<LegacyAnalysis> analyzeFiles({required String customersDb, String? balanceDb, String? removedDb}) async {
    final snapshot = await LegacyReader.read(customersDb: customersDb, balanceDb: balanceDb, removedDb: removedDb);
    return analyze(snapshot, await _app.catalog.currencies());
  }

  static LegacyAnalysis analyze(LegacySnapshot s, Map<String, Currency> currencies) {
    final issues = <MigrationIssue>[];
    final customers = <PlannedCustomer>[];
    final names = <String, String>{};

    Currency? currencyOf(Object? label) {
      final text = label?.toString().trim() ?? '';
      if (text.isEmpty) return null;
      return currencies[legacyCurrencyCodes[text] ?? text.toUpperCase()];
    }

    for (final row in s.customers) {
      final legacyId = row['id']?.toString().trim() ?? '';
      final name = row['name']?.toString().trim() ?? '';
      final phone = row['phone']?.toString().trim();
      final ref = 'customer:$legacyId';
      final c = PlannedCustomer(
        legacyId: legacyId,
        name: name,
        phone: phone == null || phone.isEmpty ? null : phone,
        isWalkIn: legacyId == '0' || _walkInNames.contains(name),
      );
      if (name.isEmpty) {
        issues.add(MigrationIssue(IssueSeverity.error, 'customer.nameMissing', 'customers.db',
            'مشتری با شناسه قبلی «$legacyId» نام ندارد. نام را در برنامه قبلی ثبت کنید.', sourceRef: ref, raw: row));
      } else if (!c.isWalkIn) {
        try {
          CustomerService.validate(c.input);
        } on ValidationError catch (e) {
          if (e.field == 'phone') {
            issues.add(MigrationIssue(IssueSeverity.warning, 'customer.phoneInvalid', 'customers.db',
                'شماره «${c.phone}» مشتری «$name» معتبر نیست؛ در یادداشت مشتری نگهداری می‌شود.', sourceRef: ref));
            c.extraNotes.add('شماره تماس قبلی: ${c.phone}');
            c.phone = null;
          } else {
            issues.add(MigrationIssue(IssueSeverity.error, 'customer.invalid', 'customers.db',
                'مشتری «$name» ($legacyId): ${e.message}', sourceRef: ref, raw: row));
          }
        }
        final key = name.replaceAll(RegExp(r'\s+'), ' ');
        final other = names[key];
        if (other != null) {
          issues.add(MigrationIssue(IssueSeverity.warning, 'customer.duplicateName', 'customers.db',
              'نام «$name» برای دو مشتری (شناسه‌های $other و $legacyId) تکرار شده؛ هر دو جداگانه منتقل می‌شوند.',
              sourceRef: ref));
        } else {
          names[key] = legacyId;
        }
      }

      final rawData = row['customersdata']?.toString() ?? '';
      List<Object?> entries = const [];
      if (rawData.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawData);
          if (decoded is! List) throw const FormatException('not a list');
          entries = decoded;
        } on FormatException {
          issues.add(MigrationIssue(IssueSeverity.error, 'customer.dataUndecodable', 'customers.db',
              'سوابق مالی مشتری «$name» ($legacyId) قابل خواندن نیست؛ مانده او قابل محاسبه نیست.',
              sourceRef: ref, raw: rawData));
          customers.add(c);
          continue;
        }
        issues.add(MigrationIssue(IssueSeverity.info, 'legacy.customerHistory', 'customers.db',
            'سوابق ${entries.length} ردیفی مشتری «$name» بایگانی شد.', sourceRef: ref, raw: rawData));
      }

      final pairs = <String, List<Map<String, Object?>>>{};
      for (final (index, e) in entries.indexed) {
        final entryRef = '$ref#$index';
        if (e is! Map) {
          issues.add(MigrationIssue(IssueSeverity.error, 'entry.malformed', 'customers.db',
              'ردیف $index مشتری «$name» ساختار معتبر ندارد.', sourceRef: entryRef, raw: e));
          continue;
        }
        final entry = e.cast<String, Object?>();
        c.entryCount++;
        for (final (amountKey, currencyKey, sign) in const [
          ('income', 'currence_income', 1),
          ('withdrawa', 'currence_withdrawa', -1),
        ]) {
          final rawAmount = entry[amountKey];
          final rawCurrency = entry[currencyKey];
          if (rawAmount == null && rawCurrency == null) continue;
          final text = _normalizeAmount(rawAmount);
          if (text.isEmpty) {
            issues.add(MigrationIssue(IssueSeverity.warning, 'amount.empty', 'customers.db',
                'ردیف $index مشتری «$name» مبلغ ندارد؛ مانند برنامه قبلی صفر حساب شد.', sourceRef: entryRef, raw: entry));
            continue;
          }
          final currency = currencyOf(rawCurrency);
          if (currency == null) {
            issues.add(MigrationIssue(IssueSeverity.warning, 'currency.unknown', 'customers.db',
                'ردیف $index مشتری «$name» ارز نامعلوم «${rawCurrency ?? ''}» دارد؛ برنامه قبلی هم آن را در مانده حساب نمی‌کرد.',
                sourceRef: entryRef, raw: entry));
            continue;
          }
          final amount = Decimal.tryParse(text);
          if (amount == null) {
            issues.add(MigrationIssue(IssueSeverity.warning, 'amount.unparseable', 'customers.db',
                'مبلغ «$rawAmount» در ردیف $index مشتری «$name» عدد نیست؛ برنامه قبلی آن را صفر حساب می‌کرد.',
                sourceRef: entryRef, raw: entry));
            continue;
          }
          if (amount.significantScale > currency.precision) {
            issues.add(MigrationIssue(IssueSeverity.error, 'amount.tooPrecise', 'customers.db',
                'مبلغ $text ${currency.code} در ردیف $index مشتری «$name» بیش از ${currency.precision} رقم اعشار دارد.',
                sourceRef: entryRef, raw: entry));
            continue;
          }
          if (amount.isNegative) {
            issues.add(MigrationIssue(IssueSeverity.warning, 'amount.negative', 'customers.db',
                'مبلغ منفی $text ${currency.code} در ردیف $index مشتری «$name»؛ مانند برنامه قبلی با علامت خودش حساب شد.',
                sourceRef: entryRef, raw: entry));
          }
          final minor = amount.toMinor(currency.precision) * sign;
          c.balances[currency.code] = (c.balances[currency.code] ?? 0) + minor;
        }
        if (entry['updatedDate'] != null) {
          issues.add(MigrationIssue(IssueSeverity.info, 'entry.edited', 'customers.db',
              'ردیف $index مشتری «$name» در برنامه قبلی ویرایش شده بود (${entry['updatedDate']}).',
              sourceRef: entryRef));
        }
        final kind = entry['dealType2']?.toString();
        final id = entry['idData']?.toString();
        if ((kind == 'خرید' || kind == 'فروش') && id != null) {
          pairs.putIfAbsent(id, () => []).add(entry);
        }
      }

      for (final MapEntry(key: id, value: legs) in pairs.entries) {
        final receipts = legs.where((l) => l['dealType'] == 'رسید').length;
        final payments = legs.where((l) => l['dealType'] == 'برد').length;
        if (receipts != 1 || payments != 1) {
          issues.add(MigrationIssue(IssueSeverity.warning, 'pair.incomplete', 'customers.db',
              'معامله خرید/فروش $id مشتری «$name» $receipts رسید و $payments برد دارد (باید یکی‌یکی باشد).',
              sourceRef: '$ref#$id', raw: legs));
        }
      }
      if (pairs.isNotEmpty && !c.isWalkIn) {
        issues.add(MigrationIssue(IssueSeverity.warning, 'customer.exchangeOnAccount', 'customers.db',
            'برنامه قبلی ${pairs.length} معامله خرید/فروش را با هر دو طرف روی حساب «$name» ثبت کرده است. '
            'مانده‌ها همان‌طور که برنامه قبلی نشان می‌داد منتقل می‌شوند؛ پیش از ادامه با مشتری تطبیق دهید.',
            sourceRef: ref));
      }
      if (c.isWalkIn && c.balances.values.any((v) => v != 0)) {
        issues.add(MigrationIssue(IssueSeverity.warning, 'walkIn.balance', 'customers.db',
            'مشتری متفرقه در برنامه قبلی مانده غیرصفر داشت (${_describe(c.balances, currencies)}). '
            'مشتری متفرقه در سیستم جدید حساب ندارد؛ این مانده منتقل نمی‌شود و فقط بایگانی است.',
            sourceRef: ref));
      }
      customers.add(c);
    }

    final cash = _analyzeCash(s.balances, currencyOf, issues);

    for (final row in s.removed) {
      issues.add(MigrationIssue(IssueSeverity.info, 'legacy.removedEntry', 'removed_data.db',
          'ردیف حذف‌شده «${row['name'] ?? ''}» (${row['date'] ?? ''}) بایگانی شد؛ در مانده‌ها حساب نمی‌شود.',
          sourceRef: 'removed:${row['_rowid']}', raw: row));
    }

    return LegacyAnalysis(
      fingerprint: s.fingerprint,
      sources: s.sources,
      customers: customers,
      cash: cash,
      issues: issues,
      removedCount: s.removed.length,
    );
  }

  static Map<String, PlannedCash> _analyzeCash(
    List<Map<String, Object?>> rows,
    Currency? Function(Object?) currencyOf,
    List<MigrationIssue> issues,
  ) {
    final latest = <String, (Jalali, int, Map<String, Object?>)>{};
    for (final row in rows) {
      issues.add(MigrationIssue(IssueSeverity.info, 'legacy.balanceRecord', 'balance.db',
          'بیلانس روزانه ${row['currency'] ?? ''} تاریخ ${row['date'] ?? ''} بایگانی شد.',
          sourceRef: 'balance:${row['_rowid']}', raw: row));
      final currency = currencyOf(row['currency']);
      if (currency == null) {
        issues.add(MigrationIssue(IssueSeverity.warning, 'balance.currencyUnknown', 'balance.db',
            'بیلانس روزانه با ارز نامعلوم «${row['currency'] ?? ''}» نادیده گرفته شد.',
            sourceRef: 'balance:${row['_rowid']}'));
        continue;
      }
      final date = _parseJalali(row['date']);
      if (date == null) {
        issues.add(MigrationIssue(IssueSeverity.warning, 'balance.dateUnparseable', 'balance.db',
            'تاریخ «${row['date'] ?? ''}» بیلانس روزانه ${currency.code} قابل خواندن نیست؛ این ردیف نادیده گرفته شد.',
            sourceRef: 'balance:${row['_rowid']}'));
        continue;
      }
      final rowid = row['_rowid'] as int? ?? 0;
      final current = latest[currency.code];
      if (current == null || date.compareTo(current.$1) > 0 || (date.compareTo(current.$1) == 0 && rowid > current.$2)) {
        latest[currency.code] = (date, rowid, row);
      }
    }

    final cash = <String, PlannedCash>{};
    for (final MapEntry(key: code, value: (date, rowid, row)) in latest.entries) {
      final currency = currencyOf(code)!;
      final dateText = '${date.year}/${date.month}/${date.day}';
      final text = _normalizeAmount(row['fundInventory']);
      final amount = Decimal.tryParse(text);
      if (amount == null) {
        issues.add(MigrationIssue(IssueSeverity.error, 'cash.unparseable', 'balance.db',
            'موجودی شمارش‌شده ${currency.code} در آخرین بیلانس ($dateText) عدد نیست: «${row['fundInventory'] ?? ''}».',
            sourceRef: 'balance:$rowid'));
      } else if (amount.significantScale > currency.precision) {
        issues.add(MigrationIssue(IssueSeverity.error, 'cash.tooPrecise', 'balance.db',
            'موجودی ${currency.code} در آخرین بیلانس ($dateText) بیش از ${currency.precision} رقم اعشار دارد.',
            sourceRef: 'balance:$rowid'));
      } else if (amount.isNegative) {
        issues.add(MigrationIssue(IssueSeverity.error, 'cash.negative', 'balance.db',
            'موجودی ${currency.code} در آخرین بیلانس ($dateText) منفی است ($text).', sourceRef: 'balance:$rowid'));
      } else {
        cash[code] = PlannedCash(code, amount.toMinor(currency.precision), dateText);
      }
    }
    return cash;
  }

  /// The exchange's own money inside a legacy physical cash count: the
  /// physical amount net of migration-date customer balances
  /// (`physical − liabilities + debts`). Only this residual is initial
  /// capital; the rest of the safe belongs to customers and enters cash
  /// through their own opening balances.
  static int residualCapitalMinor(
      String currency, int physicalMinor, List<PlannedCustomer> customers) {
    var net = 0; // signed customer total: + liability, − debt
    for (final c in customers) {
      if (c.isWalkIn) continue;
      net += c.balances[currency] ?? 0;
    }
    return physicalMinor - net;
  }

  /// Runs the import. See the class documentation for the guarantees.
  Future<LegacyImportResult> import(
    LegacyAnalysis analysis,
    Actor actor, {
    required bool includeCash,
    int? drawerId,
  }) async {
    for (final p in [
      Permissions.openingBalancesPost,
      Permissions.customersManage,
      Permissions.backupCreate,
      Permissions.backupRestore,
    ]) {
      if (!actor.can(p)) {
        throw const AuthorizationError('auth.denied', 'اجازه انتقال اطلاعات برنامه قبلی را ندارید.');
      }
    }
    final blocking = analysis.blockingIssues(includeCash: includeCash);
    if (blocking.isNotEmpty) {
      throw BusinessRuleError('legacy.blocked',
          '${blocking.length} مشکل مانع انتقال است. ابتدا آن‌ها را در اطلاعات برنامه قبلی اصلاح کنید.');
    }
    final already = await _app.db.query('legacy_import_runs',
        where: "source_fingerprint = ? AND status = 'verified'", whereArgs: [analysis.fingerprint], limit: 1);
    if (already.isNotEmpty) {
      throw const BusinessRuleError('legacy.alreadyImported', 'این اطلاعات قبلاً منتقل و تأیید شده است.');
    }
    final counts = await _app.db.rawQuery('''
      SELECT (SELECT COUNT(*) FROM transactions) AS tx,
             (SELECT COUNT(*) FROM customers WHERE is_walk_in = 0) AS customers
    ''');
    if ((counts.first['tx'] as int) > 0 || (counts.first['customers'] as int) > 0) {
      throw const BusinessRuleError('legacy.ledgerNotEmpty',
          'انتقال فقط روی دفتر خالی (بدون مشتری و معامله) انجام می‌شود تا مانده‌ها دوبار حساب نشوند.');
    }
    final drawers = await _app.catalog.drawers();
    final drawer = drawerId ?? (drawers.where((d) => d.isActive).firstOrNull?.id);
    // Every non-zero customer balance posts against the common vault
    // (drawer) — liabilities bring customer funds in, debts pay out — so
    // a drawer is required whenever any customer holds a balance (and
    // whenever legacy cash is imported).
    final hasBalances =
        analysis.customers.any((c) => !c.isWalkIn && c.balances.values.any((v) => v != 0));
    if ((includeCash || hasBalances) && drawer == null) {
      throw const ValidationError('legacy.noDrawer', 'هیچ صندوق فعالی برای ثبت موجودی نقد وجود ندارد.');
    }

    final BackupResult backup = await _app.backups.create(kind: 'pre_migration', actor: actor);
    final startedAt = _app.now().toUtc().toIso8601String();
    final date = BusinessDate.today(_app.now());
    final keyPrefix = Ids.legacyKeyPrefix(analysis.fingerprint);
    var created = 0, balances = 0, cashPosted = 0;
    int? runId;

    try {
      runId = await _insertRun(analysis, 'running', startedAt, null);

      if (includeCash) {
        // The residual of the legacy physical cash after netting
        // migration-date customer balances is the exchange's *own* money:
        // physical − customer liabilities + customer debts (receivables).
        // Only that residual is initial capital (3100); the customers'
        // share enters cash through their own opening balances below.
        for (final cash in analysis.cash.values) {
          if (cash.amountMinor == 0) continue;
          final residual = residualCapitalMinor(cash.currency, cash.amountMinor, analysis.customers);
          if (residual < 0) {
            throw ValidationError(
              'legacy.cashLessThanLiabilities',
              'موجودی نقد ${cash.currency} برنامه قبلی از مجموع خالص طلب مشتریان کمتر است؛ انتقال ممکن نیست.',
            );
          }
          if (residual == 0) continue; // the safe holds only customers' money
          await _app.posting.post(
            OpeningCashCommand(
              idempotencyKey: '$keyPrefix-CASH-${cash.currency}',
              effectiveDate: date,
              drawerId: drawer!,
              currency: cash.currency,
              amountMinor: residual,
              description: 'سرمایه اولیه (خالص مالکیت صرافی) از بیلانس ${cash.legacyDate} برنامه قبلی',
            ),
            actor,
          );
          cashPosted++;
        }
      }

      for (final c in analysis.customers) {
        if (c.isWalkIn) continue;
        final record = await _app.customers.create(c.input, actor, legacyId: 'legacy:${c.legacyId}');
        created++;
        for (final MapEntry(key: cur, value: minor) in c.balances.entries) {
          if (minor == 0) continue;
          // Without imported cash the vault starts empty; a debtor
          // opening whose currency was not imported would pay out cash
          // that is not there. Legacy replays raw balances and never
          // used the capital counter-account for this, so fund only
          // those currencies from that account as before. Debts in
          // imported currencies are covered by the physical cash above
          // and debt-exceeds-available check (validation only).
          final fundFromCapital = !includeCash || !analysis.cash.containsKey(cur);
          await _app.posting.post(
            OpeningCustomerCommand(
              idempotencyKey: '$keyPrefix-C${c.legacyId}-$cur',
              effectiveDate: date,
              customerId: record.id,
              currency: cur,
              signedMinor: minor,
              drawerId: drawer,
              description: 'مانده منتقل‌شده از برنامه قبلی',
              legacyFunding: fundFromCapital,
            ),
            actor,
          );
          balances++;
        }
        final posted = {
          for (final b in await _app.queries.customerBalances(record.id))
            if (b.positionMinor != 0) b.currency: b.positionMinor,
        };
        final expected = {for (final e in c.balances.entries) if (e.value != 0) e.key: e.value};
        if (!_sameMap(posted, expected)) {
          throw InvariantViolation('legacy.verifyFailed',
              'مانده ثبت‌شده مشتری «${c.name}» با محاسبه برنامه قبلی برابر نیست.');
        }
      }

      if (includeCash) {
        // Residual capital + customer balances must rebuild the legacy
        // physical count in the drawer exactly (validation only).
        final posted = await _app.queries.cashBalances(drawerId: drawer);
        for (final cash in analysis.cash.values) {
          if ((posted[cash.currency] ?? 0) != cash.amountMinor) {
            throw InvariantViolation('legacy.verifyFailed', 'موجودی نقد ${cash.currency} با بیلانس برنامه قبلی برابر نیست.');
          }
        }
      }

      final summary = {
        'customers_created': created,
        'balances_posted': balances,
        'cash_posted': cashPosted,
        'include_cash': includeCash,
        'pre_migration_backup': backup.databaseFile.path,
        'customer_totals': analysis.customerTotals,
        'cash': {for (final c in analysis.cash.values) c.currency: c.amountMinor},
        'removed_archived': analysis.removedCount,
        'warnings': analysis.warnings.length,
      };
      await _app.db.update(
        'legacy_import_runs',
        {'status': 'verified', 'finished_at': _app.now().toUtc().toIso8601String(), 'summary_json': jsonEncode(summary)},
        where: 'id = ?',
        whereArgs: [runId],
      );
      await AuditWriter.write(_app.db,
          actor: actor, action: 'legacy.import', entityType: 'legacy_import_run', entityId: '$runId', after: summary);
      return LegacyImportResult(
        runId: runId,
        customersCreated: created,
        balancesPosted: balances,
        cashPosted: cashPosted,
        backupPath: backup.databaseFile.path,
      );
    } catch (e) {
      await _app.backups.restore(backup.databaseFile.path, actor);
      await _insertRun(analysis, 'rolled_back', startedAt, {'error': '$e', 'pre_migration_backup': backup.databaseFile.path});
      if (e is DomainError) rethrow;
      throw PersistenceError('legacy.failed', 'انتقال ناموفق بود و دفتر به وضعیت قبل از انتقال بازگردانده شد.', cause: e);
    }
  }

  /// Import runs, newest first.
  Future<List<Map<String, Object?>>> runs() =>
      _app.db.query('legacy_import_runs', orderBy: 'id DESC');

  Future<List<Map<String, Object?>>> issuesOf(int runId, {bool includeArchive = false}) => _app.db.query(
        'migration_issues',
        where: includeArchive ? 'run_id = ?' : "run_id = ? AND code NOT LIKE 'legacy.%'",
        whereArgs: [runId],
        orderBy: 'id',
      );

  Future<int> _insertRun(LegacyAnalysis a, String status, String startedAt, Map<String, Object?>? summary) {
    return _app.db.transaction((txn) async {
      final now = _app.now().toUtc().toIso8601String();
      final id = await txn.insert('legacy_import_runs', {
        'source_fingerprint': a.fingerprint,
        'started_at': startedAt,
        'finished_at': status == 'running' ? null : now,
        'status': status,
        'summary_json': summary == null ? null : jsonEncode(summary),
      });
      final batch = txn.batch();
      for (final i in a.issues) {
        batch.insert('migration_issues', {
          'run_id': id,
          'severity': i.severity.name,
          'code': i.code,
          'source': i.source,
          'source_ref': i.sourceRef,
          'message': i.message,
          'raw_json': i.raw == null ? null : (i.raw is String ? i.raw as String : jsonEncode(i.raw)),
          'created_at': now,
        });
      }
      await batch.commit(noResult: true);
      return id;
    });
  }

  static String _normalizeAmount(Object? raw) =>
      Decimal.normalizeDigits(raw?.toString() ?? '').replaceAll(_dashes, '-').replaceAll(RegExp(r'[,\u066C\s]'), '');

  static Jalali? _parseJalali(Object? raw) {
    final parts = Decimal.normalizeDigits(raw?.toString() ?? '').replaceAll('-', '/').split('/');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]), m = int.tryParse(parts[1]), d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    try {
      return Jalali(y, m, d);
    } on DateException {
      return null;
    }
  }

  static bool _sameMap(Map<String, int> a, Map<String, int> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  static String _describe(Map<String, int> balances, Map<String, Currency> currencies) => [
        for (final e in balances.entries)
          if (e.value != 0) '${Decimal.fromMinor(e.value, currencies[e.key]!.precision).toCanonical()} ${e.key}',
      ].join('، ');
}
