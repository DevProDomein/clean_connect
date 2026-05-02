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
  static const Color _navyHeroStart = Color(0xFF1A237E);
  static const Color _navyHeroEnd = Color(0xFF0052CC);

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

  String _datumLabelNl(DateTime day) {
    final wd = DateFormat.EEEE('nl_NL').format(day);
    final d = DateFormat('d').format(day);
    final m = DateFormat.MMMM('nl_NL').format(day);
    return '${_cap(wd)} $d $m';
  }

  String _cap(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _groet() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Goedemorgen';
    if (h < 18) return 'Goedemiddag';
    return 'Goedenavond';
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
    final today = DateTime.now();
    final displayName = _userName.isNotEmpty
        ? _userName
        : 'Facilitator';
    final afspraken = _agendaVandaag.length;
    final sub = 'Je hebt vandaag $afspraken '
        '${afspraken == 1 ? 'afspraak' : 'afspraken'} gepland staan en '
        '$_ongeplandeTaken openstaande '
        '${_ongeplandeTaken == 1 ? 'taak' : 'taken'} om in te plannen.';

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
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(32),
                              bottomRight: Radius.circular(32),
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                28,
                                24,
                                32,
                              ),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [_navyHeroStart, _navyHeroEnd],
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _datumLabelNl(today),
                                    style: GoogleFonts.lato(
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '${_groet()}, $displayName!',
                                    style: GoogleFonts.lato(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 26,
                                      height: 1.15,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    sub,
                                    style: GoogleFonts.lato(
                                      color:
                                          Colors.white.withValues(alpha: 0.9),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: LayoutBuilder(
                            builder: (context, c) {
                              final wide = c.maxWidth > 620;
                              if (wide) {
                                return Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: _salesCard(),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _planCard(),
                                          const SizedBox(height: 12),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                flex: 2,
                                                child: _kwaliteitDksCard(),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                flex: 1,
                                                child: Column(
                                                  children: [
                                                    _actieveProjectenMetricCard(),
                                                    const SizedBox(height: 12),
                                                    _geplandeKeuringenMetricCard(),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }
                              final narrowStackMetrics = c.maxWidth < 360;
                              return Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  _salesCard(),
                                  const SizedBox(height: 12),
                                  _kwaliteitDksCard(),
                                  const SizedBox(height: 12),
                                  if (narrowStackMetrics) ...[
                                    _actieveProjectenMetricCard(),
                                    const SizedBox(height: 12),
                                    _geplandeKeuringenMetricCard(),
                                  ] else
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _actieveProjectenMetricCard(),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child:
                                              _geplandeKeuringenMetricCard(),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 12),
                                  _planCard(),
                                ],
                              );
                            },
                          ),
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

  Widget _salesCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _softCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Openstaande Offertes',
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: const Color(0xFF475569),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.trending_up_rounded,
                color: Colors.green.shade600,
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${_eur(_pipelineTotaal)},-',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 34,
              color: const Color(0xFF0F172A),
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Verdeeld over $_offerteAantal '
            '${_offerteAantal == 1 ? 'aanvraag' : 'aanvragen'}',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard() {
    final urgent = _ongeplandeTaken > 0;
    final bg =
        urgent ? Colors.red.shade50 : Colors.green.shade50;
    final fg =
        urgent ? Colors.red.shade700 : Colors.green.shade800;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ongeplande Taken',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: fg.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_ongeplandeTaken',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 40,
              color: fg,
              height: 1,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kwaliteitDksCard() {
    final dks = _gemiddeldeDks;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kwaliteit (DKS)',
                  style: GoogleFonts.lato(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Gemiddelde score over alle projecten (laatste 30 dagen).',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            height: 100,
            width: 100,
            child: dks == null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: 0,
                        strokeWidth: 12,
                        backgroundColor: Colors.grey.shade100,
                        color: Colors.grey.shade300,
                        strokeCap: StrokeCap.round,
                      ),
                      Center(
                        child: Text(
                          '—',
                          style: GoogleFonts.lato(
                            fontSize: 22,
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
                      end: (dks / 100).clamp(0.0, 1.0),
                    ),
                    duration: const Duration(milliseconds: 1500),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: value,
                            strokeWidth: 12,
                            backgroundColor: Colors.grey.shade100,
                            color: value >= 0.85
                                ? Colors.greenAccent.shade700
                                : (value >= 0.65
                                    ? Colors.orangeAccent
                                    : Colors.redAccent),
                            strokeCap: StrokeCap.round,
                          ),
                          Center(
                            child: Text(
                              '${(value * 100).toInt()}%',
                              style: GoogleFonts.lato(
                                fontSize: 22,
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
        ],
      ),
    );
  }

  Widget _actieveProjectenMetricCard() {
    const accent = Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.business, color: accent, size: 26),
          const SizedBox(height: 10),
          Text(
            'Actieve Projecten',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$_actieveProjecten',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 28,
              color: const Color(0xFF0F172A),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _geplandeKeuringenMetricCard() {
    final accent = Colors.orange.shade700;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fact_check_outlined, color: accent, size: 26),
          const SizedBox(height: 10),
          Text(
            'Keuringen Gepland',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$_geplandeDks',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 28,
              color: const Color(0xFF0F172A),
              height: 1,
            ),
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
