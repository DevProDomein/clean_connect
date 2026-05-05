import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/widgets/app_drawer.dart';

/// Kalenderoverzicht voor operators ([app_operator_agenda]).
class OperatorAgendaScreen extends StatefulWidget {
  const OperatorAgendaScreen({super.key});

  @override
  State<OperatorAgendaScreen> createState() => _OperatorAgendaScreenState();
}

class _OperatorAgendaScreenState extends State<OperatorAgendaScreen> {
  static const double _radiusCard = 16;
  static const Color _pageBg = Color(0xFFF7F8FB);
  static const Color _navy = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _blue = Color(0xFF2563EB);
  static const Color _green = Color(0xFF16A34A);

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  Map<DateTime, List<dynamic>> _groupedTasks = {};
  bool _isLoading = true;
  Object? _loadError;

  CalendarFormat _calendarFormat = CalendarFormat.month;

  String? _selectedKlant;
  String? _selectedProject;
  List<String> _beschikbareKlanten = [];
  List<String> _beschikbareProjecten = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAgenda());
  }

  String _t(dynamic v) => (v ?? '').toString().trim();

  DateTime _normalizeDate(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day);

  /// Kalenderdag uit rij (datum zonder tijd).
  DateTime? _dayFromRow(Map<String, dynamic> r) {
    for (final k in const [
      'datum',
      'geplande_datum',
      'agenda_datum',
      'rooster_datum',
      'start_datum',
    ]) {
      final v = r[k];
      if (v == null) continue;
      DateTime? p;
      if (v is DateTime) {
        p = v;
      } else {
        final s = v.toString().trim();
        if (s.isEmpty) continue;
        try {
          p = DateTime.parse(s);
        } catch (_) {
          p = DateTime.tryParse(s);
        }
      }
      if (p != null) return _normalizeDate(p);
    }
    return null;
  }

  String _hhmm(dynamic v) {
    final s = _t(v);
    if (s.length >= 5 && s.contains(':')) return s.substring(0, 5);
    if (s.isNotEmpty) return s;
    return '—';
  }

  Future<void> _loadAgenda() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Niet ingelogd.';
        _groupedTasks = {};
        _beschikbareKlanten = [];
        _beschikbareProjecten = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final res = await Supabase.instance.client
          .from('app_operator_agenda')
          .select()
          .eq('operator_id', uid);

      if (!mounted) return;
      final raw = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final grouped = <DateTime, List<dynamic>>{};
      for (final row in raw) {
        final day = _dayFromRow(row);
        if (day == null) continue;
        grouped.putIfAbsent(day, () => []).add(row);
      }
      for (final e in grouped.entries) {
        final sorted = [
          ...e.value.map((x) => Map<String, dynamic>.from(x as Map)),
        ];
        sorted.sort(
          (a, b) => _hhmm(a['starttijd']).compareTo(_hhmm(b['starttijd'])),
        );
        grouped[e.key] = sorted;
      }

      final klanten = <String>{};
      final projecten = <String>{};
      for (final task in raw) {
        if (task['bedrijfsnaam'] != null) {
          final k = _t(task['bedrijfsnaam']);
          if (k.isNotEmpty) klanten.add(k);
        }
        if (task['project_naam'] != null) {
          final p = _t(task['project_naam']);
          if (p.isNotEmpty) projecten.add(p);
        }
      }

      setState(() {
        _groupedTasks = grouped;
        _beschikbareKlanten = klanten.toList()..sort();
        _beschikbareProjecten = projecten.toList()..sort();
        if (_selectedKlant != null && !_beschikbareKlanten.contains(_selectedKlant)) {
          _selectedKlant = null;
        }
        if (_selectedProject != null && !_beschikbareProjecten.contains(_selectedProject)) {
          _selectedProject = null;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _groupedTasks = {};
        _beschikbareKlanten = [];
        _beschikbareProjecten = [];
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _tasksForDayUnfiltered(DateTime day) {
    final k = _normalizeDate(day);
    final raw = _groupedTasks[k];
    if (raw == null) return const [];
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  bool _taskMatchesFilters(Map<String, dynamic> task) {
    if (_selectedKlant != null && _t(task['bedrijfsnaam']) != _selectedKlant) {
      return false;
    }
    if (_selectedProject != null && _t(task['project_naam']) != _selectedProject) {
      return false;
    }
    return true;
  }

  /// Taken voor geselecteerde dag, met actieve klant/project-filters.
  List<Map<String, dynamic>> get _filteredTasksForSelectedDay {
    final day = _selectedDay != null
        ? _normalizeDate(_selectedDay!)
        : _normalizeDate(_focusedDay);
    return _eventsLoader(day);
  }

  /// Voor markers + lijst: alleen rijen die aan filters voldoen (markers verdwijnen op lege filter-dagen).
  List<Map<String, dynamic>> _eventsLoader(DateTime day) {
    return _tasksForDayUnfiltered(day).where(_taskMatchesFilters).toList();
  }

  bool _isVoltooid(Map<String, dynamic> t) {
    final s = _t(t['planning_status']).toLowerCase();
    return s.contains('voltooid') || s == 'afgerond';
  }

  Color _accentVoor(Map<String, dynamic> t) =>
      _isVoltooid(t) ? _green : _blue;

  String _statusPill(Map<String, dynamic> t) {
    final s = _t(t['planning_status']);
    return s.isEmpty ? '—' : s;
  }

  void _openDetails(Map<String, dynamic> task) {
    final project = _t(task['project_naam']);
    final bedrijf = _t(task['bedrijfsnaam']);
    final adres = _t(task['adres']);
    final start = _hhmm(task['starttijd']);
    final eind = _hhmm(task['eindtijd']);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Material(
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 16,
                  bottom: 24 + MediaQuery.paddingOf(ctx).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Afspraak',
                      style: GoogleFonts.lato(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _detailRegel(Icons.schedule_rounded, 'Tijd', '$start – $eind'),
                    const SizedBox(height: 12),
                    _detailRegel(Icons.work_outline_rounded, 'Project', project.isEmpty ? '—' : project),
                    const SizedBox(height: 12),
                    _detailRegel(Icons.business_outlined, 'Klant', bedrijf.isEmpty ? '—' : bedrijf),
                    const SizedBox(height: 12),
                    _detailRegel(Icons.place_outlined, 'Locatie', adres.isEmpty ? '—' : adres),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Sluiten',
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
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
  }

  Widget _detailRegel(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: _blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.lato(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _muted,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.lato(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _softCardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      );

  void _clearFilters() {
    setState(() {
      _selectedKlant = null;
      _selectedProject = null;
    });
  }

  Widget _buildFiltersPanel(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: _softCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Weergave & filters',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 0.2,
              color: _muted,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: _calendarFormat == CalendarFormat.month ? 0 : 1,
              backgroundColor: const Color(0xFFEEF2F9),
              thumbColor: Colors.white,
              padding: const EdgeInsets.all(4),
              children: <int, Widget>{
                0: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Maand',
                      style: GoogleFonts.lato(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: _navy,
                      ),
                    ),
                  ),
                ),
                1: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Week',
                      style: GoogleFonts.lato(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: _navy,
                      ),
                    ),
                  ),
                ),
              },
              onValueChanged: (int? v) {
                if (v == null) return;
                setState(() {
                  _calendarFormat =
                      v == 0 ? CalendarFormat.month : CalendarFormat.week;
                });
              },
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final dense = constraints.maxWidth < 360;
              final pillStyle = GoogleFonts.lato(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: _navy,
              );
              Widget klantField = Padding(
                padding: EdgeInsets.only(right: dense ? 0 : 8, bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      isDense: true,
                      isExpanded: true,
                      value: _selectedKlant,
                      hint: Text('Klant', style: pillStyle),
                      dropdownColor: Colors.white,
                      icon: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: _navy.withValues(alpha: 0.5),
                      ),
                      style: pillStyle,
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Alle Klanten', style: pillStyle),
                        ),
                        ..._beschikbareKlanten.map(
                          (s) => DropdownMenuItem<String?>(
                            value: s,
                            child: Text(
                              s,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: pillStyle,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedKlant = v),
                    ),
                  ),
                ),
              );
              Widget projectField = Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      isDense: true,
                      isExpanded: true,
                      value: _selectedProject,
                      hint: Text('Project', style: pillStyle),
                      dropdownColor: Colors.white,
                      icon: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: _navy.withValues(alpha: 0.5),
                      ),
                      style: pillStyle,
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Alle Projecten', style: pillStyle),
                        ),
                        ..._beschikbareProjecten.map(
                          (s) => DropdownMenuItem<String?>(
                            value: s,
                            child: Text(
                              s,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: pillStyle,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedProject = v),
                    ),
                  ),
                ),
              );
              final bool filtersActive =
                  _selectedKlant != null || _selectedProject != null;
              if (dense) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    klantField,
                    projectField,
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: filtersActive ? _clearFilters : null,
                        child: Text(
                          'Wissen',
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: klantField),
                  Expanded(child: projectField),
                  TextButton(
                    onPressed: filtersActive ? _clearFilters : null,
                    child: Text(
                      'Wissen',
                      style: GoogleFonts.lato(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: _pageBg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _navy),
        title: Text(
          'Mijn Agenda',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: _navy,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: _isLoading ? null : _loadAgenda,
            icon: Icon(Icons.refresh_rounded, color: cs.primary),
          ),
        ],
      ),
      body: SelectionArea(
        child: _isLoading
            ? const Center(child: CupertinoActivityIndicator(radius: 18))
            : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Agenda laden mislukt.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              color: _navy,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$_loadError',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w600,
                              color: _muted,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _loadAgenda,
                            child: Text(
                              'Opnieuw',
                              style: GoogleFonts.lato(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
              : Column(
                  children: [
                    _buildFiltersPanel(cs),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: DecoratedBox(
                        decoration: _softCardDecoration(),
                        child: TableCalendar<Map<String, dynamic>>(
                          firstDay: DateTime.utc(2022, 1, 1),
                          lastDay: DateTime.utc(2036, 12, 31),
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
                          onDaySelected: (selected, focused) {
                            setState(() {
                              _selectedDay = selected;
                              _focusedDay = focused;
                            });
                          },
                          onPageChanged: (f) {
                            setState(() => _focusedDay = f);
                          },
                          calendarFormat: _calendarFormat,
                          availableCalendarFormats: const {
                            CalendarFormat.month: 'Maand',
                            CalendarFormat.week: 'Week',
                          },
                          startingDayOfWeek: StartingDayOfWeek.monday,
                          onFormatChanged: (fmt) {
                            if (mounted) {
                              setState(() => _calendarFormat = fmt);
                            }
                          },
                          locale: 'nl_NL',
                          eventLoader: _eventsLoader,
                          headerStyle: HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: false,
                            titleTextFormatter: (d, locale) =>
                                DateFormat.yMMMM(locale ?? 'nl_NL').format(d),
                            titleTextStyle: GoogleFonts.lato(
                              color: _navy,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          calendarStyle: CalendarStyle(
                            todayDecoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            selectedDecoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                            ),
                            selectedTextStyle: GoogleFonts.lato(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                            weekendTextStyle: GoogleFonts.lato(
                              fontWeight: FontWeight.w700,
                              color: _navy.withValues(alpha: 0.7),
                            ),
                            defaultTextStyle:
                                GoogleFonts.lato(fontWeight: FontWeight.w700),
                          ),
                          calendarBuilders: CalendarBuilders(
                            markerBuilder: (context, day, evs) {
                              if (evs.isEmpty) return null;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: _dayList(cs)),
                  ],
                ),
      ),
    );
  }

  Widget _dayList(ColorScheme cs) {
    final day =
        _selectedDay != null ? _normalizeDate(_selectedDay!) : _normalizeDate(_focusedDay);
    final unfiltered = _tasksForDayUnfiltered(day);
    final list = _filteredTasksForSelectedDay;
    final bool filtersActive =
        _selectedKlant != null || _selectedProject != null;

    if (unfiltered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.local_cafe_rounded,
                size: 64,
                color: cs.primary.withValues(alpha: 0.55),
              ),
              const SizedBox(height: 16),
              Text(
                'Je bent vrij op deze dag. Geniet ervan!',
                textAlign: TextAlign.center,
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  height: 1.35,
                  color: _navy,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (list.isEmpty && filtersActive) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.filter_alt_off_rounded,
                size: 56,
                color: _muted.withValues(alpha: 0.75),
              ),
              const SizedBox(height: 16),
              Text(
                'Geen taken voor deze filters op deze dag.',
                textAlign: TextAlign.center,
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  height: 1.35,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _clearFilters,
                child: Text(
                  'Filters wissen',
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: list.length,
      separatorBuilder: (context, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final task = list[i];
        final accent = _accentVoor(task);
        final start = _hhmm(task['starttijd']);
        final eind = _hhmm(task['eindtijd']);
        final project = _t(task['project_naam']);
        final bedrijf = _t(task['bedrijfsnaam']);
        final adres = _t(task['adres']);
        final pill = _statusPill(task);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(_radiusCard),
            onTap: () => _openDetails(task),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_radiusCard),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 5,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(_radiusCard),
                          bottomLeft: Radius.circular(_radiusCard),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$start – $eind',
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      color: _navy,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (project.isNotEmpty)
                                    Text(
                                      project,
                                      style: GoogleFonts.lato(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: _navy,
                                      ),
                                    ),
                                  if (bedrijf.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      bedrijf,
                                      style: GoogleFonts.lato(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: const Color(0xFF475569),
                                      ),
                                    ),
                                  ],
                                  if (adres.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.place_rounded,
                                          size: 18,
                                          color: cs.primary,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            adres,
                                            style: GoogleFonts.lato(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              height: 1.35,
                                              color: _muted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.black.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    pill,
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      letterSpacing: 0.15,
                                      color: const Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
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
  }
}
