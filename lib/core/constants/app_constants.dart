/// Application-wide constants. Financial configuration (backdating window,
/// negative-cash policy, backups, currencies) lives in the database
/// (`application_settings`, `currencies`) — not here.
abstract final class AppConstants {
  static const String appName = 'صرافی حدید';
  static const String appNameLatin = 'Hadid Money Exchange';
  static const String appVersion = '1.0.0';

  static const String dataFolderName = 'data';
  static const String backupFolderName = 'backups';
  static const String excelExportFolderName = 'excel_exports';

  /// UI-only preferences (SharedPreferences). Nothing financial is stored here.
  static const String prefSidebarCollapsed = 'sidebar_collapsed';
  static const String prefReducedMotion = 'reduced_motion';
  static const String prefThemeMode = 'theme_mode'; // light | dark
  static const String prefDarkPalette = 'dark_palette'; // dark | hadid
  static const String prefDrawerId = 'selected_drawer_id';

  /// Calendar system: solar (default) | gregorian | lunar.
  static const String prefCalendarType = 'calendar_type';

  /// App lock (passcode or pattern). Values are salted PBKDF2 hashes.
  static const String prefAppLockEnabled = 'app_lock_enabled';
  static const String prefAppLockMethod = 'app_lock_method';
  static const String prefAppLockLength = 'app_lock_length';
  static const String prefAppLockSalt = 'app_lock_salt';
  static const String prefAppLockHash = 'app_lock_hash';
  static const String prefAppLockRecoverySalt = 'app_lock_recovery_salt';
  static const String prefAppLockRecoveryHash = 'app_lock_recovery_hash';
  static const String prefAppLockBiometric = 'app_lock_biometric';

  /// Idle time after which the app lock engages automatically.
  static const Duration idleLockAfter = Duration(minutes: 10);
}
