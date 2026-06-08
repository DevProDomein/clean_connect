import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class KlantServiceScreen extends StatelessWidget {
  const KlantServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Service & Meldingen',
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.blueGrey.shade800,
        ),
      ),
    );
  }
}
