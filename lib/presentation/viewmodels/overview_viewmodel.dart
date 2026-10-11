import 'package:flutter/foundation.dart';

import '../../core/di/service_locator.dart';
import '../../core/utils/overview_chart_period.dart';
import '../../core/widgets/gf_date_filter.dart';
import '../../data/models/report_models.dart';
import '../../domain/repositories/inventory_repository.dart';

class OverviewViewModel extends ChangeNotifier {
  OverviewViewModel({InventoryRepository? repository})
      : _repo = repository ?? ServiceLocator.instance.inventory;

  final InventoryRepository _repo;

  bool loading = true;
  bool chartLoading = false;
  String? error;
  OverviewStats stats = const OverviewStats();
  OverviewChartPeriod chartPeriod = OverviewChartPeriod.weekly;
  List<SalesTrendPoint> chartTrend = const [];
  DateFilterValue dateFilter = DateFilterValue.thisMonth();

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    final result = await _repo.getOverviewStats(
      from: dateFilter.from,
      to: dateFilter.to,
    );
    result.when(
      success: (s) {
        stats = s;
        // Seed weekly series from overview stats while chart fetch runs.
        if (chartPeriod == OverviewChartPeriod.weekly &&
            (s.movementTrend.isNotEmpty || s.salesTrend.isNotEmpty)) {
          chartTrend =
              s.movementTrend.isNotEmpty ? s.movementTrend : s.salesTrend;
        }
      },
      failure: (f) => error = f.message,
    );
    loading = false;
    notifyListeners();
    if (error == null) {
      await loadChart(chartPeriod);
    }
  }

  Future<void> setDateFilter(DateFilterValue value) async {
    dateFilter = value;
    await load();
  }

  Future<void> setChartPeriod(OverviewChartPeriod period) async {
    if (chartPeriod == period && chartTrend.isNotEmpty) return;
    chartPeriod = period;
    notifyListeners();
    await loadChart(period);
  }

  Future<void> loadChart(OverviewChartPeriod period) async {
    chartLoading = true;
    notifyListeners();
    final result = await _repo.getMovementChartTrend(period);
    result.when(
      success: (points) {
        chartPeriod = period;
        chartTrend = points;
      },
      failure: (_) {
        // Keep previous series; chart widget can show empty if none.
      },
    );
    chartLoading = false;
    notifyListeners();
  }

  /// Percent change from first to last chart point (growth of the series).
  double? get chartGrowthPercent {
    if (chartTrend.length < 2) return null;
    final first = chartTrend.first.total;
    final last = chartTrend.last.total;
    if (first == 0) {
      if (last == 0) return 0;
      return null;
    }
    return ((last - first) / first.abs()) * 100;
  }
}
