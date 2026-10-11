import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ensures base currencies exist after demo-seed removal (V20).
abstract final class MigrationV22 {
  static Future<void> up(Database db) async {
    final now = DateTime.now().toIso8601String();
    const rows = [
      ('AFN', 'Afghani', '؋', 1.0, 1),
      ('USD', 'US Dollar', '\$', 1.0, 0),
      ('EUR', 'Euro', '€', 1.0, 0),
    ];

    for (final (code, name, symbol, rate, isBase) in rows) {
      final existing = await db.query(
        'currencies',
        columns: ['id'],
        where: 'code = ?',
        whereArgs: [code],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        await db.update(
          'currencies',
          {
            'is_active': 1,
            'updated_at': now,
            if (isBase == 1) 'is_base': 1,
          },
          where: 'code = ?',
          whereArgs: [code],
        );
        continue;
      }
      await db.insert('currencies', {
        'code': code,
        'name': name,
        'symbol': symbol,
        'exchange_rate': rate,
        'is_base': isBase,
        'is_active': 1,
        'updated_at': now,
      });
    }
  }
}
