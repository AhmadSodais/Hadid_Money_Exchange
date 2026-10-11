/// One identity for catalog products.
///
/// Two active products are the same catalog item when the code, the barcode,
/// or the full variant (name, brand, pack, and sheet size) matches after
/// normalization. Sheet size is part of the variant on purpose: the same
/// glass name in two dimensions is two products, and their stock must stay
/// on their own rows.
abstract final class ProductIdentity {
  /// Folds Arabic/Persian letter variants, digits, tatweel, ZWNJ, case and
  /// spacing so names typed on different keyboards compare equal.
  static String text(String? value) {
    final buffer = StringBuffer();
    for (final rune in (value ?? '').runes) {
      if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.writeCharCode(0x30 + rune - 0x06F0);
      } else if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.writeCharCode(0x30 + rune - 0x0660);
      } else if (rune == 0x064A || rune == 0x0649 || rune == 0x06CC) {
        buffer.writeCharCode(0x06CC);
      } else if (rune == 0x0643 || rune == 0x06A9) {
        buffer.writeCharCode(0x06A9);
      } else if (rune == 0x0623 ||
          rune == 0x0625 ||
          rune == 0x0622 ||
          rune == 0x0671) {
        buffer.writeCharCode(0x0627);
      } else if (rune == 0x200C || rune == 0x200D || rune == 0x0640) {
        buffer.write(' ');
      } else if ((rune >= 0x064B && rune <= 0x065F) || rune == 0x0670) {
        // Arabic harakat carry no identity.
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer
        .toString()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  /// Stable quantity text. Null and non-positive values are blank.
  /// 1.6 and 1.600 match; 1.6 and 1.605 do not, so nearby sheet sizes stay
  /// separate products and their stock is never combined.
  static String amount(Object? value) {
    final number = asNum(value);
    if (number == null || number <= 0) return '';
    final millis = (number.toDouble() * 1000).round();
    if (millis <= 0) return '';
    if (millis % 1000 == 0) return '${millis ~/ 1000}';
    final fraction = (millis % 1000)
        .toString()
        .padLeft(3, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '${millis ~/ 1000}.$fraction';
  }

  static num? asNum(Object? value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse('$value'.trim());
  }

  static String variantKey({
    String? name,
    String? brand,
    Object? unitWeight,
    String? weightUnit,
    Object? height,
    Object? width,
    Object? thickness,
  }) {
    final weight = amount(unitWeight);
    return [
      text(name),
      text(brand),
      weight,
      weight.isEmpty ? '' : text(weightUnit),
      amount(height),
      amount(width),
      amount(thickness),
    ].join('|');
  }

  static String keyOfRow(Map<String, Object?> row) => variantKey(
        name: row['name'] as String?,
        brand: row['brand'] as String?,
        unitWeight: row['unit_weight'],
        weightUnit: row['weight_unit'] as String?,
        height: row['standard_height'],
        width: row['standard_width'],
        thickness: row['thickness'],
      );
}
