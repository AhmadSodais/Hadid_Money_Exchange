import 'dart:typed_data';

/// Cleans a snapshot before it is queued for the server.
///
/// - Images, files, PDFs and any binary content are removed. For images only
///   the file name is kept (`imageName`) as a reference.
/// - Values are reduced to plain JSON types (dates become ISO-8601 strings),
///   so the data reads back exactly the same way when it is downloaded.
abstract final class SyncPayloadSanitizer {
  static const _blockedKeys = {
    'image',
    'imagebytes',
    'image_bytes',
    'bytes',
    'file',
    'filebytes',
    'file_bytes',
    'pdf',
    'pdfbytes',
    'pdf_bytes',
    'attachment',
    'attachments',
    'video',
    'document',
    'base64',
    'logobytes',
    'logo_bytes',
  };

  static const _imagePathKeys = {
    'image_path',
    'imagePath',
    'logo_path',
    'logoPath',
    'localPath',
    'local_path',
  };

  static Map<String, dynamic> sanitize(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      if (_blockedKeys.contains(key.toLowerCase())) return;
      if (_imagePathKeys.contains(key)) return;
      final clean = _clean(value);
      if (clean is _Dropped) return;
      out[key] = clean;
    });

    if (raw.keys.any(_imagePathKeys.contains)) {
      out['imageName'] = null;
      for (final key in _imagePathKeys) {
        final path = raw[key];
        if (path is String && path.trim().isNotEmpty) {
          out['imageName'] = path.replaceAll('\\', '/').split('/').last;
          break;
        }
      }
    }
    return out;
  }

  static Object? _clean(Object? value) {
    if (value == null || value is bool || value is num) return value;
    if (value is String) {
      return _looksLikeBase64Blob(value) ? const _Dropped() : value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is TypedData) return const _Dropped();
    if (value is Map) {
      return sanitize({
        for (final e in value.entries) '${e.key}': e.value,
      });
    }
    if (value is List) {
      return [
        for (final item in value)
          if (_clean(item) case final c when c is! _Dropped) c,
      ];
    }
    return '$value';
  }

  static bool _looksLikeBase64Blob(String value) {
    if (value.length < 256) return false;
    if (value.startsWith('data:image') ||
        value.startsWith('data:application')) {
      return true;
    }
    final compact = value.replaceAll(RegExp(r'\s'), '');
    return compact.length > 512 &&
        RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(compact);
  }
}

class _Dropped {
  const _Dropped();
}
