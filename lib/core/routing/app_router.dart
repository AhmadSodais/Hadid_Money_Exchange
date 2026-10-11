import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../constants/app_routes.dart';
import 'app_page_transitions.dart';
import '../../presentation/pages/alerts_page.dart';
import '../../presentation/pages/enable_auth_page.dart';
import '../../presentation/pages/employee_detail_page.dart';
import '../../presentation/pages/employees_page.dart';
import '../../presentation/pages/expenses_page.dart';
import '../../presentation/pages/login_page.dart';
import '../../presentation/pages/orders_page.dart';
import '../../presentation/pages/outbound_order_page.dart';
import '../../presentation/pages/overview_page.dart';
import '../../presentation/pages/purchases_page.dart';
import '../../presentation/pages/settings_page.dart';
import '../../presentation/pages/customers_page.dart';
import '../../presentation/pages/trading_companies_page.dart';
import '../../presentation/pages/trading_company_activity_page.dart';
import '../../presentation/pages/warehouse_detail_page.dart';
import '../../presentation/pages/warehouse_page.dart';
import '../../presentation/pages/warehouses_page.dart';
import '../../presentation/providers/auth_provider.dart';
import '../../presentation/widgets/app_shell.dart';

GoRouter createAppRouter({Listenable? refreshListenable}) {
  return GoRouter(
    initialLocation: AppRoutes.overview,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final path = state.uri.path;
      if (path == AppRoutes.warehouseLegacy) return AppRoutes.products;

      AuthProvider? auth;
      try {
        auth = Provider.of<AuthProvider>(context, listen: false);
      } catch (_) {
        return null;
      }
      if (!auth.isReady) return null;

      final loggingIn = path == AppRoutes.login;
      if (auth.isAuthRequired && !auth.isAuthenticated) {
        return loggingIn ? null : AppRoutes.login;
      }
      if (loggingIn) {
        return auth.isAuthRequired ? AppRoutes.overview : AppRoutes.overview;
      }

      if (auth.isAuthRequired && !auth.canAccessRoute(path)) {
        return AppRoutes.overview;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) => AppPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const LoginPage(),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.overview,
            pageBuilder: (context, state) => AppPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const OverviewPage(),
            ),
          ),
          GoRoute(
            path: AppRoutes.products,
            pageBuilder: (context, state) => AppPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const WarehousePage(),
            ),
          ),
          GoRoute(
            path: AppRoutes.alerts,
            pageBuilder: (context, state) => AppPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const AlertsPage(),
            ),
          ),
          GoRoute(
            path: AppRoutes.warehouses,
            pageBuilder: (context, state) => AppPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const WarehousesPage(),
            ),
            routes: [
              GoRoute(
                path: 'detail',
                pageBuilder: (context, state) {
                  final id = state.extra;
                  if (id is! int) {
                    return AppPageTransitions.fadeSlide(
                      key: state.pageKey,
                      child: const WarehousesPage(),
                    );
                  }
                  return AppPageTransitions.slideForward(
                    key: state.pageKey,
                    child: WarehouseDetailPage(warehouseId: id),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.inboundOutbound,
            redirect: (_, __) => AppRoutes.purchases,
          ),
          GoRoute(
            path: AppRoutes.purchases,
            pageBuilder: (context, state) => AppPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const PurchasesPage(),
            ),
          ),
          GoRoute(
            path: AppRoutes.sales,
            pageBuilder: (context, state) {
              final id = state.extra;
              return AppPageTransitions.fadeSlide(
                key: state.pageKey,
                child: OutboundOrderPage(editingOrderId: id is int ? id : null),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.orders,
            pageBuilder: (context, state) => AppPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const OrdersPage(),
            ),
          ),
          GoRoute(
            path: AppRoutes.expenses,
            pageBuilder: (context, state) => AppPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const ExpensesPage(),
            ),
          ),
          GoRoute(
            path: AppRoutes.tradingCompanies,
            pageBuilder: (context, state) => AppPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const TradingCompaniesPage(),
            ),
            routes: [
              GoRoute(
                path: 'activity',
                pageBuilder: (context, state) {
                  final args = state.extra;
                  if (args is! TradingCompanyArgs) {
                    return AppPageTransitions.fadeSlide(
                      key: state.pageKey,
                      child: const TradingCompaniesPage(),
                    );
                  }
                  return AppPageTransitions.slideForward(
                    key: state.pageKey,
                    child: TradingCompanyActivityPage(company: args),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.customers,
            pageBuilder: (context, state) => AppPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const CustomersPage(),
            ),
          ),
          GoRoute(
            path: AppRoutes.employees,
            pageBuilder: (context, state) => AppPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const EmployeesPage(),
            ),
            routes: [
              GoRoute(
                path: 'detail',
                pageBuilder: (context, state) {
                  final id = state.extra;
                  if (id is! int) {
                    return AppPageTransitions.fadeSlide(
                      key: state.pageKey,
                      child: const EmployeesPage(),
                    );
                  }
                  return AppPageTransitions.slideForward(
                    key: state.pageKey,
                    child: EmployeeDetailPage(employeeId: id),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (context, state) => AppPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const SettingsPage(),
            ),
            routes: [
              GoRoute(
                path: 'enable-auth',
                pageBuilder: (context, state) =>
                    AppPageTransitions.slideForward(
                      key: state.pageKey,
                      child: const EnableAuthPage(),
                    ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
