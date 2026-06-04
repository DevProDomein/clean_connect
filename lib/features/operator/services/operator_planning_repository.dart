import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../shared/services/werkbon_pdf_service.dart';

/// Database-updates en ophalen van operator-planning.
class OperatorPlanningRepository {
  OperatorPlanningRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _roosterPlanningSelect = '''
id,
opdracht_id,
${OpdrachtPlanningTable.geplandeDatum},
${OpdrachtPlanningTable.starttijd},
${OpdrachtPlanningTable.eindtijd},
${OpdrachtPlanningTable.status},
${OpdrachtPlanningTable.urenStatus},
${OpdrachtPlanningTable.operatorId},
opdracht:opdrachten!opdracht_planning_opdracht_id_fkey(
  id,
  ${OpdrachtenTable.status},
  ${OpdrachtenTable.bedrijfsnaam},
  ${OpdrachtenTable.uitvoerAdresVolledig},
  projecten(pand_foto_url)
)
''';

  static String _vandaagDateString([DateTime? reference]) {
    final d = reference ?? DateTime.now();
    final local = DateTime(d.year, d.month, d.day);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Vandaag/toekomst én openstaande vergeten opdrachten uit het verleden.
  Future<List<Map<String, dynamic>>> fetchRoosterPlanningForOperator(
    String operatorId,
  ) async {
    if (operatorId.isEmpty) return const [];

    final vandaagStr = _vandaagDateString();
    final afgerond = OpdrachtPlanningStatus.afgerond;
    final orFilter =
        '${OpdrachtPlanningTable.geplandeDatum}.gte.$vandaagStr,'
        'and(${OpdrachtPlanningTable.geplandeDatum}.lt.$vandaagStr,'
        '${OpdrachtPlanningTable.status}.neq.$afgerond)';

    final res = await _client
        .from(OpdrachtPlanningTable.name)
        .select(_roosterPlanningSelect)
        .eq(OpdrachtPlanningTable.operatorId, operatorId)
        .or(orFilter)
        .order(OpdrachtPlanningTable.geplandeDatum, ascending: true)
        .order(OpdrachtPlanningTable.starttijd, ascending: true);

    return (res as List)
        .map((e) => normaliseRoosterPlanningRow(e as Map))
        .toList(growable: false);
  }

  /// Zelfde shape als [app_operator_agenda] voor rooster/slider UI.
  static Map<String, dynamic> normaliseRoosterPlanningRow(Map row) {
    final map = Map<String, dynamic>.from(row);
    final planningId = (map[OpdrachtPlanningTable.id] ?? '').toString().trim();
    if (planningId.isNotEmpty) {
      map['planning_id'] = planningId;
    }

    map['rooster_starttijd'] ??= map[OpdrachtPlanningTable.starttijd];
    map['rooster_eindtijd'] ??= map[OpdrachtPlanningTable.eindtijd];

    final opdracht = map['opdracht'];
    if (opdracht is Map) {
      final o = Map<String, dynamic>.from(opdracht);
      map['opdracht'] = o;
      map['bedrijfsnaam'] ??= o[OpdrachtenTable.bedrijfsnaam];
      map['uitvoer_adres_volledig'] ??= o[OpdrachtenTable.uitvoerAdresVolledig];
      map['opdracht_id'] ??= o[OpdrachtenTable.id];
    }

    final status =
        (map[OpdrachtPlanningTable.status] ?? '').toString().trim().toLowerCase();
    map['planning_status'] ??= status;
    map['status'] ??= status;
    map['mijn_persoonlijke_status'] ??= _persoonlijkeStatusLabel(status);
    return map;
  }

  static String _persoonlijkeStatusLabel(String status) {
    if (status == OpdrachtPlanningStatus.afgerond ||
        status == OpdrachtPlanningStatus.voltooid) {
      return 'voltooid';
    }
    if (status.contains('uitvoering')) return 'in_uitvoering';
    if (status == OpdrachtPlanningStatus.ingepland) return 'gepland';
    return status.isEmpty ? 'gepland' : status;
  }

  Future<void> markPlanningAndOpdrachtAfgerond({
    required String planningId,
    required String opdrachtId,
  }) async {
    if (planningId.isEmpty) {
      throw ArgumentError('planningId is verplicht.');
    }
    if (opdrachtId.isEmpty) {
      throw ArgumentError('opdrachtId is verplicht.');
    }

    await _client
        .from(OpdrachtPlanningTable.name)
        .update({
          OpdrachtPlanningTable.status: OpdrachtPlanningStatus.afgerond,
        })
        .eq(OpdrachtPlanningTable.id, planningId);

    await _client
        .from(OpdrachtenTable.name)
        .update({OpdrachtenTable.status: OpdrachtStatus.afgerond})
        .eq(OpdrachtenTable.id, opdrachtId);

    unawaited(
      WerkbonPdfService.generateAndUploadWerkbon(opdrachtId).then((url) {
        if (url == null) {
          debugPrint(
            'Werkbon upload na afronden mislukt voor opdracht $opdrachtId',
          );
        }
      }),
    );
  }
}
