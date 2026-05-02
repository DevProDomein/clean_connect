import '../contracts/supabase_v1_contract.dart';

/// Rij uit [FinancePermissionsTable.name]; permissie-key = [naam].
class FinancePermissionRow {
  const FinancePermissionRow({
    required this.id,
    this.permissionKey,
  });

  final String id;
  /// [FinancePermissionsTable.naam] — unieke lowercase key.
  final String? permissionKey;

  static FinancePermissionRow? fromRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    final id = row[FinancePermissionsTable.id]?.toString();
    if (id == null || id.isEmpty) return null;
    final raw = row[FinancePermissionsTable.naam];
    final key = raw?.toString().trim().toLowerCase();
    return FinancePermissionRow(
      id: id,
      permissionKey: (key == null || key.isEmpty) ? null : key,
    );
  }
}
