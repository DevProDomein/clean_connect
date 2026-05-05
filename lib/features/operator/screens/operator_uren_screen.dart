import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_drawer.dart';

/// Operator: dashboard voor bruto salaris ([loonadministratie_maand]) en
/// afgeronde diensten ([opdracht_planning], status `voltooid`).
class OperatorUrenScreen extends StatefulWidget {
  const OperatorUrenScreen({super.key});

  @override
  State<OperatorUrenScreen> createState() => _OperatorUrenScreenState();
}

class _OperatorUrenScreenState extends State<OperatorUrenScreen>
    with SingleTickerProviderStateMixin {
  static const Color _deepNavy = Color(0xFF1A237E);
  static const Color _brightBlue = Color(0xFF0052CC);
  static const Color _pageBg = Color(0xFFF2F4F8);

  List<Map<String, dynamic>> _maandenLijst = [];
  List<Map<String, dynamic>> _shiftsLijst = [];
  bool _isLoading = true;
  String _errorMessage = '';

  late final TabController _tabController;

  final NumberFormat _eur = NumberFormat.currency(
    locale: 'nl_NL',
    symbol: '€',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Niet ingelogd.';
        _maandenLijst = [];
        _shiftsLijst = [];
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final client = Supabase.instance.client;

      final pair = await Future.wait([
        client
            .from('loonadministratie_maand')
            .select()
            .eq('operator_id', uid)
            .order('kalender_maand', ascending: false),
        client
            .from('opdracht_planning')
            .select()
            .eq('operator_id', uid)
            .eq('status', 'voltooid')
            .order('geplande_datum', ascending: false)
            .limit(50),
      ]);

      final maanden = (pair[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final shifts = (pair[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // ignore: avoid_print
      print('X-RAY UREN DATA: $maanden');

      if (!mounted) return;
      setState(() {
        _maandenLijst = maanden;
        _shiftsLijst = shifts;
        _isLoading = false;
        _errorMessage = '';
      });
    } catch (e, st) {
      debugPrint('OperatorUrenScreen._loadData error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _maandenLijst = [];
        _shiftsLijst = [];
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  String _currentKalenderMaandKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  /// Nieuwste rij uit [loonadministratie_maand] (zelfde bron als dashboard-weergave).
  Map<String, dynamic>? _nieuwsteLoonMaandRow() {
    if (_maandenLijst.isEmpty) return null;
    return _maandenLijst.first;
  }

  String _kalenderMaandKey(dynamic v) {
    if (v == null) return '';
    if (v is DateTime) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}';
    }
    var s = v.toString().trim();
    if (s.length >= 7 && s.contains('-')) {
      s = s.substring(0, 7);
    }
    return s;
  }

  String _formatMaand(dynamic kalenderMaand) {
    final s = _kalenderMaandKey(kalenderMaand);
    final parts = s.split('-');
    if (parts.length != 2) return s.isEmpty ? '—' : s;
    final maanden = {
      '01': 'Januari',
      '02': 'Februari',
      '03': 'Maart',
      '04': 'April',
      '05': 'Mei',
      '06': 'Juni',
      '07': 'Juli',
      '08': 'Augustus',
      '09': 'September',
      '10': 'Oktober',
      '11': 'November',
      '12': 'December',
    };
    final mm = parts[1].length == 1 ? '0${parts[1]}' : parts[1];
    return '${maanden[mm] ?? parts[1]} ${parts[0]}';
  }

  String _formatMaandLongNl(dynamic kalenderMaand) {
    final d = _parseKalenderMaand(kalenderMaand);
    if (d == null) return _formatMaand(kalenderMaand);
    return DateFormat.yMMMM('nl_NL').format(DateTime(d.year, d.month));
  }

  DateTime? _parseKalenderMaand(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return DateTime(v.year, v.month);
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final dt = DateTime.tryParse(s);
    if (dt != null) return DateTime(dt.year, dt.month);
    final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(s);
    if (m != null) {
      final y = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      if (y != null && mo != null && mo >= 1 && mo <= 12) {
        return DateTime(y, mo);
      }
    }
    return null;
  }

  String _formatBruto(dynamic v) => _eur.format(_parseLoonDouble(v));

  /// Weergave met komma als decimaal (nl_NL), bv. `1,5`.
  String _formatUrenNl(dynamic v) {
    final d = _asDouble(v);
    if (d == 0 && v == null) return '0';
    if (d == d.roundToDouble()) return d.toInt().toString();
    return NumberFormat.decimalPattern('nl_NL').format(d);
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(' ', '');
    if (s.isEmpty) return 0;
    final direct = double.tryParse(s);
    if (direct != null) return direct;
    if (s.contains(',')) {
      return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  /// Parser voor loon-kolommen: eerst `double.tryParse(.toString())` (int-safe),
  /// daarna nl.-notatie (`1.234,56`).
  double _parseLoonDouble(dynamic v) {
    if (v == null) return 0.0;
    final normalized =
        v.toString().trim().replaceAll(' ', '').replaceAll('€', '');
    if (normalized.isEmpty) return 0.0;
    final fromTryParse = double.tryParse(normalized);
    if (fromTryParse != null) return fromTryParse;
    if (normalized.contains(',')) {
      return double.tryParse(
            normalized.replaceAll('.', '').replaceAll(',', '.'),
          ) ??
          0.0;
    }
    return 0.0;
  }

  DateTime? _parseShiftDay(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);
    final s = raw.toString().trim();
    if (s.length >= 10) {
      try {
        final d = DateTime.parse(s.substring(0, 10));
        return DateTime(d.year, d.month, d.day);
      } catch (_) {}
    }
    return null;
  }

  double _urenDezeWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final windowStart = today.subtract(const Duration(days: 6));
    double sum = 0;
    for (final row in _shiftsLijst) {
      final day = _parseShiftDay(row['geplande_datum']);
      if (day == null) continue;
      if (!day.isBefore(windowStart) && !day.isAfter(today)) {
        sum += _asDouble(row['gewerkte_uren_decimaal']);
      }
    }
    return sum;
  }

  String _shiftBedrijfsnaam(Map<String, dynamic> row) {
    final direct = row['bedrijfsnaam']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = row['opdrachten'];
    if (nested is Map && nested['bedrijfsnaam'] != null) {
      final b = nested['bedrijfsnaam'].toString().trim();
      if (b.isNotEmpty) return b;
    }
    return 'Locatie';
  }

  String _safeTime(dynamic timeValue) {
    if (timeValue == null) return '—';
    final t = timeValue.toString().trim();
    if (t.length >= 5) return t.substring(0, 5);
    return t.isEmpty ? '—' : t;
  }

  ({Color bg, Color fg, String label}) _statusPillUi(String? raw) {
    final s = (raw ?? '').toLowerCase().trim();
    if (s == 'uitbetaald') {
      return (
        bg: const Color(0xFFDCFCE7),
        fg: const Color(0xFF166534),
        label: 'Uitbetaald',
      );
    }
    return (
      bg: const Color(0xFFF3F4F6),
      fg: const Color(0xFF4B5563),
      label: 'Open',
    );
  }

  List<Map<String, dynamic>> _maandenHistorieZonderHuidigeMaand() {
    final key = _currentKalenderMaandKey();
    return _maandenLijst
        .where((row) => _kalenderMaandKey(row['kalender_maand']) != key)
        .toList();
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  BoxDecoration _kpiDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _heroCard(Map<String, dynamic>? row) {
    final double displayAmount;
    final double displayHours;
    if (row != null) {
      final rawAmount = row['totaal_bruto_verdiend'];
      final rawHours = row['totaal_gewerkte_uren'];
      displayAmount =
          double.tryParse(rawAmount?.toString().trim() ?? '') ??
              _parseLoonDouble(rawAmount);
      displayHours =
          double.tryParse(rawHours?.toString().trim() ?? '') ??
              _parseLoonDouble(rawHours);
    } else {
      displayAmount = 0.0;
      displayHours = 0.0;
    }

    final brutoText = _eur.format(displayAmount);
    final urenText = displayHours == displayHours.roundToDouble()
        ? displayHours.toInt().toString()
        : NumberFormat.decimalPattern('nl_NL').format(displayHours);

    final emptyMonthRows = row == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_deepNavy, _brightBlue],
        ),
        boxShadow: [
          BoxShadow(
            color: _brightBlue.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Verwacht Bruto Salaris',
            style: GoogleFonts.lato(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          if (emptyMonthRows)
            Text(
              'Nog geen uren geregistreerd.',
              style: GoogleFonts.lato(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.35,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            )
          else ...[
            Text(
              brutoText,
              style: GoogleFonts.lato(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: Colors.white,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Text('🕒', style: GoogleFonts.lato(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$urenText uur geregistreerd',
                    style: GoogleFonts.lato(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpiChip({
    required String title,
    required String value,
    IconData? icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        decoration: _kpiDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.lato(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.lato(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiRow() {
    final weekUren = _urenDezeWeek();
    final weekLabel = weekUren == weekUren.roundToDouble()
        ? '${weekUren.toInt()} u'
        : '${weekUren.toStringAsFixed(1)} u';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          _kpiChip(
            title: 'Totaal diensten',
            value: '${_shiftsLijst.length}',
            icon: Icons.calendar_month_rounded,
          ),
          const SizedBox(width: 12),
          _kpiChip(
            title: 'Uren deze week',
            value: weekLabel,
            icon: Icons.schedule_rounded,
          ),
        ],
      ),
    );
  }

  Widget _premiumShiftCard(Map<String, dynamic> row) {
    final day = _parseShiftDay(row['geplande_datum']);
    final dayNum = day != null ? '${day.day}' : '—';
    final naam = _shiftBedrijfsnaam(row);
    final t0 = _safeTime(row['werkelijke_starttijd']);
    final t1 = _safeTime(row['werkelijke_eindtijd']);
    final tijden = '$t0 – $t1';
    final urenLabel = '${_formatUrenNl(row['gewerkte_uren_decimaal'])} u';
    final brutoText = _formatBruto(row['bruto_loonkosten']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: _cardDecoration(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEEF2FF),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              alignment: Alignment.center,
              child: Text(
                dayNum,
                style: GoogleFonts.lato(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: _deepNavy,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    naam,
                    style: GoogleFonts.lato(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tijden,
                    style: GoogleFonts.lato(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Geregistreerde uren',
                  style: GoogleFonts.lato(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  urenLabel,
                  style: GoogleFonts.lato(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  brutoText,
                  style: GoogleFonts.lato(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _shiftTile(Map<String, dynamic> row) => _premiumShiftCard(row);

  Widget _maandHistorieTile(Map<String, dynamic> row) {
    final maand = _formatMaandLongNl(row['kalender_maand']);
    final rawUren = row['totaal_gewerkte_uren'];
    final rawBruto = row['totaal_bruto_verdiend'];
    final urenVal =
        double.tryParse(rawUren?.toString().trim() ?? '') ??
            _parseLoonDouble(rawUren);
    final brutoVal =
        double.tryParse(rawBruto?.toString().trim() ?? '') ??
            _parseLoonDouble(rawBruto);
    final uren = urenVal == urenVal.roundToDouble()
        ? urenVal.toInt().toString()
        : NumberFormat.decimalPattern('nl_NL').format(urenVal);
    final bruto = _eur.format(brutoVal);
    final pill = _statusPillUi(row['status']?.toString());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showMonthDetails(row['kalender_maand']),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            maand,
                            style: GoogleFonts.lato(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$uren uur · $bruto',
                            style: GoogleFonts.lato(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: pill.bg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        pill.label,
                        style: GoogleFonts.lato(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          color: pill.fg,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Bekijk specificatie',
                      style: GoogleFonts.lato(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: _brightBlue,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: _brightBlue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMonthDetails(dynamic kalenderMaandRaw) async {
    final kalenderMaand = _kalenderMaandKey(kalenderMaandRaw);
    if (kalenderMaand.isEmpty || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final height = MediaQuery.sizeOf(sheetContext).height * 0.8;
        return SelectionArea(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              height: height,
              color: _pageBg,
              child: _MaandShiftsModal(
                kalenderMaand: kalenderMaand,
                headerTitle: _formatMaand(kalenderMaand),
                shiftTile: _premiumShiftCard,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _emptyShifts() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
      child: Text(
        'Je hebt nog geen afgeronde diensten.',
        textAlign: TextAlign.center,
        style: GoogleFonts.lato(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _emptyMaandenHistorie() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
      child: Text(
        'Geen eerdere maanden beschikbaar.',
        textAlign: TextAlign.center,
        style: GoogleFonts.lato(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
          height: 1.45,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        title: Text(
          'Mijn Uren & Salaris',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.5,
            color: const Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
            tooltip: 'Vernieuwen',
          ),
        ],
      ),
      body: SelectionArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(radius: 18));
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'Kon gegevens niet laden.\n$_errorMessage',
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: Colors.red.shade800,
              height: 1.45,
            ),
          ),
        ),
      );
    }

    final heroRow = _nieuwsteLoonMaandRow();

    return RefreshIndicator(
      color: _brightBlue,
      onRefresh: _loadData,
      child: NestedScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _heroCard(heroRow),
              ),
            ),
            SliverToBoxAdapter(child: _buildKpiRow()),
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverPersistentHeader(
                pinned: true,
                delegate: _UrenStickyTabsDelegate(
                  tabBar: Material(
                    color: _pageBg,
                    elevation: innerBoxIsScrolled ? 1 : 0,
                    shadowColor: Colors.black.withValues(alpha: 0.06),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: _brightBlue,
                      unselectedLabelColor: Colors.grey.shade600,
                      indicatorColor: _brightBlue,
                      indicatorWeight: 3,
                      labelStyle: GoogleFonts.lato(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: -0.5,
                      ),
                      unselectedLabelStyle: GoogleFonts.lato(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: -0.5,
                      ),
                      tabs: const [
                        Tab(text: 'Recente diensten'),
                        Tab(text: 'Maandoverzichten'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            Builder(
              builder: (context) {
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverOverlapInjector(
                      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                          context),
                    ),
                    if (_shiftsLijst.isEmpty)
                      SliverToBoxAdapter(child: _emptyShifts())
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) =>
                                _shiftTile(_shiftsLijst[index]),
                            childCount: _shiftsLijst.length,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            Builder(
              builder: (context) {
                final hist = _maandenHistorieZonderHuidigeMaand();
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverOverlapInjector(
                      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                          context),
                    ),
                    if (hist.isEmpty)
                      SliverToBoxAdapter(child: _emptyMaandenHistorie())
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) =>
                                _maandHistorieTile(hist[index]),
                            childCount: hist.length,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MaandShiftsModal extends StatefulWidget {
  const _MaandShiftsModal({
    required this.kalenderMaand,
    required this.headerTitle,
    required this.shiftTile,
  });

  final String kalenderMaand;
  final String headerTitle;
  final Widget Function(Map<String, dynamic> row) shiftTile;

  @override
  State<_MaandShiftsModal> createState() => _MaandShiftsModalState();
}

class _MaandShiftsModalState extends State<_MaandShiftsModal> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Niet ingelogd.';
      });
      return;
    }

    try {
      final raw = await Supabase.instance.client
          .from('view_operator_maand_shifts')
          .select()
          .eq('operator_id', uid)
          .eq('kalender_maand', widget.kalenderMaand)
          .order('geplande_datum', ascending: false);

      final list = (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
        _errorMessage = '';
      });
    } catch (e, st) {
      debugPrint('_MaandShiftsModal._load error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Diensten in ${widget.headerTitle}',
                    style: GoogleFonts.lato(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: const Color(0xFF0F172A),
                      height: 1.25,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.grey.shade700,
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Sluiten',
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator(radius: 18))
                : _errorMessage.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Kon diensten niet laden.\n$_errorMessage',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Colors.red.shade800,
                            height: 1.45,
                          ),
                        ),
                      )
                    : _rows.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                'Geen diensten gevonden voor deze maand.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.lato(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade600,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                            itemCount: _rows.length,
                            itemBuilder: (context, index) =>
                                widget.shiftTile(_rows[index]),
                          ),
          ),
        ],
      ),
    );
  }
}

class _UrenStickyTabsDelegate extends SliverPersistentHeaderDelegate {
  _UrenStickyTabsDelegate({required this.tabBar});

  final Widget tabBar;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(height: 48, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _UrenStickyTabsDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar;
  }
}