import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';

/// Bulk facturatie: concept-run met preview/selectie, daarna definitief genereren.
class InvoiceBulkRunScreen extends StatefulWidget {
  const InvoiceBulkRunScreen({super.key});

  @override
  State<InvoiceBulkRunScreen> createState() => _InvoiceBulkRunScreenState();
}

class _InvoiceBulkRunScreenState extends State<InvoiceBulkRunScreen> {
  static const int _betalingsTermijnDagen = 14;

  DateTime _geselecteerdeMaand = DateTime(
    DateTime.now().year,
    DateTime.now().month - 1,
    1,
  );
  String? _geselecteerdeKlantId;
  String? _geselecteerdeKlantNaam;
  List<Map<String, dynamic>> _klantenLijst = [];
  List<Map<String, dynamic>> _klantenStatusLijst = [];
  int _analyticsTeFactureren = 0;
  int _analyticsGefactureerd = 0;
  int _analyticsTotaalKlanten = 0;
  bool _isLoading = true;
  bool _isDefinitiefBezig = false;
  String? _loadError;

  List<Map<String, dynamic>> _offertesSigned = [];
  List<Map<String, dynamic>> _planningRows = [];
  List<Map<String, dynamic>> _conceptFacturen = [];
  /// Elk bedrijf met een rij in klant_facturaties voor de maand (concept, gefactureerd, …).
  Set<String> _trackerBedrijfIdsMaand = {};
  /// Alleen status gefactureerd/betaald (analytics-kaart).
  Set<String> _gefactureerdStatusBedrijfIds = {};

  String? _defaultBtwCode;
  double _defaultBtwPct = 21;
  String? _fallbackArtikelId;

  final _eur = NumberFormat.currency(
    locale: 'nl_NL',
    symbol: '€',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadBasisGegevens();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(' ', '');
    if (s.isEmpty) return 0;
    final d = double.tryParse(s);
    if (d != null) return d;
    if (s.contains(',')) {
      return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  String _maandSleutel(DateTime m) =>
      '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}';

  bool get _isMaandVoorbij {
    final nu = DateTime.now();
    return _geselecteerdeMaand.year < nu.year ||
        (_geselecteerdeMaand.year == nu.year &&
            _geselecteerdeMaand.month < nu.month);
  }

  String _maandLabelNl(DateTime m) {
    try {
      return DateFormat('MMMM yyyy', 'nl_NL').format(m);
    } catch (_) {
      return '${m.month}/${m.year}';
    }
  }

  DateTime? _parseDateOnly(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);
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
    final d = _parseDateOnly(row['geplande_datum']);
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
    final id = _text(Map<String, dynamic>.from(project)['bedrijf_id']);
    return id.isEmpty ? null : id;
  }

  bool _isBuitenAbonnement(Map<String, dynamic> opMap) {
    final v = opMap['is_buiten_abonnement'];
    if (v is bool) return v;
    final s = _text(v).toLowerCase();
    return s == 'true' || s == '1' || s == 'ja';
  }

  bool _opdrachtAlGefactureerd(Map<String, dynamic> opMap) {
    final fid = opMap['factuur_id'];
    if (fid == null) return false;
    return _text(fid).isNotEmpty;
  }

  bool _projectHeeftAbonnement(dynamic project) {
    if (project is! Map) return false;
    final oid = Map<String, dynamic>.from(project)['offerte_id'];
    if (oid == null) return false;
    return _text(oid).isNotEmpty;
  }

  /// Basisbedrag vóór korting: opdracht_waarde → vaste_prijs_per_beurt → uren × tarief.
  double _basisWaardeVanOpdracht(Map<String, dynamic> opMap) {
    var waarde = _asDouble(opMap['opdracht_waarde_ex_btw']);
    if (waarde <= 0) waarde = _asDouble(opMap['vaste_prijs_per_beurt']);
    if (waarde <= 0) {
      final uren = _asDouble(opMap['verwachte_uren_totaal']);
      final project = opMap['project'];
      var tarief = 0.0;
      if (project is Map) {
        tarief = _asDouble(
          Map<String, dynamic>.from(project)['vastgelegd_uurtarief'],
        );
      }
      waarde = uren * tarief;
    }
    return waarde;
  }

  double _definitiefBedragVanOpdracht(Map<String, dynamic> opMap) {
    final korting = _asDouble(opMap['korting_bedrag']);
    return (_basisWaardeVanOpdracht(opMap) - korting).clamp(0.0, double.infinity);
  }

  Future<({Set<String> trackerIds, Set<String> gefactureerdStatusIds})>
      _laadFacturatieTrackerVoorMaand(String maandSleutel) async {
    final trackerIds = <String>{};
    final gefactureerdStatusIds = <String>{};
    try {
      final facturatiesRes = await AppSupabase.client
          .from('klant_facturaties')
          .select('bedrijf_id, status')
          .eq('maand_sleutel', maandSleutel);
      for (final row in facturatiesRes as List) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        final id = _text(m['bedrijf_id']);
        if (id.isEmpty) continue;
        trackerIds.add(id);
        final s = _text(m['status']).toLowerCase();
        if (s == 'gefactureerd' || s == 'betaald') {
          gefactureerdStatusIds.add(id);
        }
      }
    } catch (e) {
      debugPrint('klant_facturaties (tracker): $e');
    }
    return (trackerIds: trackerIds, gefactureerdStatusIds: gefactureerdStatusIds);
  }

