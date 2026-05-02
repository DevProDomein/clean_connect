import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user_role.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/supabase_client.dart';
import '../../../providers/user_provider.dart';
import '../widgets/opname_afspraak_form_sheet.dart';
import '../widgets/opname_edit_modal.dart';

/// Facilitator Sales Centre: leads (Zapier mail hand-offs) and survey appointments.
class SalesCentreScreen extends StatefulWidget {
  const SalesCentreScreen({super.key});

  @override
  State<SalesCentreScreen> createState() => _SalesCentreScreenState();
}

class _SalesCentreScreenState extends State<SalesCentreScreen>
    with SingleTickerProviderStateMixin {
  static const double _radius = 24;
  static const Color _navy = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _pageBg = Color(0xFFF7F8FB);
  static const Color _blue = Color(0xFF2563EB);
  static const Color _green = Color(0xFF16A34A);
  static const Color _orange = Color(0xFFFF6B35);
  static const List<String> _nlMonth3 = [
    'JAN',
    'FEB',
    'MRT',
    'APR',
    'MEI',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OKT',
    'NOV',
    'DEC',
  ];

  static const List<String> _regioOptions = [
    'Amsterdam',
    "'t Gooi",
    'Stichtse Vecht',
    'Utrecht',
    'Amersfoort',
    'De Ronde Venen',
    'Wijdemeren',
  ];

  static const List<String> _campagneTypeChoices = [
    'Standaard Sales',
    'Nieuwe Buren',
  ];

  late TabController _tabController;
  int _tabIndex = 0;

  List<Map<String, dynamic>> _leads = const [];
  bool _leadsLoading = true;
  Object? _leadsError;

  List<Map<String, dynamic>> _afspraken = const [];
  bool _afsprakenLoading = true;
  Object? _afsprakenError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabIndex = 0;
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLeads();
      _loadAfspraken();
    });
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() => _tabIndex = _tabController.index);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  bool _canAccess() {
    final up = context.read<UserProvider>();
    if (up.isGenerator) return true;
    return up.role == UserRole.administrator || up.role == UserRole.facilitator;
  }

  Future<void> _loadLeads() async {
    if (!_canAccess() || !mounted) return;
    if (mounted) {
      setState(() {
        _leadsLoading = true;
        _leadsError = null;
      });
    }
    try {
      final res = await AppSupabase.client
          .from('leads')
          .select()
          .order('aangemaakt_op', ascending: false);
      if (!mounted) return;
      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) {
        setState(() {
          _leads = list;
          _leadsLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _leadsError = e;
        _leads = const [];
        _leadsLoading = false;
      });
    }
  }

  Future<void> _loadAfspraken() async {
    if (!_canAccess() || !mounted) return;
    if (mounted) {
      setState(() {
        _afsprakenLoading = true;
        _afsprakenError = null;
      });
    }
    try {
      final res = await AppSupabase.client
          .from('opname_afspraken')
          .select()
          .eq('status', 'gepland')
          .order('geplande_datum', ascending: true)
          .order('tijdslot_start', ascending: true);
      if (!mounted) return;
      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) {
        setState(() {
          _afspraken = list;
          _afsprakenLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _afsprakenError = e;
        _afspraken = const [];
        _afsprakenLoading = false;
      });
    }
  }

  DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  /// True when the last send was at least 7 full 24h periods ago (robust for Zapier / DB UTC).
  bool _needsOpvolg(Map<String, dynamic> row) {
    if (_t(row['campagne_status']) != 'first_email_send') return false;
    final last = _parseDt(row['laatste_mail_verzonden_op']);
    if (last == null) return false;
    final start = last.isUtc ? last : last.toUtc();
    final now = DateTime.now().toUtc();
    return now.difference(start) >= const Duration(days: 7);
  }

  String _t(dynamic v) => (v?.toString() ?? '').trim().toLowerCase();

  (String, Color) _statusPill(String? status) {
    final s = (status ?? 'concept').trim().toLowerCase();
    switch (s) {
      case 'first_email_send':
        return ('1e Mail Verzonden', _blue);
      case 'opvolging_send':
        return ('Opvolging Verzonden', _green);
      case 'concept':
      default:
        if (s.isEmpty || s == 'concept') {
          return ('Concept', const Color(0xFF6B7280));
        }
        return (_humanStatus(s), const Color(0xFF6B7280));
    }
  }

  String _humanStatus(String s) {
    return s.replaceAll('_', ' ').split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }

  InputDecoration _fieldDec(String? hint, {String? label}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
    );
  }

  Future<void> _startCampagne(
    String leadId,
    String campagneType,
  ) async {
    HapticFeedback.lightImpact();
    try {
      await AppSupabase.client.from('leads').update({
        'campagne_type': campagneType,
        'campagne_status': 'first_email_send',
        'laatste_mail_verzonden_op': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', leadId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lead klaargezet voor Zapier verzending!',
            style: GoogleFonts.lato(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadLeads();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opslaan mislukt: $e',
              style: GoogleFonts.lato()),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  Future<void> _sendOpvolging(String leadId) async {
    HapticFeedback.heavyImpact();
    try {
      await AppSupabase.client.from('leads').update({
        'campagne_type': 'opvolging',
        'campagne_status': 'opvolging_send',
        'laatste_mail_verzonden_op': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', leadId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Opvolging klaargezet voor Zapier verzending!',
            style: GoogleFonts.lato(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadLeads();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opvolging mislukt: $e',
              style: GoogleFonts.lato()),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  void _openCampagneDialog(Map<String, dynamic> lead) {
    String selected = _campagneTypeChoices.first;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
          title: Text(
            'Campagne kiezen',
            style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          content: StatefulBuilder(
            builder: (context, setLocal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Kies welke mailflow via Zapier wordt getriggerd.',
                    style: GoogleFonts.lato(
                      color: _muted,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._campagneTypeChoices.map(
                    (c) {
                      final isOn = c == selected;
                      return ListTile(
                        onTap: () => setLocal(() => selected = c),
                        selected: isOn,
                        selectedTileColor: _orange.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: Icon(
                          isOn
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: isOn ? _orange : _muted,
                        ),
                        title: Text(c, style: GoogleFonts.lato()),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Annuleer', style: GoogleFonts.lato()),
            ),
            FilledButton(
              onPressed: () {
                final id = lead['id']?.toString() ?? '';
                if (id.isEmpty) {
                  Navigator.of(ctx).pop();
                  return;
                }
                Navigator.of(ctx).pop();
                _startCampagne(id, selected);
              },
              child: Text('Bevestig', style: GoogleFonts.lato()),
            ),
          ],
        );
      },
    );
  }

  void _openNewLeadDialog() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final bed = TextEditingController();
    final adres = TextEditingController();
    final email = TextEditingController();
    final tel = TextEditingController();
    String? regio = _regioOptions.first;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
          title: Text(
            'Nieuwe lead',
            style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setLocal) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: bed,
                        decoration: _fieldDec(null, label: 'Bedrijf'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: adres,
                        decoration: _fieldDec(null, label: 'Adres'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: regio,
                        decoration: _fieldDec(null, label: 'Regio'),
                        items: _regioOptions
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Text(r, style: GoogleFonts.lato()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setLocal(() => regio = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _fieldDec(null, label: 'E-mail'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tel,
                        keyboardType: TextInputType.phone,
                        decoration: _fieldDec(null, label: 'Telefoon'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                bed.dispose();
                adres.dispose();
                email.dispose();
                tel.dispose();
              },
              child: Text('Annuleer', style: GoogleFonts.lato()),
            ),
            FilledButton(
              onPressed: () async {
                if (bed.text.trim().isEmpty || email.text.trim().isEmpty) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Bedrijf en e-mail zijn verplicht.',
                          style: GoogleFonts.lato()),
                    ),
                  );
                  return;
                }
                final payload = {
                  'bedrijfsnaam': bed.text.trim(),
                  'email': email.text.trim(),
                  'adres_stad': adres.text.trim(),
                  'werk_regio': regio ?? _regioOptions.first,
                  'telefoon': tel.text.trim(),
                  'campagne_status': 'concept',
                };
                Navigator.of(ctx).pop();
                bed.dispose();
                adres.dispose();
                email.dispose();
                tel.dispose();
                try {
                  await AppSupabase.client.from('leads').insert(payload);
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content:
                            Text('Fout: $e', style: GoogleFonts.lato()),
                        backgroundColor: Colors.red.shade800,
                      ),
                    );
                  }
                  return;
                }
                if (mounted) {
                  await _loadLeads();
                }
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Lead aangemaakt.',
                          style: GoogleFonts.lato(
                              fontWeight: FontWeight.w600)),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: Text('Opslaan', style: GoogleFonts.lato()),
            ),
          ],
        );
      },
    );
  }

  void _openNewAfspraakSheet() {
    OpnameAfspraakFormSheet.show(
      context,
      onSuccess: () async {
        if (mounted) {
          await _loadAfspraken();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canAccess()) {
      return Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text('Sales Centre',
              style: GoogleFonts.lato(fontWeight: FontWeight.w900)),
        ),
        body: Center(
          child: Text(
            'Geen toegang tot het Sales Centre.',
            style: GoogleFonts.lato(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _pageBg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: _navy),
        title: Text(
          'Sales Centre',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: _navy,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _navy,
          unselectedLabelColor: _muted,
          indicatorColor: _orange,
          labelStyle: GoogleFonts.lato(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
          unselectedLabelStyle: GoogleFonts.lato(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'Leads & Campagnes'),
            Tab(text: 'Opname Afspraken'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLeadsBody(),
          _buildAfsprakenBody(),
        ],
      ),
      floatingActionButton: _tabIndex == 0
          ? _fab(
              onPressed: _openNewLeadDialog,
              label: '+ Nieuwe Lead',
              icon: Icons.person_add_alt_1_outlined,
            )
          : _fab(
              onPressed: _openNewAfspraakSheet,
              label: '+ Nieuwe Afspraak',
              icon: Icons.add_alert_outlined,
            ),
    );
  }

  Widget _fab({
    required VoidCallback onPressed,
    required String label,
    required IconData icon,
  }) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      backgroundColor: _orange,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      icon: Icon(icon, size: 24),
      label: Text(
        label,
        style: GoogleFonts.lato(fontWeight: FontWeight.w900, fontSize: 15),
      ),
    );
  }

  Widget _buildLeadsBody() {
    if (_leadsLoading) {
      return const Center(
        child: CupertinoActivityIndicator(radius: 16),
      );
    }
    if (_leadsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Laden mislukt: $_leadsError',
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(color: _muted, fontSize: 15),
          ),
        ),
      );
    }
    if (_leads.isEmpty) {
      return Center(
        child: Text(
          'Nog geen leads.',
          style: GoogleFonts.lato(
            color: _muted,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: _orange,
      onRefresh: _loadLeads,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        itemCount: _leads.length,
        separatorBuilder: (context, index) {
          return const SizedBox(height: 14);
        },
        itemBuilder: (context, i) {
          final lead = _leads[i];
          final (label, color) = _statusPill(lead['campagne_status']?.toString());
          final showOpvolg = _needsOpvolg(lead);
          return _leadCard(
            lead: lead,
            statusLabel: label,
            statusColor: color,
            showOpvolg: showOpvolg,
          );
        },
      ),
    );
  }

  Widget _leadCard({
    required Map<String, dynamic> lead,
    required String statusLabel,
    required Color statusColor,
    required bool showOpvolg,
  }) {
    final id = lead['id']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(18),
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
        border: showOpvolg
            ? Border.all(
                color: _orange.withValues(alpha: 0.5),
                width: 1.4,
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  (lead['bedrijfsnaam'] ?? '—').toString(),
                  style: GoogleFonts.lato(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: _navy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.lato(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            (lead['email'] ?? '—').toString(),
            style: GoogleFonts.lato(
              color: _muted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            [
              (lead['adres_stad'] ?? '').toString().trim(),
              (lead['werk_regio'] ?? '').toString().trim(),
            ].where((e) => e.isNotEmpty).join(' · ').trim(),
            style: GoogleFonts.lato(
              color: _muted,
              fontSize: 13,
            ),
          ),
          if (showOpvolg) ...[
            const SizedBox(height: 14),
            _OpvolgButton(
              onPressed: id.isEmpty ? null : () => _sendOpvolging(id),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: id.isEmpty ? null : () => _openCampagneDialog(lead),
              child: Text(
                'Start Campagne',
                style: GoogleFonts.lato(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timeDisplay(dynamic v) {
    if (v == null) return '—';
    final s = v.toString();
    if (s.length >= 5 && s.contains(':')) {
      return s.substring(0, 5);
    }
    return s;
  }

  Widget _buildAfsprakenBody() {
    if (_afsprakenLoading) {
      return const Center(
        child: CupertinoActivityIndicator(radius: 16),
      );
    }
    if (_afsprakenError != null) {
      return Center(
        child: Text(
          'Laden mislukt: $_afsprakenError',
          style: GoogleFonts.lato(color: _muted),
        ),
      );
    }
    if (_afspraken.isEmpty) {
      return Center(
        child: Text(
          'Geen geplande opname afspraken.',
          style: GoogleFonts.lato(
            color: _muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: _orange,
      onRefresh: _loadAfspraken,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        itemCount: _afspraken.length,
        separatorBuilder: (context, index) {
          return const SizedBox(height: 14);
        },
        itemBuilder: (context, i) {
          final row = _afspraken[i];
          final d = _parseDt(row['geplande_datum']);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(_radius),
              onTap: () {
                final id = row['id']?.toString() ?? '';
                if (id.isEmpty) {
                  return;
                }
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => OpnameEditModal(
                    afspraakId: id,
                    onSaved: () {
                      if (mounted) {
                        _loadAfspraken();
                      }
                    },
                  ),
                );
              },
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 70,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        d == null ? '—' : DateFormat('dd').format(d),
                        style: GoogleFonts.lato(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        d == null ? '' : _nlMonth3[d.month - 1],
                        style: GoogleFonts.lato(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (row['bedrijfsnaam'] ?? '—').toString(),
                        style: GoogleFonts.lato(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: _muted,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              (row['adres_volledig'] ?? '—').toString(),
                              style: GoogleFonts.lato(
                                color: _muted,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (row['contactpersoon'] ?? '—').toString(),
                        style: GoogleFonts.lato(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        (row['telefoon'] ?? '—').toString(),
                        style: GoogleFonts.lato(
                          fontSize: 13,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _timeDisplay(row['tijdslot_start']),
                      style: GoogleFonts.lato(
                        color: _orange,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _timeDisplay(row['tijdslot_eind']),
                      style: GoogleFonts.lato(
                        color: _orange,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );
  }
}

class _OpvolgButton extends StatefulWidget {
  const _OpvolgButton({this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<_OpvolgButton> createState() => _OpvolgButtonState();
}

class _OpvolgButtonState extends State<_OpvolgButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final w = math.sin(_c.value * 2 * math.pi) * 2.0;
        return Transform.translate(
          offset: Offset(w, 0),
          child: child,
        );
      },
      child: FilledButton(
        onPressed: widget.onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFEA580C),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          '🚨 Stuur Opvolging',
          textAlign: TextAlign.center,
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
