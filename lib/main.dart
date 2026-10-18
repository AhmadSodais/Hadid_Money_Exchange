import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'application/app_services.dart';
import 'application/security_service.dart';
import 'core/constants/app_constants.dart';
import 'core/routing/app_router.dart';
import 'core/snackbar/snackbar_viewmodel.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_typography.dart';
import 'core/theme/day_night_transition.dart';
import 'core/utils/app_calendar.dart';
import 'core/utils/gf_scale.dart';
import 'core/utils/shamsi_dates.dart';
import 'core/utils/window_title_bar.dart';
import 'core/widgets/gf_scroll_behavior.dart';
import 'core/widgets/gf_shamsi_date_field.dart';
import 'core/widgets/gf_snackbar.dart';
import 'core/widgets/gf_toast.dart';
import 'presentation/providers/app_lock_provider.dart';
import 'presentation/providers/app_settings_provider.dart';
import 'presentation/providers/device_authorization_provider.dart';
import 'presentation/session/app_session.dart';
import 'presentation/widgets/app_lock_gate.dart';
import 'presentation/widgets/device_auth_gate.dart';

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

void _scheduleAutoExcelExport(AppServices services) {
  Future<void> check() async {
    try {
      await services.transfer.autoExportIfDue();
    } catch (e, st) {
      debugPrint('Auto Excel export failed: $e\n$st');
    }
  }

  unawaited(check());
  Timer.periodic(const Duration(minutes: 15), (_) => check());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installWindowsKeyboardGuards();
  ShamsiDates.bindPicker(GfShamsiDatePicker.show);

  EasyLocalization.logger.enableBuildModes = const [];
  await EasyLocalization.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('locale');
  AppCalendar.apply(AppCalendarType.solar);

  AppSession? session;
  String? startupError;
  String? startupWarning;
  try {
    final support = await getApplicationSupportDirectory();
    final services = await AppServices.open(
      databasePath: p.join(support.path, AppConstants.dataFolderName, 'hadid_exchange.db'),
      backupDirectory: p.join(support.path, AppConstants.backupFolderName),
      excelExportDirectory: p.join(support.path, AppConstants.excelExportFolderName),
    );
    try {
      await services.backups.autoBackupIfDue();
    } catch (e, st) {
      startupWarning = 'پشتیبان خودکار انجام نشد: $e';
      debugPrint('Auto backup failed: $e\n$st');
    }
    session = await AppSession.start(services, SecurityService.ownerUserId);
    _scheduleAutoExcelExport(services);
  } catch (e, st) {
    startupError = e.toString();
    debugPrint('Database init failed: $e\n$st');
  }

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('fa')],
      startLocale: const Locale('fa'),
      fallbackLocale: const Locale('fa'),
      path: 'assets/lang',
      saveLocale: false,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DeviceAuthorizationProvider(), lazy: false),
          ChangeNotifierProvider(create: (_) => AppSettingsProvider(prefs)),
          ChangeNotifierProvider(create: (_) => AppLockProvider(prefs)),
          if (session != null) ChangeNotifierProvider.value(value: session),
          ChangeNotifierProvider(
            create: (_) {
              final vm = SnackbarViewModel();
              GfToast.bind(vm);
              return vm;
            },
          ),
        ],
        child: HadidExchangeApp(
          router: session == null ? null : createAppRouter(),
          startupError: startupError,
          startupWarning: startupWarning,
        ),
      ),
    ),
  );
}

class HadidExchangeApp extends StatelessWidget {
  const HadidExchangeApp({super.key, required this.router, this.startupError, this.startupWarning});

  /// Null when the database could not be opened; only the error screen is shown.
  final GoRouter? router;
  final String? startupError;
  final String? startupWarning;

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

  Widget _buildApp(BuildContext context, String langCode, AppThemeVariant variant) {
    AppColors.applyDarkPalette(variant.darkPalette);
    final delegates = <LocalizationsDelegate<dynamic>>[
      DariMaterialLocalizations.delegate,
      DariCupertinoLocalizations.delegate,
      ...context.localizationDelegates,
    ];
    final theme = AppLightTheme.lightForLanguage(langCode);
    final darkTheme = AppDarkTheme.darkForLanguage(langCode);

    if (router == null) {
      return MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: theme,
        darkTheme: darkTheme,
        themeMode: variant.themeMode,
        localizationsDelegates: delegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        builder: (context, child) => GfScaleHost(
          child: DeviceAuthGate(
            frame: (screen) => GfSnackbarHost(child: screen),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: _StartupErrorScreen(error: startupError ?? ''),
      );
    }

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const GfScrollBehavior(),
      theme: theme,
      darkTheme: darkTheme,
      themeMode: variant.themeMode,
      themeAnimationDuration: Duration.zero,
      localizationsDelegates: delegates,
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
          final primaryTextTheme = base.primaryTextTheme.apply(fontFamily: family);
          final body = AppTypography.body.copyWith(fontFamily: family);
          final label = AppTypography.label.copyWith(fontFamily: family);
          final caption = AppTypography.caption.copyWith(fontFamily: family);
          return base.copyWith(
            textTheme: textTheme,
            primaryTextTheme: primaryTextTheme,
            inputDecorationTheme: base.inputDecorationTheme.copyWith(
              hintStyle: (base.inputDecorationTheme.hintStyle ?? body).copyWith(fontFamily: family),
              labelStyle: (base.inputDecorationTheme.labelStyle ?? label).copyWith(fontFamily: family),
              errorStyle: (base.inputDecorationTheme.errorStyle ?? caption).copyWith(fontFamily: family),
              helperStyle: caption.copyWith(fontFamily: family),
              floatingLabelStyle: label.copyWith(fontFamily: family),
              prefixStyle: body.copyWith(fontFamily: family),
              suffixStyle: body.copyWith(fontFamily: family),
              counterStyle: caption.copyWith(fontFamily: family),
            ),
          );
        }

        Widget themed(Widget content) => Theme(
              data: withAppFont(Theme.of(context)),
              child: DefaultTextStyle.merge(
                style: TextStyle(fontFamily: family, color: AppColors.textPrimary),
                child: GfSnackbarHost(child: content),
              ),
            );

        return GfScaleHost(
          child: DeviceAuthGate(
            frame: themed,
            child: AppLockGate(
              child: themed(
                _StartupNotice(
                  warning: startupWarning,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StartupNotice extends StatefulWidget {
  const _StartupNotice({required this.warning, required this.child});

  final String? warning;
  final Widget child;

  @override
  State<_StartupNotice> createState() => _StartupNoticeState();
}

class _StartupNoticeState extends State<_StartupNotice> {
  @override
  void initState() {
    super.initState();
    final warning = widget.warning;
    if (warning != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) GfToast.warning(context, warning, duration: const Duration(seconds: 10));
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: AppColors.background,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storage_rounded, size: 48, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text('پایگاه داده صرافی باز نشد.', style: AppTypography.sectionTitle, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(
                    'هیچ داده‌ای تغییر داده نشده است. برنامه را ببندید و دوباره باز کنید. '
                    'اگر مشکل ادامه داشت، پیش از هر اقدامی از پوشه داده‌ها کپی بگیرید و '
                    'طبق راهنمای بازیابی، آخرین پشتیبان معتبر را بازیابی کنید.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    error,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
