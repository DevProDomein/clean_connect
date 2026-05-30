import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/image_upload_service.dart';
import '../../../core/widgets/app_drawer.dart';

/// Beheer van de [materialen]-catalogus (aanmaken, bewerken, logistieke velden).
class MaterialenBeheerScreen extends StatefulWidget {
  const MaterialenBeheerScreen({super.key});

  @override
  State<MaterialenBeheerScreen> createState() => _MaterialenBeheerScreenState();
}

class _MaterialenBeheerScreenState extends State<MaterialenBeheerScreen> {
  final _supabase = Supabase.instance.client;
  final _zoekController = TextEditingController();

  List<Map<String, dynamic>> _materialen = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _zoekTerm = '';

  @override
  void initState() {
    super.initState();
    _zoekController.addListener(() {
      setState(() => _zoekTerm = _zoekController.text.trim().toLowerCase());
    });
    _fetchMaterialen();
  }

  @override
  void dispose() {
    _zoekController.dispose();
    super.dispose();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  String _materiaalNaam(Map<String, dynamic> row) {
    return _text(row['artikelnaam']).isNotEmpty
        ? _text(row['artikelnaam'])
        : _text(row['naam']).isNotEmpty
        ? _text(row['naam'])
        : 'Naamloos materiaal';
  }

  Future<void> _fetchMaterialen() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final res = await _supabase
          .from('materialen')
          .select()
          .order('categorie', ascending: true)
          .order('artikelnaam', ascending: true);
      if (!mounted) return;
      final list = (res as List?) ?? [];
      setState(() {
        _materialen = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _gefilterd {
    if (_zoekTerm.isEmpty) return _materialen;
    return _materialen.where((m) {
      final naam = _materiaalNaam(m).toLowerCase();
      final cat = _text(m['categorie']).toLowerCase();
      return naam.contains(_zoekTerm) || cat.contains(_zoekTerm);
    }).toList();
  }

  Future<void> _openMateriaalForm({Map<String, dynamic>? bestaand}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _MateriaalFormDialog(
        bestaand: bestaand,
        onOpgeslagen: () async {
          await _fetchMaterialen();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lijst = _gefilterd;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Materialen beheer',
          style: GoogleFonts.lato(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: _fetchMaterialen,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openMateriaalForm(),
        icon: const Icon(Icons.add),
        label: const Text('Nieuw materiaal'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Kon materialen niet laden:\n$_errorMessage',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchMaterialen,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        controller: _zoekController,
                        decoration: InputDecoration(
                          labelText: 'Zoek op naam of categorie',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        '${lijst.length} materiaal${lijst.length == 1 ? '' : 'en'}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                  if (lijst.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('Geen materialen gevonden.')),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final row = lijst[index];
                        final foto = _text(row['foto_url']);
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _openMateriaalForm(bestaand: row),
                              child: ListTile(
                                leading: foto.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          foto,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              const Icon(Icons.inventory_2),
                                        ),
                                      )
                                    : const Icon(Icons.inventory_2),
                                title: Text(
                                  _materiaalNaam(row),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    if (_text(row['categorie']).isNotEmpty)
                                      _text(row['categorie']),
                                    if (row['vereist_transport'] == true)
                                      'Transport',
                                    if (row['is_vermenigvuldigbaar'] == false)
                                      'Niet vermenigvuldigbaar',
                                  ].join(' · '),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            ),
                          ),
                        );
                      }, childCount: lijst.length),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 88)),
                ],
              ),
            ),
    );
  }
}

class _MateriaalFormDialog extends StatefulWidget {
  const _MateriaalFormDialog({
    this.bestaand,
    required this.onOpgeslagen,
  });

  final Map<String, dynamic>? bestaand;
  final Future<void> Function() onOpgeslagen;

  @override
  State<_MateriaalFormDialog> createState() => _MateriaalFormDialogState();
}

class _MateriaalFormDialogState extends State<_MateriaalFormDialog> {
  final _supabase = Supabase.instance.client;
  late final TextEditingController _naamController;
  late final TextEditingController _categorieController;

