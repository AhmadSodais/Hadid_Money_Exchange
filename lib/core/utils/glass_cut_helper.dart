import 'package:easy_localization/easy_localization.dart';

import '../constants/app_constants.dart';

/// Result of evaluating a cut against a parent sheet size.
class GlassCutPlan {
  const GlassCutPlan({
    required this.isPartialCut,
    required this.sheetsConsumed,
    this.remnantLengthM,
    this.remnantWidthM,
    this.waste = false,
  });

  /// True when cut dimensions are smaller than the parent sheet.
  final bool isPartialCut;

  /// Whole sheets opened for this line (usually = sold quantity).
  final double sheetsConsumed;

  /// Leftover rectangle in meters, or null if full use / waste.
  final double? remnantLengthM;
  final double? remnantWidthM;

  /// Leftover existed but was below [AppConstants.minRemnantSideM].
  final bool waste;

  bool get hasRemnant =>
      remnantLengthM != null &&
      remnantWidthM != null &&
      remnantLengthM! > 0 &&
      remnantWidthM! > 0;
}

/// Cut-to-size sheet math for glass stock.
abstract final class GlassCutHelper {
  static const _eps = 0.005; // 5 mm tolerance in meters

  /// Normalize stored dimension to meters (legacy mm values are ≥ 50).
  static double toMeters(double raw) => raw >= 50 ? raw / 1000 : raw;

  static bool _eq(double a, double b) => (a - b).abs() <= _eps;

  static bool _lt(double a, double b) => a < b - _eps;

