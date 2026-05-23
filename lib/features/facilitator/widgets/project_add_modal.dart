import 'package:flutter/material.dart';

import '../../../core/supabase_client.dart';

/// Verplichte artikelkeuze bij nieuw project (facturatie: [projecten.standaard_artikel_code]).
class ProjectAddModal extends StatefulWidget {
  const ProjectAddModal({
    super.key,
    this.initialCode = 'SCH-001',
    this.initialName = 'Reguliere schoonmaak',
  });

  final String? initialCode;
  final String? initialName;

  @override
  State<ProjectAddModal> createState() => ProjectAddModalState();
}

class ProjectAddModalState extends State<ProjectAddModal> {
  String? geselecteerdeArtikelCode;
  String? geselecteerdeArtikelNaam;

  @override
  void initState() {
    super.initState();
    geselecteerdeArtikelCode = widget.initialCode;
    geselecteerdeArtikelNaam = widget.initialName;
  }

  String _artikelNaamUitRow(dynamic artikel) {
    return artikel['artikel_naam']?.toString() ??
        artikel['omschrijving']?.toString() ??
        artikel['naam']?.toString() ??
        'Naamloos artikel';
  }

  Future<void> _toonArtikelZoekModal() async {
    var zoekTerm = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        List<dynamic> artikelenLijst = [];
        var isLoading = true;

        return StatefulBuilder(
          builder: (context, setModalState) {
            if (isLoading && artikelenLijst.isEmpty) {
              AppSupabase.client
                  .from('artikelen')
                  .select()
                  .order('artikel_code', ascending: true)
                  .then((data) {
                if (!dialogContext.mounted) return;
                setModalState(() {
                  artikelenLijst = data;
                  isLoading = false;
                });
              }).catchError((error) {
                // ignore: avoid_print
                print('Fout bij laden artikelen: $error');
                if (!dialogContext.mounted) return;
                setModalState(() => isLoading = false);
              });
            }

            final gefilterdeLijst = artikelenLijst.where((a) {
              if (zoekTerm.isEmpty) return true;
              final naam = _artikelNaamUitRow(a).toLowerCase();
              final code = a['artikel_code']?.toString().toLowerCase() ?? '';
              final q = zoekTerm.toLowerCase();
              return naam.contains(q) || code.contains(q);
            }).toList();

            return AlertDialog(
              title: const Text('Selecteer een Artikel(groep)'),
              content: SizedBox(
                width: 500,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Zoek op naam of code',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => setModalState(() => zoekTerm = val),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : gefilterdeLijst.isEmpty
                              ? const Center(child: Text('Geen artikelen gevonden.'))
                              : ListView.builder(
                                  itemCount: gefilterdeLijst.length,
                                  itemBuilder: (ctx, i) {
                                    final artikel = gefilterdeLijst[i];
                                    final code =
                                        artikel['artikel_code']?.toString() ??
                                            'Geen code';
                                    final naam = _artikelNaamUitRow(artikel);
                                    final eenheid =
                                        artikel['eenheid']?.toString() ??
                                            'stuks';
                                    final prijsRaw = artikel['standaard_prijs'] ??
                                        artikel['verkoopprijs'] ??
                                        artikel['stukprijs'] ??
                                        artikel['verkoopprijs_ex_btw'] ??
                                        0;
                                    final prijs = double.tryParse(
                                          prijsRaw.toString(),
                                        ) ??
                                        0.0;

                                    return ListTile(
                                      leading: const CircleAvatar(
                                        backgroundColor: Colors.blue,
                                        child: Icon(
                                          Icons.inventory_2,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        '$code - $naam',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'Eenheid: $eenheid | Prijs: €${prijs.toStringAsFixed(2)}',
                                      ),
                                      onTap: () {
                                        setState(() {
                                          geselecteerdeArtikelCode = code;
                                          geselecteerdeArtikelNaam = naam;
                                        });
                                        Navigator.pop(dialogContext);
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Annuleren'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: InkWell(
        onTap: _toonArtikelZoekModal,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Gekoppeld Artikel (Verplicht voor facturatie)',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.inventory_2, color: Colors.blue),
            errorText: geselecteerdeArtikelCode == null
                ? 'Selecteer a.u.b. een artikel'
                : null,
          ),
          child: Text(
            geselecteerdeArtikelNaam ?? 'Klik om een artikel te selecteren...',
            style: TextStyle(
              color: geselecteerdeArtikelNaam == null
                  ? Colors.red.shade700
                  : Colors.black87,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
