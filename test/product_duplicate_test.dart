import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_general/core/database/app_database.dart';
import 'package:pos_general/core/database/data_transfer.dart';
import 'package:pos_general/core/errors/app_failure.dart';
import 'package:pos_general/core/errors/result.dart';
import 'package:pos_general/core/sync/converted_json_import_service.dart';
import 'package:pos_general/data/models/product_model.dart';
import 'package:pos_general/data/models/stock_movement_model.dart';
import 'package:pos_general/data/repositories/product_repository_impl.dart';

void main() {
  late Directory tempDir;
  final repo = ProductRepositoryImpl();

  ProductModel product({
    int id = 0,
    String name = 'Gold Standard Whey',
    String sku = '',
    String? barcode,
    String? brand = 'ON',
    double? unitWeight = 2,
    String weightUnit = 'lb',
    double? standardHeight,
    double? standardWidth,
    double? thickness,
  }) {
    final now = DateTime(2026);
    return ProductModel(
      id: id,
      name: name,
      sku: sku,
      barcode: barcode,
      brand: brand,
      unitWeight: unitWeight,
      weightUnit: weightUnit,
      standardHeight: standardHeight,
      standardWidth: standardWidth,
      thickness: thickness,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<int> productCount() async =>
      (await AppDatabase.instance.rawQuery('SELECT COUNT(*) AS c FROM products'))
          .first['c'] as int;

  ProductModel created(Result<ProductModel> r) =>
      (r as Success<ProductModel>).value;

  Map<String, String> fieldErrorsOf(Result<Object?> r) =>
      ((r as FailureResult).failure as ValidationFailure).fieldErrors;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('product_dup_test');
    await AppDatabase.initialize(supportDir: tempDir);
  });

  tearDown(() async {
    await AppDatabase.close();
    await tempDir.delete(recursive: true);
  });

  test('same name, brand and size is rejected even with blank SKU', () async {
    created(await repo.create(product()));
    final second = await repo.create(
      product(name: '  gold   STANDARD whey '),
    );
    expect(fieldErrorsOf(second), {'name': 'duplicate'});
    expect(await productCount(), 1);
  });

  test('Arabic and Persian letter/digit variants count as the same name',
      () async {
    created(await repo.create(product(name: 'پروتئین وی ۵', brand: null)));
    final second = await repo.create(
      product(name: 'پروتئين وي 5', brand: null),
    );
    expect(fieldErrorsOf(second), {'name': 'duplicate'});
  });

  test('different pack size or brand is a separate product', () async {
    created(await repo.create(product()));
    created(await repo.create(product(unitWeight: 5)));
    created(await repo.create(product(brand: 'MuscleTech')));
    expect(await productCount(), 3);
  });

  test('SKU and barcode are unique regardless of case', () async {
    created(await repo.create(product(sku: 'WHEY-1', barcode: '123')));
    expect(
      fieldErrorsOf(await repo.create(product(name: 'A', sku: 'whey-1'))),
      {'sku': 'duplicate'},
    );
    expect(
      fieldErrorsOf(await repo.create(product(name: 'B', barcode: '123'))),
      {'barcode': 'duplicate'},
    );
  });

  test('update cannot rename into an existing product', () async {
    created(await repo.create(product()));
    final other = created(await repo.create(product(name: 'Creatine')));
    final renamed = await repo.update(
      product(id: other.id, name: 'Gold Standard Whey'),
    );
    expect(fieldErrorsOf(renamed), {'name': 'duplicate'});
  });

  test('editing an unchanged legacy duplicate is still allowed', () async {
    final first = created(await repo.create(product()));
    final legacy = Map<String, Object?>.from(
      (await AppDatabase.instance.query(
        'products',
        where: 'id = ?',
        whereArgs: [first.id],
      ))
          .first,
    )..remove('id');
    final legacyId = await AppDatabase.instance.insert('products', legacy);

    final edited = await repo.update(
      product(id: legacyId).copyWith(sellingPrice: 99),
    );
    expect(edited, isA<Success<ProductModel>>());
  });

  test('restoring an archived product that now duplicates is blocked',
      () async {
    final first = created(await repo.create(product()));
    await repo.archive(first.id);
    created(await repo.create(product()));
    expect(fieldErrorsOf(await repo.restore(first.id)), {'name': 'duplicate'});
  });

  test('same name with a different sheet size keeps its own stock', () async {
    final narrow = created(
      await repo.create(product(standardHeight: 2.25, standardWidth: 1.60)),
    );
    final wide = created(
      await repo.create(product(standardHeight: 2.25, standardWidth: 3.21)),
    );
    expect(
      fieldErrorsOf(
        await repo.create(
          product(standardHeight: 2.25, standardWidth: 1.6),
        ),
      ),
      {'name': 'duplicate'},
    );

    expect(
      await repo.adjustStock(
        productId: narrow.id,
        quantityDelta: 10,
        type: StockMovementType.purchase,
      ),
      isA<Success<ProductModel>>(),
    );
    expect(
      await repo.adjustStock(
        productId: wide.id,
        quantityDelta: 4,
        type: StockMovementType.purchase,
      ),
      isA<Success<ProductModel>>(),
    );

    expect(created(await repo.getById(narrow.id)).currentStock, 10);
    expect(created(await repo.getById(wide.id)).currentStock, 4);
    expect(await productCount(), 2);
  });

  test('nearby sheet sizes are not treated as one product', () async {
    created(
      await repo.create(product(standardHeight: 2.25, standardWidth: 1.6)),
    );
    created(
      await repo.create(product(standardHeight: 2.25, standardWidth: 1.605)),
    );
    expect(await productCount(), 2);
  });

  test('editing a product does not rewrite its stock', () async {
    final first = created(await repo.create(product()));
    expect(
      await repo.adjustStock(
        productId: first.id,
        quantityDelta: 6,
        type: StockMovementType.purchase,
      ),
      isA<Success<ProductModel>>(),
    );
    final edited = await repo.update(
      product(id: first.id).copyWith(sellingPrice: 12, currentStock: 0),
    );
    final saved = created(edited);
    expect(saved.sellingPrice, 12);
    expect(saved.currentStock, 6);
  });

  test('import keeps each sheet size on its own product', () async {
    final result = await ConvertedJsonImportService().importMap({
      'transactions': [
        {
          'id': 1,
          'movementType': 'purchase',
          'productName': 'طلائی',
          'quantity': 10,
          'length': 2.25,
          'width': 1.60,
        },
        {
          'id': 2,
          'movementType': 'purchase',
          'productName': 'طلائى',
          'quantity': 4,
          'width': 3.21,
          'length': 2.25,
        },
      ],
    });
    expect(result.ok, isTrue, reason: result.error);
    final rows = await AppDatabase.instance.query(
      'products',
      columns: ['standard_width', 'current_stock'],
      orderBy: 'standard_width ASC',
    );
    expect(rows, hasLength(2));
    expect(rows[0]['current_stock'], 10);
    expect(rows[1]['current_stock'], 4);
  });

  test('import does not add stock onto an ambiguous duplicate', () async {
    final first = created(
      await repo.create(
        product(name: 'طلائی', brand: null, unitWeight: null),
      ),
    );
    await AppDatabase.instance.update(
      'products',
      {'current_stock': 3},
      where: 'id = ?',
      whereArgs: [first.id],
    );
    final copy = Map<String, Object?>.from(
      (await AppDatabase.instance.query(
        'products',
        where: 'id = ?',
        whereArgs: [first.id],
      ))
          .first,
    )..remove('id');
    copy['current_stock'] = 5;
    copy['sku'] = '';
    await AppDatabase.instance.insert('products', copy);

    final result = await ConvertedJsonImportService().importMap({
      'transactions': [
        {
          'id': 9,
          'movementType': 'purchase',
          'productName': 'طلائی',
          'quantity': 100,
        },
      ],
    });
    expect(result.ok, isTrue, reason: result.error);
    final stocks = await AppDatabase.instance.query(
      'products',
      columns: ['current_stock'],
      orderBy: 'id ASC',
    );
    expect(stocks.map((row) => row['current_stock']).toList(), [3, 5]);
  });

  test('spreadsheet import does not copy stock onto the existing product',
      () async {
    final first = created(await repo.create(product(sku: 'WHEY-1')));
    expect(
      await repo.adjustStock(
        productId: first.id,
        quantityDelta: 8,
        type: StockMovementType.purchase,
      ),
      isA<Success<ProductModel>>(),
    );

    final csv = File('${tempDir.path}/products.csv');
    await csv.writeAsString(
      'name,sku,brand,unit_weight,weight_unit,current_stock,created_at,updated_at\r\n'
      'Gold Standard Whey,whey-1,ON,2,lb,99,2026-01-01T00:00:00.000,2026-01-01T00:00:00.000\r\n'
      'Gold Standard Whey,,ON,2,lb,50,2026-01-01T00:00:00.000,2026-01-01T00:00:00.000\r\n',
    );
    await DataTransfer.importSpreadsheet(csv.path);

    expect(await productCount(), 1);
    expect(created(await repo.getById(first.id)).currentStock, 8);
  });
}
