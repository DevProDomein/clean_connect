import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/user_role.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import '../services/contracts_dashboard_repository.dart';

/// Facilitator: contractportfolio — KPI-radar, verkeerslicht-lijst en snelle acties.
class ContractManagementScreen extends StatefulWidget {
  const ContractManagementScreen({super.key});

  @override
  State<ContractManagementScreen> createState() => _ContractManagementScreenState();
}

class _ContractManagementScreenState extends State<ContractManagementScreen> {
  static const _bg = Color(0xFFF5F5F7);

  final _repo = ContractsDashboardRepository();

  List<Map<String, dynamic>> _vms = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final u = Supabase.instance.client.auth.currentUser;
    if (u == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Niet ingelogd.';
        });
      }
      return;
    }
    final fac = context.read<UserProvider>().role == UserRole.facilitator;

    try {
      final rows = await _repo.fetchDashboardRows(userId: u.id, facilitatorOnly: fac);
      final vms = rows.map(_repo.normalizeVm).where((vm) => vm['project_id'] != null).toList();

      int cmpVm(Map<String, dynamic> a, Map<String, dynamic> b) {
        final da = a['days_left'] as int?;
        final db = b['days_left'] as int?;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      }

      vms.sort(cmpVm);
      if (!mounted) return;
      setState(() {
        _vms = vms;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Rood ≤30 of verstreken · Oranje ≤90 · Groen >90
  Traffic _traffic(int? d) {
    if (d == null) return Traffic.green;
    if (d < 0 || d <= 30) return Traffic.red;
    if (d <= 90) return Traffic.orange;
    return Traffic.green;
  }

  int get _kpiAflopen90 =>
      _vms.where((vm) => (vm['days_left'] as int?) != null && (vm['days_left'] as int) <= 90).length;

  double get _kpiMrr {
    var s = 0.0;
    for (final vm in _vms) {
      if (vm['is_vast'] == true) {
        s += (vm['mrr'] as num?)?.toDouble() ?? 0;
      }
    }
    return s;
  }

  int get _kpiIndexatie =>
      _vms.where((vm) => vm['is_vast'] == true && vm['needs_index'] == true).length;

  String _money(double v) => NumberFormat.currency(locale: 'nl_NL', symbol: '€').format(v);

  Future<void> _pickYearsAndExtend(Map<String, dynamic> vm) async {
    var years = 1;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return SelectionArea(
          child: StatefulBuilder(
            builder: (ctx, setDlg) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Text(
                  'Contract verlengen',
                  style: GoogleFonts.lato(fontWeight: FontWeight.w900),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Met hoeveel jaar wilt u dit contract laten doorlopen?',
                      style: GoogleFonts.lato(height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            min: 1,
                            max: 7,
                            divisions: 6,
                            value: years.toDouble(),
                            label: '$years jr',
                            onChanged: (v) => setDlg(() => years = v.round()),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text('$years jr', style: GoogleFonts.lato(fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleer')),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        await _repo.extendProjectEndDate(
                          projectId: vm['project_id'] as String,
                          yearsToAdd: years,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Contract verlengd met $years jaar.'),
                            backgroundColor: Colors.green.shade700,
                          ),
                        );
                        await _load();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mislukt: $e')));
                      }
                    },
                    child: Text('Opslaan', style: GoogleFonts.lato(fontWeight: FontWeight.w800)),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _indexDialog(Map<String, dynamic> vm) async {
    final oid = vm['offerte_id'] as String?;
    if (oid == null || oid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geen gekoppelde offerte voor tariefindexatie.')),
      );
      return;
    }
    final ctl = TextEditingController(text: '3,5');
    final pct = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Indexatie toepassen', style: GoogleFonts.lato(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Met welk percentage wilt u de maandtarieven verhogen? (bv. CAO)',
              style: GoogleFonts.lato(height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Percentage (+)',
                suffixText: '%',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleer'),
          ),
          FilledButton(
            onPressed: () {
              final raw = ctl.text.trim().replaceAll(',', '.').replaceAll('%', '');
              final p = double.tryParse(raw);
              if (p == null || p <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Percentage ongeldig.')),
                );
                return;
              }
              Navigator.pop(ctx, p);
            },
            child: Text('Pas indexatie toe', style: GoogleFonts.lato(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (!mounted || pct == null || pct <= 0) return;
    try {
      await _repo.indexOffertePrices(offerteId: oid, pctIncrease: pct);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tarieven bijgewerkt met $pct%'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mislukt: $e')));
    }
  }

  Future<void> _confirmTerminate(Map<String, dynamic> vm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Contract opzeggen', style: GoogleFonts.lato(fontWeight: FontWeight.w900)),
        content: Text(
          'We markeren dit project als beëindigd. Automatische planning stopt na de einddatum. Doorgaan?',
          style: GoogleFonts.lato(height: 1.35),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleer')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB71C1C)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Beëindigen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.terminateProject(vm['project_id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Project ${vm["project_naam"]} beëindigd.'),
          backgroundColor: Colors.grey.shade800,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mislukt: $e')));
    }
  }

  void _sheetActions(Map<String, dynamic> vm) {
    final name = '${vm["klant_naam"] ?? ""} • ${vm["project_naam"] ?? ""}';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final padBottom = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 16 + padBottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Snelle acties', style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 8),
              Text(name, style: GoogleFonts.lato(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 20),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Icon(Icons.calendar_month_rounded, color: Colors.blue.shade700),
                title: Text('Verlengen', style: GoogleFonts.lato(fontWeight: FontWeight.w800)),
                subtitle: const Text('Einddatum verschuiven met extra jaren'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickYearsAndExtend(vm);
                },
              ),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Icon(Icons.trending_up_rounded, color: Colors.orange.shade800),
                title: Text('Indexeren', style: GoogleFonts.lato(fontWeight: FontWeight.w800)),
                subtitle: const Text('Prijsverhoging op maandtarief'),
                onTap: () {
                  Navigator.pop(ctx);
                  _indexDialog(vm);
                },
              ),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Icon(Icons.block_rounded, color: Colors.red.shade700),
                title: Text('Opzeggen', style: GoogleFonts.lato(fontWeight: FontWeight.w800)),
                subtitle: const Text('Project als beeindigd markeren'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmTerminate(vm);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0A0912) : _bg;

    return Scaffold(
      backgroundColor: bg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Contractbeheer', style: GoogleFonts.lato(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator(radius: 14))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Kon contracten niet laden', style: GoogleFonts.lato(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        SelectableText('$_error'),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Opnieuw')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _kpiRadar(),
                      const SizedBox(height: 14),
                      Text(
                        'Portfolio (meest urgent eerst)',
                        style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 10),
                      if (_vms.isEmpty) ...[
                        const SizedBox(height: 40),
                        _emptyHint(),
                      ] else ...[
                        for (final vm in _vms)
                          _ContractCard(
                            vm: vm,
                            traffic: _traffic(vm['days_left'] as int?),
                            onTap: () => _sheetActions(vm),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _kpiRadar() {
    return LayoutBuilder(
      builder: (ctx, bc) {
        final stack = bc.maxWidth < 580;
        final k1 = _KpiRadarTile(
          icon: Icons.warning_amber_rounded,
          title: 'Aflopend <90d',
          value: _kpiAflopen90.toString(),
          caption: 'Verlopen of binnen 90 dagen',
          color: const Color(0xFFB71C1C),
          tint: const Color(0xFFFFEBEE),
        );
        final k2 = _KpiRadarTile(
          icon: Icons.euro_rounded,
          title: 'MRR (vast)',
          value: _money(_kpiMrr),
          caption: 'Schatting maandomzet',
          color: const Color(0xFF2563EB),
          tint: const Color(0xFFE3F2FD),
        );
        final k3 = _KpiRadarTile(
          icon: Icons.show_chart_rounded,
          title: 'Indexeren open',
          value: _kpiIndexatie.toString(),
          caption: '>1 jr zonder stap',
          color: const Color(0xFF7B1FA2),
          tint: const Color(0xFFF3E5F5),
        );
        if (stack) {
          return Column(
            children: [
              k1,
              const SizedBox(height: 10),
              k2,
              const SizedBox(height: 10),
              k3,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: k1),
            const SizedBox(width: 10),
            Expanded(child: k2),
            const SizedBox(width: 10),
            Expanded(child: k3),
          ],
        );
      },
    );
  }

  Widget _emptyHint() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Geen actieve contracten gevonden.\n(Optioneel VIEW app_contracten_dashboard in Supabase voor snelle aggregaties.)',
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(color: Colors.grey.shade700, height: 1.35),
          ),
        ),
      );
}

enum Traffic { red, orange, green }

class _KpiRadarTile extends StatelessWidget {
  const _KpiRadarTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.caption,
    required this.color,
    required this.tint,
  });

  final IconData icon;
  final String title;
  final String value;
  final String caption;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 13, color: color.withValues(alpha: 0.95)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(value, style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 22)),
            const SizedBox(height: 6),
            Text(
              caption,
              style: GoogleFonts.lato(fontSize: 11.5, height: 1.25, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContractCard extends StatelessWidget {
  const _ContractCard({
    required this.vm,
    required this.traffic,
    required this.onTap,
  });

  final Map<String, dynamic> vm;
  final Traffic traffic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nl = DateFormat('dd-MM-yyyy', 'nl');
    final start = vm['start'] as DateTime?;
    final end = vm['einde'] as DateTime?;

    Color ring;
    switch (traffic) {
      case Traffic.red:
        ring = const Color(0xFFB71C1C);
        break;
      case Traffic.orange:
        ring = const Color(0xFFE65100);
        break;
      case Traffic.green:
        ring = const Color(0xFF2E7D32);
    }

    final mrrNum = vm['mrr'] as num? ?? 0;
    final vast = vm['is_vast'] == true;
    final f = NumberFormat.currency(locale: 'nl_NL', symbol: '€');

    final startS = start != null ? nl.format(start) : '—';
    final endS = end != null ? nl.format(end) : '—';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white,
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.045),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: ring, width: 3),
                        ),
                        child: Icon(Icons.folder_special_rounded, color: ring, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vm['klant_naam'] as String? ?? '—',
                              style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              vm['project_naam'] as String? ?? 'Project',
                              style: GoogleFonts.lato(fontWeight: FontWeight.w600, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                      Chip(
                        backgroundColor: ring.withValues(alpha: 0.12),
                        side: BorderSide.none,
                        label: Text(
                          traffic == Traffic.red
                              ? 'Kritiek'
                              : traffic == Traffic.orange
                                  ? '<90d'
                                  : 'OK',
                          style: GoogleFonts.lato(fontWeight: FontWeight.w800, fontSize: 11, color: ring),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Looptijd: $startS t/m $endS',
                          style: GoogleFonts.lato(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (vm['days_left'] != null)
                        Text(
                          '${vm["days_left"]} dagen',
                          style: GoogleFonts.lato(fontSize: 12, color: Colors.black54),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.payments_rounded, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          vast
                              ? 'Maandwaarde: ${f.format(mrrNum.toDouble())}'
                              : 'Flexibel • geen vaste maandbundel',
                          style: GoogleFonts.lato(fontSize: 13),
                        ),
                      ),
                      if (vm['needs_index'] == true)
                        Text(
                          'Index',
                          style: GoogleFonts.lato(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.deepPurple.shade700),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
