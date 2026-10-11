import 'package:flutter/services.dart';

import 'app_calendar.dart';

/// Date display helpers. Money is formatted exclusively by
/// `MoneyFormat` (exact integer minor units) — never through `num`.
abstract final class Formatters {
  static String date(DateTime date) => AppCalendar.formatDate(date);

  static String dateRange(DateTime start, DateTime end) =>
      AppCalendar.formatRange(start, end);

  static String dateTime(DateTime date) => AppCalendar.formatDateTime(date);
}

/// Live thousands-separator (comma) formatter for numeric text fields.
/// Persian / Arabic-Indic digits and the Persian decimal separator are
/// normalized to ASCII as the user types.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter();

  static String normalize(String raw) {
    final b = StringBuffer();
    for (final r in raw.runes) {
      if (r >= 0x06F0 && r <= 0x06F9) {
        b.writeCharCode(0x30 + r - 0x06F0);
      } else if (r >= 0x0660 && r <= 0x0669) {
        b.writeCharCode(0x30 + r - 0x0660);
      } else if (r == 0x066B) {
        b.write('.');
      } else if (r == 0x066C || r == 0x060C) {
        b.write(',');
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = normalize(newValue.text);
    if (raw.isEmpty) return newValue.copyWith(text: raw);

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
    final body = negative ? cleaned.substring(1) : cleaned;
    if (body.isEmpty) return negative ? '-' : '';

    if (RegExp(r'[^0-9.]').hasMatch(body)) return null;

    final parts = body.split('.');
    if (parts.length > 2) return null;

    final intDigits = parts[0];
    final frac = parts.length == 2 ? parts[1] : null;

    final intFormatted = intDigits.isEmpty
        ? (frac != null ? '0' : '')
        : groupDigits(intDigits);

    final buffer = StringBuffer();
    if (negative) buffer.write('-');
    buffer.write(intFormatted);
    if (frac != null) {
      buffer.write('.');
      buffer.write(frac);
    }
    return buffer.toString();
  }

  static String groupDigits(String digits) {
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
