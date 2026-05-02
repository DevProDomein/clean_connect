import 'package:supabase_flutter/supabase_flutter.dart';

import '../contracts/supabase_v1_contract.dart';
import '../supabase_client.dart';

/// Invites users and seeds `public.gebruikers` + optional permissions.
///
/// IMPORTANT: Supabase Admin invites require a service role key and therefore
/// cannot be executed directly from a client app using the anon key.
///
/// This service calls an Edge Function named `invite_user` which should perform:
/// - `supabase.auth.admin.inviteUserByEmail(email)`
/// - return `{ user_id: "<uuid>" }`
class InvitationService {
  Future<String> inviteUser({
    required String email,
    required String firstName,
    required String lastName,
    required String role, // facilitator | operator | klant
    required bool grantAdminStatus,
  }) async {
    late final FunctionResponse fnRes;
    try {
      fnRes = await AppSupabase.client.functions.invoke(
        'invite_user',
        body: {
          'email': email.trim(),
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'role': role.trim().toLowerCase(),
          'grant_admin_status': grantAdminStatus,
        },
      );
    } on FunctionException catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('not found') || msg.contains('404')) {
        throw StateError(
          'Systeem-instelling vereist: Configureer de Edge Function in Supabase.',
        );
      }
      rethrow;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('not found') || msg.contains('404')) {
        throw StateError(
          'Systeem-instelling vereist: Configureer de Edge Function in Supabase.',
        );
      }
      rethrow;
    }

    final data = fnRes.data;
    final userId = (data is Map ? data['user_id'] : null)?.toString();
    if (userId == null || userId.isEmpty) {
      throw const AuthException(
        'Edge Function invite_user did not return user_id.',
      );
    }

    // Seed master user record (contract V1.0).
    await AppSupabase.client.from(GebruikersTable.name).upsert({
      GebruikersTable.id: userId,
      GebruikersTable.email: email.trim(),
      GebruikersTable.voornaam: firstName.trim(),
      GebruikersTable.achternaam: lastName.trim(),
      GebruikersTable.gebruikersrol: role.trim().toLowerCase(),
    });

    if (grantAdminStatus) {
      await _grantAdminPermissionsForUser(userId);
    }

    return userId;
  }

  Future<void> _grantAdminPermissionsForUser(String userId) async {
    final keys = <String>{'invite_operator', 'security_center', 'finance'};

    final res = await AppSupabase.client
        .from(FinancePermissionsTable.name)
        .select('${FinancePermissionsTable.id}, ${FinancePermissionsTable.naam}')
        .inFilter(FinancePermissionsTable.naam, keys.toList());

    final rows = (res as List).cast<Map<String, dynamic>>();
    final permissionIds = rows
        .map((r) => r[FinancePermissionsTable.id]?.toString())
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toList();

    for (final pid in permissionIds) {
      await AppSupabase.client.from(GebruikerFinanceRechtenTable.name).insert({
        GebruikerFinanceRechtenTable.gebruikerId: userId,
        GebruikerFinanceRechtenTable.permissieId: pid,
      });
    }
  }
}

