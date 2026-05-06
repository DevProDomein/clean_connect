import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_drawer.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';
import 'active_work_order_screen.dart';
import '../widgets/packing_list_modal.dart';

class OperatorRoosterScreen extends StatefulWidget {
  const OperatorRoosterScreen({super.key});

  @override
  State<OperatorRoosterScreen> createState() => _OperatorRoosterScreenState();
}

class _OperatorRoosterScreenState extends State<OperatorRoosterScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String _errorMessage = '';

  String _voornaam = 'Collega';
  String? _profielfotoUrl;

  List<Map<String, dynamic>> _todaysTasks = [];
  List<Map<String, dynamic>> _upcomingTasks = [];
  int _kpiTakenVandaag = 0;
  int _kpiDezeWeek = 0;

  Timer? _liveTimer;
  DateTime _now = DateTime.now();

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour <= 11) return 'Goedemorgen';
    if (hour >= 12 && hour <= 17) return 'Goedemiddag';
    return 'Goedenavond';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    if (silent) {
      setState(() => _errorMessage = '');
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw 'Niet ingelogd.';

      try {
        final userData = await _supabase
            .from('gebruikers')
            .select('voornaam, profielfoto_url')
            .eq('id', userId)
            .maybeSingle();
        if (userData != null) {
          _voornaam = userData['voornaam'] ?? 'Collega';
          _profielfotoUrl = userData['profielfoto_url'];
        }
      } catch (e) {
        debugPrint('Fout bij ophalen profiel: $e');
      }

      final response = await _supabase
          .from('app_operator_vandaag')
          .select()
          .eq('operator_id', userId)
          .order('geplande_datum', ascending: true)
          .order('rooster_starttijd', ascending: true);

      final String todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final DateTime todayDate = DateTime.now();
      final DateTime todayDay = DateTime(todayDate.year, todayDate.month, todayDate.day);
      final DateTime weekStart = todayDay.subtract(Duration(days: todayDay.weekday - 1));
      final DateTime weekEnd = weekStart.add(const Duration(days: 6));
      final DateTime upcomingWindowEnd = todayDay.add(const Duration(days: 31));

      final List<Map<String, dynamic>> today = [];
      final List<Map<String, dynamic>> upcoming = [];
      int kpiVandaag = 0;
      int kpiWeek = 0;

      for (final row in response as List) {
        final task = Map<String, dynamic>.from(row as Map);
        final raw = task['geplande_datum']?.toString() ?? '';
        final dateStr = raw.length >= 10 ? raw.substring(0, 10) : raw;

        DateTime taskDay;
        try {
          final parsed = DateTime.parse(dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr);
          taskDay = DateTime(parsed.year, parsed.month, parsed.day);
        } catch (_) {
          continue;
        }

        if (!taskDay.isBefore(weekStart) && !taskDay.isAfter(weekEnd)) {
          kpiWeek++;
        }

        if (dateStr == todayStr) {
          today.add(task);
        } else if (taskDay.isAfter(todayDay) && !taskDay.isAfter(upcomingWindowEnd)) {
          upcoming.add(task);
        }
      }

      kpiVandaag = today.length;

      if (mounted) {
        setState(() {
          _todaysTasks = today;
          _upcomingTasks = upcoming;
          _kpiTakenVandaag = kpiVandaag;
          _kpiDezeWeek = kpiWeek;
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

  Widget _buildHeroBanner() {
    final String dateString = "Klaar voor je shift?";

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  bottomLeft: Radius.circular(32),
                ),
                image: DecorationImage(
                  image: NetworkImage(
                    'https://images.unsplash.com/photo-1581578731548-c64695cc6952?auto=format&fit=crop&w=1200&q=80',
                  ),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(32),
                    bottomLeft: Radius.circular(32),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF0F172A).withValues(alpha: 0.95),
                      const Color(0xFF0052CC).withValues(alpha: 0.85),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      dateString,
                      style: TextStyle(
                        color: Colors.blue.shade100,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${_getGreeting()}, $_voornaam! 👋',
                        style: GoogleFonts.lato(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_profielfotoUrl != null && _profielfotoUrl!.isNotEmpty)
            Container(
              width: 110,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundImage: NetworkImage(_profielfotoUrl!),
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getLiveDuration(dynamic startTimeStr) {
    if (startTimeStr == null) return '00:00:00';
    final s = startTimeStr.toString().trim();
    if (s.isEmpty) return '00:00:00';
    try {
      final now = DateTime.now();
      final parts = s.split(':');
      if (parts.length < 2) return '00:00:00';
      final start = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
        parts.length > 2 ? int.parse(parts[2].split('.').first) : 0,
      );

      final diff = _now.difference(start);
      if (diff.isNegative) return '00:00:00';

      String twoDigits(int n) => n.toString().padLeft(2, '0');
      return '${twoDigits(diff.inHours)}:${twoDigits(diff.inMinutes.remainder(60))}:${twoDigits(diff.inSeconds.remainder(60))}';
    } catch (_) {
      return '--:--:--';
    }
  }

  String _safeTime(dynamic timeValue) {
    if (timeValue == null) return '00:00';
    String t = timeValue.toString();
    if (t.length >= 5) return t.substring(0, 5);
    return t;
  }

  String _normStatus(dynamic v) {
    var s = (v ?? '').toString().trim().toLowerCase().replaceAll(' ', '_');
    if (s.contains('voltooi') || s == 'afgerond') return 'voltooid';
    if (s.contains('uitvoering')) return 'in_uitvoering';
    if (s == 'ingepland') return 'gepland';
    return s;
  }

  void _openPaklijst(String opdrachtId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SelectionArea(
        child: PackingListModal(opdrachtId: opdrachtId),
      ),
    );
  }

  void _openActieveOpdracht(Map<String, dynamic> task) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ActiveWorkOrderScreen(
          opdrachtId: task['opdracht_id'].toString(),
          planningId: task['planning_id'].toString(),
          startTime: task['werkelijke_starttijd']?.toString(),
        ),
      ),
    ).then((_) {
      if (mounted) _loadData(silent: true);
    });
  }

  Future<void> _startOpdracht(Map<String, dynamic> task) async {
    setState(() => _isLoading = true);
    try {
      final nowString = DateTime.now().toIso8601String().substring(11, 19);

      debugPrint('X-RAY: Attempting to Clock In for planning_id: ${task['planning_id']}');

      final updateResponse = await _supabase.from('opdracht_planning').update({
        'status': 'in_uitvoering',
        'werkelijke_starttijd': nowString,
      }).eq('id', task['planning_id'].toString()).select();

      debugPrint('X-RAY: Clock In Success! Response: $updateResponse');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingeklokt!'), backgroundColor: Colors.green),
        );
        await Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ActiveWorkOrderScreen(
              opdrachtId: task['opdracht_id'].toString(),
              planningId: task['planning_id'].toString(),
              startTime: nowString,
            ),
          ),
        );
        _loadData();
      }
    } catch (e, st) {
      debugPrint('X-RAY FATAL: Clock In Failed: $e');
      debugPrint('$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout bij inklokken: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: Theme.of(context).appBarTheme.iconTheme,
        title: const Text(''),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: SelectionArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CupertinoActivityIndicator(radius: 16));
    if (_errorMessage.isNotEmpty) {
      return Center(child: Text('Fout: $_errorMessage', style: const TextStyle(color: Colors.red)));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeroBanner()),
          SliverToBoxAdapter(child: _buildKpis()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'VANDAAG UIT TE VOEREN',
                style: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.blueAccent, letterSpacing: 1.0),
              ),
            ),
          ),
          if (_todaysTasks.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    Icon(Icons.done_all, size: 64, color: Colors.green.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'Je bent helemaal klaar voor vandaag!',
                      style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (c, i) => _buildTodayCard(_todaysTasks[i]),
                childCount: _todaysTasks.length,
              ),
            ),
          if (_upcomingTasks.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
                child: Text(
                  'KOMENDE MAAND',
                  style: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.grey.shade600, letterSpacing: 1.0),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (c, i) => _buildUpcomingCard(_upcomingTasks[i]),
                  childCount: _upcomingTasks.length,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: mobileNavBuffer)),
        ],
      ),
    );
  }

  Widget _buildKpis() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _kpiCard('Taken vandaag', '$_kpiTakenVandaag', Icons.today, Colors.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _kpiCard('Deze week', '$_kpiDezeWeek', Icons.calendar_month, Colors.blue),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color.shade400, size: 24),
              Text(value, style: GoogleFonts.lato(fontSize: 24, fontWeight: FontWeight.w900, color: color.shade700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildTodayCard(Map<String, dynamic> task) {
    final String status = _normStatus(task['mijn_persoonlijke_status']);
    final isActive = status == 'in_uitvoering';
    final isGepland = status == 'gepland';
    final isVoltooid = status == 'voltooid';

    String badgeLabel;
    Color badgeColor;
    Color bgChip;
    if (isActive) {
      badgeLabel = 'Nu Bezig';
      badgeColor = Colors.blueAccent;
      bgChip = Colors.blue.shade50;
    } else if (isGepland) {
      badgeLabel = 'Gepland';
      badgeColor = Colors.grey.shade600;
      bgChip = Colors.grey.shade100;
    } else if (isVoltooid) {
      badgeLabel = 'Voltooid';
      badgeColor = Colors.green.shade700;
      bgChip = Colors.green.shade50;
    } else {
      badgeLabel = task['mijn_persoonlijke_status']?.toString() ?? '—';
      badgeColor = Colors.grey.shade700;
      bgChip = Colors.grey.shade100;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: isActive ? Border.all(color: Colors.blueAccent, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_safeTime(task['rooster_starttijd'])} - ${_safeTime(task['rooster_eindtijd'])}',
                style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: bgChip, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  badgeLabel,
                  style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(task['bedrijfsnaam'] ?? 'Onbekende Klant', style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.business_center, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Expanded(child: Text(task['project_naam'] ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 14))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  task['uitvoer_adres_volledig'] ?? 'Adres onbekend',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                ),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openPaklijst(task['opdracht_id'].toString()),
                icon: const Text('📦', style: TextStyle(fontSize: 16)),
                label: const Text('Paklijst'),
                style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildTodayPrimaryActions(task, status)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodayPrimaryActions(Map<String, dynamic> task, String status) {
    if (status == 'gepland') {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: () => _startOpdracht(task),
        child: const Text('▶ INKLOKKEN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      );
    } else if (status == 'in_uitvoering') {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer, color: Colors.red.shade700, size: 18),
                const SizedBox(width: 8),
                Text(
                  _getLiveDuration(task['werkelijke_starttijd']),
                  style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => _openActieveOpdracht(task),
              child: const Text('Open Opdracht', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    } else if (status == 'voltooid') {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey.shade400,
          disabledBackgroundColor: Colors.grey.shade400,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: const Text('Afgerond', style: TextStyle(fontWeight: FontWeight.bold)),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildUpcomingCard(Map<String, dynamic> task) {
    final raw = task['geplande_datum']?.toString() ?? '';
    final dateLabel = raw.length >= 10 ? raw.substring(0, 10) : raw;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
          child: Icon(Icons.calendar_month, color: Colors.grey.shade600, size: 20),
        ),
        title: Text(task['bedrijfsnaam'] ?? 'Onbekend', style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(
          '$dateLabel • ${_safeTime(task['rooster_starttijd'])}',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade300),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Deze taak is gepland voor de toekomst.')),
          );
        },
      ),
    );
  }
}
