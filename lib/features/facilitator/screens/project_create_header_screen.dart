import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
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
  Map<String, dynamic>? _selected;
  String _contractType = 'flexibel';
  String _periodiek = '1_keer_per_jaar';
  String? _werkRegio;
  DateTime? _start;
  DateTime? _eind;
  TimeOfDay? _tStart;
  TimeOfDay? _tEnd;
  final Set<String> _days = {};
  bool _loadingKlanten = true;
  bool _saving = false;

  static const _contractOpts = [
    _Opt('vast', 'Vast'),
    _Opt('flexibel', 'Flexibel'),
    _Opt('eenmalig', 'Eenmalig'),
  ];
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

  Future<void> _loadKlanten() async {
    final u = Supabase.instance.client.auth.currentUser;
    if (u == null) {
      if (mounted) setState(() => _loadingKlanten = false);
      return;
    }
    if (!mounted) return;
    final up = context.read<UserProvider>();
    final isFac = up.roleString == 'facilitator';
    setState(() => _loadingKlanten = true);
    try {
      var q = AppSupabase.client
          .from('bedrijven')
          .select()
          .eq('is_klant', true);
      if (isFac) {
        q = q.eq('betrokken_facilitator_id', u.id);
      }
      final res = await q.order('bedrijfsnaam', ascending: true);
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
    if (_selected == null) {
      _toast('Kies een klant.', err: true);
      return;
    }
    if (_start == null || _eind == null) {
      _toast('Kies start- en einddatum contract.', err: true);
      return;
    }
    if (_eind!.isBefore(_start!)) {
      _toast('Eind moet na start liggen.', err: true);
      return;
    }
    if (_tStart == null || _tEnd == null) {
      _toast('Kies start- en eindtijd.', err: true);
      return;
    }
    if (_days.isEmpty) {
      _toast('Kies minimaal 1 vaste weekdag.', err: true);
      return;
    }
    if (_werkRegio == null) {
      _toast('Kies een werkregio.', err: true);
      return;
    }

    setState(() => _saving = true);
    final b = _selected!;
    final uid = AppSupabase.client.auth.currentUser?.id;
    final straat = _text(b['adres'] ?? b['adres_straat']);
    final postcode = _text(b['adres_postcode'] ?? b['postcode']);
    final stad = _text(b['adres_stad'] ?? b['stad']);
    final kvk = _text(b['kvk_nummer'] ?? b['kvk']);

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
      'contract_type': _contractType.toLowerCase(),
      'periodieke_frequentie': _periodiek,
      'contract_startdatum': _fmtDateDb(_start!),
      'contract_einddatum': _fmtDateDb(_eind!),
      'reguliere_weekdagen': _days.map((d) => d.toLowerCase()).toList(),
      'tijdslot_start': _fmtTimeDb(_tStart!),
      'tijdslot_eind': _fmtTimeDb(_tEnd!),
      'is_direct_project': true,
      'status': 'concept',
    };
    if (uid != null) {
      payload['aangemaakt_door_id'] = uid;
    }

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

  Iterable<Map<String, dynamic>> _options(String v) {
    final q = v.trim().toLowerCase();
    if (q.isEmpty) return _klanten.take(20);
    return _klanten
        .where((k) => _text(k['bedrijfsnaam']).toLowerCase().contains(q))
        .take(20);
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
      body: _loadingKlanten
          ? const Center(child: CupertinoActivityIndicator(radius: 14))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  _card(
                    title: 'Klant',
                    child: Autocomplete<Map<String, dynamic>>(
                      displayStringForOption: (m) => _text(m['bedrijfsnaam']),
                      optionsBuilder: (v) => _options(v.text).toList(),
                      onSelected: (m) => setState(() => _selected = m),
                      fieldViewBuilder: (ctx, c, f, s) {
                        return TextFormField(
                          controller: c,
                          focusNode: f,
                          onFieldSubmitted: (_) => s(),
                          style: GoogleFonts.lato(
                              fontWeight: FontWeight.w700, color: _navy),
                          decoration: _dec('Zoek en selecteer klant'),
                          validator: (_) =>
                              _selected == null ? 'Selecteer een klant.' : null,
                          onChanged: (_) => setState(() => _selected = null),
                        );
                      },
                      optionsViewBuilder: (c, onSel, it) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 6,
                            borderRadius: BorderRadius.circular(12),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxHeight: 240, maxWidth: 400),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: it.length,
                                itemBuilder: (_, i) {
                                  final m = it.elementAt(i);
                                  return ListTile(
                                    title: Text(
                                      _text(m['bedrijfsnaam']),
                                      style: GoogleFonts.lato(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    onTap: () => onSel(m),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_selected != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Geselecteerd: ${_text(_selected!['bedrijfsnaam'])}',
                        style: GoogleFonts.lato(
                            fontSize: 12, color: _muted, fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 16),
                  _card(
                    title: 'Contract & planning',
                    child: Column(
                      children: [
                        _dropdown(
                          label: 'Contracttype',
                          value: _contractType,
                          items: _contractOpts
                              .map((e) => DropdownMenuItem(
                                    value: e.id,
                                    child: Text(e.label,
                                        style: GoogleFonts.lato(
                                            fontWeight: FontWeight.w600)),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _contractType = v ?? 'flexibel'),
                        ),
                        const SizedBox(height: 12),
                        _dropdown(
                          label: 'Periodieke frequentie',
                          value: _periodiek,
                          items: _freqOpts
                              .map((e) => DropdownMenuItem(
                                    value: e.id,
                                    child: Text(e.label,
                                        style: GoogleFonts.lato(
                                            fontWeight: FontWeight.w600)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(
                              () => _periodiek = v ?? '1_keer_per_jaar'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          // ignore: deprecated_member_use
                          value: _werkRegio,
                          decoration: _dec('Werk regio *'),
                          items: _regioOpts
                              .map((e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e,
                                        style: GoogleFonts.lato(
                                            fontWeight: FontWeight.w600)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _werkRegio = v),
                          validator: (v) => v == null || v.isEmpty
                              ? 'Verplicht'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                                child: _dateTile('Start contract', _start,
                                    (d) => setState(() => _start = d))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _dateTile('Einde contract', _eind,
                                    (d) => setState(() => _eind = d))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                                child: _timeTile('Starttijd', _tStart,
                                    (t) => setState(() => _tStart = t))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _timeTile('Eindtijd', _tEnd,
                                    (t) => setState(() => _tEnd = t))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Vaste weekdagen',
                            style: GoogleFonts.lato(
                                fontWeight: FontWeight.w800, color: _navy),
                          ),
                        ),
                        const SizedBox(height: 8),
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
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_radius),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Volgende: ruimtes & diensten',
                            style: GoogleFonts.lato(
                                fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                  ),
                ],
              ),
            ),
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
