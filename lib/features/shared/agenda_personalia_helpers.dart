import '../../core/supabase_client.dart';

/// Helpers voor [agenda_items] + [agenda_deelnemers] (persoonlijke agenda / interne meetings).
abstract final class AgendaPersonaliaHelpers {
  static String t(dynamic v) => (v ?? '').toString().trim();

  /// Geneste [agenda_deelnemers] veilig als lijst van maps.
  static List<Map<String, dynamic>> deelnemersLijst(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    }
    if (raw is Map) {
      return [Map<String, dynamic>.from(raw)];
    }
    return const [];
  }

  /// Zichtbaar in kalenderlijst: maker altijd; deelnemer alleen bij [geaccepteerd].
  static bool magTonenInAgenda({
    required Map<String, dynamic> item,
    required String userId,
  }) {
    final maker = t(item['maker_id']);
    if (maker == userId) return true;
    for (final d in deelnemersLijst(item['agenda_deelnemers'])) {
      if (t(d['gebruiker_id']) == userId &&
          t(d['status']).toLowerCase() == 'geaccepteerd') {
        return true;
      }
    }
    return false;
  }

  /// Openstaande uitnodiging voor [userId].
  static Map<String, dynamic>? mijnDeelnemerUitgenodigd(
    Map<String, dynamic> item,
    String userId,
  ) {
    for (final d in deelnemersLijst(item['agenda_deelnemers'])) {
      if (t(d['gebruiker_id']) == userId &&
          t(d['status']).toLowerCase() == 'uitgenodigd') {
        return d;
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> filterVoorWeergave(
    List<Map<String, dynamic>> raw,
    String userId,
  ) {
    return raw.where((e) => magTonenInAgenda(item: e, userId: userId)).toList();
  }

  static List<Map<String, dynamic>> inboxUitgenodigd(
    List<Map<String, dynamic>> raw,
    String userId,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (mijnDeelnemerUitgenodigd(e, userId) != null) {
        out.add(e);
      }
    }
    return out;
  }

  /// Haal agenda-items op waarbij gebruiker maker of deelnemer is.
  static Future<List<Map<String, dynamic>>> fetchAgendaItemsVoorGebruiker(
    String userId,
  ) async {
    final res = await AppSupabase.client
        .from('agenda_items')
        .select('*, agenda_deelnemers(gebruiker_id, status)')
        .or('maker_id.eq.$userId,agenda_deelnemers.gebruiker_id.eq.$userId');

    final list = (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    return list;
  }

  static Future<void> updateDeelnemerStatus({
    required String itemId,
    required String gebruikerId,
    required String status,
  }) async {
    await AppSupabase.client
        .from('agenda_deelnemers')
        .update({'status': status})
        .eq('item_id', itemId)
        .eq('gebruiker_id', gebruikerId);
  }

  /// Voor [PlanningAgendaScreen] / app_facilitator_agenda-achtige tegels.
  static Map<String, dynamic> normaliseerVoorControlRoom(
    Map<String, dynamic> item,
  ) {
    final type = t(item['type']).toLowerCase();
    final kleur = switch (type) {
      'meeting' => 'oranje',
      'taak' => 'blauw',
      'notitie' => 'groen',
      _ => 'blauw',
    };
    final datum = item['datum'] ?? item['geplande_datum'];
    return {
      ...item,
      'geplande_datum': datum,
      'starttijd': item['starttijd'],
      'eindtijd': item['eindtijd'],
      'project_naam': t(item['titel']).isEmpty ? 'Agenda-item' : t(item['titel']),
      'bedrijfsnaam': 'Persoonlijke agenda',
      'werk_regio': 'Intern',
      'operator_namen': '—',
      'geplande_operators_aantal': '0',
      'benodigde_operators': '0',
      'agenda_kleur': kleur,
      'planning_status': type,
      '_persoonlijk_agenda': true,
    };
  }

  /// Voor [AgendaScreen] (facilitator persoonlijke agenda-lijst).
  static Map<String, dynamic> normaliseerVoorFacilitatorMijnAgenda(
    Map<String, dynamic> item,
  ) {
    final datum = item['datum'] ?? item['geplande_datum'];
    return {
      ...item,
      'geplande_datum': datum,
      'agenda_datum': datum,
      'datum': datum,
      'tijdslot_start': item['starttijd'],
      'tijdslot_eind': item['eindtijd'],
      'starttijd': item['starttijd'],
      'eindtijd': item['eindtijd'],
      'titel': t(item['titel']).isEmpty ? 'Agenda-item' : t(item['titel']),
      'afspraak_type': 'intern',
      '_persoonlijk_agenda': true,
    };
  }

  /// Voor [OperatorAgendaScreen] (kalender + lijst).
  static Map<String, dynamic> normaliseerVoorOperatorAgenda(
    Map<String, dynamic> item,
  ) {
    final datum = item['datum'] ?? item['geplande_datum'];
    return {
      ...item,
      'geplande_datum': datum,
      'datum': datum,
      'starttijd': item['starttijd'],
      'eindtijd': item['eindtijd'],
      'project_naam': t(item['titel']).isEmpty ? 'Agenda-item' : t(item['titel']),
      'bedrijfsnaam': 'Intern',
      'adres': t(item['beschrijving']),
      'planning_status': t(item['type']).isEmpty ? 'Intern' : t(item['type']),
      '_persoonlijk_agenda': true,
    };
  }
}
