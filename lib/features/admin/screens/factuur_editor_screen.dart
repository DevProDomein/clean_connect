import 'dart:async';

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
  // Header (De Kaft)
  Map<String, dynamic>? _selectedKlant;
  DateTime _factuurDatum = DateTime.now();
  DateTime _vervalDatum = DateTime.now().add(const Duration(days: 14));
  int _betalingsTermijn = 14;

  String? _factuurId;
  int? _orderNummer;
  String? _factuurNummer;

  bool _loading = true;
  bool _saving = false;
  bool _hasUnsavedChanges = false;

  final _klantCtrl = TextEditingController();
  final _omschrijvingCtrl = TextEditingController();

  bool _toonAantallen = true;
  bool _toonPrijzen = true;

  // Lines
  final List<Map<String, dynamic>> _lines = [];
  final Map<String, _LineCtrls> _lineCtrls = {};

  // VAT lookups
  List<Map<String, dynamic>> _btwCodes = const [];
  final Map<String, double> _btwPctByCode = {};
  final Map<String, bool> _btwInclByCode = {};

  // Klant autocomplete
  List<Map<String, dynamic>> _klantOptions = const [];
  Timer? _klantDebounce;
  int _klantReq = 0;

  // Artikel autocomplete per line
  final Map<String, List<Map<String, dynamic>>> _artikelOptionsByLine = {};
  final Map<String, Timer> _artikelDebounceByLine = {};

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
    _klantCtrl.dispose();
    _omschrijvingCtrl.dispose();
    _klantDebounce?.cancel();
    for (final t in _artikelDebounceByLine.values) {
      t.cancel();
    }
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

  void _calculateTotals() {
    double sub = 0;
    double btw = 0;
    for (final l in _lines) {
      final qty = _asDouble(l['aantal']);
      final ex = _asDouble(l['stukprijs_ex_btw']);
      final pct = _asDouble(l['btw_percentage']);
      final lineEx = qty * ex;
      sub += lineEx;
      btw += lineEx * (pct / 100.0);
    }
    setState(() {
      _subtotaal = sub;
      _btwTotaal = btw;
      _totaalIncl = sub + btw;
    });
  }

  Future<void> _handleBackButton() async {
    if (!_hasUnsavedChanges) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final bool? shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Niet opgeslagen wijzigingen', style: TextStyle(fontWeight: FontWeight.bold)),
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

      if (_factuurId != null) {
        final inv = await AppSupabase.client
            .from('facturen')
            .select(
              'id, order_nummer, factuur_nummer, factuur_datum, verval_datum, omschrijving, bedrijf_id, layout_toon_aantallen, layout_toon_prijzen',
            )
            .eq('id', _factuurId!)
            .maybeSingle();
        if (inv != null) {
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
                .select(
                  'id, bedrijfsnaam, kvk, straat, huisnummer, postcode, plaats, betalingstermijn_dagen',
                )
                .eq('id', bedrijfId)
                .maybeSingle();
            if (klant != null) {
              _applyKlant(klant, markDirty: false);
            }
          }

          final regels = await AppSupabase.client
              .from('factuur_regels')
              .select('id, artikel_id, omschrijving, aantal, eenheid, stukprijs_ex_btw, btw_code, btw_percentage, volgorde')
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
    final termijn = klant['betalingstermijn_dagen'] ?? 14;
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
      _klantCtrl.text = _text(klant['bedrijfsnaam']);
      _betalingsTermijn = _pickTermijn(klant);
      _vervalDatum = _factuurDatum.add(Duration(days: _betalingsTermijn));
      if (markDirty) _hasUnsavedChanges = true;
    });
  }

  Future<void> _fetchKlantSuggestions(String input) async {
    final q = input.trim();
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() => _klantOptions = const []);
      return;
    }
    final req = ++_klantReq;
    try {
      final res = await AppSupabase.client
          .from('bedrijven')
          .select(
            'id, bedrijfsnaam, kvk, straat, huisnummer, postcode, plaats, betalingstermijn_dagen',
          )
          .eq('is_klant', true)
          .ilike('bedrijfsnaam', '%$q%')
          .limit(10);
      if (!mounted || req != _klantReq) return;
      setState(() => _klantOptions = (res as List).cast<Map<String, dynamic>>());
    } catch (_) {
      if (!mounted || req != _klantReq) return;
      setState(() => _klantOptions = const []);
    }
  }

  Future<void> _openKlantModal() async {
    final res = await AppSupabase.client
        .from('bedrijven')
        .select(
          'id, bedrijfsnaam, kvk, straat, huisnummer, postcode, plaats, betalingstermijn_dagen',
        )
        .eq('is_klant', true)
        .order('bedrijfsnaam', ascending: true);
    final list = (res as List).cast<Map<String, dynamic>>();
    if (!mounted) return;

    final picked = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) {
        final search = TextEditingController();
        var filtered = List<Map<String, dynamic>>.from(list);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 640),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setLocal) {
                  void apply(String q) {
                    final needle = q.trim().toLowerCase();
                    setLocal(() {
                      filtered = needle.isEmpty
                          ? List<Map<String, dynamic>>.from(list)
                          : list
                              .where((c) => _text(c['bedrijfsnaam']).toLowerCase().contains(needle))
                              .toList(growable: false);
                    });
                  }

                  return Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Selecteer klant', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          ),
                          IconButton(onPressed: () => Navigator.of(context).pop(null), icon: const Icon(Icons.close)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: search,
                        decoration: _inputDeco('Zoeken...', icon: Icons.search),
                        onChanged: apply,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (context, i) {
                            final c = filtered[i];
                            return ListTile(
                              title: Text(_text(c['bedrijfsnaam']), style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text(_text(c['kvk']).isEmpty ? '' : 'KVK: ${_text(c['kvk'])}'),
                              onTap: () => Navigator.of(context).pop(c),
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
        );
      },
    );

    if (!mounted || picked == null) return;
    _applyKlant(picked);
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

  Future<void> _fetchArtikelSuggestions(String lineId, String input) async {
    final q = input.trim().toLowerCase();
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() => _artikelOptionsByLine[lineId] = const []);
      return;
    }
    try {
      final res = await AppSupabase.client
          .from('artikelen')
          .select(
            'id, artikel_code, naam, eenheid, stukprijs_ex_btw, verkoop_btw_code, omschrijving_factuur, factuur_omschrijving, omschrijving_intern',
          )
          .or('artikel_code.ilike.%$q%,naam.ilike.%$q%')
          .limit(10);
      if (!mounted) return;
      setState(() => _artikelOptionsByLine[lineId] = (res as List).cast<Map<String, dynamic>>());
    } catch (_) {
      if (!mounted) return;
      setState(() => _artikelOptionsByLine[lineId] = const []);
    }
  }

  Future<void> _openArtikelModal(String lineId) async {
    final res = await AppSupabase.client
        .from('artikelen')
        .select(
          'id, artikel_code, naam, eenheid, stukprijs_ex_btw, verkoop_btw_code, omschrijving_factuur, factuur_omschrijving, omschrijving_intern',
        )
        .order('artikel_code', ascending: true);
    final list = (res as List).cast<Map<String, dynamic>>();
    if (!mounted) return;

    final picked = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) {
        final search = TextEditingController();
        var filtered = List<Map<String, dynamic>>.from(list);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setLocal) {
                  void apply(String q) {
                    final needle = q.trim().toLowerCase();
                    setLocal(() {
                      filtered = needle.isEmpty
                          ? List<Map<String, dynamic>>.from(list)
                          : list
                              .where((a) {
                                final code = _text(a['artikel_code']).toLowerCase();
                                final naam = _text(a['naam']).toLowerCase();
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
                            child: Text('Selecteer artikel', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          ),
                          IconButton(onPressed: () => Navigator.of(context).pop(null), icon: const Icon(Icons.close)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: search,
                        decoration: _inputDeco('Zoeken...', icon: Icons.search),
                        onChanged: apply,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (context, i) {
                            final a = filtered[i];
                            final code = _text(a['artikel_code']);
                            final naam = _text(a['naam']);
                            final prijs = _asDouble(a['stukprijs_ex_btw']);
                            return ListTile(
                              title: Text([code, naam].where((s) => s.isNotEmpty).join(' — '),
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text('€ ${prijs.toStringAsFixed(2)}'),
                              onTap: () => Navigator.of(context).pop(a),
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
        );
      },
    );

    if (!mounted || picked == null) return;
    await _applyArtikelToLine(lineId, picked);
  }

  String _pickOmschrijving(Map<String, dynamic> a) {
    final candidates = [
      a['omschrijving_factuur'],
      a['factuur_omschrijving'],
      a['omschrijving_intern'],
      a['naam'],
    ];
    for (final c in candidates) {
      final s = (c ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
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
      l['stukprijs_ex_btw'] = _asDouble(artikel['stukprijs_ex_btw']);
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
      _vervalDatum = _factuurDatum.add(Duration(days: _betalingsTermijn));
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
  bool get _isValid {
    if (_selectedKlant == null) return false;
    if (_omschrijvingCtrl.text.trim().isEmpty) return false;
    if (_lines.isEmpty) return false;
    for (final l in _lines) {
      if (_text(l['artikel_id']).isEmpty) return false;
      if (_asDouble(l['aantal']) <= 0) return false;
      if (_asDouble(l['stukprijs_ex_btw']) <= 0) return false;
    }
    return true;
  }

  Future<void> _save({required bool closeAfter, required bool newAfter}) async {
    if (_saving) return;
    if (!_isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.withValues(alpha: 0.92),
          content: const Text('Vul klant, omschrijving en minimaal 1 geldige regel in.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final klantId = _text(_selectedKlant?['id']);
      final header = <String, dynamic>{
        'bedrijf_id': klantId,
        'status': 'concept',
        'factuur_datum': DateFormat('yyyy-MM-dd').format(_factuurDatum),
        'verval_datum': DateFormat('yyyy-MM-dd').format(_vervalDatum),
        'omschrijving': _omschrijvingCtrl.text.trim(),
        'layout_toon_aantallen': _toonAantallen,
        'layout_toon_prijzen': _toonPrijzen,
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
        });
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
          _klantCtrl.text = '';
          _omschrijvingCtrl.text = '';
          _betalingsTermijn = 14;
          _factuurDatum = DateTime.now();
          _vervalDatum = DateTime.now().add(const Duration(days: 14));
          for (final c in _lineCtrls.values) {
            c.dispose();
          }
          _lineCtrls.clear();
          _lines.clear();
          _artikelOptionsByLine.clear();
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

  Widget _miniInfo(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ', style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontWeight: FontWeight.w700)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
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
            child: Autocomplete<Map<String, dynamic>>(
              displayStringForOption: (o) {
                final aCode = _text(o['artikel_code']);
                final aNaam = _text(o['naam']);
                if (aCode.isNotEmpty && aNaam.isNotEmpty) return '$aCode — $aNaam';
                return aCode.isNotEmpty ? aCode : aNaam;
              },
              optionsBuilder: (t) {
                final q = t.text.trim().toLowerCase();
                if (q.isEmpty) return const Iterable<Map<String, dynamic>>.empty();
                final opts = _artikelOptionsByLine[id] ?? const [];
                return opts.where((o) {
                  final s = '${_text(o['artikel_code'])} ${_text(o['naam'])}'.toLowerCase();
                  return s.contains(q);
                });
              },
              onSelected: (artikel) async => _applyArtikelToLine(id, artikel),
              fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                if (controller.text != c.artikel.text) controller.value = c.artikel.value;
                return TextField(
                  controller: c.artikel,
                  focusNode: focusNode,
                  onEditingComplete: onEditingComplete,
                  decoration: _inputDeco(
                    'Artikel',
                    icon: Icons.search,
                    suffixIcon: IconButton(
                      tooltip: 'Lijst',
                      icon: const Icon(Icons.list),
                      onPressed: () => _openArtikelModal(id),
                    ),
                  ),
                  onChanged: (v) {
                    _markDirty();
                    _artikelDebounceByLine[id]?.cancel();
                    _artikelDebounceByLine[id] = Timer(const Duration(milliseconds: 250), () {
                      _fetchArtikelSuggestions(id, v);
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: TextField(
              controller: c.omschrijving,
              decoration: _inputDeco('Omschrijving'),
              onChanged: (v) {
                l['omschrijving'] = v;
                _markDirty();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: c.aantal,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            child: DropdownButtonFormField<String>(
              key: ValueKey(_text(l['btw_code'])),
              initialValue: _text(l['btw_code']).isEmpty ? null : _text(l['btw_code']),
              decoration: _inputDeco('BTW Code'),
              items: _btwCodes
                  .map((b) => DropdownMenuItem<String>(value: _text(b['code']), child: Text(_text(b['code']))))
                  .toList(growable: false),
              onChanged: (v) {
                final code = _text(v);
                l['btw_code'] = code;
                l['btw_percentage'] = _btwPctFor(code);
                _syncLinePricesWithVatMode(l);
                _markDirty();
                _calculateTotals();
              },
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
                _lines.removeAt(i);
                _lineCtrls.remove(id)?.dispose();
                _artikelOptionsByLine.remove(id);
                _artikelDebounceByLine.remove(id)?.cancel();
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

    final klantAdres = () {
      final k = _selectedKlant;
      if (k == null) return '';
      final parts = [
        _text(k['straat']),
        _text(k['huisnummer']),
        _text(k['postcode']),
        _text(k['plaats']),
      ].where((s) => s.isNotEmpty).toList();
      return parts.join(' ');
    }();
    final kvk = _text(_selectedKlant?['kvk']);

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
                            child: Autocomplete<Map<String, dynamic>>(
                              displayStringForOption: (o) => _text(o['bedrijfsnaam']),
                              optionsBuilder: (t) {
                                final q = t.text.trim().toLowerCase();
                                if (q.isEmpty) return const Iterable<Map<String, dynamic>>.empty();
                                return _klantOptions.where((o) => _text(o['bedrijfsnaam']).toLowerCase().contains(q));
                              },
                              onSelected: (k) => _applyKlant(k),
                              fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                                if (controller.text != _klantCtrl.text) controller.value = _klantCtrl.value;
                                return TextField(
                                  controller: _klantCtrl,
                                  focusNode: focusNode,
                                  onEditingComplete: onEditingComplete,
                                  decoration: _inputDeco(
                                    'Klant (Zoeken)',
                                    icon: Icons.search,
                                    suffixIcon: IconButton(
                                      tooltip: 'Lijst',
                                      icon: const Icon(Icons.list),
                                      onPressed: _openKlantModal,
                                    ),
                                  ),
                                  onChanged: (v) {
                                    _markDirty();
                                    _klantDebounce?.cancel();
                                    _klantDebounce = Timer(const Duration(milliseconds: 250), () {
                                      _fetchKlantSuggestions(v);
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                          _dateField('Factuurdatum', _factuurDatum, _pickFactuurDatum),
                          _dateField('Vervaldatum', _vervalDatum, _pickVervalDatum),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_selectedKlant != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(16)),
                          child: Wrap(
                            spacing: 18,
                            runSpacing: 8,
                            children: [
                              _miniInfo('Adres', klantAdres.isEmpty ? '—' : klantAdres),
                              _miniInfo('KVK', kvk.isEmpty ? '—' : kvk),
                              _miniInfo('Betalingstermijn', '$_betalingsTermijn dagen'),
                            ],
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
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: body,
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

