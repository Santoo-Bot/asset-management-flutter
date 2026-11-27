# Aset (Flutter) — Android + Windows portable, offline-first

Mengikuti "Spesifikasi Arsitektur Final". Status: **Fase 0 (spike teknis)**.

## Menyiapkan (sekali)
1. `flutter create --platforms=android,windows --project-name asset_app --org id.perusahaan .`
   (folder `android/` dan `windows/` dibuat; file yang sudah ada tidak ditimpa)
2. Android: set `minSdkVersion 24` di `android/app/build.gradle`.
3. `flutter pub get`
4. `dart run build_runner build --delete-conflicting-outputs` (membuat `*.g.dart` drift)

## Uji
- `flutter test` — skema, FTS5, HLC, resolver lokasi data.
  Uji `app.lock` hanya jalan di Windows.
- Benchmark: `dart run tool/seed_benchmark.dart --count 10000` lalu `--count 50000`.
  Windows butuh `sqlite3.dll` (dengan FTS5) di folder kerja. Mencetak LULUS/GAGAL per target bagian 6.
- Windows portable: `flutter build windows --release`, salin 3 DLL VC++ (app-local) ke folder rilis,
  lalu uji dari flashdisk, dari `C:\Program Files` (harus jatuh ke AppData), dan peluncuran ganda.

## Gerbang Fase 0 (belum terbukti)
- [ ] Benchmark 10.000 dan 50.000 memenuhi target (Windows dan Android kelas menengah)
- [ ] SQLCipher berjalan di Windows (`sqlcipher_flutter_libs`); bila gagal: rencana cadangan di spesifikasi
- [ ] Resolver teruji di flashdisk, Program Files, dan peluncuran ganda
