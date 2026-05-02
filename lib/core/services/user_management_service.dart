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
  });

  final String id;
  final String name;
  final String email;
  final String roleString;
  final Set<String> permissions;

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
          ),
        )
        .toList();
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

