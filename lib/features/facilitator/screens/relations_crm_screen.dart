import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/network_image_fallback.dart';
import '../../admin/screens/relation_detail_screen.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';

/// Facilitator-scoped Relatiebeheer (CRM) screen.
///
/// Binds to the `view_facilitator_crm_lijst` view and filters it by
/// the logged-in facilitator (`betrokken_facilitator_id`). Renders a
/// premium Apple-style dashboard: a KPI header, a filled search bar
/// and a list of custom client cards.
class RelationsCrmScreen extends StatefulWidget {
  const RelationsCrmScreen({super.key});

  @override
  State<RelationsCrmScreen> createState() => _RelationsCrmScreenState();
}

class _RelationsCrmScreenState extends State<RelationsCrmScreen> {
  static const double _radius = 24;
  static const Color _navy = Color(0xFF0F172A);
  static const Color _accentGreen = Color(0xFF16A34A);
  static const Color _accentGreenSoft = Color(0xFFDCFCE7);
  static const Color _accentBlue = Color(0xFF2563EB);
  static const Color _mutedSlate = Color(0xFF64748B);
  static const Color _pillSlate = Color(0xFFF1F5F9);

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Map<String, dynamic>> _clients = const [];
  bool _isLoading = true;
  Object? _loadError;

  int _quotesTotal = 0;
  int _quotesSigned = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAll();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final next = _searchController.text.trim().toLowerCase();
    if (next == _searchQuery) return;
    setState(() => _searchQuery = next);
  }

  // ---------------- helpers ----------------
  String _text(dynamic value) => (value ?? '').toString().trim();

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_text(v)) ?? 0;
  }

  DateTime? _asDate(dynamic v) {
    if (v is DateTime) return v;
    final s = _text(v);
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _firstLetter(String name) {
    final n = name.trim();
    if (n.isEmpty) return '?';
    return n.characters.first.toUpperCase();
  }

  // ---------------- data ----------------
  Future<void> _loadAll() async {
    final user = AppSupabase.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _clients = const [];
        _quotesTotal = 0;
        _quotesSigned = 0;
        _loadError = 'Geen ingelogde gebruiker gevonden.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      // 1) CRM list: facilitators may ONLY see their own portfolio.
      final crmRes = await AppSupabase.client
          .from('view_facilitator_crm_lijst')
          .select()
          .eq('betrokken_facilitator_id', user.id)
          .order('bedrijfsnaam', ascending: true);

      final clients = <Map<String, dynamic>>[];
      for (final row in (crmRes as List)) {
        if (row is Map) clients.add(Map<String, dynamic>.from(row));
      }

      // Enrich logo_url from [bedrijven] when the CRM view omits it.
      if (clients.isNotEmpty) {
        final ids = clients
            .map((c) => _text(c['id']))
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        if (ids.isNotEmpty) {
          try {
            final logoRes = await AppSupabase.client
                .from('bedrijven')
                .select('id, logo_url')
                .inFilter('id', ids);
            final byId = <String, String?>{};
            for (final row in (logoRes as List)) {
              if (row is! Map) continue;
              final m = Map<String, dynamic>.from(row);
              final id = _text(m['id']);
              final lu = _text(m['logo_url']);
              byId[id] = lu.isEmpty ? null : lu;
            }
            for (final c in clients) {
              final id = _text(c['id']);
              final fromBedrijf = byId[id];
              if (fromBedrijf != null && fromBedrijf.isNotEmpty) {
                c['logo_url'] = fromBedrijf;
              }
            }
          } catch (_) {
            // Non-fatal: keep whatever the view returned.
          }
        }
      }

      // 2) Quote KPIs: count total + signed for this facilitator.
      int quotesTotal = 0;
      int quotesSigned = 0;
      try {
        final quoteRes = await AppSupabase.client
            .from('offertes')
            .select('id, status')
            .eq('aangemaakt_door_id', user.id);
        final quotes = <Map<String, dynamic>>[];
        for (final row in (quoteRes as List)) {
          if (row is Map) quotes.add(Map<String, dynamic>.from(row));
        }
        quotesTotal = quotes.length;
        quotesSigned = quotes.where((q) {
          final s = _text(q['status']).toLowerCase();
          return s == 'signed' || s == 'getekend';
        }).length;
      } catch (_) {
        // Non-fatal: KPI can degrade without breaking the CRM list.
        quotesTotal = 0;
        quotesSigned = 0;
      }

      if (!mounted) return;
      setState(() {
        _clients = clients;
        _quotesTotal = quotesTotal;
        _quotesSigned = quotesSigned;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _clients = const [];
        _quotesTotal = 0;
        _quotesSigned = 0;
        _loadError = e;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------- derived state ----------------
  List<Map<String, dynamic>> get _filteredClients {
    if (_searchQuery.isEmpty) return _clients;
    return _clients.where((c) {
      final name = _text(c['bedrijfsnaam']).toLowerCase();
      final nr = _text(c['debiteur_nummer']).toLowerCase();
      return name.contains(_searchQuery) || nr.contains(_searchQuery);
    }).toList();
  }

  int get _totalClients => _clients.length;

  int get _newThisMonth {
    final now = DateTime.now();
    return _clients.where((c) {
      final d = _asDate(c['aangemaakt_op']);
      if (d == null) return false;
      return d.year == now.year && d.month == now.month;
    }).length;
  }

  /// Conversie Ratio:
  /// - If the facilitator has any quotes, primary formula is
  ///   (signed quotes / total quotes) * 100.
  /// - If no signed quotes yet (or data missing), fall back to
  ///   (total clients / total quotes) * 100, per spec.
  double get _conversionPct {
    if (_quotesTotal <= 0) return 0;
    if (_quotesSigned > 0) {
      return (_quotesSigned / _quotesTotal) * 100.0;
    }
    return (_totalClients / _quotesTotal) * 100.0;
  }

  void _goRelationNew() {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const RelationDetailScreen(
              bedrijfId: null,
              createAsKlant: true,
            ),
          ),
        )
        .then((_) {
      if (!mounted) return;
      _loadAll();
    });
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF4F7FC);

    return Scaffold(
      backgroundColor: bg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Relatiebeheer',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            fontSize: 22,
            color: isDark ? Colors.white : _navy,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Verversen',
            onPressed: _isLoading ? null : _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: mobileNavBuffer),
        child: FloatingActionButton(
          onPressed: _goRelationNew,
          tooltip: 'Nieuwe relatie',
          child: const Icon(Icons.add_rounded),
        ),
      ),
      body: SelectionArea(
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildKpiHeader(isDark),
              _buildSearchBar(isDark),
              Expanded(child: _buildListSection(isDark)),
            ],
          ),
        ),
      ),
    );
  }

  // --- KPI header ---
  Widget _buildKpiHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        height: 140,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _KpiCard(
              label: 'Mijn Klantenportefeuille',
              value: _totalClients.toString(),
              icon: Icons.people_alt_rounded,
              background: isDark ? _navy : Colors.white,
              foreground: isDark ? Colors.white : _navy,
              accent: _accentBlue,
            ),
            const SizedBox(width: 12),
            _KpiCard(
              label: 'Nieuw deze maand',
              value: _newThisMonth.toString(),
              icon: Icons.auto_awesome_rounded,
              background: isDark ? _navy : Colors.white,
              foreground: isDark ? Colors.white : _navy,
              accent: _accentGreen,
              trailing: _newThisMonth > 0
                  ? const _TrendUpBadge()
                  : null,
            ),
            const SizedBox(width: 12),
            _KpiCard(
              label: 'Conversie Ratio',
              value: '${_conversionPct.toStringAsFixed(0)}%',
              icon: Icons.trending_up_rounded,
              background: isDark ? _navy : Colors.white,
              foreground: isDark ? Colors.white : _navy,
              accent: _accentBlue,
            ),
          ],
        ),
      ),
    );
  }

  // --- Search + Filter ---
  Widget _buildSearchBar(bool isDark) {
    final fieldBg = isDark ? const Color(0xFF121826) : Colors.grey.shade100;
    final hintColor = (isDark ? Colors.white : _navy).withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: fieldBg,
                borderRadius: BorderRadius.circular(_radius),
              ),
              alignment: Alignment.center,
              child: TextField(
                controller: _searchController,
                textAlignVertical: TextAlignVertical.center,
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : _navy,
                ),
                cursorColor: _accentBlue,
                decoration: InputDecoration(
                  isCollapsed: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: 'Zoek op bedrijfsnaam of klantnummer...',
                  hintStyle: GoogleFonts.lato(
                    fontWeight: FontWeight.w600,
                    color: hintColor,
                  ),
                  prefixIcon: Icon(
                    CupertinoIcons.search,
                    color: hintColor,
                    size: 20,
                  ),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Wissen',
                          onPressed: () {
                            _searchController.clear();
                          },
                          icon: Icon(
                            CupertinoIcons.clear_circled_solid,
                            size: 18,
                            color: hintColor,
                          ),
                        ),
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _FilterButton(
            isDark: isDark,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Filters openen',
                    style: GoogleFonts.lato(fontWeight: FontWeight.w700),
                  ),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_radius),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // --- Main list area ---
  Widget _buildListSection(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: CupertinoActivityIndicator(radius: 14),
      );
    }
    if (_loadError != null) {
      return _buildErrorState(isDark);
    }

    final filtered = _filteredClients;
    if (filtered.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: filtered.length + 1,
      itemBuilder: (context, index) {
        if (index >= filtered.length) {
          return const SizedBox(height: mobileNavBuffer);
        }
        return _buildClientCard(filtered[index], isDark);
      },
    );
  }

  // --- Client card ---
  Widget _buildClientCard(Map<String, dynamic> client, bool isDark) {
    final bedrijfId = _text(client['id']);
    final bedrijfsnaam = _text(client['bedrijfsnaam']).isEmpty
        ? 'Onbekende relatie'
        : _text(client['bedrijfsnaam']);
    final klantnr = _text(client['debiteur_nummer']).isEmpty
        ? 'Nieuw'
        : _text(client['debiteur_nummer']);
    final laatsteOfferte = _text(client['laatste_offerte_nummer']).isEmpty
        ? 'Geen'
        : _text(client['laatste_offerte_nummer']);
    final projecten = _asInt(client['aantal_projecten']);
    final hasProjecten = projecten > 0;

    final cardBg = isDark ? const Color(0xFF121826) : Colors.white;
    final titleColor = isDark ? Colors.white : _navy;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(_radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(_radius),
            splashColor: _accentBlue.withValues(alpha: 0.10),
            onTap: bedrijfId.isEmpty
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        settings: const RouteSettings(
                            name: '/facilitator/relations/detail'),
                        builder: (_) =>
                            RelationDetailScreen(bedrijfId: bedrijfId),
                      ),
                    );
                    if (!mounted) return;
                    await _loadAll();
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  RelationLogoAvatar(
                    logoUrl: _text(client['logo_url']).isEmpty
                        ? null
                        : _text(client['logo_url']),
                    fallbackLetter: _firstLetter(bedrijfsnaam),
                    size: 52,
                    accentColor: _accentBlue,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bedrijfsnaam,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: -0.2,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DefaultTextStyle(
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _mutedSlate,
                          ),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Klantnr: $klantnr',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                child: Text(
                                  '|',
                                  style: GoogleFonts.lato(
                                    fontWeight: FontWeight.w700,
                                    color: _mutedSlate.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  'Offerte: $laatsteOfferte',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _ProjectenBadge(
                    count: projecten,
                    active: hasProjecten,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Empty / error ---
  Widget _buildEmptyState(bool isDark) {
    final baseColor = isDark ? Colors.white : _navy;
    final isSearching = _searchQuery.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentBlue.withValues(alpha: 0.08),
              ),
              alignment: Alignment.center,
              child: Icon(
                isSearching
                    ? CupertinoIcons.search
                    : Icons.people_alt_rounded,
                size: 56,
                color: _accentBlue.withValues(alpha: 0.80),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isSearching
                  ? 'Geen resultaten gevonden.'
                  : 'U heeft nog geen klanten in uw portefeuille.',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: -0.2,
                color: baseColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSearching
                  ? 'Probeer een andere zoekterm.'
                  : 'Zodra er klanten aan u worden toegewezen, verschijnen ze hier.',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: baseColor.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    final baseColor = isDark ? Colors.white : _navy;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 54,
              color: baseColor.withValues(alpha: 0.62),
            ),
            const SizedBox(height: 12),
            Text(
              'Kan relaties niet laden',
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: baseColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$_loadError',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w600,
                color: baseColor.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                'Opnieuw proberen',
                style: GoogleFonts.lato(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_radius),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
//  Sub-widgets
// ============================================================

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.accent,
    this.trailing,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
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
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: -0.1,
                    color: foreground.withValues(alpha: 0.72),
                  ),
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: accent),
              ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w900,
                  fontSize: 36,
                  letterSpacing: -0.8,
                  height: 1.02,
                  color: foreground,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: trailing!,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendUpBadge extends StatelessWidget {
  const _TrendUpBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _RelationsCrmScreenState._accentGreenSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.trending_up_rounded,
            size: 14,
            color: _RelationsCrmScreenState._accentGreen,
          ),
          const SizedBox(width: 4),
          Text(
            'Nieuw',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.1,
              color: _RelationsCrmScreenState._accentGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF121826) : Colors.grey.shade100;
    final fg =
        (isDark ? Colors.white : _RelationsCrmScreenState._navy).withValues(alpha: 0.82);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          height: 52,
          width: 52,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: Icon(
            CupertinoIcons.slider_horizontal_3,
            color: fg,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _ProjectenBadge extends StatelessWidget {
  const _ProjectenBadge({required this.count, required this.active});

  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? _RelationsCrmScreenState._accentGreenSoft
        : _RelationsCrmScreenState._pillSlate;
    final fg = active
        ? _RelationsCrmScreenState._accentGreen
        : _RelationsCrmScreenState._mutedSlate;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active
                ? Icons.folder_rounded
                : Icons.folder_outlined,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 6),
          Text(
            'Projecten: $count',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: -0.1,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
