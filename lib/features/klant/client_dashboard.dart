import 'package:flutter/material.dart';

import 'presentation/klant_scaffold.dart';

/// @deprecated Gebruik [KlantScaffold] of route `/klant/dashboard`.
class ClientDashboard extends StatelessWidget {
  const ClientDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const KlantScaffold(initialKey: 'dashboard');
  }
}
