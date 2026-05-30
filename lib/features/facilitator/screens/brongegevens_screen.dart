import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_drawer.dart';

/// Generator/Facilitator: beheer [moeder_bestek] en koppelingen via [bestek_materialen].
class BrongegevensScreen extends StatefulWidget {
  const BrongegevensScreen({super.key});

  @override
  State<BrongegevensScreen> createState() => _BrongegevensScreenState();
}

class _BrongegevensScreenState extends State<BrongegevensScreen> {
  final _supabase = Supabase.instance.client;
  final _zoekController = TextEditingController();

  List<Map<String, dynamic>> _alleBestekRegels = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _zoekTerm = '';
  String? _geselecteerdeRuimte;

  static const Map<String, String> _dienstCategorieMapping = {
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
  void initState() {
    super.initState();
    _zoekController.addListener(() {
      setState(() => _zoekTerm = _zoekController.text.trim().toLowerCase());
    });
    _fetchBrongegevens();
  }

  @override
  void dispose() {
    _zoekController.dispose();
    super.dispose();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  String _materiaalCategorie(Map<String, dynamic> row) {
    final cat = _text(row['categorie']);
    return cat.isEmpty ? 'Overig' : cat;
  }

  String _getSafeMaterialName(dynamic item) {
    if (item == null) return 'Onbekend materiaal';
    final Map<String, dynamic> data = item is Map<String, dynamic> ? item : {};
    if (data.isEmpty) return 'Onbekend materiaal';

    // Controleer dynamisch alle mogelijke kolomnamen, met 'artikelnaam' nu als absolute prioriteit!
    final String naam =
        data['artikelnaam']?.toString() ??
        data['artikel_naam']?.toString() ??
        data['materiaal_naam']?.toString() ??
        data['naam']?.toString() ??
        data['omschrijving']?.toString() ??
        'Naamloos materiaal';

    return naam.trim();
  }

  String _ruimteLabel(Map<String, dynamic> row) {
    final cat = _text(row['ruimte_categorie']);
    if (cat.isNotEmpty) return cat;
    return _text(row['ruimte']);
  }

  List<Map<String, dynamic>> _gekoppeldeMaterialenUitBestek(
    Map<String, dynamic> bestek,
  ) {
    final raw = bestek['bestek_materialen'];
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = item['materiaal'];
      if (m is Map) {
        out.add(Map<String, dynamic>.from(m));
      } else if (m is List && m.isNotEmpty && m.first is Map) {
        out.add(Map<String, dynamic>.from(m.first as Map));
      }
    }
    return out;
  }

  List<String> _gekoppeldeMateriaalIds(Map<String, dynamic> bestek) {
    final raw = bestek['bestek_materialen'];
    if (raw is! List) return [];
    final ids = <String>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final mid = _text(item['materiaal_id']);
      if (mid.isNotEmpty) ids.add(mid);
    }
    return ids;
  }

  int _materiaalTelling(Map<String, dynamic> bestek) {
    final raw = bestek['bestek_materialen'];
    if (raw is List) return raw.length;
    return 0;
  }

