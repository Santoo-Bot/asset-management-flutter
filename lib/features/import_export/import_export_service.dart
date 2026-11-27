import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/formatters.dart';
import '../../data/db/app_database.dart';
import '../../data/db/change_recorder.dart';
import '../assets/domain/asset_models.dart';
import 'import_plan.dart';

class ImportResult {
  const ImportResult({required this.inserted, required this.createdCategories, required this.createdLocations, required this.createdPeople});
  final int inserted;
  final int createdCategories;
  final int createdLocations;
  final int createdPeople;
}

class ImportExportService {
  ImportExportService(this._db, this._recorder, this._deviceId);
  final AppDatabase _db;
  final ChangeRecorder _recorder;
  final String _deviceId;

  /// Langkah 1: parse (di isolate) + validasi. Belum menulis apa pun ke database.
  Future<ImportPlan> prepare(Uint8List bytes, String extension) async {
    final table = await compute(parseTableBytes, (bytes: bytes, extension: extension));
    final codes = await _db.customSelect('SELECT asset_code FROM assets').get();
    return buildImportPlan(table, {for (final r in codes) r.read<String>('asset_code')});
  }

  static String _prefixFor(String name, Set<String> used) {
    var base = name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (base.isEmpty) base = 'AST';
    if (base.length > 4) base = base.substring(0, 4);
    var candidate = base;
    var n = 2;
    while (used.contains(candidate)) {
      candidate = '$base$n';
      n++;
    }
    used.add(candidate);
    return candidate;
  }

