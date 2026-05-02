import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../../../core/services/email_service.dart';
import '../../../shared/widgets/enterprise_tooltip.dart';
import '../../../shared/layouts/main_layout.dart';
import '../../../core/widgets/app_drawer.dart';
import 'article_management_screen.dart';
import '../services/document_generation_service.dart';
import '../services/pdf_invoice_service.dart';

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Future<_ErpInvoiceDetail>? _future;
  List<Map<String, dynamic>> _lines = const [];
  List<Map<String, dynamic>> _artikelen = const [];
  bool _hasUnsavedChanges = false;
  bool _taxBusy = false;
  bool _discountBusy = false;
  bool _pdfBusy = false;
  bool _finalizeBusy = false;
  bool _emailBusy = false;
  bool _creditBusy = false;
  bool? _localBtwVerlegd;
  double? _localFactuurKortingPercentage;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_ErpInvoiceDetail> _fetch() async {
    final inv = await AppSupabase.client
        .from('facturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .eq('id', widget.invoiceId)
        .maybeSingle();

    final regelsRes = await AppSupabase.client
        .from('factuur_regels')
        .select()
        .eq('factuur_id', widget.invoiceId)
        .order('volgorde', ascending: true);

    final artikelenRes = await AppSupabase.client
        .from('artikelen')
        .select()
        .order('artikel_code', ascending: true);

    final grootboekRes = await AppSupabase.client
        .from('grootboekrekeningen')
        .select()
        .order('rekening_nummer', ascending: true);

    final lines = (regelsRes as List).cast<Map<String, dynamic>>();
    final artikelen = (artikelenRes as List).cast<Map<String, dynamic>>();

    _lines = List<Map<String, dynamic>>.from(lines);
    _artikelen = List<Map<String, dynamic>>.from(artikelen);

    return _ErpInvoiceDetail(
      invoice: inv ?? const <String, dynamic>{},
      lines: lines,
      artikelen: artikelen,
      grootboek: (grootboekRes as List).cast<Map<String, dynamic>>(),
    );
  }

  void _refresh() {
    setState(() {
      _future = _fetch();
      _hasUnsavedChanges = false;
    });
  }

  Future<void> _handleBackButton() async {
    if (!_hasUnsavedChanges) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final bool? shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Niet-opgeslagen wijzigingen', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'U heeft wijzigingen aangebracht aan deze factuur. Als u deze pagina verlaat, gaan uw invoergegevens verloren. Wilt u echt weggaan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Blijven', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verlaten', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (shouldLeave == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'ja';
  }

  Future<void> _setBtwVerlegd(bool v) async {
    if (_taxBusy) return;
    setState(() {
      _taxBusy = true;
      _localBtwVerlegd = v;
      _hasUnsavedChanges = true;
    });
    try {
      await AppSupabase.client.from('facturen').update({'btw_verlegd': v}).eq(
            'id',
            widget.invoiceId,
          );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _localBtwVerlegd = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon BTW verlegd niet opslaan: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _taxBusy = false);
    }
  }

  Future<void> _openGlobalDiscountDialog(double current) async {
    if (_discountBusy) return;
    setState(() => _hasUnsavedChanges = true);

    final controller = TextEditingController(
      text: current == 0 ? '' : current.toStringAsFixed(current % 1 == 0 ? 0 : 2),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Korting op totaal',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^[0-9]+([\\.,][0-9]{0,2})?\$')),
            ],
            decoration: InputDecoration(
              labelText: 'Factuurkorting (%)',
              suffixIcon: const EnterpriseTooltip(
                message:
                    'Wordt toegepast op het totaal. Supabase herberekent automatisch de regels, BTW en totalen.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              child: Text(
                'Opslaan',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) return;

    final raw = controller.text.trim().replaceAll(',', '.');
    final parsed = raw.isEmpty ? 0.0 : (double.tryParse(raw) ?? double.nan);
    if (parsed.isNaN || parsed < 0 || parsed > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: const Text('Vul een percentage in tussen 0 en 100.'),
        ),
      );
      return;
    }

    setState(() {
      _discountBusy = true;
      _localFactuurKortingPercentage = parsed;
    });
    try {
      await AppSupabase.client
          .from('facturen')
          .update({'factuur_korting_percentage': parsed}).eq('id', widget.invoiceId);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _localFactuurKortingPercentage = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon factuurkorting niet opslaan: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _discountBusy = false);
    }
  }

  Future<void> _previewPdf({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> lines,
  }) async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);

    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final cfgRow = await AppSupabase.client
          .from('app_settings')
          .select('waarde')
          .eq('sleutel', 'factuur_config')
          .maybeSingle();
      final cfg = DocumentGenerationService.coerceSettingsValue(cfgRow?['waarde']);

      final pdfBytes = await DocumentGenerationService.generateInvoicePdf(
        invoice,
        lines,
        cfg,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close spinner
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).maybePop(); // close spinner if open
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon PDF niet genereren: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _confirmAndFinalize({
    required Map<String, dynamic> invoice,
  }) async {
    if (_finalizeBusy) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Factuur definitief maken?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
          content: Text(
            'Weet u zeker dat u deze factuur definitief wilt maken? Er wordt een officieel factuurnummer gegenereerd. U kunt hierna niets meer wijzigen.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              child: Text(
                'Maak Definitief',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) return;

    setState(() => _finalizeBusy = true);
    try {
      // Step A: status update -> DB trigger generates factuur_nummer.
      await AppSupabase.client
          .from('facturen')
          .update({'status': 'definitief'}).eq('id', _text(invoice['id']));

      // Step B: fetch updated invoice (contains fresh factuur_nummer).
      final updatedInvoice = await AppSupabase.client
          .from('facturen')
          .select()
          .eq('id', _text(invoice['id']))
          .maybeSingle();

      // Refresh lines to ensure trigger-calculated snapshots are current.
      final regelsRes = await AppSupabase.client
          .from('factuur_regels')
          .select()
          .eq('factuur_id', _text(invoice['id']))
          .order('volgorde', ascending: true);
      final regels = (regelsRes as List).cast<Map<String, dynamic>>();

      // Fetch app settings factuur_config.
      final cfgRow = await AppSupabase.client
          .from('app_settings')
          .select('waarde')
          .eq('sleutel', 'factuur_config')
          .maybeSingle();
      final cfg = DocumentGenerationService.coerceSettingsValue(cfgRow?['waarde']);

      // Step C: generate definitive PDF.
      final Uint8List pdfBytes = await DocumentGenerationService.generateInvoicePdf(
        (updatedInvoice ?? const <String, dynamic>{}).cast<String, dynamic>(),
        regels,
        cfg,
      );

      // Step D: upload to Storage (immutable PDF).
      final fileName = '${_text(updatedInvoice?['factuur_nummer'])}.pdf';
      await AppSupabase.client.storage.from('facturen_archief').uploadBinary(
            fileName,
            pdfBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'application/pdf',
            ),
          );

      // Step E: save path to invoice.
      await AppSupabase.client
          .from('facturen')
          .update({'definitieve_pdf_pad': fileName}).eq('id', _text(invoice['id']));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.90),
          content: const Text('Factuur definitief gemaakt en PDF veilig opgeslagen'),
        ),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon factuur niet definitief maken: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _finalizeBusy = false);
    }
  }

  String _stripPaymentBlock(String html) {
    var out = html;

    // Remove the whole payment button block if present.
    // We support both an explicit end marker and "until end-of-string" fallback.
    out = out.replaceAllMapped(
      RegExp(
        r'<!--\s*DE BETAALKNOP\s*-->[\s\S]*?<!--\s*(?:/DE BETAALKNOP|EINDE DE BETAALKNOP)\s*-->',
        caseSensitive: false,
      ),
      (_) => '',
    );
    out = out.replaceAllMapped(
      RegExp(
        r'<!--\s*DE BETAALKNOP\s*-->[\s\S]*$',
        caseSensitive: false,
      ),
      (_) => '',
    );

    // Remove any leftover betaal_link tags.
    out = out.replaceAll(RegExp(r'\{\{\s*betaal_link\s*\}\}', caseSensitive: false), '');
    return out;
  }

  Future<void> _sendInvoiceEmail({
    required Map<String, dynamic> invoice,
  }) async {
    if (_emailBusy) return;

    final invoiceId = _text(invoice['id']);
    final toEmail = _text(invoice['debiteur_email']);
    if (invoiceId.isEmpty || toEmail.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: const Text('Fout bij verzenden van e-mail. Controleer het e-mailadres van de klant.'),
        ),
      );
      return;
    }

    setState(() => _emailBusy = true);
    try {
      // Fetch active template.
      final tpl = await AppSupabase.client
          .from('factuur_email_templates')
          .select('body_html, onderwerp')
          .eq('soort', 'factuur_nieuw')
          .maybeSingle();

      // Fetch app settings.
      final cfgRow = await AppSupabase.client
          .from('app_settings')
          .select('waarde')
          .eq('sleutel', 'factuur_config')
          .maybeSingle();
      final appSettings = DocumentGenerationService.coerceSettingsValue(cfgRow?['waarde']);

      final rawHtml = _text(tpl?['body_html']);
      final rawSubject = _text(tpl?['onderwerp']);
      var html = _stripPaymentBlock(rawHtml);
      var subject = rawSubject;

      final contactVoornaam = _text(invoice['contact_voornaam']).isEmpty ? 'relatie' : _text(invoice['contact_voornaam']);
      final factuurNummer = _text(invoice['factuur_nummer']);
      final totaalInc = _eur().format(_asDouble(invoice['totaal_inc_btw']));
      final vervalDatum = _asDate(invoice['verval_datum']);
      final vervalDatumStr = vervalDatum == null ? '—' : DateFormat('dd-MM-yyyy').format(vervalDatum);
      final mijnBedrijfsnaam = _text(appSettings['bedrijfsnaam']);

      final replacements = <String, String>{
        '{{contact_voornaam}}': contactVoornaam,
        '{{factuur_nummer}}': factuurNummer,
        '{{totaal_inc_btw}}': totaalInc,
        '{{verval_datum}}': vervalDatumStr,
        '{{mijn_bedrijfsnaam}}': mijnBedrijfsnaam,
      };

      for (final e in replacements.entries) {
        html = html.replaceAll(e.key, e.value);
        subject = subject.replaceAll(e.key, e.value);
      }

      // PDF generation + Base64 attachment for Edge Function JSON payload.
      final Uint8List pdfBytes = await PdfInvoiceService.generateInvoicePdf(invoiceId);
      final String base64Pdf = base64Encode(pdfBytes);
      final attachment = [
        {
          'filename': '${factuurNummer.isEmpty ? invoiceId : factuurNummer}.pdf',
          'content': base64Pdf,
          'encoding': 'base64',
        }
      ];

      final success = await EmailService.sendEmail(
        to: toEmail,
        subject: subject,
        htmlBody: html,
        fromEmail: 'finance@facilitairdomein.nl',
        fromName: mijnBedrijfsnaam.isEmpty ? 'Finance' : mijnBedrijfsnaam,
        attachments: attachment,
      );

      if (!success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent.withValues(alpha: 0.90),
            content: const Text(
              'Fout bij verzenden van e-mail. Controleer het e-mailadres van de klant.',
            ),
          ),
        );
        return;
      }

      // Success flow: update status + audit log.
      await AppSupabase.client.from('facturen').update({'status': 'verzonden'}).eq('id', invoiceId);

      final currentUser = Supabase.instance.client.auth.currentUser;
      await AppSupabase.client.from('finance_audit_log').insert({
        'user_id': currentUser?.id,
        'actie': 'EMAIL_VERZONDEN',
        'tabel_naam': 'facturen',
        'record_id': invoiceId,
        'data_snapshot': {
          'email_to': toEmail,
          'status': 'verzonden',
        },
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.90),
          content: const Text('Factuur succesvol verzonden naar de klant.'),
        ),
      );
      _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent.withValues(alpha: 0.90),
          content: const Text('Fout bij verzenden van e-mail. Controleer het e-mailadres van de klant.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _emailBusy = false);
    }
  }

  Future<void> _creditInvoice({
    required Map<String, dynamic> invoice,
  }) async {
    if (_creditBusy) return;

    final invoiceId = _text(invoice['id']);
    if (invoiceId.isEmpty) return;

    final reasonController = TextEditingController();

    final ok = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool localBusy = false;
        String? localError;

        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> submit() async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                setState(() => localError = 'Reden is verplicht.');
                return;
              }
              setState(() {
                localBusy = true;
                localError = null;
              });
              Navigator.of(context).pop(reason);
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                'Factuur Crediteren',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: Colors.redAccent,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'U staat op het punt een officiële creditfactuur te genereren. De originele factuur wordt gemarkeerd als vervallen/gecrediteerd.',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    enabled: !localBusy,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Reden van creditering (Verplicht voor de fiscus)',
                      errorText: localError,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: localBusy ? null : () => Navigator.of(context).pop(null),
                  child: const Text('Annuleren'),
                ),
                FilledButton(
                  onPressed: localBusy ? null : submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: localBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Crediteren',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    final reasonText = ok?.trim() ?? '';
    if (reasonText.isEmpty || !mounted) return;

    setState(() => _creditBusy = true);
    try {
      final newId = await Supabase.instance.client.rpc(
        'maak_credit_factuur',
        params: {
          'p_bron_factuur_id': invoiceId,
          'p_reden': reasonText,
        },
      );

      final newIdText = (newId ?? '').toString().trim();
      if (newIdText.isEmpty) throw Exception('Geen nieuw factuur-id ontvangen.');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.90),
          content: const Text(
            'Creditfactuur aangemaakt als concept. Pas eventueel regels aan voordat u hem definitief maakt.',
          ),
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: newIdText),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon factuur niet crediteren: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _creditBusy = false);
    }
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  DateTime? _asDate(dynamic v) {
    final s = _text(v);
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  NumberFormat _eur() => NumberFormat.currency(
        locale: 'nl_NL',
        symbol: '€',
        decimalDigits: 2,
      );

  Future<void> _deleteLine(String lineId) async {
    try {
      await AppSupabase.client.from('factuur_regels').delete().eq('id', lineId);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon regel niet verwijderen: $e'),
        ),
      );
    }
  }

  Future<void> _persistOrderSilently() async {
    try {
      final updates = <Map<String, dynamic>>[];
      for (var i = 0; i < _lines.length; i++) {
        final id = _text(_lines[i]['id']);
        if (id.isEmpty) continue;
        updates.add({'id': id, 'volgorde': i + 1});
      }
      if (updates.isEmpty) return;
      await AppSupabase.client.from('factuur_regels').upsert(updates);
    } catch (_) {
      // Silent: reordering shouldn't interrupt editing flow.
    }
  }

  Future<void> _openMagicAddLineSheet() async {
    final artikelen = List<Map<String, dynamic>>.from(_artikelen)
      ..removeWhere((a) {
        final raw = a['is_actief'];
        if (raw == null) return false; // column might not exist yet
        if (raw is bool) return raw == false;
        return raw.toString().toLowerCase() == 'false';
      });

    if (artikelen.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: const Text('Geen actieve artikelen gevonden. Voeg eerst een artikel toe.'),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddInvoiceLineSheet(
        artikelen: artikelen,
        onAddArticle: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              settings: const RouteSettings(name: '/admin/finance/articles'),
              builder: (_) => const ArticleManagementScreen(),
            ),
          );
          _refresh();
        },
        onSubmit: (payload) async {
          final volgorde = _lines.length + 1;
          await AppSupabase.client.from('factuur_regels').insert({
            'factuur_id': widget.invoiceId,
            'artikel_id': payload.artikelId,
            'omschrijving': payload.omschrijving,
            'aantal': payload.aantal,
            'stukprijs_ex_btw': payload.stukprijsExBtw,
            'korting_percentage': payload.kortingPercentage,
            'volgorde': volgorde,
          });
          _refresh();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? cs.surface.withValues(alpha: 0.92) : Colors.white;
    final softBg = isDark ? cs.surface.withValues(alpha: 0.70) : const Color(0xFFF5F5F7);

    return FutureBuilder<_ErpInvoiceDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MainLayout(
            child: Scaffold(
              drawer: AppDrawer(),
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return MainLayout(
            child: PopScope(
              canPop: !_hasUnsavedChanges,
              onPopInvokedWithResult: (didPop, _) async {
                if (didPop) return;
                await _handleBackButton();
              },
              child: Scaffold(
                drawer: const AppDrawer(),
                backgroundColor: const Color(0xFFF4F5F7),
                appBar: AppBar(
                  backgroundColor: Colors.white,
                  elevation: 1,
                  shadowColor: Colors.black12,
                  leading: BackButton(onPressed: () => _handleBackButton()),
                  title: const Text(
                    'Terug naar overzicht',
                    style: TextStyle(color: Colors.black, fontSize: 14),
                  ),
                ),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Kan factuur niet laden: ${snapshot.error}'),
                  ),
                ),
              ),
            ),
          );
        }

        final inv = snapshot.data!.invoice;
        final factuurDatum = _asDate(inv['factuur_datum'] ?? inv['datum']);
        final po = _text(inv['klant_referentie']);
                final btwVerlegd = _localBtwVerlegd ?? _asBool(inv['btw_verlegd']);
                final rawKorting = _localFactuurKortingPercentage ??
                    _asDouble(inv['factuur_korting_percentage'] ?? inv['factuurkorting_percentage']);
                final factuurKorting = rawKorting < 0 ? 0.0 : rawKorting;
        final status = _text(inv['status']).toLowerCase();
        final isConcept = status == 'concept';
        final isDefinitief = status == 'definitief';
        final isVerzonden = status == 'verzonden';
        final canCredit = isDefinitief || isVerzonden;

        final bedrijfn = (() {
          final b = inv['bedrijven'];
          if (b is Map) return _text(b['bedrijfsnaam']);
          return '';
        })();
        final klantNaam = bedrijfn.isNotEmpty ? bedrijfn : _text(inv['debiteur_naam']);

        final subtotaal = _asDouble(inv['totaal_ex_btw'] ?? inv['subtotaal_ex_btw']);
        final btw = _asDouble(inv['totaal_btw'] ?? inv['btw_bedrag']);
        final totaal = _asDouble(inv['totaal_inc_btw']);

        return MainLayout(
          child: PopScope(
            canPop: !_hasUnsavedChanges,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              await _handleBackButton();
            },
            child: Scaffold(
              drawer: const AppDrawer(),
            backgroundColor: const Color(0xFFF4F5F7),
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 1,
              shadowColor: Colors.black12,
              leading: BackButton(onPressed: () => _handleBackButton()),
              title: const Text(
                'Terug naar overzicht',
                style: TextStyle(color: Colors.black, fontSize: 14),
              ),
            actions: [
              if (canCredit)
                IconButton(
                  tooltip: 'Factuur Crediteren',
                  onPressed: _creditBusy ? null : () => _creditInvoice(invoice: inv),
                  icon: const Icon(Icons.undo_rounded),
                ),
              IconButton(
                tooltip: 'PDF preview',
                onPressed: _pdfBusy
                    ? null
                    : () => _previewPdf(
                          invoice: inv,
                          lines: snapshot.data!.lines,
                        ),
                icon: const Icon(Icons.picture_as_pdf),
              ),
              IconButton(
                tooltip: 'Vernieuwen',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
              ),
          floatingActionButton: isConcept
              ? FloatingActionButton.extended(
                  onPressed: _openMagicAddLineSheet,
                  icon: const Icon(Icons.add),
                  label: Text(
                    '+ Regel Toevoegen',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                  ),
                )
              : null,
          bottomNavigationBar: SafeArea(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0912),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _TotalCell(label: 'Totaal ex. BTW', value: _eur().format(subtotaal)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TotalCell(label: 'BTW', value: _eur().format(btw)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TotalCell(
                          label: 'Totaal incl. BTW',
                          value: _eur().format(totaal),
                          isEmphasis: true,
                        ),
                      ),
                    ],
                  ),
                  if (isConcept) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _finalizeBusy ? null : () => _confirmAndFinalize(invoice: inv),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        child: _finalizeBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                '✅ Bevestig & Maak Definitief',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                              ),
                      ),
                    ),
                  ],
                  if (isDefinitief) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _emailBusy ? null : () => _sendInvoiceEmail(invoice: inv),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        icon: _emailBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.email_outlined),
                        label: Text(
                          _emailBusy ? 'Verzenden…' : 'Verstuur naar Klant',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                if (!isConcept) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4D6),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock,
                          color: Colors.black.withValues(alpha: 0.70),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '🔒 Deze factuur is definitief en fiscaal vergrendeld. Wijzigingen zijn niet meer mogelijk.',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              color: Colors.black.withValues(alpha: 0.82),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _Card(
                  background: tileBg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        klantNaam.isEmpty ? '—' : klantNaam,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Factuurdatum: ${factuurDatum == null ? '—' : DateFormat('dd-MM-yyyy').format(factuurDatum)}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface.withValues(alpha: 0.70),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PO / Referentie: ${po.isEmpty ? '—' : po}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface.withValues(alpha: 0.70),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: isDark ? 0.04 : 0.03),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.10 : 0.06),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fiscale instellingen',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Btw Verlegd (WKA)',
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const EnterpriseTooltip(
                                            message:
                                                'Verlegt de BTW volautomatisch naar 0% en voegt de wettelijke WKA tekst toe aan de PDF.',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        btwVerlegd ? 'Actief (BTW naar 0%)' : 'Uitgeschakeld',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          color: cs.onSurface.withValues(alpha: 0.65),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                CupertinoSwitch(
                                  value: btwVerlegd,
                                  onChanged: (!isConcept || _taxBusy) ? null : _setBtwVerlegd,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Text(
                                        'Korting op totaal',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const EnterpriseTooltip(
                                        message:
                                            'Stelt de globale factuurkorting in. Supabase berekent automatisch de correcties voor totalen en BTW.',
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: (!isConcept || _discountBusy)
                                      ? null
                                      : () => _openGlobalDiscountDialog(factuurKorting),
                                  style: OutlinedButton.styleFrom(
                                    shape: const StadiumBorder(),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    side: BorderSide(color: cs.onSurface.withValues(alpha: 0.14)),
                                  ),
                                  child: Text(
                                    '${factuurKorting.toStringAsFixed(factuurKorting % 1 == 0 ? 0 : 2)}%',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _lines.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: softBg,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                          ),
                          child: Text(
                            'Nog geen factuurregels. Voeg er één toe via “+ Regel Toevoegen”.',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                        )
                      : ReorderableListView.builder(
                          itemCount: _lines.length,
                          onReorder: isConcept
                              ? (oldIndex, newIndex) {
                                  setState(() {
                                    if (newIndex > oldIndex) newIndex -= 1;
                                    final item = _lines.removeAt(oldIndex);
                                    _lines.insert(newIndex, item);
                                  });
                                  _persistOrderSilently();
                                }
                              : (oldIndex, newIndex) {},
                          padding: const EdgeInsets.only(bottom: 96),
                          itemBuilder: (context, index) {
                            final l = _lines[index];
                            final lineId = _text(l['id']);
                            final oms = _text(l['omschrijving']);
                            final qty = _asDouble(l['aantal']);
                            final unit = _asDouble(l['stukprijs_ex_btw']);
                            final total = _asDouble(l['regel_totaal_ex_btw'] ?? (qty * unit));
                            final btwCode = _text(l['btw_code']).isNotEmpty
                                ? _text(l['btw_code'])
                                : _text(l['btw_percentage']);
                            final marge = _asDouble(l['regel_marge_euro']);

                            final key = ValueKey(lineId.isEmpty ? 'line_$index' : lineId);

                            final tile = Container(
                              key: key,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: cs.onSurface.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ReorderableDragStartListener(
                                    index: index,
                                    enabled: isConcept,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.drag_handle_rounded,
                                        color: isConcept
                                            ? cs.onSurface.withValues(alpha: 0.45)
                                            : cs.onSurface.withValues(alpha: 0.20),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          oms.isEmpty ? '—' : oms,
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)} x ${_eur().format(unit)} = ${_eur().format(total)}',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w700,
                                            color: cs.onSurface.withValues(alpha: 0.70),
                                          ),
                                        ),
                                        if (marge != 0) ...[
                                          const SizedBox(height: 6),
                                          Builder(
                                            builder: (context) {
                                              final isLoss = marge < 0;
                                              final bg = isLoss
                                                  ? const Color(0xFFFFE7E7)
                                                  : Colors.green.withValues(alpha: 0.10);
                                              final fg = isLoss
                                                  ? const Color(0xFF8B1E1E)
                                                  : Colors.green.withValues(alpha: 0.85);
                                              final border = isLoss
                                                  ? const Color(0xFFFFB9B9)
                                                  : Colors.green.withValues(alpha: 0.25);

                                              return Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: bg,
                                                  borderRadius: BorderRadius.circular(999),
                                                  border: Border.all(color: border),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withValues(
                                                        alpha: isLoss ? 0.05 : 0.03,
                                                      ),
                                                      blurRadius: 10,
                                                      offset: const Offset(0, 6),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  'Marge: ${_eur().format(marge)}',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w900,
                                                    color: fg,
                                                    letterSpacing: -0.1,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      btwCode.isEmpty ? '—' : btwCode,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (!isConcept) return tile;

                            return Dismissible(
                              key: key,
                              direction: DismissDirection.endToStart,
                              background: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                alignment: Alignment.centerRight,
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.90),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const Icon(Icons.delete_outline, color: Colors.white),
                              ),
                              onDismissed: (_) {
                                if (lineId.isNotEmpty) _deleteLine(lineId);
                              },
                              child: tile,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
            ),
          ),
        );
      },
    );
  }

}

