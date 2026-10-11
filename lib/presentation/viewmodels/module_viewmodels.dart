import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/database/app_database.dart';
import '../../core/database/data_transfer.dart';
import '../../core/di/service_locator.dart';
import '../../core/sync/converted_json_import_service.dart';
import '../../core/sync/data_wipe_service.dart';
import '../../core/sync/firebase_restore_service.dart';
import '../../core/sync/firebase_rtdb_client.dart';
import '../../core/sync/firebase_sync_service.dart';
import '../../core/sync/sync_backfill.dart';
import '../../core/sync/sync_outbox.dart';
import '../../data/models/category_model.dart';
import '../../data/models/currency_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/stock_movement_model.dart';
import '../../data/models/supplier_model.dart';
import '../../domain/repositories/customer_repository.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../domain/repositories/lookup_repository.dart';
import '../../domain/repositories/supplier_repository.dart';

class InventoryViewModel extends ChangeNotifier {
  InventoryViewModel({
    InventoryRepository? repo,
    LookupRepository? lookups,
  })  : _repo = repo ?? ServiceLocator.instance.inventory,
        _lookups = lookups ?? ServiceLocator.instance.lookups;
  final InventoryRepository _repo;
  final LookupRepository _lookups;

  bool _disposed = false;

  bool loading = true;
  String? error;
  String search = '';
  int? categoryId;

  /// `true` = remnants, `false` = full sheets, `null` = all.
  bool? remnantsOnly;
  int page = 1;
  int pageSize = 20;
  int total = 0;
  StockSummary summary = const StockSummary();
  List<ProductModel> items = const [];
  List<CategoryModel> categories = const [];
  List<StockMovementModel> movements = const [];
  List<StockMovementModel> waste = const [];
  WarehouseCapacity capacity = const WarehouseCapacity();

  bool _loadedOnce = false;
  int _loadSeq = 0;
  Timer? _searchDebounce;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (_disposed) return;
    final seq = ++_loadSeq;
    // Full-page loader only on first load; later reloads keep the table
    // (and its search field focus) mounted.
    if (!_loadedOnce) {
      loading = true;
      _notify();
    }
    error = null;
    final cats = await _lookups.getCategories();
    if (_disposed || seq != _loadSeq) return;
    cats.when(
      success: (v) {
        categories = v;
        // null categoryId = All categories.
        if (categories.isEmpty) {
          categoryId = null;
        } else if (categoryId != null &&
            categories.every((c) => c.id != categoryId)) {
          categoryId = null;
        }
      },
      failure: (_) {},
    );

