/// Application-wide constants. Financial configuration (backdating window,
/// negative-cash policy, backups, currencies) lives in the database
/// (`application_settings`, `currencies`) — not here.
abstract final class AppConstants {
  static const String appName = 'صرافی حدید';
  static const String appNameLatin = 'Hadid Money Exchange';
  static const String appVersion = '1.0.1';

  /// Build number; with [appVersion] this must stay aligned with
  /// `version: <appVersion>+<appBuildNumber>` in `pubspec.yaml`. The updater
  /// compares the manifest `shortVersion` against this build number.
  static const int appBuildNumber = 2;

  /// Update manifest (the release gate). Users are offered an update only
  /// when this file on the repo's `main` branch lists a `shortVersion`
  /// higher than [appBuildNumber]; pushing code alone publishes nothing.
  static const String updateManifestUrl =
      'https://raw.githubusercontent.com/AhmadSodais/Hadid_Money_Exchange/main/app-archive.json';

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
