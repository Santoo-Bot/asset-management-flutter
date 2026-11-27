import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/formatters.dart';
import '../../ui/common.dart';
import '../scan/scan_screen.dart';
import 'audit_repository.dart';

class OpnameListScreen extends ConsumerWidget {
  const OpnameListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(auditRepositoryProvider);
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/more')), title: const Text('Stock opname')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Sesi baru'),
        onPressed: () async {
          final c = TextEditingController(text: 'Opname ${formatDate(DateTime.now().millisecondsSinceEpoch)}');
          final name = await showDialog<String>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('Sesi opname baru'),
              content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Nama sesi')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
                FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Mulai')),
              ],
            ),
          );
          if (name == null) return;
          try {
            final id = await repo.start(name);
            if (context.mounted) context.go('/more/opname/$id');
          } on Object catch (e) {
            if (context.mounted) showError(context, e);
          }
        },
      ),
      body: StreamBuilder<List<AuditSessionItem>>(
        stream: repo.watchSessions(),
        builder: (context, snap) {
          final list = snap.data ?? const <AuditSessionItem>[];
          if (list.isEmpty) return const Center(child: Text('Belum ada sesi opname'));
          return ListView(children: [
            for (final s in list)
              ListTile(
                title: Text(s.name),
                subtitle: Text('${formatDateTime(s.startedAt)} · ${s.isOpen ? 'berjalan' : 'selesai'}'),
                trailing: Icon(s.isOpen ? Icons.play_circle_outline : Icons.check_circle_outline),
                onTap: () => context.go('/more/opname/${s.id}'),
              ),
          ]);
        },
      ),
    );
  }
}

class OpnameSessionScreen extends ConsumerStatefulWidget {
  const OpnameSessionScreen({super.key, required this.sessionId});
  final String sessionId;
  @override
  ConsumerState<OpnameSessionScreen> createState() => _OpnameSessionScreenState();
}

class _OpnameSessionScreenState extends ConsumerState<OpnameSessionScreen> {
  String _feedback = 'Siap memindai';
  Color? _feedbackColor;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(auditRepositoryProvider);
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/more/opname')), title: const Text('Sesi opname')),
      body: StreamBuilder<List<AuditSessionItem>>(
        stream: repo.watchSessions(),
        builder: (context, sessionSnap) {
          final session = sessionSnap.data?.where((s) => s.id == widget.sessionId).firstOrNull;
          final open = session?.isOpen ?? false;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(session?.name ?? '', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            StreamBuilder<AuditSummary>(
              stream: repo.watchSummary(widget.sessionId),
              builder: (context, snap) {
                final s = snap.data;
                if (s == null) return const SizedBox();
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  Chip(label: Text('Ditemukan ${s.found}/${s.expected}')),
                  if (!open) Chip(label: Text('Tidak ditemukan ${s.missing}')),
                  Chip(label: Text('Di luar daftar ${s.unregistered}')),
                ]);
              },
            ),
            const SizedBox(height: 12),
            if (open) ...[
              ScanInput(onCode: (code) async {
                try {
                  final r = await repo.scan(widget.sessionId, code);
                  if (!mounted) return;
                  setState(() {
                    switch (r.outcome) {
                      case ScanOutcome.found:
                        _feedback = '✔ ${r.assetName} (${r.code})';
                        _feedbackColor = Colors.green;
                      case ScanOutcome.duplicate:
                        _feedback = 'Sudah dipindai: ${r.assetName ?? r.code}';
                        _feedbackColor = Colors.orange;
                      case ScanOutcome.unregistered:
                        _feedback = 'Tidak terdaftar: ${r.code}';
                        _feedbackColor = Colors.red;
                    }
                  });
                } on Object catch (e) {
                  if (mounted) showError(context, e);
                }
              }),
              const SizedBox(height: 12),
              Text(_feedback, style: TextStyle(fontSize: 16, color: _feedbackColor)),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.flag),
                label: const Text('Selesaikan sesi'),
                onPressed: () async {
                  if (!await confirm(context, 'Selesaikan sesi?', 'Aset yang belum dipindai ditandai "tidak ditemukan". Sesi tidak bisa dilanjutkan.', action: 'Selesaikan')) return;
                  try {
                    await repo.finish(widget.sessionId);
                  } on Object catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
            ] else ...[
              _ResultList(sessionId: widget.sessionId, result: 'missing', title: 'Tidak ditemukan'),
              _ResultList(sessionId: widget.sessionId, result: 'unregistered', title: 'Di luar daftar'),
              _ResultList(sessionId: widget.sessionId, result: 'found', title: 'Ditemukan'),
            ],
          ]);
        },
      ),
    );
  }
}

class _ResultList extends ConsumerWidget {
  const _ResultList({required this.sessionId, required this.result, required this.title});
  final String sessionId;
  final String result;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(auditRepositoryProvider).items(sessionId, result),
      builder: (context, snap) {
        final items = snap.data ?? const [];
        return ExpansionTile(
          title: Text('$title (${items.length}${items.length >= 500 ? '+' : ''})'),
          children: [for (final i in items) ListTile(dense: true, title: Text(i.assetName ?? i.code), subtitle: Text(i.code))],
        );
      },
    );
  }
}
