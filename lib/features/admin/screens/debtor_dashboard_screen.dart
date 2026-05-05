import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';

class DebtorDashboardScreen extends StatefulWidget {
  const DebtorDashboardScreen({super.key});

  @override
  State<DebtorDashboardScreen> createState() => _DebtorDashboardScreenState();
}

class _DebtorDashboardScreenState extends State<DebtorDashboardScreen> {
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final res = await AppSupabase.client.from('app_debiteuren_escalatie_lijst').select();
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

  int _asInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? 0;
  }

  DateTime? _asDate(dynamic v) {
    final s = _text(v);
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  NumberFormat _eur() => NumberFormat.currency(locale: 'nl_NL', symbol: '€', decimalDigits: 2);

  Future<void> _snooze(Map<String, dynamic> row) async {
    final id = _text(row['factuur_id'] ?? row['id']);
    if (id.isEmpty) return;

    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Pauzeer tot',
    );
    if (picked == null) return;

    try {
      await AppSupabase.client
          .from('facturen')
          .update({'dunning_pauze_tot': picked.toIso8601String()})
          .eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.92),
          content: Text('Factuur gepauzeerd tot ${DateFormat('dd-MM-yyyy').format(picked)}.'),
        ),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon niet pauzeren: $e'),
        ),
      );
    }
  }

  Future<void> _sendReminder(Map<String, dynamic> row) async {
    final id = _text(row['factuur_id'] ?? row['id']);
    if (id.isEmpty) return;

    final currentDunning = _text(row['dunning_status']).toLowerCase();
    final newDunning = currentDunning == 'herinnering_1' ? 'aanmaning' : 'herinnering_1';

    try {
      await AppSupabase.client.from('facturen').update({
        'dunning_status': newDunning,
      }).eq('id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.92),
          content: const Text('Status bijgewerkt'),
        ),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon herinnering niet versturen: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canView = up.isGenerator || up.hasPermission('finance');

    if (!canView) {
      return Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(
            'Debiteurenbeheer',
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
          'Debiteurenbeheer',
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
                  child: Text('Kan lijst niet laden: ${snapshot.error}'),
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
                      'Geen achterstallige facturen gevonden.',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              itemCount: rows.length,
              separatorBuilder: (_, i) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final r = rows[i];
                final klant = _text(
                  r['bedrijfsnaam'] ??
                      r['debiteur_naam'] ??
                      r['klant_naam'] ??
                      r['bedrijf'],
                );
                final nr = _text(r['factuur_nummer']);
                final dagen = _asInt(r['dagen_te_laat'] ?? r['days_overdue']);
                final open = _asDouble(r['openstaand_saldo']);
                final advies = _text(r['escalatie_advies']);
                final pauzeTot = _asDate(r['dunning_pauze_tot']);
                final isPaused =
                    pauzeTot != null && pauzeTot.isAfter(DateTime.now());

                final badge = _AdviceTone.forAdvice(advies, isDark: isDark);
                final effectiveOpacity = isPaused ? 0.60 : 1.0;

                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: tileBg.withValues(alpha: effectiveOpacity),
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
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
                          Expanded(
                            child: Text(
                              klant.isEmpty ? 'Onbekende Klant' : klant,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (isPaused) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: cs.onSurface.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Text(
                                'Gepauzeerd',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.1,
                                  color: cs.onSurface.withValues(alpha: 0.75),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
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
                      const SizedBox(height: 6),
                      Text(
                        [if (nr.isNotEmpty) nr].join(' • '),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniStat(
                              label: 'Dagen te laat',
                              value: '$dagen',
                              valueColor:
                                  dagen > 0 ? Colors.redAccent : cs.onSurface,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MiniStat(
                              label: 'Open bedrag',
                              value: _eur().format(open),
                              valueColor: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _snooze(r),
                              icon: const Icon(Icons.snooze_rounded),
                              label: const Text('Pauzeer (Regeling)'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _sendReminder(r),
                              icon: const Icon(Icons.send_rounded),
                              label: const Text('Verstuur Herinnering'),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AdviceTone {
  const _AdviceTone({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
  });

  final String label;
  final Color bg;
  final Color fg;
  final Color border;

  static _AdviceTone forAdvice(String raw, {required bool isDark}) {
    final s = raw.trim();
    final bg = isDark ? const Color(0x22FFB300) : const Color(0xFFFFF4E5);
    return _AdviceTone(
      label: s.isEmpty ? 'Escalatie' : s,
      bg: bg,
      fg: const Color(0xFFB26A00),
      border: const Color(0x33FFB300),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.valueColor});

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

