import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_client.dart';
import '../services/offerte_pricing_service.dart';
import '../../../core/widgets/app_drawer.dart';
import 'quote_survey_screen.dart';

/// "De Kaft" — lead-entry form that creates the `offertes` header row.
///
/// Fields align with the `offertes` table columns. `offerte_nummer` is left
/// null on insert so Supabase can assign it automatically (trigger/sequence),
/// which keeps this row as a "CONCEPT" in the overview until finalized.
class QuoteCreateHeaderScreen extends StatefulWidget {
  const QuoteCreateHeaderScreen({super.key, this.offerteId});

  /// When set, this screen edits an existing quote header ("De Kaft").
  final String? offerteId;

  @override
  State<QuoteCreateHeaderScreen> createState() =>
      _QuoteCreateHeaderScreenState();
}

class _QuoteCreateHeaderScreenState extends State<QuoteCreateHeaderScreen> {
  final _formKey = GlobalKey<FormState>();

  // Section 1 - Bedrijf
  final _bedrijfsnaam = TextEditingController();
  final _kvk = TextEditingController();
  String? _werkRegio;
  final _adresStraat = TextEditingController();
  final _adresPostcode = TextEditingController();
  final _adresStad = TextEditingController();
  final _uitvoerAdresStraat = TextEditingController();
  final _uitvoerAdresPostcode = TextEditingController();
  final _uitvoerAdresStad = TextEditingController();

  // Section 2 - Contactpersoon
  final _contactVoornaam = TextEditingController();
  final _contactAchternaam = TextEditingController();
  final _contactEmail = TextEditingController();
  final _contactTelefoon = TextEditingController();

  // Section 3 - Contract instellingen
  String _contractType = 'flexibel';
  String _periodiekeFrequentie = '1_keer_per_jaar';
  String _looptijd = '1_jaar';
  DateTime? _contractStartDatum;
  DateTime? _contractEindDatumHandmatig;
  DateTime? geselecteerdeUitvoerDatum;
  bool isDatumIndicatief = true;
  bool _inclusiefMaterialen = false;
  final Set<String> _reguliereWeekdagen = <String>{};
  TimeOfDay? _tijdslotStart;
  TimeOfDay? _tijdslotEind;

  // Section 4 - Afwijkende periode
  bool _heeftAfwijkendUitvoerAdres = false;
  bool _heeftAfwijkendePeriode = false;
  DateTime? _afwijkendePeriodeStart;
  DateTime? _afwijkendePeriodeEind;
  final Set<String> _afwijkendeWeekdagen = <String>{};

  bool _saving = false;
  bool _loading = false;

  static const List<_Option> _contractTypes = [
    _Option('vast', 'Vast'),
    _Option('flexibel', 'Flexibel'),
    _Option('eenmalig', 'Eenmalig'),
    _Option('incidenteel', 'Incidenteel'),
  ];

  static const List<_Option> _frequenties = [
    _Option('1_keer_per_jaar', '1 keer per jaar'),
    _Option('2_keer_per_jaar', '2 keer per jaar'),
    _Option('3_keer_per_jaar', '3 keer per jaar'),
    _Option('4_keer_per_jaar', '4 keer per jaar'),
    _Option('6_keer_per_jaar', '6 keer per jaar'),
    _Option('op_afroep', 'Op afroep'),
  ];

  static const List<_Option> _looptijdOpties = [
    _Option('6_maanden', '6 maanden'),
    _Option('1_jaar', '1 jaar'),
    _Option('2_jaar', '2 jaar'),
    _Option('anders', 'anders'),
  ];

  static const List<String> _weekdagen = [
    'Maandag',
    'Dinsdag',
    'Woensdag',
    'Donderdag',
    'Vrijdag',
    'Zaterdag',
    'Zondag',
  ];

  static const List<String> _werkRegioOpties = [
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
    final id = (widget.offerteId ?? '').trim();
    if (id.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting(id));
    }
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  void _setContractType(String nieuwType) {
    final t = nieuwType.toLowerCase().trim();
    setState(() {
      _contractType = t;
      // DE CRUCIALE FIX: Wis de weekdagen direct als het contracttype geen weekdagen ondersteunt!
      if (t == 'eenmalig' || t == 'incidenteel') {
        _reguliereWeekdagen.clear();
      }
    });
  }

