import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DksInspectieFormScreen extends StatefulWidget {
  final String rapportId;
  const DksInspectieFormScreen({super.key, required this.rapportId});

  @override
  State<DksInspectieFormScreen> createState() => _DksInspectieFormScreenState();
}

class _DksInspectieFormScreenState extends State<DksInspectieFormScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isSaving = false;

  Map<String, dynamic>? _rapport;
  List<Map<String, dynamic>> _regels = [];
  Map<String, List<Map<String, dynamic>>> _groupedRegels = {};
  List<dynamic> _operators = [];

  final TextEditingController _finalScoreController = TextEditingController(text: '0.0');
  double _suggestedScore = 0.0;

  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  Uint8List? _signatureBytes;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _finalScoreController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final String cleanId = widget.rapportId.replaceAll('"', '').trim();
      debugPrint('X-RAY: Start laden voor CLEAN rapport ID: $cleanId');

      // 1. KAFT OPHALEN
      final rapportData = await _supabase.from('dks_rapporten').select().eq('id', cleanId).maybeSingle();
      if (rapportData == null) throw 'Rapport niet gevonden in dks_rapporten voor ID: $cleanId';
      debugPrint('X-RAY: Kaft succesvol geladen. Project ID: ${rapportData['project_id']}');

      // 2. REGELS OPHALEN (HET CRUCIALE DEEL)
      final List<dynamic> regelsData = await _supabase.from('dks_regels').select().eq('dks_rapport_id', cleanId);
      debugPrint('X-RAY: ${regelsData.length} regels gevonden in de database!');

      // 3. TEAM OPHALEN (Veilig in try-catch zodat dit de regels nooit blokkeert)
      List<dynamic> operatorData = [];
      try {
        operatorData = await _supabase.from('view_project_operator_prestaties').select().eq('project_id', rapportData['project_id']);
      } catch (e) {
        debugPrint('X-RAY: Team ophalen mislukt (Geen ramp): $e');
      }

      // 4. LOKAAL GROEPEREN OP CATEGORIE (RUIMTE)
      Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var r in regelsData) {
        final Map<String, dynamic> regel = Map<String, dynamic>.from(r);
        final String cat = regel['categorie']?.toString() ?? 'Algemene Ruimte';
        if (!grouped.containsKey(cat)) grouped[cat] = [];
        grouped[cat]!.add(regel);
      }

      if (mounted) {
        setState(() {
          _rapport = rapportData;
          _regels = List<Map<String, dynamic>>.from(regelsData);
          _operators = operatorData;
          _groupedRegels = grouped;
          _isLoading = false;
        });
        _calculateLiveScore();
      }
    } catch (e) {
      debugPrint('X-RAY FATAL ERROR: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout bij inladen: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _calculateLiveScore() {
    int count = 0;
    double totalPoints = 0;

    for (var regel in _regels) {
      final raw = regel['beoordeling'];
      if (raw == null) continue;
      final beoordeling = raw.toString().toLowerCase();
      if (beoordeling == 'nvt') continue;

      count++;
      if (beoordeling == 'uitstekend') totalPoints += 10.0;
      if (beoordeling == 'goed') totalPoints += 8.0;
      if (beoordeling == 'matig') totalPoints += 6.0;
      if (beoordeling == 'onvoldoende') totalPoints += 4.0;
      if (beoordeling == 'onacceptabel') totalPoints += 2.0;
    }

    setState(() {
      _suggestedScore = count > 0 ? (totalPoints / count) : 0.0;
      _finalScoreController.text = _suggestedScore.toStringAsFixed(1);
    });
  }

  Future<void> _updateBeoordeling(String id, String nieuweStatus) async {
    try {
      // 1. Update database asynchronously
      await _supabase.from('dks_regels').update({'beoordeling': nieuweStatus}).eq('id', id);

      // 2. Update local state STRICTLY to trigger a UI rebuild
      setState(() {
        // Update in the flat list
        final index = _regels.indexWhere((r) => r['id'].toString() == id);
        if (index != -1) {
          _regels[index]['beoordeling'] = nieuweStatus;
        }

        // Update in the grouped list (which the UI actually uses to render!)
        for (var category in _groupedRegels.keys) {
          final groupIndex = _groupedRegels[category]!.indexWhere((r) => r['id'].toString() == id);
          if (groupIndex != -1) {
            _groupedRegels[category]![groupIndex]['beoordeling'] = nieuweStatus;
            // New list + map copies so dependents (ExpansionTile subtree) reliably rebuild.
            _groupedRegels[category] = _groupedRegels[category]!
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
            break;
          }
        }
      });

      // 3. Recalculate math
      _calculateLiveScore();
    } catch (e) {
      debugPrint('Update Error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kon niet opslaan: $e')));
    }
  }

  Future<void> _afronden() async {
    if (_signatureBytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Handtekening is verplicht'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final String cleanId = widget.rapportId.replaceAll('"', '').trim();
    setState(() => _isSaving = true);
    try {
      final fileName = 'sig_${cleanId}_${DateTime.now().millisecondsSinceEpoch}.png';
      await _supabase.storage.from('dks_handtekeningen').uploadBinary(
            fileName,
            _signatureBytes!,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: false,
            ),
          );
      final signatureUrl = _supabase.storage.from('dks_handtekeningen').getPublicUrl(fileName);

      await _supabase.from('dks_rapporten').update({
        'status': 'definitief',
        'score_voorgesteld': _suggestedScore,
        'score_definitief': double.tryParse(_finalScoreController.text) ?? _suggestedScore,
        'datum_uitgevoerd': DateTime.now().toIso8601String(),
        'handtekening_url': signatureUrl,
      }).eq('id', cleanId);

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Inspectie afgerond!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e')));
      }
    }
  }

  Future<void> _showSignatureDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return SelectionArea(
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(
              'Handtekening',
              style: GoogleFonts.lato(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 250,
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  var w = constraints.maxWidth;
                  if (!w.isFinite || w <= 0) {
                    w = MediaQuery.sizeOf(dialogContext).width - 80;
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Signature(
                      controller: _signatureController,
                      width: w,
                      height: 250,
                      backgroundColor: Colors.grey.shade100,
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => _signatureController.clear(),
                child: Text(
                  'Wissen',
                  style: GoogleFonts.lato(fontWeight: FontWeight.w700),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  final bytes = await _signatureController.toPngBytes();
                  if (bytes != null && mounted) {
                    setState(() => _signatureBytes = bytes);
                  }
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
                child: Text(
                  'Opslaan',
                  style: GoogleFonts.lato(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: SelectionArea(
          child: Center(child: CupertinoActivityIndicator(radius: 15)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text('Kwaliteitscontrole', style: GoogleFonts.lato(fontWeight: FontWeight.w900, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadInitialData),
        ],
      ),
      body: SelectionArea(
        child: _groupedRegels.isEmpty
            ? Center(
                child: Text(
                  'Geen regels gevonden. Check de X-RAY logs in de console.',
                  style: GoogleFonts.lato(fontSize: 16),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_rapport != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Rapport status: ${_rapport?['status'] ?? ''} • Operators: ${_operators.length}',
                        style: GoogleFonts.lato(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ..._groupedRegels.entries.map(
                    (entry) => _buildRoomSection(entry.key, entry.value),
                  ),
                  const SizedBox(height: 24),
                  _buildFooter(),
                ],
              ),
      ),
    );
  }

  Widget _buildRoomSection(String roomName, List<Map<String, dynamic>> rules) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 10), blurRadius: 10)]),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(roomName, style: GoogleFonts.lato(fontWeight: FontWeight.w800, fontSize: 18)),
        childrenPadding: const EdgeInsets.all(16),
        children: rules.map((rule) => _buildCheckItem(rule)).toList(),
      ),
    );
  }

  Widget _buildCheckItem(Map<String, dynamic> rule) {
    final String status = (rule['beoordeling'] ?? 'nvt').toString().toLowerCase();
    final String onderdeel = (rule['onderdeel'] ?? 'Onbekende taak').toString();
    final String ruimteNaam = (rule['ruimte_naam'] ?? '').toString();
    final String ruimteCategorie = (rule['ruimte_categorie'] ?? '').toString();
    final String ruleIdStr = rule['id']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            onderdeel,
            style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                [ruimteNaam, ruimteCategorie].where((e) => e.isNotEmpty).join('  |  ').trim().isEmpty
                    ? '—'
                    : [ruimteNaam, ruimteCategorie].where((e) => e.isNotEmpty).join('  |  '),
                style: GoogleFonts.lato(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              key: ValueKey<String>('dks_chips_${ruleIdStr}_$status'),
              children: [
                _ratingBtn('uitstekend', 'Uitstekend', Colors.green.shade700, status == 'uitstekend', ruleIdStr),
                _ratingBtn('goed', 'Goed', Colors.lightGreen.shade600, status == 'goed', ruleIdStr),
                _ratingBtn('matig', 'Matig', Colors.amber.shade600, status == 'matig', ruleIdStr),
                _ratingBtn('onvoldoende', 'Onvoldoende', Colors.orange.shade700, status == 'onvoldoende', ruleIdStr),
                _ratingBtn('onacceptabel', 'Onacceptabel', Colors.red.shade700, status == 'onacceptabel', ruleIdStr),
                _ratingBtn('nvt', 'N.v.t.', Colors.grey.shade500, status == 'nvt', ruleIdStr),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingBtn(String val, String label, Color activeColor, bool active, String id) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _updateBeoordeling(id, val),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: active ? activeColor : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: active ? activeColor : Colors.transparent, width: 1.5),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.grey.shade700,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Berekend Cijfer: ${_suggestedScore.toStringAsFixed(1)}',
            style: GoogleFonts.lato(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.blue),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _finalScoreController,
            style: GoogleFonts.lato(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Definitief Cijfer',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          if (_signatureBytes == null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSaving ? null : _showSignatureDialog,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0052CC),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0052CC).withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '✍️ Zet Handtekening (Verplicht)',
                        style: GoogleFonts.lato(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              alignment: Alignment.center,
              child: Image.memory(
                _signatureBytes!,
                height: 100,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isSaving ? null : _showSignatureDialog,
              child: Text(
                'Handtekening aanpassen',
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0052CC),
                  fontSize: 15,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: (_isSaving || _signatureBytes == null) ? null : _afronden,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              backgroundColor: const Color(0xFF0052CC),
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isSaving
                ? const CupertinoActivityIndicator(color: Colors.white)
                : Text(
                    'Inspectie Afronden',
                    style: GoogleFonts.lato(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          )
        ],
      ),
    );
  }
}

