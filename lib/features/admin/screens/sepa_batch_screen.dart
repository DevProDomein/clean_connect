import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_saver/file_saver.dart';
import 'package:provider/provider.dart';
import 'package:xml/xml.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import '../../../core/models/user_role.dart';

class SepaBatchScreen extends StatefulWidget {
  const SepaBatchScreen({super.key});

  @override
  State<SepaBatchScreen> createState() => _SepaBatchScreenState();
}

class _SepaBatchScreenState extends State<SepaBatchScreen> {
  Future<_SepaData>? _future;
  final Set<String> _selectedIds = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_SepaData> _fetch() async {
    final exportRes = await AppSupabase.client.from('app_sepa_export_lijst').select();
    final exportRows = (exportRes as List).cast<Map<String, dynamic>>();
    return _SepaData(exportRows: exportRows);
  }

  void _refresh() {
    setState(() {
      _future = _fetch();
    });
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  NumberFormat _eur() => NumberFormat.currency(locale: 'nl_NL', symbol: '€', decimalDigits: 2);

  double _totalSelected(List<Map<String, dynamic>> rows) {
    double sum = 0;
    for (final r in rows) {
      final id = _text(r['id'] ?? r['factuur_id']);
      if (!_selectedIds.contains(id)) continue;
      sum += _asDouble(r['incasso_bedrag'] ?? r['totaal_inc_btw'] ?? r['bedrag'] ?? r['openstaand_saldo']);
    }
    return sum;
  }

  Future<void> _generateBatch(List<Map<String, dynamic>> rows) async {
    if (_busy) return;
    final selected = rows.where((r) {
      final id = _text(r['id'] ?? r['factuur_id']);
      return _selectedIds.contains(id);
    }).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: const Text('Selecteer minimaal 1 factuur.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final selectedTotal = _totalSelected(rows);
      final batchKenmerk = 'BATCH-${DateTime.now().millisecondsSinceEpoch}';
      final batchRow = await AppSupabase.client
          .from('sepa_incasso_batches')
          .insert({
            'batch_kenmerk': batchKenmerk,
            'status': 'aangemaakt',
            'totaal_bedrag': selectedTotal,
            'aantal_facturen': selected.length,
          })
          .select('id')
          .maybeSingle();
      final batchId = _text(batchRow?['id']);
      if (batchId.isEmpty) throw StateError('Kon batch niet aanmaken.');

      for (final r in selected) {
        final id = _text(r['id'] ?? r['factuur_id']);
        if (id.isEmpty) continue;
        await AppSupabase.client
            .from('facturen')
            .update({'sepa_batch_id': batchId, 'status': 'betaald'})
            .eq('id', id);
      }

      final xml = _buildPain008Xml(batchId: batchId, rows: selected);
      final bytes = Uint8List.fromList(xml.codeUnits);
      await FileSaver.instance.saveFile(
        name: 'SEPA_Batch',
        bytes: bytes,
        ext: 'xml',
        mimeType: MimeType.custom,
        customMimeType: 'application/xml',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.92),
          content: const Text('SEPA Batch succesvol gegenereerd en gedownload.'),
        ),
      );
      _selectedIds.clear();
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon batch niet genereren: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _buildPain008Xml({
    required String batchId,
    required List<Map<String, dynamic>> rows,
  }) {
    final msgId = 'BATCH-$batchId';
    final created = DateTime.now().toUtc().toIso8601String();
    final ctrlSum = rows.fold<double>(
      0,
      (acc, r) => acc + _asDouble(r['incasso_bedrag'] ?? r['totaal_inc_btw'] ?? r['bedrag'] ?? r['openstaand_saldo']),
    );

    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'Document',
      namespaces: {'': 'urn:iso:std:iso:20022:tech:xsd:pain.008.001.02'},
      nest: () {
        builder.element('CstmrDrctDbtInitn', nest: () {
          builder.element('GrpHdr', nest: () {
            builder.element('MsgId', nest: msgId);
            builder.element('CreDtTm', nest: created);
            builder.element('NbOfTxs', nest: rows.length.toString());
            builder.element('CtrlSum', nest: ctrlSum.toStringAsFixed(2));
          });

          builder.element('PmtInf', nest: () {
            builder.element('PmtInfId', nest: msgId);
            builder.element('PmtMtd', nest: 'DD');
            builder.element(
              'ReqdColltnDt',
              nest: DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 2))),
            );

            for (final r in rows) {
              final factuurnr = _text(r['factuur_nummer']).isEmpty
                  ? _text(r['id'] ?? r['factuur_id'])
                  : _text(r['factuur_nummer']);
              final amount = _asDouble(
                r['incasso_bedrag'] ?? r['totaal_inc_btw'] ?? r['bedrag'] ?? r['openstaand_saldo'],
              );
              final iban = _text(r['iban'] ?? r['debiteur_iban'] ?? r['rekening_iban']);
              final mandate = _text(r['sepa_mandaat_id'] ?? r['mandaat_id'] ?? r['mandate_id']);

              builder.element('DrctDbtTxInf', nest: () {
                builder.element('PmtId', nest: () {
                  builder.element('EndToEndId', nest: factuurnr);
                });
                builder.element('InstdAmt', attributes: {'Ccy': 'EUR'}, nest: amount.toStringAsFixed(2));
                builder.element('DrctDbtTx', nest: () {
                  builder.element('MndtRltdInf', nest: () {
                    builder.element('MndtId', nest: mandate.isEmpty ? '—' : mandate);
                  });
                });
                builder.element('DbtrAcct', nest: () {
                  builder.element('Id', nest: () {
                    builder.element('IBAN', nest: iban.isEmpty ? '—' : iban);
                  });
                });
              });
            }
          });
        });
      },
    );

    final doc = builder.buildDocument();
    return doc.toXmlString(pretty: true, indent: '  ');
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canView = up.hasPermission('finance') || up.role == UserRole.administrator || up.role == UserRole.generator;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    if (!canView) {
      return Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(
            'SEPA Incasso',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
        ),
        body: const Center(child: Text('Geen toegang.')),
      );
    }

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'SEPA Incasso',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(tooltip: 'Vernieuwen', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<_SepaData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: softBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                ),
                child: Text('Kan SEPA data niet laden: ${snapshot.error}'),
              ),
            );
          }

          final data = snapshot.data!;
          final total = _totalSelected(data.exportRows);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 120),
                  children: [
                    Text(
                      'Incasso Batch',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (data.exportRows.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: softBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                        ),
                        child: Text(
                          'Geen facturen beschikbaar voor SEPA export.',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      ...data.exportRows.map((r) {
                        final id = _text(r['id'] ?? r['factuur_id']);
                        final bedrijfsnaam = _text(r['bedrijfsnaam'] ?? r['debiteur_naam'] ?? r['klant_naam']);
                        final nr = _text(r['factuur_nummer']);
                        final iban = _text(r['iban'] ?? r['debiteur_iban'] ?? r['rekening_iban']);
                        final amt = _asDouble(r['incasso_bedrag'] ?? r['totaal_inc_btw'] ?? r['openstaand_saldo']);
                        final checked = _selectedIds.contains(id);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: tileBg,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 20,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: CheckboxListTile(
                            value: checked,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedIds.add(id);
                                } else {
                                  _selectedIds.remove(id);
                                }
                              });
                            },
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            title: Text(
                              bedrijfsnaam.isEmpty ? 'Onbekend bedrijf' : bedrijfsnaam,
                              style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Factuur: ${nr.isEmpty ? '—' : nr}',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface.withValues(alpha: 0.70),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'IBAN: ${iban.isEmpty ? '—' : iban}',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface.withValues(alpha: 0.65),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            secondary: Text(
                              _eur().format(amt),
                              style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
              SafeArea(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0912),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Totaal geselecteerd bedrag',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                          ),
                          Text(
                            _eur().format(total),
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : () => _generateBatch(data.exportRows),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                          ),
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.download_rounded),
                          label: Text(
                            'Genereer SEPA XML Batch',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SepaData {
  const _SepaData({required this.exportRows});

  final List<Map<String, dynamic>> exportRows;
}

