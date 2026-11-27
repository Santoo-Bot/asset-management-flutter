import '../../../core/depreciation.dart';

enum AssetStatus {
  inUse('in_use', 'Digunakan'),
  available('available', 'Tersedia'),
  repair('repair', 'Dalam perbaikan'),
  writtenOff('written_off', 'Write off');

  const AssetStatus(this.code, this.label);
  final String code;
  final String label;

  static AssetStatus fromCode(String? code) =>
      values.firstWhere((e) => e.code == code, orElse: () => AssetStatus.inUse);

  /// Cocokkan nama tampilan atau kode (tanpa peduli huruf besar/kecil), untuk impor.
  static AssetStatus? parse(String? text) {
    final t = (text ?? '').trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final e in values) {
      if (e.code == t || e.label.toLowerCase() == t) return e;
    }
    return null;
  }
}

enum AssetCondition {
  good('good', 'Baik'),
  damaged('damaged', 'Rusak');

  const AssetCondition(this.code, this.label);
  final String code;
  final String label;

  static AssetCondition fromCode(String? code) =>
      values.firstWhere((e) => e.code == code, orElse: () => AssetCondition.good);

  static AssetCondition? parse(String? text) {
    final t = (text ?? '').trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final e in values) {
      if (e.code == t || e.label.toLowerCase() == t) return e;
    }
    return null;
  }
}

class AssetFilter {
  const AssetFilter({this.categoryId, this.locationId, this.status});
  final String? categoryId;
  final String? locationId;
  final AssetStatus? status;

  bool get isEmpty => categoryId == null && locationId == null && status == null;
}

class AssetCursor {
  const AssetCursor(this.name, this.id);
  final String name;
  final String id;
}

class AssetListItem {
  const AssetListItem({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.condition,
    required this.categoryName,
    this.locationName,
    this.purchasePrice,
  });

  final String id;
  final String code;
  final String name;
  final AssetStatus status;
  final AssetCondition condition;
  final String categoryName;
  final String? locationName;
  final int? purchasePrice;

  AssetCursor get cursor => AssetCursor(name, id);
}

/// Data yang diisi pengguna. `assetCode` kosong → dibuat otomatis dari awalan kategori.
class AssetDraft {
  const AssetDraft({
    this.assetCode,
    required this.name,
    required this.categoryId,
    this.locationId,
    this.status = AssetStatus.inUse,
    this.condition = AssetCondition.good,
    this.serialNumber,
    this.brand,
    this.model,
    this.purchaseDate,
    this.purchasePrice,
    this.vendor,
    this.assignedTo,
    this.warrantyUntil,
    this.disposedAt,
    this.notes,
  });

  final String? assetCode;
  final String name;
  final String categoryId;
  final String? locationId;
  final AssetStatus status;
  final AssetCondition condition;
  final String? serialNumber;
  final String? brand;
  final String? model;
  final int? purchaseDate;
  final int? purchasePrice;
  final String? vendor;
  final String? assignedTo;
  final int? warrantyUntil;
  final int? disposedAt;
  final String? notes;

  /// Kunci sama dengan `AssetRow.toJson()` agar bisa dibandingkan bidang demi bidang.
  Map<String, Object?> toMap() => {
        'assetCode': assetCode,
        'name': name,
        'categoryId': categoryId,
        'locationId': locationId,
        'status': status.code,
        'condition': condition.code,
        'serialNumber': serialNumber,
        'brand': brand,
        'model': model,
        'purchaseDate': purchaseDate,
        'purchasePrice': purchasePrice,
        'vendor': vendor,
        'assignedTo': assignedTo,
        'warrantyUntil': warrantyUntil,
        'disposedAt': disposedAt,
        'notes': notes,
      };
}

class AssetDetail {
  const AssetDetail({
    required this.id,
    required this.code,
    required this.draft,
    required this.categoryName,
    required this.usefulLifeYears,
    required this.residualPercent,
    this.locationName,
    this.personName,
    required this.updatedAt,
  });

  final String id;
  final String code;
  final AssetDraft draft;
  final String categoryName;
  final int usefulLifeYears;
  final double residualPercent;
  final String? locationName;
  final String? personName;
  final int updatedAt;

  /// Null bila tanggal atau harga perolehan belum diisi.
  DepreciationResult? depreciation([DateTime? asOf]) {
    final date = draft.purchaseDate;
    final price = draft.purchasePrice;
    if (date == null || price == null) return null;
    return calculateDepreciation(
      cost: price,
      purchaseDate: DateTime.fromMillisecondsSinceEpoch(date),
      usefulLifeYears: usefulLifeYears,
      residualPercent: residualPercent,
      asOf: asOf ?? DateTime.now(),
      disposedAt: draft.disposedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(draft.disposedAt!),
    );
  }
}

class AssetStatusCount {
  const AssetStatusCount(this.status, this.count, this.totalPrice);
  final AssetStatus status;
  final int count;
  final int totalPrice;
}

class ValidationError implements Exception {
  ValidationError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Validasi aturan bisnis; dipakai form dan impor.
String? validateDraft(AssetDraft d) {
  if (d.name.trim().isEmpty) return 'Nama aset wajib diisi';
  if (d.categoryId.isEmpty) return 'Kategori wajib dipilih';
  final price = d.purchasePrice;
  if (price != null && price < 0) return 'Harga tidak boleh negatif';
  final code = d.assetCode?.trim();
  if (code != null && code.isNotEmpty && !RegExp(r'^[A-Za-z0-9._\-/]{1,40}$').hasMatch(code)) {
    return 'Kode aset hanya boleh huruf, angka, titik, strip, garis miring (maks 40)';
  }
  return null;
}

abstract class AssetRepository {
  /// Halaman daftar aktif (keyset paging, urut nama lalu id).
  Future<List<AssetListItem>> page({AssetFilter filter = const AssetFilter(), AssetCursor? after, int limit = 50});

  /// Pencarian awalan FTS5, maksimal [limit] baris.
  Future<List<AssetListItem>> search(String text, {AssetFilter filter = const AssetFilter(), int limit = 100});

  Future<AssetDetail?> get(String id);
  Future<String?> idByCode(String code);
  Future<String> create(AssetDraft draft);
  Future<void> update(String id, AssetDraft draft);
  Future<void> softDelete(String id);
  Stream<List<AssetStatusCount>> watchStatusCounts();
}
