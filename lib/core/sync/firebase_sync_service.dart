import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'firebase_exceptions.dart';
import 'firebase_rtdb_client.dart';
import 'sync_error_messages.dart';
import 'sync_models.dart';
import 'sync_queue_repository.dart';

/// Sends the local outbox to the server.
///
/// - Does nothing (no network at all) when nothing is waiting.
/// - Only one run at a time (app-wide). A request made during a run starts
///   another run right after the current one finishes.
/// - Jobs go strictly first-in, first-out. Each batch of waiting jobs is
///   written in ONE all-or-nothing request, and a business action (group) is
///   never split across batches, so the server never holds half an action.
/// - Each record carries a version number. Records whose server version is
///   known are written without reading them first; the server copy is read
///   only when the version is unknown, or when the batch was rejected.
/// - Temporary problems keep the jobs PENDING and stop the whole run, so the
///   order is never broken. Permanent rejections mark only the offending job
///   FAILED and the run continues.
class FirebaseSyncService {
  FirebaseSyncService({
    SyncQueueRepository? queue,
    FirebaseRtdbClient? client,
  })  : _queue = queue ?? SyncQueueRepository(),
        _client = client ?? FirebaseRtdbClient();

  final SyncQueueRepository _queue;
  final FirebaseRtdbClient _client;

  static Future<SyncRunResult>? _active;
  static bool _runAgain = false;
  static int _pauseDepth = 0;

  static const _deviceNode = 'sync_device';
  static const _auditNode = 'sync_logs';

  /// Installation that last wrote the record (tells our own earlier write,
  /// e.g. one whose reply was lost, apart from someone else's change).
  static const _writerKey = 'writerDevice';

  /// Jobs per upload. Shrinks after a timeout (slow connection) and grows
  /// back after each successful batch.
  static const _maxBatch = 200;
  static const _minBatch = 10;
  static int _batchLimit = _maxBatch;

  /// True while a sync run is in progress.
  static bool get isRunning => _active != null;

  String? lastRunError;

  SyncQueueRepository get queue => _queue;

  /// Sends every pending job. If a run is already active, a follow-up run
  /// is scheduled and the returned future completes when that one is done.
  Future<SyncRunResult> syncPending() {
    final active = _active;
    if (active != null) {
      _runAgain = true;
      return active;
    }
    final run = _loop().whenComplete(() => _active = null);
    _active = run;
    return run;
  }

  /// Kept for callers that push everything; every run drains the queue.
  Future<SyncRunResult> syncAllPending() => syncPending();

  /// Runs [body] with background sending paused (waits for an active run to
  /// finish first). Used by fetch-from-server and clear operations.
  static Future<T> runExclusive<T>(Future<T> Function() body) async {
    _pauseDepth++;
    try {
      final active = _active;
      if (active != null) await active;
      return await body();
    } finally {
      _pauseDepth--;
    }
  }

  Future<SyncRunResult> _loop() async {
    var total = const SyncRunResult.empty();
    do {
      _runAgain = false;
      final result = await _runOnce();
      total = total.followedBy(result);
      if (result.stoppedTemporarily || result.disabled) break;
    } while (_runAgain);
    return total;
  }

  /// Settings → online sync switch (default on).
  static Future<bool> onlineEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(AppConstants.prefOnlineEnabled) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<SyncRunResult> _runOnce() async {
    lastRunError = null;
    if (_pauseDepth > 0) {
      return const SyncRunResult.stopped('busy');
    }
    if (!await onlineEnabled()) {
      debugPrint('[Sync] online sync disabled — jobs stay queued');
      return const SyncRunResult(disabled: true, error: 'disabled');
    }
    if (await _queue.pendingCount() == 0) {
      return const SyncRunResult.empty();
    }

    // The ownership check is also the reachability / sign-in check.
    final String me;
    try {
      me = await _queue.deviceId();
      final deviceErr = await _checkDevice(me);
      if (deviceErr != null) {
        lastRunError = deviceErr;
        return SyncRunResult.stopped(deviceErr);
      }
    } catch (e) {
      final code = _codeOf(e);
      lastRunError = code;
      debugPrint('[Sync] not signed in / unreachable: $code');
      return SyncRunResult.stopped(code, offline: true);
    }

    final tally = _Tally();
    while (true) {
      if (_pauseDepth > 0) return tally.result(stoppedOn: 'busy');

      final batch = await _queue.nextBatch(maxJobs: _batchLimit);
      if (batch.isEmpty) break;
      debugPrint('[Sync] uploading ${batch.length} job(s)');

      try {
        await _sendBatch(batch, me, tally);
        _batchLimit = math.min(_maxBatch, _batchLimit * 2);
      } catch (e, st) {
        final code = _codeOf(e);
        lastRunError = code;
        if (code == 'timeout') {
          _batchLimit = math.max(_minBatch, _batchLimit ~/ 4);
        }
        if (FirebaseSyncException.isTemporary(e)) {
          debugPrint('[Sync] temporary problem ($code) — stopping run');
        } else {
          debugPrint(
            '[Sync] unexpected error: ${SyncErrorMessages.redact('$e')}\n$st',
          );
        }
        return tally.result(
          stoppedOn: code,
          offline: code == 'unreachable' || code == 'timeout',
        );
      }
    }

    await _queue.setLastSyncAt(DateTime.now());
    debugPrint(
      '[Sync] done processed=${tally.processed} synced=${tally.synced} '
      'failed=${tally.failed} conflicts=${tally.conflicts}',
    );
    return tally.result(error: tally.failed > 0 ? lastRunError : null);
  }

