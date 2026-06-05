import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/contracts/supabase_v1_contract.dart';

class WerkbonPdfService {
  static pw.Font? _fontReg;
  static pw.Font? _fontBold;

  static Future<void> _initFonts() async {
    if (_fontReg == null) {
      _fontReg = await PdfGoogleFonts.montserratRegular();
      _fontBold = await PdfGoogleFonts.montserratBold();
    }
  }

  static Map<String, dynamic> _mapFrom(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  static Map<String, dynamic> _moederBestekMap(dynamic mbRaw) {
    if (mbRaw is List && mbRaw.isNotEmpty) {
      return _mapFrom(mbRaw.first);
    }
    return _mapFrom(mbRaw);
  }

  static Future<Uint8List> generateWerkbonPdf(String opdrachtId) async {
    final pdf = pw.Document();
    final supabase = Supabase.instance.client;

    await _initFonts();

    final opdrachtRaw = await supabase
        .from('opdrachten')
        .select('*, projecten(offerte_id)')
        .eq('id', opdrachtId)
        .single();
    final opdracht = _mapFrom(opdrachtRaw);

    final planningen = await supabase
        .from('opdracht_planning')
        .select('*, operator:gebruikers(voornaam, achternaam)')
        .eq('opdracht_id', opdrachtId);

    final bool isAfgerond = opdracht['status']?.toString() == 'afgerond';
    final String opdrachtDatum = opdracht['geplande_datum']?.toString() ?? '';
    final String startTijd = opdracht['tijdslot_start']?.toString() ?? '--:--';
    final String eindTijd = opdracht['tijdslot_eind']?.toString() ?? '--:--';
    final String toelichtingPlanning =
        opdracht['toelichting_planning']?.toString().trim() ?? '';

    final operatorNamen = <String>[];
    for (final p in planningen as List) {
      final plan = _mapFrom(p);
      final operator = _mapFrom(plan['operator']);
      final vNaam = operator['voornaam']?.toString() ?? '';
      final aNaam = operator['achternaam']?.toString() ?? '';
      final volledigeNaam = '$vNaam $aNaam'.trim();
      if (volledigeNaam.isNotEmpty) operatorNamen.add(volledigeNaam);
    }
    final String operatorString = operatorNamen.isEmpty
        ? 'Nog niet toegewezen'
        : operatorNamen.join(', ');

    final dynamic proj = opdracht['projecten'];
    final String? offerteId = proj != null
        ? (proj is List
                ? _mapFrom(proj.first)['offerte_id']
                : _mapFrom(proj)['offerte_id'])
            ?.toString()
        : null;

    List<dynamic> ruimtes = [];
    var reqType = opdracht['frequentie_type']?.toString().toLowerCase() ?? 'regulier';
    if (offerteId != null && offerteId.isNotEmpty) {
      if (reqType == 'incidenteel' || reqType == 'eenmalig') {
        reqType = 'regulier';
      }
      ruimtes = await supabase.from('offerte_ruimtes').select('''
        naam_in_pand, ruimte_categorie, aantal_identiek, grootte_label,
        offerte_ruimte_diensten (
          frequentie_label,
          moeder_bestek ( * )
        )
      ''').eq('offerte_id', offerteId);
    }

    pw.Widget buildSectionBox(String title, pw.Widget content) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 20),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                border: const pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey400),
                ),
              ),
              child: pw.Text(
                title.toUpperCase(),
                style: pw.TextStyle(
                  font: _fontBold,
                  fontSize: 10,
                  color: PdfColors.black,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(12),
              child: content,
            ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(base: _fontReg, bold: _fontBold),
        header: (context) => pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'UITVOERINGSBON',
                  style: pw.TextStyle(
                    font: _fontBold,
                    fontSize: 24,
                    color: PdfColors.black,
                    letterSpacing: 1.5,
                  ),
                ),
                pw.Text(
                  isAfgerond ? 'STATUS: AFGEROND' : 'STATUS: OPEN',
                  style: pw.TextStyle(
                    font: _fontBold,
                    fontSize: 12,
                    color: isAfgerond ? PdfColors.green800 : PdfColors.grey600,
                  ),
                ),
              ],
            ),
            pw.Divider(color: PdfColors.black, thickness: 1.5),
            pw.SizedBox(height: 20),
          ],
        ),
        footer: (context) => pw.Column(
          children: [
            pw.Divider(color: PdfColors.grey400),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Opdrachtnummer: ${opdracht['opdracht_nummer'] ?? 'ONB'}',
                  style: pw.TextStyle(
                    font: _fontReg,
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  'Pagina ${context.pageNumber} van ${context.pagesCount}',
                  style: pw.TextStyle(
                    font: _fontReg,
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ],
        ),
        build: (pw.Context context) {
          final elements = <pw.Widget>[];

          elements.add(
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: buildSectionBox(
                    'Klantgegevens',
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          opdracht['bedrijfsnaam']?.toString() ??
                              'Onbekende klant',
                          style: pw.TextStyle(font: _fontBold, fontSize: 12),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          opdracht['uitvoer_adres_volledig']?.toString() ??
                              'Adres onbekend',
                          style: pw.TextStyle(font: _fontReg, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: buildSectionBox(
                    'Opdrachtdetails',
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Datum:',
                              style: pw.TextStyle(font: _fontBold, fontSize: 10),
                            ),
                            pw.Text(
                              opdrachtDatum,
                              style: pw.TextStyle(font: _fontReg, fontSize: 10),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Tijdslot:',
                              style: pw.TextStyle(font: _fontBold, fontSize: 10),
                            ),
                            pw.Text(
                              '$startTijd - $eindTijd',
                              style: pw.TextStyle(font: _fontReg, fontSize: 10),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Toegewezen aan:',
                              style: pw.TextStyle(font: _fontBold, fontSize: 10),
                            ),
                            pw.SizedBox(width: 8),
                            pw.Expanded(
                              child: pw.Text(
                                operatorString,
                                style: pw.TextStyle(font: _fontReg, fontSize: 10),
                                textAlign: pw.TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );

          elements.add(pw.SizedBox(height: 10));

          if (toelichtingPlanning.isNotEmpty &&
              toelichtingPlanning.toLowerCase() != 'null') {
            elements.add(
              buildSectionBox(
                'OPMERKING PLANNING',
                pw.Text(
                  toelichtingPlanning,
                  style: pw.TextStyle(
                    font: _fontReg,
                    fontSize: 10,
                    color: PdfColors.black,
                  ),
                ),
              ),
            );
          }

          elements.add(
            pw.Text(
              'WERKPROGRAMMA',
              style: pw.TextStyle(font: _fontBold, fontSize: 14),
            ),
          );
          elements.add(pw.Divider(color: PdfColors.grey400));
          elements.add(pw.SizedBox(height: 10));

          if (ruimtes.isEmpty) {
            elements.add(
              pw.Text(
                'Geen specifieke ruimtes gekoppeld aan deze opdracht.',
                style: pw.TextStyle(
                  font: _fontReg,
                  fontSize: 10,
                  color: PdfColors.grey,
                ),
              ),
            );
          }

          for (final ruimte in ruimtes) {
            final ruimteMap = _mapFrom(ruimte);
            final dienstenRaw = ruimteMap['offerte_ruimte_diensten'];
            final List<dynamic> diensten = dienstenRaw is List
                ? dienstenRaw
                : (dienstenRaw != null ? [dienstenRaw] : []);
            final List<String> actieveTaken = [];

            for (final d in diensten) {
              final dienst = _mapFrom(d);
              final String fLabel =
                  dienst['frequentie_label']?.toString().toLowerCase() ??
                      'regulier';
              var isActief = false;
              if (reqType == 'regulier' && fLabel == 'regulier') {
                isActief = true;
              }
              if (reqType == 'frequent' && fLabel == 'frequent') {
                isActief = true;
              }
              if (reqType == 'periodiek' && fLabel == 'periodiek') {
                isActief = true;
              }

              if (isActief && dienst['moeder_bestek'] != null) {
                final mb = _moederBestekMap(dienst['moeder_bestek']);
                final String taakNaam = mb['volledige_naam']?.toString() ??
                    mb['naam']?.toString() ??
                    'Dienst';
                actieveTaken.add(taakNaam);
              }
            }

            if (actieveTaken.isNotEmpty) {
              elements.add(
                pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 12),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey100,
                          border: pw.Border.all(color: PdfColors.grey300),
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              ruimteMap['naam_in_pand']?.toString() ??
                                  ruimteMap['ruimte_categorie']?.toString() ??
                                  'Ruimte',
                              style: pw.TextStyle(font: _fontBold, fontSize: 11),
                            ),
                            pw.Text(
                              'Aantal: ${ruimteMap['aantal_identiek'] ?? 1}',
                              style: pw.TextStyle(
                                font: _fontReg,
                                fontSize: 9,
                                color: PdfColors.grey700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.Container(
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            left: pw.BorderSide(color: PdfColors.grey300),
                            right: pw.BorderSide(color: PdfColors.grey300),
                            bottom: pw.BorderSide(color: PdfColors.grey300),
                          ),
                        ),
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: actieveTaken
                              .map(
                                (t) => pw.Padding(
                                  padding: const pw.EdgeInsets.only(bottom: 4),
                                  child: pw.Row(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Container(
                                        width: 10,
                                        height: 10,
                                        margin: const pw.EdgeInsets.only(
                                          top: 1,
                                          right: 8,
                                        ),
                                        decoration: pw.BoxDecoration(
                                          border: pw.Border.all(
                                            color: PdfColors.black,
                                          ),
                                        ),
                                        child: isAfgerond
                                            ? pw.Center(
                                                child: pw.Text(
                                                  'X',
                                                  style: pw.TextStyle(
                                                    font: _fontBold,
                                                    fontSize: 8,
                                                  ),
                                                ),
                                              )
                                            : null,
                                      ),
                                      pw.Expanded(
                                        child: pw.Text(
                                          t,
                                          style: pw.TextStyle(
                                            font: _fontReg,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          }

          elements.add(pw.SizedBox(height: 30));
          if (isAfgerond) {
            var afrondTijd = eindTijd;
            for (final p in planningen as List) {
              final plan = _mapFrom(p);
              final rawTijd = plan['werkelijke_eindtijd']?.toString().trim();
              if (rawTijd != null && rawTijd.isNotEmpty) {
                afrondTijd =
                    rawTijd.length >= 5 ? rawTijd.substring(0, 5) : rawTijd;
                break;
              }
            }
            if (afrondTijd == '--:--' || afrondTijd.isEmpty) {
              for (final p in planningen as List) {
                final plan = _mapFrom(p);
                final planEind = plan['eindtijd']?.toString().trim();
                if (planEind != null && planEind.isNotEmpty) {
                  afrondTijd =
                      planEind.length >= 5 ? planEind.substring(0, 5) : planEind;
                  break;
                }
              }
            }
            final datumDisplay = opdrachtDatum.length >= 10
                ? opdrachtDatum.substring(0, 10)
                : opdrachtDatum;

            elements.add(
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Digitaal afgerond en ingediend',
                      style: pw.TextStyle(
                        font: _fontBold,
                        fontSize: 11,
                        color: PdfColors.green800,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Door: $operatorString',
                      style: pw.TextStyle(font: _fontReg, fontSize: 10),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Op: $datumDisplay om $afrondTijd',
                      style: pw.TextStyle(font: _fontReg, fontSize: 10),
                    ),
                  ],
                ),
              ),
            );
          } else {
            elements.add(
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Uitvoerder(s)',
                          style: pw.TextStyle(font: _fontBold, fontSize: 10),
                        ),
                        pw.SizedBox(height: 30),
                        pw.Text(
                          '......................................................',
                          style: const pw.TextStyle(color: PdfColors.grey400),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Naam / Handtekening',
                          style: pw.TextStyle(
                            font: _fontReg,
                            fontSize: 8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Opdrachtgever (Klant)',
                          style: pw.TextStyle(font: _fontBold, fontSize: 10),
                        ),
                        pw.SizedBox(height: 30),
                        pw.Text(
                          '......................................................',
                          style: const pw.TextStyle(color: PdfColors.grey400),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Naam / Handtekening',
                          style: pw.TextStyle(
                            font: _fontReg,
                            fontSize: 8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          return elements;
        },
      ),
    );

    return pdf.save();
  }

  /// Genereert de werkbon-PDF, uploadt naar bucket [werkbonnen] en slaat URL op.
  static Future<String?> generateAndUploadWerkbon(String opdrachtId) async {
    try {
      final bytes = await generateWerkbonPdf(opdrachtId);
      final supabase = Supabase.instance.client;
      final fileName =
          'werkbon_${opdrachtId}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      await supabase.storage.from('werkbonnen').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: true,
            ),
          );

      final publicUrl =
          supabase.storage.from('werkbonnen').getPublicUrl(fileName);

      await supabase.from(OpdrachtenTable.name).update({
        OpdrachtenTable.werkbonPdfUrl: publicUrl,
      }).eq(OpdrachtenTable.id, opdrachtId);

      return publicUrl;
    } catch (e, st) {
      debugPrint('generateAndUploadWerkbon($opdrachtId): $e\n$st');
      return null;
    }
  }
}
