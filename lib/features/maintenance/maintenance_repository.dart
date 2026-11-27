import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/db/change_recorder.dart';

enum MaintenanceType {
  preventive('preventive', 'Preventif'),
  corrective('corrective', 'Korektif'),
  calibration('calibration', 'Kalibrasi'),
  inspection('inspection', 'Inspeksi');

  const MaintenanceType(this.code, this.label);
  final String code;
  final String label;
  static MaintenanceType fromCode(String c) => values.firstWhere((e) => e.code == c, orElse: () => preventive);
}

class MaintenanceItem {
  const MaintenanceItem({required this.id, required this.date, required this.type, required this.cost, this.nextDue, this.note});
  final String id;
  final int date;
  final MaintenanceType type;
  final int cost;
  final int? nextDue;
  final String? note;
}

enum ReminderKind { maintenance, warranty }

class Reminder {
  const Reminder({required this.kind, required this.assetId, required this.assetCode, required this.assetName, required this.dueDate});
  final ReminderKind kind;
  final String assetId;
  final String assetCode;
  final String assetName;
  final int dueDate;

  bool get overdue => dueDate < DateTime.now().millisecondsSinceEpoch;
}

class MaintenanceRepository {
  MaintenanceRepository(this._db, this._recorder, this._deviceId);
  final AppDatabase _db;
  final ChangeRecorder _recorder;
  final String _deviceId;

  Stream<List<MaintenanceItem>> watch(String assetId) {
    final q = _db.select(_db.maintenance)
      ..where((t) => t.assetId.equals(assetId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)]);
    return q.watch().map((rows) => [
          for (final r in rows)
            MaintenanceItem(
              id: r.id,
              date: r.date,
              type: MaintenanceType.fromCode(r.type),
              cost: r.cost,
              nextDue: r.nextDue,
              note: r.note,
            ),
        ]);
  }

  Future<void> add({
    required String assetId,
    required MaintenanceType type,
    required int date,
    int cost = 0,
    int? nextDue,
    String? note,
  }) async {
    if (cost < 0) throw ArgumentError('Biaya tidak boleh negatif');
    if (nextDue != null && nextDue < date) throw ArgumentError('Jadwal berikutnya tidak boleh sebelum tanggal perawatan');
    await _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final row = await _db.into(_db.maintenance).insertReturning(MaintenanceCompanion.insert(
            assetId: assetId,
            date: date,
            type: type.code,
            cost: Value(cost),
            nextDue: Value(nextDue),
            note: Value((note?.trim().isEmpty ?? true) ? null : note!.trim()),
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
          ));
      await _recorder.record('maintenance', row.id, 'insert', {'row': row.toJson()});
    });
  }

  Future<void> delete(String id) async {
    await _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await (_db.update(_db.maintenance)..where((t) => t.id.equals(id)))
          .write(MaintenanceCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      await _recorder.record('maintenance', id, 'delete', {});
    });
  }

  /// Pengingat tanpa internet: jadwal perawatan terakhir tiap aset dan garansi yang akan/sudah habis.
  Future<List<Reminder>> reminders({int days = 30, int warrantyDays = 90}) async {
    final now = DateTime.now();
    final maintLimit = now.add(Duration(days: days)).millisecondsSinceEpoch;
    final warrLimit = now.add(Duration(days: warrantyDays)).millisecondsSinceEpoch;
    final result = <Reminder>[];

    final m = await _db.customSelect(
      'SELECT a.id, a.asset_code, a.name, mt.next_due FROM maintenance mt '
      'JOIN assets a ON a.id = mt.asset_id AND a.deleted_at IS NULL '
      'WHERE mt.deleted_at IS NULL AND mt.next_due IS NOT NULL AND mt.next_due <= ? '
      'AND mt.date = (SELECT MAX(x.date) FROM maintenance x WHERE x.asset_id = mt.asset_id AND x.deleted_at IS NULL) '
      'GROUP BY a.id ORDER BY mt.next_due LIMIT 200',
      variables: [Variable<int>(maintLimit)],
      readsFrom: {_db.maintenance, _db.assets},
    ).get();
    for (final r in m) {
      result.add(Reminder(
        kind: ReminderKind.maintenance,
        assetId: r.read<String>('id'),
        assetCode: r.read<String>('asset_code'),
        assetName: r.read<String>('name'),
        dueDate: r.read<int>('next_due'),
      ));
    }

    final w = await _db.customSelect(
      'SELECT id, asset_code, name, warranty_until FROM assets '
      'WHERE deleted_at IS NULL AND status != \'written_off\' AND warranty_until IS NOT NULL AND warranty_until <= ? '
      'ORDER BY warranty_until LIMIT 200',
      variables: [Variable<int>(warrLimit)],
      readsFrom: {_db.assets},
    ).get();
    for (final r in w) {
      result.add(Reminder(
        kind: ReminderKind.warranty,
        assetId: r.read<String>('id'),
        assetCode: r.read<String>('asset_code'),
        assetName: r.read<String>('name'),
        dueDate: r.read<int>('warranty_until'),
      ));
    }
    result.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return result;
  }
}
