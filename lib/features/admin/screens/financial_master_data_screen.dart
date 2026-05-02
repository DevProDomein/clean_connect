import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/user_role.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import '../../../shared/widgets/enterprise_tooltip.dart';

class FinancialMasterDataScreen extends StatefulWidget {
  const FinancialMasterDataScreen({super.key});

  @override
  State<FinancialMasterDataScreen> createState() => _FinancialMasterDataScreenState();
}

class _FinancialMasterDataScreenState extends State<FinancialMasterDataScreen> {
  Future<_FinancialMasterData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  void _refresh() => setState(() => _future = _fetch());

  Future<_FinancialMasterData> _fetch() async {
    final grootboekRes = await AppSupabase.client
        .from('grootboekrekeningen')
        .select()
        .order('rekening_nummer', ascending: true);

    final btwRes = await AppSupabase.client
        .from('fiscale_btw_codes')
        .select()
        .order('code', ascending: true);

    return _FinancialMasterData(
      grootboek: (grootboekRes as List).cast<Map<String, dynamic>>(),
      btwCodes: (btwRes as List).cast<Map<String, dynamic>>(),
    );
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  bool _isBalans(Map<String, dynamic> r) {
    final t = _text(r['type']).toLowerCase();
    if (t.contains('balans')) return true;
    if (t == 'winst_en_verlies' || t.contains('verlies')) return false;
    // Fallback heuristic: lower numbers often balance accounts.
    final nr = int.tryParse(_text(r['rekening_nummer']).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    return nr > 0 && nr < 4000;
  }

  Future<void> _openAddLedgerSheet() async {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    final nrCtrl = TextEditingController();
    final naamCtrl = TextEditingController();
    final categorieCtrl = TextEditingController();
    String type = 'balans';
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> save() async {
              if (saving) return;
              final rootContext = this.context;
              final nrRaw = nrCtrl.text.trim();
              final nr = nrRaw.replaceAll(RegExp(r'[^0-9]'), '');
              if (nr.isEmpty || nr != nrRaw) {
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
                    content: Text(
                      'Rekeningnummer mag alleen cijfers bevatten.',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                    ),
                  ),
                );
                return;
              }

              setLocal(() => saving = true);
              try {
                await AppSupabase.client.from('grootboekrekeningen').insert({
                  'rekening_nummer': nr,
                  'naam': naamCtrl.text.trim(),
                  'type': type,
                  'categorie': categorieCtrl.text.trim(),
                });

                if (!context.mounted || !mounted) return;
                Navigator.of(context).pop(); // bottom-sheet context
                _refresh();
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green.withValues(alpha: 0.92),
                    content: Text(
                      'Grootboekrekening toegevoegd.',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                    ),
                  ),
                );
              } on PostgrestException catch (e) {
                if (!mounted) return;
                final msg = e.message.toLowerCase();
                final isUnique = msg.contains('duplicate') || msg.contains('unique') || msg.contains('already exists');
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    backgroundColor: (isUnique ? Colors.redAccent : Colors.deepOrange).withValues(alpha: 0.92),
                    content: Text(
                      isUnique
                          ? 'Rekeningnummer bestaat al.'
                          : 'Kon grootboekrekening niet toevoegen: ${e.message}',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                    ),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
                    content: Text('Kon grootboekrekening niet toevoegen: $e'),
                  ),
                );
              } finally {
                if (mounted) setLocal(() => saving = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 40,
                      offset: const Offset(0, -12),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Grootboekrekening toevoegen',
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: saving ? null : () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nrCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Rekeningnummer',
                            filled: true,
                            fillColor: softBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: naamCtrl,
                          decoration: InputDecoration(
                            labelText: 'Naam',
                            filled: true,
                            fillColor: softBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Type',
                            filled: true,
                            fillColor: softBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: type,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(value: 'balans', child: Text('Balans')),
                                DropdownMenuItem(value: 'winst_en_verlies', child: Text('Winst & Verlies')),
                              ],
                              onChanged: saving ? null : (v) => setLocal(() => type = v ?? 'balans'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: categorieCtrl,
                          decoration: InputDecoration(
                            labelText: 'Categorie',
                            hintText: 'Omzet, Kosten, Activa…',
                            filled: true,
                            fillColor: softBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: saving ? null : save,
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                                : const Icon(Icons.add_rounded),
                            label: Text(
                              saving ? 'Bezig…' : 'Opslaan',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAddBtwSheet() async {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    final codeCtrl = TextEditingController();
    final omsCtrl = TextEditingController();
    final pctCtrl = TextEditingController(text: '0.00');
    bool isVerlegd = false;
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> save() async {
              if (saving) return;
              final rootContext = this.context;
              setLocal(() => saving = true);
              try {
                final pct = double.tryParse(pctCtrl.text.trim().replaceAll(',', '.')) ?? 0;
                await AppSupabase.client.from('fiscale_btw_codes').insert({
                  'code': codeCtrl.text.trim(),
                  'omschrijving': omsCtrl.text.trim(),
                  'percentage': pct,
                  'is_verlegd': isVerlegd,
                  'is_systeem_code': false,
                });

                if (!context.mounted || !mounted) return;
                Navigator.of(context).pop(); // bottom-sheet context
                _refresh();
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green.withValues(alpha: 0.92),
                    content: Text(
                      'BTW-code toegevoegd.',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                    ),
                  ),
                );
              } on PostgrestException catch (e) {
                if (!mounted) return;
                final msg = e.message.toLowerCase();
                final isUnique = msg.contains('duplicate') || msg.contains('unique') || msg.contains('already exists');
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    backgroundColor: (isUnique ? Colors.redAccent : Colors.deepOrange).withValues(alpha: 0.92),
                    content: Text(
                      isUnique ? 'BTW-code bestaat al.' : 'Kon BTW-code niet toevoegen: ${e.message}',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                    ),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
                    content: Text('Kon BTW-code niet toevoegen: $e'),
                  ),
                );
              } finally {
                if (mounted) setLocal(() => saving = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 40,
                      offset: const Offset(0, -12),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'BTW-code toevoegen',
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: saving ? null : () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: codeCtrl,
                          decoration: InputDecoration(
                            labelText: 'Code',
                            hintText: 'DE_HOOG',
                            filled: true,
                            fillColor: softBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: omsCtrl,
                          decoration: InputDecoration(
                            labelText: 'Omschrijving',
                            filled: true,
                            fillColor: softBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: pctCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Percentage',
                            hintText: '21.00',
                            filled: true,
                            fillColor: softBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: softBg,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Btw verlegd',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                                ),
                              ),
                              CupertinoSwitch(
                                value: isVerlegd,
                                onChanged: saving ? null : (v) => setLocal(() => isVerlegd = v),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: saving ? null : save,
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                                : const Icon(Icons.add_rounded),
                            label: Text(
                              saving ? 'Bezig…' : 'Opslaan',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canView = up.hasPermission('finance') ||
        up.isGenerator ||
        up.role == UserRole.administrator ||
        up.role == UserRole.generator;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    final pillBg = cs.onSurface.withValues(alpha: isDark ? 0.10 : 0.06);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(
            'Financiële Stamgegevens',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
          actions: [
            IconButton(tooltip: 'Vernieuwen', onPressed: _refresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: !canView
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: softBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                    ),
                    child: Text(
                      'U heeft geen rechten om financiële stamgegevens te beheren.',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              )
            : FutureBuilder<_FinancialMasterData>(
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
                        child: Text('Kan stamgegevens niet laden: ${snapshot.error}'),
                      ),
                    );
                  }

                  final data = snapshot.data ??
                      const _FinancialMasterData(grootboek: <Map<String, dynamic>>[], btwCodes: <Map<String, dynamic>>[]);

                  final balans = data.grootboek.where(_isBalans).toList(growable: false);
                  final wv = data.grootboek.where((r) => !_isBalans(r)).toList(growable: false);

                  return Stack(
                    children: [
                      ListView(
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                        children: [
                          Text(
                            'Financiële Stamgegevens',
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Beheer uw grootboekschema (RGS) en BTW-codes. Systeemitems zijn vergrendeld.',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withValues(alpha: 0.70),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: pillBg,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
                            ),
                            child: TabBar(
                              indicator: BoxDecoration(
                                color: cs.primary.withValues(alpha: isDark ? 0.22 : 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
                              ),
                              dividerColor: Colors.transparent,
                              labelColor: cs.onSurface,
                              unselectedLabelColor: cs.onSurface.withValues(alpha: 0.65),
                              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w900),
                              unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w800),
                              tabs: const [
                                Tab(text: 'Grootboekschema (RGS)'),
                                Tab(text: 'Btw-Tarieven'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: MediaQuery.of(context).size.height - 260,
                            child: TabBarView(
                              children: [
                                _LedgerTab(
                                  balans: balans,
                                  winstEnVerlies: wv,
                                  tileBg: tileBg,
                                  softBg: softBg,
                                ),
                                _BtwTab(
                                  btwCodes: data.btwCodes,
                                  tileBg: tileBg,
                                  softBg: softBg,
                                  asBool: _asBool,
                                  asDouble: _asDouble,
                                  text: _text,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        right: 24,
                        bottom: 24,
                        child: Builder(
                          builder: (context) {
                            final tabIdx = DefaultTabController.of(context).index;
                            return FloatingActionButton(
                              onPressed: tabIdx == 0 ? _openAddLedgerSheet : _openAddBtwSheet,
                              child: const Icon(Icons.add_rounded),
                            );
                          },
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

class _FinancialMasterData {
  const _FinancialMasterData({
    required this.grootboek,
    required this.btwCodes,
  });

  final List<Map<String, dynamic>> grootboek;
  final List<Map<String, dynamic>> btwCodes;
}

class _LedgerTab extends StatelessWidget {
  const _LedgerTab({
    required this.balans,
    required this.winstEnVerlies,
    required this.tileBg,
    required this.softBg,
  });

  final List<Map<String, dynamic>> balans;
  final List<Map<String, dynamic>> winstEnVerlies;
  final Color tileBg;
  final Color softBg;

  String _text(dynamic v) => (v ?? '').toString().trim();
  bool _asBool(dynamic v) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget section(String title, List<Map<String, dynamic>> rows) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
                color: cs.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
          if (rows.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: softBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              ),
              child: Text(
                'Geen rekeningen gevonden.',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            )
          else
            ListView.separated(
              itemCount: rows.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (_, i) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final r = rows[i];
                final nr = _text(r['rekening_nummer']);
                final naam = _text(r['naam']);
                final cat = _text(r['categorie']);
                final isSys = _asBool(r['is_systeem_rekening']);

                return Container(
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
                      Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: cs.primary.withValues(alpha: 0.20)),
                        ),
                        child: Text(
                          nr.isEmpty ? '—' : nr,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    naam.isEmpty ? '—' : naam,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                if (isSys) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.lock_outline_rounded, size: 18, color: Colors.grey),
                                  const SizedBox(width: 6),
                                  const EnterpriseTooltip(
                                    message: 'Systeemrekening: Kan niet verwijderd worden',
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              cat.isEmpty ? '—' : cat,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface.withValues(alpha: 0.60),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          section('Balans Rekeningen', balans),
          const SizedBox(height: 18),
          section('Winst & Verlies', winstEnVerlies),
          const SizedBox(height: 90),
        ],
      ),
    );
  }
}

class _BtwTab extends StatelessWidget {
  const _BtwTab({
    required this.btwCodes,
    required this.tileBg,
    required this.softBg,
    required this.asBool,
    required this.asDouble,
    required this.text,
  });

  final List<Map<String, dynamic>> btwCodes;
  final Color tileBg;
  final Color softBg;
  final bool Function(dynamic) asBool;
  final double Function(dynamic) asDouble;
  final String Function(dynamic) text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pctFmt = NumberFormat('0.00', 'nl_NL');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const navy = Color(0xFF0F172A);

    if (btwCodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: softBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
          ),
          child: Text(
            'Geen BTW-codes gevonden.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 12, bottom: 90),
      itemCount: btwCodes.length,
      separatorBuilder: (_, i) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final r = btwCodes[i];
        final oms = text(r['omschrijving']);
        final code = text(r['code']);
        final pct = asDouble(r['percentage']);
        final verlegd = asBool(r['is_verlegd']);
        final isSys = asBool(r['is_systeem_code']);

        return Container(
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
                    Text(
                      oms.isEmpty ? '—' : oms,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          code.isEmpty ? '—' : code,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withValues(alpha: 0.60),
                          ),
                        ),
                        if (isSys) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _pill(
                '${pctFmt.format(pct)} %',
                bg: cs.primary.withValues(alpha: isDark ? 0.25 : 0.14),
                fg: Colors.white,
                border: cs.primary.withValues(alpha: 0.25),
              ),
              if (verlegd) ...[
                const SizedBox(width: 10),
                _pill(
                  'Btw Verlegd',
                  bg: navy.withValues(alpha: isDark ? 0.70 : 0.92),
                  fg: Colors.white,
                  border: navy.withValues(alpha: 0.40),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _pill(
    String text, {
    required Color bg,
    required Color fg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w900,
          color: fg,
        ),
      ),
    );
  }
}

