import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/repositories/customer_repository_impl.dart';
import '../constants/app_constants.dart';
import '../database/app_database.dart';
import '../utils/shamsi_dates.dart';
import 'firebase_rtdb_client.dart';
import 'firebase_sync_service.dart';
import 'sync_models.dart';
import 'sync_queue_repository.dart';

/// Result of pulling remote server data into local SQLite.
class FirebaseRestoreResult {
  const FirebaseRestoreResult({
    required this.categories,
    required this.warehouses,
    required this.companies,
    required this.customers,
    required this.products,
    required this.transactions,
    this.companyPayments = 0,
    this.expenses = 0,
    this.employees = 0,
    this.employeeWithdrawals = 0,
    this.orders = 0,
    this.purchases = 0,
    this.error,
  });

  final int categories;
  final int warehouses;
  final int companies;
  final int customers;
  final int products;
  final int transactions;
  final int companyPayments;
  final int expenses;
  final int employees;
  final int employeeWithdrawals;
  final int orders;
  final int purchases;
  final String? error;

  int get total =>
      categories +
      warehouses +
      companies +
      customers +
      products +
      transactions +
      companyPayments +
      expenses +
      employees +
      employeeWithdrawals +
      orders +
      purchases;

  bool get isEmpty => total == 0 && error == null;
  bool get ok => error == null;
}

/// Downloads synced entities from Firebase RTDB and upserts them into SQLite.
///
/// Matches the live [glassflow](https://glass-app-2e63f-default-rtdb.firebaseio.com/glassflow)
/// shape used in Firebase exports:
/// - collections are often **arrays** with a leading `null` slot
/// - or maps keyed by id string
/// - transactions may use Shamsi `transactionDate` (`1404/9/10`)
class FirebaseRestoreService {
  FirebaseRestoreService({FirebaseRtdbClient? client})
      : _client = client ?? FirebaseRtdbClient();

  final FirebaseRtdbClient _client;

  /// Replaces local business data with the server copy in one
  /// all-or-nothing step. Refuses to run while local jobs are still pending
  /// (they would be lost) and leaves local data untouched if the server is
  /// empty or anything fails.
  Future<FirebaseRestoreResult> restoreFromServer() =>
      FirebaseSyncService.runExclusive(_restoreFromServer);

  static FirebaseRestoreResult _failure(String error) => FirebaseRestoreResult(
        categories: 0,
        warehouses: 0,
        companies: 0,
        customers: 0,
        products: 0,
        transactions: 0,
        error: error,
      );