  static String _codeOf(Object e) => e is FirebaseSyncException
      ? e.message
      : SyncErrorMessages.codeFor(SyncErrorMessages.redact('$e'));

  static String _pathOf(SyncQueueItem item) =>
      '${item.entityType}/${item.entityId}';

  static String _keyOf(SyncQueueItem item) =>
      '${item.entityType}/${item.entityId}';

  static int _versionOf(Map<String, dynamic>? remote) =>
      (remote?['version'] as num?)?.toInt() ?? 0;

  /// Uploads [batch] in one write. Throws only on temporary problems.
  Future<void> _sendBatch(
    List<SyncQueueItem> batch,
    String me,
    _Tally tally,
  ) async {
    final states = await _queue.recordStates(batch);

    // Server version each record is written on top of (null = delete).
    final writes = <(SyncQueueItem, int?)>[];
    for (final item in batch) {
      if (item.operation == SyncOperation.delete) {
        writes.add((item, null));
        continue;
      }
      final state = states[_keyOf(item)];
      final known = state?.version;
      if (known != null) {
        writes.add((item, known));
        continue;
      }
      if (state == null &&
          item.operation == SyncOperation.create &&
          !item.forceLocal) {
        writes.add((item, 0));
        continue;
      }
      // Version unknown (uploaded by an older app version, or forced
      // without a known version): read the server copy once.
      try {
        final remote = await _client.get(_pathOf(item));
        if (!item.forceLocal && _isConflict(item, remote, state, me)) {
          await _markConflict(item, tally);
          continue;
        }
        writes.add((item, _versionOf(remote)));
      } catch (e, st) {
        if (FirebaseSyncException.isTemporary(e)) rethrow;
        await _markFailed(item, e, st, tally);
      }
    }
    if (writes.isEmpty) return;

    final Map<String, Object?> updates = {};
    for (final (item, base) in writes) {
      final path = _pathOf(item);
      if (base == null) {
        updates[path] = null;
      } else {
        // Field-level paths merge into the record, like a PATCH would.
        _body(item, base, me).forEach((k, v) => updates['$path/$k'] = v);
      }
      updates['$_auditNode/${item.syncId}'] = _auditEntry(item);
    }

    try {
      await _client.updateMany(updates);
    } catch (e) {
      if (FirebaseSyncException.isTemporary(e)) rethrow;
      // Rejected as a whole (a record changed on the server, or one record
      // the server refuses): send one by one to find out which.
      debugPrint(
        '[Sync] batch rejected (${_codeOf(e)}) — sending jobs one by one',
      );
      for (final (item, _) in writes) {
        await _sendSingle(item, me, tally);
      }
      return;
    }

    await _queue.markSyncedBatch([
      for (final (item, base) in writes) (item, base == null ? null : base + 1),
    ]);
    tally.synced += writes.length;
    tally.processed += writes.length;
  }

  /// Fallback for one job: read the server copy, check for a conflict, then
  /// write. Throws only on temporary problems.
  Future<void> _sendSingle(
    SyncQueueItem item,
    String me,
    _Tally tally,
  ) async {
    final path = _pathOf(item);
    try {
      if (item.operation == SyncOperation.delete) {
        await _client.delete(path);
        await _queue.markSynced(item);
      } else {
        final remote = await _client.get(path);
        final state = (await _queue.recordStates([item]))[_keyOf(item)];
        if (!item.forceLocal && _isConflict(item, remote, state, me)) {
          await _markConflict(item, tally);
          return;
        }
        final base = _versionOf(remote);
        final body = _body(item, base, me);
        // New record: written whole. Existing record: merged, so fields this
        // snapshot doesn't mention are left untouched.
        if (remote == null) {
          await _client.put(path, body);
        } else {
          await _client.patch(path, body);
        }
        await _queue.markSynced(item, version: base + 1);
      }
      tally.synced++;
      tally.processed++;
      await _writeAudit(item);
    } catch (e, st) {
      if (FirebaseSyncException.isTemporary(e)) rethrow;
      await _markFailed(item, e, st, tally);
    }
  }

