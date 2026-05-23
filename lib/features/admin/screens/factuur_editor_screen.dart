import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';

class FactuurEditorScreen extends StatefulWidget {
  const FactuurEditorScreen({super.key, this.invoiceId});

  final String? invoiceId;

  @override
  State<FactuurEditorScreen> createState() => _FactuurEditorScreenState();
}

class _FactuurEditorScreenState extends State<FactuurEditorScreen> {
  static const _klantSelectCols =
      'id, bedrijfsnaam, adres_straat_huisnr, adres_postcode, adres_stad, kvk_nummer, btw_nummer, '
      'betalingstermijn_dagen, standaard_betalingstermijn_dagen';

  // Header (De Kaft)
  Map<String, dynamic>? _selectedKlant;
  String? geselecteerdeKlantId;
  String? geselecteerdeKlantNaam;
  final straatController = TextEditingController();
  final postcodeController = TextEditingController();
  final stadController = TextEditingController();
  final kvkController = TextEditingController();
  final btwController = TextEditingController();
  int betalingstermijnDagen = 14;

  DateTime _factuurDatum = DateTime.now();
  DateTime _vervalDatum = DateTime.now().add(const Duration(days: 14));

  String? _factuurId;
  int? _orderNummer;
  String? _factuurNummer;

  bool _loading = true;
  bool _saving = false;
  bool _deleteConceptBusy = false;
  bool _hasUnsavedChanges = false;
  String _factuurStatus = 'concept';

  final _omschrijvingCtrl = TextEditingController();

  bool _toonAantallen = true;
  bool _toonPrijzen = true;

  // Lines
  final List<Map<String, dynamic>> _lines = [];
  final Map<String, _LineCtrls> _lineCtrls = {};
  List<String> gekoppeldeOpdrachtIds = [];

  String? _extraWerkArtikelId;
  String _extraWerkArtikelLabel = 'Extra werk / Incidentele taak';

  // VAT lookups
  List<Map<String, dynamic>> _btwCodes = const [];
  final Map<String, double> _btwPctByCode = {};
  final Map<String, bool> _btwInclByCode = {};

  // Totals
  double _subtotaal = 0;
  double _btwTotaal = 0;
  double _totaalIncl = 0;

  @override
  void initState() {
    super.initState();
    _factuurId = widget.invoiceId;
    _load();
  }

