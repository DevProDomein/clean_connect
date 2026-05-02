import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class DayTasksModal extends StatelessWidget {
  const DayTasksModal({
    required this.date,
    required this.tasks,
    super.key,
  });

  final DateTime date;
  final List<dynamic> tasks;

  String _text(dynamic value) => (value ?? '').toString().trim();

  TimeOfDay _toTimeOfDay(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return const TimeOfDay(hour: 0, minute: 0);
    final hhmm = raw.length >= 5 ? raw.substring(0, 5) : raw;
    final parts = hhmm.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  String _fmtTime(dynamic value) {
    final t = _toTimeOfDay(value);
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic>? _projectJoin(Map<String, dynamic> row) {
    final joined = row['projecten'];
    if (joined is Map<String, dynamic>) return joined;
    if (joined is List && joined.isNotEmpty && joined.first is Map) {
      return Map<String, dynamic>.from(joined.first as Map);
    }
    return null;
  }

  String _projectName(Map<String, dynamic> task) {
    final fromJoin = _text(_projectJoin(task)?['project_naam']);
    return fromJoin.isEmpty ? 'Onbekend project' : fromJoin;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF111019) : Colors.white;
    final dateLabel = DateFormat('EEEE d MMMM', 'nl_NL').format(date);

    final mappedTasks = tasks
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 54,
                height: 5,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Taken op $dateLabel',
                        style: GoogleFonts.inter(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: mappedTasks.isEmpty
                    ? Center(
                        child: Text(
                          'Geen taken gevonden voor deze dag.',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                        itemCount: mappedTasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final task = mappedTasks[index];
                          final title = _projectName(task);
                          final subtitle =
                              '${_fmtTime(task['tijdslot_start'])} - ${_fmtTime(task['tijdslot_eind'])}';
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.of(context).pop(task),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: cs.primary.withValues(alpha: 0.16)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitle,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurface.withValues(alpha: 0.70),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
