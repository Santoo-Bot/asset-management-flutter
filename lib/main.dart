import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/settings_store.dart';
import 'data/db/app_database.dart';
import 'data/db/change_recorder.dart';
import 'data/storage/data_location.dart';
import 'data/storage/data_location_resolver.dart';
import 'data/storage/single_instance_lock.dart';
import 'features/backup/backup_service.dart';

/// Bootstrap: lokasi data → kunci satu instance → database → HLC → pengaturan.
/// Kesalahan startup ditampilkan sebagai pesan, bukan crash.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final env = Platform.isWindows
        ? ResolverEnv.windows(args)
        : ResolverEnv.android(args, await getApplicationSupportDirectory());
    final location = await DataLocationResolver(env).resolve();
    final lock = await SingleInstanceLock.acquire(location);
    for (final d in [location.mediaDir, location.thumbsDir, location.backupDir, location.logsDir]) {
      await d.create(recursive: true);
    }
    final db = AppDatabase.open(location);
    final deviceId = await db.deviceId(); // memicu pembuatan/migrasi skema
    final hlc = await loadHlc(db, deviceId);
    final settings = await SettingsStore.load(location.settingsFile);

    // Cadangan otomatis paling banyak sekali per 24 jam; kegagalan tidak boleh menghalangi aplikasi.
    final dayMs = const Duration(hours: 24).inMilliseconds;
    if (DateTime.now().millisecondsSinceEpoch - settings.lastAutoBackupMs > dayMs) {
      try {
        await BackupService(db, location).autoBackup();
        await settings.set('lastAutoBackupMs', DateTime.now().millisecondsSinceEpoch);
      } on Object {
        // dicatat di layar Pengaturan pada rilis berikutnya
      }
    }

    runApp(ProviderScope(
      overrides: [
        dataLocationProvider.overrideWithValue(location),
        databaseProvider.overrideWithValue(db),
        deviceIdProvider.overrideWithValue(deviceId),
        hlcProvider.overrideWithValue(hlc),
        settingsProvider.overrideWithValue(settings),
      ],
      child: AssetApp(onExit: () async {
        await db.closeSafely();
        await lock.release();
      }),
    ));
  } on AnotherInstanceRunning catch (e) {
    runApp(_ErrorApp(e.toString()));
  } on NetworkDriveNotSupported catch (e) {
    runApp(_ErrorApp('${e.toString()}\nPindahkan folder aplikasi ke drive lokal atau flashdisk.'));
  } on DataLocationConflict catch (e) {
    runApp(_ErrorApp(e.toString()));
  } on Object catch (e) {
    runApp(_ErrorApp('Gagal memulai: $e'));
  }
}

class _ErrorApp extends StatelessWidget {
  const _ErrorApp(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(message)))),
      );
}
