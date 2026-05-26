import 'package:flutter/material.dart';

import '../features/facilitator/screens/bedrijfs_instellingen_screen.dart';
import '../features/facilitator/screens/pdf_preview_screen.dart';

/// Facilitator / generator routes buiten de operator mobile shell.
abstract final class AppRouter {
  /// Extra named routes (operator-shell routes blijven in [main.dart]).
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/bedrijfs-instellingen':
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const BedrijfsInstellingenScreen(),
        );
      case '/facilitator/quotes/pdf-preview':
        final offerteId = settings.arguments as String?;
        if (offerteId == null || offerteId.isEmpty) return null;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => PdfPreviewScreen(offerteId: offerteId),
        );
    }
    return null;
  }
}
