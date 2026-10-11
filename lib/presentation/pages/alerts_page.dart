import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_routes.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/report_models.dart';
import '../providers/alerts_count_provider.dart';
import '../widgets/app_shell.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  bool _loading = true;
  String? _error;
  List<InventoryAlert> _alerts = const [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ServiceLocator.instance.products.getAlerts(limit: 200);
    if (!mounted) return;
    result.when(
      success: (v) {
        setState(() {
          _alerts = v;
          _loading = false;
        });
        context.read<AlertsCountProvider>().setCount(v.length);
      },
      failure: (f) {
        setState(() {
          _error = f.message;
          _loading = false;
        });
      },
    );
  }

  List<InventoryAlert> get _filtered {
    if (_filter == 'all') return _alerts;
    return _alerts.where((a) {
      return switch (_filter) {
        'stock' => a.isStockAlert,
        'expiry' => a.isExpiryAlert,
        'expired' => a.status == 'expired',
        'lowStock' => a.status == 'lowStock' || a.status == 'Low Stock',
        'outOfStock' => a.status == 'outOfStock' || a.status == 'Out of Stock',
        'expiringSoon' => a.status == 'expiringSoon',
        _ => true,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return PageScaffold(
      title: 'alerts.title'.tr(),
      subtitle: 'alerts.subtitle'.tr(),
      actions: [
        GfSecondaryButton(
          label: 'common.refresh'.tr(),
          icon: Icons.refresh,
          onPressed: _load,
        ),
      ],
      body: _loading
          ? const GfPageLoader()
          : _error != null
          ? GfEmptyState(title: _error!, compact: true)
          : Column(
              // crossAxisAlignment: CrossAxisAlignment.,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      GfCountBox(
                        label: 'alerts.totalCount'.tr(),
                        count: _alerts.length,
                        icon: AppAssets.alertFilled,
                      ),
                      SizedBox(
                        width: 180,
                        child: GfDropdown<String>(
                          items: const [
                            'all',
                            'stock',
                            'expiry',
                            'outOfStock',
                            'lowStock',
                            'expiringSoon',
                            'expired',
                          ],
                          value: _filter,
                          labelBuilder: (v) => 'alerts.filters.$v'.tr(),
                          prefixIcon: Icons.filter_list_rounded,
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _filter = v);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: GfDataTable(
                    title: 'alerts.tableTitle'.tr(),
                    minWidth: gfTableMinWidth(context, preferred: 800),
                    columns: [
                      GfTableColumn(label: 'warehouse.product'.tr(), flex: 3),
                      GfTableColumn(
                        label: 'products.columns.category'.tr(),
                        flex: 2,
                      ),
                      GfTableColumn(label: 'warehouse.quantity'.tr(), flex: 1),
                      GfTableColumn(label: 'alerts.columns.type'.tr(), flex: 2),
                      GfTableColumn(
                        label: 'products.add.fields.expiration'.tr(),
                        flex: 2,
                      ),
                    ],
                    rowCount: items.length,
                    total: items.length,
                    clientSide: true,
                    itemLabel: 'overview.alertItems'.tr(),
                    empty: GfEmptyState(
                      title: 'alerts.empty'.tr(),
                      subtitle: 'alerts.emptyHint'.tr(),
                      compact: true,
                    ),
                    rowBuilder: (context, i) {
                      final a = items[i];
                      return GfTableRow(
                        onTap: () => context.go(AppRoutes.products),
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  a.name,
                                  style: AppTypography.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  [
                                    if (a.sku != null && a.sku!.isNotEmpty)
                                      a.sku!,
                                    if (a.brand != null && a.brand!.isNotEmpty)
                                      a.brand!,
                                  ].join(' · '),
                                  style: AppTypography.caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              a.categoryName ?? '—',
                              style: AppTypography.body,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              Formatters.number(a.currentStock),
                              style: AppTypography.body,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: _AlertBadge(status: a.status),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              a.expirationDate == null
                                  ? '—'
                                  : Formatters.date(a.expirationDate!),
                              style: AppTypography.body,
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
}

class _AlertBadge extends StatelessWidget {
  const _AlertBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'expired' => ('alerts.status.expired'.tr(), AppColors.error),
      'outOfStock' ||
      'Out of Stock' => ('alerts.status.outOfStock'.tr(), AppColors.error),
      'expiringSoon' => ('alerts.status.expiringSoon'.tr(), AppColors.warning),
      'lowStock' ||
      'Low Stock' => ('alerts.status.lowStock'.tr(), AppColors.warning),
      _ => (status, AppColors.textMuted),
    };
    return GfStatusBadge(label: label, color: color, compact: true);
  }
}
