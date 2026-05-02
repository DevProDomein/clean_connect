import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/models/user_role.dart';
import '../services/accountant_export_service.dart';
import '../../../providers/user_provider.dart';

class PeriodCloseScreen extends StatefulWidget {
  const PeriodCloseScreen({super.key});

  @override
  State<PeriodCloseScreen> createState() => _PeriodCloseScreenState();
}

class _PeriodCloseScreenState extends State<PeriodCloseScreen> {
  Future<List<Map<String, dynamic>>>? _future;
  bool _closingBusy = false;
  final Set<String> _exportBusy = {};

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final res = await AppSupabase.client
        .from('financiele_periodes')
        .select()
        .order('jaar', ascending: false)
        .order('maand', ascending: true);
    return (res as List).cast<Map<String, dynamic>>();
  }

  void _refresh() {
    setState(() {
      _future = _fetch();
    });
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  int _asInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? 0;
  }

  DateTime? _asDate(dynamic v) {
    final s = _text(v);
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  String _monthNameNl(int month) {
    const names = <int, String>{
      1: 'Januari',
      2: 'Februari',
      3: 'Maart',
      4: 'April',
      5: 'Mei',
      6: 'Juni',
      7: 'Juli',
      8: 'Augustus',
      9: 'September',
      10: 'Oktober',
      11: 'November',
      12: 'December',
    };
    return names[month] ?? 'Maand $month';
  }

  Future<void> _closeMonth(Map<String, dynamic> period) async {
    if (_closingBusy) return;

    final id = _text(period['id']);
    if (id.isEmpty) return;

    final jaar = _asInt(period['jaar']);
    final maand = _asInt(period['maand']);
    final label = '${_monthNameNl(maand)} $jaar';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Maand Definitief Afsluiten?',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: Colors.redAccent,
            ),
          ),
          content: Text(
            'Weet u zeker dat u de maand $label wilt afsluiten? Zodra gesloten, beveiligt het systeem deze data voor de accountant. Facturen, inkoop en banktransacties in deze maand kunnen dan NOOIT meer worden gewijzigd.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Bevestig & Vergrendel'),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) return;

    setState(() => _closingBusy = true);
    try {
      final currentUserId = AppSupabase.client.auth.currentUser?.id;
      if (currentUserId == null) throw StateError('Niet ingelogd.');

      await AppSupabase.client.from('financiele_periodes').update({
        'is_afgesloten': true,
        'afgesloten_op': DateTime.now().toIso8601String(),
        'afgesloten_door_id': currentUserId,
      }).eq('id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.92),
          content: const Text('Maand succesvol vergrendeld'),
        ),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon maand niet afsluiten: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _closingBusy = false);
    }
  }

  Future<void> _downloadExport(Map<String, dynamic> period) async {
    final periodId = _text(period['id']);
    if (periodId.isEmpty || _exportBusy.contains(periodId)) return;

    setState(() => _exportBusy.add(periodId));
    try {
      final ok = await AccountantExportService.generateAndDownloadExport(period);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok
              ? Colors.green.withValues(alpha: 0.92)
              : Colors.deepOrange.withValues(alpha: 0.92),
          content: Text(ok ? 'Export succesvol gegenereerd en gelogd.' : 'Kon export niet genereren.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportBusy.remove(periodId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canView = up.isGenerator || up.role == UserRole.administrator;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(
            'Financiële Periodes',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
          actions: [
            IconButton(tooltip: 'Vernieuwen', onPressed: _refresh, icon: const Icon(Icons.refresh)),
          ],
          bottom: TabBar(
            labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
            unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: -0.2),
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: const [
              Tab(text: 'Periodes'),
              Tab(text: 'Export Instellingen'),
            ],
          ),
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
                      border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                    ),
                    child: Text(
                      'U heeft geen rechten om financiële periodes te beheren.',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              )
            : TabBarView(
                children: [
                  _PeriodsTab(
                    future: _future,
                    tileBg: tileBg,
                    softBg: softBg,
                    closingBusy: _closingBusy,
                    closeMonth: _closeMonth,
                    exportBusyIds: _exportBusy,
                    downloadExport: _downloadExport,
                    asInt: _asInt,
                    asDate: _asDate,
                    monthNameNl: _monthNameNl,
                    text: _text,
                  ),
                  const _LedgerMappingTab(),
                ],
              ),
      ),
    );
  }
}

