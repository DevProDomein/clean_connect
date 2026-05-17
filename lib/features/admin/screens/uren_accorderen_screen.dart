import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/models/user_role.dart';
import '../../../core/supabase_client.dart';
import '../../../core/utils/payroll_calculation.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
/// Generator / administrator: ingediende operator-uren accorderen of corrigeren.
class UrenAccorderenScreen extends StatefulWidget {
  const UrenAccorderenScreen({super.key});

  @override
  State<UrenAccorderenScreen> createState() => _UrenAccorderenScreenState();
}

class _UrenAccorderenScreenState extends State<UrenAccorderenScreen> {
  static const Color _deepNavy = Color(0xFF1A237E);
  static const Color _brightBlue = Color(0xFF0052CC);
  static const Color _pageBg = Color(0xFFF2F4F8);

  static final _dateFmt = DateFormat('EEEE d MMMM yyyy', 'nl_NL');

  List<Map<String, dynamic>> _rows = [];
  Map<String, String> _operatorNames = {};
  bool _loading = true;
  String _error = '';
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

  /// null = alle operators
  String? _filterOperatorId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _canAccess(UserProvider up) =>
      up.isGenerator || up.role == UserRole.administrator;

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(' ', '');
    if (s.isEmpty) return 0;
    final direct = double.tryParse(s);
    if (direct != null) return direct;
    if (s.contains(',')) {
      return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  String _urenStatusNorm(Map<String, dynamic> r) =>
      _text(r['uren_status']).toLowerCase();

  /// PK van `opdracht_planning` — nooit `opdracht_id` verwarren.
  String _planningIdFromRow(Map<String, dynamic> row) {
    final direct = _text(row['id']);
    if (direct.isNotEmpty) return direct;

    final planningId = _text(row['planning_id']);
    if (planningId.isNotEmpty) return planningId;

    final nested = row['opdracht_planning'];
    if (nested is Map) {
      final m = Map<String, dynamic>.from(nested);
      final nid = _text(m['id']);
      if (nid.isNotEmpty) return nid;
    }
    return '';
  }

  DateTime? _parseShiftDay(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);
    final s = raw.toString().trim();
    if (s.length >= 10) {
      try {
        final d = DateTime.parse(s.substring(0, 10));
        return DateTime(d.year, d.month, d.day);
      } catch (_) {}
    }
    return null;
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _safeTime(dynamic timeValue) {
    if (timeValue == null) return '—';
    final t = timeValue.toString().trim();
    if (t.length >= 5) return t.substring(0, 5);
    return t.isEmpty ? '—' : t;
  }

  TimeOfDay? _timeOfDayFromRaw(dynamic v) {
    final s = _safeTime(v);
    if (s == '—' || s.length < 5) return null;
    final p = s.split(':');
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p.length > 1 ? p[1] : '0');
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  String _timeToDb(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Duration _workDurationMinutes(TimeOfDay start, TimeOfDay end) {
    final sm = start.hour * 60 + start.minute;
    var em = end.hour * 60 + end.minute;
    if (em <= sm) em += 24 * 60;
    return Duration(minutes: em - sm);
  }

  String _klantNaam(Map<String, dynamic> row) {
    final direct = row['bedrijfsnaam']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = row['opdrachten'];
    if (nested is Map) {
      final pj = nested['projecten'];
      if (pj is Map && pj['project_naam'] != null) {
        final p = pj['project_naam'].toString().trim();
        if (p.isNotEmpty) return p;
      }
      if (nested['bedrijfsnaam'] != null) {
        final b = nested['bedrijfsnaam'].toString().trim();
        if (b.isNotEmpty) return b;
      }
    }
    return 'Klant';
  }

  String _operatorName(Map<String, dynamic> row) {
    final id = _text(row['operator_id']);
    if (id.isEmpty) return 'Onbekend';
    final n = _operatorNames[id];
    if (n != null && n.isNotEmpty) return n;
    return id.length > 10 ? '${id.substring(0, 8)}…' : id;
  }

  double _plannedHoursFromRow(Map<String, dynamic> row) {
    final t = _asDouble(row['toegewezen_uren']);
    if (t > 0) return t;
    final s = _timeOfDayFromRaw(row['starttijd']);
    final e = _timeOfDayFromRaw(row['eindtijd']);
    if (s == null || e == null) return 0;
    return _workDurationMinutes(s, e).inMinutes / 60.0;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final client = AppSupabase.client;
      final from = DateTime.now().subtract(const Duration(days: 200));
      final to = DateTime.now().add(const Duration(days: 120));
      final fromStr = from.toIso8601String().split('T').first;
      final toStr = to.toIso8601String().split('T').first;

      final planningRes = await client
          .from('opdracht_planning')
          .select(
            'id, operator_id, opdracht_id, geplande_datum, starttijd, eindtijd, '
            'toegewezen_uren, werkelijke_starttijd, werkelijke_eindtijd, '
            'gewerkte_uren_decimaal, uren_status, bedrijfsnaam, '
            'operator:gebruikers(id, voornaam, achternaam, standaard_uurloon, '
            'contract_vaste_uren, contract_vast_salaris, contract_startdatum, '
            'contract_einddatum), '
            'opdrachten!opdracht_planning_opdracht_id_fkey(bedrijfsnaam, projecten(project_naam))',
          )
          .inFilter('uren_status', const ['open', 'ingediend', 'geaccordeerd'])
          .gte('geplande_datum', fromStr)
          .lte('geplande_datum', toStr)
          .order('geplande_datum', ascending: false)
          .limit(800);

      final list = (planningRes as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final ids = list
          .map((r) => _text(r['operator_id']))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final names = <String, String>{};
      if (ids.isNotEmpty) {
        try {
          final users = await client
              .from('gebruikers')
              .select(
                'id, voornaam, achternaam, standaard_uurloon, contract_vaste_uren, '
                'contract_vast_salaris',
              )
              .inFilter('id', ids);
          for (final u in users as List) {
            final m = Map<String, dynamic>.from(u as Map);
            final id = _text(m['id']);
            if (id.isEmpty) continue;
            final vn = _text(m['voornaam']);
            final an = _text(m['achternaam']);
            final full = '$vn $an'.trim();
            names[id] = full.isNotEmpty ? full : id;
          }
        } catch (_) {
          // Kolomnamen kunnen afwijken; lijst blijft bruikbaar met id.
        }
      }

      if (!mounted) return;
      setState(() {
        _rows = list;
        _operatorNames = names;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _dayHasStatus(DateTime day, String status) {
    final key = _dayOnly(day);
    for (final r in _rows) {
      if (_urenStatusNorm(r) != status) continue;
      final d = _parseShiftDay(r['geplande_datum']);
      if (d != null && _dayOnly(d) == key) return true;
    }
    return false;
  }

  String get _maandSleutel =>
      '${_focusedDay.year}-${_focusedDay.month.toString().padLeft(2, '0')}';

  /// Kalendermaand volledig voorbij (mei sluiten pas in juni).
  bool get _isFocusedMaandVoorbij {
    final nu = DateTime.now();
    return _focusedDay.year < nu.year ||
        (_focusedDay.year == nu.year && _focusedDay.month < nu.month);
  }

  bool _isInFocusedMonth(DateTime day) =>
      day.year == _focusedDay.year && day.month == _focusedDay.month;

  bool _passesOperatorFilter(Map<String, dynamic> r) {
    if (_filterOperatorId == null) return true;
    return _text(r['operator_id']) == _filterOperatorId;
  }

  List<Map<String, dynamic>> _sortRowsByDateTime(
    List<Map<String, dynamic>> rows,
  ) {
    return [...rows]..sort((a, b) {
        final da = _parseShiftDay(a['geplande_datum']);
        final db = _parseShiftDay(b['geplande_datum']);
        if (da != null && db != null) {
          final c = da.compareTo(db);
          if (c != 0) return c;
        }
        return _safeTime(a['starttijd']).compareTo(_safeTime(b['starttijd']));
      });
  }

  List<Map<String, dynamic>> _rowsIngediendForSelectedDay() {
    final sel = _selectedDay ?? _focusedDay;
    final key = _dayOnly(sel);
    return _sortRowsByDateTime(
      _rows.where((r) {
        if (_urenStatusNorm(r) != 'ingediend') return false;
        final d = _parseShiftDay(r['geplande_datum']);
        if (d == null || _dayOnly(d) != key) return false;
        return _passesOperatorFilter(r);
      }).toList(),
    );
  }

  List<Map<String, dynamic>> _rowsIngediendForMonthExcludingSelectedDay() {
    final selKey = _dayOnly(_selectedDay ?? _focusedDay);
    return _sortRowsByDateTime(
      _rows.where((r) {
        if (_urenStatusNorm(r) != 'ingediend') return false;
        final d = _parseShiftDay(r['geplande_datum']);
        if (d == null || !_isInFocusedMonth(d)) return false;
        if (_dayOnly(d) == selKey) return false;
        return _passesOperatorFilter(r);
      }).toList(),
    );
  }

  List<Map<String, dynamic>> _rowsInFocusedMonth() {
    return _takenDezeMaand();
  }

  /// Taken in de actieve kalendermaand ([_focusedDay]), lokaal gefilterd op [_rows].
  List<Map<String, dynamic>> _takenDezeMaand() {
    return _rows.where((taak) {
      final taakDatum = DateTime.tryParse(
        taak['geplande_datum']?.toString() ?? '',
      );
      if (taakDatum == null) {
        final parsed = _parseShiftDay(taak['geplande_datum']);
        if (parsed == null) return false;
        return parsed.year == _focusedDay.year &&
            parsed.month == _focusedDay.month;
      }
      return taakDatum.year == _focusedDay.year &&
          taakDatum.month == _focusedDay.month;
    }).toList();
  }

  /// `status` ontbreekt soms in de payload → behandel als ingepland (actieve planning).
  bool _isIngeplandePlanning(Map<String, dynamic> t) {
    final raw = t['status'];
    if (raw == null) return true;
    final status = raw.toString().trim();
    if (status.isEmpty) return true;
    return status == 'ingepland';
  }

  ({int open, int ingediend, int geaccordeerd}) _maandPlanningStatusCounts() {
    final takenDezeMaand = _takenDezeMaand();

    var aantalOpen = 0;
    var aantalIngediend = 0;
    var aantalGeaccordeerd = 0;

    for (final t in takenDezeMaand) {
      if (!_passesOperatorFilter(t)) continue;
      if (!_isIngeplandePlanning(t)) continue;

      final urenStatusRaw = t['uren_status'];
      final urenStatus = urenStatusRaw?.toString().trim();

      if (urenStatus == null || urenStatus.isEmpty || urenStatus == 'open') {
        aantalOpen++;
      } else if (urenStatus == 'ingediend') {
        aantalIngediend++;
      } else if (urenStatus == 'geaccordeerd') {
        aantalGeaccordeerd++;
      }
    }

    return (
      open: aantalOpen,
      ingediend: aantalIngediend,
      geaccordeerd: aantalGeaccordeerd,
    );
  }

  ({double open, double ingediend, double geaccordeerd}) _maandUrenAnalytics() {
    var open = 0.0;
    var ingediend = 0.0;
    var geacc = 0.0;
    for (final r in _rowsInFocusedMonth()) {
      if (!_passesOperatorFilter(r)) continue;
      final u = _asDouble(r['gewerkte_uren_decimaal']);
      switch (_urenStatusNorm(r)) {
        case 'open':
          open += u;
        case 'ingediend':
          ingediend += u;
        case 'geaccordeerd':
          geacc += u;
      }
    }
    return (open: open, ingediend: ingediend, geaccordeerd: geacc);
  }

  List<Map<String, dynamic>> _rowsGeaccordeerdForFocusedMonth() {
    return _sortRowsByDateTime(
      _rowsInFocusedMonth().where((r) {
        if (_urenStatusNorm(r) != 'geaccordeerd') return false;
        return _passesOperatorFilter(r);
      }).toList(),
    );
  }

  Future<List<Map<String, dynamic>>> _operatorsMetGeaccordeerdeUrenDezeMaand() async {
    final ids = <String>{};
    for (final r in _rowsInFocusedMonth()) {
      if (_urenStatusNorm(r) != 'geaccordeerd') continue;
      final id = _text(r['operator_id']);
      if (id.isNotEmpty) ids.add(id);
    }
    if (ids.isEmpty) return [];

    final res = await AppSupabase.client
        .from('gebruikers')
        .select(
          'id, voornaam, achternaam, standaard_uurloon, contract_vaste_uren, '
          'contract_vast_salaris, contract_startdatum, contract_einddatum',
        )
        .inFilter('id', ids.toList())
        .order('achternaam', ascending: true);

    return (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map(_verrijkOperatorUitPlanningEmbed)
        .toList();
  }

  Map<String, dynamic> _verrijkOperatorUitPlanningEmbed(
    Map<String, dynamic> operator,
  ) {
    final id = _text(operator['id']);
    if (id.isEmpty) return operator;

    final merged = Map<String, dynamic>.from(operator);
    for (final r in _rowsInFocusedMonth()) {
      if (_text(r['operator_id']) != id) continue;
      final nested = r['operator'];
      if (nested is! Map) continue;
      final embed = Map<String, dynamic>.from(nested);
      for (final key in [
        'id',
        'voornaam',
        'achternaam',
        'standaard_uurloon',
        'contract_vaste_uren',
        'contract_vast_salaris',
        'contract_startdatum',
        'contract_einddatum',
      ]) {
        final v = embed[key];
        if (v != null && v.toString().trim().isNotEmpty) {
          merged[key] = v;
        }
      }
      break;
    }
    return merged;
  }

  Future<void> _openMaandSluitingModal() async {
    if (!mounted) return;
    try {
      final operators = await _operatorsMetGeaccordeerdeUrenDezeMaand();

      if (!mounted) return;
      if (operators.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Geen operators met geaccordeerde uren in deze maand om af te sluiten.',
            ),
          ),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (ctx) => _MaandSluitingModal(
          maandSleutel: _maandSleutel,
          maandLabel: DateFormat.yMMMM('nl_NL').format(
            DateTime(_focusedDay.year, _focusedDay.month),
          ),
          focusedDay: DateTime(_focusedDay.year, _focusedDay.month),
          operators: operators,
          planningRows: _rowsInFocusedMonth(),
          operatorNames: _operatorNames,
          onSuccess: _load,
          parentContext: context,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kan maandsluiting niet openen: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  Widget _buildBottomPayrollBar() {
    final a = _maandUrenAnalytics();
    final aantalGeaccordeerd = _maandPlanningStatusCounts().geaccordeerd;
    final isMaandVoorbij = _isFocusedMaandVoorbij;
    final kanAfsluiten = aantalGeaccordeerd > 0 && isMaandVoorbij;
    final knopLabel = !isMaandVoorbij && aantalGeaccordeerd > 0
        ? 'Maand nog niet voorbij'
        : 'Maand Afsluiten (Loonstrook genereren)';
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Open: ${_formatUrenNl(a.open)} u | '
            'Ingediend: ${_formatUrenNl(a.ingediend)} u | '
            'Geaccordeerd: ${_formatUrenNl(a.geaccordeerd)} u',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _loading || !kanAfsluiten ? null : _openMaandSluitingModal,
            icon: const Icon(Icons.lock_clock_rounded),
            label: Text(
              knopLabel,
              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kanAfsluiten ? Colors.green : Colors.grey.shade400,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<DropdownMenuItem<String?>> _operatorFilterItems() {
    final ids =
        _rows
            .map((r) => _text(r['operator_id']))
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList()
          ..sort(
            (a, b) =>
                (_operatorNames[a] ?? a).compareTo(_operatorNames[b] ?? b),
          );
    return [
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Alle operators'),
      ),
      ...ids.map(
        (id) => DropdownMenuItem<String?>(
          value: id,
          child: Text(_operatorNames[id] ?? id),
        ),
      ),
    ];
  }

  Future<void> _enqueueOperatorPush({
    required String operatorUserId,
    required String titel,
    required String bericht,
  }) async {
    if (operatorUserId.isEmpty) return;
    try {
      await AppSupabase.client.from('push_queue').insert({
        'operator_id': operatorUserId,
        'titel': titel,
        'bericht': bericht,
      });
    } catch (_) {
      // Push-falen mag accorderen niet blokkeren; UI toont al snack op succes.
    }
  }

  String _formatUrenNl(double d) {
    if (d == d.roundToDouble()) return d.toInt().toString();
    return NumberFormat.decimalPattern('nl_NL').format(d);
  }

  Future<void> _onRowTap(Map<String, dynamic> row) async {
    final st = _urenStatusNorm(row);
    if (st == 'ingediend') {
      await _openAccordeerDialog(row);
    } else {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Geaccordeerd'),
          content: Text(
            '${_klantNaam(row)}\n${_operatorName(row)}\n'
            'Gewerkte uren: ${_formatUrenNl(_asDouble(row['gewerkte_uren_decimaal']))} u\n'
            'Werkelijk: ${_safeTime(row['werkelijke_starttijd'])} – ${_safeTime(row['werkelijke_eindtijd'])}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Sluiten'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _openAccordeerDialog(Map<String, dynamic> row) async {
    final planningId = _planningIdFromRow(row);
    if (planningId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Systeemfout: Kan planning ID niet vinden.'),
        ),
      );
      return;
    }

    final day = _parseShiftDay(row['geplande_datum']);
    final datumStr = day != null
        ? _dateFmt.format(day)
        : _text(row['geplande_datum']);

    final plannedS =
        _timeOfDayFromRaw(row['starttijd']) ??
        const TimeOfDay(hour: 8, minute: 0);
    final plannedE =
        _timeOfDayFromRaw(row['eindtijd']) ??
        const TimeOfDay(hour: 17, minute: 0);

    final submittedS = _timeOfDayFromRaw(row['werkelijke_starttijd']);
    final submittedE = _timeOfDayFromRaw(row['werkelijke_eindtijd']);
    final initialS = submittedS ?? plannedS;
    final initialE = submittedE ?? plannedE;

    final baselineS = submittedS ?? plannedS;
    final baselineE = submittedE ?? plannedE;
    final submittedDec = _asDouble(row['gewerkte_uren_decimaal']);

    final operatorId = _text(row['operator_id']);
    final klant = _klantNaam(row);
    final plannedUren = _plannedHoursFromRow(row);

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _AccordeerDialogBody(
          datumStr: datumStr,
          operatorNaam: _operatorName(row),
          klant: klant,
          plannedStart: plannedS,
          plannedEnd: plannedE,
          plannedUren: plannedUren,
          initialPickStart: initialS,
          initialPickEnd: initialE,
          baselineStart: baselineS,
          baselineEnd: baselineE,
          submittedDec: submittedDec,
          operatorUserId: operatorId,
          deepNavy: _deepNavy,
          brightBlue: _brightBlue,
          planningId: planningId,
          onReject: () async {
            final rejectResponse = await AppSupabase.client
                .from('opdracht_planning')
                .update({
                  'uren_status': 'open',
                  'werkelijke_starttijd': null,
                  'werkelijke_eindtijd': null,
                  'is_gecorrigeerd_door_beheerder': false,
                  'originele_operator_input': null,
                })
                .eq('id', planningId)
                .select();

            if ((rejectResponse as List).isEmpty) {
              throw Exception(
                'Database weigert de update. Check RLS of een foutief ID: $planningId',
              );
            }

            try {
              await AppSupabase.client.from('push_queue').insert({
                'operator_id': operatorId,
                'titel': 'Uren afgekeurd ❌',
                'bericht':
                    'Je ingediende uren voor $klant zijn afgekeurd door de beheerder. '
                    'Vul ze a.u.b. opnieuw (correct) in.',
              });
            } catch (e) {
              debugPrint('Fout bij push_queue insert: $e');
            }
          },
          onApprove:
              ({
                required TimeOfDay pickStart,
                required TimeOfDay pickEnd,
                required bool timesChangedFromOperatorSubmission,
                required String oldRangeLabel,
                required String newRangeLabel,
              }) async {
                final dur = _workDurationMinutes(pickStart, pickEnd);
                final urenDec = dur.inMinutes / 60.0;

                final update = <String, dynamic>{
                  'werkelijke_starttijd': _timeToDb(pickStart),
                  'werkelijke_eindtijd': _timeToDb(pickEnd),
                  'gewerkte_uren_decimaal': urenDec,
                  'uren_status': 'geaccordeerd',
                };

                if (timesChangedFromOperatorSubmission) {
                  update['originele_operator_input'] = {
                    'werkelijke_starttijd': _timeToDb(baselineS),
                    'werkelijke_eindtijd': _timeToDb(baselineE),
                    'gewerkte_uren_decimaal': submittedDec,
                  };
                  update['is_gecorrigeerd_door_beheerder'] = true;
                }

                final updateResponse = await AppSupabase.client
                    .from('opdracht_planning')
                    .update(update)
                    .eq('id', planningId)
                    .select();

                if ((updateResponse as List).isEmpty) {
                  throw Exception(
                    'Database weigert de update. Check RLS of een foutief ID: $planningId',
                  );
                }

                if (timesChangedFromOperatorSubmission) {
                  await _enqueueOperatorPush(
                    operatorUserId: operatorId,
                    titel: 'Uren aangepast',
                    bericht:
                        'Je uren voor $klant zijn aangepast en goedgekeurd. $oldRangeLabel -> $newRangeLabel. Let de volgende keer goed op.',
                  );
                } else {
                  await _enqueueOperatorPush(
                    operatorUserId: operatorId,
                    titel: 'Uren goedgekeurd',
                    bericht: 'Je uren voor $klant zijn goedgekeurd! ✅',
                  );
                }
              },
          parentContext: context,
        );
      },
    );

    if (result == true && mounted) {
      await _load();
    }
  }

  Widget _analyticsRow() {
    final counts = _maandPlanningStatusCounts();
    final aantalOpen = counts.open;
    final aantalIngediend = counts.ingediend;
    final aantalGeaccordeerd = counts.geaccordeerd;

    return Row(
      children: [
        Expanded(
          child: _kpiTile(
            label: 'Nog in te vullen',
            value: '$aantalOpen',
            icon: Icons.edit_calendar_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiTile(
            label: 'Te accorderen',
            value: '$aantalIngediend',
            icon: Icons.hourglass_top_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiTile(
            label: 'Geaccordeerd',
            value: '$aantalGeaccordeerd',
            icon: Icons.verified_rounded,
          ),
        ),
      ],
    );
  }

  Widget _kpiTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _brightBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _deepNavy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    if (!_canAccess(up)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Uren accorderen')),
        drawer: const AppDrawer(),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Je hebt geen toegang tot dit scherm.'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _pageBg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        title: Text(
          'Uren accorderen',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: const Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error, textAlign: TextAlign.center),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _analyticsRow(),
                          const SizedBox(height: 16),
                          TableCalendar<String>(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2035, 12, 31),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
                    calendarFormat: _calendarFormat,
                    availableCalendarFormats: const {
                      CalendarFormat.month: 'Maand',
                      CalendarFormat.twoWeeks: '2 weken',
                    },
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    locale: 'nl_NL',
                    onFormatChanged: (f) => setState(() => _calendarFormat = f),
                    onDaySelected: (sel, foc) {
                      setState(() {
                        _selectedDay = sel;
                        _focusedDay = foc;
                      });
                    },
                    onPageChanged: (foc) => setState(() => _focusedDay = foc),
                    eventLoader: (day) {
                      final tags = <String>[];
                      if (_dayHasStatus(day, 'ingediend')) tags.add('i');
                      if (_dayHasStatus(day, 'geaccordeerd')) tags.add('g');
                      return tags;
                    },
                    calendarStyle: CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: _brightBlue.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: const BoxDecoration(
                        color: _deepNavy,
                        shape: BoxShape.circle,
                      ),
                    ),
                    calendarBuilders: CalendarBuilders(
                      markerBuilder: (context, day, events) {
                        if (events.isEmpty) return const SizedBox.shrink();
                        final hasI = events.contains('i');
                        final hasG = events.contains('g');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (hasI)
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE53935),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (hasG)
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2E7D32),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            labelText: 'Operator-filter',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              isExpanded: true,
                              value: _filterOperatorId,
                              items: _operatorFilterItems(),
                              onChanged: (v) =>
                                  setState(() => _filterOperatorId = v),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _toonOperatorFinancienModal,
                        icon: const Icon(Icons.account_balance_wallet),
                        label: const Text('Beheer Operator Financiën'),
                      ),
                    ],
                          ),
                          const SizedBox(height: 16),
                          ..._buildSplitAccordeerLists(),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildBottomPayrollBar(),
              ],
            ),
    );
  }

  String _formatTaakDatumKort(DateTime d) {
    try {
      return DateFormat('E d MMM', 'nl_NL').format(d);
    } catch (_) {
      return DateFormat('E d MMM').format(d);
    }
  }

  Widget _buildTaskCard(
    Map<String, dynamic> row, {
    required bool dayHighlight,
    required bool showDate,
  }) {
    final border = const Color(0xFFE53935);
    final day = _parseShiftDay(row['geplande_datum']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: dayHighlight ? Colors.blue.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onRowTap(row),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dayHighlight ? Colors.blue.shade400 : border,
                width: dayHighlight ? 1.5 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showDate && day != null) ...[
                  Text(
                    _formatTaakDatumKort(day),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: _brightBlue,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _klantNaam(row),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: border.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Ingediend',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: border,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _operatorName(row),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Gepland: ${_safeTime(row['starttijd'])} – ${_safeTime(row['eindtijd'])} · '
                  'Gewerkt: ${_formatUrenNl(_asDouble(row['gewerkte_uren_decimaal']))} u',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIngediendListSection(
    String title,
    List<Map<String, dynamic>> items, {
    required bool dayHighlight,
    required bool showDate,
    required String emptyText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              emptyText,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) => _buildTaskCard(
              items[index],
              dayHighlight: dayHighlight,
              showDate: showDate,
            ),
          ),
      ],
    );
  }

  List<Widget> _buildSplitAccordeerLists() {
    final sel = _selectedDay ?? _focusedDay;
    final dagItems = _rowsIngediendForSelectedDay();
    final maandItems = _rowsIngediendForMonthExcludingSelectedDay();
    final dagTitel =
        'Te accorderen op ${_dateFmt.format(sel)}';

    return [
      _buildIngediendListSection(
        dagTitel,
        dagItems,
        dayHighlight: true,
        showDate: false,
        emptyText: 'Geen ingediende uren op deze dag.',
      ),
      const SizedBox(height: 20),
      _buildIngediendListSection(
        'Alle openstaande accorderingen in deze maand',
        maandItems,
        dayHighlight: false,
        showDate: true,
        emptyText: 'Geen andere openstaande accorderingen in deze maand.',
      ),
      const SizedBox(height: 20),
      _buildGeaccordeerdMaandSection(),
    ];
  }

  Widget _buildGeaccordeerdMaandCard(Map<String, dynamic> row) {
    final day = _parseShiftDay(row['geplande_datum']);
    final werkelijk =
        '${_safeTime(row['werkelijke_starttijd'])} – ${_safeTime(row['werkelijke_eindtijd'])}';
    final gepland = '${_safeTime(row['starttijd'])} – ${_safeTime(row['eindtijd'])}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onRowTap(row),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (day != null)
                  Text(
                    _formatTaakDatumKort(day),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF166534),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  _operatorName(row),
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF166534),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _klantNaam(row),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Werkelijk: $werkelijk · Gepland: $gepland',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gewerkte uren: ${_formatUrenNl(_asDouble(row['gewerkte_uren_decimaal']))} u',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeaccordeerdMaandSection() {
    final items = _rowsGeaccordeerdForFocusedMonth();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Reeds geaccordeerd deze maand',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: const Color(0xFF166534),
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Nog geen geaccordeerde uren in deze maand.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) =>
                _buildGeaccordeerdMaandCard(items[index]),
          ),
      ],
    );
  }

  List<String> _operatorIdsForFinModal() {
    final ids = <String>{};
    for (final r in _rows) {
      final id = _text(r['operator_id']);
      if (id.isNotEmpty) ids.add(id);
    }
    for (final k in _operatorNames.keys) {
      if (k.isNotEmpty) ids.add(k);
    }
    final list = ids.toList()
      ..sort(
        (a, b) => (_operatorNames[a] ?? a).toLowerCase().compareTo(
              (_operatorNames[b] ?? b).toLowerCase(),
            ),
      );
    return list;
  }

  Future<void> _toonOperatorFinancienModal() async {
    if (!mounted) return;
    final ids = _operatorIdsForFinModal();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _OperatorFinancienModal(
        operatorIds: ids,
        operatorNames: Map<String, String>.from(_operatorNames),
        onSaved: () async {
          if (mounted) await _load();
        },
      ),
    );
  }
}

