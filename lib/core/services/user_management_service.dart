import '../contracts/supabase_v1_contract.dart';
import '../models/gebruikers_metadata_row.dart';
import '../supabase_client.dart';

class UserSummary {
  const UserSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.roleString,
    required this.permissions,
    this.gebruikerEmbed,
  });

  final String id;
  final String name;
  final String email;
  final String roleString;
  final Set<String> permissions;

  /// Klant-rij uit [GebruikersTable] met geneste [bedrijven] + [offertes].
  final Map<String, dynamic>? gebruikerEmbed;

  bool get isAdminByPermission => permissions.contains('invite_operator');
}

class UserManagementService {
  Future<List<UserSummary>> fetchAllUsers() async {
    final metaRes = await AppSupabase.client
        .from(GebruikersMetadataTable.name)
        .select(
          '${GebruikersMetadataTable.id}, '
          '${GebruikersMetadataTable.naam}, '
          '${GebruikersMetadataTable.email}, '
          '${GebruikersMetadataTable.rol}',
        )
        .order(GebruikersMetadataTable.naam);

    final metaRows = (metaRes as List).cast<Map<String, dynamic>>();
    final meta = metaRows
        .map(GebruikersMetadataRow.fromRow)
        .whereType<GebruikersMetadataRow>()
        .toList();

    final permsByUser = await _fetchPermissionsForUsers(
      meta.map((m) => m.id).toList(),
    );

    final klantIds = meta
        .where((m) => (m.roleString ?? '').trim().toLowerCase() == 'klant')
        .map((m) => m.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    final embedById = await _fetchKlantBedrijfOffertes(klantIds);

    return meta
        .map(
          (m) => UserSummary(
            id: m.id,
            name: (m.displayName ?? '').trim().isEmpty
                ? '(geen naam)'
                : (m.displayName ?? '').trim(),
            email: (m.email ?? '').trim(),
            roleString: (m.roleString ?? '').trim(),
            permissions: permsByUser[m.id] ?? const <String>{},
            gebruikerEmbed: embedById[m.id],
          ),
        )
        .toList();
  }

  Future<Map<String, Map<String, dynamic>>> _fetchKlantBedrijfOffertes(
    List<String> klantIds,
  ) async {
    if (klantIds.isEmpty) return {};

    try {
      final res = await AppSupabase.client
          .from(GebruikersTable.name)
          .select(
            'id, bedrijven!gebruikers_bedrijf_id_fkey('
            'id, bedrijfsnaam, '
            'offertes(id, status, contract_type, aangemaakt_op)'
            ')',
          )
          .inFilter(GebruikersTable.id, klantIds);

      final out = <String, Map<String, dynamic>>{};
      for (final row in (res as List).whereType<Map>()) {
        final m = Map<String, dynamic>.from(row);
        final id = m[GebruikersTable.id]?.toString();
        if (id != null && id.isNotEmpty) out[id] = m;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, Set<String>>> _fetchPermissionsForUsers(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};

    final idToNaam = await _financePermissionIdToNaam();

    final res = await AppSupabase.client
        .from(GebruikerFinanceRechtenTable.name)
        .select(
          '${GebruikerFinanceRechtenTable.gebruikerId}, '
          '${GebruikerFinanceRechtenTable.permissieId}',
        )
        .inFilter(GebruikerFinanceRechtenTable.gebruikerId, userIds);

    final rows = (res as List).cast<Map<String, dynamic>>();

    final out = <String, Set<String>>{};
    for (final row in rows) {
      final uid = row[GebruikerFinanceRechtenTable.gebruikerId]?.toString();
      final pid = row[GebruikerFinanceRechtenTable.permissieId]?.toString();
      if (uid == null || uid.isEmpty || pid == null || pid.isEmpty) continue;

      final naam = idToNaam[pid];
      if (naam == null || naam.isEmpty) continue;
      (out[uid] ??= <String>{}).add(naam);
    }

    return out;
  }

  Future<Map<String, String>> _financePermissionIdToNaam() async {
    final res = await AppSupabase.client
        .from(FinancePermissionsTable.name)
        .select('${FinancePermissionsTable.id}, ${FinancePermissionsTable.naam}');
    final rows = (res as List).cast<Map<String, dynamic>>();
    final map = <String, String>{};
    for (final r in rows) {
      final id = r[FinancePermissionsTable.id]?.toString();
      if (id == null || id.isEmpty) continue;
      final naam =
          r[FinancePermissionsTable.naam]?.toString().trim().toLowerCase();
      if (naam == null || naam.isEmpty) continue;
      map[id] = naam;
    }
    return map;
  }
}

