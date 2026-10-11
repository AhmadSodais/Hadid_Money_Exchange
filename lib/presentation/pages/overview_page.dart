import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_general/core/constants/app_assets.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/security/app_permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/gf_pagination.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/report_models.dart';
import '../providers/auth_provider.dart';
import '../viewmodels/overview_viewmodel.dart';
import '../widgets/app_shell.dart';
import '../widgets/full_screen_toggle.dart';
import '../widgets/theme_mode_toggle.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OverviewViewModel()..load(),
      child: const _OverviewView(),
    );
  }
}

class _OverviewView extends StatelessWidget {
  const _OverviewView();

  static List<GfKpiCurrencyLine> _currencyLines(
    List<CurrencyMoneyTotal> items,
  ) {
    return [
      for (final t in items)
        GfKpiCurrencyLine(
          amount: t.amount,
          currencyCode: t.currencyCode,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OverviewViewModel>();
    final auth = context.watch<AuthProvider>();
    final s = vm.stats;
    final viewportH = MediaQuery.sizeOf(context).height;
    final panelHeight = GfPagination.overviewListPanelHeight(viewportH);
    final recentPanelHeight =
        (panelHeight * 1.18).clamp(panelHeight + 48.0, 520.0);
    final growth = vm.chartGrowthPercent;
    final chartSubtitle = growth == null
        ? 'chart.growthOnly'.tr()
        : 'chart.growthPercent'.tr(
            namedArgs: {'value': Formatters.percent(growth)},
          );

    final canSales = auth.hasPermission(AppPermissions.sales) ||
        auth.hasPermission(AppPermissions.orders);
    final canPurchases = auth.hasPermission(AppPermissions.purchases);
    final canExpenses = auth.hasPermission(AppPermissions.expenses);
    final canEmployees = auth.hasPermission(AppPermissions.employees);
    final canTrading =
        auth.hasPermission(AppPermissions.tradingCompanies);
    final canCustomers = auth.hasPermission(AppPermissions.customers);
    final canAlerts = auth.hasPermission(AppPermissions.alerts) ||
        auth.hasPermission(AppPermissions.products);
    final canProducts = auth.hasPermission(AppPermissions.products) ||
        auth.hasPermission(AppPermissions.sales);

    final kpiChildren = <Widget>[
      if (canSales)
        GfKpiCard(
          title: 'overview.periodSales'.tr(),
          currencies: _currencyLines(s.salesByCurrency),
          icon: AppAssets.sales,
        ),
      if (canPurchases)
        GfKpiCard(
          title: 'overview.periodPurchases'.tr(),
          currencies: _currencyLines(s.purchasesByCurrency),
          icon: AppAssets.inventory,
        ),
      if (canExpenses)
        GfKpiCard(
          title: 'overview.periodExpenses'.tr(),
          currencies: _currencyLines(s.expensesByCurrency),
          icon: AppAssets.expenses,
          tone: GfKpiTone.warning,
        ),
      if (canSales)
        GfKpiCard(
          title: 'overview.orderCount'.tr(),
          value: Formatters.number(s.orderCount),
          icon: AppAssets.order,
        ),
      if (canCustomers || canSales || canTrading)
        GfKpiCard(
          title: 'overview.customerLoans'.tr(),
          currencies: _currencyLines(s.receivableOutstanding),
          icon: AppAssets.customer,
          tone: GfKpiTone.warning,
        ),
      if (canCustomers || canSales)
        GfKpiCard(
          title: 'overview.customerCount'.tr(),
          value: Formatters.number(s.customerCount),
          icon: AppAssets.customerFilled,
        ),
      if (canTrading || canPurchases)
        GfKpiCard(
          title: 'overview.weOweThem'.tr(),
          currencies: _currencyLines(s.payableOutstanding),
          icon: AppAssets.suppliers,
          tone: GfKpiTone.error,
        ),
      if (canEmployees)
        GfKpiCard(
          title: 'overview.employeeWithdrawals'.tr(),
          currencies: _currencyLines(s.employeeWithdrawalsByCurrency),
          icon: AppAssets.expenses,
          tone: GfKpiTone.warning,
        ),
      if (canPurchases)
        GfKpiCard(
          title: 'overview.purchaseCount'.tr(),
          value: Formatters.number(s.purchaseCount),
          icon: AppAssets.invoice,
        ),
    ];

    return PageScaffold(
      title: 'overview.title'.tr(),
      subtitle: 'overview.subtitle'.tr(),
      padBody: false,
      actions: [
        const FullScreenToggle(),
        const ThemeModeToggle(),
        GfDateFilter(
          value: vm.dateFilter,
          onChanged: vm.setDateFilter,
        ),
      ],
      body: vm.loading
          ? const GfPageLoader()
          : vm.error != null
              ? GfEmptyState(
                  title: 'overview.loadFailed'.tr(),
                  subtitle: vm.error,
                  actionLabel: 'common.retry'.tr(),
                  onAction: vm.load,
                )
              : GfNoScrollbarGutter(
                  child: ListView(
                  padding: PageScaffold.pageBodyPadding(context),
                  children: [
                    if (kpiChildren.isNotEmpty) ...[
                      GfKpiGrid(children: kpiChildren),
                      SizedBox(height: gfSectionGap(context)),
                    ],
                    if (canSales || canProducts) ...[
                      _ChartTopSellersRow(
                        chartSubtitle: chartSubtitle,
                        chartPeriod: vm.chartPeriod,
                        chartLoading: vm.chartLoading,
                        onPeriodChanged: vm.setChartPeriod,
                        chartPoints: [
                          for (final p in vm.chartTrend)
                            (date: p.date, value: p.total),
                        ],
                        topProducts: canProducts ? s.topProducts : const [],
                        showChart: canSales,
                        showTopProducts: canProducts,
                      ),
                      SizedBox(height: gfSectionGap(context)),
                    ],
                    if (canSales || canPurchases) ...[
                      GfResponsiveSplit(
                        startFlex: 1,
                        endFlex: 1,
                        start: canSales
                            ? GfPaginatedListPanel(
                                height: recentPanelHeight,
                                title: 'overview.recentOrders'.tr(),
                                itemCount: s.recentOrders.length,
                                itemLabel: 'overview.invoiceItems'.tr(),
                                empty: GfEmptyState(
                                  title: 'overview.noOrders'.tr(),
                                  subtitle: 'overview.noOrdersHint'.tr(),
                                  compact: true,
                                ),
                                itemBuilder: (context, i) =>
                                    _InvoiceRow(item: s.recentOrders[i]),
                              )
                            : const SizedBox.shrink(),
                        end: canPurchases
                            ? GfPaginatedListPanel(
                                height: recentPanelHeight,
                                title: 'overview.recentPurchases'.tr(),
                                itemCount: s.recentPurchases.length,
                                itemLabel: 'overview.invoiceItems'.tr(),
                                empty: GfEmptyState(
                                  title: 'overview.noPurchases'.tr(),
                                  subtitle: 'overview.noPurchasesHint'.tr(),
                                  compact: true,
                                ),
                                itemBuilder: (context, i) =>
                                    _InvoiceRow(item: s.recentPurchases[i]),
                              )
                            : const SizedBox.shrink(),
                      ),
                      SizedBox(height: gfSectionGap(context)),
                    ],
                    if (canCustomers || canSales) ...[
                      GfPaginatedListPanel(
                        height: panelHeight,
                        title: 'overview.customerLoansList'.tr(),
                        itemCount: s.customerLoans.length,
                        itemLabel: 'overview.customerLoanItems'.tr(),
                        empty: GfEmptyState(
                          title: 'overview.noCustomerLoans'.tr(),
                          subtitle: 'overview.noCustomerLoansHint'.tr(),
                          compact: true,
                        ),
                        itemBuilder: (context, i) =>
                            _CustomerLoanRow(item: s.customerLoans[i]),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () => context.go(AppRoutes.customers),
                          child: Text('overview.viewAllCustomers'.tr()),
                        ),
                      ),
                      SizedBox(height: gfSectionGap(context)),
                    ],
                    if (canAlerts) ...[
                      GfPaginatedListPanel(
                        height: panelHeight,
                        title: 'overview.inventoryAlerts'.tr(),
                        itemCount: s.alerts.length,
                        itemHeight: 72,
                        itemLabel: 'overview.alertItems'.tr(),
                        empty: GfEmptyState(
                          title: 'overview.noAlerts'.tr(),
                          subtitle: 'overview.noAlertsHint'.tr(),
                          compact: true,
                        ),
                        itemBuilder: (context, i) {
                          final a = s.alerts[i];
                          final statusLabel = switch (a.status) {
                            'expired' => 'alerts.status.expired'.tr(),
                            'expiringSoon' =>
                              'alerts.status.expiringSoon'.tr(),
                            'outOfStock' || 'Out of Stock' =>
                              'overview.outOfStock'.tr(),
                            _ => 'overview.lowStock'.tr(),
                          };
                          final isCritical = a.status == 'expired' ||
                              a.status == 'outOfStock' ||
                              a.status == 'Out of Stock';
                          return InkWell(
                            onTap: () => context.go(AppRoutes.alerts),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    isCritical
                                        ? Icons.cancel_outlined
                                        : Icons.warning_amber_rounded,
                                    color: isCritical
                                        ? AppColors.error
                                        : AppColors.warning,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        a.name,
                                        style: AppTypography.bodyMedium,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        a.isExpiryAlert
                                            ? statusLabel
                                            : 'overview.leftStatus'.tr(
                                                namedArgs: {
                                                  'stock': Formatters.number(
                                                    a.currentStock,
                                                  ),
                                                  'status': statusLabel,
                                                },
                                              ),
                                        style: AppTypography.caption,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () => context.go(AppRoutes.alerts),
                          child: Text('overview.viewAllAlerts'.tr()),
                        ),
                      ),
                    ],
                  ],
                  ),
                ),
    );
  }
}

/// Measures the chart card and locks the top-sellers panel to the same height.
class _ChartTopSellersRow extends StatefulWidget {
  const _ChartTopSellersRow({
    required this.chartSubtitle,
    required this.chartPeriod,
    required this.chartLoading,
    required this.onPeriodChanged,
    required this.chartPoints,
    required this.topProducts,
    this.showChart = true,
    this.showTopProducts = true,
  });

  final String chartSubtitle;
  final GfLineChartPeriod chartPeriod;
  final bool chartLoading;
  final ValueChanged<GfLineChartPeriod> onPeriodChanged;
  final List<GfLineChartPoint> chartPoints;
  final List<TopProductStat> topProducts;
  final bool showChart;
  final bool showTopProducts;

  @override
  State<_ChartTopSellersRow> createState() => _ChartTopSellersRowState();
}

class _ChartTopSellersRowState extends State<_ChartTopSellersRow> {
  final GlobalKey _chartKey = GlobalKey();
  double? _matchedHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureChart());
  }

