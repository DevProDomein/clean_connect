/// Gedeelde loonberekening: werkelijke tijden → decimale uren, bruto per maand.
abstract final class PayrollCalculation {
  static String? _effectieveTijd(
    Map<String, dynamic> taak,
    String werkelijkKey,
    String geplandKey,
  ) {
    final werkelijk = taak[werkelijkKey]?.toString().trim();
    if (werkelijk != null && werkelijk.isNotEmpty && werkelijk.contains(':')) {
      return werkelijk;
    }
    final gepland = taak[geplandKey]?.toString().trim();
    if (gepland != null && gepland.isNotEmpty && gepland.contains(':')) {
      return gepland;
    }
    return null;
  }

  /// Gewerkte uren uit werkelijke tijden (HH:mm), anders geplande `starttijd`/`eindtijd`.
  static double gewerkteUrenUitTaak(Map<String, dynamic> taak) {
    // Pak de werkelijke tijd, en val anders terug op de geplande tijd
    final startStr = _effectieveTijd(taak, 'werkelijke_starttijd', 'starttijd');
    final eindStr = _effectieveTijd(taak, 'werkelijke_eindtijd', 'eindtijd');

    if (startStr == null || eindStr == null) {
      return 0.0;
    }

    try {
      final startParts = startStr.split(':');
      final eindParts = eindStr.split(':');

      final startMinuten =
          (int.parse(startParts[0]) * 60) + int.parse(startParts[1]);
      final eindMinuten = (int.parse(eindParts[0]) * 60) + int.parse(eindParts[1]);

      var gewerkteMinuten = eindMinuten - startMinuten;
      if (gewerkteMinuten < 0) {
        gewerkteMinuten += 24 * 60;
      }

      return gewerkteMinuten / 60.0;
    } catch (_) {
      return 0.0;
    }
  }

  static double totaalGewerkteUren(
    Iterable<Map<String, dynamic>> geaccordeerdeTaken,
  ) {
    var totaal = 0.0;
    for (final taak in geaccordeerdeTaken) {
      totaal += gewerkteUrenUitTaak(taak);
    }
    return totaal;
  }

  static double? tryParseDouble(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }

  /// Standaard uurloon uit `gebruikers.standaard_uurloon` (geen €20-default).
  static double resolveUurloon(Map<String, dynamic> operatorData) {
    final ruwUurloon =
        operatorData['standaard_uurloon']?.toString().replaceAll(',', '.') ??
        '0';
    return double.tryParse(ruwUurloon) ?? 0.0;
  }

  static double parseContractBedrag(dynamic raw) {
    final ruw = raw?.toString().replaceAll(',', '.') ?? '0';
    return double.tryParse(ruw) ?? 0.0;
  }

  static DateTime? parseContractDatum(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final d = DateTime.tryParse(s.length >= 10 ? s.substring(0, 10) : s);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  static bool isGeldigVastContractVoorMaand(
    Map<String, dynamic> operatorData,
    DateTime focusedDay,
  ) {
    final vasteUren = tryParseDouble(operatorData['contract_vaste_uren']) ?? 0.0;
    final vastSalaris =
        tryParseDouble(operatorData['contract_vast_salaris']) ?? 0.0;
    if (vasteUren <= 0 || vastSalaris <= 0) return false;

    final eersteDagVanMaand = DateTime(focusedDay.year, focusedDay.month, 1);
    final laatsteDagVanMaand = DateTime(
      focusedDay.year,
      focusedDay.month + 1,
      0,
    );

    final contractStart = parseContractDatum(operatorData['contract_startdatum']);
    final contractEind = parseContractDatum(operatorData['contract_einddatum']);

    final startIsGoed =
        contractStart != null && !contractStart.isAfter(laatsteDagVanMaand);
    final eindIsGoed =
        contractEind == null || !contractEind.isBefore(eersteDagVanMaand);

    return startIsGoed && eindIsGoed;
  }

  static double berekenBruto({
    required bool isGeldigVastContract,
    required double totaalGewerkteUren,
    required Map<String, dynamic> operatorData,
    required double uurTarief,
  }) {
    final vastSalaris = parseContractBedrag(operatorData['contract_vast_salaris']);
    final vasteUren = parseContractBedrag(operatorData['contract_vaste_uren']);

    if (isGeldigVastContract) {
      final overwerkUren = totaalGewerkteUren > vasteUren
          ? (totaalGewerkteUren - vasteUren)
          : 0.0;
      return vastSalaris + (overwerkUren * uurTarief);
    }

    return totaalGewerkteUren * uurTarief;
  }
}
