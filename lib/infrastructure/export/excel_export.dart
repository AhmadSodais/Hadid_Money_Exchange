import 'package:excel/excel.dart';

/// One worksheet of a report export.
final class ExportSheet {
  const ExportSheet({required this.name, required this.headers, required this.rows, this.notes = const []});

  final String name;
  final List<String> headers;

  /// Cell text. Amounts are passed as exact decimal strings produced from
  /// integer minor units, so no floating-point value is ever written.
  final List<List<String>> rows;

  /// Lines written above the table (report title, period, currency, …).
  final List<String> notes;
}

/// Builds `.xlsx` workbooks for reports. Export is read-only: it never
/// touches the database and is not a backup or import format.
abstract final class ExcelExport {
  static List<int> build(List<ExportSheet> sheets) {
    final excel = Excel.createExcel();
    final defaultName = excel.getDefaultSheet();
    for (var i = 0; i < sheets.length; i++) {
      final s = sheets[i];
      final name = _safeName(s.name, i);
      if (i == 0 && defaultName != null) {
        excel.rename(defaultName, name);
      }
      final sheet = excel[name];
      sheet.isRTL = true;
      for (final n in s.notes) {
        sheet.appendRow([TextCellValue(n)]);
      }
      if (s.notes.isNotEmpty) sheet.appendRow([]);
      sheet.appendRow([for (final h in s.headers) TextCellValue(h)]);
      for (final r in s.rows) {
        sheet.appendRow([for (final c in r) TextCellValue(c)]);
      }
      for (var c = 0; c < s.headers.length; c++) {
        sheet.setColumnWidth(c, 22);
      }
    }
    final bytes = excel.encode();
    if (bytes == null) throw StateError('Excel encoding failed');
    return bytes;
  }

  static String _safeName(String name, int index) {
    final cleaned = name.replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
    final base = cleaned.isEmpty ? 'Sheet${index + 1}' : cleaned;
    return base.length > 31 ? base.substring(0, 31) : base;
  }
}
