import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Premium offerte-PDF: kaft, intro, ruimtes, werkwijze, prijs, ondertekening, AV.
class PdfGeneratorService {
  static pw.Font? _fontMontserrat;
  static pw.Font? _fontMontserratBold;

  static pw.ImageProvider? _logoNormaal;
  static pw.ImageProvider? _logoTekst;

  static pw.ImageProvider? _coverFoto;
  static pw.ImageProvider? _introFoto;
  static pw.ImageProvider? _overOnsFoto1;
  static pw.ImageProvider? _overOnsFoto2;
  static pw.ImageProvider? _werkwijzeFoto;
  static pw.ImageProvider? _fotoKantoor;
  static pw.ImageProvider? _fotoSanitair;
  static pw.ImageProvider? _fotoKeuken;
  static pw.ImageProvider? _fotoZaal;
  static pw.ImageProvider? _fotoGang;
  static pw.ImageProvider? _fotoMagazijn;
  static pw.ImageProvider? _fotoAfval;
  static pw.ImageProvider? _fotoOverig;

  static String _urlOrPlaceholder(String? url, String fallback) {
    final s = (url ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  static Future<void> _initResources(Map<String, dynamic> bedrijfsData) async {
    if (_fontMontserrat == null) {
      try {
        _fontMontserrat = await PdfGoogleFonts.montserratRegular();
        _fontMontserratBold = await PdfGoogleFonts.montserratBold();
      } catch (e) {
        debugPrint('Font error: $e');
      }

      try {
        _logoNormaal = await networkImage(_urlOrPlaceholder(
          bedrijfsData['logo_url']?.toString(),
          'https://via.placeholder.com/400x150.png?text=NORMAAL+LOGO',
        ));
      } catch (e) {
        debugPrint('Logo normaal: $e');
      }
      try {
        _logoTekst = await networkImage(_urlOrPlaceholder(
          bedrijfsData['logo_tekst_url']?.toString(),
          'https://via.placeholder.com/600x150.png?text=TEKST+LOGO',
        ));
      } catch (e) {
        debugPrint('Logo tekst: $e');
      }
      Future<void> laadFoto(
        String url,
        void Function(pw.ImageProvider img) setter,
      ) async {
        try {
          setter(await networkImage(url));
        } catch (e) {
          debugPrint('Foto laden mislukt ($url): $e');
        }
      }

      const fotoQuery = '?q=80&w=1200&auto=format&fit=crop';
      const urlKaft =
          'https://facilitairdomein.nl/cdn/shop/files/Opleveringsschoonmaak_Nulbeurt_Sneller_Verhuren_met_een_Schone_Lei.png?v=1773761462&width=2560';
      const urlWerkwijze =
          'https://facilitairdomein.nl/cdn/shop/files/Amsterdam_zuidas_2.png?v=1776081804&width=1400';
      const urlKamer =
          'https://images.unsplash.com/photo-1497366754035-f200968a6e72$fotoQuery';
      const urlZaal =
          'https://images.unsplash.com/photo-1517502884422-41eaead166d4$fotoQuery';
      const urlSanitair =
          'https://images.unsplash.com/photo-1584622650111-993a426fbf0a$fotoQuery';
      const urlKeuken =
          'https://images.unsplash.com/photo-1556910103-1c02745aae4d$fotoQuery';
      const urlGang =
          'https://images.unsplash.com/photo-1513694203232-719a280e022f$fotoQuery';
      const urlMagazijn =
          'https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d$fotoQuery';
      const urlOverig =
          'https://images.unsplash.com/photo-1613665813446-82a78c468a1d$fotoQuery';
      const urlAfval =
          'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab$fotoQuery';
      const urlIntro =
          'https://images.unsplash.com/photo-1556761175-4b46a572b786$fotoQuery';
      const urlOverOns1 =
          'https://images.unsplash.com/photo-1527515637462-cff94eecc1ac$fotoQuery';

      await Future.wait([
        laadFoto(urlKaft, (img) => _coverFoto = img),
        laadFoto(urlWerkwijze, (img) => _werkwijzeFoto = img),
        laadFoto(urlKamer, (img) => _fotoKantoor = img),
        laadFoto(urlZaal, (img) => _fotoZaal = img),
        laadFoto(urlIntro, (img) => _introFoto = img),
        laadFoto(urlOverOns1, (img) => _overOnsFoto1 = img),
        laadFoto(urlOverig, (img) => _overOnsFoto2 = img),
        laadFoto(urlSanitair, (img) => _fotoSanitair = img),
        laadFoto(urlKeuken, (img) => _fotoKeuken = img),
        laadFoto(urlGang, (img) => _fotoGang = img),
        laadFoto(urlMagazijn, (img) => _fotoMagazijn = img),
        laadFoto(urlAfval, (img) => _fotoAfval = img),
        laadFoto(urlOverig, (img) => _fotoOverig = img),
      ]);
    }
  }

  static pw.ImageProvider? _fotoVoorRuimteCategorie(String categorie) {
    final cat = categorie.toLowerCase();
    if (cat.contains('sanitair') || cat.contains('toilet')) {
      return _fotoSanitair ?? _coverFoto;
    }
    if (cat.contains('keuken') || cat.contains('pantry') || cat.contains('kantine')) {
      return _fotoKeuken ?? _coverFoto;
    }
    if (cat.contains('zaal') || cat.contains('vergader')) {
      return _fotoZaal ?? _coverFoto;
    }
    if (cat.contains('gang') || cat.contains('entree') || cat.contains('vloer')) {
      return _fotoGang ?? _coverFoto;
    }
    if (cat.contains('magazijn') || cat.contains('opslag')) {
      return _fotoMagazijn ?? _coverFoto;
    }
    if (cat.contains('afval') || cat.contains('buiten')) {
      return _fotoAfval ?? _coverFoto;
    }
    if (cat.contains('kamer') ||
        cat.contains('kantoor') ||
        cat.contains('werkplek')) {
      return _fotoKantoor ?? _coverFoto;
    }
    return _fotoOverig ?? _coverFoto;
  }

  /// Asymmetrische hoeken (alleen voor foto's, niet voor tekstvlakken).
  static pw.Widget _asymFoto({
    required pw.ImageProvider? provider,
    required pw.BorderRadius borderRadius,
    PdfColor fallbackColor = PdfColors.grey300,
    String? placeholder,
    pw.Font? placeholderFont,
  }) {
    if (provider != null) {
      return pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(
          borderRadius: borderRadius,
          image: pw.DecorationImage(image: provider, fit: pw.BoxFit.cover),
        ),
      );
    }
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: fallbackColor,
        borderRadius: borderRadius,
      ),
      child: placeholder != null
          ? pw.Center(
              child: pw.Text(
                placeholder,
                style: pw.TextStyle(
                  font: placeholderFont,
                  fontSize: 11,
                  color: PdfColors.grey700,
                ),
              ),
            )
          : null,
    );
  }

  static double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(_text(v).replaceAll(',', '.')) ?? 0;
  }

  static double _totaalExBtwOfferte(Map<String, dynamic> offerte) {
    final override = _asDouble(offerte['vaste_prijs_override']);
    if (override > 0) return override;
    final maand = _asDouble(offerte['maandprijs_ex_btw']);
    if (maand > 0) return maand;
    return _asDouble(offerte['totaal_prijs_ex_btw']);
  }

  static Future<Uint8List> generateOffertePdf(String offerteId) async {
    final pdf = pw.Document();
    final supabase = Supabase.instance.client;

    final offerteRaw = await supabase
        .from('offertes')
        .select()
        .eq('id', offerteId)
        .single();
    final offerte = Map<String, dynamic>.from(offerteRaw as Map);

    final onzeRaw = await supabase
        .from('eigen_bedrijfsgegevens')
        .select()
        .eq('id', 1)
        .maybeSingle();
    final onzeGegevens = onzeRaw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(onzeRaw as Map);

    await _initResources(onzeGegevens);

    final fontRegular = _fontMontserrat!;
    final fontBold = _fontMontserratBold!;

    final ruimtesRaw = await supabase
        .from('offerte_ruimtes')
        .select('*, offerte_ruimte_diensten(*, moeder_bestek(*))')
        .eq('offerte_id', offerteId);
    final ruimtes = (ruimtesRaw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final blueColor = PdfColor.fromHex('#004A99');
    final lightGrey = PdfColor.fromHex('#F2F2F7');
    final primaryOrange = PdfColor.fromHex('#F26622');
    final whiteOnOrange80 = PdfColor.fromHex('#CCFFFFFF');
    final whiteOnOrange50 = PdfColor.fromHex('#80FFFFFF');

    final themeData = pw.ThemeData.withFont(
      base: _fontMontserrat,
      bold: _fontMontserratBold,
    );
    final tealAccent = PdfColor.fromHex('#009688');
    final orangeTint10 = PdfColor.fromHex('#1AF26622');
    final merkLogo = _logoNormaal;
    final logoImage = _logoTekst;

    final bedrijfsnaamKlant = _text(offerte['bedrijfsnaam_klant'], fallback: 'Onbekend');
    final onzeNaam = _text(onzeGegevens['bedrijfsnaam'], fallback: 'CleanConnect');
    final offerteNummer = _text(offerte['offerte_nummer'], fallback: 'Concept');
    final datumLabel =
        '${DateTime.now().day.toString().padLeft(2, '0')}-'
        '${DateTime.now().month.toString().padLeft(2, '0')}-'
        '${DateTime.now().year}';
    final uitvoerLocatie =
        '${_text(offerte['uitvoer_adres_straat_huisnr'])}, ${_text(offerte['uitvoer_adres_stad'])}';
    final contactVoornaam = _text(offerte['contact_voornaam'], fallback: 'relatie');

    final bool isConcept =
        offerte['status'] == 'concept' || offerte['status'] == 'new';

    pw.Widget buildFullBleedHeader(pw.Context context) {
      return pw.Container(
        height: 25,
        width: double.infinity,
        color: lightGrey,
        padding: const pw.EdgeInsets.symmetric(horizontal: 40),
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(
          bedrijfsnaamKlant,
          style: pw.TextStyle(
            font: fontBold,
            color: blueColor,
            fontSize: 9,
          ),
        ),
      );
    }

    pw.Widget buildFullBleedFooter(pw.Context context) {
      return pw.Container(
        height: 35,
        width: double.infinity,
        color: lightGrey,
        padding: const pw.EdgeInsets.symmetric(horizontal: 40),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'Offerte: $offerteNummer',
              style: pw.TextStyle(
                font: fontBold,
                color: blueColor,
                fontSize: 9,
              ),
            ),
            pw.Text(
              'Pagina ${context.pageNumber} van ${context.pagesCount}',
              style: pw.TextStyle(
                font: fontRegular,
                color: PdfColors.grey700,
                fontSize: 9,
              ),
            ),
          ],
        ),
      );
    }

    // WATERMERK (extreem transparant zodat tekst leesbaar blijft)
    final conceptWatermarkColor = PdfColor.fromHex('#33E5E5E5');

    pw.Widget buildWatermark() {
      if (!isConcept) return pw.SizedBox.shrink();
      return pw.Positioned.fill(
        child: pw.Center(
          child: pw.Transform.rotateBox(
            angle: 0.6,
            child: pw.Text(
              'CONCEPT EDITIE - GEEN RECHTEN AAN TE ONTLENEN',
              style: pw.TextStyle(
                color: conceptWatermarkColor,
                fontSize: 45,
                font: fontBold,
              ),
            ),
          ),
        ),
      );
    }

    pw.Widget pageWithBleed(pw.Context context, pw.Widget content) {
      return pw.Column(
        children: [
          buildFullBleedHeader(context),
          pw.Expanded(
            child: pw.Stack(
              children: [
                buildWatermark(),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(40),
                  child: content,
                ),
              ],
            ),
          ),
          buildFullBleedFooter(context),
        ],
      );
    }

    final blueOverlay90 = PdfColor.fromHex('#E6004A99');
    final coverOrangeShadow = PdfColor.fromHex('#59000000');

    // ==========================================
    // PAGINA 1: DE KAFT (PORTRET)
    // ==========================================
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          const fotoTopPos = 260.0;
          const orangeTopPos = 500.0;

          return pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Container(color: PdfColors.white),
              ),
              if (logoImage != null)
                pw.Positioned(
                  top: 40,
                  left: 40,
                  child: pw.SizedBox(
                    height: 180,
                    width: 450,
                    child: pw.Image(
                      logoImage,
                      fit: pw.BoxFit.contain,
                      alignment: pw.Alignment.topLeft,
                    ),
                  ),
                ),
              if (merkLogo != null)
                pw.Positioned(
                  top: 40,
                  right: 40,
                  child: pw.SizedBox(
                    height: 120,
                    width: 150,
                    child: pw.Image(
                      merkLogo,
                      fit: pw.BoxFit.contain,
                      alignment: pw.Alignment.topRight,
                    ),
                  ),
                ),
              if (_coverFoto != null)
                pw.Positioned(
                  top: fotoTopPos,
                  left: 0,
                  right: 0,
                  child: pw.SizedBox(
                    height: 350,
                    child: pw.Image(_coverFoto!, fit: pw.BoxFit.cover),
                  ),
                ),
              pw.Positioned(
                top: orangeTopPos,
                bottom: 0,
                left: 0,
                right: 0,
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    color: primaryOrange,
                    boxShadow: [
                      pw.BoxShadow(
                        color: coverOrangeShadow,
                        blurRadius: 25,
                      ),
                    ],
                  ),
                  padding: const pw.EdgeInsets.only(
                    left: 50,
                    right: 50,
                    top: 40,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: pw.BoxDecoration(
                          color: blueColor,
                          borderRadius: pw.BorderRadius.circular(20),
                        ),
                        child: pw.Text(
                          'ONDERHOUDSVOORSTEL',
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 16,
                            color: PdfColors.white,
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 35),
                      pw.Text(
                        'VOOR:',
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 18,
                          color: whiteOnOrange80,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.FittedBox(
                        fit: pw.BoxFit.scaleDown,
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Text(
                          bedrijfsnaamKlant,
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 45,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 10),
                      pw.Text(
                        uitvoerLocatie,
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 14,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 25),
                      pw.Container(
                        height: 2,
                        width: 100,
                        color: whiteOnOrange50,
                      ),
                      pw.SizedBox(height: 25),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Offerte: $offerteNummer',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 14,
                              color: PdfColors.white,
                            ),
                          ),
                          pw.Text(
                            'Datum: $datumLabel',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 14,
                              color: whiteOnOrange80,
                            ),
                          ),
                        ],
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

    // ==========================================
    // PAGINA 2: PRAKTISCHE INFO
    // ==========================================
    final cType = _text(offerte['contract_type']).toLowerCase();
    final startD = _text(offerte['contract_startdatum'], fallback: 'in overleg');
    final eindD = _text(offerte['contract_einddatum'], fallback: 'onbepaalde tijd');
    final dagenTekst = _formatWeekdagen(offerte['reguliere_weekdagen']);
    final periodiekeFreq = _text(offerte['periodieke_frequentie'])
        .replaceAll('_', ' ');
    final akkoordTekst = (cType == 'eenmalig' || cType == 'incidenteel')
        ? 'Bij akkoord zullen wij deze eenmalige/incidentele opdracht uitvoeren op of rond $startD.\n\n'
            'De gedetailleerde specificatie van de overeengekomen werkzaamheden, ingedeeld per ruimte, treft u aan in de tabel op de volgende pagina.'
        : 'Bij akkoord kunnen wij starten op $startD, de overeenkomst wordt aangegaan voor een $cType looptijd tot en met $eindD.\n\n'
            'De gedetailleerde specificatie van de overeengekomen werkzaamheden, ingedeeld per ruimte, treft u aan in de tabel op de volgende pagina.';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        theme: themeData,
        build: (pw.Context context) {
          return pageWithBleed(
            context,
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
              pw.Text(
                'Onze Samenwerking',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 32,
                  color: blueColor,
                ),
              ),
              pw.SizedBox(height: 30),
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      flex: 6,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Beste $contactVoornaam,',
                            style: pw.TextStyle(font: fontBold, fontSize: 12),
                          ),
                          pw.SizedBox(height: 10),
                          pw.Text(
                            'Hartelijk dank dat wij u deze aanbieding mogen presenteren voor het uitvoeren '
                            'van het schoonmaakonderhoud aan uw pand. Hierbij presenteren wij u deze offerte '
                            'en het gedetailleerde voorstel voor de facilitaire diensten, volledig afgestemd '
                            'op uw wensen.',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                              lineSpacing: 1.5,
                            ),
                          ),
                          pw.SizedBox(height: 25),
                          pw.Text(
                            'Praktische Informatie',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 14,
                              color: blueColor,
                            ),
                          ),
                          pw.SizedBox(height: 10),
                          pw.Container(
                            decoration: pw.BoxDecoration(
                              border: pw.Border(
                                top: pw.BorderSide(color: blueColor, width: 2),
                              ),
                            ),
                            child: pw.Column(
                              children: [
                                _buildSleekTableRow(
                                  'Locatie van uitvoering',
                                  uitvoerLocatie,
                                  fontBold,
                                  fontRegular,
                                ),
                                _buildSleekTableRow(
                                  'Type overeenkomst',
                                  cType.toUpperCase().isEmpty
                                      ? 'ONBEKEND'
                                      : cType.toUpperCase(),
                                  fontBold,
                                  fontRegular,
                                ),
                                if (cType != 'eenmalig' && cType != 'incidenteel')
                                  _buildSleekTableRow(
                                    'Uitvoerdagen',
                                    dagenTekst,
                                    fontBold,
                                    fontRegular,
                                  ),
                                _buildSleekTableRow(
                                  'Frequente werkzaamheden',
                                  'Worden maandelijks uitgevoerd',
                                  fontBold,
                                  fontRegular,
                                ),
                                _buildSleekTableRow(
                                  'Periodieke werkzaamheden',
                                  periodiekeFreq.isEmpty
                                      ? 'Volgens afspraak'
                                      : periodiekeFreq,
                                  fontBold,
                                  fontRegular,
                                ),
                                _buildSleekTableRow(
                                  'Tijdslot',
                                  '${_text(offerte['tijdslot_start'], fallback: '--:--')} tot ${_text(offerte['tijdslot_eind'], fallback: '--:--')}',
                                  fontBold,
                                  fontRegular,
                                ),
                              ],
                            ),
                          ),
                          pw.SizedBox(height: 20),
                          pw.Text(
                            akkoordTekst,
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                              color: PdfColors.black,
                              lineSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 40),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          if (_logoNormaal != null)
                            pw.Container(
                              height: 35,
                              child: pw.Image(_logoNormaal!),
                            ),
                          pw.SizedBox(height: 5),
                          pw.Text(
                            onzeNaam,
                            style: pw.TextStyle(font: fontBold, fontSize: 10),
                          ),
                          pw.Text(
                            _text(onzeGegevens['adres_straat_huisnr']),
                            style: pw.TextStyle(font: fontRegular, fontSize: 9),
                          ),
                          pw.Text(
                            '${_text(onzeGegevens['adres_postcode'])} ${_text(onzeGegevens['adres_stad'])}',
                            style: pw.TextStyle(font: fontRegular, fontSize: 9),
                          ),
                          pw.Text(
                            'KVK: ${_text(onzeGegevens['kvk_nummer'])} | Tel: ${_text(onzeGegevens['telefoonnummer'])}',
                            style: pw.TextStyle(font: fontRegular, fontSize: 9),
                          ),
                          pw.Spacer(),
                          if (_introFoto != null)
                            pw.SizedBox(
                              height: 180,
                              width: double.infinity,
                              child: _asymFoto(
                                provider: _introFoto,
                                borderRadius: pw.BorderRadius.only(
                                  topLeft: pw.Radius.circular(40),
                                  bottomRight: pw.Radius.circular(40),
                                ),
                              ),
                            ),
                          pw.SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ],
            ),
          );
        },
      ),
    );

    // ==========================================
    // PAGINA 3: OVER ONS
    // ==========================================
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        theme: themeData,
        build: (pw.Context context) {
          return pageWithBleed(
            context,
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Over $onzeNaam',
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 32,
                    color: blueColor,
                  ),
                ),
                pw.SizedBox(height: 40),
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      pw.Expanded(
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if (_overOnsFoto1 != null)
                              pw.Expanded(
                                child: pw.ClipRRect(
                                  horizontalRadius: 12,
                                  verticalRadius: 12,
                                  child: pw.Image(
                                    _overOnsFoto1!,
                                    fit: pw.BoxFit.cover,
                                  ),
                                ),
                              ),
                            pw.SizedBox(width: 40),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    'Kwaliteit & Betrouwbaarheid',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 16,
                                      color: primaryOrange,
                                    ),
                                  ),
                                  pw.SizedBox(height: 10),
                                  pw.Text(
                                    'Wij staan voor kwaliteit, betrouwbaarheid en een stralend resultaat. '
                                    'Onze ervaren medewerkers zetten zich dagelijks in om uw pand in '
                                    'topconditie te houden.\n\n'
                                    '• Gecertificeerd personeel\n'
                                    '• Vaste aanspreekpunten\n'
                                    '• 100% tevredenheidsgarantie',
                                    style: pw.TextStyle(
                                      font: fontRegular,
                                      fontSize: 12,
                                      lineSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 40),
                      pw.Expanded(
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    'Innovatie & Communicatie',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 16,
                                      color: primaryOrange,
                                    ),
                                  ),
                                  pw.SizedBox(height: 10),
                                  pw.Text(
                                    'Schoonmaak efficiënt geregeld is ons sentiment. Met innovatieve '
                                    'technieken en duidelijke communicatie nemen we al uw facilitaire '
                                    'zorgen uit handen.\n\n'
                                    '• Innovatieve materialen\n'
                                    '• Korte lijntjes\n'
                                    '• Proactieve controles (DKS)',
                                    style: pw.TextStyle(
                                      font: fontRegular,
                                      fontSize: 12,
                                      lineSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            pw.SizedBox(width: 40),
                            if (_overOnsFoto2 != null)
                              pw.Expanded(
                                child: pw.ClipRRect(
                                  horizontalRadius: 12,
                                  verticalRadius: 12,
                                  child: pw.Image(
                                    _overOnsFoto2!,
                                    fit: pw.BoxFit.cover,
                                  ),
                                ),
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
        },
      ),
    );

    // ==========================================
    // PAGINA 4+: RUIMTES (REGULIER / FREQUENT-PERIODIEK)
    // ==========================================
    for (final ruimte in ruimtes) {
      final dienstenRaw = ruimte['offerte_ruimte_diensten'];
      final List<Map<String, dynamic>> diensten = dienstenRaw is List
          ? dienstenRaw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : <Map<String, dynamic>>[];

      final cat = _text(ruimte['ruimte_categorie'], fallback: 'Ruimte');
      final beschrijving = _getCategoryDescription(cat);
      final ruimteNaam = _text(ruimte['naam_in_pand']).isNotEmpty
          ? _text(ruimte['naam_in_pand'])
          : cat;

      final regDiensten = _dienstenVoorFrequentieLabel(diensten, 'regulier');
      final freqDiensten = _dienstenVoorFrequentieLabel(diensten, 'frequent');
      final perDiensten = _dienstenVoorFrequentieLabel(diensten, 'periodiek');

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: pw.EdgeInsets.zero,
          theme: themeData,
          build: (pw.Context context) {
            return pageWithBleed(
              context,
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Specificatie',
                    style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 12,
                      color: PdfColors.grey,
                    ),
                  ),
                  pw.Text(
                    ruimteNaam,
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 24,
                      color: blueColor,
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Expanded(
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          flex: 4,
                          child: pw.Stack(
                            children: [
                              pw.ClipRRect(
                                horizontalRadius: 16,
                                verticalRadius: 16,
                                child: pw.Container(
                                  color: PdfColors.grey300,
                                  width: double.infinity,
                                  height: double.infinity,
                                  child: () {
                                    final ruimteFoto =
                                        _fotoVoorRuimteCategorie(cat);
                                    if (ruimteFoto != null) {
                                      return pw.Image(
                                        ruimteFoto,
                                        fit: pw.BoxFit.cover,
                                      );
                                    }
                                    return pw.Center(
                                      child: pw.Text(
                                        'Foto $cat',
                                        style: pw.TextStyle(
                                          font: fontRegular,
                                        ),
                                      ),
                                    );
                                  }(),
                                ),
                              ),
                              pw.Positioned(
                                bottom: 10,
                                left: 10,
                                right: 10,
                                child: pw.Container(
                                  padding: const pw.EdgeInsets.all(12),
                                  decoration: pw.BoxDecoration(
                                    color: blueOverlay90,
                                    borderRadius:
                                        pw.BorderRadius.circular(12),
                                  ),
                                  child: pw.Text(
                                    beschrijving,
                                    style: pw.TextStyle(
                                      font: fontRegular,
                                      color: PdfColors.white,
                                      fontSize: 9,
                                      lineSpacing: 1.3,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 20),
                        pw.Expanded(
                          flex: 6,
                          child: _buildFrequentieDienstenPane(
                            titel: 'Regulier Onderhoud',
                            diensten: regDiensten,
                            headerColor: blueColor,
                            bulletColor: blueColor,
                            bgColor: lightGrey,
                            fontBold: fontBold,
                            fontRegular: fontRegular,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      if (freqDiensten.isNotEmpty || perDiensten.isNotEmpty) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: pw.EdgeInsets.zero,
            theme: themeData,
            build: (pw.Context context) {
              return pageWithBleed(
                context,
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Specificatie (Vervolg)',
                      style: pw.TextStyle(
                        font: fontRegular,
                        fontSize: 12,
                        color: PdfColors.grey,
                      ),
                    ),
                    pw.Text(
                      ruimteNaam,
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 24,
                        color: blueColor,
                      ),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Expanded(
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (freqDiensten.isNotEmpty)
                            pw.Expanded(
                              child: _buildFrequentieDienstenPane(
                                titel: 'Frequent Onderhoud',
                                diensten: freqDiensten,
                                headerColor: primaryOrange,
                                bulletColor: primaryOrange,
                                bgColor: lightGrey,
                                fontBold: fontBold,
                                fontRegular: fontRegular,
                              ),
                            ),
                          if (freqDiensten.isNotEmpty &&
                              perDiensten.isNotEmpty)
                            pw.SizedBox(width: 20),
                          if (perDiensten.isNotEmpty)
                            pw.Expanded(
                              child: _buildFrequentieDienstenPane(
                                titel: 'Periodiek Onderhoud',
                                diensten: perDiensten,
                                headerColor: tealAccent,
                                bulletColor: tealAccent,
                                bgColor: lightGrey,
                                fontBold: fontBold,
                                fontRegular: fontRegular,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }
    }

    // ==========================================
    // PAGINA X: ONZE WERKWIJZE (SFEERPAGINA)
    // ==========================================
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        theme: themeData,
        build: (pw.Context context) {
          return pageWithBleed(
            context,
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.ClipRRect(
                    horizontalRadius: 16,
                    verticalRadius: 16,
                    child: pw.Container(
                      color: lightGrey,
                      width: double.infinity,
                      height: double.infinity,
                      child: _werkwijzeFoto != null
                          ? pw.Image(_werkwijzeFoto!, fit: pw.BoxFit.cover)
                          : pw.Center(
                              child: pw.Text('Sfeerfoto Werkwijze'),
                            ),
                    ),
                  ),
                ),
                    pw.SizedBox(width: 40),
                    pw.Expanded(
                      flex: 5,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: pw.BoxDecoration(
                              color: orangeTint10,
                              borderRadius: pw.BorderRadius.circular(8),
                            ),
                            child: pw.Text(
                              'ONZE WERKWIJZE',
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 12,
                                color: primaryOrange,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          pw.SizedBox(height: 16),
                          pw.Text(
                            'Schoonmaak zonder gedoe.',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 32,
                              color: blueColor,
                              lineSpacing: 1.2,
                            ),
                          ),
                          pw.SizedBox(height: 24),
                          pw.Text(
                            'Schoonmaak efficiënt geregeld is het sentiment. '
                            'Bij $onzeNaam geloven we in een transparante, daadkrachtige aanpak.',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 14,
                              color: PdfColors.grey800,
                              lineSpacing: 1.5,
                            ),
                          ),
                          pw.SizedBox(height: 16),
                          pw.Text(
                            'Wij gebruiken state-of-the-art systemen en innovatieve technieken. '
                            'Hierdoor werken we niet alleen sneller, maar leveren we structureel '
                            'een beter en schoner resultaat af.',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 14,
                              color: PdfColors.grey800,
                              lineSpacing: 1.5,
                            ),
                          ),
                          pw.SizedBox(height: 16),
                          pw.Text(
                            'Dat is goed geregeld.',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 16,
                              color: primaryOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );

    // ==========================================
    // PAGINA Y: PRIJSOVERZICHT
    // ==========================================
    final double totaalExBtw = _totaalExBtwOfferte(offerte);
    final double btwBedrag = totaalExBtw * 0.21;
    final double totaalInclBtw = totaalExBtw + btwBedrag;
    const checkIconSvg =
        '<svg viewBox="0 0 24 24" fill="none" stroke="#4CAF50" stroke-width="3" '
        'stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg">'
        '<polyline points="20 6 9 17 4 12"></polyline></svg>';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        theme: themeData,
        build: (pw.Context context) {
          return pageWithBleed(
            context,
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
              pw.Text(
                'Investeringsoverzicht',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 28,
                  color: blueColor,
                ),
              ),
              pw.SizedBox(height: 30),
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      flex: 6,
                      child: pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey300),
                          borderRadius: pw.BorderRadius.circular(12),
                        ),
                        child: pw.Column(
                          children: [
                            pw.Container(
                              padding: const pw.EdgeInsets.all(16),
                              decoration: pw.BoxDecoration(
                                color: primaryOrange,
                                borderRadius:
                                    const pw.BorderRadius.vertical(
                                  top: pw.Radius.circular(12),
                                ),
                              ),
                              child: pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text(
                                    'Omschrijving',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      color: PdfColors.white,
                                    ),
                                  ),
                                  pw.Text(
                                    'Bedrag per maand (ex BTW)',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      color: PdfColors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(16),
                              child: pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text(
                                    'Schoonmaakonderhoud volgens specificatie',
                                    style: pw.TextStyle(font: fontBold),
                                  ),
                                  pw.Text(
                                    '€ ${totaalExBtw.toStringAsFixed(2)} per maand',
                                    style: pw.TextStyle(
                                      font: fontRegular,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            pw.Divider(color: PdfColors.grey300, height: 1),
                            pw.Expanded(
                              child: pw.Container(
                              padding: const pw.EdgeInsets.all(16),
                              decoration: pw.BoxDecoration(
                                color: lightGrey,
                                borderRadius:
                                    const pw.BorderRadius.vertical(
                                  bottom: pw.Radius.circular(12),
                                ),
                              ),
                              child: pw.Column(
                                mainAxisAlignment: pw.MainAxisAlignment.end,
                                children: [
                                  pw.Row(
                                    mainAxisAlignment:
                                        pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      pw.Text(
                                        'Totaal exclusief 21% BTW',
                                        style: pw.TextStyle(
                                          font: fontRegular,
                                          color: PdfColors.grey800,
                                          fontSize: 10,
                                        ),
                                      ),
                                      pw.Text(
                                        '€ ${totaalExBtw.toStringAsFixed(2)}',
                                        style: pw.TextStyle(fontSize: 10),
                                      ),
                                    ],
                                  ),
                                  pw.SizedBox(height: 6),
                                  pw.Row(
                                    mainAxisAlignment:
                                        pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      pw.Text(
                                        '21% BTW',
                                        style: pw.TextStyle(
                                          font: fontRegular,
                                          color: PdfColors.grey800,
                                          fontSize: 10,
                                        ),
                                      ),
                                      pw.Text(
                                        '€ ${btwBedrag.toStringAsFixed(2)}',
                                        style: pw.TextStyle(fontSize: 10),
                                      ),
                                    ],
                                  ),
                                  pw.Divider(color: PdfColors.grey400, height: 20),
                                  pw.Row(
                                    mainAxisAlignment:
                                        pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      pw.Text(
                                        'TOTAAL INCLUSIEF BTW',
                                        style: pw.TextStyle(
                                          font: fontBold,
                                          fontSize: 14,
                                          color: primaryOrange,
                                        ),
                                      ),
                                      pw.Text(
                                        '€ ${totaalInclBtw.toStringAsFixed(2)} per maand',
                                        style: pw.TextStyle(
                                          font: fontBold,
                                          fontSize: 14,
                                          color: primaryOrange,
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
                      ),
                    ),
                    pw.SizedBox(width: 30),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(20),
                        decoration: pw.BoxDecoration(
                          color: lightGrey,
                          borderRadius: pw.BorderRadius.circular(12),
                          border: pw.Border.all(color: PdfColors.grey300),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Inbegrepen in de prijs',
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 14,
                                color: blueColor,
                              ),
                            ),
                            pw.SizedBox(height: 16),
                            _buildCheckItem(
                              checkIconSvg,
                              'Inzet van gekwalificeerd personeel',
                              fontRegular,
                            ),
                            _buildCheckItem(
                              checkIconSvg,
                              'Alle benodigde schoonmaakmiddelen',
                              fontRegular,
                            ),
                            _buildCheckItem(
                              checkIconSvg,
                              'Inzet van materialen en apparatuur',
                              fontRegular,
                            ),
                            _buildCheckItem(
                              checkIconSvg,
                              'Proactieve DKS-kwaliteitscontroles',
                              fontRegular,
                            ),
                            _buildCheckItem(
                              checkIconSvg,
                              'Vaste contactpersoon',
                              fontRegular,
                            ),
                            _buildCheckItem(
                              checkIconSvg,
                              'Ziektevervanging',
                              fontRegular,
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
          );
        },
      ),
    );

    // ==========================================
    // PAGINA Z: ONDERTEKENING
    // ==========================================
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        theme: themeData,
        build: (pw.Context context) {
          return pageWithBleed(
            context,
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Ondertekening',
                  style: pw.TextStyle(
                    font: _fontMontserratBold,
                    fontSize: 24,
                    color: blueColor,
                  ),
                ),
                pw.SizedBox(height: 15),
                pw.Text(
                  'Facturatie',
                  style: pw.TextStyle(
                    font: _fontMontserratBold,
                    fontSize: 14,
                    color: blueColor,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Facturatie van de overeengekomen schoonmaakdiensten geschiedt maandelijks achteraf.\n'
                  'Het bedrag bedraagt € ${totaalInclBtw.toStringAsFixed(2)} (inclusief BTW).\n'
                  'De betalingstermijn is ${offerte['bedrijven']?['standaard_betalingstermijn_dagen'] ?? 14} dagen na factuurdatum. Deze offerte is 30 dagen geldig.\n'
                  'De algemene voorwaarden worden meegestuurd als bijlage en zijn tevens in te zien op onze website www.facilitairdomein.nl.',
                  style: pw.TextStyle(
                    font: _fontMontserrat,
                    fontSize: 9,
                    lineSpacing: 1.5,
                    color: PdfColors.grey800,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Algemene Voorwaarden en Akkoord',
                  style: pw.TextStyle(
                    font: _fontMontserratBold,
                    fontSize: 14,
                    color: blueColor,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Door ondertekening van deze offerte verklaart de opdrachtgever zich akkoord met de voorgestelde diensten, de bijbehorende prijzen en de Algemene Voorwaarden van ${onzeGegevens['bedrijfsnaam'] ?? 'Domein Facilitaire Diensten'}.\n'
                  'Let op: Op deze offerte zijn onze algemene voorwaarden van toepassing.',
                  style: pw.TextStyle(
                    font: _fontMontserrat,
                    fontSize: 9,
                    lineSpacing: 1.5,
                    color: PdfColors.grey800,
                  ),
                ),
                pw.SizedBox(height: 25),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: primaryOrange, width: 1.5),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Akkoordverklaring Opdrachtgever',
                        style: pw.TextStyle(
                          font: _fontMontserratBold,
                          fontSize: 12,
                          color: primaryOrange,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Door ondertekening van deze offerte verklaart de Opdrachtgever deze te hebben gelezen en aanvaard.',
                        style: pw.TextStyle(font: _fontMontserrat, fontSize: 9),
                      ),
                      pw.SizedBox(height: 16),
                      pw.Text(
                        'Naam Bedrijf: ${offerte['bedrijfsnaam_klant'] ?? ''}',
                        style: pw.TextStyle(font: _fontMontserrat, fontSize: 9),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Naam Opdrachtgever: ${offerte['contact_voornaam'] ?? ''} ${offerte['contact_achternaam'] ?? ''}',
                        style: pw.TextStyle(font: _fontMontserrat, fontSize: 9),
                      ),
                      pw.SizedBox(height: 12),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Datum van Akkoord:',
                            style: pw.TextStyle(
                              font: _fontMontserrat,
                              fontSize: 10,
                              color: PdfColors.grey700,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            '[[d|r0]]',
                            style: pw.TextStyle(
                              font: _fontMontserrat,
                              fontSize: 10,
                              color: PdfColors.white,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 12),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Handtekening:',
                            style: pw.TextStyle(
                              font: _fontMontserrat,
                              fontSize: 10,
                              color: PdfColors.grey700,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            '[[s|0]]',
                            style: pw.TextStyle(
                              font: _fontMontserrat,
                              fontSize: 20,
                              color: PdfColors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.Spacer(),
                pw.Text(
                  'De offerte wordt van kracht zodra de Opdrachtgever deze heeft ondertekend.',
                  style: pw.TextStyle(
                    font: _fontMontserrat,
                    fontSize: 8,
                    color: PdfColors.grey,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    // ==========================================
    // PAGINA W: ALGEMENE VOORWAARDEN
    // ==========================================
    final String voorwaardenTekst =
        onzeGegevens['algemene_voorwaarden']?.toString().trim() ?? '';

    if (voorwaardenTekst.isNotEmpty) {
      final List<String> ruweParagrafen = voorwaardenTekst
          .split('\n')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      final List<String> paragrafen = [];
      for (final p in ruweParagrafen) {
        if (p.length > 2000) {
          var start = 0;
          while (start < p.length) {
            var end = start + 2000;
            if (end > p.length) end = p.length;
            paragrafen.add(
              p.substring(start, end) + (end < p.length ? '-' : ''),
            );
            start += 2000;
          }
        } else {
          paragrafen.add(p);
        }
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: pw.EdgeInsets.zero,
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: pw.EdgeInsets.zero,
            buildBackground: (pw.Context context) {
              if (!isConcept) return pw.SizedBox.shrink();
              return pw.FullPage(
                ignoreMargins: true,
                child: pw.Center(
                  child: pw.Transform.rotateBox(
                    angle: 0.6,
                    child: pw.Text(
                      'CONCEPT EDITIE - GEEN RECHTEN AAN TE ONTLENEN',
                      style: pw.TextStyle(
                        color: conceptWatermarkColor,
                        fontSize: 45,
                        font: fontBold,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          header: buildFullBleedHeader,
          footer: buildFullBleedFooter,
          build: (pw.Context context) {
            final voorwaardenWidgets = <pw.Widget>[
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(40, 40, 40, 0),
                child: pw.Text(
                  'Algemene Voorwaarden',
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 16,
                    color: blueColor,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
            ];

            final tekstStijl = pw.TextStyle(
              font: fontRegular,
              fontSize: 5.5,
              color: PdfColors.grey800,
              lineSpacing: 1.2,
            );

            for (var i = 0; i < paragrafen.length; i += 3) {
              final p1 = paragrafen[i];
              final p2 = (i + 1 < paragrafen.length) ? paragrafen[i + 1] : '';
              final p3 = (i + 2 < paragrafen.length) ? paragrafen[i + 2] : '';

              voorwaardenWidgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(40, 0, 40, 12),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          p1,
                          style: tekstStijl,
                          textAlign: pw.TextAlign.justify,
                        ),
                      ),
                      pw.SizedBox(width: 16),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: lightGrey,
                            borderRadius: pw.BorderRadius.circular(8),
                          ),
                          child: pw.Text(
                            p2,
                            style: tekstStijl,
                            textAlign: pw.TextAlign.justify,
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 16),
                      pw.Expanded(
                        child: pw.Text(
                          p3,
                          style: tekstStijl,
                          textAlign: pw.TextAlign.justify,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return voorwaardenWidgets;
          },
        ),
      );
    }

    return pdf.save();
  }

  static List<Map<String, dynamic>> _dienstenVoorFrequentieLabel(
    List<Map<String, dynamic>> diensten,
    String label,
  ) {
    final heeftLabels = diensten.any(
      (d) => _text(d['frequentie_label']).isNotEmpty,
    );
    if (!heeftLabels) {
      switch (label) {
        case 'regulier':
          final reg =
              diensten.where((d) => d['in_regulier'] == true).toList();
          return reg.isEmpty ? diensten : reg;
        case 'frequent':
          return diensten.where((d) => d['in_frequent'] == true).toList();
        case 'periodiek':
          return diensten.where((d) => d['in_periodiek'] == true).toList();
        default:
          return [];
      }
    }
    if (label == 'regulier') {
      return diensten.where((d) {
        final fl = _text(d['frequentie_label']);
        return fl.isEmpty || fl == 'regulier';
      }).toList();
    }
    return diensten
        .where((d) => _text(d['frequentie_label']) == label)
        .toList();
  }

  static pw.Widget _buildFrequentieDienstenPane({
    required String titel,
    required List<Map<String, dynamic>> diensten,
    required PdfColor headerColor,
    required PdfColor bulletColor,
    required PdfColor bgColor,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Container(
      width: double.infinity,
      height: double.infinity,
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(16),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: headerColor,
              borderRadius: const pw.BorderRadius.vertical(
                top: pw.Radius.circular(16),
              ),
            ),
            child: pw.Text(
              titel,
              style: pw.TextStyle(
                font: fontBold,
                color: PdfColors.white,
                fontSize: 14,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(16),
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.topLeft,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: diensten
                      .map(
                        (d) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 6),
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                '• ',
                                style: pw.TextStyle(
                                  color: bulletColor,
                                  font: fontBold,
                                ),
                              ),
                              pw.Text(
                                _taakNaam(d),
                                style: pw.TextStyle(
                                  font: fontRegular,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _text(dynamic v, {String fallback = ''}) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  static pw.Widget _buildCheckItem(
    String svg,
    String tekst,
    pw.Font font,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 14,
            height: 14,
            child: pw.SvgImage(svg: svg),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              tekst,
              style: pw.TextStyle(
                font: font,
                fontSize: 10,
                color: PdfColors.grey800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _taakNaam(Map<String, dynamic> dienst) {
    final mb = dienst['moeder_bestek'];
    if (mb is Map) {
      final m = Map<String, dynamic>.from(mb);
      final String taakNaam = m['volledige_naam']?.toString() ??
          m['taak_naam']?.toString() ??
          m['taak']?.toString() ??
          m['naam']?.toString() ??
          'Schoonmaak dienst';
      final trimmed = taakNaam.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return 'Schoonmaak dienst';
  }

  static String _getCategoryDescription(String categorie) {
    final cat = categorie.toLowerCase();
    if (cat.contains('sanitair') || cat.contains('toilet')) {
      return 'Een schone sanitaire ruimte is cruciaal voor de gezondheid en hygiëne van uw medewerkers en gasten. Wist u dat gerichte reiniging ziekteverzuim kan verlagen? Wij zorgen voor een bacterievrije, frisse omgeving.';
    }
    if (cat.contains('kantoor') || cat.contains('werkplek')) {
      return 'Een opgeruimde werkplek verhoogt direct de productiviteit en focus. Wij zorgen voor een stofvrije, geordende en frisse omgeving waarin uw team optimaal kan presteren.';
    }
    if (cat.contains('vloer') || cat.contains('gang') || cat.contains('entree')) {
      return 'De entree en vloeren zijn het absolute visitekaartje van uw pand. Wij zorgen voor een stralende en representatieve uitstraling vanaf de eerste stap binnen.';
    }
    if (cat.contains('keuken') || cat.contains('pantry') || cat.contains('kantine')) {
      return 'In de kantine komen mensen samen om op te laden. Hygiëne is hier van het grootste belang. Wij reinigen grondig en zorgen voor een prettige pauze-omgeving.';
    }
    return 'Regelmatig en grondig onderhoud verlengt de levensduur van uw interieur en zorgt voor een uiterst representatieve, gezonde leef- en werkomgeving.';
  }

  static String _formatWeekdagen(dynamic raw) {
    if (raw is! List || raw.isEmpty) return 'In overleg';
    final parts = raw
        .map((d) {
          final s = d.toString().trim();
          if (s.isEmpty) return '';
          return s[0].toUpperCase() + s.substring(1).toLowerCase();
        })
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'In overleg' : parts.join(', ');
  }

  static pw.Widget _buildSleekTableRow(
    String left,
    String right,
    pw.Font labelFont,
    pw.Font valueFont,
  ) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              left,
              style: pw.TextStyle(
                font: labelFont,
                fontSize: 10,
              ),
            ),
          ),
          pw.Expanded(
            flex: 6,
            child: pw.Text(
              right,
              style: pw.TextStyle(font: valueFont, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
