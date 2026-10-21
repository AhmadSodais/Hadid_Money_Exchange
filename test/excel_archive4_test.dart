import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the git-pinned excel 5.0.0 in pubspec.yaml (the first excel line
/// on archive ^4, required by desktop_updater): the app's xlsx
/// encode/decode round-trip must keep working on archive 4.
void main() {
  test('excel encode/decode round-trip works with archive 4', () {
    final book = Excel.createExcel();
    final sheet = book['Sheet1'];
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('hadid');
    sheet.cell(CellIndex.indexByString('B2')).value = IntCellValue(42);

    final bytes = book.encode();
    expect(bytes, isNotNull);

    final decoded = Excel.decodeBytes(bytes!);
    final a1 = decoded['Sheet1'].cell(CellIndex.indexByString('A1')).value;
    final b2 = decoded['Sheet1'].cell(CellIndex.indexByString('B2')).value;
    expect(a1, isA<TextCellValue>());
    // excel 5 wraps text in a rich-text span; compare its plain text.
    expect((a1! as TextCellValue).value.toString(), contains('hadid'));
    expect(b2, isA<IntCellValue>());
    expect((b2! as IntCellValue).value, 42);
  });
}
