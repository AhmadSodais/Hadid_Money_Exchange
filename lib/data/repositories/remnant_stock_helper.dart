import 'package:easy_localization/easy_localization.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/sync/sync_payload_builders.dart';
import '../../core/utils/glass_cut_helper.dart';
import '../../core/utils/product_identity.dart';

/// Creates or increments remnant products after a partial sheet cut.
abstract final class RemnantStockHelper {
  /// Upsert remnant for [parent] leftover size and add [quantity] stock.
  ///
  /// [cutLengthM] / [cutWidthM] are the sold piece dimensions (for notes).
  /// Returns remnant product id, or null if none created.
  static Future<int?> upsertRemnant({
    required DatabaseExecutor txn,
    required Map<String, Object?> parent,
    required double remnantLengthM,
    required double remnantWidthM,
    required double quantity,
    required DateTime now,
    int? warehouseId,
    String? note,
    double? cutLengthM,
    double? cutWidthM,
  }) async {
    final qty = quantity.abs();
    if (qty <= 0) return null;

    final parentId = parent['id'] as int;
    final parentSku = (parent['sku'] as String?)?.trim().isNotEmpty == true
        ? parent['sku'] as String
        : 'P$parentId';
    final parentName = (parent['name'] as String?) ?? 'Product';
    final sku = GlassCutHelper.remnantSku(
      parentSku: parentSku,
      lengthM: remnantLengthM,
      widthM: remnantWidthM,
    );
    final name = GlassCutHelper.remnantName(
      parentName: parentName,
      lengthM: remnantLengthM,
      widthM: remnantWidthM,
    );
    final wh = warehouseId ?? parent['warehouse_id'] as int?;
    final remnantArea = remnantLengthM * remnantWidthM;
    final cutArea = GlassCutHelper.pieceAreaM2(cutLengthM, cutWidthM);
    final parentWeight = (parent['unit_weight'] as num?)?.toDouble();
    final weightUnit = (parent['weight_unit'] as String?)?.trim().isNotEmpty == true
        ? (parent['weight_unit'] as String).trim()
        : 'kg';
    final remnantWeight = GlassCutHelper.proportionalWeight(
      parentWeight: parentWeight,
      parentLength: (parent['standard_height'] as num?)?.toDouble(),
      parentWidth: (parent['standard_width'] as num?)?.toDouble(),
      pieceLength: remnantLengthM,
      pieceWidth: remnantWidthM,
    );
    final detailNote = note ??
        'inventory.remnantFromCut'.tr(
          namedArgs: {
            'parent': parentName,
            'cutL': cutLengthM != null
                ? GlassCutHelper.formatDim(GlassCutHelper.toMeters(cutLengthM))
                : '—',
            'cutW': cutWidthM != null
                ? GlassCutHelper.formatDim(GlassCutHelper.toMeters(cutWidthM))
                : '—',
            'cutArea': cutArea != null ? GlassCutHelper.formatArea(cutArea) : '—',
            'remL': GlassCutHelper.formatDim(remnantLengthM),
            'remW': GlassCutHelper.formatDim(remnantWidthM),
            'remArea': GlassCutHelper.formatArea(remnantArea),
          },
        );

    final existing = await txn.query(
      'products',
      where: 'sku = ? AND is_archived = 0',
      whereArgs: [sku],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      final storedLength = ProductIdentity.amount(row['standard_height']);
      final storedWidth = ProductIdentity.amount(row['standard_width']);
      final nextLength = ProductIdentity.amount(remnantLengthM);
      final nextWidth = ProductIdentity.amount(remnantWidthM);
      final storedUnset = storedLength.isEmpty && storedWidth.isEmpty;
      final sameSize = storedLength == nextLength && storedWidth == nextWidth;
      // This code already belongs to a different size. Adding the quantity
      // here would mix two products' inventory.
      if (!storedUnset && !sameSize) return null;

      final id = row['id'] as int;
      final current = (row['current_stock'] as num?)?.toDouble() ?? 0;
      final next = current + qty;
      await txn.update(
        'products',
        {
          'current_stock': next,
          'standard_height': remnantLengthM,
          'standard_width': remnantWidthM,
          'parent_product_id': parentId,
          'is_remnant': 1,
          'is_active': 1,
          'category_id': parent['category_id'],
          if (wh != null) 'warehouse_id': wh,
          // Keep remnant unit weight aligned with current cut size / parent weight.
          if (remnantWeight != null) 'unit_weight': remnantWeight,
          'weight_unit': weightUnit,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert('stock_movements', {
        'product_id': id,
        'movement_type': 'adjustment',
        'quantity': qty,
        'balance_after': next,
        'reference_type': 'remnant',
        'reference_id': parentId,
        'notes': detailNote,
        'length_m': remnantLengthM,
        'width_m': remnantWidthM,
        'area_m2': remnantArea,
        'parent_length_m': (parent['standard_height'] as num?)?.toDouble(),
        'parent_width_m': (parent['standard_width'] as num?)?.toDouble(),
        'broken_qty': 0,
        'paid_amount': 0,
        'warehouse_id': wh,
        'created_by': 'system',
        'created_at': now.toIso8601String(),
      });
      return id;
    }

    final id = await txn.insert('products', {
      'name': name,
      'sku': sku,
      'category_id': parent['category_id'],
      'thickness': parent['thickness'],
      'standard_width': remnantWidthM,
      'standard_height': remnantLengthM,
      'unit_of_measure': parent['unit_of_measure'] ?? 'sheet',
      'initial_stock': qty,
      'current_stock': qty,
      'minimum_stock_alert': 0,
      'cost_price': parent['cost_price'] ?? 0,
      'selling_price': parent['selling_price'] ?? 0,
      'currency_id': parent['currency_id'],
      'cost_currency_id': parent['cost_currency_id'],
      'supplier_id': parent['supplier_id'],
      'image_path': parent['image_path'],
      'track_stock_by_sheet': 1,
      'is_active': 1,
      'is_archived': 0,
      'notes': detailNote,
      'warehouse_id': wh,
      'unit_weight': remnantWeight,
      'weight_unit': weightUnit,
      'parent_product_id': parentId,
      'is_remnant': 1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await txn.insert('stock_movements', {
      'product_id': id,
      'movement_type': 'initial',
      'quantity': qty,
      'balance_after': qty,
      'reference_type': 'remnant',
      'reference_id': parentId,
      'notes': detailNote,
      'length_m': remnantLengthM,
      'width_m': remnantWidthM,
      'area_m2': remnantArea,
      'parent_length_m': (parent['standard_height'] as num?)?.toDouble(),
      'parent_width_m': (parent['standard_width'] as num?)?.toDouble(),
      'broken_qty': 0,
      'paid_amount': 0,
      'warehouse_id': wh,
      'created_by': 'system',
      'created_at': now.toIso8601String(),
    });
    return id;
  }

  /// Enqueue remnant product + its movements for cloud sync after commit.
  static Future<void> enqueueRemnantProductSync(
    DatabaseExecutor db,
    int remnantId,
  ) async {
    await SyncPayloadBuilders.enqueueRemnantBundle(db, remnantId);
  }
}
