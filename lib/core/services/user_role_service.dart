import '../contracts/supabase_v1_contract.dart';
import '../models/gebruikers_metadata_row.dart';
import '../supabase_client.dart';

/// Laadt de rol-string volgens **API Contract V1.0** (geen kolom-gokwerk).
///
/// Single source of truth: [GebruikersMetadataTable] (`rol`).
///
/// NOTE: We intentionally avoid querying `gebruikers` from the client because
/// misconfigured RLS policies on that table can cause recursion errors and make
/// the whole app unusable.
class UserRoleService {
  Future<String?> fetchRoleForUser(String userId) async {
    try {
      final meta = await AppSupabase.client
          .from(GebruikersMetadataTable.name)
          .select()
          .eq(GebruikersMetadataTable.id, userId)
          .maybeSingle();
      final m = GebruikersMetadataRow.fromRow(meta);
      if (m?.roleString != null && m!.roleString!.isNotEmpty) {
        return m.roleString;
      }
    } catch (_) {}

    return null;
  }
}
