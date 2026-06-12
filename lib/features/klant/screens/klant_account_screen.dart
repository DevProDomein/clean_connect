import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase_client.dart';
import '../../../core/web_reload.dart';
import '../../../providers/user_provider.dart';

class KlantAccountScreen extends StatefulWidget {
  const KlantAccountScreen({super.key});

  @override
  State<KlantAccountScreen> createState() => _KlantAccountScreenState();
}

class _KlantAccountScreenState extends State<KlantAccountScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _bedrijfData;

  @override
  void initState() {
    super.initState();
    _loadAccountData();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  Map<String, dynamic>? _mapFrom(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return null;
  }

  Future<void> _loadAccountData() async {
    setState(() => _isLoading = true);
    try {
      final user = AppSupabase.client.auth.currentUser;
      if (user == null) return;

      final data = await AppSupabase.client
          .from('gebruikers')
          .select('''
            voornaam,
            achternaam,
            email,
            emailadres,
            telefoon,
            telefoonnummer,
            bedrijven!gebruikers_bedrijf_id_fkey (
              bedrijfsnaam,
              kvk_nummer,
              adres_straat_huisnr,
              adres_postcode,
              adres_stad
            )
          ''')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;
      final row = data == null ? null : Map<String, dynamic>.from(data as Map);
      setState(() {
        _userData = row;
        _bedrijfData = _mapFrom(
          row?['bedrijven'] ?? row?['bedrijven!gebruikers_bedrijf_id_fkey'],
        );
      });
    } catch (e) {
      debugPrint('Fout bij laden account data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _emailForReset {
    final mail = _text(_userData?['emailadres']);
    if (mail.isNotEmpty) return mail;
    return _text(_userData?['email']);
  }

  String get _telefoonDisplay {
    final t = _text(_userData?['telefoon']);
    if (t.isNotEmpty) return t;
    return _text(_userData?['telefoonnummer']);
  }

  String get _naamDisplay {
    final naam =
        '${_text(_userData?['voornaam'])} ${_text(_userData?['achternaam'])}'
            .trim();
    return naam.isEmpty ? '-' : naam;
  }

  String get _adresDisplay {
    if (_bedrijfData == null) return '-';
    final straat = _text(_bedrijfData!['adres_straat_huisnr']);
    final postcode = _text(_bedrijfData!['adres_postcode']);
    final stad = _text(_bedrijfData!['adres_stad']);
    final regel2 = [postcode, stad].where((e) => e.isNotEmpty).join(' ');
    return [straat, regel2].where((e) => e.isNotEmpty).join('\n');
  }

  Future<void> _stuurWachtwoordReset() async {
    final email = _emailForReset;
    if (email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Geen e-mailadres gevonden voor dit account.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await AppSupabase.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wachtwoord reset mail is verstuurd!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fout bij versturen mail: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _logout() async {
    try {
      await AppSupabase.client.auth.signOut();
      if (!mounted) return;
      context.read<UserProvider>().clear();
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
      if (kIsWeb) forceWebReload();
    } catch (e) {
      debugPrint('Fout bij uitloggen: $e');
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isNotEmpty ? value : '-',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade900,
            ),
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

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
          'Mijn Account',
          style: GoogleFonts.inter(
            color: Colors.blue.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userData == null
              ? const Center(child: Text('Kon accountgegevens niet laden.'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _card(
                        title: 'Persoonlijke Gegevens',
                        children: [
                          _buildInfoRow(Icons.person, 'Naam', _naamDisplay),
                          _buildInfoRow(
                            Icons.email,
                            'E-mailadres',
                            _emailForReset,
                          ),
                          _buildInfoRow(
                            Icons.phone,
                            'Telefoonnummer',
                            _telefoonDisplay,
                          ),
                          const Divider(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.lock_reset),
                              label: const Text('Wachtwoord resetten'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue.shade800,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _stuurWachtwoordReset,
                            ),
                          ),
                        ],
                      ),
                      if (_bedrijfData != null) ...[
                        const SizedBox(height: 16),
                        _card(
                          title: 'Bedrijfsgegevens',
                          children: [
                            _buildInfoRow(
                              Icons.business,
                              'Bedrijfsnaam',
                              _text(_bedrijfData!['bedrijfsnaam']),
                            ),
                            _buildInfoRow(
                              Icons.numbers,
                              'KVK Nummer',
                              _text(_bedrijfData!['kvk_nummer']),
                            ),
                            _buildInfoRow(
                              Icons.location_on,
                              'Adres',
                              _adresDisplay,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.logout, color: Colors.redAccent),
                          label: Text(
                            'Uitloggen',
                            style: GoogleFonts.inter(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: Colors.redAccent.withValues(alpha: 0.5),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _logout,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }
}
