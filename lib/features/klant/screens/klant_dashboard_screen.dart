import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/supabase_client.dart';
import '../../../providers/user_provider.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';
import '../presentation/klant_nav_scope.dart';

class KlantDashboardScreen extends StatefulWidget {
  const KlantDashboardScreen({super.key});

  @override
  State<KlantDashboardScreen> createState() => _KlantDashboardScreenState();
}

class _KlantDashboardScreenState extends State<KlantDashboardScreen> {
  static const Color _navy = Color(0xFF0D1B3E);

  bool _loading = true;
  Object? _loadError;

  String _voornaam = '';
  String _bedrijfsnaam = '';
  Map<String, dynamic>? _volgendeSchoonmaak;

  final DateFormat _datumFmt = DateFormat('dd-MM-yyyy');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDashboard());
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  String _safeTime(dynamic v) {
    final t = _text(v);
    if (t.length >= 5) return t.substring(0, 5);
    return t.isEmpty ? '--:--' : t;
  }

  Map<String, dynamic>? _mapFrom(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  String _projectLabel(Map<String, dynamic> taak) {
    final project = _mapFrom(taak['projecten']);
    final naam = _text(project?['project_naam']);
    if (naam.isNotEmpty) return naam;
    final bedrijf = _text(taak['bedrijfsnaam']);
    if (bedrijf.isNotEmpty) return bedrijf;
    return 'Uw locatie';
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final userId = AppSupabase.client.auth.currentUser?.id ?? '';
      if (userId.isEmpty) {
        throw StateError('Geen ingelogde gebruiker.');
      }

      final profiel = await AppSupabase.client
          .from('gebruikers')
          .select(
            'voornaam, achternaam, bedrijven!gebruikers_bedrijf_id_fkey(bedrijfsnaam)',
          )
          .eq('id', userId)
          .maybeSingle();

      final vandaag =
          DateTime.now().toIso8601String().split('T').first;

      final taken = await AppSupabase.client
          .from('opdrachten')
          .select('*, projecten(project_naam)')
          .gte('geplande_datum', vandaag)
          .inFilter('status', ['open', 'deels_voltooid', 'ingepland'])
          .order('geplande_datum', ascending: true)
          .limit(1);

      if (!mounted) return;

      final Map<String, dynamic>? p = profiel == null
          ? null
          : Map<String, dynamic>.from(profiel as Map);
      final bedrijf = _mapFrom(
        p?['bedrijven'] ?? p?['bedrijven!gebruikers_bedrijf_id_fkey'],
      );
      final provider = context.read<UserProvider>();

      setState(() {
        _voornaam = _text(p?['voornaam']).isNotEmpty
            ? _text(p?['voornaam'])
            : provider.displayFirstName;
        _bedrijfsnaam = _text(bedrijf?['bedrijfsnaam']);
        _volgendeSchoonmaak = (taken as List).isNotEmpty
            ? Map<String, dynamic>.from(taken.first as Map)
            : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  void _navigateTab(String tabKey) {
    KlantNavScope.maybeOf(context)?.goToTab(tabKey);
  }

  Future<void> _mailFacilitator() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'info@cleanconnect.nl',
      queryParameters: const {
        'subject': 'Hulp nodig — Klantportaal',
      },
    );
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kan e-mail niet openen.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Dashboard laden mislukt',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text('$_loadError', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadDashboard,
                child: const Text('Opnieuw proberen'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, mobileNavBuffer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildNextUpCard(),
            const SizedBox(height: 24),
            _buildQuickActionsSection(),
            const SizedBox(height: 24),
            _buildHelpFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welkom terug, $_voornaam',
          style: GoogleFonts.inter(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: _navy,
            letterSpacing: -0.5,
          ),
        ),
        if (_bedrijfsnaam.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _bedrijfsnaam,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.blueGrey.shade600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNextUpCard() {
    final taak = _volgendeSchoonmaak;
    final heeftTaak = taak != null;

    final datumRaw = _text(taak?['geplande_datum']);
    String datumLabel = '—';
    if (datumRaw.isNotEmpty) {
      final parsed = DateTime.tryParse(datumRaw.split('T').first);
      if (parsed != null) datumLabel = _datumFmt.format(parsed);
    }
    final tijdLabel =
        '${_safeTime(taak?['tijdslot_start'])} – ${_safeTime(taak?['tijdslot_eind'])}';
    final locatie = heeftTaak ? _projectLabel(taak) : '';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade900,
            Colors.blue.shade800,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade900.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: Icon(
              Icons.cleaning_services_rounded,
              size: 56,
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Eerstvolgende schoonmaak',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.85),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 14),
              if (!heeftTaak)
                Text(
                  'Geen aankomende schoonmaakmomenten gevonden.',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.4,
                  ),
                )
              else ...[
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      datumLabel,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tijdLabel,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        locatie,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Snel regelen',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _navy,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _quickActionCard(
                icon: Icons.report_outlined,
                label: 'Melding / Klacht doorgeven',
                onTap: () => _navigateTab('service'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _quickActionCard(
                icon: Icons.add_circle_outline_rounded,
                label: 'Extra dienst aanvragen',
                onTap: () => _navigateTab('service'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _quickActionCard(
          icon: Icons.description_outlined,
          label: 'Werkbonnen bekijken',
          onTap: () => _navigateTab('logboek'),
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _quickActionCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool fullWidth = false,
  }) {
    final card = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: Colors.blue.shade400),
              const SizedBox(height: 12),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _navy,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (fullWidth) return card;
    return card;
  }

  Widget _buildHelpFooter() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hulp nodig?',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Neem contact op met uw facilitator voor vragen over planning of service.',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey.shade600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _mailFacilitator,
            icon: const Icon(Icons.mail_outline_rounded),
            label: const Text('E-mail sturen'),
          ),
        ],
      ),
    );
  }
}
