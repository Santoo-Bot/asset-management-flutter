import 'dart:io';

import 'package:path/path.dart' as p;

import '../../platform/drive_type.dart';
import 'data_location.dart';

/// Masukan lingkungan; diinjeksi supaya resolver bisa diuji di semua OS.
class ResolverEnv {
  const ResolverEnv({
    required this.args,
    required this.exeDir,
    required this.appDataDir,
    required this.androidInternalDir,
    required this.isWindows,
  });

  /// Argumen baris perintah (mencari `--data-dir <path>`).
  final List<String> args;

  /// Folder tempat `.exe` berada (Windows).
  final Directory? exeDir;

  /// Folder `%APPDATA%\AssetApp\data` (Windows).
  final Directory? appDataDir;

  /// Hasil `getApplicationSupportDirectory()` (Android).
  final Directory? androidInternalDir;

  final bool isWindows;

  /// Membangun lingkungan Windows nyata. Tanpa Registry: hanya variabel lingkungan APPDATA.
  factory ResolverEnv.windows(List<String> args) {
    final appData = Platform.environment['APPDATA'];
    return ResolverEnv(
      args: args,
      exeDir: File(Platform.resolvedExecutable).parent,
      appDataDir: appData == null ? null : Directory(p.join(appData, 'AssetApp', 'data')),
      androidInternalDir: null,
      isWindows: true,
    );
  }

  factory ResolverEnv.android(List<String> args, Directory supportDir) => ResolverEnv(
        args: args,
        exeDir: null,
        appDataDir: null,
        androidInternalDir: Directory(p.join(supportDir.path, 'data')),
        isWindows: false,
      );
}

/// Menentukan lokasi data sekali saat startup (spesifikasi bagian 5).
///
/// Urutan: `--data-dir` → `data/` di samping .exe (uji tulis) → AppData.
class DataLocationResolver {
  DataLocationResolver(this.env, {DriveTypeDetector? detector})
      : _detector = detector ?? createDriveTypeDetector();

  final ResolverEnv env;
  final DriveTypeDetector _detector;

  /// [forcedChoice] diisi setelah pengguna menjawab [DataLocationConflict].
  Future<DataLocation> resolve({StorageMode? forcedChoice}) async {
    // Android: selalu direktori internal aplikasi.
    if (!env.isWindows) {
      final dir = env.androidInternalDir!;
      await dir.create(recursive: true);
      return DataLocation(dir: dir, mode: StorageMode.androidInternal, driveKind: DriveKind.internal);
    }

    // 1. --data-dir menang atas semua aturan lain.
    final custom = _argValue(env.args, '--data-dir');
    if (custom != null) {
      final dir = Directory(p.absolute(custom));
      if (!await _isWritable(dir)) {
        throw FileSystemException('Folder --data-dir tidak bisa ditulis', dir.path);
      }
      return _build(dir, StorageMode.custom);
    }

    final portable = Directory(p.join(env.exeDir!.path, 'data'));
    final appData = env.appDataDir;

    if (forcedChoice == StorageMode.appData && appData != null) {
      await appData.create(recursive: true);
      return _build(appData, StorageMode.appData);
    }

    // 4. AppData sudah berisi database, portable kosong → tanya pengguna.
    if (forcedChoice == null && appData != null) {
      final appDataHasDb = await File(p.join(appData.path, 'assets.db')).exists();
      final portableHasDb = await File(p.join(portable.path, 'assets.db')).exists();
      if (appDataHasDb && !portableHasDb && await _isWritable(portable)) {
        throw DataLocationConflict(portableDir: portable, appDataDir: appData);
      }
    }

    // 2. Uji tulis folder portable.
    if (await _isWritable(portable)) {
      return _build(portable, StorageMode.portable);
    }

    // 3. Jatuh ke AppData.
    if (appData == null) {
      throw FileSystemException('Folder data portable tidak bisa ditulis dan APPDATA tidak tersedia', portable.path);
    }
    await appData.create(recursive: true);
    return _build(appData, StorageMode.appData, fellBack: true);
  }

  DataLocation _build(Directory dir, StorageMode mode, {bool fellBack = false}) {
    final kind = _detector.detect(p.absolute(dir.path));
    if (kind == DriveKind.network) throw NetworkDriveNotSupported(dir.path);
    return DataLocation(dir: dir, mode: mode, driveKind: kind, fellBackFromPortable: fellBack);
  }

  /// Uji tulis: buat folder bila perlu, lalu buat dan hapus file sementara.
  Future<bool> _isWritable(Directory dir) async {
    try {
      await dir.create(recursive: true);
      final probe = File(p.join(dir.path, '.write_test_${pid}_${DateTime.now().microsecondsSinceEpoch}'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static String? _argValue(List<String> args, String name) {
    for (var i = 0; i < args.length; i++) {
      if (args[i] == name && i + 1 < args.length) return args[i + 1];
      if (args[i].startsWith('$name=')) return args[i].substring(name.length + 1);
    }
    return null;
  }
}
