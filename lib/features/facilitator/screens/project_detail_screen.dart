import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user_role.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/network_image_fallback.dart';
import '../../../providers/user_provider.dart';
import '../../admin/screens/relation_detail_screen.dart';

/// Detail + bewerk scherm voor één project in [projecten].
class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  static const double _radius = 24;
  static const Color _navy = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _pageBg = Color(0xFFF7F8FB);
  static const Color _blue = Color(0xFF2563EB);

  static const List<({String key, String label})> _weekdayChips = [
    (key: 'maandag', label: 'Ma'),
    (key: 'dinsdag', label: 'Di'),
    (key: 'woensdag', label: 'Wo'),
    (key: 'donderdag', label: 'Do'),
    (key: 'vrijdag', label: 'Vr'),
    (key: 'zaterdag', label: 'Za'),
    (key: 'zondag', label: 'Zo'),
  ];

  final _nameCtrl = TextEditingController();
  final _omschrijvingCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  bool _isDirty = false;
  bool _scheduleChanged = false;
  Object? _error;

  Map<String, dynamic>? _project;
  Map<String, dynamic>? _projectStats;
  String? _bedrijfId;
  String _bedrijfNaam = '';
  String? _bedrijfLogoUrl;
  String? _pandFotoUrl;
  String? _werkRegio;
  String _status = 'actief';
  String _aangemaaktLabel = '—';
  bool _uploadingPand = false;

  final Set<String> _weekdaysSelected = {};
  TimeOfDay _tijdslotStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _tijdslotEind = const TimeOfDay(hour: 17, minute: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _omschrijvingCtrl.dispose();
    super.dispose();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  void _markDirty() {
    if (_isDirty) return;
    setState(() => _isDirty = true);
  }

  String _formatTimeDb(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  TimeOfDay _parseTime(dynamic raw) {
    final s = _text(raw);
    if (s.isEmpty) return const TimeOfDay(hour: 9, minute: 0);
    final parts = s.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
      }
    }
    return const TimeOfDay(hour: 9, minute: 0);
  }

  void _parseWeekdays(dynamic raw) {
    _weekdaysSelected.clear();
    if (raw is List) {
      for (final e in raw) {
        final k = _text(e).toLowerCase();
        if (k.isNotEmpty) _weekdaysSelected.add(k);
      }
      return;
    }
    final s = _text(raw);
    if (s.isEmpty) return;
    for (final part in s.split(',')) {
      final k = part.trim().toLowerCase();
      if (k.isNotEmpty) _weekdaysSelected.add(k);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_isDirty) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Niet opgeslagen wijzigingen',
          style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        content: Text(
          'Niet opgeslagen wijzigingen. Weet u zeker dat u wilt vertrekken?',
          style: GoogleFonts.lato(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuleren', style: GoogleFonts.lato(fontWeight: FontWeight.w800)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Verlaten', style: GoogleFonts.lato(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    return go == true;
  }

  Future<bool> _confirmPlanningSave() async {
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        title: Text(
          'Waarschuwing: Planning Wijziging',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Colors.red.shade700,
          ),
        ),
        content: Text(
          'Het aanpassen van start- en eindtijd is een ingrijpende actie. Het heeft directe invloed op het planbord en zal toekomstige gegenereerde opdrachten wijzigen. Weet u zeker dat u dit wilt doorvoeren?',
          style: GoogleFonts.lato(fontWeight: FontWeight.w600, fontSize: 15, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuleren', style: GoogleFonts.lato(fontWeight: FontWeight.w800)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Ja, pas planning aan',
              style: GoogleFonts.lato(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _load() async {
    final u = AppSupabase.client.auth.currentUser;
    if (u == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Niet ingelogd.';
        });
      }
      return;
    }
    if (!mounted) return;
    final up = context.read<UserProvider>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await AppSupabase.client
          .from('projecten')
          .select('*, bedrijven(id, bedrijfsnaam, logo_url)')
          .eq('id', widget.projectId)
          .single();

      final row = Map<String, dynamic>.from(res as Map);
      final isFac = up.role == UserRole.facilitator;
      final facId = _text(row['facilitator_id']);
      if (isFac && facId.isNotEmpty && facId != u.id) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Geen toegang tot dit project.';
            _project = null;
          });
        }
        return;
      }

      Map<String, dynamic>? stats;
      try {
        final sv = await AppSupabase.client
            .from('app_dks_project_info')
            .select()
            .eq('project_id', widget.projectId)
            .maybeSingle();
        if (sv != null) {
          stats = Map<String, dynamic>.from(sv as Map);
        }
      } catch (_) {
        stats = null;
      }

      Map<String, dynamic>? b;
      final join = row['bedrijven'];
      if (join is Map) {
        b = Map<String, dynamic>.from(join);
      }

      String? logo;
      String naam = '';
      String? bid;
      if (b != null) {
        bid = _text(b['id']);
        if (bid.isEmpty) bid = null;
        naam = _text(b['bedrijfsnaam']);
        final lu = _text(b['logo_url']);
        logo = lu.isEmpty ? null : lu;
      }
      if (bid == null) {
        final rawBid = _text(row['bedrijf_id']);
        bid = rawBid.isEmpty ? null : rawBid;
      }

      DateTime? ao;
      final rawAo = row['aangemaakt_op'];
      if (rawAo != null) {
        ao = rawAo is DateTime ? rawAo : DateTime.tryParse(rawAo.toString());
      }
      final aoLabel = ao == null
          ? '—'
          : '${ao.day.toString().padLeft(2, '0')}-${ao.month.toString().padLeft(2, '0')}-${ao.year}';

      final naamProj =
          _text(row['project_naam']).isEmpty ? _text(row['naam']) : _text(row['project_naam']);
      final wr = _text(row['werk_regio']);
      final rawSt =
          _text(row['status']).isEmpty ? 'actief' : _text(row['status']).toLowerCase();
      final pand = _text(row['pand_foto_url']);
      final oms = _text(row['omschrijving']);

      if (!mounted) return;
      setState(() {
        _project = row;
        _projectStats = stats;
        _bedrijfId = bid;
        _bedrijfNaam = naam.isEmpty ? 'Klant' : naam;
        _bedrijfLogoUrl = logo;
        _pandFotoUrl = pand.isEmpty ? null : pand;
        _werkRegio = wr.isEmpty ? null : wr;
        _status = rawSt;
        _aangemaaktLabel = aoLabel;
        _nameCtrl.text = naamProj;
        _omschrijvingCtrl.text = oms;
        _parseWeekdays(row['reguliere_weekdagen']);
        _tijdslotStart = _parseTime(row['tijdslot_start']);
        _tijdslotEind = _parseTime(row['tijdslot_eind']);
        _scheduleChanged = false;
        _loading = false;
        _isDirty = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
          _project = null;
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
      await AppSupabase.client.from('projecten').update({
        'pand_foto_url': newUrl,
      }).eq('id', widget.projectId);
      if (!mounted) return;
      setState(() {
        _pandFotoUrl = newUrl;
        if (_project != null) {
          _project!['pand_foto_url'] = newUrl;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pandfoto opgeslagen.',
            style: GoogleFonts.lato(fontWeight: FontWeight.w700),
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Opslaan mislukt: $e',
            style: GoogleFonts.lato(fontWeight: FontWeight.w700),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingPand = false);
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _tijdslotStart : _tijdslotEind;
    final t = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.light(primary: _blue, surface: Colors.white),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (t == null || !mounted) return;
    setState(() {
      if (isStart) {
        _tijdslotStart = t;
      } else {
        _tijdslotEind = t;
      }
      _scheduleChanged = true;
      _isDirty = true;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_scheduleChanged) {
      final ok = await _confirmPlanningSave();
      if (!ok || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      final patch = <String, dynamic>{
        'project_naam': _nameCtrl.text.trim(),
        'omschrijving': _omschrijvingCtrl.text.trim(),
        'tijdslot_start': _formatTimeDb(_tijdslotStart),
        'tijdslot_eind': _formatTimeDb(_tijdslotEind),
      };

      try {
        await AppSupabase.client
            .from('projecten')
            .update(patch)
            .eq('id', widget.projectId);
      } catch (_) {
        final fallback = Map<String, dynamic>.from(patch)..remove('omschrijving');
        await AppSupabase.client
            .from('projecten')
            .update(fallback)
            .eq('id', widget.projectId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Project opgeslagen. Kolom omschrijving wordt niet ondersteund — overige velden wel.',
              style: GoogleFonts.lato(fontWeight: FontWeight.w600),
            ),
            backgroundColor: Colors.amber.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        setState(() {
          _isDirty = false;
          _scheduleChanged = false;
          _saving = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _isDirty = false;
        _scheduleChanged = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Wijzigingen opgeslagen.',
            style: GoogleFonts.lato(fontWeight: FontWeight.w700),
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Opslaan mislukt: $e',
            style: GoogleFonts.lato(fontWeight: FontWeight.w700),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openClientDossier() async {
    final id = _bedrijfId;
    if (id == null || id.isEmpty) return;
    if (_isDirty) {
      final ok = await _confirmLeave();
      if (!ok) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/facilitator/relations/detail'),
        builder: (_) => RelationDetailScreen(bedrijfId: id),
      ),
    );
  }

  Future<void> _onBackPressed() async {
    final ok = await _confirmLeave();
    if (ok && mounted) Navigator.of(context).pop();
  }

  String _fmtTimeUi(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int _statInt(String key) {
    final v = _projectStats?[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_text(v)) ?? 0;
  }

  Widget _buildKpiRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildKpiCard(
            icon: Icons.meeting_room_outlined,
            label: 'Aantal Ruimtes',
            value: '${_statInt('aantal_ruimtes')}',
          ),
          const SizedBox(width: 10),
          _buildKpiCard(
            icon: Icons.event_note_outlined,
            label: 'Geplande Opdrachten',
            value: '${_statInt('aankomende_opdrachten')}',
          ),
          const SizedBox(width: 10),
          _buildKpiCard(
            icon: Icons.groups_outlined,
            label: 'Actieve Operators',
            value: '${_statInt('aantal_actieve_operators')}',
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: _blue.withValues(alpha: 0.9)),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 2,
                style: GoogleFonts.lato(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _muted,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: GoogleFonts.lato(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _navy,
                  height: 1.05,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onBackPressed();
      },
      child: Scaffold(
        backgroundColor: _pageBg,
        floatingActionButton: _isDirty && !_loading && _error == null && _project != null
            ? FloatingActionButton.extended(
                onPressed: _saving ? null : _save,
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                elevation: 3,
                icon: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  'Opslaan',
                  style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              )
            : null,
        body: _loading
            ? const Center(child: CupertinoActivityIndicator(radius: 16))
            : _error != null && _project == null
                ? _buildError()
                : CustomScrollView(
                    slivers: [
                      SliverAppBar(
                        pinned: true,
                        backgroundColor: Colors.white,
                        surfaceTintColor: Colors.white,
                        elevation: 0,
                        leading: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: _navy, size: 20),
                          onPressed: _onBackPressed,
                        ),
                        title: Text(
                          'Project',
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: _navy,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(child: _buildHeader()),
                      SliverToBoxAdapter(child: _buildClientStrip()),
                      SliverToBoxAdapter(child: _buildKpiRow()),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                          child: _buildForm(),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Kan project niet laden: $_error',
          textAlign: TextAlign.center,
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w700,
            color: _muted,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final url = _pandFotoUrl?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: SizedBox(
          height: 200,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null && url.isNotEmpty)
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _placeholderHeader(),
                )
              else
                _placeholderHeader(),
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _uploadingPand ? null : _uploadPandFoto,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: _uploadingPand
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.edit_outlined,
                              color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderHeader() {
    return Container(
      color: const Color(0xFFE2E8F0),
      alignment: Alignment.center,
      child: Icon(Icons.domain_rounded, size: 64, color: Colors.grey.shade400),
    );
  }

  Widget _buildClientStrip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        elevation: 0,
        shadowColor: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: _openClientDossier,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                RelationLogoAvatar(
                  logoUrl: _bedrijfLogoUrl,
                  fallbackLetter: _bedrijfNaam,
                  size: 48,
                  accentColor: _blue,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _bedrijfNaam,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.lato(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: _navy,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: _muted.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    InputDecoration deco(String label, {String? hint}) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.lato(
          fontWeight: FontWeight.w800,
          fontSize: 13,
          color: _muted,
        ),
        hintStyle: GoogleFonts.lato(color: _muted.withValues(alpha: 0.7)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _blue, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
    }

    final statusLabel =
        _status.isEmpty ? '—' : '${_status[0].toUpperCase()}${_status.substring(1)}';
    final regioLabel = _werkRegio?.isEmpty ?? true ? '—' : _werkRegio!;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Gegevens',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: _navy,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(Icons.flag_outlined, size: 18, color: _blue.withValues(alpha: 0.85)),
                label: Text(
                  'Status: $statusLabel',
                  style: GoogleFonts.lato(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                backgroundColor: const Color(0xFFF1F5F9),
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
              Chip(
                avatar: Icon(Icons.map_outlined, size: 18, color: _blue.withValues(alpha: 0.85)),
                label: Text(
                  'Werkregio: $regioLabel',
                  style: GoogleFonts.lato(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                backgroundColor: const Color(0xFFF1F5F9),
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameCtrl,
            style: GoogleFonts.lato(fontWeight: FontWeight.w700, color: _navy),
            decoration: deco('Projectnaam'),
            onChanged: (_) => _markDirty(),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Vul een projectnaam in.';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _omschrijvingCtrl,
            maxLines: 3,
            style: GoogleFonts.lato(fontWeight: FontWeight.w600, color: _navy),
            decoration: deco('Omschrijving'),
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 18),
          Tooltip(
            message:
                'Werkdagen zijn vastgezet. Neem contact op met support om dit te wijzigen.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Werkdagen (Neem contact op met support om dit te wijzigen)',
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _weekdayChips.map((e) {
                    final sel = _weekdaysSelected.contains(e.key);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: sel
                            ? _blue.withValues(alpha: 0.14)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: sel
                              ? _blue.withValues(alpha: 0.45)
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Text(
                        e.label,
                        style: GoogleFonts.lato(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: sel ? _blue : _muted,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Tijdslot',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: _muted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _pickTime(isStart: true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule_rounded, color: _blue.withValues(alpha: 0.85)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Start',
                                  style: GoogleFonts.lato(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _muted,
                                  ),
                                ),
                                Text(
                                  _fmtTimeUi(_tijdslotStart),
                                  style: GoogleFonts.lato(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: _navy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _pickTime(isStart: false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule_send_rounded, color: _blue.withValues(alpha: 0.85)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Einde',
                                  style: GoogleFonts.lato(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _muted,
                                  ),
                                ),
                                Text(
                                  _fmtTimeUi(_tijdslotEind),
                                  style: GoogleFonts.lato(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: _navy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 20, color: _muted.withValues(alpha: 0.8)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aangemaakt op',
                        style: GoogleFonts.lato(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: _muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _aangemaaktLabel,
                        style: GoogleFonts.lato(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: _navy,
                        ),
                      ),
                      Text(
                        'Alleen-lezen',
                        style: GoogleFonts.lato(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
