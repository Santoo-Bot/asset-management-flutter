import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/db/app_database.dart';
import '../../data/db/change_recorder.dart';

enum ScanOutcome { found, duplicate, unregistered }

class AuditSessionItem {
  const AuditSessionItem({required this.id, required this.name, required this.startedAt, this.finishedAt});
  final String id;
  final String name;
  final int startedAt;
  final int? finishedAt;
  bool get isOpen => finishedAt == null;
}

class AuditSummary {
  const AuditSummary({required this.found, required this.missing, required this.unregistered, required this.expected});
  final int found;
  final int missing;
  final int unregistered;

  /// Jumlah aset aktif (selain write off) saat ini.
  final int expected;
}

class ScanResult {
  const ScanResult(this.outcome, this.code, {this.assetName});
  final ScanOutcome outcome;
  final String code;
  final String? assetName;
}

class AuditRepository {
  AuditRepository(this._db, this._recorder, this._deviceId);
  final AppDatabase _db;
  final ChangeRecorder _recorder;
  final String _deviceId;

  Stream<List<AuditSessionItem>> watchSessions() {
    final q = _db.select(_db.auditSessions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    return q.watch().map((rows) => [
          for (final r in rows) AuditSessionItem(id: r.id, name: r.name, startedAt: r.startedAt, finishedAt: r.finishedAt),
        ]);
  }

  Future<String> start(String name) async {
    final title = name.trim();
    if (title.isEmpty) throw ArgumentError('Nama sesi wajib diisi');
    return _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final row = await _db.into(_db.auditSessions).insertReturning(AuditSessionsCompanion.insert(
            name: title,
            startedAt: now,
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
          ));
      await _recorder.record('audit_sessions', row.id, 'insert', {'row': row.toJson()});
      return row.id;
    });
  }

  Future<ScanResult> scan(String sessionId, String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) throw ArgumentError('Kode kosong');
    return _db.transaction(() async {
      final session = await (_db.select(_db.auditSessions)..where((t) => t.id.equals(sessionId))).getSingle();
      if (session.finishedAt != null) throw StateError('Sesi sudah selesai');
      final asset = await (_db.select(_db.assets)..where((t) => t.assetCode.equals(code) & t.deletedAt.isNull()))
          .getSingleOrNull();
      final now = DateTime.now().millisecondsSinceEpoch;

      if (asset != null) {
        final existing = await (_db.select(_db.auditItems)
              ..where((t) => t.sessionId.equals(sessionId) & t.assetId.equals(asset.id) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (existing != null) return ScanResult(ScanOutcome.duplicate, code, assetName: asset.name);
        await _insertItem(sessionId, asset.id, code, 'found', now);
        return ScanResult(ScanOutcome.found, code, assetName: asset.name);
      }
      final dup = await (_db.select(_db.auditItems)
            ..where((t) => t.sessionId.equals(sessionId) & t.scannedCode.equals(code) & t.deletedAt.isNull()))
          .getSingleOrNull();
      if (dup != null) return ScanResult(ScanOutcome.duplicate, code);
      await _insertItem(sessionId, null, code, 'unregistered', now);
      return ScanResult(ScanOutcome.unregistered, code);
    });
  }

  Future<void> _insertItem(String sessionId, String? assetId, String code, String result, int now) async {
    final row = await _db.into(_db.auditItems).insertReturning(AuditItemsCompanion.insert(
          sessionId: sessionId,
          assetId: Value(assetId),
          scannedCode: code,
          result: result,
          scannedAt: Value(now),
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
        ));
    await _recorder.record('audit_items', row.id, 'insert', {'row': row.toJson()});
  }

  /// Menutup sesi; aset aktif yang tidak terpindai dicatat sebagai `missing`.
  Future<void> finish(String sessionId) async {
    await _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final missing = await _db.customSelect(
        "SELECT a.id, a.asset_code FROM assets a WHERE a.deleted_at IS NULL AND a.status != 'written_off' "
        'AND NOT EXISTS (SELECT 1 FROM audit_items i WHERE i.session_id = ? AND i.asset_id = a.id AND i.deleted_at IS NULL)',
        variables: [Variable<String>(sessionId)],
        readsFrom: {_db.assets, _db.auditItems},
      ).get();
      const uuid = Uuid();
      final entries = <ChangeEntry>[];
      final companions = <AuditItemsCompanion>[];
      for (final r in missing) {
        final id = uuid.v7();
        final c = AuditItemsCompanion.insert(
          id: Value(id),
          sessionId: sessionId,
          assetId: Value(r.read<String>('id')),
          scannedCode: r.read<String>('asset_code'),
          result: 'missing',
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
        );
        companions.add(c);
      }
      for (var i = 0; i < companions.length; i += 500) {
        final chunk = companions.sublist(i, i + 500 > companions.length ? companions.length : i + 500);
        await _db.batch((b) => b.insertAll(_db.auditItems, chunk));
      }
      final saved = await (_db.select(_db.auditItems)
            ..where((t) => t.sessionId.equals(sessionId) & t.result.equals('missing')))
          .get();
      for (final row in saved) {
        entries.add(ChangeEntry('audit_items', row.id, 'insert', {'row': row.toJson()}));
      }
      for (var i = 0; i < entries.length; i += 500) {
        await _recorder.recordMany(entries.sublist(i, i + 500 > entries.length ? entries.length : i + 500));
      }
      await (_db.update(_db.auditSessions)..where((t) => t.id.equals(sessionId)))
          .write(AuditSessionsCompanion(finishedAt: Value(now), updatedAt: Value(now)));
      await _recorder.record('audit_sessions', sessionId, 'update', {
        'fields': {'finishedAt': {'o': null, 'n': now}},
      });
    });
  }

  Stream<AuditSummary> watchSummary(String sessionId) {
    return _db.customSelect(
      'SELECT '
      "(SELECT COUNT(*) FROM audit_items WHERE session_id = ?1 AND result = 'found' AND deleted_at IS NULL) AS f, "
      "(SELECT COUNT(*) FROM audit_items WHERE session_id = ?1 AND result = 'missing' AND deleted_at IS NULL) AS m, "
      "(SELECT COUNT(*) FROM audit_items WHERE session_id = ?1 AND result = 'unregistered' AND deleted_at IS NULL) AS u, "
      "(SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL AND status != 'written_off') AS e",
      variables: [Variable<String>(sessionId)],
      readsFrom: {_db.auditItems, _db.assets},
    ).watchSingle().map((r) => AuditSummary(
          found: r.read<int>('f'),
          missing: r.read<int>('m'),
          unregistered: r.read<int>('u'),
          expected: r.read<int>('e'),
        ));
  }

  /// Daftar item sesi menurut hasil (untuk layar detail dan ekspor).
  Future<List<({String code, String? assetName})>> items(String sessionId, String result, {int limit = 500}) async {
    final rows = await _db.customSelect(
      'SELECT i.scanned_code, a.name FROM audit_items i LEFT JOIN assets a ON a.id = i.asset_id '
      'WHERE i.session_id = ? AND i.result = ? AND i.deleted_at IS NULL ORDER BY i.scanned_code LIMIT ?',
      variables: [Variable<String>(sessionId), Variable<String>(result), Variable<int>(limit)],
      readsFrom: {_db.auditItems, _db.assets},
    ).get();
    return [for (final r in rows) (code: r.read<String>('scanned_code'), assetName: r.readNullable<String>('name'))];
  }
}
