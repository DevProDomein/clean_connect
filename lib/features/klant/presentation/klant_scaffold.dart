import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase/chat_service.dart';
import '../../../core/supabase_client.dart';
import '../../../core/web_reload.dart';
import '../../../providers/user_provider.dart';
import '../screens/klant_account_screen.dart';
import '../screens/klant_contracten_screen.dart';
import '../screens/klant_dashboard_screen.dart';
import '../screens/klant_dks_screen.dart';
import '../screens/klant_facturen_screen.dart';
import '../screens/klant_logboek_screen.dart';
import '../screens/klant_planning_screen.dart';
import '../screens/klant_service_screen.dart';
import 'klant_nav_scope.dart';

/// Mobiele shell voor het klantportaal met vaste bottom navigation.
class KlantScaffold extends StatefulWidget {
  const KlantScaffold({
    super.key,
    this.initialKey,
    this.restorePersistedTab = false,
  });

  /// Tab-key bij eerste open via named route (bijv. `/klant/planning`).
  final String? initialKey;

  /// `true` voor de hoofd-shell in [AuthGate]: gebruik opgeslagen tab i.p.v. dashboard.
  final bool restorePersistedTab;

  /// Houdt één shell-state vast over [AuthGate]-rebuilds.
  static final GlobalKey<State<KlantScaffold>> shellKey = GlobalKey();

  @override
  State<KlantScaffold> createState() => _KlantScaffoldState();
}

class _KlantScaffoldState extends State<KlantScaffold> {
  final ChatService _chatService = ChatService();
  late int _index;

  static const _titles = <String>[
    'Dashboard',
    'Planning',
    'Logboek',
    'Mijn Berichten',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.restorePersistedTab) {
      _index = KlantTabPersistence.index;
    } else {
      KlantTabPersistence.applyInitialKey(widget.initialKey);
      _index = KlantTabPersistence.index;
    }
  }

  @override
  void didUpdateWidget(covariant KlantScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.restorePersistedTab) return;

    final key = (widget.initialKey ?? '').trim().toLowerCase();
    final oldKey = (oldWidget.initialKey ?? '').trim().toLowerCase();
    if (key.isNotEmpty && key != oldKey) {
      KlantTabPersistence.applyInitialKey(key);
      final i = KlantTabPersistence.index;
      if (i != _index) setState(() => _index = i);
    }
  }

  void _persistIndex(int i) {
    KlantTabPersistence.setIndex(i);
    if (i == _index) return;
    setState(() => _index = i);
  }

  void _goToTab(String tabKey) {
    final i = KlantTabPersistence.indexForKey(tabKey);
    _persistIndex(i);
  }

  void _onNavTap(int i) => _persistIndex(i);

  void _drawerNavTo(String tabKey) {
    Navigator.pop(context);
    _goToTab(tabKey);
  }

  void _openPushedScreen(Widget screen) {
    Navigator.pop(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  void _openAccountScreen() => _openPushedScreen(const KlantAccountScreen());

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
            leading: Icon(Icons.verified_outlined, color: Colors.blue.shade900),
            title: const Text(
              'Kwaliteit & DKS',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () => _openPushedScreen(const KlantDksScreen()),
          ),
          ListTile(
            leading: Icon(Icons.description_outlined, color: Colors.blue.shade900),
            title: const Text(
              'Contracten & Offertes',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () => _openPushedScreen(const KlantContractenScreen()),
          ),
          ListTile(
            leading: Icon(Icons.receipt_long_outlined, color: Colors.blue.shade900),
            title: const Text(
              'Facturen',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () => _openPushedScreen(const KlantFacturenScreen()),
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
            leading: StreamBuilder<int>(
              stream: _chatService.streamTotalUnreadCount(),
              initialData: 0,
              builder: (context, snap) {
                final unread = snap.data ?? 0;
                return Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: Icon(
                    Icons.chat_outlined,
                    color: Colors.blue.shade900,
                  ),
                );
              },
            ),
            title: const Text(
              'Mijn Berichten',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () => _drawerNavTo('service'),
          ),
          ListTile(
            leading: Icon(Icons.manage_accounts, color: Colors.blue.shade900),
            title: const Text(
              'Account & Instellingen',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: _openAccountScreen,
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
        bottomNavigationBar: StreamBuilder<int>(
          stream: _chatService.streamTotalUnreadCount(),
          initialData: 0,
          builder: (context, unreadSnap) {
            final unread = unreadSnap.data ?? 0;
            final serviceIcon = Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.chat_outlined),
            );
            final serviceIconSelected = Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.chat_rounded),
            );

            return NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _onNavTap,
              backgroundColor: Colors.white,
              indicatorColor: Colors.blue.shade50,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Dashboard',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: 'Planning',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder_rounded),
                  label: 'Logboek',
                ),
                NavigationDestination(
                  icon: serviceIcon,
                  selectedIcon: serviceIconSelected,
                  label: 'Mijn Berichten',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
