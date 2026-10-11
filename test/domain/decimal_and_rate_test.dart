import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/domain/errors/domain_errors.dart';
import 'package:hadid_exchange/domain/exchange/exchange_rate.dart';
import 'package:hadid_exchange/domain/money/currency.dart';
import 'package:hadid_exchange/domain/money/decimal.dart';

void main() {
  group('Decimal parsing', () {
    test('plain, grouped, Persian digits, Arabic separators, Unicode minus', () {
      expect(Decimal.parse('1234.50').toCanonical(), '1234.5');
      expect(Decimal.parse('1,234,567.25').toCanonical(), '1234567.25');
      expect(Decimal.parse('۱۲۳۴٫۵').toCanonical(), '1234.5');
      expect(Decimal.parse('١٢٣').toCanonical(), '123');
      expect(Decimal.parse('\u2212' '45.1').toCanonical(), '-45.1');
      expect(Decimal.parse('.5').toCanonical(), '0.5');
    });

    test('rejects non-finite and malformed input', () {
      for (final bad in ['', 'abc', '1e5', 'NaN', 'Infinity', '1.2.3', '--1', '-']) {
        expect(Decimal.tryParse(bad), isNull, reason: bad);
      }
    });

    test('equality ignores trailing zeros', () {
      expect(Decimal.parse('70.10'), Decimal.parse('70.1'));
      expect(Decimal.parse('70.10').hashCode, Decimal.parse('70.1').hashCode);
    });
  });

  group('Decimal rounding', () {
    Decimal d(String s) => Decimal.parse(s);

    test('half up / half even / down / up at the boundary', () {
      expect(d('2.345').rescale(2, RoundingMode.halfUp).toFixedString(), '2.35');
      expect(d('2.345').rescale(2, RoundingMode.halfEven).toFixedString(), '2.34');
      expect(d('2.355').rescale(2, RoundingMode.halfEven).toFixedString(), '2.36');
      expect(d('2.349').rescale(2, RoundingMode.down).toFixedString(), '2.34');
      expect(d('2.341').rescale(2, RoundingMode.up).toFixedString(), '2.35');
      expect(d('-2.345').rescale(2, RoundingMode.halfUp).toFixedString(), '-2.35');
    });

    test('division is exact up to requested scale', () {
      expect(d('1').divide(d('3'), 6, RoundingMode.halfUp).toFixedString(), '0.333333');
      expect(d('2').divide(d('3'), 4, RoundingMode.halfUp).toFixedString(), '0.6667');
      expect(() => d('1').divide(Decimal.zero, 2, RoundingMode.halfUp),
          throwsA(isA<ValidationError>()));
    });

    test('toMinor rejects excess precision instead of silently rounding', () {
      expect(d('12.34').toMinor(2), 1234);
      expect(d('12').toMinor(0), 12);
      expect(() => d('12.345').toMinor(2), throwsA(isA<ValidationError>()));
      expect(d('12.345').toMinor(2, mode: RoundingMode.halfUp), 1235);
    });

    test('toMinor rejects amounts beyond the safe bound', () {
      expect(() => d('100000000000000000').toMinor(2), throwsA(isA<ValidationError>()));
    });

    test('0.1 + 0.2 is exactly 0.3 (no binary floating point)', () {
      expect(d('0.1') + d('0.2'), d('0.3'));
    });
  });

  group('ExchangeRate', () {
    const all = SeedCurrencies.all;

    test('every one of the 20 ordered pairs converts with base→quote convention', () {
      var pairs = 0;
      for (final base in all) {
        for (final quote in all) {
          if (base == quote) continue;
          pairs++;
          final rate = ExchangeRate.of(base, quote, Decimal.parse('3.5'));
          // 10 units of base.
          final baseMinor = Decimal.fromInt(10).toMinor(base.precision);
          final quoteMinor = rate.convert(baseMinor);
          expect(quoteMinor, Decimal.parse('35').toMinor(quote.precision),
              reason: '${base.code}->${quote.code}');
        }
      }
      expect(pairs, 20);
    });

    test('USD→AFN and AFN→USD are both "multiply by quoted rate"', () {
      final usdAfn = ExchangeRate.of(SeedCurrencies.usd, SeedCurrencies.afn, Decimal.parse('70'));
      expect(usdAfn.convert(10000), 700000); // 100 USD → 7,000 AFN
      final afnUsd =
          ExchangeRate.of(SeedCurrencies.afn, SeedCurrencies.usd, Decimal.parse('0.0125'));
      expect(afnUsd.convert(800000), 10000); // 8,000 AFN × 0.0125 → 100 USD
    });

    test('quote rounding uses the quote currency policy', () {
      final afnUsd =
          ExchangeRate.of(SeedCurrencies.afn, SeedCurrencies.usd, Decimal.parse('0.014285'));
      // 7,000.00 AFN × 0.014285 = 99.995 USD → half-up to 100.00
      expect(afnUsd.convert(700000), 10000);
      final usdIrt =
          ExchangeRate.of(SeedCurrencies.usd, SeedCurrencies.irt, Decimal.parse('82500.5'));
      // 1.01 USD × 82,500.5 = 83,325.505 toman → precision 0 → 83,326
      expect(usdIrt.convert(101), 83326);
    });

    test('reciprocal uses exact decimal arithmetic and quote rate scale', () {
      final r = ExchangeRate.of(SeedCurrencies.usd, SeedCurrencies.afn, Decimal.parse('70'));
      final inv = r.reciprocal();
      expect(inv.base.code, 'AFN');
      expect(inv.quote.code, 'USD');
      expect(inv.rate.toCanonical(), '0.014286');
      final irt = ExchangeRate.of(SeedCurrencies.afn, SeedCurrencies.irt, Decimal.parse('850'));
      expect(irt.reciprocal().rate.toCanonical(), '0.00117647');
    });

    test('rejects zero, negative, same-pair, too precise, absurd rates', () {
      Matcher invalid(String code) =>
          throwsA(isA<ValidationError>().having((e) => e.code, 'code', code));
      expect(() => ExchangeRate.of(SeedCurrencies.usd, SeedCurrencies.afn, Decimal.zero),
          invalid('rate.notPositive'));
      expect(() => ExchangeRate.of(SeedCurrencies.usd, SeedCurrencies.afn, Decimal.parse('-1')),
          invalid('rate.notPositive'));
      expect(() => ExchangeRate.of(SeedCurrencies.usd, SeedCurrencies.usd, Decimal.one),
          invalid('rate.samePair'));
      expect(
          () => ExchangeRate.of(
              SeedCurrencies.usd, SeedCurrencies.afn, Decimal.parse('70.1234567')),
          invalid('rate.tooPrecise'));
      expect(
          () => ExchangeRate.of(
              SeedCurrencies.usd, SeedCurrencies.afn, Decimal.parse('99999999999')),
          invalid('rate.tooLarge'));
    });

    test('large amounts convert exactly', () {
      final r = ExchangeRate.of(SeedCurrencies.usd, SeedCurrencies.afn, Decimal.parse('70.125'));
      // 1,000,000,000.00 USD × 70.125 = 70,125,000,000.00 AFN
      expect(r.convert(100000000000), 7012500000000);
    });
  });
}
