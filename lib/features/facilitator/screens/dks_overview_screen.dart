import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/widgets/app_drawer.dart';
import 'widgets/placeholder_panel.dart';

/// Facilitator shell: quality controls (DKS).
class DksOverviewScreen extends StatelessWidget {
  const DksOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    return Scaffold(
      backgroundColor: bg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(
          'Kwaliteitscontroles (DKS)',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
      ),
      body: const Center(
        child: PlaceholderPanel(
          icon: Icons.verified_outlined,
          title: 'Kwaliteitscontroles (DKS)',
          subtitle: 'Kwaliteit en inspectie',
          description: 'Deze module wordt binnenkort beschikbaar.',
        ),
      ),
    );
  }
}
