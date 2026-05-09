import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_drawer.dart';
import '../../providers/user_provider.dart';
import '../../core/models/user_role.dart';
import '../../features/facilitator/screens/facilitator_dashboard_screen.dart';
import '../../features/facilitator/screens/agenda_screen.dart';
import '../../features/facilitator/screens/planbord_screen.dart';
import '../../features/facilitator/screens/planning_agenda_screen.dart';
import '../../features/facilitator/screens/dks_dashboard_screen.dart';
import '../../features/facilitator/screens/project_overview_screen.dart';
import '../../features/facilitator/screens/contract_management_screen.dart';
import '../../features/facilitator/screens/quote_overview_screen.dart';
import '../../features/facilitator/screens/sales_centre_screen.dart';
import '../../features/facilitator/screens/relations_crm_screen.dart'
    as facilitator_crm;
import '../../features/facilitator/screens/ticket_overview_screen.dart';
import '../../features/operator/screens/operator_dashboard_screen.dart';
import '../../features/operator/screens/operator_agenda_screen.dart';
import '../../features/operator/screens/operator_rooster_screen.dart';
import '../../features/operator/screens/operator_uren_screen.dart';
import '../../features/operator/screens/operator_meldingen_screen.dart';
import '../../features/operator/screens/operator_voorraad_screen.dart';
import '../../features/shared/screens/profile_screen.dart';

class MobileBottomNavLayout extends StatefulWidget {
  const MobileBottomNavLayout({super.key, this.initialKey});

  final String? initialKey;

  @override
  State<MobileBottomNavLayout> createState() => _MobileBottomNavLayoutState();
}

class _MobileBottomNavLayoutState extends State<MobileBottomNavLayout> {
  int _index = 0;

  static const _facilitatorFallbackKeys = <String>[
    'dashboard',
    'agenda',
    'tickets',
  ];

