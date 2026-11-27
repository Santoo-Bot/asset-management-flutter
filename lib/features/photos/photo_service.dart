import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../data/db/app_database.dart';
import '../../data/db/change_recorder.dart';
import '../../data/storage/data_location.dart';

class PhotoItem {
  const PhotoItem({required this.id, required this.relPath, required this.thumbRelPath, required this.bytes});
  final String id;
  final String relPath;
  final String? thumbRelPath;
  final int bytes;
}

/// Hasil pemrosesan gambar di isolate: foto utama + thumbnail JPEG.
class ProcessedImage {
  const ProcessedImage(this.full, this.thumb);
  final Uint8List full;
  final Uint8List thumb;
}

/// Berjalan di isolate (lewat `compute`). Maks 1280 px sisi panjang, JPEG q80; thumbnail 256 px.
ProcessedImage processImage(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) throw const FormatException('File bukan gambar yang didukung');
  final oriented = img.bakeOrientation(decoded);
  img.Image fit(int maxSide) {
    final longSide = oriented.width >= oriented.height ? oriented.width : oriented.height;
    if (longSide <= maxSide) return oriented;
    return oriented.width >= oriented.height
        ? img.copyResize(oriented, width: maxSide)
        : img.copyResize(oriented, height: maxSide);
  }

  return ProcessedImage(
    Uint8List.fromList(img.encodeJpg(fit(1280), quality: 80)),
    Uint8List.fromList(img.encodeJpg(fit(256), quality: 75)),
  );
}

class PhotoService {
  PhotoService(this._db, this._recorder, this._location, this._deviceId);
  final AppDatabase _db;
  final ChangeRecorder _recorder;
  final DataLocation _location;
  final String _deviceId;

  File fileFor(String relPath) => File(p.join(_location.dir.path, relPath));

  Stream<List<PhotoItem>> watch(String assetId) {
    final q = _db.select(_db.attachments)
      ..where((t) => t.assetId.equals(assetId) & t.deletedAt.isNull() & t.kind.equals('photo'))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return q.watch().map((rows) => [
          for (final r in rows) PhotoItem(id: r.id, relPath: r.relPath, thumbRelPath: r.thumbRelPath, bytes: r.bytes),
        ]);
  }

  Future<void> add(String assetId, Uint8List original) async {
    final processed = await compute(processImage, original);
    final name = const Uuid().v7();
    final rel = p.posix.join('media', assetId, '$name.jpg');
    final thumbRel = p.posix.join('thumbs', '$name.jpg');
    final full = fileFor(rel);
    final thumb = fileFor(thumbRel);
    await full.parent.create(recursive: true);
    await thumb.parent.create(recursive: true);
    await full.writeAsBytes(processed.full, flush: true);
    await thumb.writeAsBytes(processed.thumb, flush: true);
    try {
      await _db.transaction(() async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final row = await _db.into(_db.attachments).insertReturning(AttachmentsCompanion.insert(
              assetId: assetId,
              relPath: rel,
              thumbRelPath: Value(thumbRel),
              sha256: Value(sha256.convert(processed.full).toString()),
              bytes: Value(processed.full.length),
              createdAt: now,
              updatedAt: now,
              deviceId: _deviceId,
            ));
        await _recorder.record('attachments', row.id, 'insert', {'row': row.toJson()});
      });
    } on Object {
      // Jangan tinggalkan file yatim bila transaksi gagal.
      if (await full.exists()) await full.delete();
      if (await thumb.exists()) await thumb.delete();
      rethrow;
    }
  }

  /// Soft delete; file dibersihkan oleh [cleanOrphans].
  Future<void> remove(String attachmentId) async {
    await _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await (_db.update(_db.attachments)..where((t) => t.id.equals(attachmentId)))
          .write(AttachmentsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      await _recorder.record('attachments', attachmentId, 'delete', {});
    });
  }

  /// Ukuran folder media + thumbs, untuk ditampilkan di Pengaturan.
  Future<int> mediaBytes() async {
    var total = 0;
    for (final dir in [_location.mediaDir, _location.thumbsDir]) {
      if (!await dir.exists()) continue;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    }
    return total;
  }

  /// Hapus file di media/ dan thumbs/ yang tidak dirujuk baris aktif mana pun. Mengembalikan jumlah file.
  Future<int> cleanOrphans() async {
    final rows = await (_db.select(_db.attachments)..where((t) => t.deletedAt.isNull())).get();
    final keep = <String>{
      for (final r in rows) p.normalize(p.join(_location.dir.path, r.relPath)),
      for (final r in rows)
        if (r.thumbRelPath != null) p.normalize(p.join(_location.dir.path, r.thumbRelPath!)),
    };
    var removed = 0;
    for (final dir in [_location.mediaDir, _location.thumbsDir]) {
      if (!await dir.exists()) continue;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File && !keep.contains(p.normalize(e.path))) {
          await e.delete();
          removed++;
        }
      }
    }
    return removed;
  }
}
