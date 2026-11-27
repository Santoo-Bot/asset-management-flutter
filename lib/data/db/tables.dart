import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Kolom bersama: UUID v7 (urut waktu), epoch ms, soft delete, dan perangkat asal.
mixin SyncColumns on Table {
  TextColumn get id => text().clientDefault(() => _uuid.v7())();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRow')
class Categories extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get codePrefix => text()();
  TextColumn get parentId => text().nullable().references(Categories, #id)();

  /// Dipakai penyusutan garis lurus (Fase 1).
  IntColumn get usefulLifeYears => integer().withDefault(const Constant(4))();
  RealColumn get residualPercent => real().withDefault(const Constant(0))();
}

@DataClassName('LocationRow')
class Locations extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable().references(Locations, #id)();

  /// building | room | rack | other
  TextColumn get kind => text().withDefault(const Constant('room'))();
}

@DataClassName('PersonRow')
class People extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get unit => text().nullable()();
  TextColumn get contact => text().nullable()();
}

@DataClassName('AssetRow')
class Assets extends Table with SyncColumns {
  TextColumn get assetCode => text()();
  TextColumn get name => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get locationId => text().nullable().references(Locations, #id)();
  TextColumn get status => text().withDefault(const Constant('in_use'))();
  TextColumn get condition => text().withDefault(const Constant('good'))();
  TextColumn get serialNumber => text().nullable()();
  TextColumn get brand => text().nullable()();
  TextColumn get model => text().nullable()();
  IntColumn get purchaseDate => integer().nullable()();

  /// Rupiah utuh.
  IntColumn get purchasePrice => integer().nullable()();
  TextColumn get vendor => text().nullable()();
  TextColumn get assignedTo => text().nullable().references(People, #id)();
  IntColumn get warrantyUntil => integer().nullable()();

  /// Tanggal write off; penyusutan berhenti di sini.
  IntColumn get disposedAt => integer().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
}

/// Riwayat hanya ditambah, tidak diubah.
@DataClassName('MovementRow')
class AssetMovements extends Table with SyncColumns {
  TextColumn get assetId => text().references(Assets, #id)();

  /// transfer | assign | return | other
  TextColumn get type => text()();
  TextColumn get fromLocationId => text().nullable().references(Locations, #id)();
  TextColumn get toLocationId => text().nullable().references(Locations, #id)();
  TextColumn get personId => text().nullable().references(People, #id)();
  IntColumn get at => integer()();
  TextColumn get note => text().nullable()();
}

@DataClassName('MaintenanceRow')
class Maintenance extends Table with SyncColumns {
  TextColumn get assetId => text().references(Assets, #id)();
  IntColumn get date => integer()();

  /// preventive | corrective | calibration | inspection
  TextColumn get type => text()();
  IntColumn get cost => integer().withDefault(const Constant(0))();
  IntColumn get nextDue => integer().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('AttachmentRow')
class Attachments extends Table with SyncColumns {
  TextColumn get assetId => text().references(Assets, #id)();
  TextColumn get kind => text().withDefault(const Constant('photo'))();

  /// Path relatif terhadap folder data/ (tidak pernah absolut).
  TextColumn get relPath => text()();
  TextColumn get thumbRelPath => text().nullable()();
  TextColumn get sha256 => text().nullable()();
  IntColumn get bytes => integer().withDefault(const Constant(0))();
}

@DataClassName('AuditSessionRow')
class AuditSessions extends Table with SyncColumns {
  TextColumn get name => text()();
  IntColumn get startedAt => integer()();
  IntColumn get finishedAt => integer().nullable()();
}

@DataClassName('AuditItemRow')
class AuditItems extends Table with SyncColumns {
  TextColumn get sessionId => text().references(AuditSessions, #id)();
  TextColumn get assetId => text().nullable().references(Assets, #id)();
  TextColumn get scannedCode => text()();

  /// found | missing | unregistered
  TextColumn get result => text()();
  IntColumn get scannedAt => integer().nullable()();
}

/// Dasar sinkronisasi dan log audit. `seq` naik terus; `hlc` menentukan urutan antar perangkat.
@DataClassName('ChangeLogRow')
class ChangeLog extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();

  /// insert | update | delete
  TextColumn get op => text()();

  /// JSON: bidang yang berubah (nilai baru, plus nilai lama untuk audit).
  TextColumn get payload => text()();
  TextColumn get hlc => text()();
  TextColumn get deviceId => text()();
  IntColumn get createdAt => integer()();

  /// Diisi saat dimasukkan ke paket .assetpack.
  IntColumn get exportedAt => integer().nullable()();
}

@DataClassName('AppMetaRow')
class AppMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
