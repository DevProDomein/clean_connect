import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/theme_settings.dart';
import '../contracts/supabase_v1_contract.dart';
import '../supabase_client.dart';

/// Loads and watches the `theme_config` row in `app_settings` (contract V1.0).
///
/// Contract:
/// - key column = `sleutel`
/// - JSON column = `waarde`
class ThemeService {
  static const String _table = AppSettingsTable.name;
  static const String _keyValue = 'theme_config';

  Future<ThemeSettings?> fetchThemeConfig() async {
    final row = await AppSupabase.client
        .from(_table)
        .select()
        .eq(AppSettingsTable.sleutel, _keyValue)
        .maybeSingle();

    if (row == null) return null;

    final raw = row[AppSettingsTable.waarde];
    final map = _coerceToMap(raw);
    if (map == null) return null;
    return ThemeSettings.fromMap(map);
  }

  RealtimeChannel watchThemeConfig({
    required void Function(ThemeSettings settings) onChanged,
    void Function(Object error)? onError,
  }) {
    final channel = AppSupabase.client.channel('theme_config_changes');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: _table,
      callback: (payload) {
        try {
          final record = payload.newRecord;
          if (record[AppSettingsTable.sleutel] != _keyValue) return;

          final map = _coerceToMap(record[AppSettingsTable.waarde]);
          if (map == null) return;
          final settings = ThemeSettings.fromMap(map);
          onChanged(settings);
        } catch (e) {
          onError?.call(e);
        }
      },
    );

    channel.subscribe();
    return channel;
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
      if (decoded is Map) return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}

