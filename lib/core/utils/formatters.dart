import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';

import 'app_calendar.dart';

/// Formatting helpers for money, dates, and numbers.
///
/// Numbers always use English-style thousands separators (commas),
/// e.g. `1,250` / `12,500.75`, regardless of app locale.
///
/// Date displays follow [AppCalendar] (Gregorian / Solar / Lunar).
/// Money amounts use localized currency names (Afghani / Dollar / Euro).
abstract final class Formatters {
  static final NumberFormat _grouped = NumberFormat('#,##0.###', 'en_US');

  static NumberFormat _fixed(int decimals) => NumberFormat.decimalPattern('en_US')
    ..minimumFractionDigits = decimals
    ..maximumFractionDigits = decimals;

  /// Localized display name for a currency code (AFN → Afghani / افغانی).
  static String currencyName(String? code) {
    final c = (code ?? '').trim().toUpperCase();
    return switch (c) {
      '' || 'AFN' => 'currency.afn'.tr(),
      'USD' => 'currency.usd'.tr(),
      'EUR' => 'currency.eur'.tr(),
      _ => c,
    };
  }

  static String money(num value, {String currency = 'AFN', int decimals = 0}) {
    return '${_fixed(decimals).format(value)} ${currencyName(currency)}';
  }

  /// Joins multi-currency amounts as `1,000 Afghani · 50 Dollar`.
  ///
  /// Use [separator] `'\n'` for stacked KPI lines.
  static String moneyByCurrency(
    Map<String, double> amounts, {
    String fallbackCurrency = 'AFN',
    String separator = ' · ',
  }) {
    final parts = amounts.entries
        .where((e) => e.value > 0)
        .map((e) => money(e.value, currency: e.key.trim().isEmpty
            ? fallbackCurrency
            : e.key.trim()))
        .toList();
    if (parts.isEmpty) return money(0, currency: fallbackCurrency);
    return parts.join(separator);
  }

  /// Formats [value] with comma thousands separators.
  ///
  /// When [decimals] is null, keeps up to 3 useful fraction digits
  /// (integers stay without a decimal point).
  static String number(num value, {int? decimals}) {
    if (decimals != null) return _fixed(decimals).format(value);
    return _grouped.format(value);
  }

  static String percent(num value, {int decimals = 1}) {
    final sign = value >= 0 ? '+' : '';
    return '$sign${_fixed(decimals).format(value)}%';
  }

  /// Parses a user-entered number, ignoring thousands commas.
  static double? parse(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().replaceAll(',', '');
    if (s.isEmpty || s == '-' || s == '.' || s == '-.') return null;
    return double.tryParse(s);
  }

  static String date(DateTime date) => AppCalendar.formatDate(date);

  static String dateRange(DateTime start, DateTime end) =>
      AppCalendar.formatRange(start, end);

  static String dateTime(DateTime date) => AppCalendar.formatDateTime(date);

  static String relative(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return Formatters.date(date);
  }

  static String dimensions(num? width, num? height, {String unit = 'mm'}) {
    if (width == null && height == null) return '—';
    return '${number(width ?? 0)} × ${number(height ?? 0)} $unit';
  }
}

/// Live thousands-separator (comma) formatter for numeric text fields.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    if (raw.isEmpty) return newValue;

    if (RegExp(r'[^0-9.,\-]').hasMatch(raw)) return oldValue;

    final cleaned = raw.replaceAll(',', '');
    if (cleaned == '-' || cleaned == '.' || cleaned == '-.') {
      return TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }

    final formatted = formatPlain(cleaned);
    if (formatted == null) return oldValue;

    // Keep caret distance from the end stable as commas are inserted/removed.
    final fromEnd = raw.length - newValue.selection.end;
    final offset = (formatted.length - fromEnd).clamp(0, formatted.length);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  /// Formats a plain numeric string (no commas) with thousands separators.
  static String? formatPlain(String cleaned) {
    final negative = cleaned.startsWith('-');
    var body = negative ? cleaned.substring(1) : cleaned;
    if (body.isEmpty) return negative ? '-' : '';

    if (RegExp(r'[^0-9.]').hasMatch(body)) return null;

    final parts = body.split('.');
    if (parts.length > 2) return null;

    final intDigits = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
    final frac = parts.length == 2 ? parts[1].replaceAll(RegExp(r'[^0-9]'), '') : null;

    final intFormatted = intDigits.isEmpty
        ? (frac != null ? '0' : '')
        : _commas(intDigits);

    final buffer = StringBuffer();
    if (negative) buffer.write('-');
    buffer.write(intFormatted);
    if (frac != null) {
      buffer.write('.');
      buffer.write(frac);
    }
    return buffer.toString();
  }

  static String _commas(String digits) {
    if (digits.length <= 3) return digits;
    final buf = StringBuffer();
    final start = digits.length % 3;
    if (start > 0) buf.write(digits.substring(0, start));
    for (var i = start; i < digits.length; i += 3) {
      if (buf.isNotEmpty) buf.write(',');
      buf.write(digits.substring(i, i + 3));
    }
    return buf.toString();
  }
}
