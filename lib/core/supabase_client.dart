import 'package:supabase_flutter/supabase_flutter.dart';

class AppSupabase {
  static Future<void> init({
    required String url,
    required String anonKey,
  }) async {
    if (url.trim().isEmpty || anonKey.trim().isEmpty) {
      throw StateError('Supabase keys are missing.');
    }

    await Supabase.initialize(
      url: url.trim(),
      anonKey: anonKey.trim(),
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}