  /// Abonnement, incidenteel, extra per klant + regels (zelfde logica als concept-run).
  ({
    double abonnement,
    double incidenteel,
    double extra,
    double totaal,
    List<Map<String, dynamic>> regels,
  }) _facturatieVoorKlant(
    String bedrijfId, {
    required DateTime monthFirst,
    required DateTime monthLast,
    required String maandLabel,
    Set<String>? reedsGefactureerdeIds,
  }) {
    final geblokkeerd = reedsGefactureerdeIds ?? _trackerBedrijfIdsMaand;
    if (geblokkeerd.contains(bedrijfId)) {
      return (
        abonnement: 0.0,
        incidenteel: 0.0,
        extra: 0.0,
        totaal: 0.0,
        regels: <Map<String, dynamic>>[],
      );
    }

    double abonnementBedrag = 0.0;
    double incidenteelBedrag = 0.0;
    double extraBedrag = 0.0;
    final regels = <Map<String, dynamic>>[];
    final incidenteelVerwerkt = <String>{};
    final extraVerwerkt = <String>{};

    for (final o in _offertesSigned) {
      if (_text(o['bedrijf_id']) != bedrijfId) continue;
      if (!_offerteActiefInMaand(o, monthFirst, monthLast)) continue;
      if (!_offerteTeltAlsAbonnement(o)) continue;
      abonnementBedrag += _asDouble(o['maandprijs_ex_btw']);
    }

    if (abonnementBedrag > 0) {
      regels.add({
        'omschrijving': 'Abonnement $maandLabel',
        'bedrag': abonnementBedrag,
        'aantal': 1.0,
      });
    }

    for (final row in _planningRows) {
      if (!_planningInSelectedMonth(row)) continue;
      if (_bedrijfIdVanPlanning(row) != bedrijfId) continue;
      final op = row['opdracht'];
      if (op is! Map) continue;
      final opMap = Map<String, dynamic>.from(op);
      if (_opdrachtAlGefactureerd(opMap)) continue;

      final heeftAbonnement = _projectHeeftAbonnement(opMap['project']);
      final isExtra = _isBuitenAbonnement(opMap);
      final freqType = _text(opMap['frequentie_type']).toLowerCase();
      final isIncidenteel = freqType == 'incidenteel' || freqType == 'eenmalig';

      if (heeftAbonnement && !isExtra && !isIncidenteel) continue;

      final definitiefBedrag = _definitiefBedragVanOpdracht(opMap);
      if (definitiefBedrag <= 0) continue;

      final opdrachtId = _text(opMap['id']);
      var projectNaam = _text(opMap['bedrijfsnaam']);
      final project = opMap['project'];
      if (project is Map) {
        final pn = _text(Map<String, dynamic>.from(project)['project_naam']);
        if (pn.isNotEmpty) projectNaam = pn;
      }
      final datum = _parseDateOnly(row['geplande_datum']);
      final datumStr = datum != null
          ? DateFormat('dd-MM-yyyy').format(datum)
          : _text(row['geplande_datum']);

      if (isExtra || (!heeftAbonnement && !isIncidenteel)) {
        if (opdrachtId.isNotEmpty && extraVerwerkt.contains(opdrachtId)) continue;
        if (opdrachtId.isNotEmpty) extraVerwerkt.add(opdrachtId);
        extraBedrag += definitiefBedrag;
        regels.add({
          'omschrijving': 'Extra werk $datumStr — $projectNaam',
          'bedrag': definitiefBedrag,
          'aantal': 1.0,
          'planning_id': _text(row['id']),
          'opdracht_id': opdrachtId,
        });
      } else {
        if (opdrachtId.isNotEmpty && incidenteelVerwerkt.contains(opdrachtId)) {
          continue;
        }
        if (opdrachtId.isNotEmpty) incidenteelVerwerkt.add(opdrachtId);
        incidenteelBedrag += definitiefBedrag;
        regels.add({
          'omschrijving': 'Incidenteel werk $datumStr — $projectNaam',
          'bedrag': definitiefBedrag,
          'aantal': 1.0,
          'planning_id': _text(row['id']),
          'opdracht_id': opdrachtId,
        });
      }
    }

    final totaalBedrag = abonnementBedrag + incidenteelBedrag + extraBedrag;
    return (
      abonnement: abonnementBedrag,
      incidenteel: incidenteelBedrag,
      extra: extraBedrag,
      totaal: totaalBedrag,
      regels: regels,
    );
  }