  static const _operatorFallbackKeys = <String>[
    'dashboard',
    'agenda',
    'rooster',
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

  String? _routeForKey(String key, UserRole? role) {
    final k = key.trim().toLowerCase();
    if (k.isEmpty) return null;
    if (role == UserRole.operator) {
      switch (k) {
        case 'dashboard':
          return '/operator/dashboard';
        case 'agenda':
          return '/operator/agenda';
        case 'rooster':
          return '/operator/rooster';
        case 'meldingen':
          return '/operator/meldingen';
        case 'voorraad':
          return '/operator/voorraad';
        case 'uren':
          return '/operator/uren';
      }
    }
    // Facilitator/admin/other: leave untouched (existing navigation patterns).
    return null;
  }

  List<String> _keysForRole(UserRole? role) {
    final up = context.read<UserProvider>();

    switch (role) {
      case UserRole.operator:
        final allowed = <String>{
          ..._operatorFallbackKeys,
          'meldingen',
          'uren',
          'voorraad',
        };
        final prefs = up.mobileMenuPreferences
            .map((e) => e.trim().toLowerCase())
            .where((k) => allowed.contains(k))
            .toList(growable: false);
        return (prefs.isNotEmpty ? prefs : _operatorFallbackKeys)
            .take(3)
            .toList(growable: false);
      case UserRole.facilitator:
      default:
        final allowed = <String>{
          'dashboard',
          'agenda',
          'tickets',
          'planbord',
          'crm',
          'offertes',
          // Sales Center shortcuts (dynamic menu items)
          'opnames-leads',
          'calculaties-offertes',
          'projecten',
          'contracts',
          'planning-agenda',
          'dks',
          'sales-centre',
        };
        final prefs = up.mobileMenuPreferences
            .map((e) => e.trim().toLowerCase())
            .where((k) => allowed.contains(k))
            .toList(growable: false);
        return (prefs.isNotEmpty ? prefs : _facilitatorFallbackKeys)
            .take(3)
            .toList(growable: false);
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
        final role = context.read<UserProvider>().role;
        if (role == UserRole.operator) {
          return (
            label: 'Mijn Agenda',
            icon: Icons.event_outlined,
            screen: const OperatorAgendaScreen(),
          );
        }
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
      case 'planbord':
        return (
          label: 'Planbord',
          icon: Icons.calendar_month_outlined,
          screen: const PlanbordScreen(),
        );
      case 'crm':
        return (
          label: 'CRM',
          icon: Icons.groups_2_outlined,
          screen: const facilitator_crm.RelationsCrmScreen(),
        );
      case 'offertes':
        return (
          label: 'Offertes',
          icon: Icons.request_quote_outlined,
          screen: const QuoteOverviewScreen(),
        );
      case 'opnames-leads':
        return (
          label: 'Opnames & Leads',
          icon: Icons.groups_2_outlined,
          screen: const facilitator_crm.RelationsCrmScreen(),
        );
      case 'calculaties-offertes':
        return (
          label: 'Calculaties & Offertes',
          icon: Icons.request_quote_outlined,
          screen: const QuoteOverviewScreen(),
        );
      case 'projecten':
        return (
          label: 'Projecten',
          icon: Icons.view_kanban_outlined,
          screen: const ProjectOverviewScreen(),
        );
      case 'contracts':
        return (
          label: 'Contracten',
          icon: Icons.handshake_outlined,
          screen: const ContractManagementScreen(),
        );
      case 'planning-agenda':
        return (
          label: 'Agenda',
          icon: Icons.event_available_outlined,
          screen: const PlanningAgendaScreen(),
        );
      case 'dks':
        return (
          label: 'DKS',
          icon: Icons.fact_check_outlined,
          screen: const DksDashboardScreen(),
        );
      case 'sales-centre':
        return (
          label: 'Sales',
          icon: Icons.campaign_outlined,
          screen: const SalesCentreScreen(),
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
      case 'voorraad':
        return (
          label: 'Voorraad',
          icon: Icons.inventory_2_outlined,
          screen: const OperatorVoorraadScreen(),
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

    // IMPORTANT: Strictly honor the saved preferences (max 3). No smart overrides.
    var navKeys = keys.toList(growable: false);
    var navMapped = navKeys.map(_mapKey).toList(growable: false);
    if (navMapped.length < 2) {
      navKeys = const ['dashboard', 'profile'];
      navMapped = [
        _mapKey('dashboard'),
        (label: 'Profiel', icon: Icons.person, screen: const ProfileScreen()),
      ];
    }

    final currentKey =
        (widget.initialKey ?? '').trim().toLowerCase().isNotEmpty
            ? (widget.initialKey ?? '').trim().toLowerCase()
            : navKeys.first;

    // If current route isn't part of the 3 chosen menu items, keep the bar alive
    // and just fall back to a safe active index.
    final activeIndexFromRoute = navKeys.indexOf(currentKey);
    final safeIndex = (activeIndexFromRoute >= 0) ? activeIndexFromRoute : 0;

    // Always render the requested screen (even if it's not in the 3 nav items).
    final currentScreen = _mapKey(currentKey).screen;

    final body = currentScreen;

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

    final bottomBar = Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 30),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            color: Theme.of(context).cardColor.withValues(alpha: 0.6),
            child: BottomNavigationBar(
              elevation: 0,
              backgroundColor: Colors.transparent,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 140),
              currentIndex: safeIndex,
              onTap: (i) {
                setState(() => _index = i);
                final pickedKey =
                    (i >= 0 && i < navKeys.length) ? navKeys[i] : navKeys.first;
                final route = _routeForKey(pickedKey, role);
                if (route != null) {
                  Navigator.of(context).pushReplacementNamed(route);
                }
              },
              items: [
                for (final it in navMapped)
                  BottomNavigationBarItem(
                    icon: Icon(it.icon),
                    label: it.label,
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      extendBody: true,
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          body,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: bottomBar,
          ),
        ],
      ),
    );
  }
}

