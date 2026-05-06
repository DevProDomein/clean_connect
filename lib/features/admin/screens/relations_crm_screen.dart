import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user_role.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/network_image_fallback.dart';
import '../../../providers/user_provider.dart';
import 'relation_detail_screen.dart';

class RelationsCrmScreen extends StatefulWidget {
  const RelationsCrmScreen({super.key});

  @override
  State<RelationsCrmScreen> createState() => _RelationsCrmScreenState();
}

class _RelationsCrmScreenState extends State<RelationsCrmScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _relations = const [];
  bool _isLoading = true;
  Object? _loadError;

  Future<void> _loadRelaties() => _fetch();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetch();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  String _firstLetter(String name) {
    final n = name.trim();
    if (n.isEmpty) return '?';
    return n.characters.first.toUpperCase();
  }

  Future<void> _fetch() async {
    final user = AppSupabase.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Geen ingelogde gebruiker gevonden.';
        _relations = const [];
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      // Role is parsed from `gebruikers_metadata` by UserProvider.
      final up = context.read<UserProvider>();
      final isFacilitator = up.role == UserRole.facilitator;

      final query = AppSupabase.client.from('bedrijven').select();
      final dynamic res = isFacilitator
          ? await query
              .eq('betrokken_facilitator_id', user.id)
              .order('bedrijfsnaam', ascending: true)
          : await query.order('bedrijfsnaam', ascending: true);

      final data = (res as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      if (!mounted) return;
      setState(() {
        _relations = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _relations = const [];
        _isLoading = false;
        _loadError = e;
      });
    }
  }

  List<Map<String, dynamic>> _filterFor({required bool isKlantTab}) {
    final q = _searchController.text.trim().toLowerCase();
    return _relations.where((relation) {
      final matchesTab = isKlantTab
          ? _asBool(relation['is_klant'])
          : _asBool(relation['is_leverancier']);
      if (!matchesTab) return false;
      if (q.isEmpty) return true;
      final name = _text(relation['bedrijfsnaam']).toLowerCase();
      return name.contains(q);
    }).toList();
  }

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/admin/relations/detail'),
        builder: (_) => RelationDetailScreen(bedrijfId: id),
      ),
    );
    if (mounted) _fetch();
  }

  Future<void> _openCreate() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RelationDetailScreen(bedrijfId: null),
      ),
    ).then((_) => _loadRelaties());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final softBg = isDark ? const Color(0xFF090E18) : const Color(0xFFF5F7FC);
    final surface = isDark ? const Color(0xFF0D1422) : Colors.white;
    final onSurfaceMuted = (isDark ? Colors.white : const Color(0xFF0F172A))
        .withValues(alpha: 0.55);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const AppDrawer(),
        backgroundColor: softBg,
        appBar: AppBar(
          backgroundColor: softBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'Relatiebeheer',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              fontSize: 22,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Vernieuwen',
              onPressed: _fetch,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: cs.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          onPressed: _openCreate,
          icon: const Icon(Icons.add),
          label: Text(
            'Nieuwe Relatie',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
              color: Colors.white,
            ),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        body: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(4),
                  child: TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor:
                        isDark ? Colors.white70 : const Color(0xFF0F172A),
                    labelStyle: GoogleFonts.lato(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: -0.2,
                    ),
                    unselectedLabelStyle: GoogleFonts.lato(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: -0.2,
                    ),
                    dividerColor: Colors.transparent,
                    splashBorderRadius: BorderRadius.circular(20),
                    tabs: const [
                      Tab(text: 'Klanten'),
                      Tab(text: 'Leveranciers'),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  placeholder: 'Zoek op bedrijfsnaam',
                  placeholderStyle: GoogleFonts.lato(
                    fontWeight: FontWeight.w600,
                    color: onSurfaceMuted,
                  ),
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  backgroundColor: surface,
                  borderRadius: BorderRadius.circular(20),
                  prefixIcon: Icon(
                    CupertinoIcons.search,
                    color: onSurfaceMuted,
                    size: 20,
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _loadError != null
                        ? _ErrorState(error: _loadError!)
                        : TabBarView(
                            physics: const BouncingScrollPhysics(),
                            children: [
                              _RelationList(
                                relations: _filterFor(isKlantTab: true),
                                isKlantTab: true,
                                isDark: isDark,
                                surface: surface,
                                firstLetter: _firstLetter,
                                text: _text,
                                onOpen: _openDetail,
                              ),
                              _RelationList(
                                relations: _filterFor(isKlantTab: false),
                                isKlantTab: false,
                                isDark: isDark,
                                surface: surface,
                                firstLetter: _firstLetter,
                                text: _text,
                                onOpen: _openDetail,
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelationList extends StatelessWidget {
  const _RelationList({
    required this.relations,
    required this.isKlantTab,
    required this.isDark,
    required this.surface,
    required this.firstLetter,
    required this.text,
    required this.onOpen,
  });

  final List<Map<String, dynamic>> relations;
  final bool isKlantTab;
  final bool isDark;
  final Color surface;
  final String Function(String name) firstLetter;
  final String Function(dynamic v) text;
  final Future<void> Function(String id) onOpen;

  @override
  Widget build(BuildContext context) {
    if (relations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            isKlantTab
                ? 'Geen klanten gevonden.'
                : 'Geen leveranciers gevonden.',
            style: GoogleFonts.lato(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 110),
      itemCount: relations.length,
      itemBuilder: (context, index) {
        final relation = relations[index];
        return _RelationCard(
          relation: relation,
          isKlantTab: isKlantTab,
          isDark: isDark,
          surface: surface,
          firstLetter: firstLetter,
          text: text,
          onOpen: onOpen,
        );
      },
    );
  }
}

class _RelationCard extends StatelessWidget {
  const _RelationCard({
    required this.relation,
    required this.isKlantTab,
    required this.isDark,
    required this.surface,
    required this.firstLetter,
    required this.text,
    required this.onOpen,
  });

  final Map<String, dynamic> relation;
  final bool isKlantTab;
  final bool isDark;
  final Color surface;
  final String Function(String name) firstLetter;
  final String Function(dynamic v) text;
  final Future<void> Function(String id) onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final id = text(relation['id']);
    final name = text(relation['bedrijfsnaam']).isEmpty
        ? 'Onbekende relatie'
        : text(relation['bedrijfsnaam']);
    final city = text(relation['adres_stad']).isEmpty
        ? '—'
        : text(relation['adres_stad']);

    final nummer = isKlantTab
        ? text(relation['debiteur_nummer'])
        : text(relation['crediteur_nummer']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: id.isEmpty ? null : () => onOpen(id),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  RelationLogoAvatar(
                    logoUrl: text(relation['logo_url']).isEmpty
                        ? null
                        : text(relation['logo_url']),
                    fallbackLetter: firstLetter(name),
                    size: 50,
                    accentColor: cs.primary,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: -0.2,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (nummer.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        nummer,
                        style: GoogleFonts.lato(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurface.withValues(alpha: 0.38),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Kan relaties niet laden: $error',
          style: GoogleFonts.lato(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
