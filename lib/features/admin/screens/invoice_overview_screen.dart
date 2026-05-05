import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_drawer.dart';
import '../../../shared/layouts/main_layout.dart';
import 'factuur_editor_screen.dart';
import 'invoice_detail_screen.dart';
import 'relation_detail_screen.dart';

class InvoiceOverviewScreen extends StatefulWidget {
  const InvoiceOverviewScreen({super.key});

  @override
  State<InvoiceOverviewScreen> createState() => _InvoiceOverviewScreenState();
}

class _InvoiceOverviewScreenState extends State<InvoiceOverviewScreen> {
  bool _isLoading = false;
  List<dynamic> _invoices = const [];

  String _searchKlant = '';
  String _searchOrdernummer = '';
  String _searchArtikel = '';

  bool _showFactuur = true;
  bool _showCreditnota = true;

  List<String> _selectedStatuses = const ['concept', 'definitief', 'verzonden'];

  DateTime? _startDate;
  DateTime? _endDate;

  final _klantCtrl = TextEditingController();
  final _orderCtrl = TextEditingController();
  final _artikelCtrl = TextEditingController();

  bool _showFilters = true;

  // Live suggestions (kept in state for async-backed Autocomplete)
  List<Map<String, dynamic>> _klantOptions = const [];
  List<Map<String, dynamic>> _artikelOptions = const [];
  int _klantReq = 0;
  int _artikelReq = 0;

