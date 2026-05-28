import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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

  /// Operators met geaccordeerde uren die nog geen loonstrook hebben deze maand.
  int _operatorsNogAfTeSluiten = 0;

  /// Geselecteerde ingediende taak in master-detail split-view.
  Map<String, dynamic>? _geselecteerdeTaak;

  int _actieveTab = 0;

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

  bool _isOpenUrenStatus(Map<String, dynamic> r) {
    final s = _urenStatusNorm(r);
    return s.isEmpty || s == 'open';
  }

  DateTime get _vandaag => _dayOnly(DateTime.now());

  /// Open uren, alleen als de dienst vandaag of in het verleden ligt.
  bool _isVergetenOpenTaak(Map<String, dynamic> r) {
    if (!_isOpenUrenStatus(r)) return false;
    final d = _parseShiftDay(r['geplande_datum']);
    if (d == null) return false;
    return !_dayOnly(d).isAfter(_vandaag);
  }

  bool _dayHasOpenVergeten(DateTime day) {
    final key = _dayOnly(day);
    for (final r in _rows) {
      if (!_isVergetenOpenTaak(r)) continue;
      final d = _parseShiftDay(r['geplande_datum']);
      if (d != null && _dayOnly(d) == key) return true;
    }
    return false;
  }

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
            'gewerkte_uren_decimaal, uren_status, doorgeschoven_naar_maand, bedrijfsnaam, '
            'operator:gebruikers(id, voornaam, achternaam, standaard_uurloon, '
            'contract_vaste_uren, contract_vast_salaris, contract_startdatum, '
            'contract_einddatum), '
            'opdrachten!opdracht_planning_opdracht_id_fkey(bedrijfsnaam, projecten(project_naam))',
          )
          .gte('geplande_datum', fromStr)
          .lte('geplande_datum', toStr)
          .order('geplande_datum', ascending: false)
          .limit(800);

      final list = (planningRes as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) {
            final st = _urenStatusNorm(r);
            return st.isEmpty ||
                st == 'open' ||
                st == 'ingediend' ||
                st == 'geaccordeerd';
          })
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

      final nogAfTeSluiten = await _berekenOperatorsNogAfTeSluiten(list);

      Map<String, dynamic>? behoudSelectie = _geselecteerdeTaak;
      if (behoudSelectie != null) {
        final selId = _planningIdFromRow(behoudSelectie);
        final match = list.where((r) {
          if (_planningIdFromRow(r) != selId) return false;
          final st = _urenStatusNorm(r);
          return st == 'ingediend' || st == 'geaccordeerd';
        });
        behoudSelectie = match.isNotEmpty ? match.first : null;
      }

      if (!mounted) return;
      setState(() {
        _rows = list;
        _operatorNames = names;
        _operatorsNogAfTeSluiten = nogAfTeSluiten;
        _geselecteerdeTaak = behoudSelectie;
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

  List<Map<String, dynamic>> _rowsInFocusedMonth() {
    return _takenDezeMaand();
  }

  /// Taak hoort bij de focus-maand: oorspronkelijk gepland in die maand, of doorgeschoven naar die maand.
  bool _hoortBijFocusMaand(Map<String, dynamic> taak) {
    final huidigeMaandSleutel = _maandSleutel;
    final doorgeschovenRaw = taak['doorgeschoven_naar_maand'];
    final doorgeschoven = doorgeschovenRaw == null
        ? null
        : _text(doorgeschovenRaw);

    final taakDatum =
        _parseShiftDay(taak['geplande_datum']) ??
        DateTime.tryParse(taak['geplande_datum']?.toString() ?? '');
    if (taakDatum == null) return false;

    final isOrigineelDezeMaand =
        taakDatum.year == _focusedDay.year &&
        taakDatum.month == _focusedDay.month;
    final isDoorgeschovenNaarDezeMaand =
        doorgeschoven != null && doorgeschoven == huidigeMaandSleutel;

    if (isOrigineelDezeMaand &&
        doorgeschoven != null &&
        doorgeschoven.isNotEmpty &&
        doorgeschoven != huidigeMaandSleutel) {
      return true;
    }

    return isOrigineelDezeMaand || isDoorgeschovenNaarDezeMaand;
  }

  /// Taken in de actieve kalendermaand ([_focusedDay]), lokaal gefilterd op [_rows].
  List<Map<String, dynamic>> _takenDezeMaand() {
    return _rows.where(_hoortBijFocusMaand).toList();
  }

  /// Oranje/rood label voor doorschuif-status (alleen lijstweergave).
  Widget? _buildRolloverTag(Map<String, dynamic> taak) {
    final doorgeschovenSleutel = _text(taak['doorgeschoven_naar_maand']);
    if (doorgeschovenSleutel.isEmpty) return null;

    final huidigeMaandSleutel = _maandSleutel;

    if (doorgeschovenSleutel == huidigeMaandSleutel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Meegenomen uit vorige maand',
          style: GoogleFonts.inter(
            color: Colors.orange.shade900,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Doorgeschoven naar $doorgeschovenSleutel',
        style: GoogleFonts.inter(
          color: Colors.red.shade900,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
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

  Future<int> _berekenOperatorsNogAfTeSluiten(
    List<Map<String, dynamic>> rows,
  ) async {
    final geaccIds = <String>{};
    for (final r in rows) {
      if (!_hoortBijFocusMaand(r)) continue;
      if (_urenStatusNorm(r) != 'geaccordeerd') continue;
      final id = _text(r['operator_id']);
      if (id.isNotEmpty) geaccIds.add(id);
    }
    if (geaccIds.isEmpty) return 0;

    try {
      final res = await AppSupabase.client
          .from('operator_uitbetalingen')
          .select('operator_id')
          .eq('maand_sleutel', _maandSleutel)
          .inFilter('operator_id', geaccIds.toList());
      final afgesloten = (res as List)
          .map((e) => _text(Map<String, dynamic>.from(e as Map)['operator_id']))
          .where((id) => id.isNotEmpty)
          .toSet();
      return geaccIds.where((id) => !afgesloten.contains(id)).length;
    } catch (_) {
      return geaccIds.length;
    }
  }

  Future<void> _refreshAfsluitStatus() async {
    if (_rows.isEmpty) return;
    final count = await _berekenOperatorsNogAfTeSluiten(_rows);
    if (mounted) setState(() => _operatorsNogAfTeSluiten = count);
  }

  Future<List<Map<String, dynamic>>>
  _operatorsMetGeaccordeerdeUrenDezeMaand() async {
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
          maandLabel: DateFormat.yMMMM(
            'nl_NL',
          ).format(DateTime(_focusedDay.year, _focusedDay.month)),
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
    final heeftNogTeSluiten = _operatorsNogAfTeSluiten > 0;
    final kanAfsluiten =
        aantalGeaccordeerd > 0 && isMaandVoorbij && heeftNogTeSluiten;
    final knopLabel = !isMaandVoorbij && aantalGeaccordeerd > 0
        ? 'Maand nog niet voorbij'
        : aantalGeaccordeerd > 0 && !heeftNogTeSluiten
        ? 'Alle operators al afgesloten'
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
            onPressed: _loading || !kanAfsluiten
                ? null
                : _openMaandSluitingModal,
            icon: const Icon(Icons.lock_clock_rounded),
            label: Text(
              knopLabel,
              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kanAfsluiten
                  ? Colors.green
                  : Colors.grey.shade400,
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

  List<Map<String, dynamic>> _inTeDienenLijst() {
    return _sortRowsByDateTime(
      _rows.where((t) {
        if (_urenStatusNorm(t) != 'ingediend') return false;
        if (!_hoortBijFocusMaand(t)) return false;
        return _passesOperatorFilter(t);
      }).toList(),
    );
  }

  List<Map<String, dynamic>> _geaccordeerdeLijst() {
    return _sortRowsByDateTime(
      _rows.where((t) {
        if (_urenStatusNorm(t) != 'geaccordeerd') return false;
        if (!_hoortBijFocusMaand(t)) return false;
        return _passesOperatorFilter(t);
      }).toList(),
    );
  }

  List<Map<String, dynamic>> _vergetenTaken3PlusDagen() {
    final nu = DateTime.now();
    return _rows.where((t) {
      if (!_isVergetenOpenTaak(t)) return false;
      if (!_hoortBijFocusMaand(t)) return false;
      if (!_passesOperatorFilter(t)) return false;
      final taakDatum = _parseShiftDay(t['geplande_datum']);
      if (taakDatum == null) return false;
      return nu.difference(_dayOnly(taakDatum)).inDays >= 3;
    }).toList();
  }

  String _geplandeDatumDisplay(Map<String, dynamic> row) {
    final d = _parseShiftDay(row['geplande_datum']);
    if (d != null) {
      return DateFormat('dd-MM-yyyy').format(d);
    }
    return _text(row['geplande_datum']);
  }

  Future<void> _stuurPushReminder(
    String operatorId,
    String bedrijfsnaam,
  ) async {
    if (operatorId.isEmpty) return;
    try {
      await AppSupabase.client.from('push_queue').insert({
        'operator_id': operatorId,
        'titel': 'Vergeet je uren niet! ⏰',
        'bericht':
            'Vergeet niet je gewerkte uren voor $bedrijfsnaam in te vullen in de app.',
      });
    } catch (e) {
      debugPrint('Fout bij sturen reminder: $e');
      rethrow;
    }
  }

  Future<void> _toonReminderModal(List<Map<String, dynamic>> taken) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            'Achterstallige Uren (3+ dagen)',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 600,
            height: 400,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: taken.length,
                    itemBuilder: (context, index) {
                      final t = taken[index];
                      final operatorNaam = _operatorName(t);
                      final bedrijfsnaam = _klantNaam(t);
                      final datum = _geplandeDatumDisplay(t);
                      final operatorId = _text(t['operator_id']);

                      return ListTile(
                        leading: const Icon(
                          Icons.warning,
                          color: Colors.orange,
                        ),
                        title: Text(
                          '$operatorNaam - $datum',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(bedrijfsnaam),
                        trailing: IconButton(
                          icon: const Icon(Icons.send, color: Colors.blue),
                          tooltip: 'Stuur herinnering',
                          onPressed: () async {
                            try {
                              await _stuurPushReminder(
                                operatorId,
                                bedrijfsnaam,
                              );
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Reminder gestuurd!'),
                                ),
                              );
                            } catch (e) {
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Mislukt: $e')),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final inserts = <Map<String, dynamic>>[];
                        for (final t in taken) {
                          final operatorId = _text(t['operator_id']);
                          if (operatorId.isEmpty) continue;
                          inserts.add({
                            'operator_id': operatorId,
                            'titel': 'Vergeet je uren niet! ⏰',
                            'bericht':
                                'Vergeet niet je gewerkte uren voor ${_klantNaam(t)} in te vullen in de app.',
                          });
                        }
                        if (inserts.isNotEmpty) {
                          await AppSupabase.client
                              .from('push_queue')
                              .insert(inserts);
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Alle reminders verstuurd! (${inserts.length})',
                            ),
                            backgroundColor: const Color(0xFF2E7D32),
                          ),
                        );
                      } catch (e) {
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Bulk mislukt: $e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.send_and_archive),
                    label: const Text('Stuur alle reminders in één keer'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Sluiten'),
            ),
          ],
        );
      },
    );
  }

  String _formatUrenNl(double d) {
    if (d == d.roundToDouble()) return d.toInt().toString();
    return NumberFormat.decimalPattern('nl_NL').format(d);
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

  Widget _buildAnalyticsCard(
    String titel,
    String waarde,
    Color kleur,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kleur.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kleur.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: kleur, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    titel,
                    style: TextStyle(color: kleur, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              waarde,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: kleur,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _analyticsRow(BuildContext context) {
    final counts = _maandPlanningStatusCounts();
    final aantalOpen = counts.open;
    final aantalIngediend = counts.ingediend;
    final aantalGeaccordeerd = counts.geaccordeerd;
    final vergetenTaken = _vergetenTaken3PlusDagen();
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    final kaarten = [
      _buildAnalyticsCard(
        'Nog in te vullen',
        '$aantalOpen',
        Colors.blue,
        Icons.assignment,
      ),
      _buildAnalyticsCard(
        'Te accorderen',
        '$aantalIngediend',
        Colors.orange,
        Icons.access_time,
      ),
      _buildAnalyticsCard(
        'Geaccordeerd',
        '$aantalGeaccordeerd',
        Colors.green,
        Icons.check_circle,
      ),
    ];

    final analyticsBlok = isMobile
        ? Column(
            children: [
              kaarten[0],
              const SizedBox(height: 12),
              kaarten[1],
              const SizedBox(height: 12),
              kaarten[2],
            ],
          )
        : Row(
            children: [
              Expanded(child: kaarten[0]),
              const SizedBox(width: 16),
              Expanded(child: kaarten[1]),
              const SizedBox(width: 16),
              Expanded(child: kaarten[2]),
            ],
          );

    if (vergetenTaken.isEmpty) return analyticsBlok;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        analyticsBlok,
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            icon: const Icon(Icons.notifications_active, size: 16),
            label: Text(
              'Stuur Reminders (${vergetenTaken.length})',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            onPressed: () => _toonReminderModal(vergetenTaken),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final bool isMobile = MediaQuery.of(context).size.width < 800;
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
          : Builder(
              builder: (context) {
                // 1. Stop de split-view sectie in een lokale variabele.
                final Widget splitViewSectie = _buildMasterDetailSplit();

                // 2. Bouw de body Column
                final Widget pageContent = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _analyticsRow(context),
                          const SizedBox(height: 16),
                          TableCalendar<String>(
                            firstDay: DateTime.utc(2020, 1, 1),
                            lastDay: DateTime.utc(2035, 12, 31),
                            focusedDay: _focusedDay,
                            selectedDayPredicate: (d) =>
                                isSameDay(_selectedDay, d),
                            calendarFormat: _calendarFormat,
                            availableCalendarFormats: const {
                              CalendarFormat.month: 'Maand',
                              CalendarFormat.twoWeeks: '2 weken',
                            },
                            // Fix: Kalender Scroll-Kaping (mobiel)
                            availableGestures:
                                AvailableGestures.horizontalSwipe,
                            startingDayOfWeek: StartingDayOfWeek.monday,
                            locale: 'nl_NL',
                            onFormatChanged: (f) =>
                                setState(() => _calendarFormat = f),
                            onDaySelected: (sel, foc) {
                              final dayKey = _dayOnly(sel);
                              final takenOpDag = _sortRowsByDateTime(
                                _rows.where((t) {
                                  if (!_passesOperatorFilter(t)) return false;
                                  final d = _parseShiftDay(t['geplande_datum']);
                                  if (d == null || _dayOnly(d) != dayKey) {
                                    return false;
                                  }
                                  final st = _urenStatusNorm(t);
                                  return st == 'ingediend' ||
                                      st == 'geaccordeerd';
                                }).toList(),
                              );

                              setState(() {
                                _selectedDay = sel;
                                _focusedDay = foc;
                                if (takenOpDag.isNotEmpty) {
                                  final eersteIngediend = takenOpDag
                                      .where(
                                        (t) =>
                                            _urenStatusNorm(t) == 'ingediend',
                                      )
                                      .toList();
                                  _geselecteerdeTaak =
                                      eersteIngediend.isNotEmpty
                                      ? eersteIngediend.first
                                      : takenOpDag.first;
                                }
                              });
                              _refreshAfsluitStatus();
                            },
                            onPageChanged: (foc) {
                              setState(() {
                                _focusedDay = foc;
                                _geselecteerdeTaak = null;
                              });
                              _refreshAfsluitStatus();
                            },
                            eventLoader: (day) {
                              final tags = <String>[];
                              if (_dayHasOpenVergeten(day)) tags.add('o');
                              if (_dayHasStatus(day, 'ingediend')) {
                                tags.add('i');
                              }
                              if (_dayHasStatus(day, 'geaccordeerd')) {
                                tags.add('g');
                              }
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
                                if (events.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final hasO = events.contains('o');
                                final hasI = events.contains('i');
                                final hasG = events.contains('g');
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (hasO)
                                        Container(
                                          width: 6,
                                          height: 6,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _brightBlue,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
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
                          InputDecorator(
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
                                onChanged: (v) {
                                  setState(() {
                                    _filterOperatorId = v;
                                    if (_geselecteerdeTaak != null &&
                                        !_passesOperatorFilter(
                                          _geselecteerdeTaak!,
                                        )) {
                                      _geselecteerdeTaak = null;
                                    }
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Fix: Responsieve Pagina Lay-out (De Root)
                    isMobile
                        ? splitViewSectie
                        : Expanded(child: splitViewSectie),

                    _buildBottomPayrollBar(),
                    if (isMobile) const SizedBox(height: 120),
                  ],
                );

                // Fix: Mobiel globaal scrollen, desktop vaste layout.
                return isMobile
                    ? SingleChildScrollView(child: pageContent)
                    : pageContent;
              },
            ),
    );
  }

  Widget _buildInfoBlokje(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  double _detailPaneBreedte(BuildContext context) {
    if (_geselecteerdeTaak == null) return 0;
    final scherm = MediaQuery.sizeOf(context).width;
    return (scherm * 0.38).clamp(380.0, 480.0);
  }

  Widget _buildTaakLijst(
    List<Map<String, dynamic>> lijst, {
    required bool isGeaccordeerdTab,
  }) {
    if (lijst.isEmpty) {
      return Center(
        child: Text(
          isGeaccordeerdTab
              ? 'Geen geaccordeerde uren gevonden.'
              : 'Geen uren te accorderen.',
          style: GoogleFonts.inter(
            color: Colors.grey.shade600,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final selId = _geselecteerdeTaak == null
        ? ''
        : _planningIdFromRow(_geselecteerdeTaak!);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      // Op mobiel moet de lijst zijn volledige hoogte pakken (shrinkWrap) omdat de pagina zélf scrolt.
      // Op desktop moet hij false zijn, omdat hij in een Expanded zit en zélf moet scrollen.
      shrinkWrap: MediaQuery.of(context).size.width < 800,
      physics: MediaQuery.of(context).size.width < 800
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: lijst.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = lijst[index];
        final itemId = _planningIdFromRow(item);
        final isSelected = selId.isNotEmpty && selId == itemId;
        final rolloverTag = _buildRolloverTag(item);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _geselecteerdeTaak = item),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? Colors.blue.shade300
                        : Colors.grey.shade200,
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: [
                    if (!isSelected)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isGeaccordeerdTab
                            ? Colors.green.shade100
                            : Colors.orange.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person,
                        color: isGeaccordeerdTab
                            ? Colors.green.shade700
                            : Colors.orange.shade700,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _operatorName(item),
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_geplandeDatumDisplay(item)} • ${_klantNaam(item)}',
                            style: GoogleFonts.inter(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: isSelected ? Colors.blue : Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
            if (rolloverTag != null) ...[
              const SizedBox(height: 6),
              rolloverTag,
            ],
          ],
        );
      },
    );
  }

  Widget _buildDetailKaart() {
    final taak = _geselecteerdeTaak!;
    final isAlGeaccordeerd = _urenStatusNorm(taak) == 'geaccordeerd';
    final rolloverTag = _buildRolloverTag(taak);

    final klant = _klantNaam(taak);
    final operator = _operatorName(taak);
    final datum = _geplandeDatumDisplay(taak);
    final werkelijkStart = _safeTime(taak['werkelijke_starttijd']);
    final werkelijkEind = _safeTime(taak['werkelijke_eindtijd']);
    final gewerkteUren = _formatUrenNl(
      _asDouble(taak['gewerkte_uren_decimaal']),
    );
    final tijden = '$werkelijkStart – $werkelijkEind · $gewerkteUren u';

    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isAlGeaccordeerd ? 'Geaccordeerde Uren' : 'Ingediende Uren',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _geselecteerdeTaak = null),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          if (rolloverTag != null) ...[rolloverTag, const SizedBox(height: 16)],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildInfoBlokje(
                  Icons.business,
                  'Klant / Project',
                  klant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInfoBlokje(Icons.person, 'Operator', operator),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildInfoBlokje(Icons.calendar_today, 'Datum', datum),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInfoBlokje(Icons.access_time, 'Tijden', tijden),
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (!isAlGeaccordeerd)
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  'Uren Beoordelen & Accorderen',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => _openAccordeerDialog(taak),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Deze uren zijn succesvol geaccordeerd',
                    style: GoogleFonts.inter(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMasterDetailSplit() {
    final inTeDienenLijst = _inTeDienenLijst();
    final geaccordeerdeLijst = _geaccordeerdeLijst();
    final detailBreedte = _detailPaneBreedte(context);
    final bool isMobile = MediaQuery.of(context).size.width < 800;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey.shade300)),
              ),
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      onTap: (index) => setState(() => _actieveTab = index),
                      labelColor: Colors.blue.shade800,
                      unselectedLabelColor: Colors.grey.shade600,
                      indicatorColor: Colors.blue.shade800,
                      labelStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                      ),
                      tabs: [
                        Tab(text: 'Te accorderen (${inTeDienenLijst.length})'),
                        Tab(
                          text: 'Geaccordeerd (${geaccordeerdeLijst.length})',
                        ),
                      ],
                    ),
                    // Op mobiel geen verticale Expanded widgets (pagina scrolt globaal).
                    if (isMobile)
                      ColoredBox(
                        color: const Color(0xFFF2F2F7),
                        child: _actieveTab == 0
                            ? _buildTaakLijst(
                                inTeDienenLijst,
                                isGeaccordeerdTab: false,
                              )
                            : _buildTaakLijst(
                                geaccordeerdeLijst,
                                isGeaccordeerdTab: true,
                              ),
                      )
                    else
                      Expanded(
                        child: ColoredBox(
                          color: const Color(0xFFF2F2F7),
                          child: _actieveTab == 0
                              ? _buildTaakLijst(
                                  inTeDienenLijst,
                                  isGeaccordeerdTab: false,
                                )
                              : _buildTaakLijst(
                                  geaccordeerdeLijst,
                                  isGeaccordeerdTab: true,
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            width: detailBreedte,
            color: const Color(0xFFF2F2F7),
            child: ClipRect(
              child: _geselecteerdeTaak == null
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.topCenter,
                      child: _buildDetailKaart(),
                    ),
            ),
          ),
        ],
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
  String? _geselecteerdeOperatorNaam;
  double _voorschotBedrag = 0;
  bool _loadingVoorschot = false;
  bool _checkingAfgesloten = false;
  bool _isAlAfgesloten = false;
  bool _saving = false;

  String _text(dynamic v) => (v ?? '').toString().trim();

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
    return DateTime.tryParse(s);
  }

  bool _isOpenOfIngediendUrenStatus(Map<String, dynamic> r) {
    final st = _urenStatusNorm(r);
    return st.isEmpty || st == 'open' || st == 'ingediend';
  }

  String _planningIdFromRow(Map<String, dynamic> row) => _text(row['id']);

  String get _volgendeMaandSleutel {
    final fd = widget.focusedDay;
    if (fd.month == 12) {
      return '${fd.year + 1}-01';
    }
    return '${fd.year}-${(fd.month + 1).toString().padLeft(2, '0')}';
  }

  Future<bool> _checkMaandAlAfgesloten(String operatorId) async {
    final check = await AppSupabase.client
        .from('operator_uitbetalingen')
        .select('id')
        .eq('operator_id', operatorId)
        .eq('maand_sleutel', widget.maandSleutel)
        .maybeSingle();
    return check != null;
  }

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

  List<Map<String, dynamic>> _geaccordeerdeTakenVoorOperator(
    String operatorId,
  ) {
    return _planningVoorOperator(
      operatorId,
    ).where((r) => _urenStatusNorm(r) == 'geaccordeerd').toList();
  }

  ({double uren, double bruto}) _berekenMaandSalaris(
    Map<String, dynamic> operatorData,
    List<Map<String, dynamic>> geaccordeerdeTaken,
    DateTime focusedDay,
  ) {
    final totaalGewerkteUren = PayrollCalculation.totaalGewerkteUren(
      geaccordeerdeTaken,
    );

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
        PayrollCalculation.isGeldigVastContractVoorMaand(
          operatorData,
          focusedDay,
        );

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
    print(
      'Operator: ${operatorData['voornaam']} ${operatorData['achternaam']}',
    );
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

  Future<void> _toonOperatorZoekModal() async {
    if (_saving) return;
    var zoekTerm = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final q = zoekTerm.toLowerCase().trim();
            final gefilterd = widget.operators.where((op) {
              if (q.isEmpty) return true;
              return _operatorLabel(op).toLowerCase().contains(q);
            }).toList();

            return AlertDialog(
              title: Text(
                'Kies een operator',
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
                      onChanged: (val) => setModalState(() => zoekTerm = val),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: gefilterd.isEmpty
                          ? Center(
                              child: Text(
                                'Geen resultaten',
                                style: GoogleFonts.inter(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: gefilterd.length,
                              itemBuilder: (context, index) {
                                final op = gefilterd[index];
                                final opId = _text(op['id']);
                                if (opId.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final opNaam = _operatorLabel(op);
                                final isSelected = _selectedOperatorId == opId;

                                return ListTile(
                                  title: Text(
                                    opNaam,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedTileColor: Colors.blue.shade50,
                                  onTap: () async {
                                    Navigator.pop(dialogContext);
                                    setState(() {
                                      _geselecteerdeOperatorNaam = opNaam;
                                    });
                                    await _onOperatorChanged(opId);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAnalyticsBlok({
    required String operatorNaam,
    required double berekendeUren,
    required double vasteUren,
    required double voorschotBedrag,
    required double berekendBruto,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analytics voor $operatorNaam:',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '• Totaal geaccordeerd: '
            '${berekendeUren.toStringAsFixed(2).replaceAll('.', ',')} uur',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          Text(
            '• Vast contract uren: '
            '${vasteUren.toStringAsFixed(2).replaceAll('.', ',')} uur',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          Text(
            '• Voorschot deze maand: ${_eur.format(voorschotBedrag)}',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          const Divider(),
          Text(
            'Berekend Bruto Salaris: ${_eur.format(berekendBruto)}',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: Colors.green.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onOperatorChanged(String? id) async {
    setState(() {
      _selectedOperatorId = id;
      if (id == null || id.isEmpty) {
        _geselecteerdeOperatorNaam = null;
      } else {
        final op = _operatorById(id);
        if (op != null) {
          _geselecteerdeOperatorNaam = _operatorLabel(op);
        }
      }
      _voorschotBedrag = 0;
      _isAlAfgesloten = false;
      _loadingVoorschot = id != null && id.isNotEmpty;
      _checkingAfgesloten = id != null && id.isNotEmpty;
    });
    if (id == null || id.isEmpty) return;
    try {
      final voorschotFuture = AppSupabase.client
          .from('operator_voorschotten')
          .select('voorschot_bedrag')
          .eq('operator_id', id)
          .eq('maand_sleutel', widget.maandSleutel)
          .maybeSingle();
      final afgeslotenFuture = _checkMaandAlAfgesloten(id);

      final row = await voorschotFuture;
      final alAfgesloten = await afgeslotenFuture;

      if (!mounted) return;
      setState(() {
        _voorschotBedrag = row == null
            ? 0
            : _asDouble(
                Map<String, dynamic>.from(row as Map)['voorschot_bedrag'],
              );
        _isAlAfgesloten = alAfgesloten;
        _loadingVoorschot = false;
        _checkingAfgesloten = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingVoorschot = false;
          _checkingAfgesloten = false;
        });
      }
    }
  }

  Future<void> _doorschuifOpenEnIngediendNaarVolgendeMaand(
    String operatorId,
  ) async {
    final fd = widget.focusedDay;
    final volgendeMaandSleutel = _volgendeMaandSleutel;
    final doorschuifIds = <String>[];

    for (final t in widget.planningRows) {
      if (_text(t['operator_id']) != operatorId) continue;
      if (!_isOpenOfIngediendUrenStatus(t)) continue;

      final datum = _parseShiftDay(t['geplande_datum']);
      if (datum == null) continue;
      if (datum.year != fd.year || datum.month != fd.month) continue;

      final planningId = _planningIdFromRow(t);
      if (planningId.isNotEmpty) {
        doorschuifIds.add(planningId);
      }
    }

    if (doorschuifIds.isEmpty) return;

    try {
      await AppSupabase.client
          .from('opdracht_planning')
          .update({'doorgeschoven_naar_maand': volgendeMaandSleutel})
          .inFilter('id', doorschuifIds);
    } catch (e) {
      // ignore: avoid_print
      print('Fout bij doorschuiven uren: $e');
    }
  }

  Future<void> _bevestigSluiting(double berekendBruto) async {
    final id = _selectedOperatorId;
    if (id == null || id.isEmpty) return;
    setState(() => _saving = true);
    try {
      if (await _checkMaandAlAfgesloten(id)) {
        if (!mounted) return;
        setState(() {
          _isAlAfgesloten = true;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deze maand is al afgesloten voor deze operator.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final response =
          await AppSupabase.client.from('operator_uitbetalingen').upsert({
            'operator_id': id,
            'maand_sleutel': widget.maandSleutel,
            'berekend_bruto': berekendBruto,
            'verrekend_voorschot': _voorschotBedrag,
            'is_betaald': false,
          }, onConflict: 'operator_id,maand_sleutel').select();

      if ((response as List).isEmpty) {
        throw Exception('Maandsluiting niet opgeslagen (RLS of constraint).');
      }

      await _doorschuifOpenEnIngediendNaarVolgendeMaand(id);

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
      scenarioPerfect = !needsOverride && geaccordeerdCount > 0;

      final geaccTake = _geaccordeerdeTakenVoorOperator(opId);
      final salaris = _berekenMaandSalaris(
        operatorData,
        geaccTake,
        widget.focusedDay,
      );
      geaccUren = salaris.uren;
      berekendBruto = salaris.bruto;
    }

    final isGeldigVastContract =
        operatorData != null &&
        PayrollCalculation.isGeldigVastContractVoorMaand(
          operatorData,
          widget.focusedDay,
        );
    final heeftVastBasissalarisZonderUren =
        isGeldigVastContract && geaccUren == 0 && geaccordeerdCount == 0;

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
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _saving ? null : _toonOperatorZoekModal,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Selecteer Operator voor Loonstrook',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.search),
                      ),
                      child: Text(
                        _geselecteerdeOperatorNaam ??
                            (operator != null
                                ? _operatorLabel(operator)
                                : 'Tik om een operator te zoeken'),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: opId == null
                              ? Colors.grey.shade600
                              : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_loadingVoorschot || _checkingAfgesloten) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ] else if (_isAlAfgesloten && opId != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Deze maand is al succesvol afgesloten voor deze operator.',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    color: Colors.red.shade800,
                  ),
                ),
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
                _buildAnalyticsBlok(
                  operatorNaam:
                      _geselecteerdeOperatorNaam ?? _operatorLabel(operator),
                  berekendeUren: geaccUren,
                  vasteUren: _veiligParsen(
                    operatorData?['contract_vaste_uren'],
                  ),
                  voorschotBedrag: _voorschotBedrag,
                  berekendBruto: berekendBruto ?? 0.0,
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
            !_loadingVoorschot &&
            !_checkingAfgesloten &&
            !_isAlAfgesloten)
          FilledButton(
            onPressed: _saving ? null : () => _bevestigSluiting(berekendBruto!),
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
        const SnackBar(
          content: Text('Geen planning-id gevonden voor deze taak.'),
        ),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
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
