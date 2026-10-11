import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Watches device connectivity for offline-first sync triggers.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _online = false;
  bool _ready = false;

  bool get isOnline => _online;
  bool get isReady => _ready;

  Future<void> _init() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _online = _hasLink(results);
    } catch (_) {
      _online = false;
    }
    _ready = true;
    notifyListeners();

    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final next = _hasLink(results);
      if (next == _online) return;
      _online = next;
      notifyListeners();
    });
  }

  bool _hasLink(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.vpn ||
          r == ConnectivityResult.other,
    );
  }

  Future<bool> refresh() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _online = _hasLink(results);
    } catch (_) {
      _online = false;
    }
    notifyListeners();
    return _online;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