  /// The server copy was changed by someone else after this computer last
  /// wrote it: never overwrite it silently.
  bool _isConflict(
    SyncQueueItem item,
    Map<String, dynamic>? remote,
    SyncRecordState? state,
    String me,
  ) {
    if (remote == null) return false;
    if (remote[_writerKey] == me) return false;
    final known = state?.version;
    if (known != null) return _versionOf(remote) != known;
    // No version history for this record: fall back to change times.
    final remoteUpdated = _parseTime(
      remote['updatedAt'] ?? remote['updated_at'] ?? remote['lastModified'],
    );
    return remoteUpdated != null &&
        remoteUpdated.isAfter(item.changedAt.add(const Duration(seconds: 1)));
  }

  Map<String, dynamic> _body(SyncQueueItem item, int base, String me) {
    final body = <String, dynamic>{
      ...item.payload,
      'id': item.entityId,
      'updatedAt': item.changedAt.toIso8601String(),
      'updatedBy': 'windows_app',
      _writerKey: me,
      'version': base + 1,
    }..remove('forceLocal');
    if (base == 0 && body['createdAt'] == null) {
      body['createdAt'] =
          item.payload['created_at'] ?? item.changedAt.toIso8601String();
    }
    return body;
  }

  Map<String, dynamic> _auditEntry(SyncQueueItem item) => {
        'entityType': item.entityType,
        'entityId': item.entityId,
        'operation': item.operation.dbValue,
        'at': DateTime.now().toIso8601String(),
        'status': 'synced',
      };

  Future<void> _writeAudit(SyncQueueItem item) async {
    try {
      await _client.put('$_auditNode/${item.syncId}', _auditEntry(item));
    } catch (e) {
      debugPrint(
        '[Sync] audit entry skipped for #${item.id}: '
        '${SyncErrorMessages.redact('$e')}',
      );
    }
  }

  Future<void> _markConflict(SyncQueueItem item, _Tally tally) async {
    await _queue.markStatus(
      item.id,
      status: SyncItemStatus.conflict,
      error: 'conflict',
    );
    tally.conflicts++;
    tally.processed++;
  }

  Future<void> _markFailed(
    SyncQueueItem item,
    Object e,
    StackTrace st,
    _Tally tally,
  ) async {
    final code = _codeOf(e);
    lastRunError = code;
    debugPrint(
      '[Sync] job #${item.id} ${item.entityType}/${item.entityId} '
      'rejected ($code): ${SyncErrorMessages.redact('$e')}\n$st',
    );
    await _queue.markStatus(
      item.id,
      status: SyncItemStatus.failed,
      error: code,
      bumpRetry: true,
    );
    tally.failed++;
    tally.processed++;
  }

  /// One computer writes per cloud account. Returns `other_device` when the
  /// account is owned by another installation; claims it when unowned.
  Future<String?> _checkDevice(String me) async {
    final remote = await _client.get(_deviceNode);
    final owner = remote?['deviceId'];
    if (owner == null || '$owner'.isEmpty) {
      await claimDevice();
      return null;
    }
    return owner == me ? null : 'other_device';
  }

  /// Makes this installation the account's writer (fetch / push everything).
  Future<void> claimDevice() async {
    await _client.put(_deviceNode, {
      'deviceId': await _queue.deviceId(),
      'claimedAt': DateTime.now().toIso8601String(),
    });
  }

  DateTime? _parseTime(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse('$raw');
  }
}

class _Tally {
  int processed = 0;
  int synced = 0;
  int failed = 0;
  int conflicts = 0;

  SyncRunResult result({
    String? stoppedOn,
    bool offline = false,
    String? error,
  }) =>
      SyncRunResult(
        processed: processed,
        synced: synced,
        failed: failed,
        conflicts: conflicts,
        offline: offline,
        stoppedTemporarily: stoppedOn != null,
        error: stoppedOn ?? error,
      );
}

class SyncRunResult {
  const SyncRunResult({
    this.processed = 0,
    this.synced = 0,
    this.failed = 0,
    this.conflicts = 0,
    this.offline = false,
    this.stoppedTemporarily = false,
    this.disabled = false,
    this.error,
  });

  const SyncRunResult.empty() : this();

  /// Run could not start or had to stop; everything stays pending.
  const SyncRunResult.stopped(String code, {bool offline = false})
      : this(stoppedTemporarily: true, offline: offline, error: code);

  final int processed;
  final int synced;
  final int failed;
  final int conflicts;

  /// Server could not be reached (or not signed in).
  final bool offline;

  /// Stopped on a temporary problem; retry later with backoff.
  final bool stoppedTemporarily;

  /// Online sync is switched off in Settings.
  final bool disabled;
  final String? error;

  SyncRunResult followedBy(SyncRunResult next) => SyncRunResult(
        processed: processed + next.processed,
        synced: synced + next.synced,
        failed: failed + next.failed,
        conflicts: conflicts + next.conflicts,
        offline: next.offline,
        stoppedTemporarily: next.stoppedTemporarily,
        disabled: next.disabled,
        error: next.error ?? (next.processed == 0 ? error : null),
      );
}
