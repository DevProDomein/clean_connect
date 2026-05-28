import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/live_activity_service.dart';

/// Persistente checklist voor een actieve werkbon. Vinkjes zijn alleen lokaal (geen DB per tick).
class ActiveWorkOrderScreen extends StatefulWidget {
  final String opdrachtId;
  final String planningId;
  final String? startTime;

  const ActiveWorkOrderScreen({
    super.key,
    required this.opdrachtId,
    required this.planningId,
    this.startTime,
  });

  @override
  State<ActiveWorkOrderScreen> createState() => _ActiveWorkOrderScreenState();
}

class _ActiveWorkOrderScreenState extends State<ActiveWorkOrderScreen> {
  /// Blijft behouden tijdens de sessie als de operator terugkeert naar dezelfde werkbon.
  static final Map<String, Set<String>> _checkedByOpdracht = {};

  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isClockingOut = false;
  String _errorMessage = '';

  Map<String, List<Map<String, dynamic>>> _groupedTasks = {};
  late final Set<String> _checkedTasks;

  Timer? _liveTimer;
  DateTime? _parsedStartTime;
  String _elapsedTime = '00:00:00';
  double? _benodigdeUren;
  String? _headerBedrijfsnaam;

  /// Opdrachtnummer / titel / projectnaam — hoofdregel boven timer.
  String? _headerOpdrachtTitel;
  String? _headerAdres;
  String? _headerTijdLabel;

  /// Rij van `opdrachten` (o.a. `project_id`, `frequentie_type`) voor paklijst/werkprogramma.
  Map<String, dynamic>? _actieveOpdracht;

  @override
  void initState() {
    super.initState();
    _checkedTasks = _checkedByOpdracht.putIfAbsent(
      widget.opdrachtId,
      () => <String>{},
    );
    _initLiveTimer();
    _loadChecklist();
  }

