import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sync_models.dart';
import 'sync_queue_repository.dart';

/// Entry point for repositories to queue sync jobs.
///
/// Call only after the local save has committed. Jobs from one business
/// action should be queued inside [group] so they are written together and
/// the background sender is woken once, never in the middle of the action.
abstract final class SyncOutbox {
  static final SyncQueueRepository _repo = SyncQueueRepository();

  /// Bumps once per queued group — listeners start a sync when it changes.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String? lastError;

  static const _groupKey = #syncOutboxGroup;

  /// Runs [body] and queues every job it enqueues as one group, in call
  /// order (dependencies first, parent record last). The group is written
  /// in a single transaction, so the sender never sees half of it.
  static Future<T> group<T>(Future<T> Function() body) async {
    if (Zone.current[_groupKey] is List<SyncJobRequest>) return body();

    final buffer = <SyncJobRequest>[];
    try {
      return await runZoned(body, zoneValues: {_groupKey: buffer});
    } finally {
      await _write(buffer);
    }
  }

  static Future<void> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> data,
  }) async {
    final job = SyncJobRequest(
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      data: data,
    );
    final buffer = Zone.current[_groupKey];
    if (buffer is List<SyncJobRequest>) {
      buffer.add(job);
      return;
    }
    await group(() async {
      (Zone.current[_groupKey] as List<SyncJobRequest>).add(job);
    });
  }

  static Future<void> _write(List<SyncJobRequest> jobs) async {
    if (jobs.isEmpty) return;
    try {
      final ids = await _repo.enqueueAll(jobs);
      lastError = null;
      debugPrint(
        '[SyncOutbox] queued group of ${ids.length}: '
        '${jobs.map((j) => '${j.operation.dbValue} ${j.entityType}/${j.entityId}').join(', ')}',
      );
      revision.value = revision.value + 1;
    } catch (e, st) {
      lastError = e.toString();
      debugPrint('[SyncOutbox] enqueue FAILED: $e\n$st');
    }
  }
}
