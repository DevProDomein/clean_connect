class AppTexts {
  static const String localeNl = 'nl';

  static const Map<String, Map<String, String>> _t = {
    localeNl: {
      // App / general
      'app_title': 'CleanConnect ERP',
      'loading': 'Bezig met laden…',
      'unknown_error': 'Er is een onverwachte fout opgetreden.',
      'button_sign_out': 'Uitloggen',

      // Auth
      'login_title': 'Inloggen bij CleanConnect',
      'email_label': 'E-mailadres',
      'password_label': 'Wachtwoord',
      'button_login': 'Inloggen',
      'button_wait': 'Even geduld…',
      'button_forgot_password': 'Wachtwoord vergeten',
      'login_success': 'U bent ingelogd.',
      'login_failed': 'Inloggen is mislukt. Controleer uw gegevens en probeer het opnieuw.',
      'reset_email_missing': 'Vul eerst uw e-mailadres in.',
      'reset_sent': 'Er is een e-mail verstuurd om uw wachtwoord te resetten.',
      'reset_failed': 'Het versturen van de resetmail is mislukt. Probeer het later opnieuw.',

      // Role / routing
      'role_lookup_failed_title': 'Rol ophalen mislukt',
      'role_lookup_failed_body':
          'De rol kon niet worden opgehaald uit de database. Controleer de verbinding en rechten.',
      'unknown_role_title': 'Onbekende rol',
      'unknown_role_body':
          'Er is geen herkende rol gevonden in `gebruikers` of `gebruikers_metadata` (contract V1.0).',
      'logged_in_as': 'Ingelogd als:',
      'role_value_was': 'Rolwaarde was:',

      // Dashboards
      'admin_finance_title': 'Beheer • Financiën',
      'operator_dashboard_title': 'Operator-dashboard',
      'client_dashboard_title': 'Klant-dashboard',
      'facilitator_dashboard_title': 'Facilitator-dashboard',
      'coming_soon': 'Deze portal volgt binnenkort.',

      // Finance dashboard sections
      'finance_bank_matcher_title': 'Bankmatcher',
      'finance_no_transactions': 'Geen transacties gevonden.',
      'finance_auto_match': 'Automatisch matchen',
      'finance_auto_match_todo': 'Automatisch matchen wordt hierna geïmplementeerd.',
      'finance_scan_recognize_title': 'Scannen & herkennen',
      'finance_take_photo': 'Foto maken',
      'finance_upload_photo': 'Foto uploaden',
      'finance_take_upload_hint':
          'Voor foto’s uploaden/maken voegen we later een pakket toe (bijv. image_picker of file_picker).',
      'finance_no_ocr_scans': 'Nog geen OCR-scans.',
      'finance_quarterly_reports_title': 'Kwartaalrapportages',
      'finance_no_quarterly': 'Geen kwartaalgegevens beschikbaar.',
      'finance_quarter_fallback': 'Kwartaal',
      'finance_revenue': 'Omzet',
      'finance_costs': 'Kosten',
      'finance_net': 'Nettoresultaat',
    },
  };

  static String get(String key, {String locale = localeNl}) {
    return _t[locale]?[key] ?? _t[localeNl]?[key] ?? key;
  }
}

