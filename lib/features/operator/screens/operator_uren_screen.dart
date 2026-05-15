import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/widgets/app_drawer.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';

/// Operator: bruto salaris ([loonadministratie_maand]) en diensten ([opdracht_planning])
/// met offline-first urenregistratie (tab Uren Registreren).
class OperatorUrenScreen extends StatefulWidget {
  const OperatorUrenScreen({super.key});

  @override
  State<OperatorUrenScreen> createState() => _OperatorUrenScreenState();
}

class _OperatorUrenScreenState extends State<OperatorUrenScreen> {
  static const Color _deepNavy = Color(0xFF1A237E);
  static const Color _brightBlue = Color(0xFF0052CC);
  static const Color _pageBg = Color(0xFFF2F4F8);

  List<Map<String, dynamic>> _maandenLijst = [];
  List<Map<String, dynamic>> _shiftsLijst = [];
  bool _isLoading = true;
  String _errorMessage = '';

  /// Tab Overzicht: `true` = "Deze maand", `false` = "Totaal overzicht".
  bool _overzichtMaandModus = true;
  double? _contractVasteUren;
  double? _contractVastSalaris;
  double _voorschotBedrag = 0;

  DateTime _regCalendarFocusedDay = DateTime.now();
  DateTime? _regCalendarSelectedDay = DateTime.now();
  CalendarFormat _regCalendarFormat = CalendarFormat.month;

