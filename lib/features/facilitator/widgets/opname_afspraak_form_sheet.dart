import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_client.dart';

/// Bottom sheet to plan a new [opname_afspraken] record (shared by Sales Centre & agenda).
class OpnameAfspraakFormSheet {
  static const double radius = 24;
  static const Color navy = Color(0xFF0F172A);

  static const List<String> regioOptions = [
    'Amsterdam',
    "'t Gooi",
    'Stichtse Vecht',
    'Utrecht',
    'Amersfoort',
    'De Ronde Venen',
    'Wijdemeren',
  ];

  static InputDecoration _fieldDec(String? hint, {String? label}) {
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

  /// Shows the form; on success, calls [onSuccess] (e.g. refresh parent lists).
  static Future<void> show(
    BuildContext context, {
    required Future<void> Function() onSuccess,
  }) async {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final bed = TextEditingController();
    final contact = TextEditingController();
    final email = TextEditingController();
    final tel = TextEditingController();
    final adres = TextEditingController();
    String? regio = regioOptions.first;
    DateTime? dag = DateTime.now();
    var start = const TimeOfDay(hour: 9, minute: 0);
    var end = const TimeOfDay(hour: 10, minute: 0);

    void disposeCtrls() {
      bed.dispose();
      contact.dispose();
      email.dispose();
      tel.dispose();
      adres.dispose();
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SelectionArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.88,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(radius),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 20,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 16,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                  ),
                  child: StatefulBuilder(
                    builder: (context, setLocal) {
                      Future<void> pickDate() async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: dag ?? DateTime.now(),
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2040),
                        );
                        if (d != null) {
                          setLocal(() => dag = d);
                        }
                      }
 
                      Future<void> pickStart() async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: start,
                        );
                        if (t != null) {
                          setLocal(() => start = t);
                        }
                      }
 
                      Future<void> pickEnd() async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: end,
                        );
                        if (t != null) {
                          setLocal(() => end = t);
                        }
                      }
 
                      return ListView(
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
                            'Nieuwe opname afspraak',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: bed,
                            decoration: _fieldDec(null, label: 'Bedrijfsnaam'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: contact,
                            decoration: _fieldDec(null, label: 'Contactpersoon'),
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
                            items: regioOptions
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
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Datum', style: GoogleFonts.lato()),
                            subtitle: Text(
                              dag == null
                                  ? '—'
                                  : DateFormat('dd MMM yyyy').format(dag!),
                              style: GoogleFonts.lato(
                                fontWeight: FontWeight.w800,
                                color: navy,
                              ),
                            ),
                            trailing: const Icon(Icons.calendar_today_outlined),
                            onTap: pickDate,
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
                                    start.format(context),
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w800,
                                      color: navy,
                                    ),
                                  ),
                                  onTap: pickStart,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: Colors.black.withValues(alpha: 0.08),
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
                                    end.format(context),
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w800,
                                      color: navy,
                                    ),
                                  ),
                                  onTap: pickEnd,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: Colors.black.withValues(alpha: 0.08),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () async {
                              if (bed.text.trim().isEmpty) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Bedrijfsnaam is verplicht.',
                                      style: GoogleFonts.lato(),
                                    ),
                                  ),
                                );
                                return;
                              }
                              if (dag == null) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Kies een datum.',
                                      style: GoogleFonts.lato(),
                                    ),
                                  ),
                                );
                                return;
                              }
                              String tStr(TimeOfDay t) =>
                                  '${t.hour.toString().padLeft(2, '0')}:'
                                  '${t.minute.toString().padLeft(2, '0')}:00';
                              final payload = {
                                'bedrijfsnaam': bed.text.trim(),
                                'contactpersoon': contact.text.trim(),
                                'email': email.text.trim(),
                                'telefoon': tel.text.trim(),
                                'adres_volledig': adres.text.trim(),
                                'werk_regio': regio ?? regioOptions.first,
                                'geplande_datum': DateFormat('yyyy-MM-dd')
                                    .format(dag!),
                                'tijdslot_start': tStr(start),
                                'tijdslot_eind': tStr(end),
                                'status': 'gepland',
                              };
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              disposeCtrls();
                              try {
                                await AppSupabase.client
                                    .from('opname_afspraken')
                                    .insert(payload);
                              } catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Fout: $e',
                                      style: GoogleFonts.lato(),
                                    ),
                                    backgroundColor: Colors.red.shade800,
                                  ),
                                );
                                return;
                              }
                              await onSuccess();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Afspraak aangemaakt.',
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                              child: Text(
                                'Afspraak plannen',
                                style: GoogleFonts.lato(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
