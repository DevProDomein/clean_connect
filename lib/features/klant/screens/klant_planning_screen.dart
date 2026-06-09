import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_client.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';

class KlantPlanningScreen extends StatefulWidget {
  const KlantPlanningScreen({super.key});

  @override
  State<KlantPlanningScreen> createState() => _KlantPlanningScreenState();
}

class _KlantPlanningScreenState extends State<KlantPlanningScreen> {
  static const Color _navy = Color(0xFF0D1B3E);

  final EventController<Map<String, dynamic>> _eventController =
      EventController<Map<String, dynamic>>();

  List<Map<String, dynamic>> _tasks = [];
  bool _isLoading = true;
  Object? _loadError;

  String _currentView = 'Maand';
  DateTime _focusedDay = DateTime.now();
  DateTime _currentWeekDate = DateTime.now();
  DateTime? _selectedDay;

  static const double _heightPerMinute = 1.1;
  static const double _weekTimeLineWidth = 56;

  final DateFormat _maandFmt = DateFormat('MMMM yyyy', 'nl_NL');

  @override
  void initState() {
    super.initState();
    _currentWeekDate = DateTime.now();
    _loadTasks();
  }

  @override
  void dispose() {
    _eventController.dispose();
    super.dispose();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _parseDate(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return DateTime.now();
    final head = raw.length >= 10 ? raw.substring(0, 10) : raw;
    return DateTime.tryParse(head) ?? DateTime.now();
  }

  String _formatTime(dynamic raw) {
    final t = _text(raw);
    if (t.isEmpty) return '--:--';
    return t.length >= 5 ? t.substring(0, 5) : t;
  }

  DateTime _eventDateTime(
    DateTime date,
    dynamic rawTime, {
    int defaultHour = 9,
    int defaultEndHour = 10,
  }) {
    final t = _formatTime(rawTime);
    if (t == '--:--') {
      return DateTime(date.year, date.month, date.day, defaultHour);
    }
    final parts = t.split(':');
    final hour = int.tryParse(parts.first) ?? defaultHour;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  String _taskTitle(Map<String, dynamic> task) {
    final project = task['projecten'];
    if (project is Map) {
      final naam = _text(project['project_naam']);
      if (naam.isNotEmpty) return naam;
    }
    final bedrijf = _text(task['bedrijfsnaam']);
    return bedrijf.isEmpty ? 'Schoonmaak' : bedrijf;
  }

  Color _statusColor(Map<String, dynamic> task) {
    switch (_text(task['status']).toLowerCase()) {
      case 'ingepland':
        return const Color(0xFF2563EB);
      case 'open':
        return const Color(0xFFEA580C);
      case 'afgerond':
      case 'voltooid':
        return Colors.grey.shade600;
      case 'geannuleerd':
        return Colors.grey.shade400;
      default:
        return Colors.blue.shade900;
    }
  }

  CalendarEventData<Map<String, dynamic>> _eventFromTask(
    Map<String, dynamic> task,
  ) {
    final date = _normalizeDate(_parseDate(task['geplande_datum']));
    final start = _eventDateTime(
      date,
      task['tijdslot_start'] ?? task['starttijd'],
      defaultHour: 9,
    );
    var end = _eventDateTime(
      date,
      task['tijdslot_eind'] ?? task['eindtijd'],
      defaultHour: 10,
      defaultEndHour: 11,
    );
    if (!end.isAfter(start)) {
      end = start.add(const Duration(hours: 1));
    }

    return CalendarEventData<Map<String, dynamic>>(
      date: date,
      startTime: start,
      endTime: end,
      title: _taskTitle(task),
      event: task,
      color: _statusColor(task),
    );
  }

  void _syncEventController() {
    _eventController.clear();
    for (final task in _tasks) {
      if (_text(task['geplande_datum']).isEmpty) continue;
      _eventController.add(_eventFromTask(task));
    }
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final data = await AppSupabase.client
          .from('opdrachten')
          .select('*, projecten(*)')
          .order('geplande_datum', ascending: true);

      if (!mounted) return;
      setState(() {
        _tasks = (data as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _isLoading = false;
      });
      _syncEventController();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _isLoading = false;
      });
    }
  }

