import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/formatters.dart';
import '../../../ui/common.dart';
import '../../labels/pdf_service.dart';
import '../../maintenance/maintenance_repository.dart';
import '../../movements/movement_repository.dart';
import '../../photos/photo_service.dart';
import '../domain/asset_models.dart';

class AssetDetailView extends ConsumerWidget {
  const AssetDetailView({super.key, required this.assetId, this.embedded = false});
  final String assetId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(assetDetailProvider(assetId));
    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (a) {
        if (a == null) {
          return Scaffold(
            appBar: AppBar(leading: embedded ? null : BackButton(onPressed: () => context.go('/assets'))),
            body: const Center(child: Text('Aset tidak ditemukan atau sudah dihapus')),
          );
        }
        return _Body(asset: a, embedded: embedded);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.asset, required this.embedded});
  final AssetDetail asset;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = asset.draft;
    final dep = asset.depreciation();

    Future<void> printLabel() async {
      final pdf = await ref.read(pdfServiceProvider).buildLabels(
        [LabelData(asset.code, d.name, asset.locationName)],
        companyName: ref.read(settingsProvider).companyName,
      );
      await Printing.layoutPdf(onLayout: (_) async => pdf, name: 'label-${asset.code}');
    }

    Future<void> delete() async {
      if (!await confirm(context, 'Hapus aset?', '"${d.name}" akan dihapus dari daftar (data riwayat tetap tersimpan).', action: 'Hapus')) return;
      await ref.read(assetRepositoryProvider).softDelete(asset.id);
      if (context.mounted) context.go('/assets');
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: embedded ? null : BackButton(onPressed: () => context.go('/assets')),
        title: Text(d.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Cetak label QR', icon: const Icon(Icons.qr_code_2), onPressed: printLabel),
          IconButton(tooltip: 'Ubah', icon: const Icon(Icons.edit), onPressed: () => context.go('/assets/${asset.id}/edit')),
          IconButton(tooltip: 'Hapus', icon: const Icon(Icons.delete_outline), onPressed: delete),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _PhotoStrip(assetId: asset.id),
        const SizedBox(height: 12),
        infoRow('Kode', asset.code),
        infoRow('Kategori', asset.categoryName),
        infoRow('Lokasi', asset.locationName),
        infoRow('Penanggung jawab', asset.personName),
        infoRow('Status', d.status.label),
        infoRow('Kondisi', d.condition.label),
        infoRow('Serial', d.serialNumber),
        infoRow('Merek / model', [d.brand, d.model].whereType<String>().join(' ')),
        infoRow('Tgl perolehan', formatDate(d.purchaseDate)),
        infoRow('Harga perolehan', formatRupiah(d.purchasePrice)),
        infoRow('Vendor', d.vendor),
        infoRow('Garansi sampai', formatDate(d.warrantyUntil)),
        infoRow('Catatan', d.notes),
        const SizedBox(height: 8),
        if (dep != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Penyusutan (garis lurus, ${asset.usefulLifeYears} th, residu ${asset.residualPercent.toStringAsFixed(0)}%)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                infoRow('Per tahun', formatRupiah(dep.annual)),
                infoRow('Akumulasi', '${formatRupiah(dep.accumulated)} (${dep.months} bln)'),
                infoRow('Nilai buku', formatRupiah(dep.bookValue)),
                if (dep.fullyDepreciated) const Text('Sudah habis disusutkan', style: TextStyle(color: Colors.orange)),
                if (d.disposedAt != null) Text('Penyusutan berhenti pada ${formatDate(d.disposedAt)} (write off)'),
              ]),
            ),
          )
        else
          const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Isi tanggal dan harga perolehan untuk melihat penyusutan.'))),
        const SizedBox(height: 8),
        _MovementSection(assetId: asset.id),
        _MaintenanceSection(assetId: asset.id),
      ]),
    );
  }
}

// ---------------- Foto ----------------

