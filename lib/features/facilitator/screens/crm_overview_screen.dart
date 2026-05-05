import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/user_role.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import '../../admin/screens/relation_detail_screen.dart';

class CrmOverviewScreen extends StatefulWidget {
  const CrmOverviewScreen({super.key});

  @override
  State<CrmOverviewScreen> createState() => _CrmOverviewScreenState();
}

class _CrmOverviewScreenState extends State<CrmOverviewScreen> {
  static const double _radius = 24;
  static const Color _navy = Color(0xFF0F172A);
  static const Color _electricBlue = Color(0xFF2563EB);

  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _clients = const [];
  bool _isLoading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadClients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  Future<void> _loadClients() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _clients = const [];
        _isLoading = false;
        _loadError = 'Geen ingelogde gebruiker gevonden.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final role = context.read<UserProvider>().role;
      final isPrivileged = role == UserRole.generator || role == UserRole.administrator;

      final query = _supabase
          .from('view_facilitator_klanten_dashboard')
          .select('*');

      final dynamic response = isPrivileged
          ? await query.order('bedrijfsnaam', ascending: true)
          : await query
              .contains('betrokken_facilitators', '{${user.id}}')
              .order('bedrijfsnaam', ascending: true);

      final rows = <Map<String, dynamic>>[];
      for (final row in (response as List)) {
        if (row is Map) rows.add(Map<String, dynamic>.from(row));
      }

      if (!mounted) return;
      setState(() {
        _clients = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _clients = const [];
        _isLoading = false;
        _loadError = e;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredClients {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _clients;
    return _clients.where((item) {
      final name = _text(item['bedrijfsnaam']).toLowerCase();
      final debiteur = _text(item['debiteur_nummer']).toLowerCase();
      return name.contains(q) || debiteur.contains(q);
    }).toList();
  }

  LinearGradient _avatarGradient(bool isDark) {
    return LinearGradient(
      colors: isDark
          ? const [Color(0xFF1E3A8A), Color(0xFF2563EB)]
          : const [Color(0xFF60A5FA), Color(0xFF2563EB)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Widget _buildSearchField(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121826) : Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: _navy.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.lato(
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : _navy,
        ),
        decoration: InputDecoration(
          hintText: 'Zoek op bedrijfsnaam of debiteurnummer',
          hintStyle: GoogleFonts.lato(
            fontWeight: FontWeight.w500,
            color: (isDark ? Colors.white : _navy).withValues(alpha: 0.55),
          ),
          prefixIcon: const Icon(Icons.search_rounded),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
      ),
    );
  }

  Widget _buildClientCard(Map<String, dynamic> item, bool isDark) {
    final bedrijfId = _text(item['id']);
    final bedrijfsnaam = _text(item['bedrijfsnaam']).isEmpty
        ? 'Onbekende relatie'
        : _text(item['bedrijfsnaam']);
    final debiteurNummer = _text(item['debiteur_nummer']).isEmpty
        ? 'Geen debiteurnummer'
        : _text(item['debiteur_nummer']);
    final stad = _text(item['adres_stad']).isEmpty ? 'Onbekende plaats' : _text(item['adres_stad']);
    final initial = bedrijfsnaam.substring(0, 1).toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121826) : Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          splashColor: _electricBlue.withValues(alpha: 0.12),
          onTap: bedrijfId.isEmpty
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RelationDetailScreen(bedrijfId: bedrijfId),
                    ),
                  );
                },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _avatarGradient(isDark),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: GoogleFonts.lato(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bedrijfsnaam,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.lato(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: isDark ? Colors.white : _navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _navy.withValues(alpha: isDark ? 0.26 : 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              debiteurNummer,
                              style: GoogleFonts.lato(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: isDark ? Colors.white : _navy,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: (isDark ? Colors.white : _navy).withValues(alpha: 0.62),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              stad,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.lato(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: (isDark ? Colors.white : _navy).withValues(alpha: 0.70),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  color: (isDark ? Colors.white : _navy).withValues(alpha: 0.62),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF4F7FC);
    final filtered = _filteredClients;

    return Scaffold(
      backgroundColor: bg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Relatiebeheer', style: GoogleFonts.lato(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadClients,
            tooltip: 'Verversen',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SelectionArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mijn Relaties',
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w900,
                  fontSize: 28,
                  color: isDark ? Colors.white : _navy,
                ),
              ),
              _buildSearchField(isDark),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _loadError != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Fout bij laden: $_loadError',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.lato(
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : _navy,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                  onPressed: _loadClients,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label:
                                      Text('Opnieuw proberen', style: GoogleFonts.lato()),
                                ),
                              ],
                            ),
                          )
                        : filtered.isEmpty
                            ? Center(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 14),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.supervised_user_circle_outlined,
                                        size: 84,
                                        color: (isDark ? Colors.white : _navy)
                                            .withValues(alpha: 0.32),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Geen gekoppelde klanten gevonden.',
                                        style: GoogleFonts.lato(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17,
                                          color: isDark ? Colors.white : _navy,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Neem contact op met de beheerder om u toe te wijzen aan een relatie.',
                                        style: GoogleFonts.lato(
                                          fontWeight: FontWeight.w600,
                                          color:
                                              (isDark ? Colors.white : _navy)
                                                  .withValues(alpha: 0.62),
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  return _buildClientCard(
                                    filtered[index],
                                    isDark,
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
