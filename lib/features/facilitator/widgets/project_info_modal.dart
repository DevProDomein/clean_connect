import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/image_upload_service.dart';

/// Bottom sheet: rich project context from [app_dks_project_info], plus
/// bedrijfslogo (read-only) en pand-foto upload.
class ProjectInfoModal extends StatefulWidget {
  const ProjectInfoModal({required this.projectId, super.key});

  final String projectId;

  static Future<void> show(BuildContext context, {required String projectId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SelectionArea(
        child: ProjectInfoModal(projectId: projectId),
      ),
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

  String? _pandFotoUrl;
  String? _bedrijfLogoUrl;
  String _bedrijfNaam = '';
  bool _uploadingPand = false;

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
      final infoRes = await Supabase.instance.client
          .from('app_dks_project_info')
          .select()
          .eq('project_id', widget.projectId)
          .single();

      Map<String, dynamic>? extras;
      try {
        final er = await Supabase.instance.client
            .from('projecten')
            .select('pand_foto_url, bedrijven(logo_url, bedrijfsnaam)')
            .eq('id', widget.projectId)
            .maybeSingle();
        if (er != null) {
          extras = Map<String, dynamic>.from(er as Map);
        }
      } catch (_) {
        try {
          final er2 = await Supabase.instance.client
              .from('projecten')
              .select('pand_foto_url')
              .eq('id', widget.projectId)
              .maybeSingle();
          if (er2 != null) {
            extras = Map<String, dynamic>.from(er2 as Map);
          }
        } catch (_) {}
      }

      if (!mounted) return;

      String? pand;
      String? logo;
      String naam = '';
      if (extras != null) {
        pand = _t(extras['pand_foto_url']).trim();
        pand = pand.isEmpty ? null : pand;
        final b = extras['bedrijven'];
        if (b is Map) {
          final bm = Map<String, dynamic>.from(b);
          final lu = _t(bm['logo_url']).trim();
          logo = lu.isEmpty ? null : lu;
          naam = _t(bm['bedrijfsnaam']);
        }
      }

      setState(() {
        _data = Map<String, dynamic>.from(infoRes as Map);
        _pandFotoUrl = pand;
        _bedrijfLogoUrl = logo;
        _bedrijfNaam = naam;
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

  Future<void> _uploadPandFoto() async {
    final newUrl = await ImageUploadService.pickAndUploadImage(
      context,
      'projecten',
    );
    if (!mounted || newUrl == null) return;
    setState(() => _uploadingPand = true);
    try {
      await Supabase.instance.client.from('projecten').update({
        'pand_foto_url': newUrl,
      }).eq('id', widget.projectId);
      if (!mounted) return;
      setState(() => _pandFotoUrl = newUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pandfoto opgeslagen.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload opslaan mislukt: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingPand = false);
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

  Widget _bedrijfLogoBlock() {
    final url = _bedrijfLogoUrl?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bedrijfslogo',
            style: GoogleFonts.lato(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF64748B),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 72,
                  height: 72,
                  color: const Color(0xFFF1F5F9),
                  child: url != null && url.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (c, u) => const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          errorWidget: (c, u, e) => Icon(
                            Icons.business_rounded,
                            size: 36,
                            color: Colors.grey.shade400,
                          ),
                        )
                      : Icon(
                          Icons.business_rounded,
                          size: 36,
                          color: Colors.grey.shade400,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _bedrijfNaam.isEmpty ? '—' : _bedrijfNaam,
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Logo alleen te wijzigen bij de bedrijfsrelatie.',
            style: GoogleFonts.lato(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pandPhotoSection() {
    final url = _pandFotoUrl?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pand',
            style: GoogleFonts.lato(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF64748B),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          if (url != null && url.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 140,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (c, u) => Container(
                    color: const Color(0xFFF1F5F9),
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (c, u, e) => Container(
                    color: const Color(0xFFF1F5F9),
                    alignment: Alignment.center,
                    child: Icon(Icons.home_work_outlined,
                        size: 48, color: Colors.grey.shade400),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _uploadingPand ? null : _uploadPandFoto,
              icon: _uploadingPand
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo_outlined),
              label: Text(
                'Foto van het pand toevoegen',
                style: GoogleFonts.lato(fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
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
                        const SizedBox(height: 20),
                        _bedrijfLogoBlock(),
                        _pandPhotoSection(),
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
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
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