  static String formatDim(double meters) {
    final v = (meters * 1000).round() / 1000;
    if (v == v.roundToDouble()) return '${v.round()}';
    return v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// Piece area in m² from length × width (meters or legacy mm).
  static double? pieceAreaM2(double? length, double? width) {
    if (length == null || width == null || length <= 0 || width <= 0) {
      return null;
    }
    return toMeters(length) * toMeters(width);
  }

  static String formatArea(double areaM2) {
    final v = (areaM2 * 1000).round() / 1000;
    if (v == v.roundToDouble()) return '${v.round()}';
    return v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// Weight of a cut / remnant piece from a parent sheet's [parentWeight].
  ///
  /// Scales by area: `parentWeight × (pieceArea / parentArea)`.
  /// Returns null when weight or areas cannot be resolved.
  static double? proportionalWeight({
    required double? parentWeight,
    required double? parentLength,
    required double? parentWidth,
    required double? pieceLength,
    required double? pieceWidth,
  }) {
    if (parentWeight == null || parentWeight <= 0) return null;
    final parentArea = pieceAreaM2(parentLength, parentWidth);
    final pieceArea = pieceAreaM2(pieceLength, pieceWidth);
    if (parentArea == null ||
        pieceArea == null ||
        parentArea <= 0 ||
        pieceArea <= 0) {
      return null;
    }
    // Full sheet (same area within tolerance) keeps the parent weight.
    if ((pieceArea - parentArea).abs() / parentArea <= 0.005) {
      return parentWeight;
    }
    if (pieceArea >= parentArea) return parentWeight;
    final scaled = parentWeight * (pieceArea / parentArea);
    // Keep three decimal places for kg-scale values (e.g. 3.5).
    return (scaled * 1000).round() / 1000;
  }

  /// Stable remnant SKU: `{parentSku}-R-{L}x{W}` in meters.
  static String remnantSku({
    required String parentSku,
    required double lengthM,
    required double widthM,
  }) {
    final a = formatDim(lengthM);
    final b = formatDim(widthM);
    return '${parentSku.trim()}-R-${a}x$b';
  }

  static String remnantName({
    required String parentName,
    required double lengthM,
    required double widthM,
  }) {
    return 'products.remnantName'.tr(
      namedArgs: {
        'parent': parentName,
        'length': formatDim(lengthM),
        'width': formatDim(widthM),
      },
    );
  }

  /// Localized sale/cut note including piece size, area, and sheet size.
  static String saleCutNotes({
    required String base,
    required GlassCutPlan cut,
    double? cutLength,
    double? cutWidth,
    double? parentLength,
    double? parentWidth,
  }) {
    final pieceArea = pieceAreaM2(cutLength, cutWidth);
    final pL = parentLength != null ? formatDim(toMeters(parentLength)) : '-';
    final pW = parentWidth != null ? formatDim(toMeters(parentWidth)) : '-';
    final cL = cutLength != null ? formatDim(toMeters(cutLength)) : '-';
    final cW = cutWidth != null ? formatDim(toMeters(cutWidth)) : '-';
    final area = pieceArea != null ? formatArea(pieceArea) : '-';

    if (!cut.isPartialCut) return base;
    if (cut.hasRemnant) {
      return 'inventory.saleCutWithRemnant'.tr(
        namedArgs: {
          'base': base,
          'cutL': cL,
          'cutW': cW,
          'cutArea': area,
          'sheetL': pL,
          'sheetW': pW,
          'remL': formatDim(cut.remnantLengthM!),
          'remW': formatDim(cut.remnantWidthM!),
        },
      );
    }
    if (cut.waste) {
      return 'inventory.saleCutWaste'.tr(
        namedArgs: {
          'base': base,
          'cutL': cL,
          'cutW': cW,
          'cutArea': area,
          'sheetL': pL,
          'sheetW': pW,
        },
      );
    }
    return 'inventory.saleCutOnly'.tr(
      namedArgs: {
        'base': base,
        'cutL': cL,
        'cutW': cW,
        'cutArea': area,
        'sheetL': pL,
        'sheetW': pW,
      },
    );
  }

  /// Plan stock impact for selling [quantity] pieces of [cutLength]/[cutWidth]
  /// from a parent sheet of [parentLength]×[parentWidth].
  ///
  /// Dimensions may be meters or legacy millimeters.
  static GlassCutPlan plan({
    required double? parentLength,
    required double? parentWidth,
    required double? cutLength,
    required double? cutWidth,
    required double quantity,
    bool trackStockBySheet = true,
    double minRemnantSideM = AppConstants.minRemnantSideM,
  }) {
    final qty = quantity.abs();
    if (qty <= 0) {
      return const GlassCutPlan(isPartialCut: false, sheetsConsumed: 0);
    }

    // Non-sheet products: keep legacy quantity deduction.
    if (!trackStockBySheet) {
      return GlassCutPlan(isPartialCut: false, sheetsConsumed: qty);
    }

    if (parentLength == null ||
        parentWidth == null ||
        parentLength <= 0 ||
        parentWidth <= 0 ||
        cutLength == null ||
        cutWidth == null ||
        cutLength <= 0 ||
        cutWidth <= 0) {
      return GlassCutPlan(isPartialCut: false, sheetsConsumed: qty);
    }

    final pL = toMeters(parentLength);
    final pW = toMeters(parentWidth);
    final cL = toMeters(cutLength);
    final cW = toMeters(cutWidth);

    // Full sheet (same size, either orientation).
    if ((_eq(cL, pL) && _eq(cW, pW)) || (_eq(cL, pW) && _eq(cW, pL))) {
      return GlassCutPlan(isPartialCut: false, sheetsConsumed: qty);
    }

    final rem = _bestRemnant(
      parentL: pL,
      parentW: pW,
      cutL: cL,
      cutW: cW,
      minSide: minRemnantSideM,
    );
    if (rem == null) {
      // Cut doesn't fit as partial — treat as full-sheet qty sale.
      return GlassCutPlan(isPartialCut: false, sheetsConsumed: qty);
    }

    final (rL, rW, waste) = rem;
    if (waste || rL == null || rW == null) {
      return GlassCutPlan(
        isPartialCut: true,
        sheetsConsumed: qty,
        waste: true,
      );
    }
    return GlassCutPlan(
      isPartialCut: true,
      sheetsConsumed: qty,
      remnantLengthM: rL,
      remnantWidthM: rW,
    );
  }

  /// Returns (length, width, waste). Null if cut does not fit in parent.
  static (double?, double?, bool)? _bestRemnant({
    required double parentL,
    required double parentW,
    required double cutL,
    required double cutW,
    required double minSide,
  }) {
    (double, double)? tryOrient(double cL, double cW) {
      if (cL > parentL + _eps || cW > parentW + _eps) return null;

      // Same width strip cut along length.
      if (_eq(cW, parentW) && _lt(cL, parentL)) {
        return (parentL - cL, parentW);
      }
      // Same length strip cut along width.
      if (_eq(cL, parentL) && _lt(cW, parentW)) {
        return (parentL, parentW - cW);
      }

      // Both smaller: guillotine — keep the larger usable rectangle.
      if (_lt(cL, parentL) || _lt(cW, parentW)) {
        final candidates = <(double, double)>[];
        if (_lt(cL, parentL)) {
          candidates.add((parentL - cL, parentW));
        }
        if (_lt(cW, parentW)) {
          candidates.add((cL, parentW - cW));
        }
        if (candidates.isEmpty) return null;
        candidates.sort((a, b) => (b.$1 * b.$2).compareTo(a.$1 * a.$2));
        return candidates.first;
      }
      return null;
    }

    var best = tryOrient(cutL, cutW);
    final rotated = tryOrient(cutW, cutL);
    if (rotated != null) {
      if (best == null ||
          rotated.$1 * rotated.$2 > best.$1 * best.$2 + _eps) {
        best = rotated;
      }
    }
    if (best == null) return null;

    final rL = best.$1;
    final rW = best.$2;
    if (rL < minSide - _eps || rW < minSide - _eps) {
      return (null, null, true);
    }
    return (rL, rW, false);
  }
}
