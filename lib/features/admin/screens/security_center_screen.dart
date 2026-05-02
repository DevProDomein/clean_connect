import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/models/master_data_wijzigingsverzoek.dart';
import '../../../core/supabase_client.dart';
import '../../../providers/user_provider.dart';
import '../../../shared/widgets/enterprise_tooltip.dart';

class SecurityCenterScreen extends StatefulWidget {
  const SecurityCenterScreen({super.key});

  @override
  State<SecurityCenterScreen> createState() => _SecurityCenterScreenState();
}

class _PendingChange {
  const _PendingChange({
    required this.request,
    required this.submittedByName,
  });

  final MasterDataWijzigingsverzoek request;
  final String submittedByName;
}

class _SecurityCenterScreenState extends State<SecurityCenterScreen> {
  Future<List<_PendingChange>> _fetchPendingRequests() async {
    final res = await AppSupabase.client
        .from(MasterDataWijzigingsverzoekenTable.name)
        .select(
          '${MasterDataWijzigingsverzoekenTable.id}, '
          '${MasterDataWijzigingsverzoekenTable.tabelNaam}, '
          '${MasterDataWijzigingsverzoekenTable.veldNaam}, '
          '${MasterDataWijzigingsverzoekenTable.oudeWaarde}, '
          '${MasterDataWijzigingsverzoekenTable.nieuweWaarde}, '
          '${MasterDataWijzigingsverzoekenTable.ingediendDoorId}, '
          '${MasterDataWijzigingsverzoekenTable.status}, '
          // Join: get who submitted (name/email).
          'ingediend_door:${MasterDataWijzigingsverzoekenTable.ingediendDoorId}('
          '${GebruikersTable.voornaam}, ${GebruikersTable.achternaam}, ${GebruikersTable.email}'
          ')',
        )
        .eq(MasterDataWijzigingsverzoekenTable.status, 'pending')
        .order('id', ascending: false);

    final rows = (res as List).cast<Map<String, dynamic>>();
    return rows.map((row) {
      final req = MasterDataWijzigingsverzoek.fromRow(row);
      final submitted =
          (row['ingediend_door'] as Map?)?.cast<String, dynamic>() ?? {};
      final voornaam = (submitted[GebruikersTable.voornaam] ?? '').toString();
      final achternaam = (submitted[GebruikersTable.achternaam] ?? '').toString();
      final email = (submitted[GebruikersTable.email] ?? '').toString();
      final name = ('${voornaam.trim()} ${achternaam.trim()}').trim();

      return _PendingChange(
        request: req,
        submittedByName: name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Onbekend'),
      );
    }).toList();
  }

  Future<void> _approve(MasterDataWijzigingsverzoek request) async {
    final id = request.id;
    if (id == null || id.isEmpty) throw StateError('Onbekend wijzigingsverzoek-id');

    await AppSupabase.client.rpc(
      'execute_master_data_change',
      params: {'p_request_id': id},
    );
  }

  Future<void> _reject(MasterDataWijzigingsverzoek request) async {
    final requestId = request.id;
    if (requestId == null || requestId.isEmpty) throw StateError('Onbekend wijzigingsverzoek-id');
    await AppSupabase.client
        .from(MasterDataWijzigingsverzoekenTable.name)
        .update({MasterDataWijzigingsverzoekenTable.status: 'rejected'})
        .eq(MasterDataWijzigingsverzoekenTable.id, requestId);
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();

    // Permission-based access (aligned with AppDrawer).
    final isAllowed =
        userProvider.isGenerator || userProvider.hasPermission('security_center');

    if (!isAllowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Beveiligingscentrum')),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Geen toegang.'),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final surface = isDark ? const Color(0xFF2E2938) : const Color(0xFFF5F5F7);

    return Scaffold(
      appBar: AppBar(title: const Text('Beveiligingscentrum')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Beveiligingscentrum',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Autorisatie & Wijzigingsverzoeken',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.70),
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<_PendingChange>>(
                future: _fetchPendingRequests(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _ErrorBox(
                      title: 'Kan wijzigingsverzoeken niet laden',
                      message: snapshot.error.toString(),
                      onRetry: () => setState(() {}),
                    );
                  }

                  final rows = snapshot.data ?? const [];
                  if (rows.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: cs.onSurface.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            color: cs.onSurface.withValues(alpha: 0.65),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Geen openstaande wijzigingsverzoeken.',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final currentUserId = AppSupabase.client.auth.currentUser?.id;

                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final item = rows[i];
                      final req = item.request;
                      final isOwnRequest = currentUserId != null &&
                          req.ingediendDoorId == currentUserId;

                      final tabel = (req.tabelNaam ?? '').trim();
                      final veld = (req.veldNaam ?? '').trim();
                      final oud = (req.oudeWaarde ?? '').trim();
                      final nieuw = (req.nieuweWaarde ?? '').trim();

                      return Container(
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
                          border: Border.all(
                            color: cs.onSurface.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Wijziging in tabel: ${tabel.isEmpty ? '—' : tabel}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Veld: ${veld.isEmpty ? '—' : veld}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.78),
                                  ),
                            ),
                            const SizedBox(height: 12),
                            _ValueCompareRow(
                              oldValue: oud,
                              newValue: nieuw,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Ingediend door: ${item.submittedByName}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.75),
                                  ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: Colors.red.withValues(alpha: 0.55),
                                      ),
                                      foregroundColor: Colors.red,
                                    ),
                                    onPressed: () async {
                                      try {
                                        await _reject(req);
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Verzoek afgewezen.'),
                                          ),
                                        );
                                        setState(() {});
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Fout: $e')),
                                        );
                                      }
                                    },
                                    child: const Text('Afwijzen'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Stack(
                                    alignment: Alignment.centerRight,
                                    children: [
                                      FilledButton(
                                        onPressed: isOwnRequest
                                            ? null
                                            : () async {
                                                try {
                                                  await _approve(req);
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Verzoek goedgekeurd en uitgevoerd.',
                                                      ),
                                                    ),
                                                  );
                                                  setState(() {});
                                                } catch (e) {
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(content: Text('Fout: $e')),
                                                  );
                                                }
                                              },
                                        child: const Text('Goedkeuren'),
                                      ),
                                      if (isOwnRequest)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 12),
                                          child: EnterpriseTooltip(
                                            message:
                                                'U kunt uw eigen verzoek niet goedkeuren (Vier-ogen principe).',
                                          ),
                                        ),
                                    ],
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueCompareRow extends StatelessWidget {
  const _ValueCompareRow({
    required this.oldValue,
    required this.newValue,
  });

  final String oldValue;
  final String newValue;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final oldText = oldValue.isEmpty ? '—' : oldValue;
    final newText = newValue.isEmpty ? '—' : newValue;

    return Row(
      children: [
        Expanded(
          child: Text(
            oldText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.red.withValues(alpha: 0.75),
                  decoration: TextDecoration.lineThrough,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Icon(
            Icons.arrow_forward,
            size: 18,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
        Expanded(
          child: Text(
            newText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.green.withValues(alpha: 0.80),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF2E2938) : const Color(0xFFF5F5F7);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.75),
                ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Opnieuw laden'),
          ),
        ],
      ),
    );
  }
}
