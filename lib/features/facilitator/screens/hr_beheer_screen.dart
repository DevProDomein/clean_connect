import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';

/// HR: uurloon, contracttype en voorschotten per operator (alleen Generator).
class HrBeheerScreen extends StatefulWidget {
  const HrBeheerScreen({super.key});

  @override
  State<HrBeheerScreen> createState() => _HrBeheerScreenState();
}

class _HrBeheerScreenState extends State<HrBeheerScreen> {
  DateTime geselecteerdeVoorschotMaand = DateTime.now();

  String get _voorschotMaandSleutel =>
      '${geselecteerdeVoorschotMaand.year}-'
      '${geselecteerdeVoorschotMaand.month.toString().padLeft(2, '0')}';

  static const String _operatorSelect =
      'id, voornaam, achternaam, standaard_uurloon, contract_type, '
      'contract_vaste_uren, contract_vast_salaris, contract_startdatum, '
      'contract_einddatum';

  List<Map<String, dynamic>> _operatoren = [];
  String? _selectedOperatorId;
  bool _isLoading = true;
  bool _loadingForm = false;
  bool _saving = false;
  String? _listError;

  final _uurloonCtl = TextEditingController();
  final _vasteUrenCtl = TextEditingController();
  final _vastSalarisCtl = TextEditingController();
  final _voorschotCtl = TextEditingController();

  String _selectedContractType = 'nul_uren';
  DateTime? _contractStart;
  DateTime? _contractEnd;
  bool _isOnbepaaldeTijd = false;
  double _geladenVoorschot = 0;

  @override
  void initState() {
    super.initState();
    _fetchOperatoren();
  }

