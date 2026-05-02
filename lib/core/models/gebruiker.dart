import '../contracts/supabase_v1_contract.dart';

/// Masterdata-gebruiker; [id] = Supabase Auth UID (contract V1.0).
class Gebruiker {
  const Gebruiker({
    required this.id,
    this.email,
    this.role,
    this.firstName,
    this.lastName,
  });

  final String id;
  final String? email;
  /// Afkomstig van [GebruikersTable.gebruikersrol].
  final String? role;
  final String? firstName;
  final String? lastName;

  static Gebruiker? fromRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    final id = row[GebruikersTable.id]?.toString();
    if (id == null || id.isEmpty) return null;
    return Gebruiker(
      id: id,
      email: row[GebruikersTable.email]?.toString(),
      role: row[GebruikersTable.gebruikersrol]?.toString().trim().toLowerCase(),
      firstName: row[GebruikersTable.voornaam]?.toString(),
      lastName: row[GebruikersTable.achternaam]?.toString(),
    );
  }
}
