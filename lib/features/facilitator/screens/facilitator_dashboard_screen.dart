import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../admin/screens/relation_detail_screen.dart';
import 'dks_dashboard_screen.dart';
import 'dks_project_dossier_screen.dart';
import 'planbord_screen.dart';
import 'quote_create_header_screen.dart';
import '../widgets/opname_edit_modal.dart';

/// Apple-style facilitator landing: hero, bento KPIs, quick actions,
/// agenda vandaag. Data loads concurrently via `Future.wait`.
class FacilitatorDashboard extends StatefulWidget {
  const FacilitatorDashboard({super.key});

  @override
  State<FacilitatorDashboard> createState() => _FacilitatorDashboardState();
}

class _FacilitatorDashboardState extends State<FacilitatorDashboard> {
  static const Color _pageBg = Color(0xFFF7F8FB);

  final _scr = ScrollController();

  bool _loading = true;
  bool _hasEverLoaded = false;
  Object? _loadError;

  String _userName = '';

  double _pipelineTotaal = 0;
  int _offerteAantal = 0;
  int _ongeplandeTaken = 0;
  int _actieveProjecten = 0;
  int _geplandeDks = 0;
  double? _gemiddeldeDks;
  List<Map<String, dynamic>> _agendaVandaag = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboardData();
    });
  }

  @override
  void dispose() {
    _scr.dispose();
    super.dispose();
  }

  String _trim(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v == null) {
      return 0;
    }
    if (v is num) {
      return v.toDouble();
    }
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  DateTime _normalizeUtcDate(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day);

  DateTime _todayUtc() =>
      _normalizeUtcDate(DateTime.now());

  DateTime? _parseDayOnly(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) {
      return _normalizeUtcDate(raw);
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    try {
      final p = DateTime.parse(s);
      return _normalizeUtcDate(p.isUtc ? p : p.toUtc());
    } catch (_) {
      return DateTime.tryParse(s) != null
          ? _normalizeUtcDate(DateTime.parse(s))
          : null;
    }
  }

  Future<String> _fetchUserName(String uid) async {
    try {
      final row = await AppSupabase.client
          .from('gebruikers_metadata')
          .select('naam')
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return '';
      return _trim(row['naam']);
    } catch (_) {
      return '';
    }
  }

  /// Sum [totaal_prijs_ex_btw] for open pipeline offertes.
  Future<({double totaal, int count})> _fetchPipeline() async {
    try {
      final res = await AppSupabase.client
          .from('offertes')
          .select('totaal_prijs_ex_btw, status')
          .inFilter('status', const ['concept', 'new', 'send']);
      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      double sum = 0;
      for (final r in list) {
        sum += _asDouble(r['totaal_prijs_ex_btw']);
      }
      return (totaal: sum, count: list.length);
    } catch (_) {
      return (totaal: 0.0, count: 0);
    }
  }

  Future<int> _fetchOngeplandeTaken() async {
    try {
      final res = await AppSupabase.client
          .from('opdrachten')
          .select('id')
          .eq('status', 'open');
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  double? _scoreFromRow(Map<String, dynamic> r) {
    for (final k in const [
      'score_percentage',
      'score_definitief',
      'score_voorgesteld',
    ]) {
      final v = r[k];
      if (v != null) {
        return _asDouble(v);
      }
    }
    return null;
  }

  DateTime? _rapportDatumOf(Map<String, dynamic> r) {
    for (final k in const [
      'aangemaakt_op',
      'updated_at',
      'created_at',
      'datum_definitief',
    ]) {
      final d = DateTime.tryParse(_trim(r[k]));
      if (d != null) return d;
    }
    return null;
  }

  Future<int> _fetchActieveProjecten() async {
    try {
      final res = await AppSupabase.client
          .from('projecten')
          .select('id')
          .eq('status', 'actief');
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _fetchGeplandeDksCount() async {
    try {
      final res = await AppSupabase.client
          .from('dks_rapporten')
          .select('id')
          .eq('status', 'gepland');
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<double?> _fetchGemiddeldeDks30d() async {
    try {
      final res = await AppSupabase.client
          .from('dks_rapporten')
          .select()
          .eq('status', 'definitief');
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) {
            final d = _rapportDatumOf(r);
            return d != null && d.isAfter(cutoff);
          })
          .toList();
      final scores = list.map(_scoreFromRow).whereType<double>().toList();
      if (scores.isEmpty) return null;
      return scores.reduce((a, b) => a + b) / scores.length;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAgendaVandaag(
    String uid,
    String todayIso,
    DateTime todayNorm,
  ) async {
    try {
      final res = await AppSupabase.client
          .from('app_facilitator_persoonlijke_agenda')
          .select()
          .eq('toegewezen_aan_id', uid)
          .eq('datum', todayIso);
      var list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (list.isEmpty) {
        final res2 = await AppSupabase.client
            .from('app_facilitator_persoonlijke_agenda')
            .select()
            .eq('toegewezen_aan_id', uid);
        final all = (res2 as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        list = all.where((r) {
          for (final k in const [
            'geplande_datum',
            'agenda_datum',
            'datum',
            'start_datum',
          ]) {
            final day = _parseDayOnly(r[k]);
            if (day != null && day == todayNorm) {
              return true;
            }
          }
          return false;
        }).toList();
      }
      list.sort((a, b) {
        return _timeSortKey(_timeStart(a)).compareTo(
          _timeSortKey(_timeStart(b)),
        );
      });
      return list;
    } catch (_) {
      return const [];
    }
  }

  int _timeSortKey(String s) {
    final p = s.split(':');
    if (p.length >= 2) {
      final h = int.tryParse(p[0]) ?? 0;
      final m = int.tryParse(p[1]) ?? 0;
      return h * 60 + m;
    }
    return 0;
  }

  String _timeFrom(
    Map<String, dynamic> r, {
    required List<String> keys,
  }) {
    for (final k in keys) {
      final s = _trim(r[k]);
      if (s.isEmpty) continue;
      if (s.length >= 5 && s.contains(':')) {
        return s.substring(0, 5);
      }
      return s;
    }
    return '—';
  }

  String _timeStart(Map<String, dynamic> r) {
    return _timeFrom(
      r,
      keys: const [
        'tijdslot_start',
        'starttijd',
        'start_tijd',
        'begin_tijd',
        'tijd_van',
      ],
    );
  }

  String _timeEnd(Map<String, dynamic> r) {
    return _timeFrom(
      r,
      keys: const [
        'tijdslot_eind',
        'eindtijd',
        'eind_tijd',
        'einde_tijd',
        'tijd_tot',
      ],
    );
  }

  String _afspraakType(Map<String, dynamic> r) {
    final primary = _trim(r['afspraak_type']).toLowerCase();
    if (primary == 'dks') return 'dks';
    if (primary == 'opname') return 'opname';
    for (final k in const ['type', 'soort']) {
      final s = _trim(r[k]).toLowerCase();
      if (s == 'dks' || s.contains('dks')) return 'dks';
      if (s == 'opname' ||
          s.contains('opname') ||
          s.contains('sales')) {
        return 'opname';
      }
    }
    return 'opname';
  }

  String _titelOf(Map<String, dynamic> r) {
    for (final k in const [
      'titel',
      'project_naam',
      'bedrijfsnaam',
      'naam',
      'omschrijving',
    ]) {
      final s = _trim(r[k]);
      if (s.isNotEmpty) return s;
    }
    return 'Afspraak';
  }

  String _locatieOf(Map<String, dynamic> r) {
    for (final k in const ['adres', 'adres_volledig']) {
      final s = _trim(r[k]);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// No `async` closures inside `setState`: awaited work happens first.
  Future<void> _loadDashboardData() async {
    final user = AppSupabase.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasEverLoaded = true;
          _loadError = 'Niet ingelogd.';
        });
      }
      return;
    }

    final uid = user.id;
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    setState(() {
      _loading = true;
      _loadError = null;
    });

    dynamic asyncErr;
    String na = '';
    double pipe = 0;
    int qa = 0;
    var taken = 0;
    var actiefProj = 0;
    var geplandeKeuringen = 0;
    double? dksAvg;
    List<Map<String, dynamic>> agenda = const [];

    try {
      await Future.wait<void>([
        () async {
          na = await _fetchUserName(uid);
        }(),
        () async {
          final p = await _fetchPipeline();
          pipe = p.totaal;
          qa = p.count;
        }(),
        () async {
          taken = await _fetchOngeplandeTaken();
        }(),
        () async {
          actiefProj = await _fetchActieveProjecten();
        }(),
        () async {
          geplandeKeuringen = await _fetchGeplandeDksCount();
        }(),
        () async {
          dksAvg = await _fetchGemiddeldeDks30d();
        }(),
        () async {
          agenda = await _fetchAgendaVandaag(
            uid,
            todayStr,
            _todayUtc(),
          );
        }(),
      ]);
    } catch (e) {
      asyncErr = e;
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
      _hasEverLoaded = true;
      _loadError = asyncErr;
      _userName = na.isNotEmpty ? na : '';
      _pipelineTotaal = pipe;
      _offerteAantal = qa;
      _ongeplandeTaken = taken;
      _actieveProjecten = actiefProj;
      _geplandeDks = geplandeKeuringen;
      _gemiddeldeDks = dksAvg;
      _agendaVandaag = agenda;
    });
  }

  String _eur(double v) {
    final f = NumberFormat.currency(
      locale: 'nl_NL',
      symbol: '€',
      decimalDigits: 0,
    );
    return f.format(v);
  }

  BoxDecoration _softCard({Color? color}) {
    return BoxDecoration(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  void _onAgendaTap(Map<String, dynamic> item) {
    final t = _afspraakType(item);
    if (t == 'dks') {
      final pid = item['project_id'];
      if (pid != null && _trim(pid).isNotEmpty) {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => DksProjectDossierScreen(
              projectId: _trim(pid),
              projectNaam: _titelOf(item).isNotEmpty ? _titelOf(item) : 'Project',
            ),
          ),
        ).then((_) {
          _loadDashboardData();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Geen project_id gevonden voor deze DKS afspraak.',
            ),
          ),
        );
      }
      return;
    }

    for (final k in const ['bedrijf_id', 'klant_id']) {
      final v = item[k];
      if (v != null && _trim(v).isNotEmpty) {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => RelationDetailScreen(
              bedrijfId: _trim(v),
              initialTabIndex: 0,
            ),
          ),
        ).then((_) => _loadDashboardData());
        return;
      }
    }

    final aid = item['id'];
    if (aid != null && _trim(aid).isNotEmpty) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => OpnameEditModal(
          afspraakId: _trim(aid),
          onSaved: () {
            if (mounted) {
              _loadDashboardData();
            }
          },
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Geen relatie gekoppeld — open de agenda om details te bewerken.',
        ),
      ),
    );
  }

  void _goRelationNew() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const RelationDetailScreen(
          bedrijfId: null,
          createAsKlant: true,
        ),
      ),
    );
  }

  void _goQuoteNew() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const QuoteCreateHeaderScreen(),
      ),
    );
  }

  void _goPlanbord() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const PlanbordScreen(),
      ),
    );
  }

  void _goDks() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const DksDashboardScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName = _userName.isNotEmpty
        ? _userName
        : 'Facilitator';

    final showBlockingLoader = _loading && !_hasEverLoaded;

    return Scaffold(
      backgroundColor: _pageBg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Facilitator Portal',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            color: const Color(0xFF0F172A),
          ),
        ),
      ),
      body: showBlockingLoader
          ? const Center(
              child: CupertinoActivityIndicator(radius: 18),
            )
          : RefreshIndicator(
                  onRefresh: _loadDashboardData,
                  child: CustomScrollView(
                    controller: _scr,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildHeroBanner(context, displayName),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          8,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _loadError != null
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    'Waarschuwing bij laden: $_loadError',
                                    style: GoogleFonts.lato(
                                      color: cs.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.only(top: 0),
                        sliver: SliverToBoxAdapter(
                          child: _buildAnalyticsGrid(),
                        ),
                      ),
                      SliverPadding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 28, 16, 8),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            'Snel Acties',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _quickActions(),
                      ),
                      SliverPadding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 28, 16, 12),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            'Agenda voor Vandaag',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _buildAgendaSection(cs),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    ],
                  ),
                ),
    );
  }

  static const String _heroPhotoUrl =
      'https://images.unsplash.com/photo-1497366216548-37526070297c?auto=format&fit=crop&w=1200&q=80';

  Widget _buildHeroBanner(BuildContext context, String userName) {
    const String dateString = 'Welkom terug op kantoor';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        image: DecorationImage(
          image: const NetworkImage(_heroPhotoUrl),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.55),
            BlendMode.darken,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              dateString,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Goedemorgen, $userName! 👋',
              style: GoogleFonts.lato(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth >= 720;
        const gap = 12.0;
        const scrollCardWidth = 260.0;

        final salesCard = _buildKpiCard(
          title: 'Openstaande Offertes',
          value: _eur(_pipelineTotaal),
          icon: Icons.trending_up,
          color: Colors.blueAccent,
          subtitle:
              'Potentiële omzet · $_offerteAantal '
              '${_offerteAantal == 1 ? 'offerte' : 'offertes'}',
        );

        final warn = _ongeplandeTaken > 0;
        final operatieColor =
            warn ? Colors.orangeAccent : Colors.green;
        final operatieCard = _buildKpiCard(
          title: 'Actieve Projecten',
          value: '$_actieveProjecten',
          icon: Icons.business_center,
          color: operatieColor,
          subtitle: warn
              ? '$_ongeplandeTaken taken ongepland! · $_geplandeDks gepland'
              : 'Alles ingepland · $_geplandeDks keuringen gepland',
          warning: warn,
        );

        final dksCard = _buildDksCard();

        if (useRow) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: salesCard),
                const SizedBox(width: gap),
                Expanded(child: operatieCard),
                const SizedBox(width: gap),
                Expanded(child: dksCard),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: scrollCardWidth, child: salesCard),
              const SizedBox(width: gap),
              SizedBox(width: scrollCardWidth, child: operatieCard),
              const SizedBox(width: gap),
              SizedBox(width: scrollCardWidth, child: dksCard),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
    bool warning = false,
  }) {
    return Container(
      height: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: warning
            ? Border.all(
                color: color.withValues(alpha: 0.5),
                width: 2,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.lato(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade700,
                  height: 1.2,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.lato(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      warning ? FontWeight.bold : FontWeight.normal,
                  color: warning ? color : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDksCard() {
    final dks = _gemiddeldeDks;
    final double scoreNorm = dks != null
        ? (dks / 100.0).clamp(0.0, 1.0)
        : 0.0;
    final Color scoreColor = dks == null
        ? Colors.grey.shade400
        : (scoreNorm >= 0.85
            ? Colors.green
            : (scoreNorm >= 0.65 ? Colors.orange : Colors.redAccent));

    return Container(
      height: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'DKS Score',
            style: GoogleFonts.lato(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(
            height: 70,
            width: 70,
            child: dks == null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: 0,
                        strokeWidth: 8,
                        backgroundColor: Colors.grey.shade100,
                        color: Colors.grey.shade300,
                        strokeCap: StrokeCap.round,
                      ),
                      Center(
                        child: Text(
                          '—',
                          style: GoogleFonts.lato(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  )
                : TweenAnimationBuilder<double>(
                    key: ValueKey<double>(dks),
                    tween: Tween<double>(
                      begin: 0,
                      end: scoreNorm,
                    ),
                    duration: const Duration(milliseconds: 1500),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: value,
                            strokeWidth: 8,
                            backgroundColor: Colors.grey.shade100,
                            color: scoreColor,
                            strokeCap: StrokeCap.round,
                          ),
                          Center(
                            child: Text(
                              '${(value * 100).toInt()}%',
                              style: GoogleFonts.lato(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Text(
            'Laatste 30 dagen',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    final items =
        <({String label, Color accent, IconData icon, VoidCallback onTap})>[
      (
        label: '+ Nieuwe Relatie',
        accent: const Color(0xFF2563EB),
        icon: Icons.person_add_alt_1_rounded,
        onTap: _goRelationNew,
      ),
      (
        label: '+ Nieuwe Offerte',
        accent: const Color(0xFFFF9800),
        icon: Icons.request_quote_rounded,
        onTap: _goQuoteNew,
      ),
      (
        label: 'Planbord Openen',
        accent: const Color(0xFF43A047),
        icon: Icons.view_kanban_rounded,
        onTap: _goPlanbord,
      ),
      (
        label: 'Ad-hoc Kwaliteitscontrole',
        accent: const Color(0xFF7E57C2),
        icon: Icons.verified_outlined,
        onTap: _goDks,
      ),
    ];
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: items.length,
        separatorBuilder: (context, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final it = items[i];
          final accent = it.accent;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: it.onTap,
              child: Container(
                width: 154,
                padding: const EdgeInsets.all(14),
                decoration: _softCard(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        it.icon,
                        color: accent,
                        size: 24,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      it.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.lato(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: const Color(0xFF0F172A),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAgendaSection(ColorScheme cs) {
    if (_agendaVandaag.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: _softCard(),
        child: Column(
          children: [
            Icon(
              Icons.local_cafe_rounded,
              size: 48,
              color: cs.primary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              'Geen afspraken meer vandaag.',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tijd om het planbord bij te werken!',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _agendaVandaag.map((e) {
        final dks = _afspraakType(e) == 'dks';
        final accent = dks
            ? const Color(0xFFFF6B35)
            : const Color(0xFF2563EB);
        final start = _timeStart(e);
        final end = _timeEnd(e);
        final loc = _locatieOf(e);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _onAgendaTap(e),
              child: Container(
                decoration: _softCard(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          bottomLeft: Radius.circular(24),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$start – $end',
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _titelOf(e),
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  if (loc.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      loc,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.lato(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: cs.onSurface.withValues(alpha: 0.35),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
