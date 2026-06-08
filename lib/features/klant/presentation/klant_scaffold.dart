import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/klant_dashboard_screen.dart';
import '../screens/klant_logboek_screen.dart';
import '../screens/klant_planning_screen.dart';
import '../screens/klant_service_screen.dart';
import 'klant_nav_scope.dart';

/// Mobiele shell voor het klantportaal met vaste bottom navigation.
class KlantScaffold extends StatefulWidget {
  const KlantScaffold({super.key, this.initialKey});

  final String? initialKey;

  static const _tabKeys = <String>[
    'dashboard',
    'planning',
    'logboek',
    'service',
  ];

  @override
  State<KlantScaffold> createState() => _KlantScaffoldState();
}

class _KlantScaffoldState extends State<KlantScaffold> {
  late int _index;

  static const _titles = <String>[
    'Dashboard',
    'Planning',
    'Logboek',
    'Service',
  ];

  @override
  void initState() {
    super.initState();
    _index = _indexForKey(widget.initialKey);
  }

  @override
  void didUpdateWidget(covariant KlantScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = (widget.initialKey ?? '').trim().toLowerCase();
    final oldKey = (oldWidget.initialKey ?? '').trim().toLowerCase();
    if (key.isNotEmpty && key != oldKey) {
      final i = _indexForKey(key);
      if (i != _index) setState(() => _index = i);
    }
  }

  int _indexForKey(String? key) {
    final k = (key ?? 'dashboard').trim().toLowerCase();
    final i = KlantScaffold._tabKeys.indexOf(k);
    return i >= 0 ? i : 0;
  }

  void _goToTab(String tabKey) {
    final i = _indexForKey(tabKey);
    if (i == _index) return;
    setState(() => _index = i);
  }

  void _onNavTap(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return KlantNavScope(
      goToTab: _goToTab,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.grey.shade50,
          foregroundColor: const Color(0xFF0D1B3E),
          title: Text(
            _titles[_index],
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
          centerTitle: false,
        ),
        body: IndexedStack(
          index: _index,
          children: const [
            KlantDashboardScreen(),
            KlantPlanningScreen(),
            KlantLogboekScreen(),
            KlantServiceScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onNavTap,
          backgroundColor: Colors.white,
          indicatorColor: Colors.blue.shade50,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month_rounded),
              label: 'Planning',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder_rounded),
              label: 'Logboek',
            ),
            NavigationDestination(
              icon: Icon(Icons.support_agent_outlined),
              selectedIcon: Icon(Icons.support_agent_rounded),
              label: 'Service',
            ),
          ],
        ),
      ),
    );
  }
}
