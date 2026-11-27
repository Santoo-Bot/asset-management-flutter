import 'package:drift/drift.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/change_recorder.dart';
import '../domain/master_models.dart';

class DriftMasterRepository implements MasterRepository {
  DriftMasterRepository(this._db, this._recorder, this._deviceId);

  final AppDatabase _db;
  final ChangeRecorder _recorder;
  final String _deviceId;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  Stream<List<CategoryItem>> watchCategories() {
    final q = _db.select(_db.categories)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch().map((rows) => [
          for (final r in rows)
            CategoryItem(
              id: r.id,
              name: r.name,
              codePrefix: r.codePrefix,
              usefulLifeYears: r.usefulLifeYears,
              residualPercent: r.residualPercent,
            ),
        ]);
  }

  @override
  Stream<List<LocationItem>> watchLocations() {
    final q = _db.select(_db.locations)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch().map((rows) => [
          for (final r in rows) LocationItem(id: r.id, name: r.name, parentId: r.parentId, kind: r.kind),
        ]);
  }

  @override
  Stream<List<PersonItem>> watchPeople() {
    final q = _db.select(_db.people)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch().map((rows) => [
          for (final r in rows) PersonItem(id: r.id, name: r.name, unit: r.unit, contact: r.contact),
        ]);
  }

