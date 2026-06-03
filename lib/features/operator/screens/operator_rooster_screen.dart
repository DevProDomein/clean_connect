import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_drawer.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';
import '../../shared/services/werkbon_pdf_service.dart';
class OperatorRoosterScreen extends StatefulWidget {
  const OperatorRoosterScreen({super.key});

  @override
  State<OperatorRoosterScreen> createState() => _OperatorRoosterScreenState();
}

class _OperatorRoosterScreenState extends State<OperatorRoosterScreen> {
  static const String _offerteRuimtesPaklijstSelect = '''
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
        ''';

  static const String _offerteRuimtesWerkprogrammaSelect = '''
          naam_in_pand, 
          ruimte_categorie,
          offerte_ruimte_diensten(
            frequentie_label,
            moeder_bestek(
              volledige_naam,
              bestek_materialen(
                materialen(*)
              )
            )
          )
        ''';

  final _supabase = Supabase.instance.client;
  final PageController _sliderController = PageController(viewportFraction: 0.85);
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

  @override
  void dispose() {
    _sliderController.dispose();
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

      final List<Map<String, dynamic>> rawTaken = [];
      final seenPlanningIds = <String>{};

      void addRawRow(dynamic row) {
        if (row is! Map) return;
        final task = Map<String, dynamic>.from(row);
        final pid = _planningIdFromItem(task);
        if (pid.isNotEmpty) {
          if (!seenPlanningIds.add(pid)) return;
        }
        rawTaken.add(task);
      }

      final vandaagRes = await _supabase
          .from('app_operator_vandaag')
          .select()
          .eq('operator_id', userId)
          .order('geplande_datum', ascending: true)
          .order('rooster_starttijd', ascending: true);
      for (final row in vandaagRes as List) {
        addRawRow(row);
      }

      try {
        final agendaRes = await _supabase
            .from('app_operator_agenda')
            .select()
            .eq('operator_id', userId)
            .order('geplande_datum', ascending: true)
            .order('rooster_starttijd', ascending: true);
        for (final row in agendaRes as List) {
          addRawRow(row);
        }
      } catch (e) {
        debugPrint('app_operator_agenda (rooster): $e');
      }

      final nu = DateTime.now();
      final vandaag = DateTime(nu.year, nu.month, nu.day);
      final weekStart = vandaag.subtract(Duration(days: vandaag.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));

      final split = _splitActiefEnToekomst(rawTaken);
      final today = split.actief;
      final upcoming = split.toekomst;

      var kpiWeek = 0;
      for (final task in rawTaken) {
        final taskDay = _taskDayFromItem(task);
        if (taskDay == null) continue;
        if (!taskDay.isBefore(weekStart) && !taskDay.isAfter(weekEnd)) {
          kpiWeek++;
        }
      }

      final kpiVandaag = today.length;

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

  Future<void> _openWerkbonPdf(Map<String, dynamic> planningItem) async {
    final opdrachtEmbed = planningItem['opdracht'];
    final oId = planningItem['opdracht_id']?.toString() ??
        (opdrachtEmbed is Map ? opdrachtEmbed['id']?.toString() : null) ??
        '';

    if (oId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geen opdracht gekoppeld aan deze taak.')),
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
      final bytes = await WerkbonPdfService.generateWerkbonPdf(oId);
      if (!mounted) return;
      Navigator.of(context).pop();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fout bij maken PDF: $e')),
      );
    }
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

  String _rawTaskStatus(Map<String, dynamic> task) {
    final s = task['status'] ?? task['planning_status'];
    if (s != null && s.toString().trim().isNotEmpty) {
      return s.toString().trim().toLowerCase();
    }
    return _statusRaw(task);
  }

  DateTime? _taskDayFromItem(Map<String, dynamic> task) {
    final raw = task['geplande_datum']?.toString() ?? '';
    if (raw.isEmpty) return null;
    final head = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final parsed = DateTime.tryParse(head);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  ({List<Map<String, dynamic>> actief, List<Map<String, dynamic>> toekomst})
      _splitActiefEnToekomst(List<Map<String, dynamic>> rawTaken) {
    final nu = DateTime.now();
    final vandaag = DateTime(nu.year, nu.month, nu.day);

    final actieveTaken = <Map<String, dynamic>>[];
    final toekomstigeTaken = <Map<String, dynamic>>[];

    for (final task in rawTaken) {
      final taakDag = _taskDayFromItem(task) ?? vandaag;
      final status = _rawTaskStatus(task);

      final isVerleden = taakDag.isBefore(vandaag);
      final isVandaag = taakDag.year == vandaag.year &&
          taakDag.month == vandaag.month &&
          taakDag.day == vandaag.day;

      final isOpen = status != 'afgerond' &&
          status != 'geannuleerd' &&
          status != 'no_show';

      if (isVandaag || (isVerleden && isOpen)) {
        actieveTaken.add(task);
      }

      if (taakDag.isAfter(vandaag) || (isVerleden && isOpen && !isVandaag)) {
        toekomstigeTaken.add(task);
      }
    }

    actieveTaken.sort((a, b) {
      final dA = _taskDayFromItem(a) ?? vandaag;
      final dB = _taskDayFromItem(b) ?? vandaag;
      return dA.compareTo(dB);
    });

    toekomstigeTaken.sort((a, b) {
      final dA = _taskDayFromItem(a) ?? vandaag;
      final dB = _taskDayFromItem(b) ?? vandaag;
      return dA.compareTo(dB);
    });

    return (actief: actieveTaken, toekomst: toekomstigeTaken);
  }

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

  String _taakNaamUitMoederBestek(Map<String, dynamic> mb) {
    final naam = mb['volledige_naam']?.toString() ??
        mb['naam']?.toString() ??
        mb['taak_naam']?.toString() ??
        'Dienst';
    final trimmed = naam.trim();
    return trimmed.isEmpty ? 'Dienst' : trimmed;
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

    final ruimtes = await supabase
        .from('offerte_ruimtes')
        .select(_offerteRuimtesPaklijstSelect)
        .eq('offerte_id', offerteId!);

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

  Future<void> _toonWerkprogrammaModal(
    BuildContext context,
    dynamic planningItem,
  ) async {
    final planningMap = planningItem is Map<String, dynamic>
        ? planningItem
        : Map<String, dynamic>.from(planningItem as Map);
    final planningId = _planningIdFromItem(planningMap);
    final opdrachtEmbed = planningMap['opdracht'];
    final opdrachtId = planningMap['opdracht_id']?.toString() ??
        (opdrachtEmbed is Map
            ? opdrachtEmbed['id']?.toString()
            : null) ??
        '';

    if (opdrachtId.isEmpty || planningId.isEmpty) return;

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final opd = await _supabase
          .from('opdrachten')
          .select('frequentie_type, project_id, projecten(offerte_id)')
          .eq('id', opdrachtId)
          .maybeSingle();

      if (opd == null) throw Exception('Opdracht niet gevonden.');

      final opdrachtMap = Map<String, dynamic>.from(opd);
      var freqType =
          opdrachtMap['frequentie_type']?.toString().toLowerCase() ?? '';
      final offerteId = _offerteIdUitOpdrachtEmbed(opdrachtMap);

      if ((freqType == 'incidenteel' || freqType == 'eenmalig') &&
          _isGeldigeOfferteId(offerteId)) {
        freqType = 'regulier';
      }

      if (!_isGeldigeOfferteId(offerteId)) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Geen werkprogramma/blauwdruk gevonden voor deze (losse) klus.',
            ),
          ),
        );
        return;
      }

