import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import '../storage/data_location.dart';
import 'db_policy.dart';
import 'schema_sql.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Categories,
    Locations,
    People,
    Assets,
    AssetMovements,
    Maintenance,
    Attachments,
    AuditSessions,
    AuditItems,
    ChangeLog,
    AppMeta,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor, {this.policy = const DbPolicy(journalMode: 'WAL', synchronous: 'NORMAL', checkpointOnClose: true)});

  /// Database di file, dibuka di isolate latar belakang (UI tidak tersendat).
  factory AppDatabase.open(DataLocation location) {
    final policy = DbPolicy.forDrive(location.driveKind);
    final executor = NativeDatabase.createInBackground(
      location.dbFile,
      setup: (raw) {
        for (final pragma in policy.openPragmas) {
          raw.execute(pragma);
        }
      },
    );
    return AppDatabase(executor, policy: policy);
  }

  /// Untuk pengujian: database di memori.
  factory AppDatabase.memory() => AppDatabase(
        NativeDatabase.memory(setup: (raw) => raw.execute('PRAGMA foreign_keys = ON')),
      );

  final DbPolicy policy;

  /// Naik satu setiap perubahan skema; tambahkan langkah di [migration] dan uji drift.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          for (final sql in schemaV1ExtraSql) {
            await customStatement(sql);
          }
          final now = DateTime.now().millisecondsSinceEpoch;
          await batch((b) {
            b.insertAll(appMeta, [
              AppMetaCompanion.insert(key: 'schema_version', value: '$schemaVersion'),
              AppMetaCompanion.insert(key: 'device_id', value: const Uuid().v7()),
              AppMetaCompanion.insert(key: 'created_with_version', value: '0.1.0'),
              AppMetaCompanion.insert(key: 'created_at', value: '$now'),
            ]);
          });
        },
        // Salin assets.db ke backup/pre-migrate-<versi>.db SEBELUM database dibuka
        // (dilakukan oleh pemanggil, lihat BackupService di fase 1), lalu tambah langkah di sini:
        // onUpgrade: stepByStep(from1To2: (m, schema) async { ... }),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<String> deviceId() async {
    final row = await (select(appMeta)..where((t) => t.key.equals('device_id'))).getSingle();
    return row.value;
  }

  /// Dipanggil saat aplikasi ditutup.
  Future<void> closeSafely() async {
    if (policy.checkpointOnClose) {
      await customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    }
    await close();
  }

  /// Pencarian awalan FTS5; hanya aset aktif, maksimal [limit] baris.
  /// Input pengguna dibersihkan agar tidak menjadi sintaks FTS.
  Future<List<AssetRow>> searchAssets(String text, {int limit = 100}) {
    final tokens = text
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r'[^\p{L}\p{N}_-]', unicode: true), ''))
        .where((t) => t.isNotEmpty)
        .map((t) => '"$t"*')
        .join(' ');
    if (tokens.isEmpty) return Future.value(const []);
    return customSelect(
      'SELECT a.* FROM asset_fts f JOIN assets a ON a.rowid = f.rowid '
      'WHERE asset_fts MATCH ? AND a.deleted_at IS NULL ORDER BY rank LIMIT ?',
      variables: [Variable<String>(tokens), Variable<int>(limit)],
      readsFrom: {assets},
    ).map((r) => assets.map(r.data)).get();
  }
}
