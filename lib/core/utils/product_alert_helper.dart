import '../constants/app_constants.dart';
import '../../data/models/report_models.dart';

/// Shared helpers for stock + expiry product alerts.
abstract final class ProductAlertHelper {
  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Approximate day count for SQL / alert window comparisons.
  static int valueToDays(int value, String? unit) {
    final v = value < 1 ? 1 : value;
    return switch ((unit ?? 'month').trim().toLowerCase()) {
      'day' => v,
      'week' => v * 7,
      'month' => v * 30,
      'year' => v * 365,
      _ => AppConstants.expiryAlertDays,
    };
  }

  /// SQL expression: per-product alert lead time in days.
  static const String sqlAlertDaysExpr = '''
CASE LOWER(COALESCE(p.expiry_alert_unit, 'month'))
  WHEN 'day' THEN COALESCE(p.expiry_alert_value, 1)
  WHEN 'week' THEN COALESCE(p.expiry_alert_value, 1) * 7
  WHEN 'month' THEN COALESCE(p.expiry_alert_value, 1) * 30
  WHEN 'year' THEN COALESCE(p.expiry_alert_value, 1) * 365
  ELSE ${AppConstants.expiryAlertDays}
END
''';

  /// True when expiration is within the product's alert window (or past).
  static String sqlExpiringSoonPredicate() => '''
p.expiration_date IS NOT NULL
AND TRIM(p.expiration_date) != ''
AND date(p.expiration_date) <= date('now', '+' || ($sqlAlertDaysExpr) || ' days')
''';

  static int alertDaysFromRow(Map<String, Object?> r) {
    final value = (r['expiry_alert_value'] as num?)?.toInt() ?? 1;
    final unit = r['expiry_alert_unit'] as String?;
    return valueToDays(value, unit);
  }

  static String? expiryStatus(
    DateTime? expirationDate, {
    DateTime? now,
    int? alertDays,
  }) {
    if (expirationDate == null) return null;
    final today = _dayOnly(now ?? DateTime.now());
    final exp = _dayOnly(expirationDate);
    if (exp.isBefore(today)) return 'expired';
    final days = alertDays ?? AppConstants.expiryAlertDays;
    final soon = today.add(Duration(days: days < 1 ? 1 : days));
    if (!exp.isAfter(soon)) return 'expiringSoon';
    return null;
  }

  static String? stockStatus(double currentStock, double minimumStock) {
    if (currentStock <= 0) return 'outOfStock';
    if (currentStock <= minimumStock) return 'lowStock';
    return null;
  }

  /// Builds alerts for a product row. May return 0–2 alerts (stock + expiry).
  static List<InventoryAlert> fromProductRow(Map<String, Object?> r) {
    final productId = r['id'] as int;
    final name = r['name'] as String;
    final sku = r['sku'] as String?;
    final barcode = r['barcode'] as String?;
    final brand = r['brand'] as String?;
    final categoryName = r['category_name'] as String?;
    final current = (r['current_stock'] as num?)?.toDouble() ?? 0;
    final minimum = (r['minimum_stock_alert'] as num?)?.toDouble() ?? 0;
    DateTime? expiration;
    final rawExp = r['expiration_date'];
    if (rawExp != null && rawExp.toString().trim().isNotEmpty) {
      expiration = DateTime.tryParse(rawExp.toString());
    }

    final alerts = <InventoryAlert>[];
    final stock = stockStatus(current, minimum);
    if (stock != null) {
      alerts.add(
        InventoryAlert(
          productId: productId,
          name: name,
          sku: sku,
          barcode: barcode,
          brand: brand,
          categoryName: categoryName,
          currentStock: current,
          minimumStock: minimum,
          expirationDate: expiration,
          status: stock,
        ),
      );
    }
    final exp = expiryStatus(
      expiration,
      alertDays: alertDaysFromRow(r),
    );
    if (exp != null) {
      alerts.add(
        InventoryAlert(
          productId: productId,
          name: name,
          sku: sku,
          barcode: barcode,
          brand: brand,
          categoryName: categoryName,
          currentStock: current,
          minimumStock: minimum,
          expirationDate: expiration,
          status: exp,
        ),
      );
    }
    return alerts;
  }

  /// Sort priority: expired > outOfStock > expiringSoon > lowStock.
  static int statusPriority(String status) => switch (status) {
        'expired' => 0,
        'outOfStock' || 'Out of Stock' => 1,
        'expiringSoon' => 2,
        'lowStock' || 'Low Stock' => 3,
        _ => 9,
      };
}
