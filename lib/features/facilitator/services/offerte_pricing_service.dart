import 'package:flutter/foundation.dart';

import '../../../core/supabase_client.dart';

/// Resultaat van de offerte-rekenmotor (ex. BTW).
class OfferteBerekenResult {
  const OfferteBerekenResult({
    required this.totaalExBtw,
    required this.totaleMinuten,
    required this.prijsPerBeurtExBtw,
    required this.periodeFactor,
    required this.contractType,
  });

  final double totaalExBtw;
  final double totaleMinuten;
  final double prijsPerBeurtExBtw;
  final double periodeFactor;
  final String contractType;
}

/// Offerte-prijzen:
/// - Vast/Flexibel: leidend = door Supabase berekende maandcomponenten (geen 52/12 in Dart).
/// - Incidenteel/Eenmalig: exact 1 beurt = minuten × uurtarief.
abstract final class OffertePricingService {
  static bool isAbonnement(String contractType) {
    final c = contractType.trim().toLowerCase();
    return c == 'vast' || c == 'flexibel';
  }

  static bool isLosseKlus(String contractType) {
    final c = contractType.trim().toLowerCase();
    return c == 'incidenteel' || c == 'eenmalig';
  }

  /// Leidend: [offerte]['contract_type'], met optionele hint uit UI-stream.
  static String contractTypeUitOfferte(
    Map<String, dynamic> offerte, {
    String? hint,
  }) {
    for (final raw in <dynamic>[
      hint,
      offerte['contract_type'],
      offerte['contractType'],
    ]) {
      if (raw == null) continue;
      final c = raw.toString().trim().toLowerCase();
      if (c.isNotEmpty) return c;
    }
    return 'vast';
  }

  static String prijsLabelExBtw(String contractType) {
    final c = contractType.trim().toLowerCase();
    if (c == 'incidenteel') return 'Prijs per beurt';
    if (c == 'eenmalig') return 'Totaalprijs';
    return 'Maandprijs';
  }

