import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'sync_models.dart';
import 'sync_payload_sanitizer.dart';

/// One change waiting to be written to the outbox.
class SyncJobRequest {
  const SyncJobRequest({
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.data,
  });

  final String entityType;
  final String entityId;
  final SyncOperation operation;
  final Map<String, dynamic> data;
}

/// Last known server state of an uploaded record. [version] is null for
/// records uploaded before versions were tracked.
class SyncRecordState {
  const SyncRecordState(this.version);

  final int? version;
}

/// Local SQLite outbox for pending server changes.
///
/// Queue rules:
/// - Jobs are sent strictly first-in, first-out (by row id).
/// - One open job per record: a newer change supersedes the open job and a
///   single job with the latest full snapshot goes to the end of the queue.
/// - Create + edit before sending stays a CREATE with the final data.
/// - Delete wins: open creates/updates are cancelled; only the delete is sent.
class SyncQueueRepository {
  Database get _db => AppDatabase.instance;
  static const _uuid = Uuid();

  static const maxAutoRetries = 5;

  Future<SyncQueueItem?> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> data,
  }) async {
    final ids = await enqueueAll([
      SyncJobRequest(
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        data: data,
      ),
    ]);
    if (ids.isEmpty) return null;
    final rows = await _db.query(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [ids.first],
      limit: 1,
    );
    return rows.isEmpty ? null : SyncQueueItem.fromMap(rows.first);
  }

  /// Writes a group of jobs in one all-or-nothing step, in the given order.
  /// Returns the ids of the inserted rows (skipped stale updates excluded).
  Future<List<int>> enqueueAll(List<SyncJobRequest> jobs) async {
    if (jobs.isEmpty) return const [];
    final groupId = _uuid.v4();
    return _db.transaction((txn) async {
      final ids = <int>[];
      for (final job in jobs) {
        final id = await _enqueueOne(txn, job, groupId);
        if (id != null) ids.add(id);
      }
      return ids;
    });
  }

  Future<int?> _enqueueOne(
    Transaction txn,
    SyncJobRequest job,
    String groupId,
  ) async {
    final now = DateTime.now();
    final payload = SyncPayloadSanitizer.sanitize(job.data);

    final open = await txn.query(
      'sync_queue',
      where: 'entity_type = ? AND entity_id = ? '
          'AND status IN (${_placeholders(openSyncStatuses.length)})',
      whereArgs: [
        job.entityType,
        job.entityId,
        ...openSyncStatuses.map((s) => s.dbValue),
      ],
      orderBy: 'id ASC',
    );
    final openItems = open.map(SyncQueueItem.fromMap).toList();
    final openDeletes =
        openItems.where((i) => i.operation == SyncOperation.delete).toList();
    final openUpserts =
        openItems.where((i) => i.operation != SyncOperation.delete).toList();

    var operation = job.operation;
    final toSupersede = <SyncQueueItem>[];

    if (operation == SyncOperation.delete) {
      toSupersede.addAll(openItems);
      payload.remove('forceLocal');
    } else {
      // A record with a queued delete and no re-create is gone: an update
      // for it is stale and must not bring it back.
      if (operation == SyncOperation.update &&
          openDeletes.isNotEmpty &&
          openUpserts.isEmpty) {
        return null;
      }
      toSupersede.addAll(openUpserts);
      if (openUpserts.any((i) => i.operation == SyncOperation.create)) {
        operation = SyncOperation.create;
      }
      if (openUpserts.any((i) => i.forceLocal)) {
        payload['forceLocal'] = true;
      }
    }

    if (toSupersede.isNotEmpty) {
      await txn.update(
        'sync_queue',
        {
          'status': SyncItemStatus.superseded.dbValue,
          'updated_at': now.toIso8601String(),
        },
        where: 'id IN (${_placeholders(toSupersede.length)})',
        whereArgs: [for (final i in toSupersede) i.id],
      );
    }

    final changedAt = _changedAtOf(payload) ?? now;
    return txn.insert('sync_queue', {
      'sync_id': _uuid.v4(),
      'entity_type': job.entityType,
      'entity_id': job.entityId,
      'operation': operation.dbValue,
      'payload': jsonEncode(payload),
      'status': SyncItemStatus.pending.dbValue,
      'retry_count': 0,
      'last_error': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'changed_at': changedAt.toIso8601String(),
      'group_id': groupId,
    });
  }

  static DateTime? _changedAtOf(Map<String, dynamic> payload) {
    for (final key in const ['updatedAt', 'updated_at', 'lastModified']) {
      final raw = payload[key];
      if (raw == null) continue;
      final parsed = DateTime.tryParse('$raw');
      if (parsed != null) return parsed;
    }
    return null;
  }

  static String _placeholders(int n) => List.filled(n, '?').join(', ');

  /// History for the Sync Center (newest first). Superseded jobs are hidden.
  Future<List<SyncQueueItem>> list({
    SyncItemStatus? status,
    int limit = 200,
  }) async {
    final rows = await _db.query(
      'sync_queue',
      where: status == null ? 'status != ?' : 'status = ?',
      whereArgs: [
        status?.dbValue ?? SyncItemStatus.superseded.dbValue,
      ],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(SyncQueueItem.fromMap).toList();
  }

  /// Pending jobs in send order (first-in, first-out).
  Future<List<SyncQueueItem>> pending({int limit = 50}) async {
    final rows = await _db.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: [SyncItemStatus.pending.dbValue],
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(SyncQueueItem.fromMap).toList();
  }

  /// The next pending jobs to upload together, oldest first. A business
  /// action (group) is never split across batches unless the group alone is
  /// larger than [maxJobs].
  Future<List<SyncQueueItem>> nextBatch({int maxJobs = 200}) async {
    final rows = await _db.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: [SyncItemStatus.pending.dbValue],
      orderBy: 'id ASC',
      limit: maxJobs + 1,
    );
    final items = rows.map(SyncQueueItem.fromMap).toList();
    if (items.length <= maxJobs) return items;

    final overflowGroup = items.removeLast().groupId;
    if (overflowGroup == null) return items;
    var end = items.length;
    while (end > 0 && items[end - 1].groupId == overflowGroup) {
      end--;
    }
    return end == 0 ? items : items.sublist(0, end);
  }

  Future<int> countWithStatus(List<SyncItemStatus> statuses) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_queue '
      'WHERE status IN (${_placeholders(statuses.length)})',
      [for (final s in statuses) s.dbValue],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> pendingCount() => countWithStatus([SyncItemStatus.pending]);

  Future<Map<String, int>> countsByStatus() async {
    final rows = await _db.rawQuery(
      'SELECT status, COUNT(*) AS c FROM sync_queue '
      'WHERE status != ? GROUP BY status',
      [SyncItemStatus.superseded.dbValue],
    );
    final map = <String, int>{
      for (final s in SyncItemStatus.values)
        if (s != SyncItemStatus.superseded) s.dbValue: 0,
    };
    for (final row in rows) {
      map['${row['status']}'] = (row['c'] as num).toInt();
    }
    return map;
  }

  Future<Map<String, int>> pendingByEntityType() async {
    final rows = await _db.rawQuery(
      '''
      SELECT entity_type, COUNT(*) AS c
      FROM sync_queue
      WHERE status = ?
      GROUP BY entity_type
      ''',
      [SyncItemStatus.pending.dbValue],
    );
    return {
      for (final row in rows)
        '${row['entity_type']}': (row['c'] as num).toInt(),
    };
  }

  /// Marks a job SYNCED and remembers the snapshot and server [version] the
  /// record now has.
  Future<void> markSynced(SyncQueueItem item, {int? version}) =>
      markSyncedBatch([(item, version)]);

  /// [markSynced] for many jobs in one local transaction.
  Future<void> markSyncedBatch(List<(SyncQueueItem, int?)> results) async {
    if (results.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    await _db.transaction((txn) async {
      for (final (item, version) in results) {
        await txn.update(
          'sync_queue',
          {
            'status': SyncItemStatus.synced.dbValue,
            'last_error': null,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [item.id],
        );
        if (item.operation == SyncOperation.delete) {
          await txn.delete(
            'sync_record_state',
            where: 'entity_type = ? AND entity_id = ?',
            whereArgs: [item.entityType, item.entityId],
          );
        } else {
          await txn.insert(
            'sync_record_state',
            {
              'entity_type': item.entityType,
              'entity_id': item.entityId,
              'payload_hash': snapshotHash(item.payload),
              'synced_at': now,
              'version': version,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  /// What this computer knows about each job's record on the server, keyed
  /// by `entityType/entityId`. Records never uploaded are absent.
  Future<Map<String, SyncRecordState>> recordStates(
    List<SyncQueueItem> items,
  ) async {
    if (items.isEmpty) return const {};
    final keys = {for (final i in items) '${i.entityType}/${i.entityId}'};
    final rows = await _db.rawQuery(
      'SELECT entity_type, entity_id, version FROM sync_record_state '
      "WHERE entity_type || '/' || entity_id IN (${_placeholders(keys.length)})",
      keys.toList(),
    );
    return {
      for (final r in rows)
        '${r['entity_type']}/${r['entity_id']}': SyncRecordState(
          (r['version'] as num?)?.toInt(),
        ),
    };
  }

  /// After "Fetch everything": remember each record's server version so the
  /// next local change can be uploaded without reading the server first.
  Future<void> seedRecordVersions(
    DatabaseExecutor executor,
    String entityType,
    Map<String, Map<String, dynamic>> records,
  ) async {
    final now = DateTime.now().toIso8601String();
    final batch = executor.batch();
    records.forEach((id, data) {
      final version = data['version'];
      batch.insert(
        'sync_record_state',
        {
          'entity_type': entityType,
          'entity_id': id,
          'payload_hash': '',
          'synced_at': now,
          'version': version is num ? version.toInt() : null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }

  /// Removes finished history: superseded jobs after a day, synced jobs
  /// after [keepSynced].
  Future<int> prune({Duration keepSynced = const Duration(days: 30)}) async {
    final now = DateTime.now();
    final superseded = await _db.delete(
      'sync_queue',
      where: 'status = ? AND updated_at < ?',
      whereArgs: [
        SyncItemStatus.superseded.dbValue,
        now.subtract(const Duration(days: 1)).toIso8601String(),
      ],
    );
    final synced = await _db.delete(
      'sync_queue',
      where: 'status = ? AND updated_at < ?',
      whereArgs: [
        SyncItemStatus.synced.dbValue,
        now.subtract(keepSynced).toIso8601String(),
      ],
    );
    return superseded + synced;
  }

  Future<void> markStatus(
    int id, {
    required SyncItemStatus status,
    String? error,
    bool bumpRetry = false,
  }) async {
    await _db.rawUpdate(
      'UPDATE sync_queue SET status = ?, last_error = ?, updated_at = ?'
      '${bumpRetry ? ', retry_count = retry_count + 1' : ''} '
      'WHERE id = ?',
      [status.dbValue, error, DateTime.now().toIso8601String(), id],
    );
  }

  /// Manual retry from the Sync Center (resets the automatic retry budget).
  Future<void> resetToPending(int id) async {
    await _db.update(
      'sync_queue',
      {
        'status': SyncItemStatus.pending.dbValue,
        'last_error': null,
        'retry_count': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND status IN (?, ?)',
      whereArgs: [
        id,
        SyncItemStatus.failed.dbValue,
        SyncItemStatus.pending.dbValue,
      ],
    );
  }

  /// Gives FAILED jobs another automatic chance while under the retry limit.
  Future<int> requeueFailedForAutoRetry() async {
    return _db.update(
      'sync_queue',
      {
        'status': SyncItemStatus.pending.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'status = ? AND retry_count < ?',
      whereArgs: [SyncItemStatus.failed.dbValue, maxAutoRetries],
    );
  }

  /// Conflict → "Keep local": the job is restamped as the newest version,
  /// marked to override the server, and queued again at the end.
  Future<void> resolveKeepLocal(int id) async {
    final rows = await _db.query(
      'sync_queue',
      where: 'id = ? AND status = ?',
      whereArgs: [id, SyncItemStatus.conflict.dbValue],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final item = SyncQueueItem.fromMap(rows.first);
    final now = DateTime.now().toIso8601String();
    await enqueueAll([
      SyncJobRequest(
        entityType: item.entityType,
        entityId: item.entityId,
        operation: item.operation,
        data: {
          ...item.payload,
          'updatedAt': now,
          'updated_at': now,
          'lastModified': now,
          'forceLocal': true,
        },
      ),
    ]);
  }

  /// Fingerprint of a snapshot, independent of key order.
  static String snapshotHash(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)..remove('forceLocal');
    return sha1.convert(utf8.encode(jsonEncode(_canonical(copy)))).toString();
  }

  static Object? _canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _canonical(v[k])};
    }
    if (v is List) return [for (final e in v) _canonical(e)];
    return v;
  }

  /// Hash of the snapshot last accepted by the server, if any.
  Future<String?> lastSentHash(String entityType, String entityId) async {
    final rows = await _db.query(
      'sync_record_state',
      columns: ['payload_hash'],
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['payload_hash'] as String?;
  }

  Future<bool> hasOpenJob(String entityType, String entityId) async {
    final rows = await _db.rawQuery(
      'SELECT 1 FROM sync_queue WHERE entity_type = ? AND entity_id = ? '
      'AND status IN (${_placeholders(openSyncStatuses.length)}) LIMIT 1',
      [entityType, entityId, ...openSyncStatuses.map((s) => s.dbValue)],
    );
    return rows.isNotEmpty;
  }

  Future<void> clearRecordState([DatabaseExecutor? executor]) async {
    await (executor ?? _db).delete('sync_record_state');
  }

  Future<DateTime?> lastSyncAt() async {
    final raw = await metaValue('last_sync_at') ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setLastSyncAt(DateTime at) =>
      setMetaValue('last_sync_at', at.toIso8601String());

  Future<String?> metaValue(String key) async {
    final rows = await _db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMetaValue(String key, String value) async {
    await _db.insert(
      'sync_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Stable id of this installation (one writer per cloud account).
  Future<String> deviceId() async {
    final existing = await metaValue(deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _uuid.v4();
    await setMetaValue(deviceIdKey, id);
    return id;
  }

  static const deviceIdKey = 'device_id';
}
