import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';

/// App-wide calendar system for display and picking.
///
/// Storage remains Gregorian [DateTime]. UI formatting / pickers follow [type].
enum AppCalendarType {
  gregorian,
  solar,
  lunar;

  static const defaultType = AppCalendarType.solar;

  static AppCalendarType parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'solar':
      case 'jalali':
      case 'shamsi':
        return AppCalendarType.solar;
      case 'lunar':
      case 'hijri':
        return AppCalendarType.lunar;
      case 'gregorian':
      case 'miladi':
      default:
        return AppCalendarType.gregorian;
    }
  }

  String get storageKey => name;
}

/// Facade used by [Formatters], date fields, and filters.
abstract final class AppCalendar {
  static AppCalendarType _type = AppCalendarType.defaultType;

  static AppCalendarType get type => _type;

  static void apply(AppCalendarType type) {
    _type = type;
  }

  static void applyFromKey(String? key) => apply(AppCalendarType.parse(key));

  // ── Formatting ───────────────────────────────────────────────────────────

  static String formatDate(DateTime date) {
    final local = date.toLocal();
    return switch (_type) {
      AppCalendarType.gregorian =>
        '${local.year}/${local.month}/${local.day}',
      AppCalendarType.solar => _solarYmd(local),
      AppCalendarType.lunar => _lunarYmd(local),
    };
  }

  static String formatDateTime(DateTime date) {
    final local = date.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${formatDate(local)} · $h:$m';
  }

  static String formatRange(DateTime start, DateTime end) {
    if (_sameDay(start, end)) return formatDate(start);
    return '${formatDate(start)} – ${formatDate(end)}';
  }

  static String formatMonthYear(DateTime date) {
    final local = date.toLocal();
    return switch (_type) {
      AppCalendarType.gregorian => '${local.year}/${local.month}',
      AppCalendarType.solar => () {
          final j = Jalali.fromDateTime(local);
          return '${j.year}/${j.month}';
        }(),
      AppCalendarType.lunar => () {
          final h = HijriCalendar.fromDate(local);
          return '${h.hYear}/${h.hMonth}';
        }(),
    };
  }

  static String formatYear(DateTime date) {
    final local = date.toLocal();
    return switch (_type) {
      AppCalendarType.gregorian => '${local.year}',
      AppCalendarType.solar => '${Jalali.fromDateTime(local).year}',
      AppCalendarType.lunar => '${HijriCalendar.fromDate(local).hYear}',
    };
  }

  static String weekdayName(DateTime date) {
    final local = date.toLocal();
    return switch (_type) {
      AppCalendarType.gregorian => _gregorianWeekday(local.weekday),
      AppCalendarType.solar => () {
          final day = Jalali.fromDateTime(local).weekDay.clamp(1, 7);
          return _solarWeekdays[day - 1];
        }(),
      AppCalendarType.lunar => () {
          // Hijri package weekday names are English; map via Gregorian weekday.
          return _gregorianWeekday(local.weekday);
        }(),
    };
  }

  static String monthName(DateTime date) {
    final local = date.toLocal();
    return switch (_type) {
      AppCalendarType.gregorian =>
        'calendar.months.${_gregorianMonthKeys[local.month - 1]}'.tr(),
      AppCalendarType.solar => () {
          final m = Jalali.fromDateTime(local).month.clamp(1, 12);
          return _solarMonths[m - 1];
        }(),
      AppCalendarType.lunar => () {
          final h = HijriCalendar.fromDate(local);
          final m = h.hMonth.clamp(1, 12);
          return 'calendar.lunarMonths.${_lunarMonthKeys[m - 1]}'.tr();
        }(),
    };
  }

  // ── Periods (filter / overview) ──────────────────────────────────────────

  static DateTime dateOnly(DateTime date) {
    final local = date.toLocal();
    return switch (_type) {
      AppCalendarType.gregorian =>
        DateTime(local.year, local.month, local.day),
      AppCalendarType.solar => () {
          final j = Jalali.fromDateTime(local);
          return Jalali(j.year, j.month, j.day).toDateTime();
        }(),
      AppCalendarType.lunar => () {
          final h = HijriCalendar.fromDate(local);
          return h.hijriToGregorian(h.hYear, h.hMonth, h.hDay);
        }(),
    };
  }

