import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import 'reconciliation_split_screen.dart';

class BankDashboardScreen extends StatefulWidget {
  const BankDashboardScreen({super.key});

  @override
  State<BankDashboardScreen> createState() => _BankDashboardScreenState();
}

class _BankDashboardScreenState extends State<BankDashboardScreen> {
  Future<_BankDashboardData>? _future;
  bool _autoBusy = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_BankDashboardData> _fetch() async {
    final res = await AppSupabase.client
        .from('app_bank_reconciliatie_dashboard')
        .select()
        .order('transactie_datum', ascending: false);

    final rows = (res as List).cast<Map<String, dynamic>>();
    final todo = rows
        .where((r) => ((r['matching_status'] ?? '').toString().trim().toLowerCase()) != 'matched')
        .length;

    return _BankDashboardData(rows: rows, teVerwerkenCount: todo);
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

  NumberFormat _eur() => NumberFormat.currency(locale: 'nl_NL', symbol: '€', decimalDigits: 2);

  Future<void> _runAutoMatch() async {
    if (_autoBusy) return;
    setState(() => _autoBusy = true);
    try {
      final res = await AppSupabase.client.rpc('run_auto_bank_matching');
      final msg = (res ?? '').toString().trim();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.92),
          content: Text(msg.isEmpty ? 'Auto-match afgerond.' : msg),
        ),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Auto-match mislukt: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _autoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canView = up.isGenerator || up.hasPermission('finance') || up.hasPermission('sync_bank');

    if (!canView) {
      return Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(
            'Bank & Afletteren',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
        ),
        body: const SelectionArea(
          child: _NoAccessEmptyState(
            message: 'U heeft geen rechten om banktransacties te verwerken.',
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Bank & Afletteren',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(tooltip: 'Vernieuwen', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SelectionArea(
        child: FutureBuilder<_BankDashboardData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: _ErrorState(
                  title: 'Kan bankdashboard niet laden',
                  message: snapshot.error.toString(),
                  onRetry: _refresh,
                ),
              );
            }

            final data = snapshot.data!;
            final rows = data.rows;

            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _KpiCard(
                        title: 'Te Verwerken Transacties',
                        value: data.teVerwerkenCount.toString(),
                        icon: Icons.playlist_add_check_rounded,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: 88,
                        child: FilledButton.icon(
                          onPressed: _autoBusy ? null : _runAutoMatch,
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                          ),
                          icon: _autoBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.bolt_rounded),
                          label: Text(
                            'Auto-Match Algoritme Starten',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Transacties',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: isDark ? tileBg : const Color(0xFFF5F5F7),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: cs.onSurface.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Geen transacties gevonden.',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withValues(alpha: 0.80),
                            ),
                          ),
                        ),
                      ],
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
                      final id = _text(r['id'] ?? r['transactie_id']);
                      final datum = _text(r['transactie_datum']);
                      final tegen = _text(r['tegenrekening_naam']);
                      final oms = _text(r['omschrijving']);
                      final bedrag = _asDouble(r['bedrag']);
                      final status = _text(r['matching_status']);

                      final badge =
                          _MatchTone.forStatus(status, isDark: isDark);
                      final shortOms =
                          oms.length > 50 ? '${oms.substring(0, 50)}…' : oms;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: id.isEmpty
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ReconciliationSplitScreen(
                                        transactionId: id,
                                      ),
                                    ),
                                  );
                                },
                          child: Container(
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
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: cs.onSurface.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: cs.onSurface.withValues(alpha: 0.08),
                                    ),
                                  ),
                                  child: Icon(badge.icon, color: badge.fg),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tegen.isEmpty
                                            ? 'Onbekende tegenrekening'
                                            : tegen,
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        [
                                          if (datum.isNotEmpty) datum,
                                          if (shortOms.isNotEmpty) shortOms,
                                        ].join(' • '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface.withValues(
                                            alpha: 0.65,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _eur().format(bedrag),
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: badge.bg,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(color: badge.border),
                                      ),
                                      child: Text(
                                        badge.label,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.1,
                                          color: badge.fg,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BankDashboardData {
  const _BankDashboardData({required this.rows, required this.teVerwerkenCount});

  final List<Map<String, dynamic>> rows;
  final int teVerwerkenCount;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0912) : Colors.white;

    return Container(
      height: 88,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface.withValues(alpha: 0.70),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
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
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            ),
            child: Icon(icon, color: cs.primary),
          ),
        ],
      ),
    );
  }
}

class _MatchTone {
  const _MatchTone({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
    required this.icon,
  });

  final String label;
  final Color bg;
  final Color fg;
  final Color border;
  final IconData icon;

  static _MatchTone forStatus(String raw, {required bool isDark}) {
    final s = raw.trim().toLowerCase();
    if (s == 'matched') {
      final bg = isDark ? const Color(0x2219C37D) : const Color(0xFFE6F7EE);
      return _MatchTone(
        label: 'Matched',
        bg: bg,
        fg: const Color(0xFF1E6B3A),
        border: const Color(0x3319C37D),
        icon: Icons.check_circle_rounded,
      );
    }
    if (s == 'suggested') {
      final bg = isDark ? const Color(0x22FFB300) : const Color(0xFFFFF4E5);
      return _MatchTone(
        label: 'Suggestie Gevonden',
        bg: bg,
        fg: const Color(0xFFB26A00),
        border: const Color(0x33FFB300),
        icon: Icons.warning_rounded,
      );
    }
    final bg = isDark ? const Color(0x22FF3B30) : const Color(0xFFFFE9E9);
    return _MatchTone(
      label: 'Verwerken',
      bg: bg,
      fg: const Color(0xFFB42318),
      border: const Color(0x33FF3B30),
      icon: Icons.error_rounded,
    );
  }
}

class _NoAccessEmptyState extends StatelessWidget {
  const _NoAccessEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF0A0912)
                : const Color(0xFFF5F5F7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, color: cs.onSurface.withValues(alpha: 0.70)),
              const SizedBox(width: 12),
              Flexible(
                child: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0A0912)
            : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
          ),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Opnieuw proberen'),
          ),
        ],
      ),
    );
  }
}

