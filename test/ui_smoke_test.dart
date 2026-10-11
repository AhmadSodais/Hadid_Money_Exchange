import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:hadid_exchange/application/ledger_queries.dart';
import 'package:hadid_exchange/application/security_service.dart';
import 'package:hadid_exchange/core/widgets/gf_text_field.dart';
import 'package:hadid_exchange/core/constants/app_routes.dart';
import 'package:hadid_exchange/core/routing/app_router.dart';
import 'package:hadid_exchange/core/snackbar/snackbar_viewmodel.dart';
import 'package:hadid_exchange/core/widgets/gf_snackbar.dart';
import 'package:hadid_exchange/core/widgets/gf_toast.dart';
import 'package:hadid_exchange/domain/money/decimal.dart';
import 'package:hadid_exchange/domain/transactions/financial_command.dart';
import 'package:hadid_exchange/presentation/pages/cash_transaction_page.dart';
import 'package:hadid_exchange/presentation/pages/customer_statement_page.dart';
import 'package:hadid_exchange/presentation/pages/customers_page.dart';
import 'package:hadid_exchange/presentation/pages/dashboard_page.dart';
import 'package:hadid_exchange/presentation/pages/exchange_page.dart';
import 'package:hadid_exchange/presentation/pages/journal_page.dart';
import 'package:hadid_exchange/presentation/pages/rates_page.dart';
import 'package:hadid_exchange/presentation/pages/reconciliation_page.dart';
import 'package:hadid_exchange/presentation/pages/reports_page.dart';
import 'package:hadid_exchange/presentation/pages/settings_page.dart';
import 'package:hadid_exchange/presentation/providers/app_lock_provider.dart';
import 'package:hadid_exchange/presentation/providers/app_settings_provider.dart';
import 'package:hadid_exchange/presentation/session/app_session.dart';
import 'package:hadid_exchange/presentation/widgets/daily_balance_dialog.dart';
import 'package:hadid_exchange/presentation/widgets/settings_kit.dart';
import 'package:hadid_exchange/presentation/widgets/transaction_detail_dialog.dart';
import 'package:hadid_exchange/presentation/widgets/transaction_edit_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// Opens every screen against a real temporary database with some activity
/// and fails on any build, layout, or runtime exception.
void main() {
  late Harness h;
  late AppSession session;
  late SharedPreferences prefs;
  late int customerId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    EasyLocalization.logger.enableBuildModes = const [];
    await EasyLocalization.ensureInitialized();
    h = await Harness.create(clock: DateTime.now);
    final today = DateTime.now();
    final date =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    await h.openingCash('AFN', afn(100000), date: date);
    await h.openingCash('USD', usd(2000), date: date);
    customerId = (await h.customer('کریم')).id;
    await h.receipt(customerId, 'USD', usd(100), date: date);
    await h.exchange(
      direction: ExchangeDirection.buy,
      base: 'USD',
      quote: 'AFN',
      baseMinor: usd(50),
      rate: '70',
      date: date,
    );
    await h.app.rates.setRate(
      base: 'USD',
      quote: 'AFN',
      buyRate: Decimal.parse('70'),
      sellRate: Decimal.parse('71'),
      actor: h.owner,
    );
    session = await AppSession.start(h.app, SecurityService.ownerUserId);
  });

  tearDown(() async {
    session.dispose();
    await h.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final routes = <String, Type>{
    AppRoutes.dashboard: DashboardPage,
    AppRoutes.exchange: ExchangePage,
    AppRoutes.cash: CashTransactionPage,
    AppRoutes.customers: CustomersPage,
    '${AppRoutes.customerStatement}?id=CUSTOMER': CustomerStatementPage,
    AppRoutes.journal: JournalPage,
    AppRoutes.reconciliation: ReconciliationPage,
    AppRoutes.reports: ReportsPage,
    AppRoutes.rates: RatesPage,
    AppRoutes.settings: SettingsPage,
  };

  // One app instance visits every route: easy_localization only finishes
  // loading its asset bundle once per test process.
  testWidgets('every screen renders with data and without exceptions', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GoRouter router = createAppRouter();
    await tester.pumpWidget(
      EasyLocalization(
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
            ChangeNotifierProvider(
              create: (_) {
                final vm = SnackbarViewModel();
                GfToast.bind(vm);
                return vm;
              },
            ),
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
    );
    await settle(tester);

    for (final MapEntry(key: route, value: pageType) in routes.entries) {
      router.go(route.replaceFirst('CUSTOMER', '$customerId'));
      await settle(tester);

      expect(tester.takeException(), isNull, reason: route);
      expect(router.routeInformationProvider.value.uri.path, Uri.parse(route).path);
      expect(find.byType(pageType, skipOffstage: false), findsOneWidget, reason: route);
      expect(find.text('روزنامچه معاملات', skipOffstage: false), findsWidgets, reason: 'sidebar on $route');

      if (route == AppRoutes.dashboard) {
        expect(find.text('96,500.00', skipOffstage: false), findsWidgets, reason: 'AFN cash on dashboard');
      }
      if (route == AppRoutes.customers || route.startsWith(AppRoutes.customerStatement)) {
        expect(find.textContaining('کریم', skipOffstage: false), findsWidgets, reason: route);
      }
      if (route == AppRoutes.reports) {
        final tabBar = find.byType(TabBar, skipOffstage: false);
        expect(tabBar, findsOneWidget);
        final controller = DefaultTabController.of(tester.element(tabBar));
        for (var i = 1; i < controller.length; i++) {
          controller.index = i;
          await settle(tester);
          expect(tester.takeException(), isNull, reason: 'report tab $i');
        }
      }
      if (route == AppRoutes.journal) {
        final ctx = tester.element(find.byType(JournalPage));
        final txs = (await tester.runAsync(
            () => h.app.queries.journal(const JournalFilter(activeOnly: true))))!;
        for (final t in txs.where((t) => t.type == TransactionType.receipt || t.isExchange)) {
          unawaited(TransactionEditDialog.show(ctx, t));
          await settle(tester);
          expect(tester.takeException(), isNull, reason: 'edit dialog ${t.type.name}');
          expect(find.text('ذخیره ویرایش'), findsOneWidget);
          Navigator.of(tester.element(find.byType(TransactionEditDialog))).pop();
          await settle(tester);
        }
        unawaited(TransactionDetailDialog.show(ctx, txs.first.id));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'detail dialog');
        expect(find.text('ویرایش'), findsWidgets);
        Navigator.of(tester.element(find.byType(TransactionDetailDialog))).pop();
        await settle(tester);
      }
      if (route == AppRoutes.reconciliation) {
        await tester.tap(find.text('افزودن بیلانس'));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'add balance dialog');
        final dialog = find.byType(DailyBalanceDialog);
        expect(dialog, findsOneWidget);
        final amount = find.byWidgetPredicate(
            (w) => w is GfTextField && (w.label ?? '').startsWith('مبلغ شمارش‌شده'));
        await tester.enterText(find.descendant(of: amount, matching: find.byType(TextField)), '1000');
        await settle(tester);
        await tester.tap(find.descendant(of: dialog, matching: find.text('ثبت بیلانس')).last);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'saving a balance');
        expect(dialog, findsNothing);
        final saved = (await tester.runAsync(() => h.app.reconciliation.records()))!;
        expect(saved, hasLength(1));
      }
      if (route == AppRoutes.settings) {
        final tiles = find.byType(SettingsNavTile);
        expect(tiles, findsWidgets);
        final labels = [for (final e in tiles.evaluate()) (e.widget as SettingsNavTile).label];
        expect(labels, containsAll(['اطلاعات صرافی', 'قوانین ثبت اسناد', 'مدیریت داده‌ها', 'درباره برنامه']));
        expect(labels, isNot(contains('ورودی و خروجی اکسل')));
        expect(labels, isNot(contains('انتقال از برنامه قبلی')));
        expect(labels, isNot(contains('سوابق ممیزی و صحت دفاتر')));
        expect(labels, isNot(contains('پشتیبان‌گیری و بازیابی')));
        expect(labels, isNot(contains('درباره و مجوز')));
        for (var i = 0; i < tiles.evaluate().length; i++) {
          final tile = tiles.at(i);
          final label = tester.widget<SettingsNavTile>(tile).label;
          await tester.tap(tile);
          await settle(tester);
          expect(tester.takeException(), isNull, reason: 'settings section $label');
          expect(tester.widget<SettingsNavTile>(tiles.at(i)).selected, isTrue, reason: label);
          if (label == 'اطلاعات صرافی') {
            for (final field in ['نام صرافی', 'ولایت / شهر', 'آدرس صرافی', 'نام کاربری', 'شماره تماس']) {
              expect(find.byWidgetPredicate((w) => w is GfTextField && w.label == field), findsOneWidget,
                  reason: field);
            }
            expect(find.text('اجازه منفی شدن موجودی نقد صندوق'), findsNothing);
          }
          if (label == 'قوانین ثبت اسناد') {
            expect(find.text('اجازه منفی شدن موجودی نقد صندوق'), findsOneWidget);
            expect(find.text('قفل روزهای بسته‌شده'), findsOneWidget);
          }
          if (label == 'ارزها و صندوق‌ها') {
            expect(find.text('ارز جدید'), findsOneWidget);
            expect(find.text('صندوق جدید'), findsOneWidget);
            expect(find.text('صندوق اصلی'), findsWidgets);
          }
          if (label == 'مدیریت داده‌ها') {
            expect(find.text('ورودی اکسل'), findsWidgets);
            expect(find.text('خروجی اکسل'), findsWidgets);
            expect(find.text('پاک کردن همه داده‌ها'), findsWidgets);
            expect(find.text('خروجی خودکار اکسل'), findsWidgets);
            await tester.scrollUntilVisible(
              find.text('سوابق خروجی خودکار اکسل'),
              300,
              scrollable: find.ancestor(of: find.text('خروجی خودکار اکسل').first, matching: find.byType(Scrollable)).first,
            );
            await settle(tester);
            expect(tester.takeException(), isNull, reason: 'automatic export history');
          }
          if (label == 'ظاهر') {
            expect(find.text('تقویم نمایش'), findsNothing);
            expect(find.text('کاهش انیمیشن‌ها'), findsNothing);
          }
        }
      }
      if (route != AppRoutes.settings) {
        expect(find.text('خروجی اکسل'), findsNothing, reason: 'no per-page Excel output on $route');
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });
}