class _MaandSluitingModal extends StatefulWidget {
  const _MaandSluitingModal({
    required this.maandSleutel,
    required this.maandLabel,
    required this.focusedDay,
    required this.operators,
    required this.planningRows,
    required this.operatorNames,
    required this.onSuccess,
    required this.parentContext,
  });

  final String maandSleutel;
  final String maandLabel;
  final DateTime focusedDay;
  final List<Map<String, dynamic>> operators;
  final List<Map<String, dynamic>> planningRows;
  final Map<String, String> operatorNames;
  final Future<void> Function() onSuccess;
  final BuildContext parentContext;

  @override
  State<_MaandSluitingModal> createState() => _MaandSluitingModalState();
}

class _MaandSluitingModalState extends State<_MaandSluitingModal> {
  static final _eur = NumberFormat.currency(
    locale: 'nl_NL',
    symbol: '€',
    decimalDigits: 2,
  );

  String? _selectedOperatorId;
  double _voorschotBedrag = 0;
  bool _loadingVoorschot = false;
  bool _saving = false;

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(' ', '');
    if (s.isEmpty) return 0;
    final direct = double.tryParse(s);
    if (direct != null) return direct;
    if (s.contains(',')) {
      return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  String _urenStatusNorm(Map<String, dynamic> r) =>
      _text(r['uren_status']).toLowerCase();

  String _operatorLabel(Map<String, dynamic> op) {
    final vn = _text(op['voornaam']);
    final an = _text(op['achternaam']);
    final full = '$vn $an'.trim();
    if (full.isNotEmpty) return full;
    final id = _text(op['id']);
    return widget.operatorNames[id]?.isNotEmpty == true
        ? widget.operatorNames[id]!
        : 'Operator $id';
  }

  Map<String, dynamic>? _operatorById(String id) {
    for (final op in widget.operators) {
      if (_text(op['id']) == id) return op;
    }
    return null;
  }

  Map<String, dynamic> _operatorDataVoorBerekening(String operatorId) {
    final direct = _operatorById(operatorId);
    final merged = Map<String, dynamic>.from(direct ?? {'id': operatorId});

    for (final r in _planningVoorOperator(operatorId)) {
      final nested = r['operator'];
      if (nested is! Map) continue;
      final embed = Map<String, dynamic>.from(nested);
      for (final key in [
        'voornaam',
        'achternaam',
        'standaard_uurloon',
        'contract_vaste_uren',
        'contract_vast_salaris',
        'contract_startdatum',
        'contract_einddatum',
      ]) {
        final v = embed[key];
        if (v != null && v.toString().trim().isNotEmpty) {
          merged[key] = v;
        }
      }
    }
    return merged;
  }

  double _veiligParsen(dynamic waarde) {
    if (waarde == null) return 0.0;
    if (waarde is num) return waarde.toDouble();
    return double.tryParse(waarde.toString().replaceAll(',', '.')) ?? 0.0;
  }

  List<Map<String, dynamic>> _planningVoorOperator(String operatorId) {
    return widget.planningRows
        .where((r) => _text(r['operator_id']) == operatorId)
        .toList();
  }

  ({int open, int ingediend, int geaccordeerd}) _statusTelling(
    String operatorId,
  ) {
    var open = 0;
    var ingediend = 0;
    var geacc = 0;
    for (final r in _planningVoorOperator(operatorId)) {
      switch (_urenStatusNorm(r)) {
        case 'open':
          open++;
        case 'ingediend':
          ingediend++;
        case 'geaccordeerd':
          geacc++;
      }
    }
    return (open: open, ingediend: ingediend, geaccordeerd: geacc);
  }

  List<Map<String, dynamic>> _geaccordeerdeTakenVoorOperator(String operatorId) {
    return _planningVoorOperator(operatorId)
        .where((r) => _urenStatusNorm(r) == 'geaccordeerd')
        .toList();
  }

  ({double uren, double bruto}) _berekenMaandSalaris(
    Map<String, dynamic> operatorData,
    List<Map<String, dynamic>> geaccordeerdeTaken,
    DateTime focusedDay,
  ) {
    final totaalGewerkteUren =
        PayrollCalculation.totaalGewerkteUren(geaccordeerdeTaken);

    // ignore: avoid_print
    print('--- RAW OPERATOR DATA DUMP ---');
    // ignore: avoid_print
    print(operatorData);
    // ignore: avoid_print
    print('------------------------------');

    final uurTarief = _veiligParsen(operatorData['standaard_uurloon']);
    final vastSalaris = _veiligParsen(operatorData['contract_vast_salaris']);
    final vasteUren = _veiligParsen(operatorData['contract_vaste_uren']);

    final isGeldigVastContract =
        PayrollCalculation.isGeldigVastContractVoorMaand(operatorData, focusedDay);

    final double berekendBruto;
    if (isGeldigVastContract) {
      final overwerkUren = totaalGewerkteUren > vasteUren
          ? (totaalGewerkteUren - vasteUren)
          : 0.0;
      berekendBruto = vastSalaris + (overwerkUren * uurTarief);
    } else {
      berekendBruto = totaalGewerkteUren * uurTarief;
    }

    // ignore: avoid_print
    print('=== SALARIS BEREKENING X-RAY ===');
    // ignore: avoid_print
    print('Operator: ${operatorData['voornaam']} ${operatorData['achternaam']}');
    // ignore: avoid_print
    print('Uurtarief geparsed: €$uurTarief');
    // ignore: avoid_print
    print('Totaal gewerkte uren: $totaalGewerkteUren');
    // ignore: avoid_print
    print('Is Vast Contract: $isGeldigVastContract');
    // ignore: avoid_print
    print('Berekend Bruto Resultaat: €$berekendBruto');
    // ignore: avoid_print
    print('=================================');

    return (uren: totaalGewerkteUren, bruto: berekendBruto);
  }

  Future<void> _onOperatorChanged(String? id) async {
    setState(() {
      _selectedOperatorId = id;
      _voorschotBedrag = 0;
      _loadingVoorschot = id != null && id.isNotEmpty;
    });
    if (id == null || id.isEmpty) return;
    try {
      final row = await AppSupabase.client
          .from('operator_voorschotten')
          .select('voorschot_bedrag')
          .eq('operator_id', id)
          .eq('maand_sleutel', widget.maandSleutel)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _voorschotBedrag = row == null
            ? 0
            : _asDouble(
                Map<String, dynamic>.from(row as Map)['voorschot_bedrag'],
              );
        _loadingVoorschot = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingVoorschot = false);
      }
    }
  }

  Future<void> _bevestigSluiting(double berekendBruto) async {
    final id = _selectedOperatorId;
    if (id == null || id.isEmpty) return;
    setState(() => _saving = true);
    try {
      final response = await AppSupabase.client
          .from('operator_uitbetalingen')
          .upsert({
            'operator_id': id,
            'maand_sleutel': widget.maandSleutel,
            'berekend_bruto': berekendBruto,
            'verrekend_voorschot': _voorschotBedrag,
            'is_betaald': false,
          }, onConflict: 'operator_id,maand_sleutel')
          .select();

      if ((response as List).isEmpty) {
        throw Exception('Maandsluiting niet opgeslagen (RLS of constraint).');
      }

      await widget.onSuccess();
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!widget.parentContext.mounted) return;
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        const SnackBar(
          content: Text(
            'Maand afgesloten! Ga naar Salarisadministratie om uit te betalen.',
          ),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opslaan mislukt: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _operatorIdInLijst(String? id) {
    if (id == null || id.isEmpty) return false;
    return widget.operators.any((op) => _text(op['id']) == id);
  }

  @override
  Widget build(BuildContext context) {
    final opId = _operatorIdInLijst(_selectedOperatorId)
        ? _selectedOperatorId
        : null;
    final operator = opId == null ? null : _operatorById(opId);
    double? berekendBruto;
    double geaccUren = 0;
    int openCount = 0;
    int ingediendCount = 0;
    int geaccordeerdCount = 0;
    var scenarioPerfect = false;
    var needsOverride = false;

    Map<String, dynamic>? operatorData;
    if (opId != null) {
      operatorData = _operatorDataVoorBerekening(opId);
      final telling = _statusTelling(opId);
      openCount = telling.open;
      ingediendCount = telling.ingediend;
      geaccordeerdCount = telling.geaccordeerd;
      needsOverride = openCount > 0 || ingediendCount > 0;
      scenarioPerfect =
          !needsOverride && geaccordeerdCount > 0;

      final geaccTake = _geaccordeerdeTakenVoorOperator(opId);
      final salaris = _berekenMaandSalaris(
        operatorData,
        geaccTake,
        widget.focusedDay,
      );
      geaccUren = salaris.uren;
      berekendBruto = salaris.bruto;
    }

    final isGeldigVastContract = operatorData != null &&
        PayrollCalculation.isGeldigVastContractVoorMaand(
          operatorData,
          widget.focusedDay,
        );
    final heeftVastBasissalarisZonderUren = isGeldigVastContract &&
        geaccUren == 0 &&
        geaccordeerdCount == 0;

    return AlertDialog(
      title: Text(
        'Maand afsluiten — ${widget.maandLabel}',
        style: GoogleFonts.inter(fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.operators.isEmpty)
                Text(
                  'Geen operators met geaccordeerde uren in deze maand.',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  key: ValueKey<String?>(opId),
                  initialValue: opId,
                  decoration: const InputDecoration(
                    labelText: 'Selecteer Operator voor Loonstrook',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Kies een operator'),
                  items: widget.operators
                      .map(
                        (op) => DropdownMenuItem<String>(
                          value: _text(op['id']),
                          child: Text(_operatorLabel(op)),
                        ),
                      )
                      .toList(),
                  onChanged: _saving ? null : _onOperatorChanged,
                ),
              if (_loadingVoorschot) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ] else if (opId != null && operator != null) ...[
                const SizedBox(height: 16),
                if (scenarioPerfect)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF166534).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      'Alle uren van deze operator zijn ingediend en geaccordeerd! '
                      'De maand kan veilig worden afgesloten.',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF166534),
                      ),
                    ),
                  )
                else if (needsOverride)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade400),
                    ),
                    child: Text(
                      'Let op: Deze operator heeft nog $openCount oningevulde en '
                      '$ingediendCount ongeaccordeerde diensten staan. Je kunt de '
                      'maand handmatig afsluiten, maar deze uren tellen dan niet meer '
                      'mee voor deze loonstrook.',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  )
                else if (heeftVastBasissalarisZonderUren)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Text(
                      'Geen geaccordeerde uren deze maand. Geldig vast contract '
                      'voor deze periode — basissalaris wordt toegepast.',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Geaccordeerde uren (loonstrook): '
                  '${geaccUren.toStringAsFixed(2).replaceAll('.', ',')} u',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Voorschot deze maand: ${_eur.format(_voorschotBedrag)}',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Berekend bruto: ${_eur.format(berekendBruto ?? 0)}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuleren'),
        ),
        if (widget.operators.isNotEmpty &&
            opId != null &&
            operator != null &&
            berekendBruto != null &&
            !_loadingVoorschot)
          FilledButton(
            onPressed: _saving
                ? null
                : () => _bevestigSluiting(berekendBruto!),
            style: FilledButton.styleFrom(
              backgroundColor: needsOverride
                  ? Colors.orange.shade800
                  : const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Bevestig & Sluit Maand (Salaris: ${_eur.format(berekendBruto)})',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                  ),
          ),
      ],
    );
  }
}

