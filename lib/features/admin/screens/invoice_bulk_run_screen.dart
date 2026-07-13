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
  int _analyticsTeFactureren = 0;
  int _analyticsGefactureerd = 0;
  int _analyticsTotaalKlanten = 0;
  bool _isLoading = true;
  bool _isDefinitiefBezig = false;
  String? _loadError;

  List<Map<String, dynamic>> _factureerbareKlanten = [];
  List<Map<String, dynamic>> _gefactureerdeKlanten = [];
  List<Map<String, dynamic>> _conceptFacturen = [];

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

  /// Een maand is pas factureerbaar als we in de volgende maand zitten.
  bool get _isMaandAfgesloten {
    final now = DateTime.now();
    return _geselecteerdeMaand.year < now.year ||
        (_geselecteerdeMaand.year == now.year &&
            _geselecteerdeMaand.month < now.month);
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

  double _getTaakWaarde(Map<String, dynamic> taak) {
    return double.tryParse(
          taak['opdracht_waarde_ex_btw']?.toString() ?? '0',
        ) ??
        0.0;
  }

  /// Abonnement (eerste taak → offerte) + extra's (buiten abo, facturabel, open).
  ({
    double aboBedrag,
    double extraBedrag,
    int aantalExtraTaken,
    List<Map<String, dynamic>> regels,
    List<String> inbegrepenOpdrachtIds,
  }) _berekenKlantFacturatie(
    List<Map<String, dynamic>> takenVanKlant, {
    required String maandLabel,
  }) {
    double aboBedrag = 0.0;
    if (takenVanKlant.isNotEmpty) {
      final eersteTaak = takenVanKlant.first;
      final projectenRaw = eersteTaak['projecten'];
      final projecten = projectenRaw is Map
          ? Map<String, dynamic>.from(projectenRaw)
          : <String, dynamic>{};
      final offertesRaw = projecten['offertes'];

      if (offertesRaw != null) {
        Map<String, dynamic> offertesMap = {};
        if (offertesRaw is List && offertesRaw.isNotEmpty) {
          final first = offertesRaw.first;
          if (first is Map) {
            offertesMap = Map<String, dynamic>.from(first);
          }
        } else if (offertesRaw is Map) {
          offertesMap = Map<String, dynamic>.from(offertesRaw);
        }
        aboBedrag = double.tryParse(
              offertesMap['maandprijs_ex_btw']?.toString() ?? '0',
            ) ??
            0.0;
      }
    }

    double extraBedrag = 0.0;
    var aantalExtraTaken = 0;
    final regels = <Map<String, dynamic>>[];
    final inbegrepenOpdrachtIds = <String>[];

    for (final taak in takenVanKlant) {
      final isGefactureerd = taak['is_gefactureerd'] == true ||
          taak['facturatie_status'] == 'gefactureerd';
      final opdrachtId = _text(taak['id']);

      if (!isGefactureerd && opdrachtId.isNotEmpty) {
        inbegrepenOpdrachtIds.add(opdrachtId);
      }

      final isBuitenAbo = taak['is_buiten_abonnement'] == true;
      final isFacturabel = taak['facturatie_status'] == 'facturabel';

      if (isBuitenAbo && isFacturabel && !isGefactureerd) {
        final waarde = _getTaakWaarde(taak);
        extraBedrag += waarde;
        aantalExtraTaken++;

        if (waarde > 0) {
          var projectNaam = _text(taak['bedrijfsnaam']);
          final project = taak['projecten'] ?? taak['project'];
          if (project is Map) {
            final pn = _text(Map<String, dynamic>.from(project)['project_naam']);
            if (pn.isNotEmpty) projectNaam = pn;
          }
          final datum = _parseDateOnly(taak['geplande_datum']);
          final datumStr = datum != null
              ? DateFormat('dd-MM-yyyy').format(datum)
              : _text(taak['geplande_datum']);

          regels.add({
            'omschrijving': 'Extra werk $datumStr — $projectNaam',
            'bedrag': waarde,
            'aantal': 1.0,
            'opdracht_id': opdrachtId,
          });
        }
      }
    }

    if (aboBedrag > 0) {
      regels.insert(0, {
        'omschrijving': 'Abonnement $maandLabel',
        'bedrag': aboBedrag,
        'aantal': 1.0,
      });
    }

    return (
      aboBedrag: aboBedrag,
      extraBedrag: extraBedrag,
      aantalExtraTaken: aantalExtraTaken,
      regels: regels,
      inbegrepenOpdrachtIds: inbegrepenOpdrachtIds,
    );
  }

  List<Map<String, dynamic>> _takenVanKlantItem(Map<String, dynamic> klant) {
    final takenRaw = klant['taken'];
    if (takenRaw is! List) return const [];
    return takenRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  void _updatePreviewAnalytics() {
    _analyticsTeFactureren = _factureerbareKlanten.length;
    _analyticsGefactureerd = _gefactureerdeKlanten.length;
    _analyticsTotaalKlanten =
        _factureerbareKlanten.length + _gefactureerdeKlanten.length;
  }

  Future<void> _loadFacturatiePreview() async {
    final startStr = DateTime(
      _geselecteerdeMaand.year,
      _geselecteerdeMaand.month,
      1,
    ).toIso8601String().split('T')[0];
    final endStr = DateTime(
      _geselecteerdeMaand.year,
      _geselecteerdeMaand.month + 1,
      0,
    ).toIso8601String().split('T')[0];

    final now = DateTime.now();
    final isMaandAfgesloten = _geselecteerdeMaand.year < now.year ||
        (_geselecteerdeMaand.year == now.year &&
            _geselecteerdeMaand.month < now.month);

    if (!isMaandAfgesloten) {
      if (mounted) {
        setState(() {
          _factureerbareKlanten = [];
          _gefactureerdeKlanten = [];
        });
      } else {
        _factureerbareKlanten = [];
        _gefactureerdeKlanten = [];
      }
      _updatePreviewAnalytics();
      return;
    }

    try {
      final data = await AppSupabase.client
          .from('opdrachten')
          .select('*, projecten(*, offertes(*), bedrijven(*))')
          .gte('geplande_datum', startStr)
          .lte('geplande_datum', endStr);

      final factureerbaar = <Map<String, dynamic>>[];
      final reedsGefactureerd = <Map<String, dynamic>>[];
      final takenPerBedrijf = <String, List<Map<String, dynamic>>>{};

      for (final raw in data as List) {
        if (raw is! Map) continue;
        final taak = Map<String, dynamic>.from(raw);
        final projectenRaw = taak['projecten'];
        final projecten = projectenRaw is Map
            ? Map<String, dynamic>.from(projectenRaw)
            : <String, dynamic>{};

        final bedrijfIdRaw = projecten['bedrijf_id'] ?? taak['bedrijf_id'];
        final String? bedrijfId = bedrijfIdRaw == null
            ? null
            : bedrijfIdRaw.toString().trim().isEmpty
                ? null
                : bedrijfIdRaw.toString().trim();

        final bedrijven = projecten['bedrijven'];
        final bedrijfsnaamViaProject = bedrijven is Map
            ? _text(Map<String, dynamic>.from(bedrijven)['bedrijfsnaam'])
            : '';
        final bedrijfsnaam = bedrijfsnaamViaProject.isNotEmpty
            ? bedrijfsnaamViaProject
            : (_text(taak['bedrijfsnaam']).isNotEmpty
                ? _text(taak['bedrijfsnaam'])
                : 'Onbekende Klant');

        final groupKey = bedrijfId ?? bedrijfsnaam;
        takenPerBedrijf.putIfAbsent(groupKey, () => []).add(taak);
      }

      for (final entry in takenPerBedrijf.entries) {
        final tasks = entry.value;
        final first = tasks.first;
        final projectenRaw = first['projecten'];
        final projecten = projectenRaw is Map
            ? Map<String, dynamic>.from(projectenRaw)
            : <String, dynamic>{};
        final bedrijven = projecten['bedrijven'];
        final bedrijfsnaam = bedrijven is Map
            ? (_text(Map<String, dynamic>.from(bedrijven)['bedrijfsnaam']).isNotEmpty
                ? _text(Map<String, dynamic>.from(bedrijven)['bedrijfsnaam'])
                : _text(first['bedrijfsnaam']).isNotEmpty
                    ? _text(first['bedrijfsnaam'])
                    : 'Onbekende Klant')
            : (_text(first['bedrijfsnaam']).isNotEmpty
                ? _text(first['bedrijfsnaam'])
                : 'Onbekende Klant');

        final bedrijfIdRaw = projecten['bedrijf_id'] ?? first['bedrijf_id'];
        final String? bedrijfId = bedrijfIdRaw == null
            ? null
            : bedrijfIdRaw.toString().trim().isEmpty
                ? null
                : bedrijfIdRaw.toString().trim();

        final allInvoiced = tasks.every((t) {
          return t['is_gefactureerd'] == true ||
              t['facturatie_status']?.toString() == 'gefactureerd';
        });

        final berekening = _berekenKlantFacturatie(
          tasks.map((t) => Map<String, dynamic>.from(t)).toList(),
          maandLabel: _maandLabelNl(_geselecteerdeMaand),
        );

        final klantMap = {
          'bedrijf_id': bedrijfId ?? entry.key,
          'bedrijfsnaam': bedrijfsnaam,
          'taken': tasks,
          'abo_bedrag': berekening.aboBedrag,
          'extra_bedrag': berekening.extraBedrag,
          'aantal_extra_taken': berekening.aantalExtraTaken,
          'totaal_bedrag': berekening.aboBedrag + berekening.extraBedrag,
        };

        if (allInvoiced) {
          reedsGefactureerd.add(klantMap);
        } else {
          factureerbaar.add(klantMap);
        }
      }

      factureerbaar.sort(
        (a, b) => _text(a['bedrijfsnaam']).compareTo(_text(b['bedrijfsnaam'])),
      );
      reedsGefactureerd.sort(
        (a, b) => _text(a['bedrijfsnaam']).compareTo(_text(b['bedrijfsnaam'])),
      );

      _factureerbareKlanten = factureerbaar;
      _gefactureerdeKlanten = reedsGefactureerd;
      _updatePreviewAnalytics();

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Fout bij laden facturatie preview: $e');
      _factureerbareKlanten = [];
      _gefactureerdeKlanten = [];
      _updatePreviewAnalytics();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _koppelOpdrachtenAanFactuur({
    required String? factuurId,
    required Map<String, dynamic> concept,
  }) async {
    final factuurIdStr = _text(factuurId);
    if (factuurIdStr.isEmpty) return;

    final ids = <String>{};
    final opdrachtIdsRaw = concept['opdracht_ids'];
    if (opdrachtIdsRaw is List) {
      for (final id in opdrachtIdsRaw) {
        final s = id.toString();
        if (s.isNotEmpty) ids.add(s);
      }
    }
    final regelsRaw = concept['regels'];
    if (regelsRaw is List) {
      for (final regel in regelsRaw) {
        if (regel is! Map) continue;
        final oid = _text(regel['opdracht_id']);
        if (oid.isNotEmpty) ids.add(oid);
      }
    }
    if (ids.isEmpty) return;

    try {
      await AppSupabase.client.from('opdrachten').update({
        'factuur_id': factuurIdStr,
        'is_gefactureerd': true,
        'facturatie_status': 'gefactureerd',
      }).inFilter('id', ids.toList());
    } catch (e) {
      debugPrint(
        'Fout bij koppelen opdrachten aan factuur $factuurIdStr '
        '(${concept['bedrijfsnaam']}): $e',
      );
      rethrow;
    }
  }

  Future<String?> _factuurIdNaRpc({
    required String klantId,
    required String maandSleutel,
  }) async {
    try {
      final row = await AppSupabase.client
          .from('facturen')
          .select('id')
          .eq('bedrijf_id', klantId)
          .eq('maand_sleutel', maandSleutel)
          .order('factuur_datum', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) {
        return _text(row['id']);
      }
    } catch (e) {
      debugPrint('factuur-id na RPC opzoeken: $e');
    }
    return null;
  }

  /// Waakhond: markeer klant+maand als gefactureerd (voorkomt dubbele concept-runs).
  Future<void> _upsertWaakhondNaDefinitieveFactuur(
    Map<String, dynamic> concept,
  ) async {
    final bedrijfsnaam = _text(concept['bedrijfsnaam']);
    debugPrint('--- START WAAKHOND UPDATE VOOR $bedrijfsnaam ---');

    final bedrijfId = _text(concept['klant_id']);
    if (bedrijfId.isEmpty) {
      throw StateError(
        'klant_id ontbreekt in concept voor $bedrijfsnaam',
      );
    }

    final veiligeMaandSleutel = _maandSleutel(_geselecteerdeMaand);
    final payload = <String, dynamic>{
      'bedrijf_id': bedrijfId,
      'maand_sleutel': veiligeMaandSleutel,
      'berekend_abonnement': _asDouble(concept['abonnement']),
      'berekend_incidenteel': _asDouble(concept['incidenteel']),
      'berekend_extra': _asDouble(concept['extra']),
      'totaal_ex_btw': _asDouble(concept['bedrag']),
      'status': 'gefactureerd',
      'aangepast_op': DateTime.now().toIso8601String(),
    };

    debugPrint('Upsert Payload: $payload');

    try {
      await AppSupabase.client.from('klant_facturaties').upsert(
        payload,
        onConflict: 'bedrijf_id,maand_sleutel',
      );
      debugPrint('✅ WAAKHOND UPDATE SUCCESVOL voor $bedrijfsnaam!');
    } catch (e, st) {
      debugPrint(
        '❌ FATALE FOUT BIJ UPDATEN WAAKHOND (klant_facturaties) '
        'voor $bedrijfsnaam: $e',
      );
      debugPrint('$st');
      rethrow;
    }
  }

  Future<void> _toonKlantZoekModal() async {
    if (!_isMaandAfgesloten || _factureerbareKlanten.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Geen factureerbare klanten: de maand is nog niet afgesloten of '
              'alle werk is al gefactureerd.',
            ),
          ),
        );
      }
      return;
    }

    var zoekTerm = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final gefilterd = _factureerbareKlanten.where((b) {
              if (zoekTerm.isEmpty) return true;
              return _text(b['bedrijfsnaam'])
                  .toLowerCase()
                  .contains(zoekTerm.toLowerCase());
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
                                child: Center(
                                  child: Text('Geen factureerbare klanten gevonden.'),
                                ),
                              )
                            else
                              ...gefilterd.map((klant) {
                                final id = _text(klant['bedrijf_id']);
                                final naam = _text(klant['bedrijfsnaam']);

                                return ListTile(
                                  leading: Icon(
                                    Icons.check_circle,
                                    color: Colors.green.shade700,
                                  ),
                                  title: Text(
                                    naam.isEmpty ? 'Onbekend' : naam,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    'Klaar voor facturatie',
                                    style: TextStyle(
                                      color: Colors.green.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.of(dialogContext).pop();
                                    setState(() {
                                      _geselecteerdeKlantId = id;
                                      _geselecteerdeKlantNaam = naam;
                                      _conceptFacturen = [];
                                    });
                                  },
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

    try {
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

      await _loadFacturatiePreview();

      if (!mounted) return;
      setState(() {
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
    if (!_isMaandAfgesloten) return;

    setState(() {
      _isLoading = true;
      _conceptFacturen = [];
    });

    try {
      final maandLabel = _maandLabelNl(_geselecteerdeMaand);

      await _loadFacturatiePreview();

      if (_factureerbareKlanten.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Geen factureerbaar werk gevonden of maand nog niet afgesloten.',
              ),
            ),
          );
        }
        return;
      }

      final nieuweConceptLijst = <Map<String, dynamic>>[];

      for (final klant in _factureerbareKlanten) {
        final bedrijfId = _text(klant['bedrijf_id']);
        if (bedrijfId.isEmpty || !_klantPassesFilter(bedrijfId)) continue;

        final listTaken = _takenVanKlantItem(klant);
        final berekening = _berekenKlantFacturatie(
          listTaken,
          maandLabel: maandLabel,
        );

        final abonnementBedrag = berekening.aboBedrag;
        final extraBedrag = berekening.extraBedrag;
        final totaalBedrag = abonnementBedrag + extraBedrag;
        final regels = berekening.regels;
        final inbegrepenOpdrachtIds = berekening.inbegrepenOpdrachtIds;

        if (totaalBedrag > 0 && regels.isNotEmpty) {
          nieuweConceptLijst.add({
            'id': 'klant_$bedrijfId',
            'klant_id': bedrijfId,
            'bedrijfsnaam': _text(klant['bedrijfsnaam']).isEmpty
                ? 'Onbekend'
                : _text(klant['bedrijfsnaam']),
            'type': 'verzameld',
            'abonnement': abonnementBedrag,
            'incidenteel': 0.0,
            'extra': extraBedrag,
            'aantal_extra_taken': berekening.aantalExtraTaken,
            'bedrag': totaalBedrag,
            'selected': true,
            'omschrijving': 'Facturatie $maandLabel',
            'regels': regels,
            'opdracht_ids': inbegrepenOpdrachtIds.toSet().toList(),
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
              content: Text(
                'Geen factureerbaar werk gevonden voor deze maand. Dit kan komen '
                'doordat alle taken al gefactureerd zijn, óf doordat er geen '
                'facturabele extra opdrachten buiten het abonnement zijn.',
              ),
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

    if (!_isMaandAfgesloten) {
      return (
        facturen: 0,
        klanten: 0,
        totaal: 0.0,
        abonnement: 0,
        extra: 0,
      );
    }

    final filtered = _factureerbareKlanten
        .where((k) => _klantPassesFilter(_text(k['bedrijf_id'])))
        .toList();

    var totaal = 0.0;
    var metAbo = 0;
    var metExtra = 0;
    for (final k in filtered) {
      final berekening = _berekenKlantFacturatie(
        _takenVanKlantItem(k),
        maandLabel: _maandLabelNl(_geselecteerdeMaand),
      );
      totaal += berekening.aboBedrag + berekening.extraBedrag;
      if (berekening.aboBedrag > 0) metAbo++;
      if (berekening.extraBedrag > 0) metExtra++;
    }

    return (
      facturen: filtered.length,
      klanten: filtered.length,
      totaal: totaal,
      abonnement: metAbo,
      extra: metExtra,
    );
  }

  Widget _buildKlantBedragRegel({
    required String label,
    required double bedrag,
    required Color kleur,
    bool vet = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$label €${bedrag.toStringAsFixed(2)}',
        style: GoogleFonts.inter(
          fontSize: vet ? 14 : 13,
          fontWeight: vet ? FontWeight.w800 : FontWeight.w600,
          color: kleur,
        ),
      ),
    );
  }

  Widget _buildKlantFacturatieBreakdown({
    required double aboBedrag,
    required double extraBedrag,
    required int aantalExtraTaken,
    bool compact = false,
  }) {
    final totaal = aboBedrag + extraBedrag;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKlantBedragRegel(
          label: 'Vast Abonnement:',
          bedrag: aboBedrag,
          kleur: Colors.blue.shade700,
        ),
        _buildKlantBedragRegel(
          label: 'Extra Opdrachten ($aantalExtraTaken):',
          bedrag: extraBedrag,
          kleur: Colors.green.shade700,
        ),
        if (!compact) ...[
          const SizedBox(height: 4),
          _buildKlantBedragRegel(
            label: 'Totaal Factuur:',
            bedrag: totaal,
            kleur: Colors.indigo.shade800,
            vet: true,
          ),
        ],
      ],
    );
  }

  Widget _buildFactureerbareKlantenPreview() {
    if (!_isMaandAfgesloten || _factureerbareKlanten.isEmpty) {
      return const SizedBox.shrink();
    }

    final klanten = _factureerbareKlanten
        .where((k) => _klantPassesFilter(_text(k['bedrijf_id'])))
        .toList();
    if (klanten.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Controle per klant',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: klanten.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final klant = klanten[index];
            final taken = _takenVanKlantItem(klant);
            final berekening = _berekenKlantFacturatie(
              taken,
              maandLabel: _maandLabelNl(_geselecteerdeMaand),
            );
            final aboBedrag = berekening.aboBedrag;
            final extraBedrag = berekening.extraBedrag;
            final aantalExtraTaken = berekening.aantalExtraTaken;

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text(klant['bedrijfsnaam']).isEmpty
                          ? 'Onbekende klant'
                          : _text(klant['bedrijfsnaam']),
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildKlantFacturatieBreakdown(
                      aboBedrag: aboBedrag,
                      extraBedrag: extraBedrag,
                      aantalExtraTaken: aantalExtraTaken,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
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
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          _buildKlantFacturatieBreakdown(
                            aboBedrag: _asDouble(item['abonnement']),
                            extraBedrag: _asDouble(item['extra']),
                            aantalExtraTaken: item['aantal_extra_taken'] is int
                                ? item['aantal_extra_taken'] as int
                                : int.tryParse(
                                      item['aantal_extra_taken']?.toString() ??
                                          '0',
                                    ) ??
                                    0,
                            compact: true,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Totaal Factuur: ${_eur.format(_asDouble(item['bedrag']))}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.indigo.shade800,
                            ),
                          ),
                        ],
                      ),
                      isThreeLine: true,
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
    final verwerkteOpdrachtIds = <String>[];

    try {
      for (final concept in geselecteerdeConcepten) {
        final klantId = _text(concept['klant_id']);
        if (klantId.isEmpty) continue;

        try {
          String? nieuwAangemaakteFactuurId;
          final viaRpc = await _probeerRpcVoorConcept(
            concept: concept,
            jaarMaand: jaarMaand,
          );
          if (!viaRpc) {
            nieuwAangemaakteFactuurId = await _persistConceptFactuur(
              concept: concept,
              maandSleutel: jaarMaand,
              factuurDatumStr: factuurDatumStr,
              vervalDatumStr: vervalDatumStr,
              userId: userId,
            );
          } else {
            nieuwAangemaakteFactuurId = await _factuurIdNaRpc(
              klantId: klantId,
              maandSleutel: jaarMaand,
            );
          }
          await _koppelOpdrachtenAanFactuur(
            factuurId: nieuwAangemaakteFactuurId,
            concept: concept,
          );

          final opdrachtIdsRaw = concept['opdracht_ids'];
          if (opdrachtIdsRaw is List) {
            for (final id in opdrachtIdsRaw) {
              final s = id.toString();
              if (s.isNotEmpty) verwerkteOpdrachtIds.add(s);
            }
          }
          final regelsRaw = concept['regels'];
          if (regelsRaw is List) {
            for (final regel in regelsRaw) {
              if (regel is! Map) continue;
              final oid = _text(regel['opdracht_id']);
              if (oid.isNotEmpty) verwerkteOpdrachtIds.add(oid);
            }
          }

          // Waakhond pas na geslaagde factuur + regels (+ opdracht-koppeling).
          await _upsertWaakhondNaDefinitieveFactuur(concept);

          aangemaakt++;
        } catch (e, st) {
          debugPrint(
            'Fout bij factuur generatie van ${concept['bedrijfsnaam']}: $e',
          );
          debugPrint('$st');
          fouten.add('${concept['bedrijfsnaam']}: $e');
        }
      }

      if (verwerkteOpdrachtIds.isNotEmpty) {
        try {
          await AppSupabase.client
              .from('opdrachten')
              .update({
                'is_gefactureerd': true,
                'facturatie_status': 'gefactureerd',
              })
              .inFilter('id', verwerkteOpdrachtIds.toSet().toList());
          debugPrint(
            'Succes: ${verwerkteOpdrachtIds.toSet().length} opdrachten afgevinkt.',
          );
        } catch (e) {
          debugPrint('Fout bij afvinken van opdrachten: $e');
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

  Future<String> _persistConceptFactuur({
    required Map<String, dynamic> concept,
    required String maandSleutel,
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
      // FIX: koppel de maand aan de factuur (blokkeert dubbel genereren in de praktijk).
      'maand_sleutel': maandSleutel,
      // Zorg dat de factuur ook direct het bedrag draagt (regels blijven leidend als triggers herberekenen).
      'totaal_ex_btw': _asDouble(concept['bedrag']),
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

    return factuurId;
  }

  Widget _buildMaandSelector() => _buildMaandKiezer();

  Widget _buildKlantSelector() {
    final alleKlanten = _geselecteerdeKlantId == null;
    return InkWell(
      onTap: _isLoading ? null : _toonKlantZoekModal,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Geselecteerde Klant',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.domain),
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          _geselecteerdeKlantNaam ?? 'Alle factureerbare klanten',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: alleKlanten ? Colors.blue.shade700 : Colors.black87,
            fontWeight: alleKlanten ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
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

  Widget _buildMaandNietAfgeslotenWaarschuwing() {
    if (_isMaandAfgesloten) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_clock, color: Colors.orange.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Deze maand is nog niet afgesloten. Je kunt pas factureren als de '
              'maand volledig voorbij is.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegeWerkHint() {
    if (!_isMaandAfgesloten) return const SizedBox.shrink();

    if (_factureerbareKlanten.isNotEmpty || _gefactureerdeKlanten.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return const Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Geen factureerbaar werk gevonden voor deze maand. Dit kan komen doordat '
        'alle taken al gefactureerd zijn, óf doordat er geen facturabele extra '
        'opdrachten buiten het abonnement zijn.',
        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
        textAlign: TextAlign.center,
      ),
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
                              'Eén verzamelfactuur per klant: vast abonnement (maandprijs_ex_btw) '
                              'plus extra opdrachten buiten het abonnement die facturabel zijn.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildLiveAnalyticsKaartjes(),
                            _buildLegeWerkHint(),
                            const SizedBox(height: 16),
                            _buildFactureerbareKlantenPreview(),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: _buildMaandSelector(),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: _buildKlantSelector(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _buildMaandNietAfgeslotenWaarschuwing(),
                            Builder(
                              builder: (context) {
                                final isMaandAfgesloten = _isMaandAfgesloten;
                                final knopActief = isMaandAfgesloten &&
                                    !_isDefinitiefBezig &&
                                    !_isLoading;

                                return SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isMaandAfgesloten
                                          ? Colors.blue.shade800
                                          : Colors.grey.shade400,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    icon: Icon(
                                      isMaandAfgesloten
                                          ? Icons.play_arrow
                                          : Icons.lock_clock,
                                    ),
                                    label: Text(
                                      isMaandAfgesloten
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
