import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';

class InvoiceBulkRunScreen extends StatefulWidget {
  const InvoiceBulkRunScreen({super.key});

  @override
  State<InvoiceBulkRunScreen> createState() => _InvoiceBulkRunScreenState();
}

class _InvoiceBulkRunScreenState extends State<InvoiceBulkRunScreen> {
  bool _running = false;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      helpText: 'Selecteer een datum in de maand',
      cancelText: 'Annuleren',
      confirmText: 'Kiezen',
    );
    if (picked == null || !mounted) return;
    setState(() => _month = DateTime(picked.year, picked.month, 1));
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final yearMonth = DateFormat('yyyy-MM').format(_month);
      final res = await AppSupabase.client.rpc(
        'genereer_maandelijkse_facturatie_run',
        params: {'p_jaar_maand': yearMonth},
      );
      final msg = (res ?? '').toString().trim();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.92),
          content: Text(msg.isEmpty ? 'Facturatie-run voltooid.' : msg),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Fout bij genereren: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy', 'nl_NL').format(_month);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Bulk Facturatie Run'),
      ),
      body: SelectionArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Maandelijkse facturatie-run',
                        style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Genereert conceptfacturen voor actieve contracten in de geselecteerde maand.',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _running ? null : _pickMonth,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(
                              monthLabel,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _running ? null : _run,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: _running
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow, size: 18),
                            label: Text(
                              _running ? 'Bezig…' : 'Run uitvoeren',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

