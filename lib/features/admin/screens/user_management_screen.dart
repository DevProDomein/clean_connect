import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/models/user_role.dart';
import '../../../core/services/invitation_service.dart';
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

class _UserManagementScreenState extends State<UserManagementScreen> {
  Future<List<UserSummary>>? _future;

  @override
  void initState() {
    super.initState();
    _future = UserManagementService().fetchAllUsers();
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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
          child: const Icon(Icons.add),
        ),
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
                    child: _TopTabs(),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Tab 1: Medewerkers (existing list + modal)
                        DefaultTabController(
                          length: 5,
                          child: Column(
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(24, 10, 24, 10),
                                child: _FilterTabs(),
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _UserList(
                                      users: users,
                                      filter: (u) => true,
                                      isGenerator: up.isGenerator,
                                      onTap: _openDeepDive,
                                      onShowRoleDialog: _showChangeRoleDialog,
                                    ),
                                    _UserList(
                                      users: users,
                                      filter: (u) =>
                                          u.roleString.trim().toLowerCase() ==
                                          'klant',
                                      isGenerator: up.isGenerator,
                                      onTap: _openDeepDive,
                                      onShowRoleDialog: _showChangeRoleDialog,
                                    ),
                                    _UserList(
                                      users: users,
                                      filter: (u) =>
                                          u.roleString.trim().toLowerCase() ==
                                          'operator',
                                      isGenerator: up.isGenerator,
                                      onTap: _openDeepDive,
                                      onShowRoleDialog: _showChangeRoleDialog,
                                    ),
                                    _UserList(
                                      users: users,
                                      filter: (u) =>
                                          u.roleString.trim().toLowerCase() ==
                                          'facilitator',
                                      isGenerator: up.isGenerator,
                                      onTap: _openDeepDive,
                                      onShowRoleDialog: _showChangeRoleDialog,
                                    ),
                                    _UserList(
                                      users: users,
                                      filter: (u) {
                                        final r =
                                            u.roleString.trim().toLowerCase();
                                        return r == 'administrator' ||
                                            r == 'beheerder' ||
                                            r == 'generator';
                                      },
                                      isGenerator: up.isGenerator,
                                      onTap: _openDeepDive,
                                      onShowRoleDialog: _showChangeRoleDialog,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
      ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: TabBar(
        // More breathing room: bigger tabs + bigger active pill.
        labelPadding: const EdgeInsets.symmetric(horizontal: 24),
        indicatorPadding: EdgeInsets.zero,
        splashBorderRadius: BorderRadius.circular(24),
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 20,
              offset: const Offset(0, 5),
            ),
          ],
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
        labelColor: cs.onSurface,
        unselectedLabelColor: cs.onSurface.withValues(alpha: 0.60),
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w900),
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

  String _email = '';
  String _firstName = '';
  String _lastName = '';

  String? _role;
  bool _grantAdmin = false;
  bool _submitting = false;

  List<String> _roleOptions(UserProvider inviter) {
    final isFacilitator = inviter.role == UserRole.facilitator;

    if (inviter.isGenerator) return const ['facilitator', 'operator', 'klant'];

    if (isFacilitator && inviter.hasPermission('invite_operator')) {
      return const ['operator', 'klant'];
    }

    if (isFacilitator) return const ['klant'];

    // Default: no invite capability.
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final inviter = context.watch<UserProvider>();
    final options = _roleOptions(inviter);

    _role ??= options.isNotEmpty ? options.first : null;
    if (_role != 'facilitator') _grantAdmin = false;

    return AlertDialog(
      title: const Text('Nieuwe medewerker'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'E-mailadres',
                ),
                keyboardType: TextInputType.emailAddress,
                onChanged: (v) => _email = v,
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Vul een e-mailadres in.';
                  if (!s.contains('@')) return 'Ongeldig e-mailadres.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'Voornaam'),
                      onChanged: (v) => _firstName = v,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Vul een voornaam in.' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'Achternaam'),
                      onChanged: (v) => _lastName = v,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Vul een achternaam in.'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Rol'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    items: options
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    value: _role,
                    onChanged: options.isEmpty
                        ? null
                        : (v) {
                            setState(() => _role = v);
                          },
                  ),
                ),
              ),
              if (inviter.isGenerator && _role == 'facilitator') ...[
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _grantAdmin,
                  onChanged: (v) => setState(() => _grantAdmin = v),
                  title: const Text('Admin status verlenen'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuleren'),
        ),
        FilledButton(
          onPressed: _submitting
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  if (_role == null) return;

                  setState(() => _submitting = true);
                  try {
                    await InvitationService().inviteUser(
                      email: _email,
                      firstName: _firstName,
                      lastName: _lastName,
                      role: _role!,
                      grantAdminStatus: _grantAdmin,
                    );
                    if (!context.mounted) return;
                    Navigator.of(context).pop(true);
                  } on StateError catch (e) {
                    if (!context.mounted) return;
                    await showDialog<void>(
                      context: context,
                      builder: (context) => SelectionArea(
                        child: AlertDialog(
                          title: const Text('Instelling vereist'),
                          content: Text(e.message),
                          actions: [
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Sluiten'),
                            ),
                          ],
                        ),
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Uitnodigen mislukt: $e')),
                    );
                  } finally {
                    if (mounted) setState(() => _submitting = false);
                  }
                },
          child: Text(_submitting ? 'Bezig…' : 'Uitnodiging versturen'),
        ),
      ],
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

