import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

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
  Map<String, List<Map<String, dynamic>>> _afsprakenPerDatum =
      const <String, List<Map<String, dynamic>>>{};
  bool _isTijdenLaden = false;

  // Manual planning (table_calendar) state
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  String? _selectedManualProjectId;
  String _calendarViewMode = 'Maand';
  bool _showFilters = true;
  List<Map<String, dynamic>> _manualTasks = [];
  Map<DateTime, List<dynamic>> _groupedTasks = {};
  bool _isLoading = true;
  CalendarFormat _calendarFormat = CalendarFormat.month;

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

  DateTime _normalizeDate(DateTime date) => DateTime(date.year, date.month, date.day);

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

  bool _heeftOverlapVoorDag({
    required String datumDb,
    required int startMin,
    required int eindMin,
  }) {
    final afspraken = _afsprakenPerDatum[datumDb] ?? const <Map<String, dynamic>>[];
    for (final a in afspraken) {
      final stRaw = _text(a['starttijd']);
      final etRaw = _text(a['eindtijd']);
      if (stRaw.isEmpty || etRaw.isEmpty) continue;
      final aStart = _timeToMinutes(stRaw);
      final aEnd = _timeToMinutes(etRaw);
      // 15 min travel buffer around existing appointments.
      final geblokkeerdStart = aStart - 15;
      final geblokkeerdEind = aEnd + 15;
      if (startMin < geblokkeerdEind && eindMin > geblokkeerdStart) return true;
    }
    return false;
  }

  String? _zoekEersteVrijeTijdVoorDag({
    required String datumDb,
    required int vensterStartMin,
    required int vensterEindMin,
    required int duurMin,
  }) {
    for (int actuele = vensterStartMin;
        (actuele + duurMin) <= vensterEindMin;
        actuele += 15) {
      if (!_heeftOverlapVoorDag(
        datumDb: datumDb,
        startMin: actuele,
        eindMin: actuele + duurMin,
      )) {
        final h = actuele ~/ 60;
        final m = actuele % 60;
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
    }
    return null;
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

      for (int actueleMinuten = startVensterMin;
          (actueleMinuten + opdrachtMinuten) <= eindVensterMin;
          actueleMinuten += 15) {
        final potentieelEindMinuten = actueleMinuten + opdrachtMinuten;
        var vrij = 0;
        for (final d in datumsDb) {
          final afspraken = afsprakenByDate[d] ?? const <Map<String, dynamic>>[];
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
        final tijd = '${uren.toString().padLeft(2, '0')}:${minuten.toString().padLeft(2, '0')}';
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
        _afsprakenPerDatum = afsprakenByDate;
        _tijdOpties = opties;
        final cur = (_handmatigeSmartTijd ?? '').trim();
        final tijden = opties.map((e) => _text(e['tijd'])).where((t) => t.isNotEmpty).toList();
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
        _afsprakenPerDatum = const <String, List<Map<String, dynamic>>>{};
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
        _smartReedsIngeplandStart = raw.isEmpty ? null : (raw.length >= 5 ? raw.substring(0, 5) : raw);
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
      _afsprakenPerDatum = const <String, List<Map<String, dynamic>>>{};
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

    final suggested = _timeFromRaw(firstMap['starttijd'] ?? firstMap['tijdslot_start']) ??
        _timeFromRaw(_selectedProject?['tijdslot_start']) ??
        const TimeOfDay(hour: 8, minute: 0);

    final windowStart =
        _timeFromRaw(_selectedProject?['tijdslot_start']) ?? const TimeOfDay(hour: 8, minute: 0);
    final windowEnd =
        _timeFromRaw(_selectedProject?['tijdslot_eind']) ?? const TimeOfDay(hour: 17, minute: 0);

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

    final datumsDb = planning
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
    final standardPerShift = _asDouble(project['standaard_uren_per_shift'], fallback: 0);
    final rawHours = standardPerShift > 0
        ? standardPerShift
        : totalHours > 0
            ? (totalHours / safeOperators)
            : _asDouble(project['basis_uren_per_opdracht'], fallback: 1);
    final perShiftHours = rawHours.clamp(0.25, 24.0);
    final normalizedProject = Map<String, dynamic>.from(project);
    normalizedProject['project_id'] =
        _text(project['project_id']).isNotEmpty ? _text(project['project_id']) : _text(project['id']);

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
    final parsedHours = double.tryParse(_hoursController.text.replaceAll(',', '.')) ?? 0.0;
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
        params: {
          'p_project_id': projectId,
          'p_uren_per_shift': parsedHours,
        },
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
    final name = _text(result['naam']).isEmpty ? 'deze operator' : _text(result['naam']);
    final available = _asInt(result['beschikbare_beurten']);

    final shouldConfirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return SelectionArea(
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                child: Text('Annuleren', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: Text('Bevestigen', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
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
        final opdrachtenLijst = _asPlanningList(result['voorgestelde_planning']);
        var datumString = 'binnenkort';
        if (opdrachtenLijst.isNotEmpty && opdrachtenLijst.first is Map) {
          final eerste = Map<String, dynamic>.from(opdrachtenLijst.first as Map);
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
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800),
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
    return DateTime.tryParse(raw) ?? DateTime.now();
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = _normalizeDate(date);
    return normalized.subtract(Duration(days: normalized.weekday - DateTime.monday));
  }

  List<dynamic> get _filteredAgendaTasks {
    Iterable<Map<String, dynamic>> filtered = _manualTasks;

    // 1) Project filter
    if (_selectedManualProjectId != null && _selectedManualProjectId!.isNotEmpty) {
      filtered = filtered.where((task) => _text(task['project_id']) == _selectedManualProjectId);
    }

    // 2) Timeframe filter by selected calendar mode
    if (_calendarViewMode == 'Maand') {
      filtered = filtered.where((task) {
        final date = _normalizeDate(_toDate(task['geplande_datum']));
        return date.month == _focusedDay.month && date.year == _focusedDay.year;
      });
    } else if (_calendarViewMode == 'Week') {
      final start = _startOfWeek(_focusedDay);
      final end = start.add(const Duration(days: 6));
      filtered = filtered.where((task) {
        final date = _normalizeDate(_toDate(task['geplande_datum']));
        return !date.isBefore(start) && !date.isAfter(end);
      });
    } else {
      final selected = _normalizeDate(_selectedDay ?? _focusedDay);
      filtered = filtered.where((task) {
        final date = _normalizeDate(_toDate(task['geplande_datum']));
        return date.year == selected.year && date.month == selected.month && date.day == selected.day;
      });
    }

    final rows = filtered.toList(growable: false);
    final selectedKey = _normalizeDate(_selectedDay ?? _focusedDay);
    rows.sort((a, b) {
      final aDate = _normalizeDate(_toDate(a['geplande_datum']));
      final bDate = _normalizeDate(_toDate(b['geplande_datum']));
      final aIsSelected = aDate == selectedKey;
      final bIsSelected = bDate == selectedKey;
      if (aIsSelected && !bIsSelected) return -1;
      if (!aIsSelected && bIsSelected) return 1;
      return _toDate(a['geplande_datum']).compareTo(_toDate(b['geplande_datum']));
    });
    return rows;
  }

  Future<void> _loadTasks() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final baseQuery = AppSupabase.client
          .from('opdrachten')
          .select(
            'id, project_id, geplande_datum, tijdslot_start, tijdslot_eind, '
            'bedrijfsnaam, werk_regio, status, benodigde_operators, projecten(project_naam)',
          )
          .inFilter('status', const ['open', 'deels_voltooid']);

      final response = (_selectedManualProjectId != null && _selectedManualProjectId!.isNotEmpty)
          ? await baseQuery
              .eq('project_id', _selectedManualProjectId!)
              .order('geplande_datum', ascending: true)
          : await baseQuery.order('geplande_datum', ascending: true);

      final grouped = <DateTime, List<dynamic>>{};
      for (final raw in (response as List)) {
        if (raw is! Map) continue;
        final task = Map<String, dynamic>.from(raw);
        final dateRaw = _text(task['geplande_datum']);
        if (dateRaw.isEmpty) continue;
        final parsedDate = DateTime.tryParse(dateRaw);
        if (parsedDate == null) continue;
        final key = _normalizeDate(parsedDate);
        grouped.putIfAbsent(key, () => <dynamic>[]).add(task);
      }

      if (!mounted) return;
      setState(() {
        _manualTasks = (response as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        _groupedTasks = grouped;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Planbord _loadTasks failed: $error');
      if (!mounted) return;
      setState(() {
        _manualTasks = const <Map<String, dynamic>>[];
        _groupedTasks = {};
        _isLoading = false;
      });
    }
  }

  Future<void> _openManualPlanModal(String opdrachtId) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SelectionArea(
        child: ManualPlanModal(opdrachtId: opdrachtId),
      ),
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
      builder: (_) => const SelectionArea(
        child: _ExtraOpdrachtModal(),
      ),
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
    final conflicts = result['conflicten'] is List ? List<dynamic>.from(result['conflicten'] as List) : const [];
    final available = _asInt(result['beschikbare_beurten']);
    final total = _asInt(result['totale_beurten']);
    final name = _text(result['naam']).isEmpty ? 'Onbekende operator' : _text(result['naam']);
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
                            padding: const EdgeInsets.only(top: 16.0, bottom: 24.0),
                            child: DropdownButtonFormField<String>(
                              initialValue: (_handmatigeSmartTijd ?? '').trim().isEmpty
                                  ? null
                                  : _handmatigeSmartTijd,
                              dropdownColor: const Color(0xFFF2F2F7),
                              items: opties.map((opt) {
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.orange.withValues(alpha: 0.55),
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
                              }).toList(growable: false),
                              onChanged: tijden.isEmpty
                                  ? null
                                  : (v) {
                                      final next = (v ?? '').trim();
                                      if (next.isEmpty) return;
                                      setState(() => _handmatigeSmartTijd = next);
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

    final selectedResult = (_selectedResultIndex != null &&
            _selectedResultIndex! >= 0 &&
            _selectedResultIndex! < filteredResults.length)
        ? filteredResults[_selectedResultIndex!]
        : null;

    final showMultiOperatorWarning = _smartNeededOperators > 1 &&
        (_smartReedsIngeplandStart != null && _smartReedsIngeplandStart!.isNotEmpty);

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
                    itemCount: visibleProjects.length,
                    itemBuilder: (context, index) {
                      final project = Map<String, dynamic>.from(visibleProjects[index]);
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
                        project['standaard_aantal_operators'] ?? project['benodigde_operators'],
                        fallback: 1,
                      );
                      final hasAssignedHours = _asDouble(project['reeds_toegewezen_uren']) > 0;
                      final selected = selectedProjectId.isNotEmpty &&
                          projectId.isNotEmpty &&
                          selectedProjectId == projectId;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: projectId.isEmpty ? null : () => _onProjectSelected(projectId),
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
                                    color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.03),
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
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        color: Colors.orange.withValues(alpha: isDark ? 0.18 : 0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: isDark ? 0.35 : 0.30),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.orange.shade700),
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
                    style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900),
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
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
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
                                          formatHoursToText(_asDouble(_selectedProject?['benodigde_uren_totaal'])),
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
                                          formatHoursToText(_asDouble(_selectedProject?['standaard_uren_per_shift'])),
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
                                          formatHoursToText(_asDouble(_selectedProject?['reeds_toegewezen_uren'])),
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
                                          formatHoursToText(_asDouble(_selectedProject?['resterende_uren_per_beurt'])),
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1B1B23) : const Color(0xFFF5F5F7),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                              ),
                              child: Row(
                                children: [
                                  _StepperCircleButton(
                                    icon: Icons.remove_rounded,
                                    onPressed: () {
                                      setState(() {
                                        _shiftHours = (_shiftHours - 0.25).clamp(0.25, 24.0);
                                        _hoursController.text = _shiftHours.toStringAsFixed(2);
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
                                        _shiftHours = (_shiftHours + 0.25).clamp(0.25, 24.0);
                                        _hoursController.text = _shiftHours.toStringAsFixed(2);
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
                                color: cs.onSurface.withValues(alpha: isDark ? 0.10 : 0.04),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
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
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                                    )
                                  else
                                    ListView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: _plannedOperators.length,
                                      itemBuilder: (context, index) {
                                        final operator = _plannedOperators[index];
                                        final filled = _asInt(operator['aantal_beurten_gevuld']);
                                        final total = _asInt(_selectedProject?['totaal_taken']);
                                        final name = _text(operator['operator_naam']).isEmpty
                                            ? 'Operator'
                                            : _text(operator['operator_naam']);
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 6),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.person,
                                                size: 16,
                                                color: cs.onSurface.withValues(alpha: 0.74),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isCalculating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  'Slim Inplannen',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _isCalculating
                        ? const Center(child: CircularProgressIndicator())
                        : !_hasCalculated
                            ? Center(
                                child: Text(
                                  'Klik op "Slim Inplannen" om operator matches te berekenen.',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                                ),
                              )
                            : filteredResults.isEmpty
                                ? Center(
                                    child: Text(
                                      'Geen plannerresultaten gevonden voor de huidige filters.',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: filteredResults.length,
                                    itemBuilder: (context, index) {
                                      return _buildResultCard(filteredResults[index], index: index);
                                    },
                                  ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selectedResult == null
                          ? null
                          : () {
                              // HARD BLOCK: only allow save when we have safe times
                              if (_handmatigeSmartTijd == null ||
                                  _tijdOpties.isEmpty) {
                                return;
                              }
                              final suggested = (_smartSuggestedTijd ?? '').trim();
                              final chosen = (_handmatigeSmartTijd ?? suggested).trim();
                              final rawPlanning = selectedResult['voorgestelde_planning'];
                              final planning = _asPlanningList(rawPlanning);
                              if (chosen.isEmpty || planning.isEmpty || _smartActiveOpdrachtId == null) {
                                _confirmBooking(selectedResult);
                                return;
                              }

                              final hours =
                                  double.tryParse(_hoursController.text.trim().replaceAll(',', '.')) ??
                                      _shiftHours;
                              final defaultDurMin = (hours * 60).round();

                              final vensterStartMin = _timeToMinutes(
                                _text(_selectedProject?['tijdslot_start']).isEmpty
                                    ? '08:00'
                                    : _text(_selectedProject?['tijdslot_start']).substring(0, 5),
                              );
                              final vensterEindMin = _timeToMinutes(
                                _text(_selectedProject?['tijdslot_eind']).isEmpty
                                    ? '17:00'
                                    : _text(_selectedProject?['tijdslot_eind']).substring(0, 5),
                              );

                              final updatedList = planning.map((raw) {
                                if (raw is! Map) return raw;
                                final m = Map<String, dynamic>.from(raw);
                                // Apply chosen time to ALL items in the series.
                                final itemHours = _asDouble(
                                  m['toegewezen_uren'] ??
                                      m['uren_per_shift'] ??
                                      m['duur_uren'] ??
                                      m['uren'],
                                  fallback: hours,
                                );
                                final durMin =
                                    itemHours > 0 ? (itemHours * 60).round() : defaultDurMin;

                                final rawDate = _text(m['geplande_datum']);
                                final datumDb = rawDate.contains('T') ? rawDate.split('T').first : rawDate;
                                if (datumDb.isEmpty) return null;

                                // 1) Try chosen time on this day
                                final chosenMin = _timeToMinutes(chosen);
                                final chosenEnd = chosenMin + durMin;
                                var definitiveMin = chosenMin;

                                final hasOverlap = _heeftOverlapVoorDag(
                                  datumDb: datumDb,
                                  startMin: chosenMin,
                                  eindMin: chosenEnd,
                                );

                                // 2) If overlap, find first available time in window for this day
                                if (hasOverlap) {
                                  final found = _zoekEersteVrijeTijdVoorDag(
                                    datumDb: datumDb,
                                    vensterStartMin: vensterStartMin,
                                    vensterEindMin: vensterEindMin,
                                    duurMin: durMin,
                                  );
                                  if (found == null) return null; // skip this day entirely
                                  definitiveMin = _timeToMinutes(found);
                                }

                                final start = _timeFromMinutes(definitiveMin);
                                final end = _timeFromMinutes(definitiveMin + durMin);
                                m['starttijd'] = '${_timeToHuman(start)}:00';
                                m['eindtijd'] = '${_timeToHuman(end)}:00';
                                return m;
                              }).whereType<Map>().toList(growable: false);

                              final patched = Map<String, dynamic>.from(selectedResult);
                              // Keep the same type as backend expects (string JSON vs list).
                              patched['voorgestelde_planning'] =
                                  rawPlanning is String ? jsonEncode(updatedList) : updatedList;
                              _confirmBooking(patched);
                            },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Plan reeks voor ${_text(_selectedProject?['project_naam']).isEmpty ? 'project' : _text(_selectedProject?['project_naam'])}',
                      style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
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
                                  formatHoursToText(_asDouble(_selectedProject?['benodigde_uren_totaal'])),
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
                                  formatHoursToText(_asDouble(_selectedProject?['standaard_uren_per_shift'])),
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
                                  formatHoursToText(_asDouble(_selectedProject?['reeds_toegewezen_uren'])),
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
                                  formatHoursToText(_asDouble(_selectedProject?['resterende_uren_per_beurt'])),
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B1B23) : const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                      ),
                      child: Row(
                        children: [
                          _StepperCircleButton(
                            icon: Icons.remove_rounded,
                            onPressed: () {
                              setState(() {
                                _shiftHours = (_shiftHours - 0.25).clamp(0.25, 24.0);
                                _hoursController.text = _shiftHours.toStringAsFixed(2);
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
                                _shiftHours = (_shiftHours + 0.25).clamp(0.25, 24.0);
                                _hoursController.text = _shiftHours.toStringAsFixed(2);
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
                        color: cs.onSurface.withValues(alpha: isDark ? 0.10 : 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
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
                              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _plannedOperators.length,
                              itemBuilder: (context, index) {
                                final operator = _plannedOperators[index];
                                final filled = _asInt(operator['aantal_beurten_gevuld']);
                                final total = _asInt(_selectedProject?['totaal_taken']);
                                final name = _text(operator['operator_naam']).isEmpty
                                    ? 'Operator'
                                    : _text(operator['operator_naam']);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person,
                                        size: 16,
                                        color: cs.onSurface.withValues(alpha: 0.74),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isCalculating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                'Slim Inplannen',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
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
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
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
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredResults.length,
                        itemBuilder: (context, index) {
                          return _buildResultCard(filteredResults[index], index: index);
                        },
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            selectedResult == null ? null : () => _confirmBooking(selectedResult),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          'Definitief Inplannen',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: isMobile
          ? (_selectedProject == null ? buildLeftColumn() : buildRightColumnMobile())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 1, child: buildLeftColumn()),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: buildRightColumnDesktop()),
              ],
            ),
    );
  }

  Widget _buildManualPlanningTab(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 800;
    final agendaTasks = _filteredAgendaTasks;

    return Column(
      children: [
        if (isMobile)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton(
              onPressed: () => setState(() => _showFilters = !_showFilters),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                _showFilters ? 'Filters & Zoeken verbergen' : 'Filters & Zoeken tonen',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: _showFilters ? CrossFadeState.showFirst : CrossFadeState.showSecond,
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
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            ),
            child: DropdownButtonFormField<String?>(
              initialValue: _selectedManualProjectId,
              decoration: InputDecoration(
                labelText: isMobile ? 'Project' : 'Projectfilter',
                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                filled: true,
                fillColor: isDark ? const Color(0xFF1B1B23) : const Color(0xFFF5F5F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
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
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: _calendarViewMode,
              padding: const EdgeInsets.all(4),
              thumbColor: cs.primary,
              backgroundColor: cs.onSurface.withValues(alpha: isDark ? 0.14 : 0.08),
              children: {
                'Maand': Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Maand',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: _calendarViewMode == 'Maand' ? Colors.white : cs.onSurface,
                    ),
                  ),
                ),
                'Week': Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Week',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: _calendarViewMode == 'Week' ? Colors.white : cs.onSurface,
                    ),
                  ),
                ),
                'Dag': Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Dag',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: _calendarViewMode == 'Dag' ? Colors.white : cs.onSurface,
                    ),
                  ),
                ),
              },
              onValueChanged: (value) {
                if (value == null) return;
                setState(() {
                  _calendarViewMode = value;
                  _calendarFormat =
                      (value == 'Maand') ? CalendarFormat.month : CalendarFormat.week;
                });
              },
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
            child: TableCalendar<dynamic>(
              locale: 'nl_NL',
              firstDay: DateTime.now().subtract(const Duration(days: 730)),
              lastDay: DateTime.now().add(const Duration(days: 730)),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              startingDayOfWeek: StartingDayOfWeek.monday,
              availableCalendarFormats: const {
                CalendarFormat.month: 'Maand',
                CalendarFormat.week: 'Week',
              },
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              eventLoader: (day) => _groupedTasks[_normalizeDate(day)] ?? const <dynamic>[],
              onFormatChanged: (format) {
                setState(() => _calendarFormat = format);
              },
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
              },
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              calendarStyle: CalendarStyle(
                isTodayHighlighted: true,
                todayDecoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.20),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
                markerDecoration: const BoxDecoration(color: Colors.transparent),
                outsideTextStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.35)),
              ),
              headerStyle: HeaderStyle(
                titleTextStyle: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w900),
                formatButtonTextStyle: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
                formatButtonDecoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: GoogleFonts.inter(fontWeight: FontWeight.w800),
                weekendStyle: GoogleFonts.inter(fontWeight: FontWeight.w800),
              ),
              calendarBuilders: CalendarBuilders<dynamic>(
                markerBuilder: (context, date, events) {
                  if (events.isEmpty) return const SizedBox.shrink();
                  final visible = events.take(3).toList(growable: false);
                  final remainder = events.length - visible.length;
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 2, left: 2, right: 2),
                      child: Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        alignment: WrapAlignment.center,
                        children: [
                          ...visible.map((event) {
                            final task = event is Map<String, dynamic>
                                ? event
                                : Map<String, dynamic>.from(event as Map);
                            final startLabel = _timeLabel(task['tijdslot_start']);
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                startLabel,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: cs.primary,
                                  height: 1.0,
                                ),
                              ),
                            );
                          }),
                          if (remainder > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '+$remainder',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface.withValues(alpha: 0.74),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
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
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agenda (${_calendarViewMode.toLowerCase()})',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Alle opdrachten voor deze ${_calendarViewMode.toLowerCase()}',
                        style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: agendaTasks.isEmpty
                            ? Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: cs.onSurface.withValues(alpha: isDark ? 0.08 : 0.04),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    'Geen opdrachten gevonden voor deze periode.',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface.withValues(alpha: 0.72),
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: agendaTasks.length,
                                itemBuilder: (context, index) {
                                  final task = Map<String, dynamic>.from(agendaTasks[index] as Map);
                                  final opdrachtId = _text(task['id']);
                                  final project = _projectName(task);
                                  final company = _text(task['bedrijfsnaam']).isEmpty
                                      ? 'Onbekende klant'
                                      : _text(task['bedrijfsnaam']);
                                  final start = _timeLabel(task['tijdslot_start']);
                                  final end = _timeLabel(task['tijdslot_eind']);
                                  final date = _toDate(task['geplande_datum']);
                                  final needed = _asInt(task['benodigde_operators'], fallback: 1);
                                  final title = project.isNotEmpty ? project : company;
                                  final isSelectedDay =
                                      isSameDay(_selectedDay ?? _focusedDay, date);

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: opdrachtId.isEmpty ? null : () => _openManualPlanModal(opdrachtId),
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: isSelectedDay
                                                ? Colors.blue.shade50
                                                : isDark
                                                    ? const Color(0xFF171722)
                                                    : const Color(0xFFFDFDFE),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: isSelectedDay
                                                  ? Colors.blue.withValues(alpha: 0.30)
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
                                                  color: cs.primary.withValues(alpha: 0.85),
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
                                                            color: cs.primary.withValues(alpha: 0.10),
                                                            borderRadius: BorderRadius.circular(999),
                                                          ),
                                                          child: Text(
                                                            '$start - $end',
                                                            style: GoogleFonts.inter(
                                                              fontWeight: FontWeight.w800,
                                                              color: cs.primary,
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
                                                      'Nodig: $needed operators',
                                                      style: GoogleFonts.inter(
                                                        fontWeight: FontWeight.w800,
                                                        color: cs.primary.withValues(alpha: 0.85),
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
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
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
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
          ),
          actions: [
            IconButton(
              tooltip: 'Vernieuwen',
              onPressed: (_isLoading || _isLoadingProjects || _isLoadingSmartProjects || _isCalculating)
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
  final TextEditingController _urenCtrl = TextEditingController();
  bool _loadingProjects = true;
  bool _saving = false;
  Object? _error;

  List<Map<String, dynamic>> _projects = const [];
  Map<String, dynamic>? _selectedProject;
  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  @override
  void dispose() {
    _urenCtrl.dispose();
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

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (start ? _start : _end) ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  String _timeToDb(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

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
    if (_start == null || _end == null) {
      setState(() => _error = 'Kies start- en eindtijd.');
      return;
    }
    final uren = double.tryParse(_urenCtrl.text.trim().replaceAll(',', '.'));
    if (uren == null || uren <= 0) {
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

      await Supabase.instance.client.from('opdrachten').insert({
        'project_id': p['id'],
        'bedrijfsnaam': bedrijfsnaam,
        'werk_regio': p['werk_regio'],
        'geplande_datum': _date!.toIso8601String().substring(0, 10),
        'tijdslot_start': _timeToDb(_start!),
        'tijdslot_eind': _timeToDb(_end!),
        'benodigde_uren_totaal': uren,
        'verwachte_uren_totaal': uren,
        'status': 'open',
      });

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
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18),
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
                DropdownButtonFormField<Map<String, dynamic>>(
                  key: ValueKey(_selectedProject == null ? 'none' : _t(_selectedProject!['id'])),
                  initialValue: _selectedProject,
                  items: _projects
                      .map(
                        (p) => DropdownMenuItem<Map<String, dynamic>>(
                          value: p,
                          child: Text(
                            _t(p['project_naam']).isEmpty ? 'Project' : _t(p['project_naam']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (_loadingProjects || _saving) ? null : (v) => setState(() => _selectedProject = v),
                  decoration: const InputDecoration(labelText: 'Selecteer Project'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _pickDate,
                        child: Text(_date == null ? 'Datum' : _date!.toIso8601String().substring(0, 10)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => _pickTime(start: true),
                        child: Text(_start == null ? 'Starttijd' : _start!.format(context)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => _pickTime(start: false),
                        child: Text(_end == null ? 'Eindtijd' : _end!.format(context)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urenCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Benodigde uren'),
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
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text('Opslaan', style: GoogleFonts.inter(fontWeight: FontWeight.w900)),
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

