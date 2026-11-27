/// SQL mentah yang tidak bisa diungkapkan drift: indeks parsial dan FTS5 dengan trigger.
/// Dijalankan di `onCreate` (versi 1). Perubahan berikutnya masuk lewat migrasi bertingkat.
const List<String> schemaV1ExtraSql = [
  // ---- Indeks ----
  'CREATE UNIQUE INDEX idx_assets_code ON assets(asset_code)',
  'CREATE INDEX idx_assets_category ON assets(category_id) WHERE deleted_at IS NULL',
  'CREATE INDEX idx_assets_location ON assets(location_id) WHERE deleted_at IS NULL',
  'CREATE INDEX idx_assets_status ON assets(status) WHERE deleted_at IS NULL',
  'CREATE INDEX idx_assets_assigned ON assets(assigned_to) WHERE deleted_at IS NULL',
  'CREATE INDEX idx_assets_updated ON assets(updated_at)',
  // Keyset paging daftar aktif: WHERE (name, id) > (?, ?) ORDER BY name, id
  'CREATE INDEX idx_assets_name_id ON assets(name, id) WHERE deleted_at IS NULL',
  'CREATE INDEX idx_movements_asset_at ON asset_movements(asset_id, "at")',
  'CREATE INDEX idx_maintenance_asset_due ON maintenance(asset_id, next_due)',
  'CREATE INDEX idx_attachments_asset ON attachments(asset_id)',
  'CREATE INDEX idx_audit_items_session ON audit_items(session_id)',
  'CREATE INDEX idx_changelog_entity ON change_log(entity, entity_id)',
  'CREATE INDEX idx_changelog_export ON change_log(exported_at)',
  // Dedupe paket perubahan: HLC memuat device id sehingga unik secara global.
  'CREATE UNIQUE INDEX idx_changelog_hlc ON change_log(hlc, entity_id)',

  // ---- FTS5 (external content: tidak menyalin teks, hanya indeks) ----
  '''
CREATE VIRTUAL TABLE asset_fts USING fts5(
  name, asset_code, serial_number, brand, model, notes,
  content='assets', content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2'
)''',
  '''
CREATE TRIGGER assets_fts_ai AFTER INSERT ON assets BEGIN
  INSERT INTO asset_fts(rowid, name, asset_code, serial_number, brand, model, notes)
  VALUES (new.rowid, new.name, new.asset_code, new.serial_number, new.brand, new.model, new.notes);
END''',
  '''
CREATE TRIGGER assets_fts_ad AFTER DELETE ON assets BEGIN
  INSERT INTO asset_fts(asset_fts, rowid, name, asset_code, serial_number, brand, model, notes)
  VALUES ('delete', old.rowid, old.name, old.asset_code, old.serial_number, old.brand, old.model, old.notes);
END''',
  '''
CREATE TRIGGER assets_fts_au AFTER UPDATE ON assets BEGIN
  INSERT INTO asset_fts(asset_fts, rowid, name, asset_code, serial_number, brand, model, notes)
  VALUES ('delete', old.rowid, old.name, old.asset_code, old.serial_number, old.brand, old.model, old.notes);
  INSERT INTO asset_fts(rowid, name, asset_code, serial_number, brand, model, notes)
  VALUES (new.rowid, new.name, new.asset_code, new.serial_number, new.brand, new.model, new.notes);
END''',
];
