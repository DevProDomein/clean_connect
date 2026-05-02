/// Theme configuration stored in Supabase `app_settings.waarde` JSON.
class ThemeSettings {
  const ThemeSettings({
    required this.primaryColor,
    required this.secondaryColor,
    required this.fontFamily,
    required this.borderRadius,
  });

  /// Hex string like `#1A237E` (or `1A237E`).
  final String primaryColor;

  /// Hex string like `#00ACC1` (or `00ACC1`).
  final String secondaryColor;

  final String fontFamily;
  final double borderRadius;

  static ThemeSettings fallback() {
    return const ThemeSettings(
      primaryColor: '#6750A4',
      secondaryColor: '#625B71',
      fontFamily: 'Inter',
      borderRadius: 12,
    );
  }

  static ThemeSettings fromMap(Map<String, dynamic> map) {
    final fallbackSettings = fallback();

    final primary =
        _parseString(map['primary_color'])?.trim() ?? fallbackSettings.primaryColor;
    final secondary = _parseString(map['secondary_color'])?.trim() ??
        fallbackSettings.secondaryColor;
    final fontFamily = _parseString(map['font_family'])?.trim();
    final borderRadius =
        _parseDouble(map['border_radius']) ?? fallbackSettings.borderRadius;

    return ThemeSettings(
      primaryColor: primary,
      secondaryColor: secondary,
      fontFamily: (fontFamily == null || fontFamily.isEmpty)
          ? fallbackSettings.fontFamily
          : fontFamily,
      borderRadius: borderRadius,
    );
  }

  static String? _parseString(dynamic value) {
    if (value is String) return value;
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }
}