  static DateTime endOfDay(DateTime date) {
    final d = dateOnly(date);
    return DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
  }

  static (DateTime from, DateTime to) today([DateTime? now]) {
    final d = dateOnly(now ?? DateTime.now());
    return (d, endOfDay(d));
  }

  static (DateTime from, DateTime to) yesterday([DateTime? now]) {
    final d = dateOnly(now ?? DateTime.now()).subtract(const Duration(days: 1));
    final day = dateOnly(d);
    return (day, endOfDay(day));
  }

  static (DateTime from, DateTime to) thisWeek([DateTime? now]) {
    final base = now ?? DateTime.now();
    return switch (_type) {
      AppCalendarType.gregorian => () {
          // ISO week: Monday = 1 … Sunday = 7
          final d = dateOnly(base);
          final from = d.subtract(Duration(days: d.weekday - 1));
          final to = from.add(const Duration(days: 6));
          return (from, endOfDay(to));
        }(),
      AppCalendarType.solar => () {
          final j = Jalali.fromDateTime(base.toLocal());
          final start = j.addDays(-(j.weekDay - 1));
          final end = start.addDays(6);
          return (start.toDateTime(), endOfDay(end.toDateTime()));
        }(),
      // Lunar week filter uses ISO Mon–Sun on the civil calendar.
      AppCalendarType.lunar => () {
          final d = dateOnly(base);
          final from = d.subtract(Duration(days: d.weekday - 1));
          final to = from.add(const Duration(days: 6));
          return (from, endOfDay(to));
        }(),
    };
  }

  static (DateTime from, DateTime to) thisMonth([DateTime? now]) {
    final base = now ?? DateTime.now();
    return switch (_type) {
      AppCalendarType.gregorian => () {
          final d = base.toLocal();
          final from = DateTime(d.year, d.month, 1);
          final to = DateTime(d.year, d.month + 1, 0);
          return (from, endOfDay(to));
        }(),
      AppCalendarType.solar => () {
          final j = Jalali.fromDateTime(base.toLocal());
          final from = Jalali(j.year, j.month, 1);
          final to = Jalali(j.year, j.month, j.monthLength);
          return (from.toDateTime(), endOfDay(to.toDateTime()));
        }(),
      AppCalendarType.lunar => () {
          final h = HijriCalendar.fromDate(base.toLocal());
          final from = h.hijriToGregorian(h.hYear, h.hMonth, 1);
          final len = h.getDaysInMonth(h.hYear, h.hMonth);
          final to = h.hijriToGregorian(h.hYear, h.hMonth, len);
          return (dateOnly(from), endOfDay(to));
        }(),
    };
  }

  static (DateTime from, DateTime to) thisYear([DateTime? now]) {
    final base = now ?? DateTime.now();
    return switch (_type) {
      AppCalendarType.gregorian => () {
          final y = base.toLocal().year;
          return (DateTime(y, 1, 1), endOfDay(DateTime(y, 12, 31)));
        }(),
      AppCalendarType.solar => () {
          final j = Jalali.fromDateTime(base.toLocal());
          final from = Jalali(j.year, 1, 1);
          final esfandLen = Jalali(j.year, 12, 1).monthLength;
          final to = Jalali(j.year, 12, esfandLen);
          return (from.toDateTime(), endOfDay(to.toDateTime()));
        }(),
      AppCalendarType.lunar => () {
          final h = HijriCalendar.fromDate(base.toLocal());
          final from = h.hijriToGregorian(h.hYear, 1, 1);
          final len = h.getDaysInMonth(h.hYear, 12);
          final to = h.hijriToGregorian(h.hYear, 12, len);
          return (dateOnly(from), endOfDay(to));
        }(),
    };
  }

  // ── Picking ──────────────────────────────────────────────────────────────

