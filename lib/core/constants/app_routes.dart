/// Route path constants.
abstract final class AppRoutes {
  static const String login = '/login';
  static const String overview = '/';
  static const String products = '/products';
  static const String alerts = '/alerts';
  /// Legacy path — redirects to [products].
  static const String warehouseLegacy = '/warehouse';
  static const String warehouses = '/warehouses';
  static const String warehouseDetail = '/warehouses/detail';
  static const String inboundOutbound = '/inbound-outbound';
  static const String purchases = '/purchases';
  static const String sales = '/sales';
  static const String orders = '/orders';
  static const String expenses = '/expenses';
  static const String tradingCompanies = '/trading-companies';
  static const String tradingCompanyActivity = '/trading-companies/activity';
  static const String customers = '/customers';
  static const String employees = '/employees';
  static const String employeeDetail = '/employees/detail';
  static const String settings = '/settings';
  static const String enableAuth = '/settings/enable-auth';
}
