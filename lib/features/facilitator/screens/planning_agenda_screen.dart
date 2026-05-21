import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../shared/agenda_personalia_helpers.dart';
import '../../shared/widgets/agenda_item_add_modal.dart';

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

  List<Map<String, dynamic>> _inboxUitnodigingen = [];

  String? _currentUserId;

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

  String _fmtAgendaDate(DateTime d) {
    try {
      return DateFormat('EEE d MMM', 'nl_NL').format(d);
    } catch (_) {
      return DateFormat('EEE d MMM').format(d);
    }
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
      final uid = Supabase.instance.client.auth.currentUser?.id ?? '';

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

      List<Map<String, dynamic>> persoonlijkRaw = const [];
      if (uid.isNotEmpty) {
        try {
          persoonlijkRaw =
              await AgendaPersonaliaHelpers.fetchAgendaItemsVoorGebruiker(uid);
        } catch (_) {
          persoonlijkRaw = const [];
        }
      }

      final inbox = uid.isEmpty
          ? const <Map<String, dynamic>>[]
          : AgendaPersonaliaHelpers.inboxUitgenodigd(persoonlijkRaw, uid);

      final teTonen = uid.isEmpty
          ? const <Map<String, dynamic>>[]
          : AgendaPersonaliaHelpers.filterVoorWeergave(persoonlijkRaw, uid);

      for (final row in teTonen) {
        final task = AgendaPersonaliaHelpers.normaliseerVoorControlRoom(row);
        final day = _normalizeDate(_parseDate(task['geplande_datum']));
        grouped.putIfAbsent(day, () => <dynamic>[]).add(task);
      }

      if (!mounted) return;
      setState(() {
        _groupedTasks = grouped;
        _inboxUitnodigingen = inbox;
        _currentUserId = uid.isEmpty ? null : uid;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groupedTasks = {};
        _inboxUitnodigingen = [];
        _loadError = e;
        _isLoading = false;
      });
    }
  }

  List<dynamic> _tasksForSelectedDay() {
    final key = _normalizeDate(_selectedDay ?? _focusedDay);
    return _groupedTasks[key] ?? const <dynamic>[];
  }

  String _fmtDateHuman(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd-$mm-${d.year}';
  }

  List<dynamic> _tasksForVisiblePeriod({
    required DateTime focusedDay,
    required CalendarFormat format,
    DateTime? excludeDay,
  }) {
    final excludeKey = excludeDay == null ? null : _normalizeDate(excludeDay);

    DateTime start;
    DateTime end;
    if (format == CalendarFormat.week) {
      // Monday-based week.
      final weekday = focusedDay.weekday; // Mon=1..Sun=7
      start = _normalizeDate(focusedDay.subtract(Duration(days: weekday - 1)));
      end = _normalizeDate(start.add(const Duration(days: 6)));
    } else {
      // Month view.
      start = DateTime(focusedDay.year, focusedDay.month, 1);
      end = DateTime(focusedDay.year, focusedDay.month + 1, 0);
    }

    final out = <dynamic>[];
    for (final entry in _groupedTasks.entries) {
      final day = entry.key;
      if (day.isBefore(start) || day.isAfter(end)) continue;
      if (excludeKey != null && isSameDay(day, excludeKey)) continue;
      out.addAll(entry.value);
    }
    return out;
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
      builder: (_) => SelectionArea(
        child: AgendaDetailModal(task: task),
      ),
    );
  }

  Future<void> _openPersoonlijkAlleenLezen(Map<String, dynamic> task) async {
    final titel = _text(task['project_naam']).isEmpty
        ? _text(task['titel'])
        : _text(task['project_naam']);
    final start = _formatTime(task['starttijd']);
    final end = _formatTime(task['eindtijd']);
    final datum = _parseDate(task['geplande_datum']);
    final datumStr = _fmtAgendaDate(datum);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: 16 + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                titel.isEmpty ? 'Agenda-item' : titel,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$datumStr · $start – $end',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                'Dit item is door een collega aangemaakt. Alleen-lezen.',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Sluiten',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _acceptUitnodiging(Map<String, dynamic> item) async {
    final uid = _currentUserId ?? Supabase.instance.client.auth.currentUser?.id;
    final itemId = _text(item['id']);
    if (uid == null || uid.isEmpty || itemId.isEmpty) return;
    try {
      await AgendaPersonaliaHelpers.updateDeelnemerStatus(
        itemId: itemId,
        gebruikerId: uid,
        status: 'geaccepteerd',
      );
      if (mounted) await _loadAgenda();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Accepteren mislukt: $e')),
        );
      }
    }
  }

  Future<void> _weigerUitnodiging(Map<String, dynamic> item) async {
    final uid = _currentUserId ?? Supabase.instance.client.auth.currentUser?.id;
    final itemId = _text(item['id']);
    if (uid == null || uid.isEmpty || itemId.isEmpty) return;
    try {
      await AgendaPersonaliaHelpers.updateDeelnemerStatus(
        itemId: itemId,
        gebruikerId: uid,
        status: 'afgewezen',
      );
      if (mounted) await _loadAgenda();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Weigeren mislukt: $e')),
        );
      }
    }
  }

  Widget _buildInboxBanner(ColorScheme cs, bool isDark) {
    if (_inboxUitnodigingen.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.orange.shade900.withValues(alpha: 0.35)
              : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.orange.shade300.withValues(alpha: 0.85),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nieuwe Uitnodigingen',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: isDark ? Colors.orange.shade100 : Colors.orange.shade900,
              ),
            ),
            const SizedBox(height: 10),
            ..._inboxUitnodigingen.map((item) {
              final titel = _text(item['titel']).isEmpty ? 'Agenda-item' : _text(item['titel']);
              final start = _formatTime(item['starttijd']);
              final end = _formatTime(item['eindtijd']);
              final d = _parseDate(item['datum'] ?? item['geplande_datum']);
              final dLabel = _fmtAgendaDate(d);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titel,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$dLabel · $start – $end',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: cs.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.green.shade100,
                          ),
                          onPressed: _isLoading ? null : () => _acceptUitnodiging(item),
                          icon: Icon(Icons.check_rounded, color: Colors.green.shade800),
                          tooltip: 'Accepteren',
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                          ),
                          onPressed: _isLoading ? null : () => _weigerUitnodiging(item),
                          icon: Icon(Icons.close_rounded, color: Colors.red.shade800),
                          tooltip: 'Weigeren',
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = isDark ? const Color(0xFF090A12) : const Color(0xFFF2F4F7);
    final selectedDay = _selectedDay ?? _focusedDay;
    final dayTasks = _tasksForSelectedDay();
    final periodTasks = _tasksForVisiblePeriod(
      focusedDay: _focusedDay,
      format: _calendarFormat,
      excludeDay: selectedDay,
    );

    return Scaffold(
      backgroundColor: bg,
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading
            ? null
            : () async {
                final ok = await AgendaItemAddModal.show(context);
                if (ok == true && mounted) await _loadAgenda();
              },
        child: const Icon(Icons.add),
      ),
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
      body: SelectionArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            _buildInboxBanner(cs, isDark),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131722) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.onSurface.withValues(alpha: 0.10),
                    width: 1.3,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1A2132)
                                : const Color(0xFFEAF0FA),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: CupertinoSlidingSegmentedControl<CalendarFormat>(
                            groupValue: _calendarFormat,
                            thumbColor: cs.primary,
                            backgroundColor: Colors.transparent,
                            children: {
                              CalendarFormat.month: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
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
                      firstDay:
                          DateTime.now().subtract(const Duration(days: 730)),
                      lastDay: DateTime.now().add(const Duration(days: 730)),
                      focusedDay: _focusedDay,
                      calendarFormat: _calendarFormat,
                      availableCalendarFormats: const {
                        CalendarFormat.month: 'Maand',
                        CalendarFormat.week: 'Week',
                      },
                      rowHeight: 90.0,
                      daysOfWeekHeight: 40.0,
                      selectedDayPredicate: (day) =>
                          isSameDay(_selectedDay, day),
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      eventLoader: (day) =>
                          _groupedTasks[_normalizeDate(day)] ?? const <dynamic>[],
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
                      headerStyle:
                          const HeaderStyle(formatButtonVisible: false),
                      calendarStyle: CalendarStyle(
                        outsideTextStyle: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.34),
                        ),
                        markerDecoration:
                            const BoxDecoration(color: Colors.transparent),
                        todayDecoration:
                            const BoxDecoration(color: Colors.transparent),
                        selectedDecoration:
                            const BoxDecoration(color: Colors.transparent),
                      ),
                      calendarBuilders: CalendarBuilders<dynamic>(
                        defaultBuilder: (context, date, focusedDay) {
                          return _buildCalendarDayCell(
                            date: date,
                            colorScheme: cs,
                          );
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
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
            Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131722) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.onSurface.withValues(alpha: 0.10),
                    width: 1.3,
                  ),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _loadError != null
                        ? Center(
                            child: Text(
                              'Agenda laden mislukt: $_loadError',
                              textAlign: TextAlign.center,
                              style:
                                  GoogleFonts.inter(fontWeight: FontWeight.w700),
                            ),
                          )
                        : Builder(
                            builder: (context) {
                              Widget taskTile(dynamic raw) {
                                final item = Map<String, dynamic>.from(raw as Map);
                                final agendaKleur = _text(item['agenda_kleur']);
                                final statusColor = _agendaColor(agendaKleur);
                                final start = _formatTime(item['starttijd']);
                                final end = _formatTime(item['eindtijd']);
                                final plannedDate = _parseDate(item['geplande_datum']);
                                final plannedDateLabel = _fmtAgendaDate(plannedDate);
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
                                  onTap: () {
                                    final pers =
                                        item['_persoonlijk_agenda'] == true;
                                    final maker = _text(item['maker_id']);
                                    final uid = _text(_currentUserId);
                                    if (pers && maker.isNotEmpty && maker != uid) {
                                      _openPersoonlijkAlleenLezen(item);
                                      return;
                                    }
                                    _openAgendaDetailModal(item);
                                  },
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
                                          color: Colors.black.withValues(
                                            alpha: isDark ? 0.26 : 0.06,
                                          ),
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
                                            const SizedBox(width: 10),
                                            Text(
                                              plannedDateLabel,
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12,
                                                color: cs.onSurface.withValues(alpha: 0.60),
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
                              }

                              Widget sectionTitle(String text) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    text,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                );
                              }

                              Widget emptyHint(String text) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    text,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface.withValues(alpha: 0.72),
                                    ),
                                  ),
                                );
                              }

                              final periodLabel =
                                  _calendarFormat == CalendarFormat.week ? 'week' : 'maand';

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      14,
                                      14,
                                      6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF0F172A)
                                          : Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: cs.onSurface.withValues(
                                          alpha: 0.08,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        sectionTitle(
                                          'Opdrachten voor ${_fmtDateHuman(selectedDay)}',
                                        ),
                                        if (dayTasks.isEmpty)
                                          emptyHint(
                                            'Geen definitieve planning op deze dag.',
                                          )
                                        else
                                          ListView.builder(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            itemCount: dayTasks.length,
                                            itemBuilder: (context, index) {
                                              return taskTile(dayTasks[index]);
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  sectionTitle(
                                    'Opdrachten voor deze $periodLabel',
                                  ),
                                  if (periodTasks.isEmpty)
                                    emptyHint(
                                      'Geen opdrachten in deze $periodLabel.',
                                    )
                                  else
                                    ListView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: periodTasks.length,
                                      itemBuilder: (context, index) {
                                        return taskTile(periodTasks[index]);
                                      },
                                    ),
                                ],
                              );
                            },
                          ),
              ),
            const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }
}

