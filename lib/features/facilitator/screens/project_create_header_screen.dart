import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import 'quote_survey_screen.dart';

/// "Direct project" header: [offertes] row with [is_direct_project] = true,
/// then [QuoteSurveyScreen] to capture rooms; triggers set status to `signed`.
class ProjectCreateHeaderScreen extends StatefulWidget {
  const ProjectCreateHeaderScreen({super.key});

  @override
  State<ProjectCreateHeaderScreen> createState() =>
      _ProjectCreateHeaderScreenState();
}

class _ProjectCreateHeaderScreenState extends State<ProjectCreateHeaderScreen> {
  final _formKey = GlobalKey<FormState>();
  static const _radius = 24.0;
  static const _navy = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _subtle = Color(0xFFF1F5F9);
  static const _blue = Color(0xFF2563EB);
  static const _page = Color(0xFFF7F8FB);
  final _weekdagen = <String>['Maandag', 'Dinsdag', 'Woensdag', 'Donderdag', 'Vrijdag', 'Zaterdag', 'Zondag'];

  List<Map<String, dynamic>> _klanten = const [];
  String? _selectedBedrijfId;
  String _frequentieType = 'regulier';
  String _periodiek = '1_keer_per_jaar';
  String? _werkRegio;
  DateTime? _start;
  DateTime? _eind;
  TimeOfDay? _tStart;
  TimeOfDay? _tEnd;
  double _duurUren = 1.5; // basis_uren_per_opdracht (quarter-hour steps)
  final Set<String> _days = {};
  String _looptijd = '1_jaar';
  bool _loadingKlanten = true;
  bool _saving = false;

  bool _heeftGekoppeldeOfferte = false;
  bool _zelfdeAdresAlsOfferte = false;
  final _straatCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  final _plaatsCtrl = TextEditingController();

  Future<void> _onBedrijfChanged(String? newValue) async {
    setState(() {
      _selectedBedrijfId = newValue;
      _heeftGekoppeldeOfferte = false;
      _zelfdeAdresAlsOfferte = false;
    });

    final id = (newValue ?? '').trim();
    if (id.isEmpty) return;

    final offerteCheck = await AppSupabase.client
        .from('offertes')
        .select('id')
        .eq('bedrijf_id', id)
        .limit(1)
        .maybeSingle();

    if (!mounted) return;
    final has = offerteCheck != null;
    setState(() {
      _heeftGekoppeldeOfferte = has;
      _zelfdeAdresAlsOfferte = has;
    });
  }

