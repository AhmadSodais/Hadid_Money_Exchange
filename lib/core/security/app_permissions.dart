/// Canonical permission keys used by roles and sidebar/route gating.
abstract final class AppPermissions {
  static const overview = 'overview';
  static const sales = 'sales';
  static const products = 'products';
  static const orders = 'orders';
  static const purchases = 'purchases';
  static const purchasesEdit = 'purchases.edit';
  static const tradingCompanies = 'tradingCompanies';
  static const customers = 'customers';
  static const expenses = 'expenses';
  static const warehouses = 'warehouses';
  static const employees = 'employees';
  static const alerts = 'alerts';
  static const syncCenter = 'syncCenter';
  static const settings = 'settings';
  static const rolesManage = 'roles.manage';
  static const reportsView = 'reports.view';

  /// Every permission — granted by default to new roles/users.
  static const List<String> all = [
    overview,
    sales,
    products,
    orders,
    purchases,
    purchasesEdit,
    tradingCompanies,
    customers,
    expenses,
    warehouses,
    employees,
    alerts,
    syncCenter,
    settings,
    rolesManage,
    reportsView,
  ];

  /// Whether [permissions] include access to purchase prices / purchase data.
  /// Used to hide cost fields in Products and related UIs.
  static bool canViewPurchaseData(Iterable<String> permissions) =>
      permissions.contains(purchases);

  /// Maps a sidebar/app route to the permission required to see it.
  static String? forRoute(String route) {
    if (route == '/' || route.isEmpty) return overview;
    if (route.startsWith('/sales')) return sales;
    if (route.startsWith('/products')) return products;
    if (route.startsWith('/orders')) return orders;
    if (route.startsWith('/purchases')) return purchases;
    if (route.startsWith('/trading-companies')) return tradingCompanies;
    if (route.startsWith('/customers')) return customers;
    if (route.startsWith('/expenses')) return expenses;
    if (route.startsWith('/warehouses')) return warehouses;
    if (route.startsWith('/employees')) return employees;
    if (route.startsWith('/alerts')) return alerts;
    if (route.startsWith('/settings')) return settings;
    if (route.startsWith('/login')) return null;
    return overview;
  }
}

/// Supported retail business types (Settings).
abstract final class StoreTypes {
  static const general = 'general';
  static const supplement = 'supplement';
  static const clothing = 'clothing';

  static const List<String> all = [general, supplement, clothing];
}
