import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';
import '../utils/product_identity.dart';
import '../utils/shamsi_dates.dart';

/// Result of importing [haji_hamidullah_converted.json]-style seed data.
class ConvertedJsonImportResult {
  const ConvertedJsonImportResult({
    required this.customers,
    required this.products,
    required this.movements,
    required this.warehouseId,
    this.error,
  });

  final int customers;
  final int products;
  final int movements;
  final int warehouseId;
  final String? error;

  int get total => customers + products + movements;
  bool get ok => error == null;
  bool get isEmpty => total == 0 && error == null;
}

/// Imports the converted Excel→JSON format used for Haji Hamidullah seed data.
///
/// Expected shape:
/// ```json
/// {
///   "accounts": { "<name>": { "id", "name", "type": "customer" } },
///   "transactions": [
///     {
///       "id", "date": "1405/5/2", "movementType": "purchase|sale|customer_sale",
///       "productName", "quantity", "width", "length", "area", "notes",
///       "accountId?", "accountName?", "sheet?", "source?"
///     }
///   ]
/// }
/// ```
class ConvertedJsonImportService {
  static const defaultWarehouseName = 'انبار اصلی';

  Future<ConvertedJsonImportResult> importFile(File file) async {
    try {
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return const ConvertedJsonImportResult(
          customers: 0,
          products: 0,
          movements: 0,
          warehouseId: 0,
          error: 'Invalid JSON root (expected object).',
        );
      }
      return importMap(Map<String, dynamic>.from(decoded));
    } catch (e, st) {
      debugPrint('[ConvertedImport] file failed: $e\n$st');
      return ConvertedJsonImportResult(
        customers: 0,
        products: 0,
        movements: 0,
        warehouseId: 0,
        error: e.toString(),
      );
    }
  }

  Future<ConvertedJsonImportResult> importMap(Map<String, dynamic> root) async {
    try {
      final accountsRaw = root['accounts'];
      final txsRaw = root['transactions'];
      if (accountsRaw is! Map && txsRaw is! List) {
        return const ConvertedJsonImportResult(
          customers: 0,
          products: 0,
          movements: 0,
          warehouseId: 0,
          error:
              'JSON must contain "accounts" and/or "transactions" (converted format).',
        );
      }

      final accounts = <Map<String, dynamic>>[];
      if (accountsRaw is Map) {
        for (final v in accountsRaw.values) {
          if (v is Map) accounts.add(Map<String, dynamic>.from(v));
        }
      }

      final txs = <Map<String, dynamic>>[];
      if (txsRaw is List) {
        for (final v in txsRaw) {
          if (v is Map) txs.add(Map<String, dynamic>.from(v));
        }
      }

      final db = AppDatabase.instance;
      await db.execute('PRAGMA foreign_keys = OFF');
      var customerN = 0;
      var productN = 0;
      var moveN = 0;
      var warehouseId = 0;

      try {
        await db.transaction((txn) async {
          warehouseId = await _ensureWarehouse(txn);
          final customerByKey = await _upsertCustomers(txn, accounts);
          customerN = customerByKey.length;

          final productByKey = await _ensureProducts(txn, txs, warehouseId);
          productN = productByKey.length;

          moveN = await _upsertMovements(
            txn,
            txs,
            productByKey: productByKey,
            customerByKey: customerByKey,
            warehouseId: warehouseId,
          );

          await _recomputeStock(txn, productByKey.values.toSet());
          await _applyProductDimsFromMovements(
            txn,
            productByKey.values.toSet(),
          );
          await txn.delete('sync_queue');
          await _fixSequence(txn, 'customers');
          await _fixSequence(txn, 'products');
          await _fixSequence(txn, 'stock_movements');
          await _fixSequence(txn, 'warehouses');
        });
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
      }

      debugPrint(
        '[ConvertedImport] ok customers=$customerN products=$productN '
        'movements=$moveN warehouse=$warehouseId',
      );

      return ConvertedJsonImportResult(
        customers: customerN,
        products: productN,
        movements: moveN,
        warehouseId: warehouseId,
      );
    } catch (e, st) {
      debugPrint('[ConvertedImport] failed: $e\n$st');
      return ConvertedJsonImportResult(
        customers: 0,
        products: 0,
        movements: 0,
        warehouseId: 0,
        error: e.toString(),
      );
    }
  }

  Future<int> _ensureWarehouse(DatabaseExecutor txn) async {
    final existing = await txn.query(
      'warehouses',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [defaultWarehouseName],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    final now = DateTime.now().toIso8601String();
    return txn.insert('warehouses', {
      'name': defaultWarehouseName,
      'address': null,
      'notes': 'Imported from converted JSON',
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Returns map of account id string / name → local customer id.
  Future<Map<String, int>> _upsertCustomers(
    DatabaseExecutor txn,
    List<Map<String, dynamic>> accounts,
  ) async {
    final map = <String, int>{};
    final now = DateTime.now().toIso8601String();
    for (final a in accounts) {
      final name = _trim(_str(a['name']));
      if (name == null) continue;
      final remoteId = _str(a['id']);
      final preferredId = int.tryParse(remoteId ?? '');
      int id;
      if (preferredId != null) {
        await txn.insert(
          'customers',
          {
            'id': preferredId,
            'name': name,
            'phone': null,
            'email': null,
            'address': null,
            'notes': null,
            'outstanding_balance': 0,
            'total_purchases': 0,
            'last_purchase_at': null,
            'is_archived': 0,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        id = preferredId;
      } else {
        id = await txn.insert('customers', {
          'name': name,
          'phone': null,
          'email': null,
          'address': null,
          'notes': null,
          'outstanding_balance': 0,
          'total_purchases': 0,
          'last_purchase_at': null,
          'is_archived': 0,
          'created_at': now,
          'updated_at': now,
        });
      }
      map[name] = id;
      if (remoteId != null) map[remoteId] = id;
    }
    return map;
  }

  /// Identity of one imported line. Empty when the line has no product name.
  String _txKey(Map<String, dynamic> t) {
    final name = _trim(_str(t['productName']));
    if (name == null) return '';
    return ProductIdentity.variantKey(
      name: name,
      height: _num(t['length']),
      width: _num(t['width']),
      thickness: _guessThicknessMm(name),
    );
  }

  /// Reuses an existing product only when exactly one active row has this
  /// name and sheet size. A second size becomes its own product. When several
  /// rows already share a key, none of them is chosen — their stock is not
  /// combined, and another copy is not inserted.
  Future<Map<String, int>> _ensureProducts(
    DatabaseExecutor txn,
    List<Map<String, dynamic>> txs,
    int warehouseId,
  ) async {
    final map = <String, int>{};
    final now = DateTime.now().toIso8601String();
    var skuIndex = 1;

    final existing = await txn.query(
      'products',
      columns: [
        'id',
        'name',
        'brand',
        'sku',
        'unit_weight',
        'weight_unit',
        'standard_height',
        'standard_width',
        'thickness',
        'is_archived',
        'is_remnant',
      ],
    );
    final byKey = <String, List<int>>{};
    for (final row in existing) {
      if ((row['is_archived'] as int? ?? 0) == 1) continue;
      if ((row['is_remnant'] as int? ?? 0) == 1) continue;
      final key = ProductIdentity.keyOfRow(row);
      if (ProductIdentity.text(row['name'] as String?).isEmpty) continue;
      byKey.putIfAbsent(key, () => []).add(row['id'] as int);
    }

    final wanted = <String, Map<String, dynamic>>{};
    for (final t in txs) {
      final key = _txKey(t);
      if (key.isEmpty) continue;
      wanted.putIfAbsent(key, () => t);
    }

    for (final entry in wanted.entries) {
      final key = entry.key;
      final ids = byKey[key] ?? const <int>[];
      if (ids.length > 1) continue;
      if (ids.length == 1) {
        map[key] = ids.first;
        continue;
      }

      final name = _trim(_str(entry.value['productName']))!;
      final height = _num(entry.value['length']);
      final width = _num(entry.value['width']);
      while (true) {
        final sku = 'IMP-${skuIndex.toString().padLeft(4, '0')}';
        skuIndex++;
        final clash = await txn.query(
          'products',
          columns: ['id'],
          where: 'sku = ?',
          whereArgs: [sku],
          limit: 1,
        );
        if (clash.isNotEmpty) continue;
        final id = await txn.insert('products', {
          'name': name,
          'sku': sku,
          'category_id': null,
          'thickness': _guessThicknessMm(name),
          'standard_width': width,
          'standard_height': height,
          'unit_of_measure': 'sheet',
          'initial_stock': 0,
          'current_stock': 0,
          'minimum_stock_alert': 0,
          'cost_price': 0,
          'selling_price': 0,
          'currency_id': null,
          'supplier_id': null,
          'image_path': null,
          'track_stock_by_sheet': 1,
          'is_active': 1,
          'is_archived': 0,
          'is_remnant': 0,
          'notes': 'Imported from converted JSON',
          'warehouse_id': warehouseId,
          'unit_weight': null,
          'weight_unit': 'kg',
          'created_at': now,
          'updated_at': now,
        });
        map[key] = id;
        byKey[key] = [id];
        break;
      }
    }
    return map;
  }

  Future<int> _upsertMovements(
    DatabaseExecutor txn,
    List<Map<String, dynamic>> txs, {
    required Map<String, int> productByKey,
    required Map<String, int> customerByKey,
    required int warehouseId,
  }) async {
    var n = 0;
    // Running balance per product for balance_after. Each id is one variant,
    // so two sheet sizes never share a balance.
    final balances = <int, double>{
      for (final id in productByKey.values) id: 0.0,
    };

    // Sort by date then id for stable stock replay.
    final sorted = [...txs]..sort((a, b) {
        final da = ShamsiDates.tryParse(_str(a['date'])) ?? DateTime(1970);
        final db_ = ShamsiDates.tryParse(_str(b['date'])) ?? DateTime(1970);
        final c = da.compareTo(db_);
        if (c != 0) return c;
        final ia = int.tryParse('${a['id']}') ?? 0;
        final ib = int.tryParse('${b['id']}') ?? 0;
        return ia.compareTo(ib);
      });

    for (final t in sorted) {
      final key = _txKey(t);
      if (key.isEmpty) continue;
      final productId = productByKey[key];
      if (productId == null) continue;

      final qtyAbs = (_num(t['quantity']) ?? 0).abs();
      if (qtyAbs <= 0) continue;

      final typeRaw = (_str(t['movementType']) ?? 'adjustment').toLowerCase();
      final inbound = typeRaw == 'purchase' ||
          typeRaw == 'return_in' ||
          typeRaw == 'initial';
      final movementType = switch (typeRaw) {
        'purchase' => 'purchase',
        'sale' || 'customer_sale' => 'sale',
        'return_in' => 'return_in',
        'return_out' => 'return_out',
        'damage' => 'damage',
        'waste' => 'waste',
        'transfer' => 'transfer',
        'initial' => 'initial',
        _ => inbound ? 'purchase' : 'sale',
      };
      final delta = inbound ? qtyAbs : -qtyAbs;
      final balance = (balances[productId] ?? 0) + delta;
      balances[productId] = balance;

      final partner = _trim(_str(t['accountName'])) ??
          _trim(_str(t['partnerName']));
      final accountId = _str(t['accountId']);
      // Prefer linking partner name; keep notes clean.
      final noteParts = <String>[
        if (_trim(_str(t['notes'])) != null) _trim(_str(t['notes']))!,
        if (_trim(_str(t['sheet'])) != null) 'Sheet: ${_trim(_str(t['sheet']))}',
      ];

      final lengthM = _num(t['length']);
      final widthM = _num(t['width']);
      final areaM2 = _num(t['area']) ??
          ((lengthM != null &&
                  widthM != null &&
                  lengthM > 0 &&
                  widthM > 0)
              ? lengthM * widthM
              : null);

      final preferredId = int.tryParse('${t['id'] ?? ''}');
      final created =
          ShamsiDates.tryParse(_str(t['date'])) ?? DateTime.now();

      final row = <String, Object?>{
        if (preferredId != null) 'id': preferredId,
        'product_id': productId,
        'movement_type': movementType,
        'quantity': delta,
        'balance_after': balance,
        'reference_type': accountId != null
            ? 'customer'
            : (_trim(_str(t['source'])) != null ? 'import' : null),
        'reference_id': accountId != null
            ? (customerByKey[accountId] ?? int.tryParse(accountId))
            : null,
        'notes': noteParts.isEmpty ? null : noteParts.join(' · '),
        'partner_name': partner,
        'length_m': lengthM,
        'width_m': widthM,
        'area_m2': areaM2,
        'broken_qty': 0,
        'unit_price': _num(t['unitPrice'] ?? t['unit_price']),
        'paid_amount': _num(t['paidAmount'] ?? t['paid_amount']) ?? 0,
        'currency_id': null,
        'warehouse_id': warehouseId,
        'employee_id': null,
        'created_by': 'converted_json_import',
        'created_at': created.toIso8601String(),
      };

      if (preferredId != null) {
        await txn.insert(
          'stock_movements',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        await txn.insert('stock_movements', row);
      }
      n++;
    }
    return n;
  }

  Future<void> _recomputeStock(
    DatabaseExecutor txn,
    Set<int> productIds,
  ) async {
    final now = DateTime.now().toIso8601String();
    for (final id in productIds) {
      final sum = await txn.rawQuery(
        'SELECT COALESCE(SUM(quantity), 0) AS s FROM stock_movements WHERE product_id = ?',
        [id],
      );
      final stock = (sum.first['s'] as num?)?.toDouble() ?? 0;
      await txn.update(
        'products',
        {
          'current_stock': stock,
          'initial_stock': stock > 0 ? stock : 0,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// Fill missing sheet dims from the first movement that has length/width.
  Future<void> _applyProductDimsFromMovements(
    DatabaseExecutor txn,
    Set<int> productIds,
  ) async {
    final now = DateTime.now().toIso8601String();
    for (final id in productIds) {
      final product = await txn.query(
        'products',
        columns: ['standard_width', 'standard_height'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (product.isEmpty) continue;
      final hasW =
          (product.first['standard_width'] as num?)?.toDouble() != null;
      final hasH =
          (product.first['standard_height'] as num?)?.toDouble() != null;
      if (hasW && hasH) continue;

      final moves = await txn.query(
        'stock_movements',
        columns: ['length_m', 'width_m'],
        where: 'product_id = ? AND length_m IS NOT NULL AND width_m IS NOT NULL',
        whereArgs: [id],
        orderBy: 'created_at ASC, id ASC',
        limit: 1,
      );
      if (moves.isEmpty) continue;
      final lengthM = (moves.first['length_m'] as num?)?.toDouble();
      final widthM = (moves.first['width_m'] as num?)?.toDouble();
      if (lengthM == null || widthM == null) continue;
      await txn.update(
        'products',
        {
          if (!hasH) 'standard_height': lengthM,
          if (!hasW) 'standard_width': widthM,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
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

  /// Best-effort thickness from names like `ساده 6میل` / `4میل`.
  static double? _guessThicknessMm(String name) {
    final m = RegExp(r'(\d+)\s*میل').firstMatch(name);
    if (m != null) return double.tryParse(m.group(1)!);
    return null;
  }

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  static String? _trim(String? v) {
    if (v == null) return null;
    final s = v.trim();
    return s.isEmpty ? null : s;
  }

  static double? _num(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }
}
