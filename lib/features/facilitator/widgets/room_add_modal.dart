import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoomAddModal extends StatefulWidget {
  const RoomAddModal({
    super.key,
    required this.offerteId,
    required this.onSaved,
  });

  final String offerteId;
  final VoidCallback onSaved;

  @override
  State<RoomAddModal> createState() => _RoomAddModalState();
}

class _RoomAddModalState extends State<RoomAddModal> {
  final TextEditingController _naamController = TextEditingController();
  String? _geselecteerdeCategorieUi;
  String _geselecteerdeGrootte = 'A';
  int _aantal = 1;
  List<Map<String, dynamic>> _beschikbareTaken = [];
  final List<String> _geselecteerdeTakenIds = [];
  bool _isLoadingTaken = false;
  bool _isSaving = false;

  final Map<String, String> _categorieMapping = const {
    'Sanitair': 'Sanitair',
    'Keukens & Pantrys': 'Keukens',
    'Kamers & Kantoren': 'Kamers',
    'Zalen': 'Zalen',
    'Lokalen': 'Lokalen',
    'Hallen en Gangen': 'Hallen en gangen',
    'Trappenhuizen': 'Trappenhuizen',
    'Kasten & Opslag': 'Opslag',
    'Terreinonderhoud': 'Terrein onderhoud',
    'Glasbewassing': 'Glasbewassing',
  };

  @override
  void dispose() {
    _naamController.dispose();
    super.dispose();
  }

  Future<void> _fetchTakenVoorCategorie(String dbCategorie) async {
    setState(() => _isLoadingTaken = true);
    try {
      final response = await Supabase.instance.client
          .from('moeder_bestek')
          .select()
          .ilike('ruimte', '%$dbCategorie%')
          .order('volledige_naam');
        
      setState(() {
        _beschikbareTaken = List<Map<String, dynamic>>.from(response);
        _geselecteerdeTakenIds.clear(); // Always clear selections when changing category
        _isLoadingTaken = false;
      });
    } catch (e) {
      debugPrint('Error fetching tasks: $e');
      setState(() => _isLoadingTaken = false);
    }
  }

