import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import 'manual_plan_modal.dart';
/// Planbord (Smart Planner) for the Facilitator Portal.
class PlanningDashboardScreen extends StatefulWidget {
  const PlanningDashboardScreen({super.key});

  @override
  State<PlanningDashboardScreen> createState() => _PlanningDashboardScreenState();
}

class _PlanningDashboardScreenState extends State<PlanningDashboardScreen> {
  Map<String, dynamic>? _selectedProject;
  bool _isPlannerOpen = false;
  List<dynamic> _operatorResults = [];
  bool _isCalculating = false;
  final TextEditingController _hoursController = TextEditingController();

  List<dynamic> _projects = [];
  bool _isLoadingProjects = true;
  Object? _projectsError;
  bool _hasCalculated = false;
  String? _selectedManualProjectId;
  List<Map<String, dynamic>> _manualTasks = [];
  bool _isLoadingManualTasks = true;
  Object? _manualTasksError;
  late final CalendarController _calendarController;
  final Set<DateTime> _expandedDates = <DateTime>{};
  final Map<String, Map<String, dynamic>> _manualTasksById = <String, Map<String, dynamic>>{};
  OpdrachtDataSource _manualDataSource = OpdrachtDataSource(
    const <dynamic>[],
    color: const Color(0xFF4A6CF7),
  );

  @override
  void initState() {
    super.initState();
    _calendarController = CalendarController();
    _calendarController.view = CalendarView.month;
    _calendarController.displayDate = DateTime.now();
    _fetchProjects();
    _loadOpdrachten();
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _calendarController.dispose();
    super.dispose();
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(_text(value).replaceAll(',', '.')) ?? fallback;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(_text(value)) ?? fallback;
  }

