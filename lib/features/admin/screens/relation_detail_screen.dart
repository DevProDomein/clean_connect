import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/image_upload_service.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../providers/user_provider.dart';
import '../widgets/add_contact_modal.dart';

/// 360° client dossier.
///
/// Premium Apple-SaaS style relation dossier for facilitators /
/// administrators. Shows:
///   - Header met naam + KVK/adres.
///   - KPI-kaarten (`app_klant_dossier_stats`).
///   - Tab Stamgegevens (bedrijven-formulier; FAB voor eenmalige klus).
///   - Tab Contactpersonen.
class RelationDetailScreen extends StatefulWidget {
  const RelationDetailScreen({
    super.key,
    required this.bedrijfId,
    this.createAsKlant,
    this.initialTabIndex = 0,
  });

  /// When null the screen opens in "create mode" (new bedrijf).
  final String? bedrijfId;

  /// Only consulted when [bedrijfId] == null. Controls the type
  /// assigned on insert (true → klant, false → leverancier).
  final bool? createAsKlant;

  /// `0` = Stamgegevens, `1` = Contactpersonen.
  final int initialTabIndex;

  @override
  State<RelationDetailScreen> createState() => _RelationDetailScreenState();
}

class _RelationDetailScreenState extends State<RelationDetailScreen>
    with SingleTickerProviderStateMixin {
  // ---------------- design tokens ----------------
  static const double _radius = 24;
  static const Color _navy = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _subtle = Color(0xFFF5F6FA);
  static const Color _blue = Color(0xFF2563EB);
  static const Color _green = Color(0xFF16A34A);
  static const Color _orange = Color(0xFFF59E0B);
  static const Color _red = Color(0xFFDC2626);
  static const Color _pageBg = Color(0xFFF7F8FB);

  /// Postgres `unique_violation` — duplicate bedrijf / constraint clash.
  static const String _duplicateBedrijfSnackText =
      'Dit bedrijf bestaat al, voer een andere bedrijfsnaam in, of ga naar de bestaande klant.';

  /// `werk_regio_type` allowed values (kept in sync with
  /// `user_management_screen.dart` / `quote_create_header_screen.dart`).
  static const List<String> _werkRegioOpties = [
    'Amsterdam',
    "'t Gooi",
    'Stichtse Vecht',
    'Utrecht',
    'Amersfoort',
    'De Ronde Venen',
    'Wijdemeren',
  ];

  // ---------------- state ----------------
  final _formKey = GlobalKey<FormState>();

  String? _id;
  String? _debiteurNummer;
  String? _crediteurNummer;
  String? _logoUrl;

  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _contacten = [];
  List<Map<String, dynamic>> _btwCodes = [];

  late TabController _tabController;

  bool _isLoading = true;
  bool _isSaving = false;
  Object? _loadError;

  // Stamgegevens controllers.
  final _bedrijfsnaamCtrl = TextEditingController();
  final _kvkCtrl = TextEditingController();
  final _facturatieEmailCtrl = TextEditingController();
  final _adresCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  final _stadCtrl = TextEditingController();
  final _brancheCtrl = TextEditingController();
  final _betaaltermijnCtrl = TextEditingController();
  final _kredietlimietCtrl = TextEditingController();

  String? _standaardBtwCode;
  bool _isWkaPlichtig = false;
  String _standaardLayout = 'standaard';

  /// Standaard regio for "Eenmalige Klus" (from [bedrijf.werk_regio]).
  String? _clientWerkRegio;

  // ---------------- lifecycle ----------------
  @override
  void initState() {
    super.initState();
    final idx = widget.initialTabIndex.clamp(0, 1);
    _tabController = TabController(length: 2, vsync: this, initialIndex: idx);
    _id = widget.bedrijfId;
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _bedrijfsnaamCtrl.dispose();
    _kvkCtrl.dispose();
    _facturatieEmailCtrl.dispose();
    _adresCtrl.dispose();
    _postcodeCtrl.dispose();
    _stadCtrl.dispose();
    _brancheCtrl.dispose();
    _betaaltermijnCtrl.dispose();
    _kredietlimietCtrl.dispose();
    super.dispose();
  }

  // ---------------- helpers ----------------
  String _text(dynamic v) => (v ?? '').toString().trim();

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    final s = _text(v).toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 't';
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(_text(v).replaceAll(',', '.')) ?? 0;
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_text(v)) ?? 0;
  }

  DateTime? _asDate(dynamic v) {
    if (v is DateTime) return v;
    final s = _text(v);
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  int _pickInt(Map<String, dynamic>? src, List<String> keys) {
    if (src == null) return 0;
    for (final k in keys) {
      if (src.containsKey(k) && src[k] != null) return _asInt(src[k]);
    }
    return 0;
  }

  DateTime? _pickDate(Map<String, dynamic>? src, List<String> keys) {
    if (src == null) return null;
    for (final k in keys) {
      if (src.containsKey(k) && src[k] != null) {
        final d = _asDate(src[k]);
        if (d != null) return d;
      }
    }
    return null;
  }

  String _firstLetter(String s) {
    final t = s.trim();
    return t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    return DateFormat('dd-MM-yyyy').format(d);
  }

  // ---------------- data ----------------
  ///
  /// [silent]: geen full-screen loader — houdt TabBar + [TabController] gemonteerd
  /// (voorkomt `_dependents.isEmpty` / lifecycle asserts na opslaan).
  Future<void> _loadAll({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    } else {
      setState(() => _loadError = null);
    }

    try {
      Map<String, dynamic>? bedrijf;
      Map<String, dynamic>? stats;
      List<Map<String, dynamic>> contacten = const [];

      if ((_id ?? '').isNotEmpty) {
        final bedrijfRes = await AppSupabase.client
            .from('bedrijven')
            .select()
            .eq('id', _id!)
            .maybeSingle();
        bedrijf = bedrijfRes == null
            ? null
            : Map<String, dynamic>.from(bedrijfRes);

        // Stats view is optional; keep the rest of the dossier usable
        // if the view is missing or empty for this bedrijf.
        try {
          final statsRes = await AppSupabase.client
              .from('app_klant_dossier_stats')
              .select()
              .eq('bedrijf_id', _id!)
              .maybeSingle();
          stats = statsRes == null
              ? null
              : Map<String, dynamic>.from(statsRes);
        } catch (_) {
          stats = null;
        }

        final dynamic contactRes = await AppSupabase.client
            .from('contactpersonen')
            .select()
            .eq('bedrijf_id', _id!)
            .order('id', ascending: true);
        contacten = (contactRes as List)
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
      }

      final dynamic btwRes = await AppSupabase.client
          .from('fiscale_btw_codes')
          .select('code, omschrijving, percentage, is_verlegd')
          .order('omschrijving', ascending: true);
      final btwCodes = (btwRes as List)
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();

      if (bedrijf != null) {
        _seedFormFromBedrijf(bedrijf);
      }

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _contacten = contacten;
        _btwCodes = btwCodes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
      });
    } finally {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Alleen contactpersonen verversen (sneller dan volledige [_loadAll]).
  Future<void> _reloadContacten() async {
    final bid = _id;
    if (bid == null || bid.isEmpty) return;
    try {
      final dynamic contactRes = await AppSupabase.client
          .from('contactpersonen')
          .select()
          .eq('bedrijf_id', bid)
          .order('id', ascending: true);
      final list = (contactRes as List)
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      if (!mounted) return;
      setState(() => _contacten = list);
    } catch (e, st) {
      debugPrint('_reloadContacten: $e\n$st');
      if (!mounted) return;
      _showError('Kon contacten niet vernieuwen: $e');
    }
  }

  void _seedFormFromBedrijf(Map<String, dynamic> bedrijf) {
    _debiteurNummer = _text(bedrijf['debiteur_nummer']);
    _crediteurNummer = _text(bedrijf['crediteur_nummer']);

    _bedrijfsnaamCtrl.text = _text(bedrijf['bedrijfsnaam']);
    _kvkCtrl.text =
        _text(bedrijf['kvk_nummer'] ?? bedrijf['kvk']);
    _facturatieEmailCtrl.text =
        _text(bedrijf['facturatie_email'] ?? bedrijf['factuur_email']);
    _adresCtrl.text = _text(
      bedrijf['adres_straat_huisnr'] ??
          bedrijf['adres_straat'] ??
          bedrijf['adres'],
    );
    _postcodeCtrl.text =
        _text(bedrijf['adres_postcode'] ?? bedrijf['postcode']);
    _stadCtrl.text =
        _text(bedrijf['adres_stad'] ?? bedrijf['stad']);
    _brancheCtrl.text = _text(bedrijf['branche']);
    _betaaltermijnCtrl.text = _text(
        bedrijf['betalingstermijn_dagen'] ?? bedrijf['betaaltermijn_dagen']);
    _kredietlimietCtrl.text = _text(bedrijf['kredietlimiet']);

    _standaardBtwCode = _text(bedrijf['standaard_btw_code_id']).isEmpty
        ? null
        : _text(bedrijf['standaard_btw_code_id']);
    _isWkaPlichtig = _asBool(bedrijf['is_wka_plichtig']);
    _standaardLayout = _text(bedrijf['standaard_layout']).isEmpty
        ? 'standaard'
        : _text(bedrijf['standaard_layout']);
    final wr = _text(bedrijf['werk_regio']);
    _clientWerkRegio = wr.isEmpty ? null : wr;
    final logo = _text(bedrijf['logo_url']);
    _logoUrl = logo.isEmpty ? null : logo;
  }

  // ---------------- save ----------------
  Future<void> _saveStamgegevens() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final facilitator =
        context.read<UserProvider>().roleString == 'facilitator';

    setState(() => _isSaving = true);
    try {
      final payload = <String, dynamic>{
        'bedrijfsnaam': _bedrijfsnaamCtrl.text.trim(),
        'kvk_nummer': _kvkCtrl.text.trim(),
        'facturatie_email': _facturatieEmailCtrl.text.trim(),
        'adres_straat_huisnr': _adresCtrl.text.trim(),
        'adres_postcode': _postcodeCtrl.text.trim(),
        'adres_stad': _stadCtrl.text.trim(),
        'branche': _brancheCtrl.text.trim(),
        'standaard_layout': _standaardLayout,
      };

      if (facilitator && (_id ?? '').isEmpty) {
        payload['standaard_btw_code_id'] = '2';
        payload['betalingstermijn_dagen'] = 14;
        payload['is_wka_plichtig'] = false;
        payload['kredietlimiet'] = 0;
      } else {
        payload['standaard_btw_code_id'] = _standaardBtwCode;
        payload['betalingstermijn_dagen'] =
            int.tryParse(_betaaltermijnCtrl.text.trim());
        payload['kredietlimiet'] = _asDouble(_kredietlimietCtrl.text.trim());
        payload['is_wka_plichtig'] = _isWkaPlichtig;
      }

      if ((_id ?? '').isEmpty) {
        payload['is_klant'] = widget.createAsKlant == true;
        payload['is_leverancier'] = widget.createAsKlant == false;
        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid != null) {
          payload['betrokken_facilitator_id'] = uid;
        }
        final inserted = await AppSupabase.client
            .from('bedrijven')
            .insert(payload)
            .select()
            .single();
        if (!mounted) return;
        _id = _text(inserted['id']);
        _debiteurNummer = _text(inserted['debiteur_nummer']);
        _crediteurNummer = _text(inserted['crediteur_nummer']);
      } else {
        await AppSupabase.client
            .from('bedrijven')
            .update(payload)
            .eq('id', _id!);
      }

      if (!mounted) return;
      await _loadAll(silent: true);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_tabController.length > 1) {
          _tabController.animateTo(1);
        }
      });
      _showWorkflowSnack(
        'Stamgegevens opgeslagen. Voeg nu optioneel een contactpersoon toe.',
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      if (e.code == '23505') {
        _showError(_duplicateBedrijfSnackText);
      } else {
        _showError('Kon relatie niet opslaan: ${e.message}');
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Kon relatie niet opslaan: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------- UX ----------------
  void _showSuccess(String msg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _green,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius)),
        content: Text(
          msg,
          style: GoogleFonts.lato(
              fontWeight: FontWeight.w900, color: Colors.white),
        ),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _red,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius)),
        content: Text(
          msg,
          style: GoogleFonts.lato(
              fontWeight: FontWeight.w900, color: Colors.white),
        ),
      ),
    );
  }

  void _showWorkflowSnack(String msg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor: const Color(0xFF475569),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
        content: Text(
          msg,
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.white,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  // ==========================================================
  //  One-off klus modal + RPC
  // ==========================================================

  Future<void> _openEenmaligeKlusModal() async {
    if ((_id ?? '').isEmpty) {
      _showError('Sla de relatie eerst op voordat je een klus aanmaakt.');
      return;
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EenmaligeKlusSheet(
        bedrijfId: _id!,
        regioOpties: _werkRegioOpties,
        initialRegio: _clientWerkRegio,
      ),
    );
    if (!mounted) return;
    if (result == true) {
      _showSuccess('Klus aangemaakt en naar planbord verstuurd!');
      await _loadAll(silent: true);
    }
  }

  // ==========================================================
  //  Build
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UserProvider>();
    // Facilitators must see the dossier even when `manage_crm` is not
    // yet in the in-memory permissions set; rely on role + permission.
    final canView = up.hasPermission('manage_crm') ||
        up.roleString == 'facilitator' ||
        up.roleString == 'administrator' ||
        up.roleString == 'generator';

    final isFacilitator = up.roleString == 'facilitator';

    return Scaffold(
      backgroundColor: _pageBg,
      drawer: const AppDrawer(),
      appBar: _buildAppBar(),
      floatingActionButton: _buildFab(canView),
      body: !canView
          ? _buildNoPermission()
          : _isLoading
              ? const Center(child: CupertinoActivityIndicator(radius: 16))
              : _loadError != null
                  ? _buildErrorState()
                  : _buildContent(isFacilitator: isFacilitator),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.black),
      title: Text(
        'Relatie Dossier',
        style: GoogleFonts.lato(
          fontWeight: FontWeight.w900,
          fontSize: 20,
          color: Colors.black,
          letterSpacing: -0.2,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Vernieuwen',
          onPressed: _isLoading ? null : () => _loadAll(),
          icon: const Icon(Icons.refresh_rounded, color: Colors.black),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: Colors.black.withValues(alpha: 0.06),
        ),
      ),
    );
  }

  Widget? _buildFab(bool canView) {
    if (!canView) return null;
    if ((_id ?? '').isEmpty) return null;
    return FloatingActionButton.extended(
      onPressed: _openEenmaligeKlusModal,
      backgroundColor: _blue,
      foregroundColor: Colors.white,
      elevation: 2,
      extendedPadding:
          const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      icon: const Icon(Icons.add_rounded, size: 22),
      label: Text(
        'Nieuwe Klus Toevoegen',
        style: GoogleFonts.lato(
          fontWeight: FontWeight.w900,
          fontSize: 15,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  Widget _buildNoPermission() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: 40, color: _muted),
              const SizedBox(height: 10),
              Text(
                'Geen toegang',
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Je hebt het recht `manage_crm` nodig, of de rol '
                'facilitator / administrator / generator, om dit dossier te '
                'openen.',
                textAlign: TextAlign.center,
                style: GoogleFonts.lato(
                    fontWeight: FontWeight.w600, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: _red),
            const SizedBox(height: 10),
            Text(
              'Kan dossier niet laden',
              style: GoogleFonts.lato(
                  fontWeight: FontWeight.w900, color: _navy, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              '$_loadError',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(
                  fontWeight: FontWeight.w600, color: _muted),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('Opnieuw proberen',
                  style: GoogleFonts.lato(fontWeight: FontWeight.w900)),
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_radius)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent({required bool isFacilitator}) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _buildHeader(),
          _buildKpiRow(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStamgegevensTab(hideFinancials: isFacilitator),
                _buildContactpersonenTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onLogoTap() async {
    final id = _id;
    if (id == null || id.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sla de relatie eerst op om een logo toe te voegen.')),
      );
      return;
    }

    final newUrl =
        await ImageUploadService.pickAndUploadImage(context, 'bedrijven');
    if (!mounted || newUrl == null) return;

    try {
      await AppSupabase.client
          .from('bedrijven')
          .update({'logo_url': newUrl}).eq('id', id);
      if (!mounted) return;
      setState(() => _logoUrl = newUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logo succesvol bijgewerkt!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Logo opslaan mislukt: $e');
    }
  }

  // ---------------- header ----------------
  Widget _buildHeader() {
    final name = _bedrijfsnaamCtrl.text.trim().isEmpty
        ? (_id == null ? 'Nieuwe relatie' : 'Onbekende relatie')
        : _bedrijfsnaamCtrl.text.trim();
    final kvk = _kvkCtrl.text.trim();
    final addressParts = <String>[
      _adresCtrl.text.trim(),
      [_postcodeCtrl.text.trim(), _stadCtrl.text.trim()]
          .where((p) => p.isNotEmpty)
          .join(' '),
    ].where((s) => s.isNotEmpty).toList();
    final address = addressParts.join(' · ');

    final subtitleParts = <String>[
      if (kvk.isNotEmpty) 'KVK $kvk',
      if (address.isNotEmpty) address,
    ];
    final subtitle =
        subtitleParts.isEmpty ? 'Geen adres bekend' : subtitleParts.join(' · ');

    final topNumber = (_debiteurNummer?.isNotEmpty ?? false)
        ? _debiteurNummer!
        : (_crediteurNummer?.isNotEmpty ?? false)
            ? _crediteurNummer!
            : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: _Card(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _onLogoTap,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _subtle,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: _logoUrl != null && _logoUrl!.isNotEmpty
                        ? Image.network(
                            _logoUrl!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.add_a_photo,
                                color: Colors.grey,
                                size: 36,
                              );
                            },
                          )
                        : const Icon(
                            Icons.add_a_photo,
                            color: Colors.grey,
                            size: 36,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.lato(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.lato(
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
                ],
              ),
            ),
            if (topNumber.isNotEmpty) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _subtle,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  topNumber,
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: _muted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------- KPI row ----------------
  Widget _buildKpiRow() {
    final stats = _stats;
    // Guard for create-mode: skip KPI strip entirely.
    if ((_id ?? '').isEmpty) return const SizedBox(height: 8);

    final actieveProjecten = _pickInt(stats, const [
      'actieve_projecten',
      'actieve_projecten_count',
      'aantal_actieve_projecten',
      'aantal_projecten_actief',
    ]);
    final totaalTaken = _pickInt(stats, const [
      'totaal_taken',
      'totaal_opdrachten',
      'aantal_taken_totaal',
      'opdrachten_totaal',
    ]);
    final voltooideTaken = _pickInt(stats, const [
      'voltooide_taken',
      'afgeronde_taken',
      'aantal_taken_voltooid',
      'opdrachten_voltooid',
    ]);
    final contractEinde = _pickDate(stats, const [
      'eerstvolgende_contract_einde',
      'volgende_contract_einde',
    ]);

    final now = DateTime.now();
    int? daysUntil;
    if (contractEinde != null) {
      daysUntil = contractEinde
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
    }

    final pct = totaalTaken == 0
        ? 0.0
        : (voltooideTaken / totaalTaken).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _KpiCard(
              icon: Icons.folder_rounded,
              iconBg: _blue.withValues(alpha: 0.12),
              iconColor: _blue,
              label: 'Actieve Projecten',
              value: actieveProjecten.toString(),
              sub: actieveProjecten == 0
                  ? 'Geen actieve projecten'
                  : 'Lopend bij deze klant',
              valueColor: _navy,
            ),
            const SizedBox(width: 12),
            _KpiCard(
              icon: Icons.check_circle_rounded,
              iconBg: _green.withValues(alpha: 0.12),
              iconColor: _green,
              label: 'Voltooide Taken',
              value: '$voltooideTaken / $totaalTaken',
              sub: totaalTaken == 0
                  ? 'Nog geen taken'
                  : '${(pct * 100).toStringAsFixed(0)}% afgerond',
              valueColor: _navy,
              progress: totaalTaken == 0 ? null : pct,
              progressColor: _green,
            ),
            const SizedBox(width: 12),
            _KpiCard(
              icon: Icons.event_rounded,
              iconBg: (contractEinde == null
                      ? _muted
                      : (daysUntil != null && daysUntil <= 60)
                          ? (daysUntil <= 14 ? _red : _orange)
                          : _blue)
                  .withValues(alpha: 0.12),
              iconColor: contractEinde == null
                  ? _muted
                  : (daysUntil != null && daysUntil <= 60)
                      ? (daysUntil <= 14 ? _red : _orange)
                      : _blue,
              label: 'Volgende Contract Verlenging',
              value: contractEinde == null
                  ? '—'
                  : _formatDate(contractEinde),
              sub: contractEinde == null
                  ? 'Geen contract einddatum bekend'
                  : (daysUntil != null && daysUntil < 0)
                      ? 'Verstreken sinds ${daysUntil.abs()} dagen'
                      : 'Nog ${daysUntil ?? '?'} dagen',
              valueColor: contractEinde == null
                  ? _muted
                  : (daysUntil != null && daysUntil <= 60)
                      ? (daysUntil <= 14 ? _red : _orange)
                      : _navy,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- tab bar ----------------
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: _Card(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: TabBar(
          controller: _tabController,
          isScrollable: false,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: _blue,
            borderRadius: BorderRadius.circular(18),
          ),
          labelColor: Colors.white,
          unselectedLabelColor: _muted,
          labelStyle: GoogleFonts.lato(
              fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: -0.1),
          unselectedLabelStyle:
              GoogleFonts.lato(fontWeight: FontWeight.w800, fontSize: 13),
          dividerColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          tabs: const [
            Tab(text: 'Stamgegevens'),
            Tab(text: 'Contactpersonen'),
          ],
        ),
      ),
    );
  }

  // ---------------- TAB: Stamgegevens ----------------
  Widget _buildStamgegevensTab({required bool hideFinancials}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Algemeen'),
              const SizedBox(height: 12),
              _textField(_bedrijfsnaamCtrl, 'Bedrijfsnaam',
                  validator: _requiredValidator),
              const SizedBox(height: 12),
              _textField(
                _kvkCtrl,
                'KVK-nummer',
                keyboard: TextInputType.number,
                validator: _kvkValidator,
              ),
              const SizedBox(height: 12),
              _textField(
                _facturatieEmailCtrl,
                'Facturatie e-mail',
                keyboard: TextInputType.emailAddress,
                validator: _emailValidator,
              ),
              const SizedBox(height: 12),
              _textField(_brancheCtrl, 'Branche'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Adres'),
              const SizedBox(height: 12),
              _textField(_adresCtrl, 'Adres (straat + huisnummer)'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _textField(_postcodeCtrl, 'Postcode')),
                  const SizedBox(width: 12),
                  Expanded(child: _textField(_stadCtrl, 'Stad')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Financieel & Condities'),
              if (hideFinancials) const SizedBox(height: 12),
              if (!hideFinancials) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _standaardBtwCode,
                  items: _btwCodes.map((r) {
                    final oms = _text(r['omschrijving']);
                    final code = _text(r['code']);
                    return DropdownMenuItem<String>(
                      value: code,
                      child: Text(oms.isEmpty ? code : oms,
                          style: GoogleFonts.lato(
                              fontWeight: FontWeight.w700)),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _standaardBtwCode = v),
                  decoration: _fieldDecoration('Standaard BTW-code'),
                  style: GoogleFonts.lato(
                      fontWeight: FontWeight.w700, color: _navy),
                ),
                const SizedBox(height: 12),
                _textField(_betaaltermijnCtrl, 'Betalingstermijn (dagen)',
                    keyboard: TextInputType.number),
                const SizedBox(height: 12),
                _textField(
                  _kredietlimietCtrl,
                  'Kredietlimiet (€)',
                  keyboard:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _subtle,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('WKA plichtig',
                            style: GoogleFonts.lato(
                                fontWeight: FontWeight.w900,
                                color: _navy)),
                      ),
                      CupertinoSwitch(
                        value: _isWkaPlichtig,
                        onChanged: (v) =>
                            setState(() => _isWkaPlichtig = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                initialValue: _standaardLayout,
                items: const [
                  DropdownMenuItem(
                      value: 'standaard', child: Text('Standaard')),
                  DropdownMenuItem(
                      value: 'uren_specificatie',
                      child: Text('Uren specificatie')),
                  DropdownMenuItem(
                      value: 'verzamel_factuur',
                      child: Text('Verzamel factuur')),
                ],
                onChanged: (v) =>
                    setState(() => _standaardLayout = v ?? 'standaard'),
                decoration: _fieldDecoration('Standaard factuur-layout'),
                style: GoogleFonts.lato(
                    fontWeight: FontWeight.w700, color: _navy),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 58,
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _saveStamgegevens,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(
              _isSaving ? 'Opslaan…' : 'Opslaan',
              style: GoogleFonts.lato(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: -0.1),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _blue.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_radius)),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- TAB 3: Contactpersonen ----------------
  Widget _buildContactpersonenTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      children: [
        _Card(
          child: Row(
            children: [
              Expanded(child: _sectionTitle('Contactpersonen')),
              FilledButton.icon(
                onPressed:
                    (_id ?? '').isEmpty ? null : _openAddContactDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  'Toevoegen',
                  style: GoogleFonts.lato(
                      fontWeight: FontWeight.w900),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if ((_id ?? '').isEmpty)
          _buildInfoBox(
            icon: Icons.info_outline_rounded,
            title: 'Eerst opslaan',
            message:
                'Sla de relatie op om contactpersonen toe te voegen.',
          )
        else if (_contacten.isEmpty)
          _buildInfoBox(
            icon: Icons.person_add_alt_1_rounded,
            title: 'Geen contactpersonen',
            message:
                'Voeg een contactpersoon toe om communicatie vast te leggen.',
          )
        else
          ..._contacten.map(_buildContactCard),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: () {
              if (!mounted) return;
              Navigator.of(context).maybePop();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              side: BorderSide(color: Colors.black.withValues(alpha: 0.14)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_radius),
              ),
            ),
            child: Text(
              'Afronden',
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactCard(Map<String, dynamic> c) {
    final contactId = _text(c['id']);
    final vnaam = _text(c['voornaam']);
    final anaam = _text(c['achternaam']);
    final email = _text(c['email']);
    final telefoon = _text(c['telefoon']);
    final functie = _text(c['functie']);
    final isFact = _asBool(c['is_facturatie_contact']);
    final full = '$vnaam $anaam'.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: (_id ?? '').isEmpty || contactId.isEmpty
              ? null
              : () => _openEditContactDialog(c),
          child: _Card(
            borderRadius: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _firstLetter(full.isEmpty ? '?' : full),
                    style: GoogleFonts.lato(
                      fontWeight: FontWeight.w900,
                      color: _blue,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              full.isEmpty ? '—' : full,
                              style: GoogleFonts.lato(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                                color: _navy,
                              ),
                            ),
                          ),
                          if (isFact)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.receipt_long_rounded,
                                    size: 14,
                                    color: _green,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Facturatie',
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                      color: _green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (functie.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          functie,
                          style: GoogleFonts.lato(
                              fontWeight: FontWeight.w700, color: _muted),
                        ),
                      ],
                      const SizedBox(height: 6),
                      if (email.isNotEmpty)
                        _contactLine(Icons.alternate_email_rounded, email),
                      if (telefoon.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        _contactLine(Icons.phone_rounded, telefoon),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Verwijderen',
                  visualDensity: VisualDensity.compact,
                  icon:
                      Icon(Icons.delete_outline, color: Colors.grey.shade600),
                  onPressed: contactId.isEmpty
                      ? null
                      : () => _confirmDeleteContact(contactId),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contactLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _muted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: GoogleFonts.lato(
                fontWeight: FontWeight.w700, color: _muted, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteContact(String contactId) async {
    if (contactId.isEmpty || !mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
        title: Text(
          'Contactpersoon verwijderen?',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
        content: Text(
          'Deze actie kan niet ongedaan worden gemaakt.',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w600,
            color: _muted,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx, rootNavigator: true).pop(false),
            child: Text(
              'Annuleren',
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w800,
                color: _muted,
              ),
            ),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx, rootNavigator: true).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_radius),
              ),
            ),
            child: Text(
              'Verwijderen',
              style: GoogleFonts.lato(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    try {
      await AppSupabase.client
          .from('contactpersonen')
          .delete()
          .eq('id', contactId);
      await _reloadContacten();
      if (!mounted) return;
      _showSuccess('Contactpersoon verwijderd.');
    } catch (e) {
      if (!mounted) return;
      _showError('Kon contactpersoon niet verwijderen: $e');
    }
  }

  Future<void> _openAddContactDialog() async {
    if ((_id ?? '').isEmpty) return;
    final bedrijfId = _id!;

    // Capture messenger before async gap.
    final messenger = ScaffoldMessenger.maybeOf(context);

    final bool? success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: AddContactModal(bedrijfId: bedrijfId),
      ),
    );

    if (!mounted) return;
    if (success == true) {
      await _reloadContacten();
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Contactpersoon succesvol toegevoegd!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _openEditContactDialog(Map<String, dynamic> contactData) async {
    if ((_id ?? '').isEmpty) return;
    final bedrijfId = _id!;
    final messenger = ScaffoldMessenger.maybeOf(context);

    final bool? success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: AddContactModal(
          bedrijfId: bedrijfId,
          existingContact: contactData,
        ),
      ),
    );

    if (!mounted) return;
    if (success == true) {
      await _reloadContacten();
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Wijzigingen opgeslagen.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ---------------- small UI helpers ----------------
  Widget _sectionTitle(String t) => Text(
        t,
        style: GoogleFonts.lato(
          fontWeight: FontWeight.w900,
          fontSize: 16,
          letterSpacing: -0.2,
          color: _navy,
        ),
      );

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.lato(
        fontWeight: FontWeight.w700,
        color: _muted,
      ),
      filled: true,
      fillColor: _subtle,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: const BorderSide(color: _blue, width: 1.2),
      ),
    );
  }

  Widget _textField(
    TextEditingController c,
    String label, {
    TextInputType keyboard = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: keyboard,
      validator: validator,
      style: GoogleFonts.lato(fontWeight: FontWeight.w700, color: _navy),
      decoration: _fieldDecoration(label),
    );
  }

  String? _requiredValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Dit veld is verplicht.';
    return null;
  }

  String? _kvkValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    if (!RegExp(r'^\d{8}$').hasMatch(s)) {
      return 'KVK-nummer moet exact 8 cijfers zijn.';
    }
    return null;
  }

  String? _emailValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
      return 'Geen geldig e-mailadres.';
    }
    return null;
  }

  Widget _buildInfoBox({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.lato(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: -0.2,
                      color: _navy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: GoogleFonts.lato(
                  fontWeight: FontWeight.w600, color: _muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================
//  Reusable widgets
// ==========================================================

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding, this.borderRadius = 24});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
    required this.valueColor,
    this.progress,
    this.progressColor,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;
  final Color valueColor;
  final double? progress;
  final Color? progressColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.3,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                    letterSpacing: -1.0,
                    color: valueColor,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: const Color(0xFF64748B),
                ),
              ),
              if (progress != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progressColor ?? const Color(0xFF16A34A),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================================
//  Eenmalige Klus bottom sheet (calls `maak_eenmalige_klus` RPC)
// ==========================================================

class _EenmaligeKlusSheet extends StatefulWidget {
  const _EenmaligeKlusSheet({
    required this.bedrijfId,
    required this.regioOpties,
    this.initialRegio,
  });

  final String bedrijfId;
  final List<String> regioOpties;
  /// Default region from the client's [bedrijf.werk_regio] when in the list.
  final String? initialRegio;

  @override
  State<_EenmaligeKlusSheet> createState() => _EenmaligeKlusSheetState();
}

class _EenmaligeKlusSheetState extends State<_EenmaligeKlusSheet> {
  static const double _radius = 24;
  static const Color _navy = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _blue = Color(0xFF2563EB);
  static const Color _red = Color(0xFFDC2626);
  static const Color _subtle = Color(0xFFF5F6FA);

  final _formKey = GlobalKey<FormState>();
  final _naamCtrl = TextEditingController();
  final _urenCtrl = TextEditingController(text: '0');

  DateTime? _datum;
  TimeOfDay? _startTijd;
  TimeOfDay? _eindTijd;
  String? _regio;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final raw = (widget.initialRegio ?? '').trim();
    if (raw.isNotEmpty && widget.regioOpties.contains(raw)) {
      _regio = raw;
    }
  }

  @override
  void dispose() {
    _naamCtrl.dispose();
    _urenCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _fmtTimeDb(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:00';

  String _fmtTimeUi(TimeOfDay? t) {
    if (t == null) return 'Kies tijd';
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: _datum ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx)
                .colorScheme
                .copyWith(primary: _blue, onPrimary: Colors.white),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (result != null && mounted) {
      setState(() => _datum = result);
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final initial = (start ? _startTijd : _eindTijd) ??
        const TimeOfDay(hour: 9, minute: 0);
    final result = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx)
                .colorScheme
                .copyWith(primary: _blue, onPrimary: Colors.white),
          ),
          child: MediaQuery(
            data: MediaQuery.of(ctx)
                .copyWith(alwaysUse24HourFormat: true),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
    if (result != null && mounted) {
      setState(() {
        if (start) {
          _startTijd = result;
        } else {
          _eindTijd = result;
        }
        // Auto-compute uren when both set.
        if (_startTijd != null && _eindTijd != null) {
          final startMin = _startTijd!.hour * 60 + _startTijd!.minute;
          final endMin = _eindTijd!.hour * 60 + _eindTijd!.minute;
          final diff = endMin - startMin;
          if (diff > 0) {
            _urenCtrl.text = (diff / 60).toStringAsFixed(2);
          }
        }
      });
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_datum == null) {
      _snack('Kies een datum.');
      return;
    }
    if (_startTijd == null || _eindTijd == null) {
      _snack('Kies start- en eindtijd.');
      return;
    }
    if (_regio == null || _regio!.isEmpty) {
      _snack('Kies een regio.');
      return;
    }

    final uren = double.tryParse(
          _urenCtrl.text.trim().replaceAll(',', '.'),
        ) ??
        0;
    if (uren <= 0) {
      _snack('Vul een geldig aantal uren in.');
      return;
    }

    var popped = false;
    setState(() => _saving = true);
    try {
      await AppSupabase.client.rpc(
        'maak_eenmalige_klus',
        params: {
          'p_bedrijf_id': widget.bedrijfId,
          'p_naam': _naamCtrl.text.trim(),
          'p_datum': _fmtDate(_datum!),
          'p_starttijd': _fmtTimeDb(_startTijd!),
          'p_eindtijd': _fmtTimeDb(_eindTijd!),
          'p_uren': uren,
          'p_regio': _regio,
        },
      );
      if (!mounted) return;
      popped = true;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack('Aanmaken mislukt: $e');
    } finally {
      if (mounted && !popped) {
        setState(() => _saving = false);
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _red,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius)),
        content: Text(
          msg,
          style: GoogleFonts.lato(
              fontWeight: FontWeight.w900, color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Eenmalige Klus Aanmaken',
                    style: GoogleFonts.lato(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      letterSpacing: -0.4,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bijv. glasbewassing, gevelreiniging — verschijnt direct op het planbord.',
                    style: GoogleFonts.lato(
                        fontWeight: FontWeight.w600, color: _muted),
                  ),
                  const SizedBox(height: 18),
                  _input(
                    controller: _naamCtrl,
                    label: 'Project Naam',
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Naam is verplicht.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _pickerTile(
                    label: 'Datum',
                    value: _datum == null
                        ? 'Kies datum'
                        : DateFormat('dd-MM-yyyy').format(_datum!),
                    icon: Icons.calendar_today_rounded,
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _pickerTile(
                          label: 'Starttijd',
                          value: _fmtTimeUi(_startTijd),
                          icon: Icons.schedule_rounded,
                          onTap: () => _pickTime(start: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _pickerTile(
                          label: 'Eindtijd',
                          value: _fmtTimeUi(_eindTijd),
                          icon: Icons.schedule_rounded,
                          onTap: () => _pickTime(start: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _input(
                    controller: _urenCtrl,
                    label: 'Uren',
                    keyboard:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final s = (v ?? '').trim().replaceAll(',', '.');
                      final d = double.tryParse(s);
                      if (d == null || d <= 0) {
                        return 'Geldige uren vereist.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _regio,
                    items: widget.regioOpties
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(r,
                                  style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w700)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _regio = v),
                    decoration: _decoration('Regio'),
                    style: GoogleFonts.lato(
                        fontWeight: FontWeight.w700, color: _navy),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Regio is verplicht.' : null,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () {
                                  if (!mounted) return;
                                  Navigator.of(context).pop(false);
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _muted,
                            side: BorderSide(
                                color: Colors.black.withValues(alpha: 0.1)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(_radius)),
                          ),
                          child: Text(
                            'Annuleren',
                            style: GoogleFonts.lato(
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _submit,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 18),
                          label: Text(
                            _saving ? 'Bezig…' : 'Klus Aanmaken',
                            style: GoogleFonts.lato(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.1),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(_radius)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.lato(
          fontWeight: FontWeight.w700, color: _muted),
      filled: true,
      fillColor: _subtle,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: const BorderSide(color: _blue, width: 1.2),
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    TextInputType keyboard = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      validator: validator,
      style: GoogleFonts.lato(fontWeight: FontWeight.w700, color: _navy),
      decoration: _decoration(label),
    );
  }

  Widget _pickerTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(_radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _subtle,
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: _muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.lato(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.2,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: GoogleFonts.lato(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: _navy,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}