class _PeriodsTab extends StatelessWidget {
  const _PeriodsTab({
    required this.future,
    required this.tileBg,
    required this.softBg,
    required this.closingBusy,
    required this.closeMonth,
    required this.exportBusyIds,
    required this.downloadExport,
    required this.asInt,
    required this.asDate,
    required this.monthNameNl,
    required this.text,
  });

  final Future<List<Map<String, dynamic>>>? future;
  final Color tileBg;
  final Color softBg;
  final bool closingBusy;
  final Future<void> Function(Map<String, dynamic> period) closeMonth;
  final Set<String> exportBusyIds;
  final Future<void> Function(Map<String, dynamic> period) downloadExport;
  final int Function(dynamic v) asInt;
  final DateTime? Function(dynamic v) asDate;
  final String Function(int month) monthNameNl;
  final String Function(dynamic v) text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
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
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              ),
              child: Text('Kan periodes niet laden: ${snapshot.error}'),
            ),
          );
        }

        final rows = snapshot.data ?? const <Map<String, dynamic>>[];

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          children: [
            Text(
              'Financiële Periodes',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Beheer hier de status van uw boekhoudmaanden. Een afgesloten maand wordt cryptografisch vergrendeld en kan niet meer worden gewijzigd.',
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
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                ),
                child: Text(
                  'Geen periodes gevonden.',
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
                  final p = rows[i];
                  final jaar = asInt(p['jaar']);
                  final maand = asInt(p['maand']);
                  final label = '${monthNameNl(maand)} $jaar';

                  final isAfgesloten =
                      p['is_afgesloten'] == true || text(p['is_afgesloten']).toLowerCase() == 'true';
                  final afgeslotenOp = asDate(p['afgesloten_op']);
                  final periodId = text(p['id']);
                  final exporting = exportBusyIds.contains(periodId);

                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: tileBg,
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
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: cs.onSurface.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
                          ),
                          child: Icon(
                            isAfgesloten ? Icons.lock_rounded : Icons.lock_open_rounded,
                            color: isAfgesloten
                                ? const Color(0xFF1E6B3A)
                                : cs.onSurface.withValues(alpha: 0.70),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    isAfgesloten ? Icons.verified_rounded : Icons.info_outline,
                                    size: 16,
                                    color: isAfgesloten
                                        ? const Color(0xFF1E6B3A)
                                        : cs.onSurface.withValues(alpha: 0.55),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      isAfgesloten
                                          ? 'Afgesloten op ${afgeslotenOp == null ? '—' : DateFormat('dd-MM-yyyy').format(afgeslotenOp)}'
                                          : 'Open voor mutaties',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface.withValues(alpha: 0.70),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (isAfgesloten)
                          SizedBox(
                            child: OutlinedButton.icon(
                              onPressed: (periodId.isEmpty || exporting) ? null : () => downloadExport(p),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                side: BorderSide(color: cs.onSurface.withValues(alpha: 0.16)),
                              ),
                              icon: exporting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.download_rounded),
                              label: Text(
                                '📥 Download CSV Export',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                              ),
                            ),
                          )
                        else
                          FilledButton(
                            onPressed: closingBusy ? null : () => closeMonth(p),
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            child: closingBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Text(
                                    'Sluit Maand',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
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
    );
  }
}

class _LedgerMappingTab extends StatefulWidget {
  const _LedgerMappingTab();

  @override
  State<_LedgerMappingTab> createState() => _LedgerMappingTabState();
}

