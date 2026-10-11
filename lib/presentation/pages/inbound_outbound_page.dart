import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:pos_general/core/constants/app_assets.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/pdf_report_helper.dart';
import '../../core/utils/shamsi_dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/stock_movement_model.dart';
import '../dialogs/inbound_outbound_dialogs.dart';
import '../dialogs/movement_record_dialogs.dart';
import '../dialogs/warehouse_dialog_shared.dart';
import '../viewmodels/module_viewmodels.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_shell.dart';

enum _MovementFilter { all, inbound, outbound }

class InboundOutboundPage extends StatelessWidget {
  const InboundOutboundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => InventoryViewModel()..load(),
      child: const _InboundOutboundView(),
    );
  }
}

class _InboundOutboundView extends StatefulWidget {
  const _InboundOutboundView();

  @override
  State<_InboundOutboundView> createState() => _InboundOutboundViewState();
}

class _InboundOutboundViewState extends State<_InboundOutboundView> {
  final _search = TextEditingController();
  _MovementFilter _filter = _MovementFilter.all;
  DateFilterValue _dateFilter = DateFilterValue.today();
  bool _sharing = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _isInbound(StockMovementModel m) => m.quantity >= 0;

  bool _isPurchase(StockMovementModel m) =>
      m.movementType == StockMovementType.purchase ||
      m.movementType == StockMovementType.returnIn;

  bool _isSale(StockMovementModel m) =>
      m.movementType == StockMovementType.sale ||
      m.movementType == StockMovementType.returnOut;

  String _movementStatusLabel(StockMovementModel m) {
    if (_isPurchase(m)) return 'inboundOutbound.inbound'.tr();
    if (_isSale(m)) return 'inboundOutbound.outbound'.tr();
    return m.movementType.label;
  }

