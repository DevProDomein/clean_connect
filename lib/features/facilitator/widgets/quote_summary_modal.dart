import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QuoteSummaryModal extends StatefulWidget {
  const QuoteSummaryModal({
    super.key,
    required this.offerte,
    required this.ruimtes,
  });

  final Map<String, dynamic> offerte;
  final List<dynamic> ruimtes;

  @override
  State<QuoteSummaryModal> createState() => _QuoteSummaryModalState();
}

class _QuoteSummaryModalState extends State<QuoteSummaryModal> {
  final NumberFormat _eur = NumberFormat.currency(locale: 'nl_NL', symbol: '€ ');
  bool _isSending = false;

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

  String _formatDate(dynamic v) {
    final raw = _text(v);
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd-MM-yyyy').format(parsed);
  }

  Future<void> _sendFinal() async {
    if (_isSending) return;
    final offerteId = widget.offerte['id'];
    if (offerteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
          content: Text(
            'Offerte-ID ontbreekt. Verzenden is niet mogelijk.',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      await Supabase.instance.client
          .from('offertes')
          .update({'status': 'send'})
          .eq('id', offerteId);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
          content: Text(
            'Definitief verzenden mislukt. Probeer het opnieuw.',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value.isEmpty ? '-' : value,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: const Color(0xFF15141F),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.9;
    final regulier = _asInt(widget.offerte['regulier_aantal_beurten']);
    final frequent = _asInt(widget.offerte['frequent_aantal_beurten']);
    final periodiek = _asInt(widget.offerte['periodiek_aantal_beurten']);

    return Container(
      height: maxHeight,
      margin: EdgeInsets.only(top: media.padding.top + 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Offerte Overzicht',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                        letterSpacing: -0.4,
                        color: const Color(0xFF15141F),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F8),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: const Color(0xFF5F6472),
                  labelStyle: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                  unselectedLabelStyle: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                  indicator: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  tabs: const [
                    Tab(text: 'Klant & Contract'),
                    Tab(text: 'Ruimtes & Inventaris'),
                    Tab(text: 'Financieel Totaal'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    children: [
                      _buildInfoRow('Bedrijfsnaam', _text(widget.offerte['bedrijfsnaam_klant'])),
                      _buildInfoRow('Contactpersoon', _text(widget.offerte['contact_voornaam'])),
                      _buildInfoRow('E-mail', _text(widget.offerte['contact_email'])),
                      _buildInfoRow('Contracttype', _text(widget.offerte['contract_type'])),
                      _buildInfoRow('Startdatum', _formatDate(widget.offerte['contract_startdatum'])),
                      _buildInfoRow('Periodieke frequentie', _text(widget.offerte['periodieke_frequentie'])),
                    ],
                  ),
                  ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                    itemCount: widget.ruimtes.length,
                    itemBuilder: (context, index) {
                      final room = widget.ruimtes[index] as Map<String, dynamic>? ?? const {};
                      final naam = _text(room['naam_in_pand']).isEmpty
                          ? 'Onbenoemde ruimte'
                          : _text(room['naam_in_pand']);
                      final categorie = _text(room['ruimte_categorie']).isEmpty
                          ? 'Onbekende categorie'
                          : _text(room['ruimte_categorie']);
                      final aantal = _asInt(room['aantal_identiek'], fallback: 1);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    naam,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      color: const Color(0xFF15141F),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    categorie,
                                    style: GoogleFonts.inter(
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'x ${aantal < 1 ? 1 : aantal}',
                              style: GoogleFonts.inter(
                                color: cs.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    children: [
                      _buildInfoRow(
                        'Contractwaarde (ex btw)',
                        _eur.format(_asDouble(widget.offerte['totaal_prijs_ex_btw'])),
                      ),
                      _buildInfoRow(
                        'Btw per maand',
                        _eur.format(_asDouble(widget.offerte['maand_btw_bedrag'])),
                      ),
                      _buildInfoRow(
                        'Totaal per maand (incl btw)',
                        _eur.format(_asDouble(widget.offerte['maandprijs_inc_btw'])),
                      ),
                      const SizedBox(height: 4),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Text(
                        'Uitvoeringen',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildInfoRow('Regulier', '${regulier}x'),
                      _buildInfoRow('Frequent', '${frequent}x'),
                      _buildInfoRow('Periodiek', '${periodiek}x'),
                    ],
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.withValues(alpha: 0.22)),
                  ),
                ),
                child: ElevatedButton(
                  onPressed: _isSending ? null : _sendFinal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: cs.primary.withValues(alpha: 0.55),
                    elevation: 0,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Definitief verzenden naar klant',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
