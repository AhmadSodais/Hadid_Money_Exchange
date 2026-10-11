import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_constants.dart';
import 'core/database/app_database.dart';
import 'core/routing/app_router.dart';
import 'core/sync/firebase_auth_session.dart';
import 'core/sync/firebase_config.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_typography.dart';
import 'core/theme/day_night_transition.dart';
import 'presentation/providers/app_lock_provider.dart';
import 'presentation/providers/app_settings_provider.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/alerts_count_provider.dart';
import 'presentation/providers/device_authorization_provider.dart';
import 'presentation/providers/trial_license_provider.dart';
import 'presentation/viewmodels/sync_viewmodel.dart';
import 'presentation/widgets/app_lock_gate.dart';
import 'presentation/widgets/trial_lock_screen.dart';
import 'presentation/widgets/unauthorized_device_screen.dart';
import 'core/utils/app_calendar.dart';
import 'core/utils/shamsi_dates.dart';
import 'core/utils/window_title_bar.dart';
import 'core/widgets/gf_scroll_behavior.dart';
import 'core/widgets/gf_shamsi_date_field.dart';
import 'core/snackbar/snackbar_viewmodel.dart';
import 'core/widgets/gf_snackbar.dart';
import 'core/widgets/gf_toast.dart';

bool _isWindowsKeyboardGlitch(Object error) {
  final text = error.toString();
  return text.contains('keysPressed') ||
      text.contains('RawKeyDownEvent') ||
      text.contains('RawKeyUpEvent') ||
      text.contains('KeyDownEvent') ||
      text.contains('KeyUpEvent') ||
      text.contains('Unable to parse JSON message') ||
      text.contains('The document is empty');
}

void _installWindowsKeyboardGuards() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_isWindowsKeyboardGlitch(details.exception)) return;
    previousOnError?.call(details);
  };

  final previousPlatformOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    if (_isWindowsKeyboardGlitch(error)) return true;
    return previousPlatformOnError?.call(error, stack) ?? false;
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installWindowsKeyboardGuards();
  ShamsiDates.bindPicker(GfShamsiDatePicker.show);

  // Quiet Easy Localization console spam ().
  EasyLocalization.logger.enableBuildModes = const [];

  await EasyLocalization.ensureInitialized();

  String? dbError;
  try {
    await AppDatabase.initialize();
    await FirebaseConfig.load();
    await FirebaseAuthSession.load();
  } catch (e, st) {
    dbError = e.toString();
    debugPrint('Database init failed: $e\n$st');
  }

  final prefs = await SharedPreferences.getInstance();
  // Language UI is hidden — clear any previously saved locale so startLocale (fa) wins.
  await prefs.remove('locale');
  AppCalendar.applyFromKey(prefs.getString(AppConstants.prefCalendarType));
  final auth = AuthProvider(prefs);
  final router = createAppRouter(refreshListenable: auth);

  runApp(
    EasyLocalization(
      // Only allow Persian (fa) in the app at all times.
      supportedLocales: const [Locale('fa')],
      startLocale: const Locale('fa'),
      fallbackLocale: const Locale('fa'),
      path: 'assets/lang',
      // Language picker is hidden; keep app locked to Persian.
      saveLocale: false,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppSettingsProvider(prefs)),
          ChangeNotifierProvider(create: (_) => AppLockProvider(prefs)),
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => AlertsCountProvider()),
          ChangeNotifierProvider(create: (_) => DeviceAuthorizationProvider()),
          ChangeNotifierProvider(create: (_) => TrialLicenseProvider()),
          ChangeNotifierProvider(create: (_) => SyncViewModel(prefs: prefs)),
          ChangeNotifierProvider(
            create: (_) {
              final vm = SnackbarViewModel();
              GfToast.bind(vm);
              return vm;
            },
          ),
        ],
        child: GlassFlowApp(router: router, databaseError: dbError),
      ),
    ),
  );
}

class GlassFlowApp extends StatelessWidget {
  const GlassFlowApp({super.key, required this.router, this.databaseError});

  final GoRouter router;
  final String? databaseError;

  @override
  Widget build(BuildContext context) {
    final langCode = context.locale.languageCode;
    final settings = context.watch<AppSettingsProvider>();
    AppCalendar.apply(settings.calendarType);
    AppTypography.applyLanguage(langCode);

    return DayNightThemeTransition(
      variant: settings.themeVariant,
      reduceMotion: settings.reducedMotion,
      builder: (context, variant) => _buildApp(context, langCode, variant),
    );
  }

