import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/klant_module_placeholder.dart';

class KlantFacturenScreen extends StatefulWidget {
  const KlantFacturenScreen({super.key});

  @override
  State<KlantFacturenScreen> createState() => _KlantFacturenScreenState();
}

class _KlantFacturenScreenState extends State<KlantFacturenScreen> {
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
          'Facturen',
          style: GoogleFonts.inter(
            color: Colors.blue.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: const KlantModulePlaceholder(
              icon: Icons.receipt_long_outlined,
              description:
                  'Een overzicht van jouw openstaande en betaalde facturen.',
            ),
    );
  }
}
