import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/di/service_locator.dart';
import '../../data/models/report_models.dart';

/// Live count of inventory alerts for the sidebar badge.
class AlertsCountProvider extends ChangeNotifier {
  AlertsCountProvider() {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => refresh());
  }

  Timer? _timer;
  int _count = 0;
  bool _busy = false;

  int get count => _count;

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final result =
          await ServiceLocator.instance.products.getAlerts(limit: 200);
      result.when(
        success: (List<InventoryAlert> list) {
          if (list.length != _count) {
            _count = list.length;
            notifyListeners();
          }
        },
        failure: (_) {},
      );
    } finally {
      _busy = false;
    }
  }

  void setCount(int value) {
    if (value == _count) return;
    _count = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
