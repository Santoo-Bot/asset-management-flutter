import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/formatters.dart';
import '../maintenance/maintenance_repository.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(statusCountsProvider);
    final reminders = ref.watch(remindersProvider);
    final total = counts.valueOrNull?.fold<int>(0, (a, e) => a + e.count) ?? 0;
    final totalPrice = counts.valueOrNull?.fold<int>(0, (a, e) => a + e.totalPrice) ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Beranda'), automaticallyImplyLeading: false),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: _Stat(label: 'Total aset', value: '$total')),
          const SizedBox(width: 12),
          Expanded(child: _Stat(label: 'Total harga perolehan', value: formatRupiah(totalPrice))),
        ]),
        const SizedBox(height: 16),
        Text('Per status', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        counts.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (list) => list.isEmpty
              ? const Text('Belum ada aset.')
              : Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in list) Chip(label: Text('${c.status.label}: ${c.count}')),
                ]),
        ),
        const SizedBox(height: 16),
        Text('Pengingat', style: Theme.of(context).textTheme.titleMedium),
        reminders.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (list) => list.isEmpty
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Tidak ada jadwal perawatan atau garansi yang mendekati.'))
              : Column(children: [
                  for (final r in list)
                    ListTile(
                      dense: true,
                      leading: Icon(r.kind == ReminderKind.maintenance ? Icons.build : Icons.verified_user,
                          color: r.overdue ? Colors.red : null),
                      title: Text('${r.assetName} (${r.assetCode})'),
                      subtitle: Text('${r.kind == ReminderKind.maintenance ? 'Perawatan' : 'Garansi habis'} ${formatDate(r.dueDate)}'
                          '${r.overdue ? ' · terlambat' : ''}'),
                      onTap: () => context.go('/assets/${r.assetId}'),
                    ),
                ]),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ]),
        ),
      );
}
