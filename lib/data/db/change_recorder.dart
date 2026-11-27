import 'dart:convert';

import '../../core/hlc.dart';
import 'app_database.dart';

class ChangeEntry {
  const ChangeEntry(this.entity, this.entityId, this.op, this.payload);
  final String entity;
  final String entityId;

  /// insert | update | delete
  final String op;
  final Map<String, Object?> payload;
}

/// Mencatat tiap perubahan ke `change_log`. Selalu dipanggil di dalam transaksi
/// yang sama dengan penulisan datanya (spesifikasi bagian 3).
class ChangeRecorder {
  ChangeRecorder(this._db, this._hlc, this.deviceId);

  final AppDatabase _db;
  final Hlc _hlc;
  final String deviceId;

  Future<void> record(String entity, String entityId, String op, Map<String, Object?> payload) {
    return _db.into(_db.changeLog).insert(_companion(ChangeEntry(entity, entityId, op, payload)));
  }

  Future<void> recordMany(List<ChangeEntry> entries) {
    if (entries.isEmpty) return Future.value();
    return _db.batch((b) => b.insertAll(_db.changeLog, [for (final e in entries) _companion(e)]));
  }

  ChangeLogCompanion _companion(ChangeEntry e) => ChangeLogCompanion.insert(
        entity: e.entity,
        entityId: e.entityId,
        op: e.op,
        payload: jsonEncode(e.payload),
        hlc: _hlc.next(),
        deviceId: deviceId,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
}

/// Memulihkan jam HLC dari `change_log` agar urutan tetap naik setelah restart.
Future<Hlc> loadHlc(AppDatabase db, String deviceId) async {
  final hlc = Hlc(deviceId);
  final row = await db.customSelect('SELECT MAX(hlc) AS m FROM change_log').getSingle();
  final last = row.readNullable<String>('m');
  if (last != null) hlc.observe(last);
  return hlc;
}
