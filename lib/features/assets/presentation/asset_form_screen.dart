import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/formatters.dart';
import '../../../ui/common.dart';
import '../domain/asset_models.dart';

/// Tambah atau ubah aset. `assetId == null` → aset baru (kode otomatis bila dikosongkan).
class AssetFormScreen extends ConsumerStatefulWidget {
  const AssetFormScreen({super.key, this.assetId});
  final String? assetId;

  @override
  ConsumerState<AssetFormScreen> createState() => _AssetFormScreenState();
}

class _AssetFormScreenState extends ConsumerState<AssetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _serial = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _price = TextEditingController();
  final _vendor = TextEditingController();
  final _notes = TextEditingController();
  String? _categoryId;
  String? _locationId;
  String? _personId;
  AssetStatus _status = AssetStatus.inUse;
  AssetCondition _condition = AssetCondition.good;
  int? _purchaseDate;
  int? _warrantyUntil;
  int? _disposedAt;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.assetId;
    if (id != null) {
      final a = await ref.read(assetRepositoryProvider).get(id);
      if (a != null) {
        final d = a.draft;
        _code.text = a.code;
        _name.text = d.name;
        _serial.text = d.serialNumber ?? '';
        _brand.text = d.brand ?? '';
        _model.text = d.model ?? '';
        _price.text = d.purchasePrice?.toString() ?? '';
        _vendor.text = d.vendor ?? '';
        _notes.text = d.notes ?? '';
        _categoryId = d.categoryId;
        _locationId = d.locationId;
        _personId = d.assignedTo;
        _status = d.status;
        _condition = d.condition;
        _purchaseDate = d.purchaseDate;
        _warrantyUntil = d.warrantyUntil;
        _disposedAt = d.disposedAt;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _serial, _brand, _model, _price, _vendor, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      showMessage(context, 'Kategori wajib dipilih');
      return;
    }
    setState(() => _saving = true);
    try {
      final priceText = _price.text.trim();
      final price = priceText.isEmpty ? null : parseRupiah(priceText);
      // Write off menghentikan penyusutan; isi tanggalnya otomatis bila belum ada.
      final disposedAt = _status == AssetStatus.writtenOff ? (_disposedAt ?? DateTime.now().millisecondsSinceEpoch) : null;
      final draft = AssetDraft(
        assetCode: _code.text,
        name: _name.text,
        categoryId: _categoryId ?? '',
        locationId: _locationId,
        status: _status,
        condition: _condition,
        serialNumber: _serial.text,
        brand: _brand.text,
        model: _model.text,
        purchaseDate: _purchaseDate,
        purchasePrice: price,
        vendor: _vendor.text,
        assignedTo: _personId,
        warrantyUntil: _warrantyUntil,
        disposedAt: disposedAt,
        notes: _notes.text,
      );
      final repo = ref.read(assetRepositoryProvider);
      final id = widget.assetId;
      late final String savedId;
      if (id == null) {
        savedId = await repo.create(draft);
      } else {
        await repo.update(id, draft);
        savedId = id;
      }
      if (mounted) context.go('/assets/$savedId');
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final locs = ref.watch(locationsProvider).valueOrNull ?? const [];
    final people = ref.watch(peopleProvider).valueOrNull ?? const [];
    final editing = widget.assetId != null;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(editing ? '/assets/${widget.assetId}' : '/assets')),
        title: Text(editing ? 'Ubah aset' : 'Aset baru'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('Simpan')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (cats.isEmpty)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      title: const Text('Belum ada kategori'),
                      subtitle: const Text('Buat kategori dulu di Lainnya → Kategori.'),
                      onTap: () => context.go('/more/categories'),
                    ),
                  ),
                TextFormField(
                  controller: _code,
                  decoration: InputDecoration(
                    labelText: 'Kode aset',
                    helperText: editing ? null : 'Kosongkan untuk dibuat otomatis dari awalan kategori',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nama aset *', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                PickerField<String>(
                  label: 'Kategori *',
                  value: _categoryId,
                  allowEmpty: false,
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
                PickerField<String>(
                  label: 'Penanggung jawab',
                  value: _personId,
                  options: [for (final p in people) (value: p.id!, label: p.name)],
                  onChanged: (v) => setState(() => _personId = v),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: PickerField<AssetStatus>(
                      label: 'Status',
                      value: _status,
                      allowEmpty: false,
                      options: [for (final s in AssetStatus.values) (value: s, label: s.label)],
                      onChanged: (v) => setState(() => _status = v ?? _status),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PickerField<AssetCondition>(
                      label: 'Kondisi',
                      value: _condition,
                      allowEmpty: false,
                      options: [for (final s in AssetCondition.values) (value: s, label: s.label)],
                      onChanged: (v) => setState(() => _condition = v ?? _condition),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Merek', border: OutlineInputBorder()))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Model', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 12),
                TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'Nomor serial', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DateField(label: 'Tanggal perolehan', value: _purchaseDate, onChanged: (v) => setState(() => _purchaseDate = v)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Harga perolehan (Rp)', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty || parseRupiah(v) != null) ? null : 'Harga tidak valid',
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _vendor, decoration: const InputDecoration(labelText: 'Vendor', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DateField(label: 'Garansi sampai', value: _warrantyUntil, onChanged: (v) => setState(() => _warrantyUntil = v)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Catatan', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 24),
              ]),
            ),
    );
  }
}
