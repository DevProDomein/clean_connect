import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user_role.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import '../../../shared/widgets/enterprise_tooltip.dart';
import 'invoice_detail_screen.dart';

class InvoiceCreateHeaderScreen extends StatefulWidget {
  const InvoiceCreateHeaderScreen({super.key});

  @override
  State<InvoiceCreateHeaderScreen> createState() => _InvoiceCreateHeaderScreenState();
}

class _InvoiceCreateHeaderScreenState extends State<InvoiceCreateHeaderScreen> {
  Future<List<Map<String, dynamic>>>? _futureClients;
  bool _saving = false;

  Map<String, dynamic>? _selectedClient;
  DateTime _invoiceDate = DateTime.now();
  final _poCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _futureClients = _fetchClients();
  }

  @override
  void dispose() {
    _poCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchClients() async {
    final res = await AppSupabase.client
        .from('bedrijven')
        .select('id, bedrijfsnaam, is_klant')
        .eq('is_klant', true)
        .order('bedrijfsnaam', ascending: true);
    return (res as List).cast<Map<String, dynamic>>();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      helpText: 'Selecteer factuurdatum',
      cancelText: 'Annuleren',
      confirmText: 'Kiezen',
    );
    if (picked == null || !mounted) return;
    setState(() => _invoiceDate = picked);
  }

  Future<void> _openClientPicker(List<Map<String, dynamic>> clients) async {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    final search = TextEditingController();
    List<Map<String, dynamic>> filtered = clients;

    final picked = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) {
        return SelectionArea(
          child: StatefulBuilder(
            builder: (context, setLocal) {
              void applyFilter(String q) {
                final needle = q.trim().toLowerCase();
                setLocal(() {
                  if (needle.isEmpty) {
                    filtered = clients;
                  } else {
                    filtered = clients
                        .where((c) => _text(c['bedrijfsnaam']).toLowerCase().contains(needle))
                        .toList(growable: false);
                  }
                });
              }

              return Dialog(
                insetPadding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Klant selecteren',
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(null),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: search,
                          onChanged: applyFilter,
                          decoration: InputDecoration(
                            labelText: 'Zoeken',
                            hintText: 'Typ een bedrijfsnaam…',
                            filled: true,
                            fillColor: softBg,
                            prefixIcon: const Icon(Icons.search_rounded),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: Container(
                            decoration: BoxDecoration(
                              color: softBg,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, i) => Divider(
                                height: 1,
                                color: cs.onSurface.withValues(alpha: 0.08),
                              ),
                              itemBuilder: (context, i) {
                                final c = filtered[i];
                                final name = _text(c['bedrijfsnaam']);
                                return ListTile(
                                  title: Text(
                                    name.isEmpty ? '—' : name,
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                                  ),
                                  onTap: () => Navigator.of(context).pop(c),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    search.dispose();
    if (!mounted) return;
    if (picked == null) return;
    setState(() => _selectedClient = picked);
  }

  Future<void> _createAndGo() async {
    if (_saving) return;

    final clientId = _text(_selectedClient?['id']);
    if (clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent.withValues(alpha: 0.92),
          content: Text(
            'Selecteer eerst een klant.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
        ),
      );
      return;
    }

    final userId = AppSupabase.client.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: const Text('Niet ingelogd.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final inserted = await AppSupabase.client
          .from('facturen')
          .insert({
            'bedrijf_id': clientId,
            'factuur_datum': DateFormat('yyyy-MM-dd').format(_invoiceDate),
            'klant_referentie': _poCtrl.text.trim(),
            'interne_notitie': _noteCtrl.text.trim(),
            'aangemaakt_door_id': userId,
          })
          .select('id')
          .single();

      final newId = _text(inserted['id']);
      if (newId.isEmpty) throw StateError('Kon id van nieuwe factuur niet lezen.');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.92),
          content: Text(
            'Factuurkaft aangemaakt.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
        ),
      );

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/admin/sales/invoices/detail'),
          builder: (_) => InvoiceDetailScreen(invoiceId: newId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon factuur niet aanmaken: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canView = up.hasPermission('manage_invoices') ||
        up.isGenerator ||
        up.role == UserRole.administrator ||
        up.role == UserRole.generator;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;
    final softBg = isDark ? const Color(0xFF0A0912) : const Color(0xFFF5F5F7);

    final dateFmt = DateFormat('dd-MM-yyyy');

    Widget labelRow(String title, String tooltip) {
      return Row(
        children: [
          Text(
            title,
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
          ),
          const SizedBox(width: 8),
          EnterpriseTooltip(message: tooltip),
        ],
      );
    }

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: softBg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
        );

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Nieuwe Verkoopfactuur',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
      ),
      body: SelectionArea(
        child: !canView
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: softBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                    ),
                    child: Text(
                      'U heeft geen rechten om verkoopfacturen aan te maken.',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              )
            : FutureBuilder<List<Map<String, dynamic>>>(
                future: _futureClients,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: softBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                        ),
                        child: Text('Kan klanten niet laden: ${snapshot.error}'),
                      ),
                    );
                  }

                final clients = snapshot.data ?? const <Map<String, dynamic>>[];
                final clientName = _text(_selectedClient?['bedrijfsnaam']);

                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  children: [
                    Text(
                      'Nieuwe Verkoopfactuur',
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Stap 1: Klant & Condities',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.70),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: tileBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          labelRow(
                            'Klant Selectie',
                            'De factuur neemt automatisch de adresgegevens en betalingstermijn van de geselecteerde klant over.',
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: _saving ? null : () => _openClientPicker(clients),
                            child: InputDecorator(
                              decoration: deco('Klant').copyWith(
                                suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
                              ),
                              child: Text(
                                clientName.isEmpty ? 'Selecteer een klant…' : clientName,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  color: clientName.isEmpty
                                      ? cs.onSurface.withValues(alpha: 0.55)
                                      : cs.onSurface,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Factuurdatum',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: _saving ? null : _pickDate,
                            child: InputDecorator(
                              decoration: deco('Factuurdatum').copyWith(
                                suffixIcon: const Icon(Icons.calendar_today_rounded),
                              ),
                              child: Text(
                                dateFmt.format(_invoiceDate),
                                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          labelRow(
                            'Klantreferentie / PO-Nummer',
                            'Inkoopnummer of referentie van de klant. Verplicht bij sommige grote opdrachtgevers.',
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _poCtrl,
                            decoration: deco('Referentie (optioneel)'),
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 14),
                          labelRow(
                            'Interne Notitie',
                            'Optioneel. Niet zichtbaar op de uiteindelijke PDF.',
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _noteCtrl,
                            maxLines: 3,
                            decoration: deco('Interne notitie (optioneel)'),
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _createAndGo,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.arrow_forward_rounded),
                        label: Text(
                          'Aanmaken & Door naar Regels ➔',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
                },
              ),
      ),
    );
  }
}

