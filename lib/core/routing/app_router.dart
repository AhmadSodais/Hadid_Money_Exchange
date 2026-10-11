import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../domain/security/permissions.dart';
import '../../presentation/pages/cash_transaction_page.dart';
import '../../presentation/pages/customer_statement_page.dart';
import '../../presentation/pages/customers_page.dart';
import '../../presentation/pages/dashboard_page.dart';
import '../../presentation/pages/exchange_page.dart';
import '../../presentation/pages/journal_page.dart';
import '../../presentation/pages/rates_page.dart';
import '../../presentation/pages/reconciliation_page.dart';
import '../../presentation/pages/reports_page.dart';
import '../../presentation/pages/settings_page.dart';
import '../../presentation/session/app_session.dart';
import '../../presentation/widgets/app_shell.dart';
import '../constants/app_routes.dart';
import 'app_page_transitions.dart';

const Map<String, String> _routePermissions = {
  AppRoutes.exchange: Permissions.transactionsPost,
  AppRoutes.cash: Permissions.transactionsPost,
  AppRoutes.journal: Permissions.reportsView,
  AppRoutes.reconciliation: Permissions.reconciliationPerform,
  AppRoutes.reports: Permissions.reportsView,
};

GoRouter createAppRouter({Listenable? refreshListenable}) {
  Page<void> page(GoRouterState state, Widget child) =>
      AppPageTransitions.fadeSlide(key: state.pageKey, child: child);

  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final required = _routePermissions[state.uri.path];
      if (required == null) return null;
      final session = Provider.of<AppSession>(context, listen: false);
      return session.can(required) ? null : AppRoutes.dashboard;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            pageBuilder: (context, state) => page(state, const DashboardPage()),
          ),
          GoRoute(
            path: AppRoutes.exchange,
            pageBuilder: (context, state) => page(state, const ExchangePage()),
          ),
          GoRoute(
            path: AppRoutes.cash,
            pageBuilder: (context, state) => page(state, const CashTransactionPage()),
          ),
          GoRoute(
            path: AppRoutes.customers,
            pageBuilder: (context, state) => page(state, const CustomersPage()),
          ),
          GoRoute(
            path: AppRoutes.customerStatement,
            redirect: (context, state) =>
                int.tryParse(state.uri.queryParameters['id'] ?? '') == null
                    ? AppRoutes.customers
                    : null,
            pageBuilder: (context, state) => AppPageTransitions.slideForward(
              key: state.pageKey,
              child: CustomerStatementPage(
                key: ValueKey(state.uri.queryParameters['id']),
                customerId: int.parse(state.uri.queryParameters['id']!),
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.journal,
            pageBuilder: (context, state) => page(state, const JournalPage()),
          ),
          GoRoute(
            path: AppRoutes.reconciliation,
            pageBuilder: (context, state) => page(state, const ReconciliationPage()),
          ),
          GoRoute(
            path: AppRoutes.reports,
            pageBuilder: (context, state) => page(state, const ReportsPage()),
          ),
          GoRoute(
            path: AppRoutes.rates,
            pageBuilder: (context, state) => page(state, const RatesPage()),
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (context, state) => page(state, const SettingsPage()),
          ),
        ],
      ),
    ],
  );
}
