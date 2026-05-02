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

class ArticleManagementScreen extends StatefulWidget {
  const ArticleManagementScreen({super.key});

  @override
  State<ArticleManagementScreen> createState() => _ArticleManagementScreenState();
}

class _ArticleManagementScreenState extends State<ArticleManagementScreen> {
  Future<_ArticleManagementData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  void _refresh() => setState(() => _future = _fetch());

  Future<_ArticleManagementData> _fetch() async {
    final artikelenRes =
        await AppSupabase.client.from('artikelen').select().order('artikel_code', ascending: true);

    final btwRes =
        await AppSupabase.client.from('fiscale_btw_codes').select().order('omschrijving', ascending: true);

    final grootboekRes = await AppSupabase.client
        .from('grootboekrekeningen')
        .select()
        .eq('type', 'winst_en_verlies')
        .order('rekening_nummer', ascending: true);

    final artikelen = (artikelenRes as List).cast<Map<String, dynamic>>();
    final knownColumns = <String>{};
    if (artikelen.isNotEmpty) knownColumns.addAll(artikelen.first.keys);

    return _ArticleManagementData(
      artikelen: artikelen,
      btwCodes: (btwRes as List).cast<Map<String, dynamic>>(),
      omzetRekeningen: (grootboekRes as List).cast<Map<String, dynamic>>(),
      knownColumns: knownColumns,
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

  String _priceKey(Set<String> cols) {
    if (cols.contains('verkoopprijs_ex_btw')) return 'verkoopprijs_ex_btw';
    if (cols.contains('standaard_prijs_ex_btw')) return 'standaard_prijs_ex_btw';
    if (cols.contains('verkoopprijs')) return 'verkoopprijs';
    return 'standaard_prijs_ex_btw';
  }

  Future<void> _openEditor({
    required _ArticleManagementData data,
    Map<String, dynamic>? article,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ArticleEditorSheet(
        article: article,
        btwCodes: data.btwCodes,
        omzetRekeningen: data.omzetRekeningen,
        knownColumns: data.knownColumns,
        onSaved: _refresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canView = up.isGenerator || up.role == UserRole.administrator;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;
    final eur = NumberFormat.currency(locale: 'nl_NL', symbol: 'EUR ');

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Artikelbeheer',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(tooltip: 'Vernieuwen', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FutureBuilder<_ArticleManagementData>(
        future: _future,
        builder: (context, snapshot) {
          return FloatingActionButton(
            onPressed: (!canView || snapshot.data == null)
                ? null
                : () => _openEditor(data: snapshot.data!, article: null),
            child: const Icon(Icons.add_rounded),
          );
        },
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
                    'U heeft geen rechten om artikelen te beheren.',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            )
          : FutureBuilder<_ArticleManagementData>(
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
                      child: Text('Kan artikelen niet laden: ${snapshot.error}'),
                    ),
                  );
                }

                final data = snapshot.data ??
                    const _ArticleManagementData(
                      artikelen: <Map<String, dynamic>>[],
                      btwCodes: <Map<String, dynamic>>[],
                      omzetRekeningen: <Map<String, dynamic>>[],
                      knownColumns: <String>{},
                    );

                if (data.artikelen.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: softBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                      ),
                      child: Text(
                        'Geen artikelen gevonden.',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                    ),
                  );
                }

