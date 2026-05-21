import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import 'manual_plan_modal.dart';

class PlanbordScreen extends StatefulWidget {
  const PlanbordScreen({super.key});

  @override
  State<PlanbordScreen> createState() => _PlanbordScreenState();
}

class _PlanbordScreenState extends State<PlanbordScreen> {
  // Smart Planner state
  Map<String, dynamic>? _selectedProject;
  List<dynamic> _smartProjects = [];
  bool _isLoadingSmartProjects = true;
  Object? _smartProjectsError;
  List<Map<String, dynamic>> _plannedOperators = <Map<String, dynamic>>[];
  bool _isLoadingPlannedOperators = false;
  Object? _plannedOperatorsError;

  List<dynamic> _projects = [];
  bool _isLoadingProjects = true;

  List<dynamic> _operatorResults = [];
  bool _isCalculating = false;
  bool _hasCalculated = false;
  int? _selectedResultIndex;
  final TextEditingController _hoursController = TextEditingController();
  double _shiftHours = 0.25;

  // Smart Planner UX extras (ONLY Smart Planner tab)
  String? _smartActiveOpdrachtId;
  int _smartNeededOperators = 1;
  bool _smartLoadingReedsIngepland = false;
  String? _smartReedsIngeplandStart; // "HH:mm"
  String? _smartSuggestedTijd; // "HH:mm"
  String? _handmatigeSmartTijd; // "HH:mm"

  // HARD availability check (DB-backed) for Smart Planner dropdown
  List<Map<String, dynamic>> _tijdOpties = const <Map<String, dynamic>>[];
  bool _isTijdenLaden = false;

  // Manual planning (timeline) state
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  String? _selectedManualProjectId;
  String _calendarViewMode = 'Maand';
  bool _showFilters = true;
  Map<DateTime, List<Map<String, dynamic>>> _groupedOpenTaken = {};
  Map<DateTime, List<Map<String, dynamic>>> _groupedGeplandeTaken = {};

