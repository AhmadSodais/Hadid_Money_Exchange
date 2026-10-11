import '../errors/domain_errors.dart';

/// Rounding behaviour applied when a value must be reduced to fewer decimals.
enum RoundingMode {
  /// 0.5 rounds away from zero (common commercial rounding).
  halfUp,

  /// 0.5 rounds to the nearest even digit (banker's rounding).
  halfEven,

  /// Truncate toward zero.
  down,

  /// Round away from zero whenever there is any remainder.
  up;

  static RoundingMode parse(String raw) => RoundingMode.values.firstWhere(
    (m) => m.name == raw,
    orElse: () => RoundingMode.halfUp,
  );
}

/// Exact base-10 decimal: `unscaled × 10^-scale`.
///
/// Used for money and exchange rates. Binary floating point is never used for
/// financial values anywhere in the application.
final class Decimal implements Comparable<Decimal> {
  Decimal._(this.unscaled, this.scale) : assert(scale >= 0);

  factory Decimal.fromBigInt(BigInt unscaled, int scale) {
    if (scale < 0) throw ArgumentError.value(scale, 'scale');
    return Decimal._(unscaled, scale);
  }

  factory Decimal.fromInt(int value) => Decimal._(BigInt.from(value), 0);

  /// Builds a decimal from integer minor units with [precision] decimals.
  factory Decimal.fromMinor(int minor, int precision) =>
      Decimal._(BigInt.from(minor), precision);

  static final Decimal zero = Decimal._(BigInt.zero, 0);
  static final Decimal one = Decimal._(BigInt.one, 0);

  final BigInt unscaled;
  final int scale;

  /// Parses user or stored text.
  ///
  /// Accepts Persian/Arabic-Indic digits, `٫` as a decimal separator, comma /
  /// `٬` / space thousands separators, and the Unicode minus sign. Rejects
  /// exponents, `NaN`, `Infinity`, and any other character.
  static Decimal parse(String raw) {
    final value = tryParse(raw);
    if (value == null) {
      throw ValidationError('number.invalid', 'عدد واردشده معتبر نیست: "$raw"');
    }
    return value;
  }

  static Decimal? tryParse(String? raw) {
    if (raw == null) return null;
    final text = normalizeDigits(raw)
        .replaceAll(RegExp(r'[,\u066C\s\u200C\u200F\u200E]'), '')
        .replaceAll('\u066B', '.');
    final match = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?$').firstMatch(text);
    if (match == null) return null;
    final sign = match.group(1) ?? '';
    final intPart = match.group(2) ?? '';
    final fracPart = match.group(3) ?? '';
    if (intPart.isEmpty && fracPart.isEmpty) return null;
    final digits = '${intPart.isEmpty ? '0' : intPart}$fracPart';
    var unscaled = BigInt.parse(digits);
    if (sign == '-') unscaled = -unscaled;
    return Decimal._(unscaled, fracPart.length);
  }