  Future<void> _save() async {
    final naam = _naamController.text.trim();
    if (naam.isEmpty) {
      _showError('Naam van de ruimte is verplicht.');
      return;
    }
    if (_geselecteerdeCategorieUi == null) {
      _showError('Selecteer een categorie.');
      return;
    }
    if (_geselecteerdeTakenIds.isEmpty) {
      _showError('Selecteer minimaal 1 dienst.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('offerte_ruimtes')
          .insert({
            'offerte_id': widget.offerteId,
            'naam_in_pand': naam,
            'ruimte_categorie': _categorieMapping[_geselecteerdeCategorieUi],
            'grootte_label': _geselecteerdeGrootte,
            'aantal_identiek': _aantal,
          })
          .select('id')
          .single();

      final ruimteId = response['id'];
      if (ruimteId == null) {
        throw StateError('Ruimte is aangemaakt zonder id.');
      }

      final inserts = _geselecteerdeTakenIds
          .map(
            (taakId) => {
              'offerte_ruimte_id': ruimteId,
              'taak_id': taakId,
            },
          )
          .toList(growable: false);
      await client.from('offerte_ruimte_diensten').insert(inserts);

      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _showError('Ruimte toevoegen mislukt: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
    );
  }

  InputDecoration _deco(BuildContext context, String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF191923)
            : Colors.grey.shade100,
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
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF0F0E18) : Colors.white;

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 14, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Nieuwe Ruimte Toevoegen',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sluiten',
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _naamController,
                          enabled: !_isSaving,
                          decoration: _deco(context, 'Naam van de ruimte'),
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < 620) {
                              return Column(
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: _geselecteerdeCategorieUi,
                                    decoration: _deco(context, 'Categorie'),
                                    items: _categorieMapping.keys
                                        .map(
                                          (label) =>
                                              DropdownMenuItem(value: label, child: Text(label)),
                                        )
                                        .toList(growable: false),
                                    onChanged: _isSaving
                                        ? null
                                        : (newValue) async {
                                            if (newValue == null) return;
                                            setState(() => _geselecteerdeCategorieUi = newValue);
                                            await _fetchTakenVoorCategorie(_categorieMapping[newValue]!);
                                          },
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    initialValue: _geselecteerdeGrootte,
                                    decoration: _deco(context, 'Grootte'),
                                    items: const [
                                      DropdownMenuItem(value: 'A', child: Text('Klein (A)')),
                                      DropdownMenuItem(value: 'B', child: Text('Middelgroot (B)')),
                                      DropdownMenuItem(value: 'C', child: Text('Groot (C)')),
                                    ],
                                    onChanged: _isSaving
                                        ? null
                                        : (v) => setState(() => _geselecteerdeGrootte = v ?? 'A'),
                                  ),
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _geselecteerdeCategorieUi,
                                    decoration: _deco(context, 'Categorie'),
                                    items: _categorieMapping.keys
                                        .map(
                                          (label) =>
                                              DropdownMenuItem(value: label, child: Text(label)),
                                        )
                                        .toList(growable: false),
                                    onChanged: _isSaving
                                        ? null
                                        : (newValue) async {
                                            if (newValue == null) return;
                                            setState(() => _geselecteerdeCategorieUi = newValue);
                                            await _fetchTakenVoorCategorie(_categorieMapping[newValue]!);
                                          },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _geselecteerdeGrootte,
                                    decoration: _deco(context, 'Grootte'),
                                    items: const [
                                      DropdownMenuItem(value: 'A', child: Text('Klein (A)')),
                                      DropdownMenuItem(value: 'B', child: Text('Middelgroot (B)')),
                                      DropdownMenuItem(value: 'C', child: Text('Groot (C)')),
                                    ],
                                    onChanged: _isSaving
                                        ? null
                                        : (v) => setState(() => _geselecteerdeGrootte = v ?? 'A'),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF151525) : const Color(0xFFF8F8FA),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                            ),
                            child: _geselecteerdeCategorieUi == null
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Text(
                                        'Selecteer een categorie om de beschikbare diensten te laden.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface.withValues(alpha: 0.60),
                                        ),
                                      ),
                                    ),
                                  )
                                : _isLoadingTaken
                                    ? const Center(child: CircularProgressIndicator())
                                    : _beschikbareTaken.isEmpty
                                        ? Center(
                                            child: Text(
                                              'Geen diensten gevonden voor deze categorie.',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w600,
                                                color: cs.onSurface.withValues(alpha: 0.60),
                                              ),
                                            ),
                                          )
                                        : ListView.builder(
                                            padding: const EdgeInsets.all(10),
                                            itemCount: _beschikbareTaken.length,
                                            itemBuilder: (context, index) {
                                              final taak = _beschikbareTaken[index];
                                              final checked = _geselecteerdeTakenIds.contains(
                                                taak['id'].toString(),
                                              );

                                              return CheckboxListTile(
                                                value: checked,
                                                dense: true,
                                                controlAffinity: ListTileControlAffinity.leading,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(14),
                                                ),
                                                title: Text(
                                                  taak['volledige_naam'].toString(),
                                                  style: GoogleFonts.inter(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  taak['eenheid'].toString(),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: cs.onSurface.withValues(alpha: 0.60),
                                                  ),
                                                ),
                                                onChanged: _isSaving
                                                    ? null
                                                    : (value) {
                                                        setState(() {
                                                          if (value == true) {
                                                            if (!_geselecteerdeTakenIds.contains(
                                                              taak['id'].toString(),
                                                            )) {
                                                              _geselecteerdeTakenIds.add(
                                                                taak['id'].toString(),
                                                              );
                                                            }
                                                          } else {
                                                            _geselecteerdeTakenIds.remove(
                                                              taak['id'].toString(),
                                                            );
                                                          }
                                                        });
                                                      },
                                              );
                                            },
                                          ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: 0.08))),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            'Aantal identiek',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _isSaving
                                ? null
                                : () => setState(() {
                                      if (_aantal > 1) _aantal -= 1;
                                    }),
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                          ),
                          Text(
                            '$_aantal',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18),
                          ),
                          IconButton(
                            onPressed: _isSaving ? null : () => setState(() => _aantal += 1),
                            icon: const Icon(Icons.add_circle_outline_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isSaving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Ruimte Toevoegen',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