class AgendaDetailModal extends StatefulWidget {
  const AgendaDetailModal({required this.task, super.key});

  final Map<String, dynamic> task;

  @override
  State<AgendaDetailModal> createState() => _AgendaDetailModalState();
}

class _AgendaDetailModalState extends State<AgendaDetailModal> {
  String _text(dynamic value) => (value ?? '').toString().trim();

  String _timeLabel(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return '--:--';
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }

  DateTime? _parseDate(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  String _dateHuman(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  String? _originalDateHuman;
  String _originalStart = '--:--';
  String _originalEnd = '--:--';
  String _originalOperator = 'Onbekend';

  String? _geplandeDatumHuman;
  String _geplandeStart = '--:--';
  String _geplandeEind = '--:--';
  String _geplandeOperator = 'Onbekend';

  @override
  void initState() {
    super.initState();
    final t = widget.task;

    final d = _parseDate(t['geplande_datum']);

    _originalDateHuman = d == null ? null : _dateHuman(d);
    _originalStart = _timeLabel(t['starttijd']);
    _originalEnd = _timeLabel(t['eindtijd']);
    _originalOperator = _text(t['operator_namen']).isEmpty
        ? (_text(t['operator_naam']).isEmpty ? 'Onbekend' : _text(t['operator_naam']))
        : _text(t['operator_namen']);

    // Read-only planned values
    _geplandeDatumHuman = d == null ? null : _dateHuman(d);
    _geplandeStart = _timeLabel(t['starttijd']);
    _geplandeEind = _timeLabel(t['eindtijd']);
    _geplandeOperator = _originalOperator;
  }

  Widget _block(BuildContext context, String label, String value) {
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
    final project = _text(widget.task['project_naam']).isEmpty
        ? 'Onbekend project'
        : _text(widget.task['project_naam']);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
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
              const SizedBox(height: 10),

              // Oorspronkelijke data (read-only)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
                ),
                child: Text(
                  'Oorspronkelijke planning: ${_originalDateHuman ?? '—'} '
                  'van $_originalStart tot $_originalEnd - Operator: $_originalOperator',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: cs.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ),

              const SizedBox(height: 14),
              _block(context, 'Klant', _text(widget.task['bedrijfsnaam'])),
              const SizedBox(height: 8),
              _block(
                context,
                'Status',
                _text(widget.task['agenda_kleur']).isEmpty
                    ? (_text(widget.task['planning_status']).isEmpty
                        ? 'Onbekend'
                        : _text(widget.task['planning_status']))
                    : _text(widget.task['agenda_kleur']),
              ),

              const SizedBox(height: 16),
              _block(context, 'Geplande datum', _geplandeDatumHuman ?? '—'),
              const SizedBox(height: 8),
              _block(context, 'Tijd', '$_geplandeStart – $_geplandeEind'),
              const SizedBox(height: 8),
              _block(context, 'Operator', _geplandeOperator),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Sluiten',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
