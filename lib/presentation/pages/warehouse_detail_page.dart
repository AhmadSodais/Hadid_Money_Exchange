import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_routes.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/product_model.dart';
import '../../data/models/stock_movement_model.dart';
import '../../data/models/warehouse_model.dart';
import '../widgets/app_shell.dart';

enum _DetailTab { products, movements }

enum _MovementFilter { all, inbound, outbound }

class WarehouseDetailPage extends StatefulWidget {
  const WarehouseDetailPage({super.key, required this.warehouseId});

  final int warehouseId;

  @override
  State<WarehouseDetailPage> createState() => _WarehouseDetailPageState();
}

class _WarehouseDetailPageState extends State<WarehouseDetailPage> {
  final _search = TextEditingController();
  // Default to this year so warehouse history is visible (not only today).
  DateFilterValue _dateFilter = DateFilterValue.thisYear();
  _DetailTab _tab = _DetailTab.movements;
  _MovementFilter _movementFilter = _MovementFilter.all;
  WarehouseModel? _warehouse;
  List<StockMovementModel> _movements = const [];
  List<ProductModel> _products = const [];
  int _movementsPage = 1;
  int _movementsPageSize = 50;
  int _movementsTotal = 0;
  int _allMovementsTotal = 0;
  int _inboundTotal = 0;
  int _outboundTotal = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String? get _directionParam => switch (_movementFilter) {
    _MovementFilter.all => null,
    _MovementFilter.inbound => 'inbound',
    _MovementFilter.outbound => 'outbound',
  };

  Future<void> _load({int? movementsPage}) async {
    final nextPage = movementsPage ?? _movementsPage;
    setState(() => _loading = true);
    final repo = ServiceLocator.instance.warehouses;
    final wh = await repo.getById(
      widget.warehouseId,
      from: _dateFilter.from,
      to: _dateFilter.to,
    );
    final offset = (nextPage - 1) * _movementsPageSize;
    final moves = await repo.getMovements(
      widget.warehouseId,
      from: _dateFilter.from,
      to: _dateFilter.to,
      limit: _movementsPageSize,
      offset: offset,
      direction: _directionParam,
    );
    final total = await repo.countMovements(
      widget.warehouseId,
      from: _dateFilter.from,
      to: _dateFilter.to,
      direction: _directionParam,
    );
    final allTotal = await repo.countMovements(
      widget.warehouseId,
      from: _dateFilter.from,
      to: _dateFilter.to,
    );
    final inbound = await repo.countMovements(
      widget.warehouseId,
      from: _dateFilter.from,
      to: _dateFilter.to,
      direction: 'inbound',
    );
    final outbound = await repo.countMovements(
      widget.warehouseId,
      from: _dateFilter.from,
      to: _dateFilter.to,
      direction: 'outbound',
    );
    final products = await repo.getProducts(widget.warehouseId, limit: 500);
    if (!mounted) return;
    setState(() {
      _warehouse = wh.when(success: (v) => v, failure: (_) => null);
      _movements = moves.when(success: (v) => v, failure: (_) => const []);
      _movementsTotal = total.when(success: (v) => v, failure: (_) => 0);
      _allMovementsTotal =
          allTotal.when(success: (v) => v, failure: (_) => 0);
      _inboundTotal = inbound.when(success: (v) => v, failure: (_) => 0);
      _outboundTotal = outbound.when(success: (v) => v, failure: (_) => 0);
      _movementsPage = nextPage;
      _products = products.when(success: (v) => v, failure: (_) => const []);
      _loading = false;
    });
  }

  bool _isInbound(StockMovementModel m) => m.quantity >= 0;

  /// Purchases tab: commercial stock-in (purchase / return in).
  bool _isPurchase(StockMovementModel m) =>
      m.movementType == StockMovementType.purchase ||
      m.movementType == StockMovementType.returnIn;

  /// Sales tab: commercial stock-out (sale / return out).
  bool _isSale(StockMovementModel m) =>
      m.movementType == StockMovementType.sale ||
      m.movementType == StockMovementType.returnOut;

  String _movementStatusLabel(StockMovementModel m) {
    if (_isPurchase(m)) return 'warehouses.inbound'.tr();
    if (_isSale(m)) return 'warehouses.outbound'.tr();
    return m.movementType.label;
  }