  static double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim().replaceAll(',', '.')) ?? 0;
  }

  static int _asInt(dynamic v, {int fallback = 1}) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString().trim()) ?? fallback;
  }

  /// Ex-BTW bedrag voor weergave (PDF / bottom bar).
  static double weergavePrijsExBtw(Map<String, dynamic> offerte) {
    final override = _asDouble(offerte['vaste_prijs_override']);
    if (override > 0) return override;
    return berekenTotalenUitMap(offerte).totaalExBtw;
  }

  /// Aggregatie op basis van reeds geladen offerte-map (zonder extra query).
  static OfferteBerekenResult berekenTotalenUitMap(
    Map<String, dynamic> offerte,
  ) {
    final cType = contractTypeUitOfferte(offerte);
    final losseKlus = isLosseKlus(cType);

    final rUren = _asDouble(offerte['regulier_uren_per_beurt_afgerond']);
    final fUren = _asDouble(offerte['frequent_uren_per_beurt_afgerond']);
    final pUren = _asDouble(offerte['periodiek_uren_per_beurt_afgerond']);
    final urenPerBeurt = rUren + fUren + pUren;

    final maandDb = _asDouble(offerte['maandprijs_ex_btw']);
    final totaalDb = _asDouble(offerte['totaal_prijs_ex_btw']);

    if (losseKlus) {
      // Alleen totaal_prijs_ex_btw; maandprijs_ex_btw is abonnementsveld (kan 52× zijn).
      final prijsPerBeurtExBtw = totaalDb > 0 ? totaalDb : 0.0;
      return OfferteBerekenResult(
        totaalExBtw: prijsPerBeurtExBtw,
        totaleMinuten: urenPerBeurt * 60.0,
        prijsPerBeurtExBtw: prijsPerBeurtExBtw,
        periodeFactor: 1.0,
        contractType: cType,
      );
    }

    // Vast / flexibel: leidend = maandprijs uit DB (zoals vóór client-side 52/12).
    final totaalExBtw = maandDb > 0 ? maandDb : totaalDb;
    return OfferteBerekenResult(
      totaalExBtw: totaalExBtw,
      totaleMinuten: urenPerBeurt * 60.0,
      prijsPerBeurtExBtw: totaalDb > 0 ? totaalDb : totaalExBtw,
      periodeFactor: 1.0,
      contractType: cType,
    );
  }

  /// Hoofd-rekenmotor: loop over ruimtes/diensten.
  ///
  /// [contractTypeHint]: contracttype uit de UI-stream als DB-rij nog leeg is.
  static Future<OfferteBerekenResult> berekenTotalen(
    String offerteId, {
    String? contractTypeHint,
  }) async {
    final offerteRaw = await AppSupabase.client
        .from('offertes')
        .select('*, bedrijven(*)')
        .eq('id', offerteId)
        .maybeSingle();
    if (offerteRaw == null) {
      return const OfferteBerekenResult(
        totaalExBtw: 0,
        totaleMinuten: 0,
        prijsPerBeurtExBtw: 0,
        periodeFactor: 1,
        contractType: 'vast',
      );
    }
    final offerte = Map<String, dynamic>.from(offerteRaw as Map);
    final String cType = contractTypeUitOfferte(
      offerte,
      hint: contractTypeHint,
    );
    final bool isLosseKlus = cType == 'incidenteel' || cType == 'eenmalig';

    debugPrint('--- CALCULATIE ENGINE X-RAY ---');
    debugPrint('Uitgelezen Contract Type: $cType');
    debugPrint('Wordt de 52x multiplier genegeerd? $isLosseKlus');
    debugPrint('-------------------------------');

    final bool inclusiefMaterialen = offerte['inclusief_materialen'] == true;

    final override = _asDouble(offerte['vaste_prijs_override']);
    if (override > 0) {
      return OfferteBerekenResult(
        totaalExBtw: override,
        totaleMinuten: 0,
        prijsPerBeurtExBtw: override,
        periodeFactor: 1.0,
        contractType: cType,
      );
    }

    final bedrijf = offerte['bedrijven'] is Map
        ? Map<String, dynamic>.from(offerte['bedrijven'] as Map)
        : null;
    var uurtarief = _uurtariefExBtw(offerte, bedrijf);
    if (uurtarief <= 0) {
      uurtarief = await _uurtariefUitEigenBedrijf();
    }

    final ruimtesRaw = await AppSupabase.client
        .from('offerte_ruimtes')
        .select('*, offerte_ruimte_diensten(*, moeder_bestek(*))')
        .eq('offerte_id', offerteId);

    // Altijd een verse lijst; nooit opstapelen met eerdere berekeningen.
    final ruimtesLijst = <Map<String, dynamic>>[];
    for (final raw in ruimtesRaw as List) {
      ruimtesLijst.add(Map<String, dynamic>.from(raw as Map));
    }

    final int werkdagenPerWeek = _werkdagenPerWeek(offerte);

    double periodiekPerMaand = 1.0 / 12.0;
    final String pFreq =
        (offerte['periodieke_frequentie'] ?? '1_keer_per_jaar').toString();
    switch (pFreq) {
      case '1_keer_per_jaar':
        periodiekPerMaand = 1.0 / 12.0;
        break;
      case '2_keer_per_jaar':
        periodiekPerMaand = 2.0 / 12.0;
        break;
      case '3_keer_per_jaar':
        periodiekPerMaand = 3.0 / 12.0;
        break;
      case '4_keer_per_jaar':
        periodiekPerMaand = 4.0 / 12.0;
        break;
      case '6_keer_per_jaar':
        periodiekPerMaand = 6.0 / 12.0;
        break;
      case '12_keer_per_jaar':
        periodiekPerMaand = 1.0;
        break;
    }

    // 1. Onafgeronde minuten per frequentie-emmer (per beurt, incl. identieke ruimtes).
    var rawRegulierMinuten = 0.0;
    var rawFrequentMinuten = 0.0;
    var rawPeriodiekMinuten = 0.0;

    for (final ruimte in ruimtesLijst) {
      final aantalIdentiek = _asInt(ruimte['aantal_identiek'], fallback: 1);
      final grootte = (ruimte['grootte_label'] ?? 'A').toString();

      final dienstenRaw = ruimte['offerte_ruimte_diensten'];
      final diensten = dienstenRaw is List
          ? dienstenRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];

      for (final dienst in diensten) {
        final mb = dienst['moeder_bestek'] is Map
            ? Map<String, dynamic>.from(dienst['moeder_bestek'] as Map)
            : <String, dynamic>{};

        final minutenPerBeurt = _minutenPerBeurt(
          dienst: dienst,
          moederBestek: mb,
          grootteLabel: grootte,
        );
        final minutenRegel = minutenPerBeurt * aantalIdentiek;

        if (isLosseKlus) {
          rawRegulierMinuten += minutenRegel;
        } else {
          final fLabel = _frequentieLabelVanDienst(dienst, mb);

          if (fLabel == 'regulier' || dienst['in_regulier'] == true) {
            rawRegulierMinuten += minutenRegel;
          } else if (fLabel == 'frequent' || dienst['in_frequent'] == true) {
            rawFrequentMinuten += minutenRegel;
          } else if (fLabel == 'periodiek' || dienst['in_periodiek'] == true) {
            rawPeriodiekMinuten += minutenRegel;
          } else {
            rawRegulierMinuten += minutenRegel;
          }
        }
      }
    }

    // 2. Afronden op kwartieren vóór prijsberekening.
    final regulierUrenAfgerond = _urenAfgerondOpKwartier(rawRegulierMinuten);
    final frequentUrenAfgerond = _urenAfgerondOpKwartier(rawFrequentMinuten);
    final periodiekUrenAfgerond = _urenAfgerondOpKwartier(rawPeriodiekMinuten);

    // 3. Prijs op basis van afgeronde uren.
    final double tarief = uurtarief;
    var nieuwTotaalExBtw = 0.0;
    var nieuweTotaleMinuten = 0.0;
    var ruweBeurtExBtw = 0.0;

    if (isLosseKlus) {
      nieuwTotaalExBtw = regulierUrenAfgerond * tarief;
      ruweBeurtExBtw = nieuwTotaalExBtw;
      nieuweTotaleMinuten = regulierUrenAfgerond * 60.0;
    } else {
      final beurtenRegulierPerMaand = (werkdagenPerWeek * 52.0) / 12.0;
      const beurtenFrequentPerMaand = 1.0;
      final beurtenPeriodiekPerMaand = periodiekPerMaand;

      nieuwTotaalExBtw += regulierUrenAfgerond * tarief * beurtenRegulierPerMaand;
      nieuwTotaalExBtw += frequentUrenAfgerond * tarief * beurtenFrequentPerMaand;
      nieuwTotaalExBtw += periodiekUrenAfgerond * tarief * beurtenPeriodiekPerMaand;

      ruweBeurtExBtw =
          (regulierUrenAfgerond + frequentUrenAfgerond + periodiekUrenAfgerond) *
          tarief;
      nieuweTotaleMinuten =
          regulierUrenAfgerond * 60.0 * beurtenRegulierPerMaand +
          frequentUrenAfgerond * 60.0 * beurtenFrequentPerMaand +
          periodiekUrenAfgerond * 60.0 * beurtenPeriodiekPerMaand;
    }

    if (inclusiefMaterialen) {
      if (isLosseKlus) {
        nieuwTotaalExBtw += 15.0;
        ruweBeurtExBtw += 15.0;
      } else {
        final totaalBeurtenPerMaand =
            ((werkdagenPerWeek * 52.0) / 12.0) + 1.0;
        nieuwTotaalExBtw += totaalBeurtenPerMaand * 15.0;
      }
    }

    debugPrint(
      'Uren afgerond (kwartier): regulier=$regulierUrenAfgerond '
      'frequent=$frequentUrenAfgerond periodiek=$periodiekUrenAfgerond → '
      '€${nieuwTotaalExBtw.toStringAsFixed(2)}',
    );

    if (nieuwTotaalExBtw <= 0) {
      final maandDb = _asDouble(offerte['maandprijs_ex_btw']);
      final totaalDb = _asDouble(offerte['totaal_prijs_ex_btw']);
      final urenPerBeurt =
          _asDouble(offerte['regulier_uren_per_beurt_afgerond']) +
          _asDouble(offerte['frequent_uren_per_beurt_afgerond']) +
          _asDouble(offerte['periodiek_uren_per_beurt_afgerond']);

      if (isLosseKlus) {
        ruweBeurtExBtw = totaalDb > 0 ? totaalDb : 0.0;
        nieuwTotaalExBtw = ruweBeurtExBtw;
        if (urenPerBeurt > 0) {
          nieuweTotaleMinuten = urenPerBeurt * 60.0;
        }
      } else {
        nieuwTotaalExBtw = maandDb > 0 ? maandDb : totaalDb;
        ruweBeurtExBtw = totaalDb > 0 ? totaalDb : nieuwTotaalExBtw;
        if (urenPerBeurt > 0) {
          nieuweTotaleMinuten = urenPerBeurt * 60.0;
        }
      }
    }

    return OfferteBerekenResult(
      totaalExBtw: nieuwTotaalExBtw,
      totaleMinuten: nieuweTotaleMinuten,
      prijsPerBeurtExBtw: ruweBeurtExBtw,
      periodeFactor: 1.0,
      contractType: cType,
    );
  }

  static Future<double> _uurtariefUitEigenBedrijf() async {
    try {
      final raw = await AppSupabase.client
          .from('eigen_bedrijfsgegevens')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (raw == null) return 0;
      return _uurtariefExBtw(const {}, Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      debugPrint('eigen_bedrijfsgegevens uurtarief: $e');
      return 0;
    }
  }

  static double _uurtariefExBtw(
    Map<String, dynamic> offerte,
    Map<String, dynamic>? bedrijf,
  ) {
    for (final key in [
      'regulier_gem_uurtarief',
      'uurloon',
      'klant_uurtarief',
      'uurtarief',
      'standaard_uurtarief',
    ]) {
      final v = _asDouble(offerte[key]);
      if (v > 0) return v;
    }
    if (bedrijf != null) {
      for (final key in [
        'regulier_gem_uurtarief',
        'uurloon',
        'standaard_uurtarief',
        'uurtarief',
      ]) {
        final v = _asDouble(bedrijf[key]);
        if (v > 0) return v;
      }
    }
    return 0;
  }

  /// Minuten → uren, afgerond op 0,25 uur.
  static double _urenAfgerondOpKwartier(double minuten) {
    if (minuten <= 0) return 0;
    return ((minuten / 60.0) * 4).roundToDouble() / 4.0;
  }

  static int _werkdagenPerWeek(Map<String, dynamic> offerte) {
    final raw = offerte['reguliere_weekdagen'];
    if (raw is List && raw.isNotEmpty) {
      return raw.length;
    }
    return 1;
  }

  static String _frequentieLabelVanDienst(
    Map<String, dynamic> dienst,
    Map<String, dynamic> moederBestek,
  ) {
    final raw = (dienst['frequentie_label'] ?? moederBestek['frequentie_label'])
        .toString()
        .trim()
        .toLowerCase();
    if (raw == 'regulier' || raw == 'frequent' || raw == 'periodiek') {
      return raw;
    }
    if (dienst['in_frequent'] == true) return 'frequent';
    if (dienst['in_periodiek'] == true) return 'periodiek';
    if (dienst['in_regulier'] == true) return 'regulier';
    return 'regulier';
  }

  static double _minutenPerBeurt({
    required Map<String, dynamic> dienst,
    required Map<String, dynamic> moederBestek,
    required String grootteLabel,
  }) {
    final g = grootteLabel.trim().toUpperCase();
    final suffix = g == 'B'
        ? '_b'
        : g == 'C'
        ? '_c'
        : '_a';
    final candidates = <String>[
      'norm_minuten$suffix',
      'minuten$suffix',
      'norm_minuten_${g.toLowerCase()}',
      'minuten_${g.toLowerCase()}',
      'norm_minuten',
      'standaard_minuten',
      'minuten',
      'tijd_minuten',
      'normtijd_minuten',
      'normtijd',
      'tijd_norm',
      'berekende_minuten',
    ];
    for (final key in candidates) {
      final v = _asDouble(dienst[key]);
      if (v > 0) return v;
      final mb = _asDouble(moederBestek[key]);
      if (mb > 0) return mb;
    }
    return 0;
  }

  /// Persisteert correcte totalen (na ruimte-wijziging of contracttype-wissel).
  static Future<void> herberekenEnPersist(String offerteId) async {
    if (offerteId.trim().isEmpty) return;

    final result = await berekenTotalen(offerteId);
    final btw = result.totaalExBtw * 0.21;
    final incl = result.totaalExBtw + btw;

    final totaalContractExBtw = isAbonnement(result.contractType)
        ? result.totaalExBtw
        : result.prijsPerBeurtExBtw;

    final update = <String, dynamic>{
      'totaal_prijs_ex_btw': totaalContractExBtw,
    };
    if (isAbonnement(result.contractType)) {
      update['maandprijs_ex_btw'] = result.totaalExBtw;
      update['maand_btw_bedrag'] = btw;
      update['maandprijs_inc_btw'] = incl;
    } else {
      update['maandprijs_ex_btw'] = 0;
      update['maand_btw_bedrag'] = 0;
      update['maandprijs_inc_btw'] = 0;
    }

    await AppSupabase.client.from('offertes').update(update).eq('id', offerteId);
  }
}
