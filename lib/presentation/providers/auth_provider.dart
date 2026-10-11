import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/service_locator.dart';
import '../../core/errors/result.dart';
import '../../core/security/app_permissions.dart';
import '../../data/models/auth_models.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._prefs, {AuthRepository? auth})
      : _auth = auth ?? ServiceLocator.instance.auth {
    _restore();
  }

  final SharedPreferences _prefs;
  final AuthRepository _auth;

  bool _ready = false;
  bool _authEnabled = false;
  AppUserModel? _user;
  String? _error;

  bool get isReady => _ready;

  /// When false, the app is open without login (full access).
  bool get isAuthEnabled => _authEnabled;
  bool get isAuthRequired => _authEnabled;

  bool get isAuthenticated => !_authEnabled || _user != null;
  AppUserModel? get currentUser => _user;
  String? get error => _error;

  bool hasPermission(String key) {
    if (!_authEnabled) return true;
    final u = _user;
    if (u == null) return false;
    if (u.hasPermission(key)) return true;
    // Legacy: customers used to live under trading companies.
    if (key == AppPermissions.customers &&
        u.hasPermission(AppPermissions.tradingCompanies)) {
      return true;
    }
    return false;
  }

  /// Purchase prices, cost fields, and purchase-related monetary data.
  bool get canViewPurchaseData => hasPermission(AppPermissions.purchases);

  bool canAccessRoute(String route) {
    if (!_authEnabled) return true;
    final required = AppPermissions.forRoute(route);
    if (required == null) return true;
    return hasPermission(required);
  }

  Future<void> _restore() async {
    try {
      _authEnabled = await _auth.isAuthEnabled();
    } catch (_) {
      _authEnabled = false;
    }

    if (_authEnabled) {
      final id = _prefs.getInt(AppConstants.prefAuthUserId);
      if (id != null) {
        final result = await _auth.getUserById(id);
        result.when(
          success: (u) {
            if (u != null && u.isActive) {
              _user = u;
            } else {
              _prefs.remove(AppConstants.prefAuthUserId);
            }
          },
          failure: (_) {
            _prefs.remove(AppConstants.prefAuthUserId);
          },
        );
      }
    } else {
      _user = null;
      await _prefs.remove(AppConstants.prefAuthUserId);
    }

    _ready = true;
    notifyListeners();
  }

  Future<void> refreshAuthEnabled() async {
    _authEnabled = await _auth.isAuthEnabled();
    if (!_authEnabled) {
      _user = null;
      await _prefs.remove(AppConstants.prefAuthUserId);
    }
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _error = null;
    notifyListeners();
    if (!_authEnabled) {
      _error = 'auth.notEnabled';
      notifyListeners();
      return false;
    }
    final result = await _auth.login(username, password);
    if (result is FailureResult<AppUserModel?>) {
      _error = result.failure.message;
      notifyListeners();
      return false;
    }
    final u = (result as Success<AppUserModel?>).value;
    if (u == null) {
      _error = 'auth.invalidCredentials';
      notifyListeners();
      return false;
    }
    _user = u;
    await _prefs.setInt(AppConstants.prefAuthUserId, u.id);
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    _user = null;
    await _prefs.remove(AppConstants.prefAuthUserId);
    notifyListeners();
  }

  /// Enable login & roles: creates the first admin and stores a recovery code.
  Future<bool> enableAuth({
    required String username,
    required String password,
    required String displayName,
    required String recoveryCode,
    int? roleId,
  }) async {
    _error = null;
    final result = await _auth.enableAuth(
      username: username,
      password: password,
      displayName: displayName,
      recoveryCode: recoveryCode,
      roleId: roleId,
    );
    return _applyEnabledUser(result);
  }

  /// Enable login by selecting an existing user.
  Future<bool> enableAuthForExistingUser({
    required int userId,
    required String recoveryCode,
    int? roleId,
    String? newPassword,
  }) async {
    _error = null;
    final result = await _auth.enableAuthForExistingUser(
      userId: userId,
      recoveryCode: recoveryCode,
      roleId: roleId,
      newPassword: newPassword,
    );
    return _applyEnabledUser(result);
  }

  Future<bool> _applyEnabledUser(Result<AppUserModel> result) async {
    if (result is FailureResult<AppUserModel>) {
      _error = result.failure.message;
      notifyListeners();
      return false;
    }
    final u = (result as Success<AppUserModel>).value;
    _authEnabled = true;
    _user = u;
    await _prefs.setInt(AppConstants.prefAuthUserId, u.id);
    notifyListeners();
    return true;
  }

  Future<bool> disableAuth() async {
    _error = null;
    final result = await _auth.disableAuth();
    if (result is FailureResult<void>) {
      _error = result.failure.message;
      notifyListeners();
      return false;
    }
    _authEnabled = false;
    _user = null;
    await _prefs.remove(AppConstants.prefAuthUserId);
    notifyListeners();
    return true;
  }

  Future<bool> resetPasswordWithRecovery({
    required String recoveryCode,
    required String newPassword,
    String? username,
  }) async {
    _error = null;
    final result = await _auth.resetPasswordWithRecovery(
      recoveryCode: recoveryCode,
      newPassword: newPassword,
      username: username,
    );
    if (result is FailureResult<void>) {
      _error = result.failure.message;
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  /// Refresh permissions after role changes.
  Future<void> refreshSession() async {
    final id = _user?.id;
    if (id == null) return;
    final result = await _auth.getUserById(id);
    result.when(
      success: (u) {
        if (u == null || !u.isActive) {
          logout();
        } else {
          _user = u;
          notifyListeners();
        }
      },
      failure: (_) {},
    );
  }
}
