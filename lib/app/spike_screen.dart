import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/storage/data_location.dart';
import '../data/storage/single_instance_lock.dart';

/// Layar sementara Fase 0: menampilkan hasil resolver agar mudah diuji di flashdisk,
/// `C:\Program Files` (read-only), dan peluncuran ganda. Diganti UI nyata di Fase 1.
class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key, required this.location, required this.db, required this.lock});

  final DataLocation location;
  final AppDatabase db;
  final SingleInstanceLock lock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aset',
      home: Scaffold(
        appBar: AppBar(title: const Text('Aset · Fase 0')),
        body: Column(
          children: [
            if (location.fellBackFromPortable)
              const MaterialBanner(
                content: Text('Mode non-portabel: data di AppData'),
                actions: [SizedBox.shrink()],
              ),
            ListTile(title: const Text('Mode'), subtitle: Text(location.mode.name)),
            ListTile(title: const Text('Jenis drive'), subtitle: Text(location.driveKind.name)),
            ListTile(title: const Text('Folder data'), subtitle: Text(location.dir.path)),
            ListTile(title: const Text('Journal'), subtitle: Text('${db.policy.journalMode} / ${db.policy.synchronous}')),
          ],
        ),
      ),
    );
  }
}
