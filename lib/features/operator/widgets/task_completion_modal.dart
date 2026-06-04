import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../helpers/werkprogramma_data_helper.dart';
import '../services/operator_planning_repository.dart';

/// Formele afrond-flow: diensten afvinken, daarna status naar afgerond.
class TaskCompletionModal extends StatefulWidget {
  const TaskCompletionModal({
    super.key,
    required this.planningItem,
    required this.onCompleted,
  });

  final Map<String, dynamic> planningItem;
  final VoidCallback onCompleted;

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> planningItem,
    required VoidCallback onCompleted,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TaskCompletionModal(
        planningItem: planningItem,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  State<TaskCompletionModal> createState() => _TaskCompletionModalState();
}

class _TaskCompletionModalState extends State<TaskCompletionModal> {
  final _repository = OperatorPlanningRepository();
  bool _loading = true;
  String? _loadError;
  List<WerkprogrammaTaakItem> _taken = [];
  final Map<String, bool> _checked = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadTaken();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  String _planningId() {
    final pid = widget.planningItem['planning_id']?.toString().trim();
    if (pid != null && pid.isNotEmpty) return pid;
    return _text(widget.planningItem['id']);
  }

  String _opdrachtId() {
    final embed = widget.planningItem['opdracht'];
    return _text(widget.planningItem['opdracht_id']).isNotEmpty
        ? _text(widget.planningItem['opdracht_id'])
        : (embed is Map ? _text(embed['id']) : '');
  }

  String _safeTime(dynamic v) {
    final t = _text(v);
    if (t.length >= 5) return t.substring(0, 5);
    return t.isEmpty ? '--:--' : t;
  }

  Future<void> _loadTaken() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final oId = _opdrachtId();
      if (oId.isEmpty) throw Exception('Geen opdracht gekoppeld.');
      final list = await fetchWerkprogrammaTaken(oId);
      if (!mounted) return;
      setState(() {
        _taken = list;
        _checked.clear();
        for (final t in list) {
          _checked[t.key] = false;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  bool get _allChecked =>
      _taken.isNotEmpty && _taken.every((t) => _checked[t.key] == true);

  void _toggleSelectAll(bool? value) {
    final v = value ?? false;
    setState(() {
      for (final t in _taken) {
        _checked[t.key] = v;
      }
    });
  }

  void _toggleTaak(String key, bool? value) {
    setState(() => _checked[key] = value ?? false);
  }

  Future<void> _indienen() async {
    if (!_allChecked || _submitting) return;
    final planningId = _planningId();
    final opdrachtId = _opdrachtId();
    if (planningId.isEmpty || opdrachtId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Planning of opdracht ontbreekt.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _repository.markPlanningAndOpdrachtAfgerond(
        planningId: planningId,
        opdrachtId: opdrachtId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCompleted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Afronden mislukt: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.planningItem;
    final start = _safeTime(item['rooster_starttijd'] ?? item['starttijd']);
    final eind = _safeTime(item['rooster_eindtijd'] ?? item['eindtijd']);
    final datum = _text(item['geplande_datum']);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Opdracht afronden',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _submitting ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _loadError != null
                        ? Center(child: Text(_loadError!))
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Klantgegevens',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const Divider(height: 20),
                                      _infoRow(
                                        'Klant',
                                        _text(item['bedrijfsnaam']).isEmpty
                                            ? 'Onbekend'
                                            : _text(item['bedrijfsnaam']),
                                      ),
                                      _infoRow(
                                        'Adres',
                                        _text(item['uitvoer_adres_volledig'])
                                                .isEmpty
                                            ? 'Adres onbekend'
                                            : _text(
                                                item['uitvoer_adres_volledig'],
                                              ),
                                      ),
                                      _infoRow('Datum', datum),
                                      _infoRow('Tijdslot', '$start – $eind'),
                                      _infoRow(
                                        'Project',
                                        _text(item['project_naam']).isEmpty
                                            ? '—'
                                            : _text(item['project_naam']),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'Uit te voeren diensten',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        title: Text(
                                          'Selecteer alles',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        value: _allChecked,
                                        tristate: true,
                                        onChanged: _taken.isEmpty
                                            ? null
                                            : _toggleSelectAll,
                                      ),
                                      const Divider(height: 8),
                                      Expanded(
                                        child: _taken.isEmpty
                                            ? Center(
                                                child: Text(
                                                  'Geen diensten gevonden in het werkprogramma.',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              )
                                            : ListView.builder(
                                                itemCount: _taken.length,
                                                itemBuilder: (context, i) {
                                                  final t = _taken[i];
                                                  return CheckboxListTile(
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    controlAffinity:
                                                        ListTileControlAffinity
                                                            .leading,
                                                    title: Text(
                                                      t.taakNaam,
                                                      style: GoogleFonts.inter(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    subtitle: Text(
                                                      t.ruimteLabel,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors
                                                            .grey.shade600,
                                                      ),
                                                    ),
                                                    value:
                                                        _checked[t.key] ==
                                                            true,
                                                    onChanged: (v) =>
                                                        _toggleTaak(
                                                          t.key,
                                                          v,
                                                        ),
                                                  );
                                                },
                                              ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 48,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.green.shade700,
                                            foregroundColor: Colors.white,
                                            disabledBackgroundColor:
                                                Colors.grey.shade300,
                                          ),
                                          onPressed: _allChecked && !_submitting
                                              ? _indienen
                                              : null,
                                          icon: _submitting
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Icon(Icons.check_circle),
                                          label: Text(
                                            'Indienen & uren invullen',
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w800,
                                            ),
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
            ],
          ),
        ),
      ),
    );
  }
}
