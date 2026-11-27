import 'package:asset_app/core/hlc.dart';
import 'package:asset_app/data/db/app_database.dart';
import 'package:asset_app/data/db/change_recorder.dart';
import 'package:asset_app/features/assets/data/drift_asset_repository.dart';
import 'package:asset_app/features/assets/domain/asset_models.dart';
import 'package:asset_app/features/masters/data/drift_master_repository.dart';
import 'package:asset_app/features/masters/domain/master_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftAssetRepository assets;
  late DriftMasterRepository masters;
  late String categoryId;

  setUp(() async {
    db = AppDatabase.memory();
    const device = 'dev-test';
    final recorder = ChangeRecorder(db, Hlc(device), device);
    assets = DriftAssetRepository(db, recorder, device);
    masters = DriftMasterRepository(db, recorder, device);
    categoryId = await masters.saveCategory(const CategoryItem(name: 'Elektronik', codePrefix: 'IT', usefulLifeYears: 4));
  });
  tearDown(() => db.close());

  AssetDraft draft(String name, {String? code}) => AssetDraft(assetCode: code, name: name, categoryId: categoryId);

  test('kode otomatis berurutan per awalan kategori', () async {
    final a = await assets.create(draft('Laptop'));
    final b = await assets.create(draft('Monitor'));
    expect((await assets.get(a))!.code, 'IT-000001');
    expect((await assets.get(b))!.code, 'IT-000002');
  });

  test('kode manual ganda ditolak', () async {
    await assets.create(draft('Laptop', code: 'X-1'));
    expect(assets.create(draft('Lain', code: 'X-1')), throwsA(isA<ValidationError>()));
  });

  test('validasi: nama kosong dan harga negatif', () async {
    expect(assets.create(draft('  ')), throwsA(isA<ValidationError>()));
    expect(
      assets.create(AssetDraft(name: 'A', categoryId: categoryId, purchasePrice: -1)),
      throwsA(isA<ValidationError>()),
    );
  });

  test('setiap insert/update/delete tercatat di change_log dalam transaksi yang sama', () async {
    final id = await assets.create(draft('Laptop'));
    await assets.update(id, AssetDraft(name: 'Laptop Baru', categoryId: categoryId, assetCode: 'IT-000001'));
    await assets.softDelete(id);
    final log = await (db.select(db.changeLog)..where((t) => t.entityId.equals(id))).get();
    expect(log.map((e) => e.op), ['insert', 'update', 'delete']);
    expect(log[1].payload, contains('"name"'));
    expect(log.map((e) => e.hlc).toSet(), hasLength(3)); // HLC unik
  });

  test('update tanpa perubahan tidak menulis change_log', () async {
    final id = await assets.create(draft('Laptop'));
    await assets.update(id, AssetDraft(name: 'Laptop', categoryId: categoryId, assetCode: 'IT-000001'));
    final log = await (db.select(db.changeLog)..where((t) => t.entityId.equals(id))).get();
    expect(log, hasLength(1));
  });

  test('keyset paging: tanpa duplikat dan tanpa celah', () async {
    for (var i = 0; i < 120; i++) {
      await assets.create(draft('Aset ${i.toString().padLeft(3, '0')}'));
    }
    final seen = <String>[];
    AssetCursor? cursor;
    while (true) {
      final page = await assets.page(after: cursor, limit: 50);
      if (page.isEmpty) break;
      seen.addAll(page.map((e) => e.id));
      cursor = page.last.cursor;
      if (page.length < 50) break;
    }
    expect(seen, hasLength(120));
    expect(seen.toSet(), hasLength(120));
  });

  test('pencarian FTS dengan filter kategori; aset terhapus tidak muncul', () async {
    final id = await assets.create(draft('Laptop Lenovo'));
    await assets.create(draft('Laptop Dell'));
    expect(await assets.search('lapt'), hasLength(2));
    expect(await assets.search('lenovo', filter: AssetFilter(categoryId: categoryId)), hasLength(1));
    expect(await assets.search('lenovo', filter: const AssetFilter(categoryId: 'lain')), isEmpty);
    await assets.softDelete(id);
    expect(await assets.search('lenovo'), isEmpty);
  });

  test('penyusutan di detail memakai umur dan residu kategori', () async {
    final id = await assets.create(AssetDraft(
      name: 'Server',
      categoryId: categoryId,
      purchaseDate: DateTime(2024, 1, 1).millisecondsSinceEpoch,
      purchasePrice: 4800000,
    ));
    final d = (await assets.get(id))!;
    final r = d.depreciation(DateTime(2025, 1, 1))!;
    expect(r.accumulated, 1200000); // 12 dari 48 bulan
  });

  test('kategori yang dipakai aset tidak bisa dihapus', () async {
    await assets.create(draft('Laptop'));
    expect(masters.deleteCategory(categoryId), throwsA(isA<MasterInUse>()));
  });
}