  Future<FirebaseRestoreResult> _restoreFromServer() async {
    final queue = SyncQueueRepository();
    if (await queue.pendingCount() > 0) return _failure('pending_jobs');

    final pingErr = await _client.pingError();
    if (pingErr != null) return _failure(pingErr);

    try {
      final categories = await _fetchCollection(SyncEntityTypes.categories);
      final warehouses = await _fetchCollection(SyncEntityTypes.warehouses);
      final companies = await _fetchCollection(SyncEntityTypes.companies);
      final customers = await _fetchCollection(SyncEntityTypes.customers);
      final products = await _fetchCollection(SyncEntityTypes.products);
      final transactions = await _fetchCollection(SyncEntityTypes.transactions);
      final companyPayments =
          await _fetchCollection(SyncEntityTypes.companyPayments);
      final expenses = await _fetchCollection(SyncEntityTypes.expenses);
      final employees = await _fetchCollection(SyncEntityTypes.employees);
      final employeeWithdrawals =
          await _fetchCollection(SyncEntityTypes.employeeWithdrawals);
      final orders = await _fetchCollection(SyncEntityTypes.orders);
      final purchases = await _fetchCollection(SyncEntityTypes.purchases);

      if (categories.isEmpty &&
          warehouses.isEmpty &&
          companies.isEmpty &&
          products.isEmpty &&
          transactions.isEmpty &&
          customers.isEmpty &&
          companyPayments.isEmpty &&
          expenses.isEmpty &&
          employees.isEmpty &&
          employeeWithdrawals.isEmpty &&
          orders.isEmpty &&
          purchases.isEmpty) {
        return const FirebaseRestoreResult(
          categories: 0,
          warehouses: 0,
          companies: 0,
          customers: 0,
          products: 0,
          transactions: 0,
          companyPayments: 0,
          expenses: 0,
          employees: 0,
          employeeWithdrawals: 0,
          orders: 0,
          purchases: 0,
        );
      }

      final db = AppDatabase.instance;
      await db.execute('PRAGMA foreign_keys = OFF');
      var catN = 0;
      var whN = 0;
      var coN = 0;
      var cuN = 0;
      var prN = 0;
      var txN = 0;
      var payN = 0;
      var expN = 0;
      var empN = 0;
      var wdN = 0;
      var ordN = 0;
      var purN = 0;

      try {
        await db.transaction((txn) async {
          await _prepareLocalTablesForRestore(txn);
          catN = await _upsertCategories(txn, categories);
          whN = await _upsertWarehouses(txn, warehouses);
          coN = await _upsertCompanies(txn, companies);
          cuN = await _upsertCustomers(txn, customers);
          if (cuN == 0 && companies.isNotEmpty) {
            cuN = await _upsertCustomers(txn, companies);
          }
          prN = await _upsertProducts(txn, products);
          txN = await _upsertTransactions(txn, transactions);
          payN = await _upsertCompanyPayments(txn, companyPayments);
          empN = await _upsertEmployees(txn, employees);
          wdN = await _upsertEmployeeWithdrawals(txn, employeeWithdrawals);
          expN = await _upsertExpenses(txn, expenses);
          ordN = await _upsertOrders(txn, orders);
          purN = await _upsertPurchases(txn, purchases);
          await _rebuildInvoiceItemsFromMovements(txn);
          await _recalculateProductStock(txn);
          await CustomerRepositoryImpl.refreshBalancesFromOrders(txn);

          await txn.delete('sync_queue');
          await queue.clearRecordState(txn);
          for (final (type, records) in [
            (SyncEntityTypes.categories, categories),
            (SyncEntityTypes.warehouses, warehouses),
            (SyncEntityTypes.companies, companies),
            (SyncEntityTypes.customers, customers),
            (SyncEntityTypes.products, products),
            (SyncEntityTypes.transactions, transactions),
            (SyncEntityTypes.companyPayments, companyPayments),
            (SyncEntityTypes.expenses, expenses),
            (SyncEntityTypes.employees, employees),
            (SyncEntityTypes.employeeWithdrawals, employeeWithdrawals),
            (SyncEntityTypes.orders, orders),
            (SyncEntityTypes.purchases, purchases),
          ]) {
            await queue.seedRecordVersions(txn, type, records);
          }

          await _fixSequence(txn, 'categories');
          await _fixSequence(txn, 'warehouses');
          await _fixSequence(txn, 'suppliers');
          await _fixSequence(txn, 'customers');
          await _fixSequence(txn, 'products');
          await _fixSequence(txn, 'stock_movements');
          await _fixSequence(txn, 'company_payments');
          await _fixSequence(txn, 'company_payment_allocations');
          await _fixSequence(txn, 'employees');
          await _fixSequence(txn, 'employee_salaries');
          await _fixSequence(txn, 'expenses');
          await _fixSequence(txn, 'orders');
          await _fixSequence(txn, 'order_items');
          await _fixSequence(txn, 'purchases');
          await _fixSequence(txn, 'purchase_items');
        });
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
      }

      try {
        await FirebaseSyncService(queue: queue, client: _client).claimDevice();
      } catch (e) {
        debugPrint('[Restore] device claim skipped: $e');
      }

      debugPrint(
        '[Restore] ok categories=$catN warehouses=$whN companies=$coN '
        'customers=$cuN products=$prN transactions=$txN payments=$payN '
        'expenses=$expN employees=$empN withdrawals=$wdN '
        'orders=$ordN purchases=$purN',
      );

      return FirebaseRestoreResult(
        categories: catN,
        warehouses: whN,
        companies: coN,
        customers: cuN,
        products: prN,
        transactions: txN,
        companyPayments: payN,
        expenses: expN,
        employees: empN,
        employeeWithdrawals: wdN,
        orders: ordN,
        purchases: purN,
      );
    } catch (e, st) {
      debugPrint('[Restore] failed: $e\n$st');
      return FirebaseRestoreResult(
        categories: 0,
        warehouses: 0,
        companies: 0,
        customers: 0,
        products: 0,
        transactions: 0,
        companyPayments: 0,
        error: e.toString(),
      );
    }
  }

