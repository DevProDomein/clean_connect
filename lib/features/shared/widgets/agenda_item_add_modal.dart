import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/contracts/supabase_v1_contract.dart';
import '../../../core/supabase_client.dart';

/// Bottomsheet-modal: nieuw [agenda_items]-record + optioneel [agenda_deelnemers].
class AgendaItemAddModal extends StatefulWidget {
  const AgendaItemAddModal({super.key});

  /// Toont de modal; retourneert `true` bij succes (voor refresh).
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AgendaItemAddModal(),
    );
  }

  @override
  State<AgendaItemAddModal> createState() => _AgendaItemAddModalState();
}

class _AgendaItemAddModalState extends State<AgendaItemAddModal> {
  final _formKey = GlobalKey<FormState>();
  final _titelCtrl = TextEditingController();
  final _beschrijvingCtrl = TextEditingController();

  String _type = 'meeting';
  DateTime _datum = DateTime.now();
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _eind = const TimeOfDay(hour: 10, minute: 0);

  bool _loadingUsers = true;
  bool _saving = false;
  Object? _error;
  List<Map<String, dynamic>> _gebruikers = const [];
  final Set<String> _gekozenDeelnemerIds = {};

  @override
  void initState() {
    super.initState();
    _loadGebruikers();
  }

  @override
  void dispose() {
    _titelCtrl.dispose();
    _beschrijvingCtrl.dispose();
    super.dispose();
  }

  String _t(dynamic v) => (v ?? '').toString().trim();

  String _naamUitGebruiker(Map<String, dynamic> u) {
    final vn = _t(u[GebruikersTable.voornaam]);
    final an = _t(u[GebruikersTable.achternaam]);
    final combined = '$vn $an'.trim();
    if (combined.isNotEmpty) return combined;
    return _t(u[GebruikersTable.email]).isEmpty ? 'Gebruiker' : _t(u[GebruikersTable.email]);
  }

  Future<void> _loadGebruikers() async {
    setState(() {
      _loadingUsers = true;
      _error = null;
    });
    try {
      final res = await AppSupabase.client
          .from(GebruikersTable.name)
          .select(
            '${GebruikersTable.id}, ${GebruikersTable.voornaam}, '
            '${GebruikersTable.achternaam}, ${GebruikersTable.email}',
          )
          .order(GebruikersTable.voornaam);

      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _gebruikers = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  String _tijdDb(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  String _datumDb(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _pickDatum() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _datum,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null && mounted) {
      setState(() => _datum = picked);
    }
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(context: context, initialTime: _start);
    if (picked != null && mounted) setState(() => _start = picked);
  }

  Future<void> _pickEind() async {
    final picked = await showTimePicker(context: context, initialTime: _eind);
    if (picked != null && mounted) setState(() => _eind = picked);
  }

  Future<void> _opslaan() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _error = 'Niet ingelogd.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final titel = _t(_titelCtrl.text);
      final beschrijving = _t(_beschrijvingCtrl.text);
      final deelnemers = _gekozenDeelnemerIds
          .where((id) => id.isNotEmpty && id != uid)
          .toList(growable: false);

      final inserted = await AppSupabase.client
          .from('agenda_items')
          .insert({
            'maker_id': uid,
            'titel': titel,
            'type': _type,
            'datum': _datumDb(_datum),
            'starttijd': _tijdDb(_start),
            'eindtijd': _tijdDb(_eind),
            'beschrijving': beschrijving,
          })
          .select('id')
          .single();

      final id = _t(inserted['id']);
      if (id.isEmpty) throw Exception('Geen id na insert.');

      if (deelnemers.isNotEmpty) {
        final rows = deelnemers
            .map(
              (gid) => <String, dynamic>{
                'item_id': id,
                'gebruiker_id': gid,
                'status': 'uitgenodigd',
              },
            )
            .toList(growable: false);
        await AppSupabase.client.from('agenda_deelnemers').insert(rows);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final uid = Supabase.instance.client.auth.currentUser?.id;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottom),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Agenda-item toevoegen',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _titelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Titel',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      _t(v).isEmpty ? 'Vul een titel in.' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: ValueKey(_type),
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'meeting', child: Text('Meeting')),
                    DropdownMenuItem(value: 'taak', child: Text('Taak')),
                    DropdownMenuItem(value: 'notitie', child: Text('Notitie')),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() => _type = v);
                        },
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Datum',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(DateFormat('dd-MM-yyyy').format(_datum)),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today_rounded),
                    onPressed: _saving ? null : _pickDatum,
                  ),
                  onTap: _saving ? null : _pickDatum,
                ),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Start',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        subtitle: Text(_start.format(context)),
                        onTap: _saving ? null : _pickStart,
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Einde',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        subtitle: Text(_eind.format(context)),
                        onTap: _saving ? null : _pickEind,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _beschrijvingCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Beschrijving',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Deelnemers uitnodigen',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                if (_loadingUsers)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_gebruikers.isEmpty)
                  Text(
                    'Geen gebruikers geladen.',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: cs.error,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _gebruikers.map((u) {
                      final id = _t(u[GebruikersTable.id]);
                      if (id.isEmpty || id == uid) return const SizedBox.shrink();
                      final selected = _gekozenDeelnemerIds.contains(id);
                      return FilterChip(
                        label: Text(
                          _naamUitGebruiker(u),
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                        selected: selected,
                        onSelected: _saving
                            ? null
                            : (v) {
                                setState(() {
                                  if (v) {
                                    _gekozenDeelnemerIds.add(id);
                                  } else {
                                    _gekozenDeelnemerIds.remove(id);
                                  }
                                });
                              },
                      );
                    }).toList(),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '$_error',
                    style: GoogleFonts.inter(
                      color: cs.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _saving ? null : _opslaan,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Opslaan',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
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
