import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;

import '../../../core/supabase_client.dart';

class ManualPlanModal extends StatefulWidget {
  const ManualPlanModal({required this.opdrachtId, super.key});

  final String opdrachtId;

  @override
  State<ManualPlanModal> createState() => _ManualPlanModalState();
}

class _ManualPlanModalState extends State<ManualPlanModal> {
  final TextEditingController _startTimeController = TextEditingController();

  // State variabelen voor de handmatige planner
  List<Map<String, dynamic>> handmatigeStarttijden = [];
  bool isHandmatigeTijdenLaden = false;
  String? geselecteerdeHandmatigeTijd;
  DateTime? geselecteerdeHandmatigeDatum;

  bool _loading = true;
  bool _saving = false;
  bool _isSearching = false;
  bool _hasSearchedOperators = false;
  String? _error;
  Map<String, dynamic>? _opdracht;

  List<dynamic> _availableOperators = <dynamic>[];
  List<String> _gekozenOperatorIds = [];
  List<String> _gekozenOperatorNamen = [];
  String? _bestaandePlanningId;
  double _shiftHours = 0.25;

  /// Bron: uitsluitend kolommen op de hoofdopdracht (geen venster-/schatting-math).
  double _totaalUrenHoofdopdracht = 0;

  /// Effectief aantal operators (DB of fallback); gebruikt in restant-formule.
  int _safeOperatorsHoofdopdracht = 1;

  double _standaardUurPerPersoon = 1.0;

  double _reedsGeplandeUren = 0;

  int _reedsGeplandeOperators = 0;

  double _resterendeUren = 0;

