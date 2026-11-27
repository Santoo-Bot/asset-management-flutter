import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/db/change_recorder.dart';

enum MovementType {
  transfer('transfer', 'Pindah lokasi'),
  assign('assign', 'Serah terima ke penanggung jawab'),
  returned('return', 'Pengembalian'),
  other('other', 'Lainnya');

  const MovementType(this.code, this.label);
  final String code;
  final String label;
  static MovementType fromCode(String c) => values.firstWhere((e) => e.code == c, orElse: () => other);
}

class MovementItem {
  const MovementItem({
    required this.id,
    required this.type,
    required this.at,
    this.fromLocation,
    this.toLocation,
    this.person,
    this.note,
  });
  final String id;
  final MovementType type;
  final int at;
  final String? fromLocation;
  final String? toLocation;
  final String? person;
  final String? note;
}

/// Mutasi bersifat hanya-tambah. Mencatat riwayat DAN memperbarui posisi aset dalam satu transaksi.
class MovementRepository {
  MovementRepository(this._db, this._recorder, this._deviceId);
  final AppDatabase _db;
  final ChangeRecorder _recorder;
  final String _deviceId;

  Stream<List<MovementItem>> watch(String assetId) {
    return _db.customSelect(
      'SELECT m.id, m.type, m."at" AS at_ms, m.note, fl.name AS from_name, tl.name AS to_name, p.name AS person_name '
      'FROM asset_movements m '
      'LEFT JOIN locations fl ON fl.id = m.from_location_id '
      'LEFT JOIN locations tl ON tl.id = m.to_location_id '
      'LEFT JOIN people p ON p.id = m.person_id '
      'WHERE m.asset_id = ? AND m.deleted_at IS NULL ORDER BY m."at" DESC, m.id DESC',
      variables: [Variable<String>(assetId)],
      readsFrom: {_db.assetMovements, _db.locations, _db.people},
    ).watch().map((rows) => [
          for (final r in rows)
            MovementItem(
              id: r.read<String>('id'),
              type: MovementType.fromCode(r.read<String>('type')),
              at: r.read<int>('at_ms'),
              fromLocation: r.readNullable<String>('from_name'),
              toLocation: r.readNullable<String>('to_name'),
              person: r.readNullable<String>('person_name'),
              note: r.readNullable<String>('note'),
            ),
        ]);
  }

  Future<void> record({
    required String assetId,
    required MovementType type,
    String? toLocationId,
    String? personId,
    int? at,
    String? note,
  }) async {
    if (type == MovementType.transfer && toLocationId == null) {
      throw ArgumentError('Lokasi tujuan wajib diisi');
    }
    if (type == MovementType.assign && personId == null) {
      throw ArgumentError('Penanggung jawab wajib dipilih');
    }
    await _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final asset = await (_db.select(_db.assets)..where((t) => t.id.equals(assetId))).getSingle();
      final newLocation = toLocationId ?? asset.locationId;
      final newPerson = type == MovementType.returned ? null : (personId ?? asset.assignedTo);
      final row = await _db.into(_db.assetMovements).insertReturning(AssetMovementsCompanion.insert(
            assetId: assetId,
            type: type.code,
            fromLocationId: Value(asset.locationId),
            toLocationId: Value(newLocation),
            personId: Value(newPerson),
            at: at ?? now,
            note: Value((note?.trim().isEmpty ?? true) ? null : note!.trim()),
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
          ));
      await _recorder.record('asset_movements', row.id, 'insert', {'row': row.toJson()});

      final changed = <String, Object?>{
        if (asset.locationId != newLocation) 'locationId': {'o': asset.locationId, 'n': newLocation},
        if (asset.assignedTo != newPerson) 'assignedTo': {'o': asset.assignedTo, 'n': newPerson},
      };
      if (changed.isNotEmpty) {
        await (_db.update(_db.assets)..where((t) => t.id.equals(assetId))).write(AssetsCompanion(
          locationId: Value(newLocation),
          assignedTo: Value(newPerson),
          updatedAt: Value(now),
          version: Value(asset.version + 1),
        ));
        await _recorder.record('assets', assetId, 'update', {'fields': changed});
      }
    });
  }
}
