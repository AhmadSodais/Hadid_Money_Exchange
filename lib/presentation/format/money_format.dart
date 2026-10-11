import '../../core/utils/app_calendar.dart';
import '../../core/utils/formatters.dart';
import '../../domain/money/currency.dart';
import '../../domain/money/decimal.dart';
import '../../domain/shared/business_date.dart';

/// Display formatting for exact amounts. Works on integer minor units and
/// [Decimal] only; no floating-point value is ever involved.
abstract final class MoneyFormat {
  /// `1,234.50` for minor 123450 in a 2-decimal currency.
  static String amount(int minor, Currency? currency) {
    final precision = currency?.precision ?? 2;
    return decimal(Decimal.fromMinor(minor, precision));
  }

  /// Amount followed by the Persian currency name, e.g. `1,234.50 دالر`.
  static String withName(int minor, Currency? currency, {String? fallbackCode}) {
    final name = currency?.nameFa ?? fallbackCode ?? '';
    return '${amount(minor, currency)} $name'.trim();
  }

  /// Groups the integer part of a decimal string with commas.
  static String decimal(Decimal value) {
    final text = value.toFixedString();
    final negative = text.startsWith('-');
    final body = negative ? text.substring(1) : text;
    final dot = body.indexOf('.');
    final intPart = dot < 0 ? body : body.substring(0, dot);
    final frac = dot < 0 ? '' : body.substring(dot);
    return '${negative ? '-' : ''}${ThousandsSeparatorInputFormatter.groupDigits(intPart)}$frac';
  }

  /// Rate text, trailing zeros removed (rates are stored canonically).
  static String rate(String canonical) {
    final d = Decimal.tryParse(canonical);
    return d == null ? canonical : decimal(Decimal.parse(d.toCanonical()));
  }

  /// Customer position wording (positive = the exchange owes the customer).
  static String position(int minor, Currency? currency) {
    if (minor == 0) return 'تسویه';
    final text = withName(minor.abs(), currency);
    return minor > 0 ? '$text طلب مشتری' : '$text بدهی مشتری';
  }

  /// Parses user input into minor units for [currency].
  /// Throws a `ValidationError` for malformed or over-precise input.
  static int parse(String raw, Currency currency) =>
      currency.parseAmount(raw.replaceAll(',', ''));

  /// Returns null instead of throwing (for live previews).
  static int? tryParse(String raw, Currency currency) {
    try {
      final text = raw.replaceAll(',', '').trim();
      if (text.isEmpty) return null;
      return currency.parseAmount(text);
    } catch (_) {
      return null;
    }
  }

  /// Formats minor units back into editable text (no grouping).
  static String editable(int minor, Currency currency) =>
      Decimal.fromMinor(minor, currency.precision).toFixedString();
}

abstract final class DateFormatFa {
  static String business(BusinessDate date) => AppCalendar.formatDate(date.toDateTime());

  static String dateTime(DateTime utc) => AppCalendar.formatDateTime(utc.toLocal());
}