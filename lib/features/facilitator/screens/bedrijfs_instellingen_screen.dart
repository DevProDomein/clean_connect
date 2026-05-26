import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/user_role.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';

/// Masterpagina: bedrijfsgegevens, logo's en HTML-sjablonen.
class BedrijfsInstellingenScreen extends StatefulWidget {
  const BedrijfsInstellingenScreen({super.key});

  @override
  State<BedrijfsInstellingenScreen> createState() =>
      _BedrijfsInstellingenScreenState();
}

class _BedrijfsInstellingenScreenState extends State<BedrijfsInstellingenScreen> {
  Map<String, dynamic>? _gegevens;
  bool _isLoading = true;
  bool _saving = false;

  final naamCtrl = TextEditingController();
  final kvkCtrl = TextEditingController();
  final btwCtrl = TextEditingController();

  final straatCtrl = TextEditingController();
  final postcodeCtrl = TextEditingController();
  final stadCtrl = TextEditingController();
  final telefoonCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final websiteCtrl = TextEditingController();

  final ibanCtrl = TextEditingController();
  final bankCtrl = TextEditingController();

  final logoNormaalCtrl = TextEditingController();
  final logoTekstCtrl = TextEditingController();
  final logoWitCtrl = TextEditingController();

  final voorwaardenCtrl = TextEditingController();

  final factuurSjabloonCtrl = TextEditingController();
  final emailOfferteSjabloonCtrl = TextEditingController();
  final emailFactuurSjabloonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchGegevens();
  }

  @override
  void dispose() {
    naamCtrl.dispose();
    kvkCtrl.dispose();
    btwCtrl.dispose();
    straatCtrl.dispose();
    postcodeCtrl.dispose();
    stadCtrl.dispose();
    telefoonCtrl.dispose();
    emailCtrl.dispose();
    websiteCtrl.dispose();
    ibanCtrl.dispose();
    bankCtrl.dispose();
    logoNormaalCtrl.dispose();
    logoTekstCtrl.dispose();
    logoWitCtrl.dispose();
    voorwaardenCtrl.dispose();
    factuurSjabloonCtrl.dispose();
    emailOfferteSjabloonCtrl.dispose();
    emailFactuurSjabloonCtrl.dispose();
    super.dispose();
  }

  String _val(dynamic v) => (v ?? '').toString();

  String _htmlFromMap(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final s = _val(map[key]);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  bool _canAccess(UserProvider up) =>
      up.isGenerator ||
      up.role == UserRole.administrator ||
      up.role == UserRole.facilitator;

  void _vulControllers(Map<String, dynamic> map) {
    naamCtrl.text = _val(map['bedrijfsnaam']);
    kvkCtrl.text = _val(map['kvk_nummer']);
    btwCtrl.text = _val(map['btw_nummer']);
    straatCtrl.text = _val(map['adres_straat_huisnr']);
    postcodeCtrl.text = _val(map['adres_postcode']);
    stadCtrl.text = _val(map['adres_stad']);
    telefoonCtrl.text = _val(map['telefoonnummer']);
    emailCtrl.text = _val(map['emailadres']);
    websiteCtrl.text = _val(map['website']);
    ibanCtrl.text = _val(map['iban']);
    bankCtrl.text = _val(map['bank_naam']);
    logoNormaalCtrl.text = _val(map['logo_url']);
    logoTekstCtrl.text = _val(map['logo_tekst_url']);
    logoWitCtrl.text = _val(map['logo_wit_url']);
    voorwaardenCtrl.text = _val(map['algemene_voorwaarden']);
    factuurSjabloonCtrl.text = _htmlFromMap(map, [
      'factuur_template_html',
      'factuur_html_sjabloon',
    ]);
    emailOfferteSjabloonCtrl.text = _htmlFromMap(map, [
      'email_offerte_html',
      'email_offerte_sjabloon_html',
    ]);
    emailFactuurSjabloonCtrl.text = _htmlFromMap(map, [
      'email_factuur_html',
      'email_factuur_sjabloon_html',
    ]);
  }

  Future<void> _fetchGegevens() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('eigen_bedrijfsgegevens')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (!mounted) return;
      if (res != null) {
        final map = Map<String, dynamic>.from(res as Map);
        setState(() {
          _gegevens = map;
          _isLoading = false;
        });
        _vulControllers(map);
      } else {
        setState(() {
          _gegevens = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fout laden bedrijfsgegevens: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kon gegevens niet laden: $e')),
      );
    }
  }

  Future<void> _opslaan() async {
    if (_saving) return;
    if (naamCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bedrijfsnaam is verplicht.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('eigen_bedrijfsgegevens').update({
        'bedrijfsnaam': naamCtrl.text.trim(),
        'kvk_nummer': kvkCtrl.text.trim(),
        'btw_nummer': btwCtrl.text.trim(),
        'adres_straat_huisnr': straatCtrl.text.trim(),
        'adres_postcode': postcodeCtrl.text.trim(),
        'adres_stad': stadCtrl.text.trim(),
        'telefoonnummer': telefoonCtrl.text.trim(),
        'emailadres': emailCtrl.text.trim(),
        'website': websiteCtrl.text.trim(),
        'iban': ibanCtrl.text.trim(),
        'bank_naam': bankCtrl.text.trim(),
        'logo_url': logoNormaalCtrl.text.trim(),
        'logo_tekst_url': logoTekstCtrl.text.trim(),
        'logo_wit_url': logoWitCtrl.text.trim(),
        'algemene_voorwaarden': voorwaardenCtrl.text,
        'factuur_template_html': factuurSjabloonCtrl.text,
        'email_offerte_html': emailOfferteSjabloonCtrl.text,
        'email_factuur_html': emailFactuurSjabloonCtrl.text,
      }).eq('id', 1);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Instellingen succesvol opgeslagen!'),
          backgroundColor: Colors.green,
        ),
      );
      await _fetchGegevens();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fout bij opslaan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildVeld(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    IconData? icon,
    TextInputType? keyboardType,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon, color: Colors.blueGrey) : null,
          filled: true,
          fillColor: isDark ? const Color(0xFF1B1B23) : Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
    );
  }

  Widget _buildSectie(String titel, IconData icon, List<Widget> kinderen) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue.shade800),
                const SizedBox(width: 12),
                Text(
                  titel,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            ...kinderen,
          ],
        ),
      ),
    );
  }

  Widget _buildBedrijfsgegevensTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_gegevens == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Nog geen record gevonden (id=1). Vul de velden in en sla op.',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              _buildSectie('Algemene Informatie', Icons.business, [
                _buildVeld('Bedrijfsnaam', naamCtrl, icon: Icons.badge),
                Row(
                  children: [
                    Expanded(child: _buildVeld('KVK Nummer', kvkCtrl)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildVeld('BTW Nummer', btwCtrl)),
                  ],
                ),
              ]),
              _buildSectie('Adres & Contact', Icons.location_on, [
                _buildVeld('Straat & Huisnummer', straatCtrl),
                Row(
                  children: [
                    Expanded(child: _buildVeld('Postcode', postcodeCtrl)),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: _buildVeld('Stad', stadCtrl)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildVeld(
                        'E-mailadres',
                        emailCtrl,
                        icon: Icons.email,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildVeld(
                        'Telefoonnummer',
                        telefoonCtrl,
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ],
                ),
                _buildVeld(
                  'Website',
                  websiteCtrl,
                  icon: Icons.language,
                  keyboardType: TextInputType.url,
                ),
              ]),
              _buildSectie('Financieel', Icons.account_balance, [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildVeld('IBAN Rekeningnummer', ibanCtrl),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _buildVeld('Naam Bank', bankCtrl)),
                  ],
                ),
              ]),
              _buildSectie('Juridisch', Icons.gavel, [
                const Text(
                  'Deze algemene voorwaarden worden volautomatisch als bijlage '
                  'aan de PDF offertes toegevoegd.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _buildVeld('Algemene Voorwaarden', voorwaardenCtrl, maxLines: 15),
              ]),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSjablonenTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectie('Logo\'s', Icons.palette, [
                const Text(
                  'Plaats hier de URL naar jullie logo\'s voor PDF\'s en e-mails.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _buildVeld(
                  'Standaard Logo URL',
                  logoNormaalCtrl,
                  icon: Icons.image,
                ),
                _buildVeld(
                  'Tekstlogo URL (Groot)',
                  logoTekstCtrl,
                  icon: Icons.text_fields,
                ),
                _buildVeld(
                  'Wit Logo URL',
                  logoWitCtrl,
                  icon: Icons.image_outlined,
                ),
              ]),
              _buildSectie('HTML Sjablonen', Icons.html, [
                const Text(
                  'Gebruik {{variabelen}} in de HTML code om data dynamisch in te laden.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Factuur Lay-out (HTML/CSS)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildVeld(
                  'Factuur HTML Template',
                  factuurSjabloonCtrl,
                  maxLines: 10,
                ),
                const SizedBox(height: 24),
                const Text(
                  'E-mail: Offerte Verzenden (HTML)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildVeld(
                  'E-mail Offerte HTML',
                  emailOfferteSjabloonCtrl,
                  maxLines: 10,
                ),
                const SizedBox(height: 24),
                const Text(
                  'E-mail: Factuur Verzenden (HTML)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildVeld(
                  'E-mail Factuur HTML',
                  emailFactuurSjabloonCtrl,
                  maxLines: 10,
                ),
              ]),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();

    if (!_canAccess(up)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Instellingen & Sjablonen')),
        drawer: const AppDrawer(),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Je hebt geen toegang tot dit scherm.'),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: const Text('Instellingen & Sjablonen'),
          bottom: const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: [
              Tab(icon: Icon(Icons.business), text: 'Bedrijfsgegevens'),
              Tab(icon: Icon(Icons.code), text: 'Sjablonen & HTML'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildBedrijfsgegevensTab(),
                  _buildSjablonenTab(),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _saving ? null : _opslaan,
          backgroundColor: Colors.blue.shade800,
          foregroundColor: Colors.white,
          icon: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save),
          label: Text(
            _saving ? 'Opslaan...' : 'Opslaan',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