    final s = await _repo.getStockSummary();
    if (_disposed || seq != _loadSeq) return;
    final list = await _repo.listStock(
      InventoryStockQuery(
        search: search,
        categoryId: categoryId,
        remnantsOnly: remnantsOnly,
        page: page,
        pageSize: pageSize,
      ),
    );
    if (_disposed || seq != _loadSeq) return;
    final cap = await _repo.getWarehouseCapacity();
    if (_disposed || seq != _loadSeq) return;
    s.when(success: (v) => summary = v, failure: (_) {});
    list.when(
      success: (v) {
        items = v.items;
        total = v.total;
      },
      failure: (f) => error = f.message,
    );
    movements = const [];
    waste = const [];
    cap.when(success: (v) => capacity = v, failure: (_) {});
    loading = false;
    _loadedOnce = true;
    _notify();
  }

  void setSearch(String v) {
    if (_disposed) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (_disposed) return;
      search = v;
      page = 1;
      load();
    });
  }

  void setRemnantsFilter(bool? value) {
    if (_disposed) return;
    remnantsOnly = value;
    page = 1;
    load();
  }

  void setCategoryFilter(int? id) {
    if (_disposed) return;
    categoryId = id;
    page = 1;
    load();
  }

  Future<void> reloadCategories() async {
    final cats = await _lookups.getCategories();
    if (_disposed) return;
    cats.when(success: (v) => categories = v, failure: (_) {});
    if (categories.isEmpty) {
      categoryId = null;
    } else if (categoryId != null &&
        categories.every((c) => c.id != categoryId)) {
      categoryId = null;
    }
    _notify();
    await load();
  }

  void setPage(int value) {
    if (_disposed) return;
    page = value;
    load();
  }

  void setPageSize(int value) {
    if (_disposed) return;
    if (pageSize == value) return;
    pageSize = value;
    final pages = total == 0 ? 1 : (total / pageSize).ceil();
    if (page > pages) page = pages.clamp(1, pages);
    load();
  }

  Future<String?> recordMovement({
    required int productId,
    required StockMovementType type,
    required double quantity,
    String? notes,
    String? referenceType,
    int? referenceId,
    String? partnerName,
    double? lengthM,
    double? widthM,
    double brokenQty = 0,
    double? unitPrice,
    int? currencyId,
    DateTime? createdAt,
  }) async {
    final r = await _repo.recordMovement(
      productId: productId,
      type: type,
      quantity: quantity,
      notes: notes,
      referenceType: referenceType,
      referenceId: referenceId,
      partnerName: partnerName,
      lengthM: lengthM,
      widthM: widthM,
      brokenQty: brokenQty,
      unitPrice: unitPrice,
      currencyId: currencyId,
      createdAt: createdAt,
    );
    return r.when(
      success: (_) {
        load();
        return null;
      },
      failure: (f) => f.message,
    );
  }

  Future<String?> deleteProduct(int productId) async {
    final r = await ServiceLocator.instance.products.delete(productId);
    return r.when(
      success: (_) {
        load();
        return null;
      },
      failure: (f) => f.message,
    );
  }

  Future<String?> deleteMovement(int movementId) async {
    final r = await _repo.deleteMovement(movementId);
    return r.when(
      success: (_) {
        load();
        return null;
      },
      failure: (f) => f.message,
    );
  }

  Future<String?> updateMovement({
    required int movementId,
    required double quantity,
    String? notes,
    String? partnerName,
    double? lengthM,
    double? widthM,
    double brokenQty = 0,
    double? unitPrice,
    double? paidAmount,
    int? currencyId,
    int? warehouseId,
    DateTime? createdAt,
  }) async {
    final r = await _repo.updateMovement(
      movementId: movementId,
      quantity: quantity,
      notes: notes,
      partnerName: partnerName,
      lengthM: lengthM,
      widthM: widthM,
      brokenQty: brokenQty,
      unitPrice: unitPrice,
      paidAmount: paidAmount,
      currencyId: currencyId,
      warehouseId: warehouseId,
      createdAt: createdAt,
    );
    return r.when(
      success: (_) {
        load();
        return null;
      },
      failure: (f) => f.message,
    );
  }
}

class CustomersViewModel extends ChangeNotifier {
  CustomersViewModel({CustomerRepository? repo})
      : _repo = repo ?? ServiceLocator.instance.customers;
  final CustomerRepository _repo;

  bool loading = true;
  String? error;
  String search = '';
  int page = 1;
  int pageSize = 20;
  int total = 0;
  bool includeArchived = false;
  List<CustomerModel> items = const [];
  CustomerModel? selected;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    final r = await _repo.query(
      search: search,
      page: page,
      pageSize: pageSize,
      includeArchived: includeArchived,
    );
    r.when(
      success: (d) {
        items = d.items;
        total = d.total;
      },
      failure: (f) => error = f.message,
    );
    loading = false;
    notifyListeners();
  }

  void setSearch(String v) {
    search = v;
    page = 1;
    load();
  }

  void setPage(int value) {
    page = value;
    load();
  }

  void setPageSize(int value) {
    if (pageSize == value) return;
    pageSize = value;
    final pages = total == 0 ? 1 : (total / pageSize).ceil();
    if (page > pages) page = pages.clamp(1, pages);
    load();
  }

  Future<String?> save(CustomerModel model, {required bool isNew}) async {
    final r = isNew ? await _repo.create(model) : await _repo.update(model);
    return r.when(
      success: (_) {
        load();
        return null;
      },
      failure: (f) => f.message,
    );
  }

  Future<String?> archive(int id) async {
    final r = await _repo.archive(id);
    return r.when(
      success: (_) {
        load();
        return null;
      },
      failure: (f) => f.message,
    );
  }

  Future<String?> restore(int id) async {
    final r = await _repo.restore(id);
    return r.when(
      success: (_) {
        load();
        return null;
      },
      failure: (f) => f.message,
    );
  }

  Future<String?> setActive(int id, {required bool active}) {
    return active ? restore(id) : archive(id);
  }

  Future<String?> delete(int id) async {
    final r = await _repo.delete(id);
    return r.when(
      success: (_) {
        load();
        return null;
      },
      failure: (f) => f.message,
    );
  }
}

