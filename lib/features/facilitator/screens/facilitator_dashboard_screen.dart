import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/contracts/tickets_contract.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../admin/screens/relation_detail_screen.dart';
import 'dks_dashboard_screen.dart';
import 'dks_project_dossier_screen.dart';
import 'planbord_screen.dart';
import 'project_overview_screen.dart';
import 'quote_create_header_screen.dart';
import 'quote_overview_screen.dart';
import 'sales_centre_screen.dart';
import 'ticket_overview_screen.dart';
import '../widgets/opname_edit_modal.dart';

/// Apple-style facilitator landing: hero, bento KPIs, quick actions,
/// agenda vandaag. Data loads concurrently via `Future.wait`.
class FacilitatorDashboard extends StatefulWidget {
  const FacilitatorDashboard({super.key});

  @override
  State<FacilitatorDashboard> createState() => _FacilitatorDashboardState();
}

class _FacilitatorDashboardState extends State<FacilitatorDashboard> {
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
  int _nieuweLeads = 0;
  int _openTickets = 0;
  double? _gemiddeldeDks;
  List<Map<String, dynamic>> _agendaVandaag = const [];
  List<String> _chartProjectNamen = const [];
  String? _profielfotoUrl;
  int _touchedProjectIndex = -1;

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

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour <= 11) return 'Goedemorgen';
    if (hour >= 12 && hour <= 17) return 'Goedemiddag';
    return 'Goedenavond';
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

  /// Open leads: jouw toewijzing óf ongeclaimd, exclusief gewonnen/verloren.
  Future<int> _fetchLeadsCount(String uid) async {
    try {
      final res = await AppSupabase.client
          .from('leads')
          .select('id')
          .not('status', 'in', '("gewonnen","verloren")')
          .or('toegewezen_aan_id.eq.$uid,toegewezen_aan_id.is.null');
      return (res as List).length;
    } catch (_) {
      try {
        final res = await AppSupabase.client
            .from('leads')
            .select('id,status,toegewezen_aan_id')
            .or('toegewezen_aan_id.eq.$uid,toegewezen_aan_id.is.null');
        return (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((r) {
              final st = _trim(r['status']).toLowerCase();
              return st != 'gewonnen' && st != 'verloren';
            })
            .length;
      } catch (_) {
        return 0;
      }
    }
  }

  /// Open tickets voor deze gebruiker (status open / in behandeling).
  Future<int> _fetchOpenTicketsCount(String uid) async {
    try {
      final res = await AppSupabase.client
          .from(TicketsTable.name)
          .select('${TicketsTable.id},${TicketsTable.status}')
          .eq(TicketsTable.toegewezenAan, uid);
      final openish = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) {
            final s = _trim(r[TicketsTable.status]).toLowerCase();
            return s == 'open' ||
                s == 'in_behandeling' ||
                s == 'nieuw' ||
                s == 'new';
          })
          .length;
      return openish;
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
    var leadsCount = 0;
    var ticketsOpen = 0;
    double? dksAvg;
    List<Map<String, dynamic>> agenda = const [];
    List<String> chartNamen = const [];
    String? profielfoto;

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
          try {
            final chartProjects = await AppSupabase.client
                .from('projecten')
                .select('project_naam')
                .eq('status', 'actief')
                .eq('facilitator_id', uid)
                .limit(4);
            chartNamen = (chartProjects as List<dynamic>)
                .map((p) => _trim(Map<String, dynamic>.from(p as Map)['project_naam']))
                .where((s) => s.isNotEmpty)
                .take(4)
                .toList();
          } catch (_) {
            chartNamen = [];
          }
        }(),
        () async {
          try {
            final row = await AppSupabase.client
                .from('gebruikers')
                .select('profielfoto_url')
                .eq('id', uid)
                .maybeSingle();
            if (row != null) {
              final m = Map<String, dynamic>.from(row as Map);
              final u = _trim(m['profielfoto_url']);
              profielfoto = u.isEmpty ? null : u;
            }
          } catch (_) {
            profielfoto = null;
          }
        }(),
        () async {
          geplandeKeuringen = await _fetchGeplandeDksCount();
        }(),
        () async {
          leadsCount = await _fetchLeadsCount(uid);
        }(),
        () async {
          ticketsOpen = await _fetchOpenTicketsCount(uid);
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
      _nieuweLeads = leadsCount;
      _openTickets = ticketsOpen;
      _gemiddeldeDks = dksAvg;
      _agendaVandaag = agenda;
      _chartProjectNamen = chartNamen;
      _profielfotoUrl = profielfoto;
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

  BoxDecoration _softCard(BuildContext context, {Color? color}) {
    return BoxDecoration(
      color: color ?? Theme.of(context).cardColor,
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
        builder: (_) => SelectionArea(
          child: OpnameEditModal(
            afspraakId: _trim(aid),
            onSaved: () {
              if (mounted) {
                _loadDashboardData();
              }
            },
          ),
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
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final onBody = textTheme.bodyLarge?.color;
    final displayName = _userName.isNotEmpty
        ? _userName
        : 'Facilitator';

    final showBlockingLoader = _loading && !_hasEverLoaded;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Facilitator Portal',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            color: onBody,
          ),
        ),
      ),
      body: SelectionArea(
        child: showBlockingLoader
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
                        child: _buildAnalyticsGrid(context),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Snel Acties',
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: onBody,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _quickActions(),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Agenda voor Vandaag',
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: onBody,
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
      ),
    );
  }

  static const String _heroPhotoUrl =
      'https://images.unsplash.com/photo-1497366216548-37526070297c?auto=format&fit=crop&w=1200&q=80';

  Widget _buildHeroBanner(BuildContext context, String userName) {
    final String dateString = 'Welkom terug op kantoor';
    final bool showAvatar =
        _profielfotoUrl != null && _profielfotoUrl!.isNotEmpty;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
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
              decoration: BoxDecoration(
                borderRadius: showAvatar
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(32),
                        bottomLeft: Radius.circular(32),
                      )
                    : BorderRadius.circular(32),
                image: const DecorationImage(
                  image: NetworkImage(_heroPhotoUrl),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: showAvatar
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(32),
                          bottomLeft: Radius.circular(32),
                        )
                      : BorderRadius.circular(32),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF0F172A).withValues(alpha: 0.95),
                      const Color(0xFF0052CC).withValues(alpha: 0.85),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      dateString,
                      style: TextStyle(
                        color: Colors.blue.shade100,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_getGreeting()}, $userName! 👋',
                        style: GoogleFonts.lato(
                          color: Colors.white,
                          fontSize: 28,
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
          if (showAvatar)
            Container(
              width: 120,
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF1E1F22)
                    : const Color(0xFF0F172A),
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
                    radius: 36,
                    backgroundColor: Colors.transparent,
                    backgroundImage: NetworkImage(_profielfotoUrl!),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openDashboardPage(Widget page) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  Widget _buildAnalyticsGrid(BuildContext context) {
    const double squareHeight = 175.0;
    const double spacing = 16.0;
    final double tallHeight = (squareHeight * 2) + spacing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildWideKpiCard(
            title: 'Openstaande Offertes',
            value: _eur(_pipelineTotaal),
            icon: Icons.trending_up,
            color: Colors.blueAccent,
            subtitle:
                'Potentiële omzet in pijplijn · $_offerteAantal offertes',
            onTap: () =>
                _openDashboardPage(const QuoteOverviewScreen()),
          ),
          const SizedBox(height: spacing),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSquareKpiCard(
                      title: 'Ongeplande Taken',
                      value: '$_ongeplandeTaken',
                      icon: Icons.calendar_today_rounded,
                      color: _ongeplandeTaken > 0
                          ? Colors.orangeAccent
                          : Colors.grey,
                      subtitle: 'Wacht op inplanning',
                      warning: _ongeplandeTaken > 0,
                      height: squareHeight,
                      onTap: () =>
                          _openDashboardPage(const PlanbordScreen()),
                    ),
                    const SizedBox(height: spacing),
                    _buildSquareKpiCard(
                      title: 'Nieuwe Leads',
                      value: '$_nieuweLeads',
                      icon: Icons.campaign_outlined,
                      color: Colors.purpleAccent,
                      subtitle: 'Openstaande leads',
                      height: squareHeight,
                      belowValue: _buildLeadsNeonProgressBar(),
                      onTap: () =>
                          _openDashboardPage(const SalesCentreScreen()),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: spacing),
              Expanded(
                flex: 4,
                child: _buildActieveProjectenCard(
                  height: tallHeight,
                  onTap: () => _openDashboardPage(
                    const ProjectOverviewScreen(),
                  ),
                ),
              ),
              const SizedBox(width: spacing),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDksCard(height: squareHeight),
                    const SizedBox(height: spacing),
                    _buildSquareKpiCard(
                      title: 'Open Tickets',
                      value: '$_openTickets',
                      icon: Icons.warning_amber_rounded,
                      color: _openTickets > 0
                          ? Colors.redAccent
                          : Colors.grey,
                      subtitle: 'Klantmeldingen',
                      warning: _openTickets > 0,
                      height: squareHeight,
                      onTap: () => _openDashboardPage(
                        const TicketOverviewScreen(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWideKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final subtitleColor = textTheme.bodyMedium?.color ??
        textTheme.bodyLarge?.color?.withValues(alpha: 0.6);
    final titleColor = textTheme.bodyLarge?.color?.withValues(alpha: 0.7);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: GoogleFonts.lato(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }

  double get _leadsOpenBarFactor {
    if (_nieuweLeads <= 0) return 0.06;
    return math.min(_nieuweLeads / 25.0, 1.0);
  }

  Widget _buildLeadsNeonProgressBar() {
    final purple = Colors.purpleAccent;
    final deep = Colors.deepPurple;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      height: 12,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: _leadsOpenBarFactor,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              colors: [purple, deep],
            ),
            boxShadow: [
              BoxShadow(
                color: purple.withValues(alpha: 0.85),
                blurRadius: 14,
                spreadRadius: 2,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: deep.withValues(alpha: 0.55),
                blurRadius: 22,
                spreadRadius: 1,
                offset: Offset.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSquareKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
    bool warning = false,
    required double height,
    Widget? belowValue,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final titleColor = textTheme.bodyLarge?.color?.withValues(alpha: 0.75);
    final subtitleColor = textTheme.bodyMedium?.color ??
        textTheme.bodyLarge?.color?.withValues(alpha: 0.6);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          height: height,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(24),
            border: warning
                ? Border.all(
                    color: color.withValues(alpha: 0.5),
                    width: 2,
                  )
                : Border.all(color: Colors.transparent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: GoogleFonts.lato(
                          fontSize: belowValue != null ? 24 : 28,
                          fontWeight: FontWeight.w900,
                          color: textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                    ?belowValue,
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: warning
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: warning ? color : subtitleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActieveProjectenCard({
    required double height,
    VoidCallback? onTap,
  }) {
    final screenW = MediaQuery.of(context).size.width;
    final isCompact = screenW < 600;
    final touchedRadius = isCompact ? 60.0 : 85.0;
    final baseRadius = isCompact ? 40.0 : 55.0;
    final centerSpace = isCompact ? 34.0 : 40.0;
    final touchedBorderW = isCompact ? 3.0 : 4.0;
    final baseBorderW = isCompact ? 1.5 : 2.0;

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final titleColor = textTheme.bodyLarge?.color?.withValues(alpha: 0.75);
    final subtitleColor = textTheme.bodyMedium?.color ??
        textTheme.bodyLarge?.color?.withValues(alpha: 0.6);
    const colors = <Color>[
      Colors.blueAccent,
      Colors.greenAccent,
      Colors.orangeAccent,
      Colors.purpleAccent,
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          height: height,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            color: theme.cardColor,
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Actieve Projecten',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_forward_ios,
                        size: 18,
                      ),
                      onPressed: onTap,
                      tooltip: 'Bekijk alle projecten',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback:
                              (FlTouchEvent event, pieTouchResponse) {
                            setState(() {
                              if (!event.isInterestedForInteractions ||
                                  pieTouchResponse == null ||
                                  pieTouchResponse.touchedSection == null) {
                                _touchedProjectIndex = -1;

                                if (event is FlTapUpEvent) {
                                  onTap?.call();
                                }
                                return;
                              }
                              _touchedProjectIndex = pieTouchResponse
                                  .touchedSection!.touchedSectionIndex;
                            });
                          },
                        ),
                          borderData: FlBorderData(show: false),
                          sectionsSpace: 4,
                          centerSpaceRadius: centerSpace,
                          sections: List.generate(4, (i) {
                            final isTouched = i == _touchedProjectIndex;
                            final radius =
                                isTouched ? touchedRadius : baseRadius;
                            final color = colors[i % colors.length];
                            final projName = _chartProjectNamen.length > i
                                ? _chartProjectNamen[i]
                                : 'Project';
                            final displayTitle = projName.length > 12
                                ? '${projName.substring(0, 12)}..'
                                : projName;
                            return PieChartSectionData(
                              color: color,
                              value: 25,
                              title: isTouched ? displayTitle : '',
                              radius: radius,
                              titleStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              borderSide: isTouched
                                  ? BorderSide(
                                      color: color.withValues(alpha: 0.55),
                                      width: touchedBorderW,
                                    )
                                  : BorderSide(
                                      color: color.withValues(alpha: 0.35),
                                      width: baseBorderW,
                                    ),
                            );
                          }),
                        ),
                      ),
                    IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_actieveProjecten',
                            style: GoogleFonts.lato(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: textTheme.bodyLarge?.color,
                              height: 1.05,
                            ),
                          ),
                          Text(
                            'projecten',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: subtitleColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Lopende contracten',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: subtitleColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDksCard({required double height}) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final titleColor = textTheme.bodyLarge?.color?.withValues(alpha: 0.75);
    final subtitleColor = textTheme.bodyMedium?.color ??
        textTheme.bodyLarge?.color?.withValues(alpha: 0.6);
    final double? dks = _gemiddeldeDks;
    final double scoreNorm = dks == null
        ? 0.0
        : (dks / 100.0).clamp(0.0, 1.0);
    final Color scoreColor = dks == null
        ? Colors.grey
        : (scoreNorm >= 0.85
            ? Colors.green
            : (scoreNorm >= 0.65
                ? Colors.orange
                : Colors.redAccent));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDashboardPage(const DksDashboardScreen()),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          height: height,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
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
            children: [
              Text(
                'DKS Score',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
              Expanded(
                child: Center(
                  child: dks == null
                      ? SizedBox(
                          height: 80,
                          width: 80,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CircularProgressIndicator(
                                value: 0,
                                strokeWidth: 12,
                                backgroundColor: theme.dividerColor
                                    .withValues(alpha: 0.25),
                                color: theme.dividerColor
                                    .withValues(alpha: 0.7),
                                strokeCap: StrokeCap.round,
                              ),
                              Center(
                                child: Text(
                                  '—',
                                  style: GoogleFonts.lato(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: textTheme.bodyLarge?.color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                            begin: 0.0,
                            end: scoreNorm,
                          ),
                          duration: const Duration(milliseconds: 1500),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return SizedBox(
                              height: 80,
                              width: 80,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CircularProgressIndicator(
                                    value: value,
                                    strokeWidth: 12,
                                    backgroundColor: theme.dividerColor
                                        .withValues(alpha: 0.25),
                                    color: scoreColor,
                                    strokeCap: StrokeCap.round,
                                  ),
                                  Center(
                                    child: Text(
                                      '${(value * 100).toInt()}%',
                                      style: GoogleFonts.lato(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
              Text(
                'Laatste 30 dagen · $_geplandeDks gepland',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: subtitleColor,
                ),
              ),
            ],
          ),
        ),
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
          final theme = Theme.of(context);
          final onBody = theme.textTheme.bodyLarge?.color;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: it.onTap,
              child: Container(
                width: 154,
                padding: const EdgeInsets.all(14),
                decoration: _softCard(context),
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
                        color: onBody,
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
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final onBody = textTheme.bodyLarge?.color;
    final onMuted = textTheme.bodyMedium?.color ??
        textTheme.bodyLarge?.color?.withValues(alpha: 0.6);
    if (_agendaVandaag.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: _softCard(context),
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
                color: onBody,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tijd om het planbord bij te werken!',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: onMuted,
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
                decoration: _softCard(context),
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
                                      color: onMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _titelOf(e),
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      color: onBody,
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
                                        color: onMuted,
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
