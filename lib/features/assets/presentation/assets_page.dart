import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/formatters.dart';
import '../domain/asset_models.dart';
import 'asset_detail_view.dart';
import 'asset_list_controller.dart';

/// Layout adaptif: daftar + detail berdampingan di layar lebar, satu kolom di layar sempit.
class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key, this.detailId});
  final String? detailId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 840) {
        return Row(children: [
          SizedBox(width: 400, child: AssetListPane(selectedId: detailId)),
          const VerticalDivider(width: 1),
          Expanded(
            child: detailId == null
                ? const Center(child: Text('Pilih aset untuk melihat detail'))
                : AssetDetailView(key: ValueKey(detailId), assetId: detailId!, embedded: true),
          ),
        ]);
      }
      return detailId == null ? const AssetListPane() : AssetDetailView(key: ValueKey(detailId), assetId: detailId!);
    });
  }
}

class AssetListPane extends ConsumerStatefulWidget {
  const AssetListPane({super.key, this.selectedId});
  final String? selectedId;

  @override
  ConsumerState<AssetListPane> createState() => _AssetListPaneState();
}

class _AssetListPaneState extends ConsumerState<AssetListPane> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        ref.read(assetListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assetListProvider);
    final controller = ref.read(assetListProvider.notifier);
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final locs = ref.watch(locationsProvider).valueOrNull ?? const [];
    final f = state.filter;

    Widget chip<T>(String label, String? current, List<({String? id, String label})> options, void Function(String?) pick) {
      return PopupMenuButton<String?>(
        tooltip: label,
        onSelected: pick,
        itemBuilder: (_) => [
          PopupMenuItem<String?>(value: null, child: Text('Semua $label')),
          for (final o in options) PopupMenuItem<String?>(value: o.id, child: Text(o.label)),
        ],
        child: Chip(
          label: Text(current == null ? label : options.firstWhere((o) => o.id == current, orElse: () => (id: null, label: label)).label),
          backgroundColor: current == null ? null : Theme.of(context).colorScheme.primaryContainer,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Aset'), automaticallyImplyLeading: false),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/assets/new'),
        tooltip: 'Tambah aset',
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Cari nama, kode, serial, merek…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: controller.setQuery,
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            chip('Kategori', f.categoryId, [for (final c in cats) (id: c.id, label: c.name)],
                (v) => controller.setFilter(AssetFilter(categoryId: v, locationId: f.locationId, status: f.status))),
            const SizedBox(width: 8),
            chip('Lokasi', f.locationId, [for (final l in locs) (id: l.id, label: l.name)],
                (v) => controller.setFilter(AssetFilter(categoryId: f.categoryId, locationId: v, status: f.status))),
            const SizedBox(width: 8),
            chip('Status', f.status?.code, [for (final s in AssetStatus.values) (id: s.code, label: s.label)],
                (v) => controller.setFilter(AssetFilter(categoryId: f.categoryId, locationId: f.locationId, status: v == null ? null : AssetStatus.fromCode(v)))),
          ]),
        ),
        if (state.isSearching) const Padding(
          padding: EdgeInsets.all(4),
          child: Text('Hasil pencarian dibatasi 100 baris', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ),
        if (state.error != null) Padding(padding: const EdgeInsets.all(8), child: Text(state.error!, style: const TextStyle(color: Colors.red))),
        Expanded(
          child: state.items.isEmpty && !state.loading
              ? const Center(child: Text('Belum ada aset'))
              : ListView.builder(
                  controller: _scroll,
                  itemCount: state.items.length + (state.loading ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= state.items.length) {
                      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                    }
                    final a = state.items[i];
                    return ListTile(
                      selected: a.id == widget.selectedId,
                      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${a.code} · ${a.categoryName}${a.locationName == null ? '' : ' · ${a.locationName}'}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(a.status.label, style: const TextStyle(fontSize: 12)),
                        if (a.purchasePrice != null) Text(formatRupiah(a.purchasePrice), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ]),
                      onTap: () => context.go('/assets/${a.id}'),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
