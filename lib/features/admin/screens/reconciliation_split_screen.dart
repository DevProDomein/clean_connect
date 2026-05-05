import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase_client.dart';
import '../../../providers/user_provider.dart';

class ReconciliationSplitScreen extends StatefulWidget {
  const ReconciliationSplitScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  State<ReconciliationSplitScreen> createState() => _ReconciliationSplitScreenState();
}

class _ReconciliationSplitScreenState extends State<ReconciliationSplitScreen> {
  Future<_ReconData>? _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_ReconData> _fetch() async {
    final tx = await AppSupabase.client
        .from('app_bank_reconciliatie_dashboard')
        .select()
        .eq('id', widget.transactionId)
        .maybeSingle();

    if (tx == null) {
      throw StateError('Transactie niet gevonden.');
    }

    final bedrag = _asDouble(tx['bedrag']);
    final isPositive = bedrag >= 0;

    final invoices = await _fetchOpenInvoices(isPositive: isPositive);
    final grootboekRes = await AppSupabase.client
        .from('grootboekrekeningen')
        .select()
        .order('rekening_nummer', ascending: true);
    final grootboek = (grootboekRes as List).cast<Map<String, dynamic>>();

    return _ReconData(
      transaction: tx,
      isPositive: isPositive,
      invoices: invoices,
      grootboek: grootboek,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchOpenInvoices({required bool isPositive}) async {
    if (isPositive) {
      final res = await AppSupabase.client
          .from('facturen')
          .select()
          .gt('openstaand_saldo', 0)
          .order('verval_datum', ascending: true);
      return (res as List).cast<Map<String, dynamic>>();
    }

    final res = await AppSupabase.client
        .from('inkoopfacturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .gt('openstaand_saldo', 0)
        .order('factuur_datum', ascending: true);
    return (res as List).cast<Map<String, dynamic>>();
  }

  void _refresh() {
    setState(() {
      _future = _fetch();
    });
  }

  static String _text(dynamic v) => (v ?? '').toString().trim();

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  NumberFormat _eur() => NumberFormat.currency(locale: 'nl_NL', symbol: '€', decimalDigits: 2);

  Future<void> _allocateToInvoice({
    required Map<String, dynamic> tx,
    required Map<String, dynamic> invoice,
    required bool isPositive,
  }) async {
    final rest = _asDouble(tx['rest_bedrag'] ?? tx['bedrag']);
    final restAbs = rest.abs();
    final invoiceId = _text(invoice['id']);
    if (invoiceId.isEmpty) return;

    final amountCtrl = TextEditingController(text: restAbs.toStringAsFixed(2));
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return SelectionArea(
          child: StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                title: Text(
                  'Afletteren',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hoeveel van het transactie-bedrag (${_eur().format(restAbs)}) wilt u toewijzen aan deze factuur?',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Bedrag'),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Annuleren'),
                  ),
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            final amt = _asDouble(amountCtrl.text.trim());
                            if (amt <= 0 || amt > restAbs) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
                                  content: const Text('Voer een geldig bedrag in.'),
                                ),
                              );
                              return;
                            }

                            setState(() => busy = true);
                            try {
                              final payload = <String, dynamic>{
                                'bank_transactie_id': _text(tx['id']),
                                'afgeletterd_bedrag': amt,
                              };
                              if (isPositive) {
                                payload['factuur_id'] = invoiceId;
                              } else {
                                payload['inkoopfactuur_id'] = invoiceId;
                              }

                              await AppSupabase.client.from('factuur_afletteringen').insert(payload);

                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
                                  content: Text('Afletteren mislukt: $e'),
                                ),
                              );
                            } finally {
                              if (context.mounted) setState(() => busy = false);
                            }
                          },
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.link_rounded),
                    label: const Text('Toewijzen'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    amountCtrl.dispose();

    // Refresh transaction to get updated rest_bedrag from triggers.
    _refresh();
    // If triggers set rest_bedrag to 0, close cockpit on next frame (after refresh).
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final refreshed = await AppSupabase.client
            .from('app_bank_reconciliatie_dashboard')
            .select('rest_bedrag')
            .eq('id', widget.transactionId)
            .maybeSingle();
        final restNow = _asDouble(refreshed?['rest_bedrag']);
        if (!mounted) return;
        if (restNow.abs() <= 0.0001) {
          Navigator.of(context).pop();
        }
      } catch (_) {
        // ignore
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canView = up.isGenerator || up.hasPermission('finance') || up.hasPermission('sync_bank');

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    if (!canView) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Afletteren',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
        ),
        body: const SelectionArea(child: Center(child: Text('Geen toegang.'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Afletteren',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(tooltip: 'Vernieuwen', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SelectionArea(
        child: FutureBuilder<_ReconData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: _ErrorState(
                  title: 'Kan cockpit niet laden',
                  message: snapshot.error.toString(),
                  onRetry: _refresh,
                ),
              );
            }

            final data = snapshot.data!;
            final tx = data.transaction;
            final rest = _asDouble(tx['rest_bedrag'] ?? tx['bedrag']);
            final restAbs = rest.abs();

            final invoicesFiltered = data.invoices.where((inv) {
              if (_query.trim().isEmpty) return true;
              final q = _query.trim().toLowerCase();
              final nr =
                  _text(inv['factuur_nummer'] ?? inv['factuur_nummer_leverancier']);
              final klant = _text(
                inv['debiteur_naam'] ?? (inv['bedrijven'] as Map?)?['bedrijfsnaam'],
              );
              return nr.toLowerCase().contains(q) || klant.toLowerCase().contains(q);
            }).toList();

            Widget leftPanel() {
              final datum = _text(tx['transactie_datum']);
              final tegen = _text(tx['tegenrekening_naam']);
              final oms = _text(tx['omschrijving']);
              final bedrag = _asDouble(tx['bedrag']);
              final status = _text(tx['matching_status']);

              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Banktransactie',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: cs.onSurface.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                          ),
                          child: Text(
                            status.isEmpty ? '—' : status,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _kv('Datum', datum.isEmpty ? '—' : datum),
                    _kv('Tegenrekening', tegen.isEmpty ? '—' : tegen),
                    _kv('Omschrijving', oms.isEmpty ? '—' : oms),
                    _kv('Bedrag', _eur().format(bedrag)),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.payments_rounded, color: cs.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Restbedrag',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            _eur().format(restAbs),
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              letterSpacing: -0.3,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tip: wijs (gedeeltelijk) toe aan een factuur, of boek direct op grootboek.',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget rightPanel() {
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Match Finder',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: softBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                        ),
                        child: TabBar(
                          dividerColor: Colors.transparent,
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelColor: Colors.white,
                          unselectedLabelColor: cs.onSurface.withValues(alpha: 0.72),
                          indicator: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          tabs: const [
                            Tab(text: 'Facturen'),
                            Tab(text: 'Grootboekrekeningen'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'Zoeken (factuurnummer / klant)',
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _InvoicesTab(
                              invoices: invoicesFiltered,
                              isPositive: data.isPositive,
                              onSelect: (inv) => _allocateToInvoice(
                                tx: tx,
                                invoice: inv,
                                isPositive: data.isPositive,
                              ),
                            ),
                            _LedgerTab(
                              grootboek: data.grootboek,
                              onSelect: (g) async {
                                // UI only for now (SQL wiring later).
                                final descCtrl = TextEditingController();
                                final amountCtrl =
                                    TextEditingController(text: restAbs.toStringAsFixed(2));
                                await showDialog<void>(
                                  context: context,
                                  builder: (context) {
                                    return SelectionArea(
                                      child: AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(24),
                                        ),
                                        title: Text(
                                          'Boeken op Grootboek',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextField(
                                              controller: amountCtrl,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              decoration: const InputDecoration(labelText: 'Bedrag'),
                                            ),
                                            const SizedBox(height: 12),
                                            TextField(
                                              controller: descCtrl,
                                              decoration: const InputDecoration(labelText: 'Omschrijving'),
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(context).pop(),
                                            child: const Text('Sluiten'),
                                          ),
                                          FilledButton.icon(
                                            onPressed: () => Navigator.of(context).pop(),
                                            icon: const Icon(Icons.check_rounded),
                                            label: const Text('Opslaan (later)'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                                descCtrl.dispose();
                                amountCtrl.dispose();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                if (wide) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                    child: Row(
                      children: [
                        Expanded(flex: 5, child: leftPanel()),
                        const SizedBox(width: 16),
                        Expanded(flex: 6, child: rightPanel()),
                      ],
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    leftPanel(),
                    const SizedBox(height: 12),
                    SizedBox(height: 740, child: rightPanel()),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              k,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReconData {
  const _ReconData({
    required this.transaction,
    required this.isPositive,
    required this.invoices,
    required this.grootboek,
  });

  final Map<String, dynamic> transaction;
  final bool isPositive;
  final List<Map<String, dynamic>> invoices;
  final List<Map<String, dynamic>> grootboek;
}

class _InvoicesTab extends StatelessWidget {
  const _InvoicesTab({
    required this.invoices,
    required this.isPositive,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> invoices;
  final bool isPositive;
  final ValueChanged<Map<String, dynamic>> onSelect;

  static String _text(dynamic v) => (v ?? '').toString().trim();

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  NumberFormat _eur() => NumberFormat.currency(locale: 'nl_NL', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    if (invoices.isEmpty) {
      return Center(
        child: Text(
          'Geen openstaande facturen gevonden.',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.70)),
        ),
      );
    }

    return ListView.separated(
      itemCount: invoices.length,
      separatorBuilder: (_, i) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final inv = invoices[i];
        final id = _text(inv['id']);
        final nr = isPositive ? _text(inv['factuur_nummer']) : _text(inv['factuur_nummer_leverancier']);
        final naam = isPositive
            ? _text(inv['debiteur_naam'])
            : _text((inv['bedrijven'] as Map?)?['bedrijfsnaam']);
        final open = _asDouble(inv['openstaand_saldo']);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: id.isEmpty ? null : () => onSelect(inv),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.receipt_long_rounded, color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          naam.isEmpty ? 'Onbekend' : naam,
                          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nr.isEmpty ? '(geen nummer)' : nr,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _eur().format(open),
                    style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LedgerTab extends StatelessWidget {
  const _LedgerTab({required this.grootboek, required this.onSelect});

  final List<Map<String, dynamic>> grootboek;
  final ValueChanged<Map<String, dynamic>> onSelect;

  static String _text(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    return ListView.separated(
      itemCount: grootboek.length,
      separatorBuilder: (_, i) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final g = grootboek[i];
        final nr = _text(g['rekening_nummer']);
        final naam = _text(g['naam']);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => onSelect(g),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.account_balance_rounded, color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      [if (nr.isNotEmpty) nr, if (naam.isNotEmpty) naam].join(' • '),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: cs.onSurface.withValues(alpha: 0.55)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0A0912)
            : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
          ),
          const SizedBox(height: 8),
          Text(message),
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

