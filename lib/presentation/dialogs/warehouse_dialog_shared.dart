import 'dart:io';

import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/product_model.dart';

/// Soft surfaces used by warehouse dialogs (theme-aware).
Color get kDialogBorder => AppColors.border;
Color get kDialogSoftBlue => AppColors.surface;
Color get kDialogInfoBlue => AppColors.infoBg;

const List<String> kWarehouseLocations = <String>[];

/// Canonical product units stored in the database.
const List<String> kProductUnits = ['pcs', 'box', 'kg', 'g', 'meter', 'sheet', 'tube'];

/// Weight units selectable on the product form.
const List<String> kWeightUnits = ['kg', 'g', 't'];

/// Units for product expiry alert lead time.
const List<String> kExpiryAlertUnits = ['day', 'week', 'month', 'year'];

String normalizeExpiryAlertUnit(String? raw) {
  final u = (raw ?? '').trim().toLowerCase();
  if (kExpiryAlertUnits.contains(u)) return u;
  return 'month';
}

String expiryAlertUnitLabel(String unit) => switch (normalizeExpiryAlertUnit(unit)) {
      'day' => 'products.add.fields.expiryAlertUnits.day'.tr(),
      'week' => 'products.add.fields.expiryAlertUnits.week'.tr(),
      'month' => 'products.add.fields.expiryAlertUnits.month'.tr(),
      'year' => 'products.add.fields.expiryAlertUnits.year'.tr(),
      _ => 'products.add.fields.expiryAlertUnits.month'.tr(),
    };

/// Normalizes legacy Persian / mixed unit values to a canonical English key.
String normalizeProductUnit(String? raw) {
  final u = (raw ?? '').trim().toLowerCase();
  return switch (u) {
    'جام' || 'sheet' || 'sheets' => 'sheet',
    'عدد' || 'pcs' || 'pc' || 'piece' || 'pieces' => 'pcs',
    'جعبه' || 'box' || 'boxes' => 'box',
    'متر' || 'meter' || 'metre' || 'meters' || 'm' => 'meter',
    'لوله' || 'tube' || 'tubes' => 'tube',
    'kg' || 'کیلوگرم' || 'kilogram' => 'kg',
    'g' || 'گرم' || 'gram' => 'g',
    _ => u.isEmpty ? 'pcs' : u,
  };
}

/// Locale-aware product unit label (English or Persian / Pashto).
/// Stored values stay as English keys (`sheet`, `pcs`, …).
String productUnitLabel(String? unit) {
  return switch (normalizeProductUnit(unit)) {
    'sheet' => 'products.add.units.sheet'.tr(),
    'pcs' => 'products.add.units.pcs'.tr(),
    'box' => 'products.add.units.box'.tr(),
    'kg' => 'products.add.units.kg'.tr(),
    'g' => 'products.add.units.g'.tr(),
    'meter' => 'products.add.units.meter'.tr(),
    'tube' => 'products.add.units.tube'.tr(),
    final other => _capitalizeFirst(other),
  };
}

/// Locale-aware weight unit label.
String weightUnitLabel(String? unit) {
  return switch (normalizeWeightUnit(unit)) {
    'kg' => 'products.add.weightUnits.kg'.tr(),
    'g' => 'products.add.weightUnits.g'.tr(),
    't' => 'products.add.weightUnits.t'.tr(),
    final other => _capitalizeFirst(other),
  };
}

String normalizeWeightUnit(String? raw) {
  final u = (raw ?? '').trim().toLowerCase();
  return switch (u) {
    'kg' || 'kilogram' || 'کیلوگرم' => 'kg',
    'g' || 'gram' || 'گرم' => 'g',
    't' || 'ton' || 'tonne' || 'تن' => 't',
    _ => u.isEmpty ? 'kg' : u,
  };
}

String _capitalizeFirst(String value) {
  final t = value.trim();
  if (t.isEmpty) return t;
  if (t.length == 1) return t.toUpperCase();
  return '${t[0].toUpperCase()}${t.substring(1).toLowerCase()}';
}

/// Length / width input units. Thickness is always millimeters.
const List<String> kDimensionUnits = ['m', 'mm', 'cm'];