  /// Also supports restoring from a full RTDB export JSON
  /// (`{ "glassflow": { ... } }` or the glassflow object itself).
  Future<FirebaseRestoreResult> restoreFromExportMap(
    Map<String, dynamic> root,
  ) async {
    final glassflow = root['glassflow'] is Map
        ? Map<String, dynamic>.from(root['glassflow'] as Map)
        : root;
    try {
      final categories = _normalizeCollection(glassflow['categories']);
      final warehouses = _normalizeCollection(glassflow['warehouses']);
      final companies = _normalizeCollection(glassflow['companies']);
      final customers = _normalizeCollection(glassflow['customers']);
      final products = _normalizeCollection(glassflow['products']);
      final transactions = _normalizeCollection(glassflow['transactions']);
      final companyPayments = _normalizeCollection(
        glassflow['company_payments'] ?? glassflow['companyPayments'],
      );
      final expenses = _normalizeCollection(glassflow['expenses']);
      final employees = _normalizeCollection(glassflow['employees']);
      final employeeWithdrawals = _normalizeCollection(
        glassflow['employee_withdrawals'] ??
            glassflow['employeeWithdrawals'] ??
            glassflow['employee_salaries'],
      );
      final orders = _normalizeCollection(glassflow['orders']);
      final purchases = _normalizeCollection(glassflow['purchases']);

      final db = AppDatabase.instance;
      await db.execute('PRAGMA foreign_keys = OFF');
      var catN = 0;
      var whN = 0;
      var coN = 0;
      var cuN = 0;
      var prN = 0;
      var txN = 0;
      var payN = 0;
      var expN = 0;
      var empN = 0;
      var wdN = 0;
      var ordN = 0;
      var purN = 0;
      try {
        await db.transaction((txn) async {
          await _prepareLocalTablesForRestore(txn);
          catN = await _upsertCategories(txn, categories);
          whN = await _upsertWarehouses(txn, warehouses);
          coN = await _upsertCompanies(txn, companies);
          cuN = await _upsertCustomers(txn, customers);
          if (cuN == 0 && companies.isNotEmpty) {
            cuN = await _upsertCustomers(txn, companies);
          }
          prN = await _upsertProducts(txn, products);
          txN = await _upsertTransactions(txn, transactions);
          payN = await _upsertCompanyPayments(txn, companyPayments);
          empN = await _upsertEmployees(txn, employees);
          wdN = await _upsertEmployeeWithdrawals(txn, employeeWithdrawals);
          expN = await _upsertExpenses(txn, expenses);
          ordN = await _upsertOrders(txn, orders);
          purN = await _upsertPurchases(txn, purchases);
          await _rebuildInvoiceItemsFromMovements(txn);
          await _recalculateProductStock(txn);
          await CustomerRepositoryImpl.refreshBalancesFromOrders(txn);
          await txn.delete('sync_queue');
          await SyncQueueRepository().clearRecordState(txn);
          await _fixSequence(txn, 'categories');
          await _fixSequence(txn, 'warehouses');
          await _fixSequence(txn, 'suppliers');
          await _fixSequence(txn, 'customers');
          await _fixSequence(txn, 'products');
          await _fixSequence(txn, 'stock_movements');
          await _fixSequence(txn, 'company_payments');
          await _fixSequence(txn, 'company_payment_allocations');
          await _fixSequence(txn, 'employees');
          await _fixSequence(txn, 'employee_salaries');
          await _fixSequence(txn, 'expenses');
          await _fixSequence(txn, 'orders');
          await _fixSequence(txn, 'order_items');
          await _fixSequence(txn, 'purchases');
          await _fixSequence(txn, 'purchase_items');
        });
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
      }
      return FirebaseRestoreResult(
        categories: catN,
        warehouses: whN,
        companies: coN,
        customers: cuN,
        products: prN,
        transactions: txN,
        companyPayments: payN,
        expenses: expN,
        employees: empN,
        employeeWithdrawals: wdN,
        orders: ordN,
        purchases: purN,
      );
    } catch (e, st) {
      debugPrint('[Restore] export map failed: $e\n$st');
      return FirebaseRestoreResult(
        categories: 0,
        warehouses: 0,
        companies: 0,
        customers: 0,
        products: 0,
        transactions: 0,
        companyPayments: 0,
        error: e.toString(),
      );
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchCollection(
    String entityType,
  ) async {
    final raw = await _client.getRaw(entityType);
    return _normalizeCollection(raw);
  }

  /// Accepts RTDB map `{ "1": {...} }` or array `[null, {...}, ...]`.
  static Map<String, Map<String, dynamic>> _normalizeCollection(Object? raw) {
    final out = <String, Map<String, dynamic>>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is Map) {
          final m = Map<String, dynamic>.from(value);
          final id = '${m['id'] ?? key}';
          out[id] = m;
        }
      });
      return out;
    }
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final value = raw[i];
        if (value is Map) {
          final m = Map<String, dynamic>.from(value);
          final id = '${m['id'] ?? i}';
          out[id] = m;
        }
      }
    }
    return out;
  }

  Future<int> _upsertCategories(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items,
  ) async {
    var n = 0;
    for (final entry in items.entries) {
      final m = entry.value;
      final id = _int(m['id']) ?? int.tryParse(entry.key);
      final name = _str(m['name']);
      if (id == null || name == null || name.isEmpty) continue;
      await txn.insert(
        'categories',
        {
          'id': id,
          'name': name,
          'color': _str(m['color']),
          'sort_order': _int(m['sort_order']) ?? 0,
          'is_active': _flag(m['is_active'], 1),
          'created_at': _iso(m['created_at'] ?? m['createdAt']),
          'updated_at': _iso(m['updated_at'] ?? m['updatedAt']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      n++;
    }
    return n;
  }

  Future<int> _upsertWarehouses(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items,
  ) async {
    var n = 0;
    for (final entry in items.entries) {
      final m = entry.value;
      final id = _int(m['id']) ?? int.tryParse(entry.key);
      final name = _str(m['name']);
      if (id == null || name == null || name.isEmpty) continue;
      await txn.insert(
        'warehouses',
        {
          'id': id,
          'name': name,
          'address': _str(m['address']),
          'notes': _str(m['notes']),
          'is_active': _flag(m['is_active'], 1),
          'created_at': _iso(m['created_at'] ?? m['createdAt']),
          'updated_at': _iso(m['updated_at'] ?? m['updatedAt']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      n++;
    }
    return n;
  }

  Future<int> _upsertCompanies(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items,
  ) async {
    var n = 0;
    for (final entry in items.entries) {
      final m = entry.value;
      final id = _int(m['id']) ?? int.tryParse(entry.key);
      final name = _str(m['name']);
      if (id == null || name == null || name.isEmpty) continue;
      final aliases = m['source_aliases'];
      String? notes = _str(m['notes']);
      if ((notes == null || notes.isEmpty) && aliases is List && aliases.isNotEmpty) {
        notes = aliases.map((e) => '$e').where((e) => e.trim().isNotEmpty).join(' · ');
      }
      await txn.insert(
        'suppliers',
        {
          'id': id,
          'name': name,
          'phone': _str(m['phone']),
          'email': _str(m['email']),
          'address': _str(m['address']),
          'notes': notes,
          'is_archived': _flag(m['is_archived'], 0),
          'created_at': _iso(m['created_at'] ?? m['createdAt']),
          'updated_at': _iso(m['updated_at'] ?? m['updatedAt']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      n++;
    }
    return n;
  }

  Future<int> _upsertCustomers(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items,
  ) async {
    var n = 0;
    for (final entry in items.entries) {
      final m = entry.value;
      final id = _int(m['id']) ?? int.tryParse(entry.key);
      final name = _str(m['name']);
      if (id == null || name == null || name.isEmpty) continue;
      await txn.insert(
        'customers',
        {
          'id': id,
          'name': name,
          'phone': _str(m['phone']),
          'email': _str(m['email']),
          'address': _str(m['address']),
          'notes': _str(m['notes']),
          'outstanding_balance':
              _num(m['outstanding_balance'] ?? m['outstandingBalance']) ?? 0,
          'total_purchases':
              _num(m['total_purchases'] ?? m['totalPurchases']) ?? 0,
          'last_purchase_at': _nullableIso(
            m['last_purchase_at'] ?? m['lastPurchaseAt'],
          ),
          'is_archived': _flag(m['is_archived'] ?? m['isArchived'], 0),
          'created_at': _iso(m['created_at'] ?? m['createdAt']),
          'updated_at': _iso(m['updated_at'] ?? m['updatedAt']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      n++;
    }
    return n;
  }

  Future<int> _upsertProducts(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items,
  ) async {
    var n = 0;
    for (final entry in items.entries) {
      final m = entry.value;
      final id = _int(m['id']) ?? int.tryParse(entry.key);
      final name = _str(m['name']);
      final sku = _str(m['sku']);
      if (id == null || name == null || name.isEmpty) continue;
      final imageName = _str(m['imageName']);
      final imagePath = imageName != null
          ? p.join(AppDatabase.imagesDir.path, imageName)
          : _str(m['localPath']) ??
              _str(m['image_path']) ??
              _str(m['imagePath']);
      await txn.insert(
        'products',
        {
          'id': id,
          'name': name,
          'sku': sku ?? '',
          'category_id': _int(m['category_id']),
          'thickness': _num(m['thickness']),
          'standard_width':
              _num(m['standard_width'] ?? m['standardWidth']),
          'standard_height':
              _num(m['standard_height'] ?? m['standardHeight']),
          'unit_of_measure':
              _str(m['unit_of_measure'] ?? m['unitOfMeasure']) ?? 'sheet',
          'initial_stock':
              _num(m['initial_stock'] ?? m['initialStock']) ?? 0,
          'current_stock':
              _num(m['current_stock'] ?? m['currentStock']) ?? 0,
          'minimum_stock_alert':
              _num(m['minimum_stock_alert'] ?? m['minimumStockAlert']) ?? 0,
          'barcode': _str(m['barcode']),
          'brand': _str(m['brand']),
          'description': _str(m['description']),
          'expiration_date': _str(
            m['expiration_date'] ?? m['expirationDate'],
          ),
          'expiry_alert_value':
              _int(m['expiry_alert_value'] ?? m['expiryAlertValue']) ?? 1,
          'expiry_alert_unit':
              _str(m['expiry_alert_unit'] ?? m['expiryAlertUnit']) ?? 'month',
          'cost_price': _num(m['cost_price'] ?? m['costPrice']) ?? 0,
          'selling_price':
              _num(m['selling_price'] ?? m['sellingPrice']) ?? 0,
          'currency_id': _int(m['currency_id'] ?? m['currencyId']),
          'cost_currency_id':
              _int(m['cost_currency_id'] ?? m['costCurrencyId']),
          'supplier_id': _int(m['supplier_id'] ?? m['supplierId']),
          'image_path': imagePath,
          'track_stock_by_sheet': _flag(
            m['track_stock_by_sheet'] ?? m['trackStockBySheet'],
            1,
          ),
          'is_active': _flag(m['is_active'] ?? m['isActive'], 1),
          'is_archived': _flag(m['is_archived'] ?? m['isArchived'], 0),
          'notes': _str(m['notes']),
          'warehouse_id': _int(m['warehouse_id'] ?? m['warehouseId']),
          'unit_weight': _num(m['unit_weight'] ?? m['unitWeight']),
          'weight_unit': _str(m['weight_unit'] ?? m['weightUnit']) ?? 'kg',
          'parent_product_id':
              _int(m['parent_product_id'] ?? m['parentProductId']),
          'is_remnant': _flag(
            m['is_remnant'] ?? m['isRemnant'],
            _int(m['parent_product_id'] ?? m['parentProductId']) != null
                ? 1
                : 0,
          ),
          'created_at': _iso(m['created_at'] ?? m['createdAt']),
          'updated_at': _iso(m['updated_at'] ?? m['updatedAt']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      n++;
    }
    return n;
  }

  Future<int> _upsertTransactions(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items,
  ) async {
    var n = 0;
    for (final entry in items.entries) {
      final m = entry.value;
      final id = _int(m['id']) ?? int.tryParse(entry.key);
      final productId = _int(m['productId'] ?? m['product_id']);
      final qty = _num(m['quantity']);
      if (id == null || productId == null || qty == null) continue;

      var type = (_str(m['movementType'] ?? m['movement_type']) ?? 'adjustment')
          .toLowerCase();
      if (type == 'customer_sale') type = 'sale';

      // Server may store signed qty already (sale negative). Ensure outbound types
      // reduce stock if the payload was absolute.
      var quantity = qty;
      final outbound = {
        'sale',
        'damage',
        'waste',
        'return_out',
        'transfer',
      }.contains(type);
      if (outbound && quantity > 0) quantity = -quantity;
      if (!outbound &&
          (type == 'purchase' || type == 'return_in' || type == 'initial') &&
          quantity < 0) {
        quantity = quantity.abs();
      }

      final companyId = _int(m['companyId'] ?? m['company_id']);
      final noteParts = <String>[
        if (_str(m['notes']) != null) _str(m['notes'])!,
        if (_str(m['sourceSheet'] ?? m['source_sheet']) != null)
          'Sheet: ${_str(m['sourceSheet'] ?? m['source_sheet'])}',
      ];
      final explicitRefType =
          _str(m['referenceType'] ?? m['reference_type'] ?? m['sourceType']);
      final explicitRefId = _int(m['referenceId'] ?? m['reference_id']);

      await txn.insert(
        'stock_movements',
        {
          'id': id,
          'product_id': productId,
          'movement_type': type,
          'quantity': quantity,
          'balance_after': _num(m['balanceAfter'] ?? m['balance_after']) ?? 0,
          'reference_type': explicitRefType ??
              (companyId != null ? 'company' : null),
          'reference_id': explicitRefId ?? companyId,
          'notes': noteParts.isEmpty ? null : noteParts.join(' · '),
          'partner_name': _str(m['partnerName'] ?? m['partner_name']),
          'length_m': _num(m['lengthM'] ?? m['length_m']),
          'width_m': _num(m['widthM'] ?? m['width_m']),
          'area_m2': _num(m['areaM2'] ?? m['area_m2']),
          'parent_length_m':
              _num(m['parentLengthM'] ?? m['parent_length_m']),
          'parent_width_m':
              _num(m['parentWidthM'] ?? m['parent_width_m']),
          'broken_qty': _num(m['brokenQty'] ?? m['broken_qty']) ?? 0,
          'unit_price': _num(m['unitPrice'] ?? m['unit_price']),
          'paid_amount':
              _num(m['paidAmount'] ?? m['paid_amount']) ?? 0,
          'currency_id': _int(m['currencyId'] ?? m['currency_id']),
          'warehouse_id': _int(m['warehouseId'] ?? m['warehouse_id']),
          'employee_id': _int(m['employeeId'] ?? m['employee_id']),
          'order_id': _int(m['orderId'] ?? m['order_id']),
          'purchase_id': _int(m['purchaseId'] ?? m['purchase_id']),
          'created_by':
              _str(m['createdBy'] ?? m['created_by'] ?? m['updatedBy']) ??
                  'firebase_restore',
          'created_at': _movementCreatedAt(m),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      n++;
    }
    return n;
  }

  Future<int> _upsertCompanyPayments(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items,
  ) async {
    var n = 0;
    for (final entry in items.entries) {
      final m = entry.value;
      if (m['deleted'] == true) continue;
      final id = _int(m['id']) ?? int.tryParse(entry.key);
      final partnerType = _str(m['partnerType'] ?? m['partner_type']);
      final partnerId = _int(m['partnerId'] ?? m['partner_id']);
      final amount = _num(m['amount']);
      if (id == null ||
          partnerType == null ||
          partnerId == null ||
          amount == null) {
        continue;
      }
      final side = (_str(m['settlementSide'] ?? m['settlement_side']) ??
              'payable')
          .toLowerCase();
      await txn.insert(
        'company_payments',
        {
          'id': id,
          'partner_type': partnerType,
          'partner_id': partnerId,
          'partner_name': _str(m['partnerName'] ?? m['partner_name']),
          'amount': amount,
          'currency':
              _str(m['currency']) ?? AppConstants.defaultCurrencyCode,
          'paid_at': _iso(m['paidAt'] ?? m['paid_at']),
          'payment_method':
              _str(m['paymentMethod'] ?? m['payment_method']) ?? 'cash',
          'settlement_side':
              side == 'receivable' ? 'receivable' : 'payable',
          'notes': _str(m['notes']),
          'is_voided': _flag(m['isVoided'] ?? m['is_voided'], 0),
          'created_at': _iso(m['createdAt'] ?? m['created_at']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'company_payment_allocations',
        where: 'payment_id = ?',
        whereArgs: [id],
      );
      final rawAllocs = m['allocations'];
      if (rawAllocs is List) {
        for (final raw in rawAllocs) {
          if (raw is! Map) continue;
          final a = Map<String, dynamic>.from(raw);
          final movementId = _int(a['movementId'] ?? a['movement_id']);
          final purchaseId = _int(a['purchaseId'] ?? a['purchase_id']);
          final orderId = _int(a['orderId'] ?? a['order_id']);
          final allocAmount = _num(a['amount']);
          if (allocAmount == null) continue;
          if (movementId == null && purchaseId == null && orderId == null) {
            continue;
          }
          await txn.insert('company_payment_allocations', {
            if (_int(a['id']) != null) 'id': _int(a['id']),
            'payment_id': id,
            'movement_id': movementId,
            'purchase_id': purchaseId,
            'order_id': orderId,
            'amount': allocAmount,
          });
        }
      }
      n++;
    }
    return n;
  }

  Future<int> _upsertEmployees(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items,
  ) async {
    var n = 0;
    for (final entry in items.entries) {
      final m = entry.value;
      if (m['deleted'] == true) continue;
      final id = _int(m['id']) ?? int.tryParse(entry.key);
      final name = _str(m['fullName'] ?? m['full_name']);
      if (id == null || name == null || name.isEmpty) continue;
      await txn.insert(
        'employees',
        {
          'id': id,
          'code': _str(m['code']),
          'full_name': name,
          'phone': _str(m['phone']),
          'email': _str(m['email']),
          'role': _str(m['role']),
          'department': _str(m['department']),
          'hire_date': _nullableIso(m['hireDate'] ?? m['hire_date']),
          'base_salary': _num(m['baseSalary'] ?? m['base_salary']) ?? 0,
          'salary_currency':
              _str(m['salaryCurrency'] ?? m['salary_currency']) ??
                  AppConstants.defaultCurrencyCode,
          'payment_cycle':
              _str(m['paymentCycle'] ?? m['payment_cycle']) ?? 'monthly',
          'bank_account': _str(m['bankAccount'] ?? m['bank_account']),
          'address': _str(m['address']),
          'notes': _str(m['notes']),
          'is_active': _flag(m['isActive'] ?? m['is_active'], 1),
          'created_at': _iso(m['createdAt'] ?? m['created_at']),
          'updated_at': _iso(m['updatedAt'] ?? m['updated_at']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      n++;
    }
    return n;
  }

  Future<int> _upsertEmployeeWithdrawals(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items,
  ) async {
    var n = 0;
    for (final entry in items.entries) {
      final m = entry.value;
      if (m['deleted'] == true) continue;
      final id = _int(m['id']) ?? int.tryParse(entry.key);
      final employeeId = _int(m['employeeId'] ?? m['employee_id']);
      final amount = _num(m['amount']);
      if (id == null || employeeId == null || amount == null) continue;
      await txn.insert(
        'employee_salaries',
        {
          'id': id,
          'employee_id': employeeId,
          'period_label': _str(m['label'] ?? m['period_label']),
          'amount': amount,
          'currency':
              _str(m['currency']) ?? AppConstants.defaultCurrencyCode,
          'paid_at': _iso(m['withdrawnAt'] ?? m['paid_at'] ?? m['paidAt']),
          'payment_method':
              _str(m['paymentMethod'] ?? m['payment_method']),
          'notes': _str(m['notes']),
          'created_at': _iso(m['createdAt'] ?? m['created_at']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      n++;
    }
    return n;
  }

  Future<int> _upsertExpenses(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items,
  ) async {
    var n = 0;
    for (final entry in items.entries) {
      final m = entry.value;
      if (m['deleted'] == true) continue;
      final id = _int(m['id']) ?? int.tryParse(entry.key);
      final category = _str(m['category']);
      final amount = _num(m['amount']);
      if (id == null || category == null || amount == null) continue;
      await txn.insert(
        'expenses',
        {
          'id': id,
          'category': category,
          'amount': amount,
          'currency_id': _int(m['currencyId'] ?? m['currency_id']),
          'currency_code': _str(m['currencyCode'] ?? m['currency_code']),
          'exchange_rate':
              _num(m['exchangeRate'] ?? m['exchange_rate']) ?? 1,
          'payee': _str(m['payee']),
          'expense_date': _iso(m['expenseDate'] ?? m['expense_date']),
          'note': _str(m['note']),
          'receipt_path': _str(m['receiptPath'] ?? m['receipt_path']),
          'created_at': _iso(m['createdAt'] ?? m['created_at']),
          'updated_at': _iso(m['updatedAt'] ?? m['updated_at']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      n++;
    }
    return n;
  }

  Future<int> _upsertOrders(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items,
  ) async {
    return _upsertInvoiceLike(
      txn,
      items,
      table: 'orders',
      linkMovements: (id, movementIds) async {
        for (final mid in movementIds) {
          await txn.update(
            'stock_movements',
            {'order_id': id},
            where: 'id = ?',
            whereArgs: [mid],
          );
        }
      },
    );
  }

  Future<int> _upsertPurchases(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items,
  ) async {
    return _upsertInvoiceLike(
      txn,
      items,
      table: 'purchases',
      linkMovements: (id, movementIds) async {
        for (final mid in movementIds) {
          await txn.update(
            'stock_movements',
            {'purchase_id': id},
            where: 'id = ?',
            whereArgs: [mid],
          );
        }
      },
    );
  }

  Future<int> _upsertInvoiceLike(
    DatabaseExecutor txn,
    Map<String, Map<String, dynamic>> items, {
    required String table,
    required Future<void> Function(int id, List<int> movementIds)
        linkMovements,
  }) async {
    var n = 0;
    for (final entry in items.entries) {
      final m = entry.value;
      if (m['deleted'] == true) continue;
      final id = _int(m['id']) ?? int.tryParse(entry.key);
      final invoice = _str(m['invoiceNumber'] ?? m['invoice_number']);
      if (id == null || invoice == null || invoice.isEmpty) continue;
      await txn.insert(
        table,
        {
          'id': id,
          'invoice_number': invoice,
          'partner_type': _str(m['partnerType'] ?? m['partner_type']),
          'partner_id': _int(m['partnerId'] ?? m['partner_id']),
          'partner_name': _str(m['partnerName'] ?? m['partner_name']),
          'currency_id': _int(m['currencyId'] ?? m['currency_id']),
          'currency_code': _str(m['currencyCode'] ?? m['currency_code']),
          'subtotal': _num(m['subtotal']) ?? 0,
          'discount': _num(m['discount']) ?? 0,
          'total': _num(m['total']) ?? 0,
          'amount_paid': _num(m['amountPaid'] ?? m['amount_paid']) ?? 0,
          'payment_status':
              _str(m['paymentStatus'] ?? m['payment_status']) ?? 'paid',
          'status': _str(m['status']) ?? 'completed',
          'notes': _str(m['notes']),
          'created_at': _iso(m['createdAt'] ?? m['created_at']),
          'updated_at': _iso(m['updatedAt'] ?? m['updated_at']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final rawIds = m['movementIds'] ?? m['movement_ids'];
      if (rawIds is List) {
        final ids = <int>[
          for (final v in rawIds)
            if (_int(v) != null) _int(v)!,
        ];
        if (ids.isNotEmpty) await linkMovements(id, ids);
      }
      n++;
    }
    return n;
  }

  /// Clears synced business tables so fetch replaces local state completely.
  Future<void> _prepareLocalTablesForRestore(DatabaseExecutor txn) async {
    const tables = <String>[
      'order_items',
      'purchase_items',
      'company_payment_allocations',
      'company_payments',
      'employee_salaries',
      'stock_movements',
      'orders',
      'purchases',
      'expenses',
      'employees',
      'products',
      'customers',
      'suppliers',
      'categories',
      'warehouses',
      'sync_queue',
    ];
    for (final table in tables) {
      try {
        await txn.delete(table);
      } catch (e) {
        debugPrint('[Restore] skip clear $table: $e');
      }
    }
  }

  /// Rebuilds invoice line tables from linked stock movements after restore.
  Future<void> _rebuildInvoiceItemsFromMovements(DatabaseExecutor txn) async {
    await txn.delete('order_items');
    await txn.delete('purchase_items');

    final productNames = <int, String>{};
    final products = await txn.query('products', columns: ['id', 'name']);
    for (final p in products) {
      final id = p['id'] as int?;
      final name = p['name'] as String?;
      if (id != null && name != null) productNames[id] = name;
    }

    final orderMoves = await txn.query(
      'stock_movements',
      where: 'order_id IS NOT NULL',
    );
    for (final m in orderMoves) {
      final orderId = m['order_id'] as int?;
      final productId = m['product_id'] as int?;
      if (orderId == null || productId == null) continue;
      final qty = ((m['quantity'] as num?)?.toDouble() ?? 0).abs();
      final unitPrice = (m['unit_price'] as num?)?.toDouble() ?? 0;
      await txn.insert('order_items', {
        'order_id': orderId,
        'product_id': productId,
        'product_name': productNames[productId] ?? 'Product #$productId',
        'quantity': qty,
        'unit_price': unitPrice,
        'line_total': qty * unitPrice,
        'length_m': m['length_m'],
        'width_m': m['width_m'],
        'area_m2': m['area_m2'],
        'paid_amount': (m['paid_amount'] as num?)?.toDouble() ?? 0,
        'currency_id': m['currency_id'],
        'movement_id': m['id'],
        'warehouse_id': m['warehouse_id'],
      });
    }

    final purchaseMoves = await txn.query(
      'stock_movements',
      where: 'purchase_id IS NOT NULL',
    );
    for (final m in purchaseMoves) {
      final purchaseId = m['purchase_id'] as int?;
      final productId = m['product_id'] as int?;
      if (purchaseId == null || productId == null) continue;
      final qty = ((m['quantity'] as num?)?.toDouble() ?? 0).abs();
      final unitPrice = (m['unit_price'] as num?)?.toDouble() ?? 0;
      await txn.insert('purchase_items', {
        'purchase_id': purchaseId,
        'product_id': productId,
        'product_name': productNames[productId] ?? 'Product #$productId',
        'quantity': qty,
        'unit_price': unitPrice,
        'line_total': qty * unitPrice,
        'length_m': m['length_m'],
        'width_m': m['width_m'],
        'paid_amount': (m['paid_amount'] as num?)?.toDouble() ?? 0,
        'currency_id': m['currency_id'],
        'movement_id': m['id'],
        'warehouse_id': m['warehouse_id'],
      });
    }
  }

  Future<void> _recalculateProductStock(DatabaseExecutor txn) async {
    await txn.execute('''
      UPDATE products
      SET current_stock = COALESCE((
        SELECT SUM(quantity) FROM stock_movements
        WHERE stock_movements.product_id = products.id
      ), current_stock),
      updated_at = datetime('now')
      WHERE EXISTS (
        SELECT 1 FROM stock_movements sm WHERE sm.product_id = products.id
      )
    ''');
  }

  static String _movementCreatedAt(Map<String, dynamic> m) {
    final shamsi = _str(m['transactionDate'] ?? m['transaction_date']);
    if (shamsi != null) {
      final dt = ShamsiDates.tryParse(shamsi);
      if (dt != null) return dt.toIso8601String();
    }
    return _iso(m['createdAt'] ?? m['created_at']);
  }

  Future<void> _fixSequence(DatabaseExecutor txn, String table) async {
    final rows = await txn.rawQuery('SELECT MAX(id) AS m FROM $table');
    final maxRaw = rows.isEmpty ? null : rows.first['m'];
    final maxId =
        maxRaw is num ? maxRaw.toInt() : int.tryParse('$maxRaw') ?? 0;
    if (maxId <= 0) return;
    try {
      await txn.delete(
        'sqlite_sequence',
        where: 'name = ?',
        whereArgs: [table],
      );
      await txn.insert('sqlite_sequence', {'name': table, 'seq': maxId});
    } catch (_) {}
  }

  static int? _int(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  static double? _num(Object? v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  static int _flag(Object? v, int fallback) {
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v.toInt() == 0 ? 0 : 1;
    if (v is String) {
      final t = v.trim().toLowerCase();
      if (t == 'true' || t == '1') return 1;
      if (t == 'false' || t == '0') return 0;
    }
    return fallback;
  }

  static String _iso(Object? v) {
    if (v is String && v.trim().isNotEmpty) {
      return DateTime.tryParse(v)?.toIso8601String() ??
          DateTime.now().toIso8601String();
    }
    return DateTime.now().toIso8601String();
  }

  static String? _nullableIso(Object? v) {
    if (v == null) return null;
    if (v is String && v.trim().isEmpty) return null;
    if (v is String) {
      return DateTime.tryParse(v)?.toIso8601String();
    }
    return null;
  }
}
