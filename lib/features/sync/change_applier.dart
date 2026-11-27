import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/hlc.dart';
import '../../data/db/app_database.dart';

/// Satu baris `change_log` dari perangkat lain (isi paket perubahan).
class RemoteChange {
  const RemoteChange({
    required this.entity,
    required this.entityId,
    required this.op,
    required this.payload,
    required this.hlc,
    required this.deviceId,
    required this.createdAt,
  });

  final String entity;
  final String entityId;
  final String op;
  final Map<String, dynamic> payload;
  final String hlc;
  final String deviceId;
  final int createdAt;

  factory RemoteChange.fromJson(Map<String, dynamic> j) => RemoteChange(
        entity: j['entity'] as String,
        entityId: j['entityId'] as String,
        op: j['op'] as String,
        payload: (j['payload'] as Map).cast<String, dynamic>(),
        hlc: j['hlc'] as String,
        deviceId: j['deviceId'] as String,
        createdAt: j['createdAt'] as int,
      );

  Map<String, dynamic> toJson() => {
        'entity': entity,
        'entityId': entityId,
        'op': op,
        'payload': payload,
        'hlc': hlc,
        'deviceId': deviceId,
        'createdAt': createdAt,
      };
}

class ApplyReport {
  int applied = 0;
  int duplicates = 0;
  int skipped = 0;
  int conflicts = 0;
  final List<String> warnings = [];
}

String _snake(String camel) =>
    camel.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');

/// Menerapkan perubahan dari perangkat lain ke database lokal sesuai aturan konflik
/// (spesifikasi bagian 7). Semua nama tabel/kolom divalidasi terhadap skema: paket
/// perubahan adalah masukan tak tepercaya.
class ChangeApplier {
  ChangeApplier(this._db, this._hlc);

  final AppDatabase _db;
  final Hlc _hlc;

  /// Entitas yang disinkronkan → tabel drift.
  Map<String, TableInfo<Table, dynamic>> get _tables => {
        'categories': _db.categories,
        'locations': _db.locations,
        'people': _db.people,
        'assets': _db.assets,
        'asset_movements': _db.assetMovements,
        'maintenance': _db.maintenance,
        'attachments': _db.attachments,
        'audit_sessions': _db.auditSessions,
        'audit_items': _db.auditItems,
      };

  static const _protectedColumns = {'id', 'created_at', 'device_id', 'deleted_at'};

  /// Dipanggil di dalam transaksi oleh SyncService, berurutan menurut `seq` asal.
  Future<ApplyReport> applyAll(List<RemoteChange> changes) async {
    final report = ApplyReport();
    for (final c in changes) {
      await _applyOne(c, report);
    }
    return report;
  }

  Future<bool> _alreadySeen(RemoteChange c) async {
    final r = await _db.customSelect(
      'SELECT 1 AS x FROM change_log WHERE hlc = ? AND entity_id = ? LIMIT 1',
      variables: [Variable<String>(c.hlc), Variable<String>(c.entityId)],
    ).getSingleOrNull();
    return r != null;
  }

