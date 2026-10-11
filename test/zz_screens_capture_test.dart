import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hadid_exchange/application/security_service.dart';
import 'package:hadid_exchange/core/constants/app_routes.dart';
import 'package:hadid_exchange/core/routing/app_router.dart';
import 'package:hadid_exchange/core/snackbar/snackbar_viewmodel.dart';
import 'package:hadid_exchange/core/theme/app_typography.dart';
import 'package:hadid_exchange/presentation/widgets/exchange_ui.dart';
import 'package:hadid_exchange/core/widgets/gf_snackbar.dart';
import 'package:hadid_exchange/core/widgets/gf_toast.dart';
import 'package:hadid_exchange/domain/money/decimal.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';
import 'package:hadid_exchange/presentation/providers/app_lock_provider.dart';
import 'package:hadid_exchange/presentation/providers/app_settings_provider.dart';
import 'package:hadid_exchange/presentation/session/app_session.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
  }
  await loader.load();
}

void main() {
  late Harness h;
  late AppSession session;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    EasyLocalization.logger.enableBuildModes = const [];
    await EasyLocalization.ensureInitialized();
    AppTypography.applyLanguage('fa');
    await _loadFont('YekanBakh', [
      'assets/fonts/YekanBakhFaNum-Regular.ttf',
      'assets/fonts/YekanBakhFaNum-SemiBold.ttf',
      'assets/fonts/YekanBakhFaNum-Bold.ttf',
    ]);
    await _loadFont('Inter', ['assets/fonts/Inter-VariableFont_opsz,wght.ttf']);
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    await _loadFont('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf']);
    h = await Harness.create(clock: DateTime.now);
    final today = DateTime.now();
    final date = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    await h.openingCash('AFN', afn(100000), date: date);
    await h.openingCash('USD', usd(2000), date: date);
    final id = (await h.customer('کریم')).id;
    await h.receipt(id, 'USD', usd(100), date: date);
    await h.exchange(direction: ExchangeDirection.buy, base: 'USD', quote: 'AFN', baseMinor: usd(50), rate: '70', date: date);
    await h.app.rates.setRate(
        base: 'USD', quote: 'AFN', buyRate: Decimal.parse('70'), sellRate: Decimal.parse('71'), actor: h.owner);
    session = await AppSession.start(h.app, SecurityService.ownerUserId);
  });

  tearDown(() async {
    session.dispose();
    await h.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final size in const [Size(1600, 1000), Size(1100, 900)]) {
    testWidgets('capture ${size.width.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final GoRouter router = createAppRouter();
      const key = ValueKey('shot');
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: EasyLocalization(
            supportedLocales: const [Locale('fa')],
            startLocale: const Locale('fa'),
            fallbackLocale: const Locale('fa'),
            path: 'assets/lang',
            saveLocale: false,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => AppSettingsProvider(prefs)),
                ChangeNotifierProvider(create: (_) => AppLockProvider(prefs)),
                ChangeNotifierProvider.value(value: session),
                ChangeNotifierProvider(create: (_) {
                  final vm = SnackbarViewModel();
                  GfToast.bind(vm);
                  return vm;
                }),
              ],
              child: Builder(
                builder: (context) => MaterialApp.router(
                  routerConfig: router,
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: [
                    DariMaterialLocalizations.delegate,
                    DariCupertinoLocalizations.delegate,
                    ...context.localizationDelegates,
                  ],
                  builder: (context, child) => GfSnackbarHost(child: child!),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      final w = size.width.toInt();

      router.go(AppRoutes.exchange);
      await settle(tester);
      await expectLater(find.byKey(key), matchesGoldenFile('shots/exchange_empty_$w.png'));
      await tester.enterText(
          find.descendant(of: find.byType(AmountField).first, matching: find.byType(EditableText)), '500');
      await settle(tester);
      await expectLater(find.byKey(key), matchesGoldenFile('shots/exchange_filled_$w.png'));

      router.go(AppRoutes.cash);
      await settle(tester);
      await tester.tap(find.text('انتخاب مشتری…'));
      await settle(tester);
      await tester.tap(find.textContaining('کریم').last);
      await settle(tester);
      await tester.enterText(
          find.descendant(of: find.byType(AmountField).first, matching: find.byType(EditableText)), '40');
      await settle(tester);
      await expectLater(find.byKey(key), matchesGoldenFile('shots/cash_$w.png'));

      router.go(AppRoutes.reconciliation);
      await settle(tester);
      await tester.enterText(
          find.descendant(of: find.byType(LedgerTable).first, matching: find.byType(EditableText)).first, '96000');
      await settle(tester);
      await expectLater(find.byKey(key), matchesGoldenFile('shots/recon_$w.png'));

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    });
  }
}