class _LedgerMappingTabState extends State<_LedgerMappingTab> {
  Future<_LedgerMappingData>? _future;
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, Timer> _debounce = {};

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final t in _debounce.values) {
      t.cancel();
    }
    super.dispose();
  }

  Future<_LedgerMappingData> _fetch() async {
    final internal = await _fetchInternalLedgers();

    final mappingRes =
        await AppSupabase.client.from('grootboek_export_mapping').select('interne_code, accountant_code');
    final mappingRows = (mappingRes as List).cast<Map<String, dynamic>>();
    final mapping = <String, String>{};
    for (final r in mappingRows) {
      final k = (r['interne_code'] ?? '').toString().trim();
      final v = (r['accountant_code'] ?? '').toString().trim();
      if (k.isNotEmpty && v.isNotEmpty) mapping[k] = v;
    }

    return _LedgerMappingData(
      internalLedgers: internal,
      existingMapping: mapping,
    );
  }

  Future<List<String>> _fetchInternalLedgers() async {
    final candidates = <Future<List<String>> Function()>[
      () async {
        final res = await AppSupabase.client.from('grootboek_artikelen').select('artikel_code, omschrijving');
        final rows = (res as List).cast<Map<String, dynamic>>();
        return rows
            .map((r) => ((r['artikel_code'] ?? r['omschrijving'] ?? '')).toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
      },
      () async {
        final res = await AppSupabase.client.from('diensten').select('artikel_code, omschrijving');
        final rows = (res as List).cast<Map<String, dynamic>>();
        return rows
            .map((r) => ((r['artikel_code'] ?? r['omschrijving'] ?? '')).toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
      },
      () async {
        final res = await AppSupabase.client.from('factuur_regels').select('artikel_code, omschrijving');
        final rows = (res as List).cast<Map<String, dynamic>>();
        return rows
            .map((r) => ((r['artikel_code'] ?? r['omschrijving'] ?? '')).toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
      },
    ];

    for (final fn in candidates) {
      try {
        final out = await fn();
        if (out.isNotEmpty) return out;
      } catch (_) {}
    }
    return const <String>[];
  }

  void _scheduleUpsert(String interneCode, String value) {
    _debounce[interneCode]?.cancel();
    _debounce[interneCode] = Timer(const Duration(milliseconds: 450), () async {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        try {
          await AppSupabase.client
              .from('grootboek_export_mapping')
              .delete()
              .eq('interne_code', interneCode);
        } catch (_) {}
        return;
      }

      await AppSupabase.client.from('grootboek_export_mapping').upsert(
        {
          'interne_code': interneCode,
          'accountant_code': trimmed,
        },
        onConflict: 'interne_code',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    return FutureBuilder<_LedgerMappingData>(
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
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              ),
              child: Text('Kan mapping niet laden: ${snapshot.error}'),
            ),
          );
        }

        final data = snapshot.data ??
            const _LedgerMappingData(internalLedgers: <String>[], existingMapping: <String, String>{});
        final items = data.internalLedgers;

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          children: [
            Text(
              'Export Instellingen',
              style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4),
            ),
            const SizedBox(height: 8),
            Text(
              'Koppel interne codes aan accountant grootboekcodes (XAF/CSV export). Wijzigingen worden automatisch opgeslagen.',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.70),
              ),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: softBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                ),
                child: Text(
                  'Geen interne codes gevonden (controleer `grootboek_artikelen` / `diensten`).',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              )
            else
              ListView.separated(
                itemCount: items.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder: (_, i) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final interne = items[i];
                  final existing = data.existingMapping[interne] ?? '';
                  final ctrl = _ctrls.putIfAbsent(interne, () => TextEditingController(text: existing));

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: tileBg,
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
                          child: Text(
                            interne,
                            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 160,
                          child: TextField(
                            controller: ctrl,
                            onChanged: (v) => _scheduleUpsert(interne, v),
                            decoration: InputDecoration(
                              labelText: 'Accountant code',
                              hintText: '8000',
                              filled: true,
                              fillColor: softBg,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
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
    );
  }
}

class _LedgerMappingData {
  const _LedgerMappingData({
    required this.internalLedgers,
    required this.existingMapping,
  });

  final List<String> internalLedgers;
  final Map<String, String> existingMapping;
}

