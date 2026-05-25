import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../widgets/quote_summary_modal.dart';
import '../widgets/room_add_modal.dart';
import 'project_overview_screen.dart';
import 'quote_create_header_screen.dart';

class QuoteSurveyScreen extends StatefulWidget {
  const QuoteSurveyScreen({
    super.key,
    required this.offerteId,
    this.isDirectProject = false,
    this.standaardArtikelCode,
  });

  final String offerteId;
  /// When true, completion sets [offertes.status] to `signed` (direct project flow).
  final bool isDirectProject;
  final String? standaardArtikelCode;

  @override
  State<QuoteSurveyScreen> createState() => _QuoteSurveyScreenState();
}

class _QuoteSurveyScreenState extends State<QuoteSurveyScreen> {
  final NumberFormat _eur = NumberFormat.currency(locale: 'nl_NL', symbol: '€ ');
  bool _closing = false;
  double? vastePrijsOverride;

  @override
  void initState() {
    super.initState();
    _fetchOfferteData();
  }

  Future<void> _fetchOfferteData() async {
    try {
      final offerteData = await AppSupabase.client
          .from('offertes')
          .select('vaste_prijs_override')
          .eq('id', widget.offerteId)
          .maybeSingle();
      if (!mounted || offerteData == null) return;
      setState(() {
        vastePrijsOverride = double.tryParse(
          offerteData['vaste_prijs_override']?.toString() ?? '',
        );
      });
    } catch (_) {
      // Stil falen: bottom bar leest override ook uit de stream.
    }
  }

  Future<void> _toonPrijsafspraakModal() async {
    final controller = TextEditingController(
      text: vastePrijsOverride?.toStringAsFixed(2) ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vaste Prijsafspraak'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Dit overschrijft de automatisch berekende prijs voor deze klus.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Vaste prijs (ex. BTW)',
                prefixIcon: Icon(Icons.euro),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await AppSupabase.client
                  .from('offertes')
                  .update({'vaste_prijs_override': null})
                  .eq('id', widget.offerteId);
              if (!mounted) return;
              setState(() => vastePrijsOverride = null);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Wis afspraak', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(controller.text.replaceAll(',', '.'));
              if (val != null) {
                await AppSupabase.client
                    .from('offertes')
                    .update({'vaste_prijs_override': val})
                    .eq('id', widget.offerteId);
                if (!mounted) return;
                setState(() => vastePrijsOverride = val);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );

    controller.dispose();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(_text(v).replaceAll(',', '.')) ?? 0.0;
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(_text(v)) ?? fallback;
  }

  IconData _getRoomIcon(String category) {
    switch (category) {
      case 'KAMERS':
        return Icons.desk_outlined;
      case 'SANITAIR':
        return Icons.wc_outlined;
      case 'ZALEN':
        return Icons.meeting_room_outlined;
      case 'KEUKENS':
        return Icons.kitchen_outlined;
      case 'Hallen en gangen':
        return Icons.directions_walk_outlined;
      case 'TRAPPENHUIZEN':
        return Icons.stairs_outlined;
      case 'KASTEN EN OPSLAG':
        return Icons.inventory_2_outlined;
      default:
        return Icons.room_outlined;
    }
  }

  Map<String, dynamic>? _extractOfferte(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return null;
    return rows.first;
  }

  String _statusOf(Map<String, dynamic>? offerte) {
    final s = _text(offerte?['status']).toLowerCase();
    if (s == 'verzonden') return 'send';
    if (s == 'getekend') return 'signed';
    return s;
  }

  bool _isConceptStatus(String status) => status == 'concept' || status == 'new';

  Future<void> _showSummary({
    required Map<String, dynamic> offerte,
    required List<Map<String, dynamic>> ruimtes,
    required bool readOnly,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SelectionArea(
        child: QuoteSummaryModal(
          offerte: offerte,
          ruimtes: ruimtes,
          readOnly: readOnly,
        ),
      ),
    );
  }

  Future<void> _openRoomModal({
    required BuildContext context,
    Map<String, dynamic>? existingRoom,
  }) async {
    final didSave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width > 800
            ? 1200
            : MediaQuery.of(context).size.width,
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => SelectionArea(
        child: RoomAddModal(
          offerteId: widget.offerteId,
          existingRoom: existingRoom,
          onSaved: () {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(
                  existingRoom == null ? 'Ruimte toegevoegd.' : 'Ruimte bijgewerkt.',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            );
          },
        ),
      ),
    );

    if (didSave == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _reviseToConcept(String offerteId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Offerte heropenen?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Wilt u deze offerte heropenen? De status gaat terug naar Concept.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Annuleren', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Heropenen', style: GoogleFonts.inter(fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    await AppSupabase.client.from('offertes').update({'status': 'concept'}).eq('id', offerteId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Offerte is heropend (Concept).',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Future<void> _saveAndClose({required String status}) async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      // "Save" step: persist the quote row (touch update) so the editor always
      // exits after a real DB write. Rooms are saved independently.
      await AppSupabase.client
          .from('offertes')
          .update({'status': status})
          .eq('id', widget.offerteId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade800,
          content: Text(
            'Opslaan mislukt: $e',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.meeting_room_outlined,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 14),
            Text(
              'Nog geen ruimtes toegevoegd',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Klik op de knop rechtsonder om de eerste ruimte op te nemen.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onPrimaryAction({
    required Map<String, dynamic>? offerte,
    required List<Map<String, dynamic>> ruimtes,
  }) async {
    if (offerte == null) return;

    if (widget.isDirectProject) {
      if (ruimtes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Voeg minimaal één ruimte toe voordat je activeert.',
              style: GoogleFonts.lato(fontWeight: FontWeight.w800),
            ),
          ),
        );
        return;
      }
      try {
        await AppSupabase.client
            .from('offertes')
            .update({'status': 'signed'}).eq('id', widget.offerteId);

        final artikelCode = _text(widget.standaardArtikelCode);
        if (artikelCode.isNotEmpty) {
          await AppSupabase.client
              .from('projecten')
              .update({'standaard_artikel_code': artikelCode})
              .eq('offerte_id', widget.offerteId);
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF16A34A),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            content: Text(
              'Project succesvol geactiveerd! De opdrachten staan nu op het planbord.',
              style: GoogleFonts.lato(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            settings: const RouteSettings(name: '/facilitator/projecten'),
            builder: (_) => const ProjectOverviewScreen(),
          ),
          (route) => route.isFirst,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade800,
            content: Text(
              'Activeren mislukt: $e',
              style: GoogleFonts.lato(fontWeight: FontWeight.w800),
            ),
          ),
        );
      }
      return;
    }

    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final didSend = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SelectionArea(
        child: QuoteSummaryModal(
          offerte: offerte,
          ruimtes: ruimtes,
        ),
      ),
    );

    if (didSend == true && mounted) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E8E3E),
          content: Text(
            'Offerte is definitief gemaakt en wordt nu via de achtergrond verzonden!',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) {
        navigator.popUntil((route) => route.isFirst);
      }
    }
  }

