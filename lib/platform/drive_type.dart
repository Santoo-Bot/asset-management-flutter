import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win;

import '../data/storage/data_location.dart';

/// Antarmuka agar resolver bisa diuji tanpa Windows.
abstract class DriveTypeDetector {
  DriveKind detect(String absolutePath);
}

/// Windows: pakai `GetDriveType`. Path UNC (`\\server\share`) dianggap jaringan.
class WindowsDriveTypeDetector implements DriveTypeDetector {
  static const _removable = 2;
  static const _fixed = 3;
  static const _remote = 4;

  @override
  DriveKind detect(String absolutePath) {
    if (absolutePath.startsWith(r'\\')) return DriveKind.network;
    final root = p.rootPrefix(absolutePath); // mis. "E:\"
    if (root.isEmpty) return DriveKind.unknown;
    final rootPtr = (root.endsWith(r'\') ? root : '$root\\').toNativeUtf16();
    try {
      final type = win.GetDriveType(rootPtr);
      switch (type) {
        case _removable:
          return DriveKind.removable;
        case _remote:
          return DriveKind.network;
        case _fixed:
          return DriveKind.internal;
        default:
          return DriveKind.unknown;
      }
    } finally {
      calloc.free(rootPtr);
    }
  }
}

/// Android dan platform lain: semua dianggap penyimpanan internal.
class InternalDriveTypeDetector implements DriveTypeDetector {
  @override
  DriveKind detect(String absolutePath) => DriveKind.internal;
}

DriveTypeDetector createDriveTypeDetector() =>
    Platform.isWindows ? WindowsDriveTypeDetector() : InternalDriveTypeDetector();
