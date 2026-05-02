import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_client.dart';
import 'opname_afspraak_form_sheet.dart';

/// Edit an existing [opname_afspraken] row in an Apple-style bottom sheet.
class OpnameEditModal extends StatefulWidget {
  const OpnameEditModal({
    super.key,
    required this.afspraakId,
    required this.onSaved,
  });

  final String afspraakId;
  final VoidCallback onSaved;

  @override
  State<OpnameEditModal> createState() => _OpnameEditModalState();
}

class _OpnameEditModalState extends State<OpnameEditModal> {
  static const double _radius = 24;
  static const Color _navy = Color(0xFF0F172A);

  final _bed = TextEditingController();
  final _contact = TextEditingController();
  final _email = TextEditingController();
  final _telefoon = TextEditingController();
  final _adres = TextEditingController();
  final _notities = TextEditingController();

  String? _werkRegio;
  String? _status;
  DateTime? _geplandeDatum;
  TimeOfDay _tijdStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _tijdEind = const TimeOfDay(hour: 10, minute: 0);

  bool _loading = true;
  String? _loadError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _werkRegio = OpnameAfspraakFormSheet.regioOptions.first;
    _status = 'gepland';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  @override
  void dispose() {
    _bed.dispose();
    _contact.dispose();
    _email.dispose();
    _telefoon.dispose();
    _adres.dispose();
    _notities.dispose();
    super.dispose();
  }

