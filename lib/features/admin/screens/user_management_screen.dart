import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/models/user_role.dart';
import '../../../core/services/user_management_service.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import '../../../shared/widgets/enterprise_tooltip.dart';
import '../../../shared/widgets/enterprise_pill_badge.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  Future<List<UserSummary>>? _future;
  late final TabController _mainTabController;
  final GlobalKey<_MedewerkersPanelState> _medewerkersPanelKey =
      GlobalKey<_MedewerkersPanelState>();

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_mainTabController.indexIsChanging) setState(() {});
      });
    _future = UserManagementService().fetchAllUsers();
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _future = UserManagementService().fetchAllUsers();
    });
  }

  Future<void> _changeRoleForUser({
    required UserSummary user,
    required String newRole,
  }) async {
    try {
      // Contract V1.0: write to master table; trigger syncs mirror row.
      await AppSupabase.client.from(GebruikersTable.name).update({
        GebruikersTable.gebruikersrol: newRole.trim().toLowerCase(),
      }).eq(GebruikersTable.id, user.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rol bijgewerkt naar "$newRole".')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rol wijzigen mislukt: $e')),
      );
    }
  }

  Future<void> _showChangeRoleDialog(UserSummary user) async {
    final current = user.roleString.trim().toLowerCase();
    final options = const ['facilitator', 'operator', 'klant'];
    String selected = options.contains(current) ? current : options.first;

    final picked = await showDialog<String>(
      context: context,
      builder: (context) {
        return SelectionArea(
          child: AlertDialog(
            title: const Text('Rol wijzigen'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.email.isEmpty ? user.id : user.email),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Nieuwe rol'),
                    child: DropdownButtonHideUnderline(
                      child: StatefulBuilder(
                        builder: (context, setLocal) {
                          return DropdownButton<String>(
                            isExpanded: true,
                            value: selected,
                            items: options
                                .map(
                                  (r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(r),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setLocal(() => selected = v);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Wijzigingen worden opgeslagen in `gebruikers` en '
                    'automatisch gesynchroniseerd naar `gebruikers_metadata`.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Annuleren'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(selected),
                child: const Text('Opslaan'),
              ),
            ],
          ),
        );
      },
    );

    if (picked == null) return;
    await _changeRoleForUser(user: user, newRole: picked);
  }

  void _openDeepDive(UserSummary u) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SelectionArea(
        child: _UserDeepDiveSheet(user: u),
      ),
    ).then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canOpen = up.isGenerator ||
        up.hasPermission('invite_klant') ||
        up.hasPermission('invite_operator');

    if (!canOpen) {
      return Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        appBar: AppBar(title: const Text('Gebruikersbeheer')),
        body: const SelectionArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Geen toegang.'),
          ),
        ),
      );
    }

    return Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(
            'Gebruikersbeheer',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              letterSpacing: -0.4,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Vernieuwen',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue.shade900,
          tooltip: 'Nieuwe gebruiker uitnodigen',
          onPressed: () async {
            final did = await showDialog<bool>(
              context: context,
              builder: (_) => const SelectionArea(
                child: _InviteUserDialog(),
              ),
            );
            if (did == true) {
              await up.loadForCurrentUser();
              await _reload();
            }
          },
        child: const Icon(Icons.add, color: Colors.white),
        ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _mainTabController.index == 0
          ? _medewerkersPanelKey.currentState?.buildBottomPaginationBar()
          : null,
        body: SelectionArea(
          child: FutureBuilder<List<UserSummary>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _ErrorCard(
                      title: 'Kan gebruikers niet laden',
                      message: snapshot.error.toString(),
                      onRetry: _reload,
                    ),
                  ),
                );
              }

              final users = snapshot.data ?? const <UserSummary>[];

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
                    child: _KpiRow(users: users),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
                    child: _TopTabs(controller: _mainTabController),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _mainTabController,
                      children: [
                        _MedewerkersPanel(
                          key: _medewerkersPanelKey,
                                      users: users,
                                      isGenerator: up.isGenerator,
                                      onTap: _openDeepDive,
                                      onShowRoleDialog: _showChangeRoleDialog,
                          onPaginationChanged: () => setState(() {}),
                        ),

                        // Tab 2: Systeemrechten Overzicht (read-only dictionary)
                        const _SystemRightsOverviewTab(),
                      ],
                    ),
                  ),
                ],
              );
            },
        ),
      ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: controller,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicatorPadding: const EdgeInsets.all(4),
        splashBorderRadius: BorderRadius.circular(8),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        labelColor: Colors.blue.shade900,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        tabs: const [
          Tab(text: 'Medewerkers'),
          Tab(text: 'Systeemrechten Overzicht'),
        ],
      ),
    );
  }
}

class _SystemRightsOverviewTab extends StatefulWidget {
  const _SystemRightsOverviewTab();

  @override
  State<_SystemRightsOverviewTab> createState() =>
      _SystemRightsOverviewTabState();
}

class _SystemRightsOverviewTabState extends State<_SystemRightsOverviewTab> {
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final res = await AppSupabase.client.from(FinancePermissionsTable.name).select(
          '${FinancePermissionsTable.id}, '
          '${FinancePermissionsTable.naam}, '
          'weergave_naam, '
          'omschrijving, '
          'toegestane_rollen, '
          'is_systeem_recht',
        );
    return (res as List).cast<Map<String, dynamic>>();
  }

  String _title(Map<String, dynamic> row) {
    final w = (row['weergave_naam'] ?? row['weergavenaam'])?.toString().trim();
    if (w != null && w.isNotEmpty) return w;
    final n = row[FinancePermissionsTable.naam]?.toString().trim();
    return (n == null || n.isEmpty) ? '(onbekend)' : n;
  }

  String _desc(Map<String, dynamic> row) {
    return (row['omschrijving'] ?? '').toString().trim();
  }

  Set<String> _allowedRoles(Map<String, dynamic> row) {
    final v = row['toegestane_rollen'];
    if (v is List) {
      return v
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return {};
      return s
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    return {};
  }

  String _prettyRole(String r) {
    switch (r) {
      case 'administrator':
        return 'Administrator';
      case 'generator':
        return 'Generator';
      case 'facilitator':
        return 'Facilitator';
      case 'operator':
        return 'Operator';
      case 'klant':
      case 'client':
        return 'Klant';
      default:
        if (r.isEmpty) return '—';
        return r[0].toUpperCase() + r.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF2E2938) : const Color(0xFFF5F5F7);

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: _ErrorCard(
              title: 'Kan systeemrechten niet laden',
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _future = _fetch()),
            ),
          );
        }

        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        rows.sort((a, b) => _title(a).compareTo(_title(b)));

        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      color: cs.onSurface.withValues(alpha: 0.65)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Geen systeemrechten gevonden.',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.80),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final row = rows[i];
            final title = _title(row);
            final desc = _desc(row);
            final roles = _allowedRoles(row).map(_prettyRole).toList()..sort();

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                      color: cs.onSurface,
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      desc,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                        'Toegestaan voor:',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface.withValues(alpha: 0.70),
                        ),
                      ),
                      ...roles.map(
                        (r) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: cs.primary.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            r,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ),
                      if (roles.isEmpty)
                        Text(
                          '—',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface.withValues(alpha: 0.65),
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
    );
  }
}

