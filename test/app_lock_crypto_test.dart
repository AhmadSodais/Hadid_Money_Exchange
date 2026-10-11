import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_general/core/security/app_lock_crypto.dart';

void main() {
  test('PBKDF2-HMAC-SHA256 matches RFC 6070', () {
    String hex(Uint8List bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final once = AppLockCrypto.pbkdf2(
      password: utf8.encode('password'),
      salt: utf8.encode('salt'),
      iterations: 1,
      keyLength: 32,
    );
    expect(
      hex(once),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );

    final twice = AppLockCrypto.pbkdf2(
      password: utf8.encode('password'),
      salt: utf8.encode('salt'),
      iterations: 2,
      keyLength: 32,
    );
    expect(
      hex(twice),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
  });

  test('passcode must be exactly 4 digits', () {
    expect(AppLockCrypto.isValidPasscode('1234'), isTrue);
    expect(AppLockCrypto.isValidPasscode('123'), isFalse);
    expect(AppLockCrypto.isValidPasscode('12345'), isFalse);
    expect(AppLockCrypto.isValidPasscode('12a4'), isFalse);
  });

  test('pattern bridge fills the dot on the line', () {
    expect(AppLockCrypto.patternBridge(0, 2), 1);
    expect(AppLockCrypto.patternBridge(0, 8), 4);
    expect(AppLockCrypto.patternBridge(0, 5), isNull);
    expect(AppLockCrypto.patternBridge(0, 4), isNull);
  });

  test('recovery code normalizes dashes and case', () {
    final code = AppLockCrypto.newRecoveryCode();
    expect(AppLockCrypto.isValidRecovery(code), isTrue);
    expect(
      AppLockCrypto.normalizeRecovery(' ${code.toLowerCase()} '),
      AppLockCrypto.normalizeRecovery(code),
    );
  });

  test('own recovery codes ignore spaces, dashes and case', () {
    expect(
      AppLockCrypto.normalizeRecovery('My Secret-۹۹'),
      AppLockCrypto.normalizeRecovery('mysecret99'),
    );
    expect(AppLockCrypto.isValidRecovery('abc 12'), isFalse);
    expect(AppLockCrypto.isValidRecovery('abc123'), isTrue);
    expect(AppLockCrypto.normalizeRecovery('ABCD-EFGH-JKLM'), 'ABCDEFGHJKLM');
  });

  test('constant-time compare rejects a different hash', () {
    const salt = 'salt';
    final hash = AppLockCrypto.hash('lock:1234', salt, iterationCount: 1);
    expect(
      AppLockCrypto.constantTimeEquals(
        AppLockCrypto.hash('lock:1234', salt, iterationCount: 1),
        hash,
      ),
      isTrue,
    );
    expect(
      AppLockCrypto.constantTimeEquals(
        AppLockCrypto.hash('lock:1235', salt, iterationCount: 1),
        hash,
      ),
      isFalse,
    );
  });
}
