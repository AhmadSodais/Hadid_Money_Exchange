import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Minimum digit width for invoice numbers (`001`, `002`, …).
const int kInvoiceNumberWidth = 3;

/// Formats [n] as a zero-padded invoice number string.
String formatInvoiceNumber(int n) =>
    n.toString().padLeft(kInvoiceNumberWidth, '0');

/// Parses a stored invoice number into an integer, or `null` if not sequential.
int? parseInvoiceNumber(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  // Accept plain integers, including zero-padded (`001`) and legacy unpadded (`1`).
  if (!RegExp(r'^\d{1,10}$').hasMatch(s)) return null;
  final n = int.tryParse(s);
  if (n == null || n < 1) return null;
  return n;
}

/// Next invoice number as a zero-padded ascending string: `"001"`, `"002"`, …
Future<String> nextSequentialInvoiceNumber(
  DatabaseExecutor db, {
  required String table,
  String column = 'invoice_number',
}) async {
  final rows = await db.query(table, columns: [column]);
  var max = 0;
  for (final row in rows) {
    final n = parseInvoiceNumber('${row[column] ?? ''}');
    if (n != null && n > max) max = n;
  }
  return formatInvoiceNumber(max + 1);
}
