import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';

class PlanningAgendaScreen extends StatefulWidget {
  const PlanningAgendaScreen({super.key});

  @override
  State<PlanningAgendaScreen> createState() => _PlanningAgendaScreenState();
}

class _PlanningAgendaScreenState extends State<PlanningAgendaScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, List<dynamic>> _groupedTasks = {};

  bool _isLoading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadAgenda();
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  DateTime _normalizeDate(DateTime date) => DateTime(date.year, date.month, date.day);

  DateTime _parseDate(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return DateTime.now();
    return DateTime.tryParse(raw) ?? DateTime.now();
  }

  String _formatTime(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return '--:--';
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }

  Color _agendaColor(String agendaKleur) {
    switch (agendaKleur.toLowerCase()) {
      case 'rood':
        return Colors.redAccent;
      case 'groen':
        return Colors.green;
      case 'blauw':
        return Colors.blue;
      case 'oranje':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Future<void> _loadAgenda() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final response = await AppSupabase.client
          .from('app_facilitator_agenda')
          .select()
          .order('geplande_datum', ascending: true);

      final grouped = <DateTime, List<dynamic>>{};
      for (final raw in (response as List)) {
        if (raw is! Map) continue;
        final task = Map<String, dynamic>.from(raw);
        final day = _normalizeDate(_parseDate(task['geplande_datum']));
        grouped.putIfAbsent(day, () => <dynamic>[]).add(task);
      }

      if (!mounted) return;
      setState(() {
        _groupedTasks = grouped;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groupedTasks = {};
        _loadError = e;
        _isLoading = false;
      });
    }
  }

  List<dynamic> _tasksForSelectedDay() {
    final key = _normalizeDate(_selectedDay ?? _focusedDay);
    return _groupedTasks[key] ?? const <dynamic>[];
  }

  Widget _buildCalendarDayCell({
    required DateTime date,
    required ColorScheme colorScheme,
    bool isSelected = false,
    bool isToday = false,
  }) {
    final hasCircle = isSelected || isToday;
    final circleColor = isSelected ? colorScheme.primary : colorScheme.secondary;
    final dayTextColor = hasCircle ? Colors.white : colorScheme.onSurface;

    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: hasCircle ? circleColor : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${date.day}',
                style: GoogleFonts.inter(
                  color: dayTextColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Future<void> _openAgendaDetailModal(Map<String, dynamic> task) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgendaDetailModal(task: task),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = isDark ? const Color(0xFF090A12) : const Color(0xFFF2F4F7);
    final dayTasks = _tasksForSelectedDay();

    return Scaffold(
      backgroundColor: bg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(
          'Agenda Control Room',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: _isLoading ? null : _loadAgenda,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131722) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.10), width: 1.3),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1A2132) : const Color(0xFFEAF0FA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CupertinoSlidingSegmentedControl<CalendarFormat>(
                          groupValue: _calendarFormat,
                          thumbColor: cs.primary,
                          backgroundColor: Colors.transparent,
                          children: {
                            CalendarFormat.month: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Text(
                                'Maand',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  color: _calendarFormat == CalendarFormat.month
                                      ? Colors.white
                                      : cs.onSurface.withValues(alpha: 0.82),
                                ),
                              ),
                            ),
                            CalendarFormat.week: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Text(
                                'Week',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  color: _calendarFormat == CalendarFormat.week
                                      ? Colors.white
                                      : cs.onSurface.withValues(alpha: 0.82),
                                ),
                              ),
                            ),
                          },
                          onValueChanged: (format) {
                            if (format == null) return;
                            setState(() => _calendarFormat = format);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TableCalendar<dynamic>(
                    locale: 'nl_NL',
                    firstDay: DateTime.now().subtract(const Duration(days: 730)),
                    lastDay: DateTime.now().add(const Duration(days: 730)),
                    focusedDay: _focusedDay,
                    calendarFormat: _calendarFormat,
                    availableCalendarFormats: const {
                      CalendarFormat.month: 'Maand',
                      CalendarFormat.week: 'Week',
                    },
                    rowHeight: 90.0,
                    daysOfWeekHeight: 40.0,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    eventLoader: (day) => _groupedTasks[_normalizeDate(day)] ?? const <dynamic>[],
                    onFormatChanged: (format) {
                      setState(() => _calendarFormat = format);
                    },
                    onPageChanged: (focusedDay) {
                      setState(() => _focusedDay = focusedDay);
                    },
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                    },
                    headerStyle: const HeaderStyle(formatButtonVisible: false),
                    calendarStyle: CalendarStyle(
                      outsideTextStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.34)),
                      markerDecoration: const BoxDecoration(color: Colors.transparent),
                      todayDecoration: const BoxDecoration(color: Colors.transparent),
                      selectedDecoration: const BoxDecoration(color: Colors.transparent),
                    ),
                    calendarBuilders: CalendarBuilders<dynamic>(
                      defaultBuilder: (context, date, focusedDay) {
                        return _buildCalendarDayCell(date: date, colorScheme: cs);
                      },
                      selectedBuilder: (context, date, focusedDay) {
                        return _buildCalendarDayCell(
                          date: date,
                          colorScheme: cs,
                          isSelected: true,
                        );
                      },
                      todayBuilder: (context, date, focusedDay) {
                        return _buildCalendarDayCell(
                          date: date,
                          colorScheme: cs,
                          isToday: true,
                        );
                      },
                      markerBuilder: (context, date, events) {
                        if (events.isEmpty) return const SizedBox.shrink();
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF101B35),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${events.length} taken',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131722) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.10), width: 1.3),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                      ? Center(
                          child: Text(
                            'Agenda laden mislukt: $_loadError',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                        )
                      : dayTasks.isEmpty
                          ? Center(
                              child: Text(
                                'Geen definitieve planning op deze dag.',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface.withValues(alpha: 0.72),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: dayTasks.length,
                              itemBuilder: (context, index) {
                                final item = Map<String, dynamic>.from(dayTasks[index] as Map);
                                final agendaKleur = _text(item['agenda_kleur']);
                                final statusColor = _agendaColor(agendaKleur);
                                final start = _formatTime(item['starttijd']);
                                final end = _formatTime(item['eindtijd']);
                                final project = _text(item['project_naam']).isEmpty
                                    ? 'Onbekend'
                                    : _text(item['project_naam']);
                                final company = _text(item['bedrijfsnaam']).isEmpty
                                    ? 'Onbekend'
                                    : _text(item['bedrijfsnaam']);
                                final operatorNames = _text(item['operator_namen']).isEmpty
                                    ? 'Onbekend'
                                    : _text(item['operator_namen']);
                                final region = _text(item['werk_regio']).isEmpty
                                    ? 'Onbekend'
                                    : _text(item['werk_regio']);
                                final plannedOperators = _text(item['geplande_operators_aantal']).isEmpty
                                    ? '0'
                                    : _text(item['geplande_operators_aantal']);
                                final neededOperators = _text(item['benodigde_operators']).isEmpty
                                    ? '1'
                                    : _text(item['benodigde_operators']);
                                final isRood = agendaKleur.toLowerCase() == 'rood';

                                return InkWell(
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                  onTap: () => _openAgendaDetailModal(item),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: cs.surface,
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(12),
                                        bottomRight: Radius.circular(12),
                                      ),
                                      border: Border(
                                        left: BorderSide(width: 6, color: statusColor),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.06),
                                          blurRadius: 14,
                                          spreadRadius: 0,
                                          offset: const Offset(0, 5),
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
                                                '$start - $end',
                                                style: GoogleFonts.inter(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w900,
                                                  color: cs.primary,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: cs.primary.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                region,
                                                style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 11.5,
                                                  color: cs.primary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          project,
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          company,
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w700,
                                            color: cs.onSurface.withValues(alpha: 0.66),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.person,
                                              size: 16,
                                              color: cs.onSurface.withValues(alpha: 0.76),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                operatorNames,
                                                style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '$plannedOperators/$neededOperators Operators',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w900,
                                                color: isRood ? Colors.redAccent : cs.onSurface,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

class AgendaDetailModal extends StatelessWidget {
  const AgendaDetailModal({required this.task, super.key});

  final Map<String, dynamic> task;

  String _text(dynamic value) => (value ?? '').toString().trim();

  String _time(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return '--:--';
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }

  Widget _block(
    BuildContext context,
    String label,
    String value,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2030) : const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(
            color: cs.onSurface,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(text: value.isEmpty ? '-' : value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final project = _text(task['project_naam']).isEmpty ? 'Onbekend project' : _text(task['project_naam']);

    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.60,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111827) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Dossier: $project',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _block(context, 'Tijd', '${_time(task['starttijd'])} - ${_time(task['eindtijd'])}'),
              const SizedBox(height: 8),
              _block(
                context,
                'Operator(s)',
                _text(task['operator_namen']).isEmpty
                    ? (_text(task['operator_naam']).isEmpty ? 'Onbekend' : _text(task['operator_naam']))
                    : _text(task['operator_namen']),
              ),
              const SizedBox(height: 8),
              _block(context, 'Klant', _text(task['bedrijfsnaam'])),
              const SizedBox(height: 8),
              _block(
                context,
                'Status',
                _text(task['agenda_kleur']).isEmpty
                    ? (_text(task['planning_status']).isEmpty ? 'Onbekend' : _text(task['planning_status']))
                    : _text(task['agenda_kleur']),
              ),
              const SizedBox(height: 8),
              _block(context, 'Datum', _text(task['geplande_datum'])),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  disabledBackgroundColor: cs.primary.withValues(alpha: 0.40),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  'Open Project (Binnenkort beschikbaar)',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
