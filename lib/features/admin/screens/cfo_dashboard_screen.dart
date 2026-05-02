import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import '../../../shared/widgets/enterprise_tooltip.dart';

class CFODashboardScreen extends StatefulWidget {
  const CFODashboardScreen({super.key});

  @override
  State<CFODashboardScreen> createState() => _CFODashboardScreenState();
}

class _CFODashboardScreenState extends State<CFODashboardScreen> {
  Future<_CfoData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_CfoData> _fetch() async {
    final kwartaalRow = await AppSupabase.client
        .from('dashboard_kwartaal_cijfers')
        .select()
        .order('jaar', ascending: false)
        .order('kwartaal', ascending: false)
        .limit(1)
        .maybeSingle();

    final marginsRes = await AppSupabase.client
        .from('app_project_winstmarges')
        .select()
        .order('winstmarge_procent', ascending: true);

    final margins = (marginsRes as List).cast<Map<String, dynamic>>();
    return _CfoData(
      kwartaal: kwartaalRow,
      projectMargins: margins,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final canView = userProvider.hasPermission('view_reports');

    if (!canView) {
      return Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(
            'CFO Cockpit',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
        ),
        body: const _NoAccessEmptyState(
          message: 'U heeft geen rechten om financiële rapportages in te zien.',
        ),
      );
    }

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'CFO Cockpit',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: () => setState(() => _future = _fetch()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_CfoData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: _ErrorState(
                title: 'Kan CFO data niet laden',
                message: snapshot.error.toString(),
                onRetry: () => setState(() => _future = _fetch()),
              ),
            );
          }

          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            children: [
              _KpiRow(kwartaalRow: data.kwartaal),
              const SizedBox(height: 18),
              Text(
                'Projectmarges (laagste eerst)',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 12),
              _ProjectMarginsList(rows: data.projectMargins),
            ],
          );
        },
      ),
    );
  }
}

class _CfoData {
  const _CfoData({
    required this.kwartaal,
    required this.projectMargins,
  });

  final Map<String, dynamic>? kwartaal;
  final List<Map<String, dynamic>> projectMargins;
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.kwartaalRow});

  final Map<String, dynamic>? kwartaalRow;

  NumberFormat _eur() => NumberFormat.currency(
        locale: 'nl_NL',
        symbol: '€',
        decimalDigits: 2,
      );

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final netto = _asDouble(kwartaalRow?['netto_kwartaal_winst']);
    final omzet = _asDouble(kwartaalRow?['omzet_ex_btw']);
    final btw = _asDouble(kwartaalRow?['te_betalen_btw']);

    // Premium solid/gradient-ish background (kept subtle for glass vibe).
    final bg = isDark ? const Color(0xFF0A0912) : Colors.white;

    final cards = [
      _StatCardData(
        title: 'Netto Kwartaal Winst',
        tooltip: 'Verkoopfacturen minus inkoopfacturen voor dit kwartaal.',
        value: _eur().format(netto),
        icon: Icons.trending_up_rounded,
        background: bg,
      ),
      _StatCardData(
        title: 'Omzet (Ex. BTW)',
        tooltip: '',
        value: _eur().format(omzet),
        icon: Icons.receipt_long_rounded,
        background: bg,
      ),
      _StatCardData(
        title: 'Te Betalen BTW',
        tooltip:
            'Gefactureerde BTW minus terug te vorderen inkoop-BTW. Dit bedrag moet u reserveren voor de fiscus.',
        value: _eur().format(btw),
        icon: Icons.account_balance_rounded,
        background: bg,
      ),
    ];

    final child = Row(
      children: [
        for (final c in cards) ...[
          _StatCard(data: c),
          const SizedBox(width: 14),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: cards.map((c) => SizedBox(width: 320, child: _StatCard(data: c))).toList(),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: child,
        );
      },
    );
  }
}

class _StatCardData {
  const _StatCardData({
    required this.title,
    required this.tooltip,
    required this.value,
    required this.icon,
    required this.background,
  });

  final String title;
  final String tooltip;
  final String value;
  final IconData icon;
  final Color background;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});

  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 320,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: data.background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
                ),
                child: Icon(data.icon, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  data.title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    color: cs.onSurface,
                  ),
                ),
              ),
              EnterpriseTooltip(message: data.tooltip),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            data.value,
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectMarginsList extends StatelessWidget {
  const _ProjectMarginsList({required this.rows});

  final List<Map<String, dynamic>> rows;

  NumberFormat _eur() => NumberFormat.currency(
        locale: 'nl_NL',
        symbol: '€',
        decimalDigits: 2,
      );

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  ({Color bg, Color fg, String label}) _toneFor(double pct) {
    if (pct < 5.0) {
      return (
        bg: const Color(0xFFFFE5E5),
        fg: const Color(0xFF8A1F1F),
        label: 'High Risk'
      );
    }
    if (pct < 20.0) {
      return (
        bg: const Color(0xFFFFF1DB),
        fg: const Color(0xFF8A4B12),
        label: 'Warning'
      );
    }
    return (
      bg: const Color(0xFFE6F7EE),
      fg: const Color(0xFF1E6B3A),
      label: 'Healthy'
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: tileBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.inbox_outlined, color: cs.onSurface.withValues(alpha: 0.65)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Geen projecten gevonden.',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.80),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: rows.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final r = rows[i];

        final project = _text(r['project_naam'] ?? r['project'] ?? r['naam']);
        final client = _text(r['klant_naam'] ?? r['client_naam'] ?? r['klant']);
        final winstEuro = _asDouble(r['absolute_winst_euro']);
        final marge = _asDouble(r['winstmarge_procent']);

        final tone = _toneFor(marge);

        // Soften tones in dark mode (still readable).
        final badgeBg = isDark ? tone.bg.withValues(alpha: 0.18) : tone.bg;
        final badgeFg = isDark ? tone.fg.withValues(alpha: 0.95) : tone.fg;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: tileBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
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
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
                ),
                child: Icon(Icons.business, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.isEmpty ? '(onbekend project)' : project,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      client.isEmpty ? '—' : client,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface.withValues(alpha: 0.70),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _eur().format(winstEuro),
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeFg.withValues(alpha: 0.25)),
                ),
                child: Text(
                  '${marge.toStringAsFixed(1)}%',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    color: badgeFg,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NoAccessEmptyState extends StatelessWidget {
  const _NoAccessEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: tileBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, color: cs.onSurface.withValues(alpha: 0.65)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.80),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: -0.4,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w500,
              color: cs.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Opnieuw laden'),
          ),
        ],
      ),
    );
  }
}

