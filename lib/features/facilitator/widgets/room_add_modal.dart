import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/offerte_pricing_service.dart';

class RoomAddModal extends StatefulWidget {
  const RoomAddModal({
    super.key,
    required this.offerteId,
    required this.onSaved,
    this.existingRoom,
  });

  final String offerteId;
  final VoidCallback onSaved;
  final Map<String, dynamic>? existingRoom;

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

  String _freqLabelOf(Map<String, dynamic> taak) {
    final raw = (taak['frequentie_label'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (raw == 'regulier' || raw == 'frequent' || raw == 'periodiek') return raw;
    return 'regulier';
  }

  Widget _columnHeaderWithNieuweTaak(
    BuildContext context, {
    required String title,
    required Color titleColor,
    required String freqParam,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.12)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: titleColor,
            ),
          ),
          InkWell(
            onTap: _isSaving ? null : () => _toonNieuweTaakModal(freqParam),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'Nieuwe taak',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceTile(BuildContext context, Map<String, dynamic> taak) {
    final cs = Theme.of(context).colorScheme;
    final checked = _geselecteerdeTakenIds.contains(taak['id'].toString());

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
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrefillExistingRoom());
  }

  @override
  void dispose() {
    _naamController.dispose();
    super.dispose();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  Future<void> _deleteExistingRoom() async {
    final room = widget.existingRoom;
    if (room == null) return;
    final roomId = room['id'];
    if (roomId == null) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Bevestigen',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Weet je zeker dat je deze ruimte wilt verwijderen?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Annuleren',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
              ),
              child: Text(
                'Verwijderen',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    setState(() => _isSaving = true);
    try {
      final client = Supabase.instance.client;
      await client
          .from('offerte_ruimte_diensten')
          .delete()
          .eq('offerte_ruimte_id', roomId);
      await client.from('offerte_ruimtes').delete().eq('id', roomId);

      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade800,
          content: Text(
            'Verwijderen mislukt: $e',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String? _uiCategoryForDb(String? dbCategorie) {
    final needle = (dbCategorie ?? '').trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final e in _categorieMapping.entries) {
      if (e.value.trim().toLowerCase() == needle) return e.key;
    }
    return null;
  }

  Future<void> _maybePrefillExistingRoom() async {
    final room = widget.existingRoom;
    if (room == null) return;

    final roomId = room['id'];
    if (roomId == null) return;

    final naam = _text(room['naam_in_pand']);
    final dbCategorie = _text(room['ruimte_categorie']);
    final uiCategorie = _uiCategoryForDb(dbCategorie);
    final grootte = _text(room['grootte_label']).isEmpty ? 'A' : _text(room['grootte_label']);
    final parsedAantal = int.tryParse(_text(room['aantal_identiek'])) ?? 1;
    final aantal = parsedAantal < 1 ? 1 : parsedAantal;

    setState(() {
      _naamController.text = naam;
      _geselecteerdeGrootte = grootte;
      _aantal = aantal;
      _geselecteerdeCategorieUi = uiCategorie;
    });

    if (uiCategorie != null) {
      // Load available tasks for the category without wiping the selections.
      await _fetchTakenVoorCategorie(_categorieMapping[uiCategorie]!, clearSelections: false);
    }

    try {
      final res = await Supabase.instance.client
          .from('offerte_ruimte_diensten')
          .select('taak_id')
          .eq('offerte_ruimte_id', roomId);
      final ids = (res as List)
          .map((r) => (r as Map)['taak_id']?.toString() ?? '')
          .where((s) => s.trim().isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _geselecteerdeTakenIds
          ..clear()
          ..addAll(ids);
      });
    } catch (e) {
      // Non-fatal: the room can still be edited; selection can be re-done.
      debugPrint('Error loading room tasks: $e');
    }
  }

  Future<void> _fetchTakenVoorCategorie(
    String dbCategorie, {
    bool clearSelections = true,
  }) async {
    setState(() => _isLoadingTaken = true);
    try {
      final response = await Supabase.instance.client
          .from('moeder_bestek')
          .select()
          .ilike('ruimte', '%$dbCategorie%')
          .order('volledige_naam');
        
      setState(() {
        _beschikbareTaken = List<Map<String, dynamic>>.from(response);
        if (clearSelections) {
          _geselecteerdeTakenIds.clear(); // Always clear selections when changing category
        }
        _isLoadingTaken = false;
      });
    } catch (e) {
      debugPrint('Error fetching tasks: $e');
      setState(() => _isLoadingTaken = false);
    }
  }

  Future<Map<String, dynamic>?> _kiesDienstModal() async {
    var isLoading = true;
    List<dynamic> dienstenLijst = [];

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (isLoading && dienstenLijst.isEmpty) {
              Supabase.instance.client
                  .from('diensten')
                  .select('id, dienst_naam')
                  .order('dienst_naam')
                  .then((data) {
                if (!context.mounted) return;
                setModalState(() {
                  dienstenLijst = data as List;
                  isLoading = false;
                });
              }).catchError((_) {
                if (!context.mounted) return;
                setModalState(() => isLoading = false);
              });
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Kies de hoofddienst'),
              content: SizedBox(
                width: 400,
                height: 400,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: dienstenLijst.length,
                        itemBuilder: (c, i) {
                          final dienst = dienstenLijst[i];
                          return ListTile(
                            leading: const Icon(
                              Icons.cleaning_services,
                              color: Colors.blue,
                            ),
                            title: Text(dienst['dienst_naam'] ?? 'Onbekend'),
                            onTap: () => Navigator.pop(
                              ctx,
                              Map<String, dynamic>.from(dienst as Map),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuleren'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _herlaadTakenNaToevoegen({String? nieuwTaakId}) async {
    final uiCat = _geselecteerdeCategorieUi;
    if (uiCat == null) return;
    final dbCat = _categorieMapping[uiCat];
    if (dbCat == null) return;
    await _fetchTakenVoorCategorie(dbCat, clearSelections: false);
    if (nieuwTaakId != null &&
        nieuwTaakId.isNotEmpty &&
        !_geselecteerdeTakenIds.contains(nieuwTaakId)) {
      if (mounted) {
        setState(() => _geselecteerdeTakenIds.add(nieuwTaakId));
      }
    }
  }

  Future<void> _toonNieuweTaakModal(String standaardFrequentie) async {
    String? geselecteerdeDienstId;
    String? geselecteerdeDienstNaam;
    var frequentieLabel = standaardFrequentie.trim().toLowerCase();
    if (!['regulier', 'frequent', 'periodiek', 'incidenteel']
        .contains(frequentieLabel)) {
      frequentieLabel = 'regulier';
    }
    var geselecteerdeEenheid = 'stuks';
    var isGlasbewassing = false;

    final naamCtrl = TextEditingController();
    final omschrijvingCtrl = TextEditingController();
    final normAantalCtrl = TextEditingController();
    final freq1Ctrl = TextEditingController(text: '0');
    final freq2Ctrl = TextEditingController(text: '0');
    final freq3Ctrl = TextEditingController(text: '0');

    final inputDeco = InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF2F2F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        Widget buildField(String label, Widget input) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                input,
              ],
            ),
          );
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: SizedBox(
                width: 700,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Nieuwe Taak Aanmaken',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: buildField(
                                    'Gekoppelde Dienst (Verplicht)',
                                    InkWell(
                                      onTap: () async {
                                        final gekozen =
                                            await _kiesDienstModal();
                                        if (gekozen != null) {
                                          setModalState(() {
                                            geselecteerdeDienstId =
                                                gekozen['id']?.toString();
                                            geselecteerdeDienstNaam =
                                                gekozen['dienst_naam']
                                                    ?.toString();
                                          });
                                        }
                                      },
                                      child: InputDecorator(
                                        decoration: inputDeco.copyWith(
                                          prefixIcon: const Icon(
                                            Icons.link,
                                            color: Colors.blue,
                                          ),
                                        ),
                                        child: Text(
                                          geselecteerdeDienstNaam ??
                                              'Klik om een dienst te kiezen...',
                                          style: TextStyle(
                                            color: geselecteerdeDienstNaam ==
                                                    null
                                                ? Colors.red.shade700
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: buildField(
                                    'Volledige Naam',
                                    TextFormField(
                                      controller: naamCtrl,
                                      decoration: inputDeco,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      buildField(
                                        'Frequentie Label',
                                        DropdownButtonFormField<String>(
                                          initialValue: frequentieLabel,
                                          decoration: inputDeco,
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'regulier',
                                              child: Text('Regulier'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'frequent',
                                              child: Text('Frequent'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'periodiek',
                                              child: Text('Periodiek'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'incidenteel',
                                              child: Text('Incidenteel'),
                                            ),
                                          ],
                                          onChanged: (v) {
                                            if (v != null) {
                                              setModalState(
                                                () => frequentieLabel = v,
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                      buildField(
                                        'Is dit Glasbewassing?',
                                        DropdownButtonFormField<bool>(
                                          initialValue: isGlasbewassing,
                                          decoration: inputDeco,
                                          items: const [
                                            DropdownMenuItem(
                                              value: false,
                                              child: Text('Nee'),
                                            ),
                                            DropdownMenuItem(
                                              value: true,
                                              child: Text('Ja'),
                                            ),
                                          ],
                                          onChanged: (v) => setModalState(
                                            () => isGlasbewassing = v ?? false,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: buildField(
                                    'Uitgebreide Omschrijving (Optioneel)',
                                    TextFormField(
                                      controller: omschrijvingCtrl,
                                      decoration: inputDeco,
                                      maxLines: 5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 32),
                            Row(
                              children: [
                                Expanded(
                                  child: buildField(
                                    'Eenheid',
                                    DropdownButtonFormField<String>(
                                      initialValue: geselecteerdeEenheid,
                                      decoration: inputDeco,
                                      items: ['stuks', 'minuten', 'm2', 'uur']
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e,
                                              child: Text(e),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null) {
                                          setModalState(
                                            () => geselecteerdeEenheid = v,
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: buildField(
                                    'Norm Aantal (Prestatie)',
                                    TextFormField(
                                      controller: normAantalCtrl,
                                      decoration: inputDeco,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: buildField(
                                    'Freq. Optie 1',
                                    TextFormField(
                                      controller: freq1Ctrl,
                                      decoration: inputDeco,
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: buildField(
                                    'Freq. Optie 2',
                                    TextFormField(
                                      controller: freq2Ctrl,
                                      decoration: inputDeco,
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: buildField(
                                    'Freq. Optie 3',
                                    TextFormField(
                                      controller: freq3Ctrl,
                                      decoration: inputDeco,
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(20),
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            if (geselecteerdeDienstId == null ||
                                naamCtrl.text.trim().isEmpty ||
                                normAantalCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Vul alle verplichte velden (Dienst, Naam, Norm) in.',
                                  ),
                                ),
                              );
                              return;
                            }

                            try {
                              final normNummer = double.tryParse(
                                    normAantalCtrl.text
                                        .trim()
                                        .replaceAll(',', '.'),
                                  ) ??
                                  0.0;
                              final f1 = int.tryParse(freq1Ctrl.text) ?? 0;
                              final f2 = int.tryParse(freq2Ctrl.text) ?? 0;
                              final f3 = int.tryParse(freq3Ctrl.text) ?? 0;

                              final uiCat = _geselecteerdeCategorieUi;
                              final dbRuimte = uiCat != null
                                  ? _categorieMapping[uiCat]
                                  : null;

                              final omschrijving =
                                  omschrijvingCtrl.text.trim();

                              final payload = <String, dynamic>{
                                'dienst_id': geselecteerdeDienstId,
                                'import_dienst_naam': geselecteerdeDienstNaam,
                                'volledige_naam': naamCtrl.text.trim(),
                                'frequentie_label': frequentieLabel,
                                'norm_aantal': normNummer,
                                'eenheid': geselecteerdeEenheid,
                                'freq_optie_1': f1,
                                'freq_optie_2': f2,
                                'freq_optie_3': f3,
                                'freq_optie_4': 0,
                                'freq_optie_5': 0,
                                'freq_optie_6': 0,
                                'is_glasbewassing': isGlasbewassing,
                                'ruimte': ?dbRuimte,
                                if (omschrijving.isNotEmpty)
                                  'uitgebreide_omschrijving': omschrijving,
                              };

                              final inserted = await Supabase.instance.client
                                  .from('moeder_bestek')
                                  .insert(payload)
                                  .select('id')
                                  .single();

                              final nieuwId =
                                  inserted['id']?.toString() ?? '';

                              if (!context.mounted) return;
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Taak succesvol toegevoegd!'),
                                  backgroundColor: Colors.green,
                                ),
                              );

                              await _herlaadTakenNaToevoegen(
                                nieuwTaakId: nieuwId,
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Fout bij toevoegen: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          child: Text(
                            'Taak Aanmaken & Opslaan',
                            style: GoogleFonts.inter(
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
          },
        );
      },
    );

    naamCtrl.dispose();
    omschrijvingCtrl.dispose();
    normAantalCtrl.dispose();
    freq1Ctrl.dispose();
    freq2Ctrl.dispose();
    freq3Ctrl.dispose();
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
      final existing = widget.existingRoom;

      if (existing == null) {
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
      } else {
        final ruimteId = existing['id'];
        if (ruimteId == null) {
          throw StateError('Ruimte-ID ontbreekt. Bijwerken is niet mogelijk.');
        }

        // UPDATE offerte_ruimtes
        await client.from('offerte_ruimtes').update({
          'naam_in_pand': naam,
          'ruimte_categorie': _categorieMapping[_geselecteerdeCategorieUi],
          'grootte_label': _geselecteerdeGrootte,
          'aantal_identiek': _aantal,
        }).eq('id', ruimteId);

        // Clear linked tasks
        await client
            .from('offerte_ruimte_diensten')
            .delete()
            .eq('offerte_ruimte_id', ruimteId);

        // Re-link via existing RPC
        await client.rpc(
          'bulk_voeg_taken_toe',
          params: {
            'p_offerte_id': widget.offerteId,
            'p_ruimte_id': ruimteId,
            'p_taken_lijst': _geselecteerdeTakenIds,
          },
        );
      }

      await OffertePricingService.herberekenEnPersist(widget.offerteId);

      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showError('Ruimte opslaan mislukt: $e');
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
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : double.infinity),
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
                      if (widget.existingRoom != null)
                        TextButton.icon(
                          onPressed: _isSaving ? null : _deleteExistingRoom,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: Text(
                            'Verwijderen',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                          ),
                        ),
                      if (widget.existingRoom != null) const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.existingRoom == null
                              ? 'Nieuwe Ruimte Toevoegen'
                              : 'Ruimte Bewerken',
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
                                        : Builder(
                                            builder: (context) {
                                              final regulier = <Map<String, dynamic>>[];
                                              final frequent = <Map<String, dynamic>>[];
                                              final periodiek = <Map<String, dynamic>>[];

                                              for (final t in _beschikbareTaken) {
                                                final f = _freqLabelOf(t);
                                                if (f == 'frequent') {
                                                  frequent.add(t);
                                                } else if (f == 'periodiek') {
                                                  periodiek.add(t);
                                                } else {
                                                  regulier.add(t);
                                                }
                                              }

                                              final blue = cs.primary;
                                              final green = const Color(0xFF16A34A);
                                              final purple = const Color(0xFF7C3AED);

                                              if (MediaQuery.of(context).size.width > 800) {
                                                Widget col(
                                                  String title,
                                                  Color color,
                                                  List<Map<String, dynamic>> items,
                                                  String freqParam,
                                                ) {
                                                  return Expanded(
                                                    child: Column(
                                                      children: [
                                                        Padding(
                                                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                                                          child: _columnHeaderWithNieuweTaak(
                                                            context,
                                                            title: title,
                                                            titleColor: color,
                                                            freqParam: freqParam,
                                                          ),
                                                        ),
                                                        Expanded(
                                                          child: items.isEmpty
                                                              ? Center(
                                                                  child: Text(
                                                                    '—',
                                                                    style: GoogleFonts.inter(
                                                                      fontWeight: FontWeight.w700,
                                                                      color: cs.onSurface.withValues(alpha: 0.45),
                                                                    ),
                                                                  ),
                                                                )
                                                              : ListView.builder(
                                                                  padding: const EdgeInsets.all(10),
                                                                  itemCount: items.length,
                                                                  itemBuilder: (context, index) =>
                                                                      _serviceTile(context, items[index]),
                                                                ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }

                                                return Row(
                                                  children: [
                                                    col('Regulier', blue, regulier, 'regulier'),
                                                    VerticalDivider(
                                                      width: 1,
                                                      thickness: 1,
                                                      color: cs.onSurface.withValues(alpha: 0.06),
                                                    ),
                                                    col('Frequent', green, frequent, 'frequent'),
                                                    VerticalDivider(
                                                      width: 1,
                                                      thickness: 1,
                                                      color: cs.onSurface.withValues(alpha: 0.06),
                                                    ),
                                                    col('Periodiek', purple, periodiek, 'periodiek'),
                                                  ],
                                                );
                                              }

                                              Widget sliverSection({
                                                required String title,
                                                required Color color,
                                                required List<Map<String, dynamic>> items,
                                                required String freqParam,
                                              }) {
                                                return SliverMainAxisGroup(
                                                  slivers: [
                                                    SliverPersistentHeader(
                                                      pinned: true,
                                                      delegate: _StickyHeaderDelegate(
                                                        minHeight: 52,
                                                        maxHeight: 52,
                                                        child: Padding(
                                                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                                                          child: _columnHeaderWithNieuweTaak(
                                                            context,
                                                            title: title,
                                                            titleColor: color,
                                                            freqParam: freqParam,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    if (items.isEmpty)
                                                      SliverToBoxAdapter(
                                                        child: Padding(
                                                          padding: const EdgeInsets.all(14),
                                                          child: Text(
                                                            'Geen diensten.',
                                                            style: GoogleFonts.inter(
                                                              fontWeight: FontWeight.w600,
                                                              color: cs.onSurface.withValues(alpha: 0.55),
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                    else
                                                      SliverPadding(
                                                        padding: const EdgeInsets.all(10),
                                                        sliver: SliverList(
                                                          delegate: SliverChildBuilderDelegate(
                                                            (context, index) =>
                                                                _serviceTile(context, items[index]),
                                                            childCount: items.length,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                );
                                              }

                                              return CustomScrollView(
                                                slivers: [
                                                  sliverSection(
                                                    title: 'Regulier',
                                                    color: blue,
                                                    items: regulier,
                                                    freqParam: 'regulier',
                                                  ),
                                                  sliverSection(
                                                    title: 'Frequent',
                                                    color: green,
                                                    items: frequent,
                                                    freqParam: 'frequent',
                                                  ),
                                                  sliverSection(
                                                    title: 'Periodiek',
                                                    color: purple,
                                                    items: periodiek,
                                                    freqParam: 'periodiek',
                                                  ),
                                                ],
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
                                  'Ruimte opslaan',
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
        ),
      ),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.minHeight != minHeight ||
        oldDelegate.maxHeight != maxHeight ||
        oldDelegate.child != child;
  }
}
