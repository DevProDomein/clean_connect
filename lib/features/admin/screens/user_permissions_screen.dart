import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/supabase_client.dart';
import '../../../providers/user_provider.dart';

/// Admin UI to assign [FinancePermissionsTable] aan gebruikers via
/// [GebruikerFinanceRechtenTable] (contract V1.0).
///
/// Permissions are grouped into **Portaal Toegang** (`portal_*`) and
/// **Financiële Acties** (codes/names containing `manage_invoices`).
class UserPermissionsScreen extends StatefulWidget {
  const UserPermissionsScreen({super.key});

  @override
  State<UserPermissionsScreen> createState() => _UserPermissionsScreenState();
}

class _UserPermissionsScreenState extends State<UserPermissionsScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _allPermissions = [];
  List<Map<String, dynamic>> _candidateUsers = [];
  String? _selectedUserId;

  /// Permission row `id` (uuid or int as string) -> selected
  final Map<String, bool> _selectedByPermissionId = {};

  static String _permId(Map<String, dynamic> row) {
    return row[FinancePermissionsTable.id]?.toString() ?? '';
  }

  static String _permCode(Map<String, dynamic> row) {
    return row[FinancePermissionsTable.naam]?.toString().trim().toLowerCase() ?? '';
  }

  static String _permLabel(Map<String, dynamic> row) {
    final naam = row[FinancePermissionsTable.naam]?.toString().trim();
    if (naam != null && naam.isNotEmpty) return naam;
    return _permId(row);
  }

  static bool _isPortalPermission(String code) => code.startsWith('portal_');

  static bool _isFinanceActionPermission(String code) =>
      code.contains('manage_invoices');

  bool _canEdit(BuildContext context) {
    final p = context.read<UserProvider>();
    return p.isGenerator ||
        p.hasPermission('portal_admin') ||
        p.hasPermission('finance');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (!_canEdit(context)) {
      setState(() {
        _loading = false;
        _error = 'Geen rechten om gebruikerspermissies te beheren.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final permsRes =
          await AppSupabase.client.from(FinancePermissionsTable.name).select();
      final perms = (permsRes as List).cast<Map<String, dynamic>>();
      if (perms.isEmpty && mounted) {
        // Most common cause: RLS blocks SELECT, returning 0 rows.
        // Generator in-app does not bypass database RLS.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Geen permissies geladen uit finance_permissions. '
              'Controleer RLS/GRANT policies in Supabase.',
            ),
          ),
        );
      }

      // Contract V1.0: use `gebruikers_metadata` as the UI mirror.
      final u = await AppSupabase.client.from(GebruikersMetadataTable.name).select(
            '${GebruikersMetadataTable.id}, ${GebruikersMetadataTable.email}, '
            '${GebruikersMetadataTable.naam}',
          ).limit(200);
      final users = (u as List).cast<Map<String, dynamic>>();

      if (!mounted) return;

      final validIds = users
          .map(_userIdFromRow)
          .whereType<String>()
          .where((e) => e.isNotEmpty)
          .toList();

      setState(() {
        _allPermissions = perms;
        _candidateUsers = users;
        _selectedUserId ??= _inferInitialUserId(users);
        if (_selectedUserId != null && !validIds.contains(_selectedUserId)) {
          _selectedUserId =
              validIds.isNotEmpty ? validIds.first : _inferInitialUserId(users);
        }
      });

      if (_selectedUserId != null) {
        await _loadSelectionsForUser(_selectedUserId!);
      } else {
        for (final p in perms) {
          final id = _permId(p);
          if (id.isNotEmpty) _selectedByPermissionId[id] = false;
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _inferInitialUserId(List<Map<String, dynamic>> users) {
    final self = AppSupabase.client.auth.currentUser?.id;
    for (final row in users) {
      final v = row[GebruikersTable.id]?.toString() ??
          row[GebruikersMetadataTable.id]?.toString();
      if (v != null && v.isNotEmpty && self != null && v == self) return v;
    }
    if (users.isEmpty) return self;
    final first = users.first;
    return first[GebruikersTable.id]?.toString() ??
        first[GebruikersMetadataTable.id]?.toString();
  }

  String? _userIdFromRow(Map<String, dynamic> row) {
    return row[GebruikersTable.id]?.toString() ??
        row[GebruikersMetadataTable.id]?.toString();
  }

  String _userLabel(Map<String, dynamic> row) {
    final id = _userIdFromRow(row) ?? '';
    final mail =
        (row[GebruikersTable.email] ?? row[GebruikersMetadataTable.email] ?? '')
            .toString()
            .trim();
    if (mail.isNotEmpty) return '$mail ($id)';
    final vn = row[GebruikersTable.voornaam]?.toString().trim() ?? '';
    final an = row[GebruikersTable.achternaam]?.toString().trim() ?? '';
    final nm = row[GebruikersMetadataTable.naam]?.toString().trim() ?? '';
    final name = [vn, an].where((e) => e.isNotEmpty).join(' ');
    if (name.isNotEmpty) return '$name ($id)';
    if (nm.isNotEmpty) return '$nm ($id)';
    return id.isEmpty ? '(onbekend)' : id;
  }

  Future<void> _loadSelectionsForUser(String userId) async {
    _selectedByPermissionId.clear();
    for (final p in _allPermissions) {
      final id = _permId(p);
      if (id.isNotEmpty) _selectedByPermissionId[id] = false;
    }

    try {
      final res = await AppSupabase.client
          .from(GebruikerFinanceRechtenTable.name)
          .select(
            '${GebruikerFinanceRechtenTable.permissieId}, '
            '${FinancePermissionsTable.name}(${FinancePermissionsTable.id})',
          )
          .eq(GebruikerFinanceRechtenTable.gebruikerId, userId);

      final rows = (res as List).cast<Map<String, dynamic>>();
      for (final row in rows) {
        var pid = row[GebruikerFinanceRechtenTable.permissieId]?.toString();
        if (pid == null || pid.isEmpty) {
          final nested = row[FinancePermissionsTable.name];
          if (nested is Map) {
            pid = nested[FinancePermissionsTable.id]?.toString();
          }
        }
        if (pid != null && pid.isNotEmpty) {
          _selectedByPermissionId[pid] = true;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kon rechten niet laden: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    final userId = _selectedUserId;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecteer eerst een gebruiker.')),
      );
      return;
    }

    final wanted = _selectedByPermissionId.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toSet();

    try {
      final knownIds =
          _allPermissions.map(_permId).where((e) => e.isNotEmpty).toSet();
      final existingRows = await _fetchAllRightsRows(userId);
      final existingPermIds = <String>{};
      for (final row in existingRows) {
        var pid = row[GebruikerFinanceRechtenTable.permissieId]?.toString();
        if (pid == null || pid.isEmpty) {
          final nested = row[FinancePermissionsTable.name];
          if (nested is Map) {
            pid = nested[FinancePermissionsTable.id]?.toString();
          }
        }
        if (pid != null && pid.isNotEmpty && knownIds.contains(pid)) {
          existingPermIds.add(pid);
        }
      }

      final toAdd = wanted.difference(existingPermIds);
      final toRemove = existingPermIds.difference(wanted);

      for (final pid in toAdd) {
        await _insertRight(userId, pid);
      }
      for (final pid in toRemove) {
        await _deleteRight(userId, pid);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rechten opgeslagen.')),
        );
        await context.read<UserProvider>().loadForCurrentUser();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opslaan mislukt: $e')),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAllRightsRows(String userId) async {
    final res = await AppSupabase.client
        .from(GebruikerFinanceRechtenTable.name)
        .select()
        .eq(GebruikerFinanceRechtenTable.gebruikerId, userId);
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> _insertRight(String userId, String permissionId) async {
    await AppSupabase.client.from(GebruikerFinanceRechtenTable.name).insert({
      GebruikerFinanceRechtenTable.gebruikerId: userId,
      GebruikerFinanceRechtenTable.permissieId: permissionId,
    });
  }

  Future<void> _deleteRight(String userId, String permissionId) async {
    await AppSupabase.client
        .from(GebruikerFinanceRechtenTable.name)
        .delete()
        .eq(GebruikerFinanceRechtenTable.gebruikerId, userId)
        .eq(GebruikerFinanceRechtenTable.permissieId, permissionId);
  }

  @override
  Widget build(BuildContext context) {
    if (!_canEdit(context)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gebruikersrechten')),
        body: const Center(child: Text('Geen toegang.')),
      );
    }

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gebruikersrechten')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!),
        ),
      );
    }

    final portals = <Map<String, dynamic>>[];
    final financeActions = <Map<String, dynamic>>[];
    final other = <Map<String, dynamic>>[];

    for (final p in _allPermissions) {
      final code = _permCode(p);
      if (_isPortalPermission(code)) {
        portals.add(p);
      } else if (_isFinanceActionPermission(code)) {
        financeActions.add(p);
      } else {
        other.add(p);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gebruikersrechten'),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_candidateUsers.isNotEmpty) ...[
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Gebruiker',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedUserId != null &&
                          _candidateUsers.any((u) => _userIdFromRow(u) == _selectedUserId)
                      ? _selectedUserId
                      : null,
                  items: _candidateUsers
                      .map((u) {
                        final id = _userIdFromRow(u);
                        if (id == null || id.isEmpty) return null;
                        return DropdownMenuItem(
                          value: id,
                          child: Text(_userLabel(u)),
                        );
                      })
                      .whereType<DropdownMenuItem<String>>()
                      .toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _selectedUserId = v);
                    await _loadSelectionsForUser(v);
                    setState(() {});
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _PermissionSection(
            title: 'Portaal Toegang',
            permissions: portals,
            selectedById: _selectedByPermissionId,
            permId: _permId,
            permLabel: _permLabel,
            onChanged: (id, value) {
              setState(() => _selectedByPermissionId[id] = value);
            },
          ),
          const SizedBox(height: 12),
          _PermissionSection(
            title: 'Financiële Acties',
            subtitle: 'Codes/namen met manage_invoices',
            permissions: financeActions,
            selectedById: _selectedByPermissionId,
            permId: _permId,
            permLabel: _permLabel,
            onChanged: (id, value) {
              setState(() => _selectedByPermissionId[id] = value);
            },
          ),
          if (other.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PermissionSection(
              title: 'Overige permissies',
              permissions: other,
              selectedById: _selectedByPermissionId,
              permId: _permId,
              permLabel: _permLabel,
              onChanged: (id, value) {
                setState(() => _selectedByPermissionId[id] = value);
              },
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
  }
}

class _PermissionSection extends StatelessWidget {
  const _PermissionSection({
    required this.title,
    this.subtitle,
    required this.permissions,
    required this.selectedById,
    required this.permId,
    required this.permLabel,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final List<Map<String, dynamic>> permissions;
  final Map<String, bool> selectedById;
  final String Function(Map<String, dynamic>) permId;
  final String Function(Map<String, dynamic>) permLabel;
  final void Function(String id, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        children: [
          if (permissions.isEmpty)
            const ListTile(title: Text('— geen items —'))
          else
            ...permissions.map((p) {
              final id = permId(p);
              if (id.isEmpty) return const SizedBox.shrink();
              final checked = selectedById[id] ?? false;
              return SwitchListTile(
                title: Text(permLabel(p)),
                subtitle: Text(id, maxLines: 1, overflow: TextOverflow.ellipsis),
                value: checked,
                onChanged: (v) => onChanged(id, v),
              );
            }),
        ],
      ),
    );
  }
}
