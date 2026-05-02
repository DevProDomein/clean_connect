import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/contracts/tickets_contract.dart';

/// Data access voor het Tickets-dashboard (facilitator).
class TicketsRepository {
  TicketsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String _pick(Map<String, dynamic> row, List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final v = row[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return fallback;
  }

  DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  /// Alle tickets (sort meest recent eerst). Faalt zacht als tabel/RLS ontbreekt.
  Future<List<Map<String, dynamic>>> fetchTickets() async {
    try {
      try {
        final res = await _client
            .from(TicketsTable.name)
            .select()
            .order(TicketsTable.createdAt, ascending: false)
            .limit(500);

        return List<Map<String, dynamic>>.from(
          (res as List).map((r) => Map<String, dynamic>.from(r as Map)),
        );
      } catch (_) {
        // Kolomnamen verschillen per omgeving: zonder sortering proberen.
        final res = await _client.from(TicketsTable.name).select().limit(500);
        return List<Map<String, dynamic>>.from(
          (res as List).map((r) => Map<String, dynamic>.from(r as Map)),
        );
      }
    } catch (e, st) {
      debugPrint('[TicketsRepository] fetchTickets $e\n$st');
      rethrow;
    }
  }

  Future<void> updateTicket(String id, Map<String, dynamic> patch) async {
    await _client.from(TicketsTable.name).update(patch).eq(TicketsTable.id, id);
  }

  /// Collega's voor reassignment — facilitators/beheerders.
  Future<List<Map<String, dynamic>>> fetchStaffForAssignment() async {
    try {
      final res = await _client.from(GebruikersMetadataTable.name).select([
        GebruikersMetadataTable.id,
        GebruikersMetadataTable.naam,
        GebruikersMetadataTable.email,
        GebruikersMetadataTable.rol,
      ].join(', ')).order(GebruikersMetadataTable.naam, ascending: true);

      final all = List<Map<String, dynamic>>.from(
        (res as List).map((r) => Map<String, dynamic>.from(r as Map)),
      );
      bool staff(String? rol) {
        final x = rol?.trim().toLowerCase() ?? '';
        return x == 'facilitator' ||
            x == 'administrator' ||
            x == 'admin' ||
            x == 'beheerder' ||
            x == 'generator';
      }

      return all.where((row) => staff(row[GebruikersMetadataTable.rol]?.toString())).toList();
    } catch (e, st) {
      debugPrint('[TicketsRepository] fetchStaffForAssignment $e\n$st');
      return [];
    }
  }

  /// Genormaliseerd view-model voor één ticket-rij.
  Map<String, dynamic> normalizeRow(Map<String, dynamic> raw) {
    final id = _pick(raw, [TicketsTable.id], '');
    final code = _pick(raw,
        [TicketsTable.ticketNummer, 'ticket_nr', 'nummer'], '');
    final displayCode = code.isEmpty
        ? _fallbackCode(id)
        : code.toUpperCase().startsWith('TCK')
            ? code
            : 'TCK-$code';

    final onderwerp = _pick(
      raw,
      [TicketsTable.onderwerp, 'title', 'subject', 'kop'],
      'Geen onderwerp',
    );

    final bedrijf =
        _pick(raw, [TicketsTable.bedrijfsnaam, 'bedrijf', 'company_name'], '—');

    final catNorm = _normalizeCategory(
      _pick(raw, [TicketsTable.categorie, 'category', 'type'], 'overig'),
    );

    final statusNorm =
        _normalizeStatus(_pick(raw, [TicketsTable.status], 'open'));

    final bronNorm = _pick(raw, [TicketsTable.bron, 'source'], '');

    final assignee =
        _pick(raw, [TicketsTable.toegewezenAan, 'assigned_to'], '');

    DateTime? sla = _date(raw[TicketsTable.slaDeadline]) ??
        _date(raw['sla_deadline_at']) ??
        _date(raw['sla_eind']);

    final desc = _pick(
      raw,
      [
        TicketsTable.omschrijving,
        'description',
      ],
      '',
    );

    final foto = _pick(
      raw,
      [TicketsTable.fotoUrl, 'bijlage_url', 'image_url'],
      '',
    );

    final created =
        _date(raw[TicketsTable.createdAt]) ?? _date(raw['ingediend_op']);

    final resolved =
        _date(raw[TicketsTable.opgelostOp]) ?? _date(raw['resolved_at']);

    return {
      '_raw': raw,
      '_id': id,
      '_code': displayCode,
      '_onderwerp': onderwerp,
      '_bedrijf': bedrijf,
      '_categorie': catNorm,
      '_bron': bronNorm,
      '_status': statusNorm,
      '_assignee': assignee,
      '_sla': sla,
      '_desc': desc,
      '_foto': foto.isEmpty ? null : foto,
      '_created': created,
      '_resolved': resolved,
    };
  }

  String _fallbackCode(String uuid) {
    final s = uuid.replaceAll('-', '');
    final tail = s.length >= 6 ? s.substring(0, 6) : (s.padRight(6, '0')).substring(0, 6);
    final yr = DateTime.now().year;
    return 'TCK-$yr-${tail.toUpperCase()}';
  }

  String _normalizeCategory(String s) {
    final x = s.toLowerCase();
    if (x.contains('klacht') ||
        x.contains('complaint') ||
        x == 'klant') {
      return 'klacht';
    }
    if (x.contains('tech') ||
        x.contains('defect') ||
        x.contains('storing') ||
        x.contains('reparatie')) {
      return 'technisch';
    }
    if (x.contains('voorraad') ||
        x.contains('inventory') ||
        x.contains('materiaal') ||
        x.contains('bestel')) {
      return 'voorraad';
    }
    return 'overig';
  }

  String _normalizeStatus(String s) {
    final x = s.toLowerCase().replaceAll(' ', '_');
    if (x.contains('oplost') ||
        x == 'resolved' ||
        x == 'closed_done') {
      return 'opgelost';
    }
    if (x.contains('geslot') || x.contains('sloten')) {
      return 'gesloten';
    }
    if (x.contains('behandeling') ||
        x == 'busy' ||
        x == 'in_progress') {
      return 'in_behandeling';
    }
    if (x == 'nieuw') {
      return 'open';
    }
    return 'open';
  }
}
