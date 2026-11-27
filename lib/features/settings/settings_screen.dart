import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/formatters.dart';
import '../../ui/common.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String title, String route) =>
        ListTile(leading: Icon(icon), title: Text(title), trailing: const Icon(Icons.chevron_right), onTap: () => context.go(route));
    return Scaffold(
      appBar: AppBar(title: const Text('Lainnya'), automaticallyImplyLeading: false),
      body: ListView(children: [
        const _Header('Data master'),
        item(Icons.category, 'Kategori', '/more/categories'),
        item(Icons.place, 'Lokasi', '/more/locations'),
        item(Icons.person, 'Penanggung jawab', '/more/people'),
        const _Header('Operasional'),
        item(Icons.fact_check, 'Stock opname', '/more/opname'),
        item(Icons.print, 'Label QR & laporan PDF', '/more/labels'),
        const _Header('Data'),
        item(Icons.import_export, 'Impor / ekspor', '/more/import-export'),
        item(Icons.backup, 'Backup & restore', '/more/backup'),
        item(Icons.sync_alt, 'Sinkronisasi antar perangkat', '/more/sync'),
        const _Header('Aplikasi'),
        item(Icons.settings, 'Pengaturan', '/more/settings'),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _company;
  late final TextEditingController _days;
  int? _mediaBytes;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _company = TextEditingController(text: s.companyName);
    _days = TextEditingController(text: '${s.reminderDays}');
    _refreshMedia();
  }

  Future<void> _refreshMedia() async {
    final n = await ref.read(photoServiceProvider).mediaBytes();
    if (mounted) setState(() => _mediaBytes = n);
  }

  @override
  void dispose() {
    _company.dispose();
    _days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final loc = ref.watch(dataLocationProvider);
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/more')), title: const Text('Pengaturan')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _company,
          decoration: const InputDecoration(labelText: 'Nama perusahaan (di label & laporan)', border: OutlineInputBorder()),
          onSubmitted: (v) => settings.set('companyName', v.trim()),
          onTapOutside: (_) => settings.set('companyName', _company.text.trim()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _days,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Pengingat perawatan: hari sebelum jadwal', border: OutlineInputBorder()),
          onSubmitted: (v) async {
            final n = int.tryParse(v.trim());
            if (n != null && n >= 0 && n <= 365) {
              await settings.set('reminderDays', n);
              ref.invalidate(remindersProvider);
            }
          },
        ),
        const SizedBox(height: 12),
        PickerField<String>(
          label: 'Tema (berlaku setelah aplikasi dibuka ulang)',
          value: settings.themeMode,
          allowEmpty: false,
          options: const [(value: 'system', label: 'Ikuti sistem'), (value: 'light', label: 'Terang'), (value: 'dark', label: 'Gelap')],
          onChanged: (v) => settings.set('themeMode', v ?? 'system'),
        ),
        const Divider(height: 32),
        Text('Penyimpanan', style: Theme.of(context).textTheme.titleMedium),
        infoRow('Mode', loc.mode.name),
        infoRow('Jenis drive', loc.driveKind.name),
        infoRow('Folder data', loc.dir.path),
        infoRow('Ukuran foto', _mediaBytes == null ? '…' : formatBytes(_mediaBytes!)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.cleaning_services),
          label: const Text('Bersihkan file foto yatim'),
          onPressed: () async {
            final n = await ref.read(photoServiceProvider).cleanOrphans();
            await _refreshMedia();
            if (context.mounted) showMessage(context, '$n file dihapus');
          },
        ),
      ]),
    );
  }
}
