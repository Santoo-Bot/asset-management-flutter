import 'dart:io';

/// Mode penyimpanan yang dipilih saat startup.
enum StorageMode {
  /// Folder `data/` di samping `.exe` (Windows portable).
  portable,

  /// `%APPDATA%\AssetApp\data` (cadangan bila folder portable tidak bisa ditulis).
  appData,

  /// Direktori internal aplikasi di Android.
  androidInternal,

  /// Ditentukan lewat argumen `--data-dir`.
  custom,
}

/// Jenis drive tempat data berada; menentukan PRAGMA SQLite.
enum DriveKind { internal, removable, network, unknown }

/// Hasil resolusi lokasi data. Dibuat sekali saat startup, dipakai sepanjang sesi.
class DataLocation {
  const DataLocation({
    required this.dir,
    required this.mode,
    required this.driveKind,
    this.fellBackFromPortable = false,
  });

  final Directory dir;
  final StorageMode mode;
  final DriveKind driveKind;

  /// True bila portable gagal ditulis lalu jatuh ke AppData (tampilkan banner).
  final bool fellBackFromPortable;

  File get dbFile => File('${dir.path}${Platform.pathSeparator}assets.db');
  Directory get mediaDir => Directory('${dir.path}${Platform.pathSeparator}media');
  Directory get thumbsDir => Directory('${dir.path}${Platform.pathSeparator}thumbs');
  Directory get backupDir => Directory('${dir.path}${Platform.pathSeparator}backup');
  Directory get logsDir => Directory('${dir.path}${Platform.pathSeparator}logs');
  File get settingsFile => File('${dir.path}${Platform.pathSeparator}settings.json');
  File get lockFile => File('${dir.path}${Platform.pathSeparator}app.lock');
}

/// Dilempar saat database diletakkan di drive jaringan (kunci file SQLite tidak andal).
class NetworkDriveNotSupported implements Exception {
  NetworkDriveNotSupported(this.path);
  final String path;
  @override
  String toString() => 'Database tidak didukung di drive jaringan: $path';
}

/// Dilempar bila dua lokasi sama-sama berisi database dan pengguna harus memilih.
class DataLocationConflict implements Exception {
  DataLocationConflict({required this.portableDir, required this.appDataDir});
  final Directory portableDir;
  final Directory appDataDir;
  @override
  String toString() =>
      'Database ada di AppData tetapi folder data portable kosong. Pilih salah satu atau salin.';
}
