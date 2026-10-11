import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/security/app_biometric.dart';
import '../../core/security/app_lock_crypto.dart';

enum AppLockMethod { passcode, pattern }

enum AppLockBiometricUpdate { on, off, canceled, notReady, unavailable }

class AppLockProvider extends ChangeNotifier {
  AppLockProvider(this._prefs, {AppBiometric? biometric})
    : _biometric = biometric ?? AppBiometric() {
    _read();
    _sessionUnlocked = !_enabled;
    unawaited(refreshHardware());
  }

  final SharedPreferences _prefs;
  final AppBiometric _biometric;

  bool _enabled = false;
  AppLockMethod _method = AppLockMethod.passcode;
  int _length = 0;
  String? _salt;
  String? _hash;
  String? _recoverySalt;
  String? _recoveryHash;
  bool _biometricEnabled = false;
  bool _sessionUnlocked = true;
  bool _recoveryAccepted = false;
  bool _busy = false;
  int _failures = 0;
  DateTime? _cooldownUntil;
  bool _hardwareReady = false;
  bool _fingerprint = false;
  bool _face = false;
  bool _disposed = false;

  bool get isEnabled => _enabled;
  bool get isLocked => _enabled && !_sessionUnlocked;
  bool get isBusy => _busy;
  AppLockMethod get method => _method;
  int get secretLength => _length;
  bool get biometricEnabled =>
      _biometricEnabled && _enabled && hasBiometricHardware;
  bool get hardwareReady => _hardwareReady;
  bool get hasFingerprint => _fingerprint;
  bool get hasFace => _face;
  bool get hasBiometricHardware => _hardwareReady && (_fingerprint || _face);

  bool get isCoolingDown =>
      _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Locks again after the app is closed, minimized, or otherwise left.
  void lock() {
    if (!_enabled || !_sessionUnlocked) return;
    _sessionUnlocked = false;
    _recoveryAccepted = false;
    _failures = 0;
    _cooldownUntil = null;
    notifyListeners();
  }

