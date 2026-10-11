import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../invoice_numbers.dart';

/// Renumbers sales and purchase invoice numbers to `001`, `002`, `003`, …
abstract final class MigrationV18 {
  static Future<void> up(Database db) async {
    await _renumber(db, 'orders');
    await _renumber(db, 'purchases');
  }

  static Future<void> _renumber(Database db, String table) async {
    final rows = await db.query(
      table,
      columns: ['id'],
      orderBy: 'created_at ASC, id ASC',
    );
    if (rows.isEmpty) return;

    // Two-phase update avoids UNIQUE collisions while rewriting.
    for (final row in rows) {
      final id = row['id'] as int;
      await db.update(
        table,
        {'invoice_number': '__rn_$id'},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    var next = 1;
    for (final row in rows) {
      final id = row['id'] as int;
      await db.update(
        table,
        {'invoice_number': formatInvoiceNumber(next)},
        where: 'id = ?',
        whereArgs: [id],
      );
      next++;
    }
  }
}
