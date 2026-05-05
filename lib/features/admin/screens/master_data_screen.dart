import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase_client.dart';
import '../../../providers/user_provider.dart';

class MasterDataScreen extends StatefulWidget {
  const MasterDataScreen({super.key});

  @override
  State<MasterDataScreen> createState() => _MasterDataScreenState();
}

class _MasterDataScreenState extends State<MasterDataScreen> {
  Future<_MasterData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_MasterData> _fetch() async {
    final grootboekRes = await AppSupabase.client
        .from('grootboekrekeningen')
        .select()
        .order('rekening_nummer', ascending: true);

    final artikelenRes = await AppSupabase.client
        .from('artikelen')
        .select()
        .order('artikel_code', ascending: true);

    return _MasterData(
      grootboek: (grootboekRes as List).cast<Map<String, dynamic>>(),
      artikelen: (artikelenRes as List).cast<Map<String, dynamic>>(),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _fetch();
    });
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  Future<void> _addLedger() async {
    final nr = TextEditingController();
    final naam = TextEditingController();
    String type = 'balans';

    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SelectionArea(
          child: StatefulBuilder(
            builder: (context, setLocal) {
              void setSaving(bool v) => setLocal(() => saving = v);

              Future<void> save() async {
                if (saving) return;
                setSaving(true);
                try {
                  await AppSupabase.client.from('grootboekrekeningen').insert({
                    'rekening_nummer': nr.text.trim(),
                    'naam': naam.text.trim(),
                    'type': type,
                  });
                  if (context.mounted) Navigator.of(context).pop();
                  await _refresh();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
                      content: Text('Kon grootboekrekening niet toevoegen: $e'),
                    ),
                  );
                } finally {
                  if (context.mounted) setSaving(false);
                }
              }

              return AlertDialog(
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                title: Text(
                  'Grootboekrekening toevoegen',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                content: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nr,
                        decoration:
                            const InputDecoration(labelText: 'Rekeningnummer'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: naam,
                        decoration: const InputDecoration(labelText: 'Naam'),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Type'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: type,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(
                                value: 'balans',
                                child: Text('Balans'),
                              ),
                              DropdownMenuItem(
                                value: 'winst_en_verlies',
                                child: Text('Winst & Verlies'),
                              ),
                            ],
                            onChanged: saving
                                ? null
                                : (v) => setLocal(() => type = v ?? 'balans'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Annuleren'),
                  ),
                  FilledButton.icon(
                    onPressed: saving ? null : save,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w900),
                    ),
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.add),
                    label: Text(saving ? 'Bezig…' : 'Toevoegen'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _addArticle(List<Map<String, dynamic>> grootboek) async {
    final code = TextEditingController();
    final naam = TextEditingController();
    final omschrijving = TextEditingController();
    final prijs = TextEditingController(text: '0');
    String btw = 'hoog_21';
    String? omzetRekeningId;

    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SelectionArea(
          child: StatefulBuilder(
            builder: (context, setLocal) {
              void setSaving(bool v) => setLocal(() => saving = v);

            Future<void> save() async {
              if (saving) return;
              setSaving(true);
              try {
                final prijsVal =
                    double.tryParse(prijs.text.replaceAll(',', '.')) ?? 0;

                await AppSupabase.client.from('artikelen').insert({
                  'artikel_code': code.text.trim(),
                  'naam': naam.text.trim(),
                  'omschrijving': omschrijving.text.trim(),
                  'standaard_prijs_ex_btw': prijsVal,
                  'standaard_btw_code': btw,
                  'omzet_rekening_id': omzetRekeningId,
                });

                if (context.mounted) Navigator.of(context).pop();
                await _refresh();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
                    content: Text('Kon artikel niet toevoegen: $e'),
                  ),
                );
              } finally {
                if (context.mounted) setSaving(false);
              }
            }

              return AlertDialog(
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                'Artikel toevoegen',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: code,
                      decoration: const InputDecoration(labelText: 'Artikelcode'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: naam,
                      decoration: const InputDecoration(labelText: 'Naam'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: omschrijving,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Omschrijving'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: prijs,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Standaard prijs (ex. BTW)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Standaard BTW code'),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: btw,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(value: 'hoog_21', child: Text('Hoog (21%)')),
                                  DropdownMenuItem(value: 'laag_9', child: Text('Laag (9%)')),
                                  DropdownMenuItem(value: 'nul_0', child: Text('Nul (0%)')),
                                  DropdownMenuItem(value: 'verlegd', child: Text('Verlegd')),
                                ],
                                onChanged: saving
                                    ? null
                                    : (v) => setLocal(() => btw = v ?? 'hoog_21'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Omzet rekening'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: (omzetRekeningId != null &&
                                  grootboek.any((g) => _text(g['id']) == omzetRekeningId))
                              ? omzetRekeningId
                              : null,
                          isExpanded: true,
                          hint: const Text('Selecteer grootboekrekening'),
                          items: grootboek
                              .map((g) {
                                final id = _text(g['id']);
                                if (id.isEmpty) return null;
                                final nrTxt = _text(g['rekening_nummer']);
                                final nm = _text(g['naam']);
                                final label = [nrTxt, nm].where((e) => e.isNotEmpty).join(' — ');
                                return DropdownMenuItem(
                                  value: id,
                                  child: Text(label.isEmpty ? id : label),
                                );
                              })
                              .whereType<DropdownMenuItem<String>>()
                              .toList(),
                          onChanged: saving ? null : (v) => setLocal(() => omzetRekeningId = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Annuleren'),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    textStyle: GoogleFonts.inter(fontWeight: FontWeight.w900),
                  ),
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.add),
                  label: Text(saving ? 'Bezig…' : 'Toevoegen'),
                ),
              ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? cs.surface.withValues(alpha: 0.92) : Colors.white;
    final up = context.watch<UserProvider>();
    final canOpen = up.isGenerator ||
        up.role?.name == 'administrator' ||
        up.hasPermission('manage_app_settings');

    if (!canOpen) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Financiële Stamgegevens',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
        ),
        body: SelectionArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark
                    ? cs.surface.withValues(alpha: 0.70)
                    : const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              ),
              child: Text(
                'U heeft geen rechten om financiële stamgegevens te beheren.',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.80),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Financiële Stamgegevens',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
          actions: [
            IconButton(
              tooltip: 'Vernieuwen',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: Builder(
          builder: (context) {
            final tab = DefaultTabController.of(context);
            return FloatingActionButton.extended(
              onPressed: () async {
                final data = await _future;
                if (!mounted || data == null) return;
                if (tab.index == 0) {
                  await _addLedger();
                } else {
                  await _addArticle(data.grootboek);
                }
              },
              icon: const Icon(Icons.add),
              label: Text(
                'Nieuw',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
              ),
            );
          },
        ),
        body: SelectionArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: TabBar(
                    splashBorderRadius: BorderRadius.circular(50),
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: cs.primary,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey.shade600,
                    dividerColor: Colors.transparent,
                    labelStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                    tabs: const [
                      Tab(text: 'Grootboekrekeningen'),
                      Tab(text: 'Artikelen'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<_MasterData>(
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
                            color: isDark
                                ? cs.surface.withValues(alpha: 0.70)
                                : const Color(0xFFF5F5F7),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: cs.onSurface.withValues(alpha: 0.06),
                            ),
                          ),
                          child: Text(
                            'Kan stamgegevens niet laden: ${snapshot.error}',
                          ),
                        ),
                      );
                    }

                  final data = snapshot.data!;
                  final grootboek = data.grootboek;
                  final artikelen = data.artikelen;

                  Widget ledgerList() {
                    if (grootboek.isEmpty) {
                      return const Center(child: Text('Geen grootboekrekeningen gevonden.'));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
                      itemCount: grootboek.length,
                      separatorBuilder: (_, sep) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final g = grootboek[i];
                        final nr = _text(g['rekening_nummer']);
                        final nm = _text(g['naam']);
                        final tp = _text(g['type']);
                        return Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: cardBg,
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
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
                                ),
                                child: Icon(Icons.account_tree, color: cs.primary),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      [nr, nm].where((e) => e.isNotEmpty).join(' — '),
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      tp.isEmpty ? '—' : tp,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface.withValues(alpha: 0.70),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }

                  Widget articleList() {
                    if (artikelen.isEmpty) {
                      return const Center(child: Text('Geen artikelen gevonden.'));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
                      itemCount: artikelen.length,
                      separatorBuilder: (_, sep) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final a = artikelen[i];
                        final code = _text(a['artikel_code']);
                        final nm = _text(a['naam']);
                        final prijs = _asDouble(a['standaard_prijs_ex_btw']);
                        final btw = _text(a['standaard_btw_code']);
                        return Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: cardBg,
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
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
                                ),
                                child: Icon(Icons.inventory_2_outlined, color: cs.primary),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      code.isEmpty ? '(zonder code)' : code,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      nm.isEmpty ? '—' : nm,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface.withValues(alpha: 0.70),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '€ ${prijs.toStringAsFixed(2).replaceAll('.', ',')}',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Text(
                                      btw.isEmpty ? 'BTW' : 'BTW $btw',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }

                    return TabBarView(
                      children: [
                        ledgerList(),
                        articleList(),
                      ],
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

class _MasterData {
  const _MasterData({
    required this.grootboek,
    required this.artikelen,
  });

  final List<Map<String, dynamic>> grootboek;
  final List<Map<String, dynamic>> artikelen;
}

