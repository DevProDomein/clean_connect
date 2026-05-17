import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user_role.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import '../../../shared/layouts/mobile_nav_buffer.dart';

/// Generator: weergave van afgesloten maanden uit [operator_uitbetalingen].
class SalarisAdministratieScreen extends StatefulWidget {
  const SalarisAdministratieScreen({super.key});

  @override
  State<SalarisAdministratieScreen> createState() =>
      _SalarisAdministratieScreenState();
}

class _SalarisAdministratieScreenState extends State<SalarisAdministratieScreen> {
  static const Color _deepNavy = Color(0xFF1A237E);
  static const Color _brightBlue = Color(0xFF0052CC);
  static const Color _pageBg = Color(0xFFF2F4F8);

  static final _eur = NumberFormat.currency(
    locale: 'nl_NL',
    symbol: '€',
    decimalDigits: 2,
  );

  late DateTime _geselecteerdeMaand = _defaultGeselecteerdeMaand();

  static DateTime _defaultGeselecteerdeMaand() {
    final nu = DateTime.now();
    return DateTime(nu.year, nu.month - 1, 1);
  }

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _afgeslotenLoonstroken = [];

  String get _maandSleutel =>
      '${_geselecteerdeMaand.year}-${_geselecteerdeMaand.month.toString().padLeft(2, '0')}';

  String get _maandLabel {
    try {
      return DateFormat.yMMMM('nl_NL').format(_geselecteerdeMaand);
    } catch (_) {
      return DateFormat.yMMMM().format(_geselecteerdeMaand);
    }
  }

  bool _canAccess(UserProvider up) =>
      up.isGenerator || up.role == UserRole.administrator;

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(' ', '');
    if (s.isEmpty) return 0;
    final direct = double.tryParse(s);
    if (direct != null) return direct;
    if (s.contains(',')) {
      return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    final s = _text(v).toLowerCase();
    return s == 'true' || s == '1' || s == 'ja' || s == 'yes';
  }

  String _operatorNaamUitLoonstrook(Map<String, dynamic> item) {
    final op = item['operator'];
    if (op is Map) {
      final m = Map<String, dynamic>.from(op);
      final vn = _text(m['voornaam']);
      final an = _text(m['achternaam']);
      final full = '$vn $an'.trim();
      if (full.isNotEmpty) return full;
    }
    return 'Operator ${_text(item['operator_id'])}';
  }

  double _nettoUitLoonstrook(Map<String, dynamic> item) {
    final afw = item['afwijkend_bedrag'];
    if (afw != null && _text(afw).isNotEmpty) {
      return _asDouble(afw);
    }
    return _asDouble(item['berekend_bruto']) -
        _asDouble(item['verrekend_voorschot']);
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _shiftMaand(int delta) {
    setState(() {
      _geselecteerdeMaand = DateTime(
        _geselecteerdeMaand.year,
        _geselecteerdeMaand.month + delta,
      );
    });
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final maandSleutel = _maandSleutel;
      final response = await AppSupabase.client
          .from('operator_uitbetalingen')
          .select('*, operator:gebruikers(voornaam, achternaam)')
          .eq('maand_sleutel', maandSleutel)
          .order('operator_id', ascending: true);

      final rows = (response as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      rows.sort(
        (a, b) => _operatorNaamUitLoonstrook(a).toLowerCase().compareTo(
              _operatorNaamUitLoonstrook(b).toLowerCase(),
            ),
      );

      if (!mounted) return;
      setState(() {
        _afgeslotenLoonstroken = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  ({double totaalBruto, double reedsUitbetaald, double nogTeBetalen})
  _analytics() {
    var totaalBruto = 0.0;
    var reeds = 0.0;
    var nog = 0.0;
    for (final item in _afgeslotenLoonstroken) {
      totaalBruto += _asDouble(item['berekend_bruto']);
      if (_asBool(item['is_betaald'])) {
        reeds += _nettoUitLoonstrook(item);
      } else {
        nog += _nettoUitLoonstrook(item);
      }
    }
    return (totaalBruto: totaalBruto, reedsUitbetaald: reeds, nogTeBetalen: nog);
  }

  Future<void> _openUitbetaalModal(Map<String, dynamic> item) async {
    final afwijkendCtl = TextEditingController();
    final rawAfw = item['afwijkend_bedrag'];
    if (rawAfw != null) {
      if (rawAfw is num) {
        afwijkendCtl.text = rawAfw.toString().replaceAll('.', ',');
      } else {
        afwijkendCtl.text = _text(rawAfw);
      }
    }

    final bruto = _asDouble(item['berekend_bruto']);
    final voorschot = _asDouble(item['verrekend_voorschot']);
    final rowId = _text(item['id']);
    final naam = _operatorNaamUitLoonstrook(item);

    final parentContext = context;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;

        return Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.onSurface.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        naam,
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _maandLabel,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _modalRegel('Berekend bruto', _eur.format(bruto)),
                      _modalRegel('Verrekend voorschot', _eur.format(voorschot)),
                      const Divider(height: 24),
                      _modalRegel(
                        'Standaard netto',
                        _eur.format(bruto - voorschot),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: afwijkendCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Afwijkend bedrag (optioneel)',
                          hintText: 'Bonus of correctie',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () async {
                          if (rowId.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Systeemfout: geen uitbetaling-id.'),
                              ),
                            );
                            return;
                          }

                          final ingevuldeTekst = afwijkendCtl.text;
                          final afwijkendBedrag = double.tryParse(
                            ingevuldeTekst.replaceAll(',', '.'),
                          );

                          Navigator.pop(ctx);

                          try {
                            final updateResponse = await AppSupabase.client
                                .from('operator_uitbetalingen')
                                .update({
                                  'afwijkend_bedrag': afwijkendBedrag,
                                  'is_betaald': true,
                                  'betaald_op':
                                      DateTime.now().toIso8601String(),
                                })
                                .eq('id', rowId)
                                .select();

                            if ((updateResponse as List).isEmpty) {
                              throw Exception(
                                'Update mislukt. Controleer RLS of id: $rowId',
                              );
                            }

                            if (mounted) {
                              await _loadData();
                            }
                            if (!parentContext.mounted) return;
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(
                                content: Text('$naam gemarkeerd als uitbetaald.'),
                                backgroundColor: const Color(0xFF2E7D32),
                              ),
                            );
                          } catch (e) {
                            if (!parentContext.mounted) return;
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(
                                content: Text('Fout bij uitbetalen: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: _brightBlue,
                        ),
                        child: Text(
                          'Markeer als uitbetaald',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Sluiten'),
                      ),
                    ],
                  ),
                ),
              ),
            );
      },
    );

