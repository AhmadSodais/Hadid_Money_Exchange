import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';

import 'app_calendar.dart';

/// Legacy helpers — prefer [AppCalendar] / [Formatters].
///
/// Formatting, periods, and pickers respect the active [AppCalendar.type].
/// Storage stays as [DateTime] (Gregorian under the hood).
abstract final class ShamsiDates {
  /// ~100 years before/after current Shamsi year for long-range picking.
  static Jalali get minPicker {
    final y = Jalali.now().year - 100;
    return Jalali(y, 1, 1);
  }

  static Jalali get maxPicker {
    final y = Jalali.now().year + 100;
    final len = Jalali(y, 12, 1).monthLength;
    return Jalali(y, 12, len);
  }

  static Jalali of(DateTime date) => Jalali.fromDateTime(date.toLocal());

  static DateTime toDateTime(Jalali j) => j.toDateTime();

  static DateTime dateOnly(DateTime date) => AppCalendar.dateOnly(date);

  static DateTime endOfDay(DateTime date) => AppCalendar.endOfDay(date);

  static String formatDate(DateTime date) => AppCalendar.formatDate(date);

  static String formatMonthYear(DateTime date) =>
      AppCalendar.formatMonthYear(date);

  static String formatYear(DateTime date) => AppCalendar.formatYear(date);

  static String formatCompact(DateTime date) => formatDate(date);

  static String formatRange(DateTime start, DateTime end) =>
      AppCalendar.formatRange(start, end);

  static String formatDateTime(DateTime date) =>
      AppCalendar.formatDateTime(date);

  static (DateTime from, DateTime to) thisWeek([DateTime? now]) =>
      AppCalendar.thisWeek(now);

  static (DateTime from, DateTime to) thisMonth([DateTime? now]) =>
      AppCalendar.thisMonth(now);

  static (DateTime from, DateTime to) thisYear([DateTime? now]) =>
      AppCalendar.thisYear(now);

  static (DateTime from, DateTime to) today([DateTime? now]) =>
      AppCalendar.today(now);

  static (DateTime from, DateTime to) yesterday([DateTime? now]) =>
      AppCalendar.yesterday(now);

  /// Parses Shamsi `yyyy/M/d` or `yyyy/MM/dd` into a local [DateTime].
  /// Also accepts Gregorian years (>= 1700) as civil dates.
  static DateTime? tryParse(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    final parts = t.split(RegExp(r'[/-]'));
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    final d = int.tryParse(parts[2].trim());
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    // Civil Gregorian years.
    if (y >= 1700 && y <= 2200) {
      try {
        return DateTime(y, m, d);
      } catch (_) {
        return null;
      }
    }
    if (y < 1200 || y > 1600) return null;
    try {
      return Jalali(y, m, d).toDateTime();
    } catch (_) {
      return null;
    }
  }

  /// Called once from app bootstrap so [pickDate] uses the custom Solar picker.
  static void bindPicker(
    Future<DateTime?> Function(
      BuildContext context, {
      DateTime? initial,
      String? title,
    }) picker,
  ) {
    AppCalendar.bindSolarPicker(picker);
  }

  static Future<DateTime?> pickDate(
    BuildContext context, {
    DateTime? initial,
    String? title,
  }) =>
      AppCalendar.pickDate(context, initial: initial, title: title);

  static Future<DateTimeRange?> pickRange(
    BuildContext context, {
    DateTime? start,
    DateTime? end,
  }) =>
      AppCalendar.pickRange(context, start: start, end: end);

  /// Persian month names (حمل … حوت), 1-indexed.
  static const List<String> monthNames = [
    'حمل',
    'ثور',
    'جوزا',
    'سرطان',
    'اسد',
    'سنبله',
    'میزان',
    'عقرب',
    'قوس',
    'جدی',
    'دلو',
    'حوت',
  ];

  /// Shamsi weekday names (شنبه … جمعه). [Jalali.weekDay] is 1 = Saturday.
  static const List<String> weekdayNames = [
    'شنبه',
    'یکشنبه',
    'دوشنبه',
    'سه‌شنبه',
    'چهارشنبه',
    'پنجشنبه',
    'جمعه',
  ];

  static String weekdayName(DateTime date) => AppCalendar.weekdayName(date);

  static String monthName(DateTime date) => AppCalendar.monthName(date);

  static int weekOfMonth(DateTime date) {
    if (AppCalendar.type == AppCalendarType.solar) {
      final day = of(date).day;
      return ((day - 1) ~/ 7) + 1;
    }
    final day = dateOnly(date).day;
    return ((day - 1) ~/ 7) + 1;
  }

  static String weekOfMonthLabel(
    DateTime date, {
    String Function(int n)? format,
  }) {
    final week = weekOfMonth(date);
    if (format != null) return format(week);
    return 'هفته $week';
  }
}
