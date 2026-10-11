import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/sync/connectivity_service.dart';
import '../../core/sync/firebase_sync_service.dart';
import '../../core/sync/sync_backfill.dart';
import '../../core/sync/sync_error_messages.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_outbox.dart';
import '../../core/sync/sync_queue_repository.dart';

/// MVVM ViewModel for Sync Center + background sync orchestration.
///
/// Event-driven only — there is no polling timer. Uploading starts:
/// a few seconds after a change is saved (rapid edits go together), when the
/// internet comes back or online sync is switched back on (failed jobs get
/// another chance then), when the app opens with changes still waiting, and
/// when the user presses Sync / Retry. With nothing waiting, or with no
/// network, nothing touches the network.
/// While the network is up but the server can't be reached, retries wait
/// 5s, 10s, 20s … up to 2 min.
class SyncViewModel extends ChangeNotifier {
  SyncViewModel({
    SharedPreferences? prefs,
    ConnectivityService? connectivity,
    FirebaseSyncService? syncService,
  })  : _prefs = prefs,
        _connectivity = connectivity ?? ConnectivityService(),
        _sync = syncService ?? FirebaseSyncService() {
    _lastOnlineEnabled = isOnlineSyncEnabled;
    _wasConnected = _connectivity.isOnline;
    _connectivity.addListener(_onConnectivity);
    SyncOutbox.revision.addListener(_onOutboxChanged);
    Future<void>.delayed(const Duration(milliseconds: 800), _startup);
  }

  SharedPreferences? _prefs;
  final ConnectivityService _connectivity;
  final FirebaseSyncService _sync;
  Timer? _debounceTimer;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _disposed = false;
  late bool _lastOnlineEnabled;
  late bool _wasConnected;

  /// Number of open Sync Center views; full lists load only while > 0.
  int _viewers = 0;

  static const _retryBase = Duration(seconds: 5);
  static const _retryMax = Duration(minutes: 2);

  /// When false (Settings → Disable online), nothing is sent; jobs keep
  /// collecting locally.
  bool get isOnlineSyncEnabled =>
      _prefs?.getBool(AppConstants.prefOnlineEnabled) ?? true;

  /// Call after SharedPreferences become available (e.g. from main).
  void attachPrefs(SharedPreferences prefs) {
    _prefs = prefs;
    _lastOnlineEnabled = isOnlineSyncEnabled;
    notifyListeners();
  }

  /// Call after Settings toggles online sync on/off.
  void refreshOnlineFlag() {
    final enabled = isOnlineSyncEnabled;
    final switchedOn = enabled && !_lastOnlineEnabled;
    _lastOnlineEnabled = enabled;
    if (!enabled) {
      _cancelRetry();
      _debounceTimer?.cancel();
    }
    notifyListeners();
    if (switchedOn) unawaited(_resumeAfterOutage());
  }

  int _busyCount = 0;
  String? _message;
  String? _lastError;
  DateTime? _lastSyncAt;
  Map<String, int> _counts = {
    for (final s in SyncItemStatus.values)
      if (s != SyncItemStatus.superseded) s.dbValue: 0,
  };
  Map<String, int> _pendingByType = {};
  List<SyncQueueItem> _history = const [];
  List<SyncQueueItem> _failed = const [];
  List<SyncQueueItem> _conflicts = const [];

  ConnectivityService get connectivity => _connectivity;
  bool get isOnline => _connectivity.isOnline;
  bool get isBusy => _busyCount > 0;
  String? get message => _message;
  String? get lastError => _lastError;
  DateTime? get lastSyncAt => _lastSyncAt;
  Map<String, int> get counts => _counts;
  Map<String, int> get pendingByType => _pendingByType;
  List<SyncQueueItem> get history => _history;
  List<SyncQueueItem> get failed => _failed;
  List<SyncQueueItem> get conflicts => _conflicts;

  int get pendingCount => _counts[SyncItemStatus.pending.dbValue] ?? 0;
  int get syncedCount => _counts[SyncItemStatus.synced.dbValue] ?? 0;
  int get failedCount => _counts[SyncItemStatus.failed.dbValue] ?? 0;
  int get conflictCount => _counts[SyncItemStatus.conflict.dbValue] ?? 0;

  SyncQueueRepository get queue => _sync.queue;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _startup() async {
    if (_disposed) return;
    try {
      final removed = await _sync.queue.prune();
      if (removed > 0) debugPrint('[SyncVM] pruned $removed old queue rows');
    } catch (e) {
      debugPrint('[SyncVM] prune failed: $e');
    }
    await SyncBackfill.runIfNeeded();
    await refresh();
    if (pendingCount > 0) await syncNow(quiet: true);
  }

  /// Sync Center opened: load the full lists and keep them current.
  void attachView() {
    _viewers++;
    unawaited(refresh());
  }

  /// Sync Center closed: go back to counters only.
  void detachView() {
    if (_viewers > 0) _viewers--;
    if (_viewers == 0) {
      _history = const [];
      _failed = const [];
      _conflicts = const [];
      _pendingByType = {};
    }
  }

  void _onConnectivity() {
    final connected = _connectivity.isOnline;
    final cameBack = connected && !_wasConnected;
    _wasConnected = connected;
    if (!connected) _cancelRetry();
    _notify();
    if (cameBack && isOnlineSyncEnabled) unawaited(_resumeAfterOutage());
  }

