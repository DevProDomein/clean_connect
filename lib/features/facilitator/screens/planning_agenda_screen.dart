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
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, List<dynamic>> _groupedTasks = {};

  bool _isLoading = true;
  Object? _loadError;

  List<Map<String, dynamic>> _inboxUitnodigingen = [];

  String? _currentUserId;

  String _searchQuery = '';
  String? _filterKlant;
  String? _filterProject;
  String? _filterRegio;

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
      out.addAll(_filterTaskList(entry.value));
    }
    return out;
  }

  Widget _agendaFilterDropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    required ColorScheme cs,
    required bool isDark,
  }) {
    return DropdownButtonFormField<String?>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        filled: true,
        fillColor: isDark ? const Color(0xFF1B1B23) : const Color(0xFFF5F5F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            'Alle',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
        ...options.map(
          (opt) => DropdownMenuItem<String?>(
            value: opt,
            child: Text(
              opt,
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _buildAgendaFilterContainer({
    required ColorScheme cs,
    required bool isDark,
  }) {
    final klantOptions = _agendaFilterOptions('bedrijfsnaam');
    final projectOptions = _agendaFilterOptions('project_naam');
    final regioOptions = _agendaFilterOptions('werk_regio');

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
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
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
          const SizedBox(height: 10),
          _agendaFilterDropdown(
            label: 'Klant',
            value: _filterKlant,
            options: klantOptions,
            cs: cs,
            isDark: isDark,
            onChanged: (v) => setState(() => _filterKlant = v),
          ),
          const SizedBox(height: 8),
          _agendaFilterDropdown(
            label: 'Project',
            value: _filterProject,
            options: projectOptions,
            cs: cs,
            isDark: isDark,
            onChanged: (v) => setState(() => _filterProject = v),
          ),
          const SizedBox(height: 8),
          _agendaFilterDropdown(
            label: 'Regio',
            value: _filterRegio,
            options: regioOptions,
            cs: cs,
            isDark: isDark,
            onChanged: (v) => setState(() => _filterRegio = v),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarDayCell({
    required DateTime date,
    required ColorScheme colorScheme,
    bool isSelected = false,
    bool isToday = false,
  }) {
    final isMonth = _calendarFormat == CalendarFormat.month;

    if (isMonth) {
      final bgColor = isSelected
          ? colorScheme.primary
          : (isToday ? colorScheme.primary.withValues(alpha: 0.14) : null);
      final textColor = isSelected ? Colors.white : colorScheme.onSurface;
      final borderColor = isToday && !isSelected
          ? colorScheme.primary.withValues(alpha: 0.35)
          : null;

      return Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: borderColor != null ? Border.all(color: borderColor) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '${date.day}',
          style: GoogleFonts.inter(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    final textColor = isSelected
        ? colorScheme.primary
        : (isToday ? colorScheme.primary : colorScheme.onSurface);

    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.12)
            : (isToday ? colorScheme.primary.withValues(alpha: 0.06) : null),
        border: isSelected
            ? Border.all(color: colorScheme.primary, width: 2)
            : (isToday
                ? Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.35),
                  )
                : null),
      ),
      alignment: Alignment.center,
      child: Text(
        '${date.day}',
        style: GoogleFonts.inter(
          color: textColor,
          fontSize: 14,
          fontWeight: isSelected || isToday ? FontWeight.w900 : FontWeight.w700,
        ),
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
    final neededOperators = _text(item['benodigde_operators']).isEmpty
        ? '1'
        : _text(item['benodigde_operators']);
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
    final filteredGrouped = _filteredGroupedTasks();
    final dayTasks = _tasksForSelectedDay();
    final periodTasks = _tasksForVisiblePeriod(
      focusedDay: _focusedDay,
      format: _calendarFormat,
      excludeDay: _selectedDay,
    );
    final isMonthView = _calendarFormat == CalendarFormat.month;

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
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (_selectedDay != null) {
                                    setState(() => _selectedDay = null);
                                  }
                                },
                                child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: _premiumAgendaCardDecoration(
                                  isDark: isDark,
                                ),
                                child: Column(
                                  children: [
                                    _buildAgendaFilterContainer(
                                      cs: cs,
                                      isDark: isDark,
                                    ),
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
                                          child:
                                              CupertinoSlidingSegmentedControl<CalendarFormat>(
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
                                                    color: _calendarFormat ==
                                                            CalendarFormat.month
                                                        ? Colors.white
                                                        : cs.onSurface.withValues(
                                                            alpha: 0.82,
                                                          ),
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
                                                    color: _calendarFormat ==
                                                            CalendarFormat.week
                                                        ? Colors.white
                                                        : cs.onSurface.withValues(
                                                            alpha: 0.82,
                                                          ),
                                                  ),
                                                ),
                                              ),
                                            },
                                            onValueChanged: (format) {
                                              if (format == null) return;
                                              setState(
                                                () => _calendarFormat = format,
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    TableCalendar<dynamic>(
                                      locale: 'nl_NL',
                                      firstDay: DateTime.now()
                                          .subtract(const Duration(days: 730)),
                                      lastDay: DateTime.now()
                                          .add(const Duration(days: 730)),
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
                                      startingDayOfWeek:
                                          StartingDayOfWeek.monday,
                                      eventLoader: (day) =>
                                          filteredGrouped[_normalizeDate(day)] ??
                                          const <dynamic>[],
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
                                      headerStyle: const HeaderStyle(
                                        formatButtonVisible: false,
                                      ),
                                      calendarStyle: CalendarStyle(
                                        outsideTextStyle: TextStyle(
                                          color:
                                              cs.onSurface.withValues(alpha: 0.34),
                                        ),
                                        markerDecoration: const BoxDecoration(
                                          color: Colors.transparent,
                                        ),
                                        todayDecoration: isMonthView
                                            ? BoxDecoration(
                                                shape: BoxShape.rectangle,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                color: Colors.transparent,
                                              )
                                            : const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.transparent,
                                              ),
                                        selectedDecoration: isMonthView
                                            ? BoxDecoration(
                                                shape: BoxShape.rectangle,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                color: cs.primary,
                                              )
                                            : const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.transparent,
                                              ),
                                      ),
                                      calendarBuilders:
                                          CalendarBuilders<dynamic>(
                                        defaultBuilder: (context, date, _) =>
                                            _buildCalendarDayCell(
                                          date: date,
                                          colorScheme: cs,
                                        ),
                                        selectedBuilder: (context, date, _) =>
                                            _buildCalendarDayCell(
                                          date: date,
                                          colorScheme: cs,
                                          isSelected: true,
                                        ),
                                        todayBuilder: (context, date, _) =>
                                            _buildCalendarDayCell(
                                          date: date,
                                          colorScheme: cs,
                                          isToday: true,
                                        ),
                                        markerBuilder: (context, date, events) {
                                          if (events.isEmpty) {
                                            return const SizedBox.shrink();
                                          }
                                          return Align(
                                            alignment: Alignment.bottomCenter,
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF101B35),
                                                borderRadius:
                                                    BorderRadius.circular(999),
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
                            ),
                            if (_selectedDay != null) ...[
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 3,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    14,
                                    14,
                                    10,
                                  ),
                                  decoration: _premiumAgendaCardDecoration(
                                    isDark: isDark,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Geplande taken op ${DateFormat('d MMMM yyyy', 'nl_NL').format(_selectedDay!)}',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 18,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Sluiten',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () => setState(
                                              () => _selectedDay = null,
                                            ),
                                            icon: const Icon(Icons.close),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      if (dayTasks.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: Text(
                                            'Geen taken gepland op deze dag.',
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w700,
                                              color: cs.onSurface.withValues(
                                                alpha: 0.65,
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        ListView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          itemCount: dayTasks.length,
                                          itemBuilder: (context, index) {
                                            final item =
                                                Map<String, dynamic>.from(
                                              dayTasks[index] as Map,
                                            );
                                            return _premiumAgendaTaskTile(
                                              item: item,
                                              cs: cs,
                                              isDark: isDark,
                                              onTap: () {
                                                final pers =
                                                    item['_persoonlijk_agenda'] ==
                                                        true;
                                                final maker =
                                                    _text(item['maker_id']);
                                                final uid =
                                                    _text(_currentUserId);
                                                if (pers &&
                                                    maker.isNotEmpty &&
                                                    maker != uid) {
                                                  _openPersoonlijkAlleenLezen(
                                                    item,
                                                  );
                                                  return;
                                                }
                                                _openAgendaDetailModal(item);
                                              },
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                decoration: _premiumAgendaCardDecoration(isDark: isDark),
                child: Builder(
                  builder: (context) {
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

                    final periodLabel = _calendarFormat == CalendarFormat.week
                        ? 'week'
                        : 'maand';

                    return Column(
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
                          emptyHint('Geen opdrachten in deze $periodLabel.')
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
                                onTap: () {
                                  final pers = item['_persoonlijk_agenda'] == true;
                                  final maker = _text(item['maker_id']);
                                  final uid = _text(_currentUserId);
                                  if (pers && maker.isNotEmpty && maker != uid) {
                                    _openPersoonlijkAlleenLezen(item);
                                    return;
                                  }
                                  _openAgendaDetailModal(item);
                                },
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
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
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _toelichting;
  final TextEditingController _toelichtingController = TextEditingController();
  bool _loadingToelichting = false;
  bool _savingToelichting = false;

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
              _block(context, 'Geplande datum', _geplandeDatumHuman ?? '—'),
              const SizedBox(height: 8),
              _block(context, 'Tijd', '$_geplandeStart – $_geplandeEind'),
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