class _InviteUserDialog extends StatefulWidget {
  const _InviteUserDialog();

  @override
  State<_InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends State<_InviteUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _voornaamController = TextEditingController();
  final _achternaamController = TextEditingController();
  final _telefoonController = TextEditingController();

  String? _selectedRol;
  String? _selectedBedrijfId;
  bool _grantAdmin = false;
  bool _submitting = false;

  List<Map<String, dynamic>> _suggestiesLijst = [];
  Map<String, dynamic>? _geselecteerdeSuggestie;

  @override
  void initState() {
    super.initState();
    _loadSuggesties();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _voornaamController.dispose();
    _achternaamController.dispose();
    _telefoonController.dispose();
    super.dispose();
  }

  List<String> _roleOptions(UserProvider inviter) {
    final isFacilitator = inviter.role == UserRole.facilitator;

    if (inviter.isGenerator) return const ['facilitator', 'operator', 'klant'];

    if (isFacilitator && inviter.hasPermission('invite_operator')) {
      return const ['operator', 'klant'];
    }

    if (isFacilitator) return const ['klant'];

    return const [];
  }

  List<String> _beschikbareRollen(UserProvider inviter) {
    final all = _roleOptions(inviter);
    if (_geselecteerdeSuggestie != null) return all;
    return all.where((r) => r != 'klant').toList();
  }

  void _syncSelectedRolWithOptions(List<String> options) {
    if (_geselecteerdeSuggestie == null && _selectedRol == 'klant') {
      _selectedRol = options.contains('operator')
          ? 'operator'
          : (options.isNotEmpty ? options.first : null);
    }
    if (_selectedRol != null && !options.contains(_selectedRol)) {
      _selectedRol = options.isNotEmpty ? options.first : null;
    }
    _selectedRol ??= options.isNotEmpty ? options.first : null;
  }

  void _clearGeselecteerdeSuggestie(UserProvider inviter) {
    setState(() {
      _geselecteerdeSuggestie = null;
      _selectedBedrijfId = null;
      if (_selectedRol == 'klant') {
        _selectedRol = 'operator';
      }
      _syncSelectedRolWithOptions(_beschikbareRollen(inviter));
    });
  }

  String _rolFromGebruikerMap(Map<String, dynamic> g) {
    final raw = g['gebruikersrol'] ?? g['rol'];
    return raw?.toString().trim().toLowerCase() ?? '';
  }

  String _suggestieRolSectieTitel(String displayRol) {
    switch (displayRol.toLowerCase()) {
      case 'klant':
        return 'Klanten / Opdrachtgevers';
      case 'operator':
        return 'Operators';
      case 'facilitator':
        return 'Facilitators';
      case 'generator':
        return 'Generators';
      default:
        return displayRol;
    }
  }

  Map<String, dynamic>? _bedrijfMapFrom(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
                  return null;
  }

  dynamic _bedrijfEmbedFromGebruiker(Map<String, dynamic> gebruiker) {
    return gebruiker['bedrijven'] ??
        gebruiker['bedrijven!gebruikers_bedrijf_id_fkey'];
  }

  String _bedrijfsnaamFromContact(Map<String, dynamic> contact) {
    final bedrijf = _bedrijfMapFrom(_bedrijfEmbedFromGebruiker(contact));
    final naam = (bedrijf?['bedrijfsnaam'] ?? '').toString().trim();
    return naam.isEmpty ? 'Onbekend bedrijf' : naam;
  }

  String? _bedrijfIdFromContact(Map<String, dynamic> contact) {
    final bedrijf = _bedrijfMapFrom(_bedrijfEmbedFromGebruiker(contact));
    final fromEmbed = (bedrijf?['id'] ?? '').toString().trim();
    if (fromEmbed.isNotEmpty) return fromEmbed;
    final direct = (contact['bedrijf_id'] ?? '').toString().trim();
    return direct.isEmpty ? null : direct;
  }

  List<({String id, String naam})> _bedrijfOptiesUitSuggesties() {
    final map = <String, String>{};
    for (final gebruiker in _suggestiesLijst) {
      final id = _bedrijfIdFromContact(gebruiker);
      if (id == null || id.isEmpty) continue;
      map[id] = _bedrijfsnaamFromContact(gebruiker);
    }
    return map.entries
        .map((e) => (id: e.key, naam: e.value))
        .toList()
      ..sort((a, b) => a.naam.compareTo(b.naam));
  }

  Future<void> _loadSuggesties() async {
    try {
      final data = await AppSupabase.client
          .from('gebruikers')
          .select(
            '*, bedrijven!gebruikers_bedrijf_id_fkey(bedrijfsnaam, id)',
          )
          .eq('heeft_app_account', false)
          .order('achternaam');

      if (mounted) {
        setState(
          () => _suggestiesLijst = List<Map<String, dynamic>>.from(data),
        );
      }
    } catch (e) {
      debugPrint('Fout bij ophalen suggesties: $e');
    }
  }

