import 'dart:convert';
import 'dart:io';

/// Pengaturan di `data/settings.json` (tanpa Registry dan tanpa shared_preferences,
/// agar ikut terbawa saat folder dipindah). Dipakai di Android dan Windows.
class SettingsStore {
  SettingsStore._(this._file, this._data);

  final File _file;
  final Map<String, Object?> _data;

  static Future<SettingsStore> load(File file) async {
    var data = <String, Object?>{};
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, Object?>) data = decoded;
      }
    } on Object {
      // File rusak: mulai dari pengaturan bawaan, jangan crash saat startup.
    }
    return SettingsStore._(file, data);
  }

  String get companyName => (_data['companyName'] as String?) ?? '';
  String get themeMode => (_data['themeMode'] as String?) ?? 'system';
  int get reminderDays => (_data['reminderDays'] as int?) ?? 30;
  int get lastAutoBackupMs => (_data['lastAutoBackupMs'] as int?) ?? 0;

  Future<void> set(String key, Object? value) async {
    _data[key] = value;
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_data), flush: true);
    await tmp.rename(_file.path); // tulis atomik
  }
}