class _ErpInvoiceDetail {
  const _ErpInvoiceDetail({
    required this.invoice,
    required this.lines,
    required this.artikelen,
    required this.grootboek,
  });

  final Map<String, dynamic> invoice;
  final List<Map<String, dynamic>> lines;
  final List<Map<String, dynamic>> artikelen;
  final List<Map<String, dynamic>> grootboek;
}

class _Card extends StatelessWidget {
  const _Card({required this.background, required this.child});

  final Color background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TotalCell extends StatelessWidget {
  const _TotalCell({
    required this.label,
    required this.value,
    this.isEmphasis = false,
  });

  final String label;
  final String value;
  final bool isEmphasis;

  @override
  Widget build(BuildContext context) {
    final styleLabel = GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: Colors.white.withValues(alpha: 0.70),
    );
    final styleValue = GoogleFonts.inter(
      fontSize: isEmphasis ? 18 : 16,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.3,
      color: Colors.white,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: styleLabel),
        const SizedBox(height: 6),
        Text(value, style: styleValue),
      ],
    );
  }
}

class _InvoiceLineDraft {
  const _InvoiceLineDraft({
    required this.artikelId,
    required this.omschrijving,
    required this.aantal,
    required this.stukprijsExBtw,
    required this.kortingPercentage,
  });

