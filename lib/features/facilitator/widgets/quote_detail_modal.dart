import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/supabase_client.dart';

class QuoteDetailModal extends StatefulWidget {
  const QuoteDetailModal({super.key, required this.offerte});

  final Map<String, dynamic> offerte;

  @override
  State<QuoteDetailModal> createState() => _QuoteDetailModalState();
}

class _QuoteDetailModalState extends State<QuoteDetailModal> {
  bool _busy = false;
  List<Map<String, dynamic>> _ruimtes = const [];
  bool _loadingRuimtes = true;

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(_text(v).replaceAll(',', '.')) ?? 0.0;
  }

  @override
  void initState() {
    super.initState();
    _loadRuimtes();
  }

  Future<void> _loadRuimtes() async {
    final id = _text(widget.offerte['id']);
    if (id.isEmpty) {
      if (mounted) setState(() => _loadingRuimtes = false);
      return;
    }
    try {
      final res = await AppSupabase.client
          .from('offerte_ruimtes')
          .select('id, naam_in_pand, aantal_identiek')
          .eq('offerte_id', id)
          .order('id', ascending: true);
      if (!mounted) return;
      setState(() {
        _ruimtes = (res as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _ruimtes = const []);
    } finally {
      if (mounted) setState(() => _loadingRuimtes = false);
    }
  }

  Future<void> _setStatus(String status) async {
    if (_busy) return;
    final id = _text(widget.offerte['id']);
    if (id.isEmpty) return;
    setState(() => _busy = true);
    try {
      await AppSupabase.client.from('offertes').update({'status': status}).eq('id', id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Actie mislukt: $e', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCancel() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Offerte annuleren', style: GoogleFonts.inter(fontWeight: FontWeight.w900)),
          content: Text(
            'Weet je zeker dat je deze offerte wilt annuleren? Deze actie kan niet ongedaan worden gemaakt.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Nee', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: Text('Annuleren', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    await _setStatus('geannuleerd');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF111019) : Colors.white;

    final eur = NumberFormat.currency(locale: 'nl_NL', symbol: '€');
    final id = _text(widget.offerte['id']);
    final klant = _text(widget.offerte['bedrijfsnaam_klant']);
    final nr = _text(widget.offerte['offerte_nummer']);
    final totaal = _asDouble(widget.offerte['totaal_prijs_ex_btw']);
    final status = _text(widget.offerte['status']).toLowerCase();

    final isVerzonden = status == 'send';
    final isGetekend = status == 'signed' || status == 'getekend';

    String badgeLabel() {
      if (isVerzonden) return 'VERZONDEN';
      if (isGetekend) return 'GETEKEND';
      if (status.isEmpty) return 'ONBEKEND';
      return status.toUpperCase();
    }

    Color badgeBg() {
      if (isVerzonden) return const Color(0xFFFFF7ED);
      if (isGetekend) return const Color(0xFFECFDF5);
      return cs.surfaceContainerHighest;
    }

    Color badgeFg() {
      if (isVerzonden) return const Color(0xFFB45309);
      if (isGetekend) return const Color(0xFF047857);
      return cs.onSurface.withValues(alpha: 0.70);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.12),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.86,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, controller) {
              return ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Offerte overzicht',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: badgeBg(),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: badgeFg().withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          badgeLabel(),
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 0.8,
                            color: badgeFg(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Sluiten',
                        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _infoRow(label: 'Klant', value: klant.isEmpty ? '—' : klant),
                  _infoRow(label: 'Offerte nummer', value: nr.isEmpty ? '—' : '#$nr'),
                  _infoRow(label: 'Totaal', value: eur.format(totaal)),
                  _infoRow(label: 'ID', value: id.isEmpty ? '—' : id),
                  const SizedBox(height: 12),
                  Text(
                    'Ruimtes',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  if (_loadingRuimtes)
                    const LinearProgressIndicator(minHeight: 3)
                  else if (_ruimtes.isEmpty)
                    Text(
                      'Geen ruimtes gevonden.',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.65),
                      ),
                    )
                  else
                    ..._ruimtes.take(8).map((r) {
                      final n = _text(r['naam_in_pand']).isEmpty ? 'Ruimte' : _text(r['naam_in_pand']);
                      final count = _text(r['aantal_identiek']).isEmpty ? '' : 'x${_text(r['aantal_identiek'])}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(Icons.meeting_room_outlined,
                                size: 18, color: cs.onSurface.withValues(alpha: 0.65)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                n,
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (count.isNotEmpty)
                              Text(
                                count,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface.withValues(alpha: 0.65),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  if (_ruimtes.length > 8) ...[
                    const SizedBox(height: 4),
                    Text(
                      '+ ${_ruimtes.length - 8} meer…',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (isVerzonden || isGetekend) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text(
                          'Toon Definitieve PDF',
                          style: TextStyle(fontSize: 16),
                        ),
                        onPressed: _busy
                            ? null
                            : () async {
                                final offerte = widget.offerte;
                                final String? pdfUrl =
                                    offerte['definitieve_pdf_url']?.toString();

                                if (pdfUrl == null ||
                                    pdfUrl.trim().isEmpty ||
                                    pdfUrl == 'null') {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Fout: Geen definitieve PDF URL gevonden in de database. Vink de offerte opnieuw aan als verzonden.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                try {
                                  final Uri url = Uri.parse(pdfUrl);
                                  if (!await launchUrl(
                                    url,
                                    mode: LaunchMode.externalApplication,
                                  )) {
                                    throw Exception('Kan browser niet openen.');
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Kan PDF niet openen: $e'),
                                      ),
                                    );
                                  }
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (isVerzonden) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _confirmCancel,
                            icon: const Icon(Icons.block_rounded),
                            label: Text(
                              'Annuleer offerte',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: BorderSide(
                                color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy ? null : () => _setStatus('concept'),
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: Text(
                              'Open offerte opnieuw',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    FilledButton.tonal(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text('Sluiten', style: GoogleFonts.inter(fontWeight: FontWeight.w900)),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _infoRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.60),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

