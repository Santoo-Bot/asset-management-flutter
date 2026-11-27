import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/depreciation.dart';
import '../../core/formatters.dart';
import '../../data/db/app_database.dart';
import '../assets/domain/asset_models.dart';

class LabelData {
  const LabelData(this.code, this.name, this.location);
  final String code;
  final String name;
  final String? location;
}

class ReportOptions {
  const ReportOptions({this.filter = const AssetFilter(), this.maxRows = 5000});
  final AssetFilter filter;

  /// Batas baris agar memori terjaga; laporan memberi tahu bila terpotong.
  final int maxRows;
}

/// Pembuat PDF: label QR (A4, 3 kolom × 8 baris) dan laporan daftar aset dengan nilai buku.
class PdfService {
  PdfService(this._db);
  final AppDatabase _db;

  static const labelColumns = 3;
  static const labelRows = 8;

  /// QR berisi kode aset persis (dipindai lalu dicocokkan ke `asset_code`).
  Future<Uint8List> buildLabels(List<LabelData> labels, {String companyName = ''}) async {
    final doc = pw.Document();
    final perPage = labelColumns * labelRows;
    for (var start = 0; start < labels.length; start += perPage) {
      final pageLabels = labels.sublist(start, start + perPage > labels.length ? labels.length : start + perPage);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => pw.GridView(
          crossAxisCount: labelColumns,
          childAspectRatio: (PdfPageFormat.a4.width - 36) / labelColumns / ((PdfPageFormat.a4.height - 36) / labelRows),
          children: [for (final l in pageLabels) _label(l, companyName)],
        ),
      ));
    }
    return doc.save();
  }

  pw.Widget _label(LabelData l, String company) {
    return pw.Container(
      margin: const pw.EdgeInsets.all(3),
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
      child: pw.Row(children: [
        pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: l.code, width: 52, height: 52),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.center, children: [
            if (company.isNotEmpty) pw.Text(company, style: const pw.TextStyle(fontSize: 6), maxLines: 1),
            pw.Text(l.code, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), maxLines: 1),
            pw.Text(l.name, style: const pw.TextStyle(fontSize: 7), maxLines: 2),
            if (l.location != null) pw.Text(l.location!, style: const pw.TextStyle(fontSize: 6), maxLines: 1),
          ]),
        ),
      ]),
    );
  }

  /// Label untuk aset yang cocok dengan filter (maks [limit]).
  Future<List<LabelData>> labelsFor(AssetFilter filter, {int limit = 500}) async {
    final where = <String>['a.deleted_at IS NULL'];
    final vars = <Variable>[];
    if (filter.categoryId != null) { where.add('a.category_id = ?'); vars.add(Variable<String>(filter.categoryId!)); }
    if (filter.locationId != null) { where.add('a.location_id = ?'); vars.add(Variable<String>(filter.locationId!)); }
    if (filter.status != null) { where.add('a.status = ?'); vars.add(Variable<String>(filter.status!.code)); }
    final rows = await _db.customSelect(
      'SELECT a.asset_code, a.name, l.name AS location_name FROM assets a '
      'LEFT JOIN locations l ON l.id = a.location_id WHERE ${where.join(' AND ')} ORDER BY a.asset_code LIMIT ?',
      variables: [...vars, Variable<int>(limit)],
      readsFrom: {_db.assets, _db.locations},
    ).get();
    return [
      for (final r in rows) LabelData(r.read<String>('asset_code'), r.read<String>('name'), r.readNullable<String>('location_name')),
    ];
  }

  /// Laporan daftar aset + nilai buku per tanggal hari ini. Mengembalikan PDF dan jumlah baris yang tercetak.
  Future<({Uint8List pdf, int rows, bool truncated})> buildRegisterReport(ReportOptions options, {String companyName = ''}) async {
    final f = options.filter;
    final where = <String>['a.deleted_at IS NULL'];
    final vars = <Variable>[];
    if (f.categoryId != null) { where.add('a.category_id = ?'); vars.add(Variable<String>(f.categoryId!)); }
    if (f.locationId != null) { where.add('a.location_id = ?'); vars.add(Variable<String>(f.locationId!)); }
    if (f.status != null) { where.add('a.status = ?'); vars.add(Variable<String>(f.status!.code)); }
    final rows = await _db.customSelect(
      'SELECT a.asset_code, a.name, a.status, a.purchase_date, a.purchase_price, a.disposed_at, '
      'c.name AS category_name, c.useful_life_years, c.residual_percent, l.name AS location_name '
      'FROM assets a JOIN categories c ON c.id = a.category_id LEFT JOIN locations l ON l.id = a.location_id '
      'WHERE ${where.join(' AND ')} ORDER BY c.name, a.asset_code LIMIT ?',
      variables: [...vars, Variable<int>(options.maxRows + 1)],
      readsFrom: {_db.assets, _db.categories, _db.locations},
    ).get();
    final truncated = rows.length > options.maxRows;
    final used = truncated ? rows.sublist(0, options.maxRows) : rows;

    final now = DateTime.now();
    var totalCost = 0;
    var totalBook = 0;
    final data = <List<String>>[];
    for (final r in used) {
      final price = r.readNullable<int>('purchase_price');
      final date = r.readNullable<int>('purchase_date');
      String book = '-';
      if (price != null && date != null) {
        final d = calculateDepreciation(
          cost: price,
          purchaseDate: DateTime.fromMillisecondsSinceEpoch(date),
          usefulLifeYears: r.read<int>('useful_life_years'),
          residualPercent: r.read<double>('residual_percent'),
          asOf: now,
          disposedAt: r.readNullable<int>('disposed_at') == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(r.read<int>('disposed_at')),
        );
        totalCost += price;
        totalBook += d.bookValue;
        book = formatRupiah(d.bookValue);
      }
      data.add([
        r.read<String>('asset_code'),
        r.read<String>('name'),
        r.read<String>('category_name'),
        r.readNullable<String>('location_name') ?? '-',
        AssetStatus.fromCode(r.read<String>('status')).label,
        formatDate(date),
        formatRupiah(price),
        book,
      ]);
    }

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(companyName.isEmpty ? 'Daftar Aset' : '$companyName - Daftar Aset',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.Text('Per ${formatDate(now.millisecondsSinceEpoch)} · ${used.length} aset', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 6),
      ]),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Hal ${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
      ),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: const ['Kode', 'Nama', 'Kategori', 'Lokasi', 'Status', 'Tgl Perolehan', 'Harga', 'Nilai Buku'],
          data: data,
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 7),
          cellAlignments: {6: pw.Alignment.centerRight, 7: pw.Alignment.centerRight},
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        ),
        pw.SizedBox(height: 8),
        pw.Text('Total harga perolehan: ${formatRupiah(totalCost)}   ·   Total nilai buku: ${formatRupiah(totalBook)}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        if (truncated)
          pw.Text('Laporan dipotong pada ${options.maxRows} baris pertama. Persempit filter untuk melihat sisanya.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.red)),
      ],
    ));
    return (pdf: await doc.save(), rows: used.length, truncated: truncated);
  }
}
