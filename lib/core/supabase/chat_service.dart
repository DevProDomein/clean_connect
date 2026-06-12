import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

/// Real-time chat voor klant-tickets (`tickets`, `ticket_deelnemers`, `ticket_berichten`).
class ChatService {
  static const String chatMediaBucket = 'chat_media';

  String? get _currentUserId => AppSupabase.client.auth.currentUser?.id;

  /// Leest berichttekst (`bericht_inhoud` of legacy `inhoud`).
  static String leesBerichtInhoud(Map<String, dynamic> bericht) {
    final raw = bericht['bericht_inhoud'] ?? bericht['inhoud'];
    return (raw ?? '').toString();
  }

  static bool isBerichtVerwijderd(Map<String, dynamic> bericht) {
    final v = bericht['is_verwijderd'];
    if (v is bool) return v;
    if (v == null) return false;
    final s = v.toString().toLowerCase();
    return s == 'true' || s == '1' || s == 't';
  }

  static bool isBerichtBewerkt(Map<String, dynamic> bericht) {
    final v = bericht['is_bewerkt'];
    if (v is bool) return v;
    if (v == null) return false;
    final s = v.toString().toLowerCase();
    return s == 'true' || s == '1' || s == 't';
  }

  final Map<String, Map<String, dynamic>> _gebruikerCache = {};

  Stream<List<Map<String, dynamic>>> streamBerichtenForTicket(String ticketId) {
    try {
      return AppSupabase.client
          .from('ticket_berichten')
          .stream(primaryKey: ['id'])
          .eq('ticket_id', ticketId)
          .order('verzonden_op', ascending: false)
          .asyncMap(_enrichBerichtenMetGebruikers);
    } catch (e, stack) {
      debugPrint('ChatService.streamBerichtenForTicket: $e\n$stack');
      return Stream.value(const <Map<String, dynamic>>[]);
    }
  }

