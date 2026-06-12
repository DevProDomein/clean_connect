import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/klant_module_placeholder.dart';

class KlantContractenScreen extends StatefulWidget {
  const KlantContractenScreen({super.key});

  @override
  State<KlantContractenScreen> createState() => _KlantContractenScreenState();
}

class _KlantContractenScreenState extends State<KlantContractenScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: Colors.blue.shade900),
        title: Text(
          'Contracten & Offertes',
          style: GoogleFonts.inter(
            color: Colors.blue.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: const KlantModulePlaceholder(
              icon: Icons.description_outlined,
              description:
                  'Een overzicht van al jouw actieve schoonmaakcontracten en getekende offertes.',
            ),
    );
  }
}