  Future<void> _upsertKlantFacturatieTracker({
    required Map<String, dynamic> concept,
    required String maandSleutel,
  }) async {
    final klantId = _text(concept['klant_id']);
    if (klantId.isEmpty) return;
    try {
      await AppSupabase.client.from('klant_facturaties').upsert(
        {
          'bedrijf_id': klantId,
          'maand_sleutel': maandSleutel,
          'berekend_abonnement': _asDouble(concept['abonnement']),
          'berekend_incidenteel': _asDouble(concept['incidenteel']),
          'berekend_extra': _asDouble(concept['extra']),
          'totaal_ex_btw': _asDouble(concept['bedrag']),
          'status': 'gefactureerd',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'bedrijf_id,maand_sleutel',
      );
    } catch (e) {
      debugPrint(
        'Fout bij klant_facturaties voor ${concept['bedrijfsnaam']}: $e',
      );
    }
  }

  void _berekenKlantenStatus({
    required List<Map<String, dynamic>> bedrijven,
    required List<Map<String, dynamic>> facturaties,
  }) {
    final monthFirst =
        DateTime(_geselecteerdeMaand.year, _geselecteerdeMaand.month);
    final monthLast =
        DateTime(_geselecteerdeMaand.year, _geselecteerdeMaand.month + 1, 0);

    final maandLabel = _maandLabelNl(_geselecteerdeMaand);
    final trackerIds = _trackerBedrijfIdsMaand.isNotEmpty
        ? _trackerBedrijfIdsMaand
        : facturaties.map((f) => _text(f['bedrijf_id'])).where((id) => id.isNotEmpty).toSet();
    final facturenRes = facturaties;

    var teFactureren = 0;
    var gefactureerd = 0;
    final statusLijst = <Map<String, dynamic>>[];

    for (final bedrijf in bedrijven) {
      final bedrijfId = _text(bedrijf['id']);
      if (bedrijfId.isEmpty) continue;
      final bNaam = _text(bedrijf['bedrijfsnaam']);

      final bedragen = _facturatieVoorKlant(
        bedrijfId,
        monthFirst: monthFirst,
        monthLast: monthLast,
        maandLabel: maandLabel,
        reedsGefactureerdeIds: trackerIds,
      );
      final heeftOmzet = bedragen.totaal > 0;
      const heeftOnverwerkteUren = false;

      String statusType = 'geen_omzet';
      String statusTekst = 'Geen werk deze maand';

      Map<String, dynamic>? factuurTracker;
      for (final f in facturenRes) {
        if (_text(f['bedrijf_id']) == bedrijfId) {
          factuurTracker = f;
          break;
        }
      }

      if (factuurTracker != null) {
        final dbStatus = factuurTracker['status']?.toString().toLowerCase();

        if (dbStatus == 'concept') {
          statusType = 'concept';
          statusTekst = 'Concept al gegenereerd voor deze maand';
        } else {
          statusType = 'gefactureerd';
          statusTekst = 'Reeds definitief gefactureerd';
        }
        gefactureerd++;
      // ignore: dead_code — klaar voor uren-accordering zodra planning uren_status meelevert
      } else if (heeftOnverwerkteUren) {
        statusType = 'blokkade';
        statusTekst = 'Wacht op uren-accordering';
      } else if (heeftOmzet) {
        statusType = 'klaar';
        statusTekst = 'Klaar voor facturatie';
        teFactureren++;
      }

      statusLijst.add({
        'id': bedrijfId,
        'naam': bNaam,
        'status_type': statusType,
        'status_tekst': statusTekst,
      });
    }

    statusLijst.sort((a, b) => _text(a['naam']).compareTo(_text(b['naam'])));

    _klantenStatusLijst = statusLijst;
    _analyticsTeFactureren = teFactureren;
    _analyticsGefactureerd = gefactureerd;
    _analyticsTotaalKlanten = bedrijven.length;
  }

  Color _statusSubtitleColor(String statusType) {
    switch (statusType) {
      case 'klaar':
        return Colors.green.shade800;
      case 'concept':
        return Colors.orange.shade800;
      case 'blokkade':
        return Colors.red.shade700;
      case 'gefactureerd':
        return Colors.blue.shade700;
      default:
        return Colors.grey.shade500;
    }
  }

  Future<void> _toonKlantZoekModal() async {
    var zoekTerm = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final gefilterd = _klantenStatusLijst.where((b) {
              if (zoekTerm.isEmpty) return true;
              return _text(b['naam']).toLowerCase().contains(zoekTerm.toLowerCase());
            }).toList();

            return SelectionArea(
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text('Selecteer klant voor facturatie'),
                content: SizedBox(
                  width: 560,
                  height: 440,
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
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.all_inclusive, color: Colors.blue),
                              title: const Text(
                                'Alle factureerbare klanten',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: const Text(
                                'Genereer facturen voor iedereen die klaar is.',
                              ),
                              onTap: () {
                                Navigator.of(dialogContext).pop();
                                setState(() {
                                  _geselecteerdeKlantId = null;
                                  _geselecteerdeKlantNaam = 'Alle factureerbare klanten';
                                  _conceptFacturen = [];
                                });
                              },
                            ),
                            const Divider(),
                            if (gefilterd.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: Text('Geen klanten gevonden.')),
                              )
                            else
                              ...gefilterd.map((klant) {
                                final id = _text(klant['id']);
                                final statusType = _text(klant['status_type']);
                                final isKlaar = statusType == 'klaar';
                                final statusTekst = _text(klant['status_tekst']);

                                Color statusKleur = Colors.grey;
                                IconData statusIcon = Icons.info_outline;

                                if (isKlaar) {
                                  statusKleur = Colors.green;
                                  statusIcon = Icons.check_circle;
                                } else if (klant['status_type'] == 'concept') {
                                  statusKleur = Colors.orange;
                                  statusIcon = Icons.file_copy;
                                } else if (klant['status_type'] == 'blokkade') {
                                  statusKleur = Colors.red;
                                  statusIcon = Icons.warning;
                                } else if (klant['status_type'] == 'gefactureerd') {
                                  statusKleur = Colors.blue;
                                  statusIcon = Icons.receipt;
                                }

                                return ListTile(
                                  enabled: isKlaar,
                                  leading: Icon(statusIcon, color: statusKleur),
                                  title: Text(
                                    _text(klant['naam']).isEmpty ? 'Onbekend' : _text(klant['naam']),
                                    style: TextStyle(
                                      fontWeight: isKlaar ? FontWeight.bold : FontWeight.normal,
                                      color: isKlaar ? Colors.black87 : Colors.grey.shade500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    statusTekst.isEmpty ? 'Status onbekend' : statusTekst,
                                    style: TextStyle(
                                      color: _statusSubtitleColor(statusType),
                                      fontWeight: isKlaar ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                  onTap: isKlaar
                                      ? () {
                                          Navigator.of(dialogContext).pop();
                                          setState(() {
                                            _geselecteerdeKlantId = id;
                                            _geselecteerdeKlantNaam = _text(klant['naam']);
                                            _conceptFacturen = [];
                                          });
                                        }
                                      : null,
                                );
                              }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Sluiten'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _klantPassesFilter(String klantId) {
    if (_geselecteerdeKlantId == null) return true;
    return klantId == _geselecteerdeKlantId;
  }

  Future<void> _loadBasisGegevens() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _conceptFacturen = [];
    });

    final maandSleutel = _maandSleutel(_geselecteerdeMaand);
    final startMaand = DateTime(
      _geselecteerdeMaand.year,
      _geselecteerdeMaand.month,
      1,
    );
    final eindMaand = DateTime(
      _geselecteerdeMaand.year,
      _geselecteerdeMaand.month + 1,
      0,
      23,
      59,
      59,
    );

    try {
      final tracker = await _laadFacturatieTrackerVoorMaand(maandSleutel);
      _trackerBedrijfIdsMaand = tracker.trackerIds;
      _gefactureerdStatusBedrijfIds = tracker.gefactureerdStatusIds;

      final bedrijvenRes = await AppSupabase.client
          .from('bedrijven')
          .select('id, bedrijfsnaam, is_actief')
          .order('bedrijfsnaam', ascending: true);

      final offertesRes = await AppSupabase.client
          .from('offertes')
          .select(
            'id, bedrijf_id, status, '
            'contract_startdatum, contract_einddatum, maandprijs_ex_btw',
          )
          .eq('status', 'signed');

      final planningRes = await AppSupabase.client
          .from('opdracht_planning')
          .select('''
            id, status, geplande_datum,
            opdracht:opdrachten!opdracht_planning_opdracht_id_fkey(
              id, bedrijfsnaam, frequentie_type, is_buiten_abonnement,
              opdracht_waarde_ex_btw, vaste_prijs_per_beurt, korting_bedrag,
              factuur_id, verwachte_uren_totaal,
              project:projecten(bedrijf_id, project_naam, vastgelegd_uurtarief, offerte_id)
            )
          ''')
          .gte('geplande_datum', startMaand.toIso8601String())
          .lte('geplande_datum', eindMaand.toIso8601String())
          .neq('status', 'geannuleerd');

      final facturaties = _trackerBedrijfIdsMaand
          .map(
            (id) => {
              'bedrijf_id': id,
              'status': _gefactureerdStatusBedrijfIds.contains(id)
                  ? 'gefactureerd'
                  : 'concept',
            },
          )
          .toList();

      final btwRes = await AppSupabase.client
          .from('fiscale_btw_codes')
          .select('code, percentage')
          .order('percentage', ascending: false)
          .limit(1);

      final artRes = await AppSupabase.client
          .from('artikelen')
          .select('id')
          .limit(1);

      if (!mounted) return;

      final klanten = (bedrijvenRes as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((b) {
            final actief = b['is_actief'];
            if (actief is bool && !actief) return false;
            return _text(b['bedrijfsnaam']).isNotEmpty;
          })
          .toList();

      final btwList = btwRes as List;
      if (btwList.isNotEmpty) {
        final b = Map<String, dynamic>.from(btwList.first as Map);
        _defaultBtwCode = _text(b['code']);
        _defaultBtwPct = _asDouble(b['percentage']);
      }
      final artList = artRes as List;
      if (artList.isNotEmpty) {
        _fallbackArtikelId = _text(
          Map<String, dynamic>.from(artList.first as Map)['id'],
        );
      }

      final offertes = (offertesRes as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final planningLijst = (planningRes as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      _offertesSigned = offertes;
      _planningRows = planningLijst;
      _berekenKlantenStatus(
        bedrijven: klanten,
        facturaties: facturaties,
      );

      if (!mounted) return;
      setState(() {
        _klantenLijst = klanten;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.toString();
      });
    }
  }

  void _verschuifMaand(int delta) {
    setState(() {
      _geselecteerdeMaand = DateTime(
        _geselecteerdeMaand.year,
        _geselecteerdeMaand.month + delta,
      );
      _conceptFacturen = [];
      _geselecteerdeKlantId = null;
      _geselecteerdeKlantNaam = 'Alle factureerbare klanten';
    });
    _loadBasisGegevens();
  }

  Future<void> _genereerConceptRun() async {
    setState(() {
      _isLoading = true;
      _conceptFacturen = [];
    });

    try {
      final maandSleutel = _maandSleutel(_geselecteerdeMaand);
      final maandLabel = _maandLabelNl(_geselecteerdeMaand);
      final startMaand =
          DateTime(_geselecteerdeMaand.year, _geselecteerdeMaand.month, 1)
              .toIso8601String();
      final eindMaand = DateTime(
        _geselecteerdeMaand.year,
        _geselecteerdeMaand.month + 1,
        0,
        23,
        59,
        59,
      ).toIso8601String();

      final facturatiesRes = await AppSupabase.client
          .from('klant_facturaties')
          .select('bedrijf_id')
          .eq('maand_sleutel', maandSleutel);
      final reedsGefactureerdeIds = (facturatiesRes as List)
          .whereType<Map>()
          .map((f) => _text(f['bedrijf_id']))
          .where((id) => id.isNotEmpty)
          .toList();
      _trackerBedrijfIdsMaand = reedsGefactureerdeIds.toSet();

      final bedrijvenRes = await AppSupabase.client
          .from('bedrijven')
          .select('id, bedrijfsnaam');

      final actieveOffertesRes = await AppSupabase.client
          .from('offertes')
          .select(
            'id, bedrijf_id, maandprijs_ex_btw, contract_startdatum, contract_einddatum',
          )
          .eq('status', 'signed');
      final actieveOffertes = (actieveOffertesRes as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final planningRes = await AppSupabase.client
          .from('opdracht_planning')
          .select('''
            id, status, geplande_datum,
            opdracht:opdrachten!opdracht_planning_opdracht_id_fkey(
              id, bedrijfsnaam, frequentie_type, is_buiten_abonnement,
              opdracht_waarde_ex_btw, vaste_prijs_per_beurt, factuur_id,
              verwachte_uren_totaal,
              project:projecten(bedrijf_id, project_naam, vastgelegd_uurtarief, offerte_id)
            )
          ''')
          .gte('geplande_datum', startMaand)
          .lte('geplande_datum', eindMaand)
          .neq('status', 'geannuleerd');

      final planningLijst = (planningRes as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _offertesSigned = actieveOffertes;
      _planningRows = planningLijst;

      final nieuweConceptLijst = <Map<String, dynamic>>[];

      for (final bedrijfRaw in bedrijvenRes as List) {
        if (bedrijfRaw is! Map) continue;
        final bedrijf = Map<String, dynamic>.from(bedrijfRaw);
        final bedrijfId = _text(bedrijf['id']);
        if (bedrijfId.isEmpty || !_klantPassesFilter(bedrijfId)) continue;

        if (reedsGefactureerdeIds.contains(bedrijfId)) continue;

        double abonnementBedrag = 0.0;
        double incidenteelBedrag = 0.0;
        double extraBedrag = 0.0;
        final regels = <Map<String, dynamic>>[];

        final bedrijfsOffertes = actieveOffertes
            .where((o) => _text(o['bedrijf_id']) == bedrijfId)
            .toList();
        for (final o in bedrijfsOffertes) {
          abonnementBedrag +=
              double.tryParse(o['maandprijs_ex_btw']?.toString() ?? '0') ?? 0.0;
        }
        if (abonnementBedrag > 0) {
          regels.add({
            'omschrijving': 'Abonnement $maandLabel',
            'bedrag': abonnementBedrag,
            'aantal': 1.0,
          });
        }

        final bedrijfsPlanningen = planningLijst.where((p) {
          final op = p['opdracht'];
          if (op is! Map) return false;
          final project = Map<String, dynamic>.from(op)['project'];
          if (project is! Map) return false;
          return _text(Map<String, dynamic>.from(project)['bedrijf_id']) ==
              bedrijfId;
        }).toList();

        for (final taak in bedrijfsPlanningen) {
          final opdracht = taak['opdracht'];
          if (opdracht is! Map) continue;
          final opMap = Map<String, dynamic>.from(opdracht);

          if (opMap['factuur_id'] != null && _text(opMap['factuur_id']).isNotEmpty) {
            continue;
          }

          final isExtra = opMap['is_buiten_abonnement'] == true;
          final freqType = _text(opMap['frequentie_type']).toLowerCase();
          final isIncidenteel =
              freqType == 'incidenteel' || freqType == 'eenmalig';
          final project = opMap['project'];
          final heeftAbonnement = project is Map &&
              _text(Map<String, dynamic>.from(project)['offerte_id']).isNotEmpty;

          if (heeftAbonnement && !isIncidenteel && !isExtra) continue;

          double waarde =
              double.tryParse(opMap['opdracht_waarde_ex_btw']?.toString() ?? '0') ??
                  0.0;
          if (waarde <= 0.0) {
            waarde = double.tryParse(
                  opMap['vaste_prijs_per_beurt']?.toString() ?? '0',
                ) ??
                0.0;
          }
          if (waarde <= 0.0) {
            final uren = double.tryParse(
                  opMap['verwachte_uren_totaal']?.toString() ?? '0',
                ) ??
                0.0;
            var tarief = 0.0;
            if (project is Map) {
              tarief = double.tryParse(
                    Map<String, dynamic>.from(project)['vastgelegd_uurtarief']
                        ?.toString() ??
                    '0',
                  ) ??
                  0.0;
            }
            waarde = uren * tarief;
          }

          if (waarde <= 0) continue;

          var projectNaam = _text(opMap['bedrijfsnaam']);
          if (project is Map) {
            final pn =
                _text(Map<String, dynamic>.from(project)['project_naam']);
            if (pn.isNotEmpty) projectNaam = pn;
          }
          final datum = _parseDateOnly(taak['geplande_datum']);
          final datumStr = datum != null
              ? DateFormat('dd-MM-yyyy').format(datum)
              : _text(taak['geplande_datum']);

          if (isExtra || (!heeftAbonnement && !isIncidenteel)) {
            extraBedrag += waarde;
            regels.add({
              'omschrijving': 'Extra werk $datumStr — $projectNaam',
              'bedrag': waarde,
              'aantal': 1.0,
              'planning_id': _text(taak['id']),
              'opdracht_id': _text(opMap['id']),
            });
          } else {
            incidenteelBedrag += waarde;
            regels.add({
              'omschrijving': 'Incidenteel werk $datumStr — $projectNaam',
              'bedrag': waarde,
              'aantal': 1.0,
              'planning_id': _text(taak['id']),
              'opdracht_id': _text(opMap['id']),
            });
          }
        }

        final totaalBedrag =
            abonnementBedrag + incidenteelBedrag + extraBedrag;

        if (totaalBedrag > 0 && regels.isNotEmpty) {
          nieuweConceptLijst.add({
            'id': 'klant_$bedrijfId',
            'klant_id': bedrijfId,
            'bedrijfsnaam': _text(bedrijf['bedrijfsnaam']).isEmpty
                ? 'Onbekend'
                : _text(bedrijf['bedrijfsnaam']),
            'type': 'verzameld',
            'abonnement': abonnementBedrag,
            'incidenteel': incidenteelBedrag,
            'extra': extraBedrag,
            'bedrag': totaalBedrag,
            'selected': true,
            'omschrijving': 'Facturatie $maandLabel',
            'regels': regels,
          });
        }
      }

      nieuweConceptLijst.sort(
        (a, b) =>
            _text(a['bedrijfsnaam']).compareTo(_text(b['bedrijfsnaam'])),
      );

      if (!mounted) return;
      setState(() {
        _conceptFacturen = nieuweConceptLijst;
        _isLoading = false;
      });

      if (nieuweConceptLijst.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Er is niets te factureren voor deze maand.'),
            ),
          );
        }
        return;
      }

      await _toonConceptPreviewModal();
    } catch (e) {
      debugPrint('FOUT IN REKENMOTOR: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fout: $e')),
      );
    }
  }

  ({int facturen, int klanten, double totaal, int abonnement, int extra})
      _previewStatistieken() {
    if (_conceptFacturen.isNotEmpty) {
      final selected =
          _conceptFacturen.where((c) => c['selected'] == true).toList();
      final klanten = selected.map((c) => _text(c['klant_id'])).toSet();
      var totaal = 0.0;
      var metAbo = 0;
      var metExtra = 0;
      for (final c in selected) {
        totaal += _asDouble(c['bedrag']);
        if (_asDouble(c['abonnement']) > 0) metAbo++;
        if (_asDouble(c['extra']) > 0) metExtra++;
      }
      return (
        facturen: selected.length,
        klanten: klanten.length,
        totaal: totaal,
        abonnement: metAbo,
        extra: metExtra,
      );
    }

    final monthFirst =
        DateTime(_geselecteerdeMaand.year, _geselecteerdeMaand.month);
    final monthLast =
        DateTime(_geselecteerdeMaand.year, _geselecteerdeMaand.month + 1, 0);
    final maandLabel = _maandLabelNl(_geselecteerdeMaand);
    var metOmzet = 0;
    final klanten = <String>{};

    for (final k in _klantenLijst) {
      final id = _text(k['id']);
      if (id.isEmpty || !_klantPassesFilter(id)) continue;
      if (_trackerBedrijfIdsMaand.contains(id)) continue;
      final b = _facturatieVoorKlant(
        id,
        monthFirst: monthFirst,
        monthLast: monthLast,
        maandLabel: maandLabel,
        reedsGefactureerdeIds: _trackerBedrijfIdsMaand,
      );
      if (b.totaal <= 0) continue;
      metOmzet++;
      klanten.add(id);
    }

    return (
      facturen: metOmzet,
      klanten: klanten.length,
      totaal: 0.0,
      abonnement: metOmzet,
      extra: 0,
    );
  }

  String _conceptOmschrijvingRegels(Map<String, dynamic> item) {
    final parts = <String>[];
    final abo = _asDouble(item['abonnement']);
    final inc = _asDouble(item['incidenteel']);
    final extra = _asDouble(item['extra']);
    if (abo > 0) parts.add('abo ${_eur.format(abo)}');
    if (inc > 0) parts.add('inc ${_eur.format(inc)}');
    if (extra > 0) parts.add('extra ${_eur.format(extra)}');
    return parts.isEmpty ? _text(item['omschrijving']) : parts.join(' · ');
  }

  Future<void> _toonConceptPreviewModal() async {
    final concepten = List<Map<String, dynamic>>.from(
      _conceptFacturen.map((e) => Map<String, dynamic>.from(e)),
    );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final geselecteerd =
                concepten.where((c) => c['selected'] == true).toList();
            final aantal = geselecteerd.length;
            var totaal = 0.0;
            for (final c in geselecteerd) {
              totaal += _asDouble(c['bedrag']);
            }

            return AlertDialog(
              title: Text(
                'Concept Facturatie Run (${concepten.length} facturen)',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800),
              ),
              content: SizedBox(
                width: 640,
                height: 480,
                child: ListView.builder(
                  itemCount: concepten.length,
                  itemBuilder: (context, index) {
                    final item = concepten[index];
                    return CheckboxListTile(
                      value: item['selected'] == true,
                      onChanged: (v) {
                        setModalState(() {
                          item['selected'] = v ?? false;
                          _conceptFacturen[index]['selected'] = v ?? false;
                        });
                      },
                      title: Text(
                        _text(item['bedrijfsnaam']),
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${_eur.format(_asDouble(item['bedrag']))} · '
                        '${_conceptOmschrijvingRegels(item)}',
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                      secondary: Icon(
                        Icons.receipt_long_outlined,
                        color: Colors.blue.shade700,
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isDefinitiefBezig
                      ? null
                      : () => Navigator.pop(dialogCtx),
                  child: const Text('Annuleren'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: aantal == 0 || _isDefinitiefBezig
                      ? null
                      : () async {
                          Navigator.pop(dialogCtx);
                          await _uitvoerenDefinitieveGeneratie(geselecteerd);
                        },
                  icon: _isDefinitiefBezig
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    'Definitief Genereren ($aantal · ${_eur.format(totaal)})',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Probeert de backend-RPC (indien uitgebreid met klant/type); anders false.
  Future<bool> _probeerRpcVoorConcept({
    required Map<String, dynamic> concept,
    required String jaarMaand,
  }) async {
    final klantId = _text(concept['klant_id']);
    if (klantId.isEmpty) return false;
    try {
      await AppSupabase.client.rpc(
        'genereer_maandelijkse_facturatie_run',
        params: {
          'p_jaar_maand': jaarMaand,
          'p_bedrijf_id': klantId,
          'p_factuur_type': _text(concept['type']),
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _uitvoerenDefinitieveGeneratie(
    List<Map<String, dynamic>> geselecteerdeConcepten,
  ) async {
    if (_isDefinitiefBezig || geselecteerdeConcepten.isEmpty) return;
    setState(() => _isDefinitiefBezig = true);

    final jaarMaand = _maandSleutel(_geselecteerdeMaand);
    final factuurDatum = DateTime(
      _geselecteerdeMaand.year,
      _geselecteerdeMaand.month + 1,
      0,
    );
    final factuurDatumStr = DateFormat('yyyy-MM-dd').format(factuurDatum);
    final vervalDatumStr = DateFormat('yyyy-MM-dd').format(
      factuurDatum.add(const Duration(days: _betalingsTermijnDagen)),
    );
    final userId = AppSupabase.client.auth.currentUser?.id;

    var aangemaakt = 0;
    final fouten = <String>[];

    try {
      for (final concept in geselecteerdeConcepten) {
        final klantId = _text(concept['klant_id']);
        if (klantId.isEmpty) continue;

        try {
          final viaRpc = await _probeerRpcVoorConcept(
            concept: concept,
            jaarMaand: jaarMaand,
          );
          if (!viaRpc) {
            await _persistConceptFactuur(
              concept: concept,
              factuurDatumStr: factuurDatumStr,
              vervalDatumStr: vervalDatumStr,
              userId: userId,
            );
          }
          await _upsertKlantFacturatieTracker(
            concept: concept,
            maandSleutel: jaarMaand,
          );
          aangemaakt++;
        } catch (e) {
          fouten.add('${concept['bedrijfsnaam']}: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _isDefinitiefBezig = false;
        _conceptFacturen = [];
      });

      if (fouten.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(
              '$aangemaakt conceptfactuur(en) aangemaakt voor $jaarMaand '
              '(betalingstermijn $_betalingsTermijnDagen dagen).',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.deepOrange,
            content: Text(
              '$aangemaakt gelukt, ${fouten.length} mislukt. '
              '${fouten.first}',
            ),
          ),
        );
      }

      await _loadBasisGegevens();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDefinitiefBezig = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange,
          content: Text('Definitief genereren mislukt: $e'),
        ),
      );
    }
  }

  Future<void> _persistConceptFactuur({
    required Map<String, dynamic> concept,
    required String factuurDatumStr,
    required String vervalDatumStr,
    required String? userId,
  }) async {
    final klantId = _text(concept['klant_id']);
    final omschrijving = _text(concept['omschrijving']);
    final regelsRaw = concept['regels'];
    final regels = regelsRaw is List
        ? regelsRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    if (regels.isEmpty) {
      throw StateError('Geen factuurregels voor $omschrijving');
    }

    final header = <String, dynamic>{
      'bedrijf_id': klantId,
      'status': 'concept',
      'factuur_datum': factuurDatumStr,
      'verval_datum': vervalDatumStr,
      'omschrijving': omschrijving,
      'layout_toon_aantallen': true,
      'layout_toon_prijzen': true,
    };
    if (userId != null && userId.isNotEmpty) {
      header['aangemaakt_door_id'] = userId;
    }

    final inserted = await AppSupabase.client
        .from('facturen')
        .insert(header)
        .select('id')
        .single();

    final factuurId = _text(inserted['id']);
    if (factuurId.isEmpty) {
      throw StateError('Factuur-id ontbreekt na insert.');
    }

    var volgorde = 1;
    for (final regel in regels) {
      final bedrag = _asDouble(regel['bedrag']);
      final aantal = _asDouble(regel['aantal']);
      if (aantal <= 0) continue;
      final stukprijs = bedrag / aantal;

      final linePayload = <String, dynamic>{
        'factuur_id': factuurId,
        'omschrijving': _text(regel['omschrijving']).isNotEmpty
            ? _text(regel['omschrijving'])
            : omschrijving,
        'aantal': aantal,
        'eenheid': 'stuk',
        'stukprijs_ex_btw': stukprijs,
        'btw_code': _defaultBtwCode ?? 'HOOG',
        'btw_percentage': _defaultBtwPct,
        'volgorde': volgorde++,
      };
      if (_fallbackArtikelId != null && _fallbackArtikelId!.isNotEmpty) {
        linePayload['artikel_id'] = _fallbackArtikelId;
      }

      await AppSupabase.client.from('factuur_regels').insert(linePayload);
    }
  }

  Widget _buildMaandKiezer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Vorige maand',
            onPressed: _isLoading ? null : () => _verschuifMaand(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            _maandLabelNl(_geselecteerdeMaand),
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          IconButton(
            tooltip: 'Volgende maand',
            onPressed: _isLoading ? null : () => _verschuifMaand(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveAnalyticsKaartjes() {
    Widget kaart(String label, String value, IconData icon, Color tint, Color bg) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tint.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(icon, color: tint, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: tint,
                      ),
                    ),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Facturatiestatus ${_maandLabelNl(_geselecteerdeMaand)}',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            kaart(
              'Gefactureerd',
              '$_analyticsGefactureerd',
              Icons.check_circle_outline,
              Colors.green.shade800,
              Colors.green.shade50,
            ),
            const SizedBox(width: 8),
            kaart(
              'Klaar om te genereren',
              '$_analyticsTeFactureren',
              Icons.play_circle_outline,
              Colors.blue.shade800,
              Colors.blue.shade50,
            ),
            const SizedBox(width: 8),
            kaart(
              'Totaal klanten',
              '$_analyticsTotaalKlanten',
              Icons.groups_outlined,
              Colors.indigo.shade800,
              Colors.indigo.shade50,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConceptIndicatie() {
    if (_conceptFacturen.isEmpty) return const SizedBox.shrink();
    final stats = _previewStatistieken();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Concept-run: ${stats.facturen} factuur(en), ${_eur.format(stats.totaal)} ex. BTW geselecteerd',
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.green.shade800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Facturen genereren',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadBasisGegevens,
                          child: const Text('Opnieuw proberen'),
                        ),
                      ],
                    ),
                  ),
                )
              : SelectionArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Preview & selectie',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Eén verzamelfactuur per klant: abonnement plus losse taken '
                              '(incidenteel/eenmalig, extra, of regulier zonder offerte via uren×tarief). '
                              'Reeds gefactureerd (klant_facturaties) en €0 worden overgeslagen.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildMaandKiezer()),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: InkWell(
                                    onTap: _isLoading ? null : _toonKlantZoekModal,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: Colors.white,
                                        labelText: 'Geselecteerde klant',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        prefixIcon: const Icon(Icons.domain),
                                        suffixIcon: const Icon(Icons.arrow_drop_down),
                                      ),
                                      child: Text(
                                        _geselecteerdeKlantNaam ?? 'Alle factureerbare klanten',
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildLiveAnalyticsKaartjes(),
                            const SizedBox(height: 24),
                            Builder(
                              builder: (context) {
                                final isMaandVoorbij = _isMaandVoorbij;
                                final knopActief = isMaandVoorbij &&
                                    !_isDefinitiefBezig &&
                                    !_isLoading;

                                return SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isMaandVoorbij
                                          ? Colors.blue.shade800
                                          : Colors.grey.shade400,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    icon: Icon(
                                      isMaandVoorbij
                                          ? Icons.play_arrow
                                          : Icons.lock_clock,
                                    ),
                                    label: Text(
                                      isMaandVoorbij
                                          ? 'Bereken Concept Facturen'
                                          : 'De geselecteerde maand is nog niet afgesloten',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: knopActief
                                        ? _genereerConceptRun
                                        : null,
                                  ),
                                );
                              },
                            ),
                            _buildConceptIndicatie(),
                            if (_conceptFacturen.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _toonConceptPreviewModal,
                                icon: const Icon(Icons.list_alt),
                                label: Text(
                                  'Preview opnieuw openen '
                                  '(${_conceptFacturen.length})',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
