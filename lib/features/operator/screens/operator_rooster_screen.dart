import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../shared/layouts/mobile_bottom_nav_layout.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';
import '../../shared/services/werkbon_pdf_service.dart';
import '../services/operator_planning_repository.dart';
import '../widgets/task_completion_modal.dart';
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
  final _planningRepository = OperatorPlanningRepository();
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
        if (_isRoosterItemGeannuleerd(task)) return;
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
        final planningRows =
            await _planningRepository.fetchRoosterPlanningForOperator(userId);
        for (final row in planningRows) {
          addRawRow(row);
        }
      } catch (e) {
        debugPrint('fetchRoosterPlanningForOperator: $e');
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
        } catch (e2) {
          debugPrint('app_operator_agenda (rooster fallback): $e2');
        }
      }

      final nu = DateTime.now();
      final vandaag = DateTime(nu.year, nu.month, nu.day);
      final weekStart = vandaag.subtract(Duration(days: vandaag.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));

      final today = _filterRoosterLijstVandaag(rawTaken);
      final upcoming = _filterTakenVoorSlider(rawTaken);

      var kpiWeek = 0;
      for (final task in rawTaken) {
        final taskDay = _taskDayFromItem(task);
        if (taskDay == null) continue;
        if (!taskDay.isBefore(weekStart) && !taskDay.isAfter(weekEnd)) {
          kpiWeek++;
        }
      }

      final kpiVandaag = today.length;

      // Fetch toelichting_planning from opdrachten for all loaded tasks (single query).
      try {
        final ids = <String>{};
        for (final t in rawTaken) {
          final id = _opdrachtIdFromItem(t);
          if (id.isNotEmpty) ids.add(id);
        }

        if (ids.isNotEmpty) {
          final rows = await _supabase
              .from('opdrachten')
              .select('id, toelichting_planning')
              .inFilter('id', ids.toList(growable: false));

          final map = <String, String>{};
          for (final r in rows as List) {
            if (r is! Map) continue;
            final id = r['id']?.toString().trim() ?? '';
            if (id.isEmpty) continue;
            final text = r['toelichting_planning']?.toString().trim() ?? '';
            if (text.isNotEmpty && text.toLowerCase() != 'null') {
              map[id] = text;
            }
          }

          void attachToelichting(List<Map<String, dynamic>> list) {
            for (final t in list) {
              final id = _opdrachtIdFromItem(t);
              if (id.isEmpty) continue;
              final v = map[id];
              if (v != null && v.isNotEmpty) {
                t['toelichting_planning'] = v;
              }
            }
          }

          attachToelichting(today);
          attachToelichting(upcoming);
        }
      } catch (e) {
        debugPrint('toelichting_planning fetch: $e');
      }

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
    if (s.contains('voltooi') || s == OpdrachtPlanningStatus.afgerond) {
      return 'voltooid';
    }
    if (s.contains('uitvoering')) return 'in_uitvoering';
    if (s == 'ingepland') return 'gepland';
    return s;
  }

  void _navigateToMijnUren() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const MobileBottomNavLayout(initialKey: 'uren'),
      ),
    );
  }

  bool _isTaakAfgerond(Map<String, dynamic> item) {
    final status = _statusRaw(item);
    return status == OpdrachtPlanningStatus.afgerond ||
        status == OpdrachtPlanningStatus.voltooid;
  }

  /// Alleen vandaag of verleden (datum zonder tijd).
  bool _magOpdrachtAfrondenOpDatum(Map<String, dynamic> item) {
    final nu = DateTime.now();
    final vandaag = DateTime(nu.year, nu.month, nu.day);
    final taakDag = _taskDayFromItem(item) ?? vandaag;
    return !taakDag.isAfter(vandaag);
  }

  Future<void> _openTaskCompletionModal(Map<String, dynamic> planningItem) async {
    if (!_magOpdrachtAfrondenOpDatum(planningItem)) return;
    await TaskCompletionModal.show(
      context,
      planningItem: planningItem,
      onCompleted: () {
        _navigateToMijnUren();
      },
    );
    if (mounted) {
      await _loadData(silent: true);
    }
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

  String _opdrachtIdFromItem(Map<String, dynamic> item) {
    final opdrachtEmbed = item['opdracht'];
    final raw = item['opdracht_id']?.toString().trim() ??
        (opdrachtEmbed is Map ? opdrachtEmbed['id']?.toString().trim() : null) ??
        item['id']?.toString().trim() ??
        '';
    return raw;
  }

  bool _hasPlanningToelichting(Map<String, dynamic> item) {
    final t = item['toelichting_planning']?.toString().trim() ?? '';
    return t.isNotEmpty && t.toLowerCase() != 'null';
  }

  String _statusRaw(Map<String, dynamic> item) {
    final s = item['status'] ?? item['planning_status'];
    if (s != null && s.toString().trim().isNotEmpty) {
      return s.toString().trim().toLowerCase();
    }
    final pers = item['mijn_persoonlijke_status']?.toString().trim().toLowerCase();
    if (pers == 'voltooid') return OpdrachtPlanningStatus.afgerond;
    return pers ?? 'ingepland';
  }

  bool _isRoosterItemGeannuleerd(Map<String, dynamic> task) {
    if (_rawTaskStatus(task) == OpdrachtPlanningStatus.geannuleerd) {
      return true;
    }
    final opdracht = task['opdracht'];
    if (opdracht is Map) {
      final opdrachtStatus =
          (opdracht['status'] ?? '').toString().trim().toLowerCase();
      if (opdrachtStatus == OpdrachtPlanningStatus.geannuleerd) return true;
    }
    return false;
  }

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

  bool _isZelfdeKalenderdag(DateTime dag, DateTime referentie) {
    return dag.year == referentie.year &&
        dag.month == referentie.month &&
        dag.day == referentie.day;
  }

  /// ListView: strikt opdrachten van vandaag (geen overdue, geen toekomst).
  List<Map<String, dynamic>> _filterRoosterLijstVandaag(
    List<Map<String, dynamic>> rawTaken,
  ) {
    final nu = DateTime.now();
    final vandaag = DateTime(nu.year, nu.month, nu.day);
    final roosterLijst = <Map<String, dynamic>>[];

    for (final task in rawTaken) {
      final taakDag = _taskDayFromItem(task);
      if (taakDag == null) continue;
      if (_isZelfdeKalenderdag(taakDag, vandaag)) {
        roosterLijst.add(task);
      }
    }

    roosterLijst.sort((a, b) {
      final dA = _taskDayFromItem(a) ?? vandaag;
      final dB = _taskDayFromItem(b) ?? vandaag;
      return dA.compareTo(dB);
    });

    return roosterLijst;
  }

  /// Slider: vergeten (verleden, niet vandaag) + toekomstige open opdrachten.
  List<Map<String, dynamic>> _filterTakenVoorSlider(
    List<Map<String, dynamic>> rawTaken,
  ) {
    final nu = DateTime.now();
    final vandaag = DateTime(nu.year, nu.month, nu.day);
    final slider = <Map<String, dynamic>>[];

    for (final task in rawTaken) {
      final taakDag = _taskDayFromItem(task);
      if (taakDag == null) continue;
      final isVerleden = taakDag.isBefore(vandaag);
      final isVandaag = _isZelfdeKalenderdag(taakDag, vandaag);
      final isToekomst = taakDag.isAfter(vandaag);
      final status = _rawTaskStatus(task);
      final isOpen = status != OpdrachtPlanningStatus.afgerond &&
          status != OpdrachtPlanningStatus.geannuleerd &&
          status != OpdrachtPlanningStatus.noShow &&
          status != OpdrachtPlanningStatus.voltooid;

      if (!isOpen) continue;
      if (isToekomst || (isVerleden && !isVandaag)) {
        slider.add(task);
      }
    }

    slider.sort((a, b) {
      final dA = _taskDayFromItem(a) ?? vandaag;
      final dB = _taskDayFromItem(b) ?? vandaag;
      final aVerleden = dA.isBefore(vandaag);
      final bVerleden = dB.isBefore(vandaag);
      if (aVerleden != bVerleden) {
        return aVerleden ? -1 : 1;
      }
      return dA.compareTo(dB);
    });

    return slider;
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
    final toelichtingPlanning =
        planningMap['toelichting_planning']?.toString().trim() ?? '';

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

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Werkprogramma'),
          content: SizedBox(
            width: double.maxFinite,
            height: 600,
            child: ListView(
              children: [
                if (toelichtingPlanning.isNotEmpty &&
                    toelichtingPlanning.toLowerCase() != 'null') ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
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
                              Icons.notification_important_rounded,
                              color: Colors.orange.shade800,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Opmerking vanuit planning:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          toelichtingPlanning,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
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

  static const Color _premiumDeepNavy = Color(0xFF1A237E);
  static const Color _premiumBrightBlue = Color(0xFF0052CC);

  BoxDecoration _roosterPremiumCardDecoration({required bool isRedVariant}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isRedVariant
            ? [Colors.red.shade600, Colors.redAccent.shade400]
            : [
                const Color(0xFF0F172A),
                _premiumDeepNavy,
                _premiumBrightBlue.withValues(alpha: 0.92),
              ],
      ),
        borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  Widget _roosterPremiumInfoRow({
    required IconData icon,
    required String text,
    int maxLines = 1,
  }) {
    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.95)),
        ),
        const SizedBox(width: 10),
        Expanded(
                child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.lato(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaakCompactActions(
    Map<String, dynamic> task, {
    bool forPremiumCard = false,
  }) {
    final werkprogrammaColor =
        forPremiumCard ? Colors.white : Colors.blue.shade700;
    final werkbonColor = forPremiumCard ? Colors.white70 : Colors.red.shade700;

    return Row(
      mainAxisSize: MainAxisSize.min,
            children: [
        IconButton(
          tooltip: 'Bekijk werkprogramma',
          icon: Icon(Icons.fact_check_outlined, color: werkprogrammaColor),
          visualDensity: VisualDensity.compact,
          onPressed: () => _toonWerkprogrammaModal(context, task),
        ),
        IconButton(
          tooltip: 'Preview werkbon',
          icon: Icon(Icons.picture_as_pdf_outlined, color: werkbonColor),
          visualDensity: VisualDensity.compact,
          onPressed: () => _openWerkbonPdf(task),
        ),
      ],
    );
  }

  Widget _buildTaakAfrondenKnop(Map<String, dynamic> task) {
    if (_isTaakAfgerond(task)) {
      return Text(
        'Afgerond — uren via Mijn Uren',
        style: GoogleFonts.lato(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.green.shade300,
        ),
      );
    }
    if (!_magOpdrachtAfrondenOpDatum(task)) {
      return const SizedBox.shrink();
    }
    return SizedBox(
              width: double.infinity,
      height: 44,
              child: ElevatedButton.icon(
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: Text(
          'Opdracht afronden',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
                style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        onPressed: () => _openTaskCompletionModal(task),
      ),
    );
  }

  Widget? _roosterPandThumbnail(Map<String, dynamic> taak) {
    final opdrachtEmbed = taak['opdracht'];
    final projectData =
        taak['projecten'] ??
        (opdrachtEmbed is Map ? opdrachtEmbed['projecten'] : null);
    final raw = projectData is Map
        ? projectData['pand_foto_url']?.toString().trim()
        : null;
    if (raw == null || raw.isEmpty || raw == 'null') return null;

    return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 56,
        height: 56,
        child: CachedNetworkImage(
          imageUrl: raw,
          fit: BoxFit.cover,
          placeholder: (context, _) => Container(
            color: Colors.white.withValues(alpha: 0.12),
            alignment: Alignment.center,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
          errorWidget: (context, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildPremiumRoosterTaskCard({
    required Map<String, dynamic> task,
    required bool isRedVariant,
    required EdgeInsetsGeometry margin,
    bool expandVertically = false,
    String? topChipLabel,
  }) {
    final opdrachtEmbed = task['opdracht'];
    final bedrijfsnaam = task['bedrijfsnaam']?.toString() ??
        (opdrachtEmbed is Map
            ? opdrachtEmbed['bedrijfsnaam']?.toString()
            : null) ??
        'Onbekende klant';
    final adres = task['uitvoer_adres_volledig']?.toString() ??
        (opdrachtEmbed is Map
            ? opdrachtEmbed['uitvoer_adres_volledig']?.toString()
            : null) ??
        'Adres onbekend';
    final start = _safeTime(task['rooster_starttijd'] ?? task['starttijd']);
    final eind = _safeTime(task['rooster_eindtijd'] ?? task['eindtijd']);
    final projectNaam = task['project_naam']?.toString().trim() ?? '';
    final thumbnail = _roosterPandThumbnail(task);
    final hasToelichting = _hasPlanningToelichting(task);

    return Container(
      margin: margin,
      decoration: _roosterPremiumCardDecoration(isRedVariant: isRedVariant),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize:
            expandVertically ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (topChipLabel != null)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
      decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      topChipLabel,
                      style: GoogleFonts.lato(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                ),
              if (hasToelichting) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                  mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notification_important_rounded,
                        size: 16,
                        color: Colors.orange.shade200,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Opmerking toegevoegd',
                        style: GoogleFonts.lato(
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          color: Colors.orange.shade100,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              _buildTaakCompactActions(task, forPremiumCard: true),
            ],
          ),
          if (topChipLabel != null) const SizedBox(height: 14),
          Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              Expanded(
                child: Text(
                  bedrijfsnaam,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    letterSpacing: -0.3,
                    color: Colors.white,
                  ),
                ),
              ),
              if (thumbnail != null) ...[
                const SizedBox(width: 10),
                thumbnail,
              ],
            ],
          ),
          if (projectNaam.isNotEmpty) ...[
            const SizedBox(height: 10),
            _roosterPremiumInfoRow(
              icon: Icons.business_center_rounded,
              text: projectNaam,
            ),
          ],
          const SizedBox(height: 14),
          _roosterPremiumInfoRow(
            icon: Icons.access_time_rounded,
            text: '$start – $eind',
          ),
          const SizedBox(height: 10),
          _roosterPremiumInfoRow(
            icon: Icons.location_on_rounded,
            text: adres,
            maxLines: 2,
          ),
          if (expandVertically) const Spacer() else const SizedBox(height: 14),
          const SizedBox(height: 12),
          _buildTaakAfrondenKnop(task),
                ],
              ),
            );
  }

  Widget _buildTodayCard(Map<String, dynamic> task) {
    final String status = _normStatus(task['mijn_persoonlijke_status']);
    final isGepland = status == 'gepland';
    final isVoltooid = status == 'voltooid';
    final String badgeLabel;
    if (status == 'in_uitvoering') {
      badgeLabel = 'Nu bezig';
    } else if (isGepland) {
      badgeLabel = 'Gepland';
    } else if (isVoltooid) {
      badgeLabel = 'Voltooid';
          } else {
      badgeLabel = task['mijn_persoonlijke_status']?.toString() ?? '—';
    }

    return _buildPremiumRoosterTaskCard(
      task: task,
      isRedVariant: false,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      topChipLabel: badgeLabel,
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
    final isOverdue = isVerleden && !_isTaakAfgerond(taak);

    return _buildPremiumRoosterTaskCard(
      task: taak,
      isRedVariant: isOverdue,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      expandVertically: true,
      topChipLabel: datumTekst,
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
            'Vergeten & Komende Opdrachten',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: (MediaQuery.of(context).size.height * 0.35).clamp(300.0, 420.0),
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
