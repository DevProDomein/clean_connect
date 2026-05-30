import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_drawer.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';
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
      final DateTime todayDay = DateTime(
        todayDate.year,
        todayDate.month,
        todayDate.day,
      );
      final DateTime weekStart = todayDay.subtract(
        Duration(days: todayDay.weekday - 1),
      );
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
          final parsed = DateTime.parse(
            dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr,
          );
          taskDay = DateTime(parsed.year, parsed.month, parsed.day);
        } catch (_) {
          continue;
        }

        if (!taskDay.isBefore(weekStart) && !taskDay.isAfter(weekEnd)) {
          kpiWeek++;
        }

        if (dateStr == todayStr) {
          today.add(task);
        } else if (taskDay.isAfter(todayDay) &&
            !taskDay.isAfter(upcomingWindowEnd)) {
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

  void _openMijnUren() {
    Navigator.of(context).pushNamed('/operator/uren');
  }

  String _planningIdFromItem(Map<String, dynamic> item) {
    final pid = item['planning_id']?.toString().trim();
    if (pid != null && pid.isNotEmpty) return pid;
    return item['id']?.toString().trim() ?? '';
  }

  String _statusRaw(Map<String, dynamic> item) {
    final s = item['status'] ?? item['planning_status'];
    if (s != null && s.toString().trim().isNotEmpty) {
      return s.toString().trim().toLowerCase();
    }
    final pers = item['mijn_persoonlijke_status']?.toString().trim().toLowerCase();
    if (pers == 'voltooid') return 'afgerond';
    return pers ?? 'ingepland';
  }

  String _urenStatusRaw(Map<String, dynamic> item) =>
      (item['uren_status'] ?? 'open').toString().trim().toLowerCase();

  String? _offerteIdUitOpdrachtEmbed(Map<String, dynamic> opdrachtData) {
    final projectData = opdrachtData['projecten'];
    if (projectData == null) return null;
    if (projectData is List && projectData.isNotEmpty) {
      return projectData.first['offerte_id']?.toString();
    }
    if (projectData is Map) {
      return projectData['offerte_id']?.toString();
    }
    return null;
  }

  bool _isGeldigeOfferteId(String? id) {
    if (id == null) return false;
    final s = id.trim();
    return s.isNotEmpty && s != 'null';
  }

  String _getMatNaam(dynamic item) {
    if (item == null) return '';
    final Map<String, dynamic> d = item is Map<String, dynamic>
        ? item
        : (item is Map ? Map<String, dynamic>.from(item) : {});
    return (d['artikelnaam'] ??
            d['artikel_naam'] ??
            d['materiaal_naam'] ??
            d['naam'] ??
            d['omschrijving'] ??
            '')
        .toString()
        .trim();
  }

  _PaklijstMateriaal? _materiaalUitRelatieMap(Map<String, dynamic> mat) {
    final naam = _getMatNaam(mat);
    if (naam.isEmpty) return null;
    final foto = mat['foto_url']?.toString().trim();
    return _PaklijstMateriaal(
      naam: naam,
      fotoUrl: (foto != null && foto.isNotEmpty) ? foto : null,
      isVermenigvuldigbaar: mat['is_vermenigvuldigbaar'] != false,
      vereistTransport: mat['vereist_transport'] == true,
    );
  }

  _OpdrachtPaklijstData _parseRuimtesNaarPaklijst(
    List<dynamic> ruimtes,
    String effectiefFreqType,
  ) {
    final ruimteLijst = <({String label, List<_PaklijstMateriaal> materialen})>[];

    for (final ruimte in ruimtes) {
      if (ruimte is! Map) continue;
      final ruimtesDienstenRaw = ruimte['offerte_ruimte_diensten'];
      final List<dynamic> diensten = ruimtesDienstenRaw is List
          ? ruimtesDienstenRaw
          : (ruimtesDienstenRaw != null ? [ruimtesDienstenRaw] : []);
      final ruimteMap = <String, _PaklijstMateriaal>{};

      for (final d in diensten) {
        if (d is! Map) continue;
        final fLabel =
            d['frequentie_label']?.toString().toLowerCase() ?? 'regulier';
        var isActief = false;
        if (effectiefFreqType == 'regulier' && fLabel == 'regulier') {
          isActief = true;
        }
        if (effectiefFreqType == 'frequent' && fLabel == 'frequent') {
          isActief = true;
        }
        if (effectiefFreqType == 'periodiek' && fLabel == 'periodiek') {
          isActief = true;
        }

        if (!isActief || d['moeder_bestek'] == null) continue;

        final mbRaw = d['moeder_bestek'];
        final Map<String, dynamic> mb = (mbRaw is List && mbRaw.isNotEmpty)
            ? Map<String, dynamic>.from(mbRaw.first as Map)
            : (mbRaw is Map<String, dynamic>
                  ? mbRaw
                  : (mbRaw is Map ? Map<String, dynamic>.from(mbRaw) : {}));

        final bestekMatRaw = mb['bestek_materialen'];
        final List<dynamic> gekoppeldeMaterialen = bestekMatRaw is List
            ? bestekMatRaw
            : (bestekMatRaw != null ? [bestekMatRaw] : []);

        for (final koppeling in gekoppeldeMaterialen) {
          if (koppeling is! Map) continue;
          final matRaw =
              koppeling['materialen'] ?? koppeling['materiaal'] ?? koppeling;
          final Map<String, dynamic> mat =
              (matRaw is List && matRaw.isNotEmpty)
              ? Map<String, dynamic>.from(matRaw.first as Map)
              : (matRaw is Map<String, dynamic>
                    ? matRaw
                    : (matRaw is Map
                          ? Map<String, dynamic>.from(matRaw)
                          : {}));

          final matObj = _materiaalUitRelatieMap(mat);
          if (matObj != null) ruimteMap.putIfAbsent(matObj.naam, () => matObj);
        }
      }

      if (ruimteMap.isNotEmpty) {
        ruimteLijst.add((
          label:
              ruimte['naam_in_pand']?.toString() ??
              ruimte['ruimte_categorie']?.toString() ??
              'Ruimte',
          materialen: ruimteMap.values.toList(),
        ));
      }
    }

    return _OpdrachtPaklijstData(
      freqType: effectiefFreqType,
      ruimtes: ruimteLijst,
    );
  }

  Future<_PaklijstLaadResult> _laadPaklijstVoorOpdracht(
    String opdrachtId,
  ) async {
    final supabase = Supabase.instance.client;

    final opdrachtData = await supabase
        .from('opdrachten')
        .select('frequentie_type, project_id, projecten(offerte_id)')
        .eq('id', opdrachtId)
        .maybeSingle();

    if (opdrachtData == null) {
      return const _PaklijstLaadResult(
        foutmelding: 'Opdracht data niet gevonden in DB.',
      );
    }

    final opdrachtMap = Map<String, dynamic>.from(opdrachtData);
    final String taakFreq =
        opdrachtMap['frequentie_type']?.toString().toLowerCase() ?? '';
    final String? offerteId = _offerteIdUitOpdrachtEmbed(opdrachtMap);

    var effectiefFreqType = taakFreq;
    if ((taakFreq == 'incidenteel' || taakFreq == 'eenmalig') &&
        _isGeldigeOfferteId(offerteId)) {
      effectiefFreqType = 'regulier';
    }

    if ((effectiefFreqType == 'incidenteel' ||
            effectiefFreqType == 'eenmalig') &&
        !_isGeldigeOfferteId(offerteId)) {
      return const _PaklijstLaadResult(
        foutmelding:
            'Voor deze losse klus is geen paklijst beschikbaar (geen project/blauwdruk).',
      );
    }

    if (!_isGeldigeOfferteId(offerteId)) {
      return const _PaklijstLaadResult(
        foutmelding: 'Geen offerte (blauwdruk) gekoppeld aan deze klus.',
      );
    }

    final ruimtes = await supabase.from('offerte_ruimtes').select('''
          naam_in_pand, 
          ruimte_categorie,
          offerte_ruimte_diensten(
            frequentie_label,
            moeder_bestek(
              bestek_materialen(
                materialen(*)
              )
            )
          )
        ''').eq('offerte_id', offerteId!);

    final data = _parseRuimtesNaarPaklijst(
      ruimtes as List<dynamic>,
      effectiefFreqType,
    );
    if (data.globaalUniek.isEmpty) {
      return const _PaklijstLaadResult(
        foutmelding:
            'Geen gekoppelde materialen gevonden in het bestek voor deze taak.',
      );
    }
    return _PaklijstLaadResult(data: data);
  }

  void _toonMateriaalFotoPopup(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Icon(Icons.broken_image, size: 64),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _materiaalRij(
    _PaklijstMateriaal m, {
    bool bold = false,
    bool viewOnly = false,
  }) {
    final lijstIcoonKleur = bold ? Colors.orange : Colors.blueGrey;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (m.fotoUrl != null)
            GestureDetector(
              onTap: () => _toonMateriaalFotoPopup(context, m.fotoUrl!),
              child: ClipOval(
                child: Image.network(
                  m.fotoUrl!,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => CircleAvatar(
                    radius: 18,
                    child: Icon(Icons.inventory_2, size: 16, color: Colors.grey.shade600),
                  ),
                ),
              ),
            )
          else
            Icon(
              viewOnly ? Icons.circle : Icons.check_box_outline_blank,
              size: viewOnly ? 8 : 16,
              color: lijstIcoonKleur,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              m.naam,
              style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (m.vereistTransport)
            Icon(Icons.local_shipping, size: 16, color: Colors.orange.shade800),
        ],
      ),
    );
  }

  Widget _buildRuimtePaklijstSectie(
    ({String label, List<_PaklijstMateriaal> materialen}) ruimte, {
    bool viewOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              ruimte.label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...ruimte.materialen.map((m) => _materiaalRij(m, viewOnly: viewOnly)),
        ],
      ),
    );
  }

  Future<void> _toonPaklijstModal(
    BuildContext context,
    dynamic actieveOpdracht, {
    bool viewOnly = false,
  }) async {
    final planningItem = actieveOpdracht is Map<String, dynamic>
        ? actieveOpdracht
        : Map<String, dynamic>.from(actieveOpdracht as Map);

    final String? itemId = planningItem['id']?.toString();
    final String? oId = planningItem['opdracht_id']?.toString();
    final String opdrachtId = oId ?? itemId ?? '';
    final planningId = _planningIdFromItem(planningItem);

    if (opdrachtId.isEmpty) return;
    if (!viewOnly && planningId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fout: Geen planning gekoppeld aan deze taak.'),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final supabase = Supabase.instance.client;

      final opdrachtData = await supabase
          .from('opdrachten')
          .select('frequentie_type, project_id, projecten(offerte_id)')
          .eq('id', opdrachtId)
          .maybeSingle();

      if (opdrachtData == null) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opdracht data niet gevonden in DB.')),
        );
        return;
      }

      final opdrachtMap = Map<String, dynamic>.from(opdrachtData);
      final String taakFreq =
          opdrachtMap['frequentie_type']?.toString().toLowerCase() ?? '';
      final String? offerteId = _offerteIdUitOpdrachtEmbed(opdrachtMap);

      var effectiefFreqType = taakFreq;
      if ((taakFreq == 'incidenteel' || taakFreq == 'eenmalig') &&
          _isGeldigeOfferteId(offerteId)) {
        effectiefFreqType = 'regulier';
      }

      if ((effectiefFreqType == 'incidenteel' ||
              effectiefFreqType == 'eenmalig') &&
          !_isGeldigeOfferteId(offerteId)) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Voor deze losse klus is geen paklijst beschikbaar (geen project/blauwdruk).',
            ),
          ),
        );
        return;
      }

      if (!_isGeldigeOfferteId(offerteId)) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Geen offerte (blauwdruk) gekoppeld aan deze klus.'),
          ),
        );
        return;
      }

      final ruimtes = await supabase
          .from('offerte_ruimtes')
          .select('''
          naam_in_pand, 
          ruimte_categorie,
          offerte_ruimte_diensten(
            frequentie_label,
            moeder_bestek(
              bestek_materialen(
                materialen(*)
              )
            )
          )
        ''')
          .eq('offerte_id', offerteId!);

      if (!context.mounted) return;
      Navigator.of(context).pop();


      final globaleMap = <String, _PaklijstMateriaal>{};
      final ruimteLijst = <({String label, List<_PaklijstMateriaal> materialen})>[];

      for (final ruimte in ruimtes as List) {
        if (ruimte is! Map) continue;
        final ruimtesDienstenRaw = ruimte['offerte_ruimte_diensten'];
        final List<dynamic> diensten = ruimtesDienstenRaw is List
            ? ruimtesDienstenRaw
            : (ruimtesDienstenRaw != null ? [ruimtesDienstenRaw] : []);
        final ruimteMap = <String, _PaklijstMateriaal>{};

        for (final d in diensten) {
          if (d is! Map) continue;
          var isActief = false;
          final String fLabel =
              d['frequentie_label']?.toString().toLowerCase() ?? 'regulier';

          if (effectiefFreqType == 'regulier' && fLabel == 'regulier') {
            isActief = true;
          }
          if (effectiefFreqType == 'frequent' && fLabel == 'frequent') {
            isActief = true;
          }
          if (effectiefFreqType == 'periodiek' && fLabel == 'periodiek') {
            isActief = true;
          }

          if (!isActief || d['moeder_bestek'] == null) continue;

          final mbRaw = d['moeder_bestek'];
          final Map<String, dynamic> mb =
              (mbRaw is List && mbRaw.isNotEmpty)
              ? Map<String, dynamic>.from(mbRaw.first as Map)
              : (mbRaw is Map<String, dynamic>
                    ? mbRaw
                    : (mbRaw is Map ? Map<String, dynamic>.from(mbRaw) : {}));

          final bestekMatRaw = mb['bestek_materialen'];
          final List<dynamic> gekoppeldeMaterialen = bestekMatRaw is List
              ? bestekMatRaw
              : (bestekMatRaw != null ? [bestekMatRaw] : []);

          for (final koppeling in gekoppeldeMaterialen) {
            if (koppeling is! Map) continue;
            final matRaw =
                koppeling['materialen'] ??
                koppeling['materiaal'] ??
                koppeling;
            final Map<String, dynamic> mat =
                (matRaw is List && matRaw.isNotEmpty)
                ? Map<String, dynamic>.from(matRaw.first as Map)
                : (matRaw is Map<String, dynamic>
                      ? matRaw
                      : (matRaw is Map
                            ? Map<String, dynamic>.from(matRaw)
                            : {}));

            final matObj = _materiaalUitRelatieMap(mat);
            if (matObj == null) continue;
            ruimteMap.putIfAbsent(matObj.naam, () => matObj);
            globaleMap.putIfAbsent(matObj.naam, () => matObj);
          }
        }

        if (ruimteMap.isNotEmpty) {
          ruimteLijst.add((
            label:
                ruimte['naam_in_pand']?.toString() ??
                ruimte['ruimte_categorie']?.toString() ??
                'Ruimte',
            materialen: ruimteMap.values.toList(),
          ));
        }
      }

      final globaal = globaleMap.values.toList();
      final alAkkoord = planningItem['paklijst_akkoord'] == true;

      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text('Materialenlijst ($effectiefFreqType)'),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: globaal.isEmpty
                ? const Center(
                    child: Text(
                      'Geen gekoppelde materialen gevonden in het bestek voor deze taak.',
                    ),
                  )
                : ListView(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.shopping_cart,
                                  color: Colors.orange.shade800,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Totale Paklijst',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(),
                            ...globaal.map(
                              (m) => _materiaalRij(
                                m,
                                bold: true,
                                viewOnly: viewOnly,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        'Uitsplitsing per ruimte:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...ruimteLijst.map(
                        (r) => _buildRuimtePaklijstSectie(
                          r,
                          viewOnly: viewOnly,
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            if (viewOnly)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Inzien-modus. Je kunt dit pas afvinken op de dag van de opdracht.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else if (!alAkkoord)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Ik heb alles gepakt'),
                  onPressed: globaal.isEmpty
                      ? null
                      : () async {
                          try {
                            await supabase
                                .from('opdracht_planning')
                                .update({'paklijst_akkoord': true})
                                .eq('id', planningId);
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            await _loadData();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Paklijst bevestigd.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('Opslaan mislukt: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                viewOnly || alAkkoord ? 'Sluiten' : 'Annuleren',
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fout bij laden materialen: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _telMateriaalVoorDag(
    Map<String, int> tellingen,
    Map<String, _PaklijstMateriaal> info,
    _PaklijstMateriaal mat,
  ) {
    info.putIfAbsent(mat.naam, () => mat);
    if (mat.isVermenigvuldigbaar) {
      tellingen[mat.naam] = (tellingen[mat.naam] ?? 0) + 1;
    } else {
      tellingen[mat.naam] = 1;
    }
  }

  Future<void> _toonDagPaklijstModal() async {
    final taken = _todaysTasks;
    if (taken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geen taken voor vandaag.')),
      );
      return;
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final tellingen = <String, int>{};
      final info = <String, _PaklijstMateriaal>{};

      for (final task in taken) {
        final opdrachtId = task['opdracht_id']?.toString() ?? '';
        if (opdrachtId.isEmpty) continue;

        final result = await _laadPaklijstVoorOpdracht(opdrachtId);
        final data = result.data;
        if (data == null) continue;

        for (final ruimte in data.ruimtes) {
          for (final mat in ruimte.materialen) {
            _telMateriaalVoorDag(tellingen, info, mat);
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      final transportNamen = info.values
          .where((m) => m.vereistTransport)
          .map((m) => m.naam)
          .toSet()
          .toList()
        ..sort();

      final gesorteerd = tellingen.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Dag-Paklijst'),
          content: SizedBox(
            width: double.maxFinite,
            height: 480,
            child: gesorteerd.isEmpty
                ? const Center(
                    child: Text('Geen materialen voor de taken van vandaag.'),
                  )
                : ListView(
                    children: [
                      if (transportNamen.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Text(
                            'Let op: Transport vereist voor: ${transportNamen.join(', ')}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.amber.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ...gesorteerd.map((naam) {
                        final aantal = tellingen[naam] ?? 1;
                        final mat = info[naam]!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              if (mat.fotoUrl != null)
                                GestureDetector(
                                  onTap: () => _toonMateriaalFotoPopup(
                                    ctx,
                                    mat.fotoUrl!,
                                  ),
                                  child: CircleAvatar(
                                    radius: 20,
                                    backgroundImage:
                                        NetworkImage(mat.fotoUrl!),
                                  ),
                                )
                              else
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.grey.shade200,
                                  child: Icon(
                                    Icons.inventory_2,
                                    size: 18,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  aantal > 1 ? '$naam × $aantal' : naam,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (mat.vereistTransport)
                                Icon(
                                  Icons.local_shipping,
                                  color: Colors.orange.shade800,
                                  size: 20,
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Sluiten'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dag-paklijst laden mislukt: $e')),
      );
    }
  }

  Future<void> _markeerOpdrachtAfgerond(
    String planningId,
    String opdrachtId,
  ) async {
    final supabase = Supabase.instance.client;
    await supabase
        .from('opdracht_planning')
        .update({'status': 'afgerond'})
        .eq('id', planningId);
    await supabase
        .from('opdrachten')
        .update({'status': 'afgerond'})
        .eq('id', opdrachtId);
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opdracht gemarkeerd als afgerond.'),
        backgroundColor: Colors.green,
      ),
    );
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
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(radius: 16));
    }
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Text(
          'Fout: $_errorMessage',
          style: const TextStyle(color: Colors.red),
        ),
      );
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.inventory_2, size: 24),
                    label: const Text(
                      'Bekijk Paklijst voor Vandaag',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed:
                        _todaysTasks.isEmpty ? null : _toonDagPaklijstModal,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'VANDAAG UIT TE VOEREN',
                style: GoogleFonts.lato(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.blueAccent,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
          if (_todaysTasks.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.done_all,
                      size: 64,
                      color: Colors.green.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Je bent helemaal klaar voor vandaag!',
                      style: GoogleFonts.lato(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                      ),
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
          if (_upcomingTasks.isNotEmpty)
            SliverToBoxAdapter(child: _buildKomendeOpdrachtenSlider()),
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
            child: _kpiCard(
              'Taken vandaag',
              '$_kpiTakenVandaag',
              Icons.today,
              Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _kpiCard(
              'Deze week',
              '$_kpiDezeWeek',
              Icons.calendar_month,
              Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(
    String title,
    String value,
    IconData icon,
    MaterialColor color,
  ) {
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
              Text(
                value,
                style: GoogleFonts.lato(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: color.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaakActieKnoppen(Map<String, dynamic> planningItem) {
    final paklijstAkkoord = planningItem['paklijst_akkoord'] == true;
    final status = _statusRaw(planningItem);
    final urenStatus = _urenStatusRaw(planningItem);
    final planningId = _planningIdFromItem(planningItem);
    final opdrachtId = planningItem['opdracht_id']?.toString() ?? '';

    final buttonStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(double.infinity, 48),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    if (!paklijstAkkoord) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: buttonStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(Colors.blue.shade700),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
          icon: const Icon(Icons.checklist),
          label: const Text('Paklijst (Verplicht)'),
          onPressed: () => _toonPaklijstModal(context, planningItem),
        ),
      );
    }

    if (status != 'afgerond') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: buttonStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(Colors.green.shade700),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
          icon: const Icon(Icons.check_circle),
          label: const Text('Opdracht Afgerond'),
          onPressed: planningId.isEmpty || opdrachtId.isEmpty
              ? null
              : () => _markeerOpdrachtAfgerond(planningId, opdrachtId),
        ),
      );
    }

    if (urenStatus == 'open') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: buttonStyle,
          icon: const Icon(Icons.access_time),
          label: const Text('Uren Indienen'),
          onPressed: _openMijnUren,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildTodayCard(Map<String, dynamic> task) {
    final String status = _normStatus(task['mijn_persoonlijke_status']);
    final isGepland = status == 'gepland';
    final isVoltooid = status == 'voltooid';
    String badgeLabel;
    Color badgeColor;
    Color bgChip;
    if (status == 'in_uitvoering') {
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
                style: GoogleFonts.lato(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: bgChip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            task['bedrijfsnaam'] ?? 'Onbekende Klant',
            style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.business_center,
                size: 14,
                color: Colors.grey.shade400,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  task['project_naam'] ?? '',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ),
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          _buildTaakActieKnoppen(task),
        ],
      ),
    );
  }

  String _datumLabel(Map<String, dynamic> task) {
    final raw = task['geplande_datum']?.toString() ?? '';
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  Widget _buildKomendeOpdrachtenSlider() {
    final toekomstigeTakenLijst = _upcomingTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
          child: Text(
            'Komende Opdrachten',
            style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: toekomstigeTakenLijst.length,
            itemBuilder: (context, index) {
              final taak = toekomstigeTakenLijst[index];
              final datum = _datumLabel(taak);
              final bedrijfsnaam =
                  taak['bedrijfsnaam']?.toString() ?? 'Klant';
              final start = _safeTime(taak['rooster_starttijd']);
              final eind = _safeTime(taak['rooster_eindtijd']);

              return Container(
                width: 280,
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            datum,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                        const Icon(Icons.event, color: Colors.grey, size: 20),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bedrijfsnaam,
                      style: GoogleFonts.lato(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$start - $eind',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          foregroundColor: Colors.blue.shade700,
                        ),
                        onPressed: () => _toonPaklijstModal(
                          context,
                          taak,
                          viewOnly: true,
                        ),
                        child: const Text('Paklijst Inzien'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PaklijstLaadResult {
  const _PaklijstLaadResult({this.data, this.foutmelding});

  final _OpdrachtPaklijstData? data;
  final String? foutmelding;
}

class _PaklijstMateriaal {
  const _PaklijstMateriaal({
    required this.naam,
    this.fotoUrl,
    this.isVermenigvuldigbaar = true,
    this.vereistTransport = false,
  });

  final String naam;
  final String? fotoUrl;
  final bool isVermenigvuldigbaar;
  final bool vereistTransport;
}

class _OpdrachtPaklijstData {
  const _OpdrachtPaklijstData({
    required this.freqType,
    required this.ruimtes,
  });

  final String freqType;
  final List<({String label, List<_PaklijstMateriaal> materialen})> ruimtes;

  List<_PaklijstMateriaal> get globaalUniek {
    final seen = <String>{};
    final out = <_PaklijstMateriaal>[];
    for (final ruimte in ruimtes) {
      for (final m in ruimte.materialen) {
        if (seen.add(m.naam)) out.add(m);
      }
    }
    return out;
  }
}
