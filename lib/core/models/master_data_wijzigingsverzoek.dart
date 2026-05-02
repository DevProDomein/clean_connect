import '../contracts/supabase_v1_contract.dart';

/// Rij uit [MasterDataWijzigingsverzoekenTable.name] (vier-ogen, contract V1.0).
class MasterDataWijzigingsverzoek {
  const MasterDataWijzigingsverzoek({
    this.id,
    this.tabelNaam,
    this.veldNaam,
    this.oudeWaarde,
    this.nieuweWaarde,
    this.ingediendDoorId,
    this.status,
  });

  final String? id;
  final String? tabelNaam;
  final String? veldNaam;
  final String? oudeWaarde;
  final String? nieuweWaarde;
  final String? ingediendDoorId;
  final String? status;

  static MasterDataWijzigingsverzoek fromRow(Map<String, dynamic> row) {
    return MasterDataWijzigingsverzoek(
      id: row[MasterDataWijzigingsverzoekenTable.id]?.toString(),
      tabelNaam: row[MasterDataWijzigingsverzoekenTable.tabelNaam]?.toString(),
      veldNaam: row[MasterDataWijzigingsverzoekenTable.veldNaam]?.toString(),
      oudeWaarde: row[MasterDataWijzigingsverzoekenTable.oudeWaarde]?.toString(),
      nieuweWaarde: row[MasterDataWijzigingsverzoekenTable.nieuweWaarde]?.toString(),
      ingediendDoorId:
          row[MasterDataWijzigingsverzoekenTable.ingediendDoorId]?.toString(),
      status: row[MasterDataWijzigingsverzoekenTable.status]?.toString(),
    );
  }

  String get displayLabel {
    final t = (tabelNaam ?? '').trim();
    final v = (veldNaam ?? '').trim();
    if (t.isNotEmpty && v.isNotEmpty) return '$t • $v';
    if (t.isNotEmpty) return t;
    if (v.isNotEmpty) return v;
    final i = (id ?? '').trim();
    return i.isEmpty ? 'Wijzigingsverzoek' : 'Wijzigingsverzoek $i';
  }

  String get subtitleSummary {
    final parts = <String>[];
    final s = (status ?? '').trim();
    if (s.isNotEmpty) parts.add(s);
    final o = (oudeWaarde ?? '').trim();
    final n = (nieuweWaarde ?? '').trim();
    if (o.isNotEmpty || n.isNotEmpty) {
      parts.add('${o.isEmpty ? '—' : o} → ${n.isEmpty ? '—' : n}');
    }
    return parts.isEmpty ? 'Wacht op goedkeuring' : parts.join(' • ');
  }
}
