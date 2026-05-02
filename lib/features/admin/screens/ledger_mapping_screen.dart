import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user_role.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';

class LedgerMappingScreen extends StatefulWidget {
  const LedgerMappingScreen({super.key});

  @override
  State<LedgerMappingScreen> createState() => _LedgerMappingScreenState();
}

class _LedgerMappingScreenState extends State<LedgerMappingScreen> {
  Future<List<_LedgerRow>>? _future;
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _busyCodes = {};

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  Future<List<_LedgerRow>> _fetch() async {
    final artikelenRes = await AppSupabase.client
        .from('grootboek_artikelen')
        .select()
        .order('code', ascending: true);
    final artikelen = (artikelenRes as List).cast<Map<String, dynamic>>();

    final mappingRes = await AppSupabase.client.from('grootboek_export_mapping').select();
    final mappings = (mappingRes as List).cast<Map<String, dynamic>>();

    final byInternal = <String, Map<String, dynamic>>{};
    for (final m in mappings) {
      final k = _text(m['interne_code']);
      if (k.isEmpty) continue;
      byInternal[k] = m;
    }

    final rows = <_LedgerRow>[];
    for (final a in artikelen) {
      final code = _text(a['code'] ?? a['interne_code'] ?? a['id']);
      if (code.isEmpty) continue;
      final omschrijving = _text(a['omschrijving'] ?? a['naam'] ?? a['title']);
      final mapped = byInternal[code];
      rows.add(
        _LedgerRow(
          interneCode: code,
          interneOmschrijving: omschrijving,
          accountantCode: _text(mapped?['accountant_code']),
        ),
      );
    }

    // Ensure controllers exist and show current mapping.
    for (final r in rows) {
      final existing = _controllers[r.interneCode];
      if (existing == null) {
        _controllers[r.interneCode] = TextEditingController(text: r.accountantCode);
      } else if (existing.text.trim() != r.accountantCode) {
        existing.text = r.accountantCode;
      }
    }

    return rows;
  }

  void _refresh() {
    setState(() {
      _future = _fetch();
    });
  }

  Future<void> _saveMapping(String interneCode) async {
    if (_busyCodes.contains(interneCode)) return;

    final controller = _controllers[interneCode];
    final value = controller?.text.trim() ?? '';

    setState(() => _busyCodes.add(interneCode));
    try {
      if (value.isEmpty) {
        await AppSupabase.client
            .from('grootboek_export_mapping')
            .delete()
            .eq('interne_code', interneCode);
      } else {
        await AppSupabase.client.from('grootboek_export_mapping').upsert(
          {
            'interne_code': interneCode,
            'accountant_code': value,
            'accountant_omschrijving': 'Gekoppeld via ERP',
          },
          onConflict: 'interne_code',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.90),
          content: const Text('Mapping opgeslagen.'),
        ),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon mapping niet opslaan: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyCodes.remove(interneCode));
    }
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canView = up.hasPermission('finance') ||
        up.role == UserRole.administrator ||
        up.role == UserRole.generator;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    if (!canView) {
      return Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(
            'Grootboek Mapping (RGS)',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
        ),
        body: const Center(child: Text('Geen toegang.')),
      );
    }

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Grootboek Mapping (RGS)',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(tooltip: 'Vernieuwen', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<_LedgerRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: softBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                ),
                child: Text('Kan mapping niet laden: ${snapshot.error}'),
              ),
            );
          }

          final rows = snapshot.data ?? const <_LedgerRow>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            children: [
              Text(
                'Grootboek Mapping (RGS)',
                style: GoogleFonts.inter(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Koppel interne artikelen aan de grootboekrekeningen van uw accountant.',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.70),
                ),
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: softBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                  ),
                  child: Text(
                    'Geen grootboek artikelen gevonden.',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                )
              else
                ...rows.map((r) {
                  final controller = _controllers[r.interneCode]!;
                  final busy = _busyCodes.contains(r.interneCode);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: tileBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: cs.onSurface.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                                    ),
                                    child: Text(
                                      r.interneCode,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.2,
                                        color: cs.onSurface.withValues(alpha: 0.82),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      r.interneOmschrijving.isEmpty ? '—' : r.interneOmschrijving,
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.2,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: controller,
                                      enabled: !busy,
                                      onSubmitted: (_) => _saveMapping(r.interneCode),
                                      decoration: InputDecoration(
                                        labelText: 'Accountant Code',
                                        floatingLabelStyle: GoogleFonts.inter(
                                          fontWeight: FontWeight.w800,
                                          color: cs.onSurface.withValues(alpha: 0.70),
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(24),
                                          borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.10)),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(24),
                                          borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.10)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(24),
                                          borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.8), width: 1.4),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      ),
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                                    ),
                                    child: busy
                                        ? const Padding(
                                            padding: EdgeInsets.all(14),
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : IconButton(
                                            tooltip: 'Opslaan',
                                            onPressed: () => _saveMapping(r.interneCode),
                                            icon: Icon(Icons.save_rounded, color: cs.primary),
                                          ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _LedgerRow {
  const _LedgerRow({
    required this.interneCode,
    required this.interneOmschrijving,
    required this.accountantCode,
  });

  final String interneCode;
  final String interneOmschrijving;
  final String accountantCode;
}

