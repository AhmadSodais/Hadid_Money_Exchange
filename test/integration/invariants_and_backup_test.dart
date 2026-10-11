import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/application/read_models.dart';
import 'package:hadid_exchange/domain/errors/domain_errors.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';

import '../support/harness.dart';

void main() {
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  group('Property-based ledger invariants', () {
    for (final seed in [1, 7, 42]) {
      test('random valid sequence (seed $seed) matches an independent model', () async {
        final rnd = Random(seed);
        final model = <String, int>{'AFN': afn(1000000), 'USD': usd(50000)};
        final customerModel = <int, Map<String, int>>{};
        await h.openingCash('AFN', model['AFN']!);
        await h.openingCash('USD', model['USD']!);
        final customers = [
          for (var i = 0; i < 3; i++) (await h.customer('C$i')).id,
        ];
        final posted = <PostedTransaction>[];
        final days = ['2026-10-02', '2026-10-03', '2026-10-04', '2026-10-05'];

        for (var i = 0; i < 40; i++) {
          final date = days[rnd.nextInt(days.length)];
          final cur = rnd.nextBool() ? 'AFN' : 'USD';
          final amount = 100 * (1 + rnd.nextInt(500));
          final cid = customers[rnd.nextInt(customers.length)];
          switch (rnd.nextInt(4)) {
            case 0:
              posted.add(await h.receipt(cid, cur, amount, date: date));
              model[cur] = model[cur]! + amount;
              customerModel.putIfAbsent(cid, () => {}).update(cur, (v) => v + amount,
                  ifAbsent: () => amount);
            case 1:
              posted.add(await h.payment(cid, cur, amount, date: date));
              model[cur] = model[cur]! - amount;
              customerModel.putIfAbsent(cid, () => {}).update(cur, (v) => v - amount,
                  ifAbsent: () => -amount);
            case 2:
              final t = await h.exchange(
                  direction: ExchangeDirection.buy,
                  base: 'USD',
                  quote: 'AFN',
                  baseMinor: amount,
                  rate: '70.5',
                  date: date);
              posted.add(t);
              model['USD'] = model['USD']! + amount;
              model['AFN'] = model['AFN']! - t.destAmountMinor!;
            default:
              final t = await h.exchange(
                  direction: ExchangeDirection.sell,
                  base: 'USD',
                  quote: 'AFN',
                  baseMinor: amount,
                  rate: '71.25',
                  date: date);
              posted.add(t);
              model['USD'] = model['USD']! - amount;
              model['AFN'] = model['AFN']! + t.destAmountMinor!;
          }
        }

        expect(await h.app.queries.integrityProblems(), isEmpty);
        expect(await h.app.queries.cashBalances(), model);
        for (final cid in customers) {
          final actual = {
            for (final b in await h.app.queries.customerBalances(cid))
              if (b.positionMinor != 0) b.currency: b.positionMinor
          };
          final expected = {
            for (final e in (customerModel[cid] ?? {}).entries)
              if (e.value != 0) e.key: e.value
          };
          expect(actual, expected, reason: 'customer $cid');
        }

        // Trial balance: debits equal credits within each currency.
        final tb = await h.app.queries.trialBalance();
        for (final cur in ['AFN', 'USD']) {
          final rows = tb.where((r) => r.currency == cur);
          expect(rows.fold(0, (s, r) => s + r.netMinor), 0, reason: cur);
        }

        // Reversing everything neutralizes every effect.
        for (final t in posted) {
          await h.reverse(t.id);
        }
        expect(await h.app.queries.cashBalances(), {'AFN': afn(1000000), 'USD': usd(50000)});
        for (final cid in customers) {
          final bal = await h.app.queries.customerBalances(cid);
          expect(bal.every((b) => b.positionMinor == 0), isTrue);
        }
        expect(await h.app.queries.integrityProblems(), isEmpty);
      });
    }
  });

  group('Backup and restore', () {
    test('snapshot, later changes, restore → identical balances to snapshot', () async {
      await h.openingCash('AFN', afn(5000));
      final k = await h.customer('Ali');
      await h.receipt(k.id, 'AFN', afn(700));
      final backup = await h.app.backups.create(actor: h.owner);
      final snapshotFingerprint = await h.app.queries.ledgerFingerprint();
      final snapshotCash = await h.app.queries.cashBalances();

      expect((await h.app.backups.verify(backup.databaseFile.path)).problems, isEmpty);

      await h.payment(k.id, 'AFN', afn(300));
      expect(await h.app.queries.cashBalance('AFN'), afn(5400));

      await h.app.backups.restore(backup.databaseFile.path, h.owner);
      expect(await h.app.queries.cashBalances(), snapshotCash);
      final restored = await h.app.queries.ledgerFingerprint();
      expect(restored['totals'], snapshotFingerprint['totals']);
      expect(restored['transactions'], snapshotFingerprint['transactions']);
      expect(await h.app.queries.integrityProblems(), isEmpty);

      // Restoring the same backup again gives the same balances (no duplicates).
      await h.app.backups.restore(backup.databaseFile.path, h.owner);
      expect(await h.app.queries.cashBalances(), snapshotCash);

      // A safety backup of the pre-restore state was taken.
      final history = await h.app.backups.history();
      expect(history.any((r) => r['kind'] == 'pre_restore'), isTrue);
    });

    test('tampered backup is rejected and the live database is untouched', () async {
      await h.openingCash('AFN', afn(5000));
      final backup = await h.app.backups.create(actor: h.owner);
      final bytes = await backup.databaseFile.readAsBytes();
      bytes[bytes.length - 100] ^= 0xFF;
      await backup.databaseFile.writeAsBytes(bytes);

      final v = await h.app.backups.verify(backup.databaseFile.path);
      expect(v.isValid, isFalse);
      await expectLater(h.app.backups.restore(backup.databaseFile.path, h.owner),
          throwsA(isA<BusinessRuleError>()));
      expect(await h.app.queries.cashBalance('AFN'), afn(5000));
    });

    test('non-database files are rejected', () async {
      final f = File('${h.dir.path}/not_a_db.db');
      await f.writeAsString('hello');
      final v = await h.app.backups.verify(f.path);
      expect(v.isValid, isFalse);
    });

    test('automatic backup runs once per interval and respects retention', () async {
      final first = await h.app.backups.autoBackupIfDue();
      expect(first, isNotNull);
      expect(await h.app.backups.autoBackupIfDue(), isNull);
    });
  });
}
