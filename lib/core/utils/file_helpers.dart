import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../errors/app_failure.dart';

/// File helpers for product images and backups.
abstract final class FileHelpers {
  static const _uuid = Uuid();

  static void validateImageFile(File file) {
    final ext = p.extension(file.path).toLowerCase().replaceFirst('.', '');
    if (!AppConstants.allowedImageExtensions.contains(ext)) {
      throw const FileFailure('Only PNG and JPG images are allowed.');
    }
    final size = file.lengthSync();
    if (size > AppConstants.maxImageBytes) {
      throw const FileFailure('Image must be 5 MB or smaller.');
    }
  }

  static String sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[^\w\-.]+'), '_');
  }

  static Future<String> copyImageToAppStorage({
    required File source,
    required Directory imagesDir,
  }) async {
    validateImageFile(source);
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final ext = p.extension(source.path).toLowerCase();
    final destName = '${_uuid.v4()}$ext';
    final dest = File(p.join(imagesDir.path, destName));
    await source.copy(dest.path);
    return dest.path;
  }

  static Future<void> deleteIfExists(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
