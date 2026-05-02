import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/theme_settings.dart';

/// Theme engine for the Generator role:
/// - Loads theme JSON from Supabase (`app_settings` where `sleutel='theme_config'`)
/// - JSON is stored in the `waarde` column
/// - Listens live for changes and updates the app instantly
class ThemeProvider extends ChangeNotifier {
  static const _table = 'app_settings';
  static const _sleutel = 'theme_config';

  ThemeSettings _settings = ThemeSettings.fallback();
  RealtimeChannel? _channel;
  Object? _lastError;

  ThemeSettings get settings => _settings;
  Object? get lastError => _lastError;

  /// Convenient parsed colors for Flutter widgets.
  Color get primaryColor => hexToColor(_settings.primaryColor);
  Color get secondaryColor => hexToColor(_settings.secondaryColor);

  Future<void> load() async {
    try {
      final row = await AppSupabase.client
          .from(_table)
          .select()
          .eq('sleutel', _sleutel)
          .maybeSingle();

      final map = _extractWaardeJson(row);
      if (map != null) {
        _settings = ThemeSettings.fromMap(map);
        notifyListeners();
      }
    } catch (e) {
      _lastError = e;
      notifyListeners();
    }
  }

  void startLiveUpdates() {
    _channel?.unsubscribe();
    _channel = AppSupabase.client.channel('theme_config_live');

    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: _table,
      callback: (payload) {
        final record = payload.newRecord;
        if (record['sleutel'] != _sleutel) return;

        final map = _extractWaardeJson(record);
        if (map == null) return;

        _settings = ThemeSettings.fromMap(map);
        notifyListeners();
      },
    );

    _channel!.subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Map<String, dynamic>? _extractWaardeJson(Map<String, dynamic>? row) {
    if (row == null) return null;

    // Per blueprint: JSON is stored in `waarde`.
    final raw = row['waarde'];
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

  /// Converts a hex string like "#1A237E" or "1A237E" into a Flutter [Color].
  ///
  /// If alpha is missing, it assumes fully opaque.
  Color hexToColor(String hex) {
    final cleaned = hex.trim().replaceFirst('#', '');
    if (cleaned.isEmpty) return const Color(0xFF000000);

    final withAlpha = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
    final value = int.tryParse(withAlpha, radix: 16);
    if (value == null) return const Color(0xFF000000);
    return Color(value);
  }
}