class SuppliersViewModel extends ChangeNotifier {
  SuppliersViewModel({SupplierRepository? repo})
      : _repo = repo ?? ServiceLocator.instance.suppliers;
  final SupplierRepository _repo;

  bool loading = true;
  String? error;
  String search = '';
  int page = 1;
  int pageSize = 20;
  int total = 0;
  bool includeArchived = false;
  List<SupplierModel> items = const [];

  Future<void> load() async {
    loading = true;
    notifyListeners();
    final r = await _repo.query(
      search: search,
      page: page,
      pageSize: pageSize,
      includeArchived: includeArchived,
    );
    r.when(
      success: (d) {
        items = d.items;
        total = d.total;
      },
      failure: (f) => error = f.message,
    );
    loading = false;
    notifyListeners();
  }

  void setSearch(String v) {
    search = v;
    page = 1;
    load();
  }

  void setPage(int value) {
    page = value;
    load();
  }

  void setPageSize(int value) {
    if (pageSize == value) return;
    pageSize = value;
    final pages = total == 0 ? 1 : (total / pageSize).ceil();
    if (page > pages) page = pages.clamp(1, pages);
    load();
  }

  Future<String?> save(SupplierModel model, {required bool isNew}) async {
    final r = isNew ? await _repo.create(model) : await _repo.update(model);
    return r.when(
      success: (_) {
        load();
        return null;
      },
      failure: (f) => f.message,
    );
  }

  Future<String?> archive(int id) async {
    final r = await _repo.archive(id);
    return r.when(
      success: (_) {
        load();
        return null;
      },
      failure: (f) => f.message,
    );
  }

  Future<String?> restore(int id) async {
    final r = await _repo.restore(id);
    return r.when(
      success: (_) {
        load();
        return null;
      },
      failure: (f) => f.message,
    );
  }

  Future<String?> setActive(int id, {required bool active}) {
    return active ? restore(id) : archive(id);
  }

