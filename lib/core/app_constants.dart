/// Central place for app-wide constants.
///
/// Secrets (like Supabase keys) should NOT be committed in source control.
class AppConstants {
  /// Provide via `--dart-define=SUPABASE_URL=...`
  static const String supabaseUrlEnv = 'SUPABASE_URL';

  /// Provide via `--dart-define=SUPABASE_ANON_KEY=...`
  static const String supabaseAnonKeyEnv = 'SUPABASE_ANON_KEY';
}