  final NumberFormat _eur = NumberFormat.currency(
    locale: 'nl_NL',
    symbol: '€',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Niet ingelogd.';
        _maandenLijst = [];
        _shiftsLijst = [];
        _contractVasteUren = null;
        _contractVastSalaris = null;
        _voorschotBedrag = 0;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final client = Supabase.instance.client;

      final pair = await Future.wait([
        client
            .from('loonadministratie_maand')
            .select()
            .eq('operator_id', uid)
            .order('kalender_maand', ascending: false),
        client
            .from('opdracht_planning')
            .select(
              'id, opdracht_id, geplande_datum, starttijd, eindtijd, '
              'werkelijke_starttijd, werkelijke_eindtijd, gewerkte_uren_decimaal, '
              'bruto_loonkosten, uren_status, status, bedrijfsnaam, '
              'opdracht:opdrachten!opdracht_planning_opdracht_id_fkey('
              'uitvoer_adres_volledig, bedrijfsnaam, projecten(project_naam))',
            )
            .eq('operator_id', uid)
            .order('geplande_datum', ascending: false)
            .limit(200),
      ]);

      final maanden = (pair[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final shifts = (pair[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      double? contractVasteUren;
      double? contractVastSalaris;
      double voorschot = 0;
      try {
        final u = await client
            .from('gebruikers')
            .select('contract_vaste_uren, contract_vast_salaris')
            .eq('id', uid)
            .maybeSingle();
        if (u != null) {
          final m = Map<String, dynamic>.from(u as Map);
          contractVasteUren = _parseNullableDouble(m['contract_vaste_uren']);
          contractVastSalaris = _parseNullableDouble(
            m['contract_vast_salaris'],
          );
        }
      } catch (e) {
        debugPrint('OperatorUren: contractkolommen optioneel: $e');
      }
      try {
        final maandSleutel = _currentKalenderMaandKey();
        final v = await client
            .from('operator_voorschotten')
            .select('voorschot_bedrag')
            .eq('operator_id', uid)
            .eq('maand_sleutel', maandSleutel)
            .maybeSingle();
        if (v != null) {
          final m = Map<String, dynamic>.from(v as Map);
          final raw = m['voorschot_bedrag'];
          voorschot = raw == null ? 0 : _asDouble(raw);
        }
      } catch (e) {
        debugPrint('OperatorUren: operator_voorschotten optioneel: $e');
      }

      // ignore: avoid_print
      print('X-RAY UREN DATA: $maanden');

      if (!mounted) return;
      setState(() {
        _maandenLijst = maanden;
        _shiftsLijst = shifts;
        _contractVasteUren = contractVasteUren;
        _contractVastSalaris = contractVastSalaris;
        _voorschotBedrag = voorschot;
        _isLoading = false;
        _errorMessage = '';
      });
    } catch (e, st) {
      debugPrint('OperatorUrenScreen._loadData error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _maandenLijst = [];
        _shiftsLijst = [];
        _contractVasteUren = null;
        _contractVastSalaris = null;
        _voorschotBedrag = 0;
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  String _currentKalenderMaandKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  String _kalenderMaandKey(dynamic v) {
    if (v == null) return '';
    if (v is DateTime) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}';
    }
    var s = v.toString().trim();
    if (s.length >= 7 && s.contains('-')) {
      s = s.substring(0, 7);
    }
    return s;
  }

  String _formatMaand(dynamic kalenderMaand) {
    final s = _kalenderMaandKey(kalenderMaand);
    final parts = s.split('-');
    if (parts.length != 2) return s.isEmpty ? '—' : s;
    final maanden = {
      '01': 'Januari',
      '02': 'Februari',
      '03': 'Maart',
      '04': 'April',
      '05': 'Mei',
      '06': 'Juni',
      '07': 'Juli',
      '08': 'Augustus',
      '09': 'September',
      '10': 'Oktober',
      '11': 'November',
      '12': 'December',
    };
    final mm = parts[1].length == 1 ? '0${parts[1]}' : parts[1];
    return '${maanden[mm] ?? parts[1]} ${parts[0]}';
  }

  String _formatMaandLongNl(dynamic kalenderMaand) {
    final d = _parseKalenderMaand(kalenderMaand);
    if (d == null) return _formatMaand(kalenderMaand);
    return DateFormat.yMMMM('nl_NL').format(DateTime(d.year, d.month));
  }

  DateTime? _parseKalenderMaand(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return DateTime(v.year, v.month);
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final dt = DateTime.tryParse(s);
    if (dt != null) return DateTime(dt.year, dt.month);
    final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(s);
    if (m != null) {
      final y = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      if (y != null && mo != null && mo >= 1 && mo <= 12) {
        return DateTime(y, mo);
      }
    }
    return null;
  }

  String _formatBruto(dynamic v) => _eur.format(_parseLoonDouble(v));

  /// Weergave met komma als decimaal (nl_NL), bv. `1,5`.
  String _formatUrenNl(dynamic v) {
    final d = _asDouble(v);
    if (d == 0 && v == null) return '0';
    if (d == d.roundToDouble()) return d.toInt().toString();
    return NumberFormat.decimalPattern('nl_NL').format(d);
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

  double? _parseNullableDouble(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return _asDouble(v);
  }

  /// Parser voor loon-kolommen: eerst `double.tryParse(.toString())` (int-safe),
  /// daarna nl.-notatie (`1.234,56`).
  double _parseLoonDouble(dynamic v) {
    if (v == null) return 0.0;
    final normalized = v
        .toString()
        .trim()
        .replaceAll(' ', '')
        .replaceAll('€', '');
    if (normalized.isEmpty) return 0.0;
    final fromTryParse = double.tryParse(normalized);
    if (fromTryParse != null) return fromTryParse;
    if (normalized.contains(',')) {
      return double.tryParse(
            normalized.replaceAll('.', '').replaceAll(',', '.'),
          ) ??
          0.0;
    }
    return 0.0;
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

  String _urenStatusNorm(Map<String, dynamic> r) =>
      (r['uren_status'] ?? '').toString().toLowerCase().trim();

  double _taakDuurInUren(Map<String, dynamic> taak) =>
      _asDouble(taak['gewerkte_uren_decimaal']);

  /// Totaal Overzicht: geaccordeerde uren per kalendermaand, salaris met vast
  /// contract (vast maandsalaris + overwerk) of uurbasis per maand.
  ({double bruto, double uren}) _geaccordeerdAllTimeAnalytics() {
    var berekendTotaalSalaris = 0.0;
    var berekendTotaalUren = 0.0;

    final alleGeaccordeerdeTaken = _shiftsLijst
        .where((r) => _urenStatusNorm(r) == 'geaccordeerd')
        .toList();

    final urenPerMaand = <String, double>{};
    var totaalBrutoLoonkosten = 0.0;

    for (final taak in alleGeaccordeerdeTaken) {
      final date = _parseShiftDay(taak['geplande_datum']);
      if (date == null) continue;

      final monthKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}';
      final duur = _taakDuurInUren(taak);

      urenPerMaand[monthKey] = (urenPerMaand[monthKey] ?? 0.0) + duur;
      berekendTotaalUren += duur;
      totaalBrutoLoonkosten += _parseLoonDouble(taak['bruto_loonkosten']);
    }

    final uurtarief = berekendTotaalUren > 0
        ? totaalBrutoLoonkosten / berekendTotaalUren
        : 20.0;

    final heeftVastContract = _heeftVastContractVoorMaandDashboard();
    final contractVasteUren = _contractVasteUren;
    final contractVastSalaris = _contractVastSalaris;

    for (final entry in urenPerMaand.entries) {
      final maandUren = entry.value;
      if (heeftVastContract &&
          contractVasteUren != null &&
          contractVastSalaris != null) {
        final overwerkUren = math.max(0.0, maandUren - contractVasteUren);
        berekendTotaalSalaris +=
            contractVastSalaris + (overwerkUren * uurtarief);
      } else {
        berekendTotaalSalaris += maandUren * uurtarief;
      }
    }

    return (bruto: berekendTotaalSalaris, uren: berekendTotaalUren);
  }

  double _pendingSubmittedHours() {
    var u = 0.0;
    for (final row in _shiftsLijst) {
      if (_urenStatusNorm(row) == 'ingediend') {
        u += _asDouble(row['gewerkte_uren_decimaal']);
      }
    }
    return u;
  }

  List<Map<String, dynamic>> _overviewShiftsRows() {
    return _shiftsLijst.where((r) => _urenStatusNorm(r) != 'open').toList();
  }

  /// Overzicht-tab: gefilterd op kalenderhuidige maand (ingediend + geaccordeerd).
  List<Map<String, dynamic>> _overzichtLijstVoorModus() {
    final base = _overviewShiftsRows();
    if (!_overzichtMaandModus) return base;
    final n = DateTime.now();
    return base.where((r) {
      final d = _parseShiftDay(r['geplande_datum']);
      if (d == null) return false;
      return d.year == n.year && d.month == n.month;
    }).toList();
  }

  ({double uren, double bruto}) _geaccordeerdUrenEnBrutoDezeMaand() {
    final n = DateTime.now();
    var u = 0.0;
    var b = 0.0;
    for (final row in _shiftsLijst) {
      if (_urenStatusNorm(row) != 'geaccordeerd') continue;
      final d = _parseShiftDay(row['geplande_datum']);
      if (d == null || d.year != n.year || d.month != n.month) continue;
      u += _asDouble(row['gewerkte_uren_decimaal']);
      b += _parseLoonDouble(row['bruto_loonkosten']);
    }
    return (uren: u, bruto: b);
  }

  bool _heeftVastContractVoorMaandDashboard() {
    final u = _contractVasteUren;
    final s = _contractVastSalaris;
    return u != null && u > 0 && s != null && s > 0;
  }

  Widget _buildOverzichtSegmentToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment<bool>(
            value: false,
            label: Text('Totaal overzicht'),
            icon: Icon(Icons.dashboard_outlined),
          ),
          ButtonSegment<bool>(
            value: true,
            label: Text('Deze maand'),
            icon: Icon(Icons.calendar_month_rounded),
          ),
        ],
        emptySelectionAllowed: false,
        multiSelectionEnabled: false,
        selected: {_overzichtMaandModus},
        onSelectionChanged: (Set<bool> next) {
          if (next.isEmpty) return;
          setState(() => _overzichtMaandModus = next.first);
        },
      ),
    );
  }

  Widget _buildMaandHrDashboard() {
    final g = _geaccordeerdUrenEnBrutoDezeMaand();
    final geacc = g.uren;
    final brutoAcc = g.bruto;
    final uurtarief = geacc > 0 ? brutoAcc / geacc : 20.0;
    final voorschot = _voorschotBedrag;
    final vU = _contractVasteUren;
    final vS = _contractVastSalaris;
    final heeftContract = _heeftVastContractVoorMaandDashboard();

    final salarisUurbasis = geacc * uurtarief;
    final nogUurbasis = salarisUurbasis - voorschot;

    final overwerkUren = heeftContract && vU != null
        ? math.max(0.0, geacc - vU)
        : 0.0;
    final extraVerdiensten = heeftContract ? overwerkUren * uurtarief : 0.0;
    final totaalBrutoContract = heeftContract && vS != null
        ? vS + extraVerdiensten
        : 0.0;
    final nogContract = heeftContract
        ? totaalBrutoContract - voorschot
        : nogUurbasis;

    final denom = (vU != null && vU > 0) ? vU : 1.0;
    final progressRaw = geacc / denom;
    final progress = progressRaw.isFinite ? progressRaw.clamp(0.0, 1.0) : 0.0;

    final hoofdBedrag = heeftContract ? nogContract : nogUurbasis;
    final sub1Links = heeftContract
        ? _eur.format(vS ?? 0)
        : _eur.format(salarisUurbasis);
    final sub2 = _eur.format(voorschot);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_deepNavy, _brightBlue],
              ),
              boxShadow: [
                BoxShadow(
                  color: _brightBlue.withValues(alpha: 0.28),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nog te ontvangen: ${_eur.format(hoofdBedrag)}',
                  style: GoogleFonts.lato(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  heeftContract
                      ? 'Vast salaris: $sub1Links | Reeds uitbetaald (Voorschot): $sub2'
                      : 'Bruto gewerkt: $sub1Links | Reeds uitbetaald: $sub2',
                  style: GoogleFonts.lato(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
          if (heeftContract) ...[
            const SizedBox(height: 14),
            Text(
              'Contract uren: ${_formatUrenNl(geacc)} / ${_formatUrenNl(vU)} uur',
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.grey.shade300,
                color: _brightBlue,
              ),
            ),
            if (overwerkUren > 0) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF166534).withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'Extra verdiensten: ${_eur.format(extraVerdiensten)} '
                  '(+ ${_formatUrenNl(overwerkUren)} uur)',
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: const Color(0xFF166534),
                  ),
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Totaal geaccordeerde uren deze maand: ${_formatUrenNl(geacc)} uur',
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Uurtarief (indicatie): ${_eur.format(uurtarief)} / uur',
              style: GoogleFonts.lato(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _openShiftsForDay(DateTime day) {
    final key = _dayOnly(day);
    return _shiftsLijst.where((r) {
      final d = _parseShiftDay(r['geplande_datum']);
      return d != null && _dayOnly(d) == key && _urenStatusNorm(r) == 'open';
    }).toList();
  }

  /// Open uren in de maand van de kalender-focus, exclusief de geselecteerde dag (die staat al bovenaan).
  /// Geen taken in de toekomst (vangnet).
  List<Map<String, dynamic>> _openShiftsVoorMaandExclusiefGeselecteerdeDag() {
    final m = _regCalendarFocusedDay;
    final sel = _regCalendarSelectedDay ?? m;
    final selKey = _dayOnly(sel);
    final vandaag = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final out = <Map<String, dynamic>>[];
    for (final r in _shiftsLijst) {
      if (_urenStatusNorm(r) != 'open') continue;
      final d = _parseShiftDay(r['geplande_datum']);
      if (d == null) continue;
      final taakDag = DateTime(d.year, d.month, d.day);
      if (taakDag.isAfter(vandaag)) continue;
      if (d.year != m.year || d.month != m.month) continue;
      if (_dayOnly(d) == selKey) continue;
      out.add(r);
    }
    out.sort((a, b) {
      final da = _parseShiftDay(a['geplande_datum']);
      final db = _parseShiftDay(b['geplande_datum']);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      final c = da.compareTo(db);
      if (c != 0) return c;
      return _safeTime(a['starttijd']).compareTo(_safeTime(b['starttijd']));
    });
    return out;
  }

  bool _calendarDayHasStatus(DateTime day, Set<String> statuses) {
    final key = _dayOnly(day);
    for (final r in _shiftsLijst) {
      final d = _parseShiftDay(r['geplande_datum']);
      if (d == null || _dayOnly(d) != key) continue;
      if (statuses.contains(_urenStatusNorm(r))) return true;
    }
    return false;
  }

  Map<String, dynamic>? _approvedHeroRow() {
    final t = _geaccordeerdAllTimeAnalytics();
    if (t.bruto == 0 && t.uren == 0) return null;
    return {'totaal_bruto_verdiend': t.bruto, 'totaal_gewerkte_uren': t.uren};
  }

  double _urenDezeWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final windowStart = today.subtract(const Duration(days: 6));
    double sum = 0;
    for (final row in _shiftsLijst) {
      if (_urenStatusNorm(row) != 'geaccordeerd') continue;
      final day = _parseShiftDay(row['geplande_datum']);
      if (day == null) continue;
      if (!day.isBefore(windowStart) && !day.isAfter(today)) {
        sum += _asDouble(row['gewerkte_uren_decimaal']);
      }
    }
    return sum;
  }

  Map<String, dynamic>? _opdrachtEmbed(Map<String, dynamic> row) {
    final a = row['opdracht'];
    if (a is Map<String, dynamic>) return a;
    if (a is Map) return Map<String, dynamic>.from(a);
    final b = row['opdrachten'];
    if (b is Map<String, dynamic>) return b;
    if (b is Map) return Map<String, dynamic>.from(b);
    return null;
  }

  String _shiftBedrijfsnaam(Map<String, dynamic> row) {
    final direct = row['bedrijfsnaam']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = _opdrachtEmbed(row);
    if (nested != null) {
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
    return 'Locatie';
  }

  /// Adres uit geneste `opdracht` (embed), met beperkte fallbacks.
  String _uitvoerAdresVolledigVoorRegistratie(Map<String, dynamic> item) {
    String pick(dynamic v) => (v ?? '').toString().trim();

    final op = item['opdracht'];
    if (op is Map) {
      final fromOp = pick(op['uitvoer_adres_volledig']);
      if (fromOp.isNotEmpty) return fromOp;
    }

    final top = pick(item['uitvoer_adres_volledig']);
    if (top.isNotEmpty) return top;

    final proj = item['projecten'];
    if (proj is Map) {
      final fromProj = pick(proj['uitvoer_adres_volledig']);
      if (fromProj.isNotEmpty) return fromProj;
    }

    final opdr = item['opdrachten'];
    if (opdr is Map) {
      final fromLegacy = pick(opdr['uitvoer_adres_volledig']);
      if (fromLegacy.isNotEmpty) return fromLegacy;
      final opProj = opdr['projecten'];
      if (opProj is Map) {
        final fromOpProj = pick(opProj['uitvoer_adres_volledig']);
        if (fromOpProj.isNotEmpty) return fromOpProj;
      }
    }

    return 'Adres onbekend';
  }

  String _safeTime(dynamic timeValue) {
    if (timeValue == null) return '—';
    final t = timeValue.toString().trim();
    if (t.length >= 5) return t.substring(0, 5);
    return t.isEmpty ? '—' : t;
  }

  ({Color bg, Color fg, String label}) _statusPillUi(String? raw) {
    final s = (raw ?? '').toLowerCase().trim();
    if (s == 'uitbetaald') {
      return (
        bg: const Color(0xFFDCFCE7),
        fg: const Color(0xFF166534),
        label: 'Uitbetaald',
      );
    }
    return (
      bg: const Color(0xFFF3F4F6),
      fg: const Color(0xFF4B5563),
      label: 'Open',
    );
  }

  List<Map<String, dynamic>> _maandenHistorieZonderHuidigeMaand() {
    final key = _currentKalenderMaandKey();
    return _maandenLijst
        .where((row) => _kalenderMaandKey(row['kalender_maand']) != key)
        .toList();
  }

  BoxDecoration _cardDecoration({Border? border}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: border,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  BoxDecoration _kpiDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _heroCard(Map<String, dynamic>? row) {
    final double displayAmount;
    final double displayHours;
    if (row != null) {
      final rawAmount = row['totaal_bruto_verdiend'];
      final rawHours = row['totaal_gewerkte_uren'];
      displayAmount =
          double.tryParse(rawAmount?.toString().trim() ?? '') ??
          _parseLoonDouble(rawAmount);
      displayHours =
          double.tryParse(rawHours?.toString().trim() ?? '') ??
          _parseLoonDouble(rawHours);
    } else {
      displayAmount = 0.0;
      displayHours = 0.0;
    }

    final brutoText = _eur.format(displayAmount);
    final urenText = displayHours == displayHours.roundToDouble()
        ? displayHours.toInt().toString()
        : NumberFormat.decimalPattern('nl_NL').format(displayHours);

    final emptyMonthRows = row == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_deepNavy, _brightBlue],
        ),
        boxShadow: [
          BoxShadow(
            color: _brightBlue.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Totaal Verdiend (All-Time)',
            style: GoogleFonts.lato(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          if (emptyMonthRows)
            Text(
              'Nog geen uren geregistreerd.',
              style: GoogleFonts.lato(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.35,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            )
          else ...[
            Text(
              brutoText,
              style: GoogleFonts.lato(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: Colors.white,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Text('🕒', style: GoogleFonts.lato(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$urenText uur geregistreerd',
                    style: GoogleFonts.lato(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpiChip({
    required String title,
    required String value,
    IconData? icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        decoration: _kpiDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.lato(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.lato(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiRow() {
    final weekUren = _urenDezeWeek();
    final weekLabel = weekUren == weekUren.roundToDouble()
        ? '${weekUren.toInt()} u'
        : '${weekUren.toStringAsFixed(1)} u';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          _kpiChip(
            title: 'Totaal diensten',
            value: '${_overviewShiftsRows().length}',
            icon: Icons.calendar_month_rounded,
          ),
          const SizedBox(width: 12),
          _kpiChip(
            title: 'Uren deze week',
            value: weekLabel,
            icon: Icons.schedule_rounded,
          ),
        ],
      ),
    );
  }

  Widget _premiumShiftCard(Map<String, dynamic> row) {
    final day = _parseShiftDay(row['geplande_datum']);
    final dayNum = day != null ? '${day.day}' : '—';
    final naam = _shiftBedrijfsnaam(row);
    final t0 = _safeTime(row['werkelijke_starttijd']);
    final t1 = _safeTime(row['werkelijke_eindtijd']);
    final tijden = '$t0 – $t1';
    final urenLabel = '${_formatUrenNl(row['gewerkte_uren_decimaal'])} u';
    final brutoText = _formatBruto(row['bruto_loonkosten']);
    final isPendingApproval = _urenStatusNorm(row) == 'ingediend';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: _cardDecoration(
          border: isPendingApproval
              ? Border.all(color: Colors.orange.shade700, width: 2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isPendingApproval)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'In afwachting van goedkeuring',
                  style: GoogleFonts.lato(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFEEF2FF),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    dayNum,
                    style: GoogleFonts.lato(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: _deepNavy,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        naam,
                        style: GoogleFonts.lato(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tijden,
                        style: GoogleFonts.lato(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Geregistreerde uren',
                      style: GoogleFonts.lato(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      urenLabel,
                      style: GoogleFonts.lato(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      brutoText,
                      style: GoogleFonts.lato(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _shiftTile(Map<String, dynamic> row) => _premiumShiftCard(row);

  Widget _maandHistorieTile(Map<String, dynamic> row) {
    final maand = _formatMaandLongNl(row['kalender_maand']);
    final rawUren = row['totaal_gewerkte_uren'];
    final rawBruto = row['totaal_bruto_verdiend'];
    final urenVal =
        double.tryParse(rawUren?.toString().trim() ?? '') ??
        _parseLoonDouble(rawUren);
    final brutoVal =
        double.tryParse(rawBruto?.toString().trim() ?? '') ??
        _parseLoonDouble(rawBruto);
    final uren = urenVal == urenVal.roundToDouble()
        ? urenVal.toInt().toString()
        : NumberFormat.decimalPattern('nl_NL').format(urenVal);
    final bruto = _eur.format(brutoVal);
    final pill = _statusPillUi(row['status']?.toString());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showMonthDetails(row['kalender_maand']),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            maand,
                            style: GoogleFonts.lato(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$uren uur · $bruto',
                            style: GoogleFonts.lato(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: pill.bg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        pill.label,
                        style: GoogleFonts.lato(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          color: pill.fg,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Bekijk specificatie',
                      style: GoogleFonts.lato(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: _brightBlue,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: _brightBlue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMonthDetails(dynamic kalenderMaandRaw) async {
    final kalenderMaand = _kalenderMaandKey(kalenderMaandRaw);
    if (kalenderMaand.isEmpty || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final height = MediaQuery.sizeOf(sheetContext).height * 0.8;
        return SelectionArea(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              height: height,
              color: _pageBg,
              child: _MaandShiftsModal(
                kalenderMaand: kalenderMaand,
                headerTitle: _formatMaand(kalenderMaand),
                shiftTile: _premiumShiftCard,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _emptyShifts() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
      child: Text(
        'Je hebt nog geen diensten in dit overzicht.',
        textAlign: TextAlign.center,
        style: GoogleFonts.lato(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _emptyMaandenHistorie() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
      child: Text(
        'Geen eerdere maanden beschikbaar.',
        textAlign: TextAlign.center,
        style: GoogleFonts.lato(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
          height: 1.45,
        ),
      ),
    );
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

  List<String> _calendarEventsForDay(DateTime day) {
    final out = <String>[];
    if (_calendarDayHasStatus(day, {'open'})) out.add('o');
    if (_calendarDayHasStatus(day, {'ingediend', 'geaccordeerd'})) {
      out.add('g');
    }
    return out;
  }

  Future<void> _openUrenInvullenSheet(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;

    final nu = DateTime.now();
    final vandaag = DateTime(nu.year, nu.month, nu.day);
    final parsed = _parseShiftDay(row['geplande_datum']);
    final taakDatum =
        parsed ??
        DateTime.tryParse(row['geplande_datum'].toString().trim()) ??
        nu;
    final taakDag = DateTime(taakDatum.year, taakDatum.month, taakDatum.day);
    if (taakDag.isAfter(vandaag)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Je kunt geen uren in de toekomst invullen!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final startT =
        _timeOfDayFromRaw(row['starttijd']) ??
        _timeOfDayFromRaw(row['werkelijke_starttijd']);
    final endT =
        _timeOfDayFromRaw(row['eindtijd']) ??
        _timeOfDayFromRaw(row['werkelijke_eindtijd']);

    final day = _parseShiftDay(row['geplande_datum']);
    final datumStr = day != null
        ? DateFormat('EEEE d MMMM yyyy', 'nl_NL').format(day)
        : '—';
    final project = _shiftBedrijfsnaam(row);

    final times = <TimeOfDay>[
      startT ?? const TimeOfDay(hour: 8, minute: 0),
      endT ?? const TimeOfDay(hour: 17, minute: 0),
    ];

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset =
            MediaQuery.paddingOf(ctx).bottom +
            MediaQuery.viewInsetsOf(ctx).bottom;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            void pickStart() async {
              final t = await showTimePicker(
                context: ctx,
                initialTime: times[0],
              );
              if (t != null) setModal(() => times[0] = t);
            }

            void pickEnd() async {
              final t = await showTimePicker(
                context: ctx,
                initialTime: times[1],
              );
              if (t != null) setModal(() => times[1] = t);
            }

            final dur = _workDurationMinutes(times[0], times[1]);
            final totalMin = dur.inMinutes;
            final hPart = totalMin ~/ 60;
            final mPart = totalMin % 60;
            final urenDec = totalMin / 60.0;

            Future<void> submit() async {
              final ok = await showDialog<bool>(
                context: ctx,
                builder: (dCtx) => AlertDialog(
                  title: const Text('Bevestigen'),
                  content: const Text('Weet je het zeker?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dCtx, false),
                      child: const Text('Nee'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dCtx, true),
                      child: const Text('Ja'),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
              try {
                await Supabase.instance.client
                    .from('opdracht_planning')
                    .update({
                      'werkelijke_starttijd': _timeToDb(times[0]),
                      'werkelijke_eindtijd': _timeToDb(times[1]),
                      'uren_status': 'ingediend',
                      'gewerkte_uren_decimaal': urenDec,
                    })
                    .eq('id', id);
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                if (!mounted) return;
                await _loadData();
                if (!mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Uren ingediend.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('Fout: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: Material(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          datumStr,
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          project,
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        OutlinedButton(
                          onPressed: pickStart,
                          child: Text(
                            'Starttijd: ${times[0].format(ctx)}',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: pickEnd,
                          child: Text(
                            'Eindtijd: ${times[1].format(ctx)}',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Gewerkte uren: $hPart uur $mPart min',
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: _brightBlue,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: submit,
                          child: Text(
                            'Uren indienen',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _pageBg,
        drawer: const AppDrawer(),
        appBar: AppBar(
          backgroundColor: _pageBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
          title: Text(
            'Mijn Uren & Salaris',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: -0.5,
              color: const Color(0xFF0F172A),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loadData,
              tooltip: 'Vernieuwen',
            ),
          ],
          bottom: _isLoading || _errorMessage.isNotEmpty
              ? null
              : TabBar(
                  labelColor: _brightBlue,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: _brightBlue,
                  indicatorWeight: 3,
                  labelStyle: GoogleFonts.lato(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: -0.5,
                  ),
                  unselectedLabelStyle: GoogleFonts.lato(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: -0.5,
                  ),
                  tabs: const [
                    Tab(text: 'Overzicht'),
                    Tab(text: 'Uren Registreren'),
                  ],
                ),
        ),
        body: SelectionArea(
          child: _isLoading
              ? const Center(child: CupertinoActivityIndicator(radius: 18))
              : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'Kon gegevens niet laden.\n$_errorMessage',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lato(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Colors.red.shade800,
                        height: 1.45,
                      ),
                    ),
                  ),
                )
              : TabBarView(
                  children: [_buildOverzichtTab(), _buildRegistratieTab()],
                ),
        ),
      ),
    );
  }

  Widget _buildOverzichtTab() {
    final overview = _overzichtLijstVoorModus();
    final hist = _maandenHistorieZonderHuidigeMaand();
    final pending = _pendingSubmittedHours();
    final heroRow = _approvedHeroRow();

    return RefreshIndicator(
      color: _brightBlue,
      onRefresh: _loadData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildOverzichtSegmentToggle()),
          if (!_overzichtMaandModus) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _heroCard(heroRow),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(
                  'In afwachting: ${_formatUrenNl(pending)} uur',
                  style: GoogleFonts.lato(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildKpiRow()),
          ] else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Text(
                  'In afwachting: ${_formatUrenNl(pending)} uur',
                  style: GoogleFonts.lato(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildMaandHrDashboard()),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                _overzichtMaandModus
                    ? 'Diensten deze maand'
                    : 'Recente diensten',
                style: GoogleFonts.lato(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _deepNavy,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          if (overview.isEmpty)
            SliverToBoxAdapter(child: _emptyShifts())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _shiftTile(overview[index]),
                  childCount: overview.length,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Maandoverzichten',
                style: GoogleFonts.lato(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _deepNavy,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          if (hist.isEmpty)
            SliverToBoxAdapter(child: _emptyMaandenHistorie())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _maandHistorieTile(hist[index]),
                  childCount: hist.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: mobileNavBuffer)),
        ],
      ),
    );
  }

  Widget _registratieOpenShiftTile(
    BuildContext context,
    Map<String, dynamic> row, {
    required bool toonDatumInSubtitel,
    required bool isDagLijst,
    bool compact = false,
  }) {
    final tt = Theme.of(context).textTheme;
    final day = _parseShiftDay(row['geplande_datum']);
    final timeLine =
        '${_safeTime(row['starttijd'])} – ${_safeTime(row['eindtijd'])}';
    final adres = _uitvoerAdresVolledigVoorRegistratie(row);

    final cardColor = isDagLijst ? Colors.blue.shade50 : Colors.white;
    final cardRadius = BorderRadius.circular(isDagLijst ? 12 : 14);
    final cardShape = RoundedRectangleBorder(
      borderRadius: cardRadius,
      side: isDagLijst
          ? BorderSide(color: Colors.blue.shade200)
          : BorderSide.none,
    );

    final subtitleChildren = <Widget>[
      if (toonDatumInSubtitel && day != null) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: compact ? 15 : 16,
              color: Colors.grey.shade700,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                DateFormat('EEEE d MMMM', 'nl_NL').format(day),
                style: (compact ? tt.bodySmall : tt.bodyMedium)?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 4 : 6),
      ],
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.access_time_rounded,
            size: compact ? 15 : 16,
            color: Colors.grey.shade700,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              timeLine,
              style: (compact ? tt.bodySmall : tt.bodyMedium)?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              adres,
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
          ),
        ],
      ),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 6 : 8),
      child: Material(
        color: cardColor,
        shape: cardShape,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 6 : 8,
          ),
          shape: cardShape,
          title: Text(
            _shiftBedrijfsnaam(row),
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: compact ? 14 : 15,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: subtitleChildren,
          ),
          trailing: Icon(
            Icons.edit_calendar_rounded,
            color: _brightBlue,
            size: compact ? 26 : 28,
          ),
          onTap: () => _openUrenInvullenSheet(row),
        ),
      ),
    );
  }

  Widget _buildRegistratieTab() {
    final sel = _regCalendarSelectedDay ?? _regCalendarFocusedDay;
    final openList = _openShiftsForDay(sel);
    final maandVangnet = _openShiftsVoorMaandExclusiefGeselecteerdeDag();
    final dagTitel = DateFormat('EEEE d MMMM yyyy', 'nl_NL').format(sel);
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TableCalendar<void>(
            locale: 'nl_NL',
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _regCalendarFocusedDay,
            selectedDayPredicate: (d) => isSameDay(_regCalendarSelectedDay, d),
            calendarFormat: _regCalendarFormat,
            availableCalendarFormats: const {
              CalendarFormat.month: 'Maand',
              CalendarFormat.twoWeeks: '2 weken',
              CalendarFormat.week: 'Week',
            },
            eventLoader: _calendarEventsForDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            calendarStyle: CalendarStyle(
              markersMaxCount: 3,
              markerDecoration: const BoxDecoration(color: Colors.transparent),
            ),
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                if (events.isEmpty) return const SizedBox.shrink();
                final hasOpen = events.contains('o');
                final hasGreen = events.contains('g');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (hasOpen)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      if (hasOpen && hasGreen) const SizedBox(width: 3),
                      if (hasGreen)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _regCalendarSelectedDay = selectedDay;
                _regCalendarFocusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() => _regCalendarFocusedDay = focusedDay);
            },
            onFormatChanged: (format) {
              setState(() => _regCalendarFormat = format);
            },
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Uren voor $dagTitel',
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                if (openList.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Alle uren voor deze dag zijn ingevuld! ✅',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lato(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: openList.length,
                    itemBuilder: (context, index) {
                      return _registratieOpenShiftTile(
                        context,
                        openList[index],
                        toonDatumInSubtitel: false,
                        isDagLijst: true,
                      );
                    },
                  ),
                const SizedBox(height: 20),
                Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  'Alle openstaande uren deze maand',
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                if (maandVangnet.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, top: 4),
                    child: Text(
                      'Geen andere openstaande uren in deze maand.',
                      style: tt.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: maandVangnet.length,
                    itemBuilder: (context, index) {
                      return _registratieOpenShiftTile(
                        context,
                        maandVangnet[index],
                        toonDatumInSubtitel: true,
                        isDagLijst: false,
                        compact: true,
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: mobileNavBuffer),
      ],
    );
  }
}

class _MaandShiftsModal extends StatefulWidget {
  const _MaandShiftsModal({
    required this.kalenderMaand,
    required this.headerTitle,
    required this.shiftTile,
  });

  final String kalenderMaand;
  final String headerTitle;
  final Widget Function(Map<String, dynamic> row) shiftTile;

  @override
  State<_MaandShiftsModal> createState() => _MaandShiftsModalState();
}

class _MaandShiftsModalState extends State<_MaandShiftsModal> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Niet ingelogd.';
      });
      return;
    }

    try {
      final raw = await Supabase.instance.client
          .from('view_operator_maand_shifts')
          .select()
          .eq('operator_id', uid)
          .eq('kalender_maand', widget.kalenderMaand)
          .order('geplande_datum', ascending: false);

      final list = (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
        _errorMessage = '';
      });
    } catch (e, st) {
      debugPrint('_MaandShiftsModal._load error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Diensten in ${widget.headerTitle}',
                    style: GoogleFonts.lato(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: const Color(0xFF0F172A),
                      height: 1.25,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.grey.shade700,
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Sluiten',
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator(radius: 18))
                : _errorMessage.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Kon diensten niet laden.\n$_errorMessage',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lato(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.red.shade800,
                        height: 1.45,
                      ),
                    ),
                  )
                : _rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        'Geen diensten gevonden voor deze maand.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                          height: 1.45,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    itemCount: _rows.length,
                    itemBuilder: (context, index) =>
                        widget.shiftTile(_rows[index]),
                  ),
          ),
        ],
      ),
    );
  }
}
