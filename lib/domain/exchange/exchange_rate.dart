import '../errors/domain_errors.dart';
import '../money/currency.dart';
import '../money/decimal.dart';

/// Quotation convention used everywhere in the application:
///
///     1 unit of [base] = [rate] units of [quote]
///     quoteAmount = baseAmount × rate
///
/// This replaces the legacy rule "divide when the source is AFN, otherwise
/// multiply", which silently produced wrong amounts for non-AFN pairs.
const String kRateConvention = 'BASE_TO_QUOTE';

/// Upper bound for a single rate value (sanity check against typos).
final Decimal _maxRate = Decimal.fromInt(1000000000);

final class ExchangeRate {
  ExchangeRate._(this.base, this.quote, this.rate);

  /// Validates and creates a rate. Rejects zero, negative, and excessively
  /// precise values (more decimals than [base].rateScale).
  factory ExchangeRate.of(Currency base, Currency quote, Decimal rate) {
    if (base.code == quote.code) {
      throw const ValidationError(
        'rate.samePair',
        'ارز مبدا و مقصد نمی‌توانند یکسان باشند.',
        field: 'rate',
      );
    }
    if (!rate.isPositive) {
      throw const ValidationError(
        'rate.notPositive',
        'نرخ باید بزرگتر از صفر باشد.',
        field: 'rate',
      );
    }
    if (rate.significantScale > base.rateScale) {
      throw ValidationError(
        'rate.tooPrecise',
        'نرخ حداکثر ${base.rateScale} رقم اعشار می‌تواند داشته باشد.',
        field: 'rate',
      );
    }
    if (rate > _maxRate) {
      throw const ValidationError(
        'rate.tooLarge',
        'نرخ واردشده غیرعادی بزرگ است.',
        field: 'rate',
      );
    }
    return ExchangeRate._(base, quote, rate);
  }

  final Currency base;
  final Currency quote;
  final Decimal rate;

  /// Converts [baseMinor] (minor units of [base]) to minor units of [quote],
  /// rounding with the quote currency's configured rounding mode.
  int convert(int baseMinor) {
    final baseAmount = Decimal.fromMinor(baseMinor, base.precision);
    final quoteAmount = baseAmount * rate;
    return quoteAmount.toMinor(quote.precision, mode: quote.rounding);
  }

  /// Reciprocal quote (1 [quote] = 1/rate [base]) rounded to the quote
  /// currency's rate scale.
  ExchangeRate reciprocal() {
    final inv = Decimal.one.divide(rate, quote.rateScale, RoundingMode.halfUp);
    if (inv.isZero) {
      throw ValidationError(
        'rate.reciprocalZero',
        'نرخ معکوس با دقت ${quote.rateScale} رقم قابل نمایش نیست.',
        field: 'rate',
      );
    }
    return ExchangeRate._(quote, base, inv);
  }

  @override
  String toString() => '1 ${base.code} = ${rate.toCanonical()} ${quote.code}';
}
