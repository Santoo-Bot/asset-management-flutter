import 'dart:async';

import 'package:archive/archive_io.dart';

/// `ZipFileEncoder.close()` bertipe void di sebagian versi `archive` dan Future di versi lain.
/// Fungsi ini menunggu keduanya.
Future<void> closeZip(ZipFileEncoder encoder) async {
  final Object? result = (encoder as dynamic).close();
  if (result is Future) await result;
}
