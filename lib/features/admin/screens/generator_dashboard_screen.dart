import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/contracts/tickets_contract.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../facilitator/screens/hr_beheer_screen.dart';
import '../../facilitator/screens/planbord_screen.dart';
import '../../facilitator/screens/project_overview_screen.dart';
import '../../facilitator/screens/quote_create_header_screen.dart';
import '../../facilitator/screens/quote_overview_screen.dart';
import '../../facilitator/screens/relations_crm_screen.dart';
import '../../facilitator/screens/ticket_overview_screen.dart';
import 'invoice_bulk_run_screen.dart';
import 'salaris_administratie_screen.dart';
import 'uren_accorderen_screen.dart';

/// Apple-stijl controlecentrum voor Generator / beheerder.
class GeneratorDashboardScreen extends StatefulWidget {
  const GeneratorDashboardScreen({super.key});

  @override
  State<GeneratorDashboardScreen> createState() => _GeneratorDashboardScreenState();
}

class _GeneratorDashboardScreenState extends State<GeneratorDashboardScreen> {
  static const String _headerImageUrl =
      'https://images.unsplash.com/photo-1556761175-5973dc0f32e7?q=80&w=1600&auto=format&fit=crop';

  bool _loading = true;
  Object? _loadError;

  int _meldingenOpen = 0;
  int _teAccorderenUren = 0;
  int _teAccorderenOperators = 0;
  int _planbordOngepland7d = 0;
  int _actieveProjecten = 0;
  int _conceptFacturen = 0;
  int _openOffertes = 0;
  double _openOffertesWaarde = 0;
  int _salarisOperatorsOpen = 0;
  String _salarisSubtitle = '';
  List<_DashboardAlert> _alerts = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDashboardData());
  }

  String _trim(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  DateTime? _parseDayOnly(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) {
      return DateTime(raw.year, raw.month, raw.day);
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final head = s.length >= 10 ? s.substring(0, 10) : s;
    return DateTime.tryParse(head) != null
        ? DateTime.parse(head)
        : DateTime.tryParse(s);
  }

  String _maandSleutel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour <= 11) return 'Goedemorgen';
    if (hour >= 12 && hour <= 17) return 'Goedemiddag';
    return 'Goedenavond';
  }

  String _eurCompact(double v) {
    if (v >= 1000) {
      return '€ ${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
    }
    return NumberFormat.currency(
      locale: 'nl_NL',
      symbol: '€',
      decimalDigits: 0,
    ).format(v);
  }

  List<double> _sparkline(int end) {
    if (end <= 0) return List<double>.filled(7, 0);
    return List<double>.generate(7, (i) {
      final t = (i + 1) / 7;
      return (end * t).clamp(0, end.toDouble()).toDouble();
    });
  }

  bool _ticketIsOpen(Map<String, dynamic> r) {
    final s = _trim(r[TicketsTable.status]).toLowerCase();
    return s == 'open' ||
        s == 'in_behandeling' ||
        s == 'nieuw' ||
        s == 'new';
  }

  Future<int> _fetchOpenTicketsCount() async {
    try {
      final res = await AppSupabase.client
          .from(TicketsTable.name)
          .select('${TicketsTable.id}, ${TicketsTable.status}');
      return (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where(_ticketIsOpen)
          .length;
    } catch (_) {
      return 0;
    }
  }

  Future<({int uren, int operators})> _fetchTeAccorderen() async {
    try {
      final res = await AppSupabase.client
          .from('opdracht_planning')
          .select('operator_id, uren_status')
          .eq('uren_status', 'ingediend');
      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final ops = list
          .map((r) => _trim(r['operator_id']))
          .where((id) => id.isNotEmpty)
          .toSet();
      return (uren: list.length, operators: ops.length);
    } catch (_) {
      return (uren: 0, operators: 0);
    }
  }

  Future<int> _fetchOngeplandBinnen7Dagen() async {
    try {
      final today = DateTime.now();
      final horizon = today.add(const Duration(days: 7));
      final res = await AppSupabase.client
          .from('opdrachten')
          .select('id, geplande_datum')
          .eq('status', 'open');
      return (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) {
            final d = _parseDayOnly(r['geplande_datum']);
            if (d == null) return true;
            final day = DateTime(d.year, d.month, d.day);
            return !day.isAfter(horizon);
          })
          .length;
    } catch (_) {
      return 0;
    }
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

  Future<int> _fetchConceptFacturen() async {
    try {
      final res = await AppSupabase.client
          .from('facturen')
          .select('id')
          .eq('status', 'concept');
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<({int count, double waarde})> _fetchOpenOffertes() async {
    try {
      final res = await AppSupabase.client
          .from('offertes')
          .select('totaal_prijs_ex_btw, status')
          .inFilter('status', const ['concept', 'new', 'send']);
      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      var sum = 0.0;
      for (final r in list) {
        sum += _asDouble(r['totaal_prijs_ex_btw']);
      }
      return (count: list.length, waarde: sum);
    } catch (_) {
      return (count: 0, waarde: 0.0);
    }
  }

  Future<({int count, String subtitle})> _fetchSalarisRunStatus() async {
    final now = DateTime.now();
    final sleutel = _maandSleutel(now);
    final maandNaam = DateFormat('MMMM', 'nl_NL').format(now);
    try {
      final planningRes = await AppSupabase.client
          .from('opdracht_planning')
          .select('operator_id, uren_status, geplande_datum, doorgeschoven_naar_maand')
          .eq('uren_status', 'geaccordeerd');
      final geaccIds = <String>{};
      for (final raw in planningRes as List) {
        final r = Map<String, dynamic>.from(raw as Map);
        final id = _trim(r['operator_id']);
        if (id.isEmpty) continue;
        final verschoven = _trim(r['doorgeschoven_naar_maand']);
        if (verschoven.isNotEmpty) {
          if (verschoven == sleutel) geaccIds.add(id);
          continue;
        }
        final d = _parseDayOnly(r['geplande_datum']);
        if (d != null &&
            d.year == now.year &&
            d.month == now.month) {
          geaccIds.add(id);
        }
      }
      if (geaccIds.isEmpty) {
        return (
          count: 0,
          subtitle: '$maandNaam heeft geen open afsluitingen',
        );
      }
      final uitRes = await AppSupabase.client
          .from('operator_uitbetalingen')
          .select('operator_id')
          .eq('maand_sleutel', sleutel)
          .inFilter('operator_id', geaccIds.toList());
      final afgesloten = (uitRes as List)
          .map((e) => _trim(Map<String, dynamic>.from(e as Map)['operator_id']))
          .where((id) => id.isNotEmpty)
          .toSet();
      final open = geaccIds.where((id) => !afgesloten.contains(id)).length;
      return (
        count: open,
        subtitle: open > 0
            ? '$maandNaam nog niet volledig afgesloten'
            : '$maandNaam is afgesloten',
      );
    } catch (_) {
      return (count: 0, subtitle: 'Status salarisrun onbekend');
    }
  }

  Future<List<_DashboardAlert>> _fetchAlerts() async {
    final alerts = <_DashboardAlert>[];
    final cutoff = DateTime.now().subtract(const Duration(days: 7));

    try {
      final res = await AppSupabase.client
          .from('offertes')
          .select('id, status, verzonden_op, bedrijfsnaam_klant')
          .eq('status', 'send');
      final stale = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) {
            final sent = _parseDayOnly(r['verzonden_op']);
            return sent != null && sent.isBefore(cutoff);
          })
          .toList();
      if (stale.isNotEmpty) {
        alerts.add(
          _DashboardAlert(
            icon: Icons.assignment_late,
            message:
                '${stale.length} offerte(s) wachten al langer dan 7 dagen op antwoord.',
            color: Colors.orange,
            route: '/offertes',
          ),
        );
      }
    } catch (_) {}

    try {
      final morgen = DateTime.now().add(const Duration(days: 1));
      final morgenStr =
          '${morgen.year}-${morgen.month.toString().padLeft(2, '0')}-${morgen.day.toString().padLeft(2, '0')}';
      final res = await AppSupabase.client
          .from('opdrachten')
          .select('id, huidige_operator_id, projecten(project_naam)')
          .eq('status', 'ingepland')
          .eq('geplande_datum', morgenStr);
      final zonderOperator = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) => _trim(r['huidige_operator_id']).isEmpty)
          .toList();
      if (zonderOperator.isNotEmpty) {
        alerts.add(
          _DashboardAlert(
            icon: Icons.no_accounts,
            message:
                '${zonderOperator.length} ingeplande '
                '${zonderOperator.length == 1 ? 'taak' : 'taken'} voor morgen '
                'hebben nog geen operator.',
            color: Colors.red,
            route: '/planbord',
          ),
        );
      }
    } catch (_) {}

    try {
      final today = DateTime.now();
      final todayNorm = DateTime(today.year, today.month, today.day);
      final res = await AppSupabase.client
          .from('dks_rapporten')
          .select('id, geplande_datum, projecten(project_naam)')
          .eq('status', 'gepland');
      final due = (res as List).map((e) {
        final r = Map<String, dynamic>.from(e as Map);
        final d = _parseDayOnly(r['geplande_datum']);
        if (d == null) return null;
        final day = DateTime(d.year, d.month, d.day);
        if (day.isAfter(todayNorm)) return null;
        final nested = r['projecten'];
        String naam = 'onbekend project';
        if (nested is Map) {
          final pn = _trim(nested['project_naam']);
          if (pn.isNotEmpty) naam = pn;
        }
        return naam;
      }).whereType<String>().toList();
      if (due.isNotEmpty) {
        final eerste = due.first;
        final extra = due.length > 1 ? ' (+${due.length - 1} meer)' : '';
        alerts.add(
          _DashboardAlert(
            icon: Icons.cleaning_services,
            message: 'DKS-controle vereist bij project: $eerste$extra.',
            color: Colors.blue,
            route: '/projecten',
          ),
        );
      }
    } catch (_) {}

    return alerts;
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    var meldingen = 0;
    var teAccorderen = 0;
    var teAccorderenOps = 0;
    var planbord = 0;
    var projecten = 0;
    var concepten = 0;
    var offertes = 0;
    var offerteWaarde = 0.0;
    var salarisOpen = 0;
    var salarisSub = '';
    List<_DashboardAlert> alerts = const [];
    Object? err;

    try {
      await Future.wait<void>([
        () async {
          meldingen = await _fetchOpenTicketsCount();
        }(),
        () async {
          final acc = await _fetchTeAccorderen();
          teAccorderen = acc.uren;
          teAccorderenOps = acc.operators;
        }(),
        () async {
          planbord = await _fetchOngeplandBinnen7Dagen();
        }(),
        () async {
          projecten = await _fetchActieveProjecten();
        }(),
        () async {
          concepten = await _fetchConceptFacturen();
        }(),
        () async {
          final pipe = await _fetchOpenOffertes();
          offertes = pipe.count;
          offerteWaarde = pipe.waarde;
        }(),
        () async {
          final sal = await _fetchSalarisRunStatus();
          salarisOpen = sal.count;
          salarisSub = sal.subtitle;
        }(),
        () async {
          alerts = await _fetchAlerts();
        }(),
      ]);
    } catch (e) {
      err = e;
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadError = err;
      _meldingenOpen = meldingen;
      _teAccorderenUren = teAccorderen;
      _teAccorderenOperators = teAccorderenOps;
      _planbordOngepland7d = planbord;
      _actieveProjecten = projecten;
      _conceptFacturen = concepten;
      _openOffertes = offertes;
      _openOffertesWaarde = offerteWaarde;
      _salarisOperatorsOpen = salarisOpen;
      _salarisSubtitle = salarisSub;
      _alerts = alerts;
    });
  }

  void _navigateTo(BuildContext context, String route) {
    if (route.isEmpty) return;
    final navigator = Navigator.of(context);
    switch (route) {
      case '/meldingen':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/facilitator/tickets'),
            builder: (_) => const TicketOverviewScreen(),
          ),
        );
        return;
      case '/projecten':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/facilitator/projecten'),
            builder: (_) => const ProjectOverviewScreen(),
          ),
        );
        return;
      case '/offertes':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/facilitator/quotes'),
            builder: (_) => const QuoteOverviewScreen(),
          ),
        );
        return;
      case '/offerte-aanmaken':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/facilitator/quotes/create'),
            builder: (_) => const QuoteCreateHeaderScreen(),
          ),
        );
        return;
      case '/crm':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/facilitator/crm'),
            builder: (_) => const RelationsCrmScreen(),
          ),
        );
        return;
      case '/planbord':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/facilitator/planning'),
            builder: (_) => const PlanbordScreen(),
          ),
        );
        return;
      case '/uren-accorderen':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/admin/uren-accorderen'),
            builder: (_) => const UrenAccorderenScreen(),
          ),
        );
        return;
      case '/facturatie':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/admin/sales/invoices/generate'),
            builder: (_) => const InvoiceBulkRunScreen(),
          ),
        );
        return;
      case '/salaris-administratie':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/admin/salaris-administratie'),
            builder: (_) => const SalarisAdministratieScreen(),
          ),
        );
        return;
      case '/hr-beheer':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/generator/hr-beheer'),
            builder: (_) => const HrBeheerScreen(),
          ),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFFF2F2F7);
    const cardColor = Colors.white;
    final borderRadius = BorderRadius.circular(16);
    final shadow = BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 20,
      offset: const Offset(0, 4),
    );

    return Scaffold(
      backgroundColor: bgColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const Icon(Icons.menu, color: Colors.black87),
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          },
        ),
        title: const SizedBox.shrink(),
        centerTitle: false,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboardData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20.0),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  image: const DecorationImage(
                    image: NetworkImage(_headerImageUrl),
                    fit: BoxFit.cover,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade900.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        const Color(0xFF004A99).withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '${_getGreeting()},',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 4),
                      const Text(
                        'Controlecentrum',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loadError != null) ...[
                const SizedBox(height: 16),
                Material(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Kon niet alles laden: $_loadError',
                      style: TextStyle(color: Colors.orange.shade900),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              const Text(
                'Operationeel Overzicht',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 800 ? 4 : 2;
                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.1,
                    children: [
                      _buildRichKpiCard(
                        context: context,
                        title: 'Meldingen',
                        value: _loading ? '—' : '$_meldingenOpen',
                        subtitle: _meldingenOpen > 0
                            ? 'Actie vereist'
                            : 'Geen open meldingen',
                        icon: Icons.warning_amber_rounded,
                        color: Colors.orange,
                        route: '/meldingen',
                        chartData: _sparkline(_meldingenOpen),
                      ),
                      _buildRichKpiCard(
                        context: context,
                        title: 'Te accorderen',
                        value: _loading ? '—' : '$_teAccorderenUren',
                        subtitle: _teAccorderenOperators > 0
                            ? 'Van $_teAccorderenOperators operator(s)'
                            : 'Geen ingediende uren',
                        icon: Icons.access_time,
                        color: Colors.blue,
                        route: '/uren-accorderen',
                        chartData: _sparkline(_teAccorderenUren),
                      ),
                      _buildRichKpiCard(
                        context: context,
                        title: 'Planbord',
                        value: _loading ? '—' : '$_planbordOngepland7d',
                        subtitle: 'Ongepland (7 dgn)',
                        icon: Icons.calendar_month,
                        color: Colors.red,
                        route: '/planbord',
                        chartData: _sparkline(_planbordOngepland7d),
                      ),
                      _buildRichKpiCard(
                        context: context,
                        title: 'Projecten',
                        value: _loading ? '—' : '$_actieveProjecten',
                        subtitle: 'Actieve locaties',
                        icon: Icons.business,
                        color: Colors.purple,
                        route: '/projecten',
                        chartData: _sparkline(_actieveProjecten),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),
              const Text(
                'Sales & Financiën',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 800 ? 3 : 1;
                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: constraints.maxWidth > 800 ? 2.0 : 2.5,
                    children: [
                      _buildRichKpiCard(
                        context: context,
                        title: 'Concept Facturen',
                        value: _loading ? '—' : '$_conceptFacturen',
                        subtitle: _conceptFacturen > 0
                            ? 'Klaar om te genereren'
                            : 'Geen conceptfacturen',
                        icon: Icons.receipt_long,
                        color: Colors.green,
                        route: '/facturatie',
                        chartData: _sparkline(_conceptFacturen),
                      ),
                      _buildRichKpiCard(
                        context: context,
                        title: 'Open Offertes',
                        value: _loading ? '—' : '$_openOffertes',
                        subtitle: _openOffertesWaarde > 0
                            ? 'Verwachte waarde: ${_eurCompact(_openOffertesWaarde)}'
                            : 'Geen open pipeline',
                        icon: Icons.request_quote,
                        color: Colors.teal,
                        route: '/offertes',
                        chartData: _sparkline(_openOffertes),
                      ),
                      _buildRichKpiCard(
                        context: context,
                        title: 'Salaris Run',
                        value: _loading ? '—' : '$_salarisOperatorsOpen',
                        subtitle: _salarisSubtitle.isNotEmpty
                            ? _salarisSubtitle
                            : 'Laden…',
                        icon: Icons.account_balance_wallet,
                        color: Colors.indigo,
                        route: '/salaris-administratie',
                        chartData: _sparkline(_salarisOperatorsOpen),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 40),
              const Text(
                'Snelle Acties',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildActionChip(
                    context,
                    'Facturen Genereren',
                    Icons.euro,
                    Colors.green,
                    '/facturatie',
                  ),
                  _buildActionChip(
                    context,
                    'Nieuwe Offerte',
                    Icons.add_circle,
                    Colors.teal,
                    '/offerte-aanmaken',
                  ),
                  _buildActionChip(
                    context,
                    'Klant / Lead Toevoegen',
                    Icons.person_add,
                    Colors.blue,
                    '/crm',
                  ),
                  _buildActionChip(
                    context,
                    'Salarisadministratie',
                    Icons.account_balance_wallet,
                    Colors.indigo,
                    '/salaris-administratie',
                  ),
                  _buildActionChip(
                    context,
                    'HR & Contracten',
                    Icons.badge,
                    Colors.purple,
                    '/hr-beheer',
                  ),
                  _buildActionChip(
                    context,
                    'Planbord',
                    Icons.calendar_month,
                    Colors.deepOrange,
                    '/planbord',
                  ),
                ],
              ),
              const SizedBox(height: 40),
              const Text(
                'Aandacht Vereist',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: borderRadius,
                  boxShadow: [shadow],
                ),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _alerts.isEmpty
                        ? const ListTile(
                            title: Text(
                              'Geen openstaande aandachtspunten.',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (var i = 0; i < _alerts.length; i++) ...[
                                if (i > 0) const Divider(height: 1),
                                _buildAlertRow(
                                  _alerts[i].icon,
                                  _alerts[i].message,
                                  _alerts[i].color,
                                  () => _navigateTo(context, _alerts[i].route),
                                ),
                              ],
                            ],
                          ),
              ),
              const SizedBox(height: 120),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildRichKpiCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String route,
    required List<double> chartData,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _navigateTo(context, route),
          child: Stack(
            children: [
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 72,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                  child: CustomPaint(
                    painter: SparklinePainter(chartData, color),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, color: color, size: 24),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
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

  Widget _buildActionChip(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    String route,
  ) {
    return InkWell(
      onTap: () => _navigateTo(context, route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertRow(
    IconData icon,
    String text,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

class _DashboardAlert {
  const _DashboardAlert({
    required this.icon,
    required this.message,
    required this.color,
    required this.route,
  });

  final IconData icon;
  final String message;
  final Color color;
  final String route;
}

class SparklinePainter extends CustomPainter {
  SparklinePainter(this.data, this.color);

  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final maxVal = data.reduce((a, b) => a > b ? a : b);
    final minVal = data.reduce((a, b) => a < b ? a : b);
    final range = maxVal - minVal == 0 ? 1 : maxVal - minVal;

    final xStep = data.length <= 1 ? size.width : size.width / (data.length - 1);

    for (var i = 0; i < data.length; i++) {
      final x = i * xStep;
      final y = size.height -
          (((data[i] - minVal) / range) * (size.height * 0.8));

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final prevX = (i - 1) * xStep;
        final prevY = size.height -
            (((data[i - 1] - minVal) / range) * (size.height * 0.8));
        final controlX1 = prevX + (xStep / 2);
        final controlX2 = prevX + (xStep / 2);
        path.cubicTo(controlX1, prevY, controlX2, y, x, y);
      }
    }

    canvas.drawPath(path, paint);

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
