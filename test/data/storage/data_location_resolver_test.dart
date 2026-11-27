import 'dart:io';

import 'package:asset_app/data/storage/data_location.dart';
import 'package:asset_app/data/storage/data_location_resolver.dart';
import 'package:asset_app/data/storage/single_instance_lock.dart';
import 'package:asset_app/platform/drive_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeDetector implements DriveTypeDetector {
  _FakeDetector(this.kind);
  final DriveKind kind;
  @override
  DriveKind detect(String absolutePath) => kind;
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('asset_app_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ResolverEnv env({List<String> args = const [], Directory? exe, Directory? appData}) => ResolverEnv(
        args: args,
        exeDir: exe ?? Directory(p.join(tmp.path, 'app')),
        appDataDir: appData ?? Directory(p.join(tmp.path, 'appdata', 'AssetApp', 'data')),
        androidInternalDir: null,
        isWindows: true,
      );

  DataLocationResolver resolver(ResolverEnv e, [DriveKind kind = DriveKind.internal]) =>
      DataLocationResolver(e, detector: _FakeDetector(kind));

  test('mode portable: folder data di samping exe dibuat', () async {
    Directory(p.join(tmp.path, 'app')).createSync();
    final loc = await resolver(env()).resolve();
    expect(loc.mode, StorageMode.portable);
    expect(loc.dir.path, p.join(tmp.path, 'app', 'data'));
    expect(loc.fellBackFromPortable, isFalse);
  });

  test('--data-dir menang atas aturan lain', () async {
    final custom = p.join(tmp.path, 'custom');
    final loc = await resolver(env(args: ['--data-dir', custom])).resolve();
    expect(loc.mode, StorageMode.custom);
    expect(loc.dir.path, custom);
  });

  test('jatuh ke AppData bila portable tidak bisa ditulis', () async {
    // `data` berupa FILE sehingga folder tidak bisa dibuat.
    Directory(p.join(tmp.path, 'app')).createSync();
    File(p.join(tmp.path, 'app', 'data')).writeAsStringSync('x');
    final loc = await resolver(env()).resolve();
    expect(loc.mode, StorageMode.appData);
    expect(loc.fellBackFromPortable, isTrue);
  });

  test('konflik: AppData berisi db, portable kosong', () async {
    Directory(p.join(tmp.path, 'app')).createSync();
    final appData = Directory(p.join(tmp.path, 'appdata', 'AssetApp', 'data'))..createSync(recursive: true);
    File(p.join(appData.path, 'assets.db')).writeAsStringSync('db');
    expect(resolver(env()).resolve(), throwsA(isA<DataLocationConflict>()));
    // Setelah pengguna memilih AppData:
    final loc = await resolver(env()).resolve(forcedChoice: StorageMode.appData);
    expect(loc.mode, StorageMode.appData);
  });

  test('drive jaringan ditolak', () async {
    Directory(p.join(tmp.path, 'app')).createSync();
    expect(
      resolver(env(), DriveKind.network).resolve(),
      throwsA(isA<NetworkDriveNotSupported>()),
    );
  });

  // Kunci file Dart memakai fcntl di Linux/macOS (per proses), jadi hanya Windows yang menolak
  // kunci kedua dalam proses yang sama. Uji ini dijalankan di Windows.
  test('peluncuran kedua gagal memegang app.lock', skip: !Platform.isWindows, () async {
    Directory(p.join(tmp.path, 'app')).createSync();
    final loc = await resolver(env()).resolve();
    final first = await SingleInstanceLock.acquire(loc);
    await expectLater(SingleInstanceLock.acquire(loc), throwsA(isA<AnotherInstanceRunning>()));
    await first.release();
    final again = await SingleInstanceLock.acquire(loc);
    await again.release();
  });
}
