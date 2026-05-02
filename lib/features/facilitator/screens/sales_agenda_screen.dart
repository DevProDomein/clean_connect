import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/widgets/app_drawer.dart';
import 'widgets/placeholder_panel.dart';

/// Sales Agenda shell for the Facilitator Portal.
class SalesAgendaScreen extends StatelessWidget {
  const SalesAgendaScreen({super.key});

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
          'Sales Agenda',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
      ),
      body: const Center(
        child: PlaceholderPanel(
          icon: Icons.event_note_outlined,
          title: 'Sales Agenda',
          subtitle: 'Afspraken en opvolging',
          description: 'Deze module wordt binnenkort beschikbaar.',
        ),
      ),
    );
  }
}
