import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import 'operator_meldingen_screen.dart';
import 'operator_rooster_screen.dart';
import 'operator_uren_screen.dart';

/// Premium Apple-style bento dashboard voor operators.
class OperatorDashboardScreen extends StatefulWidget {
  const OperatorDashboardScreen({super.key});

  @override
  State<OperatorDashboardScreen> createState() =>
      _OperatorDashboardScreenState();
}

class _OperatorDashboardScreenState extends State<OperatorDashboardScreen>
    with SingleTickerProviderStateMixin {
  // Design tokens
  static const Color _deepNavy = Color(0xFF1A1A2E);
  static const Color _coral = Color(0xFFFF6B35);
  static const Color _electricBlue = Color(0xFF0077FF);
  static const Color _pageBg = Color(0xFFF4F6FA);

  static const double _radiusMain = 28;
  static const double _radiusSub = 20;

  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  Object? _loadError;

  Map<String, dynamic>? _statsRow;
  String? _profielfotoUrl;
  List<Map<String, dynamic>> _recentVoltooid = [];
  Map<String, dynamic>? _latestDks;
  List<Map<String, dynamic>> _vandaagRows = [];

  late final AnimationController _fadeCtl;
  late final Animation<double> _fadeAnim;

  final NumberFormat _eur = NumberFormat.currency(
    locale: 'nl_NL',
    symbol: '€',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _fadeCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtl, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDashboardData());
  }

  @override
  void dispose() {
    _fadeCtl.dispose();
    super.dispose();
  }

  String _trim(dynamic v) => (v ?? '').toString().trim();

  /// Parseert numerieke view-kolommen veilig (int, double, String, nl-komma).
  double _dashboardStatDouble(dynamic v) {
    if (v == null) return 0.0;
    final raw = v.toString().trim().replaceAll(' ', '').replaceAll('€', '');
    if (raw.isEmpty) return 0.0;
    final direct = double.tryParse(raw);
    if (direct != null) return direct;
    if (raw.contains(',')) {
      final normalized = raw.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(normalized) ?? 0.0;
    }
    return 0.0;
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(' ', '');
    if (s.isEmpty) return 0;
    final direct = double.tryParse(s);
    if (direct != null) return direct;
    if (s.contains(',')) {
      return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  double? _asDoubleNullable(dynamic v) {
    if (v == null) return null;
    final d = _asDouble(v);
    return d;
  }

  double? _dksScoreFromRow(Map<String, dynamic> r) {
    for (final k in const [
      'score_percentage',
      'score_definitief',
      'score_voorgesteld',
      'totaal_score',
      'gemiddelde_score',
    ]) {
      final x = _asDoubleNullable(r[k]);
      if (x != null && x > 0) return x;
    }
    return null;
  }

  /// Toon als schoolcijfer (bijv. 8,8): ruwe waarde > 10 wordt als percentage geïnterpreteerd.
  double? _displayDksCijfer(double? raw) {
    if (raw == null || raw <= 0) return null;
    if (raw <= 10.5) return raw;
    if (raw <= 100) return raw / 10.0;
    return raw / 10.0;
  }

  Map<String, dynamic>? _parseVolgendeKlus(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  String _safeTime(dynamic timeValue) {
    if (timeValue == null) return '—';
    final t = timeValue.toString().trim();
    if (t.length >= 5) return t.substring(0, 5);
    return t.isEmpty ? '—' : t;
  }

  String _bedrijfsnaamFromPlanning(Map<String, dynamic> row) {
    final direct = row['bedrijfsnaam']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final op = row['opdrachten'];
    if (op is Map && op['bedrijfsnaam'] != null) {
      final b = op['bedrijfsnaam'].toString().trim();
      if (b.isNotEmpty) return b;
    }
    return 'Klant';
  }

  String _maandLabelNl(Map<String, dynamic>? stats) {
    final fromView = _trim(stats?['getoonde_maand_label']);
    if (fromView.isNotEmpty) return fromView;

    if (stats != null) {
      for (final k in const [
        'maand_naam',
        'maandlabel',
        'huidige_maand_naam',
        'referentie_maand',
      ]) {
        final s = _trim(stats[k]);
        if (s.isNotEmpty) return s;
      }
      final km = stats['kalender_maand'] ?? stats['maand_key'];
      final parsed = DateTime.tryParse(_trim(km));
      if (parsed != null) {
        return DateFormat.yMMMM('nl_NL').format(parsed);
      }
    }
    return DateFormat.yMMMM('nl_NL').format(DateTime.now());
  }

  Future<void> _loadDashboardData() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _loadError = StateError('Niet ingelogd.');
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      Map<String, dynamic>? stats;
      try {
        final s = await _client
            .from('view_operator_dashboard_stats')
            .select()
            .eq('operator_id', uid)
            .maybeSingle();
        if (s != null) {
          stats = Map<String, dynamic>.from(s as Map);
          // ignore: avoid_print
          print('X-RAY DASHBOARD RAW: $stats');
        }
      } catch (e, st) {
        debugPrint('view_operator_dashboard_stats: $e\n$st');
        stats = null;
      }

      try {
        final userData = await _client
            .from('gebruikers')
            .select('profielfoto_url')
            .eq('id', _client.auth.currentUser!.id)
            .maybeSingle();
        if (userData != null && mounted) {
          setState(() {
            _profielfotoUrl = userData['profielfoto_url'];
          });
        }
      } catch (e) {
        debugPrint('Fout bij ophalen profielfoto: $e');
      }

      List<Map<String, dynamic>> recent = [];
      try {
        final r = await _client
            .from('opdracht_planning')
            .select('*, opdrachten(bedrijfsnaam)')
            .eq('operator_id', uid)
            .eq('status', 'voltooid')
            .order('geplande_datum', ascending: false)
            .limit(3);
        recent = (r as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (e, st) {
        debugPrint('opdracht_planning recent: $e\n$st');
      }

      Map<String, dynamic>? dks;
      try {
        final one = await _client
            .from('dks_rapporten')
            .select()
            .eq('operator_id', uid)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (one != null) {
          dks = Map<String, dynamic>.from(one as Map);
        }
      } catch (_) {
        try {
          final one = await _client
              .from('dks_rapporten')
              .select()
              .eq('operator_id', uid)
              .order('updated_at', ascending: false)
              .limit(1)
              .maybeSingle();
          if (one != null) dks = Map<String, dynamic>.from(one as Map);
        } catch (e2, st2) {
          debugPrint('dks_rapporten operator: $e2\n$st2');
        }
      }

      List<Map<String, dynamic>> vandaag = [];
      try {
        final tv = await _client
            .from('app_operator_vandaag')
            .select()
            .eq('operator_id', uid)
            .order('rooster_starttijd', ascending: true);
        final todayStr =
            DateTime.now().toIso8601String().substring(0, 10);
        for (final row in tv as List) {
          final m = Map<String, dynamic>.from(row as Map);
          final gd = m['geplande_datum']?.toString() ?? '';
          final dateHead =
              gd.length >= 10 ? gd.substring(0, 10) : gd;
          if (dateHead == todayStr) vandaag.add(m);
        }
      } catch (e, st) {
        debugPrint('app_operator_vandaag: $e\n$st');
      }

      if (!mounted) return;
      setState(() {
        _statsRow = stats;
        _recentVoltooid = recent;
        _latestDks = dks;
        _vandaagRows = vandaag;
        _loading = false;
      });
      _fadeCtl.forward(from: 0);
    } catch (e, st) {
      debugPrint('OperatorDashboard._loadDashboardData: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e;
      });
    }
  }

  Map<String, dynamic>? _resolvedVolgendeKlus() {
    final fromStats = _parseVolgendeKlus(_statsRow?['volgende_klus']);
    if (fromStats != null && fromStats.isNotEmpty) return fromStats;
    if (_vandaagRows.isEmpty) return null;
    return _vandaagRows.first;
  }

  double _maandsalaris() =>
      _dashboardStatDouble(_statsRow?['maandsalaris_huidig']);

  double _urenDezeWeekStat() =>
      _dashboardStatDouble(_statsRow?['uren_deze_week']);

  BoxDecoration _softCard({
    Color color = Colors.white,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(_radiusMain),
      border: Border.all(
        color: borderColor ?? Colors.black.withValues(alpha: 0.06),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 32,
          spreadRadius: -4,
          offset: const Offset(0, 18),
        ),
      ],
    );
  }

  BoxDecoration _softCardSub({Color color = Colors.white}) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(_radiusSub),
      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.045),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  void _openRooster() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const OperatorRoosterScreen(),
      ),
    );
  }

  void _openUren() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const OperatorUrenScreen(),
      ),
    );
  }

  void _openMeldingen() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const OperatorMeldingenScreen(),
      ),
    );
  }

  Widget _buildHeroBanner(String voornaam) {
    final String dateString = "Klaar voor je shift?";

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  bottomLeft: Radius.circular(32),
                ),
                image: DecorationImage(
                  image: NetworkImage(
                    'https://images.unsplash.com/photo-1581578731548-c64695cc6952?auto=format&fit=crop&w=1200&q=80',
                  ),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(32),
                    bottomLeft: Radius.circular(32),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF0F172A).withValues(alpha: 0.95),
                      const Color(0xFF0052CC).withValues(alpha: 0.85),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      dateString,
                      style: TextStyle(
                        color: Colors.blue.shade100,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Hoi, $voornaam! 👋',
                        style: GoogleFonts.lato(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_profielfotoUrl != null && _profielfotoUrl!.isNotEmpty)
            Container(
              width: 110,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundImage: NetworkImage(_profielfotoUrl!),
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _nextUpCard(Map<String, dynamic> klus) {
    final t = _safeTime(
      klus['rooster_starttijd'] ??
          klus['geplande_starttijd'] ??
          klus['starttijd'],
    );
    final naam = _bedrijfsnaamFromPlanning(klus);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_radiusMain),
          onTap: _openRooster,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radiusMain),
              gradient: LinearGradient(
                colors: [
                  _coral,
                  _coral.withValues(alpha: 0.88),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _coral.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VOLGENDE OPDRACHT',
                    style: GoogleFonts.lato(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded,
                          color: Colors.white.withValues(alpha: 0.95), size: 22),
                      const SizedBox(width: 8),
                      Text(
                        t,
                        style: GoogleFonts.lato(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          naam,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.lato(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.navigation_rounded,
                        color: Colors.white.withValues(alpha: 0.95),
                        size: 26,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tik om naar het rooster te gaan',
                    style: GoogleFonts.lato(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _verdienstenWideCard() {
    final bedrag = _maandsalaris();
    final monthLabelRaw = _trim(_statsRow?['getoonde_maand_label']);
    final maandForSubtitle = monthLabelRaw.isNotEmpty
        ? monthLabelRaw
        : _maandLabelNl(_statsRow);
    final subtitle = 'Verdiend in $maandForSubtitle';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: _softCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _electricBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: _electricBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Mijn Verdiensten',
                  style: GoogleFonts.lato(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: _deepNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _eur.format(bedrag),
            style: GoogleFonts.lato(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: _deepNavy,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.lato(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekSquareCard() {
    final u = _urenDezeWeekStat();
    final label = u == u.roundToDouble()
        ? '${u.toInt()}'
        : NumberFormat.decimalPattern('nl_NL').format(u);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        decoration: _softCard(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deze week',
              style: GoogleFonts.lato(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: _deepNavy,
              ),
            ),
            const Spacer(),
            Text(
              label,
              style: GoogleFonts.lato(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                color: _electricBlue,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Geregistreerde uren',
              style: GoogleFonts.lato(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dksSquareCard() {
    final raw = _latestDks == null ? null : _dksScoreFromRow(_latestDks!);
    final cijfer = _displayDksCijfer(raw);
    final progress =
        (cijfer == null) ? 0.0 : (cijfer / 10).clamp(0.0, 1.0);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        decoration: _softCard(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kwaliteit',
              style: GoogleFonts.lato(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: _deepNavy,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 86,
                  height: 86,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 86,
                        height: 86,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 6,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Colors.grey.shade200,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(_electricBlue),
                        ),
                      ),
                      Text(
                        cijfer == null ? '—' : NumberFormat.decimalPattern('nl_NL').format(cijfer),
                        style: GoogleFonts.lato(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: _deepNavy,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              'Laatste DKS-score',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickMenuRow() {
    Widget circleBtn({
      required String emoji,
      required String label,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Column(
          children: [
            Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 0,
              shadowColor: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Ink(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: 62,
                    height: 62,
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _deepNavy,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          circleBtn(emoji: '📅', label: 'Rooster', onTap: _openRooster),
          circleBtn(emoji: '💰', label: 'Mijn uren', onTap: _openUren),
          circleBtn(emoji: '⚠️', label: 'Melding', onTap: _openMeldingen),
        ],
      ),
    );
  }

  Widget _recentePrestatieTile(Map<String, dynamic> row) {
    final naam = _bedrijfsnaamFromPlanning(row);
    final raw = row['geplande_datum']?.toString() ?? '';
    final datum = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final uren = _asDouble(row['gewerkte_uren_decimaal']);
    final uStr = uren == uren.roundToDouble()
        ? '${uren.toInt()}'
        : NumberFormat.decimalPattern('nl_NL').format(uren);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: _softCardSub(),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    naam,
                    style: GoogleFonts.lato(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _deepNavy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    datum,
                    style: GoogleFonts.lato(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Geregistreerd',
                  style: GoogleFonts.lato(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  '$uStr u',
                  style: GoogleFonts.lato(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _electricBlue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recente prestaties',
            style: GoogleFonts.lato(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: _deepNavy,
            ),
          ),
          const SizedBox(height: 12),
          if (_recentVoltooid.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: _softCardSub(color: Colors.white),
              child: Text(
                'Nog geen afgeronde diensten om te tonen.',
                style: GoogleFonts.lato(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            )
          else
            ..._recentVoltooid.map(_recentePrestatieTile),
        ],
      ),
    );
  }

  Widget _bentoBlock() {
    final volgende = _resolvedVolgendeKlus();

    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _verdienstenWideCard(),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 164,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _weekSquareCard(),
                  const SizedBox(width: 14),
                  _dksSquareCard(),
                ],
              ),
            ),
          ),
          if (volgende != null) ...[
            const SizedBox(height: 16),
            _nextUpCard(volgende),
          ],
          _quickMenuRow(),
          _recentSection(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final voorNaam = context.watch<UserProvider>().displayFirstName;

    return Scaffold(
      backgroundColor: _pageBg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _deepNavy),
        title: Text(
          'Dashboard',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            letterSpacing: -0.5,
            color: _deepNavy,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Vernieuwen',
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator(radius: 18))
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Kon dashboard niet laden.\n$_loadError',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lato(
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadDashboardData,
                          child: const Text('Opnieuw'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: _electricBlue,
                  onRefresh: _loadDashboardData,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildHeroBanner(voorNaam),
                      ),
                      SliverToBoxAdapter(child: _bentoBlock()),
                    ],
                  ),
                ),
    );
  }
}