class _OperatorFinancienModal extends StatefulWidget {
  const _OperatorFinancienModal({
    required this.operatorIds,
    required this.operatorNames,
    required this.onSaved,
  });

  final List<String> operatorIds;
  final Map<String, String> operatorNames;
  final Future<void> Function() onSaved;

  @override
  State<_OperatorFinancienModal> createState() =>
      _OperatorFinancienModalState();
}

class _OperatorFinancienModalState extends State<_OperatorFinancienModal> {
  static String get _maandSleutel =>
      '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

  String? _selectedId;
  final _vasteUrenCtl = TextEditingController();
  final _vastSalarisCtl = TextEditingController();
  final _voorschotCtl = TextEditingController();
  DateTime? _contractStart;
  DateTime? _contractEnd;
  String? _contractBijlageUrl;
  bool _isOnbepaaldeTijd = false;
  bool _loadingData = false;
  bool _saving = false;
  String? _loadErr;

  @override
  void initState() {
    super.initState();
    if (widget.operatorIds.isNotEmpty) {
      _selectedId = widget.operatorIds.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_selectedId != null) _loadVoorOperator(_selectedId!);
      });
    }
  }

  @override
  void dispose() {
    _vasteUrenCtl.dispose();
    _vastSalarisCtl.dispose();
    _voorschotCtl.dispose();
    super.dispose();
  }

  String _trim(dynamic v) => (v ?? '').toString().trim();

  DateTime? _parseIsoDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);
    final s = raw.toString().trim();
    if (s.length >= 10) {
      try {
        final d = DateTime.parse(s.substring(0, 10));
        return DateTime(d.year, d.month, d.day);
      } catch (_) {}
    }
    return null;
  }

  double? _parseMoney(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final d = double.tryParse(t.replaceAll(',', '.'));
    if (d != null) return d;
    return double.tryParse(t.replaceAll('.', '').replaceAll(',', '.'));
  }

  Future<void> _loadVoorOperator(String id) async {
    setState(() {
      _loadingData = true;
      _loadErr = null;
      _vasteUrenCtl.clear();
      _vastSalarisCtl.clear();
      _voorschotCtl.clear();
      _contractStart = null;
      _contractEnd = null;
      _contractBijlageUrl = null;
      _isOnbepaaldeTijd = false;
    });
    try {
      final g = await AppSupabase.client
          .from('gebruikers')
          .select(
            'id, contract_vaste_uren, contract_vast_salaris, '
            'contract_startdatum, contract_einddatum, contract_bijlage_url',
          )
          .eq('id', id)
          .maybeSingle();

      final v = await AppSupabase.client
          .from('operator_voorschotten')
          .select()
          .eq('operator_id', id)
          .eq('maand_sleutel', _maandSleutel)
          .maybeSingle();

      if (!mounted) return;
      if (g != null) {
        final m = Map<String, dynamic>.from(g as Map);
        final uren = m['contract_vaste_uren'];
        if (uren != null) {
          _vasteUrenCtl.text = uren is num && uren % 1 == 0
              ? uren.toInt().toString()
              : uren.toString();
        }
        final sal = m['contract_vast_salaris'];
        if (sal != null) {
          _vastSalarisCtl.text = sal is num
              ? sal.toString().replaceAll('.', ',')
              : _trim(sal);
        }
        _contractStart = _parseIsoDate(m['contract_startdatum']);
        _contractEnd = _parseIsoDate(m['contract_einddatum']);
        _isOnbepaaldeTijd = _contractEnd == null;
        final url = _trim(m['contract_bijlage_url']);
        _contractBijlageUrl = url.isEmpty ? null : url;
      }
      if (v != null) {
        final vm = Map<String, dynamic>.from(v as Map);
        final amt = vm['voorschot_bedrag'];
        if (amt != null) {
          if (amt is num) {
            _voorschotCtl.text = amt.toString().replaceAll('.', ',');
          } else {
            _voorschotCtl.text = _trim(amt);
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadErr = e.toString());
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _pickContractPdf() async {
    final id = _selectedId;
    if (id == null || id.isEmpty) return;
    try {
      const group = XTypeGroup(label: 'PDF', extensions: ['pdf']);
      final file = await openFile(acceptedTypeGroups: const [group]);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path =
          '$id/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await AppSupabase.client.storage.from('contracten').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: true,
            ),
          );
      final url =
          AppSupabase.client.storage.from('contracten').getPublicUrl(path);
      if (!mounted) return;
      setState(() => _contractBijlageUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contract geüpload.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload mislukt: $e')),
      );
    }
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _contractStart ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) setState(() => _contractStart = d);
  }

  Future<void> _pickEnd() async {
    if (_isOnbepaaldeTijd) return;
    final d = await showDatePicker(
      context: context,
      initialDate: _contractEnd ?? _contractStart ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) {
      setState(() {
        _contractEnd = d;
        _isOnbepaaldeTijd = false;
      });
    }
  }

  void _beeindigHuidigContract() {
    setState(() {
      _isOnbepaaldeTijd = false;
      _contractEnd = DateTime.now();
    });
  }

  Future<void> _opslaan() async {
    final id = _selectedId;
    if (id == null || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecteer een operator.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final patch = <String, dynamic>{};
      final vu = _vasteUrenCtl.text.trim();
      patch['contract_vaste_uren'] = vu.isEmpty ? null : _parseMoney(vu);
      final vs = _vastSalarisCtl.text.trim();
      patch['contract_vast_salaris'] = vs.isEmpty ? null : _parseMoney(vs);
      patch['contract_startdatum'] =
          _contractStart?.toIso8601String().split('T').first;
      patch['contract_einddatum'] = _isOnbepaaldeTijd
          ? null
          : _contractEnd?.toIso8601String().split('T').first;
      if (_contractBijlageUrl != null && _contractBijlageUrl!.isNotEmpty) {
        patch['contract_bijlage_url'] = _contractBijlageUrl;
      }

      await AppSupabase.client.from('gebruikers').update(patch).eq('id', id);

      final vo = _voorschotCtl.text.trim();
      if (vo.isNotEmpty) {
        final bedrag = _parseMoney(vo) ?? 0;
        await AppSupabase.client.from('operator_voorschotten').upsert(
          {
            'operator_id': id,
            'maand_sleutel': _maandSleutel,
            'voorschot_bedrag': bedrag,
          },
          onConflict: 'operator_id,maand_sleutel',
        );
      }

      await widget.onSaved();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opgeslagen.'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
      Navigator.of(context).pop();
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
    final items = <DropdownMenuItem<String>>[
      for (final id in widget.operatorIds)
        DropdownMenuItem(
          value: id,
          child: Text(
            widget.operatorNames[id] ?? id,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];

    return AlertDialog(
      title: Text(
        'Operator financiën',
        style: GoogleFonts.inter(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Huidige maand: $_maandSleutel',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.operatorIds.isEmpty)
                Text(
                  'Geen operators in dit overzicht. Vernieuw het scherm of '
                  'wacht tot er planning met operators is geladen.',
                  style: GoogleFonts.inter(fontSize: 13),
                )
              else ...[
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Operator',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedId,
                      items: items,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _selectedId = v);
                        _loadVoorOperator(v);
                      },
                    ),
                  ),
                ),
                if (_loadingData)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  if (_loadErr != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _loadErr!,
                        style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Vast contract (optioneel)',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _vasteUrenCtl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Vaste uren per maand',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _vastSalarisCtl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Vast salaris (€)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _isOnbepaaldeTijd,
                    onChanged: _loadingData
                        ? null
                        : (v) {
                            setState(() {
                              _isOnbepaaldeTijd = v ?? false;
                              if (_isOnbepaaldeTijd) {
                                _contractEnd = null;
                              }
                            });
                          },
                    title: Text(
                      'Contract voor onbepaalde tijd',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _pickStart,
                          child: Text(
                            _contractStart == null
                                ? 'Startdatum contract'
                                : DateFormat('dd-MM-yyyy').format(_contractStart!),
                          ),
                        ),
                      ),
                      if (!_isOnbepaaldeTijd) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _pickEnd,
                            child: Text(
                              _contractEnd == null
                                  ? 'Einddatum contract'
                                  : DateFormat('dd-MM-yyyy').format(
                                      _contractEnd!,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                      ),
                      onPressed: _loadingData ? null : _beeindigHuidigContract,
                      child: Text(
                        'Huidig contract beëindigen',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        (_selectedId == null || _loadingData) ? null : _pickContractPdf,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Contract PDF uploaden'),
                  ),
                  if (_contractBijlageUrl != null &&
                      _contractBijlageUrl!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Bijlage: ${_contractBijlageUrl!}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Voorschot (huidige maand)',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _voorschotCtl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText:
                          'Voorschot reeds uitbetaald deze maand (€)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuleren'),
        ),
        FilledButton(
          onPressed: (_saving ||
                  widget.operatorIds.isEmpty ||
                  _selectedId == null)
              ? null
              : _opslaan,
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Opslaan'),
        ),
      ],
    );
  }
}

