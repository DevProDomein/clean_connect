import 'package:flutter/foundation.dart';

import '../../../core/supabase_client.dart';

/// Eén regel uit [offerte_glasbewassing].
class OfferteGlasRegel {
  const OfferteGlasRegel({
    this.id,
    this.naam = 'Glasbewassing',
    this.moederBestekIds = const [],
    this.moederBestekId,
    this.omschrijving = '',
    this.klein = 0,
    this.middel = 0,
    this.groot = 0,
    this.frequentie = 'op_afroep',
    this.moederBestek,
  });

  final String? id;
  final String naam;
  final List<String> moederBestekIds;
  /// Legacy enkelvoudige koppeling.
  final String? moederBestekId;
  final String omschrijving;
  final int klein;
  final int middel;
  final int groot;
  final String frequentie;
  final Map<String, dynamic>? moederBestek;

  factory OfferteGlasRegel.fromMap(Map<String, dynamic> row) {
    final ids = <String>[];
    final rawIds = row['moeder_bestek_ids'];
    if (rawIds is List) {
      for (final raw in rawIds) {
        final id = raw?.toString().trim() ?? '';
        if (id.isNotEmpty) ids.add(id);
      }
    }
    final legacyId = row['moeder_bestek_id']?.toString().trim() ?? '';
    if (ids.isEmpty && legacyId.isNotEmpty) {
      ids.add(legacyId);
    }

    final naamRaw = (row['naam'] ?? row['omschrijving'] ?? '').toString().trim();

    return OfferteGlasRegel(
      id: row['id']?.toString(),
      naam: naamRaw.isEmpty ? 'Glasbewassing' : naamRaw,
      moederBestekIds: ids,
      moederBestekId: legacyId.isEmpty ? null : legacyId,
      omschrijving: (row['omschrijving'] ?? '').toString().trim(),
      klein: OffertePricingService._asInt(row['aantal_klein']),
      middel: OffertePricingService._asInt(row['aantal_middel']),
      groot: OffertePricingService._asInt(row['aantal_groot']),
      frequentie: (row['frequentie'] ?? 'op_afroep').toString().trim(),
    );
  }

  bool get heeftRamen => klein > 0 || middel > 0 || groot > 0;
}

/// Berekende glascomponent (uren + prijs per beurt + maandgemiddelde).
class GlasBerekenResult {
  const GlasBerekenResult({
    required this.urenPerBeurt,
    required this.prijsPerBeurt,
    required this.maandPrijs,
  });

  final double urenPerBeurt;
  final double prijsPerBeurt;
  final double maandPrijs;
}

/// Resultaat van de offerte-rekenmotor (ex. BTW).
class OfferteBerekenResult {
  const OfferteBerekenResult({
    required this.totaalExBtw,
    required this.totaleMinuten,
    required this.prijsPerBeurtExBtw,
    required this.periodeFactor,
    required this.contractType,
    this.glasUrenPerBeurt = 0,
  });

  final double totaalExBtw;
  final double totaleMinuten;
  final double prijsPerBeurtExBtw;
  final double periodeFactor;
  final String contractType;
  final double glasUrenPerBeurt;
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