  static String? _nn(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  @override
  Future<String> saveCategory(CategoryItem item) {
    final name = item.name.trim();
    final prefix = item.codePrefix.trim().toUpperCase();
    if (name.isEmpty) throw ArgumentError('Nama kategori wajib diisi');
    if (!RegExp(r'^[A-Z0-9]{1,8}$').hasMatch(prefix)) {
      throw ArgumentError('Awalan kode: 1-8 huruf/angka');
    }
    if (item.usefulLifeYears < 1) throw ArgumentError('Umur ekonomis minimal 1 tahun');
    return _db.transaction(() async {
      if (item.id == null) {
        final row = await _db.into(_db.categories).insertReturning(CategoriesCompanion.insert(
              name: name,
              codePrefix: prefix,
              usefulLifeYears: Value(item.usefulLifeYears),
              residualPercent: Value(item.residualPercent),
              createdAt: _now,
              updatedAt: _now,
              deviceId: _deviceId,
            ));
        await _recorder.record('categories', row.id, 'insert', {'row': row.toJson()});
        return row.id;
      }
      final old = await (_db.select(_db.categories)..where((t) => t.id.equals(item.id!))).getSingle();
      final fields = <String, Object?>{
        if (old.name != name) 'name': {'o': old.name, 'n': name},
        if (old.codePrefix != prefix) 'codePrefix': {'o': old.codePrefix, 'n': prefix},
        if (old.usefulLifeYears != item.usefulLifeYears)
          'usefulLifeYears': {'o': old.usefulLifeYears, 'n': item.usefulLifeYears},
        if (old.residualPercent != item.residualPercent)
          'residualPercent': {'o': old.residualPercent, 'n': item.residualPercent},
      };
      if (fields.isNotEmpty) {
        await (_db.update(_db.categories)..where((t) => t.id.equals(item.id!))).write(CategoriesCompanion(
          name: Value(name),
          codePrefix: Value(prefix),
          usefulLifeYears: Value(item.usefulLifeYears),
          residualPercent: Value(item.residualPercent),
          updatedAt: Value(_now),
        ));
        await _recorder.record('categories', item.id!, 'update', {'fields': fields});
      }
      return item.id!;
    });
  }

  @override
  Future<String> saveLocation(LocationItem item) {
    final name = item.name.trim();
    if (name.isEmpty) throw ArgumentError('Nama lokasi wajib diisi');
    if (item.id != null && item.parentId == item.id) throw ArgumentError('Lokasi tidak bisa menjadi induk dirinya sendiri');
    return _db.transaction(() async {
      if (item.id == null) {
        final row = await _db.into(_db.locations).insertReturning(LocationsCompanion.insert(
              name: name,
              parentId: Value(item.parentId),
              kind: Value(item.kind),
              createdAt: _now,
              updatedAt: _now,
              deviceId: _deviceId,
            ));
        await _recorder.record('locations', row.id, 'insert', {'row': row.toJson()});
        return row.id;
      }
      final old = await (_db.select(_db.locations)..where((t) => t.id.equals(item.id!))).getSingle();
      final fields = <String, Object?>{
        if (old.name != name) 'name': {'o': old.name, 'n': name},
        if (old.parentId != item.parentId) 'parentId': {'o': old.parentId, 'n': item.parentId},
        if (old.kind != item.kind) 'kind': {'o': old.kind, 'n': item.kind},
      };
      if (fields.isNotEmpty) {
        await (_db.update(_db.locations)..where((t) => t.id.equals(item.id!))).write(LocationsCompanion(
          name: Value(name),
          parentId: Value(item.parentId),
          kind: Value(item.kind),
          updatedAt: Value(_now),
        ));
        await _recorder.record('locations', item.id!, 'update', {'fields': fields});
      }
      return item.id!;
    });
  }

  @override
  Future<String> savePerson(PersonItem item) {
    final name = item.name.trim();
    if (name.isEmpty) throw ArgumentError('Nama wajib diisi');
    return _db.transaction(() async {
      if (item.id == null) {
        final row = await _db.into(_db.people).insertReturning(PeopleCompanion.insert(
              name: name,
              unit: Value(_nn(item.unit)),
              contact: Value(_nn(item.contact)),
              createdAt: _now,
              updatedAt: _now,
              deviceId: _deviceId,
            ));
        await _recorder.record('people', row.id, 'insert', {'row': row.toJson()});
        return row.id;
      }
      final old = await (_db.select(_db.people)..where((t) => t.id.equals(item.id!))).getSingle();
      final fields = <String, Object?>{
        if (old.name != name) 'name': {'o': old.name, 'n': name},
        if (old.unit != _nn(item.unit)) 'unit': {'o': old.unit, 'n': _nn(item.unit)},
        if (old.contact != _nn(item.contact)) 'contact': {'o': old.contact, 'n': _nn(item.contact)},
      };
      if (fields.isNotEmpty) {
        await (_db.update(_db.people)..where((t) => t.id.equals(item.id!))).write(PeopleCompanion(
          name: Value(name),
          unit: Value(_nn(item.unit)),
          contact: Value(_nn(item.contact)),
          updatedAt: Value(_now),
        ));
        await _recorder.record('people', item.id!, 'update', {'fields': fields});
      }
      return item.id!;
    });
  }

  Future<int> _count(String sql, String id) async {
    final r = await _db.customSelect(sql, variables: [Variable<String>(id)]).getSingle();
    return r.read<int>('n');
  }

  Future<void> _softDelete(TableInfo<Table, dynamic> table, String entity, String id) async {
    await _db.customUpdate(
      'UPDATE ${table.actualTableName} SET deleted_at = ?, updated_at = ? WHERE id = ?',
      variables: [Variable<int>(_now), Variable<int>(_now), Variable<String>(id)],
      updates: {table},
    );
    await _recorder.record(entity, id, 'delete', {});
  }

  @override
  Future<void> deleteCategory(String id) => _db.transaction(() async {
        final used = await _count('SELECT COUNT(*) AS n FROM assets WHERE category_id = ? AND deleted_at IS NULL', id);
        if (used > 0) throw MasterInUse('Kategori masih dipakai $used aset');
        await _softDelete(_db.categories, 'categories', id);
      });

  @override
  Future<void> deleteLocation(String id) => _db.transaction(() async {
        final used = await _count('SELECT COUNT(*) AS n FROM assets WHERE location_id = ? AND deleted_at IS NULL', id);
        if (used > 0) throw MasterInUse('Lokasi masih dipakai $used aset');
        final kids = await _count('SELECT COUNT(*) AS n FROM locations WHERE parent_id = ? AND deleted_at IS NULL', id);
        if (kids > 0) throw MasterInUse('Lokasi masih punya $kids sub-lokasi');
        await _softDelete(_db.locations, 'locations', id);
      });

  @override
  Future<void> deletePerson(String id) => _db.transaction(() async {
        final used = await _count('SELECT COUNT(*) AS n FROM assets WHERE assigned_to = ? AND deleted_at IS NULL', id);
        if (used > 0) throw MasterInUse('Penanggung jawab masih dipakai $used aset');
        await _softDelete(_db.people, 'people', id);
      });
}
