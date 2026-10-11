import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/domain/errors/domain_errors.dart';
import 'package:hadid_exchange/domain/money/decimal.dart';
import 'package:hadid_exchange/domain/security/permissions.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

void main() {
  late Harness h;
  late int k;

  setUp(() async {
    h = await Harness.create();
    k = (await h.customer('کریم')).id;
    await h.openingCash('AFN', afn(10000));
    await h.openingCash('USD', usd(1000));
    await h.exchange(
      direction: ExchangeDirection.buy,
      base: 'USD',
      quote: 'AFN',
      baseMinor: usd(100),
      rate: '70',
      customerId: k,
    );
    final r = await h.receipt(k, 'AFN', afn(500));
    await h.app.posting.delete(transactionId: r.id, reason: 'mistake', actor: h.owner, idempotencyKey: h.key());
    await h.receipt(k, 'USD', usd(40), date: '2026-10-07');
    await h.app.rates.setRate(
      base: 'USD',
      quote: 'AFN',
      buyRate: Decimal.parse('70'),
      sellRate: Decimal.parse('71'),
      actor: h.owner,
    );
    await h.app.reconciliation.saveCount(
      drawerId: 1,
      currency: 'AFN',
      date: Harness.d('2026-10-07'),
      countedMinor: afn(3000),
      actor: h.owner,
    );
  });

  tearDown(() => h.dispose());

  Future<String> exportFile([String name = 'data.xlsx']) async {
    final path = p.join(h.dir.path, name);
    await h.app.transfer.exportTo(path, h.owner);
    return path;
  }

  Future<Map<String, int>> balances(int customerId) async => {
    for (final b in await h.app.queries.customerBalances(customerId)) b.currency: b.positionMinor,
  };

  Future<String> rewrite(String path, void Function(Excel book) change) async {
    final book = Excel.decodeBytes(await File(path).readAsBytes());
    change(book);
    final out = p.join(h.dir.path, 'changed.xlsx');
    await File(out).writeAsBytes(book.encode()!);
    return out;
  }

  int columnOf(Sheet sheet, String name) => sheet.rows.first.indexWhere((c) => c?.value.toString() == name);

  test('excel output then input restores exactly the exported data', () async {
    final fingerprint = await h.app.queries.ledgerFingerprint();
    final cash = await h.app.queries.cashBalances();
    final karim = await balances(k);
    final path = await exportFile();
    final exported = await h.app.transfer.fileLog();
    expect(exported.single.action, 'data.export');
    expect(exported.single.entityId, p.basename(path));

    await h.receipt(k, 'AFN', afn(70), date: '2026-10-08');
    final extra = await h.customer('later');

    final summary = await h.app.transfer.importFrom(path, h.owner);
    expect(summary['transactions'], fingerprint['transactions']);
    expect(jsonEncode(await h.app.queries.ledgerFingerprint()), jsonEncode(fingerprint));
    expect(await h.app.queries.cashBalances(), cash);
    expect(await balances(k), karim);
    expect(await h.app.customers.byId(extra.id), isNull);
    expect(await h.app.queries.integrityProblems(), isEmpty);
    expect(await h.app.reconciliation.active(1, 'AFN', Harness.d('2026-10-07')), isNotNull);

    final history = await h.app.backups.history();
    expect(history.any((r) => r['kind'] == 'pre_restore'), isTrue, reason: 'safety backup before replacing');
    final excelLog = await h.app.transfer.fileLog();
    expect(excelLog.any((e) => e.action == 'data.import' && e.entityId == p.basename(path)), isTrue);

    final next = await h.receipt(k, 'AFN', afn(1), date: '2026-10-08');
    expect(next.referenceNo, isNotEmpty);
    expect(await h.app.queries.integrityProblems(), isEmpty);
  });

  test('dates in the excel output are Solar Hijri and credentials are not exported', () async {
    final book = Excel.decodeBytes(await File(await exportFile()).readAsBytes());
    final tx = book['transactions'];
    final date = tx.rows[1][columnOf(tx, 'effective_date')]!.value.toString();
    expect(date, matches(RegExp(r'^14\d\d/\d\d/\d\d$')));
    final created = tx.rows[1][columnOf(tx, 'created_at')]!.value.toString();
    expect(created, matches(RegExp(r'^14\d\d/\d\d/\d\d \d\d:\d\d:\d\d$')));
    expect(columnOf(book['users'], 'password_hash'), -1);
  });

  test('a tampered amount is refused and live data is untouched', () async {
    final path = await exportFile();
    final tampered = await rewrite(path, (book) {
      final lines = book['journal_lines'];
      final col = columnOf(lines, 'debit_minor');
      final row = lines.rows.indexWhere((r) => r.length > col && r[col]?.value.toString() != '0', 1);
      lines.updateCell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row), TextCellValue('1'));
    });
    await h.receipt(k, 'AFN', afn(70), date: '2026-10-08');
    final before = jsonEncode(await h.app.queries.ledgerFingerprint());

    await expectLater(h.app.transfer.importFrom(tampered, h.owner), throwsA(isA<DomainError>()));
    expect(jsonEncode(await h.app.queries.ledgerFingerprint()), before);
    expect(await h.app.queries.integrityProblems(), isEmpty);
    await h.receipt(k, 'AFN', afn(1), date: '2026-10-08');
  });

  test('an invalid date or a foreign workbook is refused', () async {
    final path = await exportFile();
    final badDate = await rewrite(path, (book) {
      final tx = book['transactions'];
      tx.updateCell(
        CellIndex.indexByColumnRow(columnIndex: columnOf(tx, 'effective_date'), rowIndex: 1),
        TextCellValue('1405/13/40'),
      );
    });
    await expectLater(
      h.app.transfer.importFrom(badDate, h.owner),
      throwsA(isA<ValidationError>().having((e) => e.code, 'code', 'import.date')),
    );

    final foreign = Excel.createExcel();
    foreign['Sheet1'].appendRow([TextCellValue('hello')]);
    final other = p.join(h.dir.path, 'other.xlsx');
    await File(other).writeAsBytes(foreign.encode()!);
    await expectLater(
      h.app.transfer.importFrom(other, h.owner),
      throwsA(isA<ValidationError>().having((e) => e.code, 'code', 'import.notOurs')),
    );
    expect(await h.app.queries.integrityProblems(), isEmpty);
  });

  test('clear all data keeps settings and currencies, with a restorable safety backup', () async {
    await h.app.catalog.putSetting('business.name', 'صرافی تست', h.owner);
    final txBefore = await h.count('transactions');

    await h.app.transfer.clearAll(h.owner);

    expect(await h.count('transactions'), 0);
    expect(await h.count('journal_lines'), 0);
    expect(await h.count('reconciliation_records'), 0);
    expect(await h.count('exchange_rates'), 0);
    expect(await h.count('customers'), 1, reason: 'only the walk-in customer');
    expect(await h.app.catalog.setting('business.name'), 'صرافی تست');
    expect((await h.app.catalog.currencies()).keys, containsAll(['AFN', 'USD']));
    expect(await h.app.queries.cashBalances(), isEmpty);

    final safety = (await h.app.backups.history()).firstWhere((r) => r['kind'] == 'pre_restore');
    final check = await h.app.backups.verify(safety['file_path'] as String);
    expect(check.isValid, isTrue);
    expect(check.fingerprint!['transactions'], txBefore);

    await h.openingCash('AFN', afn(50));
    expect(await h.app.queries.cashBalances(), {'AFN': afn(50)});
  });

  test('importing or clearing requires the restore permission', () async {
    final path = await exportFile();
    final cashier = Actor(userId: 1, displayName: 'c', permissions: Permissions.roleDefaults['cashier']!.toSet());
    await expectLater(h.app.transfer.importFrom(path, cashier), throwsA(isA<AuthorizationError>()));
    await expectLater(h.app.transfer.clearAll(cashier), throwsA(isA<AuthorizationError>()));
    await expectLater(h.app.transfer.exportWorkbook(cashier), throwsA(isA<AuthorizationError>()));
  });

  test('automatic excel export follows the schedule, records the full path, and keeps history', () async {
    var now = Harness.fixedNow;
    final a = await Harness.create(clock: () => now);
    addTearDown(a.dispose);
    final t = a.app.transfer;
    final folder = p.join(a.dir.path, 'auto exports');

    expect(await t.autoExportIfDue(), isNull, reason: 'off by default');

    await a.app.catalog.putSetting('excel.auto_enabled', '1', a.owner);
    await a.app.catalog.putSetting('excel.auto_interval_hours', '6', a.owner);
    await a.app.catalog.putSetting('excel.auto_retention_count', '2', a.owner);
    await a.app.catalog.putSetting('excel.auto_directory', folder, a.owner);

    final first = (await t.autoExportIfDue())!;
    expect(first['outcome'], 'success');
    final firstPath = first['file_path'] as String;
    expect(p.dirname(firstPath), folder);
    expect(p.basename(firstPath), matches(RegExp(r'^hadid_auto_14\d\d-\d\d-\d\d_\d{6}\.xlsx$')));
    expect(await File(firstPath).exists(), isTrue);

    now = now.add(const Duration(hours: 5));
    expect(await t.autoExportIfDue(), isNull, reason: 'interval not reached');

    for (var i = 0; i < 2; i++) {
      now = now.add(const Duration(hours: 6));
      expect((await t.autoExportIfDue())!['outcome'], 'success');
    }
    final history = await t.autoExportHistory();
    expect(history, hasLength(3));
    expect(history.last['file_path'], firstPath);
    expect(await File(firstPath).exists(), isFalse, reason: 'only the newest 2 files are kept');
    expect(await File(history.first['file_path'] as String).exists(), isTrue);

    await t.importFrom(history.first['file_path'] as String, a.owner);
    expect(await t.autoExportHistory(), hasLength(3), reason: 'history survives an excel input');
    await t.clearAll(a.owner);
    expect(await t.autoExportHistory(), hasLength(3), reason: 'history survives clearing data');

    final cashier = Actor(userId: 1, displayName: 'c', permissions: const {});
    expect(() => t.runAutoExport(actor: cashier), throwsA(isA<AuthorizationError>()));
  });

  test('a failed automatic export is recorded with its target path', () async {
    final blocker = File(p.join(h.dir.path, 'not a folder'));
    await blocker.writeAsString('x');
    await h.app.catalog.putSetting('excel.auto_enabled', '1', h.owner);
    await h.app.catalog.putSetting('excel.auto_directory', blocker.path, h.owner);

    final row = (await h.app.transfer.autoExportIfDue())!;
    expect(row['outcome'], 'failure');
    expect(p.dirname(row['file_path'] as String), blocker.path);
    expect(row['message'], isNotNull);
    expect(await h.app.transfer.autoExportIfDue(), isNull, reason: 'a failure waits for the next interval');
  });
}
