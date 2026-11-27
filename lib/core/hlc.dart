/// Hybrid Logical Clock: urutan perubahan tetap konsisten walau jam perangkat berbeda.
///
/// Format string: `<wallMs 13 digit>-<counter 4 hex>-<deviceId>`. Urutan leksikografis
/// sama dengan urutan kausal, sehingga bisa dibandingkan langsung di SQLite.
class Hlc {
  Hlc(this.deviceId, {int Function()? now, int lastWallMs = 0, int lastCounter = 0})
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _wall = lastWallMs,
        _counter = lastCounter;

  final String deviceId;
  final int Function() _now;
  int _wall;
  int _counter;

  /// Membuat stempel baru untuk perubahan lokal.
  String next() {
    final physical = _now();
    if (physical > _wall) {
      _wall = physical;
      _counter = 0;
    } else {
      _counter++;
    }
    return _format(_wall, _counter, deviceId);
  }

  /// Dipanggil saat mengimpor perubahan dari perangkat lain agar jam lokal tidak tertinggal.
  void observe(String remote) {
    final parts = remote.split('-');
    if (parts.length < 3) return;
    final wall = int.tryParse(parts[0]);
    final counter = int.tryParse(parts[1], radix: 16);
    if (wall == null || counter == null) return;
    if (wall > _wall || (wall == _wall && counter > _counter)) {
      _wall = wall;
      _counter = counter;
    }
  }

  static String _format(int wall, int counter, String device) =>
      '${wall.toString().padLeft(13, '0')}-${counter.toRadixString(16).padLeft(4, '0')}-$device';
}
