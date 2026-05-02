import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/supabase_client.dart';
import '../services/pdf_invoice_service.dart';
import 'factuur_editor_screen.dart';

class InvoiceHistoryScreen extends StatefulWidget {
  const InvoiceHistoryScreen({super.key});

  @override
  State<InvoiceHistoryScreen> createState() => _InvoiceHistoryScreenState();
}

class _InvoiceHistoryScreenState extends State<InvoiceHistoryScreen> {
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();
  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  DateTime? _asDate(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final res = await AppSupabase.client
        .from('facturen')
        .select('id, factuur_nummer, omschrijving, bedrijf_id, factuur_datum, totaal_inc_btw, status, bedrijven(bedrijfsnaam)')
        .neq('status', 'concept')
        .order('factuur_datum', ascending: false);
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> _previewPdf(String invoiceId) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
            child: PdfPreview(
              build: (format) => PdfInvoiceService.generateInvoicePdf(invoiceId),
              allowPrinting: true,
              allowSharing: true,
              canChangePageFormat: false,
              canChangeOrientation: false,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd-MM-yyyy');
    final eur = NumberFormat.currency(locale: 'nl_NL', symbol: '€');

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: const Text('Factuurhistorie'),
        leading: const BackButton(),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: () => setState(() => _future = _fetch()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text('Error: ${snapshot.error}'),
              ),
            );
          }

          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return const Center(
              child: Text('Geen facturen gevonden.', style: TextStyle(fontSize: 13)),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 34,
                  dataRowMinHeight: 34,
                  dataRowMaxHeight: 44,
                  horizontalMargin: 12,
                  columnSpacing: 14,
                  headingRowColor: WidgetStatePropertyAll(const Color(0xFFE9ECEF)),
                  columns: const [
                    DataColumn(label: SizedBox(width: 28, child: Text(''))),
                    DataColumn(label: Text('Factuurnummer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('Omschrijving', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('Factuur voor', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('Factuurdatum', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('Bedrag', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('Uitvoer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('Track', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                  ],
                  rows: List.generate(items.length, (i) {
                    final inv = items[i];
                    final id = _text(inv['id']);
                    final nr = _text(inv['factuur_nummer']);
                    final oms = _text(inv['omschrijving']);
                    final bedrijfId = _text(inv['bedrijf_id']);
                    final bedrijfName = (inv['bedrijven'] is Map) ? _text((inv['bedrijven'] as Map)['bedrijfsnaam']) : '';
                    final date = _asDate(inv['factuur_datum']);
                    final bedrag = _asDouble(inv['totaal_inc_btw']);

                    final zebra = i.isEven ? Colors.white : const Color(0xFFF7F7F7);
                    return DataRow(
                      color: WidgetStatePropertyAll(zebra),
                      onSelectChanged: (_) {
                        if (id.isEmpty) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => FactuurEditorScreen(invoiceId: id)),
                        );
                      },
                      cells: [
                        const DataCell(SizedBox(width: 28, child: Checkbox(value: false, onChanged: null))),
                        DataCell(Text(nr.isEmpty ? '—' : nr, style: const TextStyle(fontSize: 13))),
                        DataCell(Text(oms.isEmpty ? '—' : oms, style: const TextStyle(fontSize: 13))),
                        DataCell(
                          Text(
                            [bedrijfId, bedrijfName].where((e) => e.trim().isNotEmpty).join(' • '),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        DataCell(Text(date == null ? '—' : dateFmt.format(date), style: const TextStyle(fontSize: 13))),
                        DataCell(Text(eur.format(bedrag), style: const TextStyle(fontSize: 13))),
                        DataCell(
                          IconButton(
                            tooltip: 'PDF',
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                            onPressed: id.isEmpty ? null : () => _previewPdf(id),
                          ),
                        ),
                        const DataCell(
                          Icon(Icons.email_outlined, size: 18, color: Colors.black54),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

