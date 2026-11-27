import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/formatters.dart';
import '../../data/db/app_database.dart';
import '../../ui/common.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});
  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _busy = false;

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
    final sync = ref.watch(syncServiceProvider);
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/more')), title: const Text('Sinkronisasi')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy) const LinearProgressIndicator(),
        const Text('Tukar perubahan antar perangkat lewat file paket (.assetpack) — flashdisk, Bluetooth, atau aplikasi berbagi file. '
            'Tidak butuh internet atau server.'),
        const SizedBox(height: 16),
        StreamBuilder<int>(
          stream: sync.watchPendingCount(),
          builder: (context, snap) => ListTile(
            leading: const Icon(Icons.upload),
            title: Text('Ekspor perubahan (${snap.data ?? 0} belum diekspor)'),
            subtitle: const Text('Paket berisi perubahan sejak ekspor terakhir + foto baru.'),
            trailing: FilledButton(
              onPressed: _busy || (snap.data ?? 0) == 0
                  ? null
                  : () async {
                      final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Pilih folder tujuan paket');
                      if (dir == null) return;
                      await _run(() async {
                        final r = await sync.exportPack(Directory(dir));
                        return r == null ? 'Tidak ada perubahan' : 'Paket: ${r.file.path} (${r.changes} perubahan, ${r.mediaFiles} foto)';
                      });
                    },
              child: const Text('Ekspor'),
            ),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.download),
          title: const Text('Impor paket perubahan'),
          subtitle: const Text('Perubahan digabung per bidang; bentrok dicatat di layar Konflik.'),
          trailing: FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    final r = await FilePicker.platform.pickFiles(type: FileType.any);
                    final path = r?.files.single.path;
                    if (path == null) return;
                    await _run(() async {
                      final version = await db.customSelect('PRAGMA user_version').getSingle();
                      final report = await sync.importPack(File(path), currentSchemaVersion: version.read<int>('user_version'));
                      return 'Diterapkan ${report.applied}, duplikat ${report.duplicates}, dilewati ${report.skipped}, konflik ${report.conflicts}';
                    });
                  },
            child: const Text('Impor'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.warning_amber),
          title: const Text('Konflik'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/more/conflicts'),
        ),
      ]),
    );
  }
}

class ConflictsScreen extends ConsumerWidget {
  const ConflictsScreen({super.key});

  String _describe(SyncConflictRow c) {
    switch (c.kind) {
      case 'field':
        return 'Bidang "${c.field}" diubah di dua perangkat. Dipertahankan: ${c.localValue ?? '(kosong)'}; nilai dari perangkat lain: ${c.remoteValue ?? '(kosong)'}';
      case 'delete_vs_update':
        return 'Satu perangkat menghapus, perangkat lain mengubah. Ubahan dipertahankan dan data dipulihkan.';
      case 'duplicate_code':
        return 'Kode aset kembar "${c.localValue}" → diberi akhiran: ${c.remoteValue}';
      default:
        return c.kind;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncServiceProvider);
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/more/sync')), title: const Text('Konflik')),
      body: StreamBuilder<List<SyncConflictRow>>(
        stream: sync.watchConflicts(),
        builder: (context, snap) {
          final list = snap.data ?? const <SyncConflictRow>[];
          if (list.isEmpty) return const Center(child: Text('Tidak ada konflik untuk ditinjau'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = list[i];
              return ListTile(
                title: Text('${c.entity} · ${formatDateTime(c.createdAt)}'),
                subtitle: Text(_describe(c)),
                isThreeLine: true,
                trailing: TextButton(onPressed: () => sync.markResolved(c.id), child: const Text('Selesai')),
                onTap: c.entity == 'assets' ? () => context.go('/assets/${c.entityId}') : null,
              );
            },
          );
        },
      ),
    );
  }
}
