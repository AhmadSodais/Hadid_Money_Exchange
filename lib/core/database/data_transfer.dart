import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/repositories/customer_repository_impl.dart';
import '../errors/app_failure.dart';
import '../utils/product_identity.dart';
import 'app_database.dart';

class DataTransferResult {
  const DataTransferResult({
    required this.importedRows,
    required this.tables,
  });

  final int importedRows;
  final List<String> tables;
}

/// Exports and imports warehouse / purchases-sales / company / customer tables.
abstract final class DataTransfer {
  /// Business tables exported/imported via Excel (lookup + operational).
  static const tableOrder = <String>[
    'categories',
    'currencies',
    'units_of_measure',
    'warehouses',
    'suppliers',
    'customers',
    'employees',
    'products',
    'stock_movements',
    'orders',
    'order_items',
    'purchases',
    'purchase_items',
    'company_payments',
    'company_payment_allocations',
    'expenses',
    'employee_salaries',
  ];

  static const _uniqueKeys = <String, String>{
    'categories': 'name',
    'currencies': 'code',
    'units_of_measure': 'name',
    'warehouses': 'name',
    'products': 'sku',
    'employees': 'code',
  };

  static const _sheetAliases = <String, String>{
    'units': 'units_of_measure',
    'unit_of_measure': 'units_of_measure',
    'warehouse': 'warehouses',
    'warehouses_list': 'warehouses',
    'locations': 'warehouses',
    'stock': 'products',
    'products_catalog': 'products',
    'inbound': 'stock_movements',
    'outbound': 'stock_movements',
    'inbound_outbound': 'stock_movements',
    'purchase': 'purchases',
    'sale': 'orders',
    'sales': 'orders',
    'purchases_sales': 'stock_movements',
    'movements': 'stock_movements',
    'trading_companies': 'suppliers',
    'companies': 'suppliers',
    'partners': 'suppliers',
    'customers': 'customers',
    'customer': 'customers',
    'buyers': 'customers',
    'clients': 'customers',
    'company_payments': 'company_payments',
    'payments': 'company_payments',
    'company_payment_allocations': 'company_payment_allocations',
    'payment_allocations': 'company_payment_allocations',
    'expense': 'expenses',
    'employee': 'employees',
    'staff': 'employees',
    'withdrawals': 'employee_salaries',
    'employee_withdrawals': 'employee_salaries',
    'salaries': 'employee_salaries',
    'invoices': 'orders',
    'sales_invoices': 'orders',
    'purchase_invoices': 'purchases',
    'order_lines': 'order_items',
    'purchase_lines': 'purchase_items',
  };

  static Future<File> exportExcel(String destPath) async {
    final path = _withExtension(destPath, 'xlsx');
    final dest = File(path);
    await dest.parent.create(recursive: true);

    final db = AppDatabase.instance;
    final book = Excel.createExcel();

    for (final table in tableOrder) {
      final rows = await db.query(table);
      final columns = rows.isNotEmpty
          ? rows.first.keys.toList()
          : await _columnNames(db, table);
      final sheet = book[table];
      sheet.appendRow([
        for (final column in columns) TextCellValue(column),
      ]);
      for (final row in rows) {
        sheet.appendRow([
          for (final column in columns) _toCell(row[column]),
        ]);
      }
    }

    final defaultSheet = book.getDefaultSheet();
    if (defaultSheet != null && !tableOrder.contains(defaultSheet)) {
      book.delete(defaultSheet);
    }

    final bytes = book.save();
    if (bytes == null) {
      throw const FileFailure('Could not build the Excel file.');
    }
    await dest.writeAsBytes(bytes, flush: true);
    return dest;
  }

  static Future<DataTransferResult> importSpreadsheet(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw const FileFailure('Selected file does not exist.');
    }

    final ext = p.extension(sourcePath).toLowerCase();
    final sheets = <String, List<List<String>>>{};
    if (ext == '.csv') {
      sheets.addAll(await _readCsv(file));
    } else if (ext == '.xlsx' || ext == '.xls') {
      sheets.addAll(await _readExcel(file));
    } else {
      throw const FileFailure('Use an .xlsx, .xls, or .csv file.');
    }

    if (sheets.isEmpty) {
      throw const FileFailure('No importable sheets were found in this file.');
    }

