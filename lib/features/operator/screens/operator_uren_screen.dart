import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/utils/payroll_calculation.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';

/// Operator: uren/salaris-overzicht via [opdracht_planning] en [operator_uitbetalingen].
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

  List<Map<String, dynamic>> _shiftsLijst = [];
  List<Map<String, dynamic>> _afgeslotenMaanden = [];
  bool _isLoading = true;
  String _errorMessage = '';

  /// Tab Overzicht: `true` = Deze Maand (default), `false` = Historie.
  bool _overzichtIsDezeMaand = true;

  /// Ruwe `gebruikers`-rij voor payroll (standaard_uurloon, contractvelden).
  Map<String, dynamic>? _gebruikerPayrollRow;
  double _voorschotBedrag = 0;

  DateTime _regCalendarFocusedDay = DateTime.now();
  DateTime? _regCalendarSelectedDay = DateTime.now();
  CalendarFormat _regCalendarFormat = CalendarFormat.month;
  final PageController _registratieSliderController =
      PageController(viewportFraction: 0.8);

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
    _registratieSliderController.dispose();
    super.dispose();
  }

  Widget _regCalendarChevron({required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFF0F4FA),
            _brightBlue.withValues(alpha: 0.08),
          ],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: _brightBlue.withValues(alpha: 0.12)),
      ),
      child: Icon(icon, size: 20, color: _deepNavy),
    );
  }

  Future<void> _loadData() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Niet ingelogd.';
        _shiftsLijst = [];
        _afgeslotenMaanden = [];
        _gebruikerPayrollRow = null;
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

      final shiftsResponse = await client
          .from('opdracht_planning')
          .select(
            'id, opdracht_id, geplande_datum, starttijd, eindtijd, '
            'werkelijke_starttijd, werkelijke_eindtijd, gewerkte_uren_decimaal, '
            'bruto_loonkosten, uren_status, status, bedrijfsnaam, '
            'opdracht:opdrachten!opdracht_planning_opdracht_id_fkey('
            'status, uitvoer_adres_volledig, bedrijfsnaam, projecten(project_naam))',
          )
          .eq('operator_id', uid)
          .neq('status', OpdrachtPlanningStatus.geannuleerd)
          .neq('status', OpdrachtPlanningStatus.noShow)
          .order('geplande_datum', ascending: false)
          .limit(200);

      final shifts = (shiftsResponse as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where(_isUrenShiftZichtbaar)
          .toList();

      Map<String, dynamic>? gebruikerPayrollRow;
      double voorschot = 0;
      try {
        final u = await client
            .from('gebruikers')
            .select(
              'standaard_uurloon, contract_vaste_uren, contract_vast_salaris, '
              'contract_startdatum, contract_einddatum',
            )
            .eq('id', uid)
            .maybeSingle();
        if (u != null) {
          gebruikerPayrollRow = Map<String, dynamic>.from(u as Map);
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

      var afgeslotenMaanden = <Map<String, dynamic>>[];
      try {
        final uitbetalingenRes = await client
            .from('operator_uitbetalingen')
            .select()
            .eq('operator_id', uid)
            .order('maand_sleutel', ascending: false);
        afgeslotenMaanden = (uitbetalingenRes as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (e) {
        debugPrint('OperatorUren: operator_uitbetalingen optioneel: $e');
      }

      if (!mounted) return;
      setState(() {
        _shiftsLijst = shifts;
        _afgeslotenMaanden = afgeslotenMaanden;
        _gebruikerPayrollRow = gebruikerPayrollRow;
        _voorschotBedrag = voorschot;
        _isLoading = false;
        _errorMessage = '';
      });
    } catch (e, st) {
      debugPrint('OperatorUrenScreen._loadData error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _shiftsLijst = [];
        _afgeslotenMaanden = [];
        _gebruikerPayrollRow = null;
        _voorschotBedrag = 0;
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  bool _isInHuidigeKalenderMaand(DateTime? dag) {
    if (dag == null) return false;
    final n = DateTime.now();
    return dag.year == n.year && dag.month == n.month;
  }

  Map<String, dynamic> _operatorPayrollProfiel() =>
      Map<String, dynamic>.from(_gebruikerPayrollRow ?? {});

  ({
    double uurTarief,
    double contractVastSalaris,
    double contractVasteUren,
    bool heeftVastContract,
  }) _payrollFinancien() {
    final operatorData = _operatorPayrollProfiel();

    final ruwUurloon =
        operatorData['standaard_uurloon']?.toString().replaceAll(',', '.') ??
        '0';
    final uurTarief = double.tryParse(ruwUurloon) ?? 0.0;

    final ruwVastSalaris =
        operatorData['contract_vast_salaris']?.toString().replaceAll(',', '.') ??
        '0';
    final contractVastSalaris = double.tryParse(ruwVastSalaris) ?? 0.0;

    final ruwVasteUren =
        operatorData['contract_vaste_uren']?.toString().replaceAll(',', '.') ??
        '0';
    final contractVasteUren = double.tryParse(ruwVasteUren) ?? 0.0;

    final heeftVastContract = contractVasteUren > 0;

    return (
      uurTarief: uurTarief,
      contractVastSalaris: contractVastSalaris,
      contractVasteUren: contractVasteUren,
      heeftVastContract: heeftVastContract,
    );
  }

  double _berekenTaakDuurInUren(Map<String, dynamic> taak) =>
      _urenUitTaakOfTijden(taak);

  ({double uren, double bruto}) _berekenSalarisVoorTaken(
    List<Map<String, dynamic>> taken, {
    bool sluitHuidigeMaandUit = false,
  }) {
    final fin = _payrollFinancien();
    var berekendTotaalSalaris = 0.0;
    var berekendTotaalUren = 0.0;
    final urenPerMaand = <String, double>{};
    final huidigeMaandSleutel = _currentKalenderMaandKey();

    for (final taak in taken) {
      final datumString = taak['geplande_datum']?.toString() ?? '';
      if (datumString.length >= 7) {
        final monthKey = datumString.substring(0, 7);
        final duur = _berekenTaakDuurInUren(taak);
        urenPerMaand[monthKey] = (urenPerMaand[monthKey] ?? 0.0) + duur;
        if (!sluitHuidigeMaandUit || monthKey != huidigeMaandSleutel) {
          berekendTotaalUren += duur;
        }
      }
    }

    for (final entry in urenPerMaand.entries) {
      if (sluitHuidigeMaandUit && entry.key == huidigeMaandSleutel) {
        continue;
      }

      final maandUren = entry.value;

      if (fin.heeftVastContract) {
        final overwerkUren = maandUren > fin.contractVasteUren
            ? (maandUren - fin.contractVasteUren)
            : 0.0;
        berekendTotaalSalaris +=
            fin.contractVastSalaris + (overwerkUren * fin.uurTarief);
      } else {
        berekendTotaalSalaris += maandUren * fin.uurTarief;
      }
    }

    return (uren: berekendTotaalUren, bruto: berekendTotaalSalaris);
  }

  List<Map<String, dynamic>> _alleGeaccordeerdeTaken() {
    return _shiftsLijst
        .where((r) => _urenStatusNorm(r) == 'geaccordeerd')
        .toList();
  }

  String _currentKalenderMaandKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  String _formatBruto(dynamic v) => _eur.format(_parseLoonDouble(v));

  /// Weergave met komma als decimaal (nl_NL), bv. `1,5`.
  String _formatUrenNl(dynamic v) {
    final d = _asDouble(v);
    if (d == 0 && v == null) return '0';
    if (d == d.roundToDouble()) return d.toInt().toString();
    return NumberFormat.decimalPattern('nl_NL').format(d);
  }

  bool _isUrenShiftZichtbaar(Map<String, dynamic> shift) {
    final planningStatus =
        (shift['status'] ?? '').toString().trim().toLowerCase();
    if (planningStatus == OpdrachtPlanningStatus.geannuleerd ||
        planningStatus == OpdrachtPlanningStatus.noShow) {
      return false;
    }

    final opdracht = shift['opdracht'];
    if (opdracht is Map) {
      final opdrachtStatus =
          (opdracht['status'] ?? '').toString().trim().toLowerCase();
      if (opdrachtStatus == OpdrachtPlanningStatus.geannuleerd ||
          opdrachtStatus == OpdrachtPlanningStatus.noShow) {
        return false;
      }
    }
    return true;
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

  double _urenUitTaakOfTijden(Map<String, dynamic> taak) {
    final uitTijden = PayrollCalculation.gewerkteUrenUitTaak(taak);
    if (uitTijden > 0) return uitTijden;
    return _asDouble(taak['gewerkte_uren_decimaal']);
  }

  List<Map<String, dynamic>> _geaccordeerdeTakenHuidigeMaand() {
    return _shiftsLijst.where((r) {
      if (_urenStatusNorm(r) != 'geaccordeerd') return false;
      return _isInHuidigeKalenderMaand(_parseShiftDay(r['geplande_datum']));
    }).toList();
  }

  double _pendingSubmittedHoursDezeMaand() {
    var u = 0.0;
    for (final row in _shiftsLijst) {
      if (_urenStatusNorm(row) != 'ingediend') continue;
      if (!_isInHuidigeKalenderMaand(_parseShiftDay(row['geplande_datum']))) {
        continue;
      }
      u += _urenUitTaakOfTijden(row);
    }
    return u;
  }

  List<Map<String, dynamic>> _overzichtDezeMaandLijst() {
    return _shiftsLijst.where((r) {
      if (_urenStatusNorm(r) == 'open') return false;
      return _isInHuidigeKalenderMaand(_parseShiftDay(r['geplande_datum']));
    }).toList();
  }

  ({double uren, double bruto, double uurtarief, bool isGeldigVastContract})
  _verwachtSalarisHuidigeMaand() {
    final fin = _payrollFinancien();
    final result = _berekenSalarisVoorTaken(_geaccordeerdeTakenHuidigeMaand());
    return (
      uren: result.uren,
      bruto: result.bruto,
      uurtarief: fin.uurTarief,
      isGeldigVastContract: fin.heeftVastContract,
    );
  }

  ({double uren, double bruto, double uurtarief, bool isGeldigVastContract})
  _verwachtSalarisHistorie() {
    final fin = _payrollFinancien();
    final result = _berekenSalarisVoorTaken(
      _alleGeaccordeerdeTaken(),
      sluitHuidigeMaandUit: true,
    );
    return (
      uren: result.uren,
      bruto: result.bruto,
      uurtarief: fin.uurTarief,
      isGeldigVastContract: fin.heeftVastContract,
    );
  }

  bool _isOverzichtIngediendOfGeaccordeerd(Map<String, dynamic> r) {
    final s = _urenStatusNorm(r);
    return s == 'ingediend' || s == 'geaccordeerd';
  }

  String _monthKeyFromTaak(Map<String, dynamic> taak) {
    final datumString = taak['geplande_datum']?.toString() ?? '';
    if (datumString.length >= 7) return datumString.substring(0, 7);
    return '';
  }

  Map<String, List<Map<String, dynamic>>> _takenPerHistorischeMaand() {
    final huidige = _currentKalenderMaandKey();
    final map = <String, List<Map<String, dynamic>>>{};
    for (final r in _shiftsLijst) {
      if (!_isOverzichtIngediendOfGeaccordeerd(r)) continue;
      final monthKey = _monthKeyFromTaak(r);
      if (monthKey.isEmpty || monthKey == huidige) continue;
      map.putIfAbsent(monthKey, () => []).add(r);
    }
    for (final list in map.values) {
      list.sort((a, b) {
        final da = _parseShiftDay(a['geplande_datum']);
        final db = _parseShiftDay(b['geplande_datum']);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    }
    return map;
  }

  List<String> _historischeMaandSleutelsGesorteerd() {
    final keys = _takenPerHistorischeMaand().keys.toList();
    keys.sort((a, b) => b.compareTo(a));
    return keys;
  }

  Map<String, dynamic>? _uitbetalingVoorMaandSleutel(String monthKey) {
    for (final row in _afgeslotenMaanden) {
      if (_text(row['maand_sleutel']) == monthKey) {
        return row;
      }
    }
    return null;
  }

  String _maandSleutelNaarLabel(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length == 2) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (y != null && m != null && m >= 1 && m <= 12) {
        return DateFormat.yMMMM('nl_NL').format(DateTime(y, m));
      }
    }
    return monthKey;
  }

  Widget _buildMaandHrDashboard() {
    final salaris = _verwachtSalarisHuidigeMaand();
    final fin = _payrollFinancien();
    final geacc = salaris.uren;
    final uurtarief = salaris.uurtarief;
    final voorschot = _voorschotBedrag;
    final vU = fin.contractVasteUren;
    final vS = fin.contractVastSalaris;
    final heeftContract = salaris.isGeldigVastContract;

    final brutoGewerkt = salaris.bruto;
    final nogUurbasis = brutoGewerkt - voorschot;

    final overwerkUren = heeftContract && vU > 0
        ? (geacc > vU ? (geacc - vU) : 0.0)
        : 0.0;
    final extraVerdiensten = heeftContract ? overwerkUren * uurtarief : 0.0;
    final totaalBrutoContract =
        heeftContract ? vS + extraVerdiensten : 0.0;
    final nogContract = heeftContract
        ? totaalBrutoContract - voorschot
        : nogUurbasis;

    final denom = vU > 0 ? vU : 1.0;
    final progressRaw = geacc / denom;
    final progress = progressRaw.isFinite ? progressRaw.clamp(0.0, 1.0) : 0.0;

    final hoofdBedrag = heeftContract ? nogContract : nogUurbasis;
    final sub1Links =
        heeftContract ? _eur.format(vS) : _eur.format(brutoGewerkt);
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

  Widget _buildOverzichtSegmentToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment<bool>(
            value: true,
            label: Text('Deze Maand'),
            icon: Icon(Icons.calendar_month_rounded),
          ),
          ButtonSegment<bool>(
            value: false,
            label: Text('Historie'),
            icon: Icon(Icons.history_rounded),
          ),
        ],
        emptySelectionAllowed: false,
        multiSelectionEnabled: false,
        selected: {_overzichtIsDezeMaand},
        onSelectionChanged: (Set<bool> next) {
          if (next.isEmpty) return;
          setState(() => _overzichtIsDezeMaand = next.first);
        },
      ),
    );
  }

  Widget _buildKpiRowDezeMaand() {
    final salarisMaand = _verwachtSalarisHuidigeMaand();
    final urenMaandLabel = salarisMaand.uren == salarisMaand.uren.roundToDouble()
        ? '${salarisMaand.uren.toInt()} u'
        : '${salarisMaand.uren.toStringAsFixed(1)} u';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          _kpiChip(
            title: 'Verwacht salaris',
            value: _eur.format(salarisMaand.bruto),
            icon: Icons.payments_outlined,
          ),
          const SizedBox(width: 12),
          _kpiChip(
            title: 'Uren deze maand',
            value: urenMaandLabel,
            icon: Icons.schedule_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRowHistorie() {
    final salaris = _verwachtSalarisHistorie();
    final urenLabel = salaris.uren == salaris.uren.roundToDouble()
        ? '${salaris.uren.toInt()} u'
        : '${salaris.uren.toStringAsFixed(1)} u';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          _kpiChip(
            title: 'Totaal verdiend (historie)',
            value: _eur.format(salaris.bruto),
            icon: Icons.savings_outlined,
          ),
          const SizedBox(width: 12),
          _kpiChip(
            title: 'Uren (excl. deze maand)',
            value: urenLabel,
            icon: Icons.schedule_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildMaandafsluitingCard(Map<String, dynamic> uitbetaling) {
    final bruto = _parseLoonDouble(uitbetaling['berekend_bruto']);
    final voorschot = _parseLoonDouble(uitbetaling['verrekend_voorschot']);
    final isBetaald = uitbetaling['is_betaald'] == true;
    final statusLabel = isBetaald
        ? 'Betaald'
        : 'In afwachting van uitbetaling';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: Colors.green.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Maandafsluiting beschikbaar',
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: const Color(0xFF1B5E20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Berekend bruto: ${_eur.format(bruto)}',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: const Color(0xFF2E7D32),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Verrekend voorschot: ${_eur.format(voorschot)}',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isBetaald
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isBetaald
                    ? const Color(0xFF166534)
                    : Colors.orange.shade700,
              ),
            ),
            child: Text(
              statusLabel,
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: isBetaald
                    ? const Color(0xFF166534)
                    : Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorieMaandSectie(String monthKey) {
    final taken = _takenPerHistorischeMaand()[monthKey] ?? [];
    final uitbetaling = _uitbetalingVoorMaandSleutel(monthKey);
    final maandLabel = _maandSleutelNaarLabel(monthKey);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20),
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: false,
        title: Text(
          maandLabel,
          style: GoogleFonts.lato(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: _deepNavy,
            letterSpacing: -0.3,
          ),
        ),
        subtitle: Text(
          '${taken.length} dienst${taken.length == 1 ? '' : 'en'}',
          style: GoogleFonts.lato(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        children: [
          if (uitbetaling != null) _buildMaandafsluitingCard(uitbetaling),
          if (taken.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Geen ingediende of geaccordeerde diensten in deze maand.',
                style: GoogleFonts.lato(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                children: [
                  for (final row in taken) _shiftTile(row),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistorieInhoud() {
    final maandSleutels = _historischeMaandSleutelsGesorteerd();
    final uitbetalingenZonderTaken = _afgeslotenMaanden
        .map((r) => _text(r['maand_sleutel']))
        .where(
          (k) =>
              k.isNotEmpty &&
              k != _currentKalenderMaandKey() &&
              !maandSleutels.contains(k),
        )
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (maandSleutels.isEmpty && uitbetalingenZonderTaken.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Text(
          'Nog geen historie beschikbaar. Oudere maanden verschijnen hier '
          'zodra je uren hebt ingediend of geaccordeerd.',
          textAlign: TextAlign.center,
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.grey.shade700,
            height: 1.45,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final key in maandSleutels) _buildHistorieMaandSectie(key),
        for (final key in uitbetalingenZonderTaken) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              _maandSleutelNaarLabel(key),
              style: GoogleFonts.lato(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: _deepNavy,
              ),
            ),
          ),
          if (_uitbetalingVoorMaandSleutel(key) != null)
            _buildMaandafsluitingCard(_uitbetalingVoorMaandSleutel(key)!),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  BoxDecoration get _premiumShiftCardDecoration => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F172A),
            _deepNavy,
            _brightBlue.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      );

  /// Overzicht / historie: ingevulde diensten in dezelfde premium stijl als registratie.
  Widget _premiumShiftCard(Map<String, dynamic> row) {
    final day = _parseShiftDay(row['geplande_datum']);
    final naam = _shiftBedrijfsnaam(row);
    final t0 = _safeTime(row['werkelijke_starttijd']);
    final t1 = _safeTime(row['werkelijke_eindtijd']);
    final tijden = '$t0 – $t1';
    final urenLabel = '${_formatUrenNl(row['gewerkte_uren_decimaal'])} uur';
    final brutoText = _formatBruto(row['bruto_loonkosten']);
    final isPendingApproval = _urenStatusNorm(row) == 'ingediend';
    final adres = _uitvoerAdresVolledigVoorRegistratie(row);
    final datumLabel = day != null
        ? DateFormat('EEEE d MMMM yyyy', 'nl_NL').format(day)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _premiumShiftCardDecoration,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPendingApproval)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade400.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                'In afwachting van goedkeuring',
                style: GoogleFonts.lato(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.orange.shade100,
                ),
              ),
            ),
          Text(
            naam,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              letterSpacing: -0.3,
              color: Colors.white,
            ),
          ),
          if (datumLabel != null) ...[
            const SizedBox(height: 14),
            _registratieSliderInfoRow(
              icon: Icons.calendar_today_rounded,
              text: datumLabel,
            ),
          ],
          const SizedBox(height: 14),
          _registratieSliderInfoRow(
            icon: Icons.access_time_rounded,
            text: tijden,
          ),
          if (adres.isNotEmpty && adres != 'Locatie') ...[
            const SizedBox(height: 10),
            _registratieSliderInfoRow(
              icon: Icons.location_on_rounded,
              text: adres,
              maxLines: 2,
            ),
          ],
          const SizedBox(height: 10),
          _registratieSliderInfoRow(
            icon: Icons.timelapse_rounded,
            text: 'Geregistreerd: $urenLabel',
          ),
          const SizedBox(height: 10),
          _registratieSliderInfoRow(
            icon: Icons.payments_outlined,
            text: brutoText,
          ),
        ],
      ),
    );
  }

  Widget _shiftTile(Map<String, dynamic> row) => _premiumShiftCard(row);

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

  bool _isPlanningAfgerond(Map<String, dynamic> row) {
    final planningStatus =
        (row[OpdrachtPlanningTable.status] ?? '').toString().trim().toLowerCase();
    if (planningStatus == OpdrachtPlanningStatus.afgerond) {
      return true;
    }
    final opdracht = row['opdracht'];
    if (opdracht is Map) {
      final opdrachtStatus = (opdracht[OpdrachtenTable.status] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (opdrachtStatus == OpdrachtStatus.afgerond) return true;
    }
    return false;
  }

  Future<void> _openUrenInvullenSheet(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;

    if (!_isPlanningAfgerond(row)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Rond deze opdracht eerst af op de rooster pagina om uren te kunnen invullen.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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
    final magUrenInvullen = _isPlanningAfgerond(row);
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
              if (!magUrenInvullen) return;
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
                          onPressed: magUrenInvullen ? pickStart : null,
                          child: Text(
                            'Starttijd: ${times[0].format(ctx)}',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: magUrenInvullen ? pickEnd : null,
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
                          onPressed: magUrenInvullen ? submit : null,
                          style: FilledButton.styleFrom(
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade600,
                          ),
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
                    Tab(text: 'Uren Registreren'),
                    Tab(text: 'Overzicht'),
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
                  children: [
                    _buildRegistratieTab(),
                    _buildOverzichtTab(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildOverzichtTab() {
    final alleOpgehaaldePlanningen = _shiftsLijst;
    // 1. Zoek de taken die nog openstaan en niet in de toekomst liggen
    final DateTime vandaag = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final int aantalOpenstaand = alleOpgehaaldePlanningen.where((t) {
      if (t['uren_status'] != 'open') return false;
      final taakDatum = DateTime.tryParse(
        t['geplande_datum']?.toString() ?? '',
      );
      if (taakDatum == null) return false;
      final taakDag = DateTime(taakDatum.year, taakDatum.month, taakDatum.day);
      return !taakDag.isAfter(vandaag); // Mag vandaag of verleden zijn
    }).length;

    final overview = _overzichtDezeMaandLijst();
    final pending = _pendingSubmittedHoursDezeMaand();

    return RefreshIndicator(
      color: _brightBlue,
      onRefresh: _loadData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildOverzichtSegmentToggle()),
          if (aantalOpenstaand > 0)
            SliverToBoxAdapter(
              child: Builder(
                builder: (tabContext) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.red.shade200,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.red.shade700,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Je hebt nog $aantalOpenstaand oningevulde dienst(en)!',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade600,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.edit_calendar),
                              label: const Text(
                                'Uren Nu Invullen',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () {
                                DefaultTabController.of(
                                  tabContext,
                                ).animateTo(0);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_overzichtIsDezeMaand) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
            SliverToBoxAdapter(child: _buildKpiRowDezeMaand()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  'Diensten deze maand',
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
          ] else ...[
            SliverToBoxAdapter(child: _buildKpiRowHistorie()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  'Archief per maand',
                  style: GoogleFonts.lato(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _deepNavy,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildHistorieInhoud()),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: mobileNavBuffer)),
        ],
      ),
    );
  }

  Widget _registratieOpenShiftTile(
    BuildContext context,
    Map<String, dynamic> row, {
    required bool toonDatumInSubtitel,
    bool forSlider = false,
  }) {
    final day = _parseShiftDay(row['geplande_datum']);
    final timeLine =
        '${_safeTime(row['starttijd'])} – ${_safeTime(row['eindtijd'])}';
    final adres = _uitvoerAdresVolledigVoorRegistratie(row);
    final magInvullen = _isPlanningAfgerond(row);
    final bedrijfsnaam = _shiftBedrijfsnaam(row);

    return _premiumRegistratieShiftCard(
      row: row,
      bedrijfsnaam: bedrijfsnaam,
      timeLine: timeLine,
      adres: adres,
      magInvullen: magInvullen,
      datumLabel: toonDatumInSubtitel && day != null
          ? DateFormat('EEEE d MMMM', 'nl_NL').format(day)
          : null,
      margin: forSlider
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : const EdgeInsets.only(bottom: 12),
      expandVertically: forSlider,
    );
  }

  /// Gedeelde premium card voor slider én verticale maandlijst (Uren Registreren).
  Widget _premiumRegistratieShiftCard({
    required Map<String, dynamic> row,
    required String bedrijfsnaam,
    required String timeLine,
    required String adres,
    required bool magInvullen,
    required EdgeInsetsGeometry margin,
    String? datumLabel,
    bool expandVertically = false,
  }) {
    final invullenKnop = SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              magInvullen ? Colors.orange.shade600 : Colors.grey.shade400,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
          elevation: magInvullen ? 2 : 0,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        onPressed: magInvullen ? () => _openUrenInvullenSheet(row) : null,
        child: Text(
          magInvullen ? 'Invullen' : 'Eerst afronden',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
      ),
    );

    return Container(
      margin: margin,
      decoration: _premiumShiftCardDecoration,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            bedrijfsnaam,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              letterSpacing: -0.3,
              color: Colors.white,
            ),
          ),
          if (datumLabel != null) ...[
            const SizedBox(height: 14),
            _registratieSliderInfoRow(
              icon: Icons.calendar_today_rounded,
              text: datumLabel,
            ),
          ],
          const SizedBox(height: 14),
          _registratieSliderInfoRow(
            icon: Icons.access_time_rounded,
            text: timeLine,
          ),
          const SizedBox(height: 10),
          _registratieSliderInfoRow(
            icon: Icons.location_on_rounded,
            text: adres,
            maxLines: 2,
          ),
          if (!magInvullen) ...[
            const SizedBox(height: 10),
            Text(
              'Rond deze opdracht eerst af op de rooster pagina om uren te kunnen invullen.',
              style: GoogleFonts.lato(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade100,
                height: 1.35,
              ),
            ),
          ],
          if (expandVertically) const Spacer() else const SizedBox(height: 14),
          const SizedBox(height: 12),
          invullenKnop,
        ],
      ),
    );
  }

  Widget _registratieSliderInfoRow({
    required IconData icon,
    required String text,
    int maxLines = 1,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.95)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.lato(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegistratieOpenShiftsCarousel(
    List<Map<String, dynamic>> openList,
  ) {
    return SizedBox(
      height: 252,
      child: PageView.builder(
        controller: _registratieSliderController,
        itemCount: openList.length,
        itemBuilder: (context, index) {
          return AnimatedBuilder(
            animation: _registratieSliderController,
            builder: (context, child) {
              double scale = 1.0;
              double opacity = 1.0;
              if (_registratieSliderController.position.haveDimensions) {
                final pageDelta =
                    _registratieSliderController.page! - index;
                scale = (1 - (pageDelta.abs() * 0.15)).clamp(0.85, 1.0);
                opacity = (1 - (pageDelta.abs() * 0.35)).clamp(0.55, 1.0);
              }
              return Center(
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(opacity: opacity, child: child),
                ),
              );
            },
            child: _registratieOpenShiftTile(
              context,
              openList[index],
              toonDatumInSubtitel: false,
              forSlider: true,
            ),
          );
        },
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
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
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonVisible: false,
                decoration: const BoxDecoration(color: Colors.transparent),
                titleTextStyle: GoogleFonts.lato(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  color: _deepNavy,
                ),
                leftChevronIcon: _regCalendarChevron(
                  icon: Icons.chevron_left_rounded,
                ),
                rightChevronIcon: _regCalendarChevron(
                  icon: Icons.chevron_right_rounded,
                ),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                markersMaxCount: 2,
                markerDecoration: const BoxDecoration(color: Colors.transparent),
                weekendTextStyle: GoogleFonts.lato(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
                defaultTextStyle: GoogleFonts.lato(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF334155),
                ),
                todayTextStyle: GoogleFonts.lato(
                  fontWeight: FontWeight.w900,
                  color: _brightBlue,
                ),
                selectedTextStyle: GoogleFonts.lato(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
                todayDecoration: BoxDecoration(
                  color: _brightBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _brightBlue.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                selectedDecoration: BoxDecoration(
                  color: _brightBlue,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _brightBlue.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
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
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade300,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.shade200
                                      .withValues(alpha: 0.8),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        if (hasOpen && hasGreen) const SizedBox(width: 4),
                        if (hasGreen)
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
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
                if (_registratieSliderController.hasClients) {
                  _registratieSliderController.jumpToPage(0);
                }
              },
              onPageChanged: (focusedDay) {
                setState(() => _regCalendarFocusedDay = focusedDay);
              },
              onFormatChanged: (format) {
                setState(() => _regCalendarFormat = format);
              },
            ),
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
                  _buildRegistratieOpenShiftsCarousel(openList),
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