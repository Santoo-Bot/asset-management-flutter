import 'dart:convert';

import 'package:asset_app/core/hlc.dart';
import 'package:asset_app/data/db/app_database.dart';
import 'package:asset_app/data/db/change_recorder.dart';
import 'package:asset_app/features/assets/data/drift_asset_repository.dart';
import 'package:asset_app/features/assets/domain/asset_models.dart';
import 'package:asset_app/features/masters/data/drift_master_repository.dart';
import 'package:asset_app/features/masters/domain/master_models.dart';
import 'package:asset_app/features/sync/change_applier.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

/// Satu "perangkat" lengkap dengan database sendiri dan jam yang bisa diatur.
class Device {
  Device(this.id, this.clock) {
    db = AppDatabase.memory();
    hlc = Hlc(id, now: () => clock.value);
    recorder = ChangeRecorder(db, hlc, id);
    assets = DriftAssetRepository(db, recorder, id);
    masters = DriftMasterRepository(db, recorder, id);
  }
  final String id;
  final _Clock clock;
  late final AppDatabase db;
  late final Hlc hlc;
  late final ChangeRecorder recorder;
  late final DriftAssetRepository assets;
  late final DriftMasterRepository masters;

  /// Perubahan milik perangkat ini, seperti isi paket .assetpack.
  Future<List<RemoteChange>> outgoing() async {
    final rows = await (db.select(db.changeLog)..where((t) => t.deviceId.equals(id))).get();
    return [
      for (final r in rows)
        RemoteChange(
          entity: r.entity,
          entityId: r.entityId,
          op: r.op,
          payload: jsonDecode(r.payload) as Map<String, dynamic>,
          hlc: r.hlc,
          deviceId: r.deviceId,
          createdAt: r.createdAt,
        ),
    ];
  }

  Future<ApplyReport> receive(List<RemoteChange> changes) =>
      db.transaction(() => ChangeApplier(db, hlc).applyAll(changes));
}

class _Clock {
  _Clock(this.value);
  int value;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Device a;
  late Device b;
  late String catId;

  setUp(() async {
    a = Device('device-a', _Clock(1000));
    b = Device('device-b', _Clock(1000));
    catId = await a.masters.saveCategory(const CategoryItem(name: 'Elektronik', codePrefix: 'IT'));
    // Sinkronkan kategori ke B lebih dulu.
    await b.receive(await a.outgoing());
  });

  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  Future<String> newAsset(Device d, String name, {String? code}) =>
      d.assets.create(AssetDraft(name: name, categoryId: catId, assetCode: code));

  test('insert dari A muncul di B, dan impor ulang paket yang sama diabaikan (idempoten)', () async {
    final id = await newAsset(a, 'Laptop');
    final pack = await a.outgoing();
    final r1 = await b.receive(pack);
    expect(r1.applied, greaterThan(0));
    expect((await b.assets.get(id))!.draft.name, 'Laptop');
    final r2 = await b.receive(pack);
    expect(r2.applied, 0);
    expect(r2.duplicates, pack.length);
  });

  test('bidang berbeda pada aset yang sama digabung', () async {
    final id = await newAsset(a, 'Laptop');
    await b.receive(await a.outgoing());

    a.clock.value = 2000;
    await a.assets.update(id, AssetDraft(name: 'Laptop', categoryId: catId, assetCode: 'IT-000001', brand: 'Lenovo'));
    b.clock.value = 2100;
    await b.assets.update(id, AssetDraft(name: 'Laptop', categoryId: catId, assetCode: 'IT-000001', serialNumber: 'SN1'));

    await b.receive(await a.outgoing());
    await a.receive(await b.outgoing());
    for (final d in [a, b]) {
      final x = (await d.assets.get(id))!.draft;
      expect(x.brand, 'Lenovo');
      expect(x.serialNumber, 'SN1');
    }
    expect(await b.db.select(b.db.syncConflicts).get(), isEmpty);
  });