    afwijkendCtl.dispose();
  }

  Widget _modalRegel(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _maandSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Vorige maand',
            onPressed: _loading ? null : () => _shiftMaand(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              _maandLabel,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _deepNavy,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Volgende maand',
            onPressed: _loading ? null : () => _shiftMaand(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _analyticsRow(
    ({double totaalBruto, double reedsUitbetaald, double nogTeBetalen}) a,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _kpiCard('Totaal bruto', _eur.format(a.totaalBruto), _deepNavy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _kpiCard(
              'Reeds uitbetaald',
              _eur.format(a.reedsUitbetaald),
              const Color(0xFF2E7D32),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _kpiCard(
              'Nog te betalen',
              _eur.format(a.nogTeBetalen),
              _brightBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String title, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _trailing(Map<String, dynamic> item) {
    if (_asBool(item['is_betaald'])) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'BETAALD',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            color: const Color(0xFF166534),
          ),
        ),
      );
    }
    return FilledButton(
      onPressed: () => _openUitbetaalModal(item),
      style: FilledButton.styleFrom(
        backgroundColor: _brightBlue,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(
        'Uitbetalen',
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final canView = _canAccess(up);
    final analytics = _analytics();

    return Scaffold(
      backgroundColor: _pageBg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Salarisadministratie',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !canView
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Geen toegang tot salarisadministratie.',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            )
          : Column(
              children: [
                _maandSelector(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: GoogleFonts.inter(color: Colors.red.shade800),
                    ),
                  ),
                if (!_loading) _analyticsRow(analytics),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          color: _brightBlue,
                          onRefresh: _loadData,
                          child: _afgeslotenLoonstroken.isEmpty
                              ? ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(24),
                                  children: [
                                    const SizedBox(height: 48),
                                    Text(
                                      "Geen afgesloten loonstroken voor deze maand. "
                                      "Ga naar 'Uren Accorderen' en sluit een maand af "
                                      'voor een operator.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        height: 1.45,
                                      ),
                                    ),
                                    SizedBox(height: mobileNavBuffer),
                                  ],
                                )
                              : ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    8,
                                  ),
                                  itemCount: _afgeslotenLoonstroken.length,
                                  itemBuilder: (context, index) {
                                    final item =
                                        _afgeslotenLoonstroken[index];
                                    final bruto =
                                        _asDouble(item['berekend_bruto']);
                                    final voorschot = _asDouble(
                                      item['verrekend_voorschot'],
                                    );
                                    final isBetaald =
                                        _asBool(item['is_betaald']);

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: ListTile(
                                        onTap: isBetaald
                                            ? null
                                            : () => _openUitbetaalModal(item),
                                        title: Text(
                                          _operatorNaamUitLoonstrook(item),
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'Berekend Bruto: ${_eur.format(bruto)} | '
                                          'Voorschot: ${_eur.format(voorschot)}',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        trailing: _trailing(item),
                                      ),
                                    );
                                  },
                                ),
                        ),
                ),
                SizedBox(height: mobileNavBuffer),
              ],
            ),
    );
  }
}