String normalizeDimensionUnit(String? raw) {
  final u = (raw ?? '').trim().toLowerCase();
  return switch (u) {
    'mm' || 'millimeter' || 'millimetre' || 'میلی‌متر' || 'میلیمتر' => 'mm',
    'cm' || 'centimeter' || 'centimetre' || 'سانتی‌متر' || 'سانتیمتر' => 'cm',
    'm' || 'meter' || 'metre' || 'متر' => 'm',
    _ => 'm',
  };
}

/// Locale-aware length/width unit label. Default display unit is meters.
String dimensionUnitLabel(String? unit) {
  return switch (normalizeDimensionUnit(unit)) {
    'mm' => 'products.add.dimensionUnits.mm'.tr(),
    'cm' => 'products.add.dimensionUnits.cm'.tr(),
    _ => 'products.add.dimensionUnits.m'.tr(),
  };
}

String dimensionUnitHint(String? unit) {
  return switch (normalizeDimensionUnit(unit)) {
    'mm' => 'stockEntry.lengthMmHint'.tr(),
    'cm' => 'stockEntry.lengthCmHint'.tr(),
    _ => 'stockEntry.lengthHint'.tr(),
  };
}

/// Factor: UI value × factor = meters.
double dimensionUnitToMetersFactor(String? unit) {
  return switch (normalizeDimensionUnit(unit)) {
    'mm' => 0.001,
    'cm' => 0.01,
    _ => 1,
  };
}

/// Convert a UI length/width value in [unit] to meters for storage.
double dimensionToMeters(double value, String? unit) {
  if (value <= 0) return 0;
  return value * dimensionUnitToMetersFactor(unit);
}

/// Convert stored meters to a UI value in [unit].
double metersToDimension(double meters, String? unit) {
  if (meters <= 0) return 0;
  final f = dimensionUnitToMetersFactor(unit);
  if (f <= 0) return meters;
  return meters / f;
}

/// Normalize a stored dimension that may be meters or legacy mm (>= 50).
double normalizeStoredMeters(double stored) {
  if (stored <= 0) return 0;
  // Legacy rows sometimes stored millimeters directly.
  return stored >= 50 ? stored / 1000 : stored;
}

/// Stored meters → UI string in [unit] (default meters).
String dimToDisplay(double? storedMeters, {String unit = 'm'}) {
  if (storedMeters == null || storedMeters <= 0) return '';
  final meters = normalizeStoredMeters(storedMeters);
  return Formatters.number(metersToDimension(meters, unit));
}

/// Converts stored dimension (meters or legacy mm) to mm for UI display.
/// Prefer [dimToDisplay] for length/width; thickness stays in millimeters.
String dimToMmDisplay(double? stored) => dimToDisplay(stored, unit: 'mm');

/// Parses a positive dimension number from a UI string.
double? parseMm(String raw) {
  final n = Formatters.parse(raw);
  if (n == null || n <= 0) return null;
  return n;
}

/// Stores dimensions as meters (Excel-compatible).
double mmToMeters(double mm) => mm / 1000;

/// Area = length × width [× quantity]. Values are already in the same unit.
///
/// Example: Length = 10, Width = 5, Quantity = 100 → 5000.
double areaFromDimensions({
  required double length,
  required double width,
  double quantity = 1,
}) {
  if (length <= 0 || width <= 0) return 0;
  final sheet = length * width;
  if (quantity <= 0) return sheet;
  return sheet * quantity;
}

/// Area in m² from UI length/width entered in [unit], times [quantity].
double areaM2FromUi({
  required double length,
  required double width,
  String unit = 'm',
  double quantity = 1,
}) {
  final lm = dimensionToMeters(length, unit);
  final wm = dimensionToMeters(width, unit);
  return areaFromDimensions(length: lm, width: wm, quantity: quantity);
}

/// Backwards-compatible alias.
double areaFromMm({
  required double lengthMm,
  required double widthMm,
  double quantity = 1,
}) => areaFromDimensions(length: lengthMm, width: widthMm, quantity: quantity);

/// Converts a stored dimension (meters or legacy mm) to the UI number in mm.
double dimensionToUiValue(double? stored) {
  if (stored == null || stored <= 0) return 0;
  return metersToDimension(normalizeStoredMeters(stored), 'mm');
}

