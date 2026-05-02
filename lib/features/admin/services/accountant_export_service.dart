import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';

import '../../../core/supabase_client.dart';

class AccountantExportService {
  static String _text(dynamic v) => (v ?? '').toString().trim();

  static Future<bool> generateAndDownloadExport(Map<String, dynamic> period) async {
    try {
      final currentUser = AppSupabase.client.auth.currentUser;
      if (currentUser == null) return false;

      final jaar = (period['jaar'] is num)
          ? (period['jaar'] as num).toInt()
          : int.tryParse(_text(period['jaar'])) ?? 0;
      final maand = (period['maand'] is num)
          ? (period['maand'] as num).toInt()
          : int.tryParse(_text(period['maand'])) ?? 0;
      final periodId = _text(period['id']);
      if (jaar <= 0 || maand <= 0 || maand > 12 || periodId.isEmpty) return false;

      final start = DateTime(jaar, maand, 1);
      final end = DateTime(jaar, maand + 1, 1);

      // Mapping: interne_code -> accountant_code
      final mappingRes = await AppSupabase.client.from('grootboek_export_mapping').select();
      final mappingRows = (mappingRes as List).cast<Map<String, dynamic>>();
      final mapping = <String, String>{};
      for (final r in mappingRows) {
        final k = _text(r['interne_code']);
        final v = _text(r['accountant_code']);
        if (k.isNotEmpty && v.isNotEmpty) mapping[k] = v;
      }

      // Sales (verkoop) lines joined with invoice metadata.
      final verkoopRes = await AppSupabase.client
          .from('factuur_regels')
          .select('artikel_code, omschrijving, totaal_ex_btw, btw_percentage, facturen!inner('
              'factuur_datum, factuur_nummer, status, debiteur_naam'
              ')')
          .eq('facturen.status', 'definitief')
          .gte('facturen.factuur_datum', start.toIso8601String())
          .lt('facturen.factuur_datum', end.toIso8601String());
      final verkoopLines = (verkoopRes as List).cast<Map<String, dynamic>>();

      // Purchases (inkoop) split lines joined with invoice + vendor.
      final inkoopRes = await AppSupabase.client
          .from('inkoopfactuur_split_regels')
          .select('interne_code, grootboek_code, omschrijving, bedrag_ex_btw, btw_percentage, '
              'inkoopfacturen!inner(factuur_datum, factuur_nummer_leverancier, status, '
              'bedrijven(bedrijfsnaam))')
          .inFilter('inkoopfacturen.status', const ['goedgekeurd', 'betaald'])
          .gte('inkoopfacturen.factuur_datum', start.toIso8601String())
          .lt('inkoopfacturen.factuur_datum', end.toIso8601String());
      final inkoopLines = (inkoopRes as List).cast<Map<String, dynamic>>();

      final csvData = <List<dynamic>>[];
      csvData.add([
        'Datum',
        'Factuurnummer',
        'Relatie',
        'Type',
        'Grootboek_Accountant',
        'Omschrijving',
        'Bedrag_Ex_Btw',
        'Btw_Percentage',
      ]);

      String fmtDate(dynamic v) => _text(v).split('T').first;

      // Map sales lines.
      for (final l in verkoopLines) {
        final inv = l['facturen'];
        if (inv is! Map) continue;

        final datum = fmtDate(inv['factuur_datum']);
        final factuurnr = _text(inv['factuur_nummer']);
        final relatie = _text(inv['debiteur_naam']);

        final artikelCode = _text(l['artikel_code']);
        final ledger = mapping[artikelCode] ?? (artikelCode.isNotEmpty ? artikelCode : '8000');
        final oms = _text(l['omschrijving']);
        final bedragEx = _asDouble(l['totaal_ex_btw']);
        final btwPct = _text(l['btw_percentage']);

        csvData.add([
          datum,
          factuurnr,
          relatie,
          'Verkoop',
          ledger,
          oms,
          bedragEx.toStringAsFixed(2),
          btwPct,
        ]);
      }

      // Map purchase lines.
      for (final l in inkoopLines) {
        final inv = l['inkoopfacturen'];
        if (inv is! Map) continue;

        final datum = fmtDate(inv['factuur_datum']);
        final factuurnr = _text(inv['factuur_nummer_leverancier']);
        final vendor = (inv['bedrijven'] is Map) ? _text((inv['bedrijven'] as Map)['bedrijfsnaam']) : '';

        final interne = _text(l['interne_code']).isNotEmpty
            ? _text(l['interne_code'])
            : (_text(l['grootboek_code']).isNotEmpty ? _text(l['grootboek_code']) : _text(l['omschrijving']));
        final ledger = mapping[interne] ?? (interne.isNotEmpty ? interne : '7000');

        final oms = _text(l['omschrijving']);
        final bedragEx = _asDouble(l['bedrag_ex_btw']);
        final btwPct = _text(l['btw_percentage']);

        csvData.add([
          datum,
          factuurnr,
          vendor,
          'Inkoop',
          ledger.isEmpty ? '7000' : ledger,
          oms,
          bedragEx.toStringAsFixed(2),
          btwPct,
        ]);
      }

      final csvString = const ListToCsvConverter().convert(csvData);
      final bytes = Uint8List.fromList(utf8.encode(csvString));

      await FileSaver.instance.saveFile(
        name: 'CleanConnect_Export_${jaar}_${maand.toString().padLeft(2, '0')}',
        bytes: bytes,
        ext: 'csv',
        mimeType: MimeType.custom,
        customMimeType: 'text/csv',
      );

      await AppSupabase.client.from('accountant_export_logs').insert({
        'financiele_periode_id': periodId,
        'geexporteerd_door_id': currentUser.id,
        'jaar': jaar,
        'maand': maand,
        'aantal_records_geexporteerd': csvData.length - 1,
      });

      return true;
    } catch (e, st) {
      // ignore: avoid_print
      print('accountant export error: $e\n$st');
      return false;
    }
  }

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }
}