  /// Ingeplande opdrachten voor de momenteel gekozen kalenderdag (query op `opdrachten`, status `ingepland`).
  List<Map<String, dynamic>> _reedsGeplandeTaken = [];
  bool _isLoadingReedsGeplande = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSmartProjects();
    _fetchProjects();
    _loadTasks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _showFilters = MediaQuery.of(context).size.width > 800;
      });
    });
  }

  @override
  void dispose() {
    _hoursController.dispose();
    super.dispose();
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _text(dynamic value) => (value ?? '').toString().trim();

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(_text(value)) ?? fallback;
  }

  double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(_text(value).replaceAll(',', '.')) ?? fallback;
  }

  /// Totaal uren voor planbord-kaarten (DB-kolommen, string-parse).
  double _totaalUrenVoorOpdrachtKaart(Map<String, dynamic> item) {
    return double.tryParse(
          item['benodigde_uren_totaal']?.toString() ??
              item['verwachte_uren_totaal']?.toString() ??
              '0',
        ) ??
        0.0;
  }

  /// Operators: eerst [benodigde_operators] uit DB; alleen bij 0 oude /3-fallback.
  int _safeOperatorsVoorOpdracht(Map<String, dynamic> item) {
    final dbOperators =
        int.tryParse(item['benodigde_operators']?.toString() ?? '0') ?? 0;
    final totaalUren = _totaalUrenVoorOpdrachtKaart(item);
    var safeOperators = dbOperators > 0
        ? dbOperators
        : (totaalUren > 0 ? (totaalUren / 3).ceil() : 1);
    if (safeOperators == 0) {
      safeOperators = 1;
    }
    return safeOperators;
  }

  bool _isTruthyDynamic(dynamic v) {
    if (v is bool) return v;
    final s = _text(v).toLowerCase();
    return s == 'true' || s == '1' || s == 'ja';
  }

  TimeOfDay? _timeFromRaw(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return null;
    final hhmm = raw.length >= 5 ? raw.substring(0, 5) : raw;
    final parts = hhmm.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  TimeOfDay _timeFromMinutes(int totalMinutes) {
    final m = ((totalMinutes % (24 * 60)) + (24 * 60)) % (24 * 60);
    return TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }

  String _timeToHuman(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int _timeToMinutes(String t) {
    final raw = t.trim();
    if (raw.isEmpty) return 0;
    final hhmm = raw.length >= 5 ? raw.substring(0, 5) : raw;
    final parts = hhmm.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (h * 60) + m;
  }

  Future<void> _berekenVeiligeTijden({
    required String operatorId,
    required List<String> datumsDb, // yyyy-MM-dd
    required double benodigdeUren,
    required String vensterStart, // "HH:mm"
    required String vensterEind, // "HH:mm"
  }) async {
    if (_isTijdenLaden) return;
    setState(() => _isTijdenLaden = true);
    try {
      final bestaandeAfspraken = await AppSupabase.client
          .from('opdracht_planning')
          .select('starttijd, eindtijd, geplande_datum')
          .eq('operator_id', operatorId)
          .inFilter('geplande_datum', datumsDb);

      final afsprakenByDate = <String, List<Map<String, dynamic>>>{};
      for (final raw in (bestaandeAfspraken as List)) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final d = _text(m['geplande_datum']);
        if (d.isEmpty) continue;
        afsprakenByDate.putIfAbsent(d, () => <Map<String, dynamic>>[]).add(m);
      }

      final int opdrachtMinuten = (benodigdeUren * 60).round();
      final int startVensterMin = _timeToMinutes(vensterStart);
      final int eindVensterMin = _timeToMinutes(vensterEind);

      final opties = <Map<String, dynamic>>[];
      final totaalDagen = datumsDb.length;

      for (
        int actueleMinuten = startVensterMin;
          (actueleMinuten + opdrachtMinuten) <= eindVensterMin;
        actueleMinuten += 15
      ) {
        final potentieelEindMinuten = actueleMinuten + opdrachtMinuten;
        var vrij = 0;
        for (final d in datumsDb) {
          final afspraken =
              afsprakenByDate[d] ?? const <Map<String, dynamic>>[];
          var overlap = false;
          for (final a in afspraken) {
            final stRaw = _text(a['starttijd']);
            final etRaw = _text(a['eindtijd']);
            if (stRaw.isEmpty || etRaw.isEmpty) continue;
            final aStart = _timeToMinutes(stRaw);
            final aEnd = _timeToMinutes(etRaw);
            // 15 min travel buffer around existing appointments.
            final geblokkeerdStart = aStart - 15;
            final geblokkeerdEind = aEnd + 15;
            if (actueleMinuten < geblokkeerdEind &&
                potentieelEindMinuten > geblokkeerdStart) {
              overlap = true;
              break;
            }
          }
          if (!overlap) vrij++;
        }

        if (vrij == 0) continue;

        final uren = actueleMinuten ~/ 60;
        final minuten = actueleMinuten % 60;
        final tijd =
            '${uren.toString().padLeft(2, '0')}:${minuten.toString().padLeft(2, '0')}';
        final status = vrij == totaalDagen ? 'volledig' : 'beperkt';
        opties.add({
          'tijd': tijd,
          'vrijeDagen': vrij,
          'totaalDagen': totaalDagen,
          'status': status,
        });
      }

      if (!mounted) return;
      setState(() {
        _tijdOpties = opties;
        final cur = (_handmatigeSmartTijd ?? '').trim();
        final tijden = opties
            .map((e) => _text(e['tijd']))
            .where((t) => t.isNotEmpty)
            .toList();
        if (tijden.isNotEmpty) {
          if (cur.isEmpty || !tijden.contains(cur)) {
            _handmatigeSmartTijd = tijden.first;
          }
        } else {
          _handmatigeSmartTijd = null;
        }
      });
    } catch (e) {
      debugPrint('Fout bij berekenen veilige tijden: $e');
      if (!mounted) return;
      setState(() {
        _tijdOpties = const <Map<String, dynamic>>[];
      });
    } finally {
      if (mounted) setState(() => _isTijdenLaden = false);
    }
  }

  List<dynamic> _asPlanningList(dynamic raw) {
    if (raw == null) return const <dynamic>[];
    if (raw is List) return raw;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        return decoded is List ? decoded : const <dynamic>[];
      } catch (_) {
        return const <dynamic>[];
      }
    }
    return const <dynamic>[];
  }

  Future<void> _loadSmartReedsIngepland(String opdrachtId) async {
    if (_smartLoadingReedsIngepland) return;
    setState(() {
      _smartLoadingReedsIngepland = true;
      _smartReedsIngeplandStart = null;
    });
    try {
      final res = await AppSupabase.client
          .from('opdracht_planning')
          .select('starttijd')
          .eq('opdracht_id', opdrachtId)
          .order('starttijd', ascending: true)
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      final raw = _text(res?['starttijd']);
      setState(() {
        _smartReedsIngeplandStart = raw.isEmpty
            ? null
            : (raw.length >= 5 ? raw.substring(0, 5) : raw);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _smartReedsIngeplandStart = null);
    } finally {
      if (mounted) setState(() => _smartLoadingReedsIngepland = false);
    }
  }

  Future<void> _onSmartOperatorSelected(Map<String, dynamic> result) async {
    setState(() {
      _smartActiveOpdrachtId = null;
      _smartNeededOperators = 1;
      _smartReedsIngeplandStart = null;
      _smartSuggestedTijd = null;
      _handmatigeSmartTijd = null;
      _tijdOpties = const <Map<String, dynamic>>[];
    });

    final planning = _asPlanningList(result['voorgestelde_planning']);
    if (planning.isEmpty) return;
    final first = planning.first;
    if (first is! Map) return;
    final firstMap = Map<String, dynamic>.from(first);
    final opdrachtId = _text(firstMap['opdracht_id'] ?? firstMap['id']);
    if (opdrachtId.isEmpty) return;

    final needed = _asInt(firstMap['benodigde_operators'], fallback: 0);
    final neededFallback = needed > 0
        ? needed
        : _asInt(
            _selectedProject?['standaard_aantal_operators'] ??
                _selectedProject?['benodigde_operators'],
            fallback: 1,
          );

    final suggested =
        _timeFromRaw(firstMap['starttijd'] ?? firstMap['tijdslot_start']) ??
        _timeFromRaw(_selectedProject?['tijdslot_start']) ??
        const TimeOfDay(hour: 8, minute: 0);

    final windowStart =
        _timeFromRaw(_selectedProject?['tijdslot_start']) ??
        const TimeOfDay(hour: 8, minute: 0);
    final windowEnd =
        _timeFromRaw(_selectedProject?['tijdslot_eind']) ??
        const TimeOfDay(hour: 17, minute: 0);

    final urenPerShift =
        double.tryParse(_hoursController.text.trim().replaceAll(',', '.')) ??
            _shiftHours;

    if (!mounted) return;
    setState(() {
      _smartActiveOpdrachtId = opdrachtId;
      _smartNeededOperators = neededFallback;
      _smartSuggestedTijd = _timeToHuman(suggested);
      _handmatigeSmartTijd = _smartSuggestedTijd;
    });

    await _loadSmartReedsIngepland(opdrachtId);

    final datumsDb =
        planning
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map((m) => _text(m['geplande_datum']))
        .where((d) => d.isNotEmpty)
        .map((d) => d.contains('T') ? d.split('T').first : d)
        .toSet()
        .toList()
      ..sort();

    if (datumsDb.isNotEmpty && _text(result['operator_id']).isNotEmpty) {
      await _berekenVeiligeTijden(
        operatorId: _text(result['operator_id']),
        datumsDb: datumsDb,
        benodigdeUren: urenPerShift,
        vensterStart: _text(_selectedProject?['tijdslot_start']).isEmpty
            ? _timeToHuman(windowStart)
            : _text(_selectedProject?['tijdslot_start']).substring(0, 5),
        vensterEind: _text(_selectedProject?['tijdslot_eind']).isEmpty
            ? _timeToHuman(windowEnd)
            : _text(_selectedProject?['tijdslot_eind']).substring(0, 5),
      );
    }
  }

  double _availableWindowHours(Map<String, dynamic>? project) {
    if (project == null) return 0;
    final start = _timeFromRaw(project['tijdslot_start']);
    final end = _timeFromRaw(project['tijdslot_eind']);
    if (start == null || end == null) return 0;
    final startMinutes = (start.hour * 60) + start.minute;
    final endMinutes = (end.hour * 60) + end.minute;
    var diff = endMinutes - startMinutes;
    if (diff < 0) diff += 24 * 60;
    return diff / 60;
  }

  bool _hoursExceedSelectedWindow() {
    if (_shiftHours <= 0 || _selectedProject == null) return false;
    final maxHours = _availableWindowHours(_selectedProject);
    if (maxHours <= 0) return false;
    return _shiftHours > maxHours;
  }

  String formatHoursToText(num? hoursNum) {
    if (hoursNum == null) return '0 min';
    double hours = hoursNum.toDouble();
    int h = hours.floor();
    int m = ((hours - h) * 60).round();

    if (h > 0 && m > 0) return '$h uur en $m min';
    if (h > 0) return '$h uur';
    return '$m min';
  }

  Map<String, dynamic>? _projectJoin(Map<String, dynamic> task) {
    final joined = task['projecten'];
    if (joined is Map<String, dynamic>) return joined;
    if (joined is List && joined.isNotEmpty && joined.first is Map) {
      return Map<String, dynamic>.from(joined.first as Map);
    }
    return null;
  }

  String _projectName(Map<String, dynamic> task) {
    final joined = _projectJoin(task);
    final name = _text(joined?['project_naam']);
    return name.isEmpty ? 'Naamloos project' : name;
  }

  /// Embed `planning:opdracht_planning!huidige_planning_id` (+ list→eerste rij tolerantie).
  Map<String, dynamic>? _planningDetailsVanItem(Map<String, dynamic> item) {
    final raw = item['planning'] ?? item['planning_details'];
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  /// Alias voor sort/modal/tijden: zelfde object als `planning` / `planning_details` embed.
  Map<String, dynamic>? _huidigePlanningMap(Map<String, dynamic> item) =>
      _planningDetailsVanItem(item);

  /// Uitvoerder via embed `uitvoerder_info:gebruikers!huidige_operator_id`.
  String _extractIngeplandWeergaveNaam(Map<String, dynamic> item) {
    final uitvoerderData = item['uitvoerder_info'];
    if (uitvoerderData == null) {
      // ignore: avoid_print
      print(
        'WAARSCHUWING: uitvoerder_info is NULL voor opdracht: ${item['id']}',
      );
      // ignore: avoid_print
      print('Volledige data van dit item: $item');
    }

    final String vNaam = uitvoerderData?['voornaam']?.toString() ?? '';
    final String aNaam = uitvoerderData?['achternaam']?.toString() ?? '';
    final String volledigeNaam = '$vNaam $aNaam'.trim();
    final String weergaveNaam = volledigeNaam.isNotEmpty
        ? volledigeNaam
        : 'Onbekende uitvoerder';
    return weergaveNaam;
  }

  String _displayOpdrachtNummer(Map<String, dynamic> item) {
    final n = _text(item['opdrachtnummer']);
    if (n.isNotEmpty) return n;
    final ref = _text(item['referentie']);
    if (ref.isNotEmpty) return ref;
    final id = _text(item['id']);
    if (id.length >= 8) return id.substring(0, 8).toUpperCase();
    return id.isNotEmpty ? id : '—';
  }

  String _reedsGeplandeSortTime(Map<String, dynamic> item) {
    final plan = _huidigePlanningMap(item);
    if (plan != null && _text(plan['starttijd']).isNotEmpty) {
      return _timeLabel(plan['starttijd']);
    }
    return _timeLabel(item['tijdslot_start']);
  }

  List<Map<String, dynamic>> _sortReedsGeplande(
    List<Map<String, dynamic>> rows,
  ) {
    final sorted = [...rows]
      ..sort((a, b) {
        final dateCmp = _toDate(
          a['geplande_datum'],
        ).compareTo(_toDate(b['geplande_datum']));
        if (dateCmp != 0) return dateCmp;
        return _reedsGeplandeSortTime(a).compareTo(_reedsGeplandeSortTime(b));
      });
    return sorted;
  }

  DateTime get _manualSelectedDay =>
      _normalizeDate(_selectedDay ?? _focusedDay);

  List<Map<String, dynamic>> _getZichtbareOpenTaken() {
    final zichtbareTaken = <Map<String, dynamic>>[];

    if (_calendarViewMode == 'Maand') {
      _groupedOpenTaken.forEach((date, tasks) {
        if (date.year == _focusedDay.year && date.month == _focusedDay.month) {
          zichtbareTaken.addAll(tasks);
        }
      });
    } else if (_calendarViewMode == 'Week') {
      final offset = _focusedDay.weekday - 1;
      final startOfWeek = _focusedDay.subtract(Duration(days: offset));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      final startTrunc = DateTime(
        startOfWeek.year,
        startOfWeek.month,
        startOfWeek.day,
      );
      final endTrunc = DateTime(
        endOfWeek.year,
        endOfWeek.month,
        endOfWeek.day,
      );

      _groupedOpenTaken.forEach((date, tasks) {
        final checkDate = DateTime(date.year, date.month, date.day);
        if (!checkDate.isBefore(startTrunc) && !checkDate.isAfter(endTrunc)) {
          zichtbareTaken.addAll(tasks);
        }
      });
    } else {
      final selected = _selectedDay ?? _focusedDay;
      final truncSelected = DateTime(
        selected.year,
        selected.month,
        selected.day,
      );
      zichtbareTaken.addAll(
        _groupedOpenTaken[truncSelected] ?? const <Map<String, dynamic>>[],
      );
    }

    zichtbareTaken.sort((a, b) {
      final dateA =
          DateTime.tryParse(a['geplande_datum']?.toString() ?? '') ??
          DateTime.now();
      final dateB =
          DateTime.tryParse(b['geplande_datum']?.toString() ?? '') ??
          DateTime.now();
      return dateA.compareTo(dateB);
    });

    return zichtbareTaken;
  }

  String _openTakenLeegBericht() {
    switch (_calendarViewMode) {
      case 'Maand':
        return 'Geen openstaande opdrachten in deze maand.';
      case 'Week':
        return 'Geen openstaande opdrachten in deze week.';
      default:
        return 'Geen openstaande opdrachten op deze dag.';
    }
  }

  Future<void> _fetchProjects() async {
    setState(() {
      _isLoadingProjects = true;
    });

    try {
      final results = await AppSupabase.client
          .from('projecten')
          .select()
          .eq('status', 'actief')
          .order('project_naam', ascending: true);

      if (!mounted) return;
      setState(() => _projects = List<dynamic>.from(results as List));
    } catch (error) {
      if (!mounted) return;
      setState(() => _projects = <dynamic>[]);
    } finally {
      if (mounted) {
        setState(() => _isLoadingProjects = false);
      }
    }
  }

  Future<void> _fetchSmartProjects() async {
    setState(() {
      _isLoadingSmartProjects = true;
      _smartProjectsError = null;
    });

    try {
      final response = await Supabase.instance.client
          .from('app_smart_planner_projecten')
          .select()
          .gt('open_taken', 0);

      if (!mounted) return;
      setState(() => _smartProjects = List<dynamic>.from(response as List));
    } catch (error) {
      debugPrint('Smart planner projecten query failed: $error');
      if (!mounted) return;
      setState(() => _smartProjectsError = error);
    } finally {
      if (mounted) {
        setState(() => _isLoadingSmartProjects = false);
      }
    }
  }

  Future<void> _loadPlannedOperatorsForProject() async {
    final projectId = _text(_selectedProject?['project_id']);
    if (projectId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _plannedOperators = <Map<String, dynamic>>[];
        _plannedOperatorsError = null;
      });
      return;
    }

    setState(() {
      _isLoadingPlannedOperators = true;
      _plannedOperatorsError = null;
    });

    try {
      final result = await AppSupabase.client
          .from('app_smart_planner_geplande_operators')
          .select()
          .eq('project_id', projectId);

      if (!mounted) return;
      setState(() {
        _plannedOperators = (result as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _plannedOperators = <Map<String, dynamic>>[];
        _plannedOperatorsError = error;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingPlannedOperators = false);
      }
    }
  }

  void _onProjectSelected(String? projectId) {
    if (projectId == null || projectId.isEmpty) {
      setState(() {
        _selectedProject = null;
        _operatorResults = [];
        _selectedResultIndex = null;
        _hasCalculated = false;
        _plannedOperators = <Map<String, dynamic>>[];
        _plannedOperatorsError = null;
        _hoursController.clear();
      });
      return;
    }

    final project = _smartProjects
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .firstWhere(
          (p) =>
              _text(p['id']) == projectId ||
              _text(p['project_id']) == projectId,
          orElse: () => <String, dynamic>{},
        );
    if (project.isEmpty) return;

    final neededOperators = _asInt(
      project['standaard_aantal_operators'] ?? project['benodigde_operators'],
      fallback: 1,
    );
    final safeOperators = neededOperators <= 0 ? 1 : neededOperators;
    final totalHours = _asDouble(project['benodigde_uren_totaal'], fallback: 0);
    final standardPerShift = _asDouble(
      project['standaard_uren_per_shift'],
      fallback: 0,
    );
    final rawHours = standardPerShift > 0
        ? standardPerShift
        : totalHours > 0
            ? (totalHours / safeOperators)
            : _asDouble(project['basis_uren_per_opdracht'], fallback: 1);
    final perShiftHours = rawHours.clamp(0.25, 24.0);
    final normalizedProject = Map<String, dynamic>.from(project);
    normalizedProject['project_id'] = _text(project['project_id']).isNotEmpty
        ? _text(project['project_id'])
        : _text(project['id']);

    setState(() {
      _selectedProject = normalizedProject;
      _operatorResults = [];
      _selectedResultIndex = null;
      _hasCalculated = false;
      _shiftHours = perShiftHours;
      _hoursController.text = perShiftHours.toStringAsFixed(2);
    });
    _loadPlannedOperatorsForProject();
  }

  Future<void> _runSmartPlanning() async {
    if (_selectedProject == null || _isCalculating) return;
    final selectedProject = _selectedProject!;
    final projectId = _text(selectedProject['project_id']).isNotEmpty
        ? selectedProject['project_id']
        : selectedProject['id'];
    final parsedHours =
        double.tryParse(_hoursController.text.replaceAll(',', '.')) ?? 0.0;
    if (_text(projectId).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Project-ID ontbreekt, kan slimme planning niet starten.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }
    if (parsedHours <= 0) {
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

    setState(() {
      _isCalculating = true;
      _selectedResultIndex = null;
    });

    try {
      final response = await AppSupabase.client.rpc(
        'bereken_slimme_planning',
        params: {'p_project_id': projectId, 'p_uren_per_shift': parsedHours},
      );
      debugPrint('RPC SUCCESS: $response');

      if (!mounted) return;
      final rows = List<dynamic>.from((response as List?) ?? const []);
      setState(() {
        _operatorResults = rows;
        _hasCalculated = true;
      });
    } catch (e) {
      debugPrint('RPC ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Slim plannen mislukt: $e',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCalculating = false);
    }
  }

  Future<void> _confirmBooking(Map<String, dynamic> result) async {
    final name = _text(result['naam']).isEmpty
        ? 'deze operator'
        : _text(result['naam']);
    final available = _asInt(result['beschikbare_beurten']);

    final shouldConfirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return SelectionArea(
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              'Definitief inplannen?',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
            ),
            content: Text(
              'Wilt u $name definitief inplannen op alle $available mogelijke opdrachten?',
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: Text(
                  'Bevestigen',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (shouldConfirm != true) return;

    try {
      await AppSupabase.client.rpc(
        'bevestig_slimme_planning',
        params: {
          'p_operator_id': result['operator_id'],
          'p_planning_json': result['voorgestelde_planning'],
        },
      );

      try {
        final opdrachtenLijst = _asPlanningList(
          result['voorgestelde_planning'],
        );
        var datumString = 'binnenkort';
        if (opdrachtenLijst.isNotEmpty && opdrachtenLijst.first is Map) {
          final eerste = Map<String, dynamic>.from(
            opdrachtenLijst.first as Map,
          );
          final raw = _text(eerste['geplande_datum']);
          if (raw.isNotEmpty) {
            datumString = raw.contains('T') ? raw.split('T').first : raw;
          }
        }
        await AppSupabase.client.functions.invoke(
          'send-push-notification',
          body: {
            'operator_id': _text(result['operator_id']),
            'aantal': opdrachtenLijst.length,
            'datum_string': datumString,
          },
        );
      } catch (e) {
        // ignore: avoid_print
        print('Kon pushmelding niet versturen: $e');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E8E3E),
          content: Text(
            'Reeks succesvol ingepland!',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
      setState(() {
        _selectedProject = null;
        _operatorResults = [];
        _selectedResultIndex = null;
        _hasCalculated = false;
        _plannedOperators = <Map<String, dynamic>>[];
        _plannedOperatorsError = null;
      });
      setState(() {});
      await _fetchSmartProjects();
      await _fetchProjects();
      await _loadTasks();
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

  /// Eindtijd-string (HH:mm:ss) voor Supabase, uit start HH:mm + duur in minuten.
  String _berekenEindTijd(String definitieveStartTijd, int durationMinutes) {
    final startMin = _timeToMinutes(definitieveStartTijd);
    final end = _timeFromMinutes(startMin + durationMinutes);
    return '${_timeToHuman(end)}:00';
  }

  /// Bouwt `voorgestelde_planning` voor RPC [bevestig_slimme_planning]: dropdown
  /// [\_handmatigeSmartTijd] gaat vóór de engine-suggestie; geen overlap-correctie.
  void _submitSmartPlannerBooking(Map<String, dynamic> selectedResult) {
    if (_handmatigeSmartTijd == null || _tijdOpties.isEmpty) {
      return;
    }
    final voorgesteldeTijdVanEngine = (_smartSuggestedTijd ?? '').trim();
    final manual = (_handmatigeSmartTijd ?? '').trim();
    final definitieveStartTijd = manual.isNotEmpty
        ? manual
        : voorgesteldeTijdVanEngine;

    final rawPlanning = selectedResult['voorgestelde_planning'];
    final planning = _asPlanningList(rawPlanning);

    if (definitieveStartTijd.isEmpty ||
        planning.isEmpty ||
        _smartActiveOpdrachtId == null) {
      _confirmBooking(selectedResult);
      return;
    }

    final hours =
        double.tryParse(_hoursController.text.trim().replaceAll(',', '.')) ??
        _shiftHours;
    final defaultDurMin = (hours * 60).round();

    final startHuman = definitieveStartTijd.length >= 5
        ? definitieveStartTijd.substring(0, 5)
        : definitieveStartTijd;

    final updatedList = planning
        .map((raw) {
          if (raw is! Map) return raw;
          final m = Map<String, dynamic>.from(raw);
          final itemHours = _asDouble(
            m['toegewezen_uren'] ??
                m['uren_per_shift'] ??
                m['duur_uren'] ??
                m['uren'],
            fallback: hours,
          );
          final durMin = itemHours > 0
              ? (itemHours * 60).round()
              : defaultDurMin;

          final rawDate = _text(m['geplande_datum']);
          final datumDb = rawDate.contains('T')
              ? rawDate.split('T').first
              : rawDate;
          if (datumDb.isEmpty) return null;

          m['starttijd'] = '$startHuman:00';
          m['eindtijd'] = _berekenEindTijd(startHuman, durMin);
          return m;
        })
        .whereType<Map>()
        .toList(growable: false);

    final patched = Map<String, dynamic>.from(selectedResult);
    patched['voorgestelde_planning'] = rawPlanning is String
        ? jsonEncode(updatedList)
        : updatedList;
    _confirmBooking(patched);
  }

  String _timeLabel(dynamic value, {String fallback = '--:--'}) {
    final raw = _text(value);
    if (raw.isEmpty) return fallback;
    if (raw.length >= 5) return raw.substring(0, 5);
    return raw;
  }

  String _manualRegion(Map<String, dynamic> task) {
    final region = _text(task['werk_regio']);
    return region.isEmpty ? 'Geen regio' : region;
  }

  DateTime _toDate(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return DateTime.now();
    final head = raw.length >= 10 ? raw.substring(0, 10) : raw;
    try {
      return _normalizeDate(DateFormat('yyyy-MM-dd').parse(head));
    } catch (_) {
      final d = DateTime.tryParse(raw);
      return d != null ? _normalizeDate(d) : DateTime.now();
    }
  }

  void _manualAddCalendarMonths(int delta) {
    final d = _focusedDay;
    final targetFirst = DateTime(d.year, d.month + delta, 1);
    final dim = DateTime(targetFirst.year, targetFirst.month + 1, 0).day;
    final newDay = math.min(d.day, dim);
    setState(
      () => _focusedDay = DateTime(targetFirst.year, targetFirst.month, newDay),
    );
  }

  /// Pijl-navigatie in de handmatige kalender: stap hangt af van [_calendarViewMode].
  void _manualCalendarNavigateStep(int direction) {
    if (direction != -1 && direction != 1) return;
    switch (_calendarViewMode) {
      case 'Maand':
        _manualAddCalendarMonths(direction);
        break;
      case 'Week':
        final base = _selectedDay ?? _focusedDay;
        final n = _normalizeDate(base).add(Duration(days: direction * 7));
        setState(() {
          _selectedDay = n;
          _focusedDay = n;
        });
        _fetchReedsGeplandeTakenVoorDag(n);
        break;
      case 'Dag':
      default:
        final base = _selectedDay ?? _focusedDay;
        final n = _normalizeDate(base).add(Duration(days: direction));
        setState(() {
          _selectedDay = n;
          _focusedDay = n;
        });
        _fetchReedsGeplandeTakenVoorDag(n);
        break;
    }
  }

  ({int start, int end}) _manualOpenSlotMinutes(Map<String, dynamic> task) {
    final sh = _timeLabel(task['tijdslot_start'], fallback: '09:00');
    final eh = _timeLabel(task['tijdslot_eind'], fallback: '10:00');
    var sm = _timeToMinutes(sh);
    var em = _timeToMinutes(eh);
    if (em <= sm) em = sm + 60;
    return (start: sm, end: em);
  }

  ({int start, int end}) _manualPlannedSlotMinutes(Map<String, dynamic> item) {
    final plan = _planningDetailsVanItem(item);
    final sh = plan != null && _text(plan['starttijd']).isNotEmpty
        ? _timeLabel(plan['starttijd'])
        : _timeLabel(item['tijdslot_start'], fallback: '09:00');
    final eh = plan != null && _text(plan['eindtijd']).isNotEmpty
        ? _timeLabel(plan['eindtijd'])
        : _timeLabel(item['tijdslot_eind'], fallback: '10:00');
    var sm = _timeToMinutes(sh);
    var em = _timeToMinutes(eh);
    if (em <= sm) em = sm + 60;
    return (start: sm, end: em);
  }

  String _manualTimelineOpenTitle(Map<String, dynamic> task) {
    final project = _projectName(task);
    final company = _text(task['bedrijfsnaam']).isEmpty
        ? 'Onbekende klant'
        : _text(task['bedrijfsnaam']);
    return project.isNotEmpty && project != 'Naamloos project'
        ? project
        : company;
  }

  String _manualTimelinePlannedTitle(Map<String, dynamic> item) {
    final bedrijf = _text(item['bedrijfsnaam']).isEmpty
        ? 'Onbekende klant'
        : _text(item['bedrijfsnaam']);
    return bedrijf;
  }

  /// `*` incl. [benodigde_operators]; embeds voor planning/uitvoerder.
  static const String _reedsGeplandeSelect =
      '*,projecten(project_naam),uitvoerder_info:gebruikers!huidige_operator_id(id,voornaam,achternaam),planning:opdracht_planning!huidige_planning_id(starttijd,eindtijd)';

  Future<List<Map<String, dynamic>>> _fetchReedsGeplandeQueryVoorDag(
    DateTime day,
  ) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_normalizeDate(day));
    var q = AppSupabase.client
        .from('opdrachten')
        .select(_reedsGeplandeSelect)
        .eq('status', 'ingepland')
        .eq('geplande_datum', dateStr);
    if (_selectedManualProjectId != null &&
        _selectedManualProjectId!.isNotEmpty) {
      q = q.eq('project_id', _selectedManualProjectId!);
    }
    final response = await q.order('tijdslot_start', ascending: true);
    return (response as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((row) => _text(row['huidige_planning_id']).isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _fetchReedsGeplandeTakenVoorDag(DateTime day) async {
    if (!mounted) return;
    setState(() => _isLoadingReedsGeplande = true);
    try {
      final list = await _fetchReedsGeplandeQueryVoorDag(day);
      if (!mounted) return;
      setState(() {
        _reedsGeplandeTaken = _sortReedsGeplande(list);
        _isLoadingReedsGeplande = false;
      });
    } catch (e) {
      debugPrint('Planbord reeds ingeplande opdrachten (dag) mislukt: $e');
      if (!mounted) return;
      setState(() {
        _reedsGeplandeTaken = [];
        _isLoadingReedsGeplande = false;
      });
    }
  }

  Future<void> _opdrachtOpnieuwOpenen(Map<String, dynamic> dataObject) async {
    try {
      final opdrachtId =
          dataObject['opdracht_id']?.toString() ??
          dataObject['id']?.toString();

      if (opdrachtId == null || opdrachtId.trim().isEmpty) {
        throw Exception('Kan ID niet vinden in het object.');
      }

      await AppSupabase.client.rpc(
        'reset_opdracht_naar_open',
        params: {'p_opdracht_id': opdrachtId},
      );

      if (!mounted) return;

      Navigator.pop(context);
      await _loadTasks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fout bij openen: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadTasks() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      var openQuery = AppSupabase.client
          .from('opdrachten')
          .select(
            '*, '
            'benodigde_operators, benodigde_uren_totaal, verwachte_uren_totaal, '
            'toegewezen_uren_totaal, '
            'projecten(project_naam)',
          )
          .eq('status', 'open');

      if (_selectedManualProjectId != null &&
          _selectedManualProjectId!.isNotEmpty) {
        openQuery = openQuery.eq('project_id', _selectedManualProjectId!);
      }

      final openResponse = await openQuery.order(
        'geplande_datum',
        ascending: true,
      );
      final openList = (openResponse as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);

      final groupedOpen = <DateTime, List<Map<String, dynamic>>>{};
      for (final task in openList) {
        final dateRaw = _text(task['geplande_datum']);
        if (dateRaw.isEmpty) continue;
        final head = dateRaw.length >= 10 ? dateRaw.substring(0, 10) : dateRaw;
        DateTime? parsed;
        try {
          parsed = DateFormat('yyyy-MM-dd').parse(head);
        } catch (_) {
          parsed = DateTime.tryParse(dateRaw);
        }
        if (parsed == null) continue;
        final key = _normalizeDate(parsed);
        groupedOpen.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(task);
      }

      List<Map<String, dynamic>> ingeplandList = const [];
      try {
        var ingeplandQuery = AppSupabase.client
            .from('opdrachten')
            .select(_reedsGeplandeSelect)
            .eq('status', 'ingepland');

        if (_selectedManualProjectId != null &&
            _selectedManualProjectId!.isNotEmpty) {
          ingeplandQuery = ingeplandQuery.eq(
            'project_id',
            _selectedManualProjectId!,
          );
        }

        final ingeplandResponse = await ingeplandQuery.order(
          'geplande_datum',
          ascending: true,
        );
        ingeplandList = (ingeplandResponse as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((row) => _text(row['huidige_planning_id']).isNotEmpty)
            .toList(growable: false);
      } catch (e) {
        debugPrint('Planbord ingeplande opdrachten laden mislukt: $e');
        ingeplandList = const [];
      }

      final groupedPlanned = <DateTime, List<Map<String, dynamic>>>{};
      for (final row in ingeplandList) {
        final dateRaw = _text(row['geplande_datum']);
        if (dateRaw.isEmpty) continue;
        final head = dateRaw.length >= 10 ? dateRaw.substring(0, 10) : dateRaw;
        DateTime? parsed;
        try {
          parsed = DateFormat('yyyy-MM-dd').parse(head);
        } catch (_) {
          parsed = DateTime.tryParse(dateRaw);
        }
        if (parsed == null) continue;
        final key = _normalizeDate(parsed);
        groupedPlanned
            .putIfAbsent(key, () => <Map<String, dynamic>>[])
            .add(row);
      }

      List<Map<String, dynamic>> reedsVoorDag = const [];
      try {
        reedsVoorDag = await _fetchReedsGeplandeQueryVoorDag(
          _selectedDay ?? _focusedDay,
        );
      } catch (e) {
        debugPrint('Planbord reedsGeplande (geselecteerde dag) mislukt: $e');
        reedsVoorDag = const [];
      }

      if (!mounted) return;
      setState(() {
        _groupedOpenTaken = groupedOpen;
        _groupedGeplandeTaken = groupedPlanned;
        _reedsGeplandeTaken = _sortReedsGeplande(reedsVoorDag);
        _isLoadingReedsGeplande = false;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Planbord _loadTasks failed: $error');
      if (!mounted) return;
      setState(() {
        _groupedOpenTaken = {};
        _groupedGeplandeTaken = {};
        _reedsGeplandeTaken = [];
        _isLoadingReedsGeplande = false;
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic>? _opdrachtMapUitPlanbordState(String opdrachtId) {
    for (final tasks in _groupedOpenTaken.values) {
      for (final t in tasks) {
        if (_text(t['id']) == opdrachtId) {
          return t;
        }
      }
    }
    for (final tasks in _groupedGeplandeTaken.values) {
      for (final t in tasks) {
        if (_text(t['id']) == opdrachtId) {
          return t;
        }
      }
    }
    for (final t in _reedsGeplandeTaken) {
      if (_text(t['id']) == opdrachtId) {
        return t;
      }
    }
    return null;
  }

  Future<void> _openManualPlanModal(String opdrachtId) async {
    final item = _opdrachtMapUitPlanbordState(opdrachtId);
    final int dbOperators =
        int.tryParse(item?['benodigde_operators']?.toString() ?? '0') ?? 0;
    // ignore: avoid_print
    print('Uitlezen in UI - item dbOperators: $dbOperators');
    // ignore: avoid_print
    print(
      'Uitlezen in UI - raw benodigde_operators: ${item?['benodigde_operators']}',
    );

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          SelectionArea(child: ManualPlanModal(opdrachtId: opdrachtId)),
    );
    if (!mounted || result != true) return;
    await _fetchSmartProjects();
    await _fetchProjects();
    await _loadTasks();
    if (mounted) setState(() {});
  }

  Future<void> _openExtraOpdrachtModal() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SelectionArea(child: _ExtraOpdrachtModal()),
    );
    if (!mounted || ok != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Extra opdracht aangemaakt. Deze is nu zichtbaar in de Smart Planner en Handmatige lijst.',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
    );
    await _loadTasks();
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

  Border _resultBorder(
    String matchType, {
    bool selected = false,
    bool hasAnyFreeSlot = false,
  }) {
    if (selected) return Border.all(color: const Color(0xFF0C66FF), width: 2.8);
    if (hasAnyFreeSlot) return Border.all(color: Colors.green, width: 3);
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

  Widget _buildResultCard(Map<String, dynamic> result, {required int index}) {
    final matchType = _text(result['match_type']);
    final isSolid = matchType == 'perfect_green' || matchType == 'bad_red';
    final textColor = isSolid ? Colors.white : const Color(0xFF15141F);
    final conflicts = result['conflicten'] is List
        ? List<dynamic>.from(result['conflicten'] as List)
        : const [];
    final available = _asInt(result['beschikbare_beurten']);
    final total = _asInt(result['totale_beurten']);
    final name = _text(result['naam']).isEmpty
        ? 'Onbekende operator'
        : _text(result['naam']);
    final selected = _selectedResultIndex == index;

    final hasAnyFreeSlot = _tijdOpties.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.none,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: total <= 0
              ? null
              : () {
                  setState(() => _selectedResultIndex = index);
                  _onSmartOperatorSelected(result);
                },
          child: Container(
            decoration: BoxDecoration(
              color: _resultBackground(matchType),
              borderRadius: BorderRadius.circular(24),
              border: _resultBorder(
                matchType,
                selected: selected,
                hasAnyFreeSlot: hasAnyFreeSlot,
              ),
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
                mainAxisSize: MainAxisSize.min,
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
                          color: textColor.withValues(
                            alpha: isSolid ? 0.96 : 0.82,
                          ),
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
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
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
                                      color: textColor.withValues(
                                        alpha: isSolid ? 0.92 : 0.72,
                                      ),
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
                  if (selected) ...[
                    const SizedBox(height: 12),
                    if (_isTijdenLaden)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: LinearProgressIndicator(minHeight: 3),
                      )
                    else
                      Builder(
                        builder: (context) {
                          final opties = _tijdOpties;
                          final tijden = opties
                              .map((e) => _text(e['tijd']))
                              .where((t) => t.isNotEmpty)
                              .toList(growable: false);

                          return Padding(
                            padding: const EdgeInsets.only(
                              top: 16.0,
                              bottom: 24.0,
                            ),
                            child: DropdownButtonFormField<String>(
                              initialValue:
                                  (_handmatigeSmartTijd ?? '').trim().isEmpty
                                  ? null
                                  : _handmatigeSmartTijd,
                              dropdownColor: const Color(0xFFF2F2F7),
                              items: opties
                                  .map((opt) {
                          final tijd = _text(opt['tijd']);
                          final status = _text(opt['status']);
                          final vrije = _asInt(opt['vrijeDagen']);
                          final totaal = _asInt(opt['totaalDagen']);
                          final isBeperkt = status == 'beperkt';
                          final label = isBeperkt
                              ? '$tijd (Beperkt beschikbaar: $vrije/$totaal dagen)'
                              : '$tijd (Volledig beschikbaar)';
                          return DropdownMenuItem<String>(
                            value: tijd,
                            child: isBeperkt
                                ? Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 6,
                                                  ),
                                    decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                      border: Border.all(
                                                  color: Colors.orange
                                                      .withValues(alpha: 0.55),
                                      ),
                                    ),
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.normal,
                                        fontSize: 14.0,
                                      ),
                                    ),
                                  )
                                : Text(
                                    label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.normal,
                                      fontSize: 14.0,
                                    ),
                                  ),
                          );
                                  })
                                  .toList(growable: false),
                              onChanged: tijden.isEmpty
                                  ? null
                                  : (v) {
                                      final next = (v ?? '').trim();
                                      if (next.isEmpty) return;
                                      setState(
                                        () => _handmatigeSmartTijd = next,
                                      );
                                    },
                              decoration: InputDecoration(
                                labelText: 'Kies definitieve starttijd',
                                hintText: tijden.isEmpty
                                    ? 'Geen tijden beschikbaar voor deze operator'
                                    : null,
                                filled: true,
                                fillColor: const Color(0xFFF2F2F7),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          );
                        },
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

  Widget _buildSmartPlannerTab(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 800;
    final filteredResults = _operatorResults
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((row) {
          final matchType = _text(row['match_type']);
          final total = _asInt(row['totale_beurten']);
          final available = _asInt(row['beschikbare_beurten']);
          if (available <= 0) return false;
          if (matchType == 'bad_red' && total <= 0) return false;
          return true;
        })
        .toList(growable: false);

    final selectedResult =
        (_selectedResultIndex != null &&
            _selectedResultIndex! >= 0 &&
            _selectedResultIndex! < filteredResults.length)
        ? filteredResults[_selectedResultIndex!]
        : null;

    final showMultiOperatorWarning =
        _smartNeededOperators > 1 &&
        (_smartReedsIngeplandStart != null &&
            _smartReedsIngeplandStart!.isNotEmpty);

    final selectedProjectId = _text(_selectedProject?['project_id']).isNotEmpty
        ? _text(_selectedProject?['project_id'])
        : _text(_selectedProject?['id']);
    final visibleProjects = _smartProjects
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .where((project) => _asInt(project['open_taken']) > 0)
        .toList(growable: false);

    Widget buildLeftColumn() {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111019) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
        child: _isLoadingSmartProjects
            ? const Center(child: CircularProgressIndicator())
            : _smartProjectsError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Projecten laden mislukt: $_smartProjectsError',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: visibleProjects.length,
                    itemBuilder: (context, index) {
                  final project = Map<String, dynamic>.from(
                    visibleProjects[index],
                  );
                      final projectId = _text(project['project_id']).isNotEmpty
                          ? _text(project['project_id'])
                          : _text(project['id']);
                      final projectName = _text(project['project_naam']).isEmpty
                          ? 'Naamloos project'
                          : _text(project['project_naam']);
                      final region = _text(project['werk_regio']).isEmpty
                          ? 'Geen regio'
                          : _text(project['werk_regio']);
                      final openTaskCount = _asInt(project['open_taken']);
                      final totalTaskCount = _asInt(project['totaal_taken']);
                      final neededOperators = _asInt(
                    project['standaard_aantal_operators'] ??
                        project['benodigde_operators'],
                        fallback: 1,
                      );
                  final hasAssignedHours =
                      _asDouble(project['reeds_toegewezen_uren']) > 0;
                  final selected =
                      selectedProjectId.isNotEmpty &&
                          projectId.isNotEmpty &&
                          selectedProjectId == projectId;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                        onTap: projectId.isEmpty
                            ? null
                            : () => _onProjectSelected(projectId),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: selected ? cs.primaryContainer : cs.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: hasAssignedHours
                                      ? Colors.orange
                                      : selected
                                          ? cs.primary.withValues(alpha: 0.60)
                                          : cs.onSurface.withValues(alpha: 0.06),
                                  width: hasAssignedHours ? 2 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.12 : 0.03,
                                ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    projectName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    region,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface.withValues(alpha: 0.68),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Benodigde operators: $neededOperators',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface.withValues(alpha: 0.74),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '$openTaskCount open taken van de $totalTaskCount',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: cs.primary,
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

    Widget buildRightColumnDesktop() {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111019) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
        child: _selectedProject == null
            ? Center(
                child: Text(
                  'Selecteer een project in de lijst om de slimme planner te starten.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showMultiOperatorWarning) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(
                          alpha: isDark ? 0.18 : 0.14,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.orange.withValues(
                            alpha: isDark ? 0.35 : 0.30,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Let op: Er is al een operator ingepland voor deze opdracht '
                              '(Starttijd: ${_smartReedsIngeplandStart!}). '
                              'Probeer de nieuwe operator op dezelfde tijd te laten starten.',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface.withValues(alpha: 0.86),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    'Plan reeks voor ${_text(_selectedProject?['project_naam']).isEmpty ? 'project' : _text(_selectedProject?['project_naam'])}',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(
                                  alpha: 0.5,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: cs.onSurface.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Totaal benodigd',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.62,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          formatHoursToText(
                                            _asDouble(
                                              _selectedProject?['benodigde_uren_totaal'],
                                            ),
                                          ),
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Standaard per persoon',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.62,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          formatHoursToText(
                                            _asDouble(
                                              _selectedProject?['standaard_uren_per_shift'],
                                            ),
                                          ),
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Reeds toegewezen',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.62,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          formatHoursToText(
                                            _asDouble(
                                              _selectedProject?['reeds_toegewezen_uren'],
                                            ),
                                          ),
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Nog in te vullen',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.62,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          formatHoursToText(
                                            _asDouble(
                                              _selectedProject?['resterende_uren_per_beurt'],
                                            ),
                                          ),
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                            color: cs.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1B1B23)
                                    : const Color(0xFFF5F5F7),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: cs.onSurface.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _StepperCircleButton(
                                    icon: Icons.remove_rounded,
                                    onPressed: () {
                                      setState(() {
                                        _shiftHours = (_shiftHours - 0.25)
                                            .clamp(0.25, 24.0);
                                        _hoursController.text = _shiftHours
                                            .toStringAsFixed(2);
                                      });
                                    },
                                  ),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          'Uren per shift',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.68,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          formatHoursToText(_shiftHours),
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _StepperCircleButton(
                                    icon: Icons.add_rounded,
                                    onPressed: () {
                                      setState(() {
                                        _shiftHours = (_shiftHours + 0.25)
                                            .clamp(0.25, 24.0);
                                        _hoursController.text = _shiftHours
                                            .toStringAsFixed(2);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            if (_hoursExceedSelectedWindow())
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Waarschuwing: Het aantal uren past niet binnen het tijdsbestek van de klant '
                                  '(${_text(_selectedProject?['tijdslot_start'])} - ${_text(_selectedProject?['tijdslot_eind'])}).',
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFFCC2F2F),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(
                                  alpha: isDark ? 0.10 : 0.04,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: cs.onSurface.withValues(alpha: 0.07),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Huidige Bezetting',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_isLoadingPlannedOperators)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: LinearProgressIndicator(
                                        minHeight: 3,
                                      ),
                                    )
                                  else if (_plannedOperatorsError != null)
                                    Text(
                                      'Kon bezetting niet laden.',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFFCC2F2F),
                                      ),
                                    )
                                  else if (_plannedOperators.isEmpty)
                                    Text(
                                      'Nog geen operators ingepland.',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  else
                                    ListView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: _plannedOperators.length,
                                      itemBuilder: (context, index) {
                                        final operator =
                                            _plannedOperators[index];
                                        final filled = _asInt(
                                          operator['aantal_beurten_gevuld'],
                                        );
                                        final total = _asInt(
                                          _selectedProject?['totaal_taken'],
                                        );
                                        final name =
                                            _text(
                                              operator['operator_naam'],
                                            ).isEmpty
                                            ? 'Operator'
                                            : _text(operator['operator_naam']);
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.person,
                                                size: 16,
                                                color: cs.onSurface.withValues(
                                                  alpha: 0.74,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  '$filled van de $total gevuld door $name',
                                                  style: GoogleFonts.inter(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12.5,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Nog in te vullen: ${_asInt(_selectedProject?['open_taken'])} deeltaken.',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w800,
                                      color: cs.primary.withValues(alpha: 0.90),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isCalculating ? null : _runSmartPlanning,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isCalculating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  'Slim Inplannen',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isCalculating)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (!_hasCalculated)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Klik op "Slim Inplannen" om operator matches te berekenen.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  else if (filteredResults.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Geen plannerresultaten gevonden voor de huidige filters.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredResults.length,
                      itemBuilder: (context, index) {
                        return _buildResultCard(
                          filteredResults[index],
                          index: index,
                        );
                      },
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selectedResult == null
                          ? null
                          : () => _submitSmartPlannerBooking(selectedResult),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Definitief Inplannen',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
      );
    }

    Widget buildRightColumnMobile() {
      // On mobile we only show this column when a project is selected.
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111019) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _selectedProject = null),
              tooltip: 'Terug',
            ),
            const SizedBox(height: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                    Text(
                      'Plan reeks voor ${_text(_selectedProject?['project_naam']).isEmpty ? 'project' : _text(_selectedProject?['project_naam'])}',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cs.onSurface.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Totaal benodigd',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface.withValues(alpha: 0.62),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formatHoursToText(
                                    _asDouble(
                                      _selectedProject?['benodigde_uren_totaal'],
                                    ),
                                  ),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Standaard per persoon',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface.withValues(alpha: 0.62),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formatHoursToText(
                                    _asDouble(
                                      _selectedProject?['standaard_uren_per_shift'],
                                    ),
                                  ),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reeds toegewezen',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface.withValues(alpha: 0.62),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formatHoursToText(
                                    _asDouble(
                                      _selectedProject?['reeds_toegewezen_uren'],
                                    ),
                                  ),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Nog in te vullen',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface.withValues(alpha: 0.62),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formatHoursToText(
                                    _asDouble(
                                      _selectedProject?['resterende_uren_per_beurt'],
                                    ),
                                  ),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    color: cs.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1B1B23)
                            : const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cs.onSurface.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        children: [
                          _StepperCircleButton(
                            icon: Icons.remove_rounded,
                            onPressed: () {
                              setState(() {
                                _shiftHours = (_shiftHours - 0.25).clamp(
                                  0.25,
                                  24.0,
                                );
                                _hoursController.text = _shiftHours
                                    .toStringAsFixed(2);
                              });
                            },
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'Uren per shift',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface.withValues(alpha: 0.68),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formatHoursToText(_shiftHours),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _StepperCircleButton(
                            icon: Icons.add_rounded,
                            onPressed: () {
                              setState(() {
                                _shiftHours = (_shiftHours + 0.25).clamp(
                                  0.25,
                                  24.0,
                                );
                                _hoursController.text = _shiftHours
                                    .toStringAsFixed(2);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    if (_hoursExceedSelectedWindow())
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Waarschuwing: Het aantal uren past niet binnen het tijdsbestek van de klant '
                          '(${_text(_selectedProject?['tijdslot_start'])} - ${_text(_selectedProject?['tijdslot_eind'])}).',
                          style: GoogleFonts.inter(
                            color: const Color(0xFFCC2F2F),
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(
                          alpha: isDark ? 0.10 : 0.04,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: cs.onSurface.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Huidige Bezetting',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_isLoadingPlannedOperators)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: LinearProgressIndicator(minHeight: 3),
                            )
                          else if (_plannedOperatorsError != null)
                            Text(
                              'Kon bezetting niet laden.',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFCC2F2F),
                              ),
                            )
                          else if (_plannedOperators.isEmpty)
                            Text(
                              'Nog geen operators ingepland.',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _plannedOperators.length,
                              itemBuilder: (context, index) {
                                final operator = _plannedOperators[index];
                                final filled = _asInt(
                                  operator['aantal_beurten_gevuld'],
                                );
                                final total = _asInt(
                                  _selectedProject?['totaal_taken'],
                                );
                                final name =
                                    _text(operator['operator_naam']).isEmpty
                                    ? 'Operator'
                                    : _text(operator['operator_naam']);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person,
                                        size: 16,
                                        color: cs.onSurface.withValues(
                                          alpha: 0.74,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '$filled van de $total gevuld door $name',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 6),
                          Text(
                            'Nog in te vullen: ${_asInt(_selectedProject?['open_taken'])} deeltaken.',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              color: cs.primary.withValues(alpha: 0.90),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isCalculating ? null : _runSmartPlanning,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isCalculating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                'Slim Inplannen',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isCalculating)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (!_hasCalculated)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'Klik op "Slim Inplannen" om operator matches te berekenen.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    else if (filteredResults.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'Geen plannerresultaten gevonden voor de huidige filters.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredResults.length,
                        itemBuilder: (context, index) {
                          return _buildResultCard(
                            filteredResults[index],
                            index: index,
                          );
                        },
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: selectedResult == null
                            ? null
                            : () => _submitSmartPlannerBooking(selectedResult),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Definitief Inplannen',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: isMobile
                ? (_selectedProject == null
                      ? buildLeftColumn()
                      : buildRightColumnMobile())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      const gap = 14.0;
                      final leftW = (w - gap) / 3.0;
                      final rightW = w - gap - leftW;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: leftW,
                            child: buildLeftColumn(),
                          ),
                          const SizedBox(width: gap),
                          SizedBox(
                            width: rightW,
                            child: buildRightColumnDesktop(),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildManualOpenTaskCard(
    Map<String, dynamic> task,
    ColorScheme cs,
    bool isDark,
  ) {
    final opdrachtId = _text(task['id']);
    final project = _projectName(task);
    final company = _text(task['bedrijfsnaam']).isEmpty
        ? 'Onbekende klant'
        : _text(task['bedrijfsnaam']);
    final start = _timeLabel(task['tijdslot_start']);
    final end = _timeLabel(task['tijdslot_eind']);
    final date = _toDate(task['geplande_datum']);
    final totaalUrenKaart = _totaalUrenVoorOpdrachtKaart(task);
    final safeOperators = _safeOperatorsVoorOpdracht(task);
    final urenPerPersoon = totaalUrenKaart / safeOperators;
    final title = project.isNotEmpty ? project : company;
    final isSelectedDay = DateUtils.isSameDay(
      _selectedDay ?? _focusedDay,
      date,
    );
    final accent = Colors.blue.shade700;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: opdrachtId.isEmpty
              ? null
              : () => _openManualPlanModal(opdrachtId),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelectedDay
                  ? accent.withValues(alpha: isDark ? 0.14 : 0.06)
                  : isDark
                  ? const Color(0xFF171722)
                  : const Color(0xFFFDFDFE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelectedDay
                    ? accent.withValues(alpha: 0.35)
                    : cs.onSurface.withValues(alpha: 0.06),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.035),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        company,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.70),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              _formatTaakDatumTag(date),
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                color: accent,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$start - $end',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _manualRegion(task),
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface.withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Nodig: $safeOperators operators · '
                        'ca. ${formatHoursToText(urenPerPersoon)} per persoon',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          color: accent.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _geefKortingDialog(String opdrachtId) async {
    if (opdrachtId.trim().isEmpty) return;
    final ctrl = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dCtx) {
          return AlertDialog(
            title: Text(
              'Korting / crediteren',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
            ),
            content: TextFormField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Korting ex. btw (€)',
                hintText: 'Bijv. 25,50',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dCtx).pop(),
                child: const Text('Annuleren'),
              ),
              FilledButton(
                onPressed: () async {
                  final raw = ctrl.text.trim().replaceAll(',', '.');
                  final ingevuld = double.tryParse(raw) ?? 0.0;
                  try {
                    await AppSupabase.client.from('opdrachten').update({
                      'korting_bedrag': ingevuld,
                    }).eq('id', opdrachtId);
                    if (dCtx.mounted) Navigator.of(dCtx).pop();
                    if (!mounted) return;
                    await _loadTasks();
                    await _fetchReedsGeplandeTakenVoorDag(
                      _selectedDay ?? _focusedDay,
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: Text(
                          'Korting opgeslagen.',
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
                  }
                },
                child: const Text('Opslaan'),
              ),
            ],
          );
        },
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _openReedsGeplandeInfoModal(Map<String, dynamic> item) async {
    final opdrachtId = _text(item['id']);
    final meta = () {
      final o = item['opdracht'];
      if (o is Map) return Map<String, dynamic>.from(o);
      return Map<String, dynamic>.from(item);
    }();
    final isExtraWerk = _isTruthyDynamic(meta['is_buiten_abonnement']);
    final waardeEx = _asDouble(meta['opdracht_waarde_ex_btw']);
    final kortingEx = _asDouble(meta['korting_bedrag']);
    final bedrijf = _text(item['bedrijfsnaam']).isEmpty
        ? 'Onbekende klant'
        : _text(item['bedrijfsnaam']);
    final nr = _displayOpdrachtNummer(item);
    final datum = _toDate(item['geplande_datum']);
    final plan = _planningDetailsVanItem(item);
    final start = _timeLabel(plan?['starttijd']);
    final end = _timeLabel(plan?['eindtijd']);
    final adres = _text(item['uitvoer_adres_volledig']);
    final weergaveNaam = _extractIngeplandWeergaveNaam(item);
    final datumStr = DateFormat('EEEE d MMMM yyyy', 'nl_NL').format(datum);
    final tijdStr = '$start – $end';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final modalCs = Theme.of(ctx).colorScheme;
        final bottomInset =
            MediaQuery.paddingOf(ctx).bottom +
            MediaQuery.viewInsetsOf(ctx).bottom;
        final sheetBg = Theme.of(ctx).brightness == Brightness.dark
            ? const Color(0xFF171722)
            : Colors.white;

        Widget infoRow({
          required IconData icon,
          required String title,
          required String value,
        }) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: modalCs.primary.withValues(alpha: 0.92),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                          color: modalCs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value.isNotEmpty ? value : '—',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: modalCs.onSurface.withValues(alpha: 0.92),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return SelectionArea(
                    child: Padding(
            padding: EdgeInsets.only(top: mq.size.height * 0.12),
            child: DecoratedBox(
                              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: mq.size.height * 0.82),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(22, 10, 22, 14 + bottomInset),
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                              decoration: BoxDecoration(
                              color: modalCs.onSurface.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          bedrijf,
                                style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Opdrachtnr. $nr',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                                  fontWeight: FontWeight.w800,
                            color: modalCs.onSurface.withValues(alpha: 0.56),
                          ),
                        ),
                        const SizedBox(height: 22),
                        infoRow(
                          icon: Icons.place_outlined,
                          title: 'Adres',
                          value: adres.isNotEmpty ? adres : 'Onbekend',
                        ),
                        infoRow(
                          icon: Icons.calendar_today_rounded,
                          title: 'Datum',
                          value: datumStr,
                        ),
                        infoRow(
                          icon: Icons.schedule_rounded,
                          title: 'Tijd',
                          value: tijdStr,
                        ),
                        infoRow(
                          icon: Icons.badge_outlined,
                          title: 'Operator',
                          value: weergaveNaam,
                        ),
                        if (isExtraWerk) ...[
                          const Divider(height: 28),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.receipt_long,
                              color: Color(0xFF2E7D32),
                            ),
                            title: Text(
                              'Extra werk (facturabel)',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Waarde: €${waardeEx.toStringAsFixed(2)} ex. btw | '
                                'Korting toegepast: €${kortingEx.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            trailing: TextButton(
                              onPressed: opdrachtId.isEmpty
                                  ? null
                                  : () {
                                      Navigator.of(ctx).pop();
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (!mounted) return;
                                        _geefKortingDialog(opdrachtId);
                                      });
                                    },
                              child: const Text('Korting / crediteren'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: opdrachtId.isEmpty
                              ? null
                              : () => _opdrachtOpnieuwOpenen(item),
                          icon: const Icon(Icons.undo_rounded, size: 20),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            backgroundColor: modalCs.error,
                            foregroundColor: modalCs.onError,
                          ),
                          label: Text(
                            'Opdracht opnieuw openen',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                ),
              ],
            ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReedsGeplandeCard(
    Map<String, dynamic> item,
    ColorScheme cs,
    bool isDark,
  ) {
    final opdrachtId = _text(item['id']);
    final bedrijf = _text(item['bedrijfsnaam']).isEmpty
                                      ? 'Onbekende klant'
        : _text(item['bedrijfsnaam']);
    final projectLabel = _projectName(item);
    final planningDetails = _planningDetailsVanItem(item);
    final start = _timeLabel(planningDetails?['starttijd']);
    final end = _timeLabel(planningDetails?['eindtijd']);
    final date = _toDate(item['geplande_datum']);
    final isSelectedDay = DateUtils.isSameDay(
      _selectedDay ?? _focusedDay,
      date,
    );
    final accent = Colors.red.shade400;
    final weergaveNaam = _extractIngeplandWeergaveNaam(item);
    final totaalUrenKaart = _totaalUrenVoorOpdrachtKaart(item);
    final safeOperators = _safeOperatorsVoorOpdracht(item);
    final urenPerPersoon = totaalUrenKaart / safeOperators;

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
          onTap: opdrachtId.isEmpty
              ? null
              : () => _openReedsGeplandeInfoModal(item),
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: isSelectedDay
                  ? accent.withValues(alpha: isDark ? 0.14 : 0.06)
                                                : isDark
                                                    ? const Color(0xFF171722)
                                                    : const Color(0xFFFDFDFE),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: isSelectedDay
                    ? accent.withValues(alpha: 0.35)
                                                  : cs.onSurface.withValues(alpha: 0.06),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.035),
                                                blurRadius: 14,
                                                offset: const Offset(0, 6),
                                              ),
                                            ],
                                          ),
                                          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 6,
                                                height: 52,
                                                decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.90),
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                        bedrijf,
                                                      style: GoogleFonts.inter(
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.w900,
                          color: accent,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                        projectLabel,
                                                      style: GoogleFonts.inter(
                                                        fontWeight: FontWeight.w600,
                                                        color: cs.onSurface.withValues(alpha: 0.70),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Wrap(
                                                      spacing: 8,
                                                      runSpacing: 8,
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                          decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                                                            borderRadius: BorderRadius.circular(999),
                                                          ),
                                                          child: Text(
                                                            '$start - $end',
                                                            style: GoogleFonts.inter(
                                                              fontWeight: FontWeight.w800,
                                color: accent,
                                                            ),
                                                          ),
                                                        ),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: cs.onSurface.withValues(alpha: 0.06),
                                                            borderRadius: BorderRadius.circular(999),
                                                          ),
                                                          child: Text(
                              _manualRegion(item),
                                                            style: GoogleFonts.inter(
                                                              fontWeight: FontWeight.w700,
                                                              color: cs.onSurface.withValues(alpha: 0.75),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      DateFormat('d MMMM yyyy', 'nl_NL').format(date),
                                                      style: GoogleFonts.inter(
                                                        fontWeight: FontWeight.w700,
                                                        color: cs.onSurface.withValues(alpha: 0.70),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                      Text(
                        'Nodig: $safeOperators operators · '
                        'ca. ${formatHoursToText(urenPerPersoon)} per persoon',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          color: accent.withValues(alpha: 0.92),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 16,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Uitvoerder: $weergaveNaam',
                                                      style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface.withValues(alpha: 0.70),
                              ),
                                                      ),
                          ),
                        ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                color: cs.onSurface.withValues(alpha: 0.45),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
  }

  String _formatTaakDatumTag(DateTime d) {
    try {
      return DateFormat('E d MMM', 'nl_NL').format(d);
    } catch (_) {
      return DateFormat('E d MMM').format(d);
    }
  }

  Widget _manualSplitOpenColumn(
    ColorScheme cs,
    bool isDark,
    List<Map<String, dynamic>> weergaveLijst,
    String leegBericht,
  ) {
    final accent = Colors.blue.shade700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nog in te plannen (${weergaveLijst.length})',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: accent,
          ),
        ),
        const SizedBox(height: 10),
        if (weergaveLijst.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
            child: Text(
              leegBericht,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: weergaveLijst.length,
            itemBuilder: (context, index) => _buildManualOpenTaskCard(
              weergaveLijst[index],
              cs,
              isDark,
            ),
          ),
      ],
    );
  }

  Widget _manualSplitPlannedColumn(
    ColorScheme cs,
    bool isDark,
    List<Map<String, dynamic>> reedsGeplande,
    bool isLoadingReedsGeplande,
  ) {
    final accent = Colors.red.shade400;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ingepland (${reedsGeplande.length})',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: accent,
          ),
        ),
        const SizedBox(height: 10),
        if (isLoadingReedsGeplande)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (reedsGeplande.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
            child: Text(
              'Geen planningen voor deze dag',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: reedsGeplande.length,
            itemBuilder: (context, index) =>
                _buildReedsGeplandeCard(reedsGeplande[index], cs, isDark),
          ),
      ],
    );
  }

  Widget _buildManualPlanningTab(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 800;
    final weergaveLijst = _getZichtbareOpenTaken();
    final openLeegBericht = _openTakenLeegBericht();

    return SingleChildScrollView(
      child: Column(
        children: [
        if (isMobile)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton(
              onPressed: () => setState(() => _showFilters = !_showFilters),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _showFilters
                    ? 'Filters & Zoeken verbergen'
                    : 'Filters & Zoeken tonen',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: _showFilters
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          secondChild: const SizedBox.shrink(),
          firstChild: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF111019) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: cs.onSurface.withValues(alpha: 0.06),
                    ),
                  ),
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedManualProjectId,
                    decoration: InputDecoration(
                      labelText: isMobile ? 'Project' : 'Projectfilter',
                      labelStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1B1B23)
                          : const Color(0xFFF5F5F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'Alle projecten',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
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
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                    ],
                    onChanged: _isLoading
                        ? null
                        : (value) async {
                            setState(() => _selectedManualProjectId = value);
                            await _loadTasks();
                          },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _openExtraOpdrachtModal,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      '+ Extra Opdracht',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: <ButtonSegment<String>>[
                        ButtonSegment<String>(
                          value: 'Maand',
                          label: Text(
                            'Maand',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          icon: const Icon(
                            Icons.calendar_view_month_rounded,
                            size: 18,
                          ),
                        ),
                        ButtonSegment<String>(
                          value: 'Week',
                          label: Text(
                            'Week',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          icon: const Icon(Icons.view_week_rounded, size: 18),
                        ),
                        ButtonSegment<String>(
                          value: 'Dag',
                          label: Text(
                            'Dag',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          icon: const Icon(Icons.view_day_rounded, size: 18),
                        ),
                      ],
                      selected: <String>{_calendarViewMode},
                      onSelectionChanged: (Set<String> next) {
                        if (next.isEmpty) return;
                        setState(() => _calendarViewMode = next.first);
                      },
                      multiSelectionEnabled: false,
                      emptySelectionAllowed: false,
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: const Color(0xFF004A99),
                        selectedForegroundColor: Colors.white,
                        foregroundColor: cs.onSurface.withValues(alpha: 0.85),
                        side: BorderSide(
                          color: cs.onSurface.withValues(alpha: 0.12),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF12121A) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ManualPlannerInfiniteView(
              viewMode: _calendarViewMode,
              focusedDay: _focusedDay,
              selectedDay: _selectedDay,
              groupedOpenTaken: _groupedOpenTaken,
              groupedGeplandeTaken: _groupedGeplandeTaken,
              colorScheme: cs,
              isDark: isDark,
              normalizeDay: _normalizeDate,
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                _fetchReedsGeplandeTakenVoorDag(selectedDay);
              },
              onNavigateStep: _manualCalendarNavigateStep,
              onMonthStickyChanged: (monthFirst) {
                setState(() {
                  final dim = DateTime(
                    monthFirst.year,
                    monthFirst.month + 1,
                    0,
                  ).day;
                  _focusedDay = DateTime(
                    monthFirst.year,
                    monthFirst.month,
                    math.min(_focusedDay.day, dim),
                  );
                });
              },
              onZoomToDagFromMonth: (day) {
                setState(() {
                  _selectedDay = day;
                  _focusedDay = day;
                  _calendarViewMode = 'Dag';
                });
                _fetchReedsGeplandeTakenVoorDag(day);
              },
              openSlotMinutes: _manualOpenSlotMinutes,
              plannedSlotMinutes: _manualPlannedSlotMinutes,
              openBlockTitle: _manualTimelineOpenTitle,
              plannedBlockTitle: _manualTimelinePlannedTitle,
              plannedWorkerName: _extractIngeplandWeergaveNaam,
              onOpenTap: (task) {
                final id = _text(task['id']);
                if (id.isEmpty) return;
                _openManualPlanModal(id);
              },
              onPlannedTap: (task) {
                final id = _text(task['id']);
                if (id.isEmpty) return;
                _openManualPlanModal(id);
              },
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF12121A) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: _isLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agenda — ${DateFormat('EEEE d MMMM yyyy', 'nl_NL').format(_manualSelectedDay)}',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Kalender: ${_calendarViewMode.toLowerCase()} · Open (rood) versus ingepland (blauw) voor de geselecteerde dag',
                      style: GoogleFonts.lato(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isMobile)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _manualSplitOpenColumn(
                            cs,
                            isDark,
                            weergaveLijst,
                            openLeegBericht,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Divider(
                              height: 1,
                              color: cs.onSurface.withValues(alpha: 0.12),
                            ),
                          ),
                          _manualSplitPlannedColumn(
                            cs,
                            isDark,
                            _reedsGeplandeTaken,
                            _isLoadingReedsGeplande,
                          ),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _manualSplitOpenColumn(
                              cs,
                              isDark,
                              weergaveLijst,
                              openLeegBericht,
                            ),
                          ),
                          const SizedBox(width: 16),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: cs.onSurface.withValues(alpha: 0.12),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _manualSplitPlannedColumn(
                              cs,
                              isDark,
                              _reedsGeplandeTaken,
                              _isLoadingReedsGeplande,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 120),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

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
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Vernieuwen',
              onPressed:
                  (_isLoading ||
                      _isLoadingProjects ||
                      _isLoadingSmartProjects ||
                      _isCalculating)
                  ? null
                  : () async {
                      await _fetchSmartProjects();
                      await _fetchProjects();
                      await _loadTasks();
                    },
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SelectionArea(
          child: Column(
            children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: isDark ? 0.08 : 0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(6),
                child: TabBar(
                  indicator: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: cs.onSurface.withValues(alpha: 0.70),
                  labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w900),
                  tabs: const [
                    Tab(text: 'Smart Planner'),
                    Tab(text: 'Handmatig Plannen'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildSmartPlannerTab(isDark),
                  _buildManualPlanningTab(isDark),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Handmatige planner: `infinite_calendar_view` — compacte maand + lane week/dag.
class ManualPlannerInfiniteView extends StatefulWidget {
  const ManualPlannerInfiniteView({
    super.key,
    required this.viewMode,
    required this.focusedDay,
    required this.selectedDay,
    required this.groupedOpenTaken,
    required this.groupedGeplandeTaken,
    required this.colorScheme,
    required this.isDark,
    required this.normalizeDay,
    required this.onDaySelected,

    /// Pijl-links = -1, pijl-rechts = +1; parent past stap toe (maand/week/dag).
    required this.onNavigateStep,
    required this.onMonthStickyChanged,
    required this.onZoomToDagFromMonth,
    required this.openSlotMinutes,
    required this.plannedSlotMinutes,
    required this.openBlockTitle,
    required this.plannedBlockTitle,
    required this.plannedWorkerName,
    required this.onOpenTap,
    required this.onPlannedTap,
  });

  final String viewMode;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final Map<DateTime, List<Map<String, dynamic>>> groupedOpenTaken;
  final Map<DateTime, List<Map<String, dynamic>>> groupedGeplandeTaken;
  final ColorScheme colorScheme;
  final bool isDark;
  final DateTime Function(DateTime) normalizeDay;
  final void Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final void Function(int direction) onNavigateStep;
  final void Function(DateTime monthFirstDaySticky) onMonthStickyChanged;
  final void Function(DateTime day) onZoomToDagFromMonth;
  final ({int start, int end}) Function(Map<String, dynamic>) openSlotMinutes;
  final ({int start, int end}) Function(Map<String, dynamic>)
  plannedSlotMinutes;
  final String Function(Map<String, dynamic>) openBlockTitle;
  final String Function(Map<String, dynamic>) plannedBlockTitle;
  final String Function(Map<String, dynamic>) plannedWorkerName;
  final void Function(Map<String, dynamic>) onOpenTap;
  final void Function(Map<String, dynamic>) onPlannedTap;

  @override
  State<ManualPlannerInfiniteView> createState() =>
      _ManualPlannerInfiniteViewState();
}

class _ManualPlannerInfiniteViewState extends State<ManualPlannerInfiniteView> {
  static const Object _openKind = Object();
  static const Object _plannedKind = Object();

  late final EventsController _controller = EventsController();
  final GlobalKey<EventsMonthsState> _monthsKey = GlobalKey();

  DateTime _norm(DateTime d) => widget.normalizeDay(d);

  DateTime _mondayOf(DateTime day) {
    final n = _norm(day);
    return n.subtract(Duration(days: (n.weekday - DateTime.monday + 7) % 7));
  }

  @override
  void initState() {
    super.initState();
    _applyMonthEventFilter();
    _pushEventsFromMaps();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ManualPlannerInfiniteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewMode != widget.viewMode) {
      _applyMonthEventFilter();
    }
    final mapsChanged =
        !identical(oldWidget.groupedOpenTaken, widget.groupedOpenTaken) ||
        !identical(oldWidget.groupedGeplandeTaken, widget.groupedGeplandeTaken);
    if (mapsChanged ||
        oldWidget.viewMode != widget.viewMode ||
        oldWidget.focusedDay != widget.focusedDay) {
      _pushEventsFromMaps();
    }
    if (widget.viewMode == 'Maand') {
      if (oldWidget.focusedDay.year != widget.focusedDay.year ||
          oldWidget.focusedDay.month != widget.focusedDay.month) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _monthsKey.currentState?.jumpToDate(widget.focusedDay);
        });
      }
    }
  }

  void _applyMonthEventFilter() {
    if (widget.viewMode == 'Maand') {
      _controller.updateDayEventsFilter(newFilter: (_, _) => <Event>[]);
    } else {
      _controller.updateDayEventsFilter(newFilter: (_, list) => list);
    }
  }

  void _pushEventsFromMaps() {
    _controller.updateCalendarData((calendar) {
      calendar.clearAll();
      final list = <Event>[];
      widget.groupedOpenTaken.forEach((day, rows) {
        for (final task in rows) {
          final slot = widget.openSlotMinutes(task);
          final start = DateTime(
            day.year,
            day.month,
            day.day,
          ).add(Duration(minutes: slot.start));
          var end = DateTime(
            day.year,
            day.month,
            day.day,
          ).add(Duration(minutes: slot.end));
          if (!end.isAfter(start)) {
            end = start.add(const Duration(minutes: 60));
          }
          list.add(
            Event(
              columnIndex: 0,
              startTime: start,
              endTime: end,
              title: widget.openBlockTitle(task),
              color: Colors.red.shade700,
              textColor: Colors.white,
              data: task,
              eventType: _openKind,
            ),
          );
        }
      });
      widget.groupedGeplandeTaken.forEach((day, rows) {
        for (final item in rows) {
          final slot = widget.plannedSlotMinutes(item);
          final start = DateTime(
            day.year,
            day.month,
            day.day,
          ).add(Duration(minutes: slot.start));
          var end = DateTime(
            day.year,
            day.month,
            day.day,
          ).add(Duration(minutes: slot.end));
          if (!end.isAfter(start)) {
            end = start.add(const Duration(minutes: 60));
          }
          final worker = widget.plannedWorkerName(item);
          list.add(
            Event(
              columnIndex: 1,
              startTime: start,
              endTime: end,
              title: widget.plannedBlockTitle(item),
              description: worker.isNotEmpty ? worker : null,
              color: Colors.blue.shade700,
              textColor: Colors.white,
              data: item,
              eventType: _plannedKind,
            ),
          );
        }
      });
      calendar.addEvents(list);
    });
  }

  DateTime _plannerAnchor() {
    final sel = widget.selectedDay ?? widget.focusedDay;
    if (widget.viewMode == 'Week') {
      return _mondayOf(sel);
    }
    return _norm(sel);
  }

  double _hourHeightPm() => 1.0;

  String _monthYearTitleNl() {
    final raw = DateFormat('MMMM yyyy', 'nl_NL').format(widget.focusedDay);
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  static const Color _cleanConnectBlue = Color(0xFF004A99);

  String _navigatorCenterTitle() {
    if (widget.viewMode == 'Week') {
      final m = _mondayOf(widget.selectedDay ?? widget.focusedDay);
      final end = m.add(const Duration(days: 6));
      return '${DateFormat('d MMM', 'nl_NL').format(m)} – ${DateFormat('d MMM yyyy', 'nl_NL').format(end)}';
    }
    return _monthYearTitleNl();
  }

  Widget _manualMonthNavigator() {
    final cs = widget.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => widget.onNavigateStep(-1),
            icon: Icon(
              Icons.chevron_left_rounded,
              color: cs.onSurface.withValues(alpha: 0.86),
            ),
          ),
          Expanded(
            child: Text(
              _navigatorCenterTitle(),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          IconButton(
            onPressed: () => widget.onNavigateStep(1),
            icon: Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurface.withValues(alpha: 0.86),
            ),
          ),
        ],
      ),
    );
  }

  Widget _manualMonthDayHeader(DateTime day) {
    final cs = widget.colorScheme;
    final norm = _norm(day);
    final openCount = widget.groupedOpenTaken[norm]?.length ?? 0;
    final planCount = widget.groupedGeplandeTaken[norm]?.length ?? 0;
    final inMonth =
        day.month == widget.focusedDay.month &&
        day.year == widget.focusedDay.year;
    final hasAny = openCount > 0 || planCount > 0;
    final red = Colors.red.shade700;
    final blue = Colors.blue.shade700;
    final subStyle = GoogleFonts.inter(
      fontWeight: FontWeight.w800,
      fontSize: 7.5,
      height: 1,
    );

    if (!hasAny) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Align(
          alignment: Alignment.topRight,
          child: Text(
            '${day.day}',
            style: GoogleFonts.inter(
              fontSize: inMonth ? 20 : 16,
              fontWeight: FontWeight.bold,
              color: cs.onSurface.withValues(alpha: inMonth ? 0.92 : 0.42),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              '${day.day}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: inMonth ? 12 : 10.5,
                fontWeight: FontWeight.w800,
                color: cs.onSurface.withValues(alpha: inMonth ? 0.88 : 0.45),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: '$openCount openstaand',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: openCount > 0
                          ? Colors.red.withValues(alpha: 0.05)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: red.withValues(
                          alpha: openCount > 0 ? 0.28 : 0.12,
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$openCount',
                          style: GoogleFonts.inter(
                            color: red,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'open',
                          style: subStyle.copyWith(
                            color: red.withValues(alpha: 0.88),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Tooltip(
                  message: '$planCount ingepland',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: planCount > 0
                          ? Colors.blue.withValues(alpha: 0.05)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: blue.withValues(
                          alpha: planCount > 0 ? 0.28 : 0.12,
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$planCount',
                          style: GoogleFonts.inter(
                            color: blue,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'gepl.',
                          style: subStyle.copyWith(
                            color: blue.withValues(alpha: 0.88),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _plannerTile(Event ev, double height, double width, double hpm) {
    final accent = identical(ev.eventType, _openKind)
        ? Colors.red.shade700
        : Colors.blue.shade700;
    final raw = ev.data;
    if (raw is! Map) return const SizedBox.shrink();
    final map = Map<String, dynamic>.from(raw);
    final maxLines = math.max(1, (height / 22).floor());
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (identical(ev.eventType, _openKind)) {
            widget.onOpenTap(map);
          } else {
            widget.onPlannedTap(map);
          }
        },
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: accent, width: 3)),
            color: accent.withValues(alpha: widget.isDark ? 0.22 : 0.13),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: widget.isDark ? 0.35 : 0.08,
                ),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  ev.title ?? '',
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: math.min(12, height / 8),
                    fontWeight: FontWeight.w900,
                    color: accent,
                    height: 1.05,
                  ),
                ),
              ),
              if ((ev.description ?? '').trim().isNotEmpty)
                Text(
                  ev.description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: widget.colorScheme.onSurface.withValues(alpha: 0.70),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonth(BuildContext context) {
    const nlWeekdayShort = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
    final weekParam = WeekParam(
      startOfWeekDay: 1,
      headerHeight: 34,
      weekHeight: 58,
      daySpacing: 3,
      weekDecoration: WeekParam.defaultWeekDecoration(context),
      headerDayBuilder: (weekdayIndex) {
        final i = (weekdayIndex - 1).clamp(0, 6);
        return Center(
          child: Text(
            nlWeekdayShort[i],
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        );
      },
    );

    final daysParam = DaysParam(
      headerHeight: 54,
      eventHeight: 200,
      eventSpacing: 0,
      spaceBetweenHeaderAndEvents: 0,
      dayHeaderBuilder: _manualMonthDayHeader,
      onDayTapUp: (d) => widget.onZoomToDagFromMonth(_norm(d)),
    );

    return Column(
      children: [
        _manualMonthNavigator(),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Theme(
              data: Theme.of(context).copyWith(
                appBarTheme: const AppBarTheme(
                  backgroundColor: _cleanConnectBlue,
                  foregroundColor: Colors.white,
                ),
              ),
              child: EventsMonths(
                key: _monthsKey,
                controller: _controller,
                initialMonth: DateTime(
                  widget.focusedDay.year,
                  widget.focusedDay.month,
                ),
                weekParam: weekParam,
                daysParam: daysParam,
                onMonthChange: widget.onMonthStickyChanged,
                pinchToZoomParam: PinchToZoom(pinchToZoom: false),
                verticalScrollPhysics: const NeverScrollableScrollPhysics(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlanner(BuildContext context, {required int days}) {
    final hpm = _hourHeightPm();
    const startMin = 6 * 60;
    const endMin = 22 * 60;
    final anchor = _plannerAnchor();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: EventsPlanner(
        key: ValueKey(
          'planner_${widget.viewMode}_${days}_${anchor.toIso8601String()}',
        ),
        controller: _controller,
        initialDate: anchor,
        daysShowed: days,
        heightPerMinute: hpm,
        pinchToZoomParam: PinchToZoomParameters(pinchToZoom: false),
        fullDayParam: const FullDayParam(fullDayEventsBarVisibility: false),
        initialVerticalScrollOffset: hpm * startMin,
        minVerticalScrollOffset: hpm * startMin,
        maxVerticalScrollOffset: hpm * endMin,
        dayEventsArranger: const SimpleEventArranger(),
        columnsParam: ColumnsParam(
          columns: 2,
          columnsLabels: const ['Open', 'Ingepland'],
          columnsWidthRatio: const [0.5, 0.5],
          columnsColors: [
            Colors.red.withValues(alpha: 0.05),
            Colors.blue.withValues(alpha: 0.05),
          ],
        ),
        daysHeaderParam: DaysHeaderParam(
          daysHeaderHeight: 44,
          daysHeaderColor: _cleanConnectBlue,
          daysHeaderForegroundColor: Colors.white,
          dayHeaderBuilder: (day, isToday) {
            return InkWell(
              onTap: () => widget.onDaySelected(_norm(day), _norm(day)),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat.E('nl_NL').format(day),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${day.day}',
                      style: GoogleFonts.inter(
                        fontWeight: isToday ? FontWeight.w900 : FontWeight.w800,
                        fontSize: isToday ? 18 : 17,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        dayParam: DayParam(dayEventBuilder: _plannerTile),
        offTimesParam: const OffTimesParam(
          offTimesAllDaysRanges: [
            OffTimeRange(
              TimeOfDay(hour: 0, minute: 0),
              TimeOfDay(hour: 6, minute: 0),
            ),
            OffTimeRange(
              TimeOfDay(hour: 22, minute: 0),
              TimeOfDay(hour: 24, minute: 0),
            ),
          ],
        ),
        timesIndicatorsParam: const TimesIndicatorsParam(
          timesIndicatorsWidth: 48,
        ),
        currentHourIndicatorParam: CurrentHourIndicatorParam(
          currentHourIndicatorColor: Colors.red,
          currentHourIndicatorLineVisibility: true,
          currentHourIndicatorHourVisibility: true,
        ),
        onDayChange: (firstShown) => widget.onDaySelected(
          widget.normalizeDay(firstShown),
          widget.normalizeDay(firstShown),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mqShort = MediaQuery.sizeOf(context).shortestSide;
    final plannerH = mqShort < 550 ? 600.0 : 520.0;

    Widget body;
    if (widget.viewMode == 'Maand') {
      body = SizedBox(height: 420, child: _buildMonth(context));
    } else if (widget.viewMode == 'Week') {
      body = SizedBox(height: plannerH, child: _buildPlanner(context, days: 7));
    } else {
      body = SizedBox(height: plannerH, child: _buildPlanner(context, days: 1));
    }

    final hint = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Tijdlijn 06:00 – 22:00 · kolom Open (rood) · kolom Ingepland (blauw) · rode lijn = nu',
          style: GoogleFonts.lato(
            fontSize: 11.6,
            fontWeight: FontWeight.w700,
            color: widget.colorScheme.onSurface.withValues(alpha: 0.62),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.viewMode != 'Maand') ...[
          _manualWeekDayNavigatorStrip(),
          const SizedBox(height: 8),
        ],
        body,
        if (widget.viewMode != 'Maand') hint,
      ],
    );
  }

  /// Week/Dag tonen ook maandkop + chevrons (consistent met maand-tab).
  Widget _manualWeekDayNavigatorStrip() {
    return _manualMonthNavigator();
  }
}

class _StepperCircleButton extends StatelessWidget {
  const _StepperCircleButton({required this.icon, required this.onPressed});

  final IconData icon;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.primary.withValues(alpha: 0.12),

      shape: const CircleBorder(),

      child: InkWell(
        customBorder: const CircleBorder(),

        onTap: onPressed,

        child: SizedBox(
          width: 34,

          height: 34,

          child: Icon(icon, size: 18, color: cs.primary),
        ),
      ),
    );
  }
}

class _ExtraOpdrachtModal extends StatefulWidget {
  const _ExtraOpdrachtModal();

  @override
  State<_ExtraOpdrachtModal> createState() => _ExtraOpdrachtModalState();
}

class _ExtraOpdrachtModalState extends State<_ExtraOpdrachtModal> {
  bool _loadingProjects = true;

  bool _saving = false;

  Object? _error;

  List<Map<String, dynamic>> _projects = const [];

  Map<String, dynamic>? _selectedProject;

  String? _geselecteerdeProjectNaam;

  int aantalOperators = 1;

  double _benodigdeUren = 1.0;

  DateTime? _date;

  TimeOfDay? _start;

  bool _isAnderAdres = false;

  final TextEditingController _anderAdresController = TextEditingController();

  bool _isAfwijkendePrijs = false;

  final TextEditingController _afwijkendePrijsController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _loadProjects();
  }

  @override
  void dispose() {
    _anderAdresController.dispose();
    _afwijkendePrijsController.dispose();
    super.dispose();
  }

  String _t(dynamic v) => (v ?? '').toString().trim();

  Future<void> _loadProjects() async {
    setState(() {
      _loadingProjects = true;

      _error = null;
    });

    try {
      final res = await Supabase.instance.client
          .from('projecten')
          // `bedrijfsnaam` is not a column on `projecten`; fetch it via join.
          .select('id, project_naam, werk_regio, bedrijven(bedrijfsnaam)')
          .eq('status', 'actief')
          .order('project_naam', ascending: true);

      final rows = (res as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);

      if (!mounted) return;

      setState(() => _projects = rows);
    } catch (e) {
      if (!mounted) return;

      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loadingProjects = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,

      initialDate: _date ?? now,

      firstDate: DateTime(now.year - 1),

      lastDate: DateTime(now.year + 3),
    );

    if (picked == null || !mounted) return;

    setState(() => _date = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,

      initialTime: _start ?? const TimeOfDay(hour: 8, minute: 0),
    );

    if (picked == null || !mounted) return;

    setState(() => _start = picked);
  }

  String _timeToDb(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _toonProjectZoekModal() async {
    if (_loadingProjects || _saving) return;

    String zoekTerm = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final q = zoekTerm.toLowerCase().trim();
            final gefilterdeLijst = _projects.where((p) {
              if (q.isEmpty) return true;
              final pNaam = p['project_naam']?.toString().toLowerCase() ?? '';
              final bNaam = p['bedrijven'] is Map
                  ? (p['bedrijven'] as Map)['bedrijfsnaam']
                        ?.toString()
                        .toLowerCase() ??
                      ''
                  : p['bedrijfsnaam']?.toString().toLowerCase() ??
                      p['bedrijfsnaam_klant']?.toString().toLowerCase() ??
                      '';
              return pNaam.contains(q) || bNaam.contains(q);
            }).toList();

            return AlertDialog(
              title: Text(
                'Zoek project',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Zoek op project of klant',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          zoekTerm = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: gefilterdeLijst.isEmpty
                          ? Center(
                              child: Text(
                                'Geen resultaten',
                                style: GoogleFonts.inter(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: gefilterdeLijst.length,
                              itemBuilder: (context, index) {
                                final project = gefilterdeLijst[index];
                                final pNaam =
                                    project['project_naam']?.toString() ??
                                    'Onbekend project';
                                final bNaam = project['bedrijven'] is Map
                                    ? (project['bedrijven'] as Map)['bedrijfsnaam']
                                          ?.toString() ??
                                      ''
                                    : project['bedrijfsnaam']?.toString() ??
                                        project['bedrijfsnaam_klant']
                                            ?.toString() ??
                                        '';

                                return ListTile(
                                  title: Text(
                                    pNaam,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: bNaam.isEmpty
                                      ? null
                                      : Text(
                                          bNaam,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                          ),
                                        ),
                                  onTap: () {
                                    Navigator.of(dialogContext).pop();
                                    if (!mounted) return;
                                    final label = bNaam.isEmpty
                                        ? pNaam
                                        : '$pNaam ($bNaam)';
                                    setState(() {
                                      _selectedProject = project;
                                      _geselecteerdeProjectNaam = label;
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Sluiten'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  TimeOfDay? _berekendeEindtijdBijEenOperator() {
    if (_start == null) return null;
    var totaalMinuten = _start!.hour * 60 + _start!.minute;
    totaalMinuten += (_benodigdeUren * 60).round();
    return TimeOfDay(
      hour: (totaalMinuten ~/ 60) % 24,
      minute: totaalMinuten % 60,
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    if (_selectedProject == null) {
      setState(() => _error = 'Selecteer een project.');

      return;
    }

    if (_date == null) {
      setState(() => _error = 'Kies een datum.');

      return;
    }

    if (_start == null) {
      setState(() => _error = 'Kies een starttijd.');

      return;
    }

    final eind = _berekendeEindtijdBijEenOperator();
    if (eind == null) {
      setState(() => _error = 'Kon eindtijd niet bepalen.');

      return;
    }

    if (_benodigdeUren <= 0) {
      setState(() => _error = 'Vul geldige benodigde uren in.');

      return;
    }

    setState(() {
      _saving = true;

      _error = null;
    });

    try {
      final p = _selectedProject!;

      final bedrijven = p['bedrijven'];

      final bedrijfsnaam = (bedrijven is Map)
          ? _t(bedrijven['bedrijfsnaam'])
          : 'Onbekend Bedrijf';

      final double benodigdeUren = _benodigdeUren;
      final berekendeEindTijd = _timeToDb(eind);

      final Map<String, dynamic> payload = {
        'project_id': p['id'],
        'bedrijfsnaam': bedrijfsnaam,
        'werk_regio': p['werk_regio'],
        'geplande_datum': _date!.toIso8601String().substring(0, 10),
        'tijdslot_start': _timeToDb(_start!),
        'tijdslot_eind': berekendeEindTijd,
        'benodigde_operators': aantalOperators,
        'benodigde_uren_totaal': benodigdeUren * aantalOperators,
        'verwachte_uren_totaal': benodigdeUren * aantalOperators,
        'afwijkende_uren': true,
        'status': 'open',
        'is_buiten_abonnement': true,
      };

      if (_isAnderAdres && _anderAdresController.text.trim().isNotEmpty) {
        payload['uitvoer_adres_volledig'] = _anderAdresController.text.trim();
      }

      if (_isAfwijkendePrijs &&
          _afwijkendePrijsController.text.trim().isNotEmpty) {
        final vastePrijs = double.tryParse(
              _afwijkendePrijsController.text.replaceAll(',', '.'),
            ) ??
            0.0;
        payload['opdracht_waarde_ex_btw'] = vastePrijs;
      }

      // ignore: avoid_print
      print('--- X-RAY PAYLOAD VOOR SUPABASE ---');
      // ignore: avoid_print
      print(
        'Aantal operators geselecteerd: ${payload['benodigde_operators']}',
      );
      // ignore: avoid_print
      print('Totaal uren berekend: ${payload['benodigde_uren_totaal']}');
      // ignore: avoid_print
      print('-----------------------------------');

      // ignore: avoid_print
      print('--- START INSERT NAAR SUPABASE ---');
      try {
        final response = await Supabase.instance.client
            .from('opdrachten')
            .insert(payload)
            .select('id, benodigde_operators, benodigde_uren_totaal')
            .single();

        // ignore: avoid_print
        print('--- SUPABASE HEEFT DIT OPGESLAGEN ---');
        // ignore: avoid_print
        print(response);
        // ignore: avoid_print
        print('------------------------------------');
      } catch (e) {
        // ignore: avoid_print
        print('SUPABASE INSERT ERROR: $e');
        rethrow;
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    final benodigdeUren = _benodigdeUren;
    final int urenInt = benodigdeUren.floor();
    final int minutenInt = ((benodigdeUren - urenInt) * 60).round();
    final String urenTekst = minutenInt > 0
        ? '$urenInt uur en $minutenInt min'
        : '$urenInt uur';

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),

      padding: EdgeInsets.only(bottom: viewInsets),

      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(32),

            topRight: Radius.circular(32),
          ),
        ),

        child: SafeArea(
          top: false,

          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Center(
                  child: Container(
                    width: 42,

                    height: 5,

                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.08),

                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  'Nieuwe Opdracht toevoegen aan Project',

                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,

                    fontSize: 18,
                  ),
                ),

                const SizedBox(height: 12),

                if (_error != null) ...[
                  Text(
                    '$_error',

                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,

                      color: const Color(0xFFCC2F2F),
                    ),
                  ),

                  const SizedBox(height: 10),
                ],

                if (_loadingProjects)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: (_loadingProjects || _saving)
                          ? null
                          : _toonProjectZoekModal,
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Geselecteerd project',
                          border: const OutlineInputBorder(),
                          suffixIcon: _geselecteerdeProjectNaam != null && !_saving
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: _loadingProjects
                                      ? null
                                      : () {
                                          setState(() {
                                            _selectedProject = null;
                                            _geselecteerdeProjectNaam = null;
                                          });
                                        },
                                )
                              : const Icon(Icons.search),
                        ),
                        child: Text(
                          _geselecteerdeProjectNaam ??
                              'Klik hier om een project te zoeken',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: _geselecteerdeProjectNaam == null
                                ? Colors.grey.shade600
                                : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),

                CheckboxListTile(
                  title: const Text('Ander uitvoer adres'),
                  subtitle: const Text('Wijk af van het standaard project adres'),
                  value: _isAnderAdres,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (bool? value) {
                    setState(() {
                      _isAnderAdres = value ?? false;
                    });
                  },
                ),
                if (_isAnderAdres)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: TextFormField(
                      controller: _anderAdresController,
                      decoration: const InputDecoration(
                        labelText:
                            'Volledig adres (Straat, Postcode, Stad)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _pickDate,

                        child: Text(
                          _date == null
                              ? 'Datum'
                              : _date!.toIso8601String().substring(0, 10),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _pickStartTime,

                        child: Text(
                          _start == null
                              ? 'Starttijd'
                              : _start!.format(context),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_start != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Eindtijd wordt automatisch berekend: '
                    '${_berekendeEindtijdBijEenOperator()?.format(context) ?? '—'}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Aantal operators:',
                      style: TextStyle(fontSize: 16),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.blue,
                          ),
                          onPressed: aantalOperators > 1
                              ? () {
                                  setState(() {
                                    aantalOperators--;
                                  });
                                }
                              : null,
                        ),
                        Text(
                          '$aantalOperators',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.blue,
                          ),
                          onPressed: () {
                            setState(() {
                              aantalOperators++;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Benodigde uren:',
                      style: GoogleFonts.inter(fontSize: 16),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.blue,
                          ),
                          onPressed: _saving || _benodigdeUren <= 0.25
                              ? null
                              : () => setState(
                                  () => _benodigdeUren -= 0.25,
                                ),
                        ),
                        Text(
                          urenTekst,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.blue,
                          ),
                          onPressed: _saving
                              ? null
                              : () => setState(() => _benodigdeUren += 0.25),
                        ),
                      ],
                    ),
                  ],
                ),

                if (aantalOperators > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
                    child: Text(
                      'Totale werkuren: ${(benodigdeUren * aantalOperators).toStringAsFixed(2)} uur (Fysieke dienst: $urenTekst per operator)',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),

                CheckboxListTile(
                  title: const Text('Afwijkende opdracht prijs'),
                  subtitle: const Text(
                    'Overschrijf de berekende prijs (Uren x Tarief) met een vaste prijs',
                  ),
                  value: _isAfwijkendePrijs,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (bool? value) {
                    setState(() {
                      _isAfwijkendePrijs = value ?? false;
                    });
                  },
                ),
                if (_isAfwijkendePrijs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: TextFormField(
                      controller: _afwijkendePrijsController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Vaste prijs (ex. BTW)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.euro),
                      ),
                    ),
                  ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,

                  child: FilledButton(
                    onPressed: (_saving || _loadingProjects) ? null : _save,

                    child: _saving
                        ? const SizedBox(
                            width: 18,

                            height: 18,

                            child: CircularProgressIndicator(
                              strokeWidth: 2,

                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Opslaan',

                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
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
  }
}
