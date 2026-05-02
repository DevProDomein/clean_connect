import 'dart:typed_data';

import 'dart:convert';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/supabase_client.dart';

class PdfInvoiceService {
  static Future<Uint8List> generateInvoicePdf(
    String invoiceId, {
    bool toonAantallen = true,
    bool toonPrijzen = true,
  }) async {
    // --- Fetch data ----------------------------------------------------------
    final invoice = await AppSupabase.client
        .from('facturen')
        .select('*, bedrijven(*)')
        .eq('id', invoiceId)
        .maybeSingle();

    final regelsRes = await AppSupabase.client
        .from('factuur_regels')
        .select()
        .eq('factuur_id', invoiceId)
        .order('volgorde', ascending: true);
    final regels = (regelsRes as List).cast<Map<String, dynamic>>();

    final cfgRow = await AppSupabase.client
        .from(AppSettingsTable.name)
        .select(AppSettingsTable.waarde)
        .eq(AppSettingsTable.sleutel, 'factuur_config')
        .maybeSingle();
    final appSettings =
        _coerceToMap(cfgRow?[AppSettingsTable.waarde]) ?? const <String, dynamic>{};

    // --- Setup document ------------------------------------------------------
    final pdf = pw.Document();
    final primaryColor =
        PdfColor.fromHex(_text(appSettings['primaire_kleur_hex']).isEmpty ? '#1A237E' : _text(appSettings['primaire_kleur_hex']));

    // --- Derive fields -------------------------------------------------------
    final inv = (invoice as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final bedrijf = inv['bedrijven'] is Map ? (inv['bedrijven'] as Map).cast<String, dynamic>() : const <String, dynamic>{};

    final companyName = _text(appSettings['bedrijfsnaam']).isEmpty ? 'Bedrijf' : _text(appSettings['bedrijfsnaam']);
    final companyAddress = _text(appSettings['adres']);
    final companyKvk = _text(appSettings['kvk']);
    final companyIban = _text(appSettings['iban']);

    final debiteurNaam = _text(inv['debiteur_naam']).isNotEmpty
        ? _text(inv['debiteur_naam'])
        : (_text(bedrijf['bedrijfsnaam']).isEmpty ? 'Onbekende Klant' : _text(bedrijf['bedrijfsnaam']));
    final straat = _text(inv['debiteur_adres_straat']);
    final postcode = _text(inv['debiteur_postcode']);
    final stad = _text(inv['debiteur_stad']);
    final debiteurAdres = <String>[
      straat,
      [postcode, stad].where((e) => e.isNotEmpty).join(' '),
    ].where((e) => e.trim().isNotEmpty).toList(growable: false);

    final factuurnr = _text(inv['factuur_nummer']);
    final factuurDatum = _fmtDateNl(_asDate(inv['factuur_datum'] ?? inv['datum']));
    final vervalDatum = _fmtDateNl(_asDate(inv['verval_datum']));

    final subtotal = _asDouble(inv['totaal_ex_btw'] ?? inv['subtotaal_ex_btw']);
    final vat = _asDouble(inv['totaal_btw'] ?? inv['btw_bedrag']);
    final total = _asDouble(inv['totaal_inc_btw']);

    final gRekeningToegepast = _asBool(inv['g_rekening_toegepast']);
    final btwVerlegd = _asBool(inv['btw_verlegd']);

    // Optional layout toggles (kept for editor integration)
    final showQty = toonAantallen;
    final showPrice = toonPrijzen;

    pw.Widget buildHeader() {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(companyName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                if (companyAddress.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(companyAddress, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                ],
                pw.SizedBox(height: 6),
                pw.Row(
                  children: [
                    if (companyKvk.isNotEmpty)
                      pw.Text('KVK: $companyKvk', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    if (companyKvk.isNotEmpty && companyIban.isNotEmpty) pw.SizedBox(width: 12),
                    if (companyIban.isNotEmpty)
                      pw.Text('IBAN: $companyIban', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Container(
            width: 240,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  'FACTUUR',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 26,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                    letterSpacing: 0.5,
                  ),
                ),
                pw.SizedBox(height: 6),
                _kvRow('Factuurnummer', factuurnr.isEmpty ? 'Concept' : factuurnr),
                _kvRow('Factuurdatum', factuurDatum),
                _kvRow('Vervaldatum', vervalDatum),
              ],
            ),
          ),
        ],
      );
    }

    pw.Widget buildClientInfo() {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Factuur aan', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(debiteurNaam, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            if (debiteurAdres.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              ...debiteurAdres.map(
                (l) => pw.Text(l, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              ),
            ],
          ],
        ),
      );
    }

    pw.Widget buildInvoiceTable() {
      final headers = <String>[
        'Omschrijving',
        if (showQty) 'Aantal',
        if (showPrice) 'Prijs',
        'BTW',
        'Totaal',
      ];

      final data = regels.map((r) {
        final oms = _text(r['omschrijving'] ?? r['beschrijving']);
        final qty = _fmtQty(_asDouble(r['aantal']));
        final unit = _fmtEur(_asDouble(r['stukprijs_ex_btw'] ?? r['prijs_ex_btw']));
        final btwCell = _text(r['btw_code']).isNotEmpty
            ? _text(r['btw_code'])
            : (_text(r['btw_percentage']).isNotEmpty ? '${_text(r['btw_percentage'])}%' : '');
        final lineTotal = _fmtEur(
          _asDouble(
            r['regel_totaal_ex_btw'] ??
                r['totaal_ex_btw'] ??
                (_asDouble(r['aantal']) * _asDouble(r['stukprijs_ex_btw'] ?? r['prijs_ex_btw'])),
          ),
        );

        return <String>[
          oms,
          if (showQty) qty,
          if (showPrice) unit,
          btwCell,
          lineTotal,
        ];
      }).toList(growable: false);

      return pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
        headerDecoration: pw.BoxDecoration(color: primaryColor),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          if (showQty) 1: pw.Alignment.centerRight,
          if (showPrice) (showQty ? 2 : 1): pw.Alignment.centerRight,
          (showQty ? (showPrice ? 3 : 2) : (showPrice ? 2 : 1)): pw.Alignment.center,
          (showQty ? (showPrice ? 4 : 3) : (showPrice ? 3 : 2)): pw.Alignment.centerRight,
        },
        border: pw.TableBorder.all(color: PdfColors.grey300),
        headers: headers,
        data: data,
      );
    }

    pw.Widget buildTotals() {
      return pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Container(
          width: 260,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Column(
            children: [
              _kvRow('Subtotaal', _fmtEur(subtotal)),
              _kvRow('BTW', _fmtEur(vat)),
              pw.Divider(color: PdfColors.grey400),
              _kvRow(
                'Totaal te voldoen',
                _fmtEur(total),
                keyStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                valueStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    pw.Widget buildWkaBlock() {
      if (!gRekeningToegepast && !btwVerlegd) return pw.SizedBox.shrink();

      final gAmount = _asDouble(inv['g_rekening_bedrag']);
      final restAmount = _asDouble(inv['rest_bedrag']);

      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('WKA / G-rekening', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            if (gRekeningToegepast) ...[
              _kvRow('Bedrag G-rekening', _fmtEur(gAmount)),
              _kvRow('Resterend bedrag', _fmtEur(restAmount)),
            ],
            if (btwVerlegd) ...[
              pw.SizedBox(height: 6),
              pw.Text(
                'Btw verlegd o.g.v. art. 24 lid 1 sub b Wet OB.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          ],
        ),
      );
    }

    // --- Build page(s) -------------------------------------------------------
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          buildHeader(),
          pw.SizedBox(height: 12),
          buildClientInfo(),
          pw.SizedBox(height: 12),
          buildInvoiceTable(),
          pw.SizedBox(height: 12),
          buildTotals(),
          pw.SizedBox(height: 12),
          buildWkaBlock(),
        ],
      ),
    );

    return pdf.save();
  }

  static String _text(dynamic v) => (v ?? '').toString().trim();

  static pw.Widget _kvRow(
    String key,
    String value, {
    pw.TextStyle? keyStyle,
    pw.TextStyle? valueStyle,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              key,
              style: keyStyle ?? const pw.TextStyle(color: PdfColors.grey700, fontSize: 11),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(value, style: valueStyle ?? const pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
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

  static String _fmtQty(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  static String _fmtEur(double v) {
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    return '€ $s';
  }

  static Map<String, dynamic>? _coerceToMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}

