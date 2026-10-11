import '../errors/domain_errors.dart';

/// A calendar date without time-of-day, used as the business-effective date
/// of financial records.
///
/// Stored as ISO `YYYY-MM-DD` (Gregorian) so it sorts lexically in SQLite.
/// Jalali conversion happens only at the presentation boundary.
final class BusinessDate implements Comparable<BusinessDate> {
  BusinessDate(this.year, this.month, this.day) {
    final check = DateTime.utc(year, month, day);
    if (check.year != year || check.month != month || check.day != day) {
      throw ValidationError('date.invalid', 'تاریخ نامعتبر است: $year-$month-$day');
    }
  }

  factory BusinessDate.fromDateTime(DateTime dt) =>
      BusinessDate(dt.year, dt.month, dt.day);

  factory BusinessDate.today([DateTime? clock]) =>
      BusinessDate.fromDateTime((clock ?? DateTime.now()).toLocal());

  static BusinessDate parse(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso.trim());
    if (m == null) {
      throw ValidationError('date.invalid', 'قالب تاریخ نامعتبر است: $iso');
    }
    return BusinessDate(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  final int year;
  final int month;
  final int day;

  String get iso =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  DateTime toDateTime() => DateTime(year, month, day);

  BusinessDate addDays(int days) =>
      BusinessDate.fromDateTime(DateTime.utc(year, month, day).add(Duration(days: days)));

  int daysUntil(BusinessDate other) => DateTime.utc(other.year, other.month, other.day)
      .difference(DateTime.utc(year, month, day))
      .inDays;

  bool isAfter(BusinessDate o) => compareTo(o) > 0;
  bool isBefore(BusinessDate o) => compareTo(o) < 0;

  @override
  int compareTo(BusinessDate other) => iso.compareTo(other.iso);

  @override
  bool operator ==(Object other) => other is BusinessDate && other.iso == iso;

  @override
  int get hashCode => iso.hashCode;

  @override
  String toString() => iso;
}