    final db = AppDatabase.instance;
    var imported = 0;
    final used = <String>[];

    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        for (final table in tableOrder) {
          final rows = sheets[table];
          if (rows == null || rows.isEmpty) continue;
          final count = await _importTable(txn, table, rows);
          if (count > 0) {
            imported += count;
            used.add(table);
          }
        }
        if (used.contains('stock_movements')) {
          await _recalculateProductStock(txn);
        }
        if (used.contains('customers') || used.contains('orders')) {
          await CustomerRepositoryImpl.refreshBalancesFromOrders(txn);
        }
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }

    return DataTransferResult(importedRows: imported, tables: used);
  }

  /// Rebuild product stock from imported movement quantities so catalog stays
  /// consistent after Excel/CSV import.
  static Future<void> _recalculateProductStock(DatabaseExecutor db) async {
    await db.execute('''
      UPDATE products
      SET current_stock = COALESCE((
        SELECT SUM(quantity) FROM stock_movements
        WHERE stock_movements.product_id = products.id
      ), 0),
      updated_at = datetime('now')
    ''');
  }

  static Future<Map<String, List<List<String>>>> _readExcel(File file) async {
    late Excel book;
    try {
      book = Excel.decodeBytes(await file.readAsBytes());
    } on UnsupportedError {
      throw const FileFailure(
        'This Excel format is not supported. Save the file as .xlsx or .csv.',
      );
    }

    final out = <String, List<List<String>>>{};
    for (final entry in book.tables.entries) {
      final sheet = entry.value;
      if (sheet.maxRows < 2) continue;
      final rows = <List<String>>[];
      for (final row in sheet.rows) {
        rows.add([for (final cell in row) _cellString(cell)]);
      }
      final table = _resolveTable(entry.key, rows.first);
      if (table == null) continue;
      out[table] = rows;
    }
    return out;
  }

  static Future<Map<String, List<List<String>>>> _readCsv(File file) async {
    var text = await file.readAsString();
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final parsed = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(text);
    if (parsed.length < 2) {
      throw const FileFailure('The CSV file has no data rows.');
    }
    final rows = [
      for (final row in parsed) [for (final cell in row) '$cell'.trim()],
    ];
    final table = _resolveTable(p.basenameWithoutExtension(file.path), rows.first);
    if (table == null) {
      throw const FileFailure(
        'Could not detect the table for this CSV. Use an exported Excel file or include a header row.',
      );
    }
    return {table: rows};
  }

  static Future<int> _importTable(
    DatabaseExecutor db,
    String table,
    List<List<String>> rows,
  ) async {
    final headers = rows.first.map(_normalizeHeader).toList();
    if (headers.every((h) => h.isEmpty)) return 0;

    final schema = await _schema(db, table);
    final uniqueKey = _uniqueKeys[table];
    var count = 0;

    for (var i = 1; i < rows.length; i++) {
      final values = rows[i];
      if (values.every((v) => v.trim().isEmpty)) continue;

      final map = <String, Object?>{};
      for (var c = 0; c < headers.length && c < values.length; c++) {
        final header = headers[c];
        if (header.isEmpty) continue;
        final column = _mapColumn(table, header, schema);
        if (column == null) continue;
        map[column] = _coerce(values[c], schema[column] ?? 'TEXT');
      }

      await _applyLookups(db, table, map, headers, values);
      if (map.isEmpty) continue;

      final inserted = await _upsert(db, table, map, uniqueKey);
      if (inserted) count++;
    }
    return count;
  }

  static Future<bool> _upsert(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> map,
    String? uniqueKey,
  ) async {
    if (table == 'products') return _upsertProduct(db, map);

    final pk = table == 'app_settings' ? 'key' : 'id';
    final pkValue = map[pk];

    if (pkValue != null && '$pkValue'.trim().isNotEmpty) {
      await db.insert(table, map, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    }

    map.remove(pk);

    if (uniqueKey != null &&
        map[uniqueKey] != null &&
        '${map[uniqueKey]}'.trim().isNotEmpty) {
      final existing = await db.query(
        table,
        columns: [pk],
        where: '$uniqueKey = ?',
        whereArgs: [map[uniqueKey]],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        await db.update(
          table,
          map,
          where: '$pk = ?',
          whereArgs: [existing.first[pk]],
        );
        return true;
      }
    }

    await db.insert(table, map);
    return true;
  }

  /// Inserts a product only when no active product already has its code or
  /// its name + brand + pack + sheet size. An existing match keeps its own
  /// stock: the imported `current_stock` is never copied onto another row.
  static Future<bool> _upsertProduct(
    DatabaseExecutor db,
    Map<String, Object?> map,
  ) async {
    final pkValue = map['id'];
    if (pkValue != null && '$pkValue'.trim().isNotEmpty) {
      await db.insert(
        'products',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    }

    map.remove('id');
    final sku = (map['sku'] as String?)?.trim().toUpperCase() ?? '';
    if (sku.isEmpty) {
      map['sku'] = '';
    } else {
      map['sku'] = sku;
    }

    final rows = await db.query(
      'products',
      where: 'is_archived = 0 AND IFNULL(is_remnant, 0) = 0',
    );
    final skuKey = ProductIdentity.text(sku);
    final variant = ProductIdentity.variantKey(
      name: map['name'] as String?,
      brand: map['brand'] as String?,
      unitWeight: map['unit_weight'],
      weightUnit: map['weight_unit'] as String?,
      height: map['standard_height'],
      width: map['standard_width'],
      thickness: map['thickness'],
    );

    final skuHits = skuKey.isEmpty
        ? const <int>[]
        : [
            for (final row in rows)
              if (ProductIdentity.text(row['sku'] as String?) == skuKey)
                row['id'] as int,
          ];
    if (skuHits.length > 1) return false;
    if (skuHits.length == 1) {
      await _updateProductKeepingStock(db, skuHits.first, map);
      return true;
    }

    if (ProductIdentity.text(map['name'] as String?).isEmpty) {
      await db.insert('products', map);
      return true;
    }
    final variantHits = [
      for (final row in rows)
        if (ProductIdentity.keyOfRow(row) == variant) row['id'] as int,
    ];
    // Same name and size already exists, possibly under another code.
    // Leave that row's inventory untouched and do not add a second product.
    if (variantHits.isNotEmpty) return false;

    final now = DateTime.now().toIso8601String();
    map.putIfAbsent('created_at', () => now);
    map.putIfAbsent('updated_at', () => now);
    await db.insert('products', map);
    return true;
  }

  static Future<void> _updateProductKeepingStock(
    DatabaseExecutor db,
    int id,
    Map<String, Object?> map,
  ) async {
    final values = Map<String, Object?>.from(map)
      ..remove('id')
      ..remove('current_stock')
      ..remove('initial_stock');
    if (values.isEmpty) return;
    values['updated_at'] = DateTime.now().toIso8601String();
    await db.update('products', values, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> _applyLookups(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> map,
    List<String> headers,
    List<String> values,
  ) async {
    if (table != 'products') return;

    Future<int?> lookup(String lookupTable, String column, String raw) async {
      final value = raw.trim();
      if (value.isEmpty) return null;
      final found = await db.query(
        lookupTable,
        columns: ['id'],
        where: '$column = ?',
        whereArgs: [value],
        limit: 1,
      );
      if (found.isEmpty) return null;
      return found.first['id'] as int?;
    }

    String? valueOf(Set<String> names) {
      for (var i = 0; i < headers.length && i < values.length; i++) {
        if (names.contains(headers[i])) return values[i];
      }
      return null;
    }

    if (map['category_id'] == null) {
      final name = valueOf({'category', 'category_name'});
      if (name != null) {
        map['category_id'] = await lookup('categories', 'name', name);
      }
    }
    if (map['supplier_id'] == null) {
      final name = valueOf({'supplier', 'supplier_name'});
      if (name != null) {
        map['supplier_id'] = await lookup('suppliers', 'name', name);
      }
    }
    if (map['currency_id'] == null) {
      final code = valueOf({'currency', 'currency_code'});
      if (code != null) {
        map['currency_id'] = await lookup('currencies', 'code', code);
      }
    }
  }

  static String? _mapColumn(
    String table,
    String header,
    Map<String, String> schema,
  ) {
    if (schema.containsKey(header)) return header;
    if (header == 'unit' && schema.containsKey('unit_of_measure')) {
      return 'unit_of_measure';
    }
    if (table == 'customers') {
      const aliases = <String, String>{
        'outstandingbalance': 'outstanding_balance',
        'outstanding': 'outstanding_balance',
        'loan': 'outstanding_balance',
        'loan_balance': 'outstanding_balance',
        'totalpurchases': 'total_purchases',
        'totalsales': 'total_purchases',
        'lastpurchaseat': 'last_purchase_at',
        'last_sale_at': 'last_purchase_at',
        'isarchived': 'is_archived',
        'createdat': 'created_at',
        'updatedat': 'updated_at',
      };
      final mapped = aliases[header];
      if (mapped != null && schema.containsKey(mapped)) return mapped;
    }
    if (table == 'products' &&
        {'category', 'category_name', 'supplier', 'supplier_name', 'currency', 'currency_code'}
            .contains(header)) {
      return null;
    }
    return null;
  }

  static String? _resolveTable(String rawName, List<String> headers) {
    final normalized = _normalizeHeader(rawName);
    final aliased = _sheetAliases[normalized] ?? normalized;
    if (tableOrder.contains(aliased)) return aliased;

    final set = headers.map(_normalizeHeader).where((h) => h.isNotEmpty).toSet();
    if (set.contains('sku') && set.contains('name')) return 'products';
    if (set.contains('code') && set.contains('symbol')) return 'currencies';
    if (set.contains('abbreviation')) return 'units_of_measure';
    if (set.contains('color') && set.contains('name')) return 'categories';
    if (set.contains('full_name') || set.contains('base_salary')) {
      return 'employees';
    }
    if (set.contains('employee_id') && set.contains('paid_at')) {
      return 'employee_salaries';
    }
    if (set.contains('category') &&
        set.contains('amount') &&
        set.contains('expense_date')) {
      return 'expenses';
    }
    if (set.contains('invoice_number') &&
        set.contains('subtotal') &&
        set.contains('amount_paid')) {
      return set.contains('purchase_id') ? 'purchases' : 'orders';
    }
    if (set.contains('order_id') && set.contains('product_name')) {
      return 'order_items';
    }
    if (set.contains('purchase_id') && set.contains('product_name')) {
      return 'purchase_items';
    }
    if (set.contains('name') &&
        set.contains('phone') &&
        (set.contains('outstanding_balance') ||
            set.contains('outstandingBalance') ||
            set.contains('total_purchases') ||
            set.contains('totalPurchases') ||
            set.contains('last_purchase_at') ||
            set.contains('lastPurchaseAt'))) {
      return 'customers';
    }
    if (set.contains('movement_type') ||
        set.contains('balance_after')) {
      return 'stock_movements';
    }
    final lower = rawName.toLowerCase();
    if (lower.contains('warehous') || lower.contains('location')) {
      return 'warehouses';
    }
    if (lower.contains('product')) {
      return 'products';
    }
    if (lower.contains('customer')) return 'customers';
    if (lower.contains('supplier') || lower.contains('compan')) {
      return 'suppliers';
    }
    if (lower.contains('categor')) return 'categories';
    if (lower.contains('currenc')) return 'currencies';
    if (lower.contains('employee') && lower.contains('salar')) {
      return 'employee_salaries';
    }
    if (lower.contains('employee')) return 'employees';
    if (lower.contains('expense')) return 'expenses';
    if (lower.contains('order_item')) return 'order_items';
    if (lower.contains('purchase_item')) return 'purchase_items';
    if (lower.contains('purchase') && !lower.contains('movement')) {
      return 'purchases';
    }
    if ((lower.contains('order') || lower.contains('sale')) &&
        !lower.contains('movement')) {
      return 'orders';
    }
    if (lower.contains('movement') ||
        lower.contains('inbound') ||
        lower.contains('outbound')) {
      return 'stock_movements';
    }
    // Trading companies with phone but no customer-specific columns.
    if (set.contains('name') && set.contains('phone')) return 'suppliers';
    return null;
  }

  static Future<List<String>> _columnNames(Database db, String table) async {
    final schema = await _schema(db, table);
    return schema.keys.toList();
  }

  static Future<Map<String, String>> _schema(
    DatabaseExecutor db,
    String table,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return {
      for (final row in info) row['name'] as String: row['type'] as String? ?? 'TEXT',
    };
  }

  static Object? _coerce(String raw, String type) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final t = type.toUpperCase();
    if (t.contains('INT')) return int.tryParse(value) ?? value;
    if (t.contains('REAL') || t.contains('FLOA') || t.contains('DOUB')) {
      return double.tryParse(value) ?? value;
    }
    return value;
  }

  static CellValue? _toCell(Object? value) {
    if (value == null) return null;
    if (value is int) return IntCellValue(value);
    if (value is double) return DoubleCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    return TextCellValue('$value');
  }

  static String _cellString(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is TextCellValue) return value.value.text ?? '';
    if (value is IntCellValue) return '${value.value}';
    if (value is DoubleCellValue) {
      final n = value.value;
      return n == n.roundToDouble() ? '${n.toInt()}' : '$n';
    }
    if (value is BoolCellValue) return value.value ? '1' : '0';
    if (value is DateCellValue) return value.asDateTimeLocal().toIso8601String();
    if (value is DateTimeCellValue) {
      return value.asDateTimeLocal().toIso8601String();
    }
    return value.toString();
  }

  static String _normalizeHeader(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
  }

  static String _withExtension(String path, String ext) {
    final current = p.extension(path).toLowerCase();
    if (current == '.$ext') return path;
    return '$path.$ext';
  }
}