/// Sheet area in m² from stored meter dimensions: L × W.
double areaFromStoredDimensions({
  required double? length,
  required double? width,
  double quantity = 1,
}) {
  if (length == null || width == null || length <= 0 || width <= 0) return 0;
  final l = normalizeStoredMeters(length);
  final w = normalizeStoredMeters(width);
  return areaFromDimensions(length: l, width: w, quantity: quantity);
}

/// Formats a product/line weight with its unit.
String formatProductWeight(double? value, String? unit, {double quantity = 1}) {
  if (value == null || value <= 0) return '—';
  final total = value * (quantity <= 0 ? 1 : quantity);
  final u = (unit == null || unit.trim().isEmpty) ? 'kg' : unit.trim();
  if (total >= 100) return '${Formatters.number(total, decimals: 1)} $u';
  if (total == total.roundToDouble()) return '${Formatters.number(total)} $u';
  return '${Formatters.number(total, decimals: 2)} $u';
}

String formatDimNum(double n) => Formatters.number(n);

String formatArea(double a) {
  if (a <= 0) return '—';
  if (a >= 100) return Formatters.number(a, decimals: 1);
  if (a == a.roundToDouble()) return Formatters.number(a);
  return Formatters.number(a, decimals: 3);
}

String formatWeight(double kg) {
  if (kg <= 0) return '—';
  if (kg >= 100) return '${Formatters.number(kg, decimals: 1)} kg';
  if (kg == kg.roundToDouble()) return '${Formatters.number(kg)} kg';
  return '${Formatters.number(kg, decimals: 2)} kg';
}

String formatMoney(double n) {
  if (n <= 0) return '—';
  if (n == n.roundToDouble()) return Formatters.number(n);
  return Formatters.number(n, decimals: 2);
}

/// Split warehouse location from product notes (first line if known).
(String? location, String notes) splitLocationNotes(String? raw) {
  if (raw == null || raw.trim().isEmpty) return (null, '');
  final lines = raw.split('\n');
  final first = lines.first.trim();
  final isLoc =
      kWarehouseLocations.any((l) => l == first) ||
      first.contains('Warehouse') ||
      RegExp(r'^[A-Z]\d+-\d+').hasMatch(first);
  if (isLoc) {
    final rest = lines.skip(1).join('\n').trim();
    return (first, rest);
  }
  return (null, raw.trim());
}

String joinLocationNotes(String? location, String notes) {
  final loc = location?.trim();
  final n = notes.trim();
  if (loc == null || loc.isEmpty) return n;
  if (n.isEmpty) return loc;
  return '$loc\n$n';
}

const _kMovementLogMarker = '⟦log⟧';

bool _isMovementLogisticsPart(String part) {
  final t = part.trim();
  if (t.isEmpty) return false;
  if (t.startsWith(_kMovementLogMarker)) return true;
  final lower = t.toLowerCase();
  return lower.startsWith('driver:') ||
      lower.startsWith('receiver:') ||
      lower.startsWith('vehicle:') ||
      lower.startsWith('driver details:') ||
      lower.startsWith('receiver details:');
}

/// User remarks only — strips driver / vehicle / logistics from stored notes.
String movementRemarksOnly(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final text = raw.trim();
  if (text.contains('\n$_kMovementLogMarker')) {
    return text.split('\n$_kMovementLogMarker').first.trim();
  }
  if (text.startsWith(_kMovementLogMarker)) return '';
  final parts = text.split(' · ');
  return parts
      .where((p) => !_isMovementLogisticsPart(p))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .join(' · ')
      .trim();
}

/// Driver / receiver / vehicle block from stored movement notes.
String movementLogisticsOnly(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final text = raw.trim();
  if (text.contains('\n$_kMovementLogMarker')) {
    return text.split('\n$_kMovementLogMarker').skip(1).join('\n').trim();
  }
  if (text.startsWith(_kMovementLogMarker)) {
    return text.substring(_kMovementLogMarker.length).trim();
  }
  final parts = text.split(' · ');
  return parts
      .where(_isMovementLogisticsPart)
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .join(' · ')
      .trim();
}