  Widget _buildExpandableRoomTile(Map<String, dynamic> room) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final naam = _text(room['naam_in_pand']).isEmpty ? 'Onbenoemde ruimte' : _text(room['naam_in_pand']);
    final categorie = _text(room['ruimte_categorie']).isEmpty
        ? 'Onbekende categorie'
        : _text(room['ruimte_categorie']);
    final parsedAantal = _asInt(room['aantal_identiek'], fallback: 1);
    final aantal = parsedAantal < 1 ? 1 : parsedAantal;
    final roomId = room['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111019) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        childrenPadding: EdgeInsets.zero,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getRoomIcon(categorie),
            color: cs.primary,
            size: 22,
          ),
        ),
        title: StreamBuilder<List<Map<String, dynamic>>>(
          stream: AppSupabase.client
              .from('offertes')
              .stream(primaryKey: ['id'])
              .eq('id', widget.offerteId),
          builder: (context, snapshot) {
            final offerte = snapshot.hasData ? _extractOfferte(snapshot.data!) : null;
            final status = _statusOf(offerte);
            final canEdit = _isConceptStatus(status);
            return InkWell(
              onTap: !canEdit
                  ? null
                  : () => _openRoomModal(context: context, existingRoom: room),
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      naam,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'x $aantal',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      color: theme.primaryColor,
                      fontSize: 16,
                    ),
                  ),
                  if (canEdit) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.edit_note_rounded,
                        color: cs.primary.withValues(alpha: 0.9)),
                  ],
                ],
              ),
            );
          },
        ),
        subtitle: Text(
          categorie,
          style: GoogleFonts.inter(
            color: Colors.grey,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey.withValues(alpha: 0.22)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: Supabase.instance.client
                  .from('offerte_ruimte_diensten')
                  .select('*, moeder_bestek(volledige_naam, eenheid)')
                  .eq('offerte_ruimte_id', roomId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      'Diensten laden mislukt.',
                      style: GoogleFonts.inter(
                        color: Colors.red.shade300,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }

                final diensten = snapshot.data ?? const <Map<String, dynamic>>[];
                if (diensten.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      'Geen diensten gekoppeld.',
                      style: GoogleFonts.inter(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: diensten.length,
                  itemBuilder: (context, index) {
                    final dienst = diensten[index];
                    final moederBestek = dienst['moeder_bestek'] as Map<String, dynamic>? ?? const {};
                    final naam = _text(moederBestek['volledige_naam']).isEmpty
                        ? 'Onbekende dienst'
                        : _text(moederBestek['volledige_naam']);
                    final eenheid = _text(moederBestek['eenheid']);

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                      leading: const Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.green,
                      ),
                      title: Text(
                        naam,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      trailing: Text(
                        eenheid,
                        style: GoogleFonts.inter(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);
    final offerteStream =
        AppSupabase.client.from('offertes').stream(primaryKey: ['id']).eq('id', widget.offerteId);
    final ruimtesStream = Supabase.instance.client
        .from('offerte_ruimtes')
        .stream(primaryKey: ['id'])
        .eq('offerte_id', widget.offerteId)
        .order('id', ascending: true);

    return Scaffold(
      backgroundColor: bg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: StreamBuilder<List<Map<String, dynamic>>>(
          stream: offerteStream,
          builder: (context, snapshot) {
            final offerte = snapshot.hasData ? _extractOfferte(snapshot.data!) : null;
            final bedrijfsnaam = _text(offerte?['bedrijfsnaam_klant']);
            return Text(
              bedrijfsnaam.isEmpty ? 'Opname' : 'Opname: $bedrijfsnaam',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
            );
          },
        ),
        actions: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: offerteStream,
            builder: (context, snapshot) {
              final offerte = snapshot.hasData ? _extractOfferte(snapshot.data!) : null;
              final status = _statusOf(offerte);
              final isConcept = _isConceptStatus(status);
              if (!isConcept || offerte == null) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Bewerk kaft (Stap 1)',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      settings: const RouteSettings(name: '/facilitator/quotes/header/edit'),
                      builder: (_) => QuoteCreateHeaderScreen(offerteId: widget.offerteId),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_note_rounded),
              );
            },
          ),
        ],
      ),
      body: SelectionArea(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: ruimtesStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Kon ruimtes niet laden:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
              );
            }

            final ruimtes = snapshot.data ?? const <Map<String, dynamic>>[];
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ruimtes.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 320),
                        itemCount: ruimtes.length,
                        itemBuilder: (context, i) => _buildExpandableRoomTile(ruimtes[i]),
                      ),
              ),
            );
          },
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: StreamBuilder<List<Map<String, dynamic>>>(
        stream: offerteStream,
        builder: (context, snapshot) {
          final offerte = snapshot.hasData ? _extractOfferte(snapshot.data!) : null;
          final status = _statusOf(offerte);
          final isConcept = _isConceptStatus(status);
          if (!isConcept) return const SizedBox.shrink();
          final isMobileCompact = MediaQuery.of(context).size.width < 600;
          return Padding(
            padding: EdgeInsets.only(bottom: isMobileCompact ? 200 : 260),
            child: FloatingActionButton.extended(
              onPressed: () {
                _openRoomModal(context: context);
              },
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              icon: const Icon(Icons.add_rounded, size: 28),
              label: Text(
                'Ruimte Toevoegen',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: offerteStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting || snapshot.hasError) {
              return const SizedBox.shrink();
            }

            final offerte = snapshot.hasData ? _extractOfferte(snapshot.data!) : null;
            final status = _statusOf(offerte);
            final isConcept = _isConceptStatus(status);
            final isSent = status == 'send';
            final isSigned = status == 'signed';
            final maandEx = _asDouble(offerte?['maandprijs_ex_btw']);
            final maandBtw = _asDouble(offerte?['maand_btw_bedrag']);
            final maandIncl = _asDouble(offerte?['maandprijs_inc_btw']);
            final totaalContract = _asDouble(offerte?['totaal_prijs_ex_btw']);
            final contractType = _text(offerte?['contract_type']).toLowerCase();
            final isEenmaligOfIncidenteel =
                contractType == 'eenmalig' || contractType == 'incidenteel';
            final regulier = _asInt(offerte?['regulier_aantal_beurten']);
            final frequent = _asInt(offerte?['frequent_aantal_beurten']);
            final periodiek = _asInt(offerte?['periodiek_aantal_beurten']);
            final rUren = _asDouble(offerte?['regulier_uren_per_beurt_afgerond']);
            final fUren = _asDouble(offerte?['frequent_uren_per_beurt_afgerond']);
            final pUren = _asDouble(offerte?['periodiek_uren_per_beurt_afgerond']);
            double roundToQuarter(double v) => (v * 4).roundToDouble() / 4.0;
            String fmtQuarter(double v) {
              final q = roundToQuarter(v);
              // Trim trailing zeros for a compact UI.
              var s = q.toStringAsFixed(2);
              s = s.replaceFirst(RegExp(r'\.?0+$'), '');
              return s;
            }

            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: ruimtesStream,
              builder: (context, ruimtesSnapshot) {
                final ruimtes = ruimtesSnapshot.data ?? const <Map<String, dynamic>>[];
                final Map<String, int> roomSummary = {};
                int totalRooms = 0;

                for (final room in ruimtes) {
                  final categoryRaw = _text(room['ruimte_categorie']);
                  final category = categoryRaw.isEmpty ? 'Onbekend' : categoryRaw;
                  final parsedCount = _asInt(room['aantal_identiek'], fallback: 1);
                  final count = parsedCount < 1 ? 1 : parsedCount;
                  roomSummary[category] = (roomSummary[category] ?? 0) + count;
                  totalRooms += count;
                }

                Widget buildFinanceColumn() {
                  final isCompact = MediaQuery.of(context).size.width < 600;

                  if (isEenmaligOfIncidenteel) {
                    final berekendeTotaalPrijs =
                        maandEx > 0 ? maandEx : totaalContract;
                    final weergavePrijs = vastePrijsOverride ?? berekendeTotaalPrijs;
                    final heeftPrijsafspraak = vastePrijsOverride != null;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Totaal per beurt: €${weergavePrijs.toStringAsFixed(2)} '
                          '${heeftPrijsafspraak ? '(Vaste prijs)' : ''}',
                          style: GoogleFonts.inter(
                            color: heeftPrijsafspraak
                                ? Colors.orange.shade300
                                : Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: isCompact ? 18 : 20,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Contractwaarde: ${_eur.format(totaalContract)}',
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: isCompact ? 11 : 12,
                          ),
                        ),
                        if (isConcept) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _toonPrijsafspraakModal,
                            icon: const Icon(Icons.handshake, size: 18),
                            label: const Text('Prijsafspraak'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange.shade300,
                              side: BorderSide(color: Colors.orange.shade400),
                            ),
                          ),
                        ],
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Totaal per maand (ex BTW): ${_eur.format(maandEx)}',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: isCompact ? 18 : 20,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Btw: ${_eur.format(maandBtw)} | Incl: ${_eur.format(maandIncl)}',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: isCompact ? 11 : 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Contractwaarde: ${_eur.format(totaalContract)}',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: isCompact ? 13.5 : 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (roundToQuarter(rUren) > 0 ||
                          roundToQuarter(fUren) > 0 ||
                          roundToQuarter(pUren) > 0)
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          children: [
                            if (roundToQuarter(rUren) > 0)
                              Text(
                                'Regulier: ${fmtQuarter(rUren)} uur',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: isCompact ? 12.5 : 14,
                                ),
                              ),
                            if (roundToQuarter(fUren) > 0)
                              Text(
                                'Frequent: ${fmtQuarter(fUren)} uur',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: isCompact ? 12.5 : 14,
                                ),
                              ),
                            if (roundToQuarter(pUren) > 0)
                              Text(
                                'Periodiek: ${fmtQuarter(pUren)} uur',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: isCompact ? 12.5 : 14,
                                ),
                              ),
                          ],
                        ),
                    ],
                  );
                }

                Widget buildExecutionsColumn() {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aantal Beurten',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Regulier: ${regulier}x',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Frequent: ${frequent}x',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Periodiek: ${periodiek}x',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  );
                }

                Widget buildInventoryColumn() {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inventarisatie',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: roomSummary.entries
                            .map(
                              (entry) => Text(
                                '${entry.key}: ${entry.value}',
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Totaal Ruimtes: $totalRooms',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  );
                }

                final isCompact = MediaQuery.of(context).size.width < 600;
                return Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(isCompact ? 12 : 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF15141F),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 760) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              runSpacing: 18,
                              children: [
                                buildFinanceColumn(),
                                buildExecutionsColumn(),
                                buildInventoryColumn(),
                              ],
                            ),
                            const SizedBox(height: 24),
                            if (isConcept)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        settings: const RouteSettings(
                                          name: '/facilitator/quotes/header/edit',
                                        ),
                                        builder: (_) => QuoteCreateHeaderScreen(
                                          offerteId: widget.offerteId,
                                        ),
                                      ),
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.30),
                                    ),
                                    minimumSize: const Size.fromHeight(50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  icon: const Icon(Icons.edit_note_rounded),
                                  label: Text(
                                    'Aanpassingen Kaft',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            if (isConcept) const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: offerte == null
                                        ? null
                                        : () => _saveAndClose(status: status),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                        color: Colors.white.withValues(alpha: 0.30),
                                      ),
                                      minimumSize: Size.fromHeight(isCompact ? 48 : 54),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                    child: Text(
                                      'Opslaan & Sluiten',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: isConcept
                                      ? ElevatedButton(
                                          onPressed: offerte == null
                                              ? null
                                              : () => _onPrimaryAction(
                                                    offerte: offerte,
                                                    ruimtes: ruimtes,
                                                  ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: cs.primary,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            minimumSize: Size.fromHeight(isCompact ? 48 : 54),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(24),
                                            ),
                                          ),
                                          child: Text(
                                            widget.isDirectProject
                                                ? '🚀 Project Activeren & Taken Genereren'
                                                : 'Maak definitief & Verzenden',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15,
                                            ),
                                          ),
                                        )
                                      : isSent
                                          ? ElevatedButton(
                                              onPressed: offerte == null
                                                  ? null
                                                  : () => _reviseToConcept(widget.offerteId),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: cs.primary,
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                minimumSize: Size.fromHeight(isCompact ? 48 : 54),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(24),
                                                ),
                                              ),
                                              child: Text(
                                                '🔄 Offerte aanpassen / Heropenen',
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            )
                                          : ElevatedButton(
                                              onPressed: offerte == null
                                                  ? null
                                                  : () => _showSummary(
                                                        offerte: offerte,
                                                        ruimtes: ruimtes,
                                                        readOnly: true,
                                                      ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: cs.primary,
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                minimumSize: Size.fromHeight(isCompact ? 48 : 54),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(24),
                                                ),
                                              ),
                                              child: Text(
                                                'View Details',
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                ),
                              ],
                            ),
                            if (!isConcept) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: offerte == null
                                      ? null
                                      : () => _showSummary(
                                            offerte: offerte,
                                            ruimtes: ruimtes,
                                            readOnly: true,
                                          ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(color: Colors.white.withValues(alpha: 0.30)),
                                    minimumSize: const Size.fromHeight(52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: Text(
                                    isSigned ? 'View Details' : 'View Details',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        behavior: SnackBarBehavior.floating,
                                        content: Text(
                                          'PDF is nog niet beschikbaar.',
                                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(color: Colors.white.withValues(alpha: 0.30)),
                                    minimumSize: const Size.fromHeight(52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: Text(
                                    'View PDF',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: buildFinanceColumn()),
                                const VerticalDivider(color: Colors.white24, width: 26, thickness: 1),
                                Expanded(child: buildExecutionsColumn()),
                                const VerticalDivider(color: Colors.white24, width: 26, thickness: 1),
                                Expanded(child: buildInventoryColumn()),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (isConcept)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      settings: const RouteSettings(
                                        name: '/facilitator/quotes/header/edit',
                                      ),
                                      builder: (_) => QuoteCreateHeaderScreen(
                                        offerteId: widget.offerteId,
                                      ),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.30),
                                  ),
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                                icon: const Icon(Icons.edit_note_rounded),
                                label: Text(
                                  'Aanpassingen Kaft',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          if (isConcept) const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: offerte == null
                                      ? null
                                      : () => _saveAndClose(status: status),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.30),
                                    ),
                                    minimumSize: const Size.fromHeight(56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: Text(
                                    'Opslaan & Sluiten',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: offerte == null
                                      ? null
                                      : () => _onPrimaryAction(
                                            offerte: offerte,
                                            ruimtes: ruimtes,
                                          ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: cs.primary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    minimumSize: const Size.fromHeight(56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: Text(
                                    widget.isDirectProject
                                        ? '🚀 Project Activeren & Taken Genereren'
                                        : 'Maak definitief & Verzenden',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
