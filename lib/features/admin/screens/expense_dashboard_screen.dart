import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import '../services/expense_upload_service.dart';
import 'expense_validation_screen.dart';

class ExpenseDashboardScreen extends StatefulWidget {
  const ExpenseDashboardScreen({super.key});

  @override
  State<ExpenseDashboardScreen> createState() => _ExpenseDashboardScreenState();
}

class _ExpenseDashboardScreenState extends State<ExpenseDashboardScreen> {
  Future<_ExpenseDashboardData>? _future;
  bool _uploadBusy = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_ExpenseDashboardData> _fetch() async {
    final invoicesRes = await AppSupabase.client
        .from('inkoopfacturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .order('id', ascending: false);

    final invoices = (invoicesRes as List).cast<Map<String, dynamic>>();

    double teBetalen = 0;
    int wachtOpAutorisatie = 0;

    for (final r in invoices) {
      final status = (r['status'] ?? '').toString().trim().toLowerCase();
      if (status == 'wacht_op_autorisatie') wachtOpAutorisatie++;
      final openstaand = _asDouble(r['openstaand_saldo'] ?? r['totaal_inc_btw']);
      if (openstaand > 0 && status != 'betaald') teBetalen += openstaand;
    }

    return _ExpenseDashboardData(
      invoices: invoices,
      teBetalen: teBetalen,
      wachtOpAutorisatie: wachtOpAutorisatie,
    );
  }

  void _refresh() {
    setState(() {
      _future = _fetch();
    });
  }

  Future<void> _uploadFlow() async {
    if (_uploadBusy) return;

    final action = await showModalBottomSheet<_UploadAction>(
      context: context,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SelectionArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Upload Bon / Factuur',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 14),
                _SheetAction(
                  icon: Icons.photo_camera_rounded,
                  title: 'Camera',
                  subtitle: 'Maak een foto van de bon',
                  onTap: () => Navigator.of(context).pop(_UploadAction.camera),
                  cs: cs,
                ),
                const SizedBox(height: 10),
                _SheetAction(
                  icon: Icons.photo_library_rounded,
                  title: 'Galerij',
                  subtitle: 'Kies een bestaande foto',
                  onTap: () => Navigator.of(context).pop(_UploadAction.gallery),
                  cs: cs,
                ),
                const SizedBox(height: 10),
                _SheetAction(
                  icon: Icons.upload_file_rounded,
                  title: 'Bestand (PDF/XML)',
                  subtitle: 'Upload UBL XML of een document',
                  onTap: () => Navigator.of(context).pop(_UploadAction.file),
                  cs: cs,
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuleren'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null || !mounted) return;

    setState(() => _uploadBusy = true);
    try {
      final service = ExpenseUploadService();
      final id = switch (action) {
        _UploadAction.camera =>
          await service.pickUploadAndCreateInvoice(source: ImageSource.camera),
        _UploadAction.gallery =>
          await service.pickUploadAndCreateInvoice(source: ImageSource.gallery),
        _UploadAction.file => await service.pickUploadAndCreateInvoiceFromFilePicker(),
      };
      if (!mounted) return;

      if (id == null || id.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
            content: const Text('Upload geannuleerd of mislukt.'),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.withValues(alpha: 0.90),
          content: const Text('Document wordt op de achtergrond geanalyseerd door de AI.'),
        ),
      );

      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ExpenseValidationScreen(invoiceId: id)),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon niet uploaden: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadBusy = false);
    }
  }

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  NumberFormat _eur() => NumberFormat.currency(
        locale: 'nl_NL',
        symbol: '€',
        decimalDigits: 2,
      );

  String _text(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final canView = userProvider.isGenerator || userProvider.hasPermission('manage_invoices');

    if (!canView) {
      return Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(
            'Inkoopboek',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
        ),
        body: const SelectionArea(
          child: _NoAccessEmptyState(
            message: 'U heeft geen rechten om het inkoopboek te beheren.',
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF0A0912) : Colors.white;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Inkoopboek',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadBusy ? null : _uploadFlow,
        icon: _uploadBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.add_rounded),
        label: Text(
          '+ Upload Bon / Factuur',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        ),
      ),
      body: SelectionArea(
        child: FutureBuilder<_ExpenseDashboardData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: _ErrorState(
                  title: 'Kan inkoopfacturen niet laden',
                  message: snapshot.error.toString(),
                  onRetry: _refresh,
                ),
              );
            }