/// Combines user remarks with optional logistics for storage.
String? composeMovementNotes({String? remarks, String? logistics}) {
  final r = (remarks ?? '').trim();
  final l = (logistics ?? '').trim();
  if (r.isEmpty && l.isEmpty) return null;
  if (l.isEmpty) return r;
  if (r.isEmpty) return '$_kMovementLogMarker$l';
  return '$r\n$_kMovementLogMarker$l';
}

/// Builds logistics line from inbound/outbound driver fields.
String buildMovementLogistics({
  required bool inbound,
  String? person,
  String? vehicle,
  String? details,
}) {
  final parts = <String>[
    if ((person ?? '').trim().isNotEmpty)
      '${inbound ? 'Driver' : 'Receiver'}: ${person!.trim()}',
    if ((vehicle ?? '').trim().isNotEmpty) 'Vehicle: ${vehicle!.trim()}',
    if ((details ?? '').trim().isNotEmpty)
      '${inbound ? 'Driver details' : 'Receiver details'}: ${details!.trim()}',
  ];
  return parts.join(' · ');
}

/// Parses stored logistics into editable driver / receiver fields.
({String person, String vehicle, String details}) parseMovementLogistics(
  String? raw,
) {
  var person = '';
  var vehicle = '';
  var details = '';
  final logistics = movementLogisticsOnly(raw);
  if (logistics.isEmpty) {
    return (person: person, vehicle: vehicle, details: details);
  }
  for (final part in logistics.split(' · ')) {
    final p = part.trim();
    if (p.isEmpty) continue;
    final lower = p.toLowerCase();
    if (lower.startsWith('driver:')) {
      person = p.substring(7).trim();
    } else if (lower.startsWith('receiver:')) {
      person = p.substring(9).trim();
    } else if (lower.startsWith('vehicle:')) {
      vehicle = p.substring(8).trim();
    } else if (lower.startsWith('driver details:')) {
      details = p.substring(15).trim();
    } else if (lower.startsWith('receiver details:')) {
      details = p.substring(17).trim();
    }
  }
  return (person: person, vehicle: vehicle, details: details);
}

class WarehouseDialogShell extends StatelessWidget {
  const WarehouseDialogShell({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onCancel,
    this.primaryIcon,
    this.saving = false,
    this.maxHeight = 720,
    this.maxWidth = 440,
    this.scrollBody = true,
    this.fixedHeight = false,
    this.headerAction,
    this.cancelLabel,
    this.dangerPrimary = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget body;
  final String primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final VoidCallback onCancel;
  final bool saving;
  final double maxHeight;
  final double maxWidth;
  final bool scrollBody;

  /// See [GfDialogShell.fixedHeight].
  final bool fixedHeight;

  /// See [GfDialogShell.headerAction].
  final Widget? headerAction;
  final String? cancelLabel;
  final bool dangerPrimary;

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      body: body,
      primaryLabel: primaryLabel,
      primaryIcon: primaryIcon,
      onPrimary: onPrimary,
      onCancel: onCancel,
      cancelLabel: cancelLabel,
      saving: saving,
      dangerPrimary: dangerPrimary,
      scrollBody: scrollBody,
      fixedHeight: fixedHeight,
      headerAction: headerAction,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }
}

/// Two columns on wide dialogs, one column when narrow.
class DialogResponsiveRow extends StatelessWidget {
  const DialogResponsiveRow({
    super.key,
    required this.children,
    this.gap = 12,
    this.breakpoint = 420,
  });

