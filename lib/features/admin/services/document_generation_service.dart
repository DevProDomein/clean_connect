import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';

class DocumentGenerationService {
  static Future<Uint8List> generateInvoicePdf(
    Map<String, dynamic> invoice,
    List<dynamic> lines,
    Map<String, dynamic> appSettings,
  ) async {
    final cfg = appSettings;

    final primaryHex = (cfg['primaire_kleur_hex'] ?? '#FF6B35').toString().trim();
    final primary = _pdfColorFromHex(primaryHex) ?? PdfColor.fromInt(0xFFFF6B35);

    final companyName = (cfg['bedrijfsnaam'] ?? cfg['company_name'] ?? '').toString().trim();
    final companyAddress = (cfg['adres'] ?? cfg['address'] ?? '').toString().trim();

    final factuurnr = (invoice['factuur_nummer'] ?? invoice['invoice_number'] ?? '').toString().trim();
    final status = (invoice['status'] ?? '').toString().trim();
    final factuurDatum = _asDate(invoice['factuur_datum'] ?? invoice['datum'] ?? invoice['issue_date']);

    final debiteurNaam = (invoice['debiteur_naam'] ?? invoice['client_name'] ?? '').toString().trim();
    final straat = (invoice['debiteur_adres_straat'] ?? '').toString().trim();
    final postcode = (invoice['debiteur_adres_postcode'] ?? invoice['debiteur_postcode'] ?? '').toString().trim();
    final stad = (invoice['debiteur_adres_stad'] ?? invoice['debiteur_stad'] ?? '').toString().trim();
    final debiteurBtw = (invoice['debiteur_btw_nummer'] ?? '').toString().trim();

    final debiteurAdres = [
      straat,
      [postcode, stad].where((e) => e.isNotEmpty).join(' '),
    ].where((e) => e.trim().isNotEmpty).join('\n');

    final btwVerlegd = _asBool(invoice['btw_verlegd']);
    final subtotal = _asDouble(invoice['totaal_ex_btw'] ?? invoice['subtotaal_ex_btw']);
    final vatRaw = _asDouble(invoice['totaal_btw'] ?? invoice['btw_bedrag']);
    final total = _asDouble(invoice['totaal_inc_btw']);
    final vat = btwVerlegd ? 0.0 : vatRaw;

    final gPercentage = _asDouble(invoice['g_rekening_percentage']);

    final epcData = _mockEpcPaymentString(
      creditorName: companyName.isEmpty ? 'CleanConnect' : companyName,
      iban: (cfg['iban'] ?? cfg['IBAN'] ?? 'NL00BANK0123456789').toString().trim(),
      amountEur: total,
      remittance: factuurnr.isEmpty ? 'FACTUUR' : factuurnr,
    );

    final doc = pw.Document();
    final watermarkText = status.trim().toLowerCase() == 'concept' ? 'CONCEPT - NIET BETALEN' : null;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
        build: (context) {
          final content = <pw.Widget>[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        companyName.isEmpty ? 'Bedrijf' : companyName,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: primary,
                        ),
                      ),
                      if (companyAddress.isNotEmpty) ...[
                        pw.SizedBox(height: 6),
                        pw.Text(companyAddress, style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.circular(10),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'FACTUUR',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      _kvRow('Factuurnummer', factuurnr.isEmpty ? 'Concept' : factuurnr),
                      _kvRow('Factuurdatum', _fmtDateNl(factuurDatum)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Factuur aan', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                  pw.Text(debiteurNaam.isEmpty ? 'Onbekende Klant' : debiteurNaam),
                  if (debiteurAdres.isNotEmpty) pw.Text(debiteurAdres),
                  if (btwVerlegd && debiteurBtw.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'BTW-nummer klant: $debiteurBtw',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2), // artikel
                1: const pw.FlexColumnWidth(3.2), // omschrijving
                2: const pw.FlexColumnWidth(1.0), // aantal
                3: const pw.FlexColumnWidth(1.4), // stukprijs
                4: const pw.FlexColumnWidth(1.0), // btw
                5: const pw.FlexColumnWidth(1.6), // totaal
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: primary),
                  children: [
                    _th('Artikel'),
                    _th('Omschrijving'),
                    _th('Aantal', alignRight: true),
                    _th('Stukprijs', alignRight: true),
                    _th('BTW', alignRight: true),
                    _th('Totaal', alignRight: true),
                  ],
                ),
                ...lines.map((raw) {
                  final r = (raw is Map) ? raw : const <String, dynamic>{};
                  final code = (r['artikel_code'] ?? r['artikel'] ?? '').toString().trim();
                  final oms = (r['omschrijving'] ?? r['beschrijving'] ?? '').toString().trim();
                  final aantal = _asDouble(r['aantal']);
                  final stuk = _asDouble(r['stukprijs_ex_btw'] ?? r['prijs_ex_btw']);
                  final btw = (r['btw_code'] ?? r['btw_percentage'] ?? '').toString().trim();
                  final regelTotaal = _asDouble(r['regel_totaal_ex_btw'] ?? r['totaal_ex_btw'] ?? (aantal * stuk));

                  return pw.TableRow(
                    children: [
                      _td(code.isEmpty ? '—' : code),
                      _td(oms.isEmpty ? '—' : oms),
                      _td(_fmtQty(aantal), alignRight: true),
                      _td(_fmtEur(stuk), alignRight: true),
                      _td(btwVerlegd ? '0%' : (btw.isEmpty ? '—' : btw), alignRight: true),
                      _td(_fmtEur(regelTotaal), alignRight: true),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 270,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    if (btwVerlegd)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 8),
                        child: pw.Text(
                          'Btw verlegd o.g.v. art. 24 lid 1 sub b Wet OB.',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                      ),
                    _sumRow('Subtotaal', _fmtEur(subtotal)),
                    _sumRow('BTW', _fmtEur(vat)),
                    pw.Divider(color: PdfColors.grey400),
                    _sumRow('Totaal incl. BTW', _fmtEur(total), bold: true),
                    if (btwVerlegd && gPercentage > 0) ...[
                      pw.SizedBox(height: 8),
                      pw.Divider(color: PdfColors.grey300),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'G-Rekening split',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 6),
                      _sumRow(
                        'Waarvan naar G-Rekening (${gPercentage.toStringAsFixed(2)}%)',
                        _fmtEur(total * (gPercentage / 100.0)),
                      ),
                      _sumRow(
                        'Waarvan naar Reguliere Rekening',
                        _fmtEur(total - (total * (gPercentage / 100.0))),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Betalen',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'Scan de QR-code (EPC/iDEAL mock) voor betaling.',
                          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: epcData,
                    width: 92,
                    height: 92,
                    drawText: false,
                  ),
                ],
              ),
            ),
          ];

          return [
            pw.Stack(
              children: [
                pw.Column(children: content),
                if (watermarkText != null) _buildWatermarkOverlay(watermarkText),
              ],
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  static String generateUblXml(
    Map<String, dynamic> invoice,
    List<dynamic> lines,
    Map<String, dynamic> appSettings,
  ) {
    final id = (invoice['factuur_nummer'] ?? invoice['invoice_number'] ?? '').toString().trim();
    final issueDate = _asDate(invoice['factuur_datum'] ?? invoice['datum']);
    final companyName = (appSettings['bedrijfsnaam'] ?? '').toString().trim();
    final customerName = (invoice['debiteur_naam'] ?? '').toString().trim();

    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');

    builder.element(
      'Invoice',
      namespaces: {
        'cbc': 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2',
        'cac': 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2',
      },
      nest: () {
        builder.element('cbc:ID', nest: id.isEmpty ? 'CONCEPT' : id);
        builder.element('cbc:IssueDate', nest: _fmtIsoDate(issueDate));

        builder.element('cac:AccountingSupplierParty', nest: () {
          builder.element('cac:Party', nest: () {
            builder.element('cac:PartyName', nest: () {
              builder.element('cbc:Name', nest: companyName.isEmpty ? 'Bedrijf' : companyName);
            });
          });
        });

        builder.element('cac:AccountingCustomerParty', nest: () {
          builder.element('cac:Party', nest: () {
            builder.element('cac:PartyName', nest: () {
              builder.element('cbc:Name', nest: customerName.isEmpty ? 'Klant' : customerName);
            });
          });
        });

        var lineNo = 1;
        for (final raw in lines) {
          final r = (raw is Map) ? raw : const <String, dynamic>{};
          final desc = (r['omschrijving'] ?? r['beschrijving'] ?? '').toString().trim();
          final qty = _asDouble(r['aantal']);
          final price = _asDouble(r['stukprijs_ex_btw'] ?? r['prijs_ex_btw']);

          builder.element('cac:InvoiceLine', nest: () {
            builder.element('cbc:ID', nest: '$lineNo');
            builder.element('cbc:InvoicedQuantity', nest: qty.toStringAsFixed(2));
            builder.element('cac:Item', nest: () {
              builder.element('cbc:Description', nest: desc.isEmpty ? '—' : desc);
            });
            builder.element('cac:Price', nest: () {
              builder.element('cbc:PriceAmount', nest: price.toStringAsFixed(2));
            });
          });
          lineNo += 1;
        }
      },
    );

    final doc = builder.buildDocument();
    return doc.toXmlString(pretty: true, indent: '  ');
  }

  static pw.Widget _buildWatermarkOverlay(String text) {
    return pw.Positioned.fill(
      child: pw.Center(
        child: pw.Opacity(
          opacity: 0.22,
          child: pw.Transform.rotate(
            angle: -math.pi / 4,
            child: pw.Text(
              text,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 52,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static pw.Widget _kvRow(String k, String v) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Text(
              v,
              textAlign: pw.TextAlign.right,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _th(String t, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.Text(
        t,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  static pw.Widget _td(String t, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(
        t,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: const pw.TextStyle(fontSize: 9),
      ),
    );
  }

  static pw.Widget _sumRow(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0.0;
  }

  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'ja';
  }

  static DateTime? _asDate(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  static String _fmtDateNl(DateTime? d) {
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd-$mm-${d.year}';
  }

  static String _fmtIsoDate(DateTime? d) {
    if (d == null) return DateTime.now().toIso8601String().split('T').first;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  static String _fmtQty(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  static String _fmtEur(double v) {
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    return '€ $s';
  }

  static String _mockEpcPaymentString({
    required String creditorName,
    required String iban,
    required double amountEur,
    required String remittance,
  }) {
    // EPC069-12 (simplified mock). Good enough for testing QR rendering.
    final amt = amountEur <= 0 ? 'EUR0.00' : 'EUR${amountEur.toStringAsFixed(2)}';
    final safeName = creditorName.replaceAll('\n', ' ').trim();
    final safeRem = remittance.replaceAll('\n', ' ').trim();
    return [
      'BCD',
      '001',
      '1',
      'SCT',
      '', // BIC optional
      safeName,
      iban,
      amt,
      '', // purpose
      safeRem, // remittance
      '', // information
    ].join('\n');
  }

  static PdfColor? _pdfColorFromHex(String hex) {
    var h = hex.trim();
    if (h.isEmpty) return null;
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 3) {
      h = '${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}';
    }
    if (h.length == 8) {
      h = h.substring(2); // drop alpha
    }
    if (h.length != 6) return null;
    final rgb = int.tryParse(h, radix: 16);
    if (rgb == null) return null;
    final r = ((rgb >> 16) & 0xFF) / 255.0;
    final g = ((rgb >> 8) & 0xFF) / 255.0;
    final b = (rgb & 0xFF) / 255.0;
    return PdfColor(r, g, b);
  }

  static Map<String, dynamic> coerceSettingsValue(dynamic raw) {
    if (raw == null) return const <String, dynamic>{};
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    if (raw is String) {
      final t = raw.trim();
      if (t.isEmpty) return const <String, dynamic>{};
      final decoded = jsonDecode(t);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, dynamic>{};
  }
}