  final String artikelId;
  final String omschrijving;
  final double aantal;
  final double stukprijsExBtw;
  final double kortingPercentage;
}

class _AddInvoiceLineSheet extends StatefulWidget {
  const _AddInvoiceLineSheet({
    required this.artikelen,
    required this.onAddArticle,
    required this.onSubmit,
  });

  final List<Map<String, dynamic>> artikelen;
  final Future<void> Function() onAddArticle;
  final Future<void> Function(_InvoiceLineDraft payload) onSubmit;

  @override
  State<_AddInvoiceLineSheet> createState() => _AddInvoiceLineSheetState();
}

class _AddInvoiceLineSheetState extends State<_AddInvoiceLineSheet> {
  String? _artikelId;
  bool _saving = false;

  final _qty = TextEditingController(text: '1');
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _discount = TextEditingController();

  Map<String, dynamic>? get _article {
    final id = _artikelId;
    if (id == null) return null;
    return widget.artikelen.cast<Map<String, dynamic>?>().firstWhere(
          (a) => (a?['id'] ?? '').toString() == id,
          orElse: () => null,
        );
  }

  bool _isFractioneel(Map<String, dynamic> a) {
    final raw = a['is_fractioneel'] ?? a['fractioneel'];
    if (raw is bool) return raw;
    return raw?.toString().toLowerCase() == 'true';
  }

