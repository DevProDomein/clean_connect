import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/contracts/tickets_contract.dart';
import '../../../core/widgets/app_drawer.dart';
import '../services/tickets_repository.dart';

/// Facilitator Ticket & meldingen triage-hub: KPI's, tabs, kaarten en slide-over.
class TicketOverviewScreen extends StatefulWidget {
  const TicketOverviewScreen({super.key});

  @override
  State<TicketOverviewScreen> createState() => _TicketOverviewScreenState();
}

class _TicketOverviewScreenState extends State<TicketOverviewScreen>
    with SingleTickerProviderStateMixin {
  static const Color _bg = Color(0xFFF5F5F7);
  static const Color _slaBad = Color(0xFFB71C1C);
  static const Color _accentBlue = Color(0xFF2563EB);

  final TicketsRepository _repo = TicketsRepository();
  late TabController _tabController;

  List<Map<String, dynamic>> _vms = [];
  List<Map<String, dynamic>> _staff = [];
  bool _loading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (mounted && !_tabController.indexIsChanging) setState(() {});
      });
    _refresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows = await _repo.fetchTickets();
      final staff = await _repo.fetchStaffForAssignment();
      if (!mounted) return;
      setState(() {
        _vms = rows.map(_repo.normalizeRow).toList();
        _staff = staff;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  bool _isHistorical(Map<String, dynamic> vm) {
    final s = vm['_status'] as String? ?? '';
    return s == 'opgelost' || s == 'gesloten';
  }

  bool _isOpenLike(Map<String, dynamic> vm) => !_isHistorical(vm);

  /// Open + deadline verstreken.
  bool _slaBreached(Map<String, dynamic> vm) {
    if (!_isOpenLike(vm)) return false;
    final sla = vm['_sla'] as DateTime?;
    if (sla == null) return false;
    return DateTime.now().isAfter(sla);
  }

  int _kpiSlaAlarm() => _vms.where((v) => _slaBreached(v)).length;

  int _kpiOpenCount() => _vms.where((v) => _isOpenLike(v)).length;

  int _kpiResolvedThisWeek() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 7));
    return _vms.where((v) {
      if (!_isHistorical(v)) return false;
      final r = v['_resolved'] as DateTime?;
      if (r != null && r.isAfter(start)) return true;
      return false;
    }).length;
  }

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  List<Map<String, dynamic>> _tabItems() {
    final uid = _uid;
    switch (_tabController.index) {
      case 0:
        if (uid == null) return [];
        return _vms.where((v) {
          if (_isHistorical(v)) return false;
          final a = (v['_assignee'] as String?)?.trim() ?? '';
          return a == uid;
        }).toList();
      case 1:
        return _vms.where((v) => _isOpenLike(v)).toList();
      case 2:
        return _vms.where((v) => _isHistorical(v)).toList();
      default:
        return [];
    }
  }

  void _openTicketDetail(Map<String, dynamic> vm) {
    final mq = MediaQuery.sizeOf(context);
    final wide = mq.width >= 720;
    final panelW = math.min(480.0, mq.width * (wide ? 0.42 : 1.0));

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Sluiten',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Theme.of(dialogContext).brightness == Brightness.dark
                  ? const Color(0xFF1C1C1E)
                  : Colors.white,
              elevation: 24,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
              ),
              child: SizedBox(
                width: panelW,
                height: mq.height,
                child: _TicketDetailPanel(
                  vm: vm,
                  staff: _staff,
                  repo: _repo,
                  onSaved: _refresh,
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0912) : _bg;

    return Scaffold(
      backgroundColor: bg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(
          'Tickets & Meldingen',
          style: GoogleFonts.lato(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: GoogleFonts.lato(fontWeight: FontWeight.w800, fontSize: 13),
          unselectedLabelStyle: GoogleFonts.lato(fontWeight: FontWeight.w600, fontSize: 13),
          indicatorColor: _accentBlue,
          labelColor: _accentBlue,
          unselectedLabelColor: Colors.grey.shade600,
          tabs: [
            Tab(text: 'Mijn tickets (${_countMine()})'),
            Tab(text: 'Alle open (${_countAllOpen()})'),
            Tab(text: 'Historie (${_countHist()})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator(radius: 14))
          : _loadError != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      _buildKpiRow(context),
                      const SizedBox(height: 8),
                      ..._tabItems().map((vm) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _TicketCard(
                              vm: vm,
                              onTap: () => _openTicketDetail(vm),
                            ),
                          )),
                      if (_tabItems().isEmpty) _buildEmpty(),
                    ],
                  ),
                ),
    );
  }

  int _countMine() {
    final uid = _uid;
    if (uid == null) return 0;
    return _vms.where((v) => _isOpenLike(v) && (v['_assignee'] as String?) == uid).length;
  }

  int _countAllOpen() => _vms.where((v) => _isOpenLike(v)).length;

  int _countHist() => _vms.where((v) => _isHistorical(v)).length;

  Widget _buildKpiRow(BuildContext context) {
    final mw = MediaQuery.sizeOf(context).width - 40;
    final stack = mw < 520;
    final cards = [
      _KpiCard(
        icon: Icons.local_fire_department_rounded,
        label: 'Actie vereist',
        sub: 'SLA verlopen',
        value: _kpiSlaAlarm().toString(),
        color: _slaBad,
        softBg: const Color(0xFFFFEBEE),
      ),
      _KpiCard(
        icon: Icons.inbox_rounded,
        label: 'Openstaand',
        sub: 'Totaal actief',
        value: _kpiOpenCount().toString(),
        color: const Color(0xFFFF6B35),
        softBg: const Color(0xFFFFF3E0),
      ),
      _KpiCard(
        icon: Icons.check_circle_rounded,
        label: 'Opgelost',
        sub: 'Deze week',
        value: _kpiResolvedThisWeek().toString(),
        color: const Color(0xFF16A34A),
        softBg: const Color(0xFFDCFCE7),
      ),
    ];
    if (stack) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i < cards.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 10),
        Expanded(child: cards[1]),
        const SizedBox(width: 10),
        Expanded(child: cards[2]),
      ],
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Geen tickets in deze weergave.',
              style: GoogleFonts.lato(color: Colors.grey.shade600, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(
              'Tickets konden niet worden geladen.\nControleer de tabel `tickets` en RLS in Supabase.',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              '$_loadError',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _refresh,
              child: const Text('Opnieuw proberen'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- KPI tile ---

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.sub,
    required this.value,
    required this.color,
    required this.softBg,
  });

  final IconData icon;
  final String label;
  final String sub;
  final String value;
  final Color color;
  final Color softBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: softBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.lato(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color.lerp(color, Colors.black, 0.25) ?? color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: GoogleFonts.lato(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.lato(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              color: Color.lerp(color, Colors.black, 0.2) ?? color,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Ticket list card ---

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.vm,
    required this.onTap,
  });

  final Map<String, dynamic> vm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cat = vm['_categorie'] as String? ?? 'overig';
    final IconData ic;
    Color iconBg;
    Color iconFg;
    switch (cat) {
      case 'klacht':
        ic = Icons.warning_rounded;
        iconBg = const Color(0xFFFFEBEE);
        iconFg = const Color(0xFFC62828);
        break;
      case 'technisch':
        ic = Icons.build_rounded;
        iconBg = const Color(0xFFFFF3E0);
        iconFg = const Color(0xFFE65100);
        break;
      case 'voorraad':
        ic = Icons.inventory_2_rounded;
        iconBg = const Color(0xFFE3F2FD);
        iconFg = const Color(0xFF1565C0);
        break;
      default:
        ic = Icons.support_agent_rounded;
        iconBg = Colors.grey.shade200;
        iconFg = Colors.grey.shade800;
    }

    final code = vm['_code'] as String? ?? '';
    final bedrijf = vm['_bedrijf'] as String? ?? '';
    final onderwerp = vm['_onderwerp'] as String? ?? '';
    final status = vm['_status'] as String? ?? 'open';
    final sla = vm['_sla'] as DateTime?;
    final open = status != 'opgelost' && status != 'gesloten';
    late final bool breached;
    if (!open || sla == null) {
      breached = false;
    } else {
      breached = DateTime.now().isAfter(sla);
    }

    final statusNl = _statusNl(status);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: breached ? const Color(0xFFB71C1C).withValues(alpha: 0.55) : Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(ic, color: iconFg, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code,
                        style: GoogleFonts.lato(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.black54,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bedrijf,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.lato(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        onderwerp,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.lato(fontSize: 13, height: 1.25, color: Colors.grey.shade800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusNl,
                        style: GoogleFonts.lato(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey.shade800),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color:
                            breached ? const Color(0xFFB71C1C) : const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _slaPill(open, breached, sla),
                        style: GoogleFonts.lato(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: breached ? Colors.white : const Color(0xFF2E7D32),
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
  }

  String _slaPill(bool open, bool breached, DateTime? sla) {
    if (!open) return sla == null ? 'SLA OK' : 'Afgerond';
    if (sla == null) return 'SLA: —';
    if (breached) return 'SLA verlopen';
    final diff = sla.difference(DateTime.now());
    if (diff.inMinutes <= 0) return 'SLA nu';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h >= 48) return 'SLA: ${diff.inDays} d';
    if (h >= 1) return 'SLA: ${h}u ${m}m';
    return 'SLA: ${diff.inMinutes} min';
  }

  String _statusNl(String s) {
    switch (s) {
      case 'in_behandeling':
        return 'In behandeling';
      case 'opgelost':
        return 'Opgelost';
      case 'gesloten':
        return 'Gesloten';
      default:
        return 'Open';
    }
  }
}

// --- Slide-over dossier ---

class _TicketDetailPanel extends StatefulWidget {
  const _TicketDetailPanel({
    required this.vm,
    required this.staff,
    required this.repo,
    required this.onSaved,
  });

  final Map<String, dynamic> vm;
  final List<Map<String, dynamic>> staff;
  final TicketsRepository repo;
  final Future<void> Function() onSaved;

  @override
  State<_TicketDetailPanel> createState() => _TicketDetailPanelState();
}

class _TicketDetailPanelState extends State<_TicketDetailPanel> {
  bool _busy = false;
  late String _status;
  String? _assignee;

  @override
  void initState() {
    super.initState();
    const ok = {'open', 'in_behandeling', 'opgelost', 'gesloten'};
    final raw = (widget.vm['_status'] as String? ?? 'open').trim();
    _status = ok.contains(raw) ? raw : 'open';
    final a = widget.vm['_assignee'] as String?;
    _assignee = a != null && a.isEmpty ? null : a;
  }

  Future<void> _persist({required Map<String, dynamic> patch}) async {
    final id = widget.vm['_id'] as String? ?? '';
    if (id.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.repo.updateTicket(id, patch);
      await widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opslaan mislukt: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusNormalized() {
    const ok = {'open', 'in_behandeling', 'opgelost', 'gesloten'};
    if (ok.contains(_status)) return _status;
    return 'open';
  }

  @override
  Widget build(BuildContext context) {
    final onderwerp = widget.vm['_onderwerp'] as String? ?? '';
    final bedrijf = widget.vm['_bedrijf'] as String? ?? '';
    final code = widget.vm['_code'] as String? ?? '';
    final bron = widget.vm['_bron'] as String? ?? '';
    final desc = widget.vm['_desc'] as String? ?? '';
    final foto = widget.vm['_foto'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Ticket dossier',
                  style: GoogleFonts.lato(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(code, style: GoogleFonts.lato(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black54)),
              const SizedBox(height: 4),
              Text(bedrijf, style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(onderwerp, style: GoogleFonts.lato(fontSize: 15, fontWeight: FontWeight.w600)),
              if (bron.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Bron: $bron', style: GoogleFonts.lato(fontSize: 12)),
                ),
              ],
              const SizedBox(height: 20),
              Text('Omschrijving', style: GoogleFonts.lato(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                desc.isEmpty ? '—' : desc,
                style: GoogleFonts.lato(fontSize: 14, height: 1.35, color: Colors.black87),
              ),
              if (foto != null && foto.isNotEmpty) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Image.network(
                      foto,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_rounded),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Status',
                style: GoogleFonts.lato(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _statusNormalized(),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('Open')),
                      DropdownMenuItem(value: 'in_behandeling', child: Text('In behandeling')),
                      DropdownMenuItem(value: 'opgelost', child: Text('Opgelost')),
                      DropdownMenuItem(value: 'gesloten', child: Text('Gesloten')),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) async {
                            if (v == null) return;
                            final patch = <String, dynamic>{TicketsTable.status: v};
                            if (v == 'opgelost') {
                              patch[TicketsTable.opgelostOp] = DateTime.now().toUtc().toIso8601String();
                            }
                            setState(() => _status = v);
                            await _persist(patch: patch);
                          },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Toegewezen aan',
                style: GoogleFonts.lato(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    hint: const Text('Niet toegewezen'),
                    value: _assignDropdownValue(widget.staff, _assignee),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    items: _assignMenuItems(widget.staff, _assignee),
                    onChanged: _busy
                        ? null
                        : (v) async {
                            setState(() => _assignee = v);
                            await _persist(
                              patch: {TicketsTable.toegewezenAan: v},
                            );
                          },
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_busy)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
      ],
    );
  }
}

List<DropdownMenuItem<String?>> _assignMenuItems(
    List<Map<String, dynamic>> staff, String? assignee) {
  final ids = staff
      .map((s) => s[GebruikersMetadataTable.id]?.toString() ?? '')
      .where((e) => e.isNotEmpty)
      .toSet();
  final out = <DropdownMenuItem<String?>>[
    const DropdownMenuItem<String?>(
      value: null,
      child: Text('— Niet toegewezen'),
    ),
  ];
  final a = assignee?.trim() ?? '';
  if (a.isNotEmpty && !ids.contains(a)) {
    out.add(
      DropdownMenuItem<String?>(
        value: a,
        child: Text('Toegewezen ($a)', overflow: TextOverflow.ellipsis),
      ),
    );
  }
  for (final s in staff) {
    final id = s[GebruikersMetadataTable.id]?.toString() ?? '';
    if (id.isEmpty) continue;
    final naam = s[GebruikersMetadataTable.naam]?.toString() ?? id;
    out.add(
      DropdownMenuItem<String?>(
        value: id,
        child: Text(naam, overflow: TextOverflow.ellipsis),
      ),
    );
  }
  return out;
}

/// Zorg dat de huidige toewijzing altijd een geldige [DropdownButton] value heeft.
String? _assignDropdownValue(List<Map<String, dynamic>> staff, String? assignee) {
  final a = assignee?.trim() ?? '';
  if (a.isEmpty) return null;
  final ids = staff
      .map((s) => s[GebruikersMetadataTable.id]?.toString() ?? '')
      .where((e) => e.isNotEmpty)
      .toSet();
  if (ids.contains(a)) return a;
  return a;
}
