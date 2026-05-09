import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../providers/user_provider.dart';
import '../../../core/widgets/app_drawer.dart';

/// Persoonlijk profiel: foto, vaste loginvelden, telefoon bewerkbaar.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _navy = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _blue = Color(0xFF2563EB);
  static const _radius24 = BorderRadius.all(Radius.circular(24));

  static const String _colProfielfoto = 'profielfoto_url';
  static const String _colTelefoon = 'telefoon';

  final _telefoonCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  String? _profielfotoUrl;
  String _voornaam = '';
  String _achternaam = '';
  String _email = '';

  static const List<String> _facilitatorMenuKeyOrder = [
    'dashboard',
    'agenda',
    'tickets',
    'planbord',
    'crm',
    'offertes',
  ];

  static const Map<String, String> _facilitatorMenuLabels = {
    'dashboard': 'Dashboard',
    'agenda': 'Agenda',
    'tickets': 'Tickets',
    'planbord': 'Planbord',
    'crm': 'CRM',
    'offertes': 'Offertes',
  };

  // Operator: uitsluitend operator-specifieke keuzes.
  static const List<String> _operatorMenuKeyOrder = [
    'dashboard',
    'agenda',
    'rooster',
    'meldingen',
    'voorraad',
    'uren',
  ];

  static const Map<String, String> _operatorMenuLabels = {
    'dashboard': 'Operator Dashboard',
    'agenda': 'Mijn agenda',
    'rooster': 'Mijn rooster',
    'meldingen': 'Mijn meldingen',
    'voorraad': 'Voorraad tellen',
    'uren': 'Mijn uren',
  };

  static const int _maxMobileMenuItems = 3;
  List<String> _mobileMenuPrefs = const ['dashboard', 'agenda', 'tickets'];

  bool get _isOperator =>
      context.read<UserProvider>().roleString?.toLowerCase() == 'operator';

  List<String> get _menuKeyOrderForRole =>
      _isOperator ? _operatorMenuKeyOrder : _facilitatorMenuKeyOrder;

  Map<String, String> get _menuLabelsForRole =>
      _isOperator ? _operatorMenuLabels : _facilitatorMenuLabels;

  List<String> get _defaultPrefsForRole => _isOperator
      ? const ['dashboard', 'agenda', 'rooster']
      : const ['dashboard', 'agenda', 'tickets'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _telefoonCtrl.dispose();
    super.dispose();
  }

  String _t(dynamic v) => (v ?? '').toString().trim();

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Niet ingelogd.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await Supabase.instance.client
          .from(GebruikersTable.name)
          .select()
          .eq(GebruikersTable.id, uid)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _loading = false;
          _error = 'Geen profiel gevonden.';
        });
        return;
      }
      final m = Map<String, dynamic>.from(row as Map);
      setState(() {
        _voornaam = _t(m[GebruikersTable.voornaam]);
        _achternaam = _t(m[GebruikersTable.achternaam]);
        _email = _t(m[GebruikersTable.email]);
        _telefoonCtrl.text = _t(m[_colTelefoon]);
        final pu = _t(m[_colProfielfoto]);
        _profielfotoUrl = pu.isEmpty ? null : pu;
        final rawPrefs = m[GebruikersTable.mobielMenuVoorkeuren];
        _mobileMenuPrefs = _normalizeMobileMenuPrefs(rawPrefs);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  String get _initials {
    final a = _voornaam.isNotEmpty ? _voornaam.substring(0, 1) : '';
    final b = _achternaam.isNotEmpty ? _achternaam.substring(0, 1) : '';
    final s = ('$a$b').trim();
    if (s.isEmpty) return '?';
    return s.toUpperCase();
  }

  Future<void> _pickProfilePhoto() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final newUrl = await ImageUploadService.pickAndUploadImage(
      context,
      uid,
      storageBucket: 'profielen',
    );
    if (!mounted || newUrl == null) return;

    setState(() => _profielfotoUrl = newUrl);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Foto geladen. Druk op “Wijzigingen Opslaan” om op te slaan.',
          style: GoogleFonts.lato(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _navy.withValues(alpha: 0.92),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveProfile() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final uid = currentUser?.id;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      final trimmedPhone = _telefoonCtrl.text.trim();
      final trimmedFoto = _profielfotoUrl?.trim();
      final prefsToSave =
          _mobileMenuPrefs.take(_maxMobileMenuItems).toList(growable: false);
      final Map<String, dynamic> updates = {
        'telefoon': trimmedPhone,
        if (trimmedFoto != null && trimmedFoto.isNotEmpty)
          _colProfielfoto: trimmedFoto,
        GebruikersTable.mobielMenuVoorkeuren: prefsToSave,
      };

      await Supabase.instance.client
          .from(GebruikersTable.name)
          .update(updates)
          .eq(GebruikersTable.id, uid);

      if (!mounted) return;
      context.read<UserProvider>().setProfilePhotoUrl(_profielfotoUrl);
      context.read<UserProvider>().setMobileMenuPreferences(prefsToSave);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profiel succesvol opgeslagen!',
            style: GoogleFonts.lato(fontWeight: FontWeight.w700),
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Opslaan mislukt: $e',
            style: GoogleFonts.lato(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var obscure = true;
    var saving = false;

    Future<void> save(VoidCallback repaint) async {
      final newPassword = newCtrl.text.trim();
      final confirm = confirmCtrl.text.trim();
      if (newPassword.isEmpty || confirm.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Vul beide velden in.',
              style: GoogleFonts.lato(fontWeight: FontWeight.w700),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
        return;
      }
      if (newPassword.length < 6) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Het wachtwoord moet minimaal 6 tekens lang zijn.',
              style: GoogleFonts.lato(fontWeight: FontWeight.w700),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
        return;
      }
      if (newPassword != confirm) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'De wachtwoorden komen niet overeen.',
              style: GoogleFonts.lato(fontWeight: FontWeight.w700),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
        return;
      }

      saving = true;
      repaint();
      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: newPassword),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Wachtwoord succesvol gewijzigd.',
              style: GoogleFonts.lato(fontWeight: FontWeight.w800),
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
        newCtrl.clear();
        confirmCtrl.clear();
        if (!mounted) return;
        Navigator.of(context).pop();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Wachtwoord wijzigen mislukt: $e',
              style: GoogleFonts.lato(fontWeight: FontWeight.w700),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      } finally {
        saving = false;
        repaint();
      }
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void repaint() => setDialogState(() {});
            return AlertDialog(
              shape: const RoundedRectangleBorder(borderRadius: _radius24),
              title: Text(
                'Nieuw wachtwoord instellen',
                style: GoogleFonts.lato(fontWeight: FontWeight.w900),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: newCtrl,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'Nieuw Wachtwoord',
                        labelStyle: GoogleFonts.lato(fontWeight: FontWeight.w700),
                        suffixIcon: IconButton(
                          onPressed: saving
                              ? null
                              : () => setDialogState(() => obscure = !obscure),
                          icon: Icon(
                            obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmCtrl,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'Bevestig Wachtwoord',
                        labelStyle: GoogleFonts.lato(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: Text('Annuleren', style: GoogleFonts.lato(fontWeight: FontWeight.w800)),
                ),
                FilledButton(
                  onPressed: saving ? null : () => save(repaint),
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(borderRadius: _radius24),
                  ),
                  child: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Wachtwoord Bijwerken',
                          style: GoogleFonts.lato(fontWeight: FontWeight.w900),
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8FB),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Mijn Profiel',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            color: _navy,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SelectionArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '$_error',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(color: _muted),
                      ),
                    ),
                  )
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                        children: [
                          const SizedBox(height: 12),
                          Center(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                _buildAvatar(),
                                Positioned(
                                  right: -4,
                                  bottom: -4,
                                  child: Material(
                                    color: _blue,
                                    shape: const CircleBorder(),
                                    elevation: 2,
                                    child: IconButton(
                                      tooltip: 'Foto wijzigen',
                                      icon: const Icon(
                                        Icons.camera_alt_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      onPressed: _pickProfilePhoto,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Inloggegevens',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: _muted,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Tooltip(
                            message:
                                'Neem contact op met uw beheerder om deze inloggegevens te wijzigen.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _readOnlyBlock(label: 'Voornaam', value: _voornaam),
                                const SizedBox(height: 12),
                                _readOnlyBlock(
                                  label: 'Achternaam',
                                  value: _achternaam,
                                ),
                                const SizedBox(height: 12),
                                _readOnlyBlock(label: 'E-mail', value: _email),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Mijn Mobiele Menu',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: _muted,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _mobileMenuCard(),
                          const SizedBox(height: 28),
                          Text(
                            'Contact',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: _muted,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _telefoonCtrl,
                            keyboardType: TextInputType.phone,
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w600,
                              color: _navy,
                            ),
                            decoration: _fieldDecoration('Telefoon'),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _saving ? null : _saveProfile,
                            style: FilledButton.styleFrom(
                              backgroundColor: _blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Wijzigingen Opslaan',
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Beveiliging',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: _muted,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Wachtwoord wijzigen',
                                  style: GoogleFonts.lato(
                                    fontWeight: FontWeight.w900,
                                    color: _navy,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Stel een nieuw wachtwoord in voor uw account.',
                                  style: GoogleFonts.lato(
                                    fontWeight: FontWeight.w600,
                                    color: _muted,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _showChangePasswordDialog,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _blue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: Text(
                                    'Nieuw wachtwoord instellen',
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w900,
                                    ),
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
    );
  }

  List<String> _normalizeMobileMenuPrefs(dynamic raw) {
    final allowed = _menuKeyOrderForRole.toSet();
    final out = <String>[];
    if (raw is List) {
      for (final v in raw) {
        final s = _t(v).toLowerCase();
        if (s.isEmpty) continue;
        if (!allowed.contains(s)) continue;
        if (!out.contains(s)) out.add(s);
      }
    }
    final trimmed = out.take(_maxMobileMenuItems).toList(growable: false);
    if (trimmed.length == _maxMobileMenuItems) return trimmed;
    return _defaultPrefsForRole;
  }

  Widget _mobileMenuCard() {
    final selected = _mobileMenuPrefs.toSet();
    final remaining = _maxMobileMenuItems - selected.length;
    final keyOrder = _menuKeyOrderForRole;
    final labels = _menuLabelsForRole;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Kies maximaal $_maxMobileMenuItems items voor je snelle menu.',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w700,
              color: _navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            remaining > 0 ? 'Je kunt nog $remaining toevoegen.' : 'Maximum bereikt.',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w600,
              color: _muted,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Volgorde (sleep om te rangschikken)',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: _muted,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final next = [..._mobileMenuPrefs];
                final item = next.removeAt(oldIndex);
                next.insert(newIndex, item);
                _mobileMenuPrefs = next;
              });
            },
            children: [
              for (final key in _mobileMenuPrefs)
                ListTile(
                  key: ValueKey('sel_$key'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    labels[key] ?? key,
                    style: GoogleFonts.lato(fontWeight: FontWeight.w800),
                  ),
                  trailing: IconButton(
                    tooltip: 'Verwijderen',
                    onPressed: () {
                      setState(() {
                        _mobileMenuPrefs =
                            _mobileMenuPrefs.where((e) => e != key).toList(growable: false);
                      });
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Text(
            'Beschikbare items',
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: _muted,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          ...keyOrder.map((key) {
            final isChecked = selected.contains(key);
            final isDisabled = !isChecked && selected.length >= _maxMobileMenuItems;
            return CheckboxListTile(
              value: isChecked,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                labels[key] ?? key,
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w800,
                  color: isDisabled ? _muted : _navy,
                ),
              ),
              onChanged: (v) {
                if (v == true &&
                    !isChecked &&
                    _mobileMenuPrefs.length >= _maxMobileMenuItems) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'U kunt maximaal 3 menu-onderdelen kiezen voor de zwevende balk.',
                        style: GoogleFonts.lato(fontWeight: FontWeight.w700),
                      ),
                      backgroundColor: _navy.withValues(alpha: 0.92),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                setState(() {
                  final next = [..._mobileMenuPrefs];
                  if (v == true) {
                    if (!next.contains(key)) next.add(key);
                  } else {
                    next.removeWhere((e) => e == key);
                  }
                  _mobileMenuPrefs =
                      next.take(_maxMobileMenuItems).toList(growable: false);
                });
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final url = _profielfotoUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: 120,
          height: 120,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (c, u) => Container(
              color: Colors.grey.shade200,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (c, u, e) => _avatarFallback(),
          ),
        ),
      );
    }
    return _avatarFallback();
  }

  Widget _avatarFallback() {
    return CircleAvatar(
      radius: 60,
      backgroundColor: _blue.withValues(alpha: 0.12),
      child: _initials == '?'
          ? Icon(Icons.person_rounded, size: 56, color: _blue.withValues(alpha: 0.8))
          : Text(
              _initials,
              style: GoogleFonts.lato(
                fontWeight: FontWeight.w900,
                fontSize: 36,
                color: _blue,
              ),
            ),
    );
  }

  Widget _readOnlyBlock({required String label, required String value}) {
    final display = value.isEmpty ? '—' : value;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.lato(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            display,
            style: GoogleFonts.lato(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: _navy,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.lato(
        fontWeight: FontWeight.w700,
        color: _muted,
        fontSize: 13,
      ),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: _blue, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    );
  }
}
