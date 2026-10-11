import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_calendar.dart';

class AppSettingsProvider extends ChangeNotifier {
  AppSettingsProvider(this._prefs) {
    AppCalendar.apply(calendarType);
  }

  final SharedPreferences _prefs;

  bool get sidebarCollapsed =>
      _prefs.getBool(AppConstants.prefSidebarCollapsed) ?? false;

  bool get reducedMotion =>
      _prefs.getBool(AppConstants.prefReducedMotion) ?? false;

  /// Online sync / Sync Center. Default on.
  bool get onlineEnabled =>
      _prefs.getBool(AppConstants.prefOnlineEnabled) ?? true;

  /// Block selling beyond available stock. Default on.
  bool get limitToStock =>
      _prefs.getBool(AppConstants.prefLimitToStock) ?? true;

  /// Business type: general | supplement | clothing.
  String get storeType =>
      _prefs.getString(AppConstants.prefStoreType) ?? 'general';

  /// Calendar: gregorian (default) | solar | lunar.
  AppCalendarType get calendarType =>
      AppCalendarType.parse(_prefs.getString(AppConstants.prefCalendarType));

  String get baseCurrency =>
      _prefs.getString(AppConstants.prefBaseCurrency) ??
      AppConstants.defaultCurrencyCode;

  /// `light` or `dark` (default light to match GlassFlow Light Professional).
  String get themeModeKey =>
      _prefs.getString(AppConstants.prefThemeMode) ?? 'light';

  ThemeMode get themeMode =>
      themeModeKey == 'dark' ? ThemeMode.dark : ThemeMode.light;

  bool get isLightMode => themeMode == ThemeMode.light;

  /// Dark palette remembered across light/dark toggles.
  AppThemeVariant get darkVariant =>
      _prefs.getString(AppConstants.prefDarkPalette) ==
          AppThemeVariant.hadid.name
      ? AppThemeVariant.hadid
      : AppThemeVariant.dark;

  AppThemeVariant get themeVariant =>
      isLightMode ? AppThemeVariant.light : darkVariant;

  Future<void> setSidebarCollapsed(bool value) async {
    await _prefs.setBool(AppConstants.prefSidebarCollapsed, value);
    notifyListeners();
  }

  Future<void> toggleSidebar() => setSidebarCollapsed(!sidebarCollapsed);

  Future<void> setReducedMotion(bool value) async {
    await _prefs.setBool(AppConstants.prefReducedMotion, value);
    notifyListeners();
  }

  Future<void> setOnlineEnabled(bool value) async {
    await _prefs.setBool(AppConstants.prefOnlineEnabled, value);
    notifyListeners();
  }

  Future<void> setLimitToStock(bool value) async {
    await _prefs.setBool(AppConstants.prefLimitToStock, value);
    notifyListeners();
  }

  Future<void> setStoreType(String value) async {
    await _prefs.setString(AppConstants.prefStoreType, value);
    notifyListeners();
  }

  Future<void> setCalendarType(AppCalendarType type) async {
    await _prefs.setString(AppConstants.prefCalendarType, type.storageKey);
    AppCalendar.apply(type);
    notifyListeners();
  }

  Future<void> setBaseCurrency(String code) async {
    await _prefs.setString(AppConstants.prefBaseCurrency, code);
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