  @override
  void dispose() {
    straatController.dispose();
    postcodeController.dispose();
    stadController.dispose();
    kvkController.dispose();
    btwController.dispose();
    _omschrijvingCtrl.dispose();
    for (final c in _lineCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------- helpers ----------------
  String _text(dynamic v) => (v ?? '').toString().trim();
  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = (v ?? '').toString().replaceAll(',', '.').trim();
    return double.tryParse(s) ?? 0.0;
  }

  String _newLineId() => 'line_${DateTime.now().microsecondsSinceEpoch}_${_lines.length}';

  void _markDirty() {
    if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
  }

  double _btwPctFor(String code) => _btwPctByCode[code] ?? 0.0;
  bool _btwIsInclusive(String code) => _btwInclByCode[code] ?? false;

  String _bedrijfVeld(Map<String, dynamic> k, List<String> keys) {
    for (final key in keys) {
      final s = _text(k[key]);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _straatFromKlant(Map<String, dynamic> k) {
    final combined = _bedrijfVeld(k, ['adres_straat_huisnr']);
    if (combined.isNotEmpty) return combined;
    final straat = _bedrijfVeld(k, ['straat']);
    final huis = _bedrijfVeld(k, ['huisnummer']);
    return [straat, huis].where((s) => s.isNotEmpty).join(' ');
  }

  double _artikelPrijs(Map<String, dynamic> a) {
    for (final key in ['verkoopprijs_ex_btw', 'standaard_prijs_ex_btw', 'stukprijs_ex_btw', 'verkoopprijs']) {
      if (a.containsKey(key)) return _asDouble(a[key]);
    }
    return 0;
  }

  String _artikelGroepLabel(Map<String, dynamic> a) {
    return _bedrijfVeld(a, ['artikel_groep', 'groep', 'categorie', 'branche']);
  }

  /// Belastingcode voor regelweergave: 2 = 21%, 1 = 9%, 0 = 0%.
  String _krijgBtwCode(dynamic percentage) {
    final perc = double.tryParse(percentage?.toString() ?? '');
    if (perc == 21.0) return '2';
    if (perc == 9.0) return '1';
    if (perc == 0.0) return '0';
    return percentage?.toString() ?? '2';
  }

  String _btwLabelForLine(Map<String, dynamic> l) {
    final pct = _asDouble(l['btw_percentage']);
    final code = _text(l['btw_code']).toUpperCase();
    if (code.contains('VRIJ') || l['btw_vrijgesteld'] == true) return 'Vrijgesteld van BTW';
    if (pct == 21) return '21% (Hoog tarief)';
    if (pct == 9) return '9% (Laag tarief)';
    if (pct == 0 && (code.contains('VERLEG') || l['btw_verlegd'] == true)) return '0% (Verlegd)';
    if (pct == 0) return '0% (Verlegd)';
    if (pct > 0) return '${pct.toStringAsFixed(0)}%';
    return 'BTW kiezen';
  }

  String _resolveBtwCode({required double pct, bool vrijgesteld = false, bool verlegd = false}) {
    if (vrijgesteld) {
      for (final b in _btwCodes) {
        final c = _text(b['code']).toUpperCase();
        if (c.contains('VRIJ')) return _text(b['code']);
      }
      return _btwCodes.isNotEmpty ? _text(_btwCodes.first['code']) : 'VRIJ';
    }
    if (verlegd || pct == 0) {
      for (final b in _btwCodes) {
        final c = _text(b['code']).toUpperCase();
        if (c.contains('VERLEG') || _asDouble(b['percentage']) == 0) return _text(b['code']);
      }
    }
    for (final b in _btwCodes) {
      if ((_asDouble(b['percentage']) - pct).abs() < 0.01) return _text(b['code']);
    }
    return _btwCodes.isNotEmpty ? _text(_btwCodes.first['code']) : '';
  }

  void _applyBtwPresetToLine(Map<String, dynamic> l, {required double pct, bool vrijgesteld = false, bool verlegd = false}) {
    l.remove('btw_vrijgesteld');
    l.remove('btw_verlegd');
    if (vrijgesteld) {
      l['btw_vrijgesteld'] = true;
      l['btw_percentage'] = 0.0;
    } else if (verlegd) {
      l['btw_verlegd'] = true;
      l['btw_percentage'] = 0.0;
    } else {
      l['btw_percentage'] = pct;
    }
    l['btw_code'] = _resolveBtwCode(pct: pct, vrijgesteld: vrijgesteld, verlegd: verlegd);
  }

  InputDecoration _readOnlyDeco(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  ({double ex, double btw, double incl}) _totalsFromLines() {
    double totaalExBtw = 0.0;
    double totaalBtwBedrag = 0.0;
    for (final l in _lines) {
      final qty = _asDouble(l['aantal']);
      final ex = _asDouble(l['stukprijs_ex_btw']);
      final regelTotaalEx = qty * ex;
      final regelBtwPercentage = _asDouble(l['btw_percentage']);
      final regelBtwBedrag = regelTotaalEx * (regelBtwPercentage / 100.0);
      totaalExBtw += regelTotaalEx;
      totaalBtwBedrag += regelBtwBedrag;
    }
    return (ex: totaalExBtw, btw: totaalBtwBedrag, incl: totaalExBtw + totaalBtwBedrag);
  }

  void _calculateTotals() {
    final t = _totalsFromLines();
    setState(() {
      _subtotaal = t.ex;
      _btwTotaal = t.btw;
      _totaalIncl = t.incl;
    });
  }

  Future<void> _handleBackButton() async {
    if (!_hasUnsavedChanges) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final bool? shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => SelectionArea(
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Niet opgeslagen wijzigingen',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text('Alles gaat verloren. Doorgaan?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Blijven')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Verlaten', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (shouldLeave == true && mounted) Navigator.of(context).pop();
  }

  // ---------------- load ----------------
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final btwRes =
          await AppSupabase.client.from('fiscale_btw_codes').select('code, percentage, rekent_inclusief');
      final list = (btwRes as List).cast<Map<String, dynamic>>();
      _btwCodes = list;
      _btwPctByCode.clear();
      _btwInclByCode.clear();
      for (final r in list) {
        final code = _text(r['code']);
        if (code.isEmpty) continue;
        _btwPctByCode[code] = _asDouble(r['percentage']);
        _btwInclByCode[code] = (r['rekent_inclusief'] as bool?) ?? false;
      }

      try {
        var art = await AppSupabase.client
            .from('artikelen')
            .select('id, artikel_code, naam')
            .eq('artikel_code', 'SCH-001')
            .maybeSingle();
        art ??= await AppSupabase.client
            .from('artikelen')
            .select('id, artikel_code, naam')
            .limit(1)
            .maybeSingle();
        if (art != null) {
          final m = Map<String, dynamic>.from(art as Map);
          _extraWerkArtikelId = _text(m['id']);
          final code = _text(m['artikel_code']);
          final naam = _text(m['naam']);
          final label = [code, naam].where((s) => s.isNotEmpty).join(' — ');
          if (label.isNotEmpty) _extraWerkArtikelLabel = label;
        }
      } catch (_) {
        _extraWerkArtikelId = null;
      }

      if (_factuurId != null) {
        final inv = await AppSupabase.client
            .from('facturen')
            .select(
              'id, order_nummer, factuur_nummer, factuur_datum, verval_datum, omschrijving, '
              'bedrijf_id, status, layout_toon_aantallen, layout_toon_prijzen',
            )
            .eq('id', _factuurId!)
            .maybeSingle();
        if (inv != null) {
          _factuurStatus = _text(inv['status']).toLowerCase();
          _orderNummer = inv['order_nummer'] is num
              ? (inv['order_nummer'] as num).toInt()
              : int.tryParse(_text(inv['order_nummer']));
          _factuurNummer = _text(inv['factuur_nummer']).isEmpty ? null : _text(inv['factuur_nummer']);
          final fd = DateTime.tryParse(_text(inv['factuur_datum']))?.toLocal();
          final vd = DateTime.tryParse(_text(inv['verval_datum']))?.toLocal();
          if (fd != null) _factuurDatum = fd;
          if (vd != null) _vervalDatum = vd;
          _omschrijvingCtrl.text = _text(inv['omschrijving']);
          _toonAantallen = (inv['layout_toon_aantallen'] as bool?) ?? true;
          _toonPrijzen = (inv['layout_toon_prijzen'] as bool?) ?? true;

          final bedrijfId = _text(inv['bedrijf_id']);
          if (bedrijfId.isNotEmpty) {
            final klant = await AppSupabase.client
                .from('bedrijven')
                .select(_klantSelectCols)
                .eq('id', bedrijfId)
                .maybeSingle();
            if (klant != null) {
              _applyKlant(klant, markDirty: false);
            }
          }

          final regels = await AppSupabase.client
              .from('factuur_regels')
              .select(
                'id, artikel_id, omschrijving, aantal, eenheid, stukprijs_ex_btw, '
                'btw_code, btw_percentage, volgorde, gekoppelde_opdrachten_info',
              )
              .eq('factuur_id', _factuurId!)
              .order('volgorde', ascending: true);
          _lines
            ..clear()
            ..addAll((regels as List).cast<Map<String, dynamic>>().map((l) {
              l['local_id'] = _newLineId();
              l['stukprijs_inc_btw'] = 0.0;
              return l;
            }));
          for (final l in _lines) {
            _ensureLineCtrls(l);
          }
          _calculateTotals();
          _hasUnsavedChanges = false;
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _pickTermijn(Map<String, dynamic> klant) {
    final termijn = klant['standaard_betalingstermijn_dagen'] ??
        klant['betalingstermijn_dagen'] ??
        klant['betaaltermijn_dagen'] ??
        14;
    if (termijn is num) {
      final i = termijn.toInt();
      return i > 0 ? i : 14;
    }
    final v = int.tryParse(_text(termijn));
    return (v != null && v > 0) ? v : 14;
  }

  // ---------------- klant logic ----------------
  void _applyKlant(Map<String, dynamic> klant, {bool markDirty = true}) {
    setState(() {
      _selectedKlant = klant;
      geselecteerdeKlantId = _text(klant['id']);
      geselecteerdeKlantNaam = _text(klant['bedrijfsnaam']);
      straatController.text = _straatFromKlant(klant);
      postcodeController.text = _bedrijfVeld(klant, ['adres_postcode', 'postcode']);
      stadController.text = _bedrijfVeld(klant, ['adres_stad']);
      kvkController.text = _bedrijfVeld(klant, ['kvk_nummer']);
      btwController.text = klant['btw_nummer']?.toString() ?? '';
      betalingstermijnDagen = _pickTermijn(klant);
      _vervalDatum = _factuurDatum.add(Duration(days: betalingstermijnDagen));
      if (markDirty) _hasUnsavedChanges = true;
    });
  }

  String _klantStadLabel(Map<String, dynamic> b) {
    final s = _bedrijfVeld(b, ['adres_stad']);
    return s.isEmpty ? 'Stad onbekend' : s;
  }

  String _klantKvkLabel(Map<String, dynamic> b) {
    final s = _bedrijfVeld(b, ['kvk_nummer']);
    return s.isEmpty ? 'KVK onbekend' : s;
  }

  Future<void> _toonKlantZoekModal() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var zoekTerm = '';
        var isLoading = true;
        String? loadError;
        List<Map<String, dynamic>> bedrijvenLijst = [];

        Future<void> laadBedrijven(void Function(void Function()) setModalState) async {
          setModalState(() {
            isLoading = true;
            loadError = null;
          });
          try {
            final res = await AppSupabase.client
                .from('bedrijven')
                .select(_klantSelectCols)
                .eq('is_klant', true)
                .order('bedrijfsnaam', ascending: true);
            if (!dialogContext.mounted) return;
            setModalState(() {
              bedrijvenLijst = (res as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              isLoading = false;
            });
          } catch (e) {
            if (!dialogContext.mounted) return;
            setModalState(() {
              loadError = e.toString();
              isLoading = false;
            });
          }
        }

        return SelectionArea(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              if (isLoading && bedrijvenLijst.isEmpty && loadError == null) {
                laadBedrijven(setModalState);
              }

              final gefilterdeLijst = bedrijvenLijst.where((b) {
                if (zoekTerm.isEmpty) return true;
                final naam = _text(b['bedrijfsnaam']).toLowerCase();
                return naam.contains(zoekTerm.toLowerCase());
              }).toList();

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text('Selecteer een Klant'),
                content: SizedBox(
                  width: 600,
                  height: 400,
                  child: Column(
                    children: [
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Zoek op bedrijfsnaam',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => setModalState(() => zoekTerm = val),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : loadError != null
                                ? Center(child: Text('Laden mislukt: $loadError'))
                                : gefilterdeLijst.isEmpty
                                    ? const Center(child: Text('Geen klanten gevonden.'))
                                    : ListView.separated(
                                        itemCount: gefilterdeLijst.length,
                                        separatorBuilder: (context, index) => const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final bedrijf = gefilterdeLijst[index];
                                          final stad = _klantStadLabel(bedrijf);
                                          final kvk = _klantKvkLabel(bedrijf);
                                          final naam = _text(bedrijf['bedrijfsnaam']);

                                          return InkWell(
                                            onTap: () {
                                              Navigator.of(dialogContext).pop();
                                              _applyKlant(bedrijf);
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(
                                                vertical: 12,
                                                horizontal: 8,
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.business,
                                                    color: Colors.blueGrey,
                                                    size: 24,
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      naam.isEmpty ? 'Naamloos' : naam,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    flex: 1,
                                                    child: Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.location_city,
                                                          size: 14,
                                                          color: Colors.grey,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Flexible(
                                                          child: Text(
                                                            stad,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(
                                                              color: Colors.grey.shade700,
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Expanded(
                                                    flex: 1,
                                                    child: Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.numbers,
                                                          size: 14,
                                                          color: Colors.grey,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Flexible(
                                                          child: Text(
                                                            kvk,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(
                                                              color: Colors.grey.shade700,
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Annuleren'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _toonBetalingstermijnModal() async {
    const opties = [8, 14, 21, 30, 60, 90];
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Betalingstermijn', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            ...opties.map(
              (d) => ListTile(
                title: Text('$d dagen'),
                trailing: betalingstermijnDagen == d ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  setState(() {
                    betalingstermijnDagen = d;
                    _vervalDatum = _factuurDatum.add(Duration(days: d));
                    _hasUnsavedChanges = true;
                  });
                  Navigator.of(ctx).pop();
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------- lines logic ----------------
  void _ensureLineCtrls(Map<String, dynamic> l) {
    final id = _text(l['local_id']).isEmpty ? _newLineId() : _text(l['local_id']);
    l['local_id'] = id;
    _lineCtrls.putIfAbsent(id, () => _LineCtrls());
    final c = _lineCtrls[id]!;

    c.artikel.text = _text(l['artikel_label']);
    c.omschrijving.text = _text(l['omschrijving']);
    c.aantal.text = _asDouble(l['aantal']) == 0 ? '' : _asDouble(l['aantal']).toString();
    c.eenheid.text = _text(l['eenheid']);
    c.prijsEx.text = _asDouble(l['stukprijs_ex_btw']) == 0 ? '' : _asDouble(l['stukprijs_ex_btw']).toStringAsFixed(2);
    c.prijsInc.text = _asDouble(l['stukprijs_inc_btw']) == 0 ? '' : _asDouble(l['stukprijs_inc_btw']).toStringAsFixed(2);
    c.btwCode = _text(l['btw_code']).isEmpty && _btwCodes.isNotEmpty ? _text(_btwCodes.first['code']) : _text(l['btw_code']);
    if (_text(l['btw_code']).isEmpty) l['btw_code'] = c.btwCode;
    if (_asDouble(l['btw_percentage']) == 0 && c.btwCode.isNotEmpty) l['btw_percentage'] = _btwPctFor(c.btwCode);
    _syncLinePricesWithVatMode(l);
  }

  void _syncLinePricesWithVatMode(Map<String, dynamic> l) {
    final id = _text(l['local_id']);
    final c = _lineCtrls[id];
    if (c == null) return;
    final code = _text(l['btw_code']);
    final pct = _asDouble(l['btw_percentage']);
    final inclusive = _btwIsInclusive(code);

    if (!inclusive) {
      final ex = _asDouble(l['stukprijs_ex_btw']);
      final inc = ex * (1 + pct / 100.0);
      l['stukprijs_inc_btw'] = inc;
      c.prijsInc.text = inc == 0 ? '' : inc.toStringAsFixed(2);
    } else {
      final inc = _asDouble(l['stukprijs_inc_btw']);
      final ex = pct == 0 ? inc : (inc / (1 + pct / 100.0));
      l['stukprijs_ex_btw'] = ex;
      c.prijsEx.text = ex == 0 ? '' : ex.toStringAsFixed(2);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAlleArtikelen() async {
    final res = await AppSupabase.client.from('artikelen').select().order('artikel_code', ascending: true);
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> _toonArtikelFormSubModal(
    BuildContext dialogContext,
    VoidCallback onReload, {
    Map<String, dynamic>? article,
  }) async {
    final saved = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => _FactuurArtikelFormDialog(
        article: article,
        btwCodes: _btwCodes,
      ),
    );
    if (saved == true) onReload();
  }

  Future<void> _toonArtikelBeheerModal(int lineIndex) async {
    if (lineIndex < 0 || lineIndex >= _lines.length) return;
    final lineId = _text(_lines[lineIndex]['local_id']);

    final picked = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogContext) {
        final search = TextEditingController();
        List<Map<String, dynamic>> list = const [];
        List<Map<String, dynamic>> filtered = const [];
        bool loading = true;

        Future<void> reload(StateSetter setModalState) async {
          setModalState(() => loading = true);
          try {
            list = await _fetchAlleArtikelen();
            final needle = search.text.trim().toLowerCase();
            filtered = needle.isEmpty
                ? List<Map<String, dynamic>>.from(list)
                : list
                    .where((a) {
                      final code = _text(a['artikel_code']).toLowerCase();
                      final naam = _text(a['naam'] ?? a['omschrijving_intern']).toLowerCase();
                      return code.contains(needle) || naam.contains(needle);
                    })
                    .toList(growable: false);
          } catch (_) {
            list = const [];
            filtered = const [];
          }
          setModalState(() => loading = false);
        }

        return SelectionArea(
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: StatefulBuilder(
                  builder: (context, setModalState) {
                    if (loading && list.isEmpty) {
                      reload(setModalState);
                    }

                    void applyFilter(String q) {
                      final needle = q.trim().toLowerCase();
                      setModalState(() {
                        filtered = needle.isEmpty
                            ? List<Map<String, dynamic>>.from(list)
                            : list
                                .where((a) {
                                  final code = _text(a['artikel_code']).toLowerCase();
                                  final naam = _text(a['naam'] ?? a['omschrijving_intern']).toLowerCase();
                                  return code.contains(needle) || naam.contains(needle);
                                })
                                .toList(growable: false);
                      });
                    }

                    return Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Artikelen',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(dialogContext).pop(null),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: loading
                                ? null
                                : () => _toonArtikelFormSubModal(dialogContext, () => reload(setModalState)),
                            icon: const Icon(Icons.add),
                            label: const Text('Nieuw Artikel Toevoegen'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: search,
                          decoration: _inputDeco('Zoeken...', icon: Icons.search),
                          onChanged: applyFilter,
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: loading
                              ? const Center(child: CircularProgressIndicator())
                              : ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, i) => Divider(height: 1, color: Colors.grey.shade200),
                                  itemBuilder: (context, i) {
                                    final a = filtered[i];
                                    final naam = _text(a['naam'] ?? a['omschrijving_intern']);
                                    final eenheid = _text(a['eenheid']);
                                    final groep = _artikelGroepLabel(a);
                                    final prijs = _artikelPrijs(a);
                                    return ListTile(
                                      title: Text(
                                        naam.isEmpty ? _text(a['artikel_code']) : naam,
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      subtitle: Text(
                                        [
                                          if (eenheid.isNotEmpty) eenheid,
                                          if (groep.isNotEmpty) groep,
                                          '€ ${prijs.toStringAsFixed(2)}',
                                        ].join(' · '),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _toonArtikelFormSubModal(
                                          dialogContext,
                                          () => reload(setModalState),
                                          article: a,
                                        ),
                                      ),
                                      onTap: () => Navigator.of(dialogContext).pop(a),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || picked == null) return;
    await _applyArtikelToLine(lineId, picked);
  }

  Future<void> _toonBtwCodeModal(int lineIndex) async {
    if (lineIndex < 0 || lineIndex >= _lines.length) return;
    final l = _lines[lineIndex];

    const opties = <({String label, double pct, bool vrijgesteld, bool verlegd})>[
      (label: '21% (Hoog tarief)', pct: 21, vrijgesteld: false, verlegd: false),
      (label: '9% (Laag tarief)', pct: 9, vrijgesteld: false, verlegd: false),
      (label: '0% (Verlegd)', pct: 0, vrijgesteld: false, verlegd: true),
      (label: 'Vrijgesteld van BTW', pct: 0, vrijgesteld: true, verlegd: false),
    ];

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('BTW-tarief', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            ...opties.map(
              (o) => ListTile(
                title: Text(o.label),
                onTap: () {
                  setState(() {
                    _applyBtwPresetToLine(
                      l,
                      pct: o.pct,
                      vrijgesteld: o.vrijgesteld,
                      verlegd: o.verlegd,
                    );
                    _hasUnsavedChanges = true;
                  });
                  _ensureLineCtrls(l);
                  _syncLinePricesWithVatMode(l);
                  _calculateTotals();
                  Navigator.of(ctx).pop();
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _pickOmschrijving(Map<String, dynamic> a) {
    final candidates = [
      a['omschrijving_factuur'],
      a['factuur_omschrijving'],
      a['omschrijving_intern'],
      a['artikel_naam'],
      a['omschrijving'],
      a['naam'],
    ];
    for (final c in candidates) {
      final s = (c ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  DateTime? _parseDateOnly(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final head = s.length >= 10 ? s.substring(0, 10) : s;
    return DateTime.tryParse(head);
  }

  String _opdrachtDatumLabel(dynamic raw) {
    final d = _parseDateOnly(raw);
    if (d != null) return DateFormat('dd-MM-yyyy').format(d);
    final s = _text(raw);
    return s.isEmpty ? '—' : s;
  }

  String _opdrachtAdresLabel(Map<String, dynamic> op) {
    final adres = _text(op['uitvoer_adres_volledig']);
    if (adres.isNotEmpty) return adres;
    return _text(op['bedrijfsnaam']);
  }

  Map<String, dynamic>? _projectVanOpdracht(Map<String, dynamic> op) {
    final raw = op['project'] ?? op['projecten'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  String _projectNaamVanOpdracht(Map<String, dynamic> op) {
    final proj = _projectVanOpdracht(op);
    if (proj == null) return '';
    return _text(proj['project_naam']);
  }

  String _standaardArtikelCodeVanOpdracht(Map<String, dynamic> op) {
    final projectData = op['projecten'] ?? op['project'];
    dynamic proj = projectData;
    if (proj is List && proj.isNotEmpty) proj = proj.first;
    final code = proj is Map ? _text(proj['standaard_artikel_code']) : '';
    return code.isEmpty ? 'SCH-001' : code;
  }

  String _gekoppeldeOpdrachtenInfoTekst(Map<String, dynamic> op) {
    final datum = _opdrachtDatumLabel(op['geplande_datum']);
    final nummer = _text(op['opdracht_nummer']);
    final nummerLabel = nummer.isEmpty ? 'ONB' : nummer;
    final adres = _opdrachtAdresLabel(op);
    return 'Opdracht: $nummerLabel\nDatum: $datum\nAdres: ${adres.isEmpty ? 'Onbekend' : adres}';
  }

  Future<Map<String, dynamic>?> _fetchArtikelByCode(String artikelCode) async {
    final code = artikelCode.trim();
    if (code.isEmpty) return null;
    try {
      final row = await AppSupabase.client
          .from('artikelen')
          .select()
          .eq('artikel_code', code)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row as Map);
    } catch (_) {
      return null;
    }
  }

  String _opdrachtTaakOmschrijving(Map<String, dynamic> op) {
    for (final key in ['toelichting_planning', 'omschrijving', 'bedrijfsnaam']) {
      final s = _text(op[key]);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _maandLabelVanOpdracht(Map<String, dynamic> op) {
    final d = _parseDateOnly(op['geplande_datum']);
    if (d == null) return 'Datum onbekend';
    try {
      final maandKey = DateFormat('MMMM yyyy', 'nl_NL').format(d);
      if (maandKey.isEmpty) return 'Datum onbekend';
      return maandKey[0].toUpperCase() + maandKey.substring(1);
    } catch (_) {
      return DateFormat('MMMM yyyy').format(d);
    }
  }

  Map<String, List<Map<String, dynamic>>> _groepeerOpdrachtenPerMaand(
    List<Map<String, dynamic>> opdrachten,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final taak in opdrachten) {
      final key = _maandLabelVanOpdracht(taak);
      grouped.putIfAbsent(key, () => []).add(taak);
    }
    return grouped;
  }

  String _netteFactuurOmschrijvingVanOpdracht(Map<String, dynamic> op) {
    final datum = _opdrachtDatumLabel(op['geplande_datum']);
    final naam = _projectNaamVanOpdracht(op);
    final taakOms = _opdrachtTaakOmschrijving(op);
    final adres = _opdrachtAdresLabel(op);

    final parts = <String>['Uitgevoerd op: $datum'];
    if (naam.isNotEmpty) parts.add('Werk: $naam');
    if (taakOms.isNotEmpty && taakOms != naam) parts.add('Omschrijving: $taakOms');
    if (adres.isNotEmpty) parts.add('Locatie: $adres');
    return parts.join('\n');
  }

  double _opdrachtBedragExBtw(Map<String, dynamic> opdracht) {
    dynamic projectData = opdracht['projecten'] ?? opdracht['project'];
    if (projectData is List && projectData.isNotEmpty) {
      projectData = projectData.first;
    }
    if (projectData is! Map) projectData = null;

    var bedrag = double.tryParse(
          opdracht['opdracht_waarde_ex_btw']?.toString() ?? '0',
        ) ??
        0.0;

    if (bedrag <= 0.0) {
      bedrag = double.tryParse(
            opdracht['vaste_prijs_per_beurt']?.toString() ?? '0',
          ) ??
          0.0;
    }

    if (bedrag <= 0.0 && projectData != null) {
      final proj = Map<String, dynamic>.from(projectData as Map);
      bedrag = double.tryParse(
            proj['vaste_prijs_per_beurt']?.toString() ?? '0',
          ) ??
          0.0;
    }

    if (bedrag <= 0.0 && projectData != null) {
      final proj = Map<String, dynamic>.from(projectData as Map);
      final uren = double.tryParse(
            opdracht['verwachte_uren_totaal']?.toString() ?? '0',
          ) ??
          0.0;
      final tarief = double.tryParse(
            proj['vastgelegd_uurtarief']?.toString() ?? '0',
          ) ??
          0.0;
      bedrag = uren * tarief;
    }

    final korting = _asDouble(opdracht['korting_bedrag']);
    return (bedrag - korting).clamp(0.0, double.infinity);
  }

  Map<String, dynamic> _regelVanOpdracht(
    Map<String, dynamic> opdracht, {
    Map<String, dynamic>? artikel,
  }) {
    final opdrachtId = _text(opdracht['id']);
    final bedrag = _opdrachtBedragExBtw(opdracht);
    final datum = _opdrachtDatumLabel(
      opdracht['geplande_datum'] ?? 'Datum onbekend',
    );
    final adres = _text(opdracht['uitvoer_adres_volledig']);
    final netteOmschrijving = 'Uitgevoerd op: $datum\n'
        'Locatie: ${adres.isEmpty ? 'Onbekend' : adres}';

    final berekendeArtikelCode = _standaardArtikelCodeVanOpdracht(opdracht);

    var artikelId = _extraWerkArtikelId ?? '';
    var artikelLabel = berekendeArtikelCode.isNotEmpty
        ? berekendeArtikelCode
        : _extraWerkArtikelLabel;
    var eenheid = 'stuk';
    var btwCode = _btwCodes.isEmpty ? '' : _text(_btwCodes.first['code']);
    var pct = btwCode.isEmpty ? 21.0 : _btwPctFor(btwCode);

    if (artikel != null) {
      artikelId = _text(artikel['id']);
      final code = _text(artikel['artikel_code']);
      final naam = artikel['artikel_naam']?.toString() ??
          artikel['omschrijving']?.toString() ??
          artikel['naam']?.toString() ??
          'Gekoppeld via opdracht';
      artikelLabel = [code, naam].where((s) => s.isNotEmpty).join(' — ');
      if (artikelLabel.isEmpty) {
        artikelLabel = code.isNotEmpty ? code : 'Gekoppeld via opdracht';
      }
      eenheid = _text(artikel['eenheid']).isEmpty ? 'stuk' : _text(artikel['eenheid']);
      final ac = _text(artikel['verkoop_btw_code']);
      if (ac.isNotEmpty) {
        btwCode = ac;
        pct = _btwPctFor(ac);
      }
    }

    return {
      'local_id': _newLineId(),
      'artikel_id': artikelId,
      'artikel_code': berekendeArtikelCode,
      'artikel_label': artikelLabel,
      'omschrijving': netteOmschrijving,
      'aantal': 1,
      'eenheid': eenheid,
      'stukprijs_ex_btw': bedrag,
      'stukprijs_inc_btw': 0.0,
      'btw_code': btwCode,
      'btw_percentage': pct,
      'gekoppelde_opdracht_id': opdrachtId,
      'gekoppelde_opdrachten_info': _gekoppeldeOpdrachtenInfoTekst(opdracht),
    };
  }

  Future<void> _voegGeselecteerdeOpdrachtenToe(
    List<Map<String, dynamic>> opdrachten,
    List<String> geselecteerdeIds,
  ) async {
    final artikelByCode = <String, Map<String, dynamic>>{};
    for (final id in geselecteerdeIds) {
      Map<String, dynamic>? op;
      for (final o in opdrachten) {
        if (_text(o['id']) == id) {
          op = o;
          break;
        }
      }
      if (op == null) continue;
      final code = _standaardArtikelCodeVanOpdracht(op);
      if (artikelByCode.containsKey(code)) continue;
      final art = await _fetchArtikelByCode(code);
      if (art != null) artikelByCode[code] = art;
    }

    if (artikelByCode.isEmpty &&
        (_extraWerkArtikelId == null || _text(_extraWerkArtikelId).isEmpty)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Geen artikel gevonden (controleer standaard_artikel_code op project of SCH-001).',
          ),
        ),
      );
      return;
    }

    var toegevoegd = 0;
    if (!mounted) return;
    setState(() {
      for (final id in geselecteerdeIds) {
        if (gekoppeldeOpdrachtIds.contains(id)) continue;
        Map<String, dynamic>? op;
        for (final o in opdrachten) {
          if (_text(o['id']) == id) {
            op = o;
            break;
          }
        }
        if (op == null) continue;

        final code = _standaardArtikelCodeVanOpdracht(op);
        final artikel = artikelByCode[code];
        final l = _regelVanOpdracht(op, artikel: artikel);
        if (_asDouble(l['stukprijs_ex_btw']) <= 0) continue;
        if (_text(l['artikel_id']).isEmpty) continue;

        gekoppeldeOpdrachtIds.add(id);
        _lines.add(l);
        _ensureLineCtrls(l);
        _syncLinePricesWithVatMode(l);
        toegevoegd++;
        _hasUnsavedChanges = true;
      }
    });
    _calculateTotals();

    if (toegevoegd == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Geen geldige opdrachten om toe te voegen (bedrag 0 of al gekoppeld).'),
        ),
      );
    }
  }

  Future<void> _toonOpdrachtKiezerModal() async {
    if (geselecteerdeKlantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecteer eerst een klant.')),
      );
      return;
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var isLoading = true;
        String? loadError;
        List<Map<String, dynamic>> alleOpdrachtenFlat = [];
        Map<String, List<Map<String, dynamic>>> gegroepeerdeOpdrachten = {};
        final tijdelijkeSelectie = <String>[];
        var loadGestart = false;

        Future<void> laadOpdrachten(void Function(void Function()) setModalState) async {
          try {
            final res = await AppSupabase.client
                .from('opdrachten')
                .select(
                  '*, projecten!inner(bedrijf_id, standaard_artikel_code, vaste_prijs_per_beurt, vastgelegd_uurtarief)',
                )
                .eq('projecten.bedrijf_id', geselecteerdeKlantId!)
                .eq('facturatie_status', 'facturabel')
                .isFilter('factuur_id', null)
                .order('geplande_datum', ascending: false);

            final flat = (res as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .where((o) {
                  final id = _text(o['id']);
                  if (id.isEmpty) return false;
                  return !gekoppeldeOpdrachtIds.contains(id);
                })
                .toList();

            if (!dialogContext.mounted) return;
            setModalState(() {
              alleOpdrachtenFlat = flat;
              gegroepeerdeOpdrachten = _groepeerOpdrachtenPerMaand(flat);
              isLoading = false;
              loadError = null;
            });
          } catch (e) {
            if (!dialogContext.mounted) return;
            setModalState(() {
              loadError = e.toString();
              isLoading = false;
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            if (isLoading && !loadGestart) {
              loadGestart = true;
              laadOpdrachten(setModalState);
            }

            return SelectionArea(
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text('Kies facturabele opdrachten'),
                content: SizedBox(
                  width: 600,
                  height: 500,
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : loadError != null
                          ? Center(child: Text('Laden mislukt: $loadError'))
                          : gegroepeerdeOpdrachten.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Geen openstaande opdrachten voor deze klant.',
                                  ),
                                )
                              : ListView(
                                  children: gegroepeerdeOpdrachten.entries.map((entry) {
                                    final maand = entry.key;
                                    final takenVanMaand = entry.value;

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          color: Colors.blue.shade50,
                                          margin: const EdgeInsets.only(top: 12, bottom: 8),
                                          child: ListTile(
                                            title: Text(
                                              maand,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue.shade900,
                                              ),
                                            ),
                                            trailing: TextButton.icon(
                                              icon: const Icon(
                                                Icons.playlist_add_check,
                                                size: 18,
                                              ),
                                              label: Text(
                                                'Voeg maand toe (${takenVanMaand.length})',
                                              ),
                                              onPressed: () {
                                                setModalState(() {
                                                  for (final t in takenVanMaand) {
                                                    final id = _text(t['id']);
                                                    if (id.isNotEmpty &&
                                                        !tijdelijkeSelectie.contains(id)) {
                                                      tijdelijkeSelectie.add(id);
                                                    }
                                                  }
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                        ...takenVanMaand.map((opdracht) {
                                          final id = _text(opdracht['id']);
                                          final isSelected =
                                              tijdelijkeSelectie.contains(id);
                                          final bedrag = _opdrachtBedragExBtw(opdracht);
                                          final geplandeDatum =
                                              _opdrachtDatumLabel(opdracht['geplande_datum']);
                                          final nummer = _text(opdracht['opdracht_nummer']);
                                          final adres = _opdrachtAdresLabel(opdracht);

                                          return CheckboxListTile(
                                            title: Text(
                                              [
                                                geplandeDatum,
                                                if (nummer.isNotEmpty) nummer,
                                              ].join(' • '),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            subtitle: Text(
                                              '${adres.isEmpty ? 'Adres onbekend' : adres} | '
                                              '€${bedrag.toStringAsFixed(2)}',
                                            ),
                                            value: isSelected,
                                            activeColor: Colors.blue.shade700,
                                            onChanged: (val) {
                                              setModalState(() {
                                                if (val == true) {
                                                  if (!tijdelijkeSelectie.contains(id)) {
                                                    tijdelijkeSelectie.add(id);
                                                  }
                                                } else {
                                                  tijdelijkeSelectie.remove(id);
                                                }
                                              });
                                            },
                                          );
                                        }),
                                      ],
                                    );
                                  }).toList(),
                                ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Annuleren'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: tijdelijkeSelectie.isEmpty
                        ? null
                        : () async {
                            await _voegGeselecteerdeOpdrachtenToe(
                              alleOpdrachtenFlat,
                              List<String>.from(tijdelijkeSelectie),
                            );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                    child: Text('Regels aanmaken (${tijdelijkeSelectie.length})'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _applyArtikelToLine(String lineId, Map<String, dynamic> artikel) async {
    final l = _lines.firstWhere((x) => _text(x['local_id']) == lineId);
    final code = _text(artikel['artikel_code']);
    final naam = _text(artikel['naam']);
    final label = [code, naam].where((s) => s.isNotEmpty).join(' — ');
    final btwCode = _text(artikel['verkoop_btw_code']);
    final pct = btwCode.isEmpty ? 0.0 : _btwPctFor(btwCode);

    setState(() {
      l['artikel_id'] = artikel['id'];
      l['artikel_label'] = label;
      l['omschrijving'] = _pickOmschrijving(artikel);
      l['eenheid'] = _text(artikel['eenheid']);
      l['stukprijs_ex_btw'] = _artikelPrijs(artikel);
      l['stukprijs_inc_btw'] = 0.0;
      l['btw_code'] = btwCode;
      l['btw_percentage'] = pct;
      _hasUnsavedChanges = true;
    });

    _ensureLineCtrls(l);
    _syncLinePricesWithVatMode(l);
    _calculateTotals();
  }

  // ---------------- date pickers ----------------
  Future<void> _pickFactuurDatum() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _factuurDatum,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _factuurDatum = picked;
      _vervalDatum = _factuurDatum.add(Duration(days: betalingstermijnDagen));
      _hasUnsavedChanges = true;
    });
  }

  Future<void> _pickVervalDatum() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _vervalDatum,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _vervalDatum = picked;
      _hasUnsavedChanges = true;
    });
  }

  // ---------------- save ----------------
  bool _validateVoorOpslaan() {
    if (geselecteerdeKlantId == null || _selectedKlant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.withValues(alpha: 0.92),
          content: const Text('Selecteer een klant.'),
        ),
      );
      return false;
    }
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.withValues(alpha: 0.92),
          content: const Text('Voeg minimaal 1 factuurregel toe.'),
        ),
      );
      return false;
    }
    for (final l in _lines) {
      if (_text(l['artikel_id']).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.withValues(alpha: 0.92),
            content: const Text('Kies per regel een artikel.'),
          ),
        );
        return false;
      }
      if (_asDouble(l['aantal']) == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.withValues(alpha: 0.92),
            content: const Text(
              'Aantal mag niet 0 zijn (gebruik een negatief getal voor korting).',
            ),
          ),
        );
        return false;
      }
      if (_asDouble(l['stukprijs_ex_btw']) == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.withValues(alpha: 0.92),
            content: const Text('Vul per regel een prijs ex. BTW in.'),
          ),
        );
        return false;
      }
    }
    return true;
  }

  String _maandSleutel(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  Future<void> _verwijderConceptFactuur() async {
    final factuurId = _factuurId;
    if (factuurId == null || factuurId.isEmpty || _deleteConceptBusy) return;

    setState(() => _deleteConceptBusy = true);
    try {
      final factuurData = await AppSupabase.client
          .from('facturen')
          .select('bedrijf_id, factuur_datum, status')
          .eq('id', factuurId)
          .single();

      final bedrijfId = _text(factuurData['bedrijf_id']);
      final factuurDatum = DateTime.tryParse(_text(factuurData['factuur_datum']))?.toLocal();
      final maandSleutel =
          factuurDatum == null ? '' : _maandSleutel(factuurDatum);

      await AppSupabase.client
          .from('opdrachten')
          .update({'factuur_id': null})
          .eq('factuur_id', factuurId);
      await AppSupabase.client.from('factuur_regels').delete().eq('factuur_id', factuurId);
      await AppSupabase.client.from('facturen').delete().eq('id', factuurId);

      if (bedrijfId.isNotEmpty && maandSleutel.isNotEmpty) {
        await AppSupabase.client
            .from('klant_facturaties')
            .delete()
            .eq('bedrijf_id', bedrijfId)
            .eq('maand_sleutel', maandSleutel);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Fout bij verwijderen concept: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon concept niet verwijderen: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _deleteConceptBusy = false);
    }
  }

  Future<void> _save({required bool closeAfter, required bool newAfter}) async {
    if (_saving) return;
    if (!_validateVoorOpslaan()) return;

    setState(() => _saving = true);
    try {
      final klantId = _text(_selectedKlant?['id']);
      final totals = _totalsFromLines();
      final header = <String, dynamic>{
        'bedrijf_id': klantId,
        'status': 'concept',
        'factuur_datum': DateFormat('yyyy-MM-dd').format(_factuurDatum),
        'verval_datum': DateFormat('yyyy-MM-dd').format(_vervalDatum),
        'omschrijving': _omschrijvingCtrl.text.trim(),
        'layout_toon_aantallen': _toonAantallen,
        'layout_toon_prijzen': _toonPrijzen,
        'totaal_ex_btw': totals.ex,
        'btw_bedrag': totals.btw,
        'totaal_btw': totals.btw,
        'totaal_inc_btw': totals.incl,
        'btw_verlegd': false,
      };

      if (_factuurId == null) {
        final inserted = await AppSupabase.client
            .from('facturen')
            .insert(header)
            .select('id, order_nummer, factuur_nummer')
            .single();
        _factuurId = _text(inserted['id']);
        _orderNummer = inserted['order_nummer'] is num
            ? (inserted['order_nummer'] as num).toInt()
            : int.tryParse(_text(inserted['order_nummer']));
        _factuurNummer = _text(inserted['factuur_nummer']).isEmpty ? null : _text(inserted['factuur_nummer']);
      } else {
        await AppSupabase.client.from('facturen').update(header).eq('id', _factuurId!);
      }

      final id = _factuurId!;
      await AppSupabase.client.from('factuur_regels').delete().eq('factuur_id', id);

      var volgorde = 1;
      for (final l in _lines) {
        final gekoppeldeInfo = _text(l['gekoppelde_opdrachten_info']);
        final opdrachtId = _text(l['gekoppelde_opdracht_id']);
        final slotInfo = gekoppeldeInfo.isNotEmpty
            ? gekoppeldeInfo
            : (opdrachtId.isNotEmpty ? opdrachtId : null);
        await AppSupabase.client.from('factuur_regels').insert({
          'factuur_id': id,
          'artikel_id': l['artikel_id'],
          'omschrijving': _text(l['omschrijving']),
          'aantal': _asDouble(l['aantal']),
          'eenheid': _text(l['eenheid']),
          'stukprijs_ex_btw': _asDouble(l['stukprijs_ex_btw']),
          'btw_code': _text(l['btw_code']),
          'btw_percentage': _asDouble(l['btw_percentage']),
          'volgorde': volgorde++,
          if (slotInfo != null) 'gekoppelde_opdrachten_info': slotInfo,
        });
      }

      // factuur_id koppelen; DB-trigger zet facturatie_status op 'gefactureerd'.
      if (gekoppeldeOpdrachtIds.isNotEmpty) {
        final nieuwAangemaakteFactuurId = id;
        await AppSupabase.client
            .from('opdrachten')
            .update({'factuur_id': nieuwAangemaakteFactuurId})
            .inFilter('id', gekoppeldeOpdrachtIds);
      }

      if (!mounted) return;
      setState(() => _hasUnsavedChanges = false);

      if (closeAfter) {
        Navigator.of(context).pop();
        return;
      }
      if (newAfter) {
        setState(() {
          _factuurId = null;
          _orderNummer = null;
          _factuurNummer = null;
          _selectedKlant = null;
          geselecteerdeKlantId = null;
          geselecteerdeKlantNaam = null;
          straatController.clear();
          postcodeController.clear();
          stadController.clear();
          kvkController.clear();
          btwController.clear();
          _omschrijvingCtrl.text = '';
          betalingstermijnDagen = 14;
          _factuurDatum = DateTime.now();
          _vervalDatum = DateTime.now().add(const Duration(days: 14));
          for (final c in _lineCtrls.values) {
            c.dispose();
          }
          _lineCtrls.clear();
          _lines.clear();
          gekoppeldeOpdrachtIds = [];
          _subtotaal = 0;
          _btwTotaal = 0;
          _totaalIncl = 0;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Opslaan mislukt: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------- UI helpers ----------------
  InputDecoration _inputDeco(String label, {IconData? icon, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon, size: 18),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _pill(String label, String value) {
    return SizedBox(
      width: 220,
      child: InputDecorator(
        decoration: _inputDeco(label),
        child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _dateField(String label, DateTime value, VoidCallback onTap) {
    final df = DateFormat('dd-MM-yyyy');
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.date_range),
      label: Text('$label: ${df.format(value)}', style: const TextStyle(fontWeight: FontWeight.w800)),
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide(color: Colors.grey.shade300),
        foregroundColor: const Color(0xFF0F172A),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _headerRow() {
    const style = TextStyle(fontWeight: FontWeight.w900, fontSize: 12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(16)),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('Artikel', style: style)),
          Expanded(flex: 3, child: Text('Omschrijving', style: style)),
          Expanded(child: Text('Aantal', style: style)),
          Expanded(child: Text('Eenheid', style: style)),
          Expanded(child: Text('Prijs Ex', style: style)),
          Expanded(child: Text('BTW', style: style)),
          Expanded(child: Text('Prijs Inc', style: style)),
          Expanded(child: Text('Totaal', style: style)),
          SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _lineItem(int i) {
    final l = _lines[i];
    final id = _text(l['local_id']);
    final c = _lineCtrls[id]!;

    final code = _text(l['btw_code']);
    final pct = _asDouble(l['btw_percentage']);
    final inclusive = _btwIsInclusive(code);
    final qty = _asDouble(l['aantal']);
    final ex = _asDouble(l['stukprijs_ex_btw']);
    final inc = _asDouble(l['stukprijs_inc_btw']);

    final derivedInc = ex * (1 + pct / 100.0);
    final derivedEx = pct == 0 ? inc : (inc / (1 + pct / 100.0));
    final totalEx = qty * ex;

    if (!inclusive) {
      final txt = derivedInc == 0 ? '' : derivedInc.toStringAsFixed(2);
      if (c.prijsInc.text != txt) c.prijsInc.text = txt;
      l['stukprijs_inc_btw'] = derivedInc;
    } else {
      final txt = derivedEx == 0 ? '' : derivedEx.toStringAsFixed(2);
      if (c.prijsEx.text != txt) c.prijsEx.text = txt;
      l['stukprijs_ex_btw'] = derivedEx;
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _toonArtikelBeheerModal(i),
                borderRadius: BorderRadius.circular(16),
                child: InputDecorator(
                  decoration: _inputDeco('Artikel', icon: Icons.inventory_2_outlined),
                  child: Text(
                    c.artikel.text.isEmpty ? 'Klik om artikel te kiezen' : c.artikel.text,
                    style: TextStyle(
                      fontWeight: c.artikel.text.isEmpty ? FontWeight.normal : FontWeight.w800,
                      color: c.artikel.text.isEmpty ? Colors.black54 : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: c.omschrijving,
                  decoration: _inputDeco('Omschrijving'),
                  onChanged: (v) {
                    l['omschrijving'] = v;
                    _markDirty();
                  },
                ),
                if (_text(l['gekoppelde_opdrachten_info']).isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueGrey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lock, size: 14, color: Colors.blueGrey),
                            SizedBox(width: 6),
                            Text(
                              'Gekoppelde systeemdata (vast):',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _text(l['gekoppelde_opdrachten_info']).replaceAll(r'\n', '\n'),
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: c.aantal,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: _inputDeco('Aantal'),
              onChanged: (v) {
                l['aantal'] = _asDouble(v);
                _markDirty();
                _calculateTotals();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: c.eenheid,
              decoration: _inputDeco('Eenheid'),
              onChanged: (v) {
                l['eenheid'] = v;
                _markDirty();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: c.prijsEx,
              readOnly: inclusive,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _inputDeco('Prijs Ex'),
              onChanged: (v) {
                l['stukprijs_ex_btw'] = _asDouble(v);
                _syncLinePricesWithVatMode(l);
                _markDirty();
                _calculateTotals();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _toonBtwCodeModal(i),
                borderRadius: BorderRadius.circular(16),
                child: InputDecorator(
                  decoration: _inputDeco('BTW', icon: Icons.percent),
                  child: Text(
                    'BTW: ${_krijgBtwCode(l['btw_percentage'])}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: c.prijsInc,
              readOnly: !inclusive,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _inputDeco('Prijs Inc'),
              onChanged: (v) {
                l['stukprijs_inc_btw'] = _asDouble(v);
                _syncLinePricesWithVatMode(l);
                _markDirty();
                _calculateTotals();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InputDecorator(
              decoration: _inputDeco('Totaal'),
              child: Text('€ ${totalEx.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
          IconButton(
            tooltip: 'Verwijderen',
            onPressed: () {
              setState(() {
                final opdrachtId = _text(l['gekoppelde_opdracht_id']);
                if (opdrachtId.isNotEmpty) {
                  gekoppeldeOpdrachtIds.remove(opdrachtId);
                }
                _lines.removeAt(i);
                _lineCtrls.remove(id)?.dispose();
                _hasUnsavedChanges = true;
              });
              _calculateTotals();
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eur = NumberFormat.currency(locale: 'nl_NL', symbol: '€');

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 18, offset: const Offset(0, 8)),
                    ],
                  ),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _pill('Factuurnummer', _factuurNummer ?? 'Concept'),
                          _pill('Ordernummer', _orderNummer == null ? '—' : _orderNummer.toString()),
                          SizedBox(
                            width: 420,
                            child: TextField(
                              controller: _omschrijvingCtrl,
                              decoration: _inputDeco('Factuur Omschrijving (Verplicht)', icon: Icons.description_outlined),
                              onChanged: (_) => _markDirty(),
                            ),
                          ),
                          SizedBox(
                            width: 420,
                            child: InkWell(
                              onTap: _toonKlantZoekModal,
                              borderRadius: BorderRadius.circular(4),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Klant / Bedrijf',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.domain),
                                  suffixIcon: Icon(Icons.arrow_drop_down),
                                ),
                                child: Text(
                                  geselecteerdeKlantNaam ?? 'Klik hier om een klant te selecteren...',
                                  style: TextStyle(
                                    color: geselecteerdeKlantNaam == null
                                        ? Colors.grey.shade600
                                        : Colors.black87,
                                    fontSize: 16,
                                    fontWeight: geselecteerdeKlantNaam != null
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _dateField('Factuurdatum', _factuurDatum, _pickFactuurDatum),
                          _dateField('Vervaldatum', _vervalDatum, _pickVervalDatum),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 280,
                            child: TextFormField(
                              controller: straatController,
                              readOnly: true,
                              decoration: _readOnlyDeco('Straat'),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: TextFormField(
                              controller: postcodeController,
                              readOnly: true,
                              decoration: _readOnlyDeco('Postcode'),
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: TextFormField(
                              controller: stadController,
                              readOnly: true,
                              decoration: _readOnlyDeco('Stad'),
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: TextFormField(
                              controller: kvkController,
                              readOnly: true,
                              decoration: _readOnlyDeco('KVK'),
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: TextFormField(
                              controller: btwController,
                              readOnly: true,
                              decoration: _readOnlyDeco('BTW-nummer'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          title: const Text('Betalingstermijn'),
                          subtitle: Text('$betalingstermijnDagen dagen'),
                          trailing: const Icon(Icons.arrow_drop_down),
                          onTap: _toonBetalingstermijnModal,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          initiallyExpanded: false,
                          tilePadding: EdgeInsets.zero,
                          title: const Text('PDF Instellingen', style: TextStyle(fontWeight: FontWeight.w900)),
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                FilterChip(
                                  label: const Text('Toon aantallen op PDF'),
                                  selected: _toonAantallen,
                                  onSelected: (v) {
                                    setState(() => _toonAantallen = v);
                                    _markDirty();
                                  },
                                ),
                                FilterChip(
                                  label: const Text('Toon prijzen op PDF'),
                                  selected: _toonPrijzen,
                                  onSelected: (v) {
                                    setState(() => _toonPrijzen = v);
                                    _markDirty();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(child: Text('Factuurregels', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                  ElevatedButton.icon(
                    onPressed: geselecteerdeKlantId == null || _saving ? null : _toonOpdrachtKiezerModal,
                    icon: const Icon(Icons.assignment_turned_in),
                    label: const Text('Koppel openstaande opdrachten'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade100,
                      foregroundColor: Colors.blue.shade900,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        final l = <String, dynamic>{
                          'local_id': _newLineId(),
                          'artikel_id': '',
                          'artikel_label': '',
                          'omschrijving': '',
                          'aantal': 1,
                          'eenheid': '',
                          'stukprijs_ex_btw': 0.0,
                          'stukprijs_inc_btw': 0.0,
                          'btw_code': _btwCodes.isEmpty ? '' : _text(_btwCodes.first['code']),
                          'btw_percentage': _btwCodes.isEmpty ? 0.0 : _btwPctFor(_text(_btwCodes.first['code'])),
                        };
                        _lines.add(l);
                        _ensureLineCtrls(l);
                        _hasUnsavedChanges = true;
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('+ Regel Toevoegen'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _headerRow(),
              const SizedBox(height: 6),
              Expanded(
                child: _lines.isEmpty
                    ? const Center(child: Text('Geen regels. Klik "+ Regel Toevoegen".'))
                    : ListView.builder(itemCount: _lines.length, itemBuilder: (context, i) => _lineItem(i)),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0912),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 22, offset: const Offset(0, 10))],
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 10,
                  children: [
                    _footerMetric('Subtotaal', eur.format(_subtotaal)),
                    _footerMetric('BTW Totaal', eur.format(_btwTotaal)),
                    _footerMetric('Totaal Incl. BTW', eur.format(_totaalIncl), strong: true),
                    Wrap(
                      spacing: 10,
                      children: [
                        OutlinedButton(
                          onPressed: _saving ? null : () => _save(closeAfter: true, newAfter: false),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          child: _saving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Opslaan & Sluiten', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                        FilledButton(
                          onPressed: _saving ? null : () => _save(closeAfter: false, newAfter: true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0A0912),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          child: const Text('Opslaan & Nieuw', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBackButton();
      },
      child: Scaffold(
        drawer: const AppDrawer(),
        backgroundColor: const Color(0xFFF4F5F7),
        appBar: AppBar(
          leading: BackButton(onPressed: _handleBackButton),
          title: const Text('Factuur Editor'),
          actions: [
            if (_factuurId != null && _factuurStatus == 'concept')
              IconButton(
                tooltip: 'Concept verwijderen',
                onPressed: (_saving || _deleteConceptBusy) ? null : _verwijderConceptFactuur,
                icon: _deleteConceptBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
              ),
          ],
        ),
        body: SelectionArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _footerMetric(String label, String value, {bool strong = false}) {
    final labelStyle = TextStyle(color: Colors.white.withValues(alpha: 0.72), fontWeight: FontWeight.w700);
    final valueStyle = TextStyle(
      color: Colors.white,
      fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
      fontSize: strong ? 18 : 16,
    );
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 4),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}

class _LineCtrls {
  final artikel = TextEditingController();
  final omschrijving = TextEditingController();
  final aantal = TextEditingController(text: '1');
  final eenheid = TextEditingController();
  final prijsEx = TextEditingController();
  final prijsInc = TextEditingController();
  String btwCode = '';

  void dispose() {
    artikel.dispose();
    omschrijving.dispose();
    aantal.dispose();
    eenheid.dispose();
    prijsEx.dispose();
    prijsInc.dispose();
  }
}

class _FactuurArtikelFormDialog extends StatefulWidget {
  const _FactuurArtikelFormDialog({
    required this.article,
    required this.btwCodes,
  });

  final Map<String, dynamic>? article;
  final List<Map<String, dynamic>> btwCodes;

  @override
  State<_FactuurArtikelFormDialog> createState() => _FactuurArtikelFormDialogState();
}

class _FactuurArtikelFormDialogState extends State<_FactuurArtikelFormDialog> {
  bool _saving = false;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _naamCtrl;
  late final TextEditingController _factuurCtrl;
  late final TextEditingController _prijsCtrl;
  String _eenheid = 'stuk';
  String? _btwCode;

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(_text(v).replaceAll(',', '.')) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    final a = widget.article;
    _codeCtrl = TextEditingController(text: _text(a?['artikel_code']));
    _naamCtrl = TextEditingController(text: _text(a?['naam'] ?? a?['omschrijving_intern']));
    _factuurCtrl = TextEditingController(
      text: _text(a?['factuur_omschrijving'] ?? a?['omschrijving_factuur']),
    );
    final prijs = _asDouble(a?['verkoopprijs_ex_btw'] ?? a?['standaard_prijs_ex_btw'] ?? a?['stukprijs_ex_btw']);
    _prijsCtrl = TextEditingController(text: prijs == 0 ? '' : prijs.toStringAsFixed(2));
    _eenheid = _text(a?['eenheid']).isEmpty ? 'stuk' : _text(a?['eenheid']);
    _btwCode = _text(a?['verkoop_btw_code'] ?? a?['standaard_btw_code']).isEmpty
        ? null
        : _text(a?['verkoop_btw_code'] ?? a?['standaard_btw_code']);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _naamCtrl.dispose();
    _factuurCtrl.dispose();
    _prijsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_codeCtrl.text.trim().isEmpty || _naamCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul minimaal code en naam in.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final prijs = double.tryParse(_prijsCtrl.text.trim().replaceAll(',', '.')) ?? 0;
      final payload = <String, dynamic>{
        'artikel_code': _codeCtrl.text.trim(),
        'naam': _naamCtrl.text.trim(),
        'omschrijving_intern': _naamCtrl.text.trim(),
        'factuur_omschrijving': _factuurCtrl.text.trim(),
        'omschrijving_factuur': _factuurCtrl.text.trim(),
        'eenheid': _eenheid,
        'verkoopprijs_ex_btw': prijs,
        if (_btwCode != null) 'verkoop_btw_code': _btwCode,
      };
      final id = _text(widget.article?['id']);
      if (id.isEmpty) {
        await AppSupabase.client.from('artikelen').insert(payload);
      } else {
        await AppSupabase.client.from('artikelen').update(payload).eq('id', id);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opslaan mislukt: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _text(widget.article?['id']).isEmpty;
    return SelectionArea(
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isNew ? 'Nieuw artikel' : 'Artikel bewerken'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _codeCtrl,
                decoration: const InputDecoration(labelText: 'Artikelcode'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _naamCtrl,
                decoration: const InputDecoration(labelText: 'Naam'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _factuurCtrl,
                decoration: const InputDecoration(labelText: 'Factuuromschrijving'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _eenheid,
                decoration: const InputDecoration(labelText: 'Eenheid'),
                items: const [
                  DropdownMenuItem(value: 'stuk', child: Text('stuk')),
                  DropdownMenuItem(value: 'uur', child: Text('uur')),
                  DropdownMenuItem(value: 'm2', child: Text('m²')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _eenheid = v ?? 'stuk'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _prijsCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Verkoopprijs ex. BTW'),
              ),
              if (widget.btwCodes.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _btwCode,
                  decoration: const InputDecoration(labelText: 'BTW-code'),
                  items: widget.btwCodes
                      .map((b) => DropdownMenuItem(value: _text(b['code']), child: Text(_text(b['code']))))
                      .toList(growable: false),
                  onChanged: _saving ? null : (v) => setState(() => _btwCode = v),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Annuleren')),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Opslaan'),
          ),
        ],
      ),
    );
  }
}