                final priceKey = _priceKey(data.knownColumns);

                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 96),
                  children: [
                    Text(
                      'Artikelbeheer',
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Beheer producten, diensten en tarieven',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.70),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListView.separated(
                      itemCount: data.artikelen.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      separatorBuilder: (_, i) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final a = data.artikelen[i];
                        final code = _text(a['artikel_code']);
                        final omschrijving = _text(
                          a['omschrijving_intern'] ?? a['naam'] ?? a['omschrijving'],
                        );
                        final eenheid = _text(a['eenheid']);
                        final verkoopprijs = _asDouble(a[priceKey]);
                        final actief = a.containsKey('is_actief') ? _asBool(a['is_actief']) : true;

                        return Opacity(
                          opacity: actief ? 1 : 0.48,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () => _openEditor(data: data, article: a),
                            child: Container(
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
                                    constraints: const BoxConstraints(minWidth: 68, minHeight: 54),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: cs.primary.withValues(alpha: 0.20)),
                                    ),
                                    child: Text(
                                      code.isEmpty ? '—' : code,
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
                                        Text(
                                          omschrijving.isEmpty ? '—' : omschrijving,
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: cs.onSurface.withValues(alpha: 0.06),
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
                                          ),
                                          child: Text(
                                            eenheid.isEmpty ? '—' : eenheid,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: cs.onSurface.withValues(alpha: 0.70),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    eur.format(verkoopprijs).replaceFirst('EUR', 'EUR'),
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _ArticleManagementData {
  const _ArticleManagementData({
    required this.artikelen,
    required this.btwCodes,
    required this.omzetRekeningen,
    required this.knownColumns,
  });

  final List<Map<String, dynamic>> artikelen;
  final List<Map<String, dynamic>> btwCodes;
  final List<Map<String, dynamic>> omzetRekeningen;
  final Set<String> knownColumns;
}

class _ArticleEditorSheet extends StatefulWidget {
  const _ArticleEditorSheet({
    required this.article,
    required this.btwCodes,
    required this.omzetRekeningen,
    required this.knownColumns,
    required this.onSaved,
  });

  final Map<String, dynamic>? article;
  final List<Map<String, dynamic>> btwCodes;
  final List<Map<String, dynamic>> omzetRekeningen;
  final Set<String> knownColumns;
  final VoidCallback onSaved;

  @override
  State<_ArticleEditorSheet> createState() => _ArticleEditorSheetState();
}

class _ArticleEditorSheetState extends State<_ArticleEditorSheet> {
  bool _saving = false;

  late final TextEditingController _codeCtrl;
  late final TextEditingController _internCtrl;
  late final TextEditingController _factuurCtrl;
  late final TextEditingController _kostprijsCtrl;
  late final TextEditingController _verkoopprijsCtrl;

  String _eenheid = 'stuk';
  bool _fractioneel = false;
  String? _btwCode;
  String? _omzetRekeningId;

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

  @override
  void initState() {
    super.initState();
    final a = widget.article;
    _codeCtrl = TextEditingController(text: _text(a?['artikel_code']));
    _internCtrl = TextEditingController(
      text: _text(a?['omschrijving_intern'] ?? a?['naam'] ?? a?['omschrijving']),
    );
    _factuurCtrl = TextEditingController(
      text: _text(a?['factuur_omschrijving'] ?? a?['omschrijving_factuur']),
    );
    _kostprijsCtrl = TextEditingController(
      text: _formatSeed(a?['kostprijs'] ?? a?['kostprijs_eur']),
    );
    _verkoopprijsCtrl = TextEditingController(
      text: _formatSeed(a?['verkoopprijs_ex_btw'] ?? a?['standaard_prijs_ex_btw'] ?? a?['verkoopprijs']),
    );
    _eenheid = _text(a?['eenheid']).isEmpty ? 'stuk' : _text(a?['eenheid']);
    _fractioneel = _asBool(
      a?['fractioneel'] ?? a?['mag_fractioneel'] ?? a?['allow_fractional'] ?? a?['verkoop_in_decimalen'],
    );
    _btwCode = _text(a?['verkoop_btw_code'] ?? a?['standaard_btw_code']).isEmpty
        ? null
        : _text(a?['verkoop_btw_code'] ?? a?['standaard_btw_code']);
    _omzetRekeningId = _text(a?['omzet_grootboekrekening_id'] ?? a?['omzet_rekening_id']).isEmpty
        ? null
        : _text(a?['omzet_grootboekrekening_id'] ?? a?['omzet_rekening_id']);
  }

  String _formatSeed(dynamic v) {
    final d = _asDouble(v);
    return d == 0 ? '' : d.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _internCtrl.dispose();
    _factuurCtrl.dispose();
    _kostprijsCtrl.dispose();
    _verkoopprijsCtrl.dispose();
    super.dispose();
  }

  String _pickPriceColumn() {
    if (widget.knownColumns.contains('verkoopprijs_ex_btw')) return 'verkoopprijs_ex_btw';
    if (widget.knownColumns.contains('standaard_prijs_ex_btw')) return 'standaard_prijs_ex_btw';
    if (widget.knownColumns.contains('verkoopprijs')) return 'verkoopprijs';
    return 'standaard_prijs_ex_btw';
  }

  Map<String, dynamic> _payloadForSchema() {
    final cols = widget.knownColumns;
    final payload = <String, dynamic>{};

    void setIfKnown(String key, dynamic value) {
      if (cols.isEmpty || cols.contains(key)) {
        payload[key] = value;
      }
    }

    final verkoopprijs = double.tryParse(_verkoopprijsCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final kostprijs = double.tryParse(_kostprijsCtrl.text.trim().replaceAll(',', '.')) ?? 0;

    setIfKnown('artikel_code', _codeCtrl.text.trim());
    setIfKnown('omschrijving_intern', _internCtrl.text.trim());
    setIfKnown('naam', _internCtrl.text.trim());
    setIfKnown('factuur_omschrijving', _factuurCtrl.text.trim());
    setIfKnown('omschrijving_factuur', _factuurCtrl.text.trim());
    setIfKnown('kostprijs', kostprijs);
    setIfKnown('kostprijs_eur', kostprijs);
    setIfKnown(_pickPriceColumn(), verkoopprijs);
    setIfKnown('eenheid', _eenheid);
    setIfKnown('fractioneel', _fractioneel);
    setIfKnown('mag_fractioneel', _fractioneel);
    setIfKnown('allow_fractional', _fractioneel);
    setIfKnown('verkoop_in_decimalen', _fractioneel);
    setIfKnown('verkoop_btw_code', _btwCode);
    setIfKnown('standaard_btw_code', _btwCode);
    setIfKnown('omzet_grootboekrekening_id', _omzetRekeningId);
    setIfKnown('omzet_rekening_id', _omzetRekeningId);

    return payload;
  }

  Future<void> _save() async {
    if (_saving) return;
    final rootContext = context;
    setState(() => _saving = true);
    try {
      final payload = _payloadForSchema();
      final id = _text(widget.article?['id']);

      if (id.isEmpty) {
        await AppSupabase.client.from('artikelen').insert(payload);
      } else {
        await AppSupabase.client.from('artikelen').update(payload).eq('id', id);
      }

      if (!mounted || !context.mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.92),
          content: Text(
            id.isEmpty ? 'Artikel toegevoegd.' : 'Artikel bijgewerkt.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent.withValues(alpha: 0.92),
          content: Text(
            'Kon artikel niet opslaan: ${e.message}',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon artikel niet opslaan: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    Widget field(
      TextEditingController ctrl,
      String label, {
      int maxLines = 1,
      TextInputType keyboard = TextInputType.text,
    }) {
      return TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: softBg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
        ),
        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
      );
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.article == null ? 'Nieuw Artikel' : 'Artikel Bewerken',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      field(_codeCtrl, 'Artikel Code'),
                      const SizedBox(height: 12),
                      field(_internCtrl, 'Interne Omschrijving'),
                      const SizedBox(height: 12),
                      field(_factuurCtrl, 'Factuur Omschrijving', maxLines: 2),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: field(
                              _kostprijsCtrl,
                              'Kostprijs (€)',
                              keyboard: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: field(
                              _verkoopprijsCtrl,
                              'Verkoopprijs ex. Btw (€)',
                              keyboard: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Eenheid',
                          filled: true,
                          fillColor: softBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _eenheid,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(value: 'uur', child: Text('uur')),
                              DropdownMenuItem(value: 'stuk', child: Text('stuk')),
                              DropdownMenuItem(value: 'm2', child: Text('m2')),
                              DropdownMenuItem(value: 'maand', child: Text('maand')),
                              DropdownMenuItem(value: 'liter', child: Text('liter')),
                              DropdownMenuItem(value: 'km', child: Text('km')),
                            ],
                            onChanged: _saving ? null : (v) => setState(() => _eenheid = v ?? 'stuk'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: softBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sta halve eenheden toe',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Mag dit artikel in decimalen (bijv. 1,5 uur) gefactureerd worden?',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface.withValues(alpha: 0.65),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            CupertinoSwitch(
                              value: _fractioneel,
                              onChanged: _saving ? null : (v) => setState(() => _fractioneel = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _btwCode,
                        items: widget.btwCodes.map((r) {
                          final code = _text(r['code']);
                          final oms = _text(r['omschrijving']);
                          return DropdownMenuItem<String>(
                            value: code,
                            child: Text(oms.isEmpty ? code : oms),
                          );
                        }).toList(),
                        onChanged: _saving ? null : (v) => setState(() => _btwCode = v),
                        decoration: InputDecoration(
                          labelText: 'Verkoop Btw-Code',
                          filled: true,
                          fillColor: softBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _omzetRekeningId,
                        items: widget.omzetRekeningen.map((r) {
                          final id = _text(r['id']);
                          final nr = _text(r['rekening_nummer']);
                          final naam = _text(r['naam']);
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text('$nr - $naam'),
                          );
                        }).toList(),
                        onChanged: _saving ? null : (v) => setState(() => _omzetRekeningId = v),
                        decoration: InputDecoration(
                          labelText: 'Omzet Grootboekrekening',
                          filled: true,
                          fillColor: softBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _saving ? 'Bezig…' : 'Opslaan',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