  static Future<List<OfferteGlasRegel>> fetchGlasRegels(String offerteId) async {
    if (offerteId.trim().isEmpty) return const [];
    try {
      final raw = await AppSupabase.client
          .from('offerte_glasbewassing')
          .select('*')
          .eq('offerte_id', offerteId)
          .order('aangemaakt_op', ascending: true);
      return (raw as List)
          .map((e) => OfferteGlasRegel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } catch (e) {
      debugPrint('offerte_glasbewassing laden: $e');
      return const [];
    }
  }

  static double _minutenNormGlas(
    Map<String, dynamic>? moeder, {
    required String suffix,
    required double fallback,
  }) {
    if (moeder == null) return fallback;
    for (final key in ['norm_minuten$suffix', 'minuten$suffix']) {
      final v = _asDouble(moeder[key]);
      if (v > 0) return v;
    }
    return fallback;
  }

  static Future<Map<String, Map<String, dynamic>>> _glasBestekLookup() async {
    try {
      var raw = await AppSupabase.client
          .from('moeder_bestek')
          .select('id, volledige_naam, norm_minuten_a, norm_minuten_b, norm_minuten_c, minuten_a, minuten_b, minuten_c')
          .eq('is_glasbewassing', true);

      if ((raw as List).isEmpty) {
        raw = await AppSupabase.client
            .from('moeder_bestek')
            .select('id, volledige_naam, norm_minuten_a, norm_minuten_b, norm_minuten_c, minuten_a, minuten_b, minuten_c')
            .or('ruimte.ilike.%glas%,volledige_naam.ilike.%glasbewassing%');
      }

      final map = <String, Map<String, dynamic>>{};
      for (final row in raw as List) {
        final m = Map<String, dynamic>.from(row as Map);
        final id = m['id']?.toString() ?? '';
        if (id.isNotEmpty) map[id] = m;
      }
      return map;
    } catch (e) {
      debugPrint('glas bestek lookup: $e');
      return {};
    }
  }

  static double _minutenVoorBestekEnRamen(
    Map<String, dynamic>? mb,
    int klein,
    int middel,
    int groot,
  ) {
    final minK = _minutenNormGlas(mb, suffix: '_a', fallback: 2);
    final minM = _minutenNormGlas(mb, suffix: '_b', fallback: 4);
    final minG = _minutenNormGlas(mb, suffix: '_c', fallback: 6);
    return klein * minK + middel * minM + groot * minG;
  }

  /// Minuten per beurt (som over geselecteerde diensten × ramen).
  static double glasMinutenPerBeurt(
    OfferteGlasRegel regel, {
    Map<String, Map<String, dynamic>>? bestekById,
  }) {
    final ids = regel.moederBestekIds;
    if (ids.isEmpty) {
      return _minutenVoorBestekEnRamen(
        regel.moederBestek,
        regel.klein,
        regel.middel,
        regel.groot,
      );
    }

    var totaal = 0.0;
    for (final id in ids) {
      totaal += _minutenVoorBestekEnRamen(
        bestekById?[id],
        regel.klein,
        regel.middel,
        regel.groot,
      );
    }
    return totaal;
  }

  static double glasUrenPerBeurtUitRegel(
    OfferteGlasRegel regel, {
    Map<String, Map<String, dynamic>>? bestekById,
  }) {
    return glasMinutenPerBeurt(regel, bestekById: bestekById) / 60.0;
  }

  static double _glasMaandPrijsFactor(String glasFrequentie) {
    switch (glasFrequentie) {
      case '12_keer_per_jaar':
        return 1.0;
      case '6_keer_per_jaar':
        return 6.0 / 12.0;
      case '4_keer_per_jaar':
        return 4.0 / 12.0;
      case '2_keer_per_jaar':
        return 2.0 / 12.0;
      case '1_keer_per_jaar':
        return 1.0 / 12.0;
      default:
        return 0.0;
    }
  }

  /// Ruimte uit [offerte_ruimtes] met categorie Glasbewassing.
  static bool isGlasRuimte(Map<String, dynamic> ruimte) {
    return (ruimte['ruimte_categorie'] ?? '').toString().trim() ==
        'Glasbewassing';
  }

  /// Minuten per beurt uit glas-tellers op de ruimte (2 / 4 / 6 min).
  static double glasMinutenVanRuimte(Map<String, dynamic> ruimte) {
    final k = _asInt(ruimte['glas_aantal_klein']);
    final m = _asInt(ruimte['glas_aantal_middel']);
    final g = _asInt(ruimte['glas_aantal_groot']);
    return (k * 2.0) + (m * 4.0) + (g * 6.0);
  }

  static String glasFrequentieVanRuimte(Map<String, dynamic> ruimte) {
    return (ruimte['specifieke_frequentie'] ?? 'op_afroep').toString().trim();
  }

  /// Glasbewassing: prijs per beurt en maandgemiddelde (ex. BTW) voor één regel.
  static GlasBerekenResult berekenGlasRegel(
    OfferteGlasRegel regel,
    double uurtarief, {
    Map<String, Map<String, dynamic>>? bestekById,
  }) {
    final glasUrenPerBeurt =
        glasUrenPerBeurtUitRegel(regel, bestekById: bestekById);
    final glasPrijsPerBeurt = glasUrenPerBeurt * uurtarief;
    final glasMaandPrijs =
        glasPrijsPerBeurt * _glasMaandPrijsFactor(regel.frequentie);
    return GlasBerekenResult(
      urenPerBeurt: glasUrenPerBeurt,
      prijsPerBeurt: glasPrijsPerBeurt,
      maandPrijs: glasMaandPrijs,
    );
  }

  static GlasBerekenResult _telGlasRegelsOp(
    List<OfferteGlasRegel> regels,
    double uurtarief, {
    Map<String, Map<String, dynamic>>? bestekById,
  }) {
    var uren = 0.0;
    var prijsBeurt = 0.0;
    var maand = 0.0;
    for (final regel in regels) {
      if (!regel.heeftRamen) continue;
      final c = berekenGlasRegel(regel, uurtarief, bestekById: bestekById);
      uren += c.urenPerBeurt;
      prijsBeurt += c.prijsPerBeurt;
      maand += c.maandPrijs;
    }
    return GlasBerekenResult(
      urenPerBeurt: uren,
      prijsPerBeurt: prijsBeurt,
      maandPrijs: maand,
    );
  }

  static Future<void> _persistGlasRegelBerekeningen({
    required String offerteId,
    required List<OfferteGlasRegel> regels,
    required double uurtarief,
    required bool isLosseKlus,
    Map<String, Map<String, dynamic>>? bestekById,
  }) async {
    final lookup = bestekById ?? await _glasBestekLookup();
    for (final regel in regels) {
      if (regel.id == null || regel.id!.isEmpty) continue;
      final comp = berekenGlasRegel(regel, uurtarief, bestekById: lookup);
      final prijs = isLosseKlus ? comp.prijsPerBeurt : comp.maandPrijs;
      await AppSupabase.client.from('offerte_glasbewassing').update({
        'berekende_minuten': glasMinutenPerBeurt(regel, bestekById: lookup),
        'berekende_prijs': prijs,
      }).eq('id', regel.id!);
    }
  }

  /// Hoofd-rekenmotor: loop over ruimtes/diensten.
  ///
  /// [contractTypeHint]: contracttype uit de UI-stream als DB-rij nog leeg is.
  /// [glasRegels]: optionele UI-cache; anders uit [offerte_glasbewassing].
  static Future<OfferteBerekenResult> berekenTotalen(
    String offerteId, {
    String? contractTypeHint,
    List<OfferteGlasRegel>? glasRegels,
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
        glasUrenPerBeurt: 0,
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
        glasUrenPerBeurt: 0,
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
    var glasPrijsBeurtTotaal = 0.0;
    var glasMaandPrijsTotaal = 0.0;
    var glasUrenPerBeurtTotaal = 0.0;
    var heeftGlasRuimteMetTelling = false;

    for (final ruimte in ruimtesLijst) {
      if (isGlasRuimte(ruimte)) {
        final minutenTotaal = glasMinutenVanRuimte(ruimte);
        if (minutenTotaal <= 0) continue;
        heeftGlasRuimteMetTelling = true;

        final prijsBeurt = (minutenTotaal / 60.0) * uurtarief;
        final freqMult =
            _glasMaandPrijsFactor(glasFrequentieVanRuimte(ruimte));
        glasUrenPerBeurtTotaal += minutenTotaal / 60.0;

        if (isLosseKlus) {
          glasPrijsBeurtTotaal += prijsBeurt;
        } else {
          glasMaandPrijsTotaal += prijsBeurt * freqMult;
        }
        continue;
      }

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

    if (isLosseKlus) {
      nieuwTotaalExBtw += glasPrijsBeurtTotaal;
      ruweBeurtExBtw += glasPrijsBeurtTotaal;
      nieuweTotaleMinuten += glasUrenPerBeurtTotaal * 60.0;
    } else {
      nieuwTotaalExBtw += glasMaandPrijsTotaal;
      nieuweTotaleMinuten += glasUrenPerBeurtTotaal * 60.0;
    }

    var glasUrenResult = glasUrenPerBeurtTotaal;
    if (!heeftGlasRuimteMetTelling) {
      final glasRegelsLijst = glasRegels ?? await fetchGlasRegels(offerteId);
      final glasBestekById = await _glasBestekLookup();
      final glas = _telGlasRegelsOp(
        glasRegelsLijst,
        tarief,
        bestekById: glasBestekById,
      );
      if (isLosseKlus) {
        nieuwTotaalExBtw += glas.prijsPerBeurt;
        ruweBeurtExBtw += glas.prijsPerBeurt;
      } else {
        nieuwTotaalExBtw += glas.maandPrijs;
      }
      glasUrenResult = glas.urenPerBeurt;
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
      glasUrenPerBeurt: glasUrenResult,
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
  static Future<void> herberekenEnPersist(
    String offerteId, {
    List<OfferteGlasRegel>? glasRegels,
  }) async {
    if (offerteId.trim().isEmpty) return;

    final result = await berekenTotalen(
      offerteId,
      glasRegels: glasRegels,
    );
    final btw = result.totaalExBtw * 0.21;
    final incl = result.totaalExBtw + btw;

    final totaalContractExBtw = isAbonnement(result.contractType)
        ? result.totaalExBtw
        : result.prijsPerBeurtExBtw;

    final update = <String, dynamic>{
      'totaal_prijs_ex_btw': totaalContractExBtw,
    };

    final regels = glasRegels ?? await fetchGlasRegels(offerteId);
    if (regels.isNotEmpty) {
      final bestekById = await _glasBestekLookup();
      await _persistGlasRegelBerekeningen(
        offerteId: offerteId,
        regels: regels,
        uurtarief: await _uurtariefVoorOfferte(offerteId),
        isLosseKlus: isLosseKlus(result.contractType),
        bestekById: bestekById,
      );
    }
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

  /// Uurtarief (ex. BTW) voor glas-sync vanuit de UI.
  static Future<double> uurtariefVoorOfferte(String offerteId) =>
      _uurtariefVoorOfferte(offerteId);

  /// Moederbestek lookup voor glas-minuten per dienst.
  static Future<Map<String, Map<String, dynamic>>> glasBestekLookup() =>
      _glasBestekLookup();

  static Future<double> _uurtariefVoorOfferte(String offerteId) async {
    final raw = await AppSupabase.client
        .from('offertes')
        .select('*, bedrijven(*)')
        .eq('id', offerteId)
        .maybeSingle();
    if (raw == null) return 0;
    final offerte = Map<String, dynamic>.from(raw as Map);
    final bedrijf = offerte['bedrijven'] is Map
        ? Map<String, dynamic>.from(offerte['bedrijven'] as Map)
        : null;
    var tarief = _uurtariefExBtw(offerte, bedrijf);
    if (tarief <= 0) {
      tarief = await _uurtariefUitEigenBedrijf();
    }
    return tarief;
  }
}