class _PhotoStrip extends ConsumerWidget {
  const _PhotoStrip({required this.assetId});
  final String assetId;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    try {
      Uint8List? bytes;
      if (Platform.isAndroid) {
        final source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (c) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Kamera'), onTap: () => Navigator.pop(c, ImageSource.camera)),
              ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galeri'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
            ]),
          ),
        );
        if (source == null) return;
        final x = await ImagePicker().pickImage(source: source);
        if (x == null) return;
        bytes = await x.readAsBytes();
      } else {
        final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
        bytes = r?.files.single.bytes;
      }
      if (bytes == null) return;
      await ref.read(photoServiceProvider).add(assetId, bytes);
    } on Object catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(photoServiceProvider);
    return SizedBox(
      height: 96,
      child: StreamBuilder<List<PhotoItem>>(
        stream: service.watch(assetId),
        builder: (context, snap) {
          final photos = snap.data ?? const <PhotoItem>[];
          return ListView(scrollDirection: Axis.horizontal, children: [
            for (final p in photos)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (c) => Dialog(child: InteractiveViewer(child: Image.file(service.fileFor(p.relPath)))),
                  ),
                  onLongPress: () async {
                    if (await confirm(context, 'Hapus foto?', 'Foto ini akan dihapus dari aset.', action: 'Hapus')) {
                      await service.remove(p.id);
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      service.fileFor(p.thumbRelPath ?? p.relPath),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      cacheWidth: 192,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 96, height: 96, child: Icon(Icons.broken_image)),
                    ),
                  ),
                ),
              ),
            InkWell(
              onTap: () => _add(context, ref),
              child: Container(
                width: 96,
                decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.add_a_photo),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ---------------- Mutasi ----------------

class _MovementSection extends ConsumerWidget {
  const _MovementSection({required this.assetId});
  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(movementRepositoryProvider);
    return StreamBuilder<List<MovementItem>>(
      stream: repo.watch(assetId),
      builder: (context, snap) {
        final items = snap.data ?? const <MovementItem>[];
        return ExpansionTile(
          title: Text('Mutasi (${items.length})'),
          trailing: TextButton.icon(
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Mutasi'),
            onPressed: () => showDialog<void>(context: context, builder: (_) => _MovementDialog(assetId: assetId)),
          ),
          children: [
            for (final m in items)
              ListTile(
                dense: true,
                title: Text('${m.type.label}${m.toLocation == null ? '' : ' → ${m.toLocation}'}'),
                subtitle: Text([
                  formatDateTime(m.at),
                  if (m.fromLocation != null) 'dari ${m.fromLocation}',
                  if (m.person != null) m.person!,
                  if (m.note != null) m.note!,
                ].join(' · ')),
              ),
          ],
        );
      },
    );
  }
}

class _MovementDialog extends ConsumerStatefulWidget {
  const _MovementDialog({required this.assetId});
  final String assetId;
  @override
  ConsumerState<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends ConsumerState<_MovementDialog> {
  MovementType _type = MovementType.transfer;
  String? _locationId;
  String? _personId;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locs = ref.watch(locationsProvider).valueOrNull ?? const [];
    final people = ref.watch(peopleProvider).valueOrNull ?? const [];
    return AlertDialog(
      title: const Text('Mutasi aset'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            PickerField<MovementType>(
              label: 'Jenis',
              value: _type,
              allowEmpty: false,
              options: [for (final t in MovementType.values) (value: t, label: t.label)],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            if (_type == MovementType.transfer || _type == MovementType.other)
              PickerField<String>(
                label: 'Lokasi tujuan',
                value: _locationId,
                options: [for (final l in locs) (value: l.id!, label: l.name)],
                onChanged: (v) => setState(() => _locationId = v),
              ),
            if (_type == MovementType.assign || _type == MovementType.other) ...[
              const SizedBox(height: 12),
              PickerField<String>(
                label: 'Penanggung jawab',
                value: _personId,
                options: [for (final p in people) (value: p.id!, label: p.name)],
                onChanged: (v) => setState(() => _personId = v),
              ),
            ],
            const SizedBox(height: 12),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Catatan', border: OutlineInputBorder())),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: () async {
            try {
              await ref.read(movementRepositoryProvider).record(
                    assetId: widget.assetId,
                    type: _type,
                    toLocationId: _locationId,
                    personId: _personId,
                    note: _note.text,
                  );
              if (context.mounted) Navigator.pop(context);
            } on Object catch (e) {
              if (context.mounted) showError(context, e);
            }
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

// ---------------- Perawatan ----------------

class _MaintenanceSection extends ConsumerWidget {
  const _MaintenanceSection({required this.assetId});
  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(maintenanceRepositoryProvider);
    return StreamBuilder<List<MaintenanceItem>>(
      stream: repo.watch(assetId),
      builder: (context, snap) {
        final items = snap.data ?? const <MaintenanceItem>[];
        return ExpansionTile(
          title: Text('Perawatan (${items.length})'),
          trailing: TextButton.icon(
            icon: const Icon(Icons.build),
            label: const Text('Tambah'),
            onPressed: () => showDialog<void>(context: context, builder: (_) => _MaintenanceDialog(assetId: assetId)),
          ),
          children: [
            for (final m in items)
              ListTile(
                dense: true,
                title: Text('${m.type.label} · ${formatDate(m.date)}'),
                subtitle: Text([
                  formatRupiah(m.cost),
                  if (m.nextDue != null) 'berikutnya ${formatDate(m.nextDue)}',
                  if (m.note != null) m.note!,
                ].join(' · ')),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () async {
                    if (await confirm(context, 'Hapus catatan perawatan?', 'Catatan ini akan dihapus.', action: 'Hapus')) {
                      await repo.delete(m.id);
                    }
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MaintenanceDialog extends ConsumerStatefulWidget {
  const _MaintenanceDialog({required this.assetId});
  final String assetId;
  @override
  ConsumerState<_MaintenanceDialog> createState() => _MaintenanceDialogState();
}

class _MaintenanceDialogState extends ConsumerState<_MaintenanceDialog> {
  MaintenanceType _type = MaintenanceType.preventive;
  int _date = DateTime.now().millisecondsSinceEpoch;
  int? _nextDue;
  final _cost = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _cost.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catatan perawatan'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            PickerField<MaintenanceType>(
              label: 'Jenis',
              value: _type,
              allowEmpty: false,
              options: [for (final t in MaintenanceType.values) (value: t, label: t.label)],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            DateField(label: 'Tanggal', value: _date, allowClear: false, onChanged: (v) => setState(() => _date = v ?? _date)),
            const SizedBox(height: 12),
            TextField(
              controller: _cost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Biaya (Rp)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DateField(label: 'Jadwal berikutnya', value: _nextDue, onChanged: (v) => setState(() => _nextDue = v)),
            const SizedBox(height: 12),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Catatan', border: OutlineInputBorder())),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: () async {
            try {
              final cost = _cost.text.trim().isEmpty ? 0 : parseRupiah(_cost.text);
              if (cost == null) throw ArgumentError('Biaya tidak valid');
              await ref.read(maintenanceRepositoryProvider).add(
                    assetId: widget.assetId,
                    type: _type,
                    date: _date,
                    cost: cost,
                    nextDue: _nextDue,
                    note: _note.text,
                  );
              if (context.mounted) Navigator.pop(context);
            } on Object catch (e) {
              if (context.mounted) showError(context, e);
            }
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
