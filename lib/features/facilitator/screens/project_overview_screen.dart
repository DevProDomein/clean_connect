import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/user_role.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/network_image_fallback.dart';
import '../../../core/supabase_client.dart';
import '../../../providers/user_provider.dart';
import 'project_create_header_screen.dart';
import 'project_detail_screen.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';

/// Facilitator project portfolio: KPIs, server-driven filters, actieve [projecten].
class ProjectOverviewScreen extends StatefulWidget {
  const ProjectOverviewScreen({super.key});

  @override
  State<ProjectOverviewScreen> createState() => _ProjectOverviewScreenState();
}

class _ProjectOverviewScreenState extends State<ProjectOverviewScreen> {
  static const double _radius = 24;
  static const Color _navy = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _blue = Color(0xFF2563EB);
  static const Color _green = Color(0xFF16A34A);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _pageBg = Color(0xFFF7F8FB);
  static const Color _orange = Color(0xFFFF6B35);
  static const List<String> _regioOptions = [
    'Amsterdam',
    "'t Gooi",
    'Stichtse Vecht',
    'Utrecht',
    'Amersfoort',
    'De Ronde Venen',
    'Wijdemeren',
  ];

  // Filters (spec)
  String _searchQuery = '';
  String? _filterKlantId;
  String? _filterRegio;
  String? _filterFrequentie; // regulier | frequent | periodiek
  String? _filterContractType; // vast | flexibel | eenmalig
  bool _showFilters = true;

  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _projects = const [];
  List<Map<String, dynamic>> _filterKlanten = const [];
  bool _loading = true;
  bool _loadingKlanten = false;
  Object? _error;
  String? _fetchFallbackNote;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchDebounce);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _showFilters = MediaQuery.of(context).size.width > 800;
        });
      }
      _fetchProjects();
      _loadFilterKlanten();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchDebounce);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchDebounce() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      final next = _searchCtrl.text.trim();
      if (next == _searchQuery) return;
      _searchQuery = next;
      _fetchProjects();
    });
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(_text(v).replaceAll(',', '.')) ?? 0;
  }

  DateTime? _parseDate(dynamic v) {
    if (v is DateTime) return v;
    return DateTime.tryParse(_text(v));
  }

  bool _canAccess() {
    final up = context.read<UserProvider>();
    return up.hasPermission('portal_facilitator') ||
        up.roleString == 'administrator' ||
        up.roleString == 'generator' ||
        up.roleString == 'facilitator';
  }

  Map<String, dynamic>? _offerteFromRow(Map<String, dynamic> p) {
    final o = p['offertes'];
    if (o is Map) return Map<String, dynamic>.from(o);
    if (o is List && o.isNotEmpty) {
      final f = o.first;
      if (f is Map) return Map<String, dynamic>.from(f);
    }
    return null;
  }

  String _clientName(Map<String, dynamic> row) {
    final b = row['bedrijven'];
    if (b is Map) {
      return _text(b['bedrijfsnaam']).isEmpty ? '—' : _text(b['bedrijfsnaam']);
    }
    return '—';
  }

  String? _bedrijfLogoUrl(Map<String, dynamic> row) {
    final b = row['bedrijven'];
    if (b is Map) {
      final u = _text(b['logo_url']);
      return u.isEmpty ? null : u;
    }
    return null;
  }

  String? _pandFotoUrl(Map<String, dynamic> row) {
    final u = _text(row['pand_foto_url']);
    return u.isEmpty ? null : u;
  }

  // ---------------- KPIs (local, after fetch) ----------------
  int get _kpiActieveContracten => _projects.length;

  double get _kpiWekelijkseUren {
    var s = 0.0;
    for (final p in _projects) {
      if (_text(p['frequentie_type']).toLowerCase() == 'regulier') {
        s += _asDouble(p['basis_uren_per_opdracht']);
      }
    }
    return s;
  }

  String get _kpiUrenLabel {
    final v = _kpiWekelijkseUren;
    if ((v - v.round()).abs() < 0.001) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  int get _kpiNieuwDezeMaand {
    final now = DateTime.now();
    var n = 0;
    for (final p in _projects) {
      final d = _parseDate(p['contract_startdatum']) ?? _parseDate(p['start_datum']);
      if (d != null && d.year == now.year && d.month == now.month) n++;
    }
    return n;
  }

  // ---------------- Fetches (no async in setState) ----------------
  Future<void> _loadFilterKlanten() async {
    final u = Supabase.instance.client.auth.currentUser;
    if (u == null) return;
    if (!mounted) return;
    setState(() => _loadingKlanten = true);
    try {
      var q = AppSupabase.client
          .from('bedrijven')
          .select('id, bedrijfsnaam')
          .eq('is_klant', true);
      final up = context.read<UserProvider>();
      if (up.role == UserRole.facilitator) {
        q = q.eq('betrokken_facilitator_id', u.id);
      }
      final res = await q.order('bedrijfsnaam', ascending: true);
      final list = (res as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _filterKlanten = list;
        _loadingKlanten = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _filterKlanten = const [];
          _loadingKlanten = false;
        });
      }
    }
  }

  Future<void> _fetchProjects() async {
    if (!mounted) return;
    if (!_canAccess()) {
      setState(() => _loading = false);
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _error = 'Niet ingelogd.';
          _loading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _fetchFallbackNote = null;
      });
    }

    final up = context.read<UserProvider>();
    final isFac = up.roleString == 'facilitator';

    const selectWithJoins =
        '*, bedrijven!inner(id, bedrijfsnaam, logo_url), offertes(contract_type)';

    PostgrestFilterBuilder<dynamic> buildQuery(String select) {
      dynamic q = AppSupabase.client
          .from('projecten')
          .select(select)
          .eq('status', 'actief');
      if (isFac) {
        q = q.eq('facilitator_id', user.id);
      }
      if (_searchQuery.isNotEmpty) {
        final esc = _searchQuery.replaceAll('%', r'\%');
        q = q.ilike('project_naam', '%$esc%');
      }
      if (_filterKlantId != null) {
        q = q.eq('bedrijf_id', _filterKlantId!);
      }
      if (_filterRegio != null) {
        q = q.eq('werk_regio', _filterRegio!);
      }
      if (_filterFrequentie != null) {
        q = q.eq('frequentie_type', _filterFrequentie!);
      }
      if (_filterContractType != null) {
        q = q.filter('offertes.contract_type', 'eq', _filterContractType!);
      }
      return q.order('aangemaakt_op', ascending: false) as PostgrestFilterBuilder<dynamic>;
    }

    try {
      final res = await buildQuery(selectWithJoins);
      List<Map<String, dynamic>> list = (res as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _projects = list;
        _loading = false;
      });
    } catch (e) {
      // Broader select without inner (missing FKs / RLS) then client filter contract.
      try {
        const selectLoose = selectWithJoins;
        dynamic q = AppSupabase.client
            .from('projecten')
            .select(selectLoose)
            .eq('status', 'actief');
        if (isFac) q = q.eq('facilitator_id', user.id);
        if (_searchQuery.isNotEmpty) {
          final esc = _searchQuery.replaceAll('%', r'\%');
          q = q.ilike('project_naam', '%$esc%');
        }
        if (_filterKlantId != null) q = q.eq('bedrijf_id', _filterKlantId!);
        if (_filterRegio != null) q = q.eq('werk_regio', _filterRegio!);
        if (_filterFrequentie != null) {
          q = q.eq('frequentie_type', _filterFrequentie!);
        }
        final res2 = await q.order('aangemaakt_op', ascending: false);
        var list2 = (res2 as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (_filterContractType != null) {
          list2 = list2.where((p) {
            final c = _text(_offerteFromRow(p)?['contract_type']).toLowerCase();
            return c == _filterContractType;
          }).toList();
        }
        if (!mounted) return;
        setState(() {
          _projects = list2;
          _fetchFallbackNote =
              'Contractfilter lokaal toegepast (verbinding offerte).';
          _loading = false;
        });
      } catch (e2) {
        if (!mounted) return;
        setState(() {
          _error = e2;
          _projects = const [];
          _loading = false;
        });
      }
    }
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    _searchQuery = '';
    _searchCtrl.clear();
    setState(() {
      _filterKlantId = null;
      _filterRegio = null;
      _filterFrequentie = null;
      _filterContractType = null;
    });
    _fetchProjects();
  }

  Future<void> _newProject() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/facilitator/projects/new'),
        builder: (_) => const ProjectCreateHeaderScreen(),
      ),
    );

    if (!mounted) return;
    if (result == true) {
      _fetchProjects();
    }
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
    if (!_canAccess()) {
      return Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text('Projecten',
              style: GoogleFonts.lato(fontWeight: FontWeight.w900)),
        ),
        body: SelectionArea(
          child: Center(
            child: Text(
              'Geen toegang tot projectoverzicht.',
              style: GoogleFonts.lato(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _pageBg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: _navy),
        title: Text(
          'Projecten',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            letterSpacing: -0.2,
            color: _navy,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading
                ? null
                : () {
                    _loadFilterKlanten();
                    _fetchProjects();
                  },
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 85),
        child: FloatingActionButton.extended(
          onPressed: _newProject,
          backgroundColor: _orange,
          foregroundColor: Colors.white,
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          icon: const Icon(Icons.add_rounded, size: 26),
          label: Text(
            'Nieuw Project',
            style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ),
      ),
      body: SelectionArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator(radius: 16))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Laden mislukt: $_error',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(color: _muted),
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildKpiRow(),
                      if (_fetchFallbackNote != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            _fetchFallbackNote!,
                            style: GoogleFonts.lato(
                              fontSize: 12,
                              color: _amber,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      _buildFilterBar(),
                      Expanded(child: _buildProjectList()),
                    ],
                  ),
      ),
    );
  }

  Widget _buildKpiRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _kpiCard(
              icon: Icons.assignment_turned_in_outlined,
              iconBg: _blue.withValues(alpha: 0.12),
              iconColor: _blue,
              label: 'Actieve Contracten',
              value: '$_kpiActieveContracten',
            ),
            const SizedBox(width: 12),
            _kpiCard(
              icon: Icons.schedule_outlined,
              iconBg: _green.withValues(alpha: 0.12),
              iconColor: _green,
              label: 'Wekelijkse Uren',
              value: _kpiUrenLabel,
              sub: 'regulier',
            ),
            const SizedBox(width: 12),
            _kpiCard(
              icon: Icons.fiber_new_rounded,
              iconBg: _amber.withValues(alpha: 0.14),
              iconColor: _amber,
              label: 'Nieuw Deze Maand',
              value: '$_kpiNieuwDezeMaand',
              sub: DateFormat('MMMM yyyy').format(DateTime.now()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required String value,
    String? sub,
  }) {
    return Container(
      width: 200,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.lato(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: _muted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: GoogleFonts.lato(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                height: 1.05,
                letterSpacing: -0.8,
                color: _navy,
              ),
            ),
          ),
          if (sub != null)
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.lato(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final isMobile = MediaQuery.of(context).size.width < 800;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isMobile)
              OutlinedButton(
                onPressed: () => setState(() => _showFilters = !_showFilters),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  _showFilters ? 'Filters & Zoeken verbergen' : 'Filters & Zoeken tonen',
                  style: GoogleFonts.lato(fontWeight: FontWeight.w900),
                ),
              ),
            if (isMobile) const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _fetchProjects(),
              style: GoogleFonts.lato(
                  fontWeight: FontWeight.w600, color: _navy, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Zoek op projectnaam…',
                hintStyle: GoogleFonts.lato(color: _muted),
                prefixIcon: const Icon(Icons.search_rounded, color: _muted),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 8),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: _showFilters ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              secondChild: const SizedBox.shrink(),
              firstChild: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: isMobile ? 8 : 10,
                    runSpacing: isMobile ? 8 : 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 200,
                        child: _smallDropdown<String?>(
                          label: 'Klant',
                          // ignore: deprecated_member_use
                          value: _filterKlantId,
                          items: [
                            const DropdownMenuItem<String?>(
                                value: null, child: Text('Alle klanten')),
                            ..._filterKlanten.map(
                              (b) => DropdownMenuItem<String?>(
                                value: _text(b['id']),
                                child: Text(
                                  _text(b['bedrijfsnaam']),
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                          onChanged: _loadingKlanten
                              ? null
                              : (v) {
                                  setState(() => _filterKlantId = v);
                                  _fetchProjects();
                                },
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: _smallDropdown<String?>(
                          label: 'Regio',
                          // ignore: deprecated_member_use
                          value: _filterRegio,
                          items: [
                            const DropdownMenuItem<String?>(
                                value: null, child: Text('Alle regio’s')),
                            ..._regioOptions.map(
                              (r) => DropdownMenuItem<String?>(
                                  value: r, child: Text(r)),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() => _filterRegio = v);
                            _fetchProjects();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: _smallDropdown<String?>(
                          label: isMobile ? 'Freq.' : 'Frequentie',
                          // ignore: deprecated_member_use
                          value: _filterFrequentie,
                          items: const [
                            DropdownMenuItem(
                                value: null, child: Text('Alle')),
                            DropdownMenuItem(
                                value: 'regulier', child: Text('regulier')),
                            DropdownMenuItem(
                                value: 'frequent', child: Text('frequent')),
                            DropdownMenuItem(
                                value: 'periodiek', child: Text('periodiek')),
                          ],
                          onChanged: (v) {
                            setState(() => _filterFrequentie = v);
                            _fetchProjects();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: _smallDropdown<String?>(
                          label: isMobile ? 'Type' : 'Contract',
                          // ignore: deprecated_member_use
                          value: _filterContractType,
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Alle')),
                            DropdownMenuItem(value: 'vast', child: Text('vast')),
                            DropdownMenuItem(
                                value: 'flexibel', child: Text('flexibel')),
                            DropdownMenuItem(
                                value: 'eenmalig', child: Text('eenmalig')),
                          ],
                          onChanged: (v) {
                            setState(() => _filterContractType = v);
                            _fetchProjects();
                          },
                        ),
                      ),
                      if (isMobile)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _fetchProjects,
                            child: Text(
                              'Zoek',
                              style: GoogleFonts.lato(fontWeight: FontWeight.w900),
                            ),
                          ),
                        )
                      else
                        TextButton(
                          onPressed: _clearFilters,
                          child: Text(
                            'Filters wissen',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w900,
                              color: _blue,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      if (isMobile)
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: _clearFilters,
                            child: Text(
                              'Filters wissen',
                              style: GoogleFonts.lato(
                                fontWeight: FontWeight.w900,
                                color: _blue,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return DropdownButtonFormField<T>(
      // ignore: deprecated_member_use
      value: value,
      isExpanded: true,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.lato(
            fontSize: 12, fontWeight: FontWeight.w800, color: _muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _muted.withValues(alpha: 0.2))),
        filled: true,
        fillColor: Colors.white,
      ),
      style: GoogleFonts.lato(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildProjectList() {
    if (_projects.isEmpty) {
      return Center(
        child: Text(
          'Geen actieve projecten.',
          style: GoogleFonts.lato(
              color: _muted, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      itemCount: _projects.length + 1,
      itemBuilder: (context, i) {
        if (i >= _projects.length) return const SizedBox(height: mobileNavBuffer);
        return _projectCard(_projects[i]);
      },
    );
  }

  Widget _projectCard(Map<String, dynamic> p) {
    final naam = _text(p['project_naam']).isEmpty
        ? _text(p['naam'])
        : _text(p['project_naam']);
    final title = naam.isEmpty ? 'Project' : naam;
    final regio = _text(p['werk_regio']);
    final klant = _clientName(p);
    final freq = _text(p['frequentie_type']);
    final o = _offerteFromRow(p);
    final contractType = _text(o?['contract_type']).isNotEmpty
        ? _text(o?['contract_type'])
        : 'eenmalig';
    final projectId = _text(p['id']);
    final pandUrl = _pandFotoUrl(p);
    final logoUrl = _bedrijfLogoUrl(p);
    final thumbUrl = pandUrl ?? logoUrl;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: () => _openProjectDetail(projectId),
          child: _Card(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NetworkRoundedImage(
                  imageUrl: thumbUrl,
                  fallbackLetter: klant,
                  width: 60,
                  height: 60,
                  borderRadius: 12,
                  accentColor: _blue,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.lato(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _navy,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.apartment_outlined,
                              size: 16, color: _muted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              klant,
                              style: GoogleFonts.lato(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _navy),
                            ),
                          ),
                        ],
                      ),
                      if (regio.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          regio,
                          style: GoogleFonts.lato(
                              fontSize: 12,
                              color: _muted,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (freq.isNotEmpty)
                            _pill(freq, const Color(0xFF0EA5E9)),
                          _pill(contractType, const Color(0xFF7C3AED)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(String t, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        t,
        style: GoogleFonts.lato(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: c,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
