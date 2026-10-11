/// Application-wide constants.
abstract final class AppConstants {
  static const String appName = 'Hadid';
  static const String appVersion = '1.0.0';
  static const String databaseName = 'fitness_supp_store.db';
  static const int databaseVersion = 30;

  /// When false, print actions (Save & Print, row Print menus) are hidden.
  static const bool enablePrint = false;

  /// When false, Generate PDF / save-PDF actions are hidden.
  static const bool enablePdfExport = false;

  /// When false, share (text / company profile) actions are hidden.
  static const bool enableShare = false;

  /// Minimum remnant side length in meters. Below this, leftover is waste.
  static const double minRemnantSideM = 0.3;

  /// Days before expiration that trigger an "expiring soon" alert.
  static const int expiryAlertDays = 30;

  static const int defaultPageSize = 20;
  static const int maxImageBytes = 5 * 1024 * 1024;
  static const List<String> allowedImageExtensions = ['png', 'jpg', 'jpeg'];

  static const String defaultCurrencyCode = 'AFN';
  static const String walkInCustomerName = 'Walk-in Customer';

  static const String prefSidebarCollapsed = 'sidebar_collapsed';
  static const String prefReducedMotion = 'reduced_motion';
  static const String prefBaseCurrency = 'base_currency';
  static const String prefThemeMode = 'theme_mode'; // light | dark
  static const String prefDarkPalette = 'dark_palette'; // dark | hadid
  /// When false, background sync and Sync Center are disabled.
  static const String prefOnlineEnabled = 'online_enabled';

  /// When true, outbound sales cannot exceed available stock.
  static const String prefLimitToStock = 'limit_to_stock';

  /// Business type: general | supplement | clothing.
  static const String prefStoreType = 'store_type';

  /// Calendar system: gregorian | solar | lunar. Default gregorian.
  static const String prefCalendarType = 'calendar_type';

  /// Logged-in app user id (session persistence).
  static const String prefAuthUserId = 'auth_user_id';

  /// When true, local username/password login is required.
  static const String prefAuthEnabled = 'auth_enabled';

  /// App lock (passcode or pattern) shown after the app is closed or minimized.
  static const String prefAppLockEnabled = 'app_lock_enabled';
  static const String prefAppLockMethod = 'app_lock_method';
  static const String prefAppLockLength = 'app_lock_length';
  static const String prefAppLockSalt = 'app_lock_salt';
  static const String prefAppLockHash = 'app_lock_hash';
  static const String prefAppLockRecoverySalt = 'app_lock_recovery_salt';
  static const String prefAppLockRecoveryHash = 'app_lock_recovery_hash';
  static const String prefAppLockBiometric = 'app_lock_biometric';
  static const String settingAuthEnabled = 'auth_enabled';
  static const String settingAuthRecoveryHash = 'auth_recovery_hash';

  /// Trial / owner-lock preferences.
  static const String prefTrialStartMs = 'trial_start_ms';
  static const String prefTrialDays = 'trial_days';
  static const String prefTrialEnabled = 'trial_enabled';
  static const String prefOwnerPasswordHash = 'owner_password_hash';
  static const String prefLicenseUnlocked = 'license_unlocked';
  static const String prefForceLocked = 'force_locked';
  static const int defaultTrialDays = 5;

  /// Default remote server database URL (structured data only — no files/images).
  static const String firebaseDatabaseUrl =
      'https://fitness-supp-store-default-rtdb.firebaseio.com';
  static const String firebaseRoot = 'store';

  /// Optional default Web API key (leave empty — set in Settings).
  static const String firebaseWebApiKey = '';

  /// Generic placeholder shown in the Server Link field (avoids vendor branding).
  static const String serverLinkHint =
      'https://your-project-default-rtdb.firebaseio.com/store';

  /// Quiet period after a save before uploading, so rapid edits go together.
  static const Duration syncDebounce = Duration(seconds: 3);
}
