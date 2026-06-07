import 'package:flutter/material.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart' hide WeekDays;

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
  static const _maandNamen = [
    'Januari',
    'Februari',
    'Maart',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Augustus',
    'September',
    'Oktober',
    'November',
    'December',
  ];

  final EventController<Map<String, dynamic>> _eventController =
      EventController<Map<String, dynamic>>();
  final CalendarController _calendarController = CalendarController();

  DateTime _focusedDay = DateTime.now();
  final GlobalKey _weekViewKey = GlobalKey();
  DateTime _currentWeekDate = DateTime.now();
  DateTime? _selectedDay;
  String _currentView = 'Maand';
  Map<DateTime, List<dynamic>> _groupedTasks = {};

  bool _isLoading = true;
  Object? _loadError;

  List<Map<String, dynamic>> _inboxUitnodigingen = [];

  String? _currentUserId;

  String _searchQuery = '';
  String? _filterKlant;
  String? _filterProject;
  String? _filterRegio;
  List<String> _filterOperators = [];
  bool _showFilters = false;

  static const double _heightPerMinute = 1.1;
  static const double _weekTimeLineWidth = 60.0;

  @override
  void initState() {
    super.initState();
    _calendarController.view = CalendarView.timelineDay;
    _currentWeekDate = _selectedDay ?? DateTime.now();
    _loadAgenda();
  }

  @override
  void dispose() {
    _calendarController.dispose();
    _eventController.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int _getWeekNumber(DateTime date) {
    final firstJan = DateTime(date.year, 1, 1);
    final dayOfYear = date.difference(firstJan).inDays;
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }

  void _postFrameSetState(VoidCallback update) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(update);
    });
  }

  void _onCalendarPageChange(DateTime date, int pageIndex) {
    _postFrameSetState(() {
      _focusedDay = date;
    });
  }

  void _onWeekPageChange(DateTime date, int pageIndex) {
    _currentWeekDate = date;
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

  String _opdrachtIdFromTask(Map<String, dynamic> task) {
    final candidate = _text(task['opdracht_id']).isNotEmpty
        ? _text(task['opdracht_id'])
        : _text(task['id']);
    return candidate;
  }

  bool _isVerplaatsbaarTask(Map<String, dynamic> task) {
    if (task['_persoonlijk_agenda'] == true) return false;
    return _opdrachtIdFromTask(task).isNotEmpty;
  }

  TimeOfDay _parseTimeOfDay(
    dynamic value, {
    int defaultHour = 9,
    int defaultMinute = 0,
  }) {
    final t = _formatTime(value);
    if (t == '--:--') {
      return TimeOfDay(hour: defaultHour, minute: defaultMinute);
    }
    final parts = t.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? defaultHour,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : defaultMinute,
    );
  }

  DateTime _roundTo5Mins(DateTime time) {
    final roundedMinutes = (time.minute / 5).round() * 5;
    return DateTime(time.year, time.month, time.day, time.hour, roundedMinutes);
  }

  String? _operatorIdFromResource(CalendarResource? resource) {
    final id = resource?.id.toString();
    if (id == null || id.isEmpty || id == 'ongepland' || id.startsWith('naam_')) {
      return null;
    }
    return id;
  }

  Future<void> _handleSyncfusionAppointmentChange(
    Appointment appointment,
    DateTime start,
    DateTime end,
    CalendarResource? resource,
  ) async {
    final task = _taskForAppointment(appointment);
    if (task == null || !_isVerplaatsbaarTask(task)) return;

    final snappedStart = _roundTo5Mins(start);
    var snappedEnd = _roundTo5Mins(end);
    if (!snappedEnd.isAfter(snappedStart)) {
      snappedEnd = snappedStart.add(const Duration(minutes: 5));
    }

    await _verplaatsOpdrachtVeilig(
      appointment.id.toString(),
      _normalizeDate(snappedStart),
      TimeOfDay(hour: snappedStart.hour, minute: snappedStart.minute),
      TimeOfDay(hour: snappedEnd.hour, minute: snappedEnd.minute),
      nieuweOperatorId: _operatorIdFromResource(resource),
    );
    if (mounted) await _loadAgenda();
  }

  Map<String, dynamic>? _taskForAppointment(Appointment appointment) {
    final opdrachtId = appointment.id.toString();
    final day = _normalizeDate(_selectedDay ?? _focusedDay);
    for (final taak in _allLoadedTasksForDay(day)) {
      if (_opdrachtIdFromTask(taak) == opdrachtId) return taak;
    }
    return null;
  }

  OpdrachtDataSource _getCalendarDataSource(DateTime date) {
    final appointments = <Appointment>[];
    final resourceMap = <String, CalendarResource>{};
    final day = _normalizeDate(date);

    resourceMap['ongepland'] = CalendarResource(
      id: 'ongepland',
      displayName: 'Ongepland',
      color: Colors.grey.shade400,
    );

    for (final taak in _allLoadedTasksForDay(day)) {
      final taskDate = _normalizeDate(_parseDate(taak['geplande_datum']));
      if (!_isSameDay(taskDate, day)) continue;

      var resourceId = 'ongepland';
      var resourceName = 'Ongepland';
      final planningen = taak['opdracht_planning'];

      if (planningen is List && planningen.isNotEmpty) {
        final raw = planningen.first;
        if (raw is Map) {
          final planning = Map<String, dynamic>.from(raw);
          final operatorId = _text(planning['operator_id']);
          final naam = _operatorNaamUitPlanning(planning);
          if (operatorId.isNotEmpty) {
            resourceId = operatorId;
            resourceName = naam.isEmpty ? 'Operator' : naam;
          } else if (naam.isNotEmpty) {
            resourceId = 'naam_$naam';
            resourceName = naam;
          }
        }
      } else {
        final enkel = _text(taak['operator_naam']);
        if (enkel.isNotEmpty) {
          resourceId = 'naam_$enkel';
          resourceName = enkel;
        } else {
          final namen = _text(taak['operator_namen']);
          if (namen.isNotEmpty) {
            final first = namen.split(',').first.trim();
            if (first.isNotEmpty) {
              resourceId = 'naam_$first';
              resourceName = first;
            }
          }
        }
      }

      resourceMap.putIfAbsent(
        resourceId,
        () => CalendarResource(
          id: resourceId,
          displayName: resourceName,
          color: Colors.blue.shade900,
        ),
      );

      final start = _safeParseTime(
        day,
        taak['tijdslot_start'] ?? taak['starttijd'],
        8,
      );
      var end = _safeParseTime(
        day,
        taak['tijdslot_eind'] ?? taak['eindtijd'],
        9,
      );
      if (!end.isAfter(start)) {
        end = start.add(const Duration(hours: 1));
      }

      final project = _text(taak['project_naam']);
      final company = _text(taak['bedrijfsnaam']);
      final title = project.isNotEmpty
          ? project
          : (company.isNotEmpty ? company : 'Opdracht');

      appointments.add(
        Appointment(
          id: _opdrachtIdFromTask(taak),
          startTime: start,
          endTime: end,
          subject: title,
          color: _bepaalStatusKleur(taak),
          resourceIds: [resourceId],
          notes: _text(taak['werk_regio']),
        ),
      );
    }

    if (!appointments.any((a) => a.resourceIds?.contains('ongepland') == true)) {
      resourceMap.remove('ongepland');
    }

    if (resourceMap.isEmpty) {
      resourceMap['algemeen'] = CalendarResource(
        id: 'algemeen',
        displayName: 'Algemene Planning',
        color: Colors.blue.shade900,
      );
    }

    return OpdrachtDataSource(appointments, resourceMap.values.toList());
  }

  Widget _buildWeekEventTile(
    DateTime date,
    List<CalendarEventData<Map<String, dynamic>>> events,
    Rect boundary,
    DateTime startDuration,
    DateTime endDuration,
  ) {
    if (events.isEmpty) return const SizedBox.shrink();
    final event = events.first;
    final startStr =
        '${event.startTime!.hour.toString().padLeft(2, '0')}:${event.startTime!.minute.toString().padLeft(2, '0')}';
    final eindStr =
        '${event.endTime!.hour.toString().padLeft(2, '0')}:${event.endTime!.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: event.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: event.color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: Colors.blue.shade900,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
          Text(
            '$startStr - $eindStr',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: Colors.blue.shade900,
              fontWeight: FontWeight.w500,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  void _shiftMatrixDay(int dayDelta) {
    final base = _normalizeDate(_selectedDay ?? _focusedDay);
    final next = _normalizeDate(base.add(Duration(days: dayDelta)));
    _calendarController.displayDate = next;
    setState(() {
      _selectedDay = next;
      _focusedDay = next;
      _currentWeekDate = next;
    });
  }

  Widget _buildPremiumAppointmentTile(
    BuildContext context,
    CalendarAppointmentDetails calendarAppointmentDetails,
  ) {
    if (calendarAppointmentDetails.appointments.isEmpty) {
      return const SizedBox.shrink();
    }

    final app = calendarAppointmentDetails.appointments.first as Appointment;
    final isTimeline = _calendarController.view == CalendarView.timelineDay;
    final isMonth = _calendarController.view == CalendarView.month;

    final startStr =
        '${app.startTime.hour.toString().padLeft(2, '0')}:${app.startTime.minute.toString().padLeft(2, '0')}';
    final eindStr =
        '${app.endTime.hour.toString().padLeft(2, '0')}:${app.endTime.minute.toString().padLeft(2, '0')}';

    if (isMonth || !isTimeline) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: app.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border(left: BorderSide(color: app.color, width: 3)),
        ),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                app.subject,
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (!isMonth)
                Text(
                  '$startStr - $eindStr',
                  style: TextStyle(
                    color: Colors.blue.shade900,
                    fontSize: 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: calendarAppointmentDetails.bounds.width,
      height: calendarAppointmentDetails.bounds.height,
      margin: const EdgeInsets.only(right: 2, top: 2, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: app.color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            app.subject,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '$startStr - $eindStr',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (app.notes != null && app.notes!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.location_on,
                  color: Colors.white70,
                  size: 10,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    app.notes!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSyncfusionDayView(DateTime date, ColorScheme cs, bool isDark) {
    final day = _normalizeDate(date);
    _calendarController.view = CalendarView.timelineDay;
    _calendarController.displayDate = day;

    return Column(
      children: [
        Container(
          height: 60,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(
              bottom: BorderSide(color: Colors.blue.shade900, width: 3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => _shiftMatrixDay(-1),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.chevron_left,
                    color: Colors.blue.shade900,
                    size: 24,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _getDutchDateString(day),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.blue.shade900,
                    height: 1.2,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _shiftMatrixDay(1),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.chevron_right,
                    color: Colors.blue.shade900,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SelectionContainer.disabled(
            child: SfCalendarTheme(
              data: SfCalendarThemeData(
                todayHighlightColor: Colors.orange.shade700,
                cellBorderColor: Colors.grey.shade200,
              ),
              child: SfCalendar(
                key: ValueKey('sf_day_${day.year}_${day.month}_${day.day}'),
                controller: _calendarController,
                view: CalendarView.timelineDay,
                dataSource: _getCalendarDataSource(day),
                showNavigationArrow: false,
                showDatePickerButton: false,
                headerHeight: 0,
                viewHeaderHeight: 0,
                firstDayOfWeek: 1,
                allowedViews: const [
                  CalendarView.month,
                  CalendarView.week,
                  CalendarView.timelineDay,
                ],
                timeSlotViewSettings: const TimeSlotViewSettings(
                  timeFormat: 'HH:mm',
                  timeIntervalHeight: 80,
                  timelineAppointmentHeight: 80,
                ),
              resourceViewSettings: const ResourceViewSettings(
                visibleResourceCount: 4,
                showAvatar: false,
                width: 110,
                height: 80,
              ),
              resourceViewHeaderBuilder: (context, details) {
                return Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade800,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    details.resource.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
              monthViewSettings: const MonthViewSettings(
                appointmentDisplayMode: MonthAppointmentDisplayMode.appointment,
                appointmentDisplayCount: 3,
                showAgenda: true,
              ),
              allowDragAndDrop: true,
              allowAppointmentResize: true,
              dragAndDropSettings: const DragAndDropSettings(
                showTimeIndicator: false,
              ),
              appointmentBuilder: _buildPremiumAppointmentTile,
              onDragEnd: (AppointmentDragEndDetails details) async {
                final appointment = details.appointment as Appointment?;
                final rawNieuweStart = details.droppingTime;
                if (appointment == null || rawNieuweStart == null) return;

                final nieuweStart = _roundTo5Mins(rawNieuweStart);
                final duur =
                    appointment.endTime.difference(appointment.startTime);
                final nieuweEind = nieuweStart.add(duur);
                await _handleSyncfusionAppointmentChange(
                  appointment,
                  nieuweStart,
                  nieuweEind,
                  details.targetResource,
                );
              },
              onAppointmentResizeEnd:
                  (AppointmentResizeEndDetails details) async {
                final appointment = details.appointment as Appointment?;
                if (appointment == null) return;
                await _handleSyncfusionAppointmentChange(
                  appointment,
                  appointment.startTime,
                  appointment.endTime,
                  null,
                );
              },
              onTap: (CalendarTapDetails details) {
                if (details.appointments == null ||
                    details.appointments!.isEmpty) {
                  return;
                }
                final clickedApp = details.appointments!.first as Appointment;
                final task = _taskForAppointment(clickedApp);
                if (task != null) _openAgendaDetailModal(task);
              },
            ),
          ),
        ),
        ),
      ],
    );
  }

  Future<bool> _verplaatsOpdrachtVeilig(
    String opdrachtId,
    DateTime nieuweDatum,
    TimeOfDay nieuweStart,
    TimeOfDay nieuweEind, {
    String? nieuweOperatorId,
  }) async {
    try {
      final startStr =
          '${nieuweStart.hour.toString().padLeft(2, '0')}:${nieuweStart.minute.toString().padLeft(2, '0')}:00';
      final eindStr =
          '${nieuweEind.hour.toString().padLeft(2, '0')}:${nieuweEind.minute.toString().padLeft(2, '0')}:00';
      final datumStr = nieuweDatum.toIso8601String().split('T')[0];

      final result = await AppSupabase.client.rpc('check_operator_overlap', params: {
        'p_opdracht_id': opdrachtId,
        'p_nieuwe_datum': datumStr,
        'p_nieuwe_starttijd': startStr,
        'p_nieuwe_eindtijd': eindStr,
      });

      if (!(result[0]['is_beschikbaar'] as bool)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result[0]['conflict_bericht'].toString()),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      await AppSupabase.client.from('opdrachten').update({
        'geplande_datum': datumStr,
        'tijdslot_start': startStr,
        'tijdslot_eind': eindStr,
      }).eq('id', opdrachtId);
      await AppSupabase.client.from('opdracht_planning').update({
        'geplande_datum': datumStr,
        'starttijd': startStr,
        'eindtijd': eindStr,
        if (nieuweOperatorId != null &&
            nieuweOperatorId.isNotEmpty &&
            nieuweOperatorId != 'ongepland' &&
            !nieuweOperatorId.startsWith('naam_'))
          'operator_id': nieuweOperatorId,
      }).eq('opdracht_id', opdrachtId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opdracht verplaatst!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  Future<void> _onMonthEventDrop(
    Map<String, dynamic> task,
    DateTime targetDate,
  ) async {
    if (!_isVerplaatsbaarTask(task)) return;

    final opdrachtId = _opdrachtIdFromTask(task);
    if (opdrachtId.isEmpty) return;

    final normalizedTarget = _normalizeDate(targetDate);
    final currentDate = _normalizeDate(_parseDate(task['geplande_datum']));
    if (_isSameDay(normalizedTarget, currentDate)) return;

    final start = _parseTimeOfDay(task['starttijd'], defaultHour: 9);
    final end = _parseTimeOfDay(task['eindtijd'], defaultHour: 10);

    final ok = await _verplaatsOpdrachtVeilig(
      opdrachtId,
      normalizedTarget,
      start,
      end,
    );

    if (!mounted) return;
    if (ok) {
      await _loadAgenda();
    } else {
      _syncEventController();
      setState(() {});
    }
  }

  DateTime _eventDateTime(DateTime date, dynamic rawTime, {int defaultHour = 9}) {
    final t = _formatTime(rawTime);
    if (t == '--:--') {
      return DateTime(date.year, date.month, date.day, defaultHour);
    }
    final parts = t.split(':');
    final hour = int.tryParse(parts.first) ?? defaultHour;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  DateTime _safeParseTime(DateTime baseDate, dynamic timeStr, int fallbackHour) {
    if (timeStr == null || timeStr.toString().isEmpty) {
      return DateTime(baseDate.year, baseDate.month, baseDate.day, fallbackHour, 0);
    }
    try {
      final parts = timeStr.toString().split(':');
      return DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
    } catch (_) {
      return DateTime(baseDate.year, baseDate.month, baseDate.day, fallbackHour, 0);
    }
  }

  List<Map<String, dynamic>> _allLoadedTasksForDay(DateTime date) {
    final key = _normalizeDate(date);
    return _filterTaskList(_groupedTasks[key] ?? const <dynamic>[])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
  }

  String _getDutchDateString(DateTime date) {
    const weekDays = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
    const monthNames = [
      'Jan', 'Feb', 'Mrt', 'Apr', 'Mei', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dec',
    ];
    return '${weekDays[date.weekday - 1]}\n${date.day} ${monthNames[date.month - 1]}';
  }

  Color _bepaalStatusKleur(Map<String, dynamic> task) {
    final agendaKleur = _text(task['agenda_kleur']).toLowerCase();
    switch (agendaKleur) {
      case 'rood':
        return const Color(0xFFDC2626);
      case 'groen':
        return const Color(0xFF16A34A);
      case 'oranje':
      case 'geel':
        return const Color(0xFFEA580C);
      case 'blauw':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF0052CC);
    }
  }

  CalendarEventData<Map<String, dynamic>> _calendarEventFromTask(
    Map<String, dynamic> task,
  ) {
    final date = _normalizeDate(_parseDate(task['geplande_datum']));
    final start = _eventDateTime(date, task['starttijd'], defaultHour: 9);
    final end = _eventDateTime(date, task['eindtijd'], defaultHour: 10);
    final project = _text(task['project_naam']);
    final company = _text(task['bedrijfsnaam']);
    final title = project.isNotEmpty
        ? project
        : (company.isNotEmpty ? company : 'Opdracht');

    return CalendarEventData<Map<String, dynamic>>(
      date: date,
      startTime: start,
      endTime: end.isAfter(start) ? end : start.add(const Duration(hours: 1)),
      title: title,
      event: task,
      color: _bepaalStatusKleur(task),
    );
  }

  void _syncEventController() {
    _eventController.clear();
    for (final list in _filteredGroupedTasks().values) {
      for (final raw in list) {
        if (raw is! Map) continue;
        _eventController.add(
          _calendarEventFromTask(Map<String, dynamic>.from(raw)),
        );
      }
    }
  }

  void _onMonthCellTap(DateTime date) {
    setState(() {
      _selectedDay = _normalizeDate(date);
      _focusedDay = date;
      _currentWeekDate = _normalizeDate(date);
      _currentView = 'Dag';
    });
  }

  void _onCalendarDateTap(DateTime date) {
    setState(() {
      _selectedDay = _normalizeDate(date);
      _focusedDay = date;
      _currentWeekDate = _normalizeDate(date);
    });
  }

  void _onCalendarEventTap(
    CalendarEventData<Map<String, dynamic>> event,
    DateTime date,
  ) {
    final raw = event.event;
    if (raw == null) return;
    _onAgendaTaskTap(Map<String, dynamic>.from(raw as Map));
  }

  void _onCalendarEventsCellTap(
    List<CalendarEventData<Map<String, dynamic>>> events,
    DateTime date,
  ) {
    if (events.isEmpty) return;
    _onCalendarEventTap(events.first, date);
  }

  HeaderStyle _calendarHeaderStyle(bool isDark) {
    return HeaderStyle(
      decoration: BoxDecoration(color: Colors.blue.shade900),
      headerTextStyle: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      headerPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      leftIconConfig: const IconDataConfig(color: Colors.white),
      rightIconConfig: const IconDataConfig(color: Colors.white),
    );
  }

  double _calendarViewportHeight(BuildContext context) {
    if (_currentView == 'Dag') {
      return (MediaQuery.of(context).size.height * 0.85).clamp(640.0, 920.0);
    }
    return (MediaQuery.of(context).size.height * 0.75).clamp(520.0, 720.0);
  }

  Future<void> _showPremiumFilterModal({
    required BuildContext context,
    required String title,
    required List<String> items,
    required String? selectedItem,
    required void Function(String?) onItemSelected,
  }) async {
    var searchQuery = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final modalDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final sheetBg = modalDark ? const Color(0xFF111019) : Colors.white;
        final titleColor =
            modalDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);

        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final filteredItems = items
                .where(
                  (item) => item.toLowerCase().contains(
                    searchQuery.toLowerCase(),
                  ),
                )
                .toList(growable: false);

            return Container(
              height: MediaQuery.of(modalContext).size.height * 0.75,
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: titleColor,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            onItemSelected(null);
                            Navigator.pop(modalContext);
                          },
                          child: Text(
                            'Wissen',
                            style: GoogleFonts.inter(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: TextField(
                      onChanged: (value) =>
                          setModalState(() => searchQuery = value),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Zoeken...',
                        hintStyle: GoogleFonts.inter(
                          color: Colors.grey.shade500,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.grey,
                        ),
                        filled: true,
                        fillColor: modalDark
                            ? const Color(0xFF1B1B23)
                            : Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filteredItems.isEmpty
                        ? Center(
                            child: Text(
                              'Geen resultaten gevonden',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = filteredItems[index];
                              final isSelected = item == selectedItem;
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 4,
                                ),
                                title: Text(
                                  item,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.blue.shade700
                                        : (modalDark
                                              ? Colors.white70
                                              : Colors.black87),
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(
                                        Icons.check_circle,
                                        color: Colors.blue.shade700,
                                      )
                                    : null,
                                onTap: () {
                                  onItemSelected(item);
                                  Navigator.pop(modalContext);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showPremiumMultiFilterModal({
    required String title,
    required List<String> items,
    required List<String> selectedItems,
    required void Function(List<String>) onItemsChanged,
  }) async {
    var searchQuery = '';
    final working = List<String>.from(selectedItems);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final modalDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final sheetBg = modalDark ? const Color(0xFF111019) : Colors.white;
        final titleColor =
            modalDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);

        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final filteredItems = items
                .where(
                  (item) => item.toLowerCase().contains(
                    searchQuery.toLowerCase(),
                  ),
                )
                .toList(growable: false);

            return Container(
              height: MediaQuery.of(modalContext).size.height * 0.75,
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: titleColor,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            working.clear();
                            onItemsChanged(const []);
                            setModalState(() {});
                          },
                          child: Text(
                            'Wissen',
                            style: GoogleFonts.inter(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Sluiten',
                          onPressed: () => Navigator.pop(modalContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: TextField(
                      onChanged: (value) =>
                          setModalState(() => searchQuery = value),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Zoeken...',
                        hintStyle: GoogleFonts.inter(
                          color: Colors.grey.shade500,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.grey,
                        ),
                        filled: true,
                        fillColor: modalDark
                            ? const Color(0xFF1B1B23)
                            : Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filteredItems.isEmpty
                        ? Center(
                            child: Text(
                              'Geen resultaten gevonden',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = filteredItems[index];
                              final isSelected = working.contains(item);
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 4,
                                ),
                                title: Text(
                                  item,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.blue.shade700
                                        : (modalDark
                                              ? Colors.white70
                                              : Colors.black87),
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(
                                        Icons.check_circle,
                                        color: Colors.blue.shade700,
                                      )
                                    : null,
                                onTap: () {
                                  setModalState(() {
                                    if (working.contains(item)) {
                                      working.remove(item);
                                    } else {
                                      working.add(item);
                                    }
                                  });
                                  onItemsChanged(List<String>.from(working));
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
      _syncEventController();
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

  bool _matchesAgendaFilters(dynamic raw) {
    if (raw is! Map) return false;
    final task = Map<String, dynamic>.from(raw);
    final klant = _text(task['bedrijfsnaam']);
    final project = _text(task['project_naam']);
    final regio = _text(task['werk_regio']);

    if (_filterKlant != null &&
        _filterKlant!.isNotEmpty &&
        klant != _filterKlant) {
      return false;
    }
    if (_filterProject != null &&
        _filterProject!.isNotEmpty &&
        project != _filterProject) {
      return false;
    }
    if (_filterRegio != null &&
        _filterRegio!.isNotEmpty &&
        regio != _filterRegio) {
      return false;
    }
    if (_filterOperators.isNotEmpty) {
      if (!_taskMatchesAnyOperator(task, _filterOperators)) {
        return false;
      }
    }
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      if (!klant.toLowerCase().contains(q) &&
          !project.toLowerCase().contains(q)) {
        return false;
      }
    }
    return true;
  }

  List<dynamic> _filterTaskList(List<dynamic> tasks) {
    return tasks.where(_matchesAgendaFilters).toList(growable: false);
  }

  Map<DateTime, List<dynamic>> _filteredGroupedTasks() {
    final out = <DateTime, List<dynamic>>{};
    for (final entry in _groupedTasks.entries) {
      final filtered = _filterTaskList(entry.value);
      if (filtered.isNotEmpty) out[entry.key] = filtered;
    }
    return out;
  }

  String _operatorNaamUitPlanning(Map<String, dynamic> planning) {
    final user = planning['gebruikers'];
    Map<String, dynamic>? userMap;
    if (user is Map) {
      userMap = Map<String, dynamic>.from(user);
    } else if (user is List && user.isNotEmpty && user.first is Map) {
      userMap = Map<String, dynamic>.from(user.first as Map);
    }
    if (userMap == null) return '';
    return '${_text(userMap['voornaam'])} ${_text(userMap['achternaam'])}'.trim();
  }

  bool _taskHasOperator(Map<String, dynamic> task, String operator) {
    final planningen = task['opdracht_planning'];
    if (planningen is List) {
      for (final raw in planningen) {
        if (raw is! Map) continue;
        final naam = _operatorNaamUitPlanning(Map<String, dynamic>.from(raw));
        if (naam == operator) return true;
      }
    }

    final namen = _text(task['operator_namen']);
    if (namen.isNotEmpty) {
      for (final part in namen.split(',')) {
        if (part.trim() == operator) return true;
      }
    }

    final enkel = _text(task['operator_naam']);
    return enkel == operator;
  }

  bool _taskMatchesAnyOperator(
    Map<String, dynamic> task,
    List<String> operators,
  ) {
    for (final operator in operators) {
      if (_taskHasOperator(task, operator)) return true;
    }
    return false;
  }

  String _operatorFilterLabel() {
    if (_filterOperators.isEmpty) return 'Alle';
    if (_filterOperators.length == 1) return _filterOperators.first;
    return '${_filterOperators.length} geselecteerd';
  }

  List<String> _agendaOperatorOptions() {
    final set = <String>{};
    for (final list in _groupedTasks.values) {
      for (final item in list) {
        if (item is! Map) continue;
        final task = Map<String, dynamic>.from(item);

        final namen = _text(task['operator_namen']);
        if (namen.isNotEmpty) {
          for (final part in namen.split(',')) {
            final n = part.trim();
            if (n.isNotEmpty) set.add(n);
          }
        }

        final enkel = _text(task['operator_naam']);
        if (enkel.isNotEmpty) set.add(enkel);

        final planningen = task['opdracht_planning'];
        if (planningen is List) {
          for (final raw in planningen) {
            if (raw is! Map) continue;
            final naam = _operatorNaamUitPlanning(Map<String, dynamic>.from(raw));
            if (naam.isNotEmpty) set.add(naam);
          }
        }
      }
    }
    return set.toList()..sort();
  }

  List<String> _agendaFilterOptions(String field) {
    final set = <String>{};
    for (final list in _groupedTasks.values) {
      for (final item in list) {
        if (item is! Map) continue;
        final task = Map<String, dynamic>.from(item);
        final value = field == 'bedrijfsnaam'
            ? _text(task['bedrijfsnaam'])
            : field == 'project_naam'
            ? _text(task['project_naam'])
            : _text(task['werk_regio']);
        if (value.isNotEmpty) set.add(value);
      }
    }
    return set.toList()..sort();
  }

  List<dynamic> _tasksForSelectedDay() {
    if (_selectedDay == null) return const <dynamic>[];
    final key = _normalizeDate(_selectedDay!);
    return _filterTaskList(_groupedTasks[key] ?? const <dynamic>[]);
  }

  List<dynamic> _tasksForVisiblePeriod({
    required DateTime focusedDay,
    required String view,
    DateTime? excludeDay,
  }) {
    final excludeKey = excludeDay == null ? null : _normalizeDate(excludeDay);

    DateTime start;
    DateTime end;
    if (view == 'Week') {
      final weekday = focusedDay.weekday;
      start = _normalizeDate(focusedDay.subtract(Duration(days: weekday - 1)));
      end = _normalizeDate(start.add(const Duration(days: 6)));
    } else if (view == 'Dag') {
      start = _normalizeDate(focusedDay);
      end = start;
    } else {
      start = DateTime(focusedDay.year, focusedDay.month, 1);
      end = DateTime(focusedDay.year, focusedDay.month + 1, 0);
    }

    final out = <dynamic>[];
    for (final entry in _groupedTasks.entries) {
      final day = entry.key;
      if (day.isBefore(start) || day.isAfter(end)) continue;
      if (excludeKey != null && _isSameDay(day, excludeKey)) continue;
      out.addAll(_filterTaskList(entry.value));
    }
    return out;
  }

  Widget _buildAgendaFilterButton({
    required String label,
    required String? value,
    required VoidCallback onTap,
    required ColorScheme cs,
    required bool isDark,
  }) {
    final fill = isDark ? const Color(0xFF1B1B23) : const Color(0xFFF5F5F7);
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value ?? 'Alle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgendaFilterContainer({
    required ColorScheme cs,
    required bool isDark,
  }) {
    final klantOptions = _agendaFilterOptions('bedrijfsnaam');
    final projectOptions = _agendaFilterOptions('project_naam');
    final regioOptions = _agendaFilterOptions('werk_regio');
    final operatorOptions = _agendaOperatorOptions();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF12121A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (val) {
                    setState(() => _searchQuery = val);
                    _syncEventController();
                  },
                  decoration: InputDecoration(
                    hintText: 'Zoek op klant of project',
                    hintStyle: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.45),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: cs.primary.withValues(alpha: 0.9),
                    ),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF1B1B23)
                        : const Color(0xFFF5F5F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAgendaFilterButton(
                  label: 'Regio',
                  value: _filterRegio,
                  cs: cs,
                  isDark: isDark,
                  onTap: () => _showPremiumFilterModal(
                    context: context,
                    title: 'Filter op Regio',
                    items: regioOptions,
                    selectedItem: _filterRegio,
                    onItemSelected: (v) {
                      setState(() => _filterRegio = v);
                      _syncEventController();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildAgendaFilterButton(
                  label: 'Klant',
                  value: _filterKlant,
                  cs: cs,
                  isDark: isDark,
                  onTap: () => _showPremiumFilterModal(
                    context: context,
                    title: 'Filter op Klant',
                    items: klantOptions,
                    selectedItem: _filterKlant,
                    onItemSelected: (v) {
                      setState(() => _filterKlant = v);
                      _syncEventController();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAgendaFilterButton(
                  label: 'Project',
                  value: _filterProject,
                  cs: cs,
                  isDark: isDark,
                  onTap: () => _showPremiumFilterModal(
                    context: context,
                    title: 'Filter op Project',
                    items: projectOptions,
                    selectedItem: _filterProject,
                    onItemSelected: (v) {
                      setState(() => _filterProject = v);
                      _syncEventController();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildAgendaFilterButton(
            label: 'Operators',
            value: _operatorFilterLabel(),
            cs: cs,
            isDark: isDark,
            onTap: () => _showPremiumMultiFilterModal(
              title: 'Filter op Operators',
              items: operatorOptions,
              selectedItems: _filterOperators,
              onItemsChanged: (items) {
                setState(() => _filterOperators = List<String>.from(items));
                _syncEventController();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaViewSwitcher(ColorScheme cs, bool isDark) {
    const views = ['Maand', 'Week', 'Dag'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: views.map((view) {
        final selected = _currentView == view;
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _currentView = view),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                  color: selected
                      ? cs.primary
                      : (isDark
                          ? const Color(0xFF1A2132)
                          : const Color(0xFFEAF0FA)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  view,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? Colors.white
                        : cs.onSurface.withValues(alpha: 0.82),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAppleMonthCell(
    dynamic dateRaw,
    bool isToday,
    bool isInMonth,
    ColorScheme cs,
    bool isDark,
  ) {
    final date = dateRaw as DateTime;
    final isSelected =
        _selectedDay != null && _isSameDay(_selectedDay!, date);
    final dayEvents = _eventController.getEventsOnDay(date);
    final textColor = !isInMonth
        ? cs.onSurface.withValues(alpha: 0.28)
        : (isSelected ? Colors.white : cs.onSurface);

    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) => _isVerplaatsbaarTask(details.data),
      onAcceptWithDetails: (details) => _onMonthEventDrop(details.data, date),
      builder: (context, candidateData, rejectedData) {
        final isDropHover = candidateData.isNotEmpty;
        return InkWell(
          onTap: () => _onMonthCellTap(date),
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDropHover
                  ? cs.primary.withValues(alpha: 0.22)
                  : (isSelected
                      ? cs.primary
                      : (isToday
                          ? cs.primary.withValues(alpha: 0.12)
                          : Colors.transparent)),
              borderRadius: BorderRadius.circular(10),
              border: isDropHover
                  ? Border.all(color: cs.primary, width: 2)
                  : (isToday && !isSelected
                      ? Border.all(color: cs.primary.withValues(alpha: 0.35))
                      : null),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Text(
                    '${date.day}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final event in dayEvents.take(3))
                        _buildMonthEventChip(event, date, cs),
                      if (dayEvents.length > 3)
                        Text(
                          '+ ${dayEvents.length - 3} meer',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
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

  Widget _buildMonthEventChip(
    CalendarEventData<Map<String, dynamic>> event,
    DateTime date,
    ColorScheme cs,
  ) {
    final raw = event.event;
    final task = raw is Map ? Map<String, dynamic>.from(raw as Map) : null;
    final chip = GestureDetector(
      onTap: () => _onCalendarEventTap(event, date),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: event.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border(left: BorderSide(color: event.color, width: 3)),
        ),
        child: Text(
          event.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.blue.shade900,
            height: 1.1,
          ),
        ),
      ),
    );

    if (task == null || !_isVerplaatsbaarTask(task)) return chip;

    return LongPressDraggable<Map<String, dynamic>>(
      data: task,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: event.color.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: chip),
      onDragEnd: (details) {
        if (details.wasAccepted) return;
        _syncEventController();
        if (mounted) setState(() {});
      },
      child: chip,
    );
  }

  Widget _buildCalendarView(ColorScheme cs, bool isDark) {
    final minDay = DateTime.now().subtract(const Duration(days: 730));
    final maxDay = DateTime.now().add(const Duration(days: 730));
    final activeDay = _selectedDay ?? _focusedDay;
    final headerStyle = _calendarHeaderStyle(isDark);
    final hourLines = HourIndicatorSettings(
      color: Colors.grey.shade200,
      height: 1,
    );
    final liveLine = LiveTimeIndicatorSettings(
      color: Colors.blue.shade700,
    );

    switch (_currentView) {
      case 'Week':
        return WeekView<Map<String, dynamic>>(
          key: _weekViewKey,
          controller: _eventController,
          minDay: minDay,
          maxDay: maxDay,
          initialDay: _currentWeekDate,
          startDay: WeekDays.monday,
          heightPerMinute: _heightPerMinute,
          timeLineWidth: _weekTimeLineWidth,
          showVerticalLines: false,
          headerStyle: headerStyle,
          weekTitleHeight: 70,
          headerStringBuilder: (date, {secondaryDate}) {
            final weekNum = _getWeekNumber(_currentWeekDate);
            final maandNaam = _maandNamen[_currentWeekDate.month - 1];
            return 'Week $weekNum - $maandNaam';
          },
          weekDayBuilder: (date) {
            const weekDays = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];

            final startOfWeek = _currentWeekDate.subtract(
              Duration(days: _currentWeekDate.weekday - 1),
            );
            final realDate = startOfWeek.add(
              Duration(days: date.weekday - 1),
            );

            final now = DateTime.now();
            final isToday = realDate.year == now.year &&
                realDate.month == now.month &&
                realDate.day == now.day;

            return Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    weekDays[realDate.weekday - 1],
                    style: TextStyle(
                      color: isToday
                          ? Colors.orange.shade700
                          : Colors.blue.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: isToday
                        ? BoxDecoration(
                            color: Colors.orange.shade700,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      realDate.day.toString(),
                      style: TextStyle(
                        color: isToday ? Colors.white : Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight:
                            isToday ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
          hourIndicatorSettings: hourLines,
          liveTimeIndicatorSettings: liveLine,
          eventTileBuilder: _buildWeekEventTile,
          onPageChange: _onWeekPageChange,
          onDateTap: _onCalendarDateTap,
          onEventTap: _onCalendarEventsCellTap,
          backgroundColor: isDark ? const Color(0xFF131722) : Colors.white,
        );
      case 'Dag':
        return _buildSyncfusionDayView(activeDay, cs, isDark);
      default:
        return MonthView<Map<String, dynamic>>(
          key: const ValueKey('month_view'),
          controller: _eventController,
          monthViewStyle: MonthViewStyle(
            initialMonth: _focusedDay,
            minMonth: minDay,
            maxMonth: maxDay,
            startDay: WeekDays.monday,
            cellAspectRatio: 0.72,
            hideDaysNotInMonth: false,
            borderColor: cs.onSurface.withValues(alpha: 0.06),
            headerStyle: headerStyle,
          ),
          monthViewBuilders: MonthViewBuilders(
            headerStringBuilder: (date, {secondaryDate}) =>
                DateFormat('MMMM yyyy', 'nl_NL').format(date),
            weekDayStringBuilder: (dayIndex) {
              const labels = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
              return labels[dayIndex.clamp(0, labels.length - 1)];
            },
            onPageChange: _onCalendarPageChange,
            onCellTap: (events, date) => _onMonthCellTap(date),
            onEventTap: (event, date) {
              final raw = event.event;
              if (raw is Map) {
                _onAgendaTaskTap(Map<String, dynamic>.from(raw));
              }
            },
            cellBuilder: (date, events, isToday, isInMonth, hideDaysNotInMonth) {
              return _buildAppleMonthCell(
                date,
                isToday,
                isInMonth,
                cs,
                isDark,
              );
            },
          ),
        );
    }
  }

  Widget _buildPremiumCalendarShell({
    required ColorScheme cs,
    required bool isDark,
    required Widget child,
    bool clipContent = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131722) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: clipContent
          ? ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: child,
            )
          : child,
    );
  }

  Widget _buildCalendarSection({
    required ColorScheme cs,
    required bool isDark,
  }) {
    final calendarHeight = _calendarViewportHeight(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _premiumAgendaCardDecoration(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.filter_list),
                label: const Text('Filters'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => setState(() => _showFilters = !_showFilters),
              ),
              Expanded(child: _buildAgendaViewSwitcher(cs, isDark)),
            ],
          ),
          if (_showFilters)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _buildAgendaFilterContainer(cs: cs, isDark: isDark),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: calendarHeight,
            child: _buildPremiumCalendarShell(
              cs: cs,
              isDark: isDark,
              clipContent: _currentView != 'Dag',
              child: _buildCalendarView(cs, isDark),
            ),
          ),
        ],
      ),
    );
  }

  void _onAgendaTaskTap(Map<String, dynamic> item) {
    final pers = item['_persoonlijk_agenda'] == true;
    final maker = _text(item['maker_id']);
    final uid = _text(_currentUserId);
    if (pers && maker.isNotEmpty && maker != uid) {
      _openPersoonlijkAlleenLezen(item);
      return;
    }
    _openAgendaDetailModal(item);
  }

  Widget _buildSelectedDayPanel({
    required ColorScheme cs,
    required bool isDark,
    required List<dynamic> dayTasks,
  }) {
    final selectedDay = _selectedDay!;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: _premiumAgendaCardDecoration(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Geplande taken op ${DateFormat('d MMMM yyyy', 'nl_NL').format(selectedDay)}',
                  style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -0.2,
                ),
              ),
            ),
              if (_selectedDay != null)
                IconButton(
                  tooltip: 'Sluiten',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _selectedDay = null;
                    });
                  },
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (dayTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Geen taken gepland op deze dag.',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.65),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: dayTasks.length,
              itemBuilder: (context, index) {
                final item = Map<String, dynamic>.from(
                  dayTasks[index] as Map,
                );
                return _premiumAgendaTaskTile(
                  item: item,
                  cs: cs,
                  isDark: isDark,
                  onTap: () => _onAgendaTaskTap(item),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPeriodOverview({
    required ColorScheme cs,
    required bool isDark,
    required List<dynamic> periodTasks,
  }) {
    final periodLabel = _currentView == 'Week'
        ? 'week'
        : (_currentView == 'Dag' ? 'dag' : 'maand');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: _premiumAgendaCardDecoration(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Overzicht — deze $periodLabel',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          if (periodTasks.isEmpty)
            Text(
              'Geen opdrachten in deze $periodLabel.',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withValues(alpha: 0.72),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: periodTasks.length,
              itemBuilder: (context, index) {
                final item = Map<String, dynamic>.from(
                  periodTasks[index] as Map,
                );
                return _premiumAgendaTaskTile(
                  item: item,
                  cs: cs,
                  isDark: isDark,
                  onTap: () => _onAgendaTaskTap(item),
                );
              },
            ),
        ],
      ),
    );
  }

  BoxDecoration _agendaPremiumTaskDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF0F172A).withValues(alpha: 0.95),
          const Color(0xFF0052CC).withValues(alpha: 0.85),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  BoxDecoration _premiumAgendaCardDecoration({
    required bool isDark,
    Color? leftBorderColor,
  }) {
    return BoxDecoration(
      color: isDark ? const Color(0xFF131722) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ],
    ).copyWith(
      border: leftBorderColor != null
          ? Border(
              left: BorderSide(width: 6, color: leftBorderColor),
            )
          : null,
    );
  }

  Widget _premiumAgendaTaskTile({
    required Map<String, dynamic> item,
    required ColorScheme cs,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final agendaKleur = _text(item['agenda_kleur']);
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
    final region = _text(item['werk_regio']).isEmpty ? 'Onbekend' : _text(item['werk_regio']);
    final plannedOperators = _text(item['geplande_operators_aantal']).isEmpty
        ? '0'
        : _text(item['geplande_operators_aantal']);
    final neededOperatorsRaw = _text(item['benodigde_operators']).isNotEmpty
        ? _text(item['benodigde_operators'])
        : _text(item['voorkeur_aantal_operators']);
    final neededOperators = neededOperatorsRaw.isEmpty ? '1' : neededOperatorsRaw;
    final isRood = agendaKleur.toLowerCase() == 'rood';

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: _agendaPremiumTaskDecoration(),
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
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  plannedDateLabel,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    region,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      color: Colors.white,
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
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              company,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.person,
                  size: 16,
                  color: Colors.white70,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    operatorNames,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$plannedOperators/$neededOperators Operators',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    color: isRood ? Colors.red.shade200 : Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAgendaDetailModal(Map<String, dynamic> task) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SelectionArea(
        child: AgendaDetailModal(
          task: task,
          onVerplaatsVeilig: _verplaatsOpdrachtVeilig,
          onAgendaUpdated: _loadAgenda,
        ),
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
    final isMobile = MediaQuery.of(context).size.width < 800;
    final dayTasks = _tasksForSelectedDay();
    final periodTasks = _tasksForVisiblePeriod(
      focusedDay: _focusedDay,
      view: _currentView,
      excludeDay: _selectedDay,
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
      body: CalendarControllerProvider<Map<String, dynamic>>(
        controller: _eventController,
        child: SelectionArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            _buildInboxBanner(cs, isDark),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _isLoading
                      ? const SizedBox(
                          height: 320,
                          child: Center(child: CircularProgressIndicator()),
                        )
                    : _loadError != null
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 48),
                            child: Text(
                              'Agenda laden mislukt: $_loadError',
                              textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                              ),
                            )
                          : isMobile
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildCalendarSection(
                                      cs: cs,
                                      isDark: isDark,
                                    ),
                                    if (_selectedDay != null) ...[
                                      const SizedBox(height: 12),
                                      _buildSelectedDayPanel(
                                        cs: cs,
                                        isDark: isDark,
                                        dayTasks: dayTasks,
                                      ),
                                    ],
                                  ],
                                )
                              : Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                      flex: _selectedDay == null ? 1 : 5,
                                      child: _buildCalendarSection(
                                        cs: cs,
                                        isDark: isDark,
                                      ),
                                    ),
                                    if (_selectedDay != null) ...[
                                      const SizedBox(width: 14),
                                            Expanded(
                                        flex: 3,
                                        child: _buildSelectedDayPanel(
                                          cs: cs,
                                          isDark: isDark,
                                          dayTasks: dayTasks,
                                              ),
                                            ),
                                          ],
                                      ],
                                    ),
                                  ),
                if (!_isLoading && _loadError == null && _currentView != 'Dag')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _buildPeriodOverview(
                      cs: cs,
                      isDark: isDark,
                      periodTasks: periodTasks,
                    ),
                  ),
                SizedBox(height: isMobile ? 96 : 24),
                                      ],
                                    ),
                                  ),
        ),
      ),
    );
  }
}

class OpdrachtDataSource extends CalendarDataSource {
  OpdrachtDataSource(
    List<Appointment> source,
    List<CalendarResource> resourceList,
  ) {
    appointments = source;
    resources = resourceList;
  }
}

class AgendaDetailModal extends StatefulWidget {
  const AgendaDetailModal({
    required this.task,
    this.onVerplaatsVeilig,
    this.onAgendaUpdated,
    super.key,
  });

  final Map<String, dynamic> task;
  final Future<bool> Function(
    String opdrachtId,
    DateTime nieuweDatum,
    TimeOfDay nieuweStart,
    TimeOfDay nieuweEind,
  )? onVerplaatsVeilig;
  final Future<void> Function()? onAgendaUpdated;

  @override
  State<AgendaDetailModal> createState() => _AgendaDetailModalState();
}

class _AgendaDetailModalState extends State<AgendaDetailModal> {
  String _text(dynamic value) => (value ?? '').toString().trim();
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _toelichting;
  final TextEditingController _toelichtingController = TextEditingController();
  bool _loadingToelichting = false;
  bool _savingToelichting = false;
  bool _savingVerplaatsing = false;

  DateTime? _geplandeDatum;
  TimeOfDay? _geplandeStartTod;
  TimeOfDay? _geplandeEindTod;

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

  String _timeHuman(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parseTimeOfDay(
    dynamic value, {
    int defaultHour = 9,
    int defaultMinute = 0,
  }) {
    final raw = _timeLabel(value);
    if (raw == '--:--') {
      return TimeOfDay(hour: defaultHour, minute: defaultMinute);
    }
    final parts = raw.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? defaultHour,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : defaultMinute,
    );
  }

  bool get _canVerplaatsen =>
      widget.onVerplaatsVeilig != null &&
      widget.task['_persoonlijk_agenda'] != true &&
      _opdrachtIdFromTask(widget.task).isNotEmpty;

  bool get _planningChanged {
    if (_geplandeDatum == null ||
        _geplandeStartTod == null ||
        _geplandeEindTod == null) {
      return false;
    }
    final origD = _parseDate(widget.task['geplande_datum']);
    final origStart = _parseTimeOfDay(widget.task['starttijd'], defaultHour: 9);
    final origEnd = _parseTimeOfDay(widget.task['eindtijd'], defaultHour: 10);
    if (origD == null) return true;
    return !_sameDay(origD, _geplandeDatum!) ||
        origStart.hour != _geplandeStartTod!.hour ||
        origStart.minute != _geplandeStartTod!.minute ||
        origEnd.hour != _geplandeEindTod!.hour ||
        origEnd.minute != _geplandeEindTod!.minute;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String? _originalDateHuman;
  String _originalStart = '--:--';
  String _originalEnd = '--:--';
  String _originalOperator = 'Onbekend';

  String? _geplandeDatumHuman;
  String _geplandeStart = '--:--';
  String _geplandeEind = '--:--';
  String _geplandeOperator = 'Onbekend';

  String _opdrachtIdFromTask(Map<String, dynamic> task) {
    final candidate = _text(task['opdracht_id']).isNotEmpty
        ? _text(task['opdracht_id'])
        : _text(task['id']);
    return candidate;
  }

  Future<void> _loadToelichtingPlanning() async {
    final opdrachtId = _opdrachtIdFromTask(widget.task);
    if (opdrachtId.isEmpty) return;

    setState(() => _loadingToelichting = true);
    try {
      final res = await _supabase
          .from('opdrachten')
          .select('toelichting_planning')
          .eq('id', opdrachtId)
          .maybeSingle();

      if (!mounted) return;
      final text = (res?['toelichting_planning'] ?? '').toString().trim();
      setState(() {
        _toelichting = text.isEmpty ? null : text;
        _toelichtingController.text = text;
      });
    } catch (_) {
      if (!mounted) return;
      // Silent fail: agenda moet altijd openen.
    } finally {
      if (mounted) setState(() => _loadingToelichting = false);
    }
  }

  Future<void> _pickGeplandeDatum() async {
    if (!_canVerplaatsen || _geplandeDatum == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _geplandeDatum!,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      locale: const Locale('nl', 'NL'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _geplandeDatum = DateTime(picked.year, picked.month, picked.day);
      _geplandeDatumHuman = _dateHuman(_geplandeDatum!);
    });
  }

  Future<void> _pickStartTijd() async {
    if (!_canVerplaatsen || _geplandeStartTod == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: _geplandeStartTod!,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _geplandeStartTod = picked;
      _geplandeStart = _timeHuman(picked);
    });
  }

  Future<void> _pickEindTijd() async {
    if (!_canVerplaatsen || _geplandeEindTod == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: _geplandeEindTod!,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _geplandeEindTod = picked;
      _geplandeEind = _timeHuman(picked);
    });
  }

  Future<void> _saveVerplaatsing() async {
    if (!_canVerplaatsen || _savingVerplaatsing) return;
    if (_geplandeDatum == null ||
        _geplandeStartTod == null ||
        _geplandeEindTod == null) {
      return;
    }

    final startMin = _geplandeStartTod!.hour * 60 + _geplandeStartTod!.minute;
    final endMin = _geplandeEindTod!.hour * 60 + _geplandeEindTod!.minute;
    if (endMin <= startMin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade800,
          content: Text(
            'Eindtijd moet na starttijd liggen.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final opdrachtId = _opdrachtIdFromTask(widget.task);
    if (opdrachtId.isEmpty) return;

    setState(() => _savingVerplaatsing = true);
    try {
      final ok = await widget.onVerplaatsVeilig!(
        opdrachtId,
        _geplandeDatum!,
        _geplandeStartTod!,
        _geplandeEindTod!,
      );
      if (!mounted) return;
      if (ok) {
        await widget.onAgendaUpdated?.call();
        if (mounted) Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _savingVerplaatsing = false);
    }
  }

  Widget _editablePlanningTile({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A2030) : const Color(0xFFF4F6FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
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
                      TextSpan(text: value),
                    ],
                  ),
                ),
              ),
              Icon(
                Icons.edit_outlined,
                size: 18,
                color: cs.onSurface.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveToelichtingPlanning() async {
    if (_savingToelichting) return;
    final opdrachtId = _opdrachtIdFromTask(widget.task);
    if (opdrachtId.isEmpty) return;

    final value = _toelichtingController.text.trim();

    setState(() => _savingToelichting = true);
    try {
      await _supabase.from('opdrachten').update({
        'toelichting_planning': value.isEmpty ? null : value,
      }).eq('id', opdrachtId);

      if (!mounted) return;
      setState(() => _toelichting = value.isEmpty ? null : value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Opmerking opgeslagen.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade800,
          content: Text(
            'Opslaan mislukt: $e',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingToelichting = false);
    }
  }

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

    _geplandeDatum = d == null
        ? null
        : DateTime(d.year, d.month, d.day);
    _geplandeStartTod = _parseTimeOfDay(t['starttijd'], defaultHour: 9);
    _geplandeEindTod = _parseTimeOfDay(t['eindtijd'], defaultHour: 10);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadToelichtingPlanning();
    });
  }

  @override
  void dispose() {
    _toelichtingController.dispose();
    super.dispose();
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
              if (_canVerplaatsen) ...[
                _editablePlanningTile(
                  context: context,
                  label: 'Geplande datum',
                  value: _geplandeDatumHuman ?? '—',
                  icon: Icons.calendar_today_rounded,
                  onTap: _pickGeplandeDatum,
                ),
                const SizedBox(height: 8),
                _editablePlanningTile(
                  context: context,
                  label: 'Starttijd',
                  value: _geplandeStart,
                  icon: Icons.schedule_rounded,
                  onTap: _pickStartTijd,
                ),
                const SizedBox(height: 8),
                _editablePlanningTile(
                  context: context,
                  label: 'Eindtijd',
                  value: _geplandeEind,
                  icon: Icons.schedule_outlined,
                  onTap: _pickEindTijd,
                ),
                if (_planningChanged) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _savingVerplaatsing ? null : _saveVerplaatsing,
                      icon: _savingVerplaatsing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        'Planning opslaan',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ] else ...[
                _block(context, 'Geplande datum', _geplandeDatumHuman ?? '—'),
                const SizedBox(height: 8),
                _block(context, 'Tijd', '$_geplandeStart – $_geplandeEind'),
              ],
              const SizedBox(height: 8),
              _block(context, 'Operator', _geplandeOperator),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? cs.primary.withValues(alpha: 0.12)
                      : const Color(0xFFE8F4FD),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.notification_important_rounded,
                          size: 20,
                          color: Colors.orange.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Voeg opmerking toe voor deze klus',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: cs.onSurface.withValues(alpha: 0.08),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: TextField(
                        controller: _toelichtingController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Bijv. let op sleutel bij receptie…',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed:
                            (_loadingToelichting || _savingToelichting)
                                ? null
                                : _saveToelichtingPlanning,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _savingToelichting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                _toelichting == null
                                    ? 'Opmerking opslaan'
                                    : 'Opmerking bijwerken',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),

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