  void _showAanvraagModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _KlantOpdrachtAanvraagSheet(
        onSubmitted: _loadTasks,
      ),
    );
  }

  HeaderStyle _headerStyle() {
    return HeaderStyle(
      decoration: BoxDecoration(color: Colors.blue.shade900),
      headerTextStyle: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
      headerPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      leftIconConfig: const IconDataConfig(color: Colors.white),
      rightIconConfig: const IconDataConfig(color: Colors.white),
    );
  }

  double _calendarHeight(BuildContext context) {
    if (_currentView == 'Dag') {
      return (MediaQuery.of(context).size.height * 0.65).clamp(520.0, 760.0);
    }
    if (_currentView == 'Week') {
      return (MediaQuery.of(context).size.height * 0.65).clamp(560.0, 780.0);
    }
    return (MediaQuery.of(context).size.height * 0.65).clamp(600.0, 820.0);
  }

  Widget _buildViewSwitcher() {
    const views = ['Maand', 'Week', 'Dag'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: views.map((view) {
          final selected = _currentView == view;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentView = view),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  view,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: selected ? _navy : Colors.blueGrey.shade600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _readOnlyEventTile(
    DateTime date,
    List<CalendarEventData<Map<String, dynamic>>> events,
    Rect boundary,
    DateTime startDuration,
    DateTime endDuration,
  ) {
    if (events.isEmpty) return const SizedBox.shrink();
    final event = events.first;
    return Container(
      margin: const EdgeInsets.only(right: 2, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: event.color,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.topLeft,
      child: Text(
        event.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildCalendarView() {
    final minDay = DateTime.now().subtract(const Duration(days: 730));
    final maxDay = DateTime.now().add(const Duration(days: 730));
    final activeDay = _selectedDay ?? _focusedDay;
    final headerStyle = _headerStyle();

    switch (_currentView) {
      case 'Week':
        return WeekView<Map<String, dynamic>>(
          controller: _eventController,
          minDay: minDay,
          maxDay: maxDay,
          initialDay: _currentWeekDate,
          startDay: WeekDays.monday,
          heightPerMinute: _heightPerMinute,
          timeLineWidth: _weekTimeLineWidth,
          showVerticalLines: false,
          headerStyle: headerStyle,
          weekTitleHeight: 64,
          headerStringBuilder: (date, {secondaryDate}) {
            final weekNum = _weekNumber(_currentWeekDate);
            return 'Week $weekNum · ${_maandFmt.format(_currentWeekDate)}';
          },
          hourIndicatorSettings: HourIndicatorSettings(
            color: Colors.grey.shade200,
          ),
          liveTimeIndicatorSettings: LiveTimeIndicatorSettings(
            color: Colors.blue.shade700,
          ),
          eventTileBuilder: _readOnlyEventTile,
          onPageChange: (date, page) {
            setState(() => _currentWeekDate = _normalizeDate(date));
          },
          onDateTap: (date) {
            setState(() {
              _selectedDay = _normalizeDate(date);
              _focusedDay = date;
            });
          },
          backgroundColor: Colors.white,
        );
      case 'Dag':
        return DayView<Map<String, dynamic>>(
          controller: _eventController,
          minDay: minDay,
          maxDay: maxDay,
          initialDay: activeDay,
          heightPerMinute: _heightPerMinute,
          timeLineWidth: _weekTimeLineWidth,
          headerStyle: headerStyle,
          hourIndicatorSettings: HourIndicatorSettings(
            color: Colors.grey.shade200,
          ),
          liveTimeIndicatorSettings: LiveTimeIndicatorSettings(
            color: Colors.blue.shade700,
          ),
          eventTileBuilder: _readOnlyEventTile,
          onPageChange: (date, page) {
            setState(() {
              _focusedDay = date;
              _selectedDay = _normalizeDate(date);
            });
          },
          backgroundColor: Colors.white,
        );
      default:
        return MonthView<Map<String, dynamic>>(
          controller: _eventController,
          monthViewStyle: MonthViewStyle(
            initialMonth: _focusedDay,
            minMonth: minDay,
            maxMonth: maxDay,
            startDay: WeekDays.monday,
            cellAspectRatio: 0.85,
            hideDaysNotInMonth: false,
            borderColor: Colors.grey.shade200,
            headerStyle: headerStyle,
          ),
          monthViewBuilders: MonthViewBuilders(
            headerStringBuilder: (date, {secondaryDate}) =>
                _maandFmt.format(date),
            weekDayStringBuilder: (dayIndex) {
              const labels = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
              return labels[dayIndex.clamp(0, labels.length - 1)];
            },
            onPageChange: (date, page) {
              setState(() => _focusedDay = date);
            },
            onCellTap: (events, date) {
              setState(() {
                _selectedDay = _normalizeDate(date);
                _focusedDay = date;
                _currentView = 'Dag';
              });
            },
            onEventTap: (event, date) {},
          ),
        );
    }
  }

  int _weekNumber(DateTime date) {
    final thursday = date.add(Duration(days: 4 - (date.weekday)));
    final yearStart = DateTime(thursday.year, 1, 1);
    return ((thursday.difference(yearStart).inDays) / 7).ceil();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.blue.shade900,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'Opdracht aanvragen',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        onPressed: _isLoading ? null : _showAanvraagModal,
      ),
      body: CalendarControllerProvider<Map<String, dynamic>>(
        controller: _eventController,
        child: RefreshIndicator(
          onRefresh: _loadTasks,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, mobileNavBuffer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildViewSwitcher(),
                const SizedBox(height: 14),
                if (_isLoading)
                  SizedBox(
                    height: _calendarHeight(context),
                    child: const Center(child: CircularProgressIndicator()),
                  )
                else if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Text(
                          'Planning laden mislukt',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text('$_loadError', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadTasks,
                          child: const Text('Opnieuw'),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox(
                        height: _calendarHeight(context),
                        child: _buildCalendarView(),
                      ),
                    ),
                  ),
                if (!_isLoading && _loadError == null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Alleen-lezen overzicht van uw geplande en aangevraagde opdrachten.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.blueGrey.shade600,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KlantOpdrachtAanvraagSheet extends StatefulWidget {
  const _KlantOpdrachtAanvraagSheet({required this.onSubmitted});

  final VoidCallback onSubmitted;

  @override
  State<_KlantOpdrachtAanvraagSheet> createState() =>
      _KlantOpdrachtAanvraagSheetState();
}

class _KlantOpdrachtAanvraagSheetState extends State<_KlantOpdrachtAanvraagSheet> {
  List<Map<String, dynamic>> _projecten = [];
  bool _loadingProjecten = true;
  bool _submitting = false;

  Map<String, dynamic>? _geselecteerdProject;
  DateTime? _datum;
  TimeOfDay? _startTijd;

  final DateFormat _datumFmt = DateFormat('dd-MM-yyyy', 'nl_NL');

  @override
  void initState() {
    super.initState();
    _loadProjecten();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.blueGrey.shade800,
        ),
      ),
    );
  }

  Future<void> _loadProjecten() async {
    try {
      final data = await AppSupabase.client
          .from('projecten')
          .select(
            'id, project_naam, uitvoer_adres_volledig, basis_uren_per_opdracht, facilitator_id, werk_regio',
          )
          .eq('status', 'actief')
          .order('project_naam');

      if (!mounted) return;
      setState(() {
        _projecten = (data as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loadingProjecten = false;
      });
    } catch (e) {
      debugPrint('Fout bij laden projecten: $e');
      if (mounted) setState(() => _loadingProjecten = false);
    }
  }

  String _projectLabel(Map<String, dynamic> project) {
    final naam = _text(project['project_naam']);
    return naam.isEmpty ? 'Project' : naam;
  }

  String _bedrijfsnaamVoorProject(Map<String, dynamic> project) {
    final direct = _text(project['bedrijfsnaam']);
    return direct.isEmpty ? 'Mijn Bedrijf' : direct;
  }

  String? _uitvoerAdresVoorProject(Map<String, dynamic> project) {
    final direct = _text(project['uitvoer_adres_volledig']);
    return direct.isEmpty ? null : direct;
  }

  Future<void> _pickDatum() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _datum ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('nl', 'NL'),
    );
    if (picked != null) setState(() => _datum = picked);
  }

  Future<void> _pickStartTijd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTijd ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _startTijd = picked);
  }

  Future<void> _submit() async {
    final project = _geselecteerdProject;
    final datum = _datum;
    final startTijd = _startTijd;

    if (project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecteer een project.')),
      );
      return;
    }
    if (datum == null || startTijd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kies een datum en starttijd.')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final basisUren =
          double.tryParse(project['basis_uren_per_opdracht'].toString()) ?? 1.0;
      final startDateTime = DateTime(
        datum.year,
        datum.month,
        datum.day,
        startTijd.hour,
        startTijd.minute,
      );
      final eindDateTime = startDateTime.add(
        Duration(minutes: (basisUren * 60).round()),
      );

      final startStr =
          '${startDateTime.hour.toString().padLeft(2, '0')}:${startDateTime.minute.toString().padLeft(2, '0')}:00';
      final eindStr =
          '${eindDateTime.hour.toString().padLeft(2, '0')}:${eindDateTime.minute.toString().padLeft(2, '0')}:00';
      final datumStr = datum.toIso8601String().split('T').first;

      final insertResponse = await AppSupabase.client.from('opdrachten').insert({
        'project_id': project['id'],
        'bedrijfsnaam': _bedrijfsnaamVoorProject(project),
        'uitvoer_adres_volledig': _uitvoerAdresVoorProject(project),
        'geplande_datum': datumStr,
        'tijdslot_start': startStr,
        'tijdslot_eind': eindStr,
        'benodigde_uren_totaal': basisUren,
        'status': 'open',
        'toegevoegd_door': AppSupabase.client.auth.currentUser!.id,
        'aangevraagd_op': DateTime.now().toUtc().toIso8601String(),
        'werk_regio': project['werk_regio'],
      }).select().single();

      final facilitatorId = project['facilitator_id'];
      if (facilitatorId != null && facilitatorId.toString().isNotEmpty) {
        await AppSupabase.client.from('notificaties').insert({
          'ontvanger_id': facilitatorId,
          'titel': 'Nieuwe klantaanvraag',
          'bericht':
              'Een klant heeft een nieuwe opdracht aangevraagd op $datumStr.',
          'type': 'nieuwe_aanvraag',
          'gerelateerd_id': insertResponse['id'],
        });
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aanvraag succesvol verstuurd!'),
          backgroundColor: Colors.green,
        ),
      );
      widget.onSubmitted();
    } catch (e) {
      debugPrint('Fout bij aanvragen: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Aanvragen mislukt: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.only(top: 48),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Opdracht aanvragen',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0D1B3E),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Kies een project, datum en starttijd. De eindtijd wordt automatisch berekend.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.blueGrey.shade600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            if (_loadingProjecten)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _fieldLabel('Project'),
              DropdownButtonFormField<Map<String, dynamic>>(
                key: ValueKey(_geselecteerdProject?['id']),
                initialValue: _geselecteerdProject,
                decoration: _fieldDecoration(hint: 'Selecteer project'),
                hint: Text(
                  'Selecteer project',
                  style: GoogleFonts.inter(color: Colors.blueGrey.shade500),
                ),
                isExpanded: true,
                items: _projecten
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                          _projectLabel(p),
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (val) => setState(() => _geselecteerdProject = val),
              ),
              const SizedBox(height: 16),
              Material(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(Icons.calendar_today_rounded,
                      color: Colors.blue.shade700),
                  title: Text(
                    'Datum',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _datum == null ? 'Kies een datum' : _datumFmt.format(_datum!),
                    style: GoogleFonts.inter(color: Colors.blueGrey.shade700),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _submitting ? null : _pickDatum,
                ),
              ),
              const SizedBox(height: 12),
              Material(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(Icons.schedule_rounded,
                      color: Colors.blue.shade700),
                  title: Text(
                    'Starttijd',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _startTijd == null
                        ? 'Kies een starttijd'
                        : _startTijd!.format(context),
                    style: GoogleFonts.inter(color: Colors.blueGrey.shade700),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _submitting ? null : _pickStartTijd,
                ),
              ),
              if (_geselecteerdProject != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Geschatte duur: ${double.tryParse(_geselecteerdProject!['basis_uren_per_opdracht'].toString()) ?? 1.0} uur',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue.shade900,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _submitting ? 'Bezig…' : 'Aanvragen',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
