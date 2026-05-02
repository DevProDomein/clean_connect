import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import 'quote_create_header_screen.dart';
import 'quote_survey_screen.dart';

/// Offertes dashboard for the Facilitator Portal (Quote Engine).
///
/// Shows three tabs (Concepten / Verzonden / Getekend) pulled from the
/// `offertes` table. Each list item is a custom rounded container (no
/// default Material `Card`) matching our premium SaaS aesthetic.
class QuoteOverviewScreen extends StatefulWidget {
  const QuoteOverviewScreen({super.key});

  @override
  State<QuoteOverviewScreen> createState() => _QuoteOverviewScreenState();
}

class _QuoteOverviewScreenState extends State<QuoteOverviewScreen> {
  // Status buckets per tab.
  static const List<String> _conceptStatuses = ['concept', 'new'];
  static const List<String> _verzondenStatuses = ['send'];
  static const List<String> _getekendStatuses = ['signed'];

  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await AppSupabase.client
          .from('offertes')
          .select('id, offerte_nummer, bedrijfsnaam_klant, totaal_prijs_ex_btw, status, aangemaakt_op')
          .order('aangemaakt_op', ascending: false);
      _rows = (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _filter(List<String> statuses) {
    return _rows.where((r) {
      final s = (r['status'] ?? '').toString().trim().toLowerCase();
      return statuses.contains(s);
    }).toList(growable: false);
  }

  Future<void> _openNewQuote() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/facilitator/quotes/new'),
        builder: (_) => const QuoteCreateHeaderScreen(),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(
            'Offertes',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
          actions: [
            IconButton(
              tooltip: 'Vernieuwen',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: TabBar(
            indicatorColor: cs.primary,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurface.withValues(alpha: 0.55),
            labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
            unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'Concepten'),
              Tab(text: 'Verzonden'),
              Tab(text: 'Getekend'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openNewQuote,
          backgroundColor: cs.primary,
          foregroundColor: Colors.white,
          extendedPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          icon: const Icon(Icons.add_rounded, size: 28),
          label: Text(
            'Nieuwe Offerte',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorView(error: _error!, onRetry: _load)
                : TabBarView(
                    children: [
                      _QuoteList(rows: _filter(_conceptStatuses), emptyLabel: 'Geen concept-offertes.'),
                      _QuoteList(rows: _filter(_verzondenStatuses), emptyLabel: 'Nog geen verzonden offertes.'),
                      _QuoteList(rows: _filter(_getekendStatuses), emptyLabel: 'Nog geen getekende offertes.'),
                    ],
                  ),
      ),
    );
  }
}

class _QuoteList extends StatelessWidget {
  const _QuoteList({required this.rows, required this.emptyLabel});

  final List<Map<String, dynamic>> rows;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            emptyLabel,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      itemCount: rows.length,
      itemBuilder: (context, i) => _QuoteTile(row: rows[i]),
    );
  }
}

class _QuoteTile extends StatelessWidget {
  const _QuoteTile({required this.row});

  final Map<String, dynamic> row;

  String _text(dynamic v) => (v ?? '').toString().trim();
  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(_text(v).replaceAll(',', '.')) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;

    final eur = NumberFormat.currency(locale: 'nl_NL', symbol: '€');
    final df = DateFormat('dd-MM-yyyy');

    final naam = _text(row['bedrijfsnaam_klant']);
    final offerteNr = _text(row['offerte_nummer']);
    final isConcept = offerteNr.isEmpty;
    final totaal = _asDouble(row['totaal_prijs_ex_btw']);
    final aangemaaktOp = DateTime.tryParse(_text(row['aangemaakt_op']))?.toLocal();
    final dateLabel = aangemaaktOp == null ? '—' : df.format(aangemaaktOp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            final offerteId = _text(row['id']);
            if (offerteId.isEmpty) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: '/facilitator/quotes/survey'),
                builder: (_) => QuoteSurveyScreen(offerteId: offerteId),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              naam.isEmpty ? '—' : naam,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (isConcept) ...[
                            const SizedBox(width: 8),
                            _ConceptBadge(),
                          ] else ...[
                            const SizedBox(width: 8),
                            Text(
                              '#$offerteNr',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Aangemaakt: $dateLabel',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.60),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      eur.format(totaal),
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'excl. BTW',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConceptBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Text(
        'CONCEPT',
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: softBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Kan offertes niet laden',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text('$error', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Opnieuw proberen'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
