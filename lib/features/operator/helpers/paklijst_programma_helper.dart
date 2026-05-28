import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bepaalt opdracht-ID uit planning- of opdracht-object.
String opdrachtIdUitItem(dynamic item) {
  if (item is! Map) return '';
  final map = Map<String, dynamic>.from(item);
  final oId = map['opdracht_id']?.toString();
  final itemId = map['id']?.toString();
  return oId ?? itemId ?? '';
}

/// Opdracht → Project → Offerte → Ruimtes & diensten (3 losse queries, geen join).
Future<void> openKogelvrijePaklijst(
  BuildContext context,
  String opdrachtId,
) async {
  if (opdrachtId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kan opdracht-ID niet vinden.')),
    );
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final supabase = Supabase.instance.client;

    final opdrachtData = await supabase
        .from('opdrachten')
        .select('project_id, frequentie_type')
        .eq('id', opdrachtId)
        .maybeSingle();
    if (opdrachtData == null) {
      throw Exception('Opdracht niet gevonden in database.');
    }

    final projectId = opdrachtData['project_id'];
    final freqType =
        opdrachtData['frequentie_type']?.toString().toLowerCase() ?? '';

    if (freqType == 'incidenteel' || freqType == 'eenmalig') {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Geen standaard materialenlijst voor losse klussen.'),
          ),
        );
      }
      return;
    }

    final projectData = await supabase
        .from('projecten')
        .select('offerte_id')
        .eq('id', projectId)
        .maybeSingle();
    final offerteId = projectData?['offerte_id'];

    if (offerteId == null) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Geen blauwdruk (offerte) gekoppeld aan dit project.',
            ),
          ),
        );
      }
      return;
    }

    // STAP 3: Haal de Ruimtes en Materialen op (Geen alias, puur de tabellen)
    final ruimtes = await supabase
        .from('offerte_ruimtes')
        .select('''
          naam_in_pand, 
          ruimte_categorie, 
          offerte_ruimte_diensten (
            in_regulier, 
            in_frequent, 
            in_periodiek, 
            moeder_bestek (
              volledige_naam, 
              taak_naam, 
              bestek_materialen (
                materialen (*)
              )
            )
          )
        ''')
        .eq('offerte_id', offerteId);

    if (context.mounted) Navigator.of(context).pop();

    // STAP 4: Filteren en Data Verzamelen met Kogelvrije Parsing
    List<Widget> ruimteWidgets = [];
    Set<String> globaleMaterialen = {};

    String getMatNaam(dynamic item) {
      if (item == null) return '';
      final Map<String, dynamic> d = item is Map<String, dynamic> ? item : {};
      return (d['artikelnaam'] ??
              d['artikel_naam'] ??
              d['materiaal_naam'] ??
              d['naam'] ??
              d['omschrijving'] ??
              '')
          .toString()
          .trim();
    }

    for (var ruimte in ruimtes) {
      final ruimtesDienstenRaw = ruimte['offerte_ruimte_diensten'];
      final List<dynamic> diensten = ruimtesDienstenRaw is List
          ? ruimtesDienstenRaw
          : (ruimtesDienstenRaw != null ? [ruimtesDienstenRaw] : []);
      Set<String> ruimteMaterialen = {};

      for (var d in diensten) {
        bool isActief = false;
        if (freqType == 'regulier' && d['in_regulier'] == true) isActief = true;
        if (freqType == 'frequent' && d['in_frequent'] == true) isActief = true;
        if (freqType == 'periodiek' && d['in_periodiek'] == true) {
          isActief = true;
        }

        if (isActief && d['moeder_bestek'] != null) {
          // KOGELVRIJ UITPAKKEN: Supabase kan joins soms als array doorgeven!
          final mbRaw = d['moeder_bestek'];
          final Map<String, dynamic> mb = (mbRaw is List && mbRaw.isNotEmpty)
              ? (mbRaw.first is Map
                    ? Map<String, dynamic>.from(mbRaw.first as Map)
                    : <String, dynamic>{})
              : (mbRaw is Map<String, dynamic> ? mbRaw : <String, dynamic>{});

          final bestekMatRaw = mb['bestek_materialen'];
          final List<dynamic> gekoppeldeMaterialen = bestekMatRaw is List
              ? bestekMatRaw
              : (bestekMatRaw != null ? [bestekMatRaw] : []);

          for (var koppeling in gekoppeldeMaterialen) {
            // SLIMME FALLBACKS: We kijken op elke mogelijke key waar Supabase de data verstopte!
            final matRaw =
                koppeling['materialen'] ?? koppeling['materiaal'] ?? koppeling;

            // Supabase geeft een Foreign Key soms als Object en soms als Lijst met 1 item.
            final Map<String, dynamic> materiaalData =
                (matRaw is List && matRaw.isNotEmpty)
                ? (matRaw.first is Map<String, dynamic>
                      ? matRaw.first
                      : <String, dynamic>{})
                : (matRaw is Map<String, dynamic> ? matRaw : {});

            final String naam = getMatNaam(materiaalData);
            if (naam.isNotEmpty) {
              ruimteMaterialen.add(naam);
              globaleMaterialen.add(naam);
            }
          }
        }
      }

      if (ruimteMaterialen.isNotEmpty) {
        ruimteWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
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
                ...ruimteMaterialen.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 6, left: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.subdirectory_arrow_right,
                          size: 16,
                          color: Colors.blueGrey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            m,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
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
        );
      }
    }

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Materialenlijst ($freqType)'),
        content: SizedBox(
          width: double.maxFinite,
          height: 500,
          child: globaleMaterialen.isEmpty
              ? SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Geen materialen gevonden. RAW DATABASE DUMP:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        ruimtes.toString(),
                        style: const TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  children: [
                    // HET TOTALE OVERZICHT (Bovenaan, Afwijkende Kleur)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border: Border.all(color: Colors.orange.shade200),
                        borderRadius: BorderRadius.circular(12),
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
                                'Totale Paklijst (Kar)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          ...globaleMaterialen.map(
                            (m) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.check_box_outline_blank,
                                    size: 18,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      m,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
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

                    const Text(
                      'Specificatie per ruimte',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // DE UITGESPLITSTE RUIMTES ERONDER
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
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fout bij ophalen paklijst: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// @deprecated Gebruik [openKogelvrijePaklijst] met [opdrachtIdUitItem].
Future<void> toonPaklijstProgrammaModal(
  BuildContext context,
  dynamic actieveOpdracht,
) => openKogelvrijePaklijst(context, opdrachtIdUitItem(actieveOpdracht));
