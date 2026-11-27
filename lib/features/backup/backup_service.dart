import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

import '../../core/zip_compat.dart';
import '../../data/db/app_database.dart';
import '../../data/storage/data_location.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _stamp([DateTime? t]) {
  final d = t ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}${two(d.second)}';
}

/// Backup otomatis (VACUUM INTO, bergilir 7), backup manual (zip + manifest + sha256), dan restore.
class BackupService {
  BackupService(this._db, this._location, {this.appVersion = '0.1.0'});
  final AppDatabase _db;
  final DataLocation _location;
  final String appVersion;

  static const keepAuto = 7;

  /// Salinan database yang konsisten tanpa menutup aplikasi.
  Future<void> _snapshot(File target) async {
    await target.parent.create(recursive: true);
    if (await target.exists()) await target.delete();
    await _db.customStatement('VACUUM INTO ?', [target.path]);
  }

  /// Cadangan otomatis ke `data/backup/`, menyisakan [keepAuto] terakhir.
  Future<File> autoBackup() async {
    final file = File(p.join(_location.backupDir.path, 'auto-${_stamp()}.db'));
    await _snapshot(file);
    final autos = (await _location.backupDir.list().toList())
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('auto-') && f.path.endsWith('.db'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path)); // terbaru dulu (nama memuat stempel waktu)
    for (final old in autos.skip(keepAuto)) {
      await old.delete();
    }
    return file;
  }

  /// Backup manual: zip berisi assets.db, media/, thumbs/, dan manifest.json.
  Future<File> exportZip(Directory targetDir) async {
    await targetDir.create(recursive: true);
    final tmp = Directory(p.join(_location.backupDir.path, '.tmp-${_stamp()}'));
    await tmp.create(recursive: true);
    try {
      final dbCopy = File(p.join(tmp.path, 'assets.db'));
      await _snapshot(dbCopy);
      final digest = (await sha256.bind(dbCopy.openRead()).first).toString();
      final version = await _db.customSelect('PRAGMA user_version').getSingle();
      final manifest = File(p.join(tmp.path, 'manifest.json'));
      await manifest.writeAsString(jsonEncode({
        'format': 1,
        'app_version': appVersion,
        'schema_version': version.read<int>('user_version'),
        'created_at': DateTime.now().toIso8601String(),
        'db_sha256': digest,
      }));

      final out = File(p.join(targetDir.path, 'AssetApp-backup-${_stamp()}.zip'));
      final enc = ZipFileEncoder()..create(out.path);
      await enc.addFile(manifest, 'manifest.json');
      await enc.addFile(dbCopy, 'assets.db');
      for (final dir in [_location.mediaDir, _location.thumbsDir]) {
        if (!await dir.exists()) continue;
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            final rel = p.posix.joinAll(p.split(p.relative(e.path, from: _location.dir.path)));
            await enc.addFile(e, rel);
          }
        }
      }
      await closeZip(enc);
      return out;
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }

  /// Memeriksa zip tanpa mengubah data: manifest, sha256, skema, dan integrity_check.
  /// Mengembalikan folder sementara berisi isi zip yang sudah terverifikasi.
  Future<Directory> verifyZip(File zip, {required int currentSchemaVersion}) async {
    final staging = Directory(p.join(_location.backupDir.path, '.restore-${_stamp()}'));
    await staging.create(recursive: true);
    try {
      final input = InputFileStream(zip.path);
      final archive = ZipDecoder().decodeBuffer(input);
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final name = f.name.replaceAll('\\', '/');
        // Cegah zip-slip: tolak path absolut atau yang keluar dari folder staging.
        final dest = p.normalize(p.join(staging.path, name));
        if (name.startsWith('/') || name.contains('..') || !p.isWithin(staging.path, dest)) {
          throw BackupException('Zip berisi path tidak aman: $name');
        }
        await Directory(p.dirname(dest)).create(recursive: true);
        final out = OutputFileStream(dest);
        f.writeContent(out);
        out.close();
      }
      input.close();

      final manifestFile = File(p.join(staging.path, 'manifest.json'));
      final dbFile = File(p.join(staging.path, 'assets.db'));
      if (!await manifestFile.exists() || !await dbFile.exists()) {
        throw BackupException('Bukan file backup Aset (manifest atau database tidak ada)');
      }
      final manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final digest = (await sha256.bind(dbFile.openRead()).first).toString();
      if (manifest['db_sha256'] != digest) throw BackupException('Backup rusak: sha256 database tidak cocok');
      final schema = manifest['schema_version'] as int? ?? 0;
      if (schema > currentSchemaVersion) {
        throw BackupException('Backup dibuat oleh versi aplikasi yang lebih baru (skema $schema). Perbarui aplikasi dulu.');
      }
      final raw = sql.sqlite3.open(dbFile.path, mode: sql.OpenMode.readOnly);
      try {
        final result = raw.select('PRAGMA integrity_check');
        if (result.isEmpty || result.first.values.first != 'ok') {
          throw BackupException('Database dalam backup gagal integrity_check');
        }
      } finally {
        raw.dispose();
      }
      return staging;
    } on Object {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  /// Restore: cadangkan data lama, tutup database, timpa file, lalu aplikasi HARUS dimulai ulang.
  /// Panggil [verifyZip] lebih dulu dan berikan hasilnya sebagai [staging].
  Future<void> applyRestore(Directory staging) async {
    final safety = File(p.join(_location.backupDir.path, 'pre-restore-${_stamp()}.db'));
    await _snapshot(safety);
    await _db.closeSafely();
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('${_location.dbFile.path}$suffix');
      if (await f.exists()) await f.delete();
    }
    await File(p.join(staging.path, 'assets.db')).copy(_location.dbFile.path);
    for (final name in ['media', 'thumbs']) {
      final src = Directory(p.join(staging.path, name));
      if (!await src.exists()) continue;
      await for (final e in src.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final dest = File(p.join(_location.dir.path, name, p.relative(e.path, from: src.path)));
        await dest.parent.create(recursive: true);
        await e.copy(dest.path);
      }
    }
    await staging.delete(recursive: true);
  }
}