  @override
  void dispose() {
    _uurloonCtl.dispose();
    _vasteUrenCtl.dispose();
    _vastSalarisCtl.dispose();
    _voorschotCtl.dispose();
    super.dispose();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  double? _parseMoney(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final d = double.tryParse(t.replaceAll(',', '.'));
    if (d != null) return d;
    return double.tryParse(t.replaceAll('.', '').replaceAll(',', '.'));
  }

  DateTime? _parseIsoDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);
    final s = raw.toString().trim();
    if (s.length >= 10) {
      try {
        final d = DateTime.parse(s.substring(0, 10));
        return DateTime(d.year, d.month, d.day);
      } catch (_) {}
    }
    return null;
  }

  String _operatorLabel(Map<String, dynamic> op) {
    final vn = _text(op[GebruikersTable.voornaam]);
    final an = _text(op[GebruikersTable.achternaam]);
    final full = '$vn $an'.trim();
    return full.isNotEmpty
        ? full
        : 'Operator ${_text(op[GebruikersTable.id])}';
  }

  List<Map<String, dynamic>> _parseOperatorRows(dynamic response) {
    return (response as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _queryOperatoren() async {
    final client = AppSupabase.client;

    try {
      final res = await client
          .from(GebruikersTable.name)
          .select(_operatorSelect)
          .eq(GebruikersTable.gebruikersrol, 'operator')
          .eq('is_actief', true)
          .order(GebruikersTable.achternaam, ascending: true);
      return _parseOperatorRows(res);
    } catch (e) {
      debugPrint('HR: laden met is_actief mislukt, fallback zonder filter: $e');
      final res = await client
          .from(GebruikersTable.name)
          .select(_operatorSelect)
          .eq(GebruikersTable.gebruikersrol, 'operator')
          .order(GebruikersTable.achternaam, ascending: true);
      return _parseOperatorRows(res);
    }
  }

  Future<void> _fetchOperatoren() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _listError = null;
    });

    try {
      final list = await _queryOperatoren();
      list.sort(
        (a, b) => _operatorLabel(a).toLowerCase().compareTo(
              _operatorLabel(b).toLowerCase(),
            ),
      );

      if (!mounted) return;

      final eersteId =
          list.isNotEmpty ? _text(list.first[GebruikersTable.id]) : null;

      setState(() {
        _operatoren = list;
        _isLoading = false;
        _selectedOperatorId =
            eersteId != null && eersteId.isNotEmpty ? eersteId : null;
      });

      if (_selectedOperatorId != null) {
        await _vulFormulierVoorOperator(_selectedOperatorId!);
      }
    } catch (e) {
      debugPrint('Fout bij laden operatoren: $e');
      if (!mounted) return;
      setState(() {
        _operatoren = [];
        _isLoading = false;
        _listError = e.toString();
        _selectedOperatorId = null;
      });
    }
  }

  void _resetFormControllers() {
    _uurloonCtl.clear();
    _vasteUrenCtl.clear();
    _vastSalarisCtl.clear();
    _voorschotCtl.clear();
    _contractStart = null;
    _contractEnd = null;
    _isOnbepaaldeTijd = false;
    _geladenVoorschot = 0;
    _selectedContractType = 'nul_uren';
  }

  Future<void> _vulFormulierVoorOperator(String id) async {
    if (!mounted) return;
    setState(() {
      _loadingForm = true;
      _resetFormControllers();
    });

    try {
      final g = await AppSupabase.client
          .from(GebruikersTable.name)
          .select(_operatorSelect)
          .eq(GebruikersTable.id, id)
          .maybeSingle();

      Map<String, dynamic>? voorschotRow;
      try {
        final vRes = await AppSupabase.client
            .from('operator_voorschotten')
            .select('voorschot_bedrag')
            .eq('operator_id', id)
            .eq('maand_sleutel', _voorschotMaandSleutel)
            .maybeSingle();
        if (vRes != null) {
          voorschotRow = Map<String, dynamic>.from(vRes as Map);
        }
      } catch (e) {
        debugPrint('HR: voorschot laden optioneel mislukt: $e');
      }

      if (!mounted) return;

      String uurloonTekst = '';
      String vasteUrenTekst = '';
      String vastSalarisTekst = '';
      String voorschotTekst = '';
      var contractType = 'nul_uren';
      DateTime? start;
      DateTime? end;
      var onbepaald = false;
      var geladenVoorschot = 0.0;

      if (g != null) {
        final m = Map<String, dynamic>.from(g as Map);
        final uurloon = m['standaard_uurloon'];
        if (uurloon != null) {
          uurloonTekst = uurloon is num
              ? uurloon.toString().replaceAll('.', ',')
              : _text(uurloon);
        }

        final ct = _text(m['contract_type']).toLowerCase();
        final vasteUren = _parseMoney(_text(m['contract_vaste_uren'])) ?? 0;
        final vastSalaris = _parseMoney(_text(m['contract_vast_salaris'])) ?? 0;
        contractType =
            ct == 'vast' || vasteUren > 0 || vastSalaris > 0 ? 'vast' : 'nul_uren';

        final uren = m['contract_vaste_uren'];
        if (uren != null) {
          vasteUrenTekst = uren is num && uren % 1 == 0
              ? uren.toInt().toString()
              : uren.toString();
        }
        final sal = m['contract_vast_salaris'];
        if (sal != null) {
          vastSalarisTekst = sal is num
              ? sal.toString().replaceAll('.', ',')
              : _text(sal);
        }

        start = _parseIsoDate(m['contract_startdatum']);
        end = _parseIsoDate(m['contract_einddatum']);
        onbepaald = end == null && contractType == 'vast';
      }

      if (voorschotRow != null) {
        final amt = voorschotRow['voorschot_bedrag'];
        geladenVoorschot = amt is num
            ? amt.toDouble()
            : (_parseMoney(_text(amt)) ?? 0);
        if (amt != null) {
          voorschotTekst = amt is num
              ? amt.toString().replaceAll('.', ',')
              : _text(amt);
        }
      }

      setState(() {
        _uurloonCtl.text = uurloonTekst;
        _vasteUrenCtl.text = vasteUrenTekst;
        _vastSalarisCtl.text = vastSalarisTekst;
        _voorschotCtl.text = voorschotTekst;
        _selectedContractType = contractType;
        _contractStart = start;
        _contractEnd = end;
        _isOnbepaaldeTijd = onbepaald;
        _geladenVoorschot = geladenVoorschot;
        _loadingForm = false;
      });
    } catch (e) {
      debugPrint('Fout bij laden operatorgegevens: $e');
      if (!mounted) return;
      setState(() => _loadingForm = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Laden mislukt: $e')),
      );
    }
  }

  Future<void> _onSelectOperator(String? id) async {
    if (id == null || id.isEmpty) return;
    setState(() => _selectedOperatorId = id);
    await _vulFormulierVoorOperator(id);
  }

  void _verschuifVoorschotMaand(int delta) {
    final m = DateTime(
      geselecteerdeVoorschotMaand.year,
      geselecteerdeVoorschotMaand.month + delta,
    );
    setState(() => geselecteerdeVoorschotMaand = m);
    final id = _selectedOperatorId;
    if (id != null && id.isNotEmpty) {
      _vulFormulierVoorOperator(id);
    }
  }

  Widget _buildVoorschotMaandPicker() {
    final label = DateFormat.yMMMM('nl_NL').format(geselecteerdeVoorschotMaand);
    return Row(
      children: [
        IconButton(
          tooltip: 'Vorige maand',
          onPressed: _loadingForm || _saving
              ? null
              : () => _verschuifVoorschotMaand(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Volgende maand',
          onPressed: _loadingForm || _saving
              ? null
              : () => _verschuifVoorschotMaand(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _contractStart ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) setState(() => _contractStart = d);
  }

  Future<void> _pickEnd() async {
    if (_isOnbepaaldeTijd) return;
    final d = await showDatePicker(
      context: context,
      initialDate: _contractEnd ?? _contractStart ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) {
      setState(() {
        _contractEnd = d;
        _isOnbepaaldeTijd = false;
      });
    }
  }

  Future<void> _opslaan() async {
    final id = _selectedOperatorId;
    if (id == null || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecteer een operator.')),
      );
      return;
    }

    final parsedUurloon = _parseMoney(_uurloonCtl.text.trim()) ?? 0.0;
    final parsedVasteUren = _parseMoney(_vasteUrenCtl.text.trim()) ?? 0.0;
    final parsedVastSalaris = _parseMoney(_vastSalarisCtl.text.trim()) ?? 0.0;
    final isVast = _selectedContractType == 'vast';

    setState(() => _saving = true);
    try {
      await AppSupabase.client.from(GebruikersTable.name).update({
        'contract_type': _selectedContractType,
        'standaard_uurloon': parsedUurloon,
        'contract_vaste_uren': isVast ? parsedVasteUren : 0.0,
        'contract_vast_salaris': isVast ? parsedVastSalaris : 0.0,
        'contract_startdatum': isVast
            ? _contractStart?.toIso8601String().split('T').first
            : null,
        'contract_einddatum': isVast
            ? (_isOnbepaaldeTijd
                ? null
                : _contractEnd?.toIso8601String().split('T').first)
            : null,
      }).eq(GebruikersTable.id, id);

      final vo = _voorschotCtl.text.trim();
      if (vo.isNotEmpty) {
        final bedrag = _parseMoney(vo) ?? 0;
        await AppSupabase.client.from('operator_voorschotten').upsert(
          {
            'operator_id': id,
            'maand_sleutel': _voorschotMaandSleutel,
            'voorschot_bedrag': bedrag,
          },
          onConflict: 'operator_id,maand_sleutel',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wijzigingen opgeslagen.'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
      await _vulFormulierVoorOperator(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opslaan mislukt: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildOperatorPicker({required bool compact}) {
    if (_operatoren.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _listError != null
              ? 'Kon operators niet laden. Vernieuw of controleer rechten.'
              : 'Geen actieve operators gevonden.',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      );
    }

    if (compact) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Operator',
          border: OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: _selectedOperatorId,
            items: [
              for (final op in _operatoren)
                DropdownMenuItem(
                  value: _text(op[GebruikersTable.id]),
                  child: Text(_operatorLabel(op)),
                ),
            ],
            onChanged: _loadingForm || _saving ? null : _onSelectOperator,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _operatoren.length,
      itemBuilder: (context, index) {
        final op = _operatoren[index];
        final id = _text(op[GebruikersTable.id]);
        final selected = id == _selectedOperatorId;
        return ListTile(
          selected: selected,
          title: Text(
            _operatorLabel(op),
            style: GoogleFonts.inter(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          onTap: _loadingForm || _saving ? null : () => _onSelectOperator(id),
        );
      },
    );
  }

  Widget _buildForm() {
    if (_selectedOperatorId == null) {
      return Center(
        child: Text(
          'Selecteer een operator.',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      );
    }

    if (_loadingForm) {
      return const Center(child: CircularProgressIndicator());
    }

    final isVast = _selectedContractType == 'vast';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Financiële gegevens',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _uurloonCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Uurloon (€)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Contract type',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'nul_uren',
                label: Text('0-Uren Contract'),
              ),
              ButtonSegment(
                value: 'vast',
                label: Text('Vast Contract'),
              ),
            ],
            selected: {_selectedContractType},
            onSelectionChanged: _saving
                ? null
                : (s) => setState(() => _selectedContractType = s.first),
          ),
          if (isVast) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _vasteUrenCtl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Vaste uren per maand',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _vastSalarisCtl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Vast bruto salaris (€)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _isOnbepaaldeTijd,
              onChanged: _saving
                  ? null
                  : (v) {
                      setState(() {
                        _isOnbepaaldeTijd = v ?? false;
                        if (_isOnbepaaldeTijd) _contractEnd = null;
                      });
                    },
              title: Text(
                'Contract voor onbepaalde tijd',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _pickStart,
                    child: Text(
                      _contractStart == null
                          ? 'Startdatum contract'
                          : DateFormat('dd-MM-yyyy').format(_contractStart!),
                    ),
                  ),
                ),
                if (!_isOnbepaaldeTijd) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : _pickEnd,
                      child: Text(
                        _contractEnd == null
                            ? 'Einddatum contract'
                            : DateFormat('dd-MM-yyyy').format(_contractEnd!),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Voorschotten',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          _buildVoorschotMaandPicker(),
          const SizedBox(height: 4),
          Text(
            'Maand: $_voorschotMaandSleutel',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Reeds uitbetaald in deze maand: €${_geladenVoorschot.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _voorschotCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Voorschot bedrag (€)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _opslaan,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Wijzigingen Opslaan'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_listError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Operators laden mislukt',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _listError!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.red.shade800),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _fetchOperatoren,
                child: const Text('Opnieuw proberen'),
              ),
            ],
          ),
        ),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 900;

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 280,
            child: Material(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Operators (${_operatoren.length})',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: _buildOperatorPicker(compact: false)),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildForm()),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildOperatorPicker(compact: true),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildForm()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGenerator = context.watch<UserProvider>().isGenerator;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'HR & Contracten',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (isGenerator)
            IconButton(
              tooltip: 'Vernieuwen',
              onPressed: _isLoading ? null : _fetchOperatoren,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: isGenerator
          ? _buildBody()
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Dit scherm is alleen toegankelijk voor gebruikers met de rol Generator.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ),
    );
  }
}
