import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Laadt gegevens voor het facilitator Contractbeheer-scherm.
///
/// Primaire bron: VIEW [app_contracten_dashboard] (aanbevolen in Supabase).
/// Fallback: direct [projecten] + join [bedrijven], [offertes].
class ContractsDashboardRepository {
  ContractsDashboardRepository({SupabaseClient? client})
      : _c = client ?? Supabase.instance.client;

  final SupabaseClient _c;

  static const viewName = 'app_contracten_dashboard';

  String _txt(dynamic v) => (v ?? '').toString().trim();

  double _dbl(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(_txt(v).replaceAll(',', '.')) ?? 0;
  }

  DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  /// Volledige contractrijen (+ raw voor updates).
  Future<List<Map<String, dynamic>>> fetchDashboardRows({
    required String userId,
    required bool facilitatorOnly,
  }) async {
    try {
      dynamic q = _c.from(viewName).select().limit(600);
      if (facilitatorOnly) {
        q = q.eq('facilitator_id', userId);
      }
      final res = await q;
      final rows = List<Map<String, dynamic>>.from(
        (res as List).map((r) => Map<String, dynamic>.from(r as Map)),
      );
      for (final m in rows) {
        m['_source'] = 'view';
      }
      return rows;
    } catch (e, st) {
      debugPrint('[ContractsDashboard] VIEW fallback: $e\n$st');
    }

    return _fetchFallbackFromProjecten(
      userId: userId,
      facilitatorOnly: facilitatorOnly,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchFallbackFromProjecten({
    required String userId,
    required bool facilitatorOnly,
  }) async {
    try {
      const sel =
          '*, bedrijven!inner(id, bedrijfsnaam), offertes(id, contract_type, maandprijs_ex_btw, maandprijs_inc_btw, maand_btw_bedrag, laatste_indexatie_op)';
      dynamic q = _c.from('projecten').select(sel).eq('status', 'actief');
      if (facilitatorOnly) q = q.eq('facilitator_id', userId);
      final res =
          await q.order('contract_einddatum', ascending: true).limit(600);
      final list = List<Map<String, dynamic>>.from(
        (res as List).map((r) => Map<String, dynamic>.from(r as Map)),
      );
      for (final m in list) {
        m['_source'] = 'fallback';
      }
      return list;
    } catch (e2, st2) {
      debugPrint('[ContractsDashboard] Loose join retry: $e2\n$st2');
      dynamic q = _c
          .from('projecten')
          .select('*, bedrijven(id, bedrijfsnaam), offertes(*)')
          .eq('status', 'actief');
      if (facilitatorOnly) q = q.eq('facilitator_id', userId);
      final res2 =
          await q.order('contract_einddatum', ascending: true).limit(600);
      final list = List<Map<String, dynamic>>.from(
        (res2 as List).map((r) => Map<String, dynamic>.from(r as Map)),
      );
      for (final m in list) {
        m['_source'] = 'fallback_loose';
      }
      return list;
    }
  }

  Future<void> extendProjectEndDate({
    required String projectId,
    required int yearsToAdd,
  }) async {
    final row = await _c
        .from('projecten')
        .select('contract_einddatum')
        .eq('id', projectId)
        .maybeSingle();
    if (row == null) throw StateError('Project niet gevonden');
    DateTime end = _dt(row['contract_einddatum']) ?? DateTime.now();
    final ne = DateTime(end.year + yearsToAdd, end.month, end.day);
    await _c.from('projecten').update({
      'contract_einddatum': ne.toIso8601String().split('T').first,
    }).eq('id', projectId);
  }

  /// Past maandtarieven op de offerte aan (factor op bekende monetäre kolommen).
  Future<void> indexOffertePrices({
    required String offerteId,
    required double pctIncrease,
  }) async {
    if (pctIncrease <= -100 || pctIncrease > 200) {
      throw ArgumentError.value(pctIncrease, 'pctIncrease');
    }
    final factor = 1 + pctIncrease / 100.0;

    final o =
        await _c.from('offertes').select().eq('id', offerteId).maybeSingle();
    if (o == null) throw StateError('Offerte niet gevonden');

    final ex = _dbl(o['maandprijs_ex_btw']);
    final btw = _dbl(o['maand_btw_bedrag']);
    final incl = _dbl(o['maandprijs_inc_btw']);

    final patch = <String, dynamic>{
      if (ex != 0 || incl != 0) 'maandprijs_ex_btw': ex * factor,
      if (btw != 0) 'maand_btw_bedrag': btw * factor,
      if (incl != 0) 'maandprijs_inc_btw': incl * factor,
      'laatste_indexatie_op': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await _c.from('offertes').update(patch).eq('id', offerteId);
    } catch (e) {
      patch.remove('laatste_indexatie_op');
      await _c.from('offertes').update(patch).eq('id', offerteId);
    }
  }

  /// Markeert project als niet meer actief.
  Future<void> terminateProject(String projectId) async {
    await _c.from('projecten').update({'status': 'beeindigd'}).eq('id', projectId);
  }

  Map<String, dynamic>? offerteFrom(Map<String, dynamic> row) {
    final o = row['offertes'];
    if (o is Map) return Map<String, dynamic>.from(o);
    if (o is List && o.isNotEmpty) {
      final f = o.first;
      if (f is Map) return Map<String, dynamic>.from(f);
    }
    return null;
  }

  /// Normaliseer naar UI (view-kolommen of fallback berekeningen).
  Map<String, dynamic> normalizeVm(Map<String, dynamic> row) {
    DateTime? end = _dt(row['contract_einddatum']);
    DateTime? start = _dt(row['contract_startdatum']);

    final offerte = offerteFrom(row);

    double? vmMrr = row['mrr_maand'] != null ? _dbl(row['mrr_maand']) : null;
    int? vmDaysLeft =
        row['dagen_tot_einde'] != null ? int.tryParse(_txt(row['dagen_tot_einde'])) : null;

    final ct = _txt(offerte?['contract_type']).toLowerCase();
    final vast = ct == 'vast';

    if (vmMrr == null && offerte != null) {
      final inc = _dbl(offerte['maandprijs_inc_btw']);
      final ex = _dbl(offerte['maandprijs_ex_btw']);
      vmMrr = inc > 0 ? inc : ex;
    }

    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (vmDaysLeft == null && end != null) {
      vmDaysLeft = DateTime(end.year, end.month, end.day).difference(today).inDays;
    }

    final lastIdx =
        _dt(row['laatste_indexatie_op']) ?? _dt(offerte?['laatste_indexatie_op']);

    var needsIdx = row['nog_te_indexeren'] == true ||
        row['nog_te_indexeren'] == 1 ||
        _txt(row['nog_te_indexeren']).toLowerCase() == 'true';

    if (!needsIdx && vast && start != null) {
      if (today.difference(DateTime(start.year, start.month, start.day)).inDays >
              364 &&
          (lastIdx == null ||
              today.difference(DateTime(lastIdx.year, lastIdx.month, lastIdx.day)).inDays >
                  364)) {
        needsIdx = true;
      }
    }

    final projectId = _txt(row['project_id']).isEmpty ? _txt(row['id']) : _txt(row['project_id']);

    final klant = _txt(row['klant_naam']).isEmpty
        ? () {
            final b = row['bedrijven'];
            if (b is Map) return _txt(b['bedrijfsnaam']);
            return '';
          }()
        : _txt(row['klant_naam']);

    final oid =
        offerte != null && _txt(offerte['id']).isNotEmpty ? _txt(offerte['id']) : _txt(row['offerte_id']);

    return <String, dynamic>{
      '_raw': row,
      'project_id': projectId.isNotEmpty ? projectId : null,
      'offerte_id': oid.isEmpty ? null : oid,
      'project_naam': _txt(row['project_naam']).isEmpty ? _txt(row['naam']) : _txt(row['project_naam']),
      'klant_naam': klant.isEmpty ? '—' : klant,
      'start': start,
      'einde': end,
      'days_left': vmDaysLeft,
      'mrr': vmMrr ?? 0.0,
      'is_vast': vast,
      'needs_index': needsIdx,
      '_lastIdx': lastIdx,
    };
  }
}
