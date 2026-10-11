import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/gf_button.dart';
import '../../core/widgets/gf_toast.dart';
import '../../infrastructure/export/excel_export.dart';

/// Asks for a destination and writes the workbook. Success is reported only
/// after the file has been written.
Future<void> exportSheets(BuildContext context, String fileName, List<ExportSheet> sheets) async {
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'ذخیره فایل اکسل',
      fileName: fileName.endsWith('.xlsx') ? fileName : '$fileName.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (path == null) return;
    final target = path.toLowerCase().endsWith('.xlsx') ? path : '$path.xlsx';
    await File(target).writeAsBytes(ExcelExport.build(sheets), flush: true);
    if (context.mounted) GfToast.success(context, 'فایل اکسل ذخیره شد: $target');
  } catch (e) {
    if (context.mounted) GfToast.error(context, 'ذخیره فایل اکسل ناکام شد: $e');
  }
}

class ExportButton extends StatelessWidget {
  const ExportButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GfSecondaryButton(
      label: 'خروجی اکسل',
      icon: Icons.table_view_outlined,
      onPressed: onPressed,
    );
  }
}