  @override
  void didUpdateWidget(covariant _ChartTopSellersRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureChart());
  }

  void _measureChart() {
    if (!mounted) return;
    final box = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height;
    if (_matchedHeight == null || (h - _matchedHeight!).abs() > 0.5) {
      setState(() => _matchedHeight = h);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chartPlotH = GfLineChart.responsiveHeight(context);
    // Fallback until first layout pass measures the real chart card.
    final sideHeight = _matchedHeight ?? (48 + 72 + 20 + chartPlotH);

    if (!widget.showChart && !widget.showTopProducts) {
      return const SizedBox.shrink();
    }
    if (!widget.showChart) {
      return SizedBox(
        height: sideHeight,
        child: _topProductsCard(),
      );
    }
    if (!widget.showTopProducts) {
      return KeyedSubtree(
        key: _chartKey,
        child: GfLineChart(
          title: 'chart.salesOverview'.tr(),
          subtitle: widget.chartSubtitle,
          tooltipMetricLabel: 'chart.salesMetric'.tr(),
          height: chartPlotH,
          period: widget.chartPeriod,
          loading: widget.chartLoading,
          onPeriodChanged: widget.onPeriodChanged,
          hideYAxisLabels: true,
          points: widget.chartPoints,
        ),
      );
    }

    return GfResponsiveSplit(
      startFlex: 3,
      endFlex: 2,
      start: KeyedSubtree(
        key: _chartKey,
        child: GfLineChart(
          title: 'chart.salesOverview'.tr(),
          subtitle: widget.chartSubtitle,
          tooltipMetricLabel: 'chart.salesMetric'.tr(),
          height: chartPlotH,
          period: widget.chartPeriod,
          loading: widget.chartLoading,
          onPeriodChanged: widget.onPeriodChanged,
          hideYAxisLabels: true,
          points: widget.chartPoints,
        ),
      ),
      end: SizedBox(
        height: sideHeight,
        child: _topProductsCard(),
      ),
    );
  }

  Widget _topProductsCard() {
    return GfCard(
      title: 'overview.topSelling'.tr(),
      child: widget.topProducts.isEmpty
          ? GfEmptyState(
              title: 'overview.noTopProducts'.tr(),
              subtitle: 'overview.topMovingHint'.tr(),
              compact: true,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.topProducts.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.tableHeader,
                          child: Text(
                            '${i + 1}',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.topProducts[i].name,
                                style: AppTypography.bodyMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'overview.soldCount'.tr(
                                  namedArgs: {
                                    'count': Formatters.number(
                                      widget.topProducts[i].unitsSold,
                                    ),
                                  },
                                ),
                                style: AppTypography.caption,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          Formatters.money(widget.topProducts[i].revenue),
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.item});

  final OverviewInvoiceStub item;

  @override
  Widget build(BuildContext context) {
    final currency = item.currencyCode ?? 'AFN';
    return Row(
      children: [
        Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.invoiceNumber,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                item.partnerName?.trim().isNotEmpty == true
                    ? item.partnerName!
                    : '—',
                style: AppTypography.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              Formatters.money(item.total, currency: currency),
              style: AppTypography.bodyMedium,
            ),
            Text(
              Formatters.relative(item.createdAt),
              style: AppTypography.caption,
            ),
          ],
        ),
      ],
    );
  }
}

class _CustomerLoanRow extends StatelessWidget {
  const _CustomerLoanRow({required this.item});

  final OverviewCustomerLoan item;

  @override
  Widget build(BuildContext context) {
    final amountLabel = item.outstanding.isEmpty
        ? Formatters.money(0)
        : item.outstanding
            .map((t) => Formatters.money(t.amount, currency: t.currencyCode))
            .join(' · ');
    return InkWell(
      onTap: () => context.go(AppRoutes.customers),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.name,
                  style: AppTypography.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  (item.phone ?? '').trim().isEmpty
                      ? 'overview.customerLoanHint'.tr()
                      : item.phone!,
                  style: AppTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amountLabel,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}