  List<ProductModel> get _filteredProducts {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products.where((p) {
      final hay = '${p.name} ${p.sku} ${p.categoryName ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  List<StockMovementModel> get _filteredMovements {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _movements;
    return _movements.where((m) {
      final hay =
          '${m.productName ?? ''} ${m.partnerName ?? ''} ${m.notes ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final w = _warehouse;
    final products = _filteredProducts;
    final movements = _filteredMovements;
    final purchaseCount = _inboundTotal;
    final salesCount = _outboundTotal;
    final subtitle = w == null
        ? 'warehouses.detailSubtitle'.tr()
        : [
            if (w.address != null && w.address!.trim().isNotEmpty)
              w.address!.trim(),
            'warehouses.detailSubtitle'.tr(),
          ].join(' · ');

    return PageScaffold(
      leading: Row(
        children: [
          GfIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'common.back'.tr(),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.warehouses);
              }
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w?.name ?? 'warehouses.title'.tr(),
                  style: AppTypography.localize(
                    AppTypography.pageTitle,
                    context: context,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTypography.localize(
                    AppTypography.subtitle,
                    context: context,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      title: w?.name ?? 'warehouses.title'.tr(),
      searchController: _search,
      searchHint: 'common.search'.tr(),
      onSearch: (_) => setState(() {}),
      actions: [
        GfDateFilter(
          value: _dateFilter,
          onChanged: (v) {
            setState(() {
              _dateFilter = v;
              _movementsPage = 1;
            });
            _load(movementsPage: 1);
          },
        ),
      ],
      body: _loading && w == null
          ? const GfPageLoader()
          : w == null
          ? GfEmptyState(
              title: 'warehouses.notFound'.tr(),
              subtitle: 'warehouses.notFoundHint'.tr(),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GfKpiGrid(
                  children: [
                    GfKpiCard(
                      title: 'warehouses.inbound'.tr(),
                      value: Formatters.number(w.inboundQty),
                      icon: AppAssets.inventory,
                      onTap: () {
                        setState(() {
                          _tab = _DetailTab.movements;
                          _movementFilter = _MovementFilter.inbound;
                          _movementsPage = 1;
                        });
                        _load(movementsPage: 1);
                      },
                    ),
                    GfKpiCard(
                      title: 'warehouses.outbound'.tr(),
                      value: Formatters.number(w.outboundQty),
                      icon: AppAssets.sales,
                      tone: GfKpiTone.error,
                      onTap: () {
                        setState(() {
                          _tab = _DetailTab.movements;
                          _movementFilter = _MovementFilter.outbound;
                          _movementsPage = 1;
                        });
                        _load(movementsPage: 1);
                      },
                    ),
                    GfKpiCard(
                      title: 'warehouses.products'.tr(),
                      value: Formatters.number(w.productCount),
                      icon: AppAssets.product,
                      onTap: () => setState(() {
                        _tab = _DetailTab.products;
                      }),
                    ),
                    GfKpiCard(
                      title: 'warehouses.stock'.tr(),
                      value: Formatters.number(w.stockQty),
                      icon: AppAssets.inventoryFilled,
                      tone: GfKpiTone.warning,
                      onTap: () {
                        setState(() {
                          _tab = _DetailTab.movements;
                          _movementFilter = _MovementFilter.all;
                          _movementsPage = 1;
                        });
                        _load(movementsPage: 1);
                      },
                    ),
                  ],
                ),
                SizedBox(height: gfSectionGap(context)),
                Expanded(
                  child: GfDataTable(
                    key: ValueKey(
                      '$_tab-$_movementFilter-'
                      '${_dateFilter.period.name}-'
                      '${_dateFilter.from.millisecondsSinceEpoch}-'
                      '${_dateFilter.to.millisecondsSinceEpoch}',
                    ),
                    title: _tab == _DetailTab.products
                        ? 'warehouses.productsInWarehouse'.tr()
                        : 'warehouses.movements'.tr(),
                    subtitle: _dateFilter.displayLabel,
                    minWidth: gfTableMinWidth(context, preferred: 720),
                    isLoading: _loading,
                    tabs: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label:
                                '${'warehouses.products'.tr()} (${_products.length})',
                            selected: _tab == _DetailTab.products,
                            onTap: () =>
                                setState(() => _tab = _DetailTab.products),
                          ),
                          _FilterChip(
                            label:
                                '${'common.all'.tr()} (${_allMovementsTotal})',
                            selected:
                                _tab == _DetailTab.movements &&
                                _movementFilter == _MovementFilter.all,
                            onTap: () {
                              setState(() {
                                _tab = _DetailTab.movements;
                                _movementFilter = _MovementFilter.all;
                                _movementsPage = 1;
                              });
                              _load(movementsPage: 1);
                            },
                          ),
                          _FilterChip(
                            label:
                                '${'warehouses.inbound'.tr()} ($purchaseCount)',
                            selected:
                                _tab == _DetailTab.movements &&
                                _movementFilter == _MovementFilter.inbound,
                            onTap: () {
                              setState(() {
                                _tab = _DetailTab.movements;
                                _movementFilter = _MovementFilter.inbound;
                                _movementsPage = 1;
                              });
                              _load(movementsPage: 1);
                            },
                          ),
                          _FilterChip(
                            label:
                                '${'warehouses.outbound'.tr()} ($salesCount)',
                            selected:
                                _tab == _DetailTab.movements &&
                                _movementFilter == _MovementFilter.outbound,
                            onTap: () {
                              setState(() {
                                _tab = _DetailTab.movements;
                                _movementFilter = _MovementFilter.outbound;
                                _movementsPage = 1;
                              });
                              _load(movementsPage: 1);
                            },
                          ),
                        ],
                      ),
                    ),
                    columns: _tab == _DetailTab.products
                        ? [
                            GfTableColumn(
                              label: 'common.product'.tr(),
                              flex: 3,
                            ),
                            GfTableColumn(
                              label: 'products.columns.category'.tr(),
                              flex: 2,
                            ),
                            GfTableColumn(
                              label: 'common.quantity'.tr(),
                              flex: 1,
                            ),
                          ]
                        : [
                            GfTableColumn(label: 'common.date'.tr(), flex: 2),
                            GfTableColumn(label: 'common.status'.tr(), flex: 2),
                            GfTableColumn(
                              label: 'common.product'.tr(),
                              flex: 3,
                            ),
                            GfTableColumn(
                              label: 'inboundOutbound.partner'.tr(),
                              flex: 2,
                            ),
                            GfTableColumn(
                              label: 'common.quantity'.tr(),
                              flex: 2,
                            ),
                          ],
                    rowCount: _tab == _DetailTab.products
                        ? products.length
                        : movements.length,
                    total: _tab == _DetailTab.products
                        ? products.length
                        : _movementsTotal,
                    page: _tab == _DetailTab.products ? 1 : _movementsPage,
                    pageSize: _movementsPageSize,
                    clientSide: _tab == _DetailTab.products,
                    autoPageSize: _tab == _DetailTab.movements,
                    onPageChanged: _tab == _DetailTab.products
                        ? null
                        : (p) => _load(movementsPage: p),
                    onPageSizeChanged: _tab == _DetailTab.products
                        ? null
                        : (size) {
                            if (size == _movementsPageSize) return;
                            setState(() {
                              _movementsPageSize = size;
                              _movementsPage = 1;
                            });
                            _load(movementsPage: 1);
                          },
                    itemLabel: 'common.records'.tr(),
                    empty: GfEmptyState(
                      title: _tab == _DetailTab.products
                          ? 'warehouses.noProducts'.tr()
                          : 'warehouses.noMovements'.tr(),
                      subtitle: _tab == _DetailTab.products
                          ? null
                          : _dateFilter.displayLabel,
                      compact: true,
                    ),
                    rowBuilder: (context, i) {
                      if (_tab == _DetailTab.products) {
                        return _productRow(products[i]);
                      }
                      return _movementRow(movements[i]);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  GfTableRow _productRow(ProductModel p) {
    return GfTableRow(
      children: [
        Expanded(
          flex: 3,
          child: Row(
            children: [
              _ProductThumb(path: p.imagePath),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  p.name,
                  style: AppTypography.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            p.categoryName ?? '—',
            style: AppTypography.body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Text(
            Formatters.number(p.currentStock),
            style: AppTypography.body,
          ),
        ),
      ],
    );
  }

  GfTableRow _movementRow(StockMovementModel m) {
    final inbound = _isInbound(m);
    return GfTableRow(
      children: [
        Expanded(
          flex: 2,
          child: Text(Formatters.date(m.createdAt), style: AppTypography.body),
        ),
        Expanded(
          flex: 2,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: GfStatusBadge(
              label: _movementStatusLabel(m),
              color: inbound ? AppColors.success : AppColors.error,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              _ProductThumb(path: m.productImagePath),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  m.productName ?? '—',
                  style: AppTypography.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
          child: Text(
            '${inbound ? '+' : ''}${Formatters.number(m.quantity)}',
            style: AppTypography.bodyMedium.copyWith(
              color: inbound ? AppColors.success : AppColors.error,
            ),
          ),
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
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final hasImage =
        path != null && path!.isNotEmpty && File(path!).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 36,
        height: 36,
        child: hasImage
            ? Image.file(File(path!), fit: BoxFit.cover)
            : ColoredBox(
                color: AppColors.input,
                child: Icon(
                  Icons.layers_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
      ),
    );
  }
}
