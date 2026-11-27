import 'package:drift/drift.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/change_recorder.dart';
import '../domain/asset_models.dart';

class DriftAssetRepository implements AssetRepository {
  DriftAssetRepository(this._db, this._recorder, this._deviceId);

  final AppDatabase _db;
  final ChangeRecorder _recorder;
  final String _deviceId;

  static const _listColumns = 'a.id, a.asset_code, a.name, a.status, a.condition, a.purchase_price, '
      'c.name AS category_name, l.name AS location_name';
  static const _joins = 'JOIN categories c ON c.id = a.category_id '
      'LEFT JOIN locations l ON l.id = a.location_id';

  static AssetListItem _item(QueryRow r) => AssetListItem(
        id: r.read<String>('id'),
        code: r.read<String>('asset_code'),
        name: r.read<String>('name'),
        status: AssetStatus.fromCode(r.read<String>('status')),
        condition: AssetCondition.fromCode(r.read<String>('condition')),
        categoryName: r.read<String>('category_name'),
        locationName: r.readNullable<String>('location_name'),
        purchasePrice: r.readNullable<int>('purchase_price'),
      );

  void _filterSql(AssetFilter f, List<String> where, List<Variable> vars) {
    if (f.categoryId != null) {
      where.add('a.category_id = ?');
      vars.add(Variable<String>(f.categoryId!));
    }
    if (f.locationId != null) {
      where.add('a.location_id = ?');
      vars.add(Variable<String>(f.locationId!));
    }
    if (f.status != null) {
      where.add('a.status = ?');
      vars.add(Variable<String>(f.status!.code));
    }
  }

  @override
  Future<List<AssetListItem>> page({AssetFilter filter = const AssetFilter(), AssetCursor? after, int limit = 50}) async {
    final where = <String>['a.deleted_at IS NULL'];
    final vars = <Variable>[];
    _filterSql(filter, where, vars);
    if (after != null) {
      where.add('(a.name, a.id) > (?, ?)');
      vars..add(Variable<String>(after.name))..add(Variable<String>(after.id));
    }
    final rows = await _db.customSelect(
      'SELECT $_listColumns FROM assets a $_joins WHERE ${where.join(' AND ')} '
      'ORDER BY a.name, a.id LIMIT ?',
      variables: [...vars, Variable<int>(limit)],
      readsFrom: {_db.assets, _db.categories, _db.locations},
    ).get();
    return rows.map(_item).toList();
  }

  @override
  Future<List<AssetListItem>> search(String text, {AssetFilter filter = const AssetFilter(), int limit = 100}) async {
    final fts = toFtsQuery(text);
    if (fts == null) return const [];
    final where = <String>['asset_fts MATCH ?', 'a.deleted_at IS NULL'];
    final vars = <Variable>[Variable<String>(fts)];
    _filterSql(filter, where, vars);
    final rows = await _db.customSelect(
      'SELECT $_listColumns FROM asset_fts f JOIN assets a ON a.rowid = f.rowid $_joins '
      'WHERE ${where.join(' AND ')} ORDER BY rank LIMIT ?',
      variables: [...vars, Variable<int>(limit)],
      readsFrom: {_db.assets, _db.categories, _db.locations},
    ).get();
    return rows.map(_item).toList();
  }