  static Future<DateTime?> Function(
    BuildContext context, {
    DateTime? initial,
    String? title,
  })? _solarPicker;

  static void bindSolarPicker(
    Future<DateTime?> Function(
      BuildContext context, {
      DateTime? initial,
      String? title,
    }) picker,
  ) {
    _solarPicker = picker;
  }

  static Future<DateTime?> pickDate(
    BuildContext context, {
    DateTime? initial,
    String? title,
  }) async {
    final seed = initial ?? DateTime.now();
    switch (_type) {
      case AppCalendarType.solar:
        final custom = _solarPicker;
        if (custom != null) {
          return custom(context, initial: seed, title: title);
        }
        final picked = await showPersianDatePicker(
          context: context,
          initialDate: Jalali.fromDateTime(seed),
          firstDate: Jalali(Jalali.now().year - 100, 1, 1),
          lastDate: Jalali(Jalali.now().year + 100, 12, 29),
          initialEntryMode: PersianDatePickerEntryMode.calendarOnly,
        );
        return picked?.toDateTime();
      case AppCalendarType.gregorian:
      case AppCalendarType.lunar:
        // Lunar uses Material picker; values are stored as Gregorian DateTime
        // and displayed with Hijri formatting throughout the app.
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: seed,
          firstDate: DateTime(now.year - 100),
          lastDate: DateTime(now.year + 100),
          helpText: title,
        );
        return picked == null ? null : dateOnly(picked);
    }
  }

  static Future<DateTimeRange?> pickRange(
    BuildContext context, {
    DateTime? start,
    DateTime? end,
  }) async {
    if (_type == AppCalendarType.solar) {
      final initialStart = Jalali.fromDateTime(start ?? DateTime.now());
      final initialEnd = Jalali.fromDateTime(end ?? DateTime.now());
      final range = await showPersianDateRangePicker(
        context: context,
        initialDate: initialStart,
        initialDateRange: JalaliRange(start: initialStart, end: initialEnd),
        firstDate: Jalali(Jalali.now().year - 100, 1, 1),
        lastDate: Jalali(Jalali.now().year + 100, 12, 29),
      );
      if (range == null) return null;
      return DateTimeRange(
        start: range.start.toDateTime(),
        end: endOfDay(range.end.toDateTime()),
      );
    }
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 100),
      lastDate: DateTime(DateTime.now().year + 100),
      initialDateRange: DateTimeRange(
        start: dateOnly(start ?? DateTime.now()),
        end: dateOnly(end ?? DateTime.now()),
      ),
    );
    if (range == null) return null;
    return DateTimeRange(
      start: dateOnly(range.start),
      end: endOfDay(range.end),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _solarYmd(DateTime local) {
    final j = Jalali.fromDateTime(local);
    return '${j.year}/${j.month}/${j.day}';
  }

  static String _lunarYmd(DateTime local) {
    final h = HijriCalendar.fromDate(local);
    return '${h.hYear}/${h.hMonth}/${h.hDay}';
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final da = dateOnly(a);
    final db = dateOnly(b);
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  static String _gregorianWeekday(int weekday) {
    // DateTime.weekday: 1=Mon … 7=Sun
    const keys = [
      'mon',
      'tue',
      'wed',
      'thu',
      'fri',
      'sat',
      'sun',
    ];
    return 'calendar.weekdays.${keys[(weekday - 1).clamp(0, 6)]}'.tr();
  }

  static const _gregorianMonthKeys = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  static const _lunarMonthKeys = [
    'muharram',
    'safar',
    'rabi1',
    'rabi2',
    'jumada1',
    'jumada2',
    'rajab',
    'shaban',
    'ramadan',
    'shawwal',
    'dhulQadah',
    'dhulHijjah',
  ];

  static const _solarMonths = [
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

  static const _solarWeekdays = [
    'شنبه',
    'یکشنبه',
    'دوشنبه',
    'سه‌شنبه',
    'چهارشنبه',
    'پنجشنبه',
    'جمعه',
  ];
}
