import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';

/// Generator: maandoverzicht abonnement vs. incidenteel vs. extra (buiten abonnement).
class FacturatieOverzichtScreen extends StatefulWidget {
  const FacturatieOverzichtScreen({super.key});

  @override
  State<FacturatieOverzichtScreen> createState() =>
      _FacturatieOverzichtScreenState();
}

class _FacturatieOverzichtScreenState extends State<FacturatieOverzichtScreen> {
  DateTime _geselecteerdeMaand =
      DateTime(DateTime.now().year, DateTime.now().month);

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _bedrijven = const [];
  List<Map<String, dynamic>> _offertesSigned = const [];
  List<Map<String, dynamic>> _planningRows = const [];
  List<Map<String, dynamic>> _klantFacturaties = const [];

  final _eur = NumberFormat.currency(
    locale: 'nl_NL',
    symbol: '€',
    decimalDigits: 2,
  );

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(' ', '');
    if (s.isEmpty) return 0;
    final d = double.tryParse(s);
    if (d != null) return d;
    if (s.contains(',')) {
      return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ??
          0;
    }
    return 0;
  }

  String _maandSleutel(DateTime m) =>
      '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}';

  String _maandLabelNl(DateTime m) {
    try {
      return DateFormat('MMMM yyyy', 'nl_NL').format(m);
    } catch (_) {
      return '${m.month}/${m.year}';
    }
  }

  DateTime? _parseDateOnly(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) {
      return DateTime(raw.year, raw.month, raw.day);
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final head = s.length >= 10 ? s.substring(0, 10) : s;
    return DateTime.tryParse(head);
  }

  bool _offerteActiefInMaand(
    Map<String, dynamic> o,
    DateTime monthFirst,
    DateTime monthLast,
  ) {
    final start = _parseDateOnly(o['contract_startdatum']);
    final end = _parseDateOnly(o['contract_einddatum']);
    if (start == null) return false;
    if (start.isAfter(monthLast)) return false;
    if (end != null && end.isBefore(monthFirst)) return false;
    return true;
  }

  /// Abonnement op offerte-niveau: maandprijs (frequentie staat op project/opdracht).
  bool _offerteTeltAlsAbonnement(Map<String, dynamic> o) {
    return _asDouble(o['maandprijs_ex_btw']) > 0;
  }

  bool _planningInSelectedMonth(Map<String, dynamic> row) {
    final raw = row['geplande_datum'];
    final d = _parseDateOnly(raw);
    if (d == null) return false;
    return d.year == _geselecteerdeMaand.year &&
        d.month == _geselecteerdeMaand.month;
  }

  String? _bedrijfIdVanPlanning(Map<String, dynamic> row) {
    final op = row['opdracht'];
    if (op is! Map) return null;
    final m = Map<String, dynamic>.from(op);
    final project = m['project'];
    if (project is! Map) return null;
    final bid = Map<String, dynamic>.from(project)['bedrijf_id'];
    final id = _text(bid);
    return id.isEmpty ? null : id;
  }

  String _freqVanOpdracht(Map<String, dynamic> opMap) {
    return _text(opMap['frequentie_type']).toLowerCase();
  }

  bool _isBuitenAbonnement(Map<String, dynamic> opMap) {
    final v = opMap['is_buiten_abonnement'];
    if (v is bool) return v;
    final s = _text(v).toLowerCase();
    return s == 'true' || s == '1' || s == 'ja';
  }

  double _planningRegelWaardeExBtw(Map<String, dynamic> row) {
    final op = row['opdracht'];
    if (op is! Map) return 0;
    final opMap = Map<String, dynamic>.from(op);
    final vast = _asDouble(opMap['opdracht_waarde_ex_btw']);
    if (vast > 0) return vast;
    final uren = _asDouble(row['gewerkte_uren_decimaal']);
    final project = opMap['project'];
    double tarief = 0;
    if (project is Map) {
      tarief = _asDouble(
        Map<String, dynamic>.from(project)['vastgelegd_uurtarief'],
      );
    }
    if (uren > 0 && tarief > 0) return uren * tarief;
    final vasteBeurt = _asDouble(opMap['vaste_prijs_per_beurt']);
    if (vasteBeurt > 0) return vasteBeurt;
    return 0;
  }

  Map<String, Map<String, dynamic>> _facturatiesByBedrijf() {
    final out = <String, Map<String, dynamic>>{};
    for (final r in _klantFacturaties) {
      final id = _text(r['bedrijf_id']);
      if (id.isNotEmpty) out[id] = Map<String, dynamic>.from(r);
    }
    return out;
  }

  ({double abonnement, double incidenteel, double extra, double totaal})
      _berekenVoorBedrijf(String bedrijfId) {
    var abonnement = 0.0;
    for (final o in _offertesSigned) {
      if (_text(o['bedrijf_id']) != bedrijfId) continue;
      final monthFirst =
          DateTime(_geselecteerdeMaand.year, _geselecteerdeMaand.month);
      final monthLast =
          DateTime(_geselecteerdeMaand.year, _geselecteerdeMaand.month + 1, 0);
      if (!_offerteActiefInMaand(o, monthFirst, monthLast)) continue;
      if (!_offerteTeltAlsAbonnement(o)) continue;
      abonnement += _asDouble(o['maandprijs_ex_btw']);
    }

    var incidenteel = 0.0;
    var extra = 0.0;
    for (final row in _planningRows) {
      if (!_planningInSelectedMonth(row)) continue;
      if (_bedrijfIdVanPlanning(row) != bedrijfId) continue;
      final op = row['opdracht'];
      if (op is! Map) continue;
      final opMap = Map<String, dynamic>.from(op);
      final waarde = _planningRegelWaardeExBtw(row);
      if (waarde <= 0) continue;

      if (_isBuitenAbonnement(opMap)) {
        final korting = _asDouble(opMap['korting_bedrag']);
        extra += (waarde - korting).clamp(0.0, double.infinity);
      } else if (_freqVanOpdracht(opMap) == 'incidenteel') {
        incidenteel += waarde;
      }
    }

    final totaal = abonnement + incidenteel + extra;
    return (
      abonnement: abonnement,
      incidenteel: incidenteel,
      extra: extra,
      totaal: totaal,
    );
  }

  String _statusVoorBedrijf(
    String bedrijfId,
    Map<String, Map<String, dynamic>> factMap,
  ) {
    final row = factMap[bedrijfId];
    final s = _text(row?['status']).toLowerCase();
    if (s == 'gefactureerd' || s == 'betaald' || s == 'concept') return s;
    return 'concept';
  }

  Future<void> _fetchFacturatieData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final sleutel = _maandSleutel(_geselecteerdeMaand);

    try {
      final bedrijvenRes = await AppSupabase.client.from('bedrijven').select();
      final offertesRes = await AppSupabase.client
          .from('offertes')
          .select(
            'id, bedrijf_id, status, '
            'contract_startdatum, contract_einddatum, maandprijs_ex_btw',
          )
          .eq('status', 'signed');

      final planningRes = await AppSupabase.client
          .from('opdracht_planning')
          .select(
            'id, geplande_datum, uren_status, gewerkte_uren_decimaal, '
            'opdracht:opdrachten!opdracht_planning_opdracht_id_fkey('
            'id, frequentie_type, is_buiten_abonnement, opdracht_waarde_ex_btw, '
            'vaste_prijs_per_beurt, korting_bedrag,'
            'project:projecten(bedrijf_id, vastgelegd_uurtarief))',
          )
          .eq('uren_status', 'geaccordeerd');

      List<Map<String, dynamic>> factRows = const [];
      try {
        final f = await AppSupabase.client
            .from('klant_facturaties')
            .select()
            .eq('maand_sleutel', sleutel);
        factRows = (f as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (e) {
        debugPrint('klant_facturaties (optioneel): $e');
        factRows = const [];
      }

      final bedrijven = (bedrijvenRes as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final offertes = (offertesRes as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final planning = (planningRes as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (!mounted) return;
      setState(() {
        _bedrijven = bedrijven;
        _offertesSigned = offertes;
        _planningRows = planning;
        _klantFacturaties = factRows;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('FacturatieOverzichtScreen._fetchFacturatieData: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _upsertFacturatieStatus({
    required String bedrijfId,
    required String nieuweStatus,
    required double abonnement,
    required double incidenteel,
    required double extra,
    required double totaal,
  }) async {
    final sleutel = _maandSleutel(_geselecteerdeMaand);
    try {
      await AppSupabase.client.from('klant_facturaties').upsert(
        {
          'bedrijf_id': bedrijfId,
          'maand_sleutel': sleutel,
          'berekend_abonnement': abonnement,
          'berekend_incidenteel': incidenteel,
          'berekend_extra': extra,
          'totaal_ex_btw': totaal,
          'status': nieuweStatus,
        },
        onConflict: 'bedrijf_id,maand_sleutel',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Status opgeslagen: $nieuweStatus',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
      await _fetchFacturatieData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade800,
          content: Text(
            'Opslaan mislukt: $e',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchFacturatieData();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final factMap = _facturatiesByBedrijf();

    final rijen = <({
      String id,
      String naam,
      double abonnement,
      double incidenteel,
      double extra,
      double totaal,
    })>[];

    for (final b in _bedrijven) {
      final id = _text(b['id']);
      if (id.isEmpty) continue;
      final calc = _berekenVoorBedrijf(id);
      if (calc.totaal <= 0.0001) continue;
      rijen.add((
        id: id,
        naam: _text(b['bedrijfsnaam']).isEmpty ? 'Onbekend' : _text(b['bedrijfsnaam']),
        abonnement: calc.abonnement,
        incidenteel: calc.incidenteel,
        extra: calc.extra,
        totaal: calc.totaal,
      ));
    }

    var verwachtOmzet = 0.0;
    var somGefactureerd = 0.0;
    var somBetaald = 0.0;
    for (final r in rijen) {
      verwachtOmzet += r.totaal;
      final st = _statusVoorBedrijf(r.id, factMap);
      if (st == 'gefactureerd') somGefactureerd += r.totaal;
      if (st == 'betaald') somBetaald += r.totaal;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Facturatieoverzicht',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: _loading ? null : _fetchFacturatieData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SelectionArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: Colors.red.shade800),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Vorige maand',
                        onPressed: () {
                          setState(() {
                            _geselecteerdeMaand = DateTime(
                              _geselecteerdeMaand.year,
                              _geselecteerdeMaand.month - 1,
                            );
                          });
                          _fetchFacturatieData();
                        },
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          _maandLabelNl(_geselecteerdeMaand),
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Volgende maand',
                        onPressed: () {
                          setState(() {
                            _geselecteerdeMaand = DateTime(
                              _geselecteerdeMaand.year,
                              _geselecteerdeMaand.month + 1,
                            );
                          });
                          _fetchFacturatieData();
                        },
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _kpiCard(
                          cs,
                          'Verwachte omzet',
                          _eur.format(verwachtOmzet),
                          Icons.trending_up_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _kpiCard(
                          cs,
                          'Gefactureerd',
                          _eur.format(somGefactureerd),
                          Icons.receipt_long_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _kpiCard(
                          cs,
                          'Betaald',
                          _eur.format(somBetaald),
                          Icons.payments_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (rijen.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Geen facturabele posten voor deze maand.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    )
                  else
                    ...rijen.map((r) {
                      final status = _statusVoorBedrijf(r.id, factMap);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: cs.onSurface.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r.naam,
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _eur.format(r.totaal),
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Vaste abonnementen: ${_eur.format(r.abonnement)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: cs.onSurface.withValues(alpha: 0.72),
                                  ),
                                ),
                                Text(
                                  'Incidentele klussen: ${_eur.format(r.incidenteel)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: cs.onSurface.withValues(alpha: 0.72),
                                  ),
                                ),
                                Text(
                                  'Extra / buiten abonnement: ${_eur.format(r.extra)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: cs.onSurface.withValues(alpha: 0.72),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'concept',
                                      label: Text('Concept'),
                                    ),
                                    ButtonSegment(
                                      value: 'gefactureerd',
                                      label: Text('Gefactureerd'),
                                    ),
                                    ButtonSegment(
                                      value: 'betaald',
                                      label: Text('Betaald'),
                                    ),
                                  ],
                                  selected: {status},
                                  onSelectionChanged: (set) {
                                    final v = set.first;
                                    _upsertFacturatieStatus(
                                      bedrijfId: r.id,
                                      nieuweStatus: v,
                                      abonnement: r.abonnement,
                                      incidenteel: r.incidenteel,
                                      extra: r.extra,
                                      totaal: r.totaal,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }

  Widget _kpiCard(
    ColorScheme cs,
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: cs.primary),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
