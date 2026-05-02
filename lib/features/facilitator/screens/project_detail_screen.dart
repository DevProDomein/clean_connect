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

  static const List<String> _regioOptions = [
    'Amsterdam',
    "'t Gooi",
    'Stichtse Vecht',
    'Utrecht',
    'Amersfoort',
    'De Ronde Venen',
    'Wijdemeren',
  ];

  static const List<String> _statusOptions = [
    'actief',
    'gepauzeerd',
    'afgerond',
    'beeindigd',
    'concept',
  ];

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  bool _isDirty = false;
  Object? _error;

  Map<String, dynamic>? _project;
  String? _bedrijfId;
  String _bedrijfNaam = '';
  String? _bedrijfLogoUrl;
  String? _pandFotoUrl;
  String? _werkRegio;
  String _status = 'actief';
  String _aangemaaktLabel = '—';
  bool _uploadingPand = false;

  List<String> get _werkRegioChoices {
    final set = <String>{..._regioOptions};
    final w = _werkRegio;
    if (w != null && w.isNotEmpty) set.add(w);
    final list = set.toList()..sort();
    return list;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  void _markDirty() {
    if (_isDirty) return;
    setState(() => _isDirty = true);
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
      final notes = _text(row['notities']);

      if (!mounted) return;
      setState(() {
        _project = row;
        _bedrijfId = bid;
        _bedrijfNaam = naam.isEmpty ? 'Klant' : naam;
        _bedrijfLogoUrl = logo;
        _pandFotoUrl = pand.isEmpty ? null : pand;
        _werkRegio = wr.isEmpty ? null : wr;
        _status =
            _statusOptions.contains(rawSt) ? rawSt : _statusOptions.first;
        _aangemaaktLabel = aoLabel;
        _nameCtrl.text = naamProj;
        _descCtrl.text = notes;
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final patch = <String, dynamic>{
        'project_naam': _nameCtrl.text.trim(),
        'werk_regio': _werkRegio,
        'status': _status,
      };
      if (_descCtrl.text.trim().isNotEmpty) {
        patch['notities'] = _descCtrl.text.trim();
      }
      var notesWarn = false;
      try {
        await AppSupabase.client
            .from('projecten')
            .update(patch)
            .eq('id', widget.projectId);
      } catch (_) {
        if (patch.containsKey('notities')) {
          patch.remove('notities');
          notesWarn = true;
          await AppSupabase.client
              .from('projecten')
              .update(patch)
              .eq('id', widget.projectId);
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      setState(() => _isDirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notesWarn
                ? 'Project opgeslagen. Omschrijving kon niet worden opgeslagen.'
                : 'Wijzigingen opgeslagen.',
            style: GoogleFonts.lato(fontWeight: FontWeight.w700),
          ),
          backgroundColor:
              notesWarn ? Colors.amber.shade800 : Colors.green.shade700,
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
            controller: _descCtrl,
            maxLines: 4,
            style: GoogleFonts.lato(fontWeight: FontWeight.w600, color: _navy),
            decoration: deco(
              'Omschrijving / notities',
              hint: 'Optioneel — wordt opgeslagen indien ondersteund door database',
            ),
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _werkRegio == null || _werkRegio!.isEmpty
                ? null
                : (_werkRegioChoices.contains(_werkRegio) ? _werkRegio : null),
            decoration: deco('Werkregio'),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('—'),
              ),
              ..._werkRegioChoices.map(
                (r) => DropdownMenuItem(value: r, child: Text(r)),
              ),
            ],
            onChanged: (v) {
              setState(() {
                _werkRegio = v;
                _isDirty = true;
              });
            },
            style: GoogleFonts.lato(fontWeight: FontWeight.w700, color: _navy),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _statusOptions.contains(_status) ? _status : _statusOptions.first,
            decoration: deco('Status'),
            items: _statusOptions
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s[0].toUpperCase() + s.substring(1)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _status = v;
                _isDirty = true;
              });
            },
            style: GoogleFonts.lato(fontWeight: FontWeight.w700, color: _navy),
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