  List<String> get _uniekeRuimtes {
    final set = <String>{};
    for (final row in _alleBestekRegels) {
      final label = _ruimteLabel(row);
      if (label.isNotEmpty) set.add(label);
    }
    final list = set.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  List<Map<String, dynamic>> get _gefilterdeRegels {
    return _alleBestekRegels.where((row) {
      if (_geselecteerdeRuimte != null &&
          _ruimteLabel(row) != _geselecteerdeRuimte) {
        return false;
      }
      if (_zoekTerm.isEmpty) return true;
      final naam =
          row['volledige_naam']?.toString().toLowerCase() ??
          row['naam']?.toString().toLowerCase() ??
          '';
      final haystack = '$naam ${_ruimteLabel(row)}'.toLowerCase();
      return haystack.contains(_zoekTerm);
    }).toList();
  }

  int _crossAxisCount(double width) {
    if (width >= 1200) return 6;
    if (width >= 900) return 4;
    if (width >= 600) return 2;
    return 2;
  }

  double _childAspectRatio(double width) {
    if (width >= 900) return 1.35;
    return 1.2;
  }

  IconData _icoonVoorRuimte(String ruimte) {
    final r = ruimte.toLowerCase();
    if (r.contains('sanitair')) return Icons.wc_outlined;
    if (r.contains('keuken') || r.contains('pantry')) {
      return Icons.kitchen_outlined;
    }
    if (r.contains('glas')) return Icons.window_outlined;
    if (r.contains('terrein')) return Icons.grass_outlined;
    if (r.contains('trap')) return Icons.stairs_outlined;
    if (r.contains('hal') || r.contains('gang')) {
      return Icons.door_front_door_outlined;
    }
    if (r.contains('kamer') || r.contains('kantoor')) {
      return Icons.meeting_room_outlined;
    }
    return Icons.cleaning_services_outlined;
  }

  Future<void> _fetchBrongegevens() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await _supabase
          .from('moeder_bestek')
          .select(
            '*, bestek_materialen(id, materiaal_id, materiaal:materialen(*))',
          )
          .order('volledige_naam');

      if (!mounted) return;
      setState(() {
        _alleBestekRegels = (response as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _alleBestekRegels = [];
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  String? _uiCategorieVoorDbRuimte(String dbRuimte) {
    for (final entry in _dienstCategorieMapping.entries) {
      if (entry.value.toLowerCase() == dbRuimte.toLowerCase()) {
        return entry.key;
      }
    }
    for (final key in _dienstCategorieMapping.keys) {
      if (key.toLowerCase() == dbRuimte.toLowerCase()) return key;
    }
    return dbRuimte.isEmpty ? null : dbRuimte;
  }

  Future<void> _toonMaterialenKoppelModal(
    String bestekId,
    List<String> huidigeGekoppeldeMaterialen,
  ) async {
    final geselecteerdeMateriaalIds = List<String>.from(
      huidigeGekoppeldeMaterialen,
    );
    var materiaalZoek = '';
    List<Map<String, dynamic>> alleMaterialen = [];
    var laden = true;
    String? laadFout;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> laadMaterialen() async {
              setModalState(() {
                laden = true;
                laadFout = null;
              });
              try {
                // 1. Haal de materialen plat op zonder sortering in de database (voorkomt crashes!)
                final res = await _supabase.from('materialen').select();
                if (!ctx.mounted) return;
                setModalState(() {
                  final List<dynamic> rawMaterialen = (res as List?) ?? [];

                  // 2. Sorteer de lijst razendsnel in het geheugen van de app o.b.v. de dynamische naam!
                  rawMaterialen.sort((a, b) {
                    final String nameA = _getSafeMaterialName(a).toLowerCase();
                    final String nameB = _getSafeMaterialName(b).toLowerCase();
                    return nameA.compareTo(nameB);
                  });

                  alleMaterialen = rawMaterialen
                      .whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList();
                  laden = false;
                });
              } catch (e) {
                if (!ctx.mounted) return;
                setModalState(() {
                  laadFout = e.toString();
                  laden = false;
                });
              }
            }

            if (laden && alleMaterialen.isEmpty && laadFout == null) {
              laadMaterialen();
            }

            final zoekLower = materiaalZoek.toLowerCase();
            final gefilterd = alleMaterialen.where((m) {
              if (materiaalZoek.isEmpty) return true;
              final naam = _getSafeMaterialName(m).toLowerCase();
              final cat = _materiaalCategorie(m).toLowerCase();
              return naam.contains(zoekLower) || cat.contains(zoekLower);
            }).toList();

            final perCategorie = <String, List<Map<String, dynamic>>>{};
            for (final m in gefilterd) {
              final cat = _materiaalCategorie(m);
              perCategorie.putIfAbsent(cat, () => []).add(m);
            }
            final categorieKeys = perCategorie.keys.toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

            Future<void> opslaan() async {
              try {
                await _supabase
                    .from('bestek_materialen')
                    .delete()
                    .eq('moeder_bestek_id', bestekId);

                if (geselecteerdeMateriaalIds.isNotEmpty) {
                  final payload = geselecteerdeMateriaalIds
                      .map(
                        (mId) => {
                          'moeder_bestek_id': bestekId,
                          'materiaal_id': mId,
                        },
                      )
                      .toList();
                  await _supabase.from('bestek_materialen').insert(payload);
                }

                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                await _fetchBrongegevens();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Materiaalkoppelingen opgeslagen.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('Opslaan mislukt: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Materialen koppelen'),
              content: SizedBox(
                width: double.maxFinite,
                height: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Zoek materiaal',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                          setModalState(() => materiaalZoek = v.trim()),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: laden
                          ? const Center(child: CircularProgressIndicator())
                          : laadFout != null
                          ? Center(child: Text('Fout: $laadFout'))
                          : gefilterd.isEmpty
                          ? const Center(
                              child: Text('Geen materialen gevonden.'),
                            )
                          : ListView(
                              children: [
                                for (final cat in categorieKeys) ...[
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(
                                      top: 8,
                                      bottom: 4,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      cat,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Colors.blue.shade800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  ...perCategorie[cat]!.map((m) {
                                    final mid = _text(m['id']);
                                    final checked = geselecteerdeMateriaalIds
                                        .contains(mid);
                                    return CheckboxListTile(
                                      value: checked,
                                      onChanged: (val) {
                                        setModalState(() {
                                          if (val == true) {
                                            if (!geselecteerdeMateriaalIds
                                                .contains(mid)) {
                                              geselecteerdeMateriaalIds.add(
                                                mid,
                                              );
                                            }
                                          } else {
                                            geselecteerdeMateriaalIds.remove(
                                              mid,
                                            );
                                          }
                                        });
                                      },
                                      title: Text(
                                        _getSafeMaterialName(m),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuleren'),
                ),
                FilledButton(
                  onPressed: opslaan,
                  child: const Text('Koppelingen Opslaan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toonBestekDetailModal(Map<String, dynamic> bestek) async {
    final bestekId = _text(bestek['id']);
    if (bestekId.isEmpty) return;

    final String actueleNaam =
        bestek['volledige_naam'] ?? bestek['naam'] ?? 'Taak bewerken';

    final naamCtl = TextEditingController(text: actueleNaam.toString());
    var geselecteerdeUiCat =
        _uiCategorieVoorDbRuimte(_ruimteLabel(bestek)) ??
        _dienstCategorieMapping.keys.first;
    var opslaanBezig = false;
    var gekoppeld = _gekoppeldeMaterialenUitBestek(bestek);

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Map<String, dynamic>? vindBestekRij() {
              for (final r in _alleBestekRegels) {
                if (_text(r['id']) == bestekId) return r;
              }
              return null;
            }

            Future<void> slaBestekOp() async {
              setModalState(() => opslaanBezig = true);
              try {
                final dbRuimte =
                    _dienstCategorieMapping[geselecteerdeUiCat] ??
                    geselecteerdeUiCat;
                await _supabase
                    .from('moeder_bestek')
                    .update({
                      'volledige_naam': naamCtl.text.trim(),
                      'ruimte': dbRuimte,
                    })
                    .eq('id', bestekId);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Bestekregel bijgewerkt.'),
                    backgroundColor: Colors.green,
                  ),
                );
                await _fetchBrongegevens();
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('Opslaan mislukt: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              } finally {
                if (ctx.mounted) {
                  setModalState(() => opslaanBezig = false);
                }
              }
            }

            return AlertDialog(
              title: Text(actueleNaam.toString()),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: naamCtl,
                        decoration: const InputDecoration(
                          labelText: 'Taaknaam',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          _dienstCategorieMapping.containsKey(
                            geselecteerdeUiCat,
                          )
                              ? geselecteerdeUiCat
                              : _dienstCategorieMapping.keys.first,
                        ),
                        initialValue:
                            _dienstCategorieMapping.containsKey(
                              geselecteerdeUiCat,
                            )
                            ? geselecteerdeUiCat
                            : _dienstCategorieMapping.keys.first,
                        decoration: const InputDecoration(
                          labelText: 'Dienst-categorie',
                          border: OutlineInputBorder(),
                        ),
                        items: _dienstCategorieMapping.keys
                            .map(
                              (k) => DropdownMenuItem(value: k, child: Text(k)),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setModalState(() => geselecteerdeUiCat = v);
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.link),
                          label: const Text('Materialen Koppelen / Beheren'),
                          onPressed: () async {
                            await _toonMaterialenKoppelModal(
                              bestekId,
                              _gekoppeldeMateriaalIds(
                                vindBestekRij() ?? bestek,
                              ),
                            );
                            if (!ctx.mounted) return;
                            final vernieuwd = vindBestekRij();
                            if (vernieuwd != null) {
                              setModalState(() {
                                gekoppeld = _gekoppeldeMaterialenUitBestek(
                                  vernieuwd,
                                );
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (gekoppeld.isEmpty)
                        Text(
                          'Nog geen materialen gekoppeld.',
                          style: TextStyle(color: Colors.grey.shade600),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final m in gekoppeld)
                              Chip(
                                label: Text(
                                  _text(m['naam']).isEmpty
                                      ? 'Materiaal'
                                      : _text(m['naam']),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Sluiten'),
                ),
                FilledButton(
                  onPressed: opslaanBezig ? null : slaBestekOp,
                  child: opslaanBezig
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Opslaan'),
                ),
              ],
            );
          },
        );
      },
    );

    naamCtl.dispose();
  }

  Widget _buildFilters(BuildContext context) {
    final ruimtes = _uniekeRuimtes;
    final isSmal = MediaQuery.sizeOf(context).width < 600;

    final zoekVeld = TextField(
      controller: _zoekController,
      decoration: InputDecoration(
        labelText: 'Zoek op taak of categorie',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
    );

    final ruimteDropdown = DropdownButtonFormField<String?>(
      key: ValueKey(_geselecteerdeRuimte),
      initialValue: _geselecteerdeRuimte,
      decoration: InputDecoration(
        labelText: 'Ruimte',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Alle ruimtes'),
        ),
        ...ruimtes.map(
          (r) => DropdownMenuItem<String?>(value: r, child: Text(r)),
        ),
      ],
      onChanged: (v) => setState(() => _geselecteerdeRuimte = v),
    );

    if (isSmal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [zoekVeld, const SizedBox(height: 10), ruimteDropdown],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: zoekVeld),
        const SizedBox(width: 12),
        Expanded(child: ruimteDropdown),
        IconButton(
          tooltip: 'Vernieuwen',
          onPressed: _fetchBrongegevens,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _buildBestekCard(Map<String, dynamic> row) {
    final ruimte = _ruimteLabel(row);
    final telling = _materiaalTelling(row);

    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toonBestekDetailModal(row),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _icoonVoorRuimte(ruimte),
                color: Colors.blue.shade700,
                size: 28,
              ),
              const SizedBox(height: 10),
              Text(
                row['volledige_naam'] ?? row['naam'] ?? 'Onbekende taak',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                ruimte.isEmpty ? '—' : ruimte,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$telling Materialen gekoppeld',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.blue.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gefilterd = _gefilterdeRegels;
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Brongegevens (Bestek)',
          style: GoogleFonts.lato(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Materialen beheer',
            onPressed: () =>
                Navigator.of(context).pushNamed('/materialen-beheer'),
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: _fetchBrongegevens,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Kon bestek niet laden:\n$_errorMessage',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchBrongegevens,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: _buildFilters(context),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        '${gefilterd.length} bestekregel${gefilterd.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                  if (gefilterd.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('Geen bestekregels gevonden.')),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _crossAxisCount(width),
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: _childAspectRatio(width),
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildBestekCard(gefilterd[index]),
                          childCount: gefilterd.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
