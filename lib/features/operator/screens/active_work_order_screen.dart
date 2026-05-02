import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persistente checklist voor een actieve werkbon. Vinkjes zijn alleen lokaal (geen DB per tick).
class ActiveWorkOrderScreen extends StatefulWidget {
  final String opdrachtId;
  final String planningId;
  final String? startTime;

  const ActiveWorkOrderScreen({
    super.key,
    required this.opdrachtId,
    required this.planningId,
    this.startTime,
  });

  @override
  State<ActiveWorkOrderScreen> createState() => _ActiveWorkOrderScreenState();
}

class _ActiveWorkOrderScreenState extends State<ActiveWorkOrderScreen> {
  /// Blijft behouden tijdens de sessie als de operator terugkeert naar dezelfde werkbon.
  static final Map<String, Set<String>> _checkedByOpdracht = {};

  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isClockingOut = false;
  String _errorMessage = '';

  Map<String, List<Map<String, dynamic>>> _groupedTasks = {};
  late final Set<String> _checkedTasks;

  Timer? _liveTimer;
  DateTime? _parsedStartTime;
  String _elapsedTime = '00:00:00';

  @override
  void initState() {
    super.initState();
    _checkedTasks = _checkedByOpdracht.putIfAbsent(widget.opdrachtId, () => <String>{});
    _initLiveTimer();
    _loadChecklist();
  }

  void _initLiveTimer() {
    final raw = widget.startTime?.trim();
    if (raw == null || raw.isEmpty) return;
    try {
      final parts = raw.split(':');
      if (parts.length < 2) return;
      final now = DateTime.now();
      _parsedStartTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
        parts.length > 2 ? int.parse(parts[2].split('.').first) : 0,
      );
      _tickElapsed();
      _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickElapsed());
    } catch (_) {
      _parsedStartTime = null;
    }
  }

  void _tickElapsed() {
    final start = _parsedStartTime;
    if (start == null || !mounted) return;
    final diff = DateTime.now().difference(start);
    if (diff.isNegative) return;
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    setState(() => _elapsedTime = '$h:$m:$s');
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadChecklist() async {
    try {
      final response = await _supabase
          .from('opdracht_checklist')
          .select()
          .eq('opdracht_id', widget.opdrachtId);

      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final row in response as List) {
        final r = Map<String, dynamic>.from(row as Map);
        final roomName = r['ruimte_naam']?.toString() ?? 'Algemene Ruimte';
        grouped.putIfAbsent(roomName, () => []).add(r);
      }

      if (mounted) {
        setState(() {
          _groupedTasks = grouped;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _taskKey(String roomName, int index, Map<String, dynamic> t) {
    final label = t['uit_te_voeren_taak']?.toString() ?? '';
    return '$roomName|$index|$label';
  }

  Future<void> _onUitklokken() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Uitklokken'),
        content: const Text(
          'Weet u zeker dat u wilt uitklokken? Dit sluit de werkbon definitief af en registreert uw uren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuleren', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Uitklokken', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isClockingOut = true);
    try {
      final nowString = DateTime.now().toIso8601String().substring(11, 19);
      debugPrint('X-RAY: Attempting to Clock Out for planning_id: ${widget.planningId}');

      final updateResponse = await _supabase.from('opdracht_planning').update({
        'status': 'voltooid',
        'werkelijke_eindtijd': nowString,
      }).eq('id', widget.planningId.toString()).select();

      debugPrint('X-RAY: Clock Out Success! Response: $updateResponse');

      if (mounted) {
        _checkedByOpdracht.remove(widget.opdrachtId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Klus voltooid en afgemeld!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      debugPrint('X-RAY FATAL: Clock Out Failed: $e');
      debugPrint('$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout bij uitklokken: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isClockingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        leading: const BackButton(color: Colors.black),
        title: Text('Actieve Werkbon', style: GoogleFonts.lato(fontWeight: FontWeight.w900, color: Colors.black)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_parsedStartTime != null) _buildLiveTimerHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CupertinoActivityIndicator(radius: 16))
                : _errorMessage.isNotEmpty
                    ? Center(child: Text('Fout: $_errorMessage', style: const TextStyle(color: Colors.red)))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: _groupedTasks.entries.map((entry) => _buildRoomCard(entry.key, entry.value)).toList(),
                      ),
          ),
          if (!_isLoading && _errorMessage.isEmpty) _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildLiveTimerHeader() {
    return Material(
      elevation: 2,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.red.shade50,
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              Icon(Icons.timer, color: Colors.red.shade700, size: 26),
              const SizedBox(width: 12),
              Text(
                _elapsedTime,
                style: GoogleFonts.lato(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.red.shade800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomCard(String roomName, List<Map<String, dynamic>> tasks) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(roomName, style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold)),
        children: [
          for (var i = 0; i < tasks.length; i++)
            _buildTaskTile(roomName, i, tasks[i]),
        ],
      ),
    );
  }

  Widget _buildTaskTile(String roomName, int index, Map<String, dynamic> t) {
    final key = _taskKey(roomName, index, t);
    final isChecked = _checkedTasks.contains(key);
    final label = t['uit_te_voeren_taak']?.toString() ?? 'Taak';

    return CheckboxListTile(
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          decoration: isChecked ? TextDecoration.lineThrough : null,
          color: isChecked ? Colors.grey : Colors.black87,
        ),
      ),
      value: isChecked,
      activeColor: Colors.green,
      checkColor: Colors.white,
      onChanged: (val) {
        setState(() {
          if (val == true) {
            _checkedTasks.add(key);
          } else {
            _checkedTasks.remove(key);
          }
        });
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -4)),
        ],
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isClockingOut ? null : _onUitklokken,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.red.shade200,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _isClockingOut
                ? const CupertinoActivityIndicator(color: Colors.white)
                : Text(
                    '⏹ UITKLOKKEN & AFRONDEN',
                    style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
          ),
        ),
      ),
    );
  }
}