      final ruimtes = await _supabase
          .from('offerte_ruimtes')
          .select(_offerteRuimtesWerkprogrammaSelect)
          .eq('offerte_id', offerteId!);

      if (!context.mounted) return;
      Navigator.of(context).pop();

      final ruimteWidgets = <Widget>[];
      final globaleMaterialen = <String>{};

      for (final ruimte in ruimtes as List) {
        if (ruimte is! Map) continue;
        final ruimtesDienstenRaw = ruimte['offerte_ruimte_diensten'];
        final diensten = ruimtesDienstenRaw is List
            ? ruimtesDienstenRaw
            : (ruimtesDienstenRaw != null ? [ruimtesDienstenRaw] : []);
        final ruimteTaken = <String>[];

        for (final d in diensten) {
          if (d is! Map) continue;
          var isActief = false;
          final fLabel =
              d['frequentie_label']?.toString().toLowerCase() ?? 'regulier';

          if (freqType == 'regulier' && fLabel == 'regulier') isActief = true;
          if (freqType == 'frequent' && fLabel == 'frequent') isActief = true;
          if (freqType == 'periodiek' && fLabel == 'periodiek') isActief = true;
          if ((freqType == 'incidenteel' || freqType == 'eenmalig') &&
              fLabel == 'regulier') {
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

          final taakNaam = _taakNaamUitMoederBestek(mb);
          ruimteTaken.add(taakNaam);

          final bestekMatRaw = mb['bestek_materialen'];
          final gekoppeldeMaterialen = bestekMatRaw is List
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
            final matNaam = _getMatNaam(mat);
            if (matNaam.isNotEmpty) globaleMaterialen.add(matNaam);
          }
        }

        if (ruimteTaken.isNotEmpty) {
          ruimteWidgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ruimte['naam_in_pand']?.toString() ??
                          ruimte['ruimte_categorie']?.toString() ??
                          'Ruimte',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...ruimteTaken.map(
                    (taak) => Padding(
                      padding: const EdgeInsets.only(bottom: 6, left: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.cleaning_services_outlined,
                            size: 16,
                            color: Colors.blueGrey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              taak,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }

      if (!context.mounted) return;

      final paklijstAkkoord = planningMap['paklijst_akkoord'] == true;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Werkprogramma & Paklijst'),
          content: SizedBox(
            width: double.maxFinite,
            height: 600,
            child: ListView(
              children: [
                if (globaleMaterialen.isNotEmpty) ...[
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
                        ...globaleMaterialen.map(
                          (m) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_box_outline_blank,
                                  size: 16,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    m,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
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
                ],
                const Text(
                  'Werkprogramma per ruimte:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                if (ruimteWidgets.isEmpty)
                  const Text('Geen specifieke taken gevonden.'),
                ...ruimteWidgets,
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Sluiten'),
            ),
            if (!paklijstAkkoord)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  try {
                    await _supabase
                        .from('opdracht_planning')
                        .update({'paklijst_akkoord': true})
                        .eq('id', planningId);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    await _loadData(silent: true);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Werkprogramma & paklijst bevestigd.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    debugPrint('Akkoord opslaan mislukt: $e');
                    if (!ctx.mounted) return;
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Opslaan mislukt: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Gelezen & Akkoord'),
              ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      debugPrint('Werkprogramma laden mislukt: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fout: $e')),
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
    final planningStatus = _statusRaw(planningItem);
    final urenStatus = _urenStatusRaw(planningItem);
    final planningId = _planningIdFromItem(planningItem);
    final opdrachtId = planningItem['opdracht_id']?.toString() ?? '';

    final fullWidthStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(double.infinity, 48),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!paklijstAkkoord) ...[
          ElevatedButton.icon(
            icon: const Icon(Icons.fact_check),
            label: const Text('Bekijk Werkprogramma (Verplicht)'),
            style: fullWidthStyle.copyWith(
              backgroundColor: WidgetStatePropertyAll(Colors.orange.shade600),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
            ),
            onPressed: () => _toonWerkprogrammaModal(context, planningItem),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
            label: const Text('Preview Werkbon'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              minimumSize: const Size(double.infinity, 48),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => _openWerkbonPdf(planningItem),
          ),
        ] else if (planningStatus != 'afgerond') ...[
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle),
            label: const Text('Opdracht Afronden'),
            style: fullWidthStyle.copyWith(
              backgroundColor: WidgetStatePropertyAll(Colors.green.shade600),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
            ),
            onPressed: planningId.isEmpty
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Opdracht Afronden?'),
                            content: const Text(
                              'Ben je helemaal klaar met de werkzaamheden in het pand?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Nee, nog niet'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Ja, afronden'),
                              ),
                            ],
                          ),
                        ) ??
                        false;

                    if (!confirm) return;
                    if (opdrachtId.isNotEmpty) {
                      await _markeerOpdrachtAfgerond(planningId, opdrachtId);
                    } else {
                      await _supabase
                          .from('opdracht_planning')
                          .update({'status': 'afgerond'})
                          .eq('id', planningId);
                      await _loadData(silent: true);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Opdracht gemarkeerd als afgerond.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
            label: const Text('Preview Werkbon'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              minimumSize: const Size(double.infinity, 48),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => _openWerkbonPdf(planningItem),
          ),
        ] else if (urenStatus == 'open')
          ElevatedButton.icon(
            icon: const Icon(Icons.access_time),
            label: const Text('Uren Indienen'),
            style: fullWidthStyle.copyWith(
              backgroundColor: WidgetStatePropertyAll(Colors.blue.shade700),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
            ),
            onPressed: _openMijnUren,
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.thumb_up, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text(
                  'Alles afgerond & uren ingediend!',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
              label: const Text('Preview Werkbon'),
              onPressed: () => _openWerkbonPdf(planningItem),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTodayCard(Map<String, dynamic> task) {
    final nu = DateTime.now();
    final vandaag = DateTime(nu.year, nu.month, nu.day);
    final taakDag = _taskDayFromItem(task) ?? vandaag;
    final isTeLaat = taakDag.isBefore(vandaag);
    final geplandeDatumLabel = _datumLabel(task);

    final String status = _normStatus(task['mijn_persoonlijke_status']);
    final isGepland = status == 'gepland';
    final isVoltooid = status == 'voltooid';
    String badgeLabel;
    Color badgeColor;
    Color bgChip;
    if (isTeLaat) {
      badgeLabel = 'Te laat';
      badgeColor = Colors.red.shade800;
      bgChip = Colors.red.shade50;
    } else if (status == 'in_uitvoering') {
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

    final cardBody = Padding(
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

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: isTeLaat ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTeLaat ? Colors.red.shade400 : Colors.grey.shade300,
          width: isTeLaat ? 2 : 1,
        ),
        boxShadow: isTeLaat
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isTeLaat)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
              ),
              child: Text(
                'VERGETEN AF TE RONDEN: $geplandeDatumLabel',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          cardBody,
        ],
      ),
    );
  }

  String _datumLabel(Map<String, dynamic> task) {
    final raw = task['geplande_datum']?.toString() ?? '';
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  void _sliderPreviousPage() {
    if (!_sliderController.hasClients) return;
    final current = _sliderController.page?.round() ?? 0;
    if (current > 0) {
      _sliderController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _sliderNextPage(int itemCount) {
    if (!_sliderController.hasClients) return;
    final current = _sliderController.page?.round() ?? 0;
    if (current < itemCount - 1) {
      _sliderController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildSliderCard(BuildContext context, Map<String, dynamic> taak) {
    final nu = DateTime.now();
    final vandaag = DateTime(nu.year, nu.month, nu.day);
    final taakDatum = _taskDayFromItem(taak) ?? vandaag;
    final isVerleden = taakDatum.isBefore(vandaag);
    final datumRaw = _datumLabel(taak);
    final datumTekst = isVerleden
        ? 'ACHTERSTALLIG: $datumRaw'
        : datumRaw;

    final opdrachtEmbed = taak['opdracht'];
    final bedrijfsnaam = taak['bedrijfsnaam']?.toString() ??
        (opdrachtEmbed is Map
            ? opdrachtEmbed['bedrijfsnaam']?.toString()
            : null) ??
        'Klant';
    final adres = taak['uitvoer_adres_volledig']?.toString() ??
        (opdrachtEmbed is Map
            ? opdrachtEmbed['uitvoer_adres_volledig']?.toString()
            : null) ??
        'Adres onbekend';
    final start = _safeTime(taak['rooster_starttijd'] ?? taak['starttijd']);
    final eind = _safeTime(taak['rooster_eindtijd'] ?? taak['eindtijd']);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: isVerleden ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isVerleden ? Colors.red.shade200 : Colors.grey.shade300,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
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
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isVerleden ? Colors.red.shade100 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    datumTekst,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isVerleden
                          ? Colors.red.shade900
                          : Colors.blue.shade900,
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.calendar_month,
                color: isVerleden ? Colors.red : Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            bedrijfsnaam,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'Tijd: $start - $eind',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            adres,
            style: const TextStyle(color: Colors.blueGrey, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _toonWerkprogrammaModal(context, taak),
                  child: const Text('Werkprogramma', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _openWerkbonPdf(taak),
                  child: const Text('Preview Werkbon', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKomendeOpdrachtenSlider() {
    final toekomstigeTakenLijst = _upcomingTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Overige & Komende Opdrachten',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 300,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PageView.builder(
                controller: _sliderController,
                itemCount: toekomstigeTakenLijst.length,
                itemBuilder: (context, index) {
                  return AnimatedBuilder(
                    animation: _sliderController,
                    builder: (context, child) {
                      double value = 1.0;
                      if (_sliderController.position.haveDimensions) {
                        value = _sliderController.page! - index;
                        value = (1 - (value.abs() * 0.15)).clamp(0.85, 1.0);
                      }
                      final double opacity = value.clamp(0.6, 1.0);

                      return Center(
                        child: Transform.scale(
                          scale: value,
                          child: Opacity(
                            opacity: opacity,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: _buildSliderCard(
                      context,
                      toekomstigeTakenLijst[index],
                    ),
                  );
                },
              ),
              Positioned(
                left: 0,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.blueGrey,
                    size: 30,
                  ),
                  onPressed: _sliderPreviousPage,
                ),
              ),
              Positioned(
                right: 0,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.blueGrey,
                    size: 30,
                  ),
                  onPressed: () =>
                      _sliderNextPage(toekomstigeTakenLijst.length),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
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
