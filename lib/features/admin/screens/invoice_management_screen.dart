import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import 'factuur_editor_screen.dart';
import 'invoice_bulk_run_screen.dart';

class InvoiceManagementScreen extends StatefulWidget {
  const InvoiceManagementScreen({super.key});

  @override
  State<InvoiceManagementScreen> createState() => _InvoiceManagementScreenState();
}

class _InvoiceManagementScreenState extends State<InvoiceManagementScreen> {
  Future<_InvoiceData>? _future;
  _InvoiceView _view = _InvoiceView.concept;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_InvoiceData> _fetch() async {
    final conceptRes = await AppSupabase.client
        .from('facturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .eq('status', 'concept')
        .order('aangemaakt_op', ascending: false);

    final openRes = await AppSupabase.client
        .from('facturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .inFilter('status', const [
          'definitief',
          'verzonden',
          'herinnering_1',
          'herinnering_2',
        ])
        .gt('openstaand_saldo', 0)
        .order('verval_datum', ascending: true);

    final historyRes = await AppSupabase.client
        .from('facturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .inFilter('status', const ['betaald', 'gecrediteerd', 'vervallen'])
        .order('aangemaakt_op', ascending: false);

    return _InvoiceData(
      concepts: (conceptRes as List).cast<Map<String, dynamic>>(),
      open: (openRes as List).cast<Map<String, dynamic>>(),
      history: (historyRes as List).cast<Map<String, dynamic>>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canManage = up.hasPermission('manage_invoices');

    if (!canManage) {
      return const Scaffold(
        drawer: AppDrawer(),
        body: SelectionArea(
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: _NoAccessEmptyState(
                message: 'U heeft geen rechten om verkoopfacturen te beheren.',
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Facturen Overzicht'),
        actions: [
          IconButton(
            tooltip: 'Nieuw',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: '/admin/sales/invoices/new'),
                  builder: (_) => const FactuurEditorScreen(),
                ),
              );
            },
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Bulk Facturatie Run',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: '/admin/sales/invoices/bulk-run'),
                  builder: (_) => const InvoiceBulkRunScreen(),
                ),
              );
            },
            icon: const Icon(Icons.auto_awesome),
          ),
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: () => setState(() => _future = _fetch()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SelectionArea(
        child: FutureBuilder<_InvoiceData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Fout: ${snapshot.error}'),
              );
            }

            final data = snapshot.data!;
            final items = switch (_view) {
              _InvoiceView.concept => data.concepts,
              _InvoiceView.open => data.open,
              _InvoiceView.history => data.history,
            };

            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<_InvoiceView>(
                      segments: const [
                        ButtonSegment(value: _InvoiceView.concept, label: Text('Concept')),
                        ButtonSegment(value: _InvoiceView.open, label: Text('Openstaand')),
                        ButtonSegment(value: _InvoiceView.history, label: Text('Historie')),
                      ],
                      selected: {_view},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _view = s.first),
                    ),
                  ),
                ),
                Expanded(
                  child: _InvoiceTable(
                    items: items,
                    emptyMessage: switch (_view) {
                      _InvoiceView.concept => 'Geen conceptfacturen.',
                      _InvoiceView.open => 'Geen openstaande facturen.',
                      _InvoiceView.history => 'Geen historische facturen.',
                    },
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

enum _InvoiceView { concept, open, history }

class _InvoiceData {
  const _InvoiceData({
    required this.concepts,
    required this.open,
    required this.history,
  });

  final List<Map<String, dynamic>> concepts;
  final List<Map<String, dynamic>> open;
  final List<Map<String, dynamic>> history;
}

class _InvoiceTable extends StatelessWidget {
  const _InvoiceTable({
    required this.items,
    required this.emptyMessage,
  });

  final List<Map<String, dynamic>> items;
  final String emptyMessage;

  String _text(dynamic v) => (v ?? '').toString().trim();

  DateTime? _asDate(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  NumberFormat _eur() => NumberFormat.currency(locale: 'nl_NL', symbol: '€');

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(emptyMessage, style: const TextStyle(fontSize: 13)));
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 44,
              horizontalMargin: 12,
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('Debiteur', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                DataColumn(label: Text('Nummer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                DataColumn(label: Text('Datum', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                DataColumn(label: Text('Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                DataColumn(label: Text('Totaal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                DataColumn(label: Text('Actie', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
              ],
              rows: items.map((inv) {
                final id = _text(inv['id']);
                final num = _text(inv['factuur_nummer']);
                final status = _text(inv['status']);
                final bedrijf = inv['bedrijven'];
                final name = bedrijf is Map ? _text(bedrijf['bedrijfsnaam']) : '';
                final date = _asDate(inv['factuur_datum'] ?? inv['datum']);
                final total = _asDouble(inv['totaal_inc_btw']);

                return DataRow(
                  cells: [
                    DataCell(Text(name.isEmpty ? '—' : name, style: const TextStyle(fontSize: 13))),
                    DataCell(Text(num.isEmpty ? id : num, style: const TextStyle(fontSize: 13))),
                    DataCell(
                      Text(
                        date == null ? '—' : DateFormat('dd-MM-yyyy').format(date),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    DataCell(Text(status.isEmpty ? '—' : status, style: const TextStyle(fontSize: 13))),
                    DataCell(Text(_eur().format(total), style: const TextStyle(fontSize: 13))),
                    DataCell(
                      OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              settings: const RouteSettings(name: '/admin/sales/invoices/edit'),
                              builder: (_) => FactuurEditorScreen(invoiceId: id),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: const Text('Open', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                );
              }).toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoAccessEmptyState extends StatelessWidget {
  const _NoAccessEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message));
  }
}

/*
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import 'factuur_editor_screen.dart';
import 'invoice_bulk_run_screen.dart';

class InvoiceManagementScreen extends StatefulWidget {
  const InvoiceManagementScreen({super.key});

  @override
  State<InvoiceManagementScreen> createState() => _InvoiceManagementScreenState();
}

class _InvoiceManagementScreenState extends State<InvoiceManagementScreen> {
  Future<_InvoiceData>? _future;
  _InvoiceView _view = _InvoiceView.concept;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_InvoiceData> _fetch() async {
    final conceptRes = await AppSupabase.client
        .from('facturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .eq('status', 'concept')
        .order('aangemaakt_op', ascending: false);

    final openRes = await AppSupabase.client
        .from('facturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .inFilter('status', const [
          'definitief',
          'verzonden',
          'herinnering_1',
          'herinnering_2',
        ])
        .gt('openstaand_saldo', 0)
        .order('verval_datum', ascending: true);

    final historyRes = await AppSupabase.client
        .from('facturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .inFilter('status', const ['betaald', 'gecrediteerd', 'vervallen'])
        .order('aangemaakt_op', ascending: false);

    return _InvoiceData(
      concepts: (conceptRes as List).cast<Map<String, dynamic>>(),
      open: (openRes as List).cast<Map<String, dynamic>>(),
      history: (historyRes as List).cast<Map<String, dynamic>>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canManage = up.hasPermission('manage_invoices');

    if (!canManage) {
      return const Scaffold(
        drawer: AppDrawer(),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: _NoAccessEmptyState(
              message: 'U heeft geen rechten om verkoopfacturen te beheren.',
            ),
          ),
        ),
      );
    }

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Facturen Overzicht'),
        actions: [
          IconButton(
            tooltip: 'Nieuw',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: '/admin/sales/invoices/new'),
                  builder: (_) => const FactuurEditorScreen(),
                ),
              );
            },
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Bulk Facturatie Run',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: '/admin/sales/invoices/bulk-run'),
                  builder: (_) => const InvoiceBulkRunScreen(),
                ),
              );
            },
            icon: const Icon(Icons.auto_awesome),
          ),
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: () => setState(() => _future = _fetch()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_InvoiceData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Fout: ${snapshot.error}'),
            );
          }

          final data = snapshot.data!;
          final items = switch (_view) {
            _InvoiceView.concept => data.concepts,
            _InvoiceView.open => data.open,
            _InvoiceView.history => data.history,
          };

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<_InvoiceView>(
                    segments: const [
                      ButtonSegment(value: _InvoiceView.concept, label: Text('Concept')),
                      ButtonSegment(value: _InvoiceView.open, label: Text('Openstaand')),
                      ButtonSegment(value: _InvoiceView.history, label: Text('Historie')),
                    ],
                    selected: {_view},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _view = s.first),
                  ),
                ),
              ),
              Expanded(
                child: _InvoiceTable(
                  items: items,
                  emptyMessage: switch (_view) {
                    _InvoiceView.concept => 'Geen conceptfacturen.',
                    _InvoiceView.open => 'Geen openstaande facturen.',
                    _InvoiceView.history => 'Geen historische facturen.',
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _InvoiceView { concept, open, history }

class _InvoiceData {
  const _InvoiceData({
    required this.concepts,
    required this.open,
    required this.history,
  });

  final List<Map<String, dynamic>> concepts;
  final List<Map<String, dynamic>> open;
  final List<Map<String, dynamic>> history;
}

class _InvoiceTable extends StatelessWidget {
  const _InvoiceTable({
    required this.items,
    required this.emptyMessage,
  });

  final List<Map<String, dynamic>> items;
  final String emptyMessage;

  String _text(dynamic v) => (v ?? '').toString().trim();

  DateTime? _asDate(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll(',', '.');
    return double.tryParse(s ?? '') ?? 0;
  }

  NumberFormat _eur() => NumberFormat.currency(locale: 'nl_NL', symbol: '€');

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(emptyMessage, style: const TextStyle(fontSize: 13)));
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 44,
              horizontalMargin: 12,
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('Debiteur', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                DataColumn(label: Text('Nummer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                DataColumn(label: Text('Datum', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                DataColumn(label: Text('Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                DataColumn(label: Text('Totaal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                DataColumn(label: Text('Actie', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
              ],
              rows: items.map((inv) {
                final id = _text(inv['id']);
                final num = _text(inv['factuur_nummer']);
                final status = _text(inv['status']);
                final bedrijf = inv['bedrijven'];
                final name = bedrijf is Map ? _text(bedrijf['bedrijfsnaam']) : '';
                final date = _asDate(inv['factuur_datum'] ?? inv['datum']);
                final total = _asDouble(inv['totaal_inc_btw']);

                return DataRow(
                  cells: [
                    DataCell(Text(name.isEmpty ? '—' : name, style: const TextStyle(fontSize: 13))),
                    DataCell(Text(num.isEmpty ? id : num, style: const TextStyle(fontSize: 13))),
                    DataCell(
                      Text(
                        date == null ? '—' : DateFormat('dd-MM-yyyy').format(date),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    DataCell(Text(status.isEmpty ? '—' : status, style: const TextStyle(fontSize: 13))),
                    DataCell(Text(_eur().format(total), style: const TextStyle(fontSize: 13))),
                    DataCell(
                      OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              settings: const RouteSettings(name: '/admin/sales/invoices/edit'),
                              builder: (_) => FactuurEditorScreen(invoiceId: id),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: const Text('Open', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                );
              }).toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoAccessEmptyState extends StatelessWidget {
  const _NoAccessEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message));
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/app_drawer.dart';
import '../../../core/supabase_client.dart';
import '../../../providers/user_provider.dart';
import 'invoice_settings_screen.dart';
import 'invoice_detail_screen.dart';

class InvoiceManagementScreen extends StatefulWidget {
  const InvoiceManagementScreen({super.key});

  @override
  State<InvoiceManagementScreen> createState() => _InvoiceManagementScreenState();
}

class _InvoiceManagementScreenState extends State<InvoiceManagementScreen> {
  Future<_InvoiceData>? _future;

  Future<void> _startFacturatieRun() async {
    final yearMonth = DateFormat('yyyy-MM').format(DateTime.now());

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        bool running = false;

        final cs = Theme.of(context).colorScheme;
        return SelectionArea(
          child: StatefulBuilder(
            builder: (context, setState) {
            // Keep local "running" state in sync with rebuilds.
            void setRunning(bool v) {
              setState(() {
                running = v;
              });
            }

            Future<void> runWithState() async {
              if (running) return;
              setRunning(true);
              try {
                final res = await AppSupabase.client.rpc(
                  'genereer_maandelijkse_facturatie_run',
                  params: {'p_jaar_maand': yearMonth},
                );
                final msg = (res ?? '').toString();
                if (context.mounted) Navigator.of(context).pop(true);
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green.withValues(alpha: 0.90),
                    content: Text(msg),
                  ),
                );
                if (mounted) {
                  this.setState(() {
                    _future = _fetch();
                  });
                }
              } catch (e) {
                setRunning(false);
                if (!context.mounted) return;
                Navigator.of(context).pop(false);
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
                    content: Text('Fout bij genereren: $e'),
                  ),
                );
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                'Facturatie Run Starten?',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              content: Text(
                'Wilt u alle conceptfacturen genereren voor de actieve vaste contracten van deze maand?',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface.withValues(alpha: 0.78),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: running ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Annuleren'),
                ),
                FilledButton.icon(
                  onPressed: running ? null : runWithState,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    textStyle: GoogleFonts.inter(fontWeight: FontWeight.w900),
                  ),
                  icon: running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(running ? 'Bezig…' : 'Starten'),
                ),
              ],
            );
            },
          ),
        );
      },
    );

    // Dialog already handled messaging + refresh; this keeps the future chain explicit.
    // ignore: unused_local_variable
    final _ = ok;
  }

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_InvoiceData> _fetch() async {
    final conceptRes = await AppSupabase.client
        .from('facturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .eq('status', 'concept')
        .order('aangemaakt_op', ascending: false);

    final openRes = await AppSupabase.client
        .from('facturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .inFilter('status', const [
          'definitief',
          'verzonden',
          'herinnering_1',
          'herinnering_2',
        ])
        .gt('openstaand_saldo', 0)
        .order('verval_datum', ascending: true);

    final historyRes = await AppSupabase.client
        .from('facturen')
        .select('*, bedrijven(bedrijfsnaam)')
        .inFilter('status', const ['betaald', 'gecrediteerd', 'vervallen'])
        .order('aangemaakt_op', ascending: false);

    return _InvoiceData(
      concepts: (conceptRes as List).cast<Map<String, dynamic>>(),
      open: (openRes as List).cast<Map<String, dynamic>>(),
      history: (historyRes as List).cast<Map<String, dynamic>>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canManage = up.hasPermission('manage_invoices');

    if (!canManage) {
      return const Scaffold(
        drawer: AppDrawer(),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: _NoAccessEmptyState(
              message: 'U heeft geen rechten om verkoopfacturen te beheren.',
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        drawer: const AppDrawer(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _startFacturatieRun,
          icon: const Icon(Icons.auto_awesome),
          label: Text(
            'Facturatie Run Starten',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900),
          ),
        ),
        appBar: AppBar(
          title: Text(
            'Verkoopfacturen',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Instellingen',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InvoiceSettingsScreen()),
                );
              },
              icon: const Icon(Icons.tune_rounded),
            ),
            IconButton(
              tooltip: 'Vernieuwen',
              onPressed: () {
                setState(() {
                  _future = _fetch();
                });
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 10, 24, 12),
              child: _InvoiceTabs(),
            ),
            Expanded(
              child: FutureBuilder<_InvoiceData>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: _ErrorState(
                        title: 'Kan facturen niet laden',
                        message: snapshot.error.toString(),
                        onRetry: null,
                      ),
                    );
                  }

                  final data = snapshot.data!;
                  return TabBarView(
                    children: [
                      _InvoiceList(rows: data.concepts, mode: _InvoiceListMode.concept),
                      _InvoiceList(rows: data.open, mode: _InvoiceListMode.open),
                      _InvoiceList(rows: data.history, mode: _InvoiceListMode.history),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceData {
  const _InvoiceData({
    required this.concepts,
    required this.open,
    required this.history,
  });

  final List<Map<String, dynamic>> concepts;
  final List<Map<String, dynamic>> open;
  final List<Map<String, dynamic>> history;
}

class _InvoiceTabs extends StatelessWidget {
  const _InvoiceTabs();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? cs.surface.withValues(alpha: 0.65) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: TabBar(
        splashBorderRadius: BorderRadius.circular(50),
        indicator: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(24),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        tabs: const [
          Tab(text: 'Concepten'),
          Tab(text: 'Openstaand'),
          Tab(text: 'Historie'),
        ],
      ),
    );
  }
}

enum _InvoiceListMode { concept, open, history }

class _InvoiceList extends StatelessWidget {
  const _InvoiceList({required this.rows, required this.mode});

  final List<Map<String, dynamic>> rows;
  final _InvoiceListMode mode;

  NumberFormat _eur() => NumberFormat.currency(
        locale: 'nl_NL',
        symbol: '€',
        decimalDigits: 2,
      );

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? cs.surface.withValues(alpha: 0.92) : Colors.white;

    if (rows.isEmpty) {
      final label = switch (mode) {
        _InvoiceListMode.concept => 'Geen conceptfacturen gevonden.',
        _InvoiceListMode.open => 'Geen openstaande facturen gevonden.',
        _InvoiceListMode.history => 'Geen facturen in de historie gevonden.',
      };
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? cs.surface.withValues(alpha: 0.70) : const Color(0xFFF5F5F7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.inbox_outlined, color: cs.onSurface.withValues(alpha: 0.65)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.80),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final row = rows[i];
        final invoiceId = _text(row['id']);
        final bedrijf = row['bedrijven'];
        final bedrijfsnaam = bedrijf is Map ? _text(bedrijf['bedrijfsnaam']) : '';

        final factuurnr = _text(row['factuur_nummer']);
        final totaal = _asDouble(row['totaal_inc_btw']);
        final verval = _asDate(row['verval_datum']);
        final openSaldo = _asDouble(row['openstaand_saldo']);
        final status = _text(row['status']).toLowerCase();
        final isCredited = (mode == _InvoiceListMode.history) && status == 'gecrediteerd';

        final now = DateTime.now();
        final overdue = (mode == _InvoiceListMode.open) &&
            (verval != null) &&
            verval.isBefore(DateTime(now.year, now.month, now.day)) &&
            openSaldo > 0;

        final badge = switch (mode) {
          _InvoiceListMode.concept => _PillBadgeData(
              text: 'Concept',
              bg: cs.onSurface.withValues(alpha: 0.08),
              fg: cs.onSurface.withValues(alpha: 0.80),
            ),
          _InvoiceListMode.open => _PillBadgeData(
              text: verval == null
                  ? 'Openstaand'
                  : 'Vervalt: ${DateFormat('dd-MM').format(verval)}',
              bg: overdue
                  ? Colors.red.withValues(alpha: isDark ? 0.20 : 0.14)
                  : Colors.orange.withValues(alpha: isDark ? 0.18 : 0.14),
              fg: overdue ? const Color(0xFFB00020) : const Color(0xFF8A4B12),
            ),
          _InvoiceListMode.history => _PillBadgeData(
              text: _text(row['status']).isEmpty ? 'Historie' : _text(row['status']),
              bg: cs.onSurface.withValues(alpha: 0.08),
              fg: cs.onSurface.withValues(alpha: 0.80),
            ),
        };

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: invoiceId.isEmpty
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => InvoiceDetailScreen(invoiceId: invoiceId),
                      ),
                    );
                  },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isCredited ? tileBg.withValues(alpha: 0.60) : tileBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
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
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
                    ),
                    child: Icon(Icons.receipt_long, color: cs.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bedrijfsnaam.isEmpty ? 'Onbekende Klant' : bedrijfsnaam,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          factuurnr.isEmpty ? 'Concept Factuur' : factuurnr,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface.withValues(alpha: 0.70),
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
                        _eur().format(totaal),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCredited) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.redAccent.withValues(alpha: 0.30),
                                ),
                              ),
                              child: Text(
                                'GECREDITEERD',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                  color: const Color(0xFFB00020),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          _PillBadge(data: badge),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PillBadgeData {
  const _PillBadgeData({
    required this.text,
    required this.bg,
    required this.fg,
  });

  final String text;
  final Color bg;
  final Color fg;
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.data});

  final _PillBadgeData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: data.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        data.text,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
          color: data.fg,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? cs.surface.withValues(alpha: 0.70) : const Color(0xFFF5F5F7);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: cs.onSurface.withValues(alpha: 0.65)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.80),
              ),
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
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? cs.surface.withValues(alpha: 0.70) : const Color(0xFFF5F5F7);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: -0.4,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w500,
              color: cs.onSurface.withValues(alpha: 0.75),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Opnieuw laden'),
            ),
          ],
        ],
      ),
    );
  }
}

*/