  /// Langkah 2: satu transaksi, batch 500 baris. Kategori/lokasi/orang yang belum ada dibuat otomatis.
  Future<ImportResult> commit(ImportPlan plan, {void Function(int done, int total)? onProgress}) async {
    if (!plan.canCommit) throw StateError('Tidak ada baris valid untuk diimpor');
    const uuid = Uuid();
    return _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final entries = <ChangeEntry>[];

      // ---- master: cari atau buat ----
      final prefixes = {for (final c in await _db.select(_db.categories).get()) c.codePrefix};
      final catIds = <String, String>{for (final c in await _db.select(_db.categories).get()) if (c.deletedAt == null) c.name.toLowerCase(): c.id};
      final locIds = {for (final l in await _db.select(_db.locations).get()) if (l.deletedAt == null) l.name.toLowerCase(): l.id};
      final peopleIds = {for (final p in await _db.select(_db.people).get()) if (p.deletedAt == null) p.name.toLowerCase(): p.id};
      var newCats = 0, newLocs = 0, newPeople = 0;

      Future<void> ensureCategory(String name) async {
        final key = name.toLowerCase();
        if (catIds.containsKey(key)) return;
        final row = await _db.into(_db.categories).insertReturning(CategoriesCompanion.insert(
              name: name, codePrefix: _prefixFor(name, prefixes), createdAt: now, updatedAt: now, deviceId: _deviceId));
        catIds[key] = row.id;
        newCats++;
        entries.add(ChangeEntry('categories', row.id, 'insert', {'row': row.toJson()}));
      }

      Future<void> ensureLocation(String name) async {
        final key = name.toLowerCase();
        if (locIds.containsKey(key)) return;
        final row = await _db.into(_db.locations).insertReturning(
            LocationsCompanion.insert(name: name, createdAt: now, updatedAt: now, deviceId: _deviceId));
        locIds[key] = row.id;
        newLocs++;
        entries.add(ChangeEntry('locations', row.id, 'insert', {'row': row.toJson()}));
      }

      Future<void> ensurePerson(String name) async {
        final key = name.toLowerCase();
        if (peopleIds.containsKey(key)) return;
        final row = await _db.into(_db.people).insertReturning(
            PeopleCompanion.insert(name: name, createdAt: now, updatedAt: now, deviceId: _deviceId));
        peopleIds[key] = row.id;
        newPeople++;
        entries.add(ChangeEntry('people', row.id, 'insert', {'row': row.toJson()}));
      }

      for (final r in plan.valid) {
        await ensureCategory(r.category);
        if (r.location != null) await ensureLocation(r.location!);
        if (r.assignedTo != null) await ensurePerson(r.assignedTo!);
      }

      // ---- alokasi kode otomatis per awalan, dimulai dari nomor tertinggi di database ----
      final prefixOfCat = {for (final c in await _db.select(_db.categories).get()) c.id: c.codePrefix.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')};
      final counters = <String, int>{};
      Future<int> startFor(String prefix) async {
        final r = await _db.customSelect(
          'SELECT asset_code FROM assets WHERE asset_code LIKE ? ORDER BY asset_code DESC LIMIT 1',
          variables: [Variable<String>('$prefix-%')],
        ).getSingleOrNull();
        if (r == null) return 0;
        final code = r.read<String>('asset_code');
        return int.tryParse(code.substring(code.lastIndexOf('-') + 1)) ?? 0;
      }

      final usedCodes = <String>{for (final r in plan.valid) if (r.code != null) r.code!.toLowerCase()};
      var done = 0;
      for (var i = 0; i < plan.valid.length; i += 500) {
        final chunk = plan.valid.sublist(i, i + 500 > plan.valid.length ? plan.valid.length : i + 500);
        final companions = <AssetsCompanion>[];
        for (final r in chunk) {
          final catId = catIds[r.category.toLowerCase()]!;
          var code = r.code;
          if (code == null) {
            final prefix = prefixOfCat[catId] ?? 'AST';
            var n = counters[prefix] ?? await startFor(prefix);
            do {
              n++;
              code = '$prefix-${n.toString().padLeft(6, '0')}';
            } while (usedCodes.contains(code.toLowerCase()));
            counters[prefix] = n;
            usedCodes.add(code.toLowerCase());
          }
          final id = uuid.v7();
          final c = AssetsCompanion.insert(
            id: Value(id),
            assetCode: code,
            name: r.name,
            categoryId: catId,
            locationId: Value(r.location == null ? null : locIds[r.location!.toLowerCase()]),
            status: Value(r.status.code),
            condition: Value(r.condition.code),
            serialNumber: Value(r.serialNumber),
            brand: Value(r.brand),
            model: Value(r.model),
            purchaseDate: Value(r.purchaseDate),
            purchasePrice: Value(r.purchasePrice),
            vendor: Value(r.vendor),
            assignedTo: Value(r.assignedTo == null ? null : peopleIds[r.assignedTo!.toLowerCase()]),
            warrantyUntil: Value(r.warrantyUntil),
            notes: Value(r.notes),
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
          );
          companions.add(c);
        }
        await _db.batch((b) => b.insertAll(_db.assets, companions));
        for (final c in companions) {
          // Payload sama dengan AssetRow.toJson() agar bisa diterapkan di perangkat lain.
          entries.add(ChangeEntry('assets', c.id.value, 'insert', {
            'row': {
              'id': c.id.value,
              'createdAt': now,
              'updatedAt': now,
              'deletedAt': null,
              'deviceId': _deviceId,
              'assetCode': c.assetCode.value,
              'name': c.name.value,
              'categoryId': c.categoryId.value,
              'locationId': c.locationId.value,
              'status': c.status.value,
              'condition': c.condition.value,
              'serialNumber': c.serialNumber.value,
              'brand': c.brand.value,
              'model': c.model.value,
              'purchaseDate': c.purchaseDate.value,
              'purchasePrice': c.purchasePrice.value,
              'vendor': c.vendor.value,
              'assignedTo': c.assignedTo.value,
              'warrantyUntil': c.warrantyUntil.value,
              'disposedAt': null,
              'notes': c.notes.value,
              'version': 1,
            },
          }));
        }
        done += chunk.length;
        onProgress?.call(done, plan.valid.length);
      }
      for (var i = 0; i < entries.length; i += 500) {
        await _recorder.recordMany(entries.sublist(i, i + 500 > entries.length ? entries.length : i + 500));
      }
      return ImportResult(inserted: done, createdCategories: newCats, createdLocations: newLocs, createdPeople: newPeople);
    });
  }

  /// Ekspor CSV (UTF-8 BOM, bisa dibuka Excel) secara streaming per halaman 500 baris.
  Future<int> exportCsv(File target, {AssetFilter filter = const AssetFilter()}) async {
    final sink = target.openWrite(encoding: utf8);
    const converter = ListToCsvConverter(eol: '\n');
    var count = 0;
    try {
      sink.write('﻿');
      sink.writeln(converter.convert([exportHeaders]));
      String? lastName;
      String? lastId;
      while (true) {
        final where = <String>['a.deleted_at IS NULL'];
        final vars = <Variable>[];
        if (filter.categoryId != null) { where.add('a.category_id = ?'); vars.add(Variable<String>(filter.categoryId!)); }
        if (filter.locationId != null) { where.add('a.location_id = ?'); vars.add(Variable<String>(filter.locationId!)); }
        if (filter.status != null) { where.add('a.status = ?'); vars.add(Variable<String>(filter.status!.code)); }
        if (lastName != null) {
          where.add('(a.name, a.id) > (?, ?)');
          vars..add(Variable<String>(lastName))..add(Variable<String>(lastId!));
        }
        final rows = await _db.customSelect(
          'SELECT a.*, c.name AS category_name, l.name AS location_name, p.name AS person_name FROM assets a '
          'JOIN categories c ON c.id = a.category_id LEFT JOIN locations l ON l.id = a.location_id '
          'LEFT JOIN people p ON p.id = a.assigned_to WHERE ${where.join(' AND ')} ORDER BY a.name, a.id LIMIT 500',
          variables: vars,
          readsFrom: {_db.assets, _db.categories, _db.locations, _db.people},
        ).get();
        if (rows.isEmpty) break;
        final out = <List<Object?>>[];
        for (final r in rows) {
          out.add([
            r.read<String>('asset_code'),
            r.read<String>('name'),
            r.read<String>('category_name'),
            r.readNullable<String>('location_name') ?? '',
            AssetStatus.fromCode(r.read<String>('status')).label,
            AssetCondition.fromCode(r.read<String>('condition')).label,
            r.readNullable<String>('serial_number') ?? '',
            r.readNullable<String>('brand') ?? '',
            r.readNullable<String>('model') ?? '',
            r.readNullable<int>('purchase_date') == null ? '' : formatDate(r.read<int>('purchase_date')),
            r.readNullable<int>('purchase_price')?.toString() ?? '',
            r.readNullable<String>('vendor') ?? '',
            r.readNullable<String>('person_name') ?? '',
            r.readNullable<int>('warranty_until') == null ? '' : formatDate(r.read<int>('warranty_until')),
            r.readNullable<String>('notes') ?? '',
          ]);
        }
        sink.writeln(converter.convert(out));
        count += rows.length;
        lastName = rows.last.read<String>('name');
        lastId = rows.last.read<String>('id');
        if (rows.length < 500) break;
      }
    } finally {
      await sink.close();
    }
    return count;
  }
}