            final data = snapshot.data!;

            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              children: [
                _KpiRow(
                  teBetalen: data.teBetalen,
                  wachtOpAutorisatie: data.wachtOpAutorisatie,
                ),
                const SizedBox(height: 18),
                Text(
                  'Inkoopfacturen',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 12),
                if (data.invoices.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: isDark ? tileBg : const Color(0xFFF5F5F7),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: cs.onSurface.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Nog geen inkoopfacturen gevonden.',
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
                    itemCount: data.invoices.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    separatorBuilder: (_, i) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final r = data.invoices[i];
                      final bedrijf =
                          (r['bedrijven'] as Map?) ?? const <String, dynamic>{};
                      final vendor = _text(bedrijf['bedrijfsnaam']);
                      final nr = _text(
                        r['factuur_nummer_leverancier'] ?? r['factuur_nummer'],
                      );
                      final dt = _text(r['factuur_datum'] ?? r['datum']);
                      final total = _asDouble(r['totaal_inc_btw']);
                      final status = _text(r['status']);

                      final badge =
                          _StatusTone.forStatus(status, isDark: isDark);

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () {
                            final id = _text(r['id']);
                            if (id.isEmpty) return;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ExpenseValidationScreen(invoiceId: id),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: tileBg,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: cs.onSurface.withValues(alpha: 0.06),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 20,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: cs.onSurface.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: cs.onSurface.withValues(alpha: 0.08),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.receipt_long_rounded,
                                    color: cs.primary,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        vendor.isEmpty
                                            ? 'Onbekende Leverancier'
                                            : vendor,
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        [
                                          if (nr.isNotEmpty) nr,
                                          if (dt.isNotEmpty) dt,
                                        ].join(' • '),
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface
                                              .withValues(alpha: 0.65),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _eur().format(total),
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: badge.bg,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(color: badge.border),
                                      ),
                                      child: Text(
                                        badge.label,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.1,
                                          color: badge.fg,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _UploadAction { camera, gallery, file }

class _ExpenseDashboardData {
  const _ExpenseDashboardData({
    required this.invoices,
    required this.teBetalen,
    required this.wachtOpAutorisatie,
  });

  final List<Map<String, dynamic>> invoices;
  final double teBetalen;
  final int wachtOpAutorisatie;
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.teBetalen,
    required this.wachtOpAutorisatie,
  });

  final double teBetalen;
  final int wachtOpAutorisatie;

  NumberFormat _eur() => NumberFormat.currency(
        locale: 'nl_NL',
        symbol: '€',
        decimalDigits: 2,
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = isDark ? const Color(0xFF0A0912) : Colors.white;

    final cards = [
      _StatCardData(
        title: 'Te betalen (Inkoop)',
        value: _eur().format(teBetalen),
        icon: Icons.payments_rounded,
        background: bg,
        accent: cs.primary,
      ),
      _StatCardData(
        title: 'Wacht op Autorisatie',
        value: wachtOpAutorisatie.toString(),
        icon: Icons.verified_user_rounded,
        background: bg,
        accent: Colors.deepOrange,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: cards.map((c) => SizedBox(width: 320, child: _StatCard(data: c))).toList(),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in cards) ...[
                _StatCard(data: c),
                const SizedBox(width: 14),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatCardData {
  const _StatCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.background,
    required this.accent,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color background;
  final Color accent;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});

  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 320,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: data.background,
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
                  data.title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface.withValues(alpha: 0.70),
                  ),
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: data.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                ),
                child: Icon(data.icon, color: data.accent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            data.value,
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTone {
  const _StatusTone({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
  });

  final String label;
  final Color bg;
  final Color fg;
  final Color border;

  static _StatusTone forStatus(String raw, {required bool isDark}) {
    final s = raw.trim().toLowerCase();
    if (s == 'wacht_op_autorisatie') {
      final bg = isDark ? const Color(0x22FFB300) : const Color(0xFFFFF4E5);
      return _StatusTone(
        label: 'Wacht op autorisatie',
        bg: bg,
        fg: const Color(0xFFB26A00),
        border: const Color(0x33FFB300),
      );
    }
    if (s == 'goedgekeurd') {
      final bg = isDark ? const Color(0x2219C37D) : const Color(0xFFE6F7EE);
      return _StatusTone(
        label: 'Goedgekeurd',
        bg: bg,
        fg: const Color(0xFF1E6B3A),
        border: const Color(0x3319C37D),
      );
    }
    if (s == 'in_behandeling') {
      final bg = isDark ? const Color(0x221A237E) : const Color(0xFFE9EEFF);
      return _StatusTone(
        label: 'In behandeling',
        bg: bg,
        fg: const Color(0xFF1A237E),
        border: const Color(0x331A237E),
      );
    }
    if (s == 'betaald') {
      final bg = isDark ? const Color(0x2219C37D) : const Color(0xFFE6F7EE);
      return _StatusTone(
        label: 'Betaald',
        bg: bg,
        fg: const Color(0xFF1E6B3A),
        border: const Color(0x3319C37D),
      );
    }
    final bg = isDark ? const Color(0x22FF6B35) : const Color(0xFFFFEEE8);
    return _StatusTone(
      label: raw.trim().isEmpty ? '—' : raw.trim(),
      bg: bg,
      fg: const Color(0xFFFF6B35),
      border: const Color(0x33FF6B35),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.cs,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurface.withValues(alpha: 0.55)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoAccessEmptyState extends StatelessWidget {
  const _NoAccessEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF0A0912)
                : const Color(0xFFF5F5F7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, color: cs.onSurface.withValues(alpha: 0.70)),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  message,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
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

