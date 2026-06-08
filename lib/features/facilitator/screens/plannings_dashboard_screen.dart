import 'package:flutter/material.dart';

import '../../../core/widgets/app_drawer.dart';
import 'planbord_screen.dart';
import 'planning_agenda_screen.dart';

/// Centraal planningsdashboard: Kalender, Handmatig Plannen en Smart Planner.
class PlanningsDashboardScreen extends StatelessWidget {
  const PlanningsDashboardScreen({super.key, this.initialTab = 0});

  /// 0 = Kalender, 1 = Handmatig Plannen, 2 = Smart Planner
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return PlanbordTabsHost(
      child: _PlanningsDashboardShell(initialTab: initialTab),
    );
  }
}

/// @deprecated Gebruik [PlanningsDashboardScreen].
class PlanbordScreen extends StatelessWidget {
  const PlanbordScreen({super.key, this.initialTab = 2});

  /// 0=kalender, 1=handmatig, 2=smart (default = oude Smart Planner-tab).
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return PlanningsDashboardScreen(initialTab: initialTab);
  }
}

/// @deprecated Gebruik [PlanningsDashboardScreen].
class PlanningAgendaScreen extends StatelessWidget {
  const PlanningAgendaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlanningsDashboardScreen(initialTab: 0);
  }
}

class _PlanningsDashboardShell extends StatefulWidget {
  const _PlanningsDashboardShell({required this.initialTab});

  final int initialTab;

  @override
  State<_PlanningsDashboardShell> createState() =>
      _PlanningsDashboardShellState();
}

class _PlanningsDashboardShellState extends State<_PlanningsDashboardShell> {
  final GlobalKey<AgendaTabState> _agendaKey = GlobalKey<AgendaTabState>();

  Future<void> _refreshAll() async {
    await _agendaKey.currentState?.reloadAgenda();
    if (!mounted) return;
    await PlanbordScope.of(context).refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = widget.initialTab.clamp(0, 2);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0912) : Colors.grey.shade50;

    return DefaultTabController(
      length: 3,
      initialIndex: tabIndex,
      child: Scaffold(
        backgroundColor: bg,
        drawer: const AppDrawer(),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'Planning & planbord',
            style: TextStyle(
              color: Colors.blue.shade900,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            Builder(
              builder: (context) {
                final planbord = PlanbordScope.of(context);
                final agendaLoading =
                    _agendaKey.currentState?.isLoading ?? false;
                final isRefreshing = planbord.isRefreshing || agendaLoading;
                return IconButton(
                  tooltip: 'Vernieuwen',
                  onPressed: isRefreshing ? null : _refreshAll,
                  icon: const Icon(Icons.refresh_rounded),
                );
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(64),
            child: Container(
              height: 48,
              margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(4),
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 24),
                labelColor: Colors.blue.shade900,
                unselectedLabelColor: Colors.grey.shade600,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                tabs: [
                  const Tab(text: 'Kalender'),
                  const Tab(text: 'Planbord'),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 16,
                          color: Colors.purple.shade500,
                        ),
                        const SizedBox(width: 6),
                        const Text('Smart Planner'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            AgendaTab(key: _agendaKey),
            HandmatigPlannenTab(),
            SmartPlannerTab(),
          ],
        ),
      ),
    );
  }
}
