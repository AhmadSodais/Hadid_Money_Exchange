import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/errors/domain_errors.dart';
import '../domain/exchange/exchange_rate.dart';
import '../domain/money/decimal.dart';
import '../domain/security/permissions.dart';
import 'audit_writer.dart';
import 'catalog_service.dart';
import 'ledger_events.dart';

/// Board rate for one ordered pair. [buyRate] is what the exchange pays per
/// unit of [base]; [sellRate] is what it charges per unit of [base].
final class BoardRate {
  const BoardRate({
    required this.base,
    required this.quote,
    required this.buyRate,
    required this.sellRate,
    required this.effectiveAt,
  });

  final String base;
  final String quote;
  final Decimal buyRate;
  final Decimal sellRate;
  final DateTime effectiveAt;
}

/// Rate board. Rates are reference values only: a posted transaction stores
/// the rate actually used, so changing the board never alters history.
/// No rate is ever hard-coded.
final class RateService {
  RateService(this._db, this._catalog, this._events);

  final Database _db;
  final CatalogService _catalog;
  final LedgerEvents _events;

  Future<void> setRate({
    required String base,
    required String quote,
    required Decimal buyRate,
    required Decimal sellRate,
    required Actor actor,
  }) async {
    if (!actor.can(Permissions.ratesManage)) {
      throw const AuthorizationError('auth.denied', 'اجازه تغییر نرخ را ندارید.');
    }
    final currencies = await _catalog.currencies();
    final b = currencies[base];
    final q = currencies[quote];
    if (b == null || q == null) {
      throw const ValidationError('currency.unknown', 'ارز ناشناخته.');
    }
    ExchangeRate.of(b, q, buyRate);
    ExchangeRate.of(b, q, sellRate);
    if (buyRate > sellRate) {
      throw const ValidationError('rate.buyAboveSell',
          'نرخ خرید نباید از نرخ فروش بیشتر باشد.', field: 'buyRate');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.insert('exchange_rates', {
        'base_currency': base,
        'quote_currency': quote,
        'buy_rate': buyRate.toCanonical(),
        'sell_rate': sellRate.toCanonical(),
        'convention': kRateConvention,
        'effective_at': now,
        'created_by': actor.userId,
        'created_at': now,
      });
      await AuditWriter.write(txn,
          actor: actor,
          action: 'rate.set',
          entityType: 'exchange_rate',
          entityId: '$base/$quote',
          after: {'buy': buyRate.toCanonical(), 'sell': sellRate.toCanonical()});
    });
    _events.notify(LedgerChange.rates);
  }

  Future<BoardRate?> latest(String base, String quote) async {
    final rows = await _db.query('exchange_rates',
        where: 'base_currency = ? AND quote_currency = ?',
        whereArgs: [base, quote],
        orderBy: 'effective_at DESC, id DESC',
        limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Latest board rate of every ordered pair that has one.
  Future<List<BoardRate>> board() async {
    final rows = await _db.rawQuery('''
      SELECT r.* FROM exchange_rates r
      WHERE r.id = (SELECT r2.id FROM exchange_rates r2
                    WHERE r2.base_currency = r.base_currency
                      AND r2.quote_currency = r.quote_currency
                    ORDER BY r2.effective_at DESC, r2.id DESC LIMIT 1)
      ORDER BY r.base_currency, r.quote_currency
    ''');
    return rows.map(_fromRow).toList();
  }

  Future<List<BoardRate>> history(String base, String quote, {int limit = 50}) async {
    final rows = await _db.query('exchange_rates',
        where: 'base_currency = ? AND quote_currency = ?',
        whereArgs: [base, quote],
        orderBy: 'effective_at DESC, id DESC',
        limit: limit);
    return rows.map(_fromRow).toList();
  }

  static BoardRate _fromRow(Map<String, Object?> r) => BoardRate(
        base: r['base_currency'] as String,
        quote: r['quote_currency'] as String,
        buyRate: Decimal.parse(r['buy_rate'] as String),
        sellRate: Decimal.parse(r['sell_rate'] as String),
        effectiveAt: DateTime.parse(r['effective_at'] as String),
      );
}
