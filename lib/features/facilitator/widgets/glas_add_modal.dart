import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Premium Apple-stijl dialog: naam + diensten + frequentie → [offerte_ruimtes].
class GlasAddModal {
  GlasAddModal._();

  static Future<bool?> show({
    required BuildContext context,
    required String offerteId,
    List<Map<String, dynamic>>? alleGlasDiensten,
    Map<String, dynamic>? bestaandeRegel,
    Future<void> Function()? onReloadData,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _GlasAddDialog(
        offerteId: offerteId,
        alleGlasDiensten: alleGlasDiensten,
        bestaandeRegel: bestaandeRegel,
        onReloadData: onReloadData,
      ),
    );
  }
}

class _GlasAddDialog extends StatefulWidget {
  const _GlasAddDialog({
    required this.offerteId,
    this.alleGlasDiensten,
    this.bestaandeRegel,
    this.onReloadData,
  });

  final String offerteId;
  final List<Map<String, dynamic>>? alleGlasDiensten;
  final Map<String, dynamic>? bestaandeRegel;
  final Future<void> Function()? onReloadData;

  @override
  State<_GlasAddDialog> createState() => _GlasAddDialogState();
}

class _GlasAddDialogState extends State<_GlasAddDialog> {
  final TextEditingController _naamController =
      TextEditingController(text: 'Glasbewassing');

  List<Map<String, dynamic>> _alleGlasDiensten = [];
  final List<String> _geselecteerdeDienstenIds = [];
  String _glasFrequentie = 'op_afroep';
  bool _ladenDiensten = true;
  bool _isSaving = false;

  static const _appleFill = Color(0xFFF2F2F7);

  bool get _isEditMode => widget.bestaandeRegel != null;