  final List<Widget> children;
  final double gap;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        // Unbounded maxWidth (e.g. inside unconstrained scroll) → use screen.
        final width = maxW.isFinite ? maxW : MediaQuery.sizeOf(context).width;
        if (width < breakpoint || children.length == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

class DialogInfoBanner extends StatelessWidget {
  const DialogInfoBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kDialogInfoBlue,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DialogAreaBox extends StatelessWidget {
  const DialogAreaBox({super.key, required this.areaLabel, this.weightLabel});

  final String areaLabel;
  final String? weightLabel;

  @override
  Widget build(BuildContext context) {
    final showWeight = weightLabel != null && weightLabel!.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: _MetricBox(
            icon: Icons.square_foot_outlined,
            title: 'stockEntry.area'.tr(),
            value: areaLabel,
            hint: 'stockEntry.areaAuto'.tr(),
          ),
        ),
        if (showWeight) ...[
          const SizedBox(width: 12),
          Expanded(
            child: _MetricBox(
              icon: Icons.scale_outlined,
              title: 'stockEntry.weight'.tr(),
              value: weightLabel!,
              hint: 'stockEntry.weightFromProduct'.tr(),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({
    required this.icon,
    required this.title,
    required this.value,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kDialogSoftBlue,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kDialogBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: AppTypography.bodySemiBold.copyWith(fontSize: 18),
                ),
                Text(hint, style: AppTypography.caption.copyWith(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DialogDimensionPreview extends StatelessWidget {
  const DialogDimensionPreview({
    super.key,
    required this.thickness,
    required this.length,
    required this.width,
  });

  final String thickness;
  final String length;
  final String width;

  @override
  Widget build(BuildContext context) {
    final t = thickness.trim().isEmpty ? '0' : thickness.trim();
    final l = length.trim().isEmpty ? '0' : length.trim();
    final w = width.trim().isEmpty ? '0' : width.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kDialogSoftBlue,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kDialogBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.view_in_ar_outlined, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'products.add.dimensionPreview'.tr(),
                  style: AppTypography.caption,
                ),
                Text(
                  '$t × $l × $w',
                  style: AppTypography.bodySemiBold.copyWith(fontSize: 16),
                ),
              ],
            ),
          ),
          Flexible(
            child: Text(
              'products.add.dimensionPreviewHint'.tr(),
              style: AppTypography.caption.copyWith(fontSize: 11),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class DialogProductCard extends StatelessWidget {
  const DialogProductCard({
    super.key,
    required this.product,
    this.showStock = false,
    this.afterStock,
  });

  final ProductModel product;
  final bool showStock;
  final double? afterStock;

  @override
  Widget build(BuildContext context) {
    final hasImage =
        product.imagePath != null &&
        product.imagePath!.isNotEmpty &&
        File(product.imagePath!).existsSync();
    final loc = product.warehouseName ?? splitLocationNotes(product.notes).$1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kDialogSoftBlue,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kDialogBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 64,
              height: 64,
              child: hasImage
                  ? Image.file(File(product.imagePath!), fit: BoxFit.cover)
                  : ColoredBox(
                      color: AppColors.card,
                      child: Icon(
                        Icons.layers_outlined,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.displayName,
                  style: AppTypography.bodySemiBold,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (product.sheetAreaM2 > 0)
                      '${formatArea(product.sheetAreaM2)} m²',
                    if (product.unitWeight != null && product.unitWeight! > 0)
                      product.weightLabel,
                    if (product.thickness != null)
                      formatDimNum(product.thickness!),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: AppTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (product.categoryName != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(
                      product.categoryName!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                if (showStock) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: product.currentStock > 0
                              ? AppColors.success
                              : AppColors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'stockEntry.stockAt'.tr(
                            namedArgs: {
                              'count': formatDimNum(product.currentStock),
                              'location': loc ?? '—',
                            },
                          ),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.success,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (afterStock != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'stockEntry.afterStock'.tr(
                          namedArgs: {'count': formatDimNum(afterStock!)},
                        ),
                        style: AppTypography.caption,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DialogImagePicker extends StatelessWidget {
  const DialogImagePicker({
    super.key,
    required this.imagePath,
    required this.onPick,
    required this.onClear,
  });

  final String? imagePath;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasImage =
        imagePath != null &&
        imagePath!.isNotEmpty &&
        File(imagePath!).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'products.add.fields.productImage'.tr(),
          style: AppTypography.label,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onPick,
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  painter: _DashedBorderPainter(
                    color: AppColors.primary.withValues(alpha: 0.45),
                    radius: 8,
                  ),
                  child: Container(
                    height: 96,
                    decoration: BoxDecoration(
                      color: kDialogSoftBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_outlined,
                          color: AppColors.primary,
                          size: 26,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'products.add.uploadImage'.tr(),
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          'products.add.uploadHint'.tr(),
                          style: AppTypography.caption.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Stack(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kDialogBorder),
                    color: AppColors.input,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasImage
                      ? Image.file(File(imagePath!), fit: BoxFit.cover)
                      : Icon(Icons.layers_outlined, color: AppColors.textMuted),
                ),
                if (hasImage)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: InkWell(
                      onTap: onClear,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
