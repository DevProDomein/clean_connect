import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_drawer.dart';
import 'dks_project_dossier_screen.dart';

class DksDashboardScreen extends StatefulWidget {
  const DksDashboardScreen({super.key});

  @override
  State<DksDashboardScreen> createState() => _DksDashboardScreenState();
}

class _DksDashboardScreenState extends State<DksDashboardScreen> {
  List<Map<String, dynamic>> _projects = const [];
  Map<String, dynamic>? _inspectieVandaag;
  bool _isLoading = true;
  Object? _loadError;
  double? _averageQuality;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  double? _score(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }

  Color _stoplichtColor(String kleur) {
    switch (kleur.toLowerCase()) {
      case 'rood':
        return Colors.red;
      case 'oranje':
        return Colors.orange;
      case 'groen':
        return Colors.green;
      case 'grijs':
      default:
        return Colors.grey;
    }
  }

  String _formatInspectieDatum(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return 'Nog nooit';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    return '$day-$month-${parsed.year}';
  }

  static const _navy = Color(0xFF0F172A);

  Future<void> _loadDashboard() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final client = Supabase.instance.client;
    try {
      final results = await Future.wait<dynamic>([
        client.rpc('get_dks_dashboard'),
        client.from('view_dks_vandaag_dashboard').select().maybeSingle(),
      ]);
      if (!mounted) {
        return;
      }

      final response = results[0];
      final vandaagResponse = results[1];
      final inspectieVandaag = vandaagResponse == null
          ? null
          : Map<String, dynamic>.from(vandaagResponse as Map);

      final dashboardData = List<dynamic>.from(response as List);
      final rows = <Map<String, dynamic>>[];
      for (final row in dashboardData) {
        if (row is Map) {
          rows.add(Map<String, dynamic>.from(row));
        }
      }

      rows.sort((a, b) {
        final aScore = _score(a['gemiddelde_score']);
        final bScore = _score(b['gemiddelde_score']);
        if (aScore == null && bScore == null) {
          return 0;
        }
        if (aScore == null) {
          return 1;
        }
        if (bScore == null) {
          return -1;
        }
        return aScore.compareTo(bScore);
      });

      final validScores = rows
          .map((row) => _score(row['gemiddelde_score']))
          .whereType<double>()
          .toList();
      final averageQuality = validScores.isEmpty
          ? null
          : validScores.reduce((a, b) => a + b) / validScores.length;

      if (!mounted) {
        return;
      }
      setState(() {
        _projects = rows;
        _inspectieVandaag = inspectieVandaag;
        _averageQuality = averageQuality;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _projects = const [];
          _inspectieVandaag = null;
          _averageQuality = null;
          _loadError = e;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _kpiCard({
    required BuildContext context,
    required String title,
    required String value,
    required Color valueColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: cs.onSurface.withValues(alpha: 0.78),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              fontSize: 26,
              color: valueColor,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = isDark ? const Color(0xFF090A12) : const Color(0xFFF2F4F7);
    final averageQualityLabel = _averageQuality == null ? '--%' : '${_averageQuality!.toStringAsFixed(1)}%';
    const openActionItemsLabel = '3';

    return Scaffold(
      backgroundColor: bg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(
          'Kwaliteit (DKS)',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: _isLoading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SelectionArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'Fout bij laden van data: $_loadError',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      if (_inspectieVandaag != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Vandaag Uit Te Voeren',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFFF6B35),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () {
                                      final m = _inspectieVandaag!;
                                      final pid = _text(m['project_id']);
                                      if (pid.isEmpty) {
                                        return;
                                      }
                                      Navigator.push<void>(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => DksProjectDossierScreen(
                                            projectId: pid,
                                            projectNaam:
                                                _text(m['project_naam']).isNotEmpty
                                                    ? _text(m['project_naam'])
                                                    : 'Project',
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: const Color(0xFFFF6B35),
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withValues(alpha: 0.04),
                                            blurRadius: 15,
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.warning_amber_rounded,
                                            color: Color(0xFFFF6B35),
                                            size: 32,
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _inspectieVandaag!['project_naam']
                                                      .toString(),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                Text(
                                                  _inspectieVandaag!['bedrijfsnaam']
                                                      .toString(),
                                                  style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(
                                            Icons.arrow_forward_ios,
                                            color: Colors.grey,
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: _kpiCard(
                                  context: context,
                                  title: 'Gemiddelde Kwaliteit',
                                  value: averageQualityLabel,
                                  valueColor: Colors.green,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _kpiCard(
                                  context: context,
                                  title: 'Open Actiepunten',
                                  value: openActionItemsLabel,
                                  valueColor: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            _inspectieVandaag != null ? 6 : 20,
                            20,
                            10,
                          ),
                          child: Text(
                            'Alle projecten',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: isDark
                                  ? cs.onSurface
                                  : _navy.withValues(alpha: 0.9),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                      if (_projects.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              'Geen projecten gevonden',
                              style: GoogleFonts.lato(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface.withValues(alpha: 0.72),
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = _projects[index];
                                final projectName =
                                    _text(item['project_naam']).isEmpty
                                        ? 'Onbekend'
                                        : _text(item['project_naam']);
                                final companyName =
                                    _text(item['bedrijfsnaam']).isEmpty
                                        ? 'Onbekend'
                                        : _text(item['bedrijfsnaam']);
                                final stoplichtKleur =
                                    _text(item['stoplicht_kleur']);
                                final statusColor = _stoplichtColor(stoplichtKleur);
                                final scoreRaw = item['gemiddelde_score'];
                                final scoreNumber = _score(scoreRaw);
                                final scoreText = scoreRaw == null ||
                                        _text(scoreRaw).isEmpty
                                    ? '-'
                                    : '${scoreNumber?.toStringAsFixed(1) ?? _text(scoreRaw)}%';
                                final totalInspectionsRaw = item['totaal_inspecties'];
                                final totalInspections = totalInspectionsRaw is num
                                    ? totalInspectionsRaw.toInt()
                                    : int.tryParse(_text(totalInspectionsRaw)) ??
                                        0;
                                final lastInspection = _formatInspectieDatum(
                                  item['laatste_inspectie_datum'],
                                );
                                final projectId = _text(item['project_id']);

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(12),
                                        bottomRight: Radius.circular(12),
                                      ),
                                      onTap: () {
                                        if (projectId.isEmpty) {
                                          return;
                                        }
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => DksProjectDossierScreen(
                                              projectId: projectId,
                                              projectNaam: projectName,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: cs.surface,
                                          borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(12),
                                            bottomRight: Radius.circular(12),
                                          ),
                                          border: Border(
                                            left: BorderSide(
                                              width: 6,
                                              color: statusColor,
                                            ),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: isDark ? 0.18 : 0.05,
                                              ),
                                              blurRadius: 12,
                                              offset: const Offset(0, 5),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    projectName,
                                                    style: GoogleFonts.lato(
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    companyName,
                                                    style: GoogleFonts.lato(
                                                      color: cs.onSurface.withValues(
                                                        alpha: 0.62,
                                                      ),
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    'Laatste inspectie: $lastInspection',
                                                    style: GoogleFonts.lato(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w700,
                                                      color: cs.onSurface.withValues(
                                                        alpha: 0.58,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  scoreText,
                                                  style: GoogleFonts.lato(
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 24,
                                                    color: statusColor,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '$totalInspections metingen',
                                                  style: GoogleFonts.lato(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: cs.onSurface.withValues(
                                                      alpha: 0.56,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: _projects.length,
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
