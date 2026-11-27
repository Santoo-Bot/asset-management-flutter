import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/hlc.dart';
import '../core/settings_store.dart';
import '../data/db/app_database.dart';
import '../data/db/change_recorder.dart';
import '../data/storage/data_location.dart';
import '../features/assets/data/drift_asset_repository.dart';
import '../features/assets/domain/asset_models.dart';
import '../features/audit/audit_repository.dart';
import '../features/backup/backup_service.dart';
import '../features/import_export/import_export_service.dart';
import '../features/labels/pdf_service.dart';
import '../features/maintenance/maintenance_repository.dart';
import '../features/masters/data/drift_master_repository.dart';
import '../features/masters/domain/master_models.dart';
import '../features/movements/movement_repository.dart';
import '../features/photos/photo_service.dart';
import '../features/sync/sync_service.dart';

// ---- Diisi di main() lewat ProviderScope.overrides ----
final dataLocationProvider = Provider<DataLocation>((ref) => throw UnimplementedError('override di main()'));
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('override di main()'));
final deviceIdProvider = Provider<String>((ref) => throw UnimplementedError('override di main()'));
final hlcProvider = Provider<Hlc>((ref) => throw UnimplementedError('override di main()'));
final settingsProvider = Provider<SettingsStore>((ref) => throw UnimplementedError('override di main()'));

final changeRecorderProvider = Provider<ChangeRecorder>(
  (ref) => ChangeRecorder(ref.watch(databaseProvider), ref.watch(hlcProvider), ref.watch(deviceIdProvider)),
);

// ---- Repository dan servis ----
final assetRepositoryProvider = Provider<AssetRepository>((ref) => DriftAssetRepository(
      ref.watch(databaseProvider),
      ref.watch(changeRecorderProvider),
      ref.watch(deviceIdProvider),
    ));

final masterRepositoryProvider = Provider<MasterRepository>((ref) => DriftMasterRepository(
      ref.watch(databaseProvider),
      ref.watch(changeRecorderProvider),
      ref.watch(deviceIdProvider),
    ));

final movementRepositoryProvider = Provider((ref) => MovementRepository(
      ref.watch(databaseProvider),
      ref.watch(changeRecorderProvider),
      ref.watch(deviceIdProvider),
    ));

final maintenanceRepositoryProvider = Provider((ref) => MaintenanceRepository(
      ref.watch(databaseProvider),
      ref.watch(changeRecorderProvider),
      ref.watch(deviceIdProvider),
    ));

final auditRepositoryProvider = Provider((ref) => AuditRepository(
      ref.watch(databaseProvider),
      ref.watch(changeRecorderProvider),
      ref.watch(deviceIdProvider),
    ));

final photoServiceProvider = Provider((ref) => PhotoService(
      ref.watch(databaseProvider),
      ref.watch(changeRecorderProvider),
      ref.watch(dataLocationProvider),
      ref.watch(deviceIdProvider),
    ));

final importExportServiceProvider = Provider((ref) => ImportExportService(
      ref.watch(databaseProvider),
      ref.watch(changeRecorderProvider),
      ref.watch(deviceIdProvider),
    ));

final backupServiceProvider = Provider((ref) => BackupService(
      ref.watch(databaseProvider),
      ref.watch(dataLocationProvider),
    ));

final pdfServiceProvider = Provider((ref) => PdfService(ref.watch(databaseProvider)));

final syncServiceProvider = Provider((ref) => SyncService(
      ref.watch(databaseProvider),
      ref.watch(dataLocationProvider),
      ref.watch(hlcProvider),
      ref.watch(deviceIdProvider),
    ));

// ---- Aliran data untuk UI ----
final categoriesProvider = StreamProvider<List<CategoryItem>>((ref) => ref.watch(masterRepositoryProvider).watchCategories());
final locationsProvider = StreamProvider<List<LocationItem>>((ref) => ref.watch(masterRepositoryProvider).watchLocations());
final peopleProvider = StreamProvider<List<PersonItem>>((ref) => ref.watch(masterRepositoryProvider).watchPeople());
final statusCountsProvider =
    StreamProvider<List<AssetStatusCount>>((ref) => ref.watch(assetRepositoryProvider).watchStatusCounts());

/// Detail aset; dibuat ulang bila aset berubah (mengamati tabel assets).
final assetDetailProvider = StreamProvider.family<AssetDetail?, String>((ref, id) async* {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(assetRepositoryProvider);
  yield await repo.get(id);
  await for (final _ in db.tableUpdates(TableUpdateQuery.onAllTables([db.assets, db.categories, db.locations, db.people]))) {
    yield await repo.get(id);
  }
});

final remindersProvider = FutureProvider.autoDispose((ref) {
  // Hitung ulang saat data aset atau perawatan berubah.
  final db = ref.watch(databaseProvider);
  final sub = db.tableUpdates(TableUpdateQuery.onAllTables([db.maintenance, db.assets])).listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return ref.watch(maintenanceRepositoryProvider).reminders(days: ref.watch(settingsProvider).reminderDays);
});
