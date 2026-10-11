import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../invoice_numbers.dart';

/// Pads existing sequential invoice numbers to `001`, `002`, … format.
///
/// Safe to run after v18 (which may have written unpadded `1`, `2`, …).
abstract final class MigrationV19 {
  static Future<void> up(Database db) async {
    await _pad(db, 'orders');
    await _pad(db, 'purchases');
  }

  static Future<void> _pad(Database db, String table) async {
    final rows = await db.query(table, columns: ['id', 'invoice_number']);
    if (rows.isEmpty) return;

    final updates = <({int id, String next})>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final raw = '${row['invoice_number'] ?? ''}';
      final n = parseInvoiceNumber(raw);
      if (n == null) continue;
      final formatted = formatInvoiceNumber(n);
      if (formatted == raw.trim()) continue;
      updates.add((id: id, next: formatted));
    }
    if (updates.isEmpty) return;

    // Temp values first to avoid UNIQUE collisions (e.g. `1` → `001` while `001` exists).
    for (final u in updates) {
      await db.update(
        table,
        {'invoice_number': '__pad_${u.id}'},
        where: 'id = ?',
        whereArgs: [u.id],
      );
    }
    for (final u in updates) {
      await db.update(
        table,
        {'invoice_number': u.next},
        where: 'id = ?',
        whereArgs: [u.id],
      );
    }
  }
}
