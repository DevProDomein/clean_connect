import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase_client.dart';
import '../../../core/web_reload.dart';
import '../../../providers/user_provider.dart';
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

  void _drawerNavTo(String tabKey) {
    Navigator.pop(context);
    _goToTab(tabKey);
  }

  Future<void> _logout() async {
    Navigator.pop(context);
    try {
      await AppSupabase.client.auth.signOut();
      if (!mounted) return;
      context.read<UserProvider>().clear();
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
      if (kIsWeb) forceWebReload();
    } catch (e) {
      debugPrint('Fout bij uitloggen: $e');
    }
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 60, bottom: 24, left: 24, right: 24),
            decoration: BoxDecoration(color: Colors.blue.shade900),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.business, size: 30, color: Color(0xFF0F172A)),
                ),
                SizedBox(height: 16),
                Text(
                  'Mijn Account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: Icon(Icons.dashboard_outlined, color: Colors.blue.shade900),
            title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => _drawerNavTo('dashboard'),
          ),
          ListTile(
            leading: Icon(Icons.calendar_month_outlined, color: Colors.blue.shade900),
            title: const Text('Planning', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => _drawerNavTo('planning'),
          ),
          ListTile(
            leading: Icon(Icons.folder_outlined, color: Colors.blue.shade900),
            title: const Text('Logboek', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => _drawerNavTo('logboek'),
          ),
          ListTile(
            leading: Icon(Icons.support_agent_outlined, color: Colors.blue.shade900),
            title: const Text('Service', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => _drawerNavTo('service'),
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              'Uitloggen',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
            onTap: _logout,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
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
          backgroundColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.blue.shade900),
          title: Text(
            _titles[_index],
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: Colors.blue.shade900,
            ),
          ),
          centerTitle: false,
        ),
        drawer: _buildDrawer(),
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