  /// Internet back / online switched on: failed jobs get another automatic
  /// chance (within the retry limit), then everything pending is sent.
  Future<void> _resumeAfterOutage() async {
    try {
      final requeued = await _sync.queue.requeueFailedForAutoRetry();
      if (requeued > 0) debugPrint('[SyncVM] re-queued $requeued failed jobs');
    } catch (e) {
      debugPrint('[SyncVM] auto-retry failed: $e');
    }
    _retryAttempt = 0;
    await syncNow(quiet: true);
  }

  /// A change was saved: update the counters now, upload after a short
  /// quiet period so a burst of edits goes up together.
  void _onOutboxChanged() {
    unawaited(refresh());
    if (!isOnlineSyncEnabled || _disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      AppConstants.syncDebounce,
      () => unawaited(syncNow(quiet: true)),
    );
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _scheduleRetry() {
    if (_disposed || !isOnlineSyncEnabled) return;
    // No network at all: the "connection restored" event restarts sending.
    if (!_connectivity.isOnline) return;
    _cancelRetry();
    final factor = math.pow(2, _retryAttempt).toInt();
    final wait = _retryBase * factor;
    final delay = wait > _retryMax ? _retryMax : wait;
    if (wait < _retryMax) _retryAttempt++;
    debugPrint('[SyncVM] retrying in ${delay.inSeconds}s');
    _retryTimer = Timer(delay, () => unawaited(syncNow(quiet: true)));
  }

  /// Counters always; history / failed / conflict lists only while the
  /// Sync Center is open.
  Future<void> refresh() async {
    try {
      _counts = await _sync.queue.countsByStatus();
      _lastSyncAt = await _sync.queue.lastSyncAt();
      if (_viewers > 0) {
        _pendingByType = await _sync.queue.pendingByEntityType();
        _history = await _sync.queue.list(limit: 80);
        _failed =
            await _sync.queue.list(status: SyncItemStatus.failed, limit: 50);
        _conflicts =
            await _sync.queue.list(status: SyncItemStatus.conflict, limit: 50);
      }
      if (SyncOutbox.lastError != null) {
        _lastError = SyncErrorMessages.codeFor(SyncOutbox.lastError);
      }
    } catch (e) {
      debugPrint('[SyncVM] refresh failed: ${SyncErrorMessages.redact('$e')}');
      _lastError = SyncErrorMessages.codeFor(e.toString());
    }
    _notify();
  }

  /// [quiet] runs are automatic: they skip silently when there is no
  /// network. A manual run (Sync button) always tries and reports back.
  Future<SyncRunResult?> syncNow({bool quiet = false}) async {
    if (_disposed) return null;
    _debounceTimer?.cancel();
    if (!isOnlineSyncEnabled) {
      if (!quiet) {
        _message = 'sync.disabledHint';
        _notify();
      }
      return null;
    }
    if (quiet && !await _connectivity.refresh()) return null;

    _cancelRetry();
    _busyCount++;
    if (!quiet) _message = null;
    _notify();

    try {
      if (!quiet) await _connectivity.refresh();
      final result = await _sync.syncPending();
      await refresh();

      if (result.stoppedTemporarily) {
        _scheduleRetry();
      } else {
        _retryAttempt = 0;
      }

      if (result.error != null && result.error != 'busy') {
        _lastError = SyncErrorMessages.codeFor(result.error);
      } else if (result.failed == 0 && !result.stoppedTemporarily) {
        _lastError = null;
      }
      if (!quiet) {
        if (result.stoppedTemporarily) {
          _message = result.offline &&
                  SyncErrorMessages.codeFor(result.error) == 'unreachable'
              ? 'sync.offlineHint'
              : SyncErrorMessages.messageKey(result.error);
        } else if (result.failed > 0) {
          _message = 'sync.completedWithErrors';
        } else if (result.processed == 0) {
          _message = 'sync.nothingPending';
        } else {
          _message = 'sync.completed';
        }
      }
      return result;
    } catch (e, st) {
      debugPrint(
        '[SyncVM] syncNow error: ${SyncErrorMessages.redact('$e')}\n$st',
      );
      _lastError = SyncErrorMessages.codeFor(e.toString());
      if (!quiet) _message = SyncErrorMessages.messageKey(e.toString());
      _scheduleRetry();
      return null;
    } finally {
      _busyCount--;
      _notify();
    }
  }

  Future<void> retryItem(int id) async {
    await _sync.queue.resetToPending(id);
    await refresh();
    await syncNow();
  }

  Future<void> retryAllFailed() async {
    for (final item in _failed) {
      await _sync.queue.resetToPending(item.id);
    }
    await refresh();
    await syncNow();
  }

  /// Conflict → keep the local version and override the server copy.
  Future<void> resolveKeepLocal(SyncQueueItem item) async {
    await _sync.queue.resolveKeepLocal(item.id);
    await refresh();
    await syncNow();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _cancelRetry();
    _connectivity.removeListener(_onConnectivity);
    SyncOutbox.revision.removeListener(_onOutboxChanged);
    _connectivity.dispose();
    super.dispose();
  }
}