  InputDecoration _inviteInputDecoration({
    Color? fillColor,
    String? hintText,
  }) {
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: fillColor ?? Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
    );
  }

  Widget _buildModernField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
                children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          enabled: enabled,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          decoration: _inviteInputDecoration(),
        ),
      ],
    );
  }

  Widget _buildRolDropdown(List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rol',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('rol-$_selectedRol-${_geselecteerdeSuggestie?['id']}'),
          initialValue: _selectedRol,
          decoration: _inviteInputDecoration(),
                    items: options
              .map(
                (r) => DropdownMenuItem(
                  value: r,
                  child: Text(
                    r[0].toUpperCase() + r.substring(1),
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              )
                        .toList(),
                    onChanged: options.isEmpty
                        ? null
                        : (v) {
                  setState(() {
                    _selectedRol = v;
                    if (v != 'facilitator') _grantAdmin = false;
                    if (v != 'klant') _selectedBedrijfId = null;
                  });
                },
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Selecteer een rol.' : null,
        ),
      ],
    );
  }

  Widget _buildBedrijfDropdown() {
    final opties = _bedrijfOptiesUitSuggesties();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gekoppeld bedrijf',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey(_selectedBedrijfId ?? ''),
          initialValue: _selectedBedrijfId,
          decoration: _inviteInputDecoration(),
          hint: Text(
            'Selecteer bedrijf',
            style: GoogleFonts.inter(color: Colors.blueGrey.shade500),
          ),
          items: opties
              .map(
                (b) => DropdownMenuItem(
                  value: b.id,
                  child: Text(
                    b.naam,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _selectedBedrijfId = v),
        ),
      ],
    );
  }

  Widget _twoCol({
    required bool isWide,
    required Widget left,
    required Widget right,
  }) {
    if (!isWide) {
      return Column(
        children: [
          left,
          const SizedBox(height: 16),
          right,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 16),
        Expanded(child: right),
      ],
    );
  }

  Future<void> _submitInvite(UserProvider inviter) async {
                  if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final voornaam = _voornaamController.text.trim();
    final achternaam = _achternaamController.text.trim();
    final telefoon = _telefoonController.text.trim();

    if (email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('E-mailadres is verplicht!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (_selectedRol == null || _selectedRol!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecteer een rol!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _submitting = true);
    try {
      final body = <String, dynamic>{
        'email': email,
        'role': _selectedRol,
        'fullName': '$voornaam $achternaam'.trim(),
        if (telefoon.isNotEmpty) 'telefoon': telefoon,
      };
      final suggestie = _geselecteerdeSuggestie;
      if (suggestie != null) {
        final existingId = suggestie['id']?.toString();
        if (existingId != null && existingId.isNotEmpty) {
          body['gebruiker_id'] = existingId;
        }
      }

      debugPrint('Edge Function aanroepen voor email: $email');
      final response = await AppSupabase.client.functions.invoke(
        'invite_user',
        body: body,
      );
      debugPrint('Edge Function succesvol: ${response.data}');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uitnodiging succesvol verstuurd!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('EDGE FUNCTION FOUT: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uitnodiging mislukt: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openSuggestiesModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 12),
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Kies een klaarstaande gebruiker',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
              const Divider(),
              Expanded(
                child: _suggestiesLijst.isEmpty
                    ? Center(
                        child: Text(
                          'Geen klaarstaande gebruikers gevonden.',
                          style: GoogleFonts.inter(color: Colors.blueGrey),
                        ),
                      )
                    : Builder(
                        builder: (context) {
                          final grouped = <String, List<Map<String, dynamic>>>{};
                          for (final g in _suggestiesLijst) {
                            final rolRaw = _rolFromGebruikerMap(g);
                            final normalized =
                                rolRaw.isEmpty ? 'klant' : rolRaw;
                            final displayRol = normalized[0].toUpperCase() +
                                normalized.substring(1);
                            grouped.putIfAbsent(displayRol, () => []).add(g);
                          }

                          final sortedKeys = grouped.keys.toList()..sort();

                          return ListView(
                            children: sortedKeys.map((displayRol) {
                              final users = grouped[displayRol]!;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 24,
                                      top: 24,
                                      bottom: 8,
                                    ),
                                    child: Text(
                                      _suggestieRolSectieTitel(displayRol),
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.blue.shade900,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                  ...users.map((g) {
                                    final bedrijfMap = _bedrijfMapFrom(
                                      _bedrijfEmbedFromGebruiker(g),
                                    );
                                    final bedrijf = bedrijfMap?['bedrijfsnaam'] ??
                                        'Geen bedrijf gekoppeld';
                                    final naam =
                                        '${g['voornaam'] ?? ''} ${g['achternaam'] ?? ''}'
                                            .trim();
                                    final emailRaw =
                                        g['emailadres'] ?? g['email'];
                                    final email = emailRaw?.toString() ?? '';

                                    return ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 4,
                                      ),
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.blue.shade50,
                                        child: Icon(
                                          Icons.person,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                      title: Text(
                                        naam.isEmpty ? '(geen naam)' : naam,
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.business,
                                                  size: 14,
                                                  color: Colors.grey.shade600,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    bedrijf.toString(),
                                                    style: GoogleFonts.inter(
                                                      color:
                                                          Colors.grey.shade700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.email,
                                                  size: 14,
                                                  color: Colors.grey.shade600,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    email.isEmpty
                                                        ? 'Geen e-mail'
                                                        : email,
                                                    style: GoogleFonts.inter(
                                                      color:
                                                          Colors.grey.shade700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      onTap: () {
                                        setState(() {
                                          _geselecteerdeSuggestie = g;
                                          _voornaamController.text =
                                              g['voornaam']?.toString() ?? '';
                                          _achternaamController.text =
                                              g['achternaam']?.toString() ?? '';
                                          _emailController.text = email;
                                          _telefoonController.text =
                                              g['telefoon']?.toString() ?? '';
                                          final rol = _rolFromGebruikerMap(g);
                                          if (rol.isNotEmpty) {
                                            _selectedRol = rol;
                                          }
                                          _selectedBedrijfId =
                                              _bedrijfIdFromContact(g);
                                        });
                                        Navigator.pop(sheetContext);
                                      },
                                    );
                                  }),
                                  const Divider(height: 32),
                                ],
                              );
                            }).toList(),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final inviter = context.watch<UserProvider>();
    final options = _beschikbareRollen(inviter);
    final isWide = MediaQuery.of(context).size.width > 600;

    _syncSelectedRolWithOptions(options);
    if (_selectedRol != 'facilitator') _grantAdmin = false;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 720 : 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_suggestiesLijst.isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.person_search),
                        label: Text(
                          _geselecteerdeSuggestie == null
                              ? 'Kies uit klaarstaande gebruikers'
                              : 'Andere klaarstaande gebruiker kiezen',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          foregroundColor: Colors.blue.shade800,
                          side: BorderSide(color: Colors.blue.shade200, width: 2),
                          backgroundColor: Colors.blue.shade50,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _submitting ? null : _openSuggestiesModal,
                      ),
                    ),
                    if (_geselecteerdeSuggestie != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _submitting
                              ? null
                              : () => _clearGeselecteerdeSuggestie(inviter),
                          child: Text(
                            'Selectie wissen (handmatig invullen)',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              color: Colors.blueGrey.shade700,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],

                  // 2. Titel & intro
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Gebruiker uitnodigen',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Nodig een operator, facilitator of klant uit voor CleanConnect.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.blueGrey.shade600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Invoervelden
                  _twoCol(
                    isWide: isWide,
                    left: _buildModernField(
                      label: 'Voornaam',
                      controller: _voornaamController,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Vul een voornaam in.'
                          : null,
                    ),
                    right: _buildModernField(
                      label: 'Achternaam',
                      controller: _achternaamController,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Vul een achternaam in.'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _twoCol(
                    isWide: isWide,
                    left: _buildModernField(
                      label: 'E-mailadres',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'Vul een e-mailadres in.';
                        if (!s.contains('@')) return 'Ongeldig e-mailadres.';
                        return null;
                      },
                    ),
                    right: _buildModernField(
                      label: 'Telefoonnummer',
                      controller: _telefoonController,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _twoCol(
                    isWide: isWide,
                    left: _buildRolDropdown(options),
                    right: _selectedRol == 'klant' &&
                            inviter.isGenerator &&
                            _bedrijfOptiesUitSuggesties().isNotEmpty
                        ? _buildBedrijfDropdown()
                        : const SizedBox.shrink(),
                  ),
                  if (inviter.isGenerator && _selectedRol == 'facilitator') ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _grantAdmin,
                      onChanged: (v) => setState(() => _grantAdmin = v),
                      title: Text(
                        'Admin status verlenen',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],

                  // 4. Actieknoppen
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Annuleren'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed:
                              _submitting ? null : () => _submitInvite(inviter),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _submitting
                                ? 'Bezig…'
                                : 'Uitnodiging versturen',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                            ),
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
      ),
    );
  }
}

class _PermissionOverlay extends StatefulWidget {
  const _PermissionOverlay({required this.user});

  final UserSummary user;

  @override
  State<_PermissionOverlay> createState() => _PermissionOverlayState();
}

class _PermissionOverlayState extends State<_PermissionOverlay> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _all = [];
  final Map<String, bool> _selected = {};

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

    try {
      final permsRes = await AppSupabase.client
          .from(FinancePermissionsTable.name)
          .select('${FinancePermissionsTable.id}, ${FinancePermissionsTable.naam}')
          .order(FinancePermissionsTable.naam);
      _all = (permsRes as List).cast<Map<String, dynamic>>();

      for (final p in _all) {
        final id = p[FinancePermissionsTable.id]?.toString();
        if (id != null && id.isNotEmpty) _selected[id] = false;
      }

      final rightsRes = await AppSupabase.client
          .from(GebruikerFinanceRechtenTable.name)
          .select(GebruikerFinanceRechtenTable.permissieId)
          .eq(GebruikerFinanceRechtenTable.gebruikerId, widget.user.id);
      final rights = (rightsRes as List).cast<Map<String, dynamic>>();
      for (final r in rights) {
        final pid = r[GebruikerFinanceRechtenTable.permissieId]?.toString();
        if (pid != null && pid.isNotEmpty) _selected[pid] = true;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final wanted = _selected.entries.where((e) => e.value).map((e) => e.key).toSet();

    final rightsRes = await AppSupabase.client
        .from(GebruikerFinanceRechtenTable.name)
        .select(GebruikerFinanceRechtenTable.permissieId)
        .eq(GebruikerFinanceRechtenTable.gebruikerId, widget.user.id);
    final rights = (rightsRes as List).cast<Map<String, dynamic>>();
    final existing = rights
        .map((r) => r[GebruikerFinanceRechtenTable.permissieId]?.toString())
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toSet();

    final toAdd = wanted.difference(existing);
    final toRemove = existing.difference(wanted);

    for (final pid in toAdd) {
      await AppSupabase.client.from(GebruikerFinanceRechtenTable.name).insert({
        GebruikerFinanceRechtenTable.gebruikerId: widget.user.id,
        GebruikerFinanceRechtenTable.permissieId: pid,
      });
    }

    for (final pid in toRemove) {
      await AppSupabase.client
          .from(GebruikerFinanceRechtenTable.name)
          .delete()
          .eq(GebruikerFinanceRechtenTable.gebruikerId, widget.user.id)
          .eq(GebruikerFinanceRechtenTable.permissieId, pid);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    if (!up.isGenerator) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Alleen Generator kan permissies beheren.'),
      );
    }

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Fout: ${_error!}'),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Permissies',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              widget.user.email.isEmpty ? widget.user.id : widget.user.email,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _all.map((p) {
                  final id = p[FinancePermissionsTable.id]?.toString() ?? '';
                  final key = p[FinancePermissionsTable.naam]?.toString() ?? '';
                  final checked = _selected[id] ?? false;
                  return SwitchListTile(
                    value: checked,
                    onChanged: (v) => setState(() => _selected[id] = v),
                    title: Text(key),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuleren'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Opslaan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MedewerkersPanel extends StatefulWidget {
  const _MedewerkersPanel({
    super.key,
    required this.users,
    required this.isGenerator,
    required this.onTap,
    required this.onShowRoleDialog,
    this.onPaginationChanged,
  });

  final List<UserSummary> users;
  final bool isGenerator;
  final void Function(UserSummary user) onTap;
  final Future<void> Function(UserSummary user) onShowRoleDialog;
  final VoidCallback? onPaginationChanged;

  @override
  State<_MedewerkersPanel> createState() => _MedewerkersPanelState();
}

class _MedewerkersPanelState extends State<_MedewerkersPanel> {
  static const _tabs = [
    'Alle',
    'Operators',
    'Klanten',
    'Facilitators',
    'Beheer',
  ];

  String _geselecteerdeTab = 'Alle';
  int _itemsPerPage = 8;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyPaginationChanged();
    });
  }

  bool _matchesTab(UserSummary user, String tab) {
    final r = user.roleString.trim().toLowerCase();
    switch (tab) {
      case 'Operators':
        return r == 'operator';
      case 'Klanten':
        return r == 'klant';
      case 'Facilitators':
        return r == 'facilitator';
      case 'Beheer':
        return r == 'administrator' || r == 'beheerder' || r == 'generator';
      default:
        return true;
    }
  }

  List<UserSummary> get _gefilterdeGebruikers =>
      widget.users.where((u) => _matchesTab(u, _geselecteerdeTab)).toList();

  int get _totalPages {
    if (_gefilterdeGebruikers.isEmpty) return 1;
    return (_gefilterdeGebruikers.length / _itemsPerPage).ceil();
  }

  List<UserSummary> get _paginatedUsers {
    final start = _currentPage * _itemsPerPage;
    if (start >= _gefilterdeGebruikers.length) return [];
    final end = (start + _itemsPerPage) > _gefilterdeGebruikers.length
        ? _gefilterdeGebruikers.length
        : (start + _itemsPerPage);
    return _gefilterdeGebruikers.sublist(start, end);
  }

  void _notifyPaginationChanged() {
    widget.onPaginationChanged?.call();
  }

  Widget _buildSegmentedControl() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: _tabs.map((tab) {
          final isSelected = _geselecteerdeTab == tab;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _geselecteerdeTab = tab;
                  _currentPage = 0;
                });
                _notifyPaginationChanged();
              },
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: isSelected
                    ? BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      )
                    : null,
                alignment: Alignment.center,
                child: Text(
                  tab,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontWeight:
                        isSelected ? FontWeight.w900 : FontWeight.w600,
                    fontSize: 13,
                    color: isSelected
                        ? Colors.blue.shade900
                        : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget buildBottomPaginationBar() {
    final totalPages = _totalPages;
    return Container(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'Toon:',
                style: GoogleFonts.inter(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _itemsPerPage,
                underline: const SizedBox(),
                icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  color: Colors.blue.shade900,
                  fontSize: 14,
                ),
                items: [8, 16, 32]
                    .map(
                      (value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text(value.toString()),
                      ),
                    )
                    .toList(),
                onChanged: (newValue) {
                  if (newValue != null) {
                    setState(() {
                      _itemsPerPage = newValue;
                      _currentPage = 0;
                    });
                    _notifyPaginationChanged();
                  }
                },
            ),
          ],
        ),
          Row(
            children: [
              Text(
                'Pagina ${_currentPage + 1} van $totalPages',
                style: GoogleFonts.inter(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                color: _currentPage > 0
                    ? Colors.blue.shade900
                    : Colors.grey.shade300,
                onPressed: _currentPage > 0
                    ? () {
                        setState(() => _currentPage--);
                        _notifyPaginationChanged();
                      }
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                color: _currentPage < totalPages - 1
                    ? Colors.blue.shade900
                    : Colors.grey.shade300,
                onPressed: _currentPage < totalPages - 1
                    ? () {
                        setState(() => _currentPage++);
                        _notifyPaginationChanged();
                      }
                    : null,
              ),
            ],
          ),
        ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
        _buildSegmentedControl(),
        Expanded(
          child: _UserList(
            users: _paginatedUsers,
            isGenerator: widget.isGenerator,
            onTap: widget.onTap,
            onShowRoleDialog: widget.onShowRoleDialog,
            emptyMessage: _gefilterdeGebruikers.isEmpty
                ? 'Geen gebruikers in deze categorie.'
                : null,
          ),
        ),
      ],
    );
  }
}

Color _getRoleColor(String? rol) {
  switch (rol?.toLowerCase()) {
    case 'operator':
      return Colors.blue;
    case 'klant':
      return Colors.green;
    case 'facilitator':
      return Colors.orange;
    case 'generator':
      return Colors.purple;
    case 'admin':
    case 'administrator':
    case 'beheerder':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

Color _roleIconColor(Color rolColor) {
  if (rolColor is MaterialColor) return rolColor.shade700;
  return rolColor;
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.users});

  final List<UserSummary> users;

  int _countRole(String role) =>
      users.where((u) => u.roleString.trim().toLowerCase() == role).length;

  int get _beheer => users.where((u) {
        final r = u.roleString.trim().toLowerCase();
        return r == 'administrator' || r == 'beheerder' || r == 'generator';
      }).length;

  Widget _buildAnalyticsCard(
    String titel,
    int aantal,
    IconData icon,
    Color kleur, {
    double? width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
              Container(
            padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
              color: kleur.withValues(alpha: 0.1),
              shape: BoxShape.circle,
                ),
            child: Icon(icon, color: kleur, size: 24),
              ),
          const SizedBox(height: 16),
          Text(
            aantal.toString(),
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
            ),
          ),
          Text(
            titel,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardData = <({String titel, int aantal, IconData icon, Color kleur})>[
      (
        titel: 'Totaal',
        aantal: users.length,
        icon: Icons.groups_2_rounded,
        kleur: Colors.blue.shade700,
      ),
      (
        titel: 'Operators',
        aantal: _countRole('operator'),
        icon: Icons.badge_outlined,
        kleur: const Color(0xFF2563EB),
      ),
      (
        titel: 'Klanten',
        aantal: _countRole('klant'),
        icon: Icons.business_center_outlined,
        kleur: const Color(0xFF16A34A),
      ),
      (
        titel: 'Facilitators',
        aantal: _countRole('facilitator'),
        icon: Icons.support_agent_outlined,
        kleur: const Color(0xFF7C3AED),
      ),
      (
        titel: 'Beheer',
        aantal: _beheer,
        icon: Icons.admin_panel_settings_outlined,
        kleur: const Color(0xFFEA580C),
      ),
    ];

    final isWide = MediaQuery.of(context).size.width > 900;

    if (isWide) {
      return Row(
        children: [
          for (var i = 0; i < cardData.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: _buildAnalyticsCard(
                cardData[i].titel,
                cardData[i].aantal,
                cardData[i].icon,
                cardData[i].kleur,
              ),
            ),
          ],
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < cardData.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            _buildAnalyticsCard(
              cardData[i].titel,
              cardData[i].aantal,
              cardData[i].icon,
              cardData[i].kleur,
              width: 160,
            ),
          ],
        ],
      ),
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList({
    required this.users,
    required this.isGenerator,
    required this.onTap,
    required this.onShowRoleDialog,
    this.emptyMessage,
  });

  final List<UserSummary> users;
  final bool isGenerator;
  final void Function(UserSummary user) onTap;
  final Future<void> Function(UserSummary user) onShowRoleDialog;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            emptyMessage ?? 'Geen gebruikers gevonden.',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.blueGrey.shade600,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final u = users[index];
        return _UserCard(
          user: u,
          isGenerator: isGenerator,
          onTap: () => onTap(u),
          onShowRoleDialog: () => onShowRoleDialog(u),
        );
      },
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.isGenerator,
    required this.onTap,
    required this.onShowRoleDialog,
  });

  final UserSummary user;
  final bool isGenerator;
  final VoidCallback onTap;
  final VoidCallback onShowRoleDialog;

  @override
  Widget build(BuildContext context) {
    final rol = user.roleString.trim().toLowerCase();
    final displayRol = rol.isEmpty ? 'onbekend' : rol;
    final rolColor = _getRoleColor(displayRol == 'onbekend' ? null : displayRol);

    final emailLabel =
        user.email.trim().isEmpty ? 'Geen e-mail' : user.email.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: rolColor.withValues(alpha: 0.15),
          child: Icon(Icons.person, color: _roleIconColor(rolColor)),
        ),
        title: Text(
          user.name.trim().isEmpty ? '(geen naam)' : user.name.trim(),
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              emailLabel,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: rolColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                displayRol.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: rolColor,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isGenerator)
              PopupMenuButton<String>(
                tooltip: 'Acties',
                onSelected: (v) {
                  if (v == 'role') onShowRoleDialog();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'role',
                    child: Text('Rol wijzigen'),
                  ),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: rolColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Acties',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: rolColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _RoleSwitcherPill extends StatelessWidget {
  const _RoleSwitcherPill({
    required this.role,
    required this.updating,
    required this.disabled,
    required this.onSelected,
  });

  final String role;
  final bool updating;
  final bool disabled;
  final Future<void> Function(String newRole) onSelected;

  static const _options = <String>[
    'klant',
    'operator',
    'facilitator',
    'administrator',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effective = role.trim().isEmpty ? 'onbekend' : role.trim().toLowerCase();
    final canOpen = !disabled && !updating;

    return PopupMenuButton<String>(
      enabled: canOpen,
      tooltip: disabled ? 'Generator is beschermd' : 'Rol wijzigen',
      onSelected: (v) => onSelected(v),
      itemBuilder: (context) {
        return _options
            .map(
              (r) => PopupMenuItem(
                value: r,
                enabled: r != effective,
                child: Text(r),
              ),
            )
            .toList();
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: disabled ? 0.55 : 1,
        child: EnterprisePillBadge(
          text: updating ? 'Bezig…' : effective,
          backgroundColor: cs.primary.withValues(alpha: 0.14),
          textColor: cs.primary,
          borderColor: cs.primary.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}

class _UserDeepDiveSheet extends StatefulWidget {
  const _UserDeepDiveSheet({required this.user});

  final UserSummary user;

  @override
  State<_UserDeepDiveSheet> createState() => _UserDeepDiveSheetState();
}

class _UserDeepDiveSheetState extends State<_UserDeepDiveSheet> {
  late String _role;
  bool _updatingRole = false;

  @override
  void initState() {
    super.initState();
    _role = (widget.user.roleString.trim().isEmpty ? 'onbekend' : widget.user.roleString)
        .trim()
        .toLowerCase();
  }

  bool get _isGenerator => _role == 'generator';

  Future<void> _updateRole(String newRole) async {
    if (_updatingRole) return;
    if (_isGenerator) return;
    final normalized = newRole.trim().toLowerCase();
    if (normalized.isEmpty || normalized == _role) return;

    setState(() => _updatingRole = true);
    try {
      await AppSupabase.client.from('gebruikers').update({
        'gebruikersrol': normalized,
      }).eq('id', widget.user.id);

      if (!mounted) return;
      setState(() => _role = normalized);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rol succesvol gewijzigd')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rol wijzigen mislukt: $e')),
      );
    } finally {
      if (mounted) setState(() => _updatingRole = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? cs.surface : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: DefaultTabController(
            length: 3,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: cs.primary.withValues(alpha: 0.14),
                        child: Icon(Icons.person, color: cs.primary, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.user.email.isEmpty
                                  ? widget.user.id
                                  : widget.user.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.1,
                                color: cs.onSurface.withValues(alpha: 0.70),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _RoleSwitcherPill(
                        role: _role,
                        updating: _updatingRole,
                        disabled: _isGenerator,
                        onSelected: _updateRole,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: isDark ? 0.06 : 0.04),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: TabBar(
                      splashBorderRadius: BorderRadius.circular(24),
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: cs.onSurface.withValues(alpha: 0.70),
                      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                      indicator: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      tabs: const [
                        Tab(text: 'Profiel'),
                        Tab(text: 'Rechten'),
                        Tab(text: 'Activiteit'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    children: [
                      _ProfileTab(
                        scrollController: controller,
                        user: widget.user,
                        role: _role,
                      ),
                      _RightsTab(
                        scrollController: controller,
                        userId: widget.user.id,
                        userRole: _role,
                      ),
                      _ActivityTab(
                        scrollController: controller,
                        userId: widget.user.id,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({
    required this.scrollController,
    required this.user,
    required this.role,
  });

  final ScrollController scrollController;
  final UserSummary user;
  final String role;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  static const List<String> _werkRegioOpties = [
    'Amsterdam',
    "'t Gooi",
    'Stichtse Vecht',
    'Utrecht',
    'Amersfoort',
    'De Ronde Venen',
    'Wijdemeren',
  ];

  Set<String> _selectedWerkRegios = <String>{};
  bool _loadingWerkRegios = true;
  bool _savingWerkRegios = false;
  String? _werkRegioError;

  bool get _isOperator => widget.role.trim().toLowerCase() == 'operator';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWerkRegios());
  }

  @override
  void didUpdateWidget(covariant _ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final roleChanged =
        oldWidget.role.trim().toLowerCase() != widget.role.trim().toLowerCase();
    final userChanged = oldWidget.user.id != widget.user.id;
    if (roleChanged || userChanged) {
      _loadWerkRegios();
    }
  }

  Set<String> _parseWerkRegios(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    if (value is String) {
      final v = value.trim();
      if (v.isEmpty) return <String>{};
      return v
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    return <String>{};
  }

  Future<void> _loadWerkRegios() async {
    setState(() {
      _loadingWerkRegios = true;
      _werkRegioError = null;
    });
    try {
      final row = await AppSupabase.client
          .from(GebruikersTable.name)
          .select('werk_regio')
          .eq(GebruikersTable.id, widget.user.id)
          .maybeSingle();
      final regions = row is Map<String, dynamic>
          ? _parseWerkRegios(row['werk_regio'])
          : <String>{};
      if (!mounted) return;
      setState(() => _selectedWerkRegios = regions);
    } catch (e) {
      if (!mounted) return;
      setState(() => _werkRegioError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingWerkRegios = false);
    }
  }

  Future<void> _saveWerkRegios(Set<String> regionsBefore, Set<String> regionsAfter) async {
    setState(() {
      _selectedWerkRegios = regionsAfter;
      _savingWerkRegios = true;
      _werkRegioError = null;
    });

    try {
      await AppSupabase.client.from(GebruikersTable.name).update({
        'werk_regio': regionsAfter.toList(growable: false),
      }).eq(GebruikersTable.id, widget.user.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _selectedWerkRegios = regionsBefore;
        _werkRegioError = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Werkregio\'s opslaan mislukt: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingWerkRegios = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2E2938) : const Color(0xFFF5F5F7);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Profiel',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 14),
        _ReadOnlyField(
          label: 'Naam',
          value: widget.user.name.isEmpty ? '-' : widget.user.name,
          background: bg,
        ),
        const SizedBox(height: 12),
        _ReadOnlyField(
          label: 'E-mailadres',
          value: widget.user.email.isEmpty ? '-' : widget.user.email,
          background: bg,
        ),
        const SizedBox(height: 12),
        _ReadOnlyField(
          label: 'Systeem Rol',
          value: widget.role.isEmpty ? '-' : widget.role,
          background: bg,
        ),
        const SizedBox(height: 12),
        _ReadOnlyField(
          label: 'Account ID',
          value: widget.user.id,
          background: bg,
        ),
        if (_isOperator) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Toegewezen Werkregio's",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Selecteer een of meerdere regio\'s voor Smart Planner.',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 12),
                if (_loadingWerkRegios)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _werkRegioOpties
                        .map(
                          (regio) => ChoiceChip(
                            label: Text(
                              regio,
                              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                            ),
                            selected: _selectedWerkRegios.contains(regio),
                            onSelected: _savingWerkRegios
                                ? null
                                : (enabled) {
                                    final before = Set<String>.from(_selectedWerkRegios);
                                    final after = Set<String>.from(_selectedWerkRegios);
                                    if (enabled) {
                                      after.add(regio);
                                    } else {
                                      after.remove(regio);
                                    }
                                    _saveWerkRegios(before, after);
                                  },
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            side: BorderSide(
                              color: cs.onSurface.withValues(alpha: 0.15),
                            ),
                            selectedColor: cs.primary.withValues(alpha: 0.14),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (_savingWerkRegios) ...[
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Opslaan...',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface.withValues(alpha: 0.70),
                          ),
                        ),
                      ] else
                        Text(
                          'Wijzigingen worden automatisch opgeslagen.',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface.withValues(alpha: 0.70),
                          ),
                        ),
                    ],
                  ),
                  if (_werkRegioError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Kon werkregio\'s niet laden of opslaan.',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RightsTab extends StatefulWidget {
  const _RightsTab({
    required this.scrollController,
    required this.userId,
    required this.userRole,
  });

  final ScrollController scrollController;
  final String userId;
  final String userRole;

  @override
  State<_RightsTab> createState() => _RightsTabState();
}

class _RightsTabState extends State<_RightsTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _allPermissions = [];
  final Set<String> _assignedPermissionIds = {};
  final Set<String> _busyPermissionIds = {};
  final Set<String> _flashOkPermissionIds = {};
  bool _blockedByRole = false;

  bool get _roleBlocksCustomPermissions {
    final r = widget.userRole.trim().toLowerCase();
    return r == 'operator' || r == 'klant' || r == 'client';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_roleBlocksCustomPermissions) {
        setState(() {
          _blockedByRole = true;
          _loading = false;
        });
        return;
      }
      _load();
    });
  }

  @override
  void didUpdateWidget(covariant _RightsTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.userRole.trim().toLowerCase() ==
        widget.userRole.trim().toLowerCase()) {
      return;
    }

    // Role changed in modal (role switcher). Re-evaluate business rules.
    if (_roleBlocksCustomPermissions) {
      setState(() {
        _blockedByRole = true;
        _loading = false;
        _error = null;
        _allPermissions = [];
        _assignedPermissionIds.clear();
        _busyPermissionIds.clear();
        _flashOkPermissionIds.clear();
      });
      return;
    }

    setState(() {
      _blockedByRole = false;
      _loading = true;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _allPermissions = [];
      _assignedPermissionIds.clear();
      _busyPermissionIds.clear();
      _flashOkPermissionIds.clear();
    });

    try {
      final permsRes = await AppSupabase.client.from(FinancePermissionsTable.name).select(
            '${FinancePermissionsTable.id}, '
            '${FinancePermissionsTable.naam}, '
            'weergave_naam, '
            'omschrijving, '
            'toegestane_rollen, '
            'is_systeem_recht',
          );
      final raw = (permsRes as List).cast<Map<String, dynamic>>();

      // Keep list clean: hide system rights (portal access handled by DB triggers).
      // Also apply strict role filtering (only for facilitator per business rules).
      final selectedRole = widget.userRole.trim().toLowerCase();
      _allPermissions = raw.where((row) {
        if (_isSystemRight(row)) return false;
        if (selectedRole == 'facilitator') {
          final allowed = _allowedRoles(row);
          // If no allowed roles are specified, treat as not assignable.
          if (allowed.isEmpty) return false;
          return allowed.contains('facilitator');
        }
        return true;
      }).toList();

      final rightsRes = await AppSupabase.client
          .from(GebruikerFinanceRechtenTable.name)
          .select(GebruikerFinanceRechtenTable.permissieId)
          .eq(GebruikerFinanceRechtenTable.gebruikerId, widget.userId);
      final rights = (rightsRes as List).cast<Map<String, dynamic>>();
      for (final r in rights) {
        final pid = r[GebruikerFinanceRechtenTable.permissieId]?.toString();
        if (pid != null && pid.isNotEmpty) _assignedPermissionIds.add(pid);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _permName(Map<String, dynamic> row) {
    return (row[FinancePermissionsTable.naam]?.toString() ?? '').trim();
  }

  String _permDisplayName(Map<String, dynamic> row) {
    final w = (row['weergave_naam'] ?? row['weergavenaam'])?.toString().trim();
    if (w != null && w.isNotEmpty) return w;
    return _permName(row);
  }

  String _permId(Map<String, dynamic> row) {
    return (row[FinancePermissionsTable.id]?.toString() ?? '').trim();
  }

  String _permDescription(Map<String, dynamic> row) {
    final d = (row['omschrijving'] ??
            row['description'] ??
            row['beschrijving'] ??
            row['toelichting'])
        ?.toString()
        .trim();
    return (d == null || d.isEmpty) ? '' : d;
  }

  bool _isSystemRight(Map<String, dynamic> row) {
    final v = row['is_systeem_recht'];
    if (v is bool) return v;
    final s = v?.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  Set<String> _allowedRoles(Map<String, dynamic> row) {
    final v = row['toegestane_rollen'];
    if (v is List) {
      return v
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return {};
      // Best-effort: allow comma-separated strings if returned that way.
      return s
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    return {};
  }

  Future<void> _setPermission({
    required String permissionId,
    required bool enabled,
  }) async {
    if (_busyPermissionIds.contains(permissionId)) return;
    setState(() {
      _busyPermissionIds.add(permissionId);
      // Optimistic UI: reflect the toggle immediately.
      if (enabled) {
        _assignedPermissionIds.add(permissionId);
      } else {
        _assignedPermissionIds.remove(permissionId);
      }
    });

    try {
      if (enabled) {
        await AppSupabase.client.from(GebruikerFinanceRechtenTable.name).insert({
          GebruikerFinanceRechtenTable.gebruikerId: widget.userId,
          GebruikerFinanceRechtenTable.permissieId: permissionId,
        });
      } else {
        await AppSupabase.client
            .from(GebruikerFinanceRechtenTable.name)
            .delete()
            .eq(GebruikerFinanceRechtenTable.gebruikerId, widget.userId)
            .eq(GebruikerFinanceRechtenTable.permissieId, permissionId);
      }

      // Subtle feedback only.
      HapticFeedback.selectionClick();
      _flashOkPermissionIds.add(permissionId);
      setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      _flashOkPermissionIds.remove(permissionId);
      setState(() {});
    } catch (e) {
      // Revert optimistic state and surface the failure (client request).
      if (mounted) {
        setState(() {
          if (enabled) {
            _assignedPermissionIds.remove(permissionId);
          } else {
            _assignedPermissionIds.add(permissionId);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
            content: Text('Kon recht niet bijwerken: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyPermissionIds.remove(permissionId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg =
        isDark ? const Color(0xFF2E2938) : const Color(0xFFF5F5F7);

    if (_blockedByRole) {
      return ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'De Sleutelbos',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline,
                  color: cs.onSurface.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Operators en Klanten hebben vaste systeemrechten. '
                    'U kunt hier geen extra privileges toewijzen.',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.80),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Rechten',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _ErrorCard(
            title: 'Kan permissies niet laden',
            message: _error!,
            onRetry: _load,
          ),
        ],
      );
    }

    _allPermissions
        .sort((a, b) => _permDisplayName(a).compareTo(_permDisplayName(b)));

    return ListView.separated(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: _allPermissions.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'De Sleutelbos',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Schakel permissies direct aan/uit voor deze gebruiker.',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface.withValues(alpha: 0.70),
                ),
              ),
            ],
          );
        }

        final row = _allPermissions[index - 1];
        final pid = _permId(row);
        final name = _permDisplayName(row);
        final desc = _permDescription(row);
        final enabled = _assignedPermissionIds.contains(pid);
        final busy = _busyPermissionIds.contains(pid);
        final ok = _flashOkPermissionIds.contains(pid);

        return Container(
          decoration: BoxDecoration(
            color: tileBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name.isEmpty ? '(onbekend)' : name,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          EnterpriseTooltip(message: desc),
                        ],
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: busy
                      ? SizedBox(
                          key: const ValueKey('busy'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(cs.primary),
                          ),
                        )
                      : Icon(
                          ok ? Icons.check_circle : Icons.circle_outlined,
                          key: ValueKey(ok ? 'ok' : 'idle'),
                          size: 18,
                          color: ok
                              ? Colors.green.withValues(alpha: 0.85)
                              : Colors.transparent,
                        ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: enabled,
                  onChanged: pid.isEmpty || busy
                      ? null
                      : (v) => _setPermission(permissionId: pid, enabled: v),
                  activeThumbColor: cs.primary,
                  activeTrackColor: cs.primary.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AuditLogItem {
  const _AuditLogItem({
    required this.action,
    required this.tableName,
    required this.createdAt,
  });

  final String action;
  final String tableName;
  final DateTime createdAt;
}

class _ActivityTab extends StatefulWidget {
  const _ActivityTab({
    required this.scrollController,
    required this.userId,
  });

  final ScrollController scrollController;
  final String userId;

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  Future<List<_AuditLogItem>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<_AuditLogItem>> _fetch() async {
    final res = await AppSupabase.client
        .from('finance_audit_log')
        .select('actie, tabel_naam, created_at')
        .eq('user_id', widget.userId)
        .order('created_at', ascending: false);

    final rows = (res as List).cast<Map<String, dynamic>>();
    return rows.map((r) {
      final rawCreated = r['created_at']?.toString();
      final created =
          rawCreated == null ? DateTime.now() : DateTime.parse(rawCreated);
      return _AuditLogItem(
        action: (r['actie'] ?? '').toString(),
        tableName: (r['tabel_naam'] ?? '').toString(),
        createdAt: created.toLocal(),
      );
    }).toList();
  }

  String _formatTs(BuildContext context, DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    final date = loc.formatShortDate(dt);
    final tod = TimeOfDay.fromDateTime(dt);
    final time = loc.formatTimeOfDay(tod, alwaysUse24HourFormat: true);
    return '$date • $time';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg =
        isDark ? const Color(0xFF2E2938) : const Color(0xFFF5F5F7);

    return FutureBuilder<List<_AuditLogItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Activiteit',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              _ErrorCard(
                title: 'Kan audit-log niet laden',
                message: snapshot.error.toString(),
                onRetry: () => setState(() => _future = _fetch()),
              ),
            ],
          );
        }

        final items = snapshot.data ?? const <_AuditLogItem>[];
        return ListView.separated(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(20),
          itemCount: items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Activiteit',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: tileBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: cs.onSurface.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.history,
                            color: cs.onSurface.withValues(alpha: 0.65),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Geen recente activiteit gevonden voor deze gebruiker.',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface.withValues(alpha: 0.80),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            }

            final it = items[index - 1];
            return _TimelineNode(
              action: it.action,
              tableName: it.tableName,
              timestamp: _formatTs(context, it.createdAt),
              isLast: index == items.length,
            );
          },
        );
      },
    );
  }
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.action,
    required this.tableName,
    required this.timestamp,
    required this.isLast,
  });

  final String action;
  final String tableName;
  final String timestamp;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg =
        isDark ? const Color(0xFF2E2938) : const Color(0xFFF5F5F7);

    final a = action.trim().isEmpty ? 'ACTIE' : action.trim().toUpperCase();
    final t = tableName.trim().isEmpty ? 'Onbekende tabel' : tableName.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 62,
                color: cs.onSurface.withValues(alpha: 0.08),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        a,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  timestamp,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withValues(alpha: 0.70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.background,
  });

  final String label;
  final String value;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: cs.onSurface.withValues(alpha: 0.70),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
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
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w500,
              color: cs.onSurface.withValues(alpha: 0.70),
            ),
          ),
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