class _FilterTabs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? cs.surface.withValues(alpha: 0.65) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
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
      // More container padding so the pill never looks cramped.
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: TabBar(
        isScrollable: true,
        // Bigger tabs = bigger active pill.
        labelPadding: const EdgeInsets.symmetric(horizontal: 18),
        indicatorPadding: EdgeInsets.zero,
        splashBorderRadius: BorderRadius.circular(24),
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: cs.onSurface.withValues(alpha: 0.70),
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        unselectedLabelStyle:
            GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: -0.2),
        indicator: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        tabs: const [
          Tab(text: 'Alle'),
          Tab(text: 'Klanten'),
          Tab(text: 'Operators'),
          Tab(text: 'Facilitators'),
          Tab(text: 'Beheer'),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.users});

  final List<UserSummary> users;

  int get _total => users.length;

  int get _operators =>
      users.where((u) => u.roleString.trim().toLowerCase() == 'operator').length;

  int get _beheer {
    return users.where((u) {
      final r = u.roleString.trim().toLowerCase();
      return r == 'administrator' ||
          r == 'beheerder' ||
          r == 'generator';
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    double pct(int part) => total <= 0 ? 0 : (part / total).clamp(0, 1);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _StatCard(
            label: 'Totaal Gebruikers',
            value: total.toString(),
            icon: Icons.groups_2,
            progress: 1,
          ),
          const SizedBox(width: 14),
          _StatCard(
            label: 'Operators',
            value: _operators.toString(),
            icon: Icons.badge,
            progress: pct(_operators),
          ),
          const SizedBox(width: 14),
          _StatCard(
            label: 'Beheerders',
            value: _beheer.toString(),
            icon: Icons.admin_panel_settings,
            progress: pct(_beheer),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.progress,
  });

  final String label;
  final String value;
  final IconData icon;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? cs.surface.withValues(alpha: 0.92) : Colors.white;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: cs.primary),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: cs.onSurface.withValues(alpha: 0.70),
            ),
          ),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0, 1)),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 7,
                  backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList({
    required this.users,
    required this.filter,
    required this.isGenerator,
    required this.onTap,
    required this.onShowRoleDialog,
  });

  final List<UserSummary> users;
  final bool Function(UserSummary) filter;
  final bool isGenerator;
  final void Function(UserSummary user) onTap;
  final Future<void> Function(UserSummary user) onShowRoleDialog;

  @override
  Widget build(BuildContext context) {
    final filtered = users.where(filter).toList();
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Geen gebruikers in deze categorie.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      itemCount: filtered.length + 1,
      itemBuilder: (context, index) {
        if (index == filtered.length) {
          return const SizedBox(height: 120);
        }
        final u = filtered[index];
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

    Color rolKleur = Colors.grey;
    if (displayRol == 'operator') rolKleur = Colors.blue;
    if (displayRol == 'generator' || displayRol == 'facilitator') {
      rolKleur = Colors.purple;
    }
    if (displayRol == 'klant') rolKleur = Colors.green;

    var initial = '?';
    final nameParts = user.name.trim().split(RegExp(r'\s+'));
    if (nameParts.isNotEmpty && nameParts.first.isNotEmpty) {
      initial = nameParts.first.substring(0, 1).toUpperCase();
    }

    final emailLabel =
        user.email.trim().isEmpty ? 'Geen e-mail' : user.email.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: rolKleur.withValues(alpha: 0.1),
          child: Text(
            initial,
            style: TextStyle(
              color: rolKleur,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        title: Text(
          user.name.trim().isEmpty ? '(geen naam)' : user.name.trim(),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
                color: rolKleur.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                displayRol.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: rolKleur,
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
                    color: rolKleur.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Acties',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: rolKleur,
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

