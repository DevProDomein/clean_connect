import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/models/user_role.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';

class InvoiceSettingsScreen extends StatefulWidget {
  const InvoiceSettingsScreen({super.key});

  @override
  State<InvoiceSettingsScreen> createState() => _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends State<InvoiceSettingsScreen> {
  Future<void>? _future;
  bool _savingCompany = false;
  bool _savingTemplate = false;
  bool _uploadingLogo = false;

  Map<String, dynamic> _factuurConfig = {};
  String? _emailTemplateId;
  String _logoUrl = '';

  final _bedrijfsnaam = TextEditingController();
  final _kvk = TextEditingController();
  final _btw = TextEditingController();
  final _iban = TextEditingController();
  final _adres = TextEditingController();
  // Kept as part of config, but not shown in this step:
  // final _primaryHex = TextEditingController();

  final _bodyHtml = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _bedrijfsnaam.dispose();
    _kvk.dispose();
    _btw.dispose();
    _iban.dispose();
    _adres.dispose();
    _bodyHtml.dispose();
    super.dispose();
  }

  bool _canOpen(UserProvider up) {
    return up.isGenerator || up.role == UserRole.administrator || up.role == UserRole.generator;
  }

  Future<void> _load() async {
    final configRow = await AppSupabase.client
        .from(AppSettingsTable.name)
        .select(AppSettingsTable.waarde)
        .eq(AppSettingsTable.sleutel, 'factuur_config')
        .maybeSingle();

    final templateRow = await AppSupabase.client
        .from('factuur_email_templates')
        .select()
        .eq('soort', 'factuur_nieuw')
        .maybeSingle();

    final configMap = _coerceToMap(configRow?[AppSettingsTable.waarde]) ?? {};
    _factuurConfig = configMap;

    _bedrijfsnaam.text = (configMap['bedrijfsnaam'] ?? '').toString();
    _kvk.text = (configMap['kvk'] ?? '').toString();
    _btw.text = (configMap['btw_nummer'] ?? configMap['btw'] ?? '').toString();
    _iban.text = (configMap['iban'] ?? '').toString();
    _adres.text = (configMap['adres'] ?? '').toString();
    _logoUrl = (configMap['factuur_logo_url'] ?? '').toString().trim();

    _emailTemplateId = templateRow?['id']?.toString();
    _bodyHtml.text = (templateRow?['body_html'] ?? '').toString();

    if (mounted) setState(() {});
  }