  @override
  Future<AssetDetail?> get(String id) async {
    final row = await (_db.select(_db.assets)..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (row == null) return null;
    final cat = await (_db.select(_db.categories)..where((t) => t.id.equals(row.categoryId))).getSingle();
    final loc = row.locationId == null
        ? null
        : await (_db.select(_db.locations)..where((t) => t.id.equals(row.locationId!))).getSingleOrNull();
    final person = row.assignedTo == null
        ? null
        : await (_db.select(_db.people)..where((t) => t.id.equals(row.assignedTo!))).getSingleOrNull();
    return AssetDetail(
      id: row.id,
      code: row.assetCode,
      draft: AssetDraft(
        assetCode: row.assetCode,
        name: row.name,
        categoryId: row.categoryId,
        locationId: row.locationId,
        status: AssetStatus.fromCode(row.status),
        condition: AssetCondition.fromCode(row.condition),
        serialNumber: row.serialNumber,
        brand: row.brand,
        model: row.model,
        purchaseDate: row.purchaseDate,
        purchasePrice: row.purchasePrice,
        vendor: row.vendor,
        assignedTo: row.assignedTo,
        warrantyUntil: row.warrantyUntil,
        disposedAt: row.disposedAt,
        notes: row.notes,
      ),
      categoryName: cat.name,
      usefulLifeYears: cat.usefulLifeYears,
      residualPercent: cat.residualPercent,
      locationName: loc?.name,
      personName: person?.name,
      updatedAt: row.updatedAt,
    );
  }

  @override
  Future<String?> idByCode(String code) async {
    final row = await (_db.select(_db.assets)
          ..where((t) => t.assetCode.equals(code.trim()) & t.deletedAt.isNull()))
        .getSingleOrNull();
    return row?.id;
  }

  /// Kode berikutnya: `<AWALAN>-000123`. Dipanggil di dalam transaksi.
  Future<String> _nextCode(String categoryId) async {
    final cat = await (_db.select(_db.categories)..where((t) => t.id.equals(categoryId))).getSingle();
    final prefix = cat.codePrefix.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final r = await _db.customSelect(
      'SELECT asset_code FROM assets WHERE asset_code LIKE ? ORDER BY asset_code DESC LIMIT 1',
      variables: [Variable<String>('$prefix-%')],
    ).getSingleOrNull();
    var next = 1;
    if (r != null) {
      final code = r.read<String>('asset_code');
      next = (int.tryParse(code.substring(code.lastIndexOf('-') + 1)) ?? 0) + 1;
    }
    return '$prefix-${next.toString().padLeft(6, '0')}';
  }

  AssetsCompanion _companion(AssetDraft d, {required String code, required int now}) => AssetsCompanion(
        assetCode: Value(code),
        name: Value(d.name.trim()),
        categoryId: Value(d.categoryId),
        locationId: Value(d.locationId),
        status: Value(d.status.code),
        condition: Value(d.condition.code),
        serialNumber: Value(_blankToNull(d.serialNumber)),
        brand: Value(_blankToNull(d.brand)),
        model: Value(_blankToNull(d.model)),
        purchaseDate: Value(d.purchaseDate),
        purchasePrice: Value(d.purchasePrice),
        vendor: Value(_blankToNull(d.vendor)),
        assignedTo: Value(d.assignedTo),
        warrantyUntil: Value(d.warrantyUntil),
        disposedAt: Value(d.disposedAt),
        notes: Value(_blankToNull(d.notes)),
        updatedAt: Value(now),
      );

  static String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  @override
  Future<String> create(AssetDraft draft) async {
    final error = validateDraft(draft);
    if (error != null) throw ValidationError(error);
    return _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final given = draft.assetCode?.trim() ?? '';
      final code = given.isEmpty ? await _nextCode(draft.categoryId) : given;
      if (await idByCode(code) != null) throw ValidationError('Kode aset "$code" sudah dipakai');
      final row = await _db.into(_db.assets).insertReturning(
            _companion(draft, code: code, now: now).copyWith(
              createdAt: Value(now),
              deviceId: Value(_deviceId),
            ),
          );
      await _recorder.record('assets', row.id, 'insert', {'row': row.toJson()});
      return row.id;
    });
  }

  @override
  Future<void> update(String id, AssetDraft draft) async {
    final error = validateDraft(draft);
    if (error != null) throw ValidationError(error);
    await _db.transaction(() async {
      final old = await (_db.select(_db.assets)..where((t) => t.id.equals(id))).getSingle();
      final code = (draft.assetCode?.trim().isNotEmpty ?? false) ? draft.assetCode!.trim() : old.assetCode;
      if (code != old.assetCode && await idByCode(code) != null) {
        throw ValidationError('Kode aset "$code" sudah dipakai');
      }
      final newMap = {...draft.toMap(), 'assetCode': code};
      final oldJson = old.toJson();
      final changed = <String, Object?>{};
      newMap.forEach((key, value) {
        final normalized = value is String && value.trim().isEmpty ? null : value;
        if (oldJson[key] != normalized) changed[key] = {'o': oldJson[key], 'n': normalized};
      });
      if (changed.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await (_db.update(_db.assets)..where((t) => t.id.equals(id))).write(
        _companion(draft, code: code, now: now).copyWith(version: Value(old.version + 1)),
      );
      await _recorder.record('assets', id, 'update', {'fields': changed});
    });
  }

  @override
  Future<void> softDelete(String id) async {
    await _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await (_db.update(_db.assets)..where((t) => t.id.equals(id)))
          .write(AssetsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      await _recorder.record('assets', id, 'delete', {});
    });
  }

  @override
  Stream<List<AssetStatusCount>> watchStatusCounts() {
    return _db
        .customSelect(
          'SELECT status, COUNT(*) AS n, COALESCE(SUM(purchase_price), 0) AS total '
          'FROM assets WHERE deleted_at IS NULL GROUP BY status',
          readsFrom: {_db.assets},
        )
        .watch()
        .map((rows) => [
              for (final r in rows)
                AssetStatusCount(AssetStatus.fromCode(r.read<String>('status')), r.read<int>('n'), r.read<int>('total')),
            ]);
  }
}
