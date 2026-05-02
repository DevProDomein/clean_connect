import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only view of a completed DKS report: grouped by [ruimte_naam], no interactions.
void showDksReadonlyModal(BuildContext context, {required String rapportId}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DksReadonlyModal(rapportId: rapportId),
  );
}

class DksReadonlyModal extends StatefulWidget {
  const DksReadonlyModal({super.key, required this.rapportId});

  final String rapportId;

  @override
  State<DksReadonlyModal> createState() => _DksReadonlyModalState();
}

class _DksReadonlyModalState extends State<DksReadonlyModal> {
  static const _bg = Color(0xFFF5F5F7);
  static const _radius = 24.0;

  final _client = Supabase.instance.client;
  bool _loading = true;
  Object? _error;
  Map<String, dynamic>? _rapport;
  Map<String, List<Map<String, dynamic>>> _byRoom = {};

  String _t(dynamic v) => (v?.toString() ?? '').trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cleanId = widget.rapportId.replaceAll('"', '').trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rpt = await _client.from('dks_rapporten').select().eq('id', cleanId).maybeSingle();
      if (rpt == null) throw 'Rapport niet gevonden';
      final raw = await _client.from('dks_regels').select().eq('dks_rapport_id', cleanId).order('ruimte_naam', ascending: true);
      final list = (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final row in list) {
        final key = _t(row['ruimte_naam']).isEmpty ? 'Overig' : _t(row['ruimte_naam']);
        grouped.putIfAbsent(key, () => []).add(row);
      }
      if (mounted) {
        setState(() {
          _rapport = Map<String, dynamic>.from(rpt as Map);
          _byRoom = grouped;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  static ({String label, Color color}) _pillForBeoordeling(String b) {
    switch (b) {
      case 'uitstekend':
        return (label: 'Uitstekend', color: Colors.green.shade700);
      case 'goed':
        return (label: 'Goed', color: Colors.lightGreen.shade600);
      case 'matig':
        return (label: 'Matig', color: Colors.amber.shade600);
      case 'onvoldoende':
        return (label: 'Onvoldoende', color: Colors.orange.shade700);
      case 'onacceptabel':
        return (label: 'Onacceptabel', color: Colors.red.shade700);
      case 'fout':
        return (label: 'Fout', color: Colors.red.shade700);
      case 'nvt':
        return (label: 'N.v.t.', color: Colors.grey.shade600);
      default:
        return (label: b.isEmpty ? '—' : b, color: Colors.grey.shade600);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final cijfer = _rapport?['score_definitief'] ?? _rapport?['score_voorgesteld'];
    double? cijferNum;
    if (cijfer is num) {
      cijferNum = cijfer.toDouble();
    } else if (cijfer != null) {
      cijferNum = double.tryParse(cijfer.toString().replaceAll(',', '.'));
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(_radius)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Rapport (alleen lezen)',
                        style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 20),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const Expanded(child: Center(child: CupertinoActivityIndicator(radius: 16)))
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Kon niet laden: $_error', textAlign: TextAlign.center, style: GoogleFonts.lato()),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      for (final entry in _byRoom.entries) ...[
                        _buildRoomCard(entry.key, entry.value),
                        const SizedBox(height: 12),
                      ],
                      if (_byRoom.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text('Geen regels.', style: GoogleFonts.lato(color: Colors.grey.shade600)),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(_radius),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          cijferNum != null
                              ? 'Cijfer: ${cijferNum.toStringAsFixed(1)}'
                              : 'Cijfer: —',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lato(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0052CC),
                          ),
                        ),
                      ),
                      SizedBox(height: 12 + bottom),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoomCard(String roomName, List<Map<String, dynamic>> rules) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(roomName, style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 17)),
        children: rules.map((r) => _buildReadonlyTask(r)).toList(),
      ),
    );
  }

  Widget _buildReadonlyTask(Map<String, dynamic> rule) {
    final onderdeel = _t(rule['onderdeel']).isEmpty ? 'Taak' : _t(rule['onderdeel']);
    final cat = _t(rule['ruimte_categorie']);
    final b = _t(rule['beoordeling']).toLowerCase();
    final beo = b.isEmpty ? 'nvt' : b;
    final pill = _pillForBeoordeling(beo);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(onderdeel, style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.w800)),
          if (cat.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(cat, style: GoogleFonts.lato(fontSize: 13, color: Colors.grey.shade600)),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: pill.color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: pill.color, width: 2),
              ),
              child: Text(
                pill.label,
                style: GoogleFonts.lato(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
