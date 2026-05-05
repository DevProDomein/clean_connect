import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/user_role.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import '../../../shared/layouts/main_layout.dart';
import 'project_detail_screen.dart';

/// Facilitator-wide overview of active projects / contracts.
class ProjectManagementScreen extends StatefulWidget {
  const ProjectManagementScreen({super.key});

  @override
  State<ProjectManagementScreen> createState() =>
      _ProjectManagementScreenState();
}

class _ProjectManagementScreenState extends State<ProjectManagementScreen> {
  static const double _radius = 24;
  static const Color _navy = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _green = Color(0xFF16A34A);
  static const Color _grey = Color(0xFF94A3B8);
  static const Color _pageBg = Color(0xFFF7F8FB);

  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  DateTime? _parseDate(dynamic v) {
    if (v is DateTime) return v;
    final s = _text(v);
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _fmtDate(dynamic v) {
    final d = _parseDate(v);
    if (d == null) return '—';
    return DateFormat('dd-MM-yyyy').format(d);
  }

  String _clientName(Map<String, dynamic> row) {
    final join = row['bedrijven'];
    if (join is Map) {
      final m = Map<String, dynamic>.from(join);
      final n = _text(m['bedrijfsnaam']);
      if (n.isNotEmpty) return n;
    }
    return 'Onbekende klant';
  }

  String _freqLabel(Map<String, dynamic> row) {
    final f = _text(row['frequentie_type']);
    if (f.isNotEmpty) return f;
    final p = _text(row['periodieke_frequentie']);
    if (p.isNotEmpty) return p;
    return 'Regulier';
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _rows = const [];
          _error = StateError('Niet ingelogd.');
          _loading = false;
        });
      }
      return;
    }

    // Snapshot role before await — [UserProvider] is read synchronously.
    final up = context.read<UserProvider>();
    // Only raw facilitators are scoped; generator/admin see all actieve projecten.
    final isFacilitator = up.role == UserRole.facilitator;

    try {
      var query = AppSupabase.client
          .from('projecten')
          .select('*, bedrijven(bedrijfsnaam)')
          .eq('status', 'actief');

      if (isFacilitator) {
        query = query.eq('facilitator_id', user.id);
      }

      final res = await query.order('aangemaakt_op', ascending: false);
      final list = (res as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _rows = const [];
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((r) {
      final name = _text(r['project_naam']).isEmpty
          ? _text(r['naam'])
          : _text(r['project_naam']);
      final client = _clientName(r).toLowerCase();
      return name.toLowerCase().contains(q) || client.contains(q);
    }).toList();
  }

  Color _statusPillColor(String s) {
    final x = s.toLowerCase();
    if (x == 'actief') return _green;
    if (x == 'afgerond' || x == 'gepauzeerd') return _grey;
    return _grey;
  }

  void _openProjectDetail(String? projectId) {
    final id = _text(projectId);
    if (id.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/facilitator/project-detail'),
        builder: (_) => ProjectDetailScreen(projectId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        backgroundColor: _pageBg,
        drawer: const AppDrawer(),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.black),
          title: Text(
            'Projectbeheer',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: Colors.black,
              letterSpacing: -0.2,
            ),
          ),
        ),
        body: SelectionArea(
          child: _loading
              ? const Center(child: CupertinoActivityIndicator(radius: 16))
              : _error != null
                  ? _buildError()
                  : _buildBody(),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Kon projecten niet laden: $_error',
          textAlign: TextAlign.center,
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w700,
            color: _muted,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final list = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEFF1F5),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: CupertinoSearchTextField(
              controller: _searchCtrl,
              placeholder: 'Zoek op project- of bedrijfsnaam…',
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w600,
                color: _navy,
              ),
              placeholderStyle: GoogleFonts.lato(
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    _rows.isEmpty
                        ? 'Geen actieve projecten gevonden.'
                        : 'Geen resultaten voor deze zoekopdracht.',
                    style: GoogleFonts.lato(
                      fontWeight: FontWeight.w700,
                      color: _muted,
                    ),
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    return _buildCard(list[i]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCard(Map<String, dynamic> p) {
    final naam = _text(p['project_naam']).isEmpty
        ? _text(p['naam'])
        : _text(p['project_naam']);
    final title = naam.isEmpty ? 'Naamloos project' : naam;
    final status = _text(p['status']).isEmpty ? 'actief' : _text(p['status']);
    final client = _clientName(p);
    final freq = _freqLabel(p);
    final start = _fmtDate(p['contract_startdatum']);
    final eind = _fmtDate(p['contract_einddatum']);
    final projectId = _text(p['id']);
    final pillColor = _statusPillColor(status);
    final statusLabel = status[0].toUpperCase() + status.substring(1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: () => _openProjectDetail(projectId),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.lato(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: pillColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.lato(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: pillColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.business_outlined, size: 18, color: _muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        client,
                        style: GoogleFonts.lato(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _navy,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$freq  ·  Start: $start  |  Eind: $eind',
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: _muted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
