import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../core/hlc.dart';
import '../../core/zip_compat.dart';
import '../../data/db/app_database.dart';
import '../../data/storage/data_location.dart';
import 'change_applier.dart';

class PackException implements Exception {
  PackException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ExportedPack {
  const ExportedPack(this.file, this.changes, this.mediaFiles, this.lastSeq);
  final File file;
  final int changes;
  final int mediaFiles;
  final int lastSeq;
}

class PendingExport {
  const PendingExport(this.changes);
  final int changes;
}

class SyncService {
  SyncService(this._db, this._location, this._hlc, this._deviceId);

  final AppDatabase _db;
  final DataLocation _location;
  final Hlc _hlc;
  final String _deviceId;

  static const packFormat = 1;

  /// Jumlah perubahan lokal yang belum pernah diekspor.
  Stream<int> watchPendingCount() {
    return _db
        .customSelect('SELECT COUNT(*) AS n FROM change_log WHERE exported_at IS NULL AND device_id = ?',
            variables: [Variable<String>(_deviceId)], readsFrom: {_db.changeLog})
        .watchSingle()
        .map((r) => r.read<int>('n'));
  }

  /// Ekspor `*.assetpack` (zip: manifest.json, changes.jsonl, media/…).
  /// Hanya perubahan milik perangkat ini yang belum diekspor; setelah file berhasil ditulis,
  /// baris ditandai `exported_at`.
  Future<ExportedPack?> exportPack(Directory targetDir) async {
    final rows = await (_db.select(_db.changeLog)
          ..where((t) => t.exportedAt.isNull() & t.deviceId.equals(_deviceId))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
        .get();
    if (rows.isEmpty) return null;

    await targetDir.create(recursive: true);
    final tmp = Directory(p.join(_location.backupDir.path, '.pack-${DateTime.now().microsecondsSinceEpoch}'));
    await tmp.create(recursive: true);
    try {
      final lines = StringBuffer();
      final media = <String>{};
      for (final r in rows) {
        final payload = jsonDecode(r.payload) as Map<String, dynamic>;
        lines.writeln(jsonEncode(RemoteChange(
          entity: r.entity,
          entityId: r.entityId,
          op: r.op,
          payload: payload,
          hlc: r.hlc,
          deviceId: r.deviceId,
          createdAt: r.createdAt,
        ).toJson()));
        if (r.entity == 'attachments' && r.op == 'insert') {
          final row = payload['row'];
          if (row is Map) {
            final rel = row['relPath'];
            final thumb = row['thumbRelPath'];
            if (rel is String) media.add(rel);
            if (thumb is String) media.add(thumb);
          }
        }
      }
      final changes = File(p.join(tmp.path, 'changes.jsonl'));
      await changes.writeAsString(lines.toString(), flush: true);
      final manifest = File(p.join(tmp.path, 'manifest.json'));
      final version = await _db.customSelect('PRAGMA user_version').getSingle();
      await manifest.writeAsString(jsonEncode({
        'format': packFormat,
        'device_id': _deviceId,
        'schema_version': version.read<int>('user_version'),
        'created_at': DateTime.now().toIso8601String(),
        'count': rows.length,
        'first_seq': rows.first.seq,
        'last_seq': rows.last.seq,
      }));

      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
      final out = File(p.join(targetDir.path, 'asset-$stamp.assetpack'));
      final enc = ZipFileEncoder()..create(out.path);
      await enc.addFile(manifest, 'manifest.json');
      await enc.addFile(changes, 'changes.jsonl');
      var mediaCount = 0;
      for (final rel in media) {
        final f = File(p.join(_location.dir.path, rel));
        if (await f.exists()) {
          await enc.addFile(f, p.posix.joinAll(p.posix.split(rel.replaceAll('\\', '/'))));
          mediaCount++;
        }
      }
      await closeZip(enc);

      final now = DateTime.now().millisecondsSinceEpoch;
      await (_db.update(_db.changeLog)..where((t) => t.seq.isBetweenValues(rows.first.seq, rows.last.seq) & t.deviceId.equals(_deviceId)))
          .write(ChangeLogCompanion(exportedAt: Value(now)));
      return ExportedPack(out, rows.length, mediaCount, rows.last.seq);
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }

  /// Impor `*.assetpack`: validasi manifest, terapkan perubahan dalam satu transaksi, lalu salin media.
  Future<ApplyReport> importPack(File pack, {required int currentSchemaVersion}) async {
    final staging = Directory(p.join(_location.backupDir.path, '.import-${DateTime.now().microsecondsSinceEpoch}'));
    await staging.create(recursive: true);
    try {
      final input = InputFileStream(pack.path);
      final archive = ZipDecoder().decodeBuffer(input);
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final name = f.name.replaceAll('\\', '/');
        final dest = p.normalize(p.join(staging.path, name));
        if (name.startsWith('/') || name.contains('..') || !p.isWithin(staging.path, dest)) {
          throw PackException('Paket berisi path tidak aman: $name');
        }
        await Directory(p.dirname(dest)).create(recursive: true);
        final out = OutputFileStream(dest);
        f.writeContent(out);
        out.close();
      }
      input.close();

      final manifestFile = File(p.join(staging.path, 'manifest.json'));
      final changesFile = File(p.join(staging.path, 'changes.jsonl'));
      if (!await manifestFile.exists() || !await changesFile.exists()) {
        throw PackException('Bukan paket perubahan Aset (manifest/changes tidak ada)');
      }
      final manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      if (manifest['format'] != packFormat) throw PackException('Format paket ${manifest['format']} tidak didukung');
      final schema = manifest['schema_version'] as int? ?? 0;
      if (schema > currentSchemaVersion) {
        throw PackException('Paket dibuat oleh versi aplikasi lebih baru (skema $schema). Perbarui aplikasi dulu.');
      }
      if (manifest['device_id'] == _deviceId) throw PackException('Paket ini berasal dari perangkat ini sendiri');

      final changes = <RemoteChange>[];
      var lineNo = 0;
      for (final line in await changesFile.readAsLines()) {
        lineNo++;
        if (line.trim().isEmpty) continue;
        try {
          changes.add(RemoteChange.fromJson(jsonDecode(line) as Map<String, dynamic>));
        } on Object {
          throw PackException('Baris $lineNo di changes.jsonl rusak');
        }
      }

      final report = await _db.transaction(() => ChangeApplier(_db, _hlc).applyAll(changes));

      // Media baru: jangan menimpa file yang sudah ada.
      final mediaRoot = staging;
      for (final name in ['media', 'thumbs']) {
        final src = Directory(p.join(mediaRoot.path, name));
        if (!await src.exists()) continue;
        await for (final e in src.list(recursive: true, followLinks: false)) {
          if (e is! File) continue;
          final dest = File(p.join(_location.dir.path, name, p.relative(e.path, from: src.path)));
          if (await dest.exists()) continue;
          await dest.parent.create(recursive: true);
          await e.copy(dest.path);
        }
      }
      return report;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  // ---- layar Konflik ----
  Stream<List<SyncConflictRow>> watchConflicts() {
    final q = _db.select(_db.syncConflicts)
      ..where((t) => t.resolvedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return q.watch();
  }

  Future<void> markResolved(String conflictId) async {
    await (_db.update(_db.syncConflicts)..where((t) => t.id.equals(conflictId)))
        .write(SyncConflictsCompanion(resolvedAt: Value(DateTime.now().millisecondsSinceEpoch)));
  }
}
