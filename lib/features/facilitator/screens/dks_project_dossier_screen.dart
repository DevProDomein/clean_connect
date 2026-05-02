import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dks_inspectie_form_screen.dart';
import '../widgets/dks_readonly_modal.dart';

class DksProjectDossierScreen extends StatefulWidget {
  final String projectId;
  final String projectNaam;

  const DksProjectDossierScreen({
    super.key,
    required this.projectId,
    this.projectNaam = 'Project',
  });

  @override
  State<DksProjectDossierScreen> createState() => _DksProjectDossierScreenState();
}

class _DksProjectDossierScreenState extends State<DksProjectDossierScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _reports = [];

  bool _isTodayOrPast(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return false;
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final normalizedDate = DateTime(date.year, date.month, date.day);
      final normalizedNow = DateTime(now.year, now.month, now.day);
      return normalizedDate.isBefore(normalizedNow) || normalizedDate.isAtSameMomentAs(normalizedNow);
    } catch (e) {
      return false;
    }
  }

  bool _isPast(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return false;
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      return DateTime(date.year, date.month, date.day).isBefore(DateTime(now.year, now.month, now.day));
    } catch (e) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final response = await _supabase
          .from('view_dks_project_dossier')
          .select()
          .eq('project_id', widget.projectId)
          .order('geplande_datum', ascending: true);

      if (mounted) {
        setState(() {
          _reports = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching dossier: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showProjectInfo(Map<String, dynamic> rapport) {
    final bedrijfsnaam = (rapport['bedrijfsnaam'] ?? '').toString();
    final adres = (rapport['uitvoer_adres_volledig'] ?? '').toString();
    final aantalRuimtes = rapport['aantal_ruimtes'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: 20 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                bedrijfsnaam.isEmpty ? 'Projectinformatie' : bedrijfsnaam,
                style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              if (adres.isNotEmpty) ...[
                Text('Adres', style: GoogleFonts.lato(fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                const SizedBox(height: 6),
                Text(adres, style: TextStyle(color: Colors.grey.shade700, height: 1.2)),
                const SizedBox(height: 14),
              ],
              Text('Aantal ruimtes', style: GoogleFonts.lato(fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
              const SizedBox(height: 6),
              Text(
                aantalRuimtes == null ? 'Onbekend' : aantalRuimtes.toString(),
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Sluiten'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final geplandeRondes = _reports.where((r) => r['status'] == 'gepland' || r['status'] == 'concept').toList();
    final historieRondes = _reports.where((r) => r['status'] == 'definitief').toList();
    
    // Sorteer historie op meest recent bovenaan
    historieRondes.sort((a, b) => (b['datum_uitgevoerd'] ?? '').compareTo(a['datum_uitgevoerd'] ?? ''));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text(
          '${widget.projectNaam} (DKS)',
          style: GoogleFonts.lato(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // --- SECTIE 1: AANSTAANDE INSPECTIE ---
                  Text('Ingeplande Keuringen', style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                  const SizedBox(height: 12),
                  
                  if (geplandeRondes.isEmpty)
                    _buildEmptyState('Geen geplande DKS inspecties. Inspecties worden automatisch ingepland.')
                  else
                    _buildAanstaandeInspectieKaart(geplandeRondes.first),

                  const SizedBox(height: 40),

                  // --- SECTIE 2: HISTORIE ---
                  Text('Historie', style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                  const SizedBox(height: 12),
                  
                  if (historieRondes.isEmpty)
                    _buildEmptyState('Nog geen afgeronde inspecties.')
                  else
                    ...historieRondes.map((rapport) => _buildHistorieKaart(rapport)),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.event_busy, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildAanstaandeInspectieKaart(Map<String, dynamic> rapport) {
    final geplandeRaw = rapport['geplande_datum']?.toString();
    final canStart = _isTodayOrPast(geplandeRaw);
    final overdue = _isPast(geplandeRaw);
    final dateStr = geplandeRaw == null || geplandeRaw.isEmpty ? 'Onbekend' : geplandeRaw;

    late final Color borderColor;
    late final Color titleColor;
    late final IconData leadingIcon;
    late final String statusTitle;

    if (overdue) {
      statusTitle = '⚠️ Inspectie VERLOPEN (Nog uit te voeren)';
      titleColor = const Color(0xFFC62828);
      borderColor = const Color(0xFFFFCDD2);
      leadingIcon = Icons.warning_amber_rounded;
    } else if (canStart) {
      statusTitle = 'Inspectie gepland voor VANDAAG';
      titleColor = const Color(0xFFFF6B35);
      borderColor = const Color(0xFFFFCC80);
      leadingIcon = Icons.today_rounded;
    } else {
      statusTitle = 'Aankomende inspectie';
      titleColor = Colors.blue.shade700;
      borderColor = Colors.blue.shade200;
      leadingIcon = Icons.calendar_month;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 10), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _showProjectInfo(rapport),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(leadingIcon, color: titleColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            statusTitle,
                            style: GoogleFonts.lato(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: titleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Gepland voor: $dateStr', style: const TextStyle(fontSize: 15, color: Colors.black87)),
                    const SizedBox(height: 8),
                    Text(
                      'Tik op deze kaart om projectinformatie te bekijken.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ),
            if (canStart)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DksInspectieFormScreen(rapportId: rapport['rapport_id']),
                        ),
                      ).then((_) => _fetchData());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: overdue ? const Color(0xFFC62828) : const Color(0xFFFF6B35),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      elevation: 0,
                    ),
                    child: Text(
                      '▶ Start Inspectie',
                      style: GoogleFonts.lato(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorieKaart(Map<String, dynamic> rapport) {
    final raw = rapport['score_definitief'] ?? rapport['score_voorgesteld'];
    double? grade;
    if (raw is num) {
      grade = raw.toDouble();
    } else if (raw != null) {
      grade = double.tryParse(raw.toString().replaceAll(',', '.'));
    }
    final g = grade ?? 0.0;
    final hasGrade = grade != null;

    Color badgeColor;
    if (!hasGrade) {
      badgeColor = Colors.grey.shade500;
    } else if (g >= 7.5) {
      badgeColor = Colors.green;
    } else if (g >= 5.5) {
      badgeColor = Colors.orange;
    } else {
      badgeColor = Colors.red;
    }

    final rapportId = (rapport['rapport_id'] ?? rapport['id'])?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 8), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: rapportId.isEmpty
              ? null
              : () => showDksReadonlyModal(context, rapportId: rapportId),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            leading: CircleAvatar(
              backgroundColor: badgeColor.withValues(alpha: 26),
              child: Icon(Icons.fact_check, color: badgeColor),
            ),
            title: Text(
              'Inspectie ${rapport['datum_uitgevoerd']?.toString().substring(0, 10) ?? ''}',
              style: GoogleFonts.lato(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Afgeronde kwaliteitscontrole', style: TextStyle(color: Colors.grey.shade600)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(12)),
              child: Text(
                hasGrade ? 'Cijfer: ${g.toStringAsFixed(1)}' : 'Cijfer: —',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),
    );
  }
}