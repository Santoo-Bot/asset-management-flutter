class CategoryItem {
  const CategoryItem({
    this.id,
    required this.name,
    required this.codePrefix,
    this.usefulLifeYears = 4,
    this.residualPercent = 0,
  });
  final String? id;
  final String name;
  final String codePrefix;
  final int usefulLifeYears;
  final double residualPercent;
}

class LocationItem {
  const LocationItem({this.id, required this.name, this.parentId, this.kind = 'room'});
  final String? id;
  final String name;
  final String? parentId;

  /// building | room | rack | other
  final String kind;
}

class PersonItem {
  const PersonItem({this.id, required this.name, this.unit, this.contact});
  final String? id;
  final String name;
  final String? unit;
  final String? contact;
}

abstract class MasterRepository {
  Stream<List<CategoryItem>> watchCategories();
  Stream<List<LocationItem>> watchLocations();
  Stream<List<PersonItem>> watchPeople();

  /// Insert bila `id == null`, selain itu update. Mengembalikan id.
  Future<String> saveCategory(CategoryItem item);
  Future<String> saveLocation(LocationItem item);
  Future<String> savePerson(PersonItem item);

  /// Soft delete; ditolak (lempar [MasterInUse]) bila masih dipakai aset.
  Future<void> deleteCategory(String id);
  Future<void> deleteLocation(String id);
  Future<void> deletePerson(String id);
}

class MasterInUse implements Exception {
  MasterInUse(this.message);
  final String message;
  @override
  String toString() => message;
}
