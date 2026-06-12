import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/supabase/chat_service.dart';
import '../../../core/supabase_client.dart';
import '../helpers/paklijst_programma_helper.dart';

/// Simpele modal: operator deelt een melding in de project-chat van de klant.
class OperatorMeldingModal extends StatefulWidget {
  const OperatorMeldingModal({
    super.key,
    required this.projectId,
    required this.opdrachtNummer,
  });

  final String projectId;
  final String opdrachtNummer;

  static Future<void> showForPlanningItem(
    BuildContext context, {
    required Map<String, dynamic> planningItem,
  }) async {
    final ctx = await _resolveMeldingContext(planningItem);
    if (!context.mounted) return;
    if (ctx.projectId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Geen project gekoppeld aan deze opdracht.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    return show(context, projectId: ctx.projectId, opdrachtNummer: ctx.opdrachtNummer);
  }

  static Future<void> show(
    BuildContext context, {
    required String projectId,
    required String opdrachtNummer,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => OperatorMeldingModal(
        projectId: projectId,
        opdrachtNummer: opdrachtNummer,
      ),
    );
  }

  static Future<({String projectId, String opdrachtNummer})> _resolveMeldingContext(
    Map<String, dynamic> item,
  ) async {
    var projectId = _projectIdUitItem(item);
    var opdrachtNummer = _opdrachtNummerUitItem(item);
    final opdrachtId = opdrachtIdUitItem(item);

    if ((projectId.isEmpty || opdrachtNummer.isEmpty) && opdrachtId.isNotEmpty) {
      try {
        final row = await AppSupabase.client
            .from('opdrachten')
            .select('project_id, opdracht_nummer')
            .eq('id', opdrachtId)
            .maybeSingle();
        if (row != null) {
          final m = Map<String, dynamic>.from(row as Map);
          if (projectId.isEmpty) {
            projectId = (m['project_id'] ?? '').toString().trim();
          }
          if (opdrachtNummer.isEmpty) {
            opdrachtNummer = (m['opdracht_nummer'] ?? '').toString().trim();
          }
        }
      } catch (e) {
        debugPrint('OperatorMeldingModal: opdracht lookup mislukt: $e');
      }
    }

    return (projectId: projectId, opdrachtNummer: opdrachtNummer);
  }

  static String _projectIdUitItem(Map<String, dynamic> item) {
    final direct = (item['project_id'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final embed = item['opdrachten'] ?? item['opdracht'];
    if (embed is Map) {
      final fromEmbed = (embed['project_id'] ?? '').toString().trim();
      if (fromEmbed.isNotEmpty) return fromEmbed;
      final project = embed['projecten'] ?? embed['project'];
      if (project is Map) {
        final id = (project['id'] ?? '').toString().trim();
        if (id.isNotEmpty) return id;
      }
    }

    final projectTop = item['projecten'] ?? item['project'];
    if (projectTop is Map) {
      final id = (projectTop['id'] ?? '').toString().trim();
      if (id.isNotEmpty) return id;
    }

    return '';
  }

  static String _opdrachtNummerUitItem(Map<String, dynamic> item) {
    final direct = (item['opdracht_nummer'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final embed = item['opdrachten'] ?? item['opdracht'];
    if (embed is Map) {
      final n = (embed['opdracht_nummer'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }

    return '';
  }

  @override
  State<OperatorMeldingModal> createState() => _OperatorMeldingModalState();
}

class _OperatorMeldingModalState extends State<OperatorMeldingModal> {
  final _chatService = ChatService();
  final _tekstController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _tekstController.dispose();
    super.dispose();
  }

  Future<void> _verstuur() async {
    final tekst = _tekstController.text.trim();
    if (tekst.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul een melding in.')),
      );
      return;
    }
    if (_submitting) return;

    final projectId = widget.projectId.trim();
    if (projectId.isEmpty) {
      debugPrint(
        'Kan melding niet versturen: Geen project_id gevonden bij deze opdracht.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kan niet verzenden: Onbekend project.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _chatService.verstuurOperatorMeldingInProjectChat(
        projectId: projectId,
        opdrachtNummer: widget.opdrachtNummer,
        tekst: tekst,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Melding is succesvol doorgegeven aan kantoor!',
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('Fatale fout bij plaatsen operator melding: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fout bij verzenden: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final werkbonLabel = widget.opdrachtNummer.trim().isEmpty
        ? '—'
        : widget.opdrachtNummer.trim();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Melding maken',
        style: GoogleFonts.inter(fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Werkbon $werkbonLabel — je melding komt direct in de project-chat van de klant.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tekstController,
              maxLines: 5,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Beschrijf wat je wilt melden…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Annuleren'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _verstuur,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Melding versturen'),
        ),
      ],
    );
  }
}