  Future<void> refreshHardware() async {
    for (var attempt = 0; attempt < 12; attempt++) {
      if (_disposed) return;
      final hardware = await _biometric.detect();
      if (_disposed) return;
      if (hardware.ready) {
        _hardwareReady = true;
        _fingerprint = hardware.fingerprint;
        _face = hardware.face;
        if (!_disposed) notifyListeners();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (_disposed) return;
    _hardwareReady = true;
    notifyListeners();
  }

  Future<bool> unlockWithSecret(String secret) async {
    final ok = await _matchesLock(secret);
    if (!ok) return false;
    _sessionUnlocked = true;
    _recoveryAccepted = false;
    notifyListeners();
    return true;
  }

  Future<AppBiometricStatus> unlockWithBiometric(String reason) async {
    if (!biometricEnabled || _busy || isCoolingDown) {
      return AppBiometricStatus.unavailable;
    }
    final status = await _biometric.prompt(reason);
    if (status != AppBiometricStatus.success) return status;
    _failures = 0;
    _cooldownUntil = null;
    _sessionUnlocked = true;
    notifyListeners();
    return status;
  }

  /// Checks the recovery code and allows one secret reset.
  Future<bool> acceptRecovery(String code) async {
    if (_busy || isCoolingDown || !_enabled || _recoverySalt == null) {
      return false;
    }
    if (!AppLockCrypto.isValidRecovery(code)) {
      _noteFailure();
      notifyListeners();
      return false;
    }
    _busy = true;
    notifyListeners();
    var ok = false;
    try {
      final actual = await _hashSecret(
        'recovery:${AppLockCrypto.normalizeRecovery(code)}',
        _recoverySalt ?? '',
      );
      ok = AppLockCrypto.constantTimeEquals(actual, _recoveryHash ?? '');
    } finally {
      _busy = false;
    }
    if (ok) {
      _failures = 0;
      _cooldownUntil = null;
      _recoveryAccepted = true;
    } else {
      _noteFailure();
    }
    notifyListeners();
    return ok;
  }

  /// Replaces the secret after a recovery code was accepted.
  Future<bool> replaceAndUnlock({
    required AppLockMethod method,
    required String secret,
  }) async {
    if (!_recoveryAccepted || !_isAcceptable(method, secret)) return false;
    await _writeSecret(method, secret);
    _recoveryAccepted = false;
    _sessionUnlocked = true;
    _failures = 0;
    _cooldownUntil = null;
    notifyListeners();
    return true;
  }

  /// Turns the lock on and returns the recovery code to show once.
  ///
  /// [recovery] is a code the user wrote; when null one is generated.
  Future<String?> enable({
    required AppLockMethod method,
    required String secret,
    String? recovery,
  }) async {
    if (_enabled || _busy || !_isAcceptable(method, secret)) return null;
    if (recovery != null && !AppLockCrypto.isValidRecovery(recovery)) {
      return null;
    }
    _busy = true;
    notifyListeners();
    try {
      recovery ??= AppLockCrypto.newRecoveryCode();
      await _writeSecret(method, secret);
      await _writeRecovery(recovery);
      _enabled = true;
      _biometricEnabled = false;
      _sessionUnlocked = true;
      await _prefs.setBool(AppConstants.prefAppLockEnabled, true);
      await _prefs.setBool(AppConstants.prefAppLockBiometric, false);
      return recovery;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> checkSecret(String secret) => _matchesLock(secret);

  Future<bool> changeSecret({
    required String current,
    required AppLockMethod method,
    required String next,
  }) async {
    if (!_isAcceptable(method, next)) return false;
    final ok = await _matchesLock(current);
    if (!ok) return false;
    await _writeSecret(method, next);
    notifyListeners();
    return true;
  }

  /// Replaces the recovery code with [custom], or a generated one when null.
  Future<String?> regenerateRecovery(String current, {String? custom}) async {
    if (custom != null && !AppLockCrypto.isValidRecovery(custom)) return null;
    final ok = await _matchesLock(current);
    if (!ok) return null;
    final recovery = custom ?? AppLockCrypto.newRecoveryCode();
    await _writeRecovery(recovery);
    notifyListeners();
    return recovery;
  }

  Future<bool> disable(String current) async {
    final ok = await _matchesLock(current);
    if (!ok) return false;
    await _clearStored();
    _enabled = false;
    _biometricEnabled = false;
    _sessionUnlocked = true;
    _recoveryAccepted = false;
    _salt = null;
    _hash = null;
    _recoverySalt = null;
    _recoveryHash = null;
    _length = 0;
    notifyListeners();
    return true;
  }

  Future<AppLockBiometricUpdate> setBiometricEnabled(
    bool value,
    String reason,
  ) async {
    if (!_enabled || !hasBiometricHardware) {
      return AppLockBiometricUpdate.unavailable;
    }
    if (!value) {
      _biometricEnabled = false;
      await _prefs.setBool(AppConstants.prefAppLockBiometric, false);
      notifyListeners();
      return AppLockBiometricUpdate.off;
    }
    final status = await _biometric.prompt(reason);
    switch (status) {
      case AppBiometricStatus.success:
        _biometricEnabled = true;
        await _prefs.setBool(AppConstants.prefAppLockBiometric, true);
        notifyListeners();
        return AppLockBiometricUpdate.on;
      case AppBiometricStatus.canceled:
        return AppLockBiometricUpdate.canceled;
      case AppBiometricStatus.notReady:
        return AppLockBiometricUpdate.notReady;
      case AppBiometricStatus.failed:
      case AppBiometricStatus.unavailable:
        return AppLockBiometricUpdate.unavailable;
    }
  }

  Future<bool> _matchesLock(String secret) async {
    if (_busy || isCoolingDown || !_enabled || _salt == null || _hash == null) {
      return false;
    }
    _busy = true;
    notifyListeners();
    var ok = false;
    try {
      final actual = await _hashSecret('lock:$secret', _salt!);
      ok = AppLockCrypto.constantTimeEquals(actual, _hash!);
    } finally {
      _busy = false;
    }
    if (ok) {
      _failures = 0;
      _cooldownUntil = null;
    } else {
      _noteFailure();
    }
    notifyListeners();
    return ok;
  }

  void _noteFailure() {
    _failures += 1;
    if (_failures >= 5) {
      _failures = 0;
      _cooldownUntil = DateTime.now().add(const Duration(seconds: 20));
    }
  }

  bool _isAcceptable(AppLockMethod method, String secret) {
    if (method == AppLockMethod.passcode) {
      return AppLockCrypto.isValidPasscode(secret);
    }
    final dots = secret.split('-').map(int.tryParse).toList();
    if (dots.any((dot) => dot == null)) return false;
    return AppLockCrypto.isValidPattern(dots.cast<int>());
  }

  Future<void> _writeSecret(AppLockMethod method, String secret) async {
    final salt = AppLockCrypto.newSalt();
    final hash = await _hashSecret('lock:$secret', salt);
    _method = method;
    _length = method == AppLockMethod.passcode
        ? secret.length
        : secret.split('-').length;
    _salt = salt;
    _hash = hash;
    await _prefs.setString(
      AppConstants.prefAppLockMethod,
      method == AppLockMethod.pattern ? 'pattern' : 'passcode',
    );
    await _prefs.setInt(AppConstants.prefAppLockLength, _length);
    await _prefs.setString(AppConstants.prefAppLockSalt, salt);
    await _prefs.setString(AppConstants.prefAppLockHash, hash);
  }

  Future<void> _writeRecovery(String recovery) async {
    final salt = AppLockCrypto.newSalt();
    final hash = await _hashSecret(
      'recovery:${AppLockCrypto.normalizeRecovery(recovery)}',
      salt,
    );
    _recoverySalt = salt;
    _recoveryHash = hash;
    await _prefs.setString(AppConstants.prefAppLockRecoverySalt, salt);
    await _prefs.setString(AppConstants.prefAppLockRecoveryHash, hash);
  }

  Future<void> _clearStored() async {
    await _prefs.remove(AppConstants.prefAppLockEnabled);
    await _prefs.remove(AppConstants.prefAppLockMethod);
    await _prefs.remove(AppConstants.prefAppLockLength);
    await _prefs.remove(AppConstants.prefAppLockSalt);
    await _prefs.remove(AppConstants.prefAppLockHash);
    await _prefs.remove(AppConstants.prefAppLockRecoverySalt);
    await _prefs.remove(AppConstants.prefAppLockRecoveryHash);
    await _prefs.remove(AppConstants.prefAppLockBiometric);
  }

  void _read() {
    _enabled = _prefs.getBool(AppConstants.prefAppLockEnabled) ?? false;
    _method = _prefs.getString(AppConstants.prefAppLockMethod) == 'pattern'
        ? AppLockMethod.pattern
        : AppLockMethod.passcode;
    _length = _prefs.getInt(AppConstants.prefAppLockLength) ?? 0;
    _salt = _prefs.getString(AppConstants.prefAppLockSalt);
    _hash = _prefs.getString(AppConstants.prefAppLockHash);
    _recoverySalt = _prefs.getString(AppConstants.prefAppLockRecoverySalt);
    _recoveryHash = _prefs.getString(AppConstants.prefAppLockRecoveryHash);
    _biometricEnabled = _prefs.getBool(AppConstants.prefAppLockBiometric) ?? false;
    if (_enabled &&
        (_salt == null ||
            _hash == null ||
            _recoverySalt == null ||
            _recoveryHash == null ||
            _length < 4)) {
      _enabled = false;
    }
  }
}

Future<String> _hashSecret(String secret, String salt) {
  return compute(_hashSecretIsolate, <String>[secret, salt]);
}

String _hashSecretIsolate(List<String> args) {
  return AppLockCrypto.hash(args[0], args[1]);
}