  @override
  void initState() {
    super.initState();
    _fetchData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _showFilters = MediaQuery.of(context).size.width > 800;
      });
    });
  }

  @override
  void dispose() {
    _klantCtrl.dispose();
    _orderCtrl.dispose();
    _artikelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (!mounted || picked == null) return;
    setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (!mounted || picked == null) return;
    setState(() => _endDate = picked);
  }

  Future<void> _fetchData() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      var query = Supabase.instance.client.from('app_facturen_overzicht').select();

      if (_searchKlant.isNotEmpty) {
        query = query.ilike('klantnaam', '%$_searchKlant%');
      }
      if (_searchOrdernummer.isNotEmpty) {
        query = query.eq('order_nummer', int.tryParse(_searchOrdernummer) ?? 0);
      }
      if (_searchArtikel.isNotEmpty) {
        query = query.ilike('artikelen_zoektekst', '%$_searchArtikel%');
      }

      // Type Filter
      final types = <String>[];
      if (_showFactuur) types.add('factuur');
      if (_showCreditnota) types.add('creditnota');
      if (types.isNotEmpty) query = query.inFilter('type', types);

      // Status Filter
      if (_selectedStatuses.isNotEmpty) {
        query = query.inFilter('status', _selectedStatuses);
      }

      // Date Filter
      if (_startDate != null) query = query.gte('orderdatum', _startDate!.toIso8601String());
      if (_endDate != null) query = query.lte('orderdatum', _endDate!.toIso8601String());

      // ORDER BY ORDERNUMMER ASCENDING
      final response = await query.order('order_nummer', ascending: true);

      if (!mounted) return;
      setState(() {
        _invoices = response as List<dynamic>;
      });
    } catch (e) {
      // ignore: avoid_print
      print('Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.92),
          content: Text('Kon facturen niet laden: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _deco(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchKlantOptions(String q) async {
    final query = q.trim();
    if (query.isEmpty) return const [];
    final response = await Supabase.instance.client
        .from('bedrijven')
        .select('id, bedrijfsnaam')
        .eq('is_klant', true)
        .ilike('bedrijfsnaam', '%$query%')
        .limit(10);
    return (response as List)
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .cast<Map<String, dynamic>>()
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchArtikelOptions(String q) async {
    final query = q.trim();
    if (query.isEmpty) return const [];
    final response = await Supabase.instance.client
        .from('artikelen')
        .select('id, naam')
        .ilike('naam', '%$query%')
        .limit(10);
    return (response as List)
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .cast<Map<String, dynamic>>()
        .toList();
  }

  Widget _premiumOptionsViewBuilder<T extends Object>(
    BuildContext context,
    AutocompleteOnSelected<T> onSelected,
    Iterable<T> options,
    String Function(T) displayString,
  ) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 8,
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320, maxWidth: 420),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final opt = options.elementAt(index);
              return InkWell(
                onTap: () => onSelected(opt),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    displayString(opt),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _dateChip({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    final df = DateFormat('dd-MM-yyyy');
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.date_range),
      label: Text(
        value == null ? label : '$label: ${df.format(value)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide(color: Colors.grey.shade300),
        foregroundColor: const Color(0xFF0F172A),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eur = NumberFormat.currency(locale: 'nl_NL', symbol: '€');
    final df = DateFormat('dd-MM-yyyy');
    final isMobile = MediaQuery.of(context).size.width < 800;

    return MainLayout(
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F5F7),
        drawer: const AppDrawer(),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Facturen Overzicht',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FactuurEditorScreen()),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Nieuwe Factuur'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        body: SelectionArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (isMobile)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => setState(() => _showFilters = !_showFilters),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        _showFilters ? 'Filters & Zoeken verbergen' : 'Filters & Zoeken tonen',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                if (isMobile) const SizedBox(height: 12),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 180),
                  crossFadeState: _showFilters ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                  secondChild: const SizedBox.shrink(),
                  firstChild: Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: isMobile ? 8 : 16,
                            runSpacing: isMobile ? 8 : 16,
                            children: [
                              SizedBox(
                                width: 280,
                                child: Autocomplete<Map<String, dynamic>>(
                                displayStringForOption: (o) =>
                                    (o['bedrijfsnaam'] ?? '').toString(),
                                optionsBuilder: (TextEditingValue t) {
                                  final q = t.text.trim().toLowerCase();
                                  if (q.isEmpty) {
                                    return const Iterable<Map<String, dynamic>>
                                        .empty();
                                  }
                                  return _klantOptions.where((o) {
                                    final name = (o['bedrijfsnaam'] ?? '')
                                        .toString()
                                        .toLowerCase();
                                    return name.contains(q);
                                  });
                                },
                                onSelected: (selection) {
                                  final name =
                                      (selection['bedrijfsnaam'] ?? '').toString();
                                  setState(() {
                                    _searchKlant = name;
                                    _klantCtrl.text = name;
                                  });
                                  _fetchData();
                                },
                                fieldViewBuilder: (context, controller, focusNode,
                                    onEditingComplete) {
                                  if (controller.text != _klantCtrl.text) {
                                    controller.value = _klantCtrl.value;
                                  }
                                  return TextField(
                                    controller: _klantCtrl,
                                    focusNode: focusNode,
                                    onEditingComplete: onEditingComplete,
                                    decoration: _deco(
                                      'Klantnaam',
                                      icon: Icons.search,
                                    ),
                                    onChanged: (v) async {
                                      _searchKlant = v.trim();
                                      final req = ++_klantReq;
                                      try {
                                        final opts = await _fetchKlantOptions(v);
                                        if (!mounted || req != _klantReq) return;
                                        setState(() => _klantOptions = opts);
                                      } catch (_) {
                                        if (!mounted || req != _klantReq) return;
                                        setState(
                                          () => _klantOptions = const [],
                                        );
                                      }
                                    },
                                  );
                                },
                                optionsViewBuilder: (context, onSelected, options) {
                                  return _premiumOptionsViewBuilder<
                                      Map<String, dynamic>>(
                                    context,
                                    onSelected,
                                    options,
                                    (o) => (o['bedrijfsnaam'] ?? '').toString(),
                                  );
                                },
                              ),
                            ),
                            SizedBox(
                              width: 200,
                              child: TextField(
                                controller: _orderCtrl,
                                keyboardType: TextInputType.number,
                                decoration: _deco('Ordernummer'),
                                onChanged: (v) =>
                                    _searchOrdernummer = v.trim(),
                              ),
                            ),
                            SizedBox(
                              width: 280,
                              child: Autocomplete<Map<String, dynamic>>(
                                displayStringForOption: (o) =>
                                    (o['naam'] ?? '').toString(),
                                optionsBuilder: (TextEditingValue t) {
                                  final q = t.text.trim().toLowerCase();
                                  if (q.isEmpty) {
                                    return const Iterable<Map<String, dynamic>>
                                        .empty();
                                  }
                                  return _artikelOptions.where((o) {
                                    final name = (o['naam'] ?? '')
                                        .toString()
                                        .toLowerCase();
                                    return name.contains(q);
                                  });
                                },
                                onSelected: (selection) {
                                  final name =
                                      (selection['naam'] ?? '').toString();
                                  setState(() {
                                    _searchArtikel = name;
                                    _artikelCtrl.text = name;
                                  });
                                  _fetchData();
                                },
                                fieldViewBuilder: (context, controller, focusNode,
                                    onEditingComplete) {
                                  if (controller.text != _artikelCtrl.text) {
                                    controller.value = _artikelCtrl.value;
                                  }
                                  return TextField(
                                    controller: _artikelCtrl,
                                    focusNode: focusNode,
                                    onEditingComplete: onEditingComplete,
                                    decoration:
                                        _deco('Artikel', icon: Icons.search),
                                    onChanged: (v) async {
                                      _searchArtikel = v.trim();
                                      final req = ++_artikelReq;
                                      try {
                                        final opts = await _fetchArtikelOptions(v);
                                        if (!mounted || req != _artikelReq) return;
                                        setState(() => _artikelOptions = opts);
                                      } catch (_) {
                                        if (!mounted || req != _artikelReq) return;
                                        setState(
                                          () => _artikelOptions = const [],
                                        );
                                      }
                                    },
                                  );
                                },
                                optionsViewBuilder: (context, onSelected, options) {
                                  return _premiumOptionsViewBuilder<
                                      Map<String, dynamic>>(
                                    context,
                                    onSelected,
                                    options,
                                    (o) => (o['naam'] ?? '').toString(),
                                  );
                                },
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F5F7),
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: _showFactuur,
                                    onChanged: (v) => setState(
                                      () => _showFactuur = v ?? false,
                                    ),
                                  ),
                                  const Text(
                                    'Factuur',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 10),
                                  Checkbox(
                                    value: _showCreditnota,
                                    onChanged: (v) => setState(
                                      () => _showCreditnota = v ?? false,
                                    ),
                                  ),
                                  const Text(
                                    'Creditnota',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                            _dateChip(
                              label: 'Start',
                              value: _startDate,
                              onTap: _pickStartDate,
                            ),
                            _dateChip(
                              label: 'Eind',
                              value: _endDate,
                              onTap: _pickEndDate,
                            ),
                          ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: isMobile ? 8 : 10,
                            runSpacing: isMobile ? 8 : 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                'Status:',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              ...[
                                'concept',
                                'definitief',
                                'verzonden',
                                'betaald',
                                'vervallen',
                              ].map((s) {
                                final selected = _selectedStatuses.contains(s);
                                return FilterChip(
                                  label: Text(s),
                                  selected: selected,
                                  onSelected: (v) {
                                    setState(() {
                                      final next = [..._selectedStatuses];
                                      if (v) {
                                        if (!next.contains(s)) next.add(s);
                                      } else {
                                        next.remove(s);
                                      }
                                      _selectedStatuses = next;
                                    });
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  selectedColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.14),
                                  checkmarkColor:
                                      Theme.of(context).colorScheme.primary,
                                  backgroundColor: const Color(0xFFF5F5F7),
                                  side: BorderSide(color: Colors.grey.shade200),
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : const Color(0xFF0F172A),
                                  ),
                                );
                              }),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: _isLoading ? null : _fetchData,
                                icon: const Icon(Icons.search),
                                label: Text(isMobile ? 'Zoek' : 'Zoeken / Toepassen'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  textStyle:
                                      const TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _invoices.isEmpty
                          ? const Center(
                              child: Text('Geen facturen gevonden.'),
                            )
                          : ListView.builder(
                              itemCount: _invoices.length,
                              itemBuilder: (context, index) {
                                final inv = (_invoices[index] as Map).map(
                                  (k, v) => MapEntry(k.toString(), v),
                                );
                                final id = (inv['id'] ?? '').toString();
                                final bedrijfId =
                                    (inv['bedrijf_id'] ?? '').toString();
                                final klantnaam =
                                    (inv['klantnaam'] ?? '').toString();
                                final orderNr =
                                    (inv['order_nummer'] ?? '').toString();
                                final type = (inv['type'] ?? '').toString();
                                final omschrijving =
                                    (inv['omschrijving'] ?? '').toString();
                                final status =
                                    (inv['status'] ?? '').toString();
                                final orderdatumRaw = inv['orderdatum'];
                                final orderDatum = orderdatumRaw == null
                                    ? null
                                    : DateTime.tryParse(orderdatumRaw.toString());
                                final ex = (inv['bedrag_ex_btw'] ??
                                    inv['totaal_ex_btw'] ??
                                    0);
                                final inc = (inv['bedrag_inc_btw'] ??
                                    inv['totaal_inc_btw'] ??
                                    0);

                                final exVal = ex is num
                                    ? ex.toDouble()
                                    : double.tryParse(ex.toString()) ?? 0.0;
                                final incVal = inc is num
                                    ? inc.toDouble()
                                    : double.tryParse(inc.toString()) ?? 0.0;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: id.isEmpty
                                          ? null
                                          : () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      InvoiceDetailScreen(
                                                    invoiceId: id,
                                                  ),
                                                ),
                                              );
                                            },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withValues(alpha: 0.10),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: Text(
                                                orderNr.isEmpty
                                                    ? '—'
                                                    : '#$orderNr',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        type.toUpperCase(),
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: Colors.black
                                                              .withValues(
                                                            alpha: 0.70,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: const Color(
                                                            0xFFF5F5F7,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            999,
                                                          ),
                                                          border: Border.all(
                                                            color: Colors
                                                                .grey.shade200,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          status,
                                                          style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    omschrijving.isEmpty
                                                        ? '—'
                                                        : omschrijving,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: TextButton(
                                                      onPressed: bedrijfId.isEmpty
                                                          ? null
                                                          : () {
                                                              Navigator.push(
                                                                context,
                                                                MaterialPageRoute(
                                                                  builder: (_) =>
                                                                      RelationDetailScreen(
                                                                    bedrijfId:
                                                                        bedrijfId,
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                      style: TextButton.styleFrom(
                                                        padding: EdgeInsets.zero,
                                                        minimumSize:
                                                            const Size(20, 20),
                                                        tapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                        foregroundColor:
                                                            const Color(
                                                          0xFF0052CC,
                                                        ),
                                                        textStyle: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w900,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        klantnaam.isEmpty
                                                            ? '—'
                                                            : klantnaam,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 14,
                                                    runSpacing: 8,
                                                    children: [
                                                      _kv('Valuta', 'EUR'),
                                                      _kv(
                                                        'Ex. BTW',
                                                        eur.format(exVal),
                                                      ),
                                                      _kv(
                                                        'Incl. BTW',
                                                        eur.format(incVal),
                                                      ),
                                                      _kv(
                                                        'Orderdatum',
                                                        orderDatum == null
                                                            ? '—'
                                                            : df.format(orderDatum),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
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
  }

  Widget _kv(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$k: ',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.black.withValues(alpha: 0.55),
          ),
        ),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