  String _pickOmschrijving(Map<String, dynamic> a) {
    final candidates = [
      a['omschrijving_factuur'],
      a['factuur_omschrijving'],
      a['omschrijving_intern'],
      a['naam'],
    ];
    for (final c in candidates) {
      final s = (c ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  double _pickStukprijs(Map<String, dynamic> a) {
    final candidates = [
      a['stukprijs_ex_btw'],
      a['verkoopprijs_ex_btw'],
      a['standaard_prijs_ex_btw'],
      a['verkoopprijs'],
    ];
    for (final c in candidates) {
      if (c is num) return c.toDouble();
      final s = (c ?? '').toString().replaceAll(',', '.');
      final v = double.tryParse(s);
      if (v != null) return v;
    }
    return 0;
  }

  @override
  void dispose() {
    _qty.dispose();
    _desc.dispose();
    _price.dispose();
    _discount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? cs.surface.withValues(alpha: 0.92) : Colors.white;

    final a = _article;
    final isFractioneel = a == null ? true : _isFractioneel(a);

    final qtyFormatters = isFractioneel
        ? <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'^[0-9]+([\\.,][0-9]{0,2})?\$')),
          ]
        : <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, -12),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Factuurregel toevoegen',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sluiten',
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Artikel (verplicht)'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _artikelId,
                          hint: const Text('Selecteer artikel'),
                          items: widget.artikelen
                              .map((x) {
                                final id = (x['id'] ?? '').toString();
                                if (id.isEmpty) return null;
                                final code = (x['artikel_code'] ?? '').toString().trim();
                                final nm = _pickOmschrijving(x);
                                final label =
                                    [code, nm].where((e) => e.trim().isNotEmpty).join(' — ');
                                return DropdownMenuItem(value: id, child: Text(label));
                              })
                              .whereType<DropdownMenuItem<String>>()
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (v) {
                                  setState(() {
                                    _artikelId = v;
                                    final a = _article;
                                    if (a == null) return;
                                    _desc.text = _pickOmschrijving(a);
                                    _price.text = _pickStukprijs(a).toStringAsFixed(2);
                                    _qty.text = '1';
                                  });
                                },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : widget.onAddArticle,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(Icons.add),
                    label: Text(
                      'Nieuw Artikel',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _desc,
                enabled: !_saving && _artikelId != null,
                decoration: const InputDecoration(labelText: 'Omschrijving'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qty,
                      enabled: !_saving && _artikelId != null,
                      keyboardType: TextInputType.numberWithOptions(decimal: isFractioneel),
                      inputFormatters: qtyFormatters,
                      decoration: InputDecoration(
                        labelText: 'Aantal',
                        suffixIcon: (!isFractioneel)
                            ? const EnterpriseTooltip(
                                message:
                                    'Dit artikel kan alleen in hele eenheden worden verkocht.',
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _price,
                      enabled: !_saving && _artikelId != null,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^[0-9]+([\\.,][0-9]{0,2})?\$')),
                      ],
                      decoration: const InputDecoration(labelText: 'Stukprijs ex. BTW'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _discount,
                enabled: !_saving && _artikelId != null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^[0-9]+([\\.,][0-9]{0,2})?\$')),
                ],
                decoration: InputDecoration(
                  labelText: 'Korting (%)',
                  suffixIcon: const EnterpriseTooltip(
                    message:
                        'Optionele korting op deze regel. 100% korting of €0,00 is toegestaan voor service/coulance-regels.',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_saving || _artikelId == null)
                      ? null
                      : () async {
                          final artikelId = _artikelId ?? '';
                          if (artikelId.isEmpty) return;

                          final qty = double.tryParse(_qty.text.replaceAll(',', '.')) ?? 0;
                          final price = double.tryParse(_price.text.replaceAll(',', '.')) ?? 0;
                          final discRaw = _discount.text.trim().replaceAll(',', '.');
                          final discount = discRaw.isEmpty
                              ? 0.0
                              : (double.tryParse(discRaw) ?? double.nan);
                          final oms = _desc.text.trim();
                          if (qty <= 0 || price < 0 || oms.isEmpty) return;
                          if (discount.isNaN || discount < 0 || discount > 100) return;

                          setState(() => _saving = true);
                          try {
                            await widget.onSubmit(
                              _InvoiceLineDraft(
                                artikelId: artikelId,
                                omschrijving: oms,
                                aantal: qty,
                                stukprijsExBtw: price,
                                kortingPercentage: discount,
                              ),
                            );
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.green.withValues(alpha: 0.90),
                                content: const Text('Factuurregel toegevoegd.'),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
                                content: Text('Kon factuurregel niet toevoegen: $e'),
                              ),
                            );
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    _saving ? 'Bezig…' : 'Opslaan',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

