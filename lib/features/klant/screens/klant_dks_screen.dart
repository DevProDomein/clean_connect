import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/klant_module_placeholder.dart';

class KlantDksScreen extends StatefulWidget {
  const KlantDksScreen({super.key});

  @override
  State<KlantDksScreen> createState() => _KlantDksScreenState();
}

class _KlantDksScreenState extends State<KlantDksScreen> {
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
          'Kwaliteit & DKS',
          style: GoogleFonts.inter(
            color: Colors.blue.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: const KlantModulePlaceholder(
              icon: Icons.verified_outlined,
              description:
                  'Hier vind je binnenkort de resultaten van onze kwaliteitscontroles.',
            ),
    );
  }
}
