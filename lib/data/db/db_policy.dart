import '../storage/data_location.dart';

/// PRAGMA SQLite per jenis drive (spesifikasi bagian 5).
class DbPolicy {
  const DbPolicy({required this.journalMode, required this.synchronous, required this.checkpointOnClose});

  final String journalMode;
  final String synchronous;

  /// Jalankan `wal_checkpoint(TRUNCATE)` saat aplikasi ditutup.
  final bool checkpointOnClose;

  /// Drive removable: DELETE + FULL (aman saat flashdisk dicabut).
  /// Internal/Android: WAL + NORMAL.
  factory DbPolicy.forDrive(DriveKind kind) {
    switch (kind) {
      case DriveKind.removable:
      case DriveKind.unknown:
        return const DbPolicy(journalMode: 'DELETE', synchronous: 'FULL', checkpointOnClose: false);
      case DriveKind.internal:
        return const DbPolicy(journalMode: 'WAL', synchronous: 'NORMAL', checkpointOnClose: true);
      case DriveKind.network:
        throw NetworkDriveNotSupported('network');
    }
  }

  /// Urutan PRAGMA yang dijalankan tepat setelah database dibuka.
  List<String> get openPragmas => [
        'PRAGMA foreign_keys = ON',
        'PRAGMA busy_timeout = 5000',
        'PRAGMA journal_mode = $journalMode',
        'PRAGMA synchronous = $synchronous',
      ];
}
