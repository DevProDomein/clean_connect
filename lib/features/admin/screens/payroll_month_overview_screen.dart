import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user_role.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';

/// Maandoverzicht loonadministratie (`loonadministratie_maand`).
class PayrollMonthOverviewScreen extends StatefulWidget {
  const PayrollMonthOverviewScreen({super.key});

  @override
  State<PayrollMonthOverviewScreen> createState() =>
      _PayrollMonthOverviewScreenState();
}

class _PayrollMonthOverviewScreenState extends State<PayrollMonthOverviewScreen> {
  static final _eur = NumberFormat.currency(
    locale: 'nl_NL',
    symbol: '€',
    decimalDigits: 2,
  );

  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final res = await AppSupabase.client
        .from('loonadministratie_maand')
        .select()
        .order('kalender_maand', ascending: false);
    final rows = (res as List).cast<Map<String, dynamic>>();
    _sortPayrollRows(rows);
    return rows;
  }

  void _sortPayrollRows(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) {
      final da = _parseKalenderMaand(a['kalender_maand']);
      final db = _parseKalenderMaand(b['kalender_maand']);
      if (da != null && db != null) {
        final c = db.compareTo(da);
        if (c != 0) return c;
      } else {
        final sa = (a['kalender_maand'] ?? '').toString();
        final sb = (b['kalender_maand'] ?? '').toString();
        final c = sb.compareTo(sa);
        if (c != 0) return c;
      }
      final na = _operatorNaamSortKey(a);
      final nb = _operatorNaamSortKey(b);
      return na.compareTo(nb);
    });
  }

  static String _operatorNaamSortKey(Map<String, dynamic> row) {
    final raw = (row['operator_naam'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw.toLowerCase();
    final oid = (row['operator_id'] ?? '').toString().trim();
    if (oid.isNotEmpty) return 'zzzz_operator_$oid'.toLowerCase();
    return 'zzzz_onbekend';
  }

  static DateTime? _parseKalenderMaand(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return DateTime(v.year, v.month);
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final dt = DateTime.tryParse(s);
    if (dt != null) return DateTime(dt.year, dt.month);
    final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(s);
    if (m != null) {
      final y = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      if (y != null && mo != null && mo >= 1 && mo <= 12) {
        return DateTime(y, mo);
      }
    }
    if (RegExp(r'^\d{6}$').hasMatch(s)) {
      final y = int.tryParse(s.substring(0, 4));
      final mo = int.tryParse(s.substring(4, 6));
      if (y != null && mo != null && mo >= 1 && mo <= 12) {
        return DateTime(y, mo);
      }
    }
    return null;
  }

  static String _text(dynamic v) => (v ?? '').toString().trim();

  static String _displayOperatorName(Map<String, dynamic> row) {
    final naam = _text(row['operator_naam']);
    if (naam.isNotEmpty) return naam;
    final oid = _text(row['operator_id']);
    if (oid.isNotEmpty) return 'Operator $oid';
    return 'Onbekende medewerker';
  }

  static String _formatKalenderMaand(dynamic v) {
    final d = _parseKalenderMaand(v);
    if (d == null) {
      final s = _text(v);
      return s.isEmpty ? '—' : s;
    }
    return DateFormat.yMMMM('nl_NL').format(DateTime(d.year, d.month));
  }

  static String _formatBruto(dynamic v) {
    if (v == null) return _eur.format(0);
    if (v is num) return _eur.format(v.toDouble());
    final s = v.toString().trim().replaceAll(' ', '');
    if (s.isEmpty) return _eur.format(0);
    final direct = double.tryParse(s);
    if (direct != null) return _eur.format(direct);
    if (s.contains(',')) {
      final normalized = s.replaceAll('.', '').replaceAll(',', '.');
      final n = double.tryParse(normalized);
      if (n != null) return _eur.format(n);
    }
    return _eur.format(0);
  }

  void _refresh() {
    setState(() => _future = _fetch());
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canView = up.isGenerator || up.role == UserRole.administrator;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Loonadministratie (maand)',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !canView
          ? Center(
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
                    'U heeft geen rechten om loongegevens te bekijken.',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            )
          : FutureBuilder<List<Map<String, dynamic>>>(
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
                      child: Text(
                        'Kan loonadministratie niet laden: ${snapshot.error}',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                }

                final rows = snapshot.data ?? const <Map<String, dynamic>>[];

                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  children: [
                    Text(
                      'Maandoverzicht brutoloon',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Per medewerker en kalendermaand. Bedragen worden in het Nederlands (€ …) weergegeven.',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.70),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (rows.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: softBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: cs.onSurface.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Text(
                          'Geen loonadministratieregels gevonden.',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      ListView.separated(
                        itemCount: rows.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        separatorBuilder: (_, i) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          final title = _displayOperatorName(r);
                          final subtitle =
                              _formatKalenderMaand(r['kalender_maand']);
                          final bruto =
                              _formatBruto(r['totaal_bruto_verdiend']);

                          return Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: tileBg,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: cs.onSurface.withValues(alpha: 0.06),
                              ),
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
                                        title,
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.2,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        subtitle,
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface
                                              .withValues(alpha: 0.65),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  bruto,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
    );
  }
}
