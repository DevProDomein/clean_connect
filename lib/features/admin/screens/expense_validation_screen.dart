import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_client.dart';

class ExpenseValidationScreen extends StatefulWidget {
  const ExpenseValidationScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<ExpenseValidationScreen> createState() => _ExpenseValidationScreenState();
}

class _ExpenseValidationScreenState extends State<ExpenseValidationScreen> {
  Future<_ExpenseValidationData>? _future;
  bool _saving = false;

  // Form fields (kept simple for now; AI/OCR will fill later).
  String? _vendorId;
  final _invoiceNrCtrl = TextEditingController();
  final _totalIncCtrl = TextEditingController();
  DateTime? _invoiceDate;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void dispose() {
    _invoiceNrCtrl.dispose();
    _totalIncCtrl.dispose();
    super.dispose();
  }

  Future<_ExpenseValidationData> _fetch() async {
    final inv = await AppSupabase.client
        .from('inkoopfacturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .eq('id', widget.invoiceId)
        .maybeSingle();

    final vendorsRes = await AppSupabase.client
        .from('bedrijven')
        .select('id, bedrijfsnaam')
        .eq('is_leverancier', true)
        .order('bedrijfsnaam', ascending: true);
    final vendors = (vendorsRes as List).cast<Map<String, dynamic>>();

    final linesRes = await AppSupabase.client
        .from('inkoopfactuur_split_regels')
        .select()
        .eq('inkoopfactuur_id', widget.invoiceId)
        .order('id', ascending: true);
    final lines = (linesRes as List).cast<Map<String, dynamic>>();

    final projects = await _fetchActiveProjects();

    final grootboekRes = await AppSupabase.client
        .from('grootboekrekeningen')
        .select()
        .order('rekening_nummer', ascending: true);
    final grootboek = (grootboekRes as List).cast<Map<String, dynamic>>();

    // Seed form from DB once.
    final vendorId = inv?['bedrijf_id']?.toString() ??
        inv?['leverancier_id']?.toString() ??
        (inv?['bedrijven'] as Map?)?['id']?.toString();
    final factuurNr = (inv?['factuur_nummer_leverancier'] ?? inv?['factuur_nummer'] ?? '')
        .toString()
        .trim();
    final factuurDatumRaw = (inv?['factuur_datum'] ?? inv?['datum'])?.toString();
    final totalIncRaw = (inv?['totaal_inc_btw'] ?? '').toString().trim();

    _vendorId ??= vendorId;
    if (_invoiceNrCtrl.text.isEmpty) _invoiceNrCtrl.text = factuurNr;
    if (_totalIncCtrl.text.isEmpty) _totalIncCtrl.text = totalIncRaw;
    if (_invoiceDate == null && factuurDatumRaw != null) {
      _invoiceDate = DateTime.tryParse(factuurDatumRaw)?.toLocal();
    }

    return _ExpenseValidationData(
      invoice: inv ?? const <String, dynamic>{},
      vendors: vendors,
      projects: projects,
      grootboek: grootboek,
      splitLines: lines,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchActiveProjects() async {
    // Preferred: the view usually has project_id + project_naam.
    try {
      final res = await AppSupabase.client
          .from('app_project_winstmarges')
          .select('project_id, project_naam')
          .order('project_naam', ascending: true);
      final rows = (res as List).cast<Map<String, dynamic>>();

      // De-dup by project_id.
      final seen = <String>{};
      final out = <Map<String, dynamic>>[];
      for (final r in rows) {
        final id = (r['project_id'] ?? '').toString();
        if (id.isEmpty || seen.contains(id)) continue;
        seen.add(id);
        out.add(r);
      }
      return out;
    } catch (_) {
      // Fallback: common base table name.
      final res = await AppSupabase.client
          .from('projecten')
          .select('id, naam')
          .eq('actief', true)
          .order('naam', ascending: true);
      return (res as List).cast<Map<String, dynamic>>();
    }
  }

  void _refresh() {
    setState(() {
      _future = _fetch();
    });
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  NumberFormat _eur() => NumberFormat.currency(locale: 'nl_NL', symbol: '€', decimalDigits: 2);

  Map<String, dynamic> _confidenceMap(Map<String, dynamic> inv) {
    final raw = inv['ocr_confidence_scores'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    return const <String, dynamic>{};
  }

  double? _confidenceFor(Map<String, dynamic> inv, String key) {
    final map = _confidenceMap(inv);
    final v = map[key];
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString());
  }

  _FieldTone _toneFor({
    required Map<String, dynamic> inv,
    required String key,
    required bool isUbl,
  }) {
    if (isUbl) return _FieldTone.high;
    final c = _confidenceFor(inv, key);
    if (c == null) return _FieldTone.low;
    return c < 85.0 ? _FieldTone.low : _FieldTone.high;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _invoiceDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      helpText: 'Factuurdatum',
    );
    if (picked == null) return;
    setState(() => _invoiceDate = picked);
  }

  Future<void> _saveInvoiceHeader() async {
    if (_saving) return;
    final vendorId = _vendorId?.trim() ?? '';
    final nr = _invoiceNrCtrl.text.trim();
    final totalInc = _asDouble(_totalIncCtrl.text.trim());

    setState(() => _saving = true);
    try {
      await AppSupabase.client.from('inkoopfacturen').update({
        if (vendorId.isNotEmpty) 'bedrijf_id': vendorId,
        'factuur_nummer_leverancier': nr,
        if (_invoiceDate != null) 'factuur_datum': _invoiceDate!.toIso8601String(),
        if (totalInc > 0) 'totaal_inc_btw': totalInc,
      }).eq('id', widget.invoiceId);
    } catch (e) {
      if (!mounted) return;
      await _handleDuplicateOrShowError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleDuplicateOrShowError(Object e) async {
    final msg = e.toString();
    if (msg.contains('idx_unieke_inkoopfactuur') ||
        msg.toLowerCase().contains('duplicate') ||
        msg.toLowerCase().contains('unique')) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: const Color(0xFFFFE9E9),
            title: Text(
              'Fraude/Duplicaat Preventie',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
            ),
            content: Text(
              'Deze factuur van deze leverancier is al ingeboekt in het systeem.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Begrepen'),
              ),
            ],
          );
        },
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
        content: Text('Opslaan mislukt: $e'),
      ),
    );
  }

  Future<void> _addSplitLineDialog(_ExpenseValidationData data) async {
    final omsCtrl = TextEditingController();
    final bedragCtrl = TextEditingController();
    bool busy = false;
    String? projectId;
    String? grootboekId;
    String btwCode = 'hoog_21';

    await showDialog<void>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                'Kostenregel toevoegen',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Project (cruciaal)'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: (projectId?.isNotEmpty == true) ? projectId : null,
                            hint: const Text('Selecteer project'),
                            items: data.projects.map((p) {
                              final id = _text(p['project_id'] ?? p['id']);
                              final name = _text(p['project_naam'] ?? p['naam']);
                              return DropdownMenuItem(value: id, child: Text(name));
                            }).toList(),
                            onChanged: busy ? null : (v) => setState(() => projectId = v),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Grootboekrekening'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: (grootboekId?.isNotEmpty == true) ? grootboekId : null,
                            hint: const Text('Selecteer grootboekrekening'),
                            items: data.grootboek.map((g) {
                              final id = _text(g['id']);
                              final nr = _text(g['rekening_nummer']);
                              final name = _text(g['naam']);
                              return DropdownMenuItem(value: id, child: Text('$nr • $name'));
                            }).toList(),
                            onChanged: busy ? null : (v) => setState(() => grootboekId = v),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: omsCtrl,
                        decoration: const InputDecoration(labelText: 'Omschrijving'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: bedragCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Bedrag (ex. BTW)'),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'BTW-code'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: btwCode,
                            items: const [
                              DropdownMenuItem(value: 'hoog_21', child: Text('Hoog (21%)')),
                              DropdownMenuItem(value: 'laag_9', child: Text('Laag (9%)')),
                              DropdownMenuItem(value: 'nul_0', child: Text('Nul (0%)')),
                            ],
                            onChanged: busy ? null : (v) => setState(() => btwCode = v ?? btwCode),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Let op: totalen worden automatisch berekend door Supabase triggers.',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.60),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: busy ? null : () => Navigator.of(context).pop(), child: const Text('Annuleren')),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final pid = projectId?.trim() ?? '';
                          final gid = grootboekId?.trim() ?? '';
                          final oms = omsCtrl.text.trim();
                          final bedrag = _asDouble(bedragCtrl.text.trim());
                          if (pid.isEmpty || gid.isEmpty || bedrag <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
                                content: const Text('Vul project, grootboek en bedrag in.'),
                              ),
                            );
                            return;
                          }

                          setState(() => busy = true);
                          try {
                            await AppSupabase.client.from('inkoopfactuur_split_regels').insert({
                              'inkoopfactuur_id': widget.invoiceId,
                              'project_id': pid,
                              'grootboek_rekening_id': gid,
                              'omschrijving': oms,
                              'bedrag_ex_btw': bedrag,
                              'btw_code': btwCode,
                            });
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
                                content: Text('Kon kostenregel niet toevoegen: $e'),
                              ),
                            );
                          } finally {
                            if (context.mounted) setState(() => busy = false);
                          }
                        },
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.add_rounded),
                  label: const Text('Toevoegen'),
                ),
              ],
            );
          },
        );
      },
    );

    omsCtrl.dispose();
    bedragCtrl.dispose();

    _refresh(); // triggers recalculated totals/status
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Validatie (Inkoop)',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(tooltip: 'Vernieuwen', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<_ExpenseValidationData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: _ErrorState(
                title: 'Kan factuur niet laden',
                message: snapshot.error.toString(),
                onRetry: _refresh,
              ),
            );
          }

          final data = snapshot.data!;
          final inv = data.invoice;
          final pdfUrl = _text(inv['pdf_url']);
          final ocrStatus = _text(inv['ocr_verwerkings_status']).toLowerCase();
          final isProcessing = ocrStatus == 'processing';
          final isUbl = (inv['is_ubl_xml'] == true) ||
              _text(inv['is_ubl_xml']).toLowerCase() == 'true';

          final totaalEx = _asDouble(inv['totaal_ex_btw']);
          final totaalBtw = _asDouble(inv['totaal_btw']);
          final totaalInc = _asDouble(inv['totaal_inc_btw']);
          final status = _text(inv['status']);

          final layout = LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;

              Widget leftPreview() {
                return Container(
                  decoration: BoxDecoration(
                    color: softBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: InteractiveViewer(
                      minScale: 0.6,
                      maxScale: 4.0,
                      child: pdfUrl.isEmpty
                          ? Center(
                              child: Text(
                                'Geen scan gevonden.',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: pdfUrl,
                              fit: BoxFit.contain,
                              placeholder: (context, url) =>
                                  const Center(child: CircularProgressIndicator()),
                              errorWidget: (context, url, error) => Center(
                                child: Text(
                                  'Kan afbeelding niet laden.',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                    ),
                  ),
                );
              }

              Widget rightForm() {
                final vendorTone = _toneFor(inv: inv, key: 'leverancier', isUbl: isUbl);
                final invoiceNrTone =
                    _toneFor(inv: inv, key: 'factuur_nummer_leverancier', isUbl: isUbl);
                final dateTone = _toneFor(inv: inv, key: 'factuur_datum', isUbl: isUbl);
                final totalTone = _toneFor(inv: inv, key: 'totaal_inc_btw', isUbl: isUbl);

                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Factuurgegevens',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                            ),
                            child: Text(
                              status.isEmpty ? '—' : status,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _VendorDropdown(
                        vendors: data.vendors,
                        value: _vendorId,
                        onChanged: (v) => setState(() => _vendorId = v),
                        tone: vendorTone,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _invoiceNrCtrl,
                        decoration: _decorateWithTone(
                          context,
                          labelText: 'Factuurnummer leverancier',
                          tone: invoiceNrTone,
                        ),
                        style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        onChanged: (_) {
                          // Save on change, but debounced by button.
                        },
                      ),
                      const SizedBox(height: 12),
                      _DateField(
                        label: 'Factuurdatum',
                        value: _invoiceDate,
                        onTap: _pickDate,
                        tone: dateTone,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _totalIncCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _decorateWithTone(
                          context,
                          labelText: 'Totaal (incl. BTW)',
                          tone: totalTone,
                        ),
                        style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Split-Boeking (Job Costing)',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () => _addSplitLineDialog(data),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Kostenregel'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (data.splitLines.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? softBg : const Color(0xFFF5F5F7),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.rule_folder_outlined,
                                  color: cs.onSurface.withValues(alpha: 0.65)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Nog geen kostenregels. Voeg minimaal 1 regel toe om totalen te berekenen.',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface.withValues(alpha: 0.80),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ListView.separated(
                          itemCount: data.splitLines.length,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          separatorBuilder: (_, i) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final r = data.splitLines[i];
                            final oms = _text(r['omschrijving']);
                            final bedrag = _asDouble(r['bedrag_ex_btw']);
                            final lineId = _text(r['id']);

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? softBg : const Color(0xFFF5F5F7),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          oms.isEmpty ? '(zonder omschrijving)' : oms,
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Bedrag (ex.): ${_eur().format(bedrag)}',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                            color: cs.onSurface.withValues(alpha: 0.65),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Verwijderen',
                                    onPressed: () async {
                                      if (lineId.isEmpty) return;
                                      await AppSupabase.client
                                          .from('inkoopfactuur_split_regels')
                                          .delete()
                                          .eq('id', lineId);
                                      _refresh();
                                    },
                                    icon: Icon(Icons.delete_outline,
                                        color: cs.onSurface.withValues(alpha: 0.70)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? softBg : const Color(0xFFF5F5F7),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _TotalTile(label: 'Totaal Ex.', value: _eur().format(totaalEx))),
                            const SizedBox(width: 12),
                            Expanded(child: _TotalTile(label: 'BTW', value: _eur().format(totaalBtw))),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TotalTile(
                                label: 'Totaal Incl.',
                                value: _eur().format(totaalInc),
                                primary: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  await _saveInvoiceHeader();
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                },
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.verified_rounded),
                          label: Text(
                            'Bevestigen & Sluiten',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (wide) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Row(
                    children: [
                      Expanded(flex: 5, child: leftPreview()),
                      const SizedBox(width: 16),
                      Expanded(flex: 5, child: SingleChildScrollView(child: rightForm())),
                    ],
                  ),
                );
              }

              return DefaultTabController(
                length: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? softBg : const Color(0xFFF5F5F7),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                        ),
                        child: TabBar(
                          dividerColor: Colors.transparent,
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelColor: Colors.white,
                          unselectedLabelColor: cs.onSurface.withValues(alpha: 0.72),
                          indicator: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          tabs: const [
                            Tab(text: 'Scan'),
                            Tab(text: 'Formulier'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: TabBarView(
                          children: [
                            leftPreview(),
                            SingleChildScrollView(child: rightForm()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );

          return Stack(
            children: [
              layout,
              if (isProcessing)
                Positioned.fill(
                  child: Container(
                    color:
                        Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.60),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: tileBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 22,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'AI is het document aan het lezen...',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ExpenseValidationData {
  const _ExpenseValidationData({
    required this.invoice,
    required this.vendors,
    required this.projects,
    required this.grootboek,
    required this.splitLines,
  });

  final Map<String, dynamic> invoice;
  final List<Map<String, dynamic>> vendors;
  final List<Map<String, dynamic>> projects;
  final List<Map<String, dynamic>> grootboek;
  final List<Map<String, dynamic>> splitLines;
}

enum _FieldTone { low, high }

InputDecoration _decorateWithTone(
  BuildContext context, {
  required String labelText,
  required _FieldTone tone,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final warnBg = Colors.orange.withValues(alpha: isDark ? 0.14 : 0.10);
  final okBorder = Colors.green.withValues(alpha: 0.45);

  switch (tone) {
    case _FieldTone.low:
      return InputDecoration(
        labelText: labelText,
        filled: true,
        fillColor: warnBg,
        suffixIcon: Tooltip(
          message: 'Lage AI Zekerheid. Controleer dit veld zorgvuldig.',
          child: const Icon(Icons.warning_rounded, color: Colors.orange),
        ),
      );
    case _FieldTone.high:
      return InputDecoration(
        labelText: labelText,
        suffixIcon: const Icon(Icons.check_circle_rounded, color: Colors.green),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: okBorder),
        ),
      );
  }
}

class _VendorDropdown extends StatelessWidget {
  const _VendorDropdown({
    required this.vendors,
    required this.value,
    required this.onChanged,
    required this.tone,
  });

  final List<Map<String, dynamic>> vendors;
  final String? value;
  final ValueChanged<String?> onChanged;
  final _FieldTone tone;

  String _text(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: _decorateWithTone(context, labelText: 'Leverancier', tone: tone),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value?.isNotEmpty == true ? value : null,
          hint: const Text('Selecteer leverancier'),
          items: vendors.map((v) {
            final id = _text(v['id']);
            final name = _text(v['bedrijfsnaam']);
            return DropdownMenuItem(value: id, child: Text(name.isEmpty ? id : name));
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.tone,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final _FieldTone tone;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Kies datum'
        : DateFormat('dd-MM-yyyy').format(value!);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: InputDecorator(
        decoration: _decorateWithTone(context, labelText: label, tone: tone).copyWith(
          // keep the confidence icon; date picking is still on tap
          suffixIcon: (tone == _FieldTone.low)
              ? Tooltip(
                  message: 'Lage AI Zekerheid. Controleer dit veld zorgvuldig.',
                  child: const Icon(Icons.warning_rounded, color: Colors.orange),
                )
              : const Icon(Icons.check_circle_rounded, color: Colors.green),
        ),
        child: Text(text),
      ),
    );
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({
    required this.label,
    required this.value,
    this.primary = false,
  });

  final String label;
  final String value;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: primary ? cs.primary.withValues(alpha: 0.10) : cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
              color: primary ? cs.primary : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0A0912)
            : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
          ),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Opnieuw proberen'),
          ),
        ],
      ),
    );
  }
}