  test('bidang sama: HLC terbaru menang dan yang kalah dicatat sebagai konflik', () async {
    final id = await newAsset(a, 'Laptop');
    await b.receive(await a.outgoing());

    a.clock.value = 2000;
    await a.assets.update(id, AssetDraft(name: 'Dari A', categoryId: catId, assetCode: 'IT-000001'));
    b.clock.value = 3000; // B lebih baru
    await b.assets.update(id, AssetDraft(name: 'Dari B', categoryId: catId, assetCode: 'IT-000001'));

    await b.receive(await a.outgoing()); // B menerima perubahan lama A → B menang
    await a.receive(await b.outgoing()); // A menerima perubahan baru B → B menang
    expect((await b.assets.get(id))!.draft.name, 'Dari B');
    expect((await a.assets.get(id))!.draft.name, 'Dari B');
    final conflicts = await b.db.select(b.db.syncConflicts).get();
    expect(conflicts.single.kind, 'field');
    expect(conflicts.single.field, 'name');
  });

  test('hapus vs ubah: ubahan menang, aset dipulihkan, ditandai', () async {
    final id = await newAsset(a, 'Laptop');
    await b.receive(await a.outgoing());

    a.clock.value = 2000;
    await a.assets.softDelete(id);
    b.clock.value = 2100;
    await b.assets.update(id, AssetDraft(name: 'Laptop revisi', categoryId: catId, assetCode: 'IT-000001'));

    await a.receive(await b.outgoing()); // A: terhapus lalu menerima ubahan → pulih
    expect((await a.assets.get(id))!.draft.name, 'Laptop revisi');
    expect((await a.db.select(a.db.syncConflicts).get()).map((e) => e.kind), contains('delete_vs_update'));

    await b.receive(await a.outgoing()); // B: hapusan A lebih lama dari ubahan lokal → dilewati
    expect(await b.assets.get(id), isNotNull);
  });

  test('kode aset kembar dari dua perangkat: yang masuk belakangan diberi akhiran', () async {
    await newAsset(a, 'Laptop A', code: 'DUP-1');
    final idB = await newAsset(b, 'Laptop B', code: 'DUP-1');
    await b.receive(await a.outgoing());
    final all = await b.db.select(b.db.assets).get();
    expect(all.map((e) => e.assetCode).toSet(), {'DUP-1', 'DUP-1-2'});
    expect((await b.assets.get(idB))!.code, 'DUP-1'); // milik lokal tidak berubah
    expect((await b.db.select(b.db.syncConflicts).get()).single.kind, 'duplicate_code');
  });

  test('paket jahat: nama kolom/tabel tidak dikenal dan path lampiran tidak aman diabaikan', () async {
    final id = await newAsset(a, 'Laptop');
    await b.receive(await a.outgoing());
    final evil = RemoteChange(
      entity: 'assets',
      entityId: id,
      op: 'update',
      payload: {
        'fields': {
          'name; DROP TABLE assets; --': {'o': null, 'n': 'x'},
          'id': {'o': null, 'n': 'hijack'},
        },
      },
      hlc: '0000000009999-0000-device-a',
      deviceId: 'device-a',
      createdAt: 9999,
    );
    final unknownEntity = RemoteChange(
      entity: 'sqlite_master',
      entityId: 'x',
      op: 'insert',
      payload: {'row': {}},
      hlc: '0000000009999-0001-device-a',
      deviceId: 'device-a',
      createdAt: 9999,
    );
    final badPath = RemoteChange(
      entity: 'attachments',
      entityId: 'att-1',
      op: 'insert',
      payload: {
        'row': {'id': 'att-1', 'assetId': id, 'relPath': '../../etc/passwd', 'kind': 'photo', 'bytes': 1,
          'createdAt': 1, 'updatedAt': 1, 'deviceId': 'device-a'},
      },
      hlc: '0000000009999-0002-device-a',
      deviceId: 'device-a',
      createdAt: 9999,
    );
    final report = await b.receive([evil, unknownEntity, badPath]);
    expect(report.skipped, greaterThanOrEqualTo(2));
    expect((await b.assets.get(id))!.draft.name, 'Laptop'); // tidak berubah
    expect(await b.db.select(b.db.attachments).get(), isEmpty);
    expect(await b.db.select(b.db.assets).get(), hasLength(1)); // tabel masih utuh
  });
}
