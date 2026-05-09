import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';

typedef _CatOption = ({String value, String label});

const List<_CatOption> _ticketCategories = [
  (value: 'schade', label: 'Schade aan pand'),
  (value: 'gevaarlijke_situatie', label: 'Gevaarlijke situatie'),
  (value: 'extra_vervuiling', label: 'Extra vervuiling'),
  (value: 'materieel_defect', label: 'Materieel / Stofzuiger defect'),
  (value: 'klacht', label: 'Klacht'),
  (value: 'overig', label: 'Overig'),
];

String? _pickStr(Map<String, dynamic> row, List<String> keys) {
  for (final k in keys) {
    final v = row[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}

String _catLabel(String? raw) {
  final v = raw?.trim() ?? '';
  for (final o in _ticketCategories) {
    if (o.value == v) return o.label;
  }
  if (v.isEmpty) return '—';
  return v.replaceAll('_', ' ');
}

/// Operator: nieuwe meldingen indienen en eigen historie.
class OperatorMeldingenScreen extends StatefulWidget {
  const OperatorMeldingenScreen({super.key});

  @override
  State<OperatorMeldingenScreen> createState() =>
      _OperatorMeldingenScreenState();
}

class _OperatorMeldingenScreenState extends State<OperatorMeldingenScreen>
    with SingleTickerProviderStateMixin {
  static const Color _navy = Color(0xFF0F172A);
  static const Color _accent = Color(0xFF2563EB);

  late TabController _tabController;

  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _history = [];
  bool _loadingLocs = true;
  bool _loadingHist = false;
  Object? _locsErr;
  Object? _histErr;
  bool _submitting = false;

  String? _selectedBedrijfId;
  String _selectedCategory = _ticketCategories.first.value;
  final TextEditingController _onderwerpCtl = TextEditingController();
  final TextEditingController _toelichtingCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabTick);
    _loadLocations();
    _loadHistory();
  }

  void _onTabTick() {
    if (!mounted) return;
    if (_tabController.index == 1 && !_tabController.indexIsChanging) {
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabTick);
    _tabController.dispose();
    _onderwerpCtl.dispose();
    _toelichtingCtl.dispose();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    setState(() {
      _loadingLocs = true;
      _locsErr = null;
    });
    try {
      final raw = await AppSupabase.client
          .from('app_operator_huidige_locaties')
          .select();
      final list = (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _locations = list;
        _loadingLocs = false;
        if (_selectedBedrijfId == null && list.isNotEmpty) {
          final id = _bedrijfIdFromRow(list.first);
          _selectedBedrijfId = id;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locsErr = e;
        _loadingLocs = false;
      });
    }
  }

  String? _bedrijfIdFromRow(Map<String, dynamic> row) {
    return _pickStr(row, ['bedrijf_id', 'company_id', 'klant_id', 'client_id']);
  }

  String _locationLabel(Map<String, dynamic> row) {
    final naam = _pickStr(row, [
          'bedrijfsnaam',
          'bedrijf_naam',
          'klant_naam',
          'locatie_naam',
          'naam',
        ]) ??
        'Locatie';
    final sub = _pickStr(row, ['vestiging', 'adres', 'plaats']);
    if (sub != null) return '$naam · $sub';
    return naam;
  }

  Future<void> _loadHistory() async {
    final uid = AppSupabase.client.auth.currentUser?.id;
    if (uid == null) return;

    setState(() {
      _loadingHist = true;
      _histErr = null;
    });
    try {
      List<Map<String, dynamic>> list;

      Future<List<Map<String, dynamic>>> run(
        String col,
        String orderCol,
      ) async {
        final raw = await AppSupabase.client
            .from('tickets')
            .select()
            .eq(col, uid)
            .order(orderCol, ascending: false);
        return (raw as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      try {
        list = await run('gemeld_door_id', 'aangemaakt_op');
      } catch (_) {
        try {
          list = await run('gemeld_door_id', 'created_at');
        } catch (_) {
          list = await run('ingediend_door_id', 'created_at');
        }
      }

      if (!mounted) return;
      setState(() {
        _history = list;
        _loadingHist = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _histErr = e;
        _loadingHist = false;
      });
    }
  }

  Future<void> _submitTicket() async {
    final uid = AppSupabase.client.auth.currentUser?.id;
    if (uid == null) {
      _snack('U bent niet ingelogd.', ok: false);
      return;
    }
    final bid = _selectedBedrijfId;
    if (bid == null || bid.isEmpty) {
      _snack('Selecteer een locatie (klant).', ok: false);
      return;
    }
    final onderwerp = _onderwerpCtl.text.trim();
    if (onderwerp.isEmpty) {
      _snack('Vul een onderwerp in.', ok: false);
      return;
    }
    final text = _toelichtingCtl.text.trim();

    setState(() => _submitting = true);
    try {
      final payload = <String, dynamic>{
        'bedrijf_id': bid,
        'gemeld_door_id': uid,
        'categorie': _selectedCategory,
        'onderwerp': onderwerp,
        'omschrijving': text,
        'prioriteit': 'normaal',
        'status': 'open',
        'bron': 'operator',
      };

      await AppSupabase.client.from('tickets').insert(payload);

      if (!mounted) return;
      _onderwerpCtl.clear();
      _toelichtingCtl.clear();
      setState(() => _submitting = false);
      _snack('Melding verstuurd.', ok: true);
      await _loadHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('Versturen mislukt: $e', ok: false);
    }
  }

  void _snack(String msg, {required bool ok}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            ok ? Colors.green.shade700 : Colors.deepOrange.shade800,
        content: Text(msg, style: GoogleFonts.lato(fontWeight: FontWeight.w600)),
      ),
    );
  }

  DateTime? _ticketDate(Map<String, dynamic> row) {
    for (final k in ['aangemaakt_op', 'created_at', 'ingediend_op']) {
      final v = row[k];
      if (v == null) continue;
      final d = DateTime.tryParse(v.toString());
      if (d != null) return d;
    }
    return null;
  }

  bool _isResolved(Map<String, dynamic> row) {
    final s = (_pickStr(row, ['status']) ?? 'open').toLowerCase();
    if (s.contains('oplost') || s.contains('geslot')) return true;
    return false;
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
        title: Text(
          'Mijn Meldingen',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            color: Theme.of(context).textTheme.titleLarge?.color,
            fontSize: 22,
            letterSpacing: -0.4,
          ),
        ),
        iconTheme: Theme.of(context).appBarTheme.iconTheme,
        bottom: TabBar(
          controller: _tabController,
          labelColor: _accent,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: _accent,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
          unselectedLabelStyle: GoogleFonts.lato(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'Nieuwe Melding'),
            Tab(text: 'Mijn Historie'),
          ],
        ),
      ),
      body: SelectionArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildNewForm(),
            _buildHistory(),
          ],
        ),
      ),
    );
  }

  Widget _cardShell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  InputDecoration _decor(String hint, {String? label}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
      labelStyle: GoogleFonts.lato(fontWeight: FontWeight.w700),
      hintStyle: GoogleFonts.lato(color: Colors.grey.shade500),
    );
  }

  Widget _buildNewForm() {
    if (_loadingLocs) {
      return const Center(child: CupertinoActivityIndicator(radius: 16));
    }
    if (_locsErr != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Locaties laden mislukt.\n$_locsErr',
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w600,
              color: Colors.red.shade800,
            ),
          ),
        ),
      );
    }

    if (_locations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Er zijn nu geen locaties gekoppeld aan uw planning.',
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
              height: 1.45,
            ),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          'Dien een melding in bij de locatie waar u nu werkt.',
          style: GoogleFonts.lato(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        _cardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Selecteer Locatie (Klant)',
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _validSelectedId(),
                decoration: _decor('Kies locatie', label: null),
                borderRadius: BorderRadius.circular(16),
                items: _locations.map((row) {
                  final id = _bedrijfIdFromRow(row);
                  if (id == null) return null;
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(
                      _locationLabel(row),
                      style: GoogleFonts.lato(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).whereType<DropdownMenuItem<String>>().toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedBedrijfId = v);
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Categorie',
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: _decor('Categorie', label: null),
                borderRadius: BorderRadius.circular(16),
                items: _ticketCategories
                    .map(
                      (o) => DropdownMenuItem<String>(
                        value: o.value,
                        child: Text(
                          o.label,
                          style: GoogleFonts.lato(fontWeight: FontWeight.w600),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedCategory = v);
                },
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _onderwerpCtl,
                textInputAction: TextInputAction.next,
                decoration: _decor('Korte omschrijving', label: 'Onderwerp'),
                style: GoogleFonts.lato(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _toelichtingCtl,
                maxLines: 4,
                decoration: _decor(
                  'Wat is er aan de hand?',
                  label: 'Uitgebreide toelichting',
                ),
                style: GoogleFonts.lato(fontWeight: FontWeight.w600, height: 1.35),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _submitting ? null : _submitTicket,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Melding Versturen',
                          style: GoogleFonts.lato(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: mobileNavBuffer),
      ],
    );
  }

  String? _validSelectedId() {
    if (_selectedBedrijfId == null) return null;
    final ids = _locations
        .map(_bedrijfIdFromRow)
        .whereType<String>()
        .toSet();
    if (ids.contains(_selectedBedrijfId)) return _selectedBedrijfId;
    return ids.isEmpty ? null : ids.first;
  }

  Widget _buildHistory() {
    if (_loadingHist && _history.isEmpty) {
      return const Center(child: CupertinoActivityIndicator(radius: 16));
    }
    if (_histErr != null && _history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Historie laden mislukt.\n$_histErr',
                textAlign: TextAlign.center,
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade800,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadHistory,
                child: const Text('Opnieuw proberen'),
              ),
            ],
          ),
        ),
      );
    }

    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'U heeft nog geen meldingen ingediend.',
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        ..._history.map(_historyCard),
        const SizedBox(height: mobileNavBuffer),
      ],
    );
  }

  Widget _historyCard(Map<String, dynamic> row) {
    final resolved = _isResolved(row);
    final onderwerp =
        _pickStr(row, ['onderwerp', 'title', 'subject']) ?? '—';
    final catRaw = _pickStr(row, ['categorie', 'category']);
    final catLabel = _catLabel(catRaw);
    final dt = _ticketDate(row);
    final dateStr = dt == null
        ? '—'
        : '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    onderwerp,
                    style: GoogleFonts.lato(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: _navy,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _statusChip(resolved),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              catLabel,
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              dateStr,
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(bool resolved) {
    final bg = resolved ? Colors.green.shade50 : Colors.orange.shade50;
    final fg = resolved ? Colors.green.shade800 : Colors.orange.shade900;
    final label = resolved ? 'Opgelost' : 'Open';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.lato(
          fontWeight: FontWeight.w900,
          fontSize: 11,
          color: fg,
        ),
      ),
    );
  }
}
