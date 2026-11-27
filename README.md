# Aset (Flutter) — Android + Windows portable, offline-first

Mengikuti "Spesifikasi Arsitektur Final". Fase 0–3 sudah ditulis.

**Status verifikasi (GitHub Actions):** `flutter analyze` tanpa error/warning, 49 uji lulus (1 dilewati: `app.lock`, hanya
Windows), `flutter build windows --release` dan `flutter build apk --release` berhasil. **Belum diuji manual di perangkat**:
UI, kamera, printer, flashdisk, dan benchmark 10.000/50.000 belum pernah dijalankan.

## Mengunduh hasil build
Buka tab **Actions** → run terbaru → bagian **Artifacts**: `AssetApp-win-x64` (zip portable, DLL VC++ sudah termasuk)
dan `AssetApp-android-apk` (APK rilis bertanda tangan kunci debug, untuk uji).

## Menyiapkan (sekali)
1. `flutter create --platforms=android,windows --project-name asset_app --org id.perusahaan .`
   (folder `android/` dan `windows/` dibuat; file yang sudah ada tidak ditimpa)
2. Android: di `android/app/build.gradle` set `minSdkVersion 24`; di `android/app/src/main/AndroidManifest.xml`
   tambahkan `<uses-permission android:name="android.permission.CAMERA"/>` (scan QR dan foto).
3. `flutter pub get`
4. `dart run build_runner build --delete-conflicting-outputs` (membuat `*.g.dart` drift)
5. `flutter test` lalu `flutter run -d windows` (atau perangkat Android)

## Fitur
| Fase | Fitur |
| --- | --- |
| 1 | Aset (CRUD, kode otomatis, soft delete), kategori/lokasi/penanggung jawab, foto + thumbnail, pencarian FTS5 + filter, keyset paging, penyusutan garis lurus, scan QR (kamera di Android, pemindai USB/ketik di Windows), impor CSV/Excel, ekspor CSV, backup otomatis + zip, restore |
| 2 | Mutasi, perawatan + pengingat (dashboard), stock opname, label QR (PDF A4 3×8), laporan daftar aset + nilai buku (PDF) |
| 3 | Paket perubahan `.assetpack`, penggabungan per bidang dengan HLC, layar Konflik |

## Struktur
`lib/core` util murni · `lib/data/db` drift (skema, FTS5, change_log) · `lib/data/storage` lokasi data portable + app.lock ·
`lib/features/*` per fitur · `lib/app` router, shell adaptif, provider · `tool/` benchmark.

## Uji
- `flutter test`: skema/FTS5, HLC, resolver lokasi data, penyusutan, importer, repository, penggabungan sinkronisasi.
  Uji `app.lock` hanya jalan di Windows.
- Benchmark: `dart run tool/seed_benchmark.dart --count 10000` lalu `--count 50000`.
  Windows butuh `sqlite3.dll` (dengan FTS5) di folder kerja. Mencetak LULUS/GAGAL per target bagian 6.
- Windows portable: `flutter build windows --release`, salin `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`
  ke folder rilis, lalu uji dari flashdisk, dari `C:\Program Files` (harus jatuh ke AppData), dan peluncuran ganda.

## Belum dikerjakan / keputusan terbuka
- **SQLCipher (enkripsi)**: belum ada; harus dibuktikan di Windows dulu (gerbang Fase 0). Tanpa enkripsi, siapa pun
  yang memegang flashdisk bisa membaca `assets.db`.
- Login/peran multi-pengguna, stok barang habis pakai, dan asuransi (ada di aplikasi Kotlin acuan) belum dibuat.
- Notifikasi sistem untuk pengingat: pengingat hanya tampil di Beranda.
- Ekspor Excel (.xlsx): hanya CSV (impor mendukung keduanya).
- Daftar Windows memakai `ListView`, belum `two_dimensional_scrollables`.
- Server sinkronisasi (Fase 4) belum ada.

## Penyimpangan dari spesifikasi (perlu persetujuan)
- Pengaturan di `data/settings.json` untuk Android juga (spesifikasi: `shared_preferences` di Android).
- `flutter_image_compress` tidak dipakai; foto diproses paket `image` di isolate untuk kedua platform.
- Paket tambahan: `file_picker`, `image_picker`, `archive`, `crypto` (backup zip, foto, sha256).
- Skema v1 menambah `categories.useful_life_years/residual_percent` dan `assets.warranty_until/disposed_at`
  (penyusutan, garansi, write off) serta tabel `sync_conflicts` (layar Konflik).
- Impor paket perubahan menandai perubahan masuk sebagai sudah diekspor (tidak diteruskan ke perangkat ketiga).
