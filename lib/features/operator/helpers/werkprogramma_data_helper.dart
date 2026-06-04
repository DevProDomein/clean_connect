import 'package:supabase_flutter/supabase_flutter.dart';

/// Eén uit te voeren taak in het werkprogramma (per ruimte).
class WerkprogrammaTaakItem {
  const WerkprogrammaTaakItem({
    required this.key,
    required this.ruimteLabel,
    required this.taakNaam,
  });

  final String key;
  final String ruimteLabel;
  final String taakNaam;
}

const String _offerteRuimtesWerkprogrammaSelect = '''
          naam_in_pand, 
          ruimte_categorie,
          offerte_ruimte_diensten(
            frequentie_label,
            moeder_bestek(
              volledige_naam,
              bestek_materialen(
                materialen(*)
              )
            )
          )
        ''';

Map<String, dynamic> _mapFrom(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return {};
}

Map<String, dynamic> _moederBestekMap(dynamic mbRaw) {
  if (mbRaw is List && mbRaw.isNotEmpty) {
    return _mapFrom(mbRaw.first);
  }
  return _mapFrom(mbRaw);
}

String _taakNaamUitMoederBestek(Map<String, dynamic> mb) {
  for (final key in ['volledige_naam', 'naam', 'taak_naam']) {
    final v = mb[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return 'Dienst';
}

String? _offerteIdUitOpdrachtEmbed(Map<String, dynamic> opdrachtData) {
  final projectData = opdrachtData['projecten'];
  if (projectData == null) return null;
  if (projectData is List && projectData.isNotEmpty) {
    return _mapFrom(projectData.first)['offerte_id']?.toString();
  }
  if (projectData is Map) {
    return _mapFrom(projectData)['offerte_id']?.toString();
  }
  return null;
}

bool _isGeldigeOfferteId(String? id) {
  if (id == null) return false;
  final t = id.trim();
  return t.isNotEmpty && t.toLowerCase() != 'null';
}

/// Haalt alle actieve diensten/taken op voor een opdracht (gegroepeerd per ruimte).
Future<List<WerkprogrammaTaakItem>> fetchWerkprogrammaTaken(
  String opdrachtId, {
  SupabaseClient? client,
}) async {
  final supabase = client ?? Supabase.instance.client;

  final opd = await supabase
      .from('opdrachten')
      .select('frequentie_type, project_id, projecten(offerte_id)')
      .eq('id', opdrachtId)
      .maybeSingle();

  if (opd == null) return const [];

  final opdrachtMap = _mapFrom(opd);
  var freqType = opdrachtMap['frequentie_type']?.toString().toLowerCase() ?? '';
  final offerteId = _offerteIdUitOpdrachtEmbed(opdrachtMap);

  if ((freqType == 'incidenteel' || freqType == 'eenmalig') &&
      _isGeldigeOfferteId(offerteId)) {
    freqType = 'regulier';
  }
  if (!_isGeldigeOfferteId(offerteId)) return const [];

  final ruimtes = await supabase
      .from('offerte_ruimtes')
      .select(_offerteRuimtesWerkprogrammaSelect)
      .eq('offerte_id', offerteId!);

  final taken = <WerkprogrammaTaakItem>[];

  for (final ruimte in ruimtes as List) {
    if (ruimte is! Map) continue;
    final ruimteMap = _mapFrom(ruimte);
    final ruimteLabel = ruimteMap['naam_in_pand']?.toString() ??
        ruimteMap['ruimte_categorie']?.toString() ??
        'Ruimte';

    final dienstenRaw = ruimteMap['offerte_ruimte_diensten'];
    final diensten = dienstenRaw is List
        ? dienstenRaw
        : (dienstenRaw != null ? [dienstenRaw] : []);

    for (final d in diensten) {
      if (d is! Map) continue;
      final dienst = _mapFrom(d);
      final fLabel =
          dienst['frequentie_label']?.toString().toLowerCase() ?? 'regulier';
      var isActief = false;
      if (freqType == 'regulier' && fLabel == 'regulier') isActief = true;
      if (freqType == 'frequent' && fLabel == 'frequent') isActief = true;
      if (freqType == 'periodiek' && fLabel == 'periodiek') isActief = true;
      if ((freqType == 'incidenteel' || freqType == 'eenmalig') &&
          fLabel == 'regulier') {
        isActief = true;
      }
      if (!isActief || dienst['moeder_bestek'] == null) continue;

      final mb = _moederBestekMap(dienst['moeder_bestek']);
      final taakNaam = _taakNaamUitMoederBestek(mb);
      final key = '$ruimteLabel|$taakNaam';
      if (taken.any((t) => t.key == key)) continue;
      taken.add(
        WerkprogrammaTaakItem(
          key: key,
          ruimteLabel: ruimteLabel,
          taakNaam: taakNaam,
        ),
      );
    }
  }

  return taken;
}
