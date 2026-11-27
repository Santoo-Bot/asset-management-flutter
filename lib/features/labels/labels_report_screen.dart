import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../app/providers.dart';
import '../../ui/common.dart';
import '../assets/domain/asset_models.dart';
import 'pdf_service.dart';

/// Cetak label QR massal dan laporan daftar aset (PDF) menurut filter.
class LabelsReportScreen extends ConsumerStatefulWidget {
  const LabelsReportScreen({super.key});
  @override
  ConsumerState<LabelsReportScreen> createState() => _LabelsReportScreenState();
}

class _LabelsReportScreenState extends ConsumerState<LabelsReportScreen> {
  String? _categoryId;
  String? _locationId;
  AssetStatus? _status;
  bool _busy = false;

  AssetFilter get _filter => AssetFilter(categoryId: _categoryId, locationId: _locationId, status: _status);

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final locs = ref.watch(locationsProvider).valueOrNull ?? const [];
    final pdf = ref.watch(pdfServiceProvider);
    final company = ref.watch(settingsProvider).companyName;

    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/more')), title: const Text('Label & laporan')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy) const LinearProgressIndicator(),
        Text('Filter', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        PickerField<String>(
          label: 'Kategori',
          value: _categoryId,
          options: [for (final c in cats) (value: c.id!, label: c.name)],
          onChanged: (v) => setState(() => _categoryId = v),
        ),
        const SizedBox(height: 12),
        PickerField<String>(
          label: 'Lokasi',
          value: _locationId,
          options: [for (final l in locs) (value: l.id!, label: l.name)],
          onChanged: (v) => setState(() => _locationId = v),
        ),
        const SizedBox(height: 12),
        PickerField<AssetStatus>(
          label: 'Status',
          value: _status,
          options: [for (final s in AssetStatus.values) (value: s, label: s.label)],
          onChanged: (v) => setState(() => _status = v),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: const Icon(Icons.qr_code_2),
          label: const Text('Cetak label QR (maks 500, A4 3×8)'),
          onPressed: _busy
              ? null
              : () => _run(() async {
                    final labels = await pdf.labelsFor(_filter);
                    if (labels.isEmpty) {
                      if (mounted) showMessage(context, 'Tidak ada aset yang cocok');
                      return;
                    }
                    final bytes = await pdf.buildLabels(labels, companyName: company);
                    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'label-aset');
                  }),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Laporan daftar aset + nilai buku (PDF)'),
          onPressed: _busy
              ? null
              : () => _run(() async {
                    final r = await pdf.buildRegisterReport(ReportOptions(filter: _filter), companyName: company);
                    if (r.truncated && mounted) showMessage(context, 'Laporan dipotong pada 5000 baris; persempit filter.');
                    await Printing.layoutPdf(onLayout: (_) async => r.pdf, name: 'laporan-aset');
                  }),
        ),
      ]),
    );
  }
}
