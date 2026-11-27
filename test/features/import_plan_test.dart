import 'package:asset_app/features/import_export/import_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const header = ['Kode', 'Nama', 'Kategori', 'Lokasi', 'Status', 'Harga', 'Tanggal Perolehan'];

  test('baris valid dan kode kosong diizinkan (dibuat otomatis)', () {
    final plan = buildImportPlan([
      header,
      ['', 'Laptop', 'Elektronik', 'Gudang', 'Digunakan', 'Rp 12.000.000', '15/01/2024'],
    ], {});
    expect(plan.errors, isEmpty);
    expect(plan.valid.single.code, isNull);
    expect(plan.valid.single.purchasePrice, 12000000);
    expect(plan.canCommit, isTrue);
  });

  test('header alias bahasa Inggris dan pemisah tak peduli huruf besar/kecil', () {
    final plan = buildImportPlan([
      ['ASSET CODE', 'name', 'CATEGORY'],
      ['A-1', 'Printer', 'Elektronik'],
    ], {});
    expect(plan.valid.single.code, 'A-1');
  });

  test('kolom wajib hilang → tidak ada yang diproses', () {
    final plan = buildImportPlan([
      ['Kode', 'Lokasi'],
      ['A-1', 'Gudang'],
    ], {});
    expect(plan.missingColumns, containsAll(['name', 'category']));
    expect(plan.canCommit, isFalse);
  });

  test('kesalahan dilaporkan per baris dengan nomor baris gaya Excel', () {
    final plan = buildImportPlan([
      header,
      ['A-1', '', 'Elektronik', '', '', '', ''], // nama kosong → baris 2
      ['A-2', 'Meja', 'Furnitur', '', 'Aneh', '', ''], // status tak dikenal → baris 3
      ['A-3', 'Kursi', 'Furnitur', '', '', 'banyak', ''], // harga salah → baris 4
      ['A-4', 'Lemari', 'Furnitur', '', '', '', '31/02/2024'], // tanggal salah → baris 5
      ['A-5', 'OK', 'Furnitur', '', '', '', ''],
    ], {});
    expect(plan.valid.map((e) => e.code), ['A-5']);
    expect(plan.errors.map((e) => e.line), [2, 3, 4, 5]);
  });

  test('kode ganda di file dan di database ditolak', () {
    final plan = buildImportPlan([
      header,
      ['A-1', 'Satu', 'K', '', '', '', ''],
      ['a-1', 'Dua', 'K', '', '', '', ''], // ganda di file (tanpa peduli huruf)
      ['DB-9', 'Tiga', 'K', '', '', '', ''], // sudah ada di database
    ], {'DB-9'});
    expect(plan.valid, hasLength(1));
    expect(plan.errors, hasLength(2));
  });

  test('baris kosong dilewati diam-diam', () {
    final plan = buildImportPlan([
      header,
      ['', '', '', '', '', '', ''],
      ['', 'Meja', 'Furnitur', '', '', '', ''],
    ], {});
    expect(plan.errors, isEmpty);
    expect(plan.valid, hasLength(1));
  });

  test('kode dengan karakter berbahaya ditolak', () {
    final plan = buildImportPlan([
      header,
      ["A';DROP", 'Meja', 'Furnitur', '', '', '', ''],
    ], {});
    expect(plan.valid, isEmpty);
    expect(plan.errors.single.message, contains('tidak valid'));
  });
}
