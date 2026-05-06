import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_drawer.dart';
import '../../providers/user_provider.dart';
import '../../core/models/user_role.dart';
import '../../features/facilitator/screens/facilitator_dashboard_screen.dart';
import '../../features/facilitator/screens/agenda_screen.dart';
import '../../features/facilitator/screens/ticket_overview_screen.dart';
import '../../features/operator/screens/operator_dashboard_screen.dart';
import '../../features/operator/screens/operator_rooster_screen.dart';
import '../../features/operator/screens/operator_uren_screen.dart';
import '../../features/operator/screens/operator_meldingen_screen.dart';

class MobileBottomNavLayout extends StatefulWidget {
  const MobileBottomNavLayout({super.key, this.initialKey});

  final String? initialKey;

  @override
  State<MobileBottomNavLayout> createState() => _MobileBottomNavLayoutState();
}

class _MobileBottomNavLayoutState extends State<MobileBottomNavLayout> {
  int _index = 0;

  static const _facilitatorKeys = <String>[
    'dashboard',
    'agenda',
    'tickets',
  ];

  static const _operatorKeys = <String>[
    'dashboard',
    'rooster',
    'uren',
    'meldingen',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final key = (widget.initialKey ?? '').trim().toLowerCase();
    if (key.isEmpty) return;
    final role = context.read<UserProvider>().role;
    final keys = _keysForRole(role);
    final i = keys.indexOf(key);
    if (i >= 0 && i != _index) {
      _index = i;
    }
  }

  List<String> _keysForRole(UserRole? role) {
    switch (role) {
      case UserRole.operator:
        return _operatorKeys;
      case UserRole.facilitator:
      default:
        return _facilitatorKeys;
    }
  }

  ({String label, IconData icon, Widget screen}) _mapKey(String key) {
    switch (key) {
      case 'dashboard':
        final role = context.read<UserProvider>().role;
        if (role == UserRole.operator) {
          return (
            label: 'Dashboard',
            icon: Icons.dashboard_outlined,
            screen: const OperatorDashboardScreen(),
          );
        }
        return (
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          screen: const FacilitatorDashboard(),
        );
      case 'agenda':
        return (
          label: 'Mijn Agenda',
          icon: Icons.event_outlined,
          screen: const AgendaScreen(),
        );
      case 'tickets':
        return (
          label: 'Tickets',
          icon: Icons.confirmation_number_outlined,
          screen: const TicketOverviewScreen(),
        );
      case 'rooster':
        return (
          label: 'Mijn Rooster',
          icon: Icons.calendar_month_outlined,
          screen: const OperatorRoosterScreen(),
        );
      case 'uren':
        return (
          label: 'Mijn Uren',
          icon: Icons.timelapse_outlined,
          screen: const OperatorUrenScreen(),
        );
      case 'meldingen':
        return (
          label: 'Meldingen',
          icon: Icons.notifications_none_outlined,
          screen: const OperatorMeldingenScreen(),
        );
      default:
        return (
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          screen: const FacilitatorDashboard(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    final role = context.watch<UserProvider>().role;
    final keys = _keysForRole(role);

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
      bottomNavigationBar: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 32),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black.withValues(alpha: 128) // ~0.50
                      : Colors.white.withValues(alpha: 179), // ~0.70
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 51), // ~0.20
                    width: 1,
                  ),
                ),
                child: BottomNavigationBar(
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  type: BottomNavigationBarType.fixed,
                  selectedItemColor: Theme.of(context).colorScheme.primary,
                  unselectedItemColor:
                      Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 140), // ~0.55
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
      ),
    );
  }
}