  Future<String?> delete(int id) async {
    final r = await _repo.delete(id);
    return r.when(
      success: (_) {
        load();
        return null;
      },
      failure: (f) => f.message,
    );
  }
}

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({LookupRepository? repo})
      : _repo = repo ?? ServiceLocator.instance.lookups;
  final LookupRepository _repo;

  bool loading = true;
  bool busy = false;
  String? error;
  String? message;
  Map<String, String> settings = {};
  List<CurrencyModel> currencies = const [];

  Future<void> load() async {
    loading = true;
    notifyListeners();
    final s = await _repo.getAllSettings();
    final c = await _repo.getCurrencies();
    s.when(success: (v) => settings = v, failure: (f) => error = f.message);
    c.when(success: (v) => currencies = v, failure: (_) {});
    loading = false;
    notifyListeners();
  }

  String get(String key, [String fallback = '']) => settings[key] ?? fallback;

  Future<void> set(String key, String value) async {
    settings = {...settings, key: value};
    notifyListeners();
    await _repo.setSetting(key, value);
  }

  Future<String?> backup() async {
    busy = true;
    message = null;
    error = null;
    notifyListeners();
    try {
      final file = await AppDatabase.backup();
      busy = false;
      message = file.path;
      notifyListeners();
      return null;
    } catch (e) {
      busy = false;
      error = e.toString();
      notifyListeners();
      return error;
    }
  }

  Future<String?> exportDatabaseTo(String destPath) async {
    busy = true;
    message = null;
    error = null;
    notifyListeners();
    try {
      final file = await AppDatabase.backupTo(destPath);
      busy = false;
      message = file.path;
      notifyListeners();
      return null;
    } catch (e) {
      busy = false;
      error = e.toString();
      notifyListeners();
      return error;
    }
  }

  Future<String?> exportExcelTo(String destPath) async {
    busy = true;
    message = null;
    error = null;
    notifyListeners();
    try {
      final file = await DataTransfer.exportExcel(destPath);
      busy = false;
      message = file.path;
      notifyListeners();
      return null;
    } catch (e) {
      busy = false;
      error = e.toString();
      notifyListeners();
      return error;
    }
  }

  Future<String?> restore(String path) async {
    busy = true;
    message = null;
    error = null;
    notifyListeners();
    try {
      await AppDatabase.restore(File(path));
      busy = false;
      message = 'Database restored successfully.';
      notifyListeners();
      return null;
    } catch (e) {
      busy = false;
      error = e.toString();
      notifyListeners();
      return error;
    }
  }

  /// Pull products, movements, partners, etc. from Firebase into local SQLite.
  Future<String?> restoreFromServer() async {
    busy = true;
    message = null;
    error = null;
    notifyListeners();
    try {
      // Send anything still queued first: fetch replaces local data, so it
      // refuses to run while jobs are pending.
      await FirebaseSyncService().syncPending();
      final result = await FirebaseRestoreService().restoreFromServer();
      if (!result.ok) {
        busy = false;
        error = result.error;
        notifyListeners();
        return error;
      }
      if (result.isEmpty) {
        busy = false;
        error = 'empty';
        message = '0';
        notifyListeners();
        return 'empty';
      }
      await set(
        'last_cloud_restore_at',
        DateTime.now().toIso8601String(),
      );
      busy = false;
      message =
          '${result.products}|${result.transactions}|${result.customers}|'
          '${result.companies}|${result.warehouses}|${result.categories}|'
          '${result.companyPayments}|${result.expenses}|${result.employees}|'
          '${result.employeeWithdrawals}|${result.orders}|${result.purchases}|'
          '${result.total}';
      notifyListeners();
      return null;
    } catch (e) {
      busy = false;
      error = e.toString();
      notifyListeners();
      return error;
    }
  }

  /// Queue every local business row and upload the full outbox to the server.
  Future<String?> pushAllToServer() async {
    busy = true;
    message = null;
    error = null;
    notifyListeners();
    try {
      final sync = FirebaseSyncService();
      final queued = await SyncBackfill.enqueueAllLocalData(notifyOutbox: false);
      // Push everything deliberately rebuilds the server copy from this PC.
      try {
        if (await FirebaseSyncService.onlineEnabled() &&
            await sync.queue.pendingCount() > 0 &&
            await FirebaseRtdbClient().ping()) {
          await sync.claimDevice();
        }
      } catch (_) {}
      final result = await sync.syncAllPending();
      if (result.disabled || result.stoppedTemporarily) {
        busy = false;
        error = result.error ?? 'offline';
        notifyListeners();
        return error;
      }
      if (queued == 0 && result.processed == 0) {
        busy = false;
        error = 'empty';
        message = '0';
        notifyListeners();
        return 'empty';
      }
      await set(
        'last_cloud_push_at',
        DateTime.now().toIso8601String(),
      );
      // Refresh Sync Center counters without triggering another push mid-run.
      SyncOutbox.revision.value = SyncOutbox.revision.value + 1;
      busy = false;
      message =
          '$queued|${result.synced}|${result.failed}|${result.conflicts}|'
          '${result.processed}';
      notifyListeners();
      return result.failed > 0 || result.conflicts > 0 ? 'partial' : null;
    } catch (e) {
      busy = false;
      error = e.toString();
      notifyListeners();
      return error;
    }
  }

  /// Import converted Excel JSON (`accounts` + `transactions`) into SQLite.
  /// Also accepts a full Firebase RTDB export (`glassflow: { products, ... }`).
  Future<String?> importConvertedJson(String path) async {
    busy = true;
    message = null;
    error = null;
    notifyListeners();
    try {
      final file = File(path);
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        busy = false;
        error = 'Invalid JSON root (expected object).';
        notifyListeners();
        return error;
      }
      final root = Map<String, dynamic>.from(decoded);
      final looksLikeFirebaseExport = root.containsKey('glassflow') ||
          root.containsKey('products') ||
          root.containsKey('transactions') ||
          root.containsKey('companies') ||
          root.containsKey('customers');

      if (looksLikeFirebaseExport && !root.containsKey('accounts')) {
        final result =
            await FirebaseRestoreService().restoreFromExportMap(root);
        if (!result.ok) {
          busy = false;
          error = result.error;
          notifyListeners();
          return error;
        }
        if (result.isEmpty) {
          busy = false;
          error = 'empty';
          message = '0';
          notifyListeners();
          return 'empty';
        }
        await set(
          'last_cloud_restore_at',
          DateTime.now().toIso8601String(),
        );
        busy = false;
        message =
            '${result.products}|${result.transactions}|${result.customers}|'
            '${result.companies}|${result.warehouses}|${result.categories}|'
            '${result.companyPayments}|${result.expenses}|${result.employees}|'
            '${result.employeeWithdrawals}|${result.orders}|${result.purchases}|'
            '${result.total}';
        notifyListeners();
        return null;
      }

      final result =
          await ConvertedJsonImportService().importFile(file);
      if (!result.ok) {
        busy = false;
        error = result.error;
        notifyListeners();
        return error;
      }
      if (result.isEmpty) {
        busy = false;
        error = 'empty';
        message = '0';
        notifyListeners();
        return 'empty';
      }
      await set(
        'last_converted_import_at',
        DateTime.now().toIso8601String(),
      );
      busy = false;
      message =
          '${result.customers}|${result.products}|${result.movements}|'
          '${result.total}';
      notifyListeners();
      return null;
    } catch (e) {
      busy = false;
      error = e.toString();
      notifyListeners();
      return error;
    }
  }

  Future<String?> clearServerData() async {
    busy = true;
    message = null;
    error = null;
    notifyListeners();
    try {
      final err = await DataWipeService().clearServerData();
      busy = false;
      if (err != null) {
        error = err;
        notifyListeners();
        return err;
      }
      message = 'server_cleared';
      notifyListeners();
      return null;
    } catch (e) {
      busy = false;
      error = e.toString();
      notifyListeners();
      return error;
    }
  }

  Future<String?> clearOfflineData() async {
    busy = true;
    message = null;
    error = null;
    notifyListeners();
    try {
      final err = await DataWipeService().clearOfflineData();
      busy = false;
      if (err != null) {
        error = err;
        notifyListeners();
        return err;
      }
      message = 'offline_cleared';
      notifyListeners();
      return null;
    } catch (e) {
      busy = false;
      error = e.toString();
      notifyListeners();
      return error;
    }
  }

  Future<String?> importSpreadsheet(String path) async {
    busy = true;
    message = null;
    error = null;
    notifyListeners();
    try {
      final result = await DataTransfer.importSpreadsheet(path);
      // Queue refreshed local rows (incl. customers + loan balances) for sync.
      if (result.importedRows > 0) {
        await SyncBackfill.enqueueAllLocalData(notifyOutbox: false);
      }
      final s = await _repo.getAllSettings();
      final c = await _repo.getCurrencies();
      s.when(success: (v) => settings = v, failure: (_) {});
      c.when(success: (v) => currencies = v, failure: (_) {});
      busy = false;
      message =
          '${result.importedRows}|${result.tables.isEmpty ? '-' : result.tables.join(', ')}';
      if (result.importedRows == 0) {
        error = 'No importable rows were found.';
        notifyListeners();
        return error;
      }
      notifyListeners();
      return null;
    } catch (e) {
      busy = false;
      error = e.toString();
      notifyListeners();
      return error;
    }
  }
}
