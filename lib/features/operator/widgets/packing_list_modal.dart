import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Eén niet-lege string uit de rij, of null.
String? _pickString(Map<String, dynamic> row, List<String> keys) {
  for (final k in keys) {
    final v = row[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}

/// Unieke materiaalsleutel; null = rij niet bruikbaar voor paklijst.
String? _materialMergeKeyOrNull(Map<String, dynamic> row) {
  final id = _pickString(row, ['materiaal_id', 'artikel_id', 'product_id']);
  if (id != null) return 'id|$id';
  final naam = _pickString(row, [
    'materiaal_naam',
    'artikel_naam',
    'product_naam',
    'naam',
  ]);
  if (naam != null) return 'nm|${naam.toLowerCase()}';
  return null;
}

String _displayMateriaalNaam(Map<String, dynamic> row) {
  return _pickString(row, [
        'materiaal_naam',
        'artikel_naam',
        'product_naam',
        'naam',
      ]) ??
      'Materiaal';
}

/// Paklijst uit database-view [view_operator_paklijst_volledig]:
/// samenvatting voor de bus + breakdown per ruimte + detail per materiaal.
class PackingListModal extends StatefulWidget {
  const PackingListModal({super.key, required this.opdrachtId});

  final String opdrachtId;

  static Future<void> show(BuildContext context, {required String opdrachtId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PackingListModal(opdrachtId: opdrachtId),
    );
  }

  @override
  State<PackingListModal> createState() => _PackingListModalState();
}

/// Unieke materialen over de hele opdracht (alle ruimtes).
class _JobWideMaterial {
  _JobWideMaterial({
    required this.mergeKey,
    required this.materiaalNaam,
  });

  final String mergeKey;
  final String materiaalNaam;
  final Set<String> ruimteNamen = {};
  final Set<String> taakNamen = {};
  String? materiaalGebruiksdoel;
  String? materiaalBeschrijving;

  static _JobWideMaterial fromRow(Map<String, dynamic> row) {
    return _JobWideMaterial(
      mergeKey: _materialMergeKeyOrNull(row)!,
      materiaalNaam: _displayMateriaalNaam(row),
    );
  }

  void absorb(Map<String, dynamic> row) {
    final r = _pickString(row, ['ruimte_naam', 'ruimte_label', 'ruimte']);
    if (r != null) ruimteNamen.add(r);
    final taak = _pickString(row, ['taak_naam', 'taak', 'service_naam']);
    if (taak != null) taakNamen.add(taak);
    final g = _pickString(row, ['materiaal_gebruiksdoel', 'gebruiksdoel']);
    if (g != null) materiaalGebruiksdoel ??= g;
    final d = _pickString(row, [
      'materiaal_beschrijving',
      'beschrijving',
      'omschrijving',
      'artikel_beschrijving',
    ]);
    if (d != null) materiaalBeschrijving ??= d;
  }

  String lineageLabel() {
    if (ruimteNamen.isEmpty) return 'Nodig in: —';
    final sorted = ruimteNamen.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return 'Nodig in: ${sorted.join(', ')}';
  }

  /// Tekst onder de titel: eerst gebruiksdoel, anders beschrijving.
  String summaryBodyText() {
    final g = (materiaalGebruiksdoel ?? '').trim();
    if (g.isNotEmpty) return g;
    return (materiaalBeschrijving ?? '').trim();
  }
}

List<_JobWideMaterial> _buildJobWideMaterials(List<Map<String, dynamic>> rows) {
  final map = <String, _JobWideMaterial>{};
  for (final row in rows) {
    final k = _materialMergeKeyOrNull(row);
    if (k == null) continue;
    map.putIfAbsent(k, () => _JobWideMaterial.fromRow(row));
    map[k]!.absorb(row);
  }
  final list = map.values.toList()
    ..sort((a, b) =>
        a.materiaalNaam.toLowerCase().compareTo(b.materiaalNaam.toLowerCase()));
  return list;
}

class _MergedMaterial {
  _MergedMaterial({
    required this.mergeKey,
    required this.materiaalNaam,
    required this.ruimteCategorieHint,
  });

  final String mergeKey;
  final String materiaalNaam;
  String ruimteCategorieHint;
  final Set<String> taakNamen = {};
  final Set<String> materiaalCategorieen = {};
  String? materiaalBeschrijving;
  String? materiaalGebruiksdoel;

  static String? mergeKeyForRow(Map<String, dynamic> row) =>
      _materialMergeKeyOrNull(row);

  static _MergedMaterial fromRow(Map<String, dynamic> row) {
    final k = _materialMergeKeyOrNull(row)!;
    return _MergedMaterial(
      mergeKey: k,
      materiaalNaam: _displayMateriaalNaam(row),
      ruimteCategorieHint:
          _pickString(row, ['ruimte_categorie', 'categorie_ruimte']) ?? '',
    );
  }

  void absorb(Map<String, dynamic> row) {
    final taak = _pickString(row, ['taak_naam', 'taak', 'service_naam']);
    if (taak != null) taakNamen.add(taak);
    for (final c in _categoryStringsFromRow(row)) {
      materiaalCategorieen.add(c);
    }
    final desc = _pickString(row, [
      'materiaal_beschrijving',
      'beschrijving',
      'omschrijving',
      'artikel_beschrijving',
    ]);
    if (desc != null) materiaalBeschrijving ??= desc;
    final gebruik = _pickString(row, [
      'materiaal_gebruiksdoel',
      'gebruiksdoel',
    ]);
    if (gebruik != null) materiaalGebruiksdoel ??= gebruik;
    final rc = _pickString(row, ['ruimte_categorie', 'categorie_ruimte']);
    if (rc != null && ruimteCategorieHint.isEmpty) {
      ruimteCategorieHint = rc;
    }
  }
}

Set<String> _categoryStringsFromRow(Map<String, dynamic> row) {
  const keys = <String>[
    'materiaal_categorie',
    'materiaal_categorie_naam',
    'product_categorie',
    'categorie_naam',
    'artikel_categorie',
    'toepassingsgebied',
  ];
  final out = <String>{};
  for (final k in keys) {
    final s = _pickString(row, [k]);
    if (s != null) out.add(s);
  }
  return out;
}

String _roomBucketKey(Map<String, dynamic> row) {
  final naam = _pickString(row, ['ruimte_naam', 'ruimte_label', 'ruimte']);
  return (naam == null || naam.isEmpty) ? 'Overig' : naam;
}

String _roomSectionTitle(String bucketKey, Map<String, dynamic>? sampleRow) {
  if (sampleRow == null) return bucketKey;
  final ruimteNaam =
      _pickString(sampleRow, ['ruimte_naam', 'ruimte_label', 'ruimte']) ?? '';
  final cat =
      _pickString(sampleRow, ['ruimte_categorie', 'categorie_ruimte']) ?? '';
  if (cat.isEmpty) return ruimteNaam.isEmpty ? bucketKey : ruimteNaam;
  if (ruimteNaam.isEmpty) return cat;
  final n = ruimteNaam.toLowerCase();
  final c = cat.toLowerCase();
  if (n.contains(c) || c.contains(n)) return ruimteNaam;
  return '$cat: $ruimteNaam';
}

IconData _iconForRuimteCategorie(String? raw) {
  final s = (raw ?? '').toLowerCase();
  if (s.contains('sanitair') ||
      s.contains('toilet') ||
      s.contains('wc') ||
      s.contains('badkamer')) {
    return Icons.wc_rounded;
  }
  if (s.contains('keuken')) return Icons.kitchen_rounded;
  if (s.contains('kantoor')) return Icons.business_rounded;
  if (s.contains('trap')) return Icons.stairs_rounded;
  if (s.contains('gang') || s.contains('hal')) {
    return Icons.meeting_room_rounded;
  }
  if (s.contains('raam')) return Icons.window_rounded;
  if (s.contains('vloer')) return Icons.grid_on_rounded;
  return Icons.cleaning_services_rounded;
}

class _RoomSection {
  const _RoomSection({
    required this.roomKey,
    required this.headerTitle,
    required this.materials,
  });

  final String roomKey;
  final String headerTitle;
  final List<_MergedMaterial> materials;
}

List<_RoomSection> _buildRoomSections(List<Map<String, dynamic>> rows) {
  final byRoom = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    if (_materialMergeKeyOrNull(r) == null) continue;
    final key = _roomBucketKey(r);
    byRoom.putIfAbsent(key, () => []).add(r);
  }

  final keys = byRoom.keys.toList()
    ..sort((a, b) {
      if (a == 'Overig') return 1;
      if (b == 'Overig') return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

  final sections = <_RoomSection>[];
  for (final roomKey in keys) {
    final roomRows = byRoom[roomKey]!;
    final merged = <String, _MergedMaterial>{};
    for (final row in roomRows) {
      final k = _MergedMaterial.mergeKeyForRow(row);
      if (k == null) continue;
      merged.putIfAbsent(k, () => _MergedMaterial.fromRow(row));
      merged[k]!.absorb(row);
    }
    final list = merged.values.toList()
      ..sort((a, b) =>
          a.materiaalNaam.toLowerCase().compareTo(b.materiaalNaam.toLowerCase()));
    final headerTitle = _roomSectionTitle(roomKey, roomRows.first);
    sections.add(
      _RoomSection(roomKey: roomKey, headerTitle: headerTitle, materials: list),
    );
  }
  return sections;
}

class _PackingListModalState extends State<PackingListModal> {
  static const Color _sheetBg = Color(0xFFF5F5F7);
  static const Color _card = Colors.white;
  static const Color _navy = Color(0xFF0F172A);
  static const Color _jobSummaryBg = Color(0xFFF0F4FF);
  static const Color _accentIndigo = Color(0xFF4338CA);

  bool _isLoading = true;
  String? _errorMessage;
  List<_JobWideMaterial> _jobWide = [];
  List<_RoomSection> _sections = [];

  @override
  void initState() {
    super.initState();
    _fetchPaklijst();
  }

  Future<void> _fetchPaklijst() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final opdrachtId = widget.opdrachtId.trim();
      if (opdrachtId.isEmpty) {
        throw StateError('Geen opdracht-id.');
      }

      final dynamic raw = await Supabase.instance.client
          .from('view_operator_paklijst_volledig')
          .select()
          .eq('opdracht_id', opdrachtId);

      if (!mounted) return;

      final List<Map<String, dynamic>> mapped = raw is List
          ? raw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : <Map<String, dynamic>>[];

      setState(() {
        _jobWide = _buildJobWideMaterials(mapped);
        _sections = _buildRoomSections(mapped);
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('Paklijst laden mislukt: $e\n$st');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _openMaterialDetailSheet(
    BuildContext context, {
    required String materiaalNaam,
    required String? gebruiksdoel,
    required String? instructie,
    required List<String> taakNamen,
    required IconData icon,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final mq = MediaQuery.sizeOf(ctx);
        final bottomInset = MediaQuery.paddingOf(ctx).bottom;
        final taken = List<String>.from(taakNamen)..sort();
        final g = (gebruiksdoel ?? '').trim();
        final iText = (instructie ?? '').trim();

        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            constraints: BoxConstraints(maxHeight: mq.height * 0.78),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  height: 5,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 12, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(icon, color: _accentIndigo, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          materiaalNaam,
                          style: GoogleFonts.lato(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: _navy,
                            height: 1.2,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: mq.height * 0.52),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gebruiksdoel',
                          style: GoogleFonts.lato(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          g.isEmpty ? '—' : g,
                          style: GoogleFonts.lato(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                            color: g.isEmpty
                                ? Colors.grey.shade500
                                : _navy.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Omschrijving',
                          style: GoogleFonts.lato(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          iText.isEmpty ? '—' : iText,
                          style: GoogleFonts.lato(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                            color: iText.isEmpty
                                ? Colors.grey.shade500
                                : _navy.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Diensten / taken',
                          style: GoogleFonts.lato(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (taken.isEmpty)
                          Text(
                            'Geen taken gekoppeld in deze weergave.',
                            style: GoogleFonts.lato(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          )
                        else
                          ...taken.map(
                            (t) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.check_circle_outline_rounded,
                                      size: 18,
                                      color: _accentIndigo
                                          .withValues(alpha: 0.85)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      t,
                                      style: GoogleFonts.lato(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        height: 1.35,
                                        color: _navy,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openDetailFromJobWide(BuildContext context, _JobWideMaterial j) {
    _openMaterialDetailSheet(
      context,
      materiaalNaam: j.materiaalNaam,
      gebruiksdoel: j.materiaalGebruiksdoel,
      instructie: j.materiaalBeschrijving,
      taakNamen: j.taakNamen.toList(),
      icon: Icons.local_shipping_rounded,
    );
  }

  void _openDetailFromRoomMaterial(BuildContext context, _MergedMaterial m) {
    _openMaterialDetailSheet(
      context,
      materiaalNaam: m.materiaalNaam,
      gebruiksdoel: m.materiaalGebruiksdoel,
      instructie: m.materiaalBeschrijving,
      taakNamen: m.taakNamen.toList(),
      icon: _iconForRuimteCategorie(m.ruimteCategorieHint),
    );
  }

  static BoxDecoration _innerCardDecoration() {
    return BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.86,
      decoration: const BoxDecoration(
        color: _sheetBg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            height: 5,
            width: 40,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E7FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: Color(0xFF3730A3),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Paklijst voor deze klus',
                    style: GoogleFonts.lato(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: _navy,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
        child: Center(
          child: Text(
            'Kon paklijst niet laden.\n$_errorMessage',
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.red.shade800,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    final totalMaterials =
        _sections.fold<int>(0, (sum, e) => sum + e.materials.length);
    if (totalMaterials == 0 && _jobWide.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
          child: Column(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 20),
              Text(
                'Geen materialen gevonden voor deze opdracht.',
                textAlign: TextAlign.center,
                style: GoogleFonts.lato(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          decoration: BoxDecoration(
            color: _jobSummaryBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _accentIndigo.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: _accentIndigo.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'GEHELE KLUS (Samenvatting)',
                style: GoogleFonts.lato(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: _navy.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '📦 Voor in de bus',
                style: GoogleFonts.lato(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _accentIndigo,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 14),
              ..._jobWide.map((j) {
                final body = j.summaryBodyText();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openDetailFromJobWide(context, j),
                      borderRadius: BorderRadius.circular(16),
                      child: Ink(
                        decoration: _innerCardDecoration(),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                j.materiaalNaam,
                                style: GoogleFonts.lato(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  height: 1.25,
                                  color: _navy,
                                ),
                              ),
                              if (body.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  body,
                                  style: GoogleFonts.lato(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                    color: _navy.withValues(alpha: 0.78),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                j.lineageLabel(),
                                style: GoogleFonts.lato(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _navy.withValues(alpha: 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '📍 Per ruimte',
                style: GoogleFonts.lato(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 14),
              for (var s = 0; s < _sections.length; s++) ...[
                if (s > 0) const SizedBox(height: 6),
                _buildRoomSection(context, _sections[s]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoomSection(BuildContext context, _RoomSection section) {
    final title = section.headerTitle;
    final materials = section.materials;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade200.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            title,
            style: GoogleFonts.lato(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: _navy.withValues(alpha: 0.88),
              letterSpacing: -0.2,
            ),
          ),
        ),
        ...materials.map((m) {
          final icon = _iconForRuimteCategorie(m.ruimteCategorieHint);
          final subParts = m.materiaalCategorieen.toList()
            ..sort((a, b) => a.compareTo(b));
          final subtitle = subParts.isEmpty ? null : subParts.join(' · ');

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openDetailFromRoomMaterial(context, m),
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  decoration: _innerCardDecoration(),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(icon, color: const Color(0xFF475569)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.materiaalNaam,
                                style: GoogleFonts.lato(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  height: 1.25,
                                  color: _navy,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  subtitle,
                                  style: GoogleFonts.lato(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