  Future<List<Map<String, dynamic>>> _enrichBerichtenMetGebruikers(
    List<Map<String, dynamic>> rows,
  ) async {
    final seen = <String>{};
    final list = <Map<String, dynamic>>[];
    for (final row in rows) {
      final m = Map<String, dynamic>.from(row);
      final id = (m['id'] ?? '').toString();
      if (id.isNotEmpty) {
        if (seen.contains(id)) continue;
        seen.add(id);
      }
      list.add(m);
    }

    final missingIds = <String>{};
    for (final b in list) {
      final afzenderId = (b['afzender_id'] ?? '').toString().trim();
      if (afzenderId.isEmpty || _gebruikerCache.containsKey(afzenderId)) {
        continue;
      }
      missingIds.add(afzenderId);
    }

    if (missingIds.isNotEmpty) {
      try {
        final users = await AppSupabase.client
            .from('gebruikers')
            .select('id, voornaam, achternaam, rol')
            .inFilter('id', missingIds.toList());
        for (final row in users as List) {
          if (row is! Map) continue;
          final m = Map<String, dynamic>.from(row);
          final uid = (m['id'] ?? '').toString();
          if (uid.isNotEmpty) _gebruikerCache[uid] = m;
        }
      } catch (e) {
        debugPrint('ChatService: gebruikers lookup mislukt: $e');
      }
    }

    return list.map((b) {
      final afzenderId = (b['afzender_id'] ?? '').toString().trim();
      final gebruiker = _gebruikerCache[afzenderId];
      if (gebruiker == null) return b;
      return {
        ...b,
        'gebruikers': Map<String, dynamic>.from(gebruiker),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> fetchMijnChats() async {
    try {
      final user = AppSupabase.client.auth.currentUser;
      if (user == null) return [];

      // RLS filtert automatisch de tickets die bij het bedrijf van deze klant horen.
      final response = await AppSupabase.client
          .from('tickets')
          .select('''
            *,
            ticket_berichten (
              bericht_inhoud,
              verzonden_op,
              is_gelezen,
              afzender_id
            )
          ''')
          .inFilter('categorie', ['project_chat', 'direct_chat'])
          .order('aangemaakt_op', ascending: false);

      final chats = _parseTicketRows(response);
      return _sortChatsOpLaatsteBericht(chats);
    } catch (e) {
      debugPrint('Fout bij ophalen project chats: $e');
      return [];
    }
  }

  /// Facilitator-inbox: alle project/direct chats (RLS filtert voor staf).
  Future<List<Map<String, dynamic>>> fetchFacilitatorChats() async {
    try {
      final user = AppSupabase.client.auth.currentUser;
      if (user == null) return [];

      final response = await AppSupabase.client
          .from('tickets')
          .select(
            '*, bedrijven(bedrijfsnaam), projecten(project_naam), '
            'ticket_berichten(bericht_inhoud, verzonden_op, is_gelezen, afzender_id)',
          )
          .inFilter('categorie', ['project_chat', 'direct_chat'])
          .order('aangemaakt_op', ascending: false);

      final chats = _parseTicketRows(response);
      return _sortChatsOpLaatsteBericht(chats);
    } catch (e) {
      debugPrint('Fout bij ophalen facilitator chats: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _parseTicketRows(dynamic response) {
    return (response as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Recente berichten van operators (werkvloer-meldingen in project-chats).
  Future<List<Map<String, dynamic>>> fetchOperatorMeldingen({
    int limit = 100,
  }) async {
    try {
      List<Map<String, dynamic>> allMessages;

      try {
        final response = await AppSupabase.client
            .from('ticket_berichten')
            .select('''
              *,
              tickets!inner(project_id, onderwerp, categorie),
              gebruikers (
                voornaam, achternaam, rol, gebruikersrol
              )
            ''')
            .eq('tickets.categorie', 'project_chat')
            .order('verzonden_op', ascending: false)
            .limit(100);

        allMessages = _parseBerichtRows(response);
      } catch (e) {
        debugPrint('ChatService.fetchOperatorMeldingen (embedded filter): $e');
        final response = await AppSupabase.client
            .from('ticket_berichten')
            .select('''
              *,
              tickets(project_id, onderwerp, categorie),
              gebruikers (
                voornaam, achternaam, rol, gebruikersrol
              )
            ''')
            .order('verzonden_op', ascending: false)
            .limit(200);

        allMessages = _parseBerichtRows(response)
            .where(_isProjectChatBericht)
            .toList();
      }

      return allMessages.where(_isOperatorBericht).take(limit).toList();
    } catch (e, stack) {
      debugPrint('Fout bij ophalen operator meldingen: $e\n$stack');
      return [];
    }
  }

  List<Map<String, dynamic>> _parseBerichtRows(dynamic response) {
    return (response as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((b) => !isBerichtVerwijderd(b))
        .toList();
  }

  static const _operatorRollen = {'operator', 'schoonmaker'};

  static bool _isOperatorBericht(Map<String, dynamic> bericht) {
    final raw = bericht['gebruikers'];
    if (raw is Map) {
      return _isOperatorGebruiker(raw);
    }
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return _isOperatorGebruiker(raw.first as Map);
    }
    return false;
  }

  static bool _isOperatorGebruiker(Map user) {
    final rol = _textRol(user['rol']);
    final gebruikersrol = _textRol(user['gebruikersrol']);
    return _operatorRollen.contains(rol) ||
        _operatorRollen.contains(gebruikersrol);
  }

  static bool _isProjectChatBericht(Map<String, dynamic> bericht) {
    final raw = bericht['tickets'];
    if (raw is Map) {
      return _textRol(raw['categorie']) == 'project_chat';
    }
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return _textRol((raw.first as Map)['categorie']) == 'project_chat';
    }
    return false;
  }

  static String _textRol(dynamic v) => (v ?? '').toString().trim().toLowerCase();

  List<Map<String, dynamic>> _sortChatsOpLaatsteBericht(
    List<Map<String, dynamic>> chats,
  ) {
    chats.sort((a, b) {
      final berichtenA = a['ticket_berichten'] as List<dynamic>? ?? [];
      final berichtenB = b['ticket_berichten'] as List<dynamic>? ?? [];

      DateTime dateA;
      if (berichtenA.isNotEmpty) {
        dateA = DateTime.parse(berichtenA.last['verzonden_op'].toString());
      } else {
        dateA = DateTime.parse(a['aangemaakt_op'].toString());
      }

      DateTime dateB;
      if (berichtenB.isNotEmpty) {
        dateB = DateTime.parse(berichtenB.last['verzonden_op'].toString());
      } else {
        dateB = DateTime.parse(b['aangemaakt_op'].toString());
      }

      return dateB.compareTo(dateA);
    });
    return chats;
  }

  Future<void> markeerAlsGelezen(String ticketId) async {
    try {
      final myId = _currentUserId;
      if (myId == null) return;

      await AppSupabase.client
          .from('ticket_berichten')
          .update({'is_gelezen': true})
          .eq('ticket_id', ticketId)
          .eq('is_gelezen', false)
          .neq('afzender_id', myId);
    } catch (e) {
      debugPrint('Fout bij markeren als gelezen: $e');
    }
  }

  Stream<int> streamTotalUnreadCount() {
    final myId = _currentUserId;
    if (myId == null) return Stream.value(0);

    try {
      return AppSupabase.client
          .from('ticket_berichten')
          .stream(primaryKey: ['id'])
          .map(
            (berichten) => berichten
                .where(
                  (b) =>
                      _isOngelezenVoorGebruiker(b, myId),
                )
                .length,
          );
    } catch (e, stack) {
      debugPrint('ChatService.streamTotalUnreadCount: $e\n$stack');
      return Stream.value(0);
    }
  }

  static bool _isOngelezenVoorGebruiker(
    Map<String, dynamic> bericht,
    String myId,
  ) {
    final afzender = (bericht['afzender_id'] ?? '').toString();
    if (afzender == myId) return false;
    final gelezen = bericht['is_gelezen'];
    if (gelezen is bool) return !gelezen;
    if (gelezen == null) return true;
    final s = gelezen.toString().toLowerCase();
    return s != 'true' && s != '1' && s != 't';
  }

  /// Operator-melding injecteren in de preset project-chat via RPC (RLS-safe).
  Future<void> verstuurOperatorMeldingInProjectChat({
    required String projectId,
    required String opdrachtNummer,
    required String tekst,
  }) async {
    if (_currentUserId == null) {
      throw StateError('Geen ingelogde gebruiker.');
    }
    final bericht = tekst.trim();
    if (bericht.isEmpty) {
      throw ArgumentError('Melding mag niet leeg zijn.');
    }
    final pid = projectId.trim();
    if (pid.isEmpty) {
      debugPrint(
        'Kan melding niet versturen: Geen project_id gevonden bij deze opdracht.',
      );
      throw ArgumentError('Geen project gekoppeld aan deze opdracht.');
    }

    try {
      final werkbonLabel =
          opdrachtNummer.trim().isEmpty ? '—' : opdrachtNummer.trim();
      final compleetBericht =
          '🏢 *Melding vanuit uitvoering (Werkbon $werkbonLabel)*\n\n$bericht';

      final success = await AppSupabase.client.rpc(
        'stuur_operator_project_melding',
        params: {
          'p_project_id': pid,
          'p_bericht': compleetBericht,
        },
      );

      if (success != true) {
        throw Exception('RPC retourneerde false');
      }

      debugPrint('Melding veilig opgeslagen via RPC.');
    } catch (e, stack) {
      debugPrint('Fatale fout bij plaatsen operator melding: $e\n$stack');
      rethrow;
    }
  }

  Future<void> verstuurBericht(
    String ticketId,
    String inhoud, {
    String? mediaUrl,
  }) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw StateError('Geen ingelogde gebruiker.');
    }
    final tekst = inhoud.trim();
    if (tekst.isEmpty && (mediaUrl == null || mediaUrl.trim().isEmpty)) {
      throw ArgumentError('Bericht mag niet leeg zijn.');
    }

    try {
      await AppSupabase.client.from('ticket_berichten').insert({
        'ticket_id': ticketId,
        'afzender_id': uid,
        'bericht_inhoud': tekst,
        if (mediaUrl != null && mediaUrl.trim().isNotEmpty)
          'media_url': mediaUrl.trim(),
      });
    } catch (e, stack) {
      debugPrint('ChatService.verstuurBericht: $e\n$stack');
      rethrow;
    }
  }

  Future<void> editBericht(String berichtId, String nieuweTekst) async {
    final id = berichtId.trim();
    if (id.isEmpty) {
      throw ArgumentError('Bericht-id ontbreekt.');
    }
    final tekst = nieuweTekst.trim();
    if (tekst.isEmpty) {
      throw ArgumentError('Bericht mag niet leeg zijn.');
    }

    try {
      await AppSupabase.client.from('ticket_berichten').update({
        'bericht_inhoud': tekst,
        'is_bewerkt': true,
      }).eq('id', id);
    } catch (e, stack) {
      debugPrint('ChatService.editBericht: $e\n$stack');
      rethrow;
    }
  }

  Future<void> deleteBericht(String berichtId) async {
    final id = berichtId.trim();
    if (id.isEmpty) {
      throw ArgumentError('Bericht-id ontbreekt.');
    }

    try {
      await AppSupabase.client.from('ticket_berichten').update({
        'is_verwijderd': true,
      }).eq('id', id);
    } catch (e, stack) {
      debugPrint('ChatService.deleteBericht: $e\n$stack');
      rethrow;
    }
  }

  /// Upload chatfoto naar [chatMediaBucket] en retourneer de public URL.
  Future<String> uploadChatFoto(XFile imageFile) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw StateError('Geen ingelogde gebruiker.');
    }

    try {
      final bytes = await imageFile.readAsBytes();
      if (bytes.isEmpty) {
        throw ArgumentError('Leeg afbeeldingsbestand.');
      }

      final name = imageFile.name.trim();
      var ext = 'jpg';
      if (name.contains('.')) {
        ext = name.split('.').last.toLowerCase();
      }
      if (ext != 'png' && ext != 'webp' && ext != 'gif') {
        ext = 'jpg';
      }

      final contentType = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };

      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = '$uid/$fileName';

      await AppSupabase.client.storage.from(chatMediaBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: contentType,
            ),
          );

      return AppSupabase.client.storage
          .from(chatMediaBucket)
          .getPublicUrl(path);
    } catch (e, stack) {
      debugPrint('ChatService.uploadChatFoto: $e\n$stack');
      rethrow;
    }
  }

  Future<String> maakNieuwTicketAan({
    required String onderwerp,
    required String categorie,
    String? opdrachtId,
    String? projectId,
  }) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw StateError('Geen ingelogde gebruiker.');
    }

    final titel = onderwerp.trim();
    if (titel.isEmpty) {
      throw ArgumentError('Onderwerp is verplicht.');
    }

    try {
      final insertPayload = <String, dynamic>{
        'onderwerp': titel,
        'categorie': categorie.trim().isEmpty ? 'algemeen' : categorie.trim(),
        'status': 'open',
        'bron': 'klant',
        'gemeld_door_id': uid,
        if (opdrachtId != null && opdrachtId.isNotEmpty)
          'gekoppelde_opdracht_id': opdrachtId,
        if (projectId != null && projectId.isNotEmpty) 'project_id': projectId,
      };

      final ticketRow = await AppSupabase.client
          .from('tickets')
          .insert(insertPayload)
          .select('id')
          .single();

      final ticketId = ticketRow['id']?.toString();
      if (ticketId == null || ticketId.isEmpty) {
        throw StateError('Geen ticket-id teruggekregen.');
      }

      await AppSupabase.client.from('ticket_deelnemers').insert({
        'ticket_id': ticketId,
        'gebruiker_id': uid,
      });

      return ticketId;
    } catch (e, stack) {
      debugPrint('ChatService.maakNieuwTicketAan: $e\n$stack');
      rethrow;
    }
  }
}
