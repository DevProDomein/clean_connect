import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium lege-statuskaart voor klantmodules.
class KlantModulePlaceholder extends StatelessWidget {
  const KlantModulePlaceholder({
    super.key,
    required this.icon,
    required this.description,
  });

  final IconData icon;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 64, color: Colors.blue.shade100),
                const SizedBox(height: 16),
                Text(
                  'Binnenkort beschikbaar',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
