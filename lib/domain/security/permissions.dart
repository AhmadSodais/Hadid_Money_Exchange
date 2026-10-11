/// Permission codes enforced by application services.
///
/// The deployment is currently single-user (the owner, protected by the app
/// lock), but every sensitive operation is checked against these codes so
/// staff accounts can be introduced without touching the financial core.
abstract final class Permissions {
  static const transactionsPost = 'transactions.post';
  static const transactionsReverse = 'transactions.reverse';
  static const adjustmentsPost = 'adjustments.post';
  static const openingBalancesPost = 'opening_balances.post';
  static const customersManage = 'customers.manage';
  static const ratesManage = 'rates.manage';
  static const reconciliationPerform = 'reconciliation.perform';
  static const reconciliationReopen = 'reconciliation.reopen';
  static const reportsView = 'reports.view';
  static const auditView = 'audit.view';
  static const backupCreate = 'backup.create';
  static const backupRestore = 'backup.restore';
  static const settingsManage = 'settings.manage';

  static const all = <String, String>{
    transactionsPost: 'ثبت معاملات',
    transactionsReverse: 'برگشت معاملات',
    adjustmentsPost: 'ثبت اصلاحات مالی',
    openingBalancesPost: 'ثبت بیلانس افتتاحیه',
    customersManage: 'مدیریت مشتریان',
    ratesManage: 'مدیریت نرخ‌ها',
    reconciliationPerform: 'اخذ بیلانس روزانه',
    reconciliationReopen: 'بازگشایی روز بسته‌شده',
    reportsView: 'مشاهده گزارش‌ها',
    auditView: 'مشاهده سوابق ممیزی',
    backupCreate: 'تهیه پشتیبان',
    backupRestore: 'بازیابی پشتیبان',
    settingsManage: 'تنظیمات سیستم',
  };

  /// Default permission sets per seeded role code.
  static const roleDefaults = <String, List<String>>{
    'admin': [
      transactionsPost, transactionsReverse, adjustmentsPost,
      openingBalancesPost, customersManage, ratesManage,
      reconciliationPerform, reconciliationReopen, reportsView, auditView,
      backupCreate, backupRestore, settingsManage,
    ],
    'cashier': [
      transactionsPost, customersManage, reconciliationPerform, reportsView,
    ],
    'accountant': [
      transactionsPost, transactionsReverse, adjustmentsPost,
      openingBalancesPost, customersManage, ratesManage,
      reconciliationPerform, reportsView, backupCreate,
    ],
    'auditor': [reportsView, auditView],
  };
}

/// The user on whose behalf an operation runs.
final class Actor {
  const Actor({
    required this.userId,
    required this.displayName,
    required this.permissions,
  });

  final int userId;
  final String displayName;
  final Set<String> permissions;

  bool can(String permission) => permissions.contains(permission);
}
