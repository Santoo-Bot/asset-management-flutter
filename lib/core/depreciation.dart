/// Penyusutan garis lurus, prorata per bulan penuh sejak tanggal perolehan.
class DepreciationResult {
  const DepreciationResult({
    required this.residualValue,
    required this.depreciable,
    required this.annual,
    required this.months,
    required this.accumulated,
    required this.bookValue,
  });

  final int residualValue;
  final int depreciable;
  final int annual;
  final int months;
  final int accumulated;
  final int bookValue;

  bool get fullyDepreciated => accumulated >= depreciable;
}

int monthsBetween(DateTime from, DateTime to) {
  if (!to.isAfter(from)) return 0;
  var m = (to.year - from.year) * 12 + (to.month - from.month);
  if (to.day < from.day) m--;
  return m < 0 ? 0 : m;
}

/// [disposedAt] (write off) menghentikan penyusutan pada tanggal tersebut.
DepreciationResult calculateDepreciation({
  required int cost,
  required DateTime purchaseDate,
  required int usefulLifeYears,
  required double residualPercent,
  required DateTime asOf,
  DateTime? disposedAt,
}) {
  if (cost < 0) throw ArgumentError.value(cost, 'cost', 'Harga tidak boleh negatif');
  final life = usefulLifeYears < 1 ? 1 : usefulLifeYears;
  final pct = residualPercent.clamp(0.0, 100.0).toDouble();
  final residual = (cost * pct / 100).round();
  final depreciable = cost - residual;
  final end = (disposedAt != null && disposedAt.isBefore(asOf)) ? disposedAt : asOf;
  final months = monthsBetween(purchaseDate, end);
  final total = life * 12;
  // Dihitung dari nilai yang dapat disusutkan agar tidak pernah melebihi batas.
  final accumulated = months >= total ? depreciable : (depreciable * months / total).round();
  return DepreciationResult(
    residualValue: residual,
    depreciable: depreciable,
    annual: (depreciable / life).round(),
    months: months,
    accumulated: accumulated,
    bookValue: cost - accumulated,
  );
}