  Widget _buildApp(
    BuildContext context,
    String langCode,
    AppThemeVariant variant,
  ) {
    AppColors.applyDarkPalette(variant.darkPalette);
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const GfScrollBehavior(),
      theme: AppLightTheme.lightForLanguage(langCode),
      darkTheme: AppDarkTheme.darkForLanguage(langCode),
      themeMode: variant.themeMode,
      // Theme switches are animated by DayNightThemeTransition.
      themeAnimationDuration: Duration.zero,
      localizationsDelegates: [
        // Shamsi calendar Material localizations (must come first).
        if (langCode == 'ps')
          PashtoMaterialLocalizations.delegate
        else if (langCode == 'fa')
          DariMaterialLocalizations.delegate
        else
          DefaultPersianMaterialLocalizations.delegate,
        if (langCode == 'ps')
          PashtoCupertinoLocalizations.delegate
        else if (langCode == 'fa')
          DariCupertinoLocalizations.delegate
        else
          DefaultPersianCupertinoLocalizations.delegate,
        ...context.localizationDelegates,
      ],
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      routerConfig: router,
      builder: (context, child) {
        final localeCode = context.locale.languageCode;
        final brightness = Theme.of(context).brightness;
        AppColors.applyBrightness(brightness);
        WindowTitleBar.sync(
          background: AppColors.background,
          foreground: AppColors.textPrimary,
          brightness: brightness,
        );
        AppTypography.applyLanguage(localeCode);
        final family = AppTypography.fontFamilyByLanguage(localeCode);

        ThemeData withAppFont(ThemeData base) {
          final textTheme = base.textTheme.apply(fontFamily: family);
          final primaryTextTheme = base.primaryTextTheme.apply(
            fontFamily: family,
          );
          final body = AppTypography.body.copyWith(fontFamily: family);
          final label = AppTypography.label.copyWith(fontFamily: family);
          final caption = AppTypography.caption.copyWith(fontFamily: family);
          return base.copyWith(
            textTheme: textTheme,
            primaryTextTheme: primaryTextTheme,
            inputDecorationTheme: base.inputDecorationTheme.copyWith(
              hintStyle: (base.inputDecorationTheme.hintStyle ?? body).copyWith(
                fontFamily: family,
              ),
              labelStyle: (base.inputDecorationTheme.labelStyle ?? label)
                  .copyWith(fontFamily: family),
              errorStyle: (base.inputDecorationTheme.errorStyle ?? caption)
                  .copyWith(fontFamily: family),
              helperStyle: caption.copyWith(fontFamily: family),
              floatingLabelStyle: label.copyWith(fontFamily: family),
              prefixStyle: body.copyWith(fontFamily: family),
              suffixStyle: body.copyWith(fontFamily: family),
              counterStyle: caption.copyWith(fontFamily: family),
            ),
          );
        }

        final themed = Theme(
          data: withAppFont(Theme.of(context)),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontFamily: family, color: AppColors.textPrimary),
            child: GfSnackbarHost(child: child ?? const SizedBox.shrink()),
          ),
        );

        final Widget page;
        if (databaseError != null) {
          page = Material(
            color: AppColors.background,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${'common.dbInitFailed'.tr()}\n\n$databaseError',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(
                    fontFamily: family,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        } else {
          final deviceAuth = context.watch<DeviceAuthorizationProvider>();
          if (!deviceAuth.isReady) {
            page = const AuthLoadingOverlay();
          } else if (!deviceAuth.isAuthorized) {
            page = Theme(
              data: withAppFont(Theme.of(context)),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontFamily: family,
                  color: AppColors.textPrimary,
                ),
                child: GfSnackbarHost(
                  child: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => const UnauthorizedDeviceScreen(),
                    ),
                  ),
                ),
              ),
            );
          } else {
            final license = context.watch<TrialLicenseProvider>();
            if (!license.isReady) {
              page = const AuthLoadingOverlay();
            } else if (license.isLocked) {
              // Nested Navigator provides the Overlay that TextFields need.
              page = Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const TrialLockScreen(),
                ),
              );
            } else {
              final auth = context.watch<AuthProvider>();
              page = auth.isReady ? themed : const AuthLoadingOverlay();
            }
          }
        }

        return AppLockGate(child: page);
      },
    );
  }
}
