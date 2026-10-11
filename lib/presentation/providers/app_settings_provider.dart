import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_calendar.dart';

/// UI preferences only (theme, sidebar, calendar). Financial settings are
/// stored in the database and changed through `CatalogService`.
class AppSettingsProvider extends ChangeNotifier {
  AppSettingsProvider(this._prefs) {
    AppCalendar.apply(calendarType);
  }

  final SharedPreferences _prefs;

  bool get sidebarCollapsed =>
      _prefs.getBool(AppConstants.prefSidebarCollapsed) ?? false;

  bool get reducedMotion =>
      _prefs.getBool(AppConstants.prefReducedMotion) ?? false;

  /// Calendar: solar (default for Afghanistan) | gregorian | lunar.
  AppCalendarType get calendarType {
    final raw = _prefs.getString(AppConstants.prefCalendarType);
    return raw == null ? AppCalendarType.solar : AppCalendarType.parse(raw);
  }

  String get themeModeKey =>
      _prefs.getString(AppConstants.prefThemeMode) ?? 'light';

  ThemeMode get themeMode =>
      themeModeKey == 'dark' ? ThemeMode.dark : ThemeMode.light;

  bool get isLightMode => themeMode == ThemeMode.light;

  AppThemeVariant get darkVariant =>
      _prefs.getString(AppConstants.prefDarkPalette) ==
          AppThemeVariant.hadid.name
      ? AppThemeVariant.hadid
      : AppThemeVariant.dark;

  AppThemeVariant get themeVariant =>
      isLightMode ? AppThemeVariant.light : darkVariant;

  int? get selectedDrawerId => _prefs.getInt(AppConstants.prefDrawerId);

  Future<void> setSelectedDrawerId(int id) async {
    await _prefs.setInt(AppConstants.prefDrawerId, id);
    notifyListeners();
  }

  Future<void> setSidebarCollapsed(bool value) async {
    await _prefs.setBool(AppConstants.prefSidebarCollapsed, value);
    notifyListeners();
  }

  Future<void> toggleSidebar() => setSidebarCollapsed(!sidebarCollapsed);

  Future<void> setReducedMotion(bool value) async {
    await _prefs.setBool(AppConstants.prefReducedMotion, value);
    notifyListeners();
  }

  Future<void> setCalendarType(AppCalendarType type) async {
    await _prefs.setString(AppConstants.prefCalendarType, type.storageKey);
    AppCalendar.apply(type);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final key = mode == ThemeMode.dark ? 'dark' : 'light';
    await _prefs.setString(AppConstants.prefThemeMode, key);
    notifyListeners();
  }

  Future<void> setLightMode(bool light) =>
      setThemeMode(light ? ThemeMode.light : ThemeMode.dark);

  Future<void> setThemeVariant(AppThemeVariant variant) async {
    if (!variant.isLight) {
      await _prefs.setString(AppConstants.prefDarkPalette, variant.name);
    }
    await setThemeMode(variant.themeMode);
  }

  Duration anim(Duration normal) => reducedMotion ? Duration.zero : normal;
}