  void _initLiveTimer() {
    final raw = widget.startTime?.trim();
    if (raw == null || raw.isEmpty) return;
    try {
      final parts = raw.split(':');
      if (parts.length < 2) return;
      final now = DateTime.now();
      _parsedStartTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
        parts.length > 2 ? int.parse(parts[2].split('.').first) : 0,
      );
      _tickElapsed();
      _liveTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _tickElapsed(),
      );
    } catch (_) {
      _parsedStartTime = null;
    }
  }

  void _tickElapsed() {
    final start = _parsedStartTime;
    if (start == null || !mounted) return;
    final diff = DateTime.now().difference(start);
    if (diff.isNegative) return;
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    setState(() => _elapsedTime = '$h:$m:$s');
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadChecklist() async {
    double? benodigdeUren;
    String? headerBedrijfsnaam;
    String? headerOpdrachtTitel;
    String? headerAdres;
    String? headerTijdLabel;
    Map<String, dynamic>? actieveOpdracht;
    try {
      final opdrachtRow = await _supabase
          .from('opdrachten')
          .select(
            'benodigde_uren_totaal, benodigde_uren, uitvoer_adres_volledig, '
            'project_naam, opdracht_nummer, titel, project_id, frequentie_type',
          )
          .eq('id', widget.opdrachtId)
          .maybeSingle();
      if (opdrachtRow != null) {
        final m = Map<String, dynamic>.from(opdrachtRow as Map);
        actieveOpdracht = m;
        headerAdres = m['uitvoer_adres_volledig']?.toString();
        headerOpdrachtTitel = _composeOpdrachtTitel(m);
        final raw = m['benodigde_uren_totaal'] ?? m['benodigde_uren'];
        if (raw is num) {
          benodigdeUren = raw.toDouble();
        } else if (raw != null) {
          benodigdeUren = double.tryParse(raw.toString());
        }
      }
    } catch (_) {}

    try {
      final headRow = await _supabase
          .from('app_operator_vandaag')
          .select('bedrijfsnaam, rooster_starttijd, rooster_eindtijd')
          .eq('planning_id', widget.planningId)
          .maybeSingle();
      if (headRow != null) {
        final m = Map<String, dynamic>.from(headRow as Map);
        headerBedrijfsnaam = m['bedrijfsnaam']?.toString();
        final st = _fmtClock(m['rooster_starttijd']);
        final en = _fmtClock(m['rooster_eindtijd']);
        headerTijdLabel = '$st - $en';
      }
    } catch (_) {}

    try {
      final response = await _supabase
          .from('opdracht_checklist')
          .select()
          .eq('opdracht_id', widget.opdrachtId);

      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final row in response as List) {
        final r = Map<String, dynamic>.from(row as Map);
        final roomName = r['ruimte_naam']?.toString() ?? 'Algemene Ruimte';
        grouped.putIfAbsent(roomName, () => []).add(r);
      }

      if (mounted) {
        setState(() {
          _groupedTasks = grouped;
          _benodigdeUren = benodigdeUren;
          _headerBedrijfsnaam = headerBedrijfsnaam;
          _headerOpdrachtTitel = headerOpdrachtTitel;
          _headerAdres = headerAdres;
          _headerTijdLabel = headerTijdLabel;
          _actieveOpdracht = actieveOpdracht;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _benodigdeUren = benodigdeUren;
          _headerBedrijfsnaam = headerBedrijfsnaam;
          _headerOpdrachtTitel = headerOpdrachtTitel;
          _headerAdres = headerAdres;
          _headerTijdLabel = headerTijdLabel;
          _actieveOpdracht = actieveOpdracht;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openKogelvrijePaklijst(
    BuildContext context,
    String opdrachtId,
  ) async {
    if (opdrachtId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kan opdracht-ID niet vinden.')),
      );
      return;
    }

    // 1. Toon direct een lader
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final supabase = Supabase.instance.client;

      // STAP 1: Haal de Opdracht op (voor project_id en frequentie)
      final opdrachtData = await supabase
          .from('opdrachten')
          .select('project_id, frequentie_type')
          .eq('id', opdrachtId)
          .maybeSingle();
      if (opdrachtData == null) {
        throw Exception('Opdracht niet gevonden in database.');
      }

      final projectId = opdrachtData['project_id'];
      final freqType =
          opdrachtData['frequentie_type']?.toString().toLowerCase() ?? '';

      if (freqType == 'incidenteel' || freqType == 'eenmalig') {
        if (context.mounted) Navigator.of(context).pop();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Geen standaard materialenlijst voor losse klussen.',
              ),
            ),
          );
        }
        return;
      }

      // STAP 2: Haal het Project op (voor offerte_id)
      final projectData = await supabase
          .from('projecten')
          .select('offerte_id')
          .eq('id', projectId)
          .maybeSingle();
      final offerteId = projectData?['offerte_id'];

      if (offerteId == null) {
        if (context.mounted) Navigator.of(context).pop();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Geen blauwdruk (offerte) gekoppeld aan dit project.',
              ),
            ),
          );
        }
        return;
      }

      // STAP 3: Haal de Ruimtes en Materialen op (Geen alias, puur de tabellen)
      final ruimtes = await supabase
          .from('offerte_ruimtes')
          .select('''
          naam_in_pand, 
          ruimte_categorie, 
          offerte_ruimte_diensten (
            in_regulier, 
            in_frequent, 
            in_periodiek, 
            moeder_bestek (
              volledige_naam, 
              taak_naam, 
              bestek_materialen (
                materialen (*)
              )
            )
          )
        ''')
          .eq('offerte_id', offerteId);

      if (context.mounted) Navigator.of(context).pop();

      // STAP 4: Filteren en Data Verzamelen met Kogelvrije Parsing
      List<Widget> ruimteWidgets = [];
      Set<String> globaleMaterialen = {};

      String getMatNaam(dynamic item) {
        if (item == null) return '';
        final Map<String, dynamic> d = item is Map<String, dynamic> ? item : {};
        return (d['artikelnaam'] ??
                d['artikel_naam'] ??
                d['materiaal_naam'] ??
                d['naam'] ??
                d['omschrijving'] ??
                '')
            .toString()
            .trim();
      }

      for (var ruimte in ruimtes) {
        final ruimtesDienstenRaw = ruimte['offerte_ruimte_diensten'];
        final List<dynamic> diensten = ruimtesDienstenRaw is List
            ? ruimtesDienstenRaw
            : (ruimtesDienstenRaw != null ? [ruimtesDienstenRaw] : []);
        Set<String> ruimteMaterialen = {};

        for (var d in diensten) {
          bool isActief = false;
          if (freqType == 'regulier' && d['in_regulier'] == true) {
            isActief = true;
          }
          if (freqType == 'frequent' && d['in_frequent'] == true) {
            isActief = true;
          }
          if (freqType == 'periodiek' && d['in_periodiek'] == true) {
            isActief = true;
          }

          if (isActief && d['moeder_bestek'] != null) {
            // KOGELVRIJ UITPAKKEN: Supabase kan joins soms als array doorgeven!
            final mbRaw = d['moeder_bestek'];
            final Map<String, dynamic> mb = (mbRaw is List && mbRaw.isNotEmpty)
                ? (mbRaw.first is Map
                      ? Map<String, dynamic>.from(mbRaw.first as Map)
                      : <String, dynamic>{})
                : (mbRaw is Map<String, dynamic> ? mbRaw : <String, dynamic>{});

            final bestekMatRaw = mb['bestek_materialen'];
            final List<dynamic> gekoppeldeMaterialen = bestekMatRaw is List
                ? bestekMatRaw
                : (bestekMatRaw != null ? [bestekMatRaw] : []);

            for (var koppeling in gekoppeldeMaterialen) {
              // SLIMME FALLBACKS: We kijken op elke mogelijke key waar Supabase de data verstopte!
              final matRaw =
                  koppeling['materialen'] ??
                  koppeling['materiaal'] ??
                  koppeling;

              // Supabase geeft een Foreign Key soms als Object en soms als Lijst met 1 item.
              final Map<String, dynamic> materiaalData =
                  (matRaw is List && matRaw.isNotEmpty)
                  ? (matRaw.first is Map<String, dynamic>
                        ? matRaw.first
                        : <String, dynamic>{})
                  : (matRaw is Map<String, dynamic> ? matRaw : {});

              final String naam = getMatNaam(materiaalData);
              if (naam.isNotEmpty) {
                ruimteMaterialen.add(naam);
                globaleMaterialen.add(naam);
              }
            }
          }
        }

        if (ruimteMaterialen.isNotEmpty) {
          ruimteWidgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ruimte['naam_in_pand']?.toString() ??
                          ruimte['ruimte_categorie']?.toString() ??
                          'Ruimte',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...ruimteMaterialen.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 6, left: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.subdirectory_arrow_right,
                            size: 16,
                            color: Colors.blueGrey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              m,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }

      // STAP 5: Toon de Modal met de resultaten
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Materialenlijst ($freqType)'),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: globaleMaterialen.isEmpty
                ? SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Geen materialen gevonden. RAW DATABASE DUMP:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          ruimtes.toString(),
                          style: const TextStyle(
                            fontSize: 9,
                            fontFamily: 'monospace',
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      // HET TOTALE OVERZICHT (Bovenaan, Afwijkende Kleur)
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          border: Border.all(color: Colors.orange.shade200),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.shopping_cart,
                                  color: Colors.orange.shade800,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Totale Paklijst (Kar)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            ...globaleMaterialen.map(
                              (m) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.check_box_outline_blank,
                                      size: 18,
                                      color: Colors.orange,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        m,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        'Specificatie per ruimte',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // DE UITGESPLITSTE RUIMTES ERONDER
                      ...ruimteWidgets,
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Sluiten'),
            ),
          ],
        ),
      );
    } catch (e) {
      // Vang het veilig af en sluit de lader als die er nog is
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fout bij ophalen paklijst: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Volgorde: opdracht_nummer → titel → project_naam.
  String _composeOpdrachtTitel(Map<String, dynamic> m) {
    final n = m['opdracht_nummer'];
    if (n != null && n.toString().trim().isNotEmpty) {
      return 'Opdracht ${n.toString().trim()}';
    }
    final titel = m['titel']?.toString().trim();
    if (titel != null && titel.isNotEmpty) return titel;
    final pn = m['project_naam']?.toString().trim();
    if (pn != null && pn.isNotEmpty) return pn;
    return 'Opdracht';
  }

  String _fmtClock(dynamic timeValue) {
    if (timeValue == null) return '--:--';
    final t = timeValue.toString();
    if (t.length >= 5) return t.substring(0, 5);
    return t;
  }

  String _taskKey(String roomName, int index, Map<String, dynamic> t) {
    final label = t['uit_te_voeren_taak']?.toString() ?? '';
    return '$roomName|$index|$label';
  }

  Future<void> _onUitklokken() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => SelectionArea(
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Uitklokken'),
          content: const Text(
            'Weet u zeker dat u wilt uitklokken? Dit sluit de werkbon definitief af en registreert uw uren.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuleren'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () => Navigator.pop(c, true),
              child: const Text(
                'Uitklokken',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isClockingOut = true);
    try {
      final nowString = DateTime.now().toIso8601String().substring(11, 19);
      debugPrint(
        'X-RAY: Attempting to Clock Out for planning_id: ${widget.planningId}',
      );

      final updateResponse = await _supabase
          .from('opdracht_planning')
          .update({'status': 'voltooid', 'werkelijke_eindtijd': nowString})
          .eq('id', widget.planningId.toString())
          .select();

      debugPrint('X-RAY: Clock Out Success! Response: $updateResponse');

      if (mounted) {
        _checkedByOpdracht.remove(widget.opdrachtId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Klus voltooid en afgemeld!'),
            backgroundColor: Colors.green,
          ),
        );
        LiveActivityService.stopLiveTimer();
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      debugPrint('X-RAY FATAL: Clock Out Failed: $e');
      debugPrint('$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fout bij uitklokken: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClockingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          'Actieve Werkbon',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            color: Theme.of(context).textTheme.titleLarge?.color,
          ),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 1,
      ),
      body: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_parsedStartTime != null) _buildLiveTimerHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CupertinoActivityIndicator(radius: 16))
                  : _errorMessage.isNotEmpty
                  ? Center(
                      child: Text(
                        'Fout: $_errorMessage',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: _groupedTasks.entries
                          .map(
                            (entry) => _buildRoomCard(entry.key, entry.value),
                          )
                          .toList(),
                    ),
            ),
            if (!_isLoading && _errorMessage.isEmpty) _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTimerHeader() {
    final benodigdeUren = _benodigdeUren;
    final urenForRing = (benodigdeUren != null && benodigdeUren > 0)
        ? benodigdeUren
        : 1.0;
    final totaalSecondenNodig = urenForRing * 3600;
    var verstrekenSeconden = 0;
    final start = _parsedStartTime;
    if (start != null) {
      final diff = DateTime.now().difference(start);
      if (!diff.isNegative) verstrekenSeconden = diff.inSeconds;
    }
    var progress = verstrekenSeconden / totaalSecondenNodig;
    progress = progress.clamp(0.0, 1.0);

    final cs = Theme.of(context).colorScheme;
    final urenLabel = benodigdeUren == null
        ? null
        : (benodigdeUren == benodigdeUren.roundToDouble()
              ? benodigdeUren.toInt().toString()
              : benodigdeUren.toStringAsFixed(1));

    final opdrachtTitelDisp =
        (_headerOpdrachtTitel != null &&
            _headerOpdrachtTitel!.trim().isNotEmpty)
        ? _headerOpdrachtTitel!.trim()
        : 'Opdracht';
    final bedrijfsNaamDisp =
        (_headerBedrijfsnaam != null && _headerBedrijfsnaam!.trim().isNotEmpty)
        ? _headerBedrijfsnaam!.trim()
        : '';
    final adresDisp = (_headerAdres != null && _headerAdres!.trim().isNotEmpty)
        ? _headerAdres!.trim()
        : 'Adres onbekend';
    final tijdDisp =
        (_headerTijdLabel != null && _headerTijdLabel!.trim().isNotEmpty)
        ? _headerTijdLabel!.trim()
        : '--:-- - --:--';

    return Material(
      elevation: 2,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        color: Colors.red.shade50,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.assignment, size: 20, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            opdrachtTitelDisp,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (bedrijfsNaamDisp.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        bedrijfsNaamDisp,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 20,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            adresDisp,
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 20,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tijdDisp,
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 250,
                    height: 250,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 12,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _elapsedTime,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        urenLabel != null ? 'van $urenLabel u' : '—',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomCard(String roomName, List<Map<String, dynamic>> tasks) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          roomName,
          style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        children: [
          for (var i = 0; i < tasks.length; i++)
            _buildTaskTile(roomName, i, tasks[i]),
        ],
      ),
    );
  }

  Widget _buildTaskTile(String roomName, int index, Map<String, dynamic> t) {
    final key = _taskKey(roomName, index, t);
    final isChecked = _checkedTasks.contains(key);
    final label = t['uit_te_voeren_taak']?.toString() ?? 'Taak';

    return CheckboxListTile(
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          decoration: isChecked ? TextDecoration.lineThrough : null,
          color: isChecked ? Colors.grey : Colors.black87,
        ),
      ),
      value: isChecked,
      activeColor: Colors.green,
      checkColor: Colors.white,
      onChanged: (val) {
        setState(() {
          if (val == true) {
            _checkedTasks.add(key);
          } else {
            _checkedTasks.remove(key);
          }
        });
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.checklist),
                label: const Text('Bekijk Paklijst & Programma'),
                onPressed: () {
                  final actieveOpdracht = _actieveOpdracht;
                  final actueelId =
                      actieveOpdracht?['id']?.toString() ?? widget.opdrachtId;
                  _openKogelvrijePaklijst(context, actueelId);
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isClockingOut ? null : _onUitklokken,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.red.shade200,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isClockingOut
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : Text(
                        '⏹ UITKLOKKEN & AFRONDEN',
                        style: GoogleFonts.lato(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