  static List<String> _idsUitRegel(Map<String, dynamic>? regel) {
    if (regel == null) return [];
    final raw = regel['moeder_bestek_ids'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    final legacy = regel['moeder_bestek_id']?.toString().trim() ?? '';
    if (legacy.isNotEmpty) return [legacy];
    return [];
  }

  @override
  void initState() {
    super.initState();
    final bestaand = widget.bestaandeRegel;
    if (bestaand != null) {
      _naamController.text = (bestaand['naam_in_pand'] ??
              bestaand['naam'] ??
              'Glasbewassing')
          .toString()
          .trim();
      _glasFrequentie = (bestaand['specifieke_frequentie'] ??
              bestaand['frequentie'] ??
              'op_afroep')
          .toString()
          .trim();
      _geselecteerdeDienstenIds.addAll(_idsUitRegel(bestaand));
    }
    if (widget.alleGlasDiensten != null && widget.alleGlasDiensten!.isNotEmpty) {
      _alleGlasDiensten = List<Map<String, dynamic>>.from(widget.alleGlasDiensten!);
      _ladenDiensten = false;
    } else {
      _laadGlasDiensten();
    }
  }

  @override
  void dispose() {
    _naamController.dispose();
    super.dispose();
  }

  String _dienstId(Map<String, dynamic> dienst) => dienst['id']?.toString() ?? '';

  String _dienstNaam(Map<String, dynamic> dienst) {
    final v = dienst['volledige_naam'] ?? dienst['naam'];
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? 'Dienst' : s;
  }

  Future<void> _laadGlasDiensten() async {
    setState(() => _ladenDiensten = true);
    try {
      var response = await Supabase.instance.client
          .from('moeder_bestek')
          .select('id, volledige_naam')
          .eq('is_glasbewassing', true)
          .order('volledige_naam');

      var lijst = List<Map<String, dynamic>>.from(response as List);

      if (lijst.isEmpty) {
        response = await Supabase.instance.client
            .from('moeder_bestek')
            .select('id, volledige_naam')
            .or('ruimte.ilike.%glas%,volledige_naam.ilike.%glasbewassing%')
            .order('volledige_naam');
        lijst = List<Map<String, dynamic>>.from(response as List);
      }

      if (!mounted) return;
      setState(() {
        _alleGlasDiensten = lijst;
        _ladenDiensten = false;
      });
    } catch (e) {
      debugPrint('Glas diensten laden: $e');
      if (!mounted) return;
      setState(() => _ladenDiensten = false);
    }
  }

  Future<void> _opslaan() async {
    final naam = _naamController.text.trim();
    if (naam.isEmpty) {
      _toonFout('Vul een naam in voor dit onderdeel.');
      return;
    }
    if (_geselecteerdeDienstenIds.isEmpty) {
      _toonFout('Selecteer minimaal één werkzaamheid.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final client = Supabase.instance.client;
      final takenLijst = List<String>.from(_geselecteerdeDienstenIds);

      if (_isEditMode) {
        final ruimteId = widget.bestaandeRegel!['offerte_ruimte_id']?.toString() ??
            widget.bestaandeRegel!['id']?.toString();
        if (ruimteId == null || ruimteId.isEmpty) {
          throw StateError('Ruimte-ID ontbreekt.');
        }

        await client.from('offerte_ruimtes').update({
          'naam_in_pand': naam,
          'ruimte_categorie': 'Glasbewassing',
          'specifieke_frequentie': _glasFrequentie,
          'grootte_label': 'A',
          'aantal_identiek': 1,
        }).eq('id', ruimteId);

        await client
            .from('offerte_ruimte_diensten')
            .delete()
            .eq('offerte_ruimte_id', ruimteId);

        if (takenLijst.isNotEmpty) {
          await client.rpc(
            'bulk_voeg_taken_toe',
            params: {
              'p_offerte_id': widget.offerteId,
              'p_ruimte_id': ruimteId,
              'p_taken_lijst': takenLijst,
            },
          );
        }
      } else {
        final roomRes = await client
            .from('offerte_ruimtes')
            .insert({
              'offerte_id': widget.offerteId,
              'naam_in_pand': naam,
              'ruimte_categorie': 'Glasbewassing',
              'specifieke_frequentie': _glasFrequentie,
              'glas_aantal_klein': 0,
              'glas_aantal_middel': 0,
              'glas_aantal_groot': 0,
              'grootte_label': 'A',
              'aantal_identiek': 1,
            })
            .select('id')
            .single();

        final ruimteId = roomRes['id']?.toString();
        if (ruimteId == null || ruimteId.isEmpty) {
          throw StateError('Ruimte is aangemaakt zonder id.');
        }

        if (takenLijst.isNotEmpty) {
          await client.rpc(
            'bulk_voeg_taken_toe',
            params: {
              'p_offerte_id': widget.offerteId,
              'p_ruimte_id': ruimteId,
              'p_taken_lijst': takenLijst,
            },
          );
        }
      }

      if (widget.onReloadData != null) {
        await widget.onReloadData!();
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Fout bij opslaan glasbewassing: $e');
      if (!mounted) return;
      _toonFout(
        _isEditMode ? 'Opslaan mislukt: $e' : 'Toevoegen mislukt: $e',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _toonFout(String message) {
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

  InputDecoration _veldDeco(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: _appleFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade700, width: 1.2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width;
    final dialogW = maxW > 520 ? 500.0 : (maxW - 32).clamp(280.0, 500.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: dialogW,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _isEditMode
                          ? 'Glasbewassing Bewerken'
                          : 'Glasbewassing Toevoegen',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    color: Colors.blue.shade900,
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _naamController,
                      enabled: !_isSaving,
                      decoration: _veldDeco(
                        'Naam onderdeel (bijv. Buitenramen begane grond)',
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Frequentie',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _glasFrequentie,
                      decoration: _veldDeco(''),
                      items: const [
                        DropdownMenuItem(
                          value: 'op_afroep',
                          child: Text('Op afroep / Eenmalig'),
                        ),
                        DropdownMenuItem(
                          value: '12_keer_per_jaar',
                          child: Text('Maandelijks (12× per jaar)'),
                        ),
                        DropdownMenuItem(
                          value: '6_keer_per_jaar',
                          child: Text('Elke 2 maanden (6× per jaar)'),
                        ),
                        DropdownMenuItem(
                          value: '4_keer_per_jaar',
                          child: Text('Elk kwartaal (4× per jaar)'),
                        ),
                        DropdownMenuItem(
                          value: '2_keer_per_jaar',
                          child: Text('Elk half jaar (2× per jaar)'),
                        ),
                        DropdownMenuItem(
                          value: '1_keer_per_jaar',
                          child: Text('Jaarlijks (1× per jaar)'),
                        ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() => _glasFrequentie = val);
                              }
                            },
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Selecteer Werkzaamheden',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    if (_ladenDiensten)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_alleGlasDiensten.isEmpty)
                      Text(
                        'Geen glas-diensten in het moederbestek.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.orange.shade800,
                        ),
                      )
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          children: _alleGlasDiensten.map((dienst) {
                            final id = _dienstId(dienst);
                            final isChecked =
                                _geselecteerdeDienstenIds.contains(id);
                            return CheckboxListTile(
                              activeColor: Colors.blue.shade700,
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                _dienstNaam(dienst),
                                style: const TextStyle(fontSize: 14),
                              ),
                              value: isChecked,
                              onChanged: _isSaving
                                  ? null
                                  : (bool? val) {
                                      setState(() {
                                        if (val == true) {
                                          if (!_geselecteerdeDienstenIds
                                              .contains(id)) {
                                            _geselecteerdeDienstenIds.add(id);
                                          }
                                        } else {
                                          _geselecteerdeDienstenIds.remove(id);
                                        }
                                      });
                                    },
                            );
                          }).toList(growable: false),
                        ),
                      ),
                  ],
                ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed:
                      _isSaving || _ladenDiensten ? null : _opslaan,
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isEditMode ? 'Wijzigingen Opslaan' : 'Onderdeel Toevoegen',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
}
