import 'package:flutter/widgets.dart';

import 'screens/operator_dashboard_screen.dart';

export 'screens/operator_dashboard_screen.dart' show OperatorDashboardScreen;

/// Barrel entry retained for routing / drawer imports.
class OperatorDashboard extends StatelessWidget {
  const OperatorDashboard({super.key});

  @override
  Widget build(BuildContext context) =>
      const OperatorDashboardScreen();
}
