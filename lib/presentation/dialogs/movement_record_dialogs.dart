import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/shamsi_dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/currency_model.dart';
import '../../data/models/stock_movement_model.dart';
import '../../data/models/warehouse_model.dart';
import '../widgets/permission_gate.dart';
import 'warehouse_dialog_shared.dart';

/// Shared view / edit / delete flows for purchase & sale stock movements.
abstract final class MovementRecordDialogs {
  static bool isInbound(StockMovementModel m) => m.quantity >= 0;

  static bool isPurchase(StockMovementModel m) =>
      m.movementType == StockMovementType.purchase ||
      m.movementType == StockMovementType.returnIn;

  static bool isSale(StockMovementModel m) =>
      m.movementType == StockMovementType.sale ||
      m.movementType == StockMovementType.returnOut;

  static String statusLabel(StockMovementModel m) {
    if (isPurchase(m)) return 'inboundOutbound.inbound'.tr();
    if (isSale(m)) return 'inboundOutbound.outbound'.tr();
    return m.movementType.label;
  }

  static Future<void> showDetails(
    BuildContext context,
    StockMovementModel m,
  ) {
    final inbound = isInbound(m);
    final accent = inbound ? AppColors.success : AppColors.error;
    final remarks = movementRemarksOnly(m.notes);
    final logistics = movementLogisticsOnly(m.notes);
    final showPurchaseMoney = !inbound || canViewPurchaseData(context);
    final priceText = !showPurchaseMoney || m.unitPrice == null
        ? '—'
        : Formatters.money(
            m.unitPrice!,
            currency: m.currencyCode ?? 'AFN',
          );

    return showDialog<void>(
      context: context,
      builder: (ctx) {
        return GfDialogShell(
          icon: inbound
              ? Icons.north_east_rounded
              : Icons.south_west_rounded,
          iconColor: accent,
          title: statusLabel(m),
          subtitle: Formatters.dateTime(m.createdAt),
          onCancel: () => Navigator.of(ctx).pop(),
          cancelLabel: 'common.back'.tr(),
          maxWidth: 560,
          maxHeight: 680,
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MovementDetailHeroCard(
                  productName: m.productName ?? '—',
                  imagePath: m.productImagePath,
                  partnerName: m.partnerName,
                  inbound: inbound,
                  quantity: m.quantity,
                  accent: accent,
                  statusLabel: statusLabel(m),
                ),
                const SizedBox(height: 14),
                MovementDetailSection(
                  title: 'inboundOutbound.detailMetrics'.tr(),
                  child: Column(
                    children: [
                      DialogResponsiveRow(
                        children: [
                          MovementDetailMetric(
                            label: 'inboundOutbound.area'.tr(),
                            value: m.areaM2 <= 0
                                ? '—'
                                : '${formatArea(m.areaM2)} m²',
                          ),
                          MovementDetailMetric(
                            label: 'inboundOutbound.weight'.tr(),
                            value: m.weightLabel,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DialogResponsiveRow(
                        children: [
                          MovementDetailMetric(
                            label: 'inboundOutbound.length'.tr(),
                            value: m.lengthM == null
                                ? '—'
                                : '${dimToDisplay(m.lengthM)} m',
                          ),
                          MovementDetailMetric(
                            label: 'inboundOutbound.width'.tr(),
                            value: m.widthM == null
                                ? '—'
                                : '${dimToDisplay(m.widthM)} m',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DialogResponsiveRow(
                        children: [
                          MovementDetailMetric(
                            label: 'inboundOutbound.unitPrice'.tr(),
                            value: priceText,
                          ),
                          MovementDetailMetric(
                            label: 'inboundOutbound.warehouse'.tr(),
                            value: m.warehouseName ?? '—',
                          ),
                        ],
                      ),
                      if (showPurchaseMoney) ...[
                        const SizedBox(height: 10),
                        DialogResponsiveRow(
                          children: [
                            MovementDetailMetric(
                              label: 'inboundOutbound.lineTotal'.tr(),
                              value: m.unitPrice == null
                                  ? '—'
                                  : Formatters.money(
                                      m.lineTotal,
                                      currency:
                                          (m.currencyCode ?? '').trim().isEmpty
                                              ? 'AFN'
                                              : m.currencyCode!.trim(),
                                    ),
                            ),
                            MovementDetailMetric(
                              label: 'inboundOutbound.paid'.tr(),
                              value: m.unitPrice == null
                                  ? '—'
                                  : Formatters.money(
                                      m.paidAmount,
                                      currency:
                                          (m.currencyCode ?? '').trim().isEmpty
                                              ? 'AFN'
                                              : m.currencyCode!.trim(),
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        MovementDetailMetric(
                          label: 'inboundOutbound.outstanding'.tr(),
                          value: m.unitPrice == null
                              ? '—'
                              : Formatters.money(
                                  m.outstanding,
                                  currency:
                                      (m.currencyCode ?? '').trim().isEmpty
                                          ? 'AFN'
                                          : m.currencyCode!.trim(),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (logistics.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  MovementDetailSection(
                    title: inbound
                        ? 'stockEntry.driverSection'.tr()
                        : 'stockEntry.receiverSection'.tr(),
                    child: Text(logistics, style: AppTypography.body),
                  ),
                ],
                const SizedBox(height: 14),
                MovementDetailSection(
                  title: 'inboundOutbound.notes'.tr(),
                  child: Text(
                    remarks.isEmpty ? '—' : remarks,
                    style: AppTypography.body.copyWith(
                      color: remarks.isEmpty
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                if ((m.employeeName ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  MovementDetailSection(
                    title: 'stockEntry.employee'.tr(),
                    child: Text(
                      m.employeeName!,
                      style: AppTypography.bodyMedium,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Opens the edit dialog and persists changes. Returns `true` if saved.
  static Future<bool> edit(
    BuildContext context,
    StockMovementModel m,
  ) async {
    final result = await showDialog<MovementEditResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => MovementEditDialog(movement: m),
    );
    if (result == null || !context.mounted) return false;
    if (result.quantity <= 0) {
      GfToast.error(context, 'inventory.enterValidQty'.tr());
      return false;
    }
    final r = await ServiceLocator.instance.inventory.updateMovement(
      movementId: m.id,
      quantity: result.quantity,
      notes: result.notes,
      partnerName: result.partnerName,
      lengthM: result.lengthM,
      widthM: result.widthM,
      brokenQty: m.brokenQty,
      unitPrice: result.unitPrice,
      paidAmount: result.paidAmount,
      currencyId: result.currencyId,
      warehouseId: result.warehouseId,
      createdAt: result.createdAt,
    );
    if (!context.mounted) return false;
    return r.when(
      success: (_) {
        GfToast.success(context, 'inboundOutbound.updated'.tr());
        return true;
      },
      failure: (f) {
        GfToast.error(context, f.message);
        return false;
      },
    );
  }

  /// Confirms and deletes a movement. Returns `true` if deleted.
  static Future<bool> delete(
    BuildContext context,
    StockMovementModel m,
  ) async {
    final ok = await GfConfirmDialog.show(
      context,
      title: 'inboundOutbound.deleteTitle'.tr(),
      message: 'inboundOutbound.deleteMessage'.tr(),
      confirmLabel: 'common.delete'.tr(),
      danger: true,
    );
    if (ok != true || !context.mounted) return false;
    final r = await ServiceLocator.instance.inventory.deleteMovement(m.id);
    if (!context.mounted) return false;
    return r.when(
      success: (_) {
        GfToast.success(context, 'inboundOutbound.deleted'.tr());
        return true;
      },
      failure: (f) {
        GfToast.error(context, f.message);
        return false;
      },
    );
  }
}

class MovementDetailHeroCard extends StatelessWidget {
  const MovementDetailHeroCard({
    required this.productName,
    required this.imagePath,
    required this.partnerName,
    required this.inbound,
    required this.quantity,
    required this.accent,
    required this.statusLabel,
  });

  final String productName;
  final String? imagePath;
  final String? partnerName;
  final bool inbound;
  final double quantity;
  final Color accent;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          MovementProductThumb(path: imagePath, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: AppTypography.bodySemiBold.copyWith(fontSize: 16),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  partnerName?.trim().isNotEmpty == true
                      ? partnerName!
                      : '—',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    GfStatusBadge(
                      label: statusLabel,
                      color: accent,
                      compact: true,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${inbound ? '+' : ''}${Formatters.number(quantity)}',
                        style: AppTypography.caption.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MovementDetailSection extends StatelessWidget {
  const MovementDetailSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class MovementDetailMetric extends StatelessWidget {
  const MovementDetailMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class MovementEditResult {
  const MovementEditResult({
    required this.quantity,
    this.unitPrice,
    this.paidAmount,
    this.lengthM,
    this.widthM,
    this.partnerName,
    this.notes,
    this.warehouseId,
    this.currencyId,
    this.createdAt,
  });

  final double quantity;
  final double? unitPrice;
  final double? paidAmount;
  final double? lengthM;
  final double? widthM;
  final String? partnerName;
  final String? notes;
  final int? warehouseId;
  final int? currencyId;
  final DateTime? createdAt;
}

class MovementEditDialog extends StatefulWidget {
  const MovementEditDialog({required this.movement});

  final StockMovementModel movement;

  @override
  State<MovementEditDialog> createState() => MovementEditDialogState();
}

class MovementEditDialogState extends State<MovementEditDialog> {
  late final TextEditingController _qty;
  late final TextEditingController _price;
  late final TextEditingController _paid;
  late final TextEditingController _partner;
  late final TextEditingController _notes;
  late final TextEditingController _length;
  late final TextEditingController _width;
  late final TextEditingController _driver;
  late final TextEditingController _vehicle;
  late final TextEditingController _driverDetails;
  late DateTime _date;
  List<WarehouseModel> _warehouses = const [];
  List<CurrencyModel> _currencies = const [];
  WarehouseModel? _warehouse;
  CurrencyModel? _currency;
  bool _loading = true;

  bool get _isInbound => widget.movement.quantity >= 0;

  @override
  void initState() {
    super.initState();
    final m = widget.movement;
    final logistics = parseMovementLogistics(m.notes);
    _qty = TextEditingController(text: Formatters.number(m.quantity.abs()));
    _price = TextEditingController(
      text: m.unitPrice == null ? '' : Formatters.number(m.unitPrice!),
    );
    _paid = TextEditingController(
      text: m.paidAmount <= 0 ? '' : Formatters.number(m.paidAmount),
    );
    _partner = TextEditingController(text: m.partnerName ?? '');
    _notes = TextEditingController(text: movementRemarksOnly(m.notes));
    _length = TextEditingController(text: dimToDisplay(m.lengthM));
    _width = TextEditingController(text: dimToDisplay(m.widthM));
    _driver = TextEditingController(text: logistics.person);
    _vehicle = TextEditingController(text: logistics.vehicle);
    _driverDetails = TextEditingController(text: logistics.details);
    _date = m.createdAt;
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    final whs = await ServiceLocator.instance.warehouses.list();
    final curs = await ServiceLocator.instance.lookups.getCurrencies();
    if (!mounted) return;
    setState(() {
      _warehouses = whs.when(success: (v) => v, failure: (_) => const []);
      _currencies = curs.when(
        success: (v) => v.where((c) => c.isActive).toList(),
        failure: (_) => const [],
      );
      _warehouse = _warehouses
              .where((w) => w.id == widget.movement.warehouseId)
              .firstOrNull ??
          (_warehouses.isEmpty
              ? null
              : _warehouses.firstWhere(
                  (w) => w.name == widget.movement.warehouseName,
                  orElse: () => _warehouses.first,
                ));
      _currency = _currencies
              .where((c) => c.id == widget.movement.currencyId)
              .firstOrNull ??
          _currencies.where((c) => c.code == widget.movement.currencyCode).firstOrNull;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    _paid.dispose();
    _partner.dispose();
    _notes.dispose();
    _length.dispose();
    _width.dispose();
    _driver.dispose();
    _vehicle.dispose();
    _driverDetails.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await ShamsiDates.pickDate(
      context,
      initial: _date,
    );
    if (picked != null && mounted) {
      setState(() {
        _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        );
      });
    }
  }

  void _save() {
    final qty = Formatters.parse(_qty.text);
    if (qty == null || qty <= 0) return;
    final lengthMm = parseMm(_length.text);
    final widthMm = parseMm(_width.text);
    // Edit dialog uses meters for length/width (default dimension unit).
    final lengthM = lengthMm == null ? null : dimensionToMeters(lengthMm, 'm');
    final widthM = widthMm == null ? null : dimensionToMeters(widthMm, 'm');
    final preservePurchase = _isInbound && !canViewPurchaseData(context);
    Navigator.pop(
      context,
      MovementEditResult(
        quantity: qty,
        unitPrice: preservePurchase
            ? widget.movement.unitPrice
            : Formatters.parse(_price.text),
        paidAmount: preservePurchase
            ? widget.movement.paidAmount
            : (Formatters.parse(_paid.text) ?? 0),
        lengthM: lengthM,
        widthM: widthM,
        partnerName:
            _partner.text.trim().isEmpty ? null : _partner.text.trim(),
        notes: composeMovementNotes(
          remarks: _notes.text,
          logistics: buildMovementLogistics(
            inbound: _isInbound,
            person: _driver.text,
            vehicle: _vehicle.text,
            details: _driverDetails.text,
          ),
        ),
        warehouseId: _warehouse?.id,
        currencyId: preservePurchase
            ? widget.movement.currencyId
            : _currency?.id,
        createdAt: _date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.movement;
    final inbound = _isInbound;
    return GfDialogShell(
      icon: Icons.edit_note_outlined,
      iconColor: AppColors.primary,
      title: 'inboundOutbound.editTitle'.tr(),
      subtitle: 'inboundOutbound.editSubtitle'.tr(),
      primaryLabel: 'common.save'.tr(),
      primaryIcon: Icons.save_outlined,
      onCancel: () => Navigator.pop(context),
      onPrimary: _loading ? null : _save,
      maxWidth: 520,
      maxHeight: 720,
      body: _loading
          ? const SizedBox(
              height: 160,
              child: GfPageLoader(),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  m.productName ?? '—',
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: AppSpacing.controlHeight,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'stockEntry.transactionDate'.tr(),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        suffixIcon:
                            const Icon(Icons.calendar_today, size: 18),
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          ShamsiDates.formatDate(_date),
                          style: AppTypography.body,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GfDropdown<WarehouseModel>(
                  label: 'stockEntry.warehouseLocation'.tr(),
                  required: true,
                  items: _warehouses,
                  value: _warehouse,
                  searchable: true,
                  searchHint: 'common.search'.tr(),
                  hint: 'stockEntry.selectLocation'.tr(),
                  labelBuilder: (w) => w.name,
                  prefixIcon: Icons.location_on_outlined,
                  onChanged: (w) => setState(() => _warehouse = w),
                ),
                const SizedBox(height: 14),
                DialogResponsiveRow(
                  children: [
                    GfTextField(
                      controller: _qty,
                      label: 'common.quantity'.tr(),
                      required: true,
                      numberMode: true,
                    ),
                    if (!_isInbound || canViewPurchaseData(context))
                      GfTextField(
                        controller: _price,
                        label: 'inboundOutbound.unitPrice'.tr(),
                        numberMode: true,
                      ),
                  ],
                ),
                if (!_isInbound || canViewPurchaseData(context)) ...[
                  const SizedBox(height: 14),
                  GfTextField(
                    controller: _paid,
                    label: 'inboundOutbound.paid'.tr(),
                    hint: 'stockEntry.paidHint'.tr(),
                    numberMode: true,
                    prefixIcon: Icons.account_balance_wallet_outlined,
                  ),
                  const SizedBox(height: 14),
                  GfDropdown<CurrencyModel>(
                    label: 'stockEntry.currency'.tr(),
                    items: _currencies,
                    value: _currency,
                    hint: 'stockEntry.selectCurrency'.tr(),
                    labelBuilder: (c) => Formatters.currencyName(c.code),
                    prefixIcon: Icons.attach_money_rounded,
                    onChanged: (c) => setState(() => _currency = c),
                  ),
                ],
                const SizedBox(height: 14),
                DialogResponsiveRow(
                  children: [
                    GfTextField(
                      controller: _length,
                      label: 'stockEntry.length'.tr(),
                      hint: 'stockEntry.lengthHint'.tr(),
                      numberMode: true,
                    ),
                    GfTextField(
                      controller: _width,
                      label: 'stockEntry.width'.tr(),
                      hint: 'stockEntry.widthHint'.tr(),
                      numberMode: true,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                GfTextField(
                  controller: _partner,
                  label: 'inboundOutbound.partner'.tr(),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.badge_outlined,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              inbound
                                  ? 'stockEntry.driverSection'.tr()
                                  : 'stockEntry.receiverSection'.tr(),
                              style: AppTypography.bodySemiBold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'stockEntry.driverSectionHint'.tr(),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DialogResponsiveRow(
                        children: [
                          GfTextField(
                            controller: _driver,
                            label: inbound
                                ? 'stockEntry.driver'.tr()
                                : 'stockEntry.receiver'.tr(),
                            prefixIcon: Icons.person_outline,
                          ),
                          GfTextField(
                            controller: _vehicle,
                            label: 'stockEntry.vehicle'.tr(),
                            prefixIcon: Icons.local_shipping_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GfTextField(
                        controller: _driverDetails,
                        label: 'stockEntry.driverDescription'.tr(),
                        hint: 'stockEntry.driverDescriptionHint'.tr(),
                        prefixIcon: Icons.description_outlined,
                        minLines: 1,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GfTextField(
                  controller: _notes,
                  label: 'inboundOutbound.notes'.tr(),
                  minLines: 1,
                  maxLines: 2,
                ),
              ],
            ),
    );
  }
}

class MovementProductThumb extends StatelessWidget {
  const MovementProductThumb({this.path, this.size = 36});

  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasImage =
        path != null && path!.isNotEmpty && File(path!).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: hasImage
            ? Image.file(File(path!), fit: BoxFit.cover)
            : ColoredBox(
                color: AppColors.input,
                child: Icon(
                  Icons.layers_outlined,
                  size: size * 0.5,
                  color: AppColors.textMuted,
                ),
              ),
      ),
    );
  }
}

