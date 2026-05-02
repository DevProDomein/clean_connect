import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bottom sheet: rich project context from [app_dks_project_info].
class ProjectInfoModal extends StatefulWidget {
  const ProjectInfoModal({required this.projectId, super.key});

  final String projectId;

  static Future<void> show(BuildContext context, {required String projectId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProjectInfoModal(projectId: projectId),
    );
  }

  @override
  State<ProjectInfoModal> createState() => _ProjectInfoModalState();
}

class _ProjectInfoModalState extends State<ProjectInfoModal> {
  static const double _radius = 24;

  Map<String, dynamic>? _data;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetch();
    });
  }

  String _t(dynamic v) => (v ?? '').toString();

  Future<void> _fetch() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .from('app_dks_project_info')
          .select()
          .eq('project_id', widget.projectId)
          .single();
      if (!mounted) {
        return;
      }
      setState(() {
        _data = Map<String, dynamic>.from(res as Map);
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _data = null;
          _error = e;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Widget _row(IconData icon, String line) {
    if (line.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: const Color(0xFF0052CC)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              line,
              style: GoogleFonts.lato(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF0F172A),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(_radius)),
            boxShadow: [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 24,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Laden mislukt: $_error',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lato(
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(
                        20,
                        20,
                        20,
                        MediaQuery.of(context).viewPadding.bottom + 20,
                      ),
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        Text(
                          'Project Details',
                          style: GoogleFonts.lato(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        if (_data != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _t(_data!['project_naam']),
                            style: GoogleFonts.lato(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (_data != null) ...[
                          _row(
                            Icons.location_on_outlined,
                            _t(_data!['uitvoer_adres_volledig']),
                          ),
                          _row(
                            Icons.calendar_month_outlined,
                            [
                              _t(_data!['frequentie_type']),
                              _t(_data!['reguliere_weekdagen']),
                            ].where((e) => e.isNotEmpty).join(' · '),
                          ),
                          _row(
                            Icons.access_time_outlined,
                            '${_t(_data!['tijdslot_start'])} – ${_t(_data!['tijdslot_eind'])}',
                          ),
                          _row(
                            Icons.room_outlined,
                            'Aantal ruimtes: ${_t(_data!['aantal_ruimtes'])}',
                          ),
                          _row(
                            Icons.people_outline,
                            'Actieve operators (30d): ${_t(_data!['aantal_actieve_operators'])}',
                          ),
                          _row(
                            Icons.assignment_outlined,
                            'Aankomende opdrachten: ${_t(_data!['aankomende_opdrachten'])}',
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'Sluiten',
                              style: GoogleFonts.lato(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
        );
      },
    );
  }
}
