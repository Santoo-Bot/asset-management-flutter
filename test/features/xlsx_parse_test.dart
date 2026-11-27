import 'dart:convert';
import 'dart:typed_data';

import 'package:asset_app/features/import_export/import_plan.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('xlsx → tabel string → rencana impor (roundtrip)', () {
    final book = Excel.createExcel();
    final sheet = book[book.getDefaultSheet()!];
    sheet.appendRow([TextCellValue('Kode'), TextCellValue('Nama'), TextCellValue('Kategori'), TextCellValue('Harga')]);
    sheet.appendRow([TextCellValue('A-1'), TextCellValue('Laptop Lenovo'), TextCellValue('Elektronik'), IntCellValue(12000000)]);
    final bytes = Uint8List.fromList(book.encode()!);

    final table = parseTableBytes((bytes: bytes, extension: '.xlsx'));
    expect(table.first, ['Kode', 'Nama', 'Kategori', 'Harga']);
    expect(table[1][1], 'Laptop Lenovo'); // teks tidak boleh berubah jadi "TextSpan(...)"
    expect(table[1][3], '12000000');

    final plan = buildImportPlan(table, {});
    expect(plan.errors, isEmpty);
    expect(plan.valid.single.purchasePrice, 12000000);
  });

  test('csv titik koma (Excel Indonesia) dan BOM', () {
    const csv = '﻿Kode;Nama;Kategori\nA-1;Meja;Furnitur\n';
    final table = parseTableBytes((bytes: Uint8List.fromList(utf8.encode(csv)), extension: 'csv'));
    expect(table[1], ['A-1', 'Meja', 'Furnitur']);
  });

  test('format tidak dikenal ditolak', () {
    expect(() => parseTableBytes((bytes: Uint8List(0), extension: '.pdf')), throwsFormatException);
  });
}