  Map<String, dynamic>? _coerceToMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return null;
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  Future<void> _saveCompany() async {
    if (_savingCompany) return;
    setState(() => _savingCompany = true);
    try {
      final merged = <String, dynamic>{
        ..._factuurConfig, // merge JSONB: keep unknown keys
        'bedrijfsnaam': _bedrijfsnaam.text.trim(),
        'kvk': _kvk.text.trim(),
        'btw_nummer': _btw.text.trim(),
        'iban': _iban.text.trim(),
        'adres': _adres.text.trim(),
        'factuur_logo_url': _logoUrl,
      };

      await AppSupabase.client.from(AppSettingsTable.name).upsert(
        {
          AppSettingsTable.sleutel: 'factuur_config',
          AppSettingsTable.waarde: merged,
        },
        onConflict: AppSettingsTable.sleutel,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bedrijfsgegevens opgeslagen.')),
      );
      _factuurConfig = merged;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opslaan mislukt: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingCompany = false);
    }
  }

  Future<void> _saveTemplate() async {
    if (_savingTemplate) return;
    setState(() => _savingTemplate = true);
    try {
      if (_emailTemplateId != null && _emailTemplateId!.isNotEmpty) {
        await AppSupabase.client.from('factuur_email_templates').update({
          'body_html': _bodyHtml.text,
        }).eq('id', _emailTemplateId!);
      } else {
        final inserted = await AppSupabase.client.from('factuur_email_templates').insert({
          'soort': 'factuur_nieuw',
          'body_html': _bodyHtml.text,
        }).select().maybeSingle();
        _emailTemplateId = inserted?['id']?.toString();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sjabloon opgeslagen.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opslaan mislukt: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingTemplate = false);
    }
  }

  Future<void> _uploadLogo() async {
    if (_uploadingLogo) return;
    setState(() => _uploadingLogo = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) throw StateError('Leeg bestand.');

      final ext = (() {
        final p = picked.path.toLowerCase();
        if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'jpg';
        if (p.endsWith('.png')) return 'png';
        return 'png';
      })();

      final objectPath =
          'logos/logo_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final storage = AppSupabase.client.storage.from('public_assets');
      await storage.uploadBinary(
        objectPath,
        bytes,
        fileOptions: FileOptions(
          upsert: false,
          contentType: ext == 'jpg' ? 'image/jpeg' : 'image/png',
        ),
      );

      final publicUrl = storage.getPublicUrl(objectPath);
      _logoUrl = publicUrl;

      await _saveCompany();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo geüpload en opgeslagen.')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload mislukt: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    final cs = Theme.of(context).colorScheme;
    final canOpen = _canOpen(up);

    if (!canOpen) {
      return Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(title: const Text('Factuur Instellingen')),
        body: const SelectionArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: _NoAccessEmpty(
              message: 'U heeft geen rechten om app-instellingen te beheren.',
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(
            'Sjablonen & Logo',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
        ),
        body: SelectionArea(
          child: FutureBuilder<void>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: _NoAccessEmpty(message: 'Fout: ${snapshot.error}'),
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: cs.onSurface.withValues(alpha: 0.06),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: TabBar(
                        splashBorderRadius: BorderRadius.circular(50),
                        indicator: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: cs.onSurface.withValues(alpha: 0.70),
                        labelStyle: GoogleFonts.inter(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                        tabs: const [
                          Tab(
                            child: _PillTabLabel(
                              text: 'Bedrijfsgegevens & Logo',
                            ),
                          ),
                          Tab(
                            child: _PillTabLabel(text: 'HTML Sjablonen'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _CompanyAndLogoTab(
                          logoUrl: _logoUrl,
                          uploadingLogo: _uploadingLogo,
                          saving: _savingCompany,
                          onUploadLogo: _uploadLogo,
                          onSave: _saveCompany,
                          bedrijfsnaam: _bedrijfsnaam,
                          kvk: _kvk,
                          btw: _btw,
                          iban: _iban,
                        ),
                        _HtmlTemplateTab(
                          bodyHtml: _bodyHtml,
                          saving: _savingTemplate,
                          onSave: _saveTemplate,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CompanyAndLogoTab extends StatelessWidget {
  const _CompanyAndLogoTab({
    required this.logoUrl,
    required this.uploadingLogo,
    required this.saving,
    required this.onUploadLogo,
    required this.onSave,
    required this.bedrijfsnaam,
    required this.kvk,
    required this.btw,
    required this.iban,
  });

  final String logoUrl;
  final bool uploadingLogo;
  final bool saving;
  final VoidCallback onUploadLogo;
  final VoidCallback onSave;

  final TextEditingController bedrijfsnaam;
  final TextEditingController kvk;
  final TextEditingController btw;
  final TextEditingController iban;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? cs.surface.withValues(alpha: 0.70) : const Color(0xFFF5F5F7);

    Widget field(String label, TextEditingController c, {String? hint}) {
      return TextField(
        controller: c,
        decoration: InputDecoration(labelText: label, hintText: hint),
      );
    }

    final logoBox = Container(
      width: 160,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isDark ? 0.04 : 0.60),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: logoUrl.trim().isEmpty
            ? Center(
                child: Icon(
                  Icons.image_outlined,
                  color: cs.onSurface.withValues(alpha: 0.45),
                  size: 34,
                ),
              )
            : Image.network(
                logoUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: cs.onSurface.withValues(alpha: 0.45),
                    size: 34,
                  ),
                ),
              ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: tileBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bedrijfsgegevens & Logo',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  logoBox,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FilledButton.icon(
                          onPressed: uploadingLogo ? null : onUploadLogo,
                          style: FilledButton.styleFrom(
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                          icon: uploadingLogo
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload_rounded),
                          label: Text(
                            uploadingLogo ? 'Uploaden…' : 'Upload Logo (PNG/JPG)',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Logo wordt opgeslagen in de Supabase Storage bucket “public_assets” en de URL wordt bewaard in factuur_config.factuur_logo_url.',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withValues(alpha: 0.70),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              field('Bedrijfsnaam', bedrijfsnaam),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: field('KVK', kvk)),
                  const SizedBox(width: 12),
                  Expanded(child: field('BTW-nummer', btw)),
                ],
              ),
              const SizedBox(height: 12),
              field('IBAN', iban),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: saving ? null : onSave,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Opslaan',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HtmlTemplateTab extends StatelessWidget {
  const _HtmlTemplateTab({
    required this.bodyHtml,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController bodyHtml;
  final bool saving;
  final VoidCallback onSave;

  static const vars = <String>[
    '{{factuur_nummer}}',
    '{{totaal_inc_btw}}',
    '{{klant_naam}}',
    '{{logo_url}}',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? cs.surface.withValues(alpha: 0.70) : const Color(0xFFF5F5F7);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: tileBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HTML Sjabloon (factuur_nieuw)',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.14)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Beschikbare tags',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: vars
                          .map(
                            (v) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
                              ),
                              child: Text(
                                v,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: bodyHtml,
                maxLines: 20,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'body_html',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: saving ? null : onSave,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Sjabloon Opslaan',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PillTabLabel extends StatelessWidget {
  const _PillTabLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text),
    );
  }
}

class _NoAccessEmpty extends StatelessWidget {
  const _NoAccessEmpty({required this.message});

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

