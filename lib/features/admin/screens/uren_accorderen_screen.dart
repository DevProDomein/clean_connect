import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/models/user_role.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';

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
  int _openOpdrachtenCount = 0;

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

      final results = await Future.wait([
        client
            .from('opdracht_planning')
            .select(
              'id, operator_id, opdracht_id, geplande_datum, starttijd, eindtijd, '
              'toegewezen_uren, werkelijke_starttijd, werkelijke_eindtijd, '
              'gewerkte_uren_decimaal, uren_status, bedrijfsnaam, '
              'opdrachten!opdracht_planning_opdracht_id_fkey(bedrijfsnaam, projecten(project_naam))',
            )
            .inFilter('uren_status', const ['ingediend', 'geaccordeerd'])
            .gte('geplande_datum', fromStr)
            .lte('geplande_datum', toStr)
            .order('geplande_datum', ascending: false)
            .limit(800),
        client.from('opdrachten').select('id').eq('status', 'open'),
      ]);

      final list = (results[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final openList = results[1] as List;

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
              .select('id, voornaam, achternaam')
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
        _openOpdrachtenCount = openList.length;
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

  double _queueHoursTotal() {
    var u = 0.0;
    for (final r in _rows) {
      if (_urenStatusNorm(r) == 'ingediend') {
        u += _asDouble(r['gewerkte_uren_decimaal']);
      }
    }
    return u;
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

  List<Map<String, dynamic>> _rowsForSelectedDay() {
    final sel = _selectedDay ?? _focusedDay;
    final key = _dayOnly(sel);
    return _rows.where((r) {
      final st = _urenStatusNorm(r);
      if (st != 'ingediend' && st != 'geaccordeerd') return false;
      final d = _parseShiftDay(r['geplande_datum']);
      if (d == null || _dayOnly(d) != key) return false;
      final oid = _text(r['operator_id']);
      if (_filterOperatorId != null && oid != _filterOperatorId) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) {
      final sa = _safeTime(a['starttijd']);
      final sb = _safeTime(b['starttijd']);
      return sa.compareTo(sb);
    });
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
    final id = _text(row['id']);
    if (id.isEmpty) return;

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

    await showDialog<void>(
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

                await AppSupabase.client
                    .from('opdracht_planning')
                    .update(update)
                    .eq('id', id);

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
          onDone: () {
            if (mounted) Navigator.of(ctx).pop();
          },
          reload: _load,
          parentContext: context,
        );
      },
    );
  }

  Widget _analyticsRow() {
    final queueH = _queueHoursTotal();
    final urenTxt = _formatUrenNl(queueH);
    return Row(
      children: [
        Expanded(
          child: _kpiTile(
            label: 'Totaal uren in wachtrij',
            value: '$urenTxt u',
            icon: Icons.hourglass_top_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiTile(
            label: 'Openstaande opdrachten',
            value: '$_openOpdrachtenCount',
            icon: Icons.assignment_outlined,
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
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                  Text(
                    'Geselecteerde dag',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 12),
                  ..._buildDayList(),
                  const SizedBox(height: mobileNavBuffer),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildDayList() {
    final items = _rowsForSelectedDay();
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text(
              'Geen ingediende of geaccordeerde uren voor deze selectie.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ),
      ];
    }
    return items.map((row) {
      final st = _urenStatusNorm(row);
      final isRed = st == 'ingediend';
      final border = isRed ? const Color(0xFFE53935) : const Color(0xFF2E7D32);
      final label = isRed ? 'Ingediend — wacht op accordering' : 'Geaccordeerd';
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _onRowTap(row),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border, width: 2),
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
                          label,
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
    }).toList();
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
    final d = await showDatePicker(
      context: context,
      initialDate: _contractEnd ?? _contractStart ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) setState(() => _contractEnd = d);
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
      patch['contract_einddatum'] =
          _contractEnd?.toIso8601String().split('T').first;
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _pickEnd,
                          child: Text(
                            _contractEnd == null
                                ? 'Einddatum contract'
                                : DateFormat('dd-MM-yyyy').format(_contractEnd!),
                          ),
                        ),
                      ),
                    ],
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
    required this.deepNavy,
    required this.brightBlue,
    required this.onApprove,
    required this.onDone,
    required this.reload,
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
  final Color deepNavy;
  final Color brightBlue;
  final Future<void> Function({
    required TimeOfDay pickStart,
    required TimeOfDay pickEnd,
    required bool timesChangedFromOperatorSubmission,
    required String oldRangeLabel,
    required String newRangeLabel,
  })
  onApprove;
  final void Function() onDone;
  final Future<void> Function() reload;
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
      await widget.reload();
      if (!mounted) return;
      widget.onDone();
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
          content: Text('Fout bij opslaan: $e'),
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
            FilledButton(
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
