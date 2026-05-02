import '../contracts/supabase_v1_contract.dart';

/// Flutter read-mirror rij uit [GebruikersMetadataTable.name].
class GebruikersMetadataRow {
  const GebruikersMetadataRow({
    required this.id,
    this.displayName,
    this.email,
    this.roleString,
  });

  final String id;
  final String? displayName;
  final String? email;
  /// Platte tekst voor routering / [UserProvider] (kolom [GebruikersMetadataTable.rol]).
  final String? roleString;

  static GebruikersMetadataRow? fromRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    final id = row[GebruikersMetadataTable.id]?.toString();
    if (id == null || id.isEmpty) return null;
    return GebruikersMetadataRow(
      id: id,
      displayName: row[GebruikersMetadataTable.naam]?.toString(),
      email: row[GebruikersMetadataTable.email]?.toString(),
      roleString: row[GebruikersMetadataTable.rol]?.toString().trim().toLowerCase(),
    );
  }
}
