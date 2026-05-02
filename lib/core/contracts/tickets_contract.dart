/// Facilitator module: incidenten (`tickets`) — kolommen spiegelen Supabase DDL.
abstract final class TicketsTable {
  static const String name = 'tickets';

  static const String id = 'id';
  /// Leesbare referentie, bijv. TCK-2026-042
  static const String ticketNummer = 'ticket_nummer';

  /// 'klacht' | 'technisch' | 'voorraad' (flexibel: ook Engelse synoniemen in mapper)
  static const String categorie = 'categorie';

  /// 'klant' | 'operator' | 'dks' — optioneel voor filters
  static const String bron = 'bron';

  static const String onderwerp = 'onderwerp';
  static const String omschrijving = 'omschrijving';

  /// 'open' | 'in_behandeling' | 'opgelost' | 'gesloten' — flexibel gegenereerde enum
  static const String status = 'status';

  static const String bedrijfsnaam = 'bedrijfsnaam';

  /// auth.users UUID
  static const String toegewezenAan = 'toegewezen_aan';

  /// timestamptz; trigger SLA-rekenaar
  static const String slaDeadline = 'sla_deadline';

  static const String fotoUrl = 'foto_url';
  static const String createdAt = 'created_at';
  static const String opgelostOp = 'opgelost_op';
}
