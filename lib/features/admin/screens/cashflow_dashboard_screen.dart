import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';

class CashflowDashboardScreen extends StatefulWidget {
  const CashflowDashboardScreen({super.key});

  @override
  State<CashflowDashboardScreen> createState() => _CashflowDashboardScreenState();
}

class _CashflowDashboardScreenState extends State<CashflowDashboardScreen> {
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final res = await AppSupabase.client
        .from('app_cashflow_prognose')
        .select()
        .order('sorteer_datum', ascending: true);
    return (res as List).cast<Map<String, dynamic>>();
  }

  void _refresh() {
    setState(() {
      _future = _fetch();
    });
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  NumberFormat _eur() => NumberFormat.currency(locale: 'nl_NL', symbol: '€', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canView = up.isGenerator || up.hasPermission('finance');

    if (!canView) {
      return Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(
            'Cashflow Prognose',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
        ),
        body: const SelectionArea(
          child: Center(child: Text('Geen toegang.')),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Cashflow Prognose',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(tooltip: 'Vernieuwen', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SelectionArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: softBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: cs.onSurface.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Text('Kan cashflow niet laden: ${snapshot.error}'),
                ),
              );
            }

            final rows = snapshot.data ?? const <Map<String, dynamic>>[];
            if (rows.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: softBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: cs.onSurface.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Text(
                      'Geen prognose-data gevonden.',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              );
            }

            final upcoming = rows.length <= 6 ? rows : rows.take(6).toList();
            final nettoSum = upcoming.fold<double>(
              0,
              (acc, r) => acc + _asDouble(r['netto_cashflow_mutatie']),
            );

            final maxY = upcoming
                .map(
                  (r) => _asDouble(r['verwachte_inkomsten']).abs().toDouble(),
                )
                .followedBy(
                  upcoming.map(
                    (r) => _asDouble(r['verwachte_uitgaven']).abs().toDouble(),
                  ),
                )
                .fold<double>(0, (m, v) => v > m ? v : m);

            final groups = <BarChartGroupData>[];
            for (var i = 0; i < upcoming.length; i++) {
              final r = upcoming[i];
              final income = _asDouble(r['verwachte_inkomsten']);
              final expense = _asDouble(r['verwachte_uitgaven']);
              groups.add(
                BarChartGroupData(
                  x: i,
                  barsSpace: 6,
                  barRods: [
                    BarChartRodData(
                      toY: income,
                      color: const Color(0xFF19C37D),
                      width: 10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    BarChartRodData(
                      toY: expense,
                      color: const Color(0xFFFF6B6B),
                      width: 10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: cs.onSurface.withValues(alpha: 0.06),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Netto Cashflow Mutatie Komende 6 Mnd',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface.withValues(alpha: 0.70),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _eur().format(nettoSum),
                              style: GoogleFonts.inter(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cs.onSurface.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Icon(Icons.show_chart_rounded, color: cs.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Prognose (6 maanden)',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: cs.onSurface.withValues(alpha: 0.06),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: 320,
                    child: BarChart(
                      BarChartData(
                        maxY: (maxY * 1.15).clamp(1000, double.infinity),
                        minY: 0,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: cs.onSurface.withValues(alpha: 0.08),
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 46,
                              getTitlesWidget: (value, meta) => Text(
                                _eur().format(value),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                  color: cs.onSurface.withValues(alpha: 0.65),
                                ),
                              ),
                            ),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx < 0 || idx >= upcoming.length) {
                                  return const SizedBox.shrink();
                                }
                                final p = _text(upcoming[idx]['periode']);
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    p.isEmpty ? '-' : p,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.72),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: groups,
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            tooltipBgColor: tileBg,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final label =
                                  rodIndex == 0 ? 'Inkomsten' : 'Uitgaven';
                              return BarTooltipItem(
                                '$label\n${_eur().format(rod.toY)}',
                                GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _LegendDot(
                      color: const Color(0xFF19C37D),
                      label: 'Verwachte inkomsten',
                    ),
                    const SizedBox(width: 14),
                    _LegendDot(
                      color: const Color(0xFFFF6B6B),
                      label: 'Verwachte uitgaven',
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

