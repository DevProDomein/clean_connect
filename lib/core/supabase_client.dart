import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_constants.dart';

class AppSupabase {
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static Future<void> init() async {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Supabase keys are missing.\n'
        'Provide them via --dart-define:\n'
        '  --dart-define=${AppConstants.supabaseUrlEnv}=... '
        '--dart-define=${AppConstants.supabaseAnonKeyEnv}=...\n',
      );
    }

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}

