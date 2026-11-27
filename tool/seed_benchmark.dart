// Benchmark skema dan query terhadap target spesifikasi bagian 6.
//
//   dart run tool/seed_benchmark.dart --count 10000
//   dart run tool/seed_benchmark.dart --count 50000
//
// Membuat database sementara di tool/out/, mengisi data seed, lalu mengukur tiap query
// (median dari 21 kali jalan) dan mencetak LULUS/GAGAL terhadap target. Tidak ada angka karangan:
// hasil bergantung pada mesin yang menjalankan. Jalankan juga di Android kelas menengah
// lewat layar debug (Fase 1) untuk angka perangkat sebenarnya.
//
// Windows: butuh sqlite3.dll (dengan FTS5) di folder kerja atau PATH. Unduh dari sqlite.org.
import 'dart:io';
import 'dart:math';

import 'package:asset_app/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

class Result {
  Result(this.name, this.medianMs, this.targetMs);
  final String name;
  final double medianMs;
  final double targetMs;
  bool get pass => medianMs < targetMs;
}

Future<double> measure(Future<void> Function() body, {int runs = 21}) async {
  await body(); // pemanasan
  final times = <double>[];
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    await body();
    sw.stop();
    times.add(sw.elapsedMicroseconds / 1000);
  }
  times.sort();
  return times[times.length ~/ 2];
}

Future<void> main(List<String> args) async {
  final countIdx = args.indexOf('--count');
  final count = countIdx >= 0 ? int.parse(args[countIdx + 1]) : 10000;
  final out = Directory('tool/out')..createSync(recursive: true);
  final file = File('${out.path}/bench_$count.db');
  for (final ext in ['', '-wal', '-shm']) {
    final f = File('${file.path}$ext');
    if (f.existsSync()) f.deleteSync();
  }

  final db = AppDatabase(NativeDatabase(file, setup: (raw) {
    raw.execute('PRAGMA foreign_keys = ON');
    raw.execute('PRAGMA journal_mode = WAL');
    raw.execute('PRAGMA synchronous = NORMAL');
  }));
  final rnd = Random(42);
  final now = DateTime.now().millisecondsSinceEpoch;
  const device = 'bench';

  // ---- Seed master ----
  final categoryIds = <String>[];
  final locationIds = <String>[];
  await db.transaction(() async {
    for (var i = 0; i < 8; i++) {
      final c = await db.into(db.categories).insertReturning(CategoriesCompanion.insert(
          name: 'Kategori $i', codePrefix: 'K$i', createdAt: now, updatedAt: now, deviceId: device));
      categoryIds.add(c.id);
    }
    for (var i = 0; i < 40; i++) {
      final l = await db.into(db.locations).insertReturning(
          LocationsCompanion.insert(name: 'Lokasi $i', createdAt: now, updatedAt: now, deviceId: device));
      locationIds.add(l.id);
    }
  });

  // ---- Seed aset: satu transaksi, batch 500 ----
  const brands = ['Lenovo', 'Dell', 'HP', 'Epson', 'Canon', 'Samsung', 'Asus', 'Logitech'];
  const nouns = ['Laptop', 'Monitor', 'Printer', 'Meja', 'Kursi', 'Proyektor', 'Router', 'Scanner', 'Lemari', 'AC'];
  const statuses = ['in_use', 'available', 'repair', 'written_off'];
  final seedSw = Stopwatch()..start();
  await db.transaction(() async {
    for (var start = 0; start < count; start += 500) {
      final end = min(start + 500, count);
      await db.batch((b) {
        b.insertAll(db.assets, [
          for (var i = start; i < end; i++)
            AssetsCompanion.insert(
              assetCode: 'AST-${i.toString().padLeft(6, '0')}',
              name: '${nouns[rnd.nextInt(nouns.length)]} ${brands[rnd.nextInt(brands.length)]} $i',
              categoryId: categoryIds[rnd.nextInt(categoryIds.length)],
              locationId: Value(locationIds[rnd.nextInt(locationIds.length)]),
              status: Value(statuses[rnd.nextInt(statuses.length)]),
              serialNumber: Value('SN${rnd.nextInt(1 << 30)}'),
              brand: Value(brands[rnd.nextInt(brands.length)]),
              createdAt: now,
              updatedAt: now,
              deviceId: device,
            ),
        ]);
      });
    }
  });
  seedSw.stop();

  // ---- Pengukuran ----
  final results = <Result>[
    Result('Impor/seed $count baris (target 10.000 < 30 dtk)', seedSw.elapsedMilliseconds.toDouble(), 30000),
  ];

  results.add(Result(
    'Daftar aset: halaman pertama 50 baris',
    await measure(() => db
        .customSelect('SELECT * FROM assets WHERE deleted_at IS NULL ORDER BY name, id LIMIT 50')
        .get()),
    300,
  ));

  final mid = await db
      .customSelect('SELECT name, id FROM assets WHERE deleted_at IS NULL ORDER BY name, id LIMIT 1 OFFSET ?',
          variables: [Variable<int>(count ~/ 2)])
      .getSingle();
  results.add(Result(
    'Daftar aset: halaman tengah (keyset)',
    await measure(() => db.customSelect(
          'SELECT * FROM assets WHERE deleted_at IS NULL AND (name, id) > (?, ?) ORDER BY name, id LIMIT 50',
          variables: [Variable<String>(mid.read<String>('name')), Variable<String>(mid.read<String>('id'))],
        ).get()),
    300,
  ));

  results.add(Result('Pencarian FTS5 awalan "lapt"', await measure(() => db.searchAssets('lapt')), 100));
  results.add(Result('Pencarian FTS5 dua kata "laptop dell"', await measure(() => db.searchAssets('laptop dell')), 100));

  results.add(Result(
    'Filter kategori + lokasi + status',
    await measure(() => db.customSelect(
          'SELECT * FROM assets WHERE deleted_at IS NULL AND category_id = ? AND location_id = ? AND status = ? LIMIT 50',
          variables: [
            Variable<String>(categoryIds.first),
            Variable<String>(locationIds.first),
            const Variable<String>('in_use'),
          ],
        ).get()),
    150,
  ));

  results.add(Result(
    'Dashboard: COUNT GROUP BY status',
    await measure(() => db
        .customSelect('SELECT status, COUNT(*) AS n FROM assets WHERE deleted_at IS NULL GROUP BY status')
        .get()),
    100,
  ));

  // ---- Laporan ----
  stdout.writeln('\nBenchmark: $count aset · ${Platform.operatingSystem}');
  stdout.writeln('-' * 88);
  for (final r in results) {
    final status = r.pass ? 'LULUS' : 'GAGAL';
    stdout.writeln('${r.name.padRight(58)} ${r.medianMs.toStringAsFixed(1).padLeft(9)} ms  '
        '(< ${r.targetMs.toStringAsFixed(0)})  $status');
  }
  final failed = results.where((r) => !r.pass).length;
  stdout.writeln('-' * 88);
  stdout.writeln(failed == 0 ? 'Semua target tercapai.' : '$failed target belum tercapai: putuskan ulang sebelum Fase 1.');

  await db.close();
  exit(failed == 0 ? 0 : 1);
}
