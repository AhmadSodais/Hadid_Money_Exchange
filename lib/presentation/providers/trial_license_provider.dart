import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';

/// Manages the free trial window and owner-password unlock.
class TrialLicenseProvider extends ChangeNotifier {
  TrialLicenseProvider() {
    _load();
  }

  SharedPreferences? _prefs;
  bool _ready = false;
  bool _trialEnabled = true;
  int _trialDays = AppConstants.defaultTrialDays;
  DateTime? _trialStart;
  String? _passwordHash;
  bool _unlocked = false;
  bool _forceLocked = false;

  bool get isReady => _ready;
  bool get trialEnabled => _trialEnabled;
  int get trialDays => _trialDays;
  bool get hasPassword => _passwordHash != null && _passwordHash!.isNotEmpty;
  bool get isUnlocked => _unlocked;
  bool get isForceLocked => _forceLocked;
  DateTime? get trialStart => _trialStart;

  /// True when the app must show the lock screen.
  bool get isLocked {
    if (!_ready) return false;
    if (!_trialEnabled) return false;
    if (_unlocked) return false;
    if (_forceLocked) return true;
    return daysRemaining <= 0;
  }

  int get daysRemaining {
    if (!_ready || _trialStart == null) return _trialDays;
    final elapsed = DateTime.now().difference(_trialStart!).inDays;
    final left = _trialDays - elapsed;
    return left < 0 ? 0 : left;
  }

  DateTime? get trialEndsAt {
    if (_trialStart == null) return null;
    return _trialStart!.add(Duration(days: _trialDays));
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    _trialEnabled = _prefs!.getBool(AppConstants.prefTrialEnabled) ?? true;
    _trialDays =
        _prefs!.getInt(AppConstants.prefTrialDays) ??
        AppConstants.defaultTrialDays;
    if (_trialDays < 1) _trialDays = AppConstants.defaultTrialDays;

    final startMs = _prefs!.getInt(AppConstants.prefTrialStartMs);
    if (startMs == null) {
      _trialStart = DateTime.now();
      await _prefs!.setInt(
        AppConstants.prefTrialStartMs,
        _trialStart!.millisecondsSinceEpoch,
      );
    } else {
      _trialStart = DateTime.fromMillisecondsSinceEpoch(startMs);
    }

    _passwordHash = _prefs!.getString(AppConstants.prefOwnerPasswordHash);
    _unlocked = _prefs!.getBool(AppConstants.prefLicenseUnlocked) ?? false;
    _forceLocked = _prefs!.getBool(AppConstants.prefForceLocked) ?? false;
    _ready = true;
    notifyListeners();
  }

  static String hashPassword(String password) {
    final bytes = utf8.encode(password.trim());
    return sha256.convert(bytes).toString();
  }

  Future<void> setTrialEnabled(bool value) async {
    _trialEnabled = value;
    await _prefs?.setBool(AppConstants.prefTrialEnabled, value);
    if (!value) {
      _forceLocked = false;
      await _prefs?.setBool(AppConstants.prefForceLocked, false);
    }
    notifyListeners();
  }

  Future<void> setTrialDays(int days) async {
    final clamped = days.clamp(1, 365);
    _trialDays = clamped;
    await _prefs?.setInt(AppConstants.prefTrialDays, clamped);
    notifyListeners();
  }

  /// Sets or replaces the owner password. [currentPassword] required when one exists.
  Future<bool> setPassword({
    required String newPassword,
    String? currentPassword,
  }) async {
    final next = newPassword.trim();
    if (next.length < 4) return false;

    if (hasPassword) {
      if (currentPassword == null ||
          hashPassword(currentPassword) != _passwordHash) {
        return false;
      }
    }

    _passwordHash = hashPassword(next);
    await _prefs?.setString(AppConstants.prefOwnerPasswordHash, _passwordHash!);
    notifyListeners();
    return true;
  }

  /// Creates the first owner password (no current password required).
  Future<bool> createPassword(String newPassword) async {
    if (hasPassword) return false;
    final next = newPassword.trim();
    if (next.length < 4) return false;
    _passwordHash = hashPassword(next);
    await _prefs?.setString(AppConstants.prefOwnerPasswordHash, _passwordHash!);
    notifyListeners();
    return true;
  }

  Future<bool> unlockWithPassword(String password) async {
    if (!hasPassword) return false;
    if (hashPassword(password) != _passwordHash) return false;
    _unlocked = true;
    _forceLocked = false;
    await _prefs?.setBool(AppConstants.prefLicenseUnlocked, true);
    await _prefs?.setBool(AppConstants.prefForceLocked, false);
    notifyListeners();
    return true;
  }

  /// Checks the owner password without changing lock state.
  bool verifyPassword(String password) {
    if (!hasPassword) return false;
    return hashPassword(password) == _passwordHash;
  }

  /// Create password on lock screen when none exists, then unlock.
  Future<bool> bootstrapAndUnlock(String newPassword) async {
    final ok = await createPassword(newPassword);
    if (!ok) return false;
    _unlocked = true;
    _forceLocked = false;
    await _prefs?.setBool(AppConstants.prefLicenseUnlocked, true);
    await _prefs?.setBool(AppConstants.prefForceLocked, false);
    notifyListeners();
    return true;
  }

  /// Immediately shows the lock screen (owner password required).
  Future<bool> lockNow(String password) async {
    if (!_trialEnabled) return false;
    if (!hasPassword || hashPassword(password) != _passwordHash) return false;
    _unlocked = false;
    _forceLocked = true;
    await _prefs?.setBool(AppConstants.prefLicenseUnlocked, false);
    await _prefs?.setBool(AppConstants.prefForceLocked, true);
    notifyListeners();
    return true;
  }

  /// Restarts the trial clock (owner password required).
  Future<bool> restartTrial(String password) async {
    if (!hasPassword || hashPassword(password) != _passwordHash) return false;
    _trialStart = DateTime.now();
    _unlocked = false;
    _forceLocked = false;
    await _prefs?.setInt(
      AppConstants.prefTrialStartMs,
      _trialStart!.millisecondsSinceEpoch,
    );
    await _prefs?.setBool(AppConstants.prefLicenseUnlocked, false);
    await _prefs?.setBool(AppConstants.prefForceLocked, false);
    notifyListeners();
    return true;
  }
}