  Future<void> _logImported(RemoteChange c) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.changeLog).insert(ChangeLogCompanion.insert(
          entity: c.entity,
          entityId: c.entityId,
          op: c.op,
          payload: jsonEncode(c.payload),
          hlc: c.hlc,
          deviceId: c.deviceId,
          createdAt: c.createdAt,
          exportedAt: Value(now), // tidak diekspor ulang
        ));
  }

  Future<void> _applyOne(RemoteChange c, ApplyReport report) async {
    final table = _tables[c.entity];
    if (table == null) {
      report.skipped++;
      report.warnings.add('Entitas tidak dikenal: ${c.entity}');
      return;
    }
    if (await _alreadySeen(c)) {
      report.duplicates++;
      return;
    }
    _hlc.observe(c.hlc);
    switch (c.op) {
      case 'insert':
        await _insert(c, table, report);
      case 'update':
        await _update(c, table, report);
      case 'delete':
        await _delete(c, table, report);
      default:
        report.skipped++;
        report.warnings.add('Operasi tidak dikenal: ${c.op}');
        return;
    }
    await _logImported(c);
  }

  Future<bool> _exists(TableInfo<Table, dynamic> table, String id) async {
    final r = await _db.customSelect('SELECT 1 AS x FROM ${table.actualTableName} WHERE id = ?',
        variables: [Variable<String>(id)]).getSingleOrNull();
    return r != null;
  }

  Future<void> _conflict(RemoteChange c, String kind, {String? field, Object? local, Object? remote}) async {
    await _db.into(_db.syncConflicts).insert(SyncConflictsCompanion.insert(
          entity: c.entity,
          entityId: c.entityId,
          field: Value(field),
          kind: kind,
          localValue: Value(local?.toString()),
          remoteValue: Value(remote?.toString()),
          remoteHlc: c.hlc,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  // ---- insert ----
  Future<void> _insert(RemoteChange c, TableInfo<Table, dynamic> table, ApplyReport report) async {
    if (await _exists(table, c.entityId)) {
      report.duplicates++; // baris sama sudah ada (mis. paket tumpang tindih)
      return;
    }
    final row = (c.payload['row'] as Map?)?.cast<String, dynamic>();
    if (row == null) {
      report.skipped++;
      return;
    }
    final values = <String, Object?>{};
    final allowed = table.$columns.map((e) => e.$name).toSet();
    row.forEach((key, value) {
      final col = _snake(key);
      if (allowed.contains(col)) values[col] = value;
    });
    values['id'] = c.entityId;

    // Path media dari paket tak tepercaya: harus relatif dan tidak keluar dari folder data.
    if (c.entity == 'attachments') {
      for (final k in ['rel_path', 'thumb_rel_path']) {
        final v = values[k];
        if (v is String && (v.startsWith('/') || v.contains('..') || v.contains(':') || v.startsWith('\\'))) {
          report.skipped++;
          report.warnings.add('Lampiran dengan path tidak aman dilewati');
          return;
        }
      }
    }

    // Kode aset kembar dari dua perangkat: yang masuk belakangan diberi akhiran dan ditandai.
    if (c.entity == 'assets') {
      final code = values['asset_code'] as String?;
      if (code != null) {
        var candidate = code;
        var n = 2;
        while (await _codeTaken(candidate)) {
          candidate = '$code-$n';
          n++;
        }
        if (candidate != code) {
          values['asset_code'] = candidate;
          await _conflict(c, 'duplicate_code', field: 'assetCode', local: code, remote: candidate);
          report.conflicts++;
        }
      }
    }
    final cols = values.keys.toList();
    await _db.customInsert(
      'INSERT INTO ${table.actualTableName} (${cols.join(', ')}) VALUES (${List.filled(cols.length, '?').join(', ')})',
      variables: [for (final k in cols) _variable(values[k])],
      updates: {table},
    );
    report.applied++;
  }

  Future<bool> _codeTaken(String code) async {
    final r = await _db.customSelect('SELECT 1 AS x FROM assets WHERE asset_code = ? LIMIT 1',
        variables: [Variable<String>(code)]).getSingleOrNull();
    return r != null;
  }

  Variable _variable(Object? v) {
    if (v == null) return const Variable<String>(null);
    if (v is int) return Variable<int>(v);
    if (v is double) return Variable<double>(v);
    if (v is bool) return Variable<int>(v ? 1 : 0);
    return Variable<String>(v.toString());
  }

  // ---- update (digabung per bidang, HLC terbaru menang) ----
  Future<void> _update(RemoteChange c, TableInfo<Table, dynamic> table, ApplyReport report) async {
    if (!await _exists(table, c.entityId)) {
      report.skipped++; // barisnya belum/tidak pernah tiba; abaikan
      return;
    }
    final fields = (c.payload['fields'] as Map?)?.cast<String, dynamic>() ?? const {};
    final allowed = table.$columns.map((e) => e.$name).toSet();

    // Perubahan lokal pada entitas ini yang lebih baru daripada perubahan masuk.
    final newerLocal = await _db.customSelect(
      "SELECT op, payload FROM change_log WHERE entity_id = ? AND hlc > ? AND device_id != ?",
      variables: [Variable<String>(c.entityId), Variable<String>(c.hlc), Variable<String>(c.deviceId)],
    ).get();
    final localNewerFields = <String>{};
    var localDeletedLater = false;
    for (final r in newerLocal) {
      if (r.read<String>('op') == 'delete') {
        localDeletedLater = true;
        continue;
      }
      try {
        final p = jsonDecode(r.read<String>('payload')) as Map<String, dynamic>;
        final f = p['fields'];
        if (f is Map) localNewerFields.addAll(f.keys.cast<String>());
      } on FormatException {
        // abaikan payload rusak
      }
    }

    // Satu sisi hapus, sisi lain ubah → ubahan menang, pulihkan, tandai untuk ditinjau.
    final deleted = await _db.customSelect(
      'SELECT deleted_at FROM ${table.actualTableName} WHERE id = ?',
      variables: [Variable<String>(c.entityId)],
    ).getSingle();
    if (deleted.readNullable<int>('deleted_at') != null || localDeletedLater) {
      await _db.customUpdate(
        'UPDATE ${table.actualTableName} SET deleted_at = NULL WHERE id = ?',
        variables: [Variable<String>(c.entityId)],
        updates: {table},
      );
      await _conflict(c, 'delete_vs_update');
      report.conflicts++;
    }

    final sets = <String>[];
    final vars = <Variable>[];
    for (final e in fields.entries) {
      final col = _snake(e.key);
      if (!allowed.contains(col) || _protectedColumns.contains(col)) continue;
      final remoteValue = (e.value as Map)['n'];
      if (localNewerFields.contains(e.key) && !localDeletedLater) {
        final cur = await _db.customSelect('SELECT $col AS v FROM ${table.actualTableName} WHERE id = ?',
            variables: [Variable<String>(c.entityId)]).getSingle();
        await _conflict(c, 'field', field: e.key, local: cur.data['v'], remote: remoteValue);
        report.conflicts++;
        continue; // yang kalah dicatat, lokal dipertahankan
      }
      sets.add('$col = ?');
      vars.add(_variable(remoteValue));
    }
    if (sets.isNotEmpty) {
      sets.add('updated_at = ?');
      vars.add(Variable<int>(c.createdAt));
      await _db.customUpdate(
        'UPDATE ${table.actualTableName} SET ${sets.join(', ')} WHERE id = ?',
        variables: [...vars, Variable<String>(c.entityId)],
        updates: {table},
      );
    }
    report.applied++;
  }

  // ---- delete ----
  Future<void> _delete(RemoteChange c, TableInfo<Table, dynamic> table, ApplyReport report) async {
    if (!await _exists(table, c.entityId)) {
      report.skipped++;
      return;
    }
    // Bila lokal punya ubahan yang lebih baru, ubahan menang dan hapusan dilewati + ditandai.
    final newerUpdate = await _db.customSelect(
      "SELECT 1 AS x FROM change_log WHERE entity_id = ? AND op = 'update' AND hlc > ? AND device_id != ? LIMIT 1",
      variables: [Variable<String>(c.entityId), Variable<String>(c.hlc), Variable<String>(c.deviceId)],
    ).getSingleOrNull();
    if (newerUpdate != null) {
      await _conflict(c, 'delete_vs_update');
      report.conflicts++;
      return;
    }
    await _db.customUpdate(
      'UPDATE ${table.actualTableName} SET deleted_at = ?, updated_at = ? WHERE id = ?',
      variables: [Variable<int>(c.createdAt), Variable<int>(c.createdAt), Variable<String>(c.entityId)],
      updates: {table},
    );
    report.applied++;
  }
}
