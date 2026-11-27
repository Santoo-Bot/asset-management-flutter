import 'dart:io';

import 'data_location.dart';

/// Dilempar bila instance lain sudah memegang `app.lock`.
class AnotherInstanceRunning implements Exception {
  @override
  String toString() => 'Aplikasi sudah berjalan dan memakai data ini.';
}

/// Kunci eksklusif pada `data/app.lock` agar dua proses tidak menulis ke database yang sama.
/// Kunci dilepas otomatis oleh OS bila proses mati.
class SingleInstanceLock {
  SingleInstanceLock._(this._raf);
  final RandomAccessFile _raf;

  static Future<SingleInstanceLock> acquire(DataLocation location) async {
    final file = location.lockFile;
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.append);
    try {
      // FileLock.exclusive tidak menunggu: langsung gagal bila sudah dikunci.
      await raf.lock(FileLock.exclusive);
    } on FileSystemException {
      await raf.close();
      throw AnotherInstanceRunning();
    }
    return SingleInstanceLock._(raf);
  }

  Future<void> release() async {
    try {
      await _raf.unlock();
    } finally {
      await _raf.close();
    }
  }
}
