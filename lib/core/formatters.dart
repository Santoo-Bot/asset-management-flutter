String _two(int n) => n.toString().padLeft(2, '0');

/// "Rp 1.234.567"; null → "-".
String formatRupiah(int? value) {
  if (value == null) return '-';
  final digits = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return 'Rp ${value < 0 ? '-' : ''}$buf';
}

/// Epoch ms → "dd/MM/yyyy"; null → "-".
String formatDate(int? ms) {
  if (ms == null) return '-';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

String formatDateTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${formatDate(ms)} ${_two(d.hour)}:${_two(d.minute)}';
}

/// Terima "dd/MM/yyyy", "d-M-yyyy", atau "yyyy-MM-dd". Mengembalikan epoch ms (tengah malam lokal) atau null.
int? parseDate(String? input) {
  final s = input?.trim() ?? '';
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{1,4})[/\-.](\d{1,2})[/\-.](\d{1,4})$').firstMatch(s);
  if (m == null) return null;
  var a = int.parse(m.group(1)!);
  final b = int.parse(m.group(2)!);
  var c = int.parse(m.group(3)!);
  int y, mo, d;
  if (m.group(1)!.length == 4) {
    y = a; mo = b; d = c;
  } else {
    d = a; mo = b; y = c;
  }
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || y < 1900 || y > 2200) return null;
  final dt = DateTime(y, mo, d);
  if (dt.month != mo) return null; // mis. 31 Februari
  return dt.millisecondsSinceEpoch;
}

/// "Rp 1.500.000", "1.500.000", "1500000" → 1500000. Tidak valid → null.
int? parseRupiah(String? input) {
  final s = (input ?? '').toLowerCase().replaceAll('rp', '').replaceAll(RegExp(r'[\s.]'), '').replaceAll(',00', '');
  if (s.isEmpty || !RegExp(r'^\d+$').hasMatch(s)) return null;
  return int.tryParse(s);
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
}
