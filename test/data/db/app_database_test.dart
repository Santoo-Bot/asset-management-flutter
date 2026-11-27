import 'package:asset_app/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  const device = 'test-device';
  final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;

  Future<String> addCategory() async {
    final c = await db.into(db.categories).insertReturning(CategoriesCompanion.insert(
          name: 'Elektronik',
          codePrefix: 'IT',
          createdAt: now,
          updatedAt: now,
          deviceId: device,
        ));
    return c.id;
  }

  Future<AssetRow> addAsset(String categoryId, String code, String name, {String? serial}) {
    return db.into(db.assets).insertReturning(AssetsCompanion.insert(
          assetCode: code,
          name: name,
          categoryId: categoryId,
          serialNumber: Value(serial),
          createdAt: now,
          updatedAt: now,
          deviceId: device,
        ));
  }

  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('onCreate mengisi app_meta (schema_version, device_id)', () async {
    expect(await db.deviceId(), isNotEmpty);
    final v = await (db.select(db.appMeta)..where((t) => t.key.equals('schema_version'))).getSingle();
    expect(v.value, '1');
  });

  test('id memakai UUID v7 (urut waktu)', () async {
    final cat = await addCategory();
    final a = await addAsset(cat, 'IT-001', 'Laptop');
    final b = await addAsset(cat, 'IT-002', 'Monitor');
    expect(a.id.length, 36);
    expect(a.id.compareTo(b.id), lessThan(0));
  });

  test('asset_code unik', () async {
    final cat = await addCategory();
    await addAsset(cat, 'IT-001', 'Laptop');
    expect(addAsset(cat, 'IT-001', 'Laptop lain'), throwsA(isA<Exception>()));
  });

  test('DIAGNOSTIK pragma foreign_keys', () async {
    final r = await db.customSelect('PRAGMA foreign_keys').getSingle();
    final ddl = await db.customSelect("SELECT sql FROM sqlite_master WHERE name = 'assets'").getSingle();
    // ignore: avoid_print
    print('FK_PRAGMA=${r.data} DDL=${ddl.data['sql']}');
  });

  test('foreign key aktif: kategori tidak ada ditolak', () async {
    expect(addAsset('tidak-ada', 'X-1', 'Barang'), throwsA(isA<Exception>()));
  });

  test('FTS5: pencarian awalan, nama dan serial', () async {
    final cat = await addCategory();
    await addAsset(cat, 'IT-001', 'Laptop Lenovo ThinkPad', serial: 'SN12345');
    await addAsset(cat, 'IT-002', 'Monitor Dell');
    expect((await db.searchAssets('lapt')).map((e) => e.assetCode), ['IT-001']);
    expect((await db.searchAssets('SN123')).map((e) => e.assetCode), ['IT-001']);
    expect(await db.searchAssets('zzz'), isEmpty);
  });

  test('FTS5 mengikuti update dan mengabaikan aset yang di-soft-delete', () async {
    final cat = await addCategory();
    final a = await addAsset(cat, 'IT-001', 'Laptop');
    await (db.update(db.assets)..where((t) => t.id.equals(a.id))).write(const AssetsCompanion(name: Value('Printer')));
    expect(await db.searchAssets('laptop'), isEmpty);
    expect(await db.searchAssets('printer'), hasLength(1));
    await (db.update(db.assets)..where((t) => t.id.equals(a.id))).write(AssetsCompanion(deletedAt: Value(now)));
    expect(await db.searchAssets('printer'), isEmpty);
  });

  test('input pencarian berisi sintaks FTS tidak membuat error', () async {
    await addCategory();
    expect(await db.searchAssets('"( OR * -'), isEmpty);
  });
}
