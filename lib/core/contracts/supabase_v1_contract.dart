// CleanConnect Data Mapping & API Contract (V1.0)
//
// Harde afspraken tussen Supabase en Flutter — geen gokwerk op tabel-/kolomnamen.
// Permissie-strings in de database zijn lowercase; de app vergelijkt ook lowercase.

// --- Identity: master `gebruikers` ---

abstract final class GebruikersTable {
  static const String name = 'gebruikers';

  static const String id = 'id';
  static const String email = 'email';
  static const String gebruikersrol = 'gebruikersrol';
  static const String voornaam = 'voornaam';
  static const String achternaam = 'achternaam';
}

// --- Identity: read-mirror `gebruikers_metadata` ---

abstract final class GebruikersMetadataTable {
  static const String name = 'gebruikers_metadata';

  static const String id = 'id';
  static const String naam = 'naam';
  static const String email = 'email';
  static const String rol = 'rol';
}

// --- Security: permissions ---

abstract final class FinancePermissionsTable {
  static const String name = 'finance_permissions';

  /// Unieke permissie-string (bijv. `portal_admin`, `manage_invoices`).
  static const String naam = 'naam';

  static const String id = 'id';
}

abstract final class GebruikerFinanceRechtenTable {
  static const String name = 'gebruiker_finance_rechten';

  static const String gebruikerId = 'gebruiker_id';
  static const String permissieId = 'permissie_id';
}

// --- App settings ---

abstract final class AppSettingsTable {
  static const String name = 'app_settings';

  /// Contract: setting key column = `sleutel`.
  static const String sleutel = 'sleutel';

  /// Contract: JSON value column = `waarde`.
  static const String waarde = 'waarde';
}

// --- Module 2.1: vier-ogen ---

abstract final class MasterDataWijzigingsverzoekenTable {
  static const String name = 'master_data_wijzigingsverzoeken';

  static const String id = 'id';
  static const String tabelNaam = 'tabel_naam';
  static const String veldNaam = 'veld_naam';
  static const String oudeWaarde = 'oude_waarde';
  static const String nieuweWaarde = 'nieuwe_waarde';
  static const String ingediendDoorId = 'ingediend_door_id';
  static const String status = 'status';
}
