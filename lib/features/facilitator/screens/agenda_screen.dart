import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/models/user_role.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/supabase_client.dart';
import '../../../providers/user_provider.dart';
import '../widgets/opname_afspraak_form_sheet.dart';
import '../widgets/opname_edit_modal.dart';
import 'dks_project_dossier_screen.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';

/// Facilitator agenda from [app_facilitator_persoonlijke_agenda] (opname + DKS).
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  static const double _radius = 24;
  static const Color _muted = Color(0xFF64748B);
  static const Color _blue = Color(0xFF2563EB);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _orange = Color(0xFFFF6B35);

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  Map<DateTime, List<Map<String, dynamic>>> _groupedEvents = {};
  CalendarFormat _calendarFormat = CalendarFormat.month;

  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAgenda();
    });
  }

  bool _canAccess() {
    final u = context.read<UserProvider>();
    if (u.isGenerator) return true;
    if (u.role == UserRole.administrator || u.role == UserRole.facilitator) {
      return true;
    }
    return u.hasPermission('portal_facilitator');
  }

  /// Calendar keys must match [TableCalendar] day comparisons (date-only, UTC).
  DateTime _normalizeDate(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  String _t(dynamic v) => (v ?? '').toString().trim();

  /// Picks a calendar day from a view row (flexible column names).
  DateTime? _dayFromRow(Map<String, dynamic> r) {
    for (final k in const [
      'geplande_datum',
      'agenda_datum',
      'datum',
      'start_datum',
      'd',
    ]) {
      final v = r[k];
      if (v == null) {
        continue;
      }
      DateTime? parsed;
      if (v is DateTime) {
        parsed = v;
      } else {
        final s = v.toString().trim();
        if (s.isEmpty) {
          continue;
        }
        try {
          parsed = DateTime.parse(s);
        } catch (_) {
          parsed = DateTime.tryParse(s);
        }
      }
      if (parsed != null) {
        return _normalizeDate(parsed);
      }
    }
    return null;
  }

  String _timeFrom(
    Map<String, dynamic> r, {
    required List<String> keys,
  }) {
    for (final k in keys) {
      final s = _t(r[k]);
      if (s.isEmpty) continue;
      if (s.length >= 5 && s.contains(':')) {
        return s.substring(0, 5);
      }
      return s;
    }
    return '—';
  }

  String _timeStart(Map<String, dynamic> r) {
    return _timeFrom(
      r,
      keys: const [
        'tijdslot_start',
        'starttijd',
        'start_tijd',
        'begin_tijd',
        'tijd_van',
      ],
    );
  }

  String _timeEnd(Map<String, dynamic> r) {
    return _timeFrom(
      r,
      keys: const [
        'tijdslot_eind',
        'eindtijd',
        'eind_tijd',
        'einde_tijd',
        'tijd_tot',
      ],
    );
  }

  /// Uses [afspraak_type] from [app_facilitator_persoonlijke_agenda] — 'opname' | 'dks'.
  String _afspraakType(Map<String, dynamic> r) {
    final primary = _t(r['afspraak_type']).toLowerCase();
    if (primary == 'dks') {
      return 'dks';
    }
    if (primary == 'opname') {
      return 'opname';
    }
    for (final k in const ['type', 'soort']) {
      final s = _t(r[k]).toLowerCase();
      if (s == 'dks' || s.contains('dks')) {
        return 'dks';
      }
      if (s == 'opname' || s.contains('opname') || s.contains('sales')) {
        return 'opname';
      }
    }
    return 'opname';
  }

  String _titelOf(Map<String, dynamic> r) {
    for (final k in const [
      'titel',
      'project_naam',
      'bedrijfsnaam',
      'naam',
      'omschrijving',
    ]) {
      final s = _t(r[k]);
      if (s.isNotEmpty) {
        return s;
      }
    }
    return 'Afspraak';
  }

  String _extraInfoOf(Map<String, dynamic> r) {
    for (final k in const [
      'extra_info',
      'werk_regio',
      'regio',
    ]) {
      final s = _t(r[k]);
      if (s.isNotEmpty) {
        return s;
      }
    }
    return '—';
  }

  String _statusOf(Map<String, dynamic> r) {
    return _t(
      r['status'] ?? r['agenda_status'] ?? r['state'],
    );
  }

  int _timeSortKey(String s) {
    final p = s.split(':');
    if (p.length >= 2) {
      final h = int.tryParse(p[0]) ?? 0;
      final m = int.tryParse(p[1]) ?? 0;
      return h * 60 + m;
    }
    return 0;
  }

  /// Groups [raw] by calendar day; does not [setState].
  Map<DateTime, List<Map<String, dynamic>>> _buildGrouped(
    List<Map<String, dynamic>> raw,
  ) {
    final m = <DateTime, List<Map<String, dynamic>>>{};
    for (final r in raw) {
      final d = _dayFromRow(r);
      if (d == null) {
        continue;
      }
      m.putIfAbsent(d, () => []).add(r);
    }
    for (final e in m.entries) {
      e.value.sort(
        (a, b) => _timeSortKey(_timeStart(a)).compareTo(
          _timeSortKey(_timeStart(b)),
        ),
      );
    }
    return m;
  }

  Future<void> _loadAgenda() async {
    if (!_canAccess() || !mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Niet ingelogd.';
        });
      }
      return;
    }

    try {
      final res = await AppSupabase.client
          .from('app_facilitator_persoonlijke_agenda')
          .select()
          .or('toegewezen_aan_id.eq.${user.id},toegewezen_aan_id.is.null');
      if (!mounted) {
        return;
      }
      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _groupedEvents = _buildGrouped(list);
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _groupedEvents = {};
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _eventsForDay(DateTime day) {
    return _groupedEvents[_normalizeDate(day)] ?? const [];
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = _normalizeDate(date);
    return normalized.subtract(Duration(days: normalized.weekday - DateTime.monday));
  }

  String get _calendarViewMode {
    switch (_calendarFormat) {
      case CalendarFormat.month:
        return 'Maand';
      case CalendarFormat.week:
        return 'Week';
      default:
        return 'Maand';
    }
  }

  List<Map<String, dynamic>> _eventsForCurrentView() {
    final focused = _normalizeDate(_focusedDay);
    if (_calendarFormat == CalendarFormat.month) {
      final out = <Map<String, dynamic>>[];
      for (final e in _groupedEvents.entries) {
        final d = e.key;
        if (d.year == focused.year && d.month == focused.month) {
          out.addAll(e.value);
        }
      }
      return out;
    }
    if (_calendarFormat == CalendarFormat.week) {
      final start = _startOfWeek(_focusedDay);
      final end = start.add(const Duration(days: 6));
      final out = <Map<String, dynamic>>[];
      for (final e in _groupedEvents.entries) {
        final d = e.key;
        if (!d.isBefore(start) && !d.isAfter(end)) {
          out.addAll(e.value);
        }
      }
      return out;
    }
    return _eventsForDay(_selectedDay ?? focused);
  }

  Color _dotFor(Map<String, dynamic> r) {
    return _afspraakType(r) == 'dks' ? _amber : _blue;
  }

  void _openOpnameSheet() {
    OpnameAfspraakFormSheet.show(
      context,
      onSuccess: () async {
        if (mounted) {
          await _loadAgenda();
        }
      },
    );
  }

  String _adresOf(Map<String, dynamic> r) {
    for (final k in const [
      'adres',
      'adres_volledig',
    ]) {
      final s = _t(r[k]);
      if (s.isNotEmpty) {
        return s;
      }
    }
    return '';
  }

  void _onAgendaItemTap(Map<String, dynamic> item) {
    final t = item['afspraak_type']?.toString().toLowerCase();
    if (t == 'opname') {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SelectionArea(
          child: OpnameEditModal(
            afspraakId: (item['id'] ?? '').toString(),
            onSaved: () {
              if (mounted) {
                _loadAgenda();
              }
            },
          ),
        ),
      );
    } else if (item['afspraak_type'] == 'dks' ||
        item['afspraak_type']?.toString().toLowerCase() == 'dks') {
      final pid = item['project_id'];
      if (pid != null && pid.toString().trim().isNotEmpty) {
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => DksProjectDossierScreen(
              projectId: pid.toString(),
              projectNaam: _titelOf(item).isNotEmpty ? _titelOf(item) : 'Project',
            ),
          ),
        ).then((_) {
          if (mounted) {
            _loadAgenda();
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Fout: Geen project_id gevonden voor deze DKS ronde.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final onBody = textTheme.bodyLarge?.color;
    final onMuted = textTheme.bodyMedium?.color ??
        textTheme.bodyLarge?.color?.withValues(alpha: 0.6);
    if (!_canAccess()) {
      return Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text('Mijn Agenda',
              style: GoogleFonts.lato(fontWeight: FontWeight.w900)),
        ),
        body: SelectionArea(
          child: Center(
            child: Text(
              'Geen toegang tot deze agenda.',
              style: GoogleFonts.lato(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }

    _selectedDay ??= _normalizeDate(_focusedDay);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        foregroundColor: theme.appBarTheme.foregroundColor,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: theme.iconTheme.color),
        title: Text(
          'Mijn Agenda',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: onBody,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _loading ? null : _loadAgenda,
          ),
        ],
      ),
      body: SelectionArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator(radius: 16))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Laden mislukt: $_error',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: TableCalendar<Map<String, dynamic>>(
                          firstDay: DateTime(2022, 1, 1),
                          lastDay: DateTime(2035, 12, 31),
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (d) =>
                              isSameDay(_selectedDay, d),
                          onDaySelected: (s, f) {
                            setState(() {
                              _selectedDay = s;
                              _focusedDay = f;
                            });
                          },
                          onPageChanged: (f) {
                            setState(() {
                              _focusedDay = f;
                            });
                          },
                          calendarFormat: _calendarFormat,
                          availableCalendarFormats: const {
                            CalendarFormat.month: 'Maand',
                            CalendarFormat.week: 'Week',
                          },
                          onFormatChanged: (f) {
                            if (mounted) {
                              setState(() => _calendarFormat = f);
                            }
                          },
                          startingDayOfWeek: StartingDayOfWeek.monday,
                          eventLoader: _eventsForDay,
                          locale: 'nl_NL',
                          headerStyle: HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: true,
                            titleTextStyle: TextStyle(
                              color: onBody,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            leftChevronIcon: Icon(
                              Icons.chevron_left,
                              color: theme.iconTheme.color,
                            ),
                            rightChevronIcon: Icon(
                              Icons.chevron_right,
                              color: theme.iconTheme.color,
                            ),
                          ),
                          daysOfWeekStyle: DaysOfWeekStyle(
                            weekdayStyle: TextStyle(color: onBody),
                            weekendStyle: TextStyle(color: onMuted),
                          ),
                          calendarStyle: CalendarStyle(
                            defaultTextStyle: TextStyle(color: onBody),
                            weekendTextStyle: TextStyle(color: onMuted),
                            outsideTextStyle: TextStyle(
                              color: theme.dividerColor,
                            ),
                            todayDecoration: BoxDecoration(
                              color: _blue.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            selectedDecoration: const BoxDecoration(
                              color: _orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          calendarBuilders: CalendarBuilders(
                            markerBuilder: (context, day, evs) {
                              if (evs.isEmpty) {
                                return null;
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: evs
                                      .take(5)
                                      .map(
                                        (e) => Container(
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 1.5,
                                          ),
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: _dotFor(e),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                              child: Text(
                                'Alle opdrachten voor deze ${_calendarViewMode.toLowerCase()}',
                                style: GoogleFonts.lato(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Expanded(child: _buildDayList()),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 85),
        child: FloatingActionButton(
          onPressed: _openOpnameSheet,
          tooltip: 'Nieuwe opname afspraak',
          backgroundColor: _orange,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius / 2),
          ),
          child: const Icon(Icons.add, size: 32),
        ),
      ),
    );
  }

  Widget _buildDayList() {
    final list = List<Map<String, dynamic>>.from(_eventsForCurrentView());
    final selected = _selectedDay ?? _normalizeDate(_focusedDay);
    list.sort((a, b) {
      final aDay = _dayFromRow(a);
      final bDay = _dayFromRow(b);
      final aIsSelected = aDay != null && isSameDay(aDay, selected);
      final bIsSelected = bDay != null && isSameDay(bDay, selected);
      if (aIsSelected && !bIsSelected) return -1;
      if (!aIsSelected && bIsSelected) return 1;
      if (aDay == null && bDay == null) return 0;
      if (aDay == null) return 1;
      if (bDay == null) return -1;
      final byDate = aDay.compareTo(bDay);
      if (byDate != 0) return byDate;
      return _timeSortKey(_timeStart(a)).compareTo(_timeSortKey(_timeStart(b)));
    });

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Geen afspraken in deze periode.',
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(
              color: _muted,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: list.length + 1,
      separatorBuilder: (context, index) {
        if (index >= list.length - 1) return const SizedBox.shrink();
        return const SizedBox(height: 10);
      },
      itemBuilder: (context, i) {
        if (i >= list.length) {
          return const SizedBox(height: mobileNavBuffer);
        }
        final theme = Theme.of(context);
        final textTheme = theme.textTheme;
        final onBody = textTheme.bodyLarge?.color;
        final onMuted = textTheme.bodyMedium?.color ??
            textTheme.bodyLarge?.color?.withValues(alpha: 0.6);
        final e = list[i];
        final isDks = _afspraakType(e) == 'dks';
        final accent = isDks ? _amber : _blue;
        final rowDay = _dayFromRow(e);
        final isSelectedDay = rowDay != null && isSameDay(rowDay, selected);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _onAgendaItemTap(e),
            child: Container(
              decoration: BoxDecoration(
                color: isSelectedDay
                    ? theme.primaryColor.withValues(alpha: 0.10)
                    : theme.cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isSelectedDay
                      ? theme.primaryColor.withValues(alpha: 0.30)
                      : Colors.transparent,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
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
                          topLeft: Radius.circular(24),
                          bottomLeft: Radius.circular(24),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              isDks ? Icons.fact_check : Icons.campaign,
                              color: accent,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_timeStart(e)} - ${_timeEnd(e)}',
                                    style: GoogleFonts.lato(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: onBody,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isDks
                                        ? 'Kwaliteitscontrole (DKS)'
                                        : 'Sales Opname',
                                    style: GoogleFonts.lato(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.3,
                                      color: accent,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _titelOf(e),
                                    style: GoogleFonts.lato(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: onBody,
                                    ),
                                  ),
                                  if (_adresOf(e).isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.location_on_outlined,
                                          size: 16,
                                          color: onMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            _adresOf(e),
                                            style: GoogleFonts.lato(
                                              fontSize: 14,
                                              color: onMuted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      _pill(
                                        _extraInfoOf(e),
                                        const Color(0xFF6B7280),
                                      ),
                                      if (_statusOf(e).isNotEmpty) ...[
                                        _pill(
                                          _statusOf(e),
                                          const Color(0xFF94A3B8),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
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

  Widget _pill(String t, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        t,
        style: GoogleFonts.lato(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: c,
        ),
      ),
    );
  }
}
