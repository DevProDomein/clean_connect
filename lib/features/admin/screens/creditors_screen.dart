import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/widgets/app_drawer.dart';

class CreditorsScreen extends StatelessWidget {
  const CreditorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Crediteuren',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
      ),
      body: SelectionArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: softBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            ),
            child: Text(
              'Crediteurenbeheer komt hier (enterprise module in opbouw).',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

