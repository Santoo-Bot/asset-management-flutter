import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/asset_models.dart';

class AssetListState {
  const AssetListState({
    this.items = const [],
    this.loading = false,
    this.hasMore = true,
    this.query = '',
    this.filter = const AssetFilter(),
    this.error,
  });

  final List<AssetListItem> items;
  final bool loading;
  final bool hasMore;
  final String query;
  final AssetFilter filter;
  final String? error;

  bool get isSearching => query.trim().isNotEmpty;

  AssetListState copyWith({
    List<AssetListItem>? items,
    bool? loading,
    bool? hasMore,
    String? query,
    AssetFilter? filter,
    String? error,
    bool clearError = false,
  }) =>
      AssetListState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        hasMore: hasMore ?? this.hasMore,
        query: query ?? this.query,
        filter: filter ?? this.filter,
        error: clearError ? null : (error ?? this.error),
      );
}

const _pageSize = 50;

/// Daftar aset dengan keyset paging; pencarian FTS5 (didebounce 250 ms) dibatasi 100 baris.
/// Dimuat ulang otomatis saat tabel assets berubah.
class AssetListController extends Notifier<AssetListState> {
  Timer? _debounce;
  int _generation = 0;

  @override
  AssetListState build() {
    final db = ref.watch(databaseProvider);
    final sub = db.tableUpdates(TableUpdateQuery.onTable(db.assets)).listen((_) => refresh());
    ref.onDispose(() {
      sub.cancel();
      _debounce?.cancel();
    });
    Future.microtask(refresh);
    return const AssetListState(loading: true);
  }

  Future<void> refresh() async {
    final gen = ++_generation;
    final repo = ref.read(assetRepositoryProvider);
    final s = state;
    state = s.copyWith(loading: true, clearError: true);
    try {
      final items = s.isSearching
          ? await repo.search(s.query, filter: s.filter)
          : await repo.page(filter: s.filter, limit: _pageSize);
      if (gen != _generation) return; // permintaan lebih baru sudah berjalan
      state = state.copyWith(items: items, loading: false, hasMore: !s.isSearching && items.length == _pageSize);
    } on Object catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    final s = state;
    if (s.loading || !s.hasMore || s.items.isEmpty) return;
    final gen = _generation;
    state = s.copyWith(loading: true);
    try {
      final more = await ref.read(assetRepositoryProvider).page(filter: s.filter, after: s.items.last.cursor, limit: _pageSize);
      if (gen != _generation) return;
      state = state.copyWith(items: [...s.items, ...more], loading: false, hasMore: more.length == _pageSize);
    } on Object catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      state = state.copyWith(query: q);
      refresh();
    });
  }

  void setFilter(AssetFilter f) {
    state = state.copyWith(filter: f);
    refresh();
  }
}

final assetListProvider = NotifierProvider<AssetListController, AssetListState>(AssetListController.new);
