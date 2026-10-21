import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/domain/errors/domain_errors.dart';
import 'package:hadid_exchange/infrastructure/database/exchange_database.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

/// Builds legacy databases with the exact schemas of the previous app.
Future<({String customers, String balance, String removed})> _legacyFiles(
  Directory dir, {
  required List<Map<String, Object?>> customers,
  List<Map<String, Object?>> balances = const [],
  List<Map<String, Object?>> removed = const [],
}) async {
  final f = ExchangeDatabase.factory;
  final cPath = p.join(dir.path, 'customers.db');
  final bPath = p.join(dir.path, 'balance.db');
  final rPath = p.join(dir.path, 'removed_data.db');

  final c = await f.openDatabase(cPath);
  await c.execute(
      'CREATE TABLE customers(id TEXT PRIMARY KEY, name TEXT, phone TEXT, customersdata TEXT,date TEXT,time TEXT)');
  for (final row in customers) {
    await c.insert('customers', row);
  }
  await c.close();

  final b = await f.openDatabase(bPath);
  await b.execute('CREATE TABLE balance(date TEXT,time TEXT, currency TEXT, systemInventory TEXT, '
      'fundInventory TEXT, calculatedBalance TEXT, balanceDifference TEXT, withdrawal TEXT, '
      'previousBalanceUpdated TEXT,description TEXT)');
  for (final row in balances) {
    await b.insert('balance', row);
  }
  await b.close();

  final r = await f.openDatabase(rPath);
  await r.execute('CREATE TABLE removed_data(rowid INTEGER PRIMARY KEY AUTOINCREMENT, id INTEGER, name TEXT, '
      'idData TEXT, dealType TEXT, dealType2 TEXT, dealModel TEXT, details TEXT, date TEXT, time TEXT, '
      'currence_income TEXT, income TEXT, currence_withdrawa TEXT, withdrawa TEXT, feePrice TEXT)');
  for (final row in removed) {
    await r.insert('removed_data', row);
  }
  await r.close();
  return (customers: cPath, balance: bPath, removed: rPath);
}

Map<String, Object?> _receipt(String id, String cur, String amount, {String? kind}) => {
      'idData': id,
      'dealType': 'رسید',
      'dealType2': kind ?? 'رسید',
      'date': '1405/7/1',
      'currence_income': cur,
      'income': amount,
    };

Map<String, Object?> _payment(String id, String cur, String amount, {String? kind}) => {
      'idData': id,
      'dealType': 'برد',
      'dealType2': kind ?? 'برد',
      'date': '1405/7/1',
      'currence_withdrawa': cur,
      'withdrawa': amount,
    };

Future<String> _hash(String path) async => sha256.convert(await File(path).readAsBytes()).toString();