class _AccordeerDialogBody extends StatefulWidget {
  const _AccordeerDialogBody({
    required this.datumStr,
    required this.operatorNaam,
    required this.klant,
    required this.plannedStart,
    required this.plannedEnd,
    required this.plannedUren,
    required this.initialPickStart,
    required this.initialPickEnd,
    required this.baselineStart,
    required this.baselineEnd,
    required this.submittedDec,
    required this.operatorUserId,
    required this.planningId,
    required this.deepNavy,
    required this.brightBlue,
    required this.onReject,
    required this.onApprove,
    required this.parentContext,
  });

  final String datumStr;
  final String operatorNaam;
  final String klant;
  final TimeOfDay plannedStart;
  final TimeOfDay plannedEnd;
  final double plannedUren;
  final TimeOfDay initialPickStart;
  final TimeOfDay initialPickEnd;
  final TimeOfDay baselineStart;
  final TimeOfDay baselineEnd;
  final double submittedDec;
  final String operatorUserId;
  final String planningId;
  final Color deepNavy;
  final Color brightBlue;
  final Future<void> Function() onReject;
  final Future<void> Function({
    required TimeOfDay pickStart,
    required TimeOfDay pickEnd,
    required bool timesChangedFromOperatorSubmission,
    required String oldRangeLabel,
    required String newRangeLabel,
  })
  onApprove;
  final BuildContext parentContext;

