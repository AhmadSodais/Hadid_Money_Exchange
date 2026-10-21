import 'dart:async';

import 'package:flutter/foundation.dart';

import 'snackbar_model.dart';

/// Holds the active snackbar stack (max 3) for the glass overlay host.
class SnackbarViewModel extends ChangeNotifier {
  static const int maxVisible = 3;

  final List<SnackbarModel> _items = [];
  final Map<String, Timer> _timers = {};
  int _seq = 0;

  List<SnackbarModel> get items => List.unmodifiable(_items);

  String show({
    required String title,
    String? message,
    SnackbarType type = SnackbarType.info,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
    double? progress,
  }) {
    final id = 'sb-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
    final resolvedDuration = duration ??
        (type == SnackbarType.loading
            ? Duration.zero
            : type == SnackbarType.action
                ? const Duration(seconds: 6)
                : const Duration(seconds: 4));

    final model = SnackbarModel(
      id: id,
      title: title,
      message: message,
      type: type,
      duration: resolvedDuration,
      actionLabel: actionLabel,
      onAction: onAction,
      progress: progress,
      createdAt: DateTime.now(),
    );

    _items.insert(0, model);
    while (_items.length > maxVisible) {
      final removed = _items.removeLast();
      _cancelTimer(removed.id);
    }
    _scheduleDismiss(model);
    notifyListeners();
    return id;
  }

  void update(
    String id, {
    String? title,
    String? message,
    double? progress,
    bool clearProgress = false,
    SnackbarType? type,
  }) {
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(
      title: title,
      message: message,
      progress: progress,
      clearProgress: clearProgress,
      type: type,
    );
    notifyListeners();
  }

  /// Pauses the auto-dismiss timer (e.g. while the user has expanded a
  /// long message with "more" and is still reading it).
  void pauseDismiss(String id) => _cancelTimer(id);

  /// Resumes auto-dismiss for a previously paused snackbar.
  void resumeDismiss(String id, {Duration duration = const Duration(seconds: 4)}) {
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _cancelTimer(id);
    if (duration <= Duration.zero) return;
    _timers[id] = Timer(duration, () => dismiss(id));
  }

  void dismiss(String id) {
    final before = _items.length;
    _items.removeWhere((e) => e.id == id);
    _cancelTimer(id);
    if (_items.length != before) notifyListeners();
  }

  void dismissAll() {
    for (final id in _timers.keys.toList()) {
      _cancelTimer(id);
    }
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  void _scheduleDismiss(SnackbarModel model) {
    if (model.duration <= Duration.zero) return;
    _cancelTimer(model.id);
    _timers[model.id] = Timer(model.duration, () => dismiss(model.id));
  }

  void _cancelTimer(String id) {
    _timers.remove(id)?.cancel();
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}
