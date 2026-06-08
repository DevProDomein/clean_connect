import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class KlantLogboekScreen extends StatelessWidget {
  const KlantLogboekScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Logboek & Werkbonnen',
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.blueGrey.shade800,
        ),
      ),
    );
  }
}
