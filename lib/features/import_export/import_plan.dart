import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import '../../core/formatters.dart';
import '../assets/domain/asset_models.dart';

/// Satu baris impor yang lolos validasi (nama kategori/lokasi/orang masih berupa teks).
class ParsedAssetRow {
  const ParsedAssetRow({
    required this.line,
    required this.code,
    required this.name,
    required this.category,
    this.location,
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
    this.notes,
  });

  final int line;
  final String? code;
  final String name;
  final String category;
  final String? location;
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
  final String? notes;
}

class RowError {
  const RowError(this.line, this.message);
  final int line;
  final String message;
  @override
  String toString() => 'Baris $line: $message';
}

class ImportPlan {
  const ImportPlan(this.valid, this.errors, {this.missingColumns = const []});
  final List<ParsedAssetRow> valid;
  final List<RowError> errors;

  /// Kolom wajib yang tidak ditemukan di header; bila tidak kosong, tidak ada baris yang diproses.
  final List<String> missingColumns;
  bool get canCommit => missingColumns.isEmpty && valid.isNotEmpty;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

const _aliases = <String, List<String>>{
  'code': ['kode', 'kodeaset', 'code', 'assetcode', 'nomoraset'],
  'name': ['nama', 'namaaset', 'name', 'assetname'],
  'category': ['kategori', 'category'],
  'location': ['lokasi', 'location'],
  'status': ['status'],
  'condition': ['kondisi', 'condition'],
  'serial': ['serial', 'serialnumber', 'noseri', 'nomorseri', 'sn'],
  'brand': ['merek', 'merk', 'brand'],
  'model': ['model', 'tipe'],
  'date': ['tanggalbeli', 'tanggalperolehan', 'purchasedate', 'tglperolehan', 'tglbeli'],
  'price': ['harga', 'hargaperolehan', 'price', 'purchaseprice', 'nilaiperolehan'],
  'vendor': ['vendor', 'pemasok', 'supplier'],
  'person': ['penanggungjawab', 'pic', 'assignedto', 'pengguna'],
  'warranty': ['garansi', 'garansisampai', 'warrantyuntil', 'warranty'],
  'notes': ['catatan', 'keterangan', 'notes', 'note'],
};

/// Kolom yang wajib ada di header.
const requiredImportColumns = ['name', 'category'];

/// Template header yang dipakai ekspor dan contoh impor (urutan tetap).
const exportHeaders = [
  'Kode', 'Nama', 'Kategori', 'Lokasi', 'Status', 'Kondisi', 'Serial', 'Merek', 'Model',
  'Tanggal Perolehan', 'Harga', 'Vendor', 'Penanggung Jawab', 'Garansi Sampai', 'Catatan',
];

/// Membuat rencana impor dari tabel mentah (baris pertama = header). Fungsi murni, mudah diuji.
/// [existingCodes] = kode aset yang sudah ada di database (huruf besar/kecil diabaikan).
ImportPlan buildImportPlan(List<List<String>> table, Set<String> existingCodes) {
  if (table.isEmpty) return const ImportPlan([], [], missingColumns: ['name', 'category']);
  final header = table.first.map(_norm).toList();
  final index = <String, int>{};
  _aliases.forEach((key, names) {
    final i = header.indexWhere(names.contains);
    if (i >= 0) index[key] = i;
  });
  final missing = [for (final c in requiredImportColumns) if (!index.containsKey(c)) c];
  if (missing.isNotEmpty) return ImportPlan(const [], const [], missingColumns: missing);

  String? cell(List<String> row, String key) {
    final i = index[key];
    if (i == null || i >= row.length) return null;
    final v = row[i].trim();
    return v.isEmpty ? null : v;
  }

  final valid = <ParsedAssetRow>[];
  final errors = <RowError>[];
  final seen = <String>{};
  final existing = existingCodes.map((c) => c.toLowerCase()).toSet();

  for (var r = 1; r < table.length; r++) {
    final row = table[r];
    final line = r + 1; // nomor baris seperti di Excel (header = baris 1)
    if (row.every((c) => c.trim().isEmpty)) continue;

    final name = cell(row, 'name');
    final category = cell(row, 'category');
    final code = cell(row, 'code');
    if (name == null) { errors.add(RowError(line, 'Nama kosong')); continue; }
    if (category == null) { errors.add(RowError(line, 'Kategori kosong')); continue; }
    if (code != null) {
      if (!RegExp(r'^[A-Za-z0-9._\-/]{1,40}$').hasMatch(code)) {
        errors.add(RowError(line, 'Kode "$code" tidak valid')); continue;
      }
      final key = code.toLowerCase();
      if (existing.contains(key)) { errors.add(RowError(line, 'Kode "$code" sudah ada di database')); continue; }
      if (!seen.add(key)) { errors.add(RowError(line, 'Kode "$code" ganda di file')); continue; }
    }

    final priceText = cell(row, 'price');
    final price = priceText == null ? null : parseRupiah(priceText);
    if (priceText != null && price == null) { errors.add(RowError(line, 'Harga "$priceText" tidak valid')); continue; }

    final dateText = cell(row, 'date');
    final date = dateText == null ? null : parseDate(dateText);
    if (dateText != null && date == null) { errors.add(RowError(line, 'Tanggal "$dateText" tidak valid (pakai dd/MM/yyyy)')); continue; }

    final warrantyText = cell(row, 'warranty');
    final warranty = warrantyText == null ? null : parseDate(warrantyText);
    if (warrantyText != null && warranty == null) { errors.add(RowError(line, 'Tanggal garansi "$warrantyText" tidak valid')); continue; }

    final statusText = cell(row, 'status');
    final status = statusText == null ? AssetStatus.inUse : AssetStatus.parse(statusText);
    if (status == null) { errors.add(RowError(line, 'Status "$statusText" tidak dikenal')); continue; }

    final condText = cell(row, 'condition');
    final cond = condText == null ? AssetCondition.good : AssetCondition.parse(condText);
    if (cond == null) { errors.add(RowError(line, 'Kondisi "$condText" tidak dikenal')); continue; }

    valid.add(ParsedAssetRow(
      line: line,
      code: code,
      name: name,
      category: category,
      location: cell(row, 'location'),
      status: status,
      condition: cond,
      serialNumber: cell(row, 'serial'),
      brand: cell(row, 'brand'),
      model: cell(row, 'model'),
      purchaseDate: date,
      purchasePrice: price,
      vendor: cell(row, 'vendor'),
      assignedTo: cell(row, 'person'),
      warrantyUntil: warranty,
      notes: cell(row, 'notes'),
    ));
  }
  return ImportPlan(valid, errors);
}

/// Mengubah byte file (.csv atau .xlsx) menjadi tabel string. Berjalan di isolate lewat `compute`.
/// Lempar [FormatException] untuk format yang tidak dikenal.
List<List<String>> parseTableBytes(({Uint8List bytes, String extension}) input) {
  final ext = input.extension.toLowerCase().replaceFirst('.', '');
  if (ext == 'xlsx') return _parseXlsx(input.bytes);
  if (ext == 'csv' || ext == 'txt') return _parseCsv(input.bytes);
  throw FormatException('Format .$ext tidak didukung (gunakan .csv atau .xlsx)');
}

List<List<String>> _parseCsv(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final firstLine = text.split('\n').first;
  // Excel berbahasa Indonesia mengekspor dengan pemisah titik koma.
  final delimiter = (firstLine.contains(';') && !firstLine.contains(',')) ? ';' : ',';
  final rows = CsvToListConverter(fieldDelimiter: delimiter, eol: '\n', shouldParseNumbers: false).convert<dynamic>(text);
  return [for (final r in rows) [for (final c in r) c?.toString() ?? '']];
}

List<List<String>> _parseXlsx(Uint8List bytes) {
  final book = Excel.decodeBytes(bytes);
  if (book.tables.isEmpty) return const [];
  final sheet = book.tables[book.tables.keys.first]!;
  String str(CellValue? v) {
    if (v == null) return '';
    if (v is DateCellValue) return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.truncateToDouble() ? d.toInt().toString() : d.toString();
    }
    return v.toString();
  }

  return [
    for (final row in sheet.rows) [for (final cell in row) str(cell?.value)],
  ];
}
