import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class KlantPlanningScreen extends StatelessWidget {
  const KlantPlanningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Mijn Planning',
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.blueGrey.shade800,
        ),
      ),
    );
  }
}
