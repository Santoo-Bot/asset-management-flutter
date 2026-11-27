import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../ui/common.dart';
import '../domain/master_models.dart';

/// Kerangka daftar master dengan tombol tambah, ketuk untuk ubah, dan hapus.
class _MasterList<T> extends StatelessWidget {
  const _MasterList({
    required this.title,
    required this.items,
    required this.tileBuilder,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });
  final String title;
  final AsyncValue<List<T>> items;
  final ListTile Function(T item) tileBuilder;
  final VoidCallback onAdd;
  final void Function(T item) onEdit;
  final Future<void> Function(T item) onDelete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/more')), title: Text(title)),
      floatingActionButton: FloatingActionButton(onPressed: onAdd, child: const Icon(Icons.add)),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? Center(child: Text('Belum ada data. Ketuk + untuk menambah.'))
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final item = list[i];
                  final tile = tileBuilder(item);
                  return ListTile(
                    title: tile.title,
                    subtitle: tile.subtitle,
                    onTap: () => onEdit(item),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (!await confirm(context, 'Hapus?', 'Data ini akan dihapus.', action: 'Hapus')) return;
                        try {
                          await onDelete(item);
                        } on Object catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

Future<void> _formDialog(
  BuildContext context, {
  required String title,
  required List<Widget> fields,
  required Future<void> Function() onSave,
}) {
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: fields))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
        FilledButton(
          onPressed: () async {
            try {
              await onSave();
              if (c.mounted) Navigator.pop(c);
            } on Object catch (e) {
              if (c.mounted) showError(c, e);
            }
          },
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
}

Widget _field(TextEditingController c, String label, {bool number = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );

// ---------------- Kategori ----------------

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(masterRepositoryProvider);
    void edit([CategoryItem? item]) {
      final name = TextEditingController(text: item?.name);
      final prefix = TextEditingController(text: item?.codePrefix);
      final life = TextEditingController(text: '${item?.usefulLifeYears ?? 4}');
      final residual = TextEditingController(text: '${item?.residualPercent ?? 0}');
      _formDialog(context,
          title: item == null ? 'Kategori baru' : 'Ubah kategori',
          fields: [
            _field(name, 'Nama *'),
            _field(prefix, 'Awalan kode * (mis. IT)'),
            _field(life, 'Umur ekonomis (tahun)', number: true),
            _field(residual, 'Nilai residu (%)', number: true),
          ],
          onSave: () async {
            await repo.saveCategory(CategoryItem(
              id: item?.id,
              name: name.text,
              codePrefix: prefix.text,
              usefulLifeYears: int.tryParse(life.text.trim()) ?? 0,
              residualPercent: double.tryParse(residual.text.trim().replaceAll(',', '.')) ?? 0,
            ));
          });
    }

    return _MasterList<CategoryItem>(
      title: 'Kategori',
      items: ref.watch(categoriesProvider),
      tileBuilder: (c) => ListTile(
        title: Text(c.name),
        subtitle: Text('${c.codePrefix} · umur ${c.usefulLifeYears} th · residu ${c.residualPercent.toStringAsFixed(0)}%'),
      ),
      onAdd: edit,
      onEdit: edit,
      onDelete: (c) => repo.deleteCategory(c.id!),
    );
  }
}

// ---------------- Lokasi ----------------

class LocationsScreen extends ConsumerWidget {
  const LocationsScreen({super.key});

  static const kinds = {'building': 'Gedung', 'room': 'Ruang', 'rack': 'Rak', 'other': 'Lainnya'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(masterRepositoryProvider);
    final all = ref.watch(locationsProvider).valueOrNull ?? const <LocationItem>[];
    String nameOf(String? id) => all.where((l) => l.id == id).map((l) => l.name).firstOrNull ?? '';

    void edit([LocationItem? item]) {
      final name = TextEditingController(text: item?.name);
      String kind = item?.kind ?? 'room';
      String? parent = item?.parentId;
      _formDialog(context,
          title: item == null ? 'Lokasi baru' : 'Ubah lokasi',
          fields: [
            _field(name, 'Nama *'),
            StatefulBuilder(builder: (c, setState) {
              return Column(children: [
                PickerField<String>(
                  label: 'Jenis',
                  value: kind,
                  allowEmpty: false,
                  options: [for (final e in kinds.entries) (value: e.key, label: e.value)],
                  onChanged: (v) => setState(() => kind = v ?? kind),
                ),
                const SizedBox(height: 12),
                PickerField<String>(
                  label: 'Induk (opsional)',
                  value: parent,
                  options: [for (final l in all) if (l.id != item?.id) (value: l.id!, label: l.name)],
                  onChanged: (v) => setState(() => parent = v),
                ),
              ]);
            }),
          ],
          onSave: () async {
            await repo.saveLocation(LocationItem(id: item?.id, name: name.text, parentId: parent, kind: kind));
          });
    }

    return _MasterList<LocationItem>(
      title: 'Lokasi',
      items: ref.watch(locationsProvider),
      tileBuilder: (l) => ListTile(
        title: Text(l.name),
        subtitle: Text([kinds[l.kind] ?? l.kind, if (l.parentId != null) 'di ${nameOf(l.parentId)}'].join(' · ')),
      ),
      onAdd: edit,
      onEdit: edit,
      onDelete: (l) => repo.deleteLocation(l.id!),
    );
  }
}

// ---------------- Penanggung jawab ----------------

class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(masterRepositoryProvider);
    void edit([PersonItem? item]) {
      final name = TextEditingController(text: item?.name);
      final unit = TextEditingController(text: item?.unit);
      final contact = TextEditingController(text: item?.contact);
      _formDialog(context,
          title: item == null ? 'Penanggung jawab baru' : 'Ubah penanggung jawab',
          fields: [_field(name, 'Nama *'), _field(unit, 'Unit / bagian'), _field(contact, 'Kontak')],
          onSave: () async {
            await repo.savePerson(PersonItem(id: item?.id, name: name.text, unit: unit.text, contact: contact.text));
          });
    }

    return _MasterList<PersonItem>(
      title: 'Penanggung jawab',
      items: ref.watch(peopleProvider),
      tileBuilder: (p) => ListTile(title: Text(p.name), subtitle: Text([p.unit, p.contact].whereType<String>().where((s) => s.isNotEmpty).join(' · '))),
      onAdd: edit,
      onEdit: edit,
      onDelete: (p) => repo.deletePerson(p.id!),
    );
  }
}
