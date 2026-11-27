import 'package:asset_app/core/depreciation.dart';
import 'package:asset_app/core/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DepreciationResult calc({int cost = 12000000, int life = 4, double residual = 0, required DateTime asOf, DateTime? disposed}) =>
      calculateDepreciation(
        cost: cost,
        purchaseDate: DateTime(2024, 1, 15),
        usefulLifeYears: life,
        residualPercent: residual,
        asOf: asOf,
        disposedAt: disposed,
      );

  test('garis lurus prorata bulan penuh', () {
    final r = calc(asOf: DateTime(2025, 1, 15)); // 12 bulan dari 48
    expect(r.months, 12);
    expect(r.accumulated, 3000000);
    expect(r.bookValue, 9000000);
    expect(r.annual, 3000000);
  });

  test('bulan belum penuh tidak dihitung', () {
    expect(calc(asOf: DateTime(2024, 2, 14)).months, 0);
    expect(calc(asOf: DateTime(2024, 2, 15)).months, 1);
  });

  test('nilai residu menjaga nilai buku minimal', () {
    final r = calc(residual: 10, asOf: DateTime(2040, 1, 1));
    expect(r.residualValue, 1200000);
    expect(r.bookValue, 1200000);
    expect(r.fullyDepreciated, isTrue);
  });

  test('akumulasi tidak pernah melebihi nilai yang dapat disusutkan', () {
    final r = calc(cost: 1000001, life: 3, asOf: DateTime(2100, 1, 1));
    expect(r.accumulated, r.depreciable);
    expect(r.bookValue, 0);
  });

  test('write off menghentikan penyusutan', () {
    final r = calc(asOf: DateTime(2030, 1, 15), disposed: DateTime(2025, 1, 15));
    expect(r.months, 12);
  });

  test('tanggal beli di masa depan → 0', () {
    expect(calc(asOf: DateTime(2020, 1, 1)).accumulated, 0);
  });

  test('harga negatif ditolak', () {
    expect(() => calc(cost: -1, asOf: DateTime(2025, 1, 1)), throwsArgumentError);
  });

  group('formatters', () {
    test('rupiah', () {
      expect(formatRupiah(1234567), 'Rp 1.234.567');
      expect(formatRupiah(0), 'Rp 0');
      expect(formatRupiah(null), '-');
    });
    test('parseRupiah', () {
      expect(parseRupiah('Rp 1.500.000'), 1500000);
      expect(parseRupiah('1500000'), 1500000);
      expect(parseRupiah('abc'), isNull);
      expect(parseRupiah('-5'), isNull);
    });
    test('parseDate', () {
      expect(parseDate('15/01/2024'), DateTime(2024, 1, 15).millisecondsSinceEpoch);
      expect(parseDate('2024-01-15'), DateTime(2024, 1, 15).millisecondsSinceEpoch);
      expect(parseDate('31/02/2024'), isNull);
      expect(parseDate('xx'), isNull);
    });
  });
}
