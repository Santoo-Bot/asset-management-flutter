import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/spike_screen.dart';
import 'data/db/app_database.dart';
import 'data/storage/data_location.dart';
import 'data/storage/data_location_resolver.dart';
import 'data/storage/single_instance_lock.dart';

/// Bootstrap Fase 0: tentukan lokasi data → kunci satu instance → buka database.
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
    await db.deviceId(); // memicu pembuatan skema
    runApp(ProviderScope(child: SpikeApp(location: location, db: db, lock: lock)));
  } on AnotherInstanceRunning catch (e) {
    runApp(_ErrorApp(e.toString()));
  } on NetworkDriveNotSupported catch (e) {
    runApp(_ErrorApp('${e.toString()}\nPindahkan folder aplikasi ke drive lokal atau flashdisk.'));
  } on DataLocationConflict catch (e) {
    // Fase 1: dialog pilihan (gunakan AppData / gunakan portable / salin).
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
