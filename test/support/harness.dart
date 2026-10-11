import 'dart:io';

import 'package:hadid_exchange/application/app_services.dart';
import 'package:hadid_exchange/application/customer_service.dart';
import 'package:hadid_exchange/application/posting_service.dart';
import 'package:hadid_exchange/application/read_models.dart';
import 'package:hadid_exchange/domain/money/decimal.dart';
import 'package:hadid_exchange/domain/security/permissions.dart';
import 'package:hadid_exchange/domain/shared/business_date.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';
import 'package:path/path.dart' as p;

/// Fresh, isolated database per test. Never touches production data.
final class Harness {
  Harness._(this.dir, this.app, this.owner);

  static final DateTime fixedNow = DateTime(2026, 10, 11, 10);

  static Future<Harness> create({DateTime Function()? clock}) async {
    final dir = await Directory.systemTemp.createTemp('hadid_test_');
    final app = await AppServices.open(
      databasePath: p.join(dir.path, 'hadid_exchange.db'),
      backupDirectory: p.join(dir.path, 'backups'),
      clock: clock ?? () => fixedNow,
    );
    final owner = await app.security.actorFor(1);
    return Harness._(dir, app, owner);
  }

  final Directory dir;
  final AppServices app;
  final Actor owner;
  int _key = 0;

  String key() => 'test-key-${_key++}';

  static BusinessDate d(String iso) => BusinessDate.parse(iso);

  Future<void> dispose() async {
    await app.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }

  Future<CustomerRecord> customer(String name) =>
      app.customers.create(CustomerInput(name: name), owner);

  Future<int> walkInId() => app.catalog.walkInCustomerId();

  Future<PostedTransaction> openingCash(String cur, int minor, {String date = '2026-10-01'}) =>
      app.posting.post(
        OpeningCashCommand(
          idempotencyKey: key(),
          effectiveDate: d(date),
          drawerId: 1,
          currency: cur,
          amountMinor: minor,
        ),
        owner,
      );

  Future<PostedTransaction> exchange({
    required ExchangeDirection direction,
    required String base,
    required String quote,
    required int baseMinor,
    required String rate,
    int? customerId,
    String date = '2026-10-05',
    Settlement baseSettlement = Settlement.cash,
    Settlement quoteSettlement = Settlement.cash,
    ExchangeFee? fee,
  }) async =>
      app.posting.post(
        ExchangeCommand(
          idempotencyKey: key(),
          effectiveDate: d(date),
          direction: direction,
          customerId: customerId ?? await walkInId(),
          drawerId: 1,
          baseCurrency: base,
          quoteCurrency: quote,
          baseAmountMinor: baseMinor,
          rate: Decimal.parse(rate),
          baseSettlement: baseSettlement,
          quoteSettlement: quoteSettlement,
          fee: fee,
        ),
        owner,
      );

  Future<PostedTransaction> receipt(int customerId, String cur, int minor,
          {String date = '2026-10-06'}) =>
      app.posting.post(
        ReceiptCommand(
          idempotencyKey: key(),
          effectiveDate: d(date),
          customerId: customerId,
          drawerId: 1,
          currency: cur,
          amountMinor: minor,
        ),
        owner,
      );

  Future<PostedTransaction> payment(int customerId, String cur, int minor,
          {String date = '2026-10-06'}) =>
      app.posting.post(
        PaymentCommand(
          idempotencyKey: key(),
          effectiveDate: d(date),
          customerId: customerId,
          drawerId: 1,
          currency: cur,
          amountMinor: minor,
        ),
        owner,
      );

  Future<PostedTransaction> reverse(int id, {String? date}) => app.posting.reverse(
        transactionId: id,
        reason: 'test reversal',
        actor: owner,
        idempotencyKey: PostingService.newIdempotencyKey(),
        effectiveDate: date == null ? null : d(date),
      );

  Future<int> count(String table) async =>
      (await app.db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n'] as int;
}

/// Amount helpers: whole units → minor units for 2-decimal currencies.
int afn(int units) => units * 100;
int usd(int units) => units * 100;