  List<StockMovementModel> _filtered(List<StockMovementModel> all) {
    final q = _search.text.trim().toLowerCase();
    return all.where((m) {
      if (!_dateFilter.contains(m.createdAt)) return false;
      // All = complete dataset, not only purchases and sales.
      final matchFilter = switch (_filter) {
        _MovementFilter.all => true,
        _MovementFilter.inbound => _isPurchase(m),
        _MovementFilter.outbound => _isSale(m),
      };
      if (!matchFilter) return false;
      if (q.isEmpty) return true;
      final hay =
          '${m.productName ?? ''} ${m.partnerName ?? ''} ${m.referenceType ?? ''} ${m.notes ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  /// Date + search only (direction comes from the PDF option dialog).
  List<StockMovementModel> _pdfSource(List<StockMovementModel> all) {
    final q = _search.text.trim().toLowerCase();
    return all.where((m) {
      if (!_dateFilter.contains(m.createdAt)) return false;
      if (q.isEmpty) return true;
      final hay =
          '${m.productName ?? ''} ${m.partnerName ?? ''} ${m.referenceType ?? ''} ${m.notes ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _shareFiltered(List<StockMovementModel> source) async {
    if (_sharing) return;
    if (!_dateFilter.supportsPdfExport) {
      GfToast.error(context, 'pdfReport.pdfNotForYear'.tr());
      return;
    }
    final kind = await _pickPdfExportKind();
    if (kind == null || !mounted) return;

    final scoped = switch (kind) {
      PdfMovementExportKind.inbound => source.where(_isInbound).toList(),
      PdfMovementExportKind.outbound =>
        source.where((m) => !_isInbound(m)).toList(),
      PdfMovementExportKind.both => source,
    };

    setState(() => _sharing = true);
    try {
      final bytes = await PdfReportHelper.buildMovementsInvoice(
        context,
        periodLabel: _dateFilter.exportPeriodLabel,
        kind: kind,
        movements: scoped,
      );
      if (!mounted) return;
      final tag = switch (kind) {
        PdfMovementExportKind.outbound => 'outbound',
        PdfMovementExportKind.inbound => 'inbound',
        PdfMovementExportKind.both => 'both',
      };
      await PdfReportHelper.savePdf(
        context,
        bytes: bytes,
        fileName: 'glassflow_invoice_${tag}_${PdfReportHelper.stamp()}.pdf',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Print a single movement invoice (no save dialog).
  Future<void> _printMovement(StockMovementModel m) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final inbound = _isInbound(m);
      final kind = inbound
          ? PdfMovementExportKind.inbound
          : PdfMovementExportKind.outbound;
      final bytes = await PdfReportHelper.buildMovementsInvoice(
        context,
        periodLabel: ShamsiDates.formatRange(m.createdAt, m.createdAt),
        kind: kind,
        movements: [m],
      );
      if (!mounted) return;
      final tag = inbound ? 'inbound' : 'outbound';
      await PdfReportHelper.printPdf(
        context,
        bytes: bytes,
        fileName:
            'glassflow_invoice_${tag}_${m.id}_${PdfReportHelper.stamp()}.pdf',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<PdfMovementExportKind?> _pickPdfExportKind() {
    return showDialog<PdfMovementExportKind>(
      context: context,
      builder: (ctx) {
        Widget option({
          required PdfMovementExportKind kind,
          required String title,
          required String hint,
          required IconData icon,
          required Color color,
        }) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(ctx).pop(kind),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: AppTypography.localize(
                                AppTypography.bodySemiBold,
                                context: ctx,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hint,
                              style: AppTypography.localize(
                                AppTypography.caption,
                                context: ctx,
                              ).copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return GfDialogShell(
          icon: Icons.receipt_long_outlined,
          title: 'inboundOutbound.pdfOptionsTitle'.tr(),
          subtitle: 'inboundOutbound.pdfOptionsSubtitle'.tr(),
          onCancel: () => Navigator.of(ctx).pop(),
          maxWidth: 420,
          maxHeight: 420,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(
                kind: PdfMovementExportKind.outbound,
                title: 'inboundOutbound.pdfOutbound'.tr(),
                hint: 'inboundOutbound.pdfOutboundHint'.tr(),
                icon: Icons.south_west_rounded,
                color: AppColors.error,
              ),
              option(
                kind: PdfMovementExportKind.inbound,
                title: 'inboundOutbound.pdfInbound'.tr(),
                hint: 'inboundOutbound.pdfInboundHint'.tr(),
                icon: Icons.north_east_rounded,
                color: AppColors.success,
              ),
              option(
                kind: PdfMovementExportKind.both,
                title: 'inboundOutbound.pdfBoth'.tr(),
                hint: 'inboundOutbound.pdfBothHint'.tr(),
                icon: Icons.swap_vert_rounded,
                color: AppColors.primary,
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<InventoryViewModel>();
    final canSeePurchase = context.watch<AuthProvider>().canViewPurchaseData;
    final inPeriod = vm.movements
        .where((m) => _dateFilter.contains(m.createdAt))
        .toList();
    final movements = _filtered(vm.movements);
    final inboundToday = vm.movements
        .where((m) => _isPurchase(m) && _isToday(m.createdAt))
        .length;
    final outboundToday = vm.movements
        .where((m) => _isSale(m) && _isToday(m.createdAt))
        .length;
    final inboundCount = inPeriod.where(_isPurchase).length;
    final outboundCount = inPeriod.where(_isSale).length;

    return PageScaffold(
      title: 'inboundOutbound.title'.tr(),
      subtitle: 'inboundOutbound.subtitle'.tr(),
      searchController: _search,
      searchHint: 'inboundOutbound.searchHint'.tr(),
      onSearch: (_) => setState(() {}),
      actions: [
        GfPrimaryButton(
          label: 'inboundOutbound.newInbound'.tr(),
          icon: Icons.add,
          onPressed: () => _openMovement(context, vm, inbound: true),
        ),
        GfSecondaryButton(
          label: 'inboundOutbound.newOutbound'.tr(),
          icon: Icons.remove,
          onPressed: () => _openMovement(context, vm, inbound: false),
        ),
      ],
      body: vm.loading
          ? const GfPageLoader()
          : Column(
              children: [
                GfKpiGrid(
                  children: [
                    GfKpiCard(
                      title: 'inboundOutbound.todayInbound'.tr(),
                      value: '$inboundToday',
                      icon: AppAssets.inventory,
                    ),
                    GfKpiCard(
                      title: 'inboundOutbound.todayOutbound'.tr(),
                      value: '$outboundToday',
                      icon: AppAssets.sales,
                    ),
                    GfKpiCard(
                      title: 'inboundOutbound.totalMovement'.tr(),
                      value: '${inboundToday + outboundToday}',
                      icon: AppAssets.product,
                    ),
                    GfCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'inboundOutbound.today'.tr(),
                            style: AppTypography.bodySemiBold,
                          ),
                          const SizedBox(height: 10),
                          _MiniStat(
                            label: 'inboundOutbound.inbound'.tr(),
                            value: '$inboundToday',
                            color: AppColors.success,
                          ),
                          const SizedBox(height: 6),
                          _MiniStat(
                            label: 'inboundOutbound.outbound'.tr(),
                            value: '$outboundToday',
                            color: AppColors.error,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: gfSectionGap(context)),
                Expanded(
                  child: GfDataTable(
                    key: ValueKey(
                      'io_${_filter.name}_${_dateFilter.period.name}_'
                      '${_dateFilter.from.millisecondsSinceEpoch}_'
                      '${_dateFilter.to.millisecondsSinceEpoch}_'
                      '${_search.text}',
                    ),
                    title: 'inboundOutbound.transactions'.tr(),
                    minWidth: gfTableMinWidth(context, preferred: 1100),
                    tabs: GfScrollableRow(
                      children: [
                        _FilterChip(
                          label:
                              '${'common.all'.tr()} (${inPeriod.length})',
                          selected: _filter == _MovementFilter.all,
                          onTap: () =>
                              setState(() => _filter = _MovementFilter.all),
                        ),
                        _FilterChip(
                          label:
                              '${'inboundOutbound.inbound'.tr()} ($inboundCount)',
                          selected: _filter == _MovementFilter.inbound,
                          onTap: () => setState(
                            () => _filter = _MovementFilter.inbound,
                          ),
                        ),
                        _FilterChip(
                          label:
                              '${'inboundOutbound.outbound'.tr()} ($outboundCount)',
                          selected: _filter == _MovementFilter.outbound,
                          onTap: () => setState(
                            () => _filter = _MovementFilter.outbound,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      GfDateFilter(
                        value: _dateFilter,
                        onChanged: (v) => setState(() => _dateFilter = v),
                      ),
                      if (AppConstants.enablePdfExport)
                        GfSecondaryButton(
                          label: 'common.generatePdf'.tr(),
                          icon: Icons.ios_share_rounded,
                          compact: true,
                          isLoading: _sharing,
                          onPressed: _sharing || !_dateFilter.supportsPdfExport
                              ? null
                              : () => _shareFiltered(_pdfSource(vm.movements)),
                        ),
                    ],
                    columns: [
                      GfTableColumn(label: 'common.date'.tr(), flex: 2),
                      GfTableColumn(label: 'common.status'.tr(), flex: 2),
                      GfTableColumn(label: 'common.product'.tr(), flex: 3),
                      GfTableColumn(
                        label: 'common.quantity'.tr(),
                        flex: 2,
                      ),
                      GfTableColumn(
                        label: 'inboundOutbound.unitPrice'.tr(),
                        flex: 2,
                      ),
                      GfTableColumn(
                        label: 'inboundOutbound.partner'.tr(),
                        flex: 2,
                      ),
                      GfTableColumn(
                        label: 'inboundOutbound.notes'.tr(),
                        flex: 2,
                      ),
                      const GfTableColumn(label: '', width: 48),
                    ],
                    rowCount: movements.length,
                    total: movements.length,
                    clientSide: true,
                    itemLabel: 'common.records'.tr(),
                    empty: GfEmptyState(
                      title: 'inboundOutbound.empty'.tr(),
                      subtitle: 'inboundOutbound.emptyHint'.tr(),
                      compact: true,
                    ),
                    rowBuilder: (context, i) {
                      final m = movements[i];
                      final inbound = _isInbound(m);
                      final remarksText = movementRemarksOnly(m.notes);
                      return GfTableRow(
                        onTap: () => MovementRecordDialogs.showDetails(context, m),
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              Formatters.date(m.createdAt),
                              style: AppTypography.body,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: GfStatusBadge(
                                label: _movementStatusLabel(m),
                                color: inbound
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              m.productName ?? '—',
                              style: AppTypography.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${inbound ? '+' : ''}${Formatters.number(m.quantity)}',
                              style: AppTypography.bodyMedium.copyWith(
                                color: inbound
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              (!inbound || canSeePurchase) &&
                                      m.unitPrice != null
                                  ? Formatters.money(
                                      m.unitPrice!,
                                      currency: m.currencyCode ?? 'AFN',
                                    )
                                  : '—',
                              style: AppTypography.body,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              m.partnerName ?? '—',
                              style: AppTypography.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: remarksText.isEmpty
                                ? Text('—', style: AppTypography.body)
                                : Tooltip(
                                    message: remarksText,
                                    waitDuration:
                                        const Duration(milliseconds: 400),
                                    child: Text(
                                      remarksText,
                                      style: AppTypography.body.copyWith(
                                        color: AppColors.primary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                          ),
                          SizedBox(
                            width: 48,
                            child: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18),
                              color: AppColors.modal,
                              onSelected: (action) async {
                                if (action == 'view') {
                                  await MovementRecordDialogs.showDetails(context, m);
                                } else if (action == 'edit') {
                                  final saved =
                                      await MovementRecordDialogs.edit(context, m);
                                  if (saved) await vm.load();
                                } else if (action == 'print') {
                                  await _printMovement(m);
                                } else if (action == 'delete') {
                                  final deleted =
                                      await MovementRecordDialogs.delete(context, m);
                                  if (deleted) await vm.load();
                                }
                              },
                              itemBuilder: (_) => [
                                gfPopupMenuItem(
                                  value: 'view',
                                  label: 'common.view'.tr(),
                                ),
                                gfPopupMenuItem(
                                  value: 'edit',
                                  label: 'common.edit'.tr(),
                                ),
                                if (AppConstants.enablePrint)
                                  gfPopupMenuItem(
                                    value: 'print',
                                    label: 'common.print'.tr(),
                                  ),
                                gfPopupMenuItem(
                                  value: 'delete',
                                  label: 'common.delete'.tr(),
                                  danger: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  Future<void> _openMovement(
    BuildContext context,
    InventoryViewModel vm, {
    required bool inbound,
  }) async {
    final saved = inbound
        ? await InboundStockDialog.show(context)
        : await OutboundStockDialog.show(context);
    if (saved == true) {
      await vm.load();
      if (context.mounted) {
        GfToast.success(context, 'inventory.movementRecorded'.tr());
      }
    }
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: AppTypography.caption)),
        Text(
          '$value ${'inboundOutbound.transactionsLabel'.tr()}',
          style: AppTypography.bodyMedium,
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
