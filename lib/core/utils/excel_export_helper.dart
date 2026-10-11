import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/data_transfer.dart';
import '../widgets/gf_toast.dart';

/// Shared Excel export picker used by Settings and list-page Export buttons.
abstract final class ExcelExportHelper {
  static String stamp() {
    return DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
  }

  static Future<void> pickAndExport(BuildContext context) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'settings.chooseSaveLocation'.tr(),
      fileName: 'glassflow_export_${stamp()}.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      lockParentWindow: true,
    );
    if (path == null || path.isEmpty) return;
    try {
      final file = await DataTransfer.exportExcel(path);
      if (!context.mounted) return;
      GfToast.success(
        context,
        'settings.exportComplete'.tr(namedArgs: {'path': file.path}),
      );
    } catch (e) {
      if (!context.mounted) return;
      GfToast.error(context, e.toString());
    }
  }
}