  void _toggleWeekdag(String dag) {
    final schoneDag = dag.toLowerCase().trim();
    setState(() {
      if (_reguliereWeekdagen.contains(schoneDag)) {
        _reguliereWeekdagen.remove(schoneDag);
      } else {
        _reguliereWeekdagen.add(schoneDag);
      }
    });
  }

  TimeOfDay? _parseTime(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _loadExisting(String offerteId) async {
    setState(() => _loading = true);
    try {
      final row = await AppSupabase.client
          .from('offertes')
          .select()
          .eq('id', offerteId)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        _showError('Kon offerte niet laden.');
        return;
      }

      final m = Map<String, dynamic>.from(row as Map);

      // 1. Fix de Initialisatie (Veilig inladen & Ontdubbelen)
      final dynamic dbWeekdagen = m['reguliere_weekdagen'];
      final List<String> initWeekdagen =
          (dbWeekdagen != null && dbWeekdagen is List)
          ? dbWeekdagen
                .map((e) => e.toString().toLowerCase().trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList()
          : <String>[];

      setState(() {
        _bedrijfsnaam.text = _text(m['bedrijfsnaam_klant']);
        _kvk.text = _text(m['kvk_nummer']);
        final regio = _text(m['werk_regio']);
        _werkRegio = regio.isEmpty ? null : regio;

        _adresStraat.text = _text(m['adres_straat_huisnr']);
        _adresPostcode.text = _text(m['adres_postcode']);
        _adresStad.text = _text(m['adres_stad']);

        final uitvoerStraat = _text(m['uitvoer_adres_straat_huisnr']);
        final uitvoerPostcode = _text(m['uitvoer_adres_postcode']);
        final uitvoerStad = _text(m['uitvoer_adres_stad']);
        _heeftAfwijkendUitvoerAdres =
            uitvoerStraat.isNotEmpty ||
            uitvoerPostcode.isNotEmpty ||
            uitvoerStad.isNotEmpty;
        _uitvoerAdresStraat.text = uitvoerStraat;
        _uitvoerAdresPostcode.text = uitvoerPostcode;
        _uitvoerAdresStad.text = uitvoerStad;

        _contactVoornaam.text = _text(m['contact_voornaam']);
        _contactAchternaam.text = _text(m['contact_achternaam']);
        _contactEmail.text = _text(m['contact_email']);
        _contactTelefoon.text = _text(m['contact_telefoon']);

        final ct = _text(m['contract_type']).toLowerCase();
        if (ct.isNotEmpty) _contractType = ct;

        final freq = _text(m['periodieke_frequentie']).toLowerCase();
        if (freq.isNotEmpty) _periodiekeFrequentie = freq;

        _contractStartDatum = DateTime.tryParse(
          _text(m['contract_startdatum']),
        );
        _contractEindDatumHandmatig = DateTime.tryParse(
          _text(m['contract_einddatum']),
        );
        geselecteerdeUitvoerDatum = DateTime.tryParse(
          _text(m['uitvoer_datum']),
        );
        final indicRaw = m['datum_is_indicatief'];
        if (indicRaw is bool) {
          isDatumIndicatief = indicRaw;
        } else if (indicRaw != null) {
          isDatumIndicatief = indicRaw.toString().toLowerCase() == 'true';
        }

        _inclusiefMaterialen = m['inclusief_materialen'] == true;

        _reguliereWeekdagen
          ..clear()
          ..addAll(initWeekdagen);

        _tijdslotStart = _parseTime(_text(m['tijdslot_start']));
        _tijdslotEind = _parseTime(_text(m['tijdslot_eind']));

        final apStart = DateTime.tryParse(_text(m['afwijkende_periode_start']));
        final apEnd = DateTime.tryParse(_text(m['afwijkende_periode_eind']));
        _heeftAfwijkendePeriode = apStart != null && apEnd != null;
        _afwijkendePeriodeStart = apStart;
        _afwijkendePeriodeEind = apEnd;

        final aw =
            (m['afwijkende_weekdagen'] as List?)
                ?.whereType<String>()
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList() ??
            const <String>[];
        _afwijkendeWeekdagen
          ..clear()
          ..addAll(aw);
      });
    } catch (e) {
      if (!mounted) return;
      _showError('Kon offerte niet laden: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _bedrijfsnaam.dispose();
    _kvk.dispose();
    _adresStraat.dispose();
    _adresPostcode.dispose();
    _adresStad.dispose();
    _uitvoerAdresStraat.dispose();
    _uitvoerAdresPostcode.dispose();
    _uitvoerAdresStad.dispose();
    _contactVoornaam.dispose();
    _contactAchternaam.dispose();
    _contactEmail.dispose();
    _contactTelefoon.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(
    BuildContext context,
    String label, {
    IconData? icon,
    String? hint,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon),
      filled: true,
      fillColor: isDark ? const Color(0xFF1B1B23) : Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.4,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Future<void> _pickDate({
    required DateTime? initial,
    required ValueChanged<DateTime> onPicked,
    required String helpText,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
      helpText: helpText,
    );
    if (picked == null || !mounted) return;
    setState(() => onPicked(picked));
  }

  Future<void> _pickTime({
    required TimeOfDay? initial,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() => onPicked(picked));
  }

  DateTime? _autoCalculatedEndDate() {
    if (_contractStartDatum == null) return null;
    final start = _contractStartDatum!;
    switch (_looptijd) {
      case '6_maanden':
        return DateTime(start.year, start.month + 6, start.day);
      case '1_jaar':
        return DateTime(start.year + 1, start.month, start.day);
      case '2_jaar':
        return DateTime(start.year + 2, start.month, start.day);
      case 'anders':
        return _contractEindDatumHandmatig;
      default:
        return null;
    }
  }

  bool _isEmailValid(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return re.hasMatch(trimmed);
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _fmtDateHuman(DateTime? d) =>
      d == null ? '' : DateFormat('dd-MM-yyyy').format(d);
  String _fmtTimeHuman(TimeOfDay? t) => t == null
      ? ''
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String _fmtTimeDb(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  bool _validateConditionalFields() {
    if (_heeftAfwijkendUitvoerAdres) {
      if (_uitvoerAdresStraat.text.trim().isEmpty ||
          _uitvoerAdresPostcode.text.trim().isEmpty ||
          _uitvoerAdresStad.text.trim().isEmpty) {
        _showError('Vul alle velden van het afwijkend uitvoer adres in.');
        return false;
      }
    }

    if (_contractType == 'eenmalig') {
      if (geselecteerdeUitvoerDatum == null) {
        _showError('Selecteer een gewenste uitvoerdatum.');
        return false;
      }
    } else {
      if (_contractStartDatum == null) {
        _showError('Selecteer een startdatum.');
        return false;
      }

      if (_looptijd == 'anders' && _contractEindDatumHandmatig == null) {
        _showError('Selecteer een einddatum voor het contract.');
        return false;
      }

      final contractEnd = _autoCalculatedEndDate();
      if (contractEnd == null) {
        _showError('Kan contracteinddatum niet bepalen.');
        return false;
      }
      if (contractEnd.isBefore(_contractStartDatum!)) {
        _showError('Contracteinddatum moet na de startdatum liggen.');
        return false;
      }
    }

    if (_contractType != 'eenmalig' && _contractType != 'incidenteel') {
      if (_reguliereWeekdagen.isEmpty) {
        _showError('Selecteer minimaal 1 reguliere weekdag.');
        return false;
      }
    }

    if (_tijdslotStart == null || _tijdslotEind == null) {
      _showError('Selecteer begin- en eindtijd.');
      return false;
    }

    if (_heeftAfwijkendePeriode) {
      if (_afwijkendePeriodeStart == null || _afwijkendePeriodeEind == null) {
        _showError('Selecteer start en eind van de afwijkende periode.');
        return false;
      }
      if (_afwijkendePeriodeEind!.isBefore(_afwijkendePeriodeStart!)) {
        _showError('Eind seizoen moet na start seizoen liggen.');
        return false;
      }
      if (_afwijkendeWeekdagen.isEmpty) {
        _showError('Selecteer minimaal 1 afwijkende weekdag.');
        return false;
      }
    }

    return true;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_validateConditionalFields()) return;

    final contractTypeDb = _contractType.toLowerCase();
    final isEenmalig = contractTypeDb == 'eenmalig';
    final hideWeekdagen = isEenmalig || contractTypeDb == 'incidenteel';

    DateTime? contractEinddatum;
    if (!isEenmalig) {
      contractEinddatum = _autoCalculatedEndDate();
      if (contractEinddatum == null || _contractStartDatum == null) {
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final userId = AppSupabase.client.auth.currentUser?.id;
      final reguliereWeekdagenDb = hideWeekdagen
          ? null
          : _reguliereWeekdagen
                .map((d) => d.toLowerCase())
                .toList(growable: false);
      final afwijkendeWeekdagenDb = _afwijkendeWeekdagen
          .map((d) => d.toLowerCase())
          .toList(growable: false);
      final frequentieDb = _periodiekeFrequentie
          .replaceAll(' ', '_')
          .toLowerCase();

      final payload = <String, dynamic>{
        'bedrijfsnaam_klant': _bedrijfsnaam.text.trim(),
        'kvk_nummer': _kvk.text.trim(),
        'werk_regio': _werkRegio,
        'adres_straat_huisnr': _adresStraat.text.trim(),
        'adres_postcode': _adresPostcode.text.trim(),
        'adres_stad': _adresStad.text.trim(),
        'uitvoer_adres_straat_huisnr': _heeftAfwijkendUitvoerAdres
            ? _uitvoerAdresStraat.text.trim()
            : null,
        'uitvoer_adres_postcode': _heeftAfwijkendUitvoerAdres
            ? _uitvoerAdresPostcode.text.trim()
            : null,
        'uitvoer_adres_stad': _heeftAfwijkendUitvoerAdres
            ? _uitvoerAdresStad.text.trim()
            : null,
        'contact_voornaam': _contactVoornaam.text.trim(),
        'contact_achternaam': _contactAchternaam.text.trim(),
        'contact_email': _contactEmail.text.trim(),
        'contact_telefoon': _contactTelefoon.text.trim(),
        'contract_type': contractTypeDb,
        'periodieke_frequentie': frequentieDb,
        'uitvoer_datum': isEenmalig
            ? geselecteerdeUitvoerDatum?.toIso8601String()
            : null,
        'datum_is_indicatief': isEenmalig ? isDatumIndicatief : false,
        'contract_startdatum': isEenmalig
            ? null
            : _fmtDate(_contractStartDatum!),
        'contract_einddatum': isEenmalig ? null : _fmtDate(contractEinddatum!),
        'inclusief_materialen': _inclusiefMaterialen,
        'reguliere_weekdagen': reguliereWeekdagenDb,
        'tijdslot_start': _fmtTimeDb(_tijdslotStart!),
        'tijdslot_eind': _fmtTimeDb(_tijdslotEind!),
        'afwijkende_periode_start': _heeftAfwijkendePeriode
            ? _fmtDate(_afwijkendePeriodeStart!)
            : null,
        'afwijkende_periode_eind': _heeftAfwijkendePeriode
            ? _fmtDate(_afwijkendePeriodeEind!)
            : null,
        'afwijkende_weekdagen': _heeftAfwijkendePeriode
            ? afwijkendeWeekdagenDb
            : null,
        'status': 'concept',
        // ignore: use_null_aware_elements — explicit null-skip for Supabase insert
        if (userId != null) 'aangemaakt_door_id': userId,
      };

      final existingId = (widget.offerteId ?? '').trim();
      if (existingId.isNotEmpty) {
        await AppSupabase.client
            .from('offertes')
            .update(payload)
            .eq('id', existingId);
        await OffertePricingService.herberekenEnPersist(existingId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Offerte bijgewerkt.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        );
        Navigator.of(context).pop();
      } else {
        final inserted = await AppSupabase.client
            .from('offertes')
            .insert(payload)
            .select('id')
            .single();
        final newId = (inserted['id'] ?? '').toString();

        if (!mounted) return;
        if (newId.isEmpty) {
          _showError('Kon nieuw offerte-id niet ophalen.');
          return;
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            settings: const RouteSettings(
              name: '/facilitator/quotes/new/survey',
            ),
            builder: (_) =>
                QuoteSurveyScreen(offerteId: newId, isDirectProject: false),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Kon offerte niet aanmaken: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);
    final cardBg = isDark ? const Color(0xFF111019) : Colors.white;
    final contractEindPreview = _autoCalculatedEndDate();

    Widget sectionCard({required String title, required Widget child}) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );
    }

    Widget twoCol({required Widget left, required Widget right}) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(children: [left, const SizedBox(height: 14), right]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 14),
              Expanded(child: right),
            ],
          );
        },
      );
    }

    Widget pickerField({
      required String label,
      required String value,
      required IconData icon,
      required VoidCallback onTap,
      String? Function(String?)? validator,
    }) {
      return TextFormField(
        readOnly: true,
        onTap: _saving ? null : onTap,
        validator: validator,
        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        controller: TextEditingController(text: value),
        decoration: _fieldDecoration(context, label, icon: icon),
      );
    }

    Widget weekdayWrap({
      required Set<String> selected,
      required void Function(String day, bool enabled) onToggle,
    }) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _weekdagen
            .map((d) {
              final String schoneDag = d.toLowerCase().trim();
              final bool isGeselecteerd = selected.contains(schoneDag);
              return FilterChip(
                label: Text(
                  d, // Toon de mooie versie met hoofdletter
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
                selected: isGeselecteerd,
                onSelected: _saving ? null : (v) => onToggle(schoneDag, v),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                side: BorderSide(color: cs.onSurface.withValues(alpha: 0.15)),
                selectedColor: cs.primary.withValues(alpha: 0.14),
                checkmarkColor: cs.primary,
              );
            })
            .toList(growable: false),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(
          (widget.offerteId ?? '').trim().isNotEmpty
              ? 'Offerte bewerken'
              : 'Nieuwe Offerte',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SelectionArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                      children: [
                        Text(
                          'De Kaft',
                          style: GoogleFonts.inter(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Vul de basisgegevens in en ga daarna direct door naar de opname.',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withValues(alpha: 0.70),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Section 1 - Bedrijf
                        sectionCard(
                          title: '1. Bedrijf',
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _bedrijfsnaam,
                                decoration: _fieldDecoration(
                                  context,
                                  'Bedrijfsnaam klant *',
                                  icon: Icons.business,
                                ),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Bedrijfsnaam is verplicht'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _kvk,
                                decoration: _fieldDecoration(
                                  context,
                                  'KVK-nummer',
                                ),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _werkRegio,
                                decoration: _fieldDecoration(
                                  context,
                                  'Werkregio (Verplicht)',
                                  icon: Icons.map_outlined,
                                ),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                ),
                                items: _werkRegioOpties
                                    .map(
                                      (regio) => DropdownMenuItem<String>(
                                        value: regio,
                                        child: Text(
                                          regio,
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: _saving
                                    ? null
                                    : (value) =>
                                          setState(() => _werkRegio = value),
                                validator: (value) =>
                                    (value == null || value.trim().isEmpty)
                                    ? 'Werkregio is verplicht'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _adresStraat,
                                decoration: _fieldDecoration(
                                  context,
                                  'Adres: straat + huisnummer *',
                                ),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Adres is verplicht'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              twoCol(
                                left: TextFormField(
                                  controller: _adresPostcode,
                                  decoration: _fieldDecoration(
                                    context,
                                    'Postcode *',
                                  ),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Postcode is verplicht'
                                      : null,
                                ),
                                right: TextFormField(
                                  controller: _adresStad,
                                  decoration: _fieldDecoration(
                                    context,
                                    'Stad *',
                                  ),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Stad is verplicht'
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile.adaptive(
                                value: _heeftAfwijkendUitvoerAdres,
                                onChanged: _saving
                                    ? null
                                    : (v) => setState(
                                        () => _heeftAfwijkendUitvoerAdres = v,
                                      ),
                                title: Text(
                                  'Afwijkend uitvoer adres?',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 230),
                                curve: Curves.easeInOut,
                                child: !_heeftAfwijkendUitvoerAdres
                                    ? const SizedBox.shrink()
                                    : Column(
                                        children: [
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            controller: _uitvoerAdresStraat,
                                            decoration: _fieldDecoration(
                                              context,
                                              'Uitvoer adres: straat + huisnummer *',
                                            ),
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w700,
                                            ),
                                            validator: (v) {
                                              if (!_heeftAfwijkendUitvoerAdres) {
                                                return null;
                                              }
                                              if (v == null ||
                                                  v.trim().isEmpty) {
                                                return 'Uitvoer adres is verplicht';
                                              }
                                              return null;
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          twoCol(
                                            left: TextFormField(
                                              controller: _uitvoerAdresPostcode,
                                              decoration: _fieldDecoration(
                                                context,
                                                'Uitvoer postcode *',
                                              ),
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w700,
                                              ),
                                              validator: (v) {
                                                if (!_heeftAfwijkendUitvoerAdres) {
                                                  return null;
                                                }
                                                if (v == null ||
                                                    v.trim().isEmpty) {
                                                  return 'Postcode is verplicht';
                                                }
                                                return null;
                                              },
                                            ),
                                            right: TextFormField(
                                              controller: _uitvoerAdresStad,
                                              decoration: _fieldDecoration(
                                                context,
                                                'Uitvoer stad *',
                                              ),
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w700,
                                              ),
                                              validator: (v) {
                                                if (!_heeftAfwijkendUitvoerAdres) {
                                                  return null;
                                                }
                                                if (v == null ||
                                                    v.trim().isEmpty) {
                                                  return 'Stad is verplicht';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Section 2 - Contactpersoon
                        sectionCard(
                          title: '2. Contactpersoon',
                          child: Column(
                            children: [
                              twoCol(
                                left: TextFormField(
                                  controller: _contactVoornaam,
                                  decoration: _fieldDecoration(
                                    context,
                                    'Voornaam *',
                                  ),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Voornaam is verplicht'
                                      : null,
                                ),
                                right: TextFormField(
                                  controller: _contactAchternaam,
                                  decoration: _fieldDecoration(
                                    context,
                                    'Achternaam *',
                                  ),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Achternaam is verplicht'
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _contactEmail,
                                decoration: _fieldDecoration(
                                  context,
                                  'E-mail *',
                                  icon: Icons.mail_outline,
                                ),
                                keyboardType: TextInputType.emailAddress,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'E-mail is verplicht';
                                  }
                                  if (!_isEmailValid(v)) {
                                    return 'Ongeldig e-mailadres';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _contactTelefoon,
                                decoration: _fieldDecoration(
                                  context,
                                  'Telefoonnummer',
                                  icon: Icons.phone_outlined,
                                ),
                                keyboardType: TextInputType.phone,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return null;
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Section 3 - Contract Instellingen
                        sectionCard(
                          title: '3. Contract instellingen',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Contract type *',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _contractTypes
                                    .map(
                                      (o) => ChoiceChip(
                                        label: Text(
                                          o.label,
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        selected: _contractType == o.value,
                                        onSelected: _saving
                                            ? null
                                            : (_) async {
                                                _setContractType(o.value);
                                                final id =
                                                    (widget.offerteId ?? '')
                                                        .trim();
                                                if (id.isNotEmpty) {
                                                  await AppSupabase.client
                                                      .from('offertes')
                                                      .update({
                                                        'contract_type': o.value
                                                            .toLowerCase(),
                                                      })
                                                      .eq('id', id);
                                                  await OffertePricingService.herberekenEnPersist(
                                                    id,
                                                  );
                                                }
                                              },
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                        side: BorderSide(
                                          color: cs.onSurface.withValues(
                                            alpha: 0.16,
                                          ),
                                        ),
                                        selectedColor: cs.primary.withValues(
                                          alpha: 0.14,
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _periodiekeFrequentie,
                                decoration: _fieldDecoration(
                                  context,
                                  'Frequentie *',
                                ),
                                items: _frequenties
                                    .map(
                                      (o) => DropdownMenuItem(
                                        value: o.value,
                                        child: Text(o.label),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: _saving
                                    ? null
                                    : (v) => setState(
                                        () => _periodiekeFrequentie =
                                            v ?? _periodiekeFrequentie,
                                      ),
                              ),
                              CheckboxListTile(
                                title: const Text(
                                  'Wij leveren schoonmaakmaterialen aan',
                                ),
                                subtitle: const Text(
                                  'Voegt € 15,00 per beurt toe aan de calculatie',
                                ),
                                value: _inclusiefMaterialen,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: _saving
                                    ? null
                                    : (bool? value) {
                                        setState(() {
                                          _inclusiefMaterialen = value ?? false;
                                        });
                                      },
                              ),
                              if (_contractType == 'eenmalig') ...[
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.calendar_today,
                                    color: Colors.blue,
                                  ),
                                  title: const Text('Gewenste uitvoerdatum'),
                                  subtitle: Text(
                                    geselecteerdeUitvoerDatum != null
                                        ? '${geselecteerdeUitvoerDatum!.day}-'
                                              '${geselecteerdeUitvoerDatum!.month}-'
                                              '${geselecteerdeUitvoerDatum!.year}'
                                        : 'Kies een datum',
                                  ),
                                  trailing: const TextButton(
                                    onPressed: null,
                                    child: Text('Kiezen'),
                                  ),
                                  onTap: _saving
                                      ? null
                                      : () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate:
                                                geselecteerdeUitvoerDatum ??
                                                DateTime.now(),
                                            firstDate: DateTime.now(),
                                            lastDate: DateTime.now().add(
                                              const Duration(days: 365 * 2),
                                            ),
                                          );
                                          if (picked != null) {
                                            setState(
                                              () => geselecteerdeUitvoerDatum =
                                                  picked,
                                            );
                                          }
                                        },
                                ),
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: const Text(
                                    'Datum is indicatief (Afhankelijk van planning/overleg)',
                                  ),
                                  value: isDatumIndicatief,
                                  onChanged: _saving
                                      ? null
                                      : (val) => setState(
                                          () => isDatumIndicatief = val ?? true,
                                        ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (_contractType != 'eenmalig') ...[
                                const SizedBox(height: 12),
                                pickerField(
                                  label: 'Startdatum *',
                                  value: _fmtDateHuman(_contractStartDatum),
                                  icon: Icons.calendar_today_rounded,
                                  onTap: () => _pickDate(
                                    initial: _contractStartDatum,
                                    helpText: 'Selecteer startdatum',
                                    onPicked: (d) => _contractStartDatum = d,
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Startdatum is verplicht'
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Looptijd *',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _looptijdOpties
                                      .map(
                                        (o) => ChoiceChip(
                                          label: Text(
                                            o.label,
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          selected: _looptijd == o.value,
                                          onSelected: _saving
                                              ? null
                                              : (_) => setState(() {
                                                  _looptijd = o.value;
                                                  if (_looptijd != 'anders') {
                                                    _contractEindDatumHandmatig =
                                                        null;
                                                  }
                                                }),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                          ),
                                          side: BorderSide(
                                            color: cs.onSurface.withValues(
                                              alpha: 0.16,
                                            ),
                                          ),
                                          selectedColor: cs.primary.withValues(
                                            alpha: 0.14,
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 230),
                                  curve: Curves.easeInOut,
                                  child: _looptijd != 'anders'
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                            top: 10,
                                          ),
                                          child: Text(
                                            'Einddatum contract (automatisch): ${_fmtDateHuman(contractEindPreview)}',
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w700,
                                              color: cs.onSurface.withValues(
                                                alpha: 0.70,
                                              ),
                                            ),
                                          ),
                                        )
                                      : Column(
                                          children: [
                                            const SizedBox(height: 12),
                                            pickerField(
                                              label: 'Einddatum contract *',
                                              value: _fmtDateHuman(
                                                _contractEindDatumHandmatig,
                                              ),
                                              icon:
                                                  Icons.calendar_today_rounded,
                                              onTap: () => _pickDate(
                                                initial:
                                                    _contractEindDatumHandmatig,
                                                helpText:
                                                    'Selecteer einddatum contract',
                                                onPicked: (d) =>
                                                    _contractEindDatumHandmatig =
                                                        d,
                                              ),
                                              validator: (v) {
                                                if (_looptijd != 'anders') {
                                                  return null;
                                                }
                                                if (v == null ||
                                                    v.trim().isEmpty) {
                                                  return 'Einddatum is verplicht';
                                                }
                                                return null;
                                              },
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                              if (_contractType != 'eenmalig' &&
                                  _contractType != 'incidenteel') ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Weekdagen *',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                weekdayWrap(
                                  selected: _reguliereWeekdagen,
                                  onToggle: (day, enabled) {
                                    _toggleWeekdag(day);
                                    setState(() {
                                      // Optioneel: Sorteer de weekdagen chronologisch voor een strakke weergave in de database/PDF
                                      final volgorde = <String>[
                                        'maandag',
                                        'dinsdag',
                                        'woensdag',
                                        'donderdag',
                                        'vrijdag',
                                        'zaterdag',
                                        'zondag',
                                      ];
                                      final sorted =
                                          _reguliereWeekdagen.toList()..sort(
                                            (a, b) => volgorde
                                                .indexOf(a)
                                                .compareTo(volgorde.indexOf(b)),
                                          );
                                      _reguliereWeekdagen
                                        ..clear()
                                        ..addAll(sorted);
                                    });
                                  },
                                ),
                              ],
                              const SizedBox(height: 12),
                              twoCol(
                                left: pickerField(
                                  label: 'Begin tijd *',
                                  value: _fmtTimeHuman(_tijdslotStart),
                                  icon: Icons.schedule_rounded,
                                  onTap: () => _pickTime(
                                    initial: _tijdslotStart,
                                    onPicked: (t) => _tijdslotStart = t,
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Begin tijd is verplicht'
                                      : null,
                                ),
                                right: pickerField(
                                  label: 'Eindtijd *',
                                  value: _fmtTimeHuman(_tijdslotEind),
                                  icon: Icons.schedule_rounded,
                                  onTap: () => _pickTime(
                                    initial: _tijdslotEind,
                                    onPicked: (t) => _tijdslotEind = t,
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Eindtijd is verplicht'
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Section 4 - Afwijkende periode
                        sectionCard(
                          title: '4. Afwijkende periode',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwitchListTile.adaptive(
                                value: _heeftAfwijkendePeriode,
                                onChanged: _saving
                                    ? null
                                    : (v) => setState(() {
                                        _heeftAfwijkendePeriode = v;
                                        if (!v) {
                                          _afwijkendePeriodeStart = null;
                                          _afwijkendePeriodeEind = null;
                                          _afwijkendeWeekdagen.clear();
                                        }
                                      }),
                                title: Text(
                                  'Afwijkende periode?',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 230),
                                curve: Curves.easeInOut,
                                child: !_heeftAfwijkendePeriode
                                    ? const SizedBox.shrink()
                                    : Column(
                                        children: [
                                          const SizedBox(height: 8),
                                          twoCol(
                                            left: pickerField(
                                              label: 'Start seizoen *',
                                              value: _fmtDateHuman(
                                                _afwijkendePeriodeStart,
                                              ),
                                              icon:
                                                  Icons.calendar_month_rounded,
                                              onTap: () => _pickDate(
                                                initial:
                                                    _afwijkendePeriodeStart,
                                                helpText:
                                                    'Selecteer start seizoen',
                                                onPicked: (d) =>
                                                    _afwijkendePeriodeStart = d,
                                              ),
                                              validator: (v) {
                                                if (!_heeftAfwijkendePeriode) {
                                                  return null;
                                                }
                                                if (v == null ||
                                                    v.trim().isEmpty) {
                                                  return 'Start seizoen is verplicht';
                                                }
                                                return null;
                                              },
                                            ),
                                            right: pickerField(
                                              label: 'Eind seizoen *',
                                              value: _fmtDateHuman(
                                                _afwijkendePeriodeEind,
                                              ),
                                              icon:
                                                  Icons.calendar_month_rounded,
                                              onTap: () => _pickDate(
                                                initial: _afwijkendePeriodeEind,
                                                helpText:
                                                    'Selecteer eind seizoen',
                                                onPicked: (d) =>
                                                    _afwijkendePeriodeEind = d,
                                              ),
                                              validator: (v) {
                                                if (!_heeftAfwijkendePeriode) {
                                                  return null;
                                                }
                                                if (v == null ||
                                                    v.trim().isEmpty) {
                                                  return 'Eind seizoen is verplicht';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Afwijkende weekdagen *',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          weekdayWrap(
                                            selected: _afwijkendeWeekdagen,
                                            onToggle: (day, enabled) {
                                              setState(() {
                                                if (enabled) {
                                                  _afwijkendeWeekdagen.add(day);
                                                } else {
                                                  _afwijkendeWeekdagen.remove(
                                                    day,
                                                  );
                                                }
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 20,
                              ),
                            ),
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.arrow_forward_rounded),
                            label: Text(
                              'Opslaan & Door naar Ruimtes',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _Option {
  const _Option(this.value, this.label);
  final String value;
  final String label;
}
