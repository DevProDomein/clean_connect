import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/supabase_client.dart';

class InvoiceFilters {
  final String? bedrijfId;
  final String? bedrijfsnaam;
  final String ordernummer;
  final String artikel;
  final bool typeFactuur;
  final bool typeCreditnota;
  final bool statusOpen;
  final bool statusVerwerkt;
  final DateTime? startDate;
  final DateTime? endDate;

  InvoiceFilters({
    this.bedrijfId,
    this.bedrijfsnaam,
    this.ordernummer = '',
    this.artikel = '',
    this.typeFactuur = true,
    this.typeCreditnota = true,
    this.statusOpen = true,
    this.statusVerwerkt = false,
    this.startDate,
    this.endDate,
  });
}

class InvoiceFilterBar extends StatefulWidget {
  const InvoiceFilterBar({super.key, required this.onApply});

  final Function(InvoiceFilters) onApply;

  @override
  State<InvoiceFilterBar> createState() => _InvoiceFilterBarState();
}

class _InvoiceFilterBarState extends State<InvoiceFilterBar> {
  bool _showFilters = true;

  String? _bedrijfId;
  String? _bedrijfsnaam;
  String _ordernummer = '';
  String _artikel = '';

  bool _typeFactuur = true;
  bool _typeCreditnota = true;
  bool _statusOpen = true;
  bool _statusVerwerkt = false;

  DateTime? _startDate;
  DateTime? _endDate;

  final _relatieCtrl = TextEditingController();
  final _ordernummerCtrl = TextEditingController();
  final _artikelCtrl = TextEditingController();

  List<Map<String, dynamic>> _bedrijfOptions = const [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _relatieCtrl.dispose();
    _ordernummerCtrl.dispose();
    _artikelCtrl.dispose();
    super.dispose();
  }

  InputDecoration _denseDeco(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      prefixIcon: icon == null ? null : Icon(icon, size: 16),
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        borderSide: BorderSide(color: Color(0xFF0052CC), width: 1),
      ),
    );
  }

  Future<void> _fetchBedrijven(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() => _bedrijfOptions = const []);
      return;
    }

    try {
      final res = await AppSupabase.client
          .from('bedrijven')
          .select('id, bedrijfsnaam')
          .ilike('bedrijfsnaam', '%$query%')
          .limit(10);

      final items = (res as List)
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .where((e) => (e['bedrijfsnaam'] ?? '').toString().trim().isNotEmpty)
          .cast<Map<String, dynamic>>()
          .toList();

      if (!mounted) return;
      setState(() => _bedrijfOptions = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _bedrijfOptions = const []);
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (!mounted || picked == null) return;
    setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (!mounted || picked == null) return;
    setState(() => _endDate = picked);
  }

  Widget _dateField(String label, DateTime? value, VoidCallback onTap) {
    final txt = value == null
        ? '—'
        : '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: _denseDeco(label),
        child: Text(txt, style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F7),
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: () {
                    widget.onApply(
                      InvoiceFilters(
                        bedrijfId: _bedrijfId,
                        bedrijfsnaam: _bedrijfsnaam,
                        ordernummer: _ordernummer,
                        artikel: _artikel,
                        typeFactuur: _typeFactuur,
                        typeCreditnota: _typeCreditnota,
                        statusOpen: _statusOpen,
                        statusVerwerkt: _statusVerwerkt,
                        startDate: _startDate,
                        endDate: _endDate,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0052CC),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    minimumSize: const Size(100, 36),
                    elevation: 0,
                  ),
                  child: const Text('Toepassen', style: TextStyle(fontSize: 13)),
                ),
                TextButton(
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                  child: Text(
                    _showFilters ? 'Filters verbergen ^' : 'Filters tonen v',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF0052CC)),
                  ),
                ),
              ],
            ),
          ),
          if (_showFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 24,
                runSpacing: 16,
                children: [
                  // Group 1: Relatie
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Relatie', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 4),
                        Autocomplete<Map<String, dynamic>>(
                          displayStringForOption: (o) => (o['bedrijfsnaam'] ?? '').toString(),
                          optionsBuilder: (TextEditingValue t) {
                            final q = t.text.trim().toLowerCase();
                            if (q.isEmpty) return const Iterable<Map<String, dynamic>>.empty();
                            return _bedrijfOptions.where((o) {
                              final name = (o['bedrijfsnaam'] ?? '').toString().toLowerCase();
                              return name.contains(q);
                            });
                          },
                          onSelected: (selection) {
                            setState(() {
                              _bedrijfId = selection['id']?.toString();
                              _bedrijfsnaam = selection['bedrijfsnaam']?.toString();
                              _relatieCtrl.text = _bedrijfsnaam ?? '';
                            });
                          },
                          fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                            if (controller.text != _relatieCtrl.text) {
                              controller.value = _relatieCtrl.value;
                            }
                            return TextField(
                              controller: _relatieCtrl,
                              focusNode: focusNode,
                              onEditingComplete: onEditingComplete,
                              style: const TextStyle(fontSize: 13),
                              decoration: _denseDeco('Relatie (Zoek in database...)', icon: Icons.search),
                              onChanged: (v) {
                                setState(() {
                                  _bedrijfId = null;
                                  _bedrijfsnaam = v.trim().isEmpty ? null : v;
                                });
                                _debounce?.cancel();
                                _debounce = Timer(const Duration(milliseconds: 250), () {
                                  _fetchBedrijven(v);
                                });
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // Group 2: Type & Ordernummer
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _typeFactuur,
                              visualDensity: VisualDensity.compact,
                              onChanged: (v) => setState(() => _typeFactuur = v ?? false),
                            ),
                            const Text('Factuur', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 10),
                            Checkbox(
                              value: _typeCreditnota,
                              visualDensity: VisualDensity.compact,
                              onChanged: (v) => setState(() => _typeCreditnota = v ?? false),
                            ),
                            const Text('Creditnota', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _ordernummerCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: _denseDeco('Ordernummer'),
                          onChanged: (v) => _ordernummer = v,
                        ),
                      ],
                    ),
                  ),

                  // Group 3: Artikel & Status
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _artikelCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: _denseDeco('Artikel', icon: Icons.search),
                          onChanged: (v) => _artikel = v,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Checkbox(
                              value: _statusOpen,
                              visualDensity: VisualDensity.compact,
                              onChanged: (v) => setState(() => _statusOpen = v ?? false),
                            ),
                            const Text('Open', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 10),
                            Checkbox(value: false, onChanged: null, visualDensity: VisualDensity.compact),
                            const Text('Verwerken...', style: TextStyle(fontSize: 13, color: Colors.black45)),
                            const SizedBox(width: 10),
                            Checkbox(
                              value: _statusVerwerkt,
                              visualDensity: VisualDensity.compact,
                              onChanged: (v) => setState(() => _statusVerwerkt = v ?? false),
                            ),
                            const Text('Verwerkt', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Group 4: Orderdatum
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Orderdatum', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(child: _dateField('Start', _startDate, _pickStartDate)),
                            const SizedBox(width: 8),
                            Expanded(child: _dateField('Eind', _endDate, _pickEndDate)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

