import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class InvoiceDataTable extends StatelessWidget {
  const InvoiceDataTable({
    super.key,
    required this.invoices,
    required this.isLoading,
    required this.totalItems,
    required this.currentPage,
    required this.itemsPerPage,
    required this.onPageChanged,
    required this.onRowTap,
  });

  final List<dynamic> invoices;
  final bool isLoading;
  final int totalItems;
  final int currentPage;
  final int itemsPerPage;
  final Function(int) onPageChanged;
  final Function(String) onRowTap;

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

  @override
  Widget build(BuildContext context) {
    final eur = NumberFormat.currency(locale: 'nl_NL', symbol: '€');
    final dateFmt = DateFormat('dd-MM-yyyy');

    final start = totalItems == 0 ? 0 : (currentPage * itemsPerPage) + 1;
    final end = math.min((currentPage + 1) * itemsPerPage, totalItems);

    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          headingRowColor: const WidgetStatePropertyAll(Color(0xFFE9ECEF)),
                          columnSpacing: 24,
                          horizontalMargin: 12,
                          headingRowHeight: 36,
                          dataRowMinHeight: 34,
                          dataRowMaxHeight: 40,
                          columns: const [
                            DataColumn(label: SizedBox(width: 28, child: Text(''))),
                            DataColumn(label: Text('Ordernummer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                            DataColumn(label: Text('Omschrijving', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                            DataColumn(label: Text('Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                            DataColumn(label: Text('Factuur voor', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                            DataColumn(label: Text('Val.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                            DataColumn(label: Text('Bedrag', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                            DataColumn(label: Text('Bedrag + Btw', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                            DataColumn(label: Text('Orderdatum', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                          ],
                          rows: invoices.map((raw) {
                            final inv = (raw as Map).map((k, v) => MapEntry(k.toString(), v));
                            final id = _text(inv['id']);
                            final orderNr = _text(inv['order_nummer']);
                            final oms = _text(inv['omschrijving']);
                            final type = _text(inv['type']);
                            final date = _asDate(inv['factuur_datum']);
                            final bedrag = _asDouble(inv['totaal_ex_btw']);
                            final bedragInc = _asDouble(inv['totaal_inc_btw']);
                            final bedrijfName = (inv['bedrijven'] is Map)
                                ? _text((inv['bedrijven'] as Map)['bedrijfsnaam'])
                                : '';

                            return DataRow(
                              onSelectChanged: (_) {
                                if (id.isEmpty) return;
                                onRowTap(id);
                              },
                              cells: [
                                const DataCell(SizedBox(width: 28, child: Checkbox(value: false, onChanged: null))),
                                DataCell(Text(orderNr.isEmpty ? '—' : orderNr, style: const TextStyle(fontSize: 13))),
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 320),
                                    child: Text(
                                      oms.isEmpty ? '—' : oms,
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(Text(type.isEmpty ? '—' : type, style: const TextStyle(fontSize: 13))),
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 280),
                                    child: Text(
                                      bedrijfName.isEmpty ? '—' : bedrijfName,
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const DataCell(Text('EUR', style: TextStyle(fontSize: 13))),
                                DataCell(Text(eur.format(bedrag), style: const TextStyle(fontSize: 13))),
                                DataCell(Text(eur.format(bedragInc), style: const TextStyle(fontSize: 13))),
                                DataCell(Text(date == null ? '—' : dateFmt.format(date), style: const TextStyle(fontSize: 13))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade300, width: 1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('$start-$end van $totalItems', style: const TextStyle(fontSize: 13)),
                  IconButton(
                    onPressed: (isLoading || currentPage <= 0) ? null : () => onPageChanged(currentPage - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    onPressed: (isLoading || (currentPage + 1) * itemsPerPage >= totalItems)
                        ? null
                        : () => onPageChanged(currentPage + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

