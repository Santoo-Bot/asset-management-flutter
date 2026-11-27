import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../ui/common.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  String? _restoredNotice;

  Future<void> _run(Future<String> Function() job) async {
    setState(() => _busy = true);
    try {
      final msg = await job();
      if (mounted) showMessage(context, msg);
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(backupServiceProvider);
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/more')), title: const Text('Backup & restore')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy) const LinearProgressIndicator(),
        if (_restoredNotice != null)
          Card(
            color: Colors.green.shade100,
            child: Padding(padding: const EdgeInsets.all(12), child: Text(_restoredNotice!, style: const TextStyle(color: Colors.black87))),
          ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Cadangan otomatis'),
          subtitle: const Text('Dibuat sekali per hari saat aplikasi dibuka, 7 terakhir disimpan di folder data/backup.'),
          trailing: TextButton(
            onPressed: _busy ? null : () => _run(() async => 'Dibuat: ${(await service.autoBackup()).path}'),
            child: const Text('Buat sekarang'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.archive),
          title: const Text('Backup manual (zip)'),
          subtitle: const Text('Database + foto + manifest. Simpan ke folder luar (flashdisk, cloud pribadi, dll).'),
          trailing: TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Pilih folder tujuan');
                    if (dir == null) return;
                    await _run(() async => 'Backup: ${(await service.exportZip(Directory(dir))).path}');
                  },
            child: const Text('Backup'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('Restore dari zip'),
          subtitle: const Text('Memeriksa versi skema, sha256, dan integrity_check. Data lama dicadangkan dulu. Aplikasi perlu dimulai ulang.'),
          trailing: TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
                    final path = r?.files.single.path;
                    if (path == null) return;
                    await _run(() async {
                      final version = await db.customSelect('PRAGMA user_version').getSingle();
                      final staging = await service.verifyZip(File(path), currentSchemaVersion: version.read<int>('user_version'));
                      if (!mounted) return 'Dibatalkan';
                      final ok = await confirm(context, 'Timpa data saat ini?',
                          'Backup valid. Data sekarang akan dicadangkan lalu diganti isi backup, dan aplikasi harus ditutup lalu dibuka lagi.',
                          action: 'Restore');
                      if (!ok) {
                        await staging.delete(recursive: true);
                        return 'Restore dibatalkan';
                      }
                      await service.applyRestore(staging);
                      setState(() => _restoredNotice = 'Restore selesai. Tutup aplikasi lalu buka lagi untuk memakai data hasil restore.');
                      return 'Restore selesai';
                    });
                  },
            child: const Text('Restore'),
          ),
        ),
      ]),
    );
  }
}
