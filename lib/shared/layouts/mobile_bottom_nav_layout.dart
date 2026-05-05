import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_drawer.dart';
import '../../providers/user_provider.dart';
import '../../features/facilitator/screens/facilitator_dashboard_screen.dart';
import '../../features/facilitator/screens/agenda_screen.dart';
import '../../features/facilitator/screens/ticket_overview_screen.dart';
import '../../features/facilitator/screens/planbord_screen.dart';
import '../../features/facilitator/screens/relations_crm_screen.dart'
    as facilitator_crm;
import '../../features/facilitator/screens/quote_overview_screen.dart';

class MobileBottomNavLayout extends StatefulWidget {
  const MobileBottomNavLayout({super.key, this.initialKey});

  final String? initialKey;

  @override
  State<MobileBottomNavLayout> createState() => _MobileBottomNavLayoutState();
}

class _MobileBottomNavLayoutState extends State<MobileBottomNavLayout> {
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final key = (widget.initialKey ?? '').trim().toLowerCase();
    if (key.isEmpty) return;
    final prefs = context.read<UserProvider>().mobileMenuPreferences;
    final i = prefs.indexOf(key);
    if (i >= 0 && i != _index) {
      _index = i;
    }
  }

  static const _fallbackPrefs = <String>[
    'dashboard',
    'agenda',
    'tickets',
    'crm',
  ];

  ({String label, IconData icon, Widget screen}) _mapKey(String key) {
    switch (key) {
      case 'dashboard':
        return (label: 'Dashboard', icon: Icons.dashboard_outlined, screen: const FacilitatorDashboard());
      case 'agenda':
        return (label: 'Agenda', icon: Icons.event_note_outlined, screen: const AgendaScreen());
      case 'tickets':
        return (label: 'Tickets', icon: Icons.confirmation_number_outlined, screen: const TicketOverviewScreen());
      case 'planbord':
        return (label: 'Planbord', icon: Icons.view_kanban_outlined, screen: const PlanbordScreen());
      case 'crm':
        return (label: 'CRM', icon: Icons.groups_2_outlined, screen: const facilitator_crm.RelationsCrmScreen());
      case 'offertes':
        return (label: 'Offertes', icon: Icons.request_quote_outlined, screen: const QuoteOverviewScreen());
      default:
        return (label: 'Dashboard', icon: Icons.dashboard_outlined, screen: const FacilitatorDashboard());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    final prefs = context.watch<UserProvider>().mobileMenuPreferences;
    final keys = (prefs.length == 4 ? prefs : _fallbackPrefs)
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final mapped = keys.map(_mapKey).toList(growable: false);
    final safeIndex = (_index >= 0 && _index < mapped.length) ? _index : 0;

    final body = IndexedStack(
      index: safeIndex,
      children: mapped.map((m) => m.screen).toList(growable: false),
    );

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            const SizedBox(
              width: 280,
              child: AppDrawerPanel(
                child: AppDrawerContent(),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      drawer: const AppDrawer(),
      body: body,
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: SafeArea(
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BottomNavigationBar(
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black.withValues(alpha: 0.60)
                    : Colors.white.withValues(alpha: 0.82),
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: Colors.blueAccent,
                unselectedItemColor: Colors.grey.shade500,
                currentIndex: safeIndex,
                onTap: (i) => setState(() => _index = i),
                items: [
                  for (final it in mapped)
                    BottomNavigationBarItem(
                      icon: Icon(it.icon),
                      label: it.label,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