  int _resterendeOperators = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOpdracht());
  }

  @override
  void dispose() {
    _startTimeController.dispose();
    super.dispose();
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  /// Totaal uren volgens klant-spec: parse-keten op string-niveau.
  double _totaalUrenKlantFormule(Map<String, dynamic> item) {
    return double.tryParse(
          item['benodigde_uren_totaal']?.toString() ??
              item['verwachte_uren_totaal']?.toString() ??
              '0',
        ) ??
        0.0;
  }

  /// Ruw aantal uit [benodigde_operators] (mag 0 zijn voor oude rijen).
  int _dbOperatorsUitHoofdopdrachtRow(Map<String, dynamic> row) {
    return int.tryParse(row['benodigde_operators']?.toString() ?? '0') ?? 0;
  }

  /// Minuten sedert middernacht voor DB-tijd (HH:mm, HH:mm:ss of fragment in ISO-string).
  int? _dbTijdStringNaarMinuten(String raw) {
    final s = _text(raw);
    if (s.isEmpty) return null;
    var head = s;
    if (s.contains('T')) {
      final i = s.indexOf('T');
      head = s.substring(i + 1).split('+').first.split('-').first;
    }
    head = head.length >= 8
        ? head.substring(0, 8).trim()
        : head.split('.').first.trim();
    final parts = head.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m.clamp(0, 59);
  }

  /// Uren tussen planning [starttijd] en [eindtijd] (nachtdienst: eind < start → +24u).
  double _urenTussenPlanningTijden(dynamic startV, dynamic eindV) {
    final startMin = _dbTijdStringNaarMinuten(startV.toString());
    final eindMin = _dbTijdStringNaarMinuten(eindV.toString());
    if (startMin == null || eindMin == null) return 0;
    var e = eindMin;
    if (e < startMin) e += 24 * 60;
    return (e - startMin) / 60.0;
  }

  /// Realtime geplande uren en aantal planning-rijen voor deze opdracht (excl. geannuleerd).
  /// Bij bewerken van bestaande planning: [excludePlanningId] telt niet mee in som en aantal.
  Future<void> _berekenRestant({required String excludePlanningId}) async {
    double somUren = 0;
    var count = 0;
    try {
      final res = await Supabase.instance.client
          .from('opdracht_planning')
          .select('id, starttijd, eindtijd, status')
          .eq('opdracht_id', widget.opdrachtId);

      final list = List<dynamic>.from((res as List?) ?? const <dynamic>[]);
      for (final raw in list) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        if (_text(m['status']) == 'geannuleerd') continue;
        final id = _text(m['id']);
        if (excludePlanningId.isNotEmpty && id == excludePlanningId) {
          continue;
        }
        count++;
        if (m['starttijd'] != null && m['eindtijd'] != null) {
          somUren += _urenTussenPlanningTijden(m['starttijd'], m['eindtijd']);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Fout bij berekenen reeds geplande uren: $e');
    }
    if (!mounted) return;
    final safeOps = _safeOperatorsHoofdopdracht;
    final totaal = _totaalUrenHoofdopdracht;
    setState(() {
      _reedsGeplandeUren = somUren;
      _reedsGeplandeOperators = count;
      _resterendeOperators = (safeOps - count).clamp(0, 99);
      _resterendeUren = (totaal - somUren).clamp(0.0, 999.0);
    });
  }

  double get _maxUrenVoorRegelaar {
    if (_resterendeUren > 0) return math.min(24.0, _resterendeUren);
    return 24.0;
  }

  String _operatorDisplayNaam(Map<String, dynamic> op) {
    final n = _text(op['naam']);
    if (n.isNotEmpty) return n;
    final on = _text(op['operator_naam']);
    return on.isNotEmpty ? on : 'Operator';
  }

  String _berekenEindTijdDb(String startHuman, double uren) {
    final startMin = _timeStringToMinutes(startHuman);
    final endMin = startMin + (uren * 60).round();
    return _minutesToDb(endMin);
  }

  DateTime _dateFromValue(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return DateTime.now();
    return DateTime.tryParse(raw) ?? DateTime.now();
  }

  TimeOfDay _timeFromValue(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return const TimeOfDay(hour: 8, minute: 0);
    final hhmm = raw.length >= 5 ? raw.substring(0, 5) : raw;
    final parts = hhmm.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 8 : 8;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  String _timeToHuman(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  int _timeStringToMinutes(String t) {
    final raw = _text(t);
    if (raw.isEmpty) return 0;
    final hhmm = raw.length >= 5 ? raw.substring(0, 5) : raw;
    final parts = hhmm.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (h.clamp(0, 23) * 60) + m.clamp(0, 59);
  }

  String _minutesToHuman(int minutes) {
    final mm = minutes.clamp(0, 24 * 60);
    final h = (mm ~/ 60).toString().padLeft(2, '0');
    final m = (mm % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _minutesToDb(int minutes) => '${_minutesToHuman(minutes)}:00';

  void _prefillHandmatigePlannerState(Map<String, dynamic> item) {
    if (_text(item['status']) == 'ingepland') {
      final pd = DateTime.tryParse(
            _text(item['geplande_datum']).length >= 10
                ? _text(item['geplande_datum']).substring(0, 10)
                : _text(item['geplande_datum']),
          ) ??
          DateTime.now();
      geselecteerdeHandmatigeDatum = DateTime(pd.year, pd.month, pd.day);
      _bestaandePlanningId = _text(item['huidige_planning_id']);
      final hid = _text(item['huidige_operator_id']);
      if (hid.isNotEmpty) {
        _gekozenOperatorIds = [hid];
        _gekozenOperatorNamen = ['Operator'];
      } else {
        _gekozenOperatorIds = [];
        _gekozenOperatorNamen = [];
      }

      final planningDetails = item['planning_details'] ?? item['planning'];
      String? startRaw;
      String? endRaw;
      if (planningDetails is List && planningDetails.isNotEmpty) {
        final first = planningDetails.first;
        if (first is Map) {
          startRaw = first['starttijd']?.toString();
          endRaw = first['eindtijd']?.toString();
        }
      } else if (planningDetails is Map) {
        startRaw = planningDetails['starttijd']?.toString();
        endRaw = planningDetails['eindtijd']?.toString();
      }

      if (startRaw != null && startRaw.isNotEmpty) {
        final start = _timeToHuman(_timeFromValue(startRaw));
        geselecteerdeHandmatigeTijd = start;
        _startTimeController.text = start;
        if (endRaw != null && endRaw.isNotEmpty) {
          final startMin = _timeStringToMinutes(start);
          final endMin = _timeStringToMinutes(_timeToHuman(_timeFromValue(endRaw)));
          if (endMin > startMin) {
            _shiftHours = ((endMin - startMin) / 60.0).clamp(0.25, 24.0);
          }
        }
      }

      if (_gekozenOperatorIds.isNotEmpty) {
        _hasSearchedOperators = true;
      }
    } else {
      final pd = _dateFromValue(item['geplande_datum']);
      geselecteerdeHandmatigeDatum = DateTime(pd.year, pd.month, pd.day);
      _bestaandePlanningId = null;
      _gekozenOperatorIds = [];
      _gekozenOperatorNamen = [];
      geselecteerdeHandmatigeTijd = null;
      _hasSearchedOperators = false;
      _availableOperators = <dynamic>[];
    }
  }

  Map<String, dynamic>? _projectJoin() {
    final row = _opdracht;
    if (row == null) return null;
    final joined = row['projecten'];
    if (joined is Map<String, dynamic>) return joined;
    if (joined is List && joined.isNotEmpty && joined.first is Map) {
      return Map<String, dynamic>.from(joined.first as Map);
    }
    return null;
  }

  String get _projectName {
    final fromJoin = _text(_projectJoin()?['project_naam']);
    if (fromJoin.isNotEmpty) return fromJoin;
    return 'Onbekend project';
  }

  String get _clientName {
    final direct = _text(_opdracht?['bedrijfsnaam']);
    return direct.isEmpty ? 'Onbekende klant' : direct;
  }

  String get _regio {
    final fromJoin = _text(_projectJoin()?['werk_regio']);
    if (fromJoin.isNotEmpty) return fromJoin;
    final direct = _text(_opdracht?['werk_regio']);
    return direct.isEmpty ? '' : direct;
  }

  DateTime get _plannedDate => _dateFromValue(_opdracht?['geplande_datum']);

  /// Datum voor handmatige planning (kiezer override of opdracht-bron).
  DateTime get _effectieveHandmatigePlanningDatum {
    final d = geselecteerdeHandmatigeDatum ?? _plannedDate;
    return DateTime(d.year, d.month, d.day);
  }

  TimeOfDay get _windowStart => _timeFromValue(_opdracht?['tijdslot_start']);

  TimeOfDay get _windowEnd => _timeFromValue(_opdracht?['tijdslot_eind']);

  TimeOfDay? get _selectedStartTime {
    final value = _text(_startTimeController.text);
    if (value.isEmpty) return null;
    return _timeFromValue(value);
  }

  String get _plannedDateDb =>
      DateFormat('yyyy-MM-dd').format(_effectieveHandmatigePlanningDatum);

  String _formatDate(DateTime date) => DateFormat('dd-MM-yyyy').format(date);

  String formatHoursToText(num? hoursNum) {
    if (hoursNum == null) return '0 min';
    double hours = hoursNum.toDouble();
    int h = hours.floor();
    int m = ((hours - h) * 60).round();

    if (h > 0 && m > 0) return '$h uur en $m min';
    if (h > 0) return '$h uur';
    return '$m min';
  }

  Future<void> _loadOpdracht() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final row = await AppSupabase.client
          .from('opdrachten')
          .select(
            'id, project_id, status, geplande_datum, tijdslot_start, tijdslot_eind, '
            'huidige_operator_id, huidige_planning_id, '
            'benodigde_uren_totaal, verwachte_uren_totaal, toegewezen_uren_totaal, resterende_uren, '
            'benodigde_operators, werk_regio, uitvoer_adres_volledig, '
            'toelichting_planning, bedrijfsnaam, '
            'projecten(project_naam), '
            'planning:opdracht_planning!huidige_planning_id(starttijd, eindtijd, operator_id)',
          )
          .eq('id', widget.opdrachtId)
          .single();

      final map = Map<String, dynamic>.from(row as Map);

      // 1. Haal totalen op (exacte klant-logica op string-niveau)
      final double totaalUren = _totaalUrenKlantFormule(map);
      final int dbOperators = _dbOperatorsUitHoofdopdrachtRow(map);
      // ignore: avoid_print
      print('Uitlezen in UI (ManualPlanModal) - item dbOperators: $dbOperators');
      // ignore: avoid_print
      print(
        'Uitlezen in UI (ManualPlanModal) - raw benodigde_operators: ${map['benodigde_operators']}',
      );

      // 2. Kogelvrije fallback: alleen bij DB 0 → /3; anders altijd DB
      var safeOperators = dbOperators > 0
          ? dbOperators
          : (totaalUren > 0 ? (totaalUren / 3).ceil() : 1);
      if (safeOperators == 0) {
        safeOperators = 1;
      }

      // 3. Standaard per persoon (bijv. 24 uur / 4 man = 6.0 uur)
      final double standaardUurPerPersoon = totaalUren / safeOperators;

      _totaalUrenHoofdopdracht = totaalUren;
      _safeOperatorsHoofdopdracht = safeOperators;
      _standaardUurPerPersoon = standaardUurPerPersoon;

      final excludePlanningId =
          _text(map['status']) == 'ingepland' &&
                  _text(map['huidige_planning_id']).isNotEmpty
              ? _text(map['huidige_planning_id'])
              : '';

      await _berekenRestant(excludePlanningId: excludePlanningId);

      // 4. Startwaarde +/- regelaar
      var benodigdeUren = standaardUurPerPersoon;
      if (benodigdeUren > _resterendeUren && _resterendeUren > 0) {
        benodigdeUren = _resterendeUren;
      } else if (benodigdeUren == 0) {
        benodigdeUren = 1.0;
      }
      _shiftHours = benodigdeUren.clamp(0.25, _maxUrenVoorRegelaar);

      _prefillHandmatigePlannerState(map);

      if (_text(map['status']) == 'ingepland' &&
          _text(_bestaandePlanningId).isNotEmpty) {
        _shiftHours = _shiftHours.clamp(0.25, _maxUrenVoorRegelaar);
      }

      final slotStartRaw = _text(geselecteerdeHandmatigeTijd);
      if (slotStartRaw.isEmpty) {
        final slotStart = _text(map['tijdslot_start']).isEmpty
            ? const TimeOfDay(hour: 8, minute: 0)
            : _timeFromValue(map['tijdslot_start']);
        final startHuman = _timeToHuman(slotStart);
        _startTimeController.text = startHuman;
        geselecteerdeHandmatigeTijd = startHuman;
      }

      final pdDay = geselecteerdeHandmatigeDatum ??
          DateTime(
            _dateFromValue(map['geplande_datum']).year,
            _dateFromValue(map['geplande_datum']).month,
            _dateFromValue(map['geplande_datum']).day,
          );

      if (!mounted) return;
      setState(() {
        _opdracht = map;
        geselecteerdeHandmatigeDatum = pdDay;
      });

      await _berekenHandmatigeTijden(
        _gekozenOperatorIds.isNotEmpty ? _gekozenOperatorIds.first : '',
        pdDay,
        _shiftHours,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _berekenHandmatigeTijden(
    String operatorId,
    DateTime datum,
    double benodigdeUren,
  ) async {
    setState(() => isHandmatigeTijdenLaden = true);
    try {
      final opId = _text(operatorId);
      final dateString = DateFormat('yyyy-MM-dd').format(datum);

      // 1. Haal afspraken op voor deze dag (als operator onbekend is: geen blokkades/warnings).
      var afsprakenQuery = Supabase.instance.client
          .from('opdracht_planning')
          .select('id, starttijd, eindtijd')
          .eq('operator_id', opId)
          .eq('geplande_datum', dateString);
      final excludeId = _text(_bestaandePlanningId);
      if (excludeId.isNotEmpty) {
        afsprakenQuery = afsprakenQuery.neq('id', excludeId);
      }
      final List<dynamic> bestaandeAfspraken = opId.isEmpty
          ? const <dynamic>[]
          : List<dynamic>.from(await afsprakenQuery);

      /// Minuten sedert middernacht uit DB-tijd-string (HH:MM of HH:MM:SS). Geen buffers.
      int timeToMinutes(String t) {
        final s = _text(t);
        if (s.isEmpty) return 0;
        final hhmm = s.contains('T') ? s.substring(s.indexOf('T') + 1).split('+').first.split('-').first : s;
        final head = hhmm.length >= 8 ? hhmm.substring(0, 8).trim() : hhmm.split('.').first.trim();
        final parts = head.split(':');
        if (parts.length < 2) return 0;
        final uren = int.tryParse(parts[0]) ?? 0;
        final minuten = int.tryParse(parts[1]) ?? 0;
        return uren * 60 + minuten.clamp(0, 59);
      }

      final int opdrachtMinuten = (benodigdeUren * 60).round();
      final List<Map<String, dynamic>> beschikbareTijden = [];

      // Loop van 06:00 tot 22:00 — uitsluitend harde tijdoverlap (0 minuten marge).
      for (int actueleMinuten = 360;
          (actueleMinuten + opdrachtMinuten) <= 1320;
          actueleMinuten += 15) {
        final int potentieelEind = actueleMinuten + opdrachtMinuten;
        var heeftHardeOverlap = false;

        for (final raw in bestaandeAfspraken) {
          if (raw is! Map) continue;
          final afspraak = Map<String, dynamic>.from(raw);
          if (afspraak['starttijd'] == null || afspraak['eindtijd'] == null) continue;

          final int afspraakStart =
              timeToMinutes(afspraak['starttijd'].toString());
          final int afspraakEind =
              timeToMinutes(afspraak['eindtijd'].toString());

          // Exacte 0‑min overlap: blokkeert o.a. 10:30 start bij 10:00–11:00; laat toe 11:00 na 11:00 einde.
          if (actueleMinuten < afspraakEind && potentieelEind > afspraakStart) {
            heeftHardeOverlap = true;
            break;
          }
        }

        if (!heeftHardeOverlap) {
          final int uren = actueleMinuten ~/ 60;
          final int minuten = actueleMinuten % 60;
          final String tijdString =
              '${uren.toString().padLeft(2, '0')}:${minuten.toString().padLeft(2, '0')}';

          beschikbareTijden.add({
            'tijd': tijdString,
          });
        }
      }

      if (!mounted) return;
      setState(() {
        handmatigeStarttijden = beschikbareTijden;
        if (geselecteerdeHandmatigeTijd == null ||
            !handmatigeStarttijden.any(
              (t) => _text(t['tijd']) == geselecteerdeHandmatigeTijd,
            )) {
          geselecteerdeHandmatigeTijd =
              handmatigeStarttijden.isNotEmpty ? _text(handmatigeStarttijden.first['tijd']) : null;
        }
        if (geselecteerdeHandmatigeTijd != null) {
          _startTimeController.text = geselecteerdeHandmatigeTijd!;
        }
      });
    } catch (e) {
      // ignore: avoid_print
      print('Fout handmatige tijden: $e');
    } finally {
      if (mounted) setState(() => isHandmatigeTijdenLaden = false);
    }
  }

  Future<void> _loadAvailableOperators() async {
    final start = _selectedStartTime;
    final hours = _shiftHours;
    if (start == null || hours <= 0 || _regio.isEmpty) {
      setState(() {
        _availableOperators = <dynamic>[];
        _gekozenOperatorIds = [];
        _gekozenOperatorNamen = [];
        _hasSearchedOperators = false;
      });
      return;
    }

    final selectedStartTimeFormatted =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final dateString = _plannedDateDb.contains('T') ? _plannedDateDb.split('T').first : _plannedDateDb;
    final regio = _text(_opdracht?['werk_regio']);
    final opdrachtIdParam =
        _text(_opdracht?['id']).isNotEmpty ? _text(_opdracht?['id']) : widget.opdrachtId;

    setState(() {
      _isSearching = true;
      _gekozenOperatorIds = [];
      _gekozenOperatorNamen = [];
    });
    void logRpc(Object message) {
      assert(() {
        debugPrint(message.toString());
        return true;
      }());
    }
    try {
      logRpc('--- START RPC CALL ---');
      logRpc('Datum: $dateString');
      logRpc('Start: $selectedStartTimeFormatted');
      logRpc('Duur: $_shiftHours');
      logRpc('Regio: $regio');

      final result = await Supabase.instance.client.rpc(
        'haal_beschikbare_operators_op',
        params: {
          'p_geplande_datum': dateString,
          'p_starttijd': '$selectedStartTimeFormatted:00',
          'p_duur_uren': hours,
          'p_regio': regio,
          'p_opdracht_id': opdrachtIdParam,
          // Handmatige planner: geen reistijd-buffer in RPC (past SQL‑functie migratie hieronder aan).
          'p_negeer_reistijd': true,
        },
      );

      logRpc('--- RPC SUCCESS ---');
      logRpc(result);
      final rows = List<dynamic>.from((result as List?) ?? const <dynamic>[]);
      if (!mounted) return;
      setState(() {
        _availableOperators = rows;
        _hasSearchedOperators = true;
      });
    } catch (e) {
      logRpc('--- RPC ERROR ---');
      logRpc(e);
      if (!mounted) return;
      setState(() {
        _availableOperators = <dynamic>[];
        _gekozenOperatorIds = [];
        _gekozenOperatorNamen = [];
        _hasSearchedOperators = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Fout bij zoeken: $e',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _toonOperatorZoekModal(
    List<dynamic> operatorLijst,
    int maxAantal,
  ) async {
    if (!mounted) return;
    var zoekTerm = '';
    var tempIds = List<String>.from(_gekozenOperatorIds);
    var tempNamen = List<String>.from(_gekozenOperatorNamen);

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final q = zoekTerm.toLowerCase().trim();
            final gefilterdeLijst = operatorLijst.where((op) {
              if (op is! Map) return false;
              final m = Map<String, dynamic>.from(op);
              if (q.isEmpty) return true;
              final naam = _operatorDisplayNaam(m).toLowerCase();
              return naam.contains(q);
            }).toList();

            return AlertDialog(
              title: Text(
                maxAantal > 1
                    ? 'Kies operators (max $maxAantal)'
                    : 'Kies een operator',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Zoek operator',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) =>
                          setModalState(() => zoekTerm = val),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: gefilterdeLijst.isEmpty
                          ? Center(
                              child: Text(
                                'Geen resultaten',
                                style: GoogleFonts.inter(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: gefilterdeLijst.length,
                              itemBuilder: (context, index) {
                                final raw = gefilterdeLijst[index];
                                if (raw is! Map) return const SizedBox.shrink();
                                final operator =
                                    Map<String, dynamic>.from(raw);
                                final opId = _text(operator['id']);
                                final opNaam = _operatorDisplayNaam(operator);
                                if (opId.isEmpty) return const SizedBox.shrink();
                                final isSelected = tempIds.contains(opId);

                                return ListTile(
                                  title: Text(
                                    opNaam,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  trailing: maxAantal > 1
                                      ? Icon(
                                          isSelected
                                              ? Icons.check_box_rounded
                                              : Icons.check_box_outline_blank_rounded,
                                          color: isSelected
                                              ? Theme.of(context).colorScheme.primary
                                              : Colors.grey.shade500,
                                        )
                                      : null,
                                  selected: isSelected,
                                  selectedTileColor: Colors.blue.shade50,
                                  onTap: () {
                                    if (maxAantal == 1) {
                                      setState(() {
                                        _gekozenOperatorIds = [opId];
                                        _gekozenOperatorNamen = [opNaam];
                                      });
                                      Navigator.pop(dialogContext);
                                      _berekenHandmatigeTijden(
                                        opId,
                                        _effectieveHandmatigePlanningDatum,
                                        _shiftHours,
                                      );
                                    } else {
                                      setModalState(() {
                                        if (isSelected) {
                                          final i = tempIds.indexOf(opId);
                                          if (i >= 0) {
                                            tempIds.removeAt(i);
                                            if (i < tempNamen.length) {
                                              tempNamen.removeAt(i);
                                            }
                                          }
                                        } else if (tempIds.length <
                                            maxAantal) {
                                          tempIds.add(opId);
                                          tempNamen.add(opNaam);
                                        } else {
                                          ScaffoldMessenger.of(
                                            dialogContext,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Je kunt maximaal $maxAantal operators kiezen.',
                                                style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                      });
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Annuleren'),
                ),
                if (maxAantal > 1)
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _gekozenOperatorIds = List<String>.from(tempIds);
                        _gekozenOperatorNamen = List<String>.from(tempNamen);
                      });
                      Navigator.pop(dialogContext);
                      if (_gekozenOperatorIds.isNotEmpty) {
                        _berekenHandmatigeTijden(
                          _gekozenOperatorIds.first,
                          _effectieveHandmatigePlanningDatum,
                          _shiftHours,
                        );
                      }
                    },
                    child: const Text('Bevestigen'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickHandmatigeDatum() async {
    final initial = _effectieveHandmatigePlanningDatum;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null || !mounted) return;
    final pickedDay = DateTime(picked.year, picked.month, picked.day);
    if (pickedDay.year == initial.year &&
        pickedDay.month == initial.month &&
        pickedDay.day == initial.day) {
      return;
    }

    final opId = _gekozenOperatorIds.isNotEmpty ? _gekozenOperatorIds.first : '';
    setState(() {
      geselecteerdeHandmatigeDatum = pickedDay;
      geselecteerdeHandmatigeTijd = null;
    });

    await _berekenHandmatigeTijden(opId, pickedDay, _shiftHours);
  }

  Future<void> _submitPlan() async {
    if (_saving) return;
    if (_gekozenOperatorIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Kies minimaal één operator.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final hours = _shiftHours;
    final startHuman = _text(geselecteerdeHandmatigeTijd);
    if (startHuman.isEmpty || hours <= 0) return;

    final startMinutes = _timeStringToMinutes(startHuman);
    final startDb = _minutesToDb(startMinutes);
    final berekendeEindTijd = _berekenEindTijdDb(startHuman, hours);

    setState(() => _saving = true);
    try {
      final item = _opdracht ?? <String, dynamic>{'id': widget.opdrachtId};
      final opdrachtId = _text(item['id']).isEmpty
          ? widget.opdrachtId
          : _text(item['id']);

      final String? bestaandePlanningIdRaw =
          _text(_bestaandePlanningId ?? item['huidige_planning_id']).isEmpty
              ? null
              : _text(_bestaandePlanningId ?? item['huidige_planning_id']);
      final bool isBestaandePlanning =
          _text(item['status']) == 'ingepland' && bestaandePlanningIdRaw != null;

      final String nieuweDatum = geselecteerdeHandmatigeDatum!
          .toIso8601String()
          .split('T')
          .first;
      final String gekozenOperatorId = _gekozenOperatorIds.first;
      final int operatorsNodig =
          int.tryParse(item['benodigde_operators']?.toString() ?? '1') ?? 1;
      final double benodigdeUren = hours;
      final double berekendeTotaalUren = benodigdeUren * operatorsNodig;

      if (isBestaandePlanning) {
        await Supabase.instance.client.from('opdracht_planning').update({
          'operator_id': gekozenOperatorId,
          'geplande_datum': nieuweDatum,
          'starttijd': startDb,
          'eindtijd': berekendeEindTijd,
          'toegewezen_uren': hours,
          'status': 'gepland',
        }).eq('id', bestaandePlanningIdRaw);

        final Map<String, dynamic> opdrachtUpdate = {
          'geplande_datum': nieuweDatum,
          'status': 'ingepland',
          'huidige_operator_id': gekozenOperatorId,
        };

        final double origineleUren =
            double.tryParse(item['benodigde_uren_totaal']?.toString() ?? '0') ??
                0.0;
        if (berekendeTotaalUren != origineleUren) {
          opdrachtUpdate['benodigde_uren_totaal'] = berekendeTotaalUren;
          opdrachtUpdate['verwachte_uren_totaal'] = berekendeTotaalUren;
          opdrachtUpdate['afwijkende_uren'] = true;
        }

        await Supabase.instance.client
            .from('opdrachten')
            .update(opdrachtUpdate)
            .eq('id', opdrachtId);
      } else {
        final planningRes = await Supabase.instance.client
            .from('opdracht_planning')
            .insert({
              'opdracht_id': opdrachtId,
              'operator_id': gekozenOperatorId,
              'geplande_datum': nieuweDatum,
              'starttijd': startDb,
              'eindtijd': berekendeEindTijd,
              'toegewezen_uren': hours,
              'status': 'gepland',
            })
            .select('id')
            .single();

        final String nieuwePlanningId = planningRes['id'].toString();

        final Map<String, dynamic> opdrachtUpdate = {
          'geplande_datum': nieuweDatum,
          'status': 'ingepland',
          'huidige_planning_id': nieuwePlanningId,
          'huidige_operator_id': gekozenOperatorId,
        };

        final double origineleUren =
            double.tryParse(item['benodigde_uren_totaal']?.toString() ?? '0') ??
                0.0;
        if (berekendeTotaalUren != origineleUren) {
          opdrachtUpdate['benodigde_uren_totaal'] = berekendeTotaalUren;
          opdrachtUpdate['verwachte_uren_totaal'] = berekendeTotaalUren;
          opdrachtUpdate['afwijkende_uren'] = true;
        }

        await Supabase.instance.client
            .from('opdrachten')
            .update(opdrachtUpdate)
            .eq('id', opdrachtId);

        for (var i = 1; i < _gekozenOperatorIds.length; i++) {
          final extraOpId = _gekozenOperatorIds[i];
          await Supabase.instance.client.from('opdracht_planning').insert({
            'opdracht_id': opdrachtId,
            'operator_id': extraOpId,
            'geplande_datum': nieuweDatum,
            'starttijd': startDb,
            'eindtijd': berekendeEindTijd,
            'toegewezen_uren': hours,
            'status': 'gepland',
          });
        }
      }

      try {
        final datumString = nieuweDatum.isNotEmpty ? nieuweDatum : 'binnenkort';
        for (final opId in _gekozenOperatorIds) {
          final id = _text(opId);
          if (id.isEmpty) continue;
          await AppSupabase.client.functions.invoke(
            'send-push-notification',
            body: {
              'operator_id': id,
              'aantal': 1,
              'datum_string': datumString,
            },
          );
        }
      } catch (e) {
        // ignore: avoid_print
        print('Kon pushmelding niet versturen: $e');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E8E3E),
          content: Text(
            isBestaandePlanning
                ? 'Planning succesvol bijgewerkt.'
                : 'Opdracht succesvol ingepland.',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Inplannen mislukt: $e',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
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
    final surface = isDark ? const Color(0xFF111019) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 30,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Kon opdracht niet laden: $_error',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                  : DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: 56,
                            height: 5,
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _projectName,
                                    style: GoogleFonts.inter(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(alpha: isDark ? 0.08 : 0.05),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: TabBar(
                                splashBorderRadius: BorderRadius.circular(16),
                                dividerColor: Colors.transparent,
                                labelColor: Colors.white,
                                unselectedLabelColor: cs.onSurface.withValues(alpha: 0.70),
                                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w900),
                                indicator: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                tabs: const [
                                  Tab(text: 'Informatie'),
                                  Tab(text: 'Inplannen'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildInfoTab(scrollController, cs, isDark),
                                _buildPlanTab(scrollController, cs, isDark),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
        );
      },
    );
  }

  Widget _buildInfoTab(ScrollController controller, ColorScheme cs, bool isDark) {
    final item = _opdracht ?? <String, dynamic>{};
    final totaalUren = _totaalUrenHoofdopdracht > 0
        ? _totaalUrenHoofdopdracht
        : (double.tryParse(
              item['benodigde_uren_totaal']?.toString() ?? '0',
            ) ??
            0.0);
    final operators = _safeOperatorsHoofdopdracht > 0
        ? _safeOperatorsHoofdopdracht
        : (int.tryParse(item['benodigde_operators']?.toString() ?? '1') ?? 1);
    final urenPerPersoon = operators > 0 ? (totaalUren / operators) : totaalUren;

    final klant = _text(item['bedrijfsnaam']).isEmpty
        ? _clientName
        : _text(item['bedrijfsnaam']);
    final datumLabel = _formatDate(_effectieveHandmatigePlanningDatum);
    final startSlot = _timeToHuman(_windowStart);
    final endSlot = _timeToHuman(_windowEnd);

    Widget buildInfoRow(IconData icon, String label, String waarde) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey.shade500),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    waarde,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              buildInfoRow(
                Icons.business,
                'Klant / Bedrijf',
                klant.isEmpty ? 'Onbekend' : klant,
              ),
              Divider(height: 1, color: Colors.grey.shade300),
              buildInfoRow(Icons.calendar_today, 'Datum', datumLabel),
              Divider(height: 1, color: Colors.grey.shade300),
              buildInfoRow(
                Icons.access_time,
                'Tijdslot',
                '$startSlot tot $endSlot',
              ),
              Divider(height: 1, color: Colors.grey.shade300),
              buildInfoRow(
                Icons.people_outline,
                'Aantal operators',
                '$operators geadviseerd',
              ),
              Divider(height: 1, color: Colors.grey.shade300),
              buildInfoRow(
                Icons.timer_outlined,
                'Standaard per persoon',
                '${urenPerPersoon.toStringAsFixed(2)} uur',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlanTab(ScrollController controller, ColorScheme cs, bool isDark) {
    final opdracht = _opdracht;
    final totaalUren = _totaalUrenHoofdopdracht;
    final safeOperators = _safeOperatorsHoofdopdracht;
    final reedsGeplandeUren = _reedsGeplandeUren;
    final reedsGeplandeOperators = _reedsGeplandeOperators;
    final standaardUurPerPersoon = _standaardUurPerPersoon;
    final resterendeUren = _resterendeUren;
    final resterendeOperators = _resterendeOperators;
    final isEditingIngepland = _text(opdracht?['status']) == 'ingepland' &&
        _text(_bestaandePlanningId).isNotEmpty;
    final canLoadOperators = _selectedStartTime != null && _shiftHours > 0;
    final maxTeKiezen = isEditingIngepland ? 1 : _resterendeOperators;

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
      children: [
        Text(
          'Plan opdracht voor $_projectName',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Nodig: $safeOperators operators (effectief) • Mogelijk tussen ${_timeToHuman(_windowStart)} en ${_timeToHuman(_windowEnd)}',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: cs.onSurface.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Totaal benodigd',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${totaalUren.toStringAsFixed(2)} uur\n($safeOperators operators)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reeds toegewezen',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${reedsGeplandeUren.toStringAsFixed(2)} uur\n($reedsGeplandeOperators operators)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Standaard per persoon',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${standaardUurPerPersoon.toStringAsFixed(2)} uur',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nog in te vullen',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${resterendeUren.toStringAsFixed(2)} uur\n($resterendeOperators operators)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: resterendeUren > 0
                                ? Colors.orange.shade700
                                : Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.calendar_today, color: cs.primary),
          title: Text(
            'Datum opdracht',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            geselecteerdeHandmatigeDatum != null
                ? '${geselecteerdeHandmatigeDatum!.day}-${geselecteerdeHandmatigeDatum!.month}-${geselecteerdeHandmatigeDatum!.year}'
                : 'Kies een datum',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          trailing: TextButton(
            onPressed: _pickHandmatigeDatum,
            child: const Text('Wijzigen'),
          ),
          onTap: _pickHandmatigeDatum,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _StepperCircleButton(
              icon: Icons.remove_rounded,
              onPressed: () {
                setState(() {
                  _shiftHours =
                      (_shiftHours - 0.25).clamp(0.25, _maxUrenVoorRegelaar).toDouble();
                  _gekozenOperatorIds = [];
                  _gekozenOperatorNamen = [];
                });
                _berekenHandmatigeTijden(
                  _gekozenOperatorIds.isNotEmpty ? _gekozenOperatorIds.first : '',
                  _effectieveHandmatigePlanningDatum,
                  _shiftHours,
                );
              },
            ),
            Expanded(
              child: Text(
                formatHoursToText(_shiftHours),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            _StepperCircleButton(
              icon: Icons.add_rounded,
              onPressed: () {
                setState(() {
                  _shiftHours =
                      (_shiftHours + 0.25).clamp(0.25, _maxUrenVoorRegelaar).toDouble();
                  _gekozenOperatorIds = [];
                  _gekozenOperatorNamen = [];
                });
                _berekenHandmatigeTijden(
                  _gekozenOperatorIds.isNotEmpty ? _gekozenOperatorIds.first : '',
                  _effectieveHandmatigePlanningDatum,
                  _shiftHours,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('handmatige_tijd_${geselecteerdeHandmatigeTijd ?? ''}_${handmatigeStarttijden.length}'),
          initialValue: geselecteerdeHandmatigeTijd,
          decoration: InputDecoration(
            labelText: 'Kies starttijd',
            labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
            prefixIcon: const Icon(Icons.schedule_rounded),
            filled: true,
            fillColor: const Color(0xFFF2F2F7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide.none,
            ),
          ),
          items: handmatigeStarttijden.map((item) {
            final tijd = item['tijd'] as String? ?? '';
            return DropdownMenuItem<String>(
              value: tijd,
              child: Text(
                tijd,
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 14.0,
                ),
              ),
            );
          }).toList(growable: false),
          onChanged: isHandmatigeTijdenLaden
              ? null
              : (val) {
                  setState(() {
                    geselecteerdeHandmatigeTijd = val;
                    if (val != null) _startTimeController.text = val;
                    _gekozenOperatorIds = [];
                    _gekozenOperatorNamen = [];
                    _availableOperators = <dynamic>[];
                    _hasSearchedOperators = false;
                  });
                },
        ),
        if (isHandmatigeTijdenLaden) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                'Tijden laden...',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: (_isSearching || !canLoadOperators) ? null : _loadAvailableOperators,
          icon: _isSearching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search_rounded),
          label: Text(
            _isSearching ? 'Operators zoeken...' : 'Zoek Beschikbare Operators',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        if (!isEditingIngepland && maxTeKiezen <= 0) ...[
          const SizedBox(height: 6),
          Text(
            'Alle geplande operator-plekken voor deze opdracht zijn ingevuld.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.orange.shade800,
            ),
          ),
        ] else if (maxTeKiezen > 1) ...[
          const SizedBox(height: 6),
          Text(
            'Je kunt nog tot $maxTeKiezen operator(s) selecteren voor deze opdracht.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.68),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_availableOperators.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              !canLoadOperators
                  ? 'Kies eerst starttijd + uren'
                  : _hasSearchedOperators
                      ? 'Geen beschikbare operators gevonden voor dit tijdstip.'
                      : 'Klik op zoek om beschikbare operators te laden.',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withValues(alpha: 0.70),
              ),
            ),
          )
        else
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (!canLoadOperators || _isSearching)
                  ? null
                  : () {
                      if (!isEditingIngepland && maxTeKiezen <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              'Er zijn geen vrije operator-plekken meer voor deze opdracht.',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                            ),
                          ),
                        );
                        return;
                      }
                      _toonOperatorZoekModal(_availableOperators, maxTeKiezen);
                    },
              borderRadius: BorderRadius.circular(16),
              child: InputDecorator(
                decoration: _fieldDecoration(
                  isDark,
                  cs,
                  'Geselecteerde operator(s)',
                  Icons.person_search_rounded,
                ).copyWith(
                  suffixIcon: _gekozenOperatorIds.isNotEmpty && !_isSearching
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            setState(() {
                              _gekozenOperatorIds = [];
                              _gekozenOperatorNamen = [];
                            });
                            _berekenHandmatigeTijden(
                              '',
                              _effectieveHandmatigePlanningDatum,
                              _shiftHours,
                            );
                          },
                        )
                      : const Icon(Icons.search_rounded),
                ),
                child: Text(
                  _gekozenOperatorIds.isNotEmpty
                      ? _gekozenOperatorNamen.join(', ')
                      : 'Klik hier om te zoeken…',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _gekozenOperatorIds.isNotEmpty
                        ? cs.onSurface
                        : cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: (_gekozenOperatorIds.isEmpty || _saving) ? null : _submitPlan,
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  (_text(_opdracht?['status']) == 'ingepland' &&
                          _text(_bestaandePlanningId).isNotEmpty)
                      ? 'Wijziging Opslaan'
                      : 'Definitief Inplannen',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(
    bool isDark,
    ColorScheme cs,
    String label,
    IconData icon,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: isDark ? const Color(0xFF1B1B23) : const Color(0xFFF5F5F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 1.2),
      ),
    );
  }
}

class _StepperCircleButton extends StatelessWidget {
  const _StepperCircleButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: cs.primary),
        ),
      ),
    );
  }
}
