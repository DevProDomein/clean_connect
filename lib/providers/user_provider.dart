import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models/user_role.dart';

/// Holds who is logged in and what portal/role they have.
class UserProvider extends ChangeNotifier {
  String? _userId;
  String? _email;
  String? _firstName;
  String? _profilePhotoUrl;
  UserRole? _role;
  final Set<String> _permissions = {};
  Object? _lastError;

  String? get userId => _userId;
  String? get email => _email;
  String? get firstName => _firstName;
  /// Public URL for the logged-in user’s profile photo (`gebruikers.profielfoto_url`), when known.
  String? get profilePhotoUrl => _profilePhotoUrl;
  UserRole? get role => _role;
  Set<String> get permissions => Set.unmodifiable(_permissions);
  Object? get lastError => _lastError;

  /// Lowercase role string for UI / policy checks (matches
  /// `gebruikers_metadata.rol` canonical values, except `beheerder`
  /// is normalized to `administrator` via [UserRole]).
  String? get roleString {
    switch (_role) {
      case UserRole.administrator:
        return 'administrator';
      case UserRole.facilitator:
        return 'facilitator';
      case UserRole.operator:
        return 'operator';
      case UserRole.klant:
        return 'klant';
      case UserRole.generator:
        return 'generator';
      case null:
        return null;
    }
  }

  /// Best-effort display name for greetings. Falls back to the email's
  /// local part (capitalized) when no `voornaam` is available, and finally
  /// to a generic label so UI never shows an empty string.
  String get displayFirstName {
    final vn = (_firstName ?? '').trim();
    if (vn.isNotEmpty) return vn;
    final mail = (_email ?? '').trim();
    if (mail.contains('@')) {
      final local = mail.split('@').first.trim();
      if (local.isNotEmpty) {
        return local[0].toUpperCase() + local.substring(1);
      }
    }
    return 'Gebruiker';
  }

  bool get isLoggedIn => _userId != null;

  bool get isGenerator => _role == UserRole.generator;

  /// True if the user may open at least one portal route (`portal_*`), or legacy
  /// [`finance`] which maps to the administrator/finance portal.
  ///
  /// Generator always qualifies via [hasPermission].
  bool get hasAnyPortalPermission {
    if (!isLoggedIn) return false;
    return hasPermission('portal_klant') ||
        hasPermission('portal_operator') ||
        hasPermission('portal_facilitator') ||
        hasPermission('portal_admin') ||
        hasPermission('finance');
  }

  /// Reload role + permissions from Supabase (e.g. after DB changes or app resume).
  Future<void> refreshIdentity() => loadForCurrentUser();

  /// Returns true if the logged-in user is allowed to perform [permissionName].
  ///
  /// - If role == Generator, always returns true.
  /// - Permission names are compared case-insensitively.
  bool hasPermission(String permissionName) {
    if (!isLoggedIn) return false;
    if (isGenerator) return true;
    final needle = permissionName.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return _permissions.contains(needle);
  }

  Future<void> loadForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      // Hard debug statement (requested).
      // ignore: avoid_print
      print('AUTH USER IS NULL');
      return;
    }

    _lastError = null;
    _userId = user.id;
    _email = user.email;

    // IMPORTANT: Boot identity is metadata-only (single source of truth).
    final data = await Supabase.instance.client
        .from('gebruikers_metadata')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    // Hard debug statement (requested).
    // ignore: avoid_print
    print('RAW DATABASE RESPONSE: $data');

    if (data == null) {
      // Hard debug statement (requested).
      // ignore: avoid_print
      print('NO DATA FOUND FOR USER');
      _role = null;
      _permissions.clear();
      _lastError = StateError(
        'Geen rol gevonden in `gebruikers_metadata`. '
        'Controleer RLS/policies op `gebruikers_metadata` voor ingelogde gebruikers.',
      );
      notifyListeners();
      return;
    }

    final rawRole = data['rol']?.toString();
    _role = _parseRole(rawRole);
    _firstName = data['voornaam']?.toString();

    try {
      final g = await Supabase.instance.client
          .from('gebruikers')
          .select('profielfoto_url')
          .eq('id', user.id)
          .maybeSingle();
      final raw = g?['profielfoto_url']?.toString().trim();
      _profilePhotoUrl =
          (raw != null && raw.isNotEmpty) ? raw : null;
    } catch (_) {
      // RLS or schema variance — profile UI still loads its own row.
    }

    if (_role == null) {
      _permissions.clear();
      _lastError = StateError(
        'Geen geldige rol gevonden in `gebruikers_metadata.rol`.',
      );
      notifyListeners();
      return;
    }

    // Boot must not query other tables. Permissions are loaded later (not here).
    if (isGenerator) {
      _permissions
        ..clear()
        ..add('*');
    } else {
      _permissions.clear();
    }

    notifyListeners();
  }

  void setUser({
    required String userId,
    String? email,
    required UserRole role,
  }) {
    _userId = userId;
    _email = email;
    _role = role;
    notifyListeners();
  }

  /// Call after the user saves a new profile photo URL so shell/widgets can refresh.
  void setProfilePhotoUrl(String? url) {
    final t = url?.trim();
    _profilePhotoUrl = (t != null && t.isNotEmpty) ? t : null;
    notifyListeners();
  }

  void clear() {
    _userId = null;
    _email = null;
    _firstName = null;
    _profilePhotoUrl = null;
    _role = null;
    _permissions.clear();
    _lastError = null;
    notifyListeners();
  }

  UserRole? _parseRole(String? raw) {
    final role = (raw ?? '').trim().toLowerCase();
    switch (role) {
      case 'administrator':
      case 'beheerder':
        return UserRole.administrator;
      case 'facilitator':
        return UserRole.facilitator;
      case 'operator':
        return UserRole.operator;
      case 'klant':
      case 'client':
        return UserRole.klant;
      case 'generator':
        return UserRole.generator;
      default:
        return null;
    }
  }
}