void main() {
  late Harness h;
  late Directory legacyDir;

  setUp(() async {
    h = await Harness.create();
    legacyDir = await Directory.systemTemp.createTemp('hadid_legacy_src_');
  });

  tearDown(() async {
    await h.dispose();
    await legacyDir.delete(recursive: true);
  });

  Future<({String customers, String balance, String removed})> standardFiles() => _legacyFiles(
        legacyDir,
        customers: [
          {
            'id': '0',
            'name': 'مشتری متفرقه',
            'phone': '',
            'customersdata': jsonEncode([
              _receipt('1', 'دالر', '100', kind: 'خرید'),
              _payment('1', 'افغانی', '7,000', kind: 'خرید'),
            ]),
          },
          {
            'id': '11',
            'name': 'کریم',
            'phone': '0700',
            'customersdata': jsonEncode([
              _receipt('2', 'افغانی', '۱۰,۰۰۰'),
              _payment('3', 'افغانی', '2,500'),
              _receipt('4', 'دالر', '50'),
              _receipt('5', 'درهم', '40'),
              _payment('6', 'دالر', 'abc'),
              _receipt('7', 'دالر', '100', kind: 'خرید'),
              _payment('7', 'افغانی', '7,000', kind: 'خرید'),
            ]),
          },
          {
            'id': '12',
            'name': 'فرهاد',
            'phone': null,
            'customersdata': jsonEncode([_payment('8', 'تومان', '3,000,000')]),
          },
          {'id': '13', 'name': 'علی احمد', 'phone': null, 'customersdata': null},
        ],
        balances: [
          {'date': '1405/9/30', 'currency': 'افغانی', 'fundInventory': '50000'},
          {'date': '1405/10/2', 'currency': 'افغانی', 'fundInventory': '61,000'},
          {'date': '1405/10/2', 'currency': 'دالر', 'fundInventory': '1200'},
        ],
        removed: [
          {'id': 11, 'name': 'کریم', 'idData': '99', 'dealType': 'رسید', 'currence_income': 'دالر', 'income': '5'},
        ],
      );

  test('analysis reproduces legacy balances and reports every discrepancy', () async {
    final files = await standardFiles();
    final a = await h.app.legacy
        .analyzeFiles(customersDb: files.customers, balanceDb: files.balance, removedDb: files.removed);

    final karim = a.customers.singleWhere((c) => c.legacyId == '11');
    expect(karim.balances, {'AFN': afn(10000 - 2500 - 7000), 'USD': usd(50 + 100)});
    final farhad = a.customers.singleWhere((c) => c.legacyId == '12');
    expect(farhad.balances, {'IRT': -3000000});
    expect(a.customers.singleWhere((c) => c.legacyId == '0').isWalkIn, isTrue);

    final codes = a.issues.map((i) => i.code).toList();
    expect(codes, contains('currency.unknown'));
    expect(codes, contains('amount.unparseable'));
    expect(codes, contains('customer.exchangeOnAccount'));
    expect(codes, contains('walkIn.balance'));
    expect(codes, contains('customer.phoneInvalid'));
    expect(karim.input.phone, isNull);
    expect(karim.input.notes, contains('0700'));
    expect(codes.where((c) => c == 'legacy.removedEntry'), hasLength(1));
    expect(a.blockingIssues(includeCash: true), isEmpty);

    // Latest balance chosen by real Shamsi date (10/2 after 9/30), not string order.
    expect(a.cash['AFN']!.amountMinor, afn(61000));
    expect(a.cash['USD']!.amountMinor, usd(1200));
  });

  test('import posts verified opening balances and never touches legacy files', () async {
    final files = await standardFiles();
    final before = [for (final f in [files.customers, files.balance, files.removed]) await _hash(f)];

    final a = await h.app.legacy
        .analyzeFiles(customersDb: files.customers, balanceDb: files.balance, removedDb: files.removed);
    final result = await h.app.legacy.import(a, h.owner, includeCash: true);

    expect(result.customersCreated, 3);
    expect(result.cashPosted, 2);
    expect(await File(result.backupPath).exists(), isTrue);

    final karim = (await h.app.db.query('customers', where: 'legacy_id = ?', whereArgs: ['legacy:11'])).single;
    final balances = {
      for (final b in await h.app.queries.customerBalances(karim['id'] as int)) b.currency: b.positionMinor,
    };
    expect(balances['AFN'], afn(500));
    expect(balances['USD'], usd(150));
    // Residual initial capital excludes customer funds: 61,000 − 500 and
    // 1,200 − 150. The full legacy physical count is rebuilt in the drawer.
    final capital = {
      for (final r in await h.app.queries.trialBalance()) if (r.accountCode == '3100') r.currency: r.netMinor,
    };
    // IRT has no imported legacy cash, so its debtor balance keeps the
    // historical 3100 funding in that currency only (see B15).
    expect(capital, {'AFN': -afn(60500), 'USD': -usd(1050), 'IRT': -3000000});
    expect(await h.app.queries.cashBalances(), {'AFN': afn(61000), 'USD': usd(1200)});
    expect(await h.app.queries.integrityProblems(), isEmpty);

    final run = (await h.app.legacy.runs()).single;
    expect(run['status'], 'verified');
    expect(await h.app.legacy.issuesOf(run['id'] as int), isNotEmpty);
    final archived = await h.app.legacy.issuesOf(run['id'] as int, includeArchive: true);
    expect(archived.where((i) => i['code'] == 'legacy.customerHistory'), hasLength(3));

    final after = [for (final f in [files.customers, files.balance, files.removed]) await _hash(f)];
    expect(after, before);

    await expectLater(h.app.legacy.import(a, h.owner, includeCash: true),
        throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'legacy.alreadyImported')));
  });

  test('blocking issues stop the import before anything is written', () async {
    final files = await _legacyFiles(legacyDir, customers: [
      {
        'id': '21',
        'name': 'نمونه',
        'customersdata': jsonEncode([_receipt('1', 'افغانی', '10.555')]),
      },
    ]);
    final a = await h.app.legacy.analyzeFiles(customersDb: files.customers);
    expect(a.blockingIssues(includeCash: false).single.code, 'amount.tooPrecise');

    await expectLater(h.app.legacy.import(a, h.owner, includeCash: false),
        throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'legacy.blocked')));
    expect(await h.count('transactions'), 0);
    expect(await h.count('legacy_import_runs'), 0);
  });

  test('import refuses a ledger that already has activity', () async {
    final files = await standardFiles();
    await h.openingCash('AFN', afn(1000));
    final a = await h.app.legacy.analyzeFiles(customersDb: files.customers);
    await expectLater(h.app.legacy.import(a, h.owner, includeCash: false),
        throwsA(isA<BusinessRuleError>().having((e) => e.code, 'code', 'legacy.ledgerNotEmpty')));
  });

  test('a failure midway restores the pre-migration state and records the run', () async {
    final files = await standardFiles();
    final a = await h.app.legacy
        .analyzeFiles(customersDb: files.customers, balanceDb: files.balance, removedDb: files.removed);

    await expectLater(h.app.legacy.import(a, h.owner, includeCash: true, drawerId: 999), throwsA(isA<DomainError>()));

    expect(await h.count('transactions'), 0);
    expect((await h.app.db.query('customers', where: 'is_walk_in = 0')), isEmpty);
    final run = (await h.app.legacy.runs()).single;
    expect(run['status'], 'rolled_back');
    expect(await h.app.queries.integrityProblems(), isEmpty);
  });
}
