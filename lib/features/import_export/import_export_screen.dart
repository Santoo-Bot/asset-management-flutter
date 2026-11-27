import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../ui/common.dart';
import 'import_plan.dart';

class ImportExportScreen extends ConsumerStatefulWidget {
  const ImportExportScreen({super.key});
  @override
  ConsumerState<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends ConsumerState<ImportExportScreen> {
  ImportPlan? _plan;
  String? _fileName;
  bool _busy = false;
  double? _progress;

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'xlsx'], withData: true);
      final f = r?.files.single;
      if (f == null || f.bytes == null) return;
      final plan = await ref.read(importExportServiceProvider).prepare(f.bytes!, p.extension(f.name));
      setState(() {
        _plan = plan;
        _fileName = f.name;
      });
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final plan = _plan!;
    if (!await confirm(context, 'Impor ${plan.valid.length} aset?',
        '${plan.errors.length} baris bermasalah akan dilewati. Kategori/lokasi/penanggung jawab yang belum ada dibuat otomatis.',
        action: 'Impor')) {
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final result = await ref.read(importExportServiceProvider).commit(plan, onProgress: (d, t) {
        if (mounted) setState(() => _progress = d / t);
      });
      if (!mounted) return;
      showMessage(context,
          'Berhasil mengimpor ${result.inserted} aset (+${result.createdCategories} kategori, +${result.createdLocations} lokasi, +${result.createdPeople} orang)');
      setState(() => _plan = null);
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _export() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Pilih folder tujuan ekspor');
    if (dir == null) return;
    setState(() => _busy = true);
    try {
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
      final file = File(p.join(dir, 'aset-$stamp.csv'));
      final n = await ref.read(importExportServiceProvider).exportCsv(file);
      if (mounted) showMessage(context, 'Mengekspor $n aset ke ${file.path}');
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/more')), title: const Text('Impor / ekspor')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy) LinearProgressIndicator(value: _progress),
        const SizedBox(height: 8),
        Text('Impor dari CSV atau Excel (.xlsx)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Baris pertama = header. Kolom wajib: Nama, Kategori. Kolom lain: Kode, Lokasi, Status, Kondisi, Serial, Merek, '
            'Model, Tanggal Perolehan (dd/MM/yyyy), Harga, Vendor, Penanggung Jawab, Garansi Sampai, Catatan. '
            'Kode kosong dibuat otomatis.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          FilledButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.upload_file), label: const Text('Pilih file')),
          OutlinedButton.icon(onPressed: _busy ? null : _export, icon: const Icon(Icons.download), label: const Text('Ekspor semua (CSV)')),
        ]),
        if (plan != null) ...[
          const Divider(height: 32),
          Text(_fileName ?? '', style: Theme.of(context).textTheme.titleSmall),
          if (plan.missingColumns.isNotEmpty)
            Text('Kolom wajib tidak ditemukan: ${plan.missingColumns.join(', ')}', style: const TextStyle(color: Colors.red))
          else ...[
            Text('${plan.valid.length} baris valid · ${plan.errors.length} bermasalah'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy || !plan.canCommit ? null : _commit, child: const Text('Impor baris valid')),
            if (plan.errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Baris bermasalah (menampilkan ${plan.errors.length > 200 ? 200 : plan.errors.length} dari ${plan.errors.length})',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final e in plan.errors.take(200)) Text(e.toString(), style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ],
        ],
      ]),
    );
  }
}