  static const _freqOpts = [
    _Opt('1_keer_per_jaar', '1 keer per jaar'),
    _Opt('2_keer_per_jaar', '2 keer per jaar'),
    _Opt('3_keer_per_jaar', '3 keer per jaar'),
    _Opt('4_keer_per_jaar', '4 keer per jaar'),
    _Opt('6_keer_per_jaar', '6 keer per jaar'),
    _Opt('op_afroep', 'Op afroep'),
  ];
  static const _regioOpts = [
    'Amsterdam',
    "'t Gooi",
    'Stichtse Vecht',
    'Utrecht',
    'Amersfoort',
    'De Ronde Venen',
    'Wijdemeren',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadKlanten());
  }

  @override
  void dispose() {
    _straatCtrl.dispose();
    _postcodeCtrl.dispose();
    _plaatsCtrl.dispose();
    super.dispose();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  String _fmtDateDb(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _fmtTimeDb(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
  String _fmtDateUi(DateTime? d) =>
      d == null ? '' : DateFormat('dd-MM-yyyy').format(d);
  String _fmtTimeUi(TimeOfDay? t) => t == null
      ? ''
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _buildAdresVolledig({
    required String straat,
    required String postcode,
    required String plaats,
  }) {
    final s = straat.trim();
    final pc = postcode.trim();
    final pl = plaats.trim();
    final right = [pc, pl].where((x) => x.isNotEmpty).join(' ').trim();
    if (s.isEmpty) return right;
    if (right.isEmpty) return s;
    return '$s, $right';
  }

  String _duurLabel() {
    final totalMin = (_duurUren * 60).round();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h <= 0) return '$m min';
    if (m == 0) return '$h uur';
    return '$h uur ${m.toString().padLeft(2, '0')} min';
  }

  void _adjustDuur(bool increase) {
    final next = (_duurUren + (increase ? 0.25 : -0.25)).clamp(0.25, 24.0);
    setState(() {
      _duurUren = next;
    });
  }

  void _applyLooptijdFromStart() {
    final s = _start;
    if (s == null) return;
    if (_looptijd == '6_maanden') {
      _eind = DateTime(s.year, s.month + 6, s.day);
      return;
    }
    if (_looptijd == '1_jaar') {
      _eind = DateTime(s.year + 1, s.month, s.day);
      return;
    }
    if (_looptijd == '2_jaar') {
      _eind = DateTime(s.year + 2, s.month, s.day);
      return;
    }
    // anders: handmatige einddatum (laat _eind ongemoeid)
  }

  Future<void> _loadKlanten() async {
    final u = Supabase.instance.client.auth.currentUser;
    if (u == null) {
      if (mounted) setState(() => _loadingKlanten = false);
      return;
    }
    if (!mounted) return;
    // Direct projects should allow selecting any bedrijf (incl. offer-generated).
    // Keep the UI responsible for selection; do not restrict by is_klant / is_handmatig.
    setState(() => _loadingKlanten = true);
    try {
      final res = await AppSupabase.client
          .from('bedrijven')
          .select()
          .order('bedrijfsnaam', ascending: true);
      final list = (res as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _klanten = list;
        _loadingKlanten = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _klanten = const [];
          _loadingKlanten = false;
        });
        _toast('Klanten laden mislukt: $e', err: true);
      }
    }
  }

  void _toast(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: err ? const Color(0xFFDC2626) : _blue,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius)),
        content: Text(m, style: GoogleFonts.lato(fontWeight: FontWeight.w800)),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if ((_selectedBedrijfId ?? '').trim().isEmpty) {
      _toast('Kies een klant.', err: true);
      return;
    }
    final selectedId = (_selectedBedrijfId ?? '').trim();

    // Adres toggle validation + offerte check (early exit)
    Map<String, dynamic>? offerteAdres;
    if (_zelfdeAdresAlsOfferte) {
      offerteAdres = await AppSupabase.client
          .from('offertes')
          .select('id, uitvoer_adres_straat_huisnr, uitvoer_adres_postcode, uitvoer_adres_stad')
          .eq('bedrijf_id', selectedId)
          .order('aangemaakt_op', ascending: false)
          .limit(1)
          .maybeSingle();
      if (offerteAdres == null) {
        _toast(
          'Geen offerte gevonden voor deze klant. Zet de adres-schakelaar uit en vul het adres handmatig in.',
          err: true,
        );
        return;
      }
    } else {
      if (_straatCtrl.text.trim().isEmpty) {
        _toast('Vul straat & huisnummer in.', err: true);
        return;
      }
    }
    if (_start == null || _eind == null) {
      _toast('Kies start- en einddatum project.', err: true);
      return;
    }
    if (_eind!.isBefore(_start!)) {
      _toast('Eind moet na start liggen.', err: true);
      return;
    }
    if (_tStart == null || _tEnd == null) {
      _toast('Kies starttijd en eindtijd.', err: true);
      return;
    }
    if (_frequentieType != 'incidenteel' && _days.isEmpty) {
      _toast('Kies minimaal 1 vaste weekdag.', err: true);
      return;
    }
    if (_werkRegio == null) {
      _toast('Kies een werkregio.', err: true);
      return;
    }
    if (_frequentieType == 'periodiek' &&
        (_periodiek.trim().isEmpty)) {
      _toast('Kies een periodieke frequentie.', err: true);
      return;
    }

    setState(() => _saving = true);
    final b = _klanten.firstWhere(
      (k) => _text(k['id']) == selectedId,
      orElse: () => const <String, dynamic>{},
    );
    if (b.isEmpty) {
      _toast('Geselecteerde klant niet gevonden.', err: true);
      if (mounted) setState(() => _saving = false);
      return;
    }
    final uid = AppSupabase.client.auth.currentUser?.id;
    final straat = _text(b['adres'] ?? b['adres_straat']);
    final postcode = _text(b['adres_postcode'] ?? b['postcode']);
    final stad = _text(b['adres_stad'] ?? b['stad']);
    final kvk = _text(b['kvk_nummer'] ?? b['kvk']);

    final currentUserId = AppSupabase.client.auth.currentUser?.id;
    final klantRecord = await AppSupabase.client
        .from('gebruikers')
        .select('id')
        .eq('bedrijf_id', selectedId)
        .eq('rol', 'klant')
        .limit(1)
        .maybeSingle();
    final klantId = klantRecord == null ? null : klantRecord['id'];

    String? definitiefAdres;
    if (!_zelfdeAdresAlsOfferte) {
      definitiefAdres = _buildAdresVolledig(
        straat: _straatCtrl.text,
        postcode: _postcodeCtrl.text,
        plaats: _plaatsCtrl.text,
      );
    } else {
      definitiefAdres = _buildAdresVolledig(
        straat: _text(offerteAdres?['uitvoer_adres_straat_huisnr']),
        postcode: _text(offerteAdres?['uitvoer_adres_postcode']),
        plaats: _text(offerteAdres?['uitvoer_adres_stad']),
      );
    }

    final payload = <String, dynamic>{
      'bedrijf_id': b['id'],
      'bedrijfsnaam_klant': _text(b['bedrijfsnaam']),
      'kvk_nummer': kvk,
      'werk_regio': _werkRegio,
      'adres_straat_huisnr': straat,
      'adres_postcode': postcode,
      'adres_stad': stad,
      'contact_voornaam': _text(b['contact_voornaam'] ?? b['primaire_voornaam']),
      'contact_achternaam': _text(b['contact_achternaam'] ?? b['primaire_achternaam']),
      'contact_email': _text(b['contact_email'] ?? b['primaire_email'] ?? b['facturatie_email']),
      'contact_telefoon': _text(b['contact_telefoon'] ?? b['telefoon'] ?? b['vast_telefoonnummer']),
      'frequentie_type': _frequentieType,
      'periodieke_frequentie': _frequentieType == 'periodiek' ? _periodiek : null,
      'contract_startdatum': _fmtDateDb(_start!), // db column name kept
      'contract_einddatum': _fmtDateDb(_eind!),   // db column name kept
      'reguliere_weekdagen': _days.map((d) => d.toLowerCase()).toList(),
      'tijdslot_start': _fmtTimeDb(_tStart!),
      'tijdslot_eind': _fmtTimeDb(_tEnd!),
      'basis_uren_per_opdracht': _duurUren,
      'uitvoer_adres_volledig': definitiefAdres,
      'facilitator_id': currentUserId,
      'klant_id': klantId,
      'is_direct_project': true,
      'status': 'concept',
    };
    if (uid != null) payload['aangemaakt_door_id'] = uid;

    try {
      final ins = await AppSupabase.client
          .from('offertes')
          .insert(payload)
          .select('id')
          .single();
      final newId = _text(ins['id']);
      if (newId.isEmpty) {
        _toast('Geen offerte-id teruggekregen.', err: true);
        return;
      }
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(
              name: '/facilitator/projects/direct/survey'),
          builder: (_) => QuoteSurveyScreen(
                offerteId: newId,
                isDirectProject: true,
              ),
        ),
      );
    } catch (e) {
      _toast('Opslaan mislukt: $e', err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toonIncidenteelPrijsModalEnSlaOp() async {
    // Reuse same safety checks as _save(), but without weekdagen requirement.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if ((_selectedBedrijfId ?? '').trim().isEmpty) {
      _toast('Kies een klant.', err: true);
      return;
    }
    final selectedId = (_selectedBedrijfId ?? '').trim();

    // Adres toggle validation + offerte check (early exit)
    Map<String, dynamic>? offerteAdres;
    if (_zelfdeAdresAlsOfferte) {
      offerteAdres = await AppSupabase.client
          .from('offertes')
          .select('id, uitvoer_adres_straat_huisnr, uitvoer_adres_postcode, uitvoer_adres_stad')
          .eq('bedrijf_id', selectedId)
          .order('aangemaakt_op', ascending: false)
          .limit(1)
          .maybeSingle();
      if (offerteAdres == null) {
        _toast(
          'Geen offerte gevonden voor deze klant. Zet de adres-schakelaar uit en vul het adres handmatig in.',
          err: true,
        );
        return;
      }
    } else {
      if (_straatCtrl.text.trim().isEmpty) {
        _toast('Vul straat & huisnummer in.', err: true);
        return;
      }
    }
    if (_start == null || _eind == null) {
      _toast('Kies start- en einddatum project.', err: true);
      return;
    }
    if (_eind!.isBefore(_start!)) {
      _toast('Eind moet na start liggen.', err: true);
      return;
    }
    if (_tStart == null || _tEnd == null) {
      _toast('Kies starttijd en eindtijd.', err: true);
      return;
    }
    if (_werkRegio == null) {
      _toast('Kies een werkregio.', err: true);
      return;
    }

    if (!mounted) return;
    final prijsController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Vaste prijs bepalen'),
          content: TextFormField(
            controller: prijsController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Prijs per beurt',
              hintText: 'Bijv. 125,50',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Opslaan'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final prijsText = prijsController.text.trim();
    final prijs = double.tryParse(prijsText.replaceAll(',', '.')) ?? 0.0;
    if (prijs <= 0) {
      _toast('Vul een geldige prijs in.', err: true);
      return;
    }

    setState(() => _saving = true);
    final b = _klanten.firstWhere(
      (k) => _text(k['id']) == selectedId,
      orElse: () => const <String, dynamic>{},
    );
    if (b.isEmpty) {
      _toast('Geselecteerde klant niet gevonden.', err: true);
      if (mounted) setState(() => _saving = false);
      return;
    }

    // Incidenteel projects are stored as rows in [projecten] (NOT offertes).

    final currentUserId = AppSupabase.client.auth.currentUser?.id;
    final klantRecord = await AppSupabase.client
        .from('gebruikers')
        .select('id')
        .eq('bedrijf_id', selectedId)
        .eq('rol', 'klant')
        .limit(1)
        .maybeSingle();
    final klantId = klantRecord == null ? null : klantRecord['id'];

    String? definitiefAdres;
    if (!_zelfdeAdresAlsOfferte) {
      definitiefAdres = _buildAdresVolledig(
        straat: _straatCtrl.text,
        postcode: _postcodeCtrl.text,
        plaats: _plaatsCtrl.text,
      );
    } else {
      definitiefAdres = _buildAdresVolledig(
        straat: _text(offerteAdres?['uitvoer_adres_straat_huisnr']),
        postcode: _text(offerteAdres?['uitvoer_adres_postcode']),
        plaats: _text(offerteAdres?['uitvoer_adres_stad']),
      );
    }

    final payload = <String, dynamic>{
      'bedrijf_id': b['id'],
      'project_naam':
          _text(b['bedrijfsnaam']).isEmpty ? 'Project' : _text(b['bedrijfsnaam']),
      'werk_regio': _werkRegio,
      'frequentie_type': _frequentieType,
      // Required by projecten table (NOT NULL constraints).
      'start_datum': _fmtDateDb(_start!),
      'eind_datum': _fmtDateDb(_eind!),
      'contract_startdatum': _fmtDateDb(_start!),
      'contract_einddatum': _fmtDateDb(_eind!),
      'reguliere_weekdagen': null,
      'tijdslot_start': _fmtTimeDb(_tStart!),
      'tijdslot_eind': _fmtTimeDb(_tEnd!),
      'basis_uren_per_opdracht': _duurUren,
      'uitvoer_adres_volledig': definitiefAdres,
      'facilitator_id': currentUserId,
      'klant_id': klantId,
      'status': 'actief',
      // Pricing column for incidenteel fixed appointment.
      'vaste_prijs_per_beurt': prijs,
    };

    try {
      await AppSupabase.client.from('projecten').insert(payload).select('id').single();
      if (!mounted) return;
      _toast('Project opgeslagen.', err: false);
      Navigator.of(context).pop(true);
    } catch (e) {
      _toast('Opslaan mislukt: $e', err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: _navy),
        title: Text(
          'Nieuw project (direct)',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            color: _navy,
            fontSize: 19,
          ),
        ),
      ),
      body: SelectionArea(
        child: _loadingKlanten
            ? const Center(child: CupertinoActivityIndicator(radius: 14))
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    _card(
                      title: 'Klant',
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _selectedBedrijfId,
                            decoration: _dec('Selecteer Klant / Bedrijf'),
                            items: _klanten.map<DropdownMenuItem<String>>((bedrijf) {
                              return DropdownMenuItem<String>(
                                value: bedrijf['id'].toString(),
                                child: Text(
                                  bedrijf['bedrijfsnaam']?.toString() ?? 'Onbekend bedrijf',
                                  style: GoogleFonts.lato(fontWeight: FontWeight.w600),
                                ),
                              );
                            }).toList(),
                            onChanged: _onBedrijfChanged,
                            validator: (value) => value == null || value.isEmpty
                                ? 'Selecteer een klant'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Zelfde uitvoer adres als offerte?',
                              style: GoogleFonts.lato(
                                fontWeight: FontWeight.w800,
                                color: _navy,
                              ),
                            ),
                            subtitle: Text(
                              _heeftGekoppeldeOfferte
                                  ? 'Gebruik het adres uit de offerte'
                                  : 'Geen offerte gevonden voor dit bedrijf, vul handmatig in.',
                              style: GoogleFonts.lato(
                                fontWeight: FontWeight.w600,
                                color: _muted,
                              ),
                            ),
                            value: _zelfdeAdresAlsOfferte,
                            onChanged: !_heeftGekoppeldeOfferte
                                ? null
                                : (v) => setState(() => _zelfdeAdresAlsOfferte = v),
                          ),
                          Visibility(
                            visible: !_zelfdeAdresAlsOfferte,
                            child: Column(
                              children: [
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _straatCtrl,
                                  decoration: _dec('Straat & Huisnummer'),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _postcodeCtrl,
                                  decoration: _dec('Postcode'),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _plaatsCtrl,
                                  decoration: _dec('Plaatsnaam'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _card(
                      title: 'Project & planning',
                      child: Column(
                        children: [
                          _dropdown(
                            label: 'Frequentie type',
                            value: _frequentieType,
                            items: const [
                              DropdownMenuItem(value: 'regulier', child: Text('Regulier')),
                              DropdownMenuItem(value: 'frequent', child: Text('Frequent')),
                              DropdownMenuItem(value: 'periodiek', child: Text('Periodiek')),
                              DropdownMenuItem(value: 'incidenteel', child: Text('Incidenteel')),
                            ],
                            onChanged: (v) => setState(() {
                              _frequentieType = v ?? 'regulier';
                              // Ensure periodieke frequentie doesn't block validation when hidden.
                              if (_frequentieType != 'periodiek') {
                                _periodiek = '1_keer_per_jaar';
                              }
                            }),
                          ),
                          const SizedBox(height: 12),
                          if (_frequentieType == 'periodiek')
                            _dropdown(
                              label: 'Periodieke frequentie',
                              value: _periodiek,
                              items: _freqOpts
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.id,
                                      child: Text(
                                        e.label,
                                        style: GoogleFonts.lato(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(
                                () => _periodiek = v ?? '1_keer_per_jaar',
                              ),
                            ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: _werkRegio,
                            decoration: _dec('Werk regio *'),
                            items: _regioOpts
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                      e,
                                      style: GoogleFonts.lato(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _werkRegio = v),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Verplicht' : null,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _dateTile(
                                  'Start project',
                                  _start,
                                  (d) => setState(() {
                                    _start = d;
                                    _applyLooptijdFromStart();
                                  }),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('6 maanden'),
                                selected: _looptijd == '6_maanden',
                                onSelected: (v) => setState(() {
                                  _looptijd = '6_maanden';
                                  _applyLooptijdFromStart();
                                }),
                              ),
                              ChoiceChip(
                                label: const Text('1 jaar'),
                                selected: _looptijd == '1_jaar',
                                onSelected: (v) => setState(() {
                                  _looptijd = '1_jaar';
                                  _applyLooptijdFromStart();
                                }),
                              ),
                              ChoiceChip(
                                label: const Text('2 jaar'),
                                selected: _looptijd == '2_jaar',
                                onSelected: (v) => setState(() {
                                  _looptijd = '2_jaar';
                                  _applyLooptijdFromStart();
                                }),
                              ),
                              ChoiceChip(
                                label: const Text('Kies einddatum'),
                                selected: _looptijd == 'anders',
                                onSelected: (v) => setState(() {
                                  _looptijd = 'anders';
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_looptijd == 'anders')
                            _dateTile(
                              'Eind project',
                              _eind,
                              (d) => setState(() => _eind = d),
                            )
                          else
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Eind project: ${_fmtDateUi(_eind).isEmpty ? '—' : _fmtDateUi(_eind)}',
                                style: GoogleFonts.lato(
                                  fontWeight: FontWeight.w700,
                                  color: _muted,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _timeTile(
                                  'Starttijd',
                                  _tStart,
                                  (t) => setState(() => _tStart = t),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _timeTile(
                                  'Eindtijd',
                                  _tEnd,
                                  (t) => setState(() => _tEnd = t),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => _adjustDuur(false),
                                icon: const Icon(Icons.remove_circle_outline_rounded),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      'Verwachte benodigde tijd',
                                      style: GoogleFonts.lato(fontWeight: FontWeight.w800, color: _navy),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _duurLabel(),
                                      style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 16, color: _navy),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => _adjustDuur(true),
                                icon: const Icon(Icons.add_circle_outline_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Vaste weekdagen',
                              style: GoogleFonts.lato(
                                fontWeight: FontWeight.w800,
                                color: _navy,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_frequentieType != 'incidenteel')
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _weekdagen.map((d) {
                                final sel = _days.contains(d);
                                return FilterChip(
                                  label: Text(d, style: GoogleFonts.lato()),
                                  selected: sel,
                                  onSelected: (v) {
                                    setState(() {
                                      if (v) {
                                        _days.add(d);
                                      } else {
                                        _days.remove(d);
                                      }
                                    });
                                  },
                                  selectedColor: _blue.withValues(alpha: 0.2),
                                  checkmarkColor: _blue,
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _submitButtons(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _submitButtons() {
    final isIncidenteel = _frequentieType == 'incidenteel';
    final baseStyle = FilledButton.styleFrom(
      backgroundColor: _blue,
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
    );

    if (!isIncidenteel) {
      return FilledButton(
        onPressed: _saving ? null : _save,
        style: baseStyle,
        child: _saving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                'Volgende: ruimtes & diensten',
                style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 16),
              ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: baseStyle,
            child: Text(
              'Volgende: ruimtes & diensten',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: _saving ? null : _toonIncidenteelPrijsModalEnSlaOp,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_radius),
              ),
            ),
            child: Text(
              'Vaste afspraak',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _dec(String l) => InputDecoration(
        labelText: l,
        labelStyle: GoogleFonts.lato(fontWeight: FontWeight.w600, color: _muted),
        filled: true,
        fillColor: _subtle,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_radius),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_radius),
            borderSide: const BorderSide(color: _blue, width: 1.2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  Widget _dropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: value,
      decoration: _dec(label),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _dateTile(
      String label, DateTime? v, void Function(DateTime) onPick) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 10, 12, 31),
          initialDate: v ?? now,
        );
        if (d != null) onPick(d);
      },
      borderRadius: BorderRadius.circular(_radius),
      child: InputDecorator(
        decoration: _dec(label),
        child: Text(
          v == null ? 'Kies…' : _fmtDateUi(v),
          style: GoogleFonts.lato(
              fontWeight: FontWeight.w700, color: _navy, fontSize: 15),
        ),
      ),
    );
  }

  Widget _timeTile(
      String label, TimeOfDay? v, void Function(TimeOfDay) onPick) {
    return InkWell(
      onTap: () async {
        final t = await showTimePicker(
          context: context,
          initialTime: v ?? const TimeOfDay(hour: 8, minute: 0),
          builder: (ctx, child) {
            return MediaQuery(
              data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
        if (t != null) onPick(t);
      },
      borderRadius: BorderRadius.circular(_radius),
      child: InputDecorator(
        decoration: _dec(label),
        child: Text(
          v == null ? 'Kies…' : _fmtTimeUi(v),
          style: GoogleFonts.lato(
              fontWeight: FontWeight.w700, color: _navy, fontSize: 15),
        ),
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: GoogleFonts.lato(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: _navy,
                  letterSpacing: -0.2)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _Opt {
  const _Opt(this.id, this.label);
  final String id;
  final String label;
}
