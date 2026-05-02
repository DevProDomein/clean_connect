import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;

import '../../../core/supabase_client.dart';

class ManualPlanModal extends StatefulWidget {
  const ManualPlanModal({required this.opdrachtId, super.key});

  final String opdrachtId;

  @override
  State<ManualPlanModal> createState() => _ManualPlanModalState();
}

class _ManualPlanModalState extends State<ManualPlanModal> {
  final TextEditingController _startTimeController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _isSearching = false;
  bool _hasSearchedOperators = false;
  String? _error;
  Map<String, dynamic>? _opdracht;

  List<dynamic> _availableOperators = <dynamic>[];
  String? _selectedOperatorId;
  double _shiftHours = 0.25;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOpdracht());
  }

  @override
  void dispose() {
    _startTimeController.dispose();
    super.dispose();
  }

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

  DateTime _dateFromValue(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return DateTime.now();
    return DateTime.tryParse(raw) ?? DateTime.now();
  }

  TimeOfDay _timeFromValue(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return const TimeOfDay(hour: 8, minute: 0);
    final hhmm = raw.length >= 5 ? raw.substring(0, 5) : raw;
    final parts = hhmm.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 8 : 8;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  String _timeToDb(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m:00';
  }

  String _timeToHuman(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  DateTime _combine(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Map<String, dynamic>? _projectJoin() {
    final row = _opdracht;
    if (row == null) return null;
    final joined = row['projecten'];
    if (joined is Map<String, dynamic>) return joined;
    if (joined is List && joined.isNotEmpty && joined.first is Map) {
      return Map<String, dynamic>.from(joined.first as Map);
    }
    return null;
  }

  String get _projectName {
    final fromJoin = _text(_projectJoin()?['project_naam']);
    if (fromJoin.isNotEmpty) return fromJoin;
    return 'Onbekend project';
  }

  String get _clientName {
    final direct = _text(_opdracht?['bedrijfsnaam']);
    return direct.isEmpty ? 'Onbekende klant' : direct;
  }

  String get _regio {
    final fromJoin = _text(_projectJoin()?['werk_regio']);
    if (fromJoin.isNotEmpty) return fromJoin;
    final direct = _text(_opdracht?['werk_regio']);
    return direct.isEmpty ? '' : direct;
  }

  DateTime get _plannedDate => _dateFromValue(_opdracht?['geplande_datum']);

  TimeOfDay get _windowStart => _timeFromValue(_opdracht?['tijdslot_start']);

  TimeOfDay get _windowEnd => _timeFromValue(_opdracht?['tijdslot_eind']);

  TimeOfDay? get _selectedStartTime {
    final value = _text(_startTimeController.text);
    if (value.isEmpty) return null;
    return _timeFromValue(value);
  }

  TimeOfDay get _defaultWindowStartTime {
    final raw = _text(_opdracht?['tijdslot_start']);
    if (raw.isEmpty) return const TimeOfDay(hour: 8, minute: 0);
    final timeParts = raw.split(':');
    final hour = timeParts.isNotEmpty ? int.tryParse(timeParts[0]) ?? 8 : 8;
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  String get _plannedDateDb {
    final raw = _text(_opdracht?['geplande_datum']);
    if (raw.isEmpty) return _plannedDate.toIso8601String().split('T').first;
    return raw.contains('T') ? raw.split('T').first : raw;
  }

  String _formatDate(DateTime date) => DateFormat('dd-MM-yyyy').format(date);

  String formatHoursToText(num? hoursNum) {
    if (hoursNum == null) return '0 min';
    double hours = hoursNum.toDouble();
    int h = hours.floor();
    int m = ((hours - h) * 60).round();

    if (h > 0 && m > 0) return '$h uur en $m min';
    if (h > 0) return '$h uur';
    return '$m min';
  }

  Future<void> _loadOpdracht() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final row = await AppSupabase.client
          .from('opdrachten')
          .select(
            'id, project_id, geplande_datum, tijdslot_start, tijdslot_eind, '
            'benodigde_uren_totaal, toegewezen_uren_totaal, resterende_uren, '
            'benodigde_operators, werk_regio, uitvoer_adres_volledig, '
            'toelichting_planning, bedrijfsnaam, '
            'projecten(project_naam)',
          )
          .eq('id', widget.opdrachtId)
          .single();

      final map = Map<String, dynamic>.from(row as Map);
      final totalHours = _asDouble(map['benodigde_uren_totaal'], fallback: 0);
      final neededOperators = _asInt(map['benodigde_operators'], fallback: 1);
      final standardPerPerson = totalHours / math.max(1, neededOperators);
      final remainingHours = _asDouble(map['resterende_uren'], fallback: 0);
      _shiftHours = (remainingHours > 0 ? remainingHours : standardPerPerson).clamp(0.25, 24.0);
      final slotStartRaw = _text(map['tijdslot_start']);
      final slotStart = slotStartRaw.isEmpty ? const TimeOfDay(hour: 8, minute: 0) : _timeFromValue(slotStartRaw);
      _startTimeController.text = _timeToHuman(slotStart);

      if (!mounted) return;
      setState(() => _opdracht = map);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickStartTime() async {
    final previousValue = _startTimeController.text;
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedStartTime ?? _defaultWindowStartTime,
    );
    if (picked == null || !mounted) return;

    final hours = _shiftHours;
    if (hours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Vul eerst geldige uren per shift in.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final slotStartMinutes = (_windowStart.hour * 60) + _windowStart.minute;
    final slotEndMinutes = (_windowEnd.hour * 60) + _windowEnd.minute;
    final selectedStartMinutes = (picked.hour * 60) + picked.minute;
    final selectedEndMinutes = selectedStartMinutes + (hours * 60).round();
    if (selectedStartMinutes < slotStartMinutes || selectedEndMinutes > slotEndMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFCC2F2F),
          content: Text(
            'Gekozen tijd + duur valt buiten het afgesproken tijdsvenster van de klant.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
      if (previousValue.isNotEmpty) {
        _startTimeController.text = previousValue;
      }
      return;
    }

    _startTimeController.text = _timeToHuman(picked);
    _selectedOperatorId = null;
    setState(() {
      _availableOperators = <dynamic>[];
      _hasSearchedOperators = false;
    });
  }

  Future<void> _loadAvailableOperators() async {
    final start = _selectedStartTime;
    final hours = _shiftHours;
    if (start == null || hours <= 0 || _regio.isEmpty) {
      setState(() {
        _availableOperators = <dynamic>[];
        _selectedOperatorId = null;
        _hasSearchedOperators = false;
      });
      return;
    }

    final selectedStartTimeFormatted =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final dateString = _plannedDateDb.contains('T') ? _plannedDateDb.split('T').first : _plannedDateDb;
    final regio = _text(_opdracht?['werk_regio']);
    final opdrachtIdParam =
        _text(_opdracht?['id']).isNotEmpty ? _text(_opdracht?['id']) : widget.opdrachtId;

    setState(() {
      _isSearching = true;
      _selectedOperatorId = null;
    });
    void logRpc(Object message) {
      assert(() {
        debugPrint(message.toString());
        return true;
      }());
    }
    try {
      logRpc('--- START RPC CALL ---');
      logRpc('Datum: $dateString');
      logRpc('Start: $selectedStartTimeFormatted');
      logRpc('Duur: $_shiftHours');
      logRpc('Regio: $regio');

      final result = await Supabase.instance.client.rpc(
        'haal_beschikbare_operators_op',
        params: {
          'p_geplande_datum': dateString,
          'p_starttijd': '$selectedStartTimeFormatted:00',
          'p_duur_uren': hours,
          'p_regio': regio,
          'p_opdracht_id': opdrachtIdParam,
        },
      );

      logRpc('--- RPC SUCCESS ---');
      logRpc(result);
      final rows = List<dynamic>.from((result as List?) ?? const <dynamic>[]);
      if (!mounted) return;
      setState(() {
        _availableOperators = rows;
        _hasSearchedOperators = true;
        if (_selectedOperatorId != null &&
            !_availableOperators.any((o) {
              if (o is! Map) return false;
              return _text(o['id']) == _selectedOperatorId;
            })) {
          _selectedOperatorId = null;
        }
      });
    } catch (e) {
      logRpc('--- RPC ERROR ---');
      logRpc(e);
      if (!mounted) return;
      setState(() {
        _availableOperators = <dynamic>[];
        _selectedOperatorId = null;
        _hasSearchedOperators = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Fout bij zoeken: $e',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  DateTime? _selectedEndTime() {
    final start = _selectedStartTime;
    final hours = _shiftHours;
    if (start == null || hours <= 0) return null;
    return _combine(_plannedDate, start).add(Duration(minutes: (hours * 60).round()));
  }

  Future<void> _submitPlan() async {
    if (_saving || _selectedOperatorId == null) return;
    final start = _selectedStartTime;
    final end = _selectedEndTime();
    final hours = _shiftHours;
    if (start == null || end == null || hours <= 0) return;

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('opdracht_planning').insert({
        'opdracht_id': widget.opdrachtId,
        'operator_id': _selectedOperatorId,
        'geplande_datum': _plannedDateDb,
        'starttijd': _timeToDb(start),
        'eindtijd': _timeToDb(TimeOfDay(hour: end.hour, minute: end.minute)),
        'toegewezen_uren': hours,
        'status': 'gepland',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E8E3E),
          content: Text(
            'Opdracht succesvol ingepland.',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Inplannen mislukt: $e',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF111019) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 30,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Kon opdracht niet laden: $_error',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                  : DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: 56,
                            height: 5,
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _projectName,
                                    style: GoogleFonts.inter(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(alpha: isDark ? 0.08 : 0.05),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: TabBar(
                                splashBorderRadius: BorderRadius.circular(16),
                                dividerColor: Colors.transparent,
                                labelColor: Colors.white,
                                unselectedLabelColor: cs.onSurface.withValues(alpha: 0.70),
                                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w900),
                                indicator: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                tabs: const [
                                  Tab(text: 'Informatie'),
                                  Tab(text: 'Inplannen'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildInfoTab(scrollController, cs, isDark),
                                _buildPlanTab(scrollController, cs, isDark),
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

  Widget _buildInfoTab(ScrollController controller, ColorScheme cs, bool isDark) {
    final address = _text(_opdracht?['uitvoer_adres_volledig']);
    final instructions = _text(_opdracht?['toelichting_planning']).isNotEmpty
        ? _text(_opdracht?['toelichting_planning'])
        : 'Geen toelichting';

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
      children: [
        _infoCard(
          cs,
          isDark,
          title: 'Project',
          value: _projectName,
        ),
        const SizedBox(height: 10),
        _infoCard(
          cs,
          isDark,
          title: 'Klant',
          value: _clientName,
        ),
        const SizedBox(height: 10),
        _infoCard(
          cs,
          isDark,
          title: 'Geplande datum',
          value: _formatDate(_plannedDate),
        ),
        const SizedBox(height: 10),
        _infoCard(
          cs,
          isDark,
          title: 'Tijdslot',
          value: '${_timeToHuman(_windowStart)} - ${_timeToHuman(_windowEnd)}',
        ),
        const SizedBox(height: 10),
        _infoCard(
          cs,
          isDark,
          title: 'Werkregio',
          value: _regio.isEmpty ? '-' : _regio,
        ),
        const SizedBox(height: 10),
        _infoCard(
          cs,
          isDark,
          title: 'Adres',
          value: address.isEmpty ? '-' : address,
        ),
        const SizedBox(height: 10),
        _infoCard(
          cs,
          isDark,
          title: 'Instructies',
          value: instructions,
        ),
      ],
    );
  }

  Widget _buildPlanTab(ScrollController controller, ColorScheme cs, bool isDark) {
    final neededOperators = _asInt(_opdracht?['benodigde_operators'], fallback: 1);
    final canLoadOperators = _selectedStartTime != null && _shiftHours > 0;
    final totalHours = _asDouble(_opdracht?['benodigde_uren_totaal']);
    final standardPerPerson = totalHours / math.max(1, neededOperators);
    final assignedHours = _asDouble(_opdracht?['toegewezen_uren_totaal']);
    final remainingHours = _asDouble(_opdracht?['resterende_uren']);

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
      children: [
        Text(
          'Plan opdracht voor $_projectName',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Nodig: $neededOperators operators • Mogelijk tussen ${_timeToHuman(_windowStart)} en ${_timeToHuman(_windowEnd)}',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: cs.onSurface.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
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
                        color: cs.onSurface.withValues(alpha: 0.66),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatHoursToText(totalHours),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Standaard per persoon',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withValues(alpha: 0.66),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatHoursToText(standardPerPerson),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900),
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
                        color: cs.onSurface.withValues(alpha: 0.66),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatHoursToText(assignedHours),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Nog in te vullen',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withValues(alpha: 0.66),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatHoursToText(remainingHours),
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
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
        Row(
          children: [
            _StepperCircleButton(
              icon: Icons.remove_rounded,
              onPressed: () {
                setState(() {
                  _shiftHours = (_shiftHours - 0.25).clamp(0.25, 24.0);
                  _selectedOperatorId = null;
                });
              },
            ),
            Expanded(
              child: Text(
                formatHoursToText(_shiftHours),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            _StepperCircleButton(
              icon: Icons.add_rounded,
              onPressed: () {
                setState(() {
                  _shiftHours = (_shiftHours + 0.25).clamp(0.25, 24.0);
                  _selectedOperatorId = null;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _startTimeController,
          readOnly: true,
          onTap: _pickStartTime,
          decoration: _fieldDecoration(
            isDark,
            cs,
            'Starttijd',
            Icons.schedule_rounded,
          ).copyWith(
            suffixIcon: IconButton(
              onPressed: _pickStartTime,
              icon: const Icon(Icons.access_time_rounded),
            ),
          ),
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: (_isSearching || !canLoadOperators) ? null : _loadAvailableOperators,
          icon: _isSearching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search_rounded),
          label: Text(
            _isSearching ? 'Operators zoeken...' : 'Zoek Beschikbare Operators',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 12),
        if (_availableOperators.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              !canLoadOperators
                  ? 'Kies eerst starttijd + uren'
                  : _hasSearchedOperators
                      ? 'Geen beschikbare operators gevonden voor dit tijdstip.'
                      : 'Klik op zoek om beschikbare operators te laden.',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withValues(alpha: 0.70),
              ),
            ),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _selectedOperatorId,
            decoration: _fieldDecoration(
              isDark,
              cs,
              'Beschikbare operator',
              Icons.person_outline_rounded,
            ),
            items: _availableOperators
                .whereType<Map>()
                .map((raw) => Map<String, dynamic>.from(raw))
                .map(
                  (op) => DropdownMenuItem<String>(
                    value: _text(op['id']),
                    child: Text(
                      _text(op['naam']).isEmpty
                          ? (_text(op['operator_naam']).isEmpty ? 'Onbekende operator' : _text(op['operator_naam']))
                          : _text(op['naam']),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: !canLoadOperators || _isSearching
                ? null
                : (value) => setState(() => _selectedOperatorId = value),
          ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: (_selectedOperatorId == null || _saving) ? null : _submitPlan,
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  'Definitief Inplannen',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                ),
        ),
      ],
    );
  }

  Widget _infoCard(
    ColorScheme cs,
    bool isDark, {
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B23) : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: cs.onSurface.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(
    bool isDark,
    ColorScheme cs,
    String label,
    IconData icon,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: isDark ? const Color(0xFF1B1B23) : const Color(0xFFF5F5F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 1.2),
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
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: cs.primary),
        ),
      ),
    );
  }
}