  @override
  State<_AccordeerDialogBody> createState() => _AccordeerDialogBodyState();
}

class _AccordeerDialogBodyState extends State<_AccordeerDialogBody> {
  late TimeOfDay _pickStart;
  late TimeOfDay _pickEnd;
  bool _busy = false;

  static String _rangeLabel(TimeOfDay s, TimeOfDay e) =>
      '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')} – '
      '${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')}';

  static String _clock(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _pickStart = widget.initialPickStart;
    _pickEnd = widget.initialPickEnd;
  }

  bool _sameClock(TimeOfDay a, TimeOfDay b) =>
      a.hour == b.hour && a.minute == b.minute;

  Duration _dur(TimeOfDay start, TimeOfDay end) {
    final sm = start.hour * 60 + start.minute;
    var em = end.hour * 60 + end.minute;
    if (em <= sm) em += 24 * 60;
    return Duration(minutes: em - sm);
  }

  Future<void> _pick(bool start) async {
    final t = await showTimePicker(
      context: context,
      initialTime: start ? _pickStart : _pickEnd,
    );
    if (t != null) {
      setState(() {
        if (start) {
          _pickStart = t;
        } else {
          _pickEnd = t;
        }
      });
    }
  }

  Future<void> _onAccorderen() async {
    final changed =
        !_sameClock(_pickStart, widget.baselineStart) ||
        !_sameClock(_pickEnd, widget.baselineEnd);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bevestigen'),
        content: const Text('Weet je het zeker?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nee'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ja'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    final planningId = widget.planningId;
    if (planningId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Systeemfout: Kan planning ID niet vinden.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final oldL = _rangeLabel(widget.baselineStart, widget.baselineEnd);
      final newL = _rangeLabel(_pickStart, _pickEnd);
      await widget.onApprove(
        pickStart: _pickStart,
        pickEnd: _pickEnd,
        timesChangedFromOperatorSubmission: changed,
        oldRangeLabel: oldL,
        newRangeLabel: newL,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      if (!widget.parentContext.mounted) return;
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        const SnackBar(
          content: Text('Uren geaccordeerd.'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fout bij accorderen: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onAfkeuren() async {
    if (widget.planningId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geen planning-id gevonden voor deze taak.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Uren afkeuren'),
        content: const Text(
          'Weet je zeker dat je deze ingediende uren wilt weigeren? '
          'Ze worden verwijderd en de operator moet ze opnieuw indienen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Afkeuren'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await widget.onReject();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      if (!widget.parentContext.mounted) return;
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        const SnackBar(
          content: Text('Uren afgekeurd. De operator kan opnieuw indienen.'),
          backgroundColor: Color(0xFFE65100),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Afkeuren mislukt: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _dur(_pickStart, _pickEnd);
    final totalMin = d.inMinutes;
    final hPart = totalMin ~/ 60;
    final mPart = totalMin % 60;
    final wide = MediaQuery.sizeOf(context).width >= 880;

    final leftCol = Container(
      width: wide ? 280 : double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.deepNavy,
        borderRadius: wide
            ? const BorderRadius.horizontal(left: Radius.circular(4))
            : const BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Originele Planning',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            _whiteLine('Datum', widget.datumStr),
            _whiteLine('Operator', widget.operatorNaam),
            _whiteLine('Klant', widget.klant),
            _whiteLine('Geplande start', _clock(widget.plannedStart)),
            _whiteLine('Geplande eind', _clock(widget.plannedEnd)),
            _whiteLine(
              'Benodigde uren (planning)',
              widget.plannedUren == widget.plannedUren.roundToDouble()
                  ? widget.plannedUren.toInt().toString()
                  : widget.plannedUren.toStringAsFixed(2).replaceAll('.', ','),
            ),
          ],
        ),
      ),
    );

    final rightContent = Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ingegeven door Operator',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _busy ? null : () => _pick(true),
              child: Text(
                'Starttijd: ${_pickStart.format(context)}',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _pick(false),
              child: Text(
                'Eindtijd: ${_pickEnd.format(context)}',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Gewerkte uren: $hPart uur $mPart min',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: widget.brightBlue,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade700, width: 1.5),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _busy ? null : _onAfkeuren,
                  child: Text(
                    'Uren Afkeuren',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.brightBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _busy ? null : _onAccorderen,
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Accorderen',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leftCol,
              Expanded(child: rightContent),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [leftCol, rightContent],
          );

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: EdgeInsets.zero,
      title: Text(
        'Uren accorderen',
        style: GoogleFonts.inter(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(width: wide ? 860 : 420, child: body),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuleren'),
        ),
      ],
    );
  }

  Widget _whiteLine(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            v,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