  bool isVermenigvuldigbaar = true;
  bool vereistTransport = false;
  String? fotoUrl;
  bool _opslaanBezig = false;
  bool _uploadBezig = false;

  bool get _isBewerken => widget.bestaand != null;

  @override
  void initState() {
    super.initState();
    final row = widget.bestaand;
    _naamController = TextEditingController(
      text: row?['artikelnaam']?.toString() ?? row?['naam']?.toString() ?? '',
    );
    _categorieController = TextEditingController(
      text: row?['categorie']?.toString() ?? '',
    );
    if (row != null) {
      isVermenigvuldigbaar = row['is_vermenigvuldigbaar'] != false;
      vereistTransport = row['vereist_transport'] == true;
      final rawFoto = row['foto_url']?.toString().trim();
      fotoUrl = (rawFoto != null && rawFoto.isNotEmpty) ? rawFoto : null;
    }
  }

  @override
  void dispose() {
    _naamController.dispose();
    _categorieController.dispose();
    super.dispose();
  }

  Future<void> _uploadFoto() async {
    if (_uploadBezig) return;
    setState(() => _uploadBezig = true);
    try {
      final newUrl = await ImageUploadService.pickAndUploadImage(
        context,
        'uploads',
        storageBucket: 'materialen',
      );
      if (!mounted || newUrl == null) return;
      setState(() => fotoUrl = newUrl);
    } finally {
      if (mounted) setState(() => _uploadBezig = false);
    }
  }

  Future<void> _opslaan() async {
    final naam = _naamController.text.trim();
    final categorie = _categorieController.text.trim();
    if (naam.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul een artikelnaam in.')),
      );
      return;
    }
    if (categorie.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul een categorie in.')),
      );
      return;
    }

    setState(() => _opslaanBezig = true);
    try {
      final payload = <String, dynamic>{
        'artikelnaam': naam,
        'categorie': categorie,
        'foto_url': fotoUrl,
        'is_vermenigvuldigbaar': isVermenigvuldigbaar,
        'vereist_transport': vereistTransport,
      };

      if (_isBewerken) {
        final id = widget.bestaand!['id']?.toString();
        if (id == null || id.isEmpty) {
          throw StateError('Materiaal heeft geen id.');
        }
        await _supabase.from('materialen').update(payload).eq('id', id);
      } else {
        await _supabase.from('materialen').insert(payload);
      }

      if (!mounted) return;
      Navigator.pop(context);
      await widget.onOpgeslagen();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isBewerken ? 'Materiaal bijgewerkt.' : 'Materiaal toegevoegd.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opslaan mislukt: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _opslaanBezig = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isBewerken ? 'Materiaal bewerken' : 'Nieuw materiaal'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _naamController,
                decoration: const InputDecoration(
                  labelText: 'Artikelnaam',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _categorieController,
                decoration: const InputDecoration(
                  labelText: 'Categorie',
                  border: OutlineInputBorder(),
                  hintText: 'bijv. Sanitair, Schoonmaakmiddelen',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Is vermenigvuldigbaar (bijv. doekjes per ruimte)',
                ),
                value: isVermenigvuldigbaar,
                onChanged: (v) => setState(() => isVermenigvuldigbaar = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Vereist transport (past niet in een tas)',
                ),
                value: vereistTransport,
                onChanged: (v) => setState(() => vereistTransport = v),
              ),
              const SizedBox(height: 8),
              if (fotoUrl != null && fotoUrl!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    fotoUrl!,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 120,
                      child: Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: _uploadBezig ? null : _uploadFoto,
                icon: _uploadBezig
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_outlined),
                label: Text(
                  fotoUrl == null || fotoUrl!.isEmpty
                      ? 'Foto uploaden'
                      : 'Foto vervangen',
                ),
              ),
              if (fotoUrl != null && fotoUrl!.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => fotoUrl = null),
                  child: const Text('Foto verwijderen'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _opslaanBezig ? null : () => Navigator.pop(context),
          child: const Text('Annuleren'),
        ),
        FilledButton(
          onPressed: _opslaanBezig ? null : _opslaan,
          child: _opslaanBezig
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Opslaan'),
        ),
      ],
    );
  }
}
