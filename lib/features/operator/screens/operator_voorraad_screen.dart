import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';

String? _pickStr(Map<String, dynamic> row, List<String> keys) {
  for (final k in keys) {
    final v = row[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? 0;
}

/// Operator: voorraad tellen per klantlocatie.
class OperatorVoorraadScreen extends StatefulWidget {
  const OperatorVoorraadScreen({super.key});

  @override
  State<OperatorVoorraadScreen> createState() => _OperatorVoorraadScreenState();
}

class _OperatorVoorraadScreenState extends State<OperatorVoorraadScreen> {
  static const Color _bg = Color(0xFFF5F5F7);
  static const Color _navy = Color(0xFF0F172A);
  static const Color _accent = Color(0xFF2563EB);

  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _items = [];
  final Map<String, int> _counts = {};

  bool _loadingLocs = true;
  bool _loadingItems = false;
  bool _saving = false;

  Object? _locsErr;
  Object? _itemsErr;

  String? _selectedBedrijfId;

  @override
  void initState() {
    super.initState();
    _loadLocations();
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

      String? sel = _selectedBedrijfId;
      if (sel == null && list.isNotEmpty) {
        sel = _bedrijfIdFromRow(list.first);
      }

      setState(() {
        _locations = list;
        _loadingLocs = false;
        _selectedBedrijfId = sel;
      });

      if (sel != null) {
        await _loadItems(sel);
      } else {
        if (!mounted) return;
        setState(() {
          _items = [];
          _counts.clear();
        });
      }
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

  String? _voorraadRowId(Map<String, dynamic> row) {
    return _pickStr(row, ['voorraad_id', 'locatie_voorraad_id', 'id']);
  }

  Future<void> _loadItems(String bedrijfId) async {
    setState(() {
      _loadingItems = true;
      _itemsErr = null;
    });
    try {
      final raw = await AppSupabase.client
          .from('app_operator_voorraad_tellen')
          .select()
          .eq('bedrijf_id', bedrijfId);

      final list = (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;

      final next = <String, int>{};
      for (final row in list) {
        final id = _voorraadRowId(row);
        if (id == null) continue;
        next[id] = _asInt(row['huidig_aantal']);
      }

      setState(() {
        _items = list;
        _counts
          ..clear()
          ..addAll(next);
        _loadingItems = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _itemsErr = e;
        _loadingItems = false;
      });
    }
  }

  void _onLocationChanged(String? bedrijfId) {
    if (bedrijfId == null) return;
    setState(() => _selectedBedrijfId = bedrijfId);
    _loadItems(bedrijfId);
  }

  void _delta(String id, int d) {
    final cur = _counts[id] ?? 0;
    final n = (cur + d).clamp(0, 999999);
    setState(() => _counts[id] = n);
  }

  Future<void> _saveAll() async {
    if (_saving) return;
    if (_items.isEmpty) return;

    setState(() => _saving = true);
    try {
      for (final row in _items) {
        final id = _voorraadRowId(row);
        if (id == null) continue;
        final v = _counts[id] ?? 0;
        await AppSupabase.client.from('locatie_voorraad').update({
          'huidig_aantal': v,
        }).eq('id', id);
      }

      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(
            'Voorraad succesvol bijgewerkt!',
            style: GoogleFonts.lato(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.shade800,
          content: Text(
            'Opslaan mislukt: $e',
            style: GoogleFonts.lato(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
  }

  String? _validLocationValue() {
    final ids = _locations
        .map(_bedrijfIdFromRow)
        .whereType<String>()
        .toList();
    if (ids.isEmpty) return null;
    final sel = _selectedBedrijfId;
    if (sel != null && ids.contains(sel)) return sel;
    return ids.first;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _bg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _navy),
        title: Text(
          'Voorraad Tellen',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            color: _navy,
            fontSize: 22,
            letterSpacing: -0.4,
          ),
        ),
      ),
      body: SelectionArea(
        child: Column(
          children: [
            Expanded(child: _body()),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + bottomInset),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: (_saving ||
                            _items.isEmpty ||
                            _validLocationValue() == null)
                        ? null
                        : _saveAll,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Voorraadtelling Opslaan',
                            style: GoogleFonts.lato(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loadingLocs) {
      return const Center(child: CupertinoActivityIndicator(radius: 16));
    }
    if (_locsErr != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Kon locaties niet laden.\n$_locsErr',
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
            'Geen locaties gevonden voor uw account.',
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        Text(
          'Selecteer uw huidige locatie',
          style: GoogleFonts.lato(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButtonFormField<String>(
              initialValue: _validLocationValue(),
              isExpanded: true,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              borderRadius: BorderRadius.circular(20),
              icon: Icon(Icons.expand_more_rounded, color: _accent),
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: _navy,
              ),
              items: _locations.map((row) {
                final id = _bedrijfIdFromRow(row);
                if (id == null) return null;
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(
                    _locationLabel(row),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).whereType<DropdownMenuItem<String>>().toList(),
              onChanged: _onLocationChanged,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _inventoryBlock(),
      ],
    );
  }

  Widget _inventoryBlock() {
    if (_loadingItems) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CupertinoActivityIndicator(radius: 16)),
      );
    }

    if (_itemsErr != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Voorraad laden mislukt.\n$_itemsErr',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w600,
            color: Colors.red.shade800,
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          'Voorraadbeheer is niet geactiveerd voor deze klant.',
          textAlign: TextAlign.center,
          style: GoogleFonts.lato(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
            height: 1.45,
          ),
        ),
      );
    }

    return Column(
      children: _items.map(_itemCard).toList(),
    );
  }

  Widget _itemCard(Map<String, dynamic> row) {
    final id = _voorraadRowId(row);
    if (id == null) return const SizedBox.shrink();

    final naam =
        _pickStr(row, ['artikel_naam', 'product_naam', 'naam']) ?? 'Artikel';
    final minA = _asInt(row['minimum_aantal']);
    final eenheid = _pickStr(row, ['eenheid', 'unit']) ?? 'st';

    final cur = _counts[id] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              naam,
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: _navy,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Minimaal nodig: $minA $eenheid',
                    style: GoogleFonts.lato(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                Row(
                  children: [
                    _hitButton(
                      icon: Icons.remove_rounded,
                      onPressed: cur > 0 ? () => _delta(id, -1) : null,
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '$cur',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: _navy,
                        ),
                      ),
                    ),
                    _hitButton(
                      icon: Icons.add_rounded,
                      onPressed: () => _delta(id, 1),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hitButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: onPressed == null
          ? Colors.grey.shade200
          : const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, size: 28, color: _accent),
        ),
      ),
    );
  }
}
