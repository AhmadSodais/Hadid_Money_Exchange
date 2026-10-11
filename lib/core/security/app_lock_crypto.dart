import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Salted hashes for the app lock secret and recovery code.
abstract final class AppLockCrypto {
  static const int iterations = 10000;
  static const int keyLength = 32;

  static const int passcodeLength = 4;

  static final RegExp _passcode = RegExp('^\\d{$passcodeLength}\$');
  static bool isValidPasscode(String value) => _passcode.hasMatch(value);

  static bool isValidPattern(List<int> dots) {
    if (dots.length < 4 || dots.length > 9) return false;
    final seen = <int>{};
    for (final dot in dots) {
      if (dot < 0 || dot > 8 || !seen.add(dot)) return false;
    }
    return true;
  }

  static String patternSecret(List<int> dots) => dots.join('-');

  /// Dot that sits on the straight line between [from] and [to], if any.
  static int? patternBridge(int from, int to) {
    final fromRow = from ~/ 3;
    final fromCol = from % 3;
    final toRow = to ~/ 3;
    final toCol = to % 3;
    final dRow = toRow - fromRow;
    final dCol = toCol - fromCol;
    if (dRow.abs() % 2 != 0 || dCol.abs() % 2 != 0) return null;
    if (dRow.abs() <= 1 && dCol.abs() <= 1) return null;
    return (fromRow + dRow ~/ 2) * 3 + (fromCol + dCol ~/ 2);
  }

  static String newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Human-readable code, grouped for reading. Only the hash is stored.
  static String newRecoveryCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final chars = List.generate(
      12,
      (_) => alphabet[random.nextInt(alphabet.length)],
    );
    final raw = chars.join();
    return '${raw.substring(0, 4)}-${raw.substring(4, 8)}-${raw.substring(8, 12)}';
  }

  static const int recoveryMinLength = 6;
  static const int recoveryMaxLength = 64;

  /// Ignores spaces, dashes, underscores and letter case; Persian / Arabic
  /// digits count as 0–9. Generated codes normalize to their 12 characters.
  static String normalizeRecovery(String code) {
    final buffer = StringBuffer();
    for (final rune in code.runes) {
      if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.write(rune - 0x06F0);
      } else if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.write(rune - 0x0660);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[\s\-_]'), '')
        .toUpperCase();
  }

  static bool isValidRecovery(String code) {
    final normalized = normalizeRecovery(code);
    return normalized.length >= recoveryMinLength &&
        normalized.length <= recoveryMaxLength;
  }

  static String hash(String secret, String salt, {int iterationCount = iterations}) {
    final bytes = pbkdf2(
      password: utf8.encode(secret),
      salt: utf8.encode(salt),
      iterations: iterationCount,
      keyLength: keyLength,
    );
    return base64UrlEncode(bytes);
  }

  static Uint8List pbkdf2({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int keyLength,
  }) {
    if (iterations < 1 || keyLength < 1) {
      throw ArgumentError('Invalid PBKDF2 parameters');
    }
    final hmac = Hmac(sha256, password);
    const hashLen = 32;
    final blocks = (keyLength + hashLen - 1) ~/ hashLen;
    final out = Uint8List(blocks * hashLen);
    var offset = 0;
    for (var block = 1; block <= blocks; block++) {
      final blockIndex = ByteData(4)..setUint32(0, block, Endian.big);
      var u = Uint8List.fromList(
        hmac.convert([...salt, ...blockIndex.buffer.asUint8List()]).bytes,
      );
      final mixed = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < hashLen; j++) {
          mixed[j] ^= u[j];
        }
      }
      out.setRange(offset, offset + hashLen, mixed);
      offset += hashLen;
    }
    return Uint8List.sublistView(out, 0, keyLength);
  }

  static bool constantTimeEquals(String a, String b) {
    final left = utf8.encode(a);
    final right = utf8.encode(b);
    var diff = left.length ^ right.length;
    final length = left.length < right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      diff |= left[i] ^ right[i];
    }
    return diff == 0;
  }
}
