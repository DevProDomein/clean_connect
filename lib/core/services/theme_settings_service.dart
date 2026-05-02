import 'dart:convert';

import '../../models/theme_settings.dart';
import '../contracts/supabase_v1_contract.dart';
import '../supabase_client.dart';

class ThemeSettingsService {
  Future<ThemeSettings?> fetchThemeSettings() async {
    final res = await AppSupabase.client
        .from(AppSettingsTable.name)
        .select()
        .eq(AppSettingsTable.sleutel, 'theme_config')
        .maybeSingle();

    if (res == null) return null;

    // Contract: JSON is stored in `waarde` (string or map).
    final dynamic rawValue = res[AppSettingsTable.waarde];
    final map = _coerceToMap(rawValue);
    if (map == null) return null;

    return ThemeSettings.fromMap(map);
  }

  Map<String, dynamic>? _coerceToMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    }
    return null;
  }
}