  List<String> _asStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => _text(e)).where((e) => e.isNotEmpty).toList(growable: false);
    }
    final raw = _text(value);
    if (raw.isEmpty) return const [];
    return raw
        .replaceAll('[', '')
        .replaceAll(']', '')
        .split(',')
        .map((e) => e.replaceAll('"', '').replaceAll("'", '').trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _fetchProjects() async {
    setState(() {
      _isLoadingProjects = true;
      _projectsError = null;
    });

    try {
      final results = await AppSupabase.client
          .from('projecten')
          .select()
          .eq('status', 'actief')
          .order('project_naam', ascending: true);
      if (!mounted) return;
      setState(() {
        _projects = List<dynamic>.from(results as List);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _projectsError = error;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingProjects = false);
      }
    }
  }

  Future<void> _loadOpdrachten() async {
    setState(() {
      _isLoadingManualTasks = true;
      _manualTasksError = null;
    });

    try {
      final baseQuery = AppSupabase.client
          .from('opdrachten')
          .select(
            'id, project_id, geplande_datum, status, tijdslot_start, tijdslot_eind, '
            'benodigde_operators, werk_regio, bedrijfsnaam, uitvoer_adres_volledig, '
            'projecten(project_naam)',
          )
          .inFilter('status', const ['open', 'deels_voltooid']);

      final result = (_selectedManualProjectId != null && _selectedManualProjectId!.isNotEmpty)
          ? await baseQuery
              .eq('project_id', _selectedManualProjectId!)
              .order('geplande_datum', ascending: true)
          : await baseQuery.order('geplande_datum', ascending: true);

      final parsedAppointments = (result as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);

      final idIndex = <String, Map<String, dynamic>>{};
      for (final row in parsedAppointments) {
        final id = _text(row['id']);
        if (id.isNotEmpty) idIndex[id] = row;
      }

      if (!mounted) return;
      setState(() {
        _manualTasks = parsedAppointments;
        _manualTasksById
          ..clear()
          ..addAll(idIndex);
        _manualDataSource = OpdrachtDataSource(
          parsedAppointments,
          color: Theme.of(context).colorScheme.primary,
        );
      });
    } catch (error) {
      debugPrint('Planbord manual tasks query failed: $error');
      if (!mounted) return;
      setState(() {
        _manualTasksError = error;
        _manualTasks = const <Map<String, dynamic>>[];
        _manualTasksById.clear();
        _manualDataSource = OpdrachtDataSource(
          const <dynamic>[],
          color: Theme.of(context).colorScheme.primary,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingManualTasks = false);
      }
    }
  }

  DateTime _toDate(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return DateTime.now();
    return DateTime.tryParse(raw) ?? DateTime.now();
  }

  TimeOfDay _toTimeOfDay(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return const TimeOfDay(hour: 8, minute: 0);
    final hhmm = raw.length >= 5 ? raw.substring(0, 5) : raw;
    final parts = hhmm.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 8 : 8;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  String _fmtTime(dynamic value) {
    final tod = _toTimeOfDay(value);
    return '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic>? _projectJoin(Map<String, dynamic> row) {
    final joined = row['projecten'];
    if (joined is Map<String, dynamic>) return joined;
    if (joined is List && joined.isNotEmpty && joined.first is Map) {
      return Map<String, dynamic>.from(joined.first as Map);
    }
    return null;
  }

  String _manualProjectName(Map<String, dynamic> task) {
    final joined = _projectJoin(task);
    final fromJoin = _text(joined?['project_naam']);
    if (fromJoin.isNotEmpty) return fromJoin;
    return 'Onbekend project';
  }

  String _manualCompanyName(Map<String, dynamic> task) {
    final local = _text(task['bedrijfsnaam']);
    return local.isEmpty ? 'Onbekende klant' : local;
  }

  String _manualRegion(Map<String, dynamic> task) {
    final local = _text(task['werk_regio']);
    return local.isEmpty ? 'Geen regio' : local;
  }

  DateTime _dateKey(DateTime date) => DateTime(date.year, date.month, date.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Map<String, dynamic>? _taskFromAppointment(Appointment appointment) {
    final appointmentId = _text(appointment.id);
    if (appointmentId.isEmpty) return null;
    final fromIndex = _manualTasksById[appointmentId];
    if (fromIndex != null) return fromIndex;
    for (final task in _manualTasks) {
      if (_text(task['id']) == appointmentId) return task;
    }
    return null;
  }

  void _showDayTasksModal(BuildContext context, DateTime date, List<dynamic>? appointments) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final appointmentList = (appointments ?? const <dynamic>[])
            .whereType<Appointment>()
            .where((item) => _sameDay(item.startTime, date))
            .toList(growable: false);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Planning voor ${DateFormat('dd-MM-yyyy').format(date)}',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sluiten',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (appointmentList.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Geen opdrachten gepland',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: appointmentList.length,
                      separatorBuilder: (context, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final appointment = appointmentList[index];
                        final task = _taskFromAppointment(appointment);
                        final opdrachtId = _text(task?['id']);
                        final subtitle = DateFormat('HH:mm').format(appointment.startTime);

                        return ListTile(
                          title: Text(
                            appointment.subject,
                            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            subtitle,
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: opdrachtId.isEmpty
                              ? null
                              : () async {
                                  Navigator.of(sheetContext).pop();
                                  await _openManualPlanModal(opdrachtId);
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
  }

  Future<void> _openManualPlanModal(String opdrachtId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManualPlanModal(opdrachtId: opdrachtId),
    );
    if (!mounted) return;
    await _loadOpdrachten();
  }

  Widget _buildManualPlannerTab(bool isDark) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoadingManualTasks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_manualTasksError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Kon handmatige planning niet laden: $_manualTasksError',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOpdrachten,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111019) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            ),
            child: DropdownButtonFormField<String?>(
              initialValue: _selectedManualProjectId,
              decoration: InputDecoration(
                labelText: 'Project',
                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                filled: true,
                fillColor: isDark ? const Color(0xFF1B1B23) : const Color(0xFFF5F5F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Alle projecten', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                ),
                ..._projects
                    .map((raw) => Map<String, dynamic>.from(raw as Map))
                    .map(
                      (project) => DropdownMenuItem<String?>(
                        value: _text(project['id']),
                        child: Text(
                          _text(project['project_naam']).isEmpty
                              ? 'Naamloos project'
                              : _text(project['project_naam']),
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
              ],
              onChanged: (value) async {
                setState(() => _selectedManualProjectId = value);
                await _loadOpdrachten();
              },
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111019) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Kalender',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: Text(
                            'Maand',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                          ),
                          backgroundColor: _calendarController.view == CalendarView.month
                              ? cs.primary.withValues(alpha: 0.16)
                              : cs.onSurface.withValues(alpha: 0.06),
                          side: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)),
                          onPressed: () {
                            final currentDisplay =
                                _calendarController.displayDate ?? DateTime.now();
                            setState(() {
                              _calendarController.view = CalendarView.month;
                              _calendarController.displayDate = currentDisplay;
                            });
                          },
                        ),
                        ActionChip(
                          label: Text(
                            'Week',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                          ),
                          backgroundColor: _calendarController.view == CalendarView.week
                              ? cs.primary.withValues(alpha: 0.16)
                              : cs.onSurface.withValues(alpha: 0.06),
                          side: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)),
                          onPressed: () {
                            final currentDisplay =
                                _calendarController.displayDate ?? DateTime.now();
                            setState(() {
                              _calendarController.view = CalendarView.week;
                              _calendarController.displayDate = currentDisplay;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 420,
                  child: Column(
                    children: [
                      Expanded(
                        child: SfCalendar(
                          controller: _calendarController,
                          dataSource: _manualDataSource,
                          showNavigationArrow: true,
                          allowViewNavigation: false,
                          firstDayOfWeek: 1,
                          timeSlotViewSettings: const TimeSlotViewSettings(
                            timeFormat: 'HH:mm',
                          ),
                          monthViewSettings: const MonthViewSettings(
                            appointmentDisplayMode: MonthAppointmentDisplayMode.none,
                          ),
                          appointmentBuilder: (context, details) {
                      final appointment = details.appointments.first as Appointment;
                      return Container(
                        margin: const EdgeInsets.all(1),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${DateFormat('HH:mm').format(appointment.startTime)} ${appointment.subject}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                          },
                          monthCellBuilder: (context, details) {
                      final dayKey = _dateKey(details.date);
                      final dayAppointments = details.appointments
                          .whereType<Appointment>()
                          .where((a) => _sameDay(a.startTime, dayKey))
                          .toList(growable: false);
                      if (dayAppointments.isEmpty) {
                        return Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: cs.onSurface.withValues(alpha: 0.05)),
                              bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.05)),
                            ),
                          ),
                          padding: const EdgeInsets.all(6),
                          alignment: Alignment.topRight,
                          child: Text(
                            '${details.date.day}',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.45),
                            ),
                          ),
                        );
                      }

                      final expanded = _expandedDates.contains(dayKey);
                      if (!expanded) {
                        return GestureDetector(
                          onTap: () {
                            _showDayTasksModal(context, dayKey, dayAppointments);
                          },
                          child: Container(
                            margin: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Text(
                                    '${dayAppointments.length}',
                                    style: GoogleFonts.inter(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: cs.primary,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() => _expandedDates.add(dayKey));
                                    },
                                    child: Icon(
                                      Icons.unfold_more,
                                      size: 16,
                                      color: cs.primary.withValues(alpha: 0.80),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final visibleAppointments = dayAppointments.take(4).toList(growable: false);
                      final remaining = dayAppointments.length - visibleAppointments.length;
                      return Container(
                        margin: const EdgeInsets.all(1.5),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: GestureDetector(
                                onTap: () => setState(() => _expandedDates.remove(dayKey)),
                                child: Icon(
                                  Icons.unfold_less,
                                  size: 16,
                                  color: cs.primary.withValues(alpha: 0.80),
                                ),
                              ),
                            ),
                            ...visibleAppointments.map((appointment) {
                              final task = _taskFromAppointment(appointment);
                              final startLabel = DateFormat('HH:mm').format(appointment.startTime);
                              return GestureDetector(
                                onTap: () {
                                  final opdrachtId = _text(task?['id']);
                                  if (opdrachtId.isNotEmpty) {
                                    _openManualPlanModal(opdrachtId);
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.20),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    startLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: cs.primary.withValues(alpha: 0.78),
                                    ),
                                  ),
                                ),
                              );
                            }),
                            if (remaining > 0)
                              GestureDetector(
                                onTap: () {
                                  _showDayTasksModal(context, dayKey, dayAppointments);
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(top: 1),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Text(
                                    '+ $remaining meer',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: cs.primary.withValues(alpha: 0.82),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                          },
                          onTap: (details) {
                      if (details.targetElement == CalendarElement.calendarCell &&
                          details.date != null) {
                        _showDayTasksModal(context, details.date!, details.appointments);
                        return;
                      }

                      final first = details.appointments?.isNotEmpty == true
                          ? details.appointments!.first
                          : null;
                      if (first is Appointment) {
                        final task = _taskFromAppointment(first);
                        final opdrachtId = _text(task?['id']);
                        if (opdrachtId.isNotEmpty) {
                          _openManualPlanModal(opdrachtId);
                        }
                      }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Open opdrachten',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          if (_manualTasks.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111019) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              ),
              child: Text(
                'Geen open of deels voltooide opdrachten gevonden.',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.70),
                ),
              ),
            )
          else
            ..._manualTasks.map((task) {
              final opdrachtId = _text(task['id']);
              final projectName = _manualProjectName(task);
              final companyName = _manualCompanyName(task);
              final timeRange = '${_fmtTime(task['tijdslot_start'])} - ${_fmtTime(task['tijdslot_eind'])}';
              final region = _manualRegion(task);
              final neededOperators = _asInt(task['benodigde_operators'], fallback: 1);
              final date = _toDate(task['geplande_datum']);
              final dateLabel = DateFormat('dd-MM-yyyy').format(date);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: opdrachtId.isEmpty ? null : () => _openManualPlanModal(opdrachtId),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF111019) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  projectName,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  companyName,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface.withValues(alpha: 0.68),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _buildTag(cs, '$dateLabel • $timeRange'),
                                    _buildTag(cs, region),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Nodig: $neededOperators operators',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTag(ColorScheme cs, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.20)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    );
  }

  Future<void> _runSmartPlanning() async {
    if (_selectedProject == null || _isCalculating) return;
    final parsedHours = double.tryParse(_hoursController.text.replaceAll(',', '.'));
    if (parsedHours == null || parsedHours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Vul een geldig aantal uren in.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => _isCalculating = true);
    try {
      final results = await AppSupabase.client.rpc(
        'bereken_slimme_planning',
        params: {
          'p_project_id': _selectedProject!['id'],
          'p_uren_per_shift': parsedHours,
        },
      );

      if (!mounted) return;
      setState(() {
        _operatorResults = List<dynamic>.from((results as List?) ?? const []);
        _hasCalculated = true;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Slim plannen mislukt: $error',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCalculating = false);
      }
    }
  }

  Future<void> _confirmBooking(Map<String, dynamic> result) async {
    final name = _text(result['naam']).isEmpty ? 'deze operator' : _text(result['naam']);
    final available = _asInt(result['beschikbare_beurten']);

    final shouldConfirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Definitief inplannen?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Wilt u $name definitief inplannen op alle $available mogelijke opdrachten? '
            'De starttijden worden volautomatisch door het systeem gevuld.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Annuleren',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: Text(
                'Bevestigen',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (shouldConfirm != true) return;

    try {
      await AppSupabase.client.rpc(
        'bevestig_slimme_planning',
        params: {
          'p_voorgestelde_planning': result['voorgestelde_planning'],
          'p_operator_id': result['operator_id'],
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E8E3E),
          content: Text(
            'Planning is definitief opgeslagen.',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );

      setState(() {
        _isPlannerOpen = false;
        _selectedProject = null;
        _operatorResults = [];
        _hasCalculated = false;
      });
      await _fetchProjects();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Definitief inplannen mislukt: $error',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
  }

  void _openPlannerForProject(Map<String, dynamic> project) {
    final basisUren = _asDouble(project['basis_uren_per_opdracht'], fallback: 1);
    setState(() {
      _selectedProject = project;
      _isPlannerOpen = true;
      _hoursController.text = basisUren.toStringAsFixed(
        basisUren.truncateToDouble() == basisUren ? 0 : 1,
      );
      _operatorResults = [];
      _hasCalculated = false;
    });
  }

  Widget _buildProjectInbox(bool isDark) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoadingProjects) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_projectsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Projecten laden mislukt',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                '$_projectsError',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _fetchProjects,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  'Opnieuw proberen',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_projects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'Geen actieve projecten gevonden.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.60),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchProjects,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        itemCount: _projects.length,
        itemBuilder: (context, index) {
          final project = Map<String, dynamic>.from(_projects[index] as Map);
          final projectName = _text(project['project_naam']).isEmpty ? 'Naamloos project' : _text(project['project_naam']);
          final regio = _text(project['werk_regio']).isEmpty ? 'Geen regio' : _text(project['werk_regio']);
          final start = _text(project['tijdslot_start']).isEmpty ? '--:--' : _text(project['tijdslot_start']);
          final end = _text(project['tijdslot_eind']).isEmpty ? '--:--' : _text(project['tijdslot_eind']);
          final basisUren = _asDouble(project['basis_uren_per_opdracht'], fallback: 0);
          final weekdays = _asStringList(project['reguliere_weekdagen']);
          final isSelected = _selectedProject?['id'] == project['id'];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _openPlannerForProject(project),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF111019) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isSelected ? cs.primary.withValues(alpha: 0.35) : cs.onSurface.withValues(alpha: 0.06),
                      width: isSelected ? 1.3 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  projectName,
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  regio,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface.withValues(alpha: 0.56),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$start - $end',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: weekdays
                            .map(
                              (day) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
                                ),
                                child: Text(
                                  day,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Standaard: ${basisUren.toStringAsFixed(basisUren.truncateToDouble() == basisUren ? 0 : 1)} uur',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface.withValues(alpha: 0.66),
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
      ),
    );
  }

  Color _resultBackground(String matchType) {
    switch (matchType) {
      case 'perfect_green':
        return const Color(0xFF1E8E3E);
      case 'bad_red':
        return const Color(0xFFCC2F2F);
      default:
        return Colors.white;
    }
  }

  Border _resultBorder(String matchType) {
    switch (matchType) {
      case 'varied_green':
        return Border.all(color: Colors.green, width: 3);
      case 'partial_yellow':
        return Border.all(color: const Color(0xFFE3B72C), width: 3);
      case 'partial_grey':
        return Border.all(color: Colors.grey.shade500, width: 3);
      case 'perfect_green':
      case 'bad_red':
        return Border.all(color: Colors.transparent);
      default:
        return Border.all(color: Colors.grey.shade300, width: 1);
    }
  }

  String _matchLabel(String matchType) {
    switch (matchType) {
      case 'perfect_green':
        return '100% Match - Vaste tijden';
      case 'varied_green':
        return '100% Match - Wisselende tijden';
      case 'partial_yellow':
        return 'Deels Match - Beperkte beschikbaarheid';
      case 'partial_grey':
        return 'Beperkte Match';
      case 'bad_red':
        return 'Geen bruikbare match';
      default:
        return 'Match resultaat';
    }
  }

  Widget _buildResultCard(Map<String, dynamic> result) {
    final matchType = _text(result['match_type']);
    final isSolid = matchType == 'perfect_green' || matchType == 'bad_red';
    final textColor = isSolid ? Colors.white : const Color(0xFF15141F);
    final conflicts = result['conflicten'] is List ? List<dynamic>.from(result['conflicten'] as List) : const [];
    final available = _asInt(result['beschikbare_beurten']);
    final total = _asInt(result['totale_beurten']);
    final name = _text(result['naam']).isEmpty ? 'Onbekende operator' : _text(result['naam']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: total > 0 ? () => _confirmBooking(result) : null,
          child: Container(
            decoration: BoxDecoration(
              color: _resultBackground(matchType),
              borderRadius: BorderRadius.circular(24),
              border: _resultBorder(matchType),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _matchLabel(matchType),
                        textAlign: TextAlign.right,
                        style: GoogleFonts.inter(
                          color: textColor.withValues(alpha: isSolid ? 0.96 : 0.82),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$available van de $total beurten beschikbaar',
                    style: GoogleFonts.inter(
                      color: textColor.withValues(alpha: isSolid ? 0.92 : 0.70),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (conflicts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 6),
                        iconColor: textColor,
                        collapsedIconColor: textColor,
                        textColor: textColor,
                        collapsedTextColor: textColor,
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Text(
                          'Bekijk Conflicten',
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        children: conflicts
                            .map(
                              (conflict) => Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '• ${_text((conflict is Map) ? conflict['datum'] ?? conflict['date'] ?? conflict['omschrijving'] ?? conflict : conflict)}',
                                    style: GoogleFonts.inter(
                                      color: textColor.withValues(alpha: isSolid ? 0.92 : 0.72),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlannerPanel(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final projectName = _text(_selectedProject?['project_naam']).isEmpty
        ? 'project'
        : _text(_selectedProject?['project_naam']);

    final visibleResults = _operatorResults.where((item) {
      if (item is! Map) return false;
      final map = Map<String, dynamic>.from(item);
      final matchType = _text(map['match_type']);
      final total = _asInt(map['totale_beurten']);
      if (matchType == 'bad_red' && total <= 0) return false;
      return true;
    }).map((item) => Map<String, dynamic>.from(item)).toList(growable: false);

    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      offset: _isPlannerOpen ? Offset.zero : const Offset(0.25, 0),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: _isPlannerOpen ? 1 : 0,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 18, 20, 20),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border(
              left: BorderSide(color: cs.primary.withValues(alpha: 0.25), width: 1.2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Plan reeks voor $projectName',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF15141F),
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _isPlannerOpen = false),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Sluiten',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _hoursController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Uren per shift (Aanpasbaar)',
                  labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  filled: true,
                  fillColor: const Color(0xFFF5F7FB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: cs.primary, width: 1.2),
                  ),
                ),
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF15141F),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCalculating ? null : _runSmartPlanning,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: cs.primary.withValues(alpha: 0.52),
                    elevation: 0,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: _isCalculating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          '🧠 Slim Inplannen',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _isCalculating
                    ? const Center(child: CircularProgressIndicator())
                    : visibleResults.isEmpty
                        ? Center(
                            child: Text(
                              _hasCalculated
                                  ? 'Geen plannerresultaten gevonden voor dit project.'
                                  : 'Klik op "Slim Inplannen" om operator matches te berekenen.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: const Color(0xFF15141F).withValues(alpha: 0.62),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 12),
                            itemCount: visibleResults.length,
                            itemBuilder: (context, index) {
                              return _buildResultCard(visibleResults[index]);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmartPlannerTab(bool isDark) {
    final isCompact = MediaQuery.of(context).size.width < 1040;
    final leftFlex = _isPlannerOpen ? (isCompact ? 3 : 4) : 10;
    final rightFlex = isCompact ? 7 : 6;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      child: Row(
        children: [
          Expanded(
            flex: leftFlex,
            child: _buildProjectInbox(isDark),
          ),
          if (_isPlannerOpen)
            Expanded(
              flex: rightFlex,
              child: _buildPlannerPanel(isDark),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bg,
        drawer: const AppDrawer(),
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          title: Text(
            'Planbord & Projecten',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
          actions: [
            IconButton(
              tooltip: 'Vernieuwen',
              onPressed: (_isLoadingProjects || _isLoadingManualTasks)
                  ? null
                  : () async {
                      await _fetchProjects();
                      await _loadOpdrachten();
                    },
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(58),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: isDark ? 0.08 : 0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: TabBar(
                  splashBorderRadius: BorderRadius.circular(24),
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: cs.onSurface.withValues(alpha: 0.70),
                  labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w900),
                  indicator: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  tabs: const [
                    Tab(text: 'Smart Planner'),
                    Tab(text: 'Handmatig Plannen'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildSmartPlannerTab(isDark),
            _buildManualPlannerTab(isDark),
          ],
        ),
      ),
    );
  }
}

class OpdrachtDataSource extends CalendarDataSource {
  OpdrachtDataSource(
    List<dynamic> supabaseData, {
    required Color color,
  }) {
    final mapped = <Appointment>[];

    String normalizeTime(dynamic value) {
      final raw = (value ?? '').toString().trim();
      if (raw.isEmpty) return '';
      if (raw.length == 5) return '$raw:00';
      return raw;
    }

    for (final raw in supabaseData) {
      try {
        if (raw is! Map) continue;
        final opdracht = Map<String, dynamic>.from(raw);
        final dateStr = (opdracht['geplande_datum'] ?? '').toString().trim();
        final startStr = normalizeTime(opdracht['tijdslot_start']);
        final endStr = normalizeTime(opdracht['tijdslot_eind']);
        if (dateStr.isEmpty || startStr.isEmpty) continue;

        final startTime = DateTime.parse('${dateStr}T$startStr');
        DateTime endTime;
        try {
          if (endStr.isEmpty) {
            endTime = startTime.add(const Duration(hours: 2));
          } else {
            endTime = DateTime.parse('${dateStr}T$endStr');
          }
        } catch (_) {
          endTime = startTime.add(const Duration(hours: 2));
        }
        if (!endTime.isAfter(startTime)) {
          endTime = startTime.add(const Duration(hours: 2));
        }

        final subject = _projectName(opdracht).isNotEmpty
            ? _projectName(opdracht)
            : _companyName(opdracht).isNotEmpty
                ? _companyName(opdracht)
                : 'Opdracht';

        mapped.add(
          Appointment(
            id: opdracht['id'],
            startTime: startTime,
            endTime: endTime,
            subject: subject,
            color: color,
            isAllDay: false,
          ),
        );
      } catch (error) {
        final taskId = (raw is Map ? raw['id'] : null) ?? 'unknown';
        debugPrint('CALENDAR PARSE ERROR for Task $taskId: $error');
      }
    }
    appointments = mapped;
  }

  static String _projectName(Map<String, dynamic> opdracht) {
    final joined = opdracht['projecten'];
    if (joined is Map) {
      final value = (joined['project_naam'] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    if (joined is List && joined.isNotEmpty && joined.first is Map) {
      final map = joined.first as Map;
      final value = (map['project_naam'] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _companyName(Map<String, dynamic> opdracht) {
    return (opdracht['bedrijfsnaam'] ?? '').toString().trim();
  }
}