  /// Converts Persian (U+06F0..) and Arabic-Indic (U+0660..) digits to ASCII
  /// and Unicode minus (U+2212) / dashes used as minus to `-`.
  static String normalizeDigits(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.writeCharCode(0x30 + rune - 0x06F0);
      } else if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.writeCharCode(0x30 + rune - 0x0660);
      } else if (rune == 0x2212 || rune == 0x2012 || rune == 0x2013) {
        buffer.write('-');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString().trim();
  }

  bool get isZero => unscaled == BigInt.zero;
  bool get isNegative => unscaled < BigInt.zero;
  bool get isPositive => unscaled > BigInt.zero;
  int get signum => unscaled.sign;

  /// Number of decimals actually needed (trailing zeros ignored).
  int get significantScale => _stripped().scale;

  Decimal _stripped() {
    var u = unscaled;
    var s = scale;
    final ten = BigInt.from(10);
    while (s > 0 && u % ten == BigInt.zero) {
      u = u ~/ ten;
      s--;
    }
    return Decimal._(u, s);
  }

  Decimal abs() => isNegative ? Decimal._(-unscaled, scale) : this;
  Decimal operator -() => Decimal._(-unscaled, scale);

  Decimal operator +(Decimal other) {
    final s = scale > other.scale ? scale : other.scale;
    return Decimal._(_upscale(s) + other._upscale(s), s);
  }

  Decimal operator -(Decimal other) => this + (-other);

  Decimal operator *(Decimal other) =>
      Decimal._(unscaled * other.unscaled, scale + other.scale);

  /// `this / other` rounded to [resultScale] decimals.
  Decimal divide(Decimal other, int resultScale, RoundingMode mode) {
    if (other.isZero) {
      throw const ValidationError('number.divByZero', 'تقسیم بر صفر ممکن نیست.');
    }
    // this = a·10^-s1, other = b·10^-s2; result·10^-r = a·10^(s2 - s1 + r) / b
    final shift = other.scale - scale + resultScale;
    var numerator = unscaled;
    var denominator = other.unscaled;
    if (shift >= 0) {
      numerator *= BigInt.from(10).pow(shift);
    } else {
      denominator *= BigInt.from(10).pow(-shift);
    }
    return Decimal._(_divRound(numerator, denominator, mode), resultScale);
  }

  /// Returns the value with exactly [newScale] decimals.
  Decimal rescale(int newScale, RoundingMode mode) {
    if (newScale >= scale) return Decimal._(_upscale(newScale), newScale);
    final divisor = BigInt.from(10).pow(scale - newScale);
    return Decimal._(_divRound(unscaled, divisor, mode), newScale);
  }

  /// Integer minor units for a currency with [precision] decimals.
  ///
  /// Throws if rounding would be required and [mode] is null, so user-entered
  /// amounts with too many decimals are rejected instead of silently rounded.
  int toMinor(int precision, {RoundingMode? mode}) {
    if (significantScale > precision && mode == null) {
      throw ValidationError(
        'amount.tooPrecise',
        'تعداد ارقام اعشار بیشتر از حد مجاز ($precision) است.',
      );
    }
    final r = rescale(precision, mode ?? RoundingMode.halfUp).unscaled;
    if (!r.isValidInt || r.abs() > BigInt.from(maxMinor)) {
      throw const ValidationError('amount.tooLarge', 'مبلغ بیش از حد بزرگ است.');
    }
    return r.toInt();
  }

  /// Upper bound for stored minor units (well inside SQLite's 64-bit range,
  /// leaving head-room for SUM aggregates).
  static const int maxMinor = 1000000000000000; // 10^15

  BigInt _upscale(int target) =>
      unscaled * BigInt.from(10).pow(target - scale);

  static BigInt _divRound(BigInt n, BigInt d, RoundingMode mode) {
    if (d.isNegative) {
      n = -n;
      d = -d;
    }
    final q = n ~/ d; // truncates toward zero
    final r = n.remainder(d);
    if (r == BigInt.zero) return q;
    final sign = n.isNegative ? -BigInt.one : BigInt.one;
    switch (mode) {
      case RoundingMode.down:
        return q;
      case RoundingMode.up:
        return q + sign;
      case RoundingMode.halfUp:
        return (r.abs() * BigInt.two >= d) ? q + sign : q;
      case RoundingMode.halfEven:
        final twice = r.abs() * BigInt.two;
        if (twice > d) return q + sign;
        if (twice < d) return q;
        return q.isEven ? q : q + sign;
    }
  }

  @override
  int compareTo(Decimal other) {
    final s = scale > other.scale ? scale : other.scale;
    return _upscale(s).compareTo(other._upscale(s));
  }

  bool operator <(Decimal o) => compareTo(o) < 0;
  bool operator >(Decimal o) => compareTo(o) > 0;
  bool operator <=(Decimal o) => compareTo(o) <= 0;
  bool operator >=(Decimal o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) => other is Decimal && compareTo(other) == 0;

  @override
  int get hashCode {
    final s = _stripped();
    return Object.hash(s.unscaled, s.scale);
  }

  /// Plain canonical text (no grouping, `.` decimal point, trailing zeros
  /// removed). Safe for storage.
  String toCanonical() => _stripped().toFixedString();

  /// Plain text with exactly [scale] decimals.
  String toFixedString() {
    final negative = unscaled.isNegative;
    final digits = unscaled.abs().toString().padLeft(scale + 1, '0');
    final intPart = digits.substring(0, digits.length - scale);
    final frac = scale == 0 ? '' : '.${digits.substring(digits.length - scale)}';
    return '${negative ? '-' : ''}$intPart$frac';
  }

  @override
  String toString() => toCanonical();
}