  InputDecoration _fieldDec(String? label) {
    return InputDecoration(
      labelText: label,
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

  static TimeOfDay? _parseTimeOfDay(dynamic v) {
    if (v == null) {
      return null;
    }
    final s = v.toString().trim();
    if (s.length >= 5 && s.contains(':')) {
      final p = s.split(':');
      final h = int.tryParse(p[0]) ?? 0;
      final m = int.tryParse(p[1]) ?? 0;
      return TimeOfDay(hour: h, minute: m);
    }
    return null;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) {
      return null;
    }
    if (v is DateTime) {
      return v;
    }
    return DateTime.tryParse(v.toString());
  }

  String _t(dynamic v) => (v ?? '').toString().trim();

  static const _statusOptions = <String>[
    'gepland',
    'voltooid',
    'geannuleerd',
    'no_show',
  ];

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await AppSupabase.client
          .from('opname_afspraken')
          .select()
          .eq('id', widget.afspraakId)
          .maybeSingle();
      if (res == null) {
        if (mounted) {
          setState(() {
            _loadError = 'Afspraak niet gevonden.';
            _loading = false;
          });
        }
        return;
      }
      final row = Map<String, dynamic>.from(res);
      if (!mounted) {
        return;
      }
      setState(() {
        _bed.text = _t(row['bedrijfsnaam']);
        _contact.text = _t(row['contactpersoon']);
        _email.text = _t(row['email']);
        _telefoon.text = _t(row['telefoon']);
        _adres.text = _t(row['adres_volledig']);
        _notities.text = _t(row['notities']);
        final r = _t(row['werk_regio']);
        _werkRegio = OpnameAfspraakFormSheet.regioOptions.contains(r)
            ? r
            : OpnameAfspraakFormSheet.regioOptions.first;
        final st = _t(row['status']).toLowerCase();
        _status = _statusOptions.contains(st) ? st : 'gepland';
        _geplandeDatum = _parseDate(row['geplande_datum']) ?? DateTime.now();
        _tijdStart = _parseTimeOfDay(row['tijdslot_start']) ??
            const TimeOfDay(hour: 9, minute: 0);
        _tijdEind = _parseTimeOfDay(row['tijdslot_eind']) ??
            const TimeOfDay(hour: 10, minute: 0);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _timeStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:00';

  String _dateStr(DateTime? d) {
    if (d == null) {
      return '—';
    }
    return DateFormat('dd MMM yyyy').format(d);
  }

  Future<void> _save() async {
    if (!mounted) {
      return;
    }
    if (_geplandeDatum == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kies een datum.', style: GoogleFonts.lato()),
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final payload = <String, dynamic>{
        'bedrijfsnaam': _bed.text.trim(),
        'contactpersoon': _contact.text.trim(),
        'email': _email.text.trim(),
        'telefoon': _telefoon.text.trim(),
        'adres_volledig': _adres.text.trim(),
        'notities': _notities.text.trim(),
        'werk_regio': _werkRegio ?? OpnameAfspraakFormSheet.regioOptions.first,
        'status': _status ?? 'gepland',
        'geplande_datum': DateFormat('yyyy-MM-dd').format(_geplandeDatum!),
        'tijdslot_start': _timeStr(_tijdStart),
        'tijdslot_eind': _timeStr(_tijdEind),
      };
      await AppSupabase.client
          .from('opname_afspraken')
          .update(payload)
          .eq('id', widget.afspraakId);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Opname succesvol bijgewerkt',
            style: GoogleFonts.lato(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Opslaan mislukt: $e', style: GoogleFonts.lato()),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(_radius),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lato(
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  : Padding(
                      padding: EdgeInsets.only(
                        left: 20,
                        right: 20,
                        top: 12,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                      ),
                      child: ListView(
                        controller: scrollController,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          Text(
                            'Opname bewerken',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              color: _navy,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _bed,
                            decoration: _fieldDec('Bedrijfsnaam'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _contact,
                            decoration: _fieldDec('Contactpersoon'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _fieldDec('E-mail'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _telefoon,
                            keyboardType: TextInputType.phone,
                            decoration: _fieldDec('Telefoon'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _adres,
                            maxLines: 2,
                            decoration: _fieldDec('Adres (volledig)'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _notities,
                            maxLines: 3,
                            decoration: _fieldDec('Notities'),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: _werkRegio,
                            decoration: _fieldDec('Werk regio'),
                            items: OpnameAfspraakFormSheet.regioOptions
                                .map(
                                  (r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(r, style: GoogleFonts.lato()),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _werkRegio = v);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: _status,
                            decoration: _fieldDec('Status'),
                            items: _statusOptions
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s, style: GoogleFonts.lato()),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _status = v);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Geplande datum', style: GoogleFonts.lato()),
                            subtitle: Text(
                              _dateStr(_geplandeDatum),
                              style: GoogleFonts.lato(
                                fontWeight: FontWeight.w800,
                                color: _navy,
                              ),
                            ),
                            trailing: const Icon(Icons.calendar_today_outlined),
                            onTap: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _geplandeDatum ?? DateTime.now(),
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2040),
                              );
                              if (d != null) {
                                setState(() => _geplandeDatum = d);
                              }
                            },
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 0,
                                  ),
                                  title: Text('Start', style: GoogleFonts.lato()),
                                  subtitle: Text(
                                    _tijdStart.format(context),
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w800,
                                      color: _navy,
                                    ),
                                  ),
                                  onTap: () async {
                                    final t = await showTimePicker(
                                      context: context,
                                      initialTime: _tijdStart,
                                    );
                                    if (t != null) {
                                      setState(() => _tijdStart = t);
                                    }
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: Colors.black
                                          .withValues(alpha: 0.08),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 0,
                                  ),
                                  title: Text('Eind', style: GoogleFonts.lato()),
                                  subtitle: Text(
                                    _tijdEind.format(context),
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w800,
                                      color: _navy,
                                    ),
                                  ),
                                  onTap: () async {
                                    final t = await showTimePicker(
                                      context: context,
                                      initialTime: _tijdEind,
                                    );
                                    if (t != null) {
                                      setState(() => _tijdEind = t);
                                    }
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: Colors.black
                                          .withValues(alpha: 0.08),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
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
                                      'Opslaan & Sluiten',
                                      style: GoogleFonts.lato(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
        );
      },
    );
  }
}
