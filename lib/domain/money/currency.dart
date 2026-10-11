import '../errors/domain_errors.dart';
import 'decimal.dart';

/// A currency from the configurable catalog (`currencies` table).
///
/// [code] is the stable identifier used by every financial record; display
/// names may change freely without affecting history.
final class Currency {
  const Currency({
    required this.code,
    required this.nameFa,
    required this.symbol,
    required this.precision,
    required this.rateScale,
    required this.rounding,
    this.isActive = true,
    this.sortOrder = 0,
  });

  /// Stable identifier, e.g. `AFN`, `USD`, `IRT`.
  final String code;
  final String nameFa;
  final String symbol;

  /// Number of decimals for amounts (minor units = amount × 10^precision).
  final int precision;

  /// Maximum decimals allowed in a rate quoted as "1 [code] = R other".
  final int rateScale;

  /// Rounding used when a computed amount in this currency must be reduced
  /// to [precision] decimals (e.g. the counter amount of an exchange).
  final RoundingMode rounding;

  final bool isActive;
  final int sortOrder;

  /// Parses a user-entered amount into minor units, rejecting values with
  /// more decimals than [precision].
  int parseAmount(String raw) => Decimal.parse(raw).toMinor(precision);

  Decimal toDecimal(int minor) => Decimal.fromMinor(minor, precision);

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// An amount in integer minor units of a specific currency.
final class Money {
  const Money(this.minor, this.currency);

  final int minor;
  final String currency;

  bool get isPositive => minor > 0;
  bool get isZero => minor == 0;

  Money operator -() => Money(-minor, currency);

  Money operator +(Money other) {
    _same(other);
    return Money(minor + other.minor, currency);
  }

  Money operator -(Money other) {
    _same(other);
    return Money(minor - other.minor, currency);
  }

  void _same(Money other) {
    if (other.currency != currency) {
      throw InvariantViolation(
        'money.currencyMismatch',
        'جمع مبالغ با ارزهای متفاوت مجاز نیست ($currency / ${other.currency}).',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => '$minor $currency(minor)';
}

/// Seed definitions for the five initial currencies.
///
/// `IRT` is the application-defined **Iranian toman** (1 toman = 10 Iranian
/// rials). It is deliberately not the ISO code `IRR` (rial) so the two units
/// can never be confused.
abstract final class SeedCurrencies {
  static const afn = Currency(
    code: 'AFN',
    nameFa: 'افغانی',
    symbol: '؋',
    precision: 2,
    rateScale: 6,
    rounding: RoundingMode.halfUp,
    sortOrder: 1,
  );
  static const usd = Currency(
    code: 'USD',
    nameFa: 'دالر',
    symbol: r'$',
    precision: 2,
    rateScale: 6,
    rounding: RoundingMode.halfUp,
    sortOrder: 2,
  );
  static const eur = Currency(
    code: 'EUR',
    nameFa: 'یورو',
    symbol: '€',
    precision: 2,
    rateScale: 6,
    rounding: RoundingMode.halfUp,
    sortOrder: 3,
  );
  static const irt = Currency(
    code: 'IRT',
    nameFa: 'تومان',
    symbol: 'T',
    precision: 0,
    rateScale: 8,
    rounding: RoundingMode.halfUp,
    sortOrder: 4,
  );
  static const pkr = Currency(
    code: 'PKR',
    nameFa: 'کالدار',
    symbol: '₨',
    precision: 2,
    rateScale: 6,
    rounding: RoundingMode.halfUp,
    sortOrder: 5,
  );

  static const all = [afn, usd, eur, irt, pkr];
}
