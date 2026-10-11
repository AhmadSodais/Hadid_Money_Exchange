import 'package:easy_localization/easy_localization.dart';

/// Localized labels for auth roles/users stored with English seed values in DB.
abstract final class AuthLabels {
  /// Display name for a role (e.g. seeded «Administrator» → Persian when locale is fa).
  static String roleName(String? storedName) {
    if (storedName == null || storedName.trim().isEmpty) {
      return 'auth.role'.tr();
    }
    final key = _roleNameKey(storedName.trim());
    return key?.tr() ?? storedName;
  }

  /// Optional role description from DB.
  static String? roleDescription(String? stored) {
    if (stored == null || stored.trim().isEmpty) return null;
    final key = _roleDescriptionKey(stored.trim());
    return key?.tr() ?? stored;
  }

  /// Display name for users (seeded «Administrator» etc.).
  static String userDisplayName(String stored) {
    final key = _userDisplayNameKey(stored.trim());
    return key?.tr() ?? stored;
  }

  /// Permission key → localized label (handles dotted keys).
  static String permission(String permissionKey) {
    final translationKey = switch (permissionKey) {
      'purchases.edit' => 'auth.permissions.purchasesEdit',
      'roles.manage' => 'auth.permissions.rolesManage',
      'reports.view' => 'auth.permissions.reportsView',
      'tradingCompanies' => 'auth.permissions.tradingCompanies',
      'syncCenter' => 'auth.permissions.syncCenter',
      _ => 'auth.permissions.$permissionKey',
    };
    return translationKey.tr();
  }

  static String? _roleNameKey(String name) {
    return switch (name.toLowerCase()) {
      'administrator' => 'auth.roleNames.administrator',
      _ => null,
    };
  }

  static String? _roleDescriptionKey(String description) {
    return switch (description) {
      'Full access to all sections' =>
        'auth.roleDescriptions.administratorFull',
      _ => null,
    };
  }

  static String? _userDisplayNameKey(String name) {
    return switch (name.toLowerCase()) {
      'administrator' => 'auth.defaultDisplayNames.administrator',
      _ => null,
    };
  }
}
