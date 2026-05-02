import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/supabase_client.dart';
import '../../providers/user_provider.dart';
import '../admin/screens/security_center_screen.dart';

/// Shown when the account is active but no portal permissions are assigned.
class NoPortalsAssignedScreen extends StatelessWidget {
  const NoPortalsAssignedScreen({
    super.key,
    required this.onRetry,
  });

  /// Clears cached identity load in [AuthGate] so the next build refetches.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final email = up.email ?? up.userId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Geen portal toegewezen'),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: () async {
              onRetry();
              await context.read<UserProvider>().loadForCurrentUser();
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Uitloggen',
            onPressed: () => AppSupabase.client.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Uw account is geactiveerd, maar er zijn nog geen portalen aan u toegewezen. '
              'Neem contact op met uw beheerder.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (email.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Ingelogd als: $email', style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                onRetry();
                final userProvider = context.read<UserProvider>();
                await AppSupabase.client.auth.refreshSession();
                await userProvider.loadForCurrentUser();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Opnieuw laden'),
            ),
            if (up.hasPermission('security_center')) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SecurityCenterScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.security),
                label: const Text('Beveiliging'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
