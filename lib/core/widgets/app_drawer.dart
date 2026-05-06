import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/web_reload.dart';
import '../../providers/user_provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../features/admin/screens/cfo_dashboard_screen.dart';
import '../../features/admin/screens/creditors_screen.dart';
import '../../features/admin/screens/expense_dashboard_screen.dart';
import '../../features/admin/screens/invoice_settings_screen.dart';
import '../../features/admin/screens/offers_screen.dart';
import '../../features/admin/screens/relations_crm_screen.dart';
import '../../features/admin/screens/security_center_screen.dart';
import '../../features/admin/screens/user_management_screen.dart';
import '../../features/admin/screens/bank_dashboard_screen.dart';
import '../../features/admin/screens/article_management_screen.dart';
import '../../features/admin/screens/debtor_dashboard_screen.dart';
import '../../features/admin/screens/financial_master_data_screen.dart';
import '../../features/admin/screens/payroll_month_overview_screen.dart';
import '../../features/admin/screens/period_close_screen.dart';
import '../../features/admin/screens/factuur_editor_screen.dart';
import '../../features/admin/screens/invoice_bulk_run_screen.dart';
import '../../features/admin/screens/invoice_overview_screen.dart';
import '../../features/admin/screens/invoice_history_screen.dart';
import '../../features/admin/screens/open_items_screen.dart';
import '../../features/admin/screens/analyses_screen.dart';
import '../../features/facilitator/facilitator_dashboard.dart';
import '../../features/facilitator/screens/contract_management_screen.dart';
import '../../features/facilitator/screens/project_overview_screen.dart';
import '../../features/facilitator/screens/relations_crm_screen.dart'
    as facilitator_crm;
import '../../features/facilitator/screens/dks_dashboard_screen.dart';
import '../../features/facilitator/screens/planbord_screen.dart';
import '../../features/facilitator/screens/planning_agenda_screen.dart';
import '../../features/facilitator/screens/quote_overview_screen.dart';
import '../../features/facilitator/screens/agenda_screen.dart';
import '../../features/facilitator/screens/sales_centre_screen.dart';
import '../../features/facilitator/screens/ticket_overview_screen.dart';
import '../../features/klant/client_dashboard.dart';
import '../../features/operator/screens/operator_dashboard_screen.dart';
import '../../features/operator/screens/operator_agenda_screen.dart';
import '../../features/operator/screens/operator_meldingen_screen.dart';
import '../../features/operator/screens/operator_voorraad_screen.dart';
import '../../features/operator/screens/operator_rooster_screen.dart';
import '../../features/operator/screens/operator_uren_screen.dart';
import '../../features/shared/screens/profile_screen.dart';
import '../../shared/layouts/mobile_bottom_nav_layout.dart';
import '../models/user_role.dart';

/// Central app navigation.
///
/// EMERGENCY RULE: for Generator, show **all** items and always keep logout accessible.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  static const String permPortalKlant = 'portal_klant';
  static const String permPortalOperator = 'portal_operator';
  static const String permPortalFacilitator = 'portal_facilitator';
  static const String permPortalAdmin = 'portal_admin';
  static const String permSecurityCenter = 'security_center';

  @override
  Widget build(BuildContext context) {
    return const Drawer(
      child: AppDrawerPanel(
        child: AppDrawerContent(),
      ),
    );
  }
}

/// Only the scrollable menu + header.
/// This is used both inside a Drawer (mobile) and the permanent left sidebar (desktop).
class AppDrawerContent extends StatelessWidget {
  const AppDrawerContent({super.key});

  static const double _fontSize = 15;

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final email = userProvider.email ?? userProvider.userId ?? '';
    final isGen = userProvider.isGenerator;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 800;
    final routeName = ModalRoute.of(context)?.settings.name ?? '';
    final isEnterpriseAdmin = isGen || userProvider.role == UserRole.administrator;

    final canKlant = isGen || userProvider.hasPermission(AppDrawer.permPortalKlant);
    final isOperatorOnly =
        userProvider.roleString?.trim().toLowerCase() == 'operator';
    final canFacilitatorRole = userProvider.role == UserRole.facilitator;
    final canFacilitatorPerm = userProvider.hasPermission(AppDrawer.permPortalFacilitator);
    // Keep facilitator shell visible when either role OR permission grants access.
    final canFacilitator = isGen || isEnterpriseAdmin || canFacilitatorRole || canFacilitatorPerm;
    final canSalesCentre = isGen ||
        userProvider.role == UserRole.administrator ||
        userProvider.role == UserRole.facilitator;
    final canSecurity = isGen || userProvider.hasPermission(AppDrawer.permSecurityCenter);
    final canPeriodClose = isGen || userProvider.role == UserRole.administrator;

    Future<void> reloadPerms() => context.read<UserProvider>().loadForCurrentUser();

    void go(String name, Widget screen) {
      Navigator.of(context).maybePop();
      if (routeName == name) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: RouteSettings(name: name),
          builder: (_) => screen,
        ),
      );
    }

    Widget leadingOrSpacer(IconData icon) {
      if (!isDesktop) return Icon(icon);
      // Keep layout stable/aligned on desktop with no icons.
      return const SizedBox(width: 0, height: 0);
    }

    ListTile navTile({
      required String name,
      required IconData icon,
      required String title,
      required Widget screen,
    }) {
      final selected = routeName == name;
      return ListTile(
        leading: isDesktop ? null : Icon(icon),
        minLeadingWidth: isDesktop ? 0 : null,
        selected: selected,
        selectedColor: Theme.of(context).colorScheme.primary,
        selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: Text(title, style: const TextStyle(fontSize: _fontSize, fontWeight: FontWeight.w600)),
        onTap: () => go(name, screen),
      );
    }

    TextStyle groupStyle() => const TextStyle(fontSize: _fontSize, fontWeight: FontWeight.w700);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Menu',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 18),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Vernieuwen',
                            onPressed: reloadPerms,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(email, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (isEnterpriseAdmin) ...[
                  ExpansionTile(
                    leading: isDesktop ? null : const Icon(Icons.folder_open_rounded),
                    title: Text('Relaties (CRM)', style: groupStyle()),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    children: [
                      navTile(
                        name: '/admin/relations',
                        icon: Icons.business_rounded,
                        title: 'Overzicht',
                        screen: const RelationsCrmScreen(),
                      ),
                      navTile(
                        name: '/admin/users',
                        icon: Icons.group_rounded,
                        title: 'Gebruikersbeheer',
                        screen: const UserManagementScreen(),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    leading: isDesktop ? null : const Icon(Icons.payments_rounded),
                    title: Text('Verkoop', style: groupStyle()),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    children: [
                      ExpansionTile(
                        leading: isDesktop ? null : const Icon(Icons.request_quote_rounded),
                        title: Text('Facturen', style: groupStyle()),
                        childrenPadding: const EdgeInsets.fromLTRB(28, 0, 12, 8),
                        children: [
                          navTile(
                            name: '/admin/sales/invoices/create',
                            icon: Icons.add_rounded,
                            title: 'Aanmaken',
                            screen: const FactuurEditorScreen(),
                          ),
                          navTile(
                            name: '/admin/sales/invoices/history',
                            icon: Icons.history_rounded,
                            title: 'Historie',
                            screen: const InvoiceHistoryScreen(),
                          ),
                          navTile(
                            name: '/admin/sales/invoices/overview',
                            icon: Icons.table_rows_rounded,
                            title: 'Overzicht',
                            screen: const InvoiceOverviewScreen(),
                          ),
                          navTile(
                            name: '/admin/sales/invoices/generate',
                            icon: Icons.auto_awesome,
                            title: 'Genereren',
                            screen: const InvoiceBulkRunScreen(),
                          ),
                        ],
                      ),
                      navTile(
                        name: '/admin/sales/articles',
                        icon: Icons.inventory_2_outlined,
                        title: 'Artikelen',
                        screen: const ArticleManagementScreen(),
                      ),
                      navTile(
                        name: '/admin/sales/offers',
                        icon: Icons.description_rounded,
                        title: 'Offertes',
                        screen: const OffersScreen(),
                      ),
                      navTile(
                        name: '/admin/sales/open-items',
                        icon: Icons.list_alt_rounded,
                        title: 'Openstaande Posten',
                        screen: const OpenItemsScreen(),
                      ),
                      navTile(
                        name: '/admin/sales/analyses',
                        icon: Icons.query_stats_rounded,
                        title: 'Analyses',
                        screen: const AnalysesScreen(),
                      ),
                      navTile(
                        name: '/admin/sales/debtors',
                        icon: Icons.groups_2_rounded,
                        title: 'Debiteuren en Herinneringen',
                        screen: const DebtorDashboardScreen(),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    leading: isDesktop ? null : const Icon(Icons.shopping_bag_rounded),
                    title: Text('Inkoop', style: groupStyle()),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    children: [
                      navTile(
                        name: '/admin/purchase/scans',
                        icon: Icons.document_scanner_rounded,
                        title: 'Inkoopboek (Scans)',
                        screen: const ExpenseDashboardScreen(),
                      ),
                      navTile(
                        name: '/admin/purchase/creditors',
                        icon: Icons.receipt_long_rounded,
                        title: 'Crediteuren',
                        screen: const CreditorsScreen(),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    leading: isDesktop ? null : const Icon(Icons.query_stats_rounded),
                    title: Text('Financieel', style: groupStyle()),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    children: [
                      navTile(
                        name: '/admin/finance/cfo',
                        icon: Icons.pie_chart_rounded,
                        title: 'CFO Dashboard',
                        screen: const CFODashboardScreen(),
                      ),
                      navTile(
                        name: '/admin/finance/bank',
                        icon: Icons.account_balance_rounded,
                        title: 'Bank & Afletteren',
                        screen: const BankDashboardScreen(),
                      ),
                      navTile(
                        name: '/admin/finance/financial-master-data',
                        icon: Icons.account_balance,
                        title: 'Financiële Stamgegevens',
                        screen: const FinancialMasterDataScreen(),
                      ),
                      navTile(
                        name: '/admin/finance/article-management',
                        icon: Icons.inventory_2_outlined,
                        title: 'Artikelbeheer',
                        screen: const ArticleManagementScreen(),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    leading: isDesktop ? null : const Icon(Icons.settings_rounded),
                    title: Text('Instellingen', style: groupStyle()),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    children: [
                      navTile(
                        name: '/admin/settings/invoice',
                        icon: Icons.business_rounded,
                        title: 'Sjablonen & Logo',
                        screen: const InvoiceSettingsScreen(),
                      ),
                      if (canSecurity)
                        navTile(
                          name: '/admin/settings/security',
                          icon: Icons.shield_outlined,
                          title: 'Beveiligingscentrum',
                          screen: const SecurityCenterScreen(),
                        ),
                      if (canPeriodClose)
                        navTile(
                          name: '/admin/settings/payroll-month',
                          icon: Icons.payments_outlined,
                          title: 'Loonadministratie',
                          screen: const PayrollMonthOverviewScreen(),
                        ),
                      if (canPeriodClose)
                        navTile(
                          name: '/admin/settings/period-close',
                          icon: Icons.lock_clock_rounded,
                          title: 'Maandafsluiting',
                          screen: const PeriodCloseScreen(),
                        ),
                    ],
                  ),
                ],
                if (canFacilitator)
                  ExpansionTile(
                    leading: isDesktop ? null : const Icon(Icons.event_note),
                    title: Text('Facilitator Portal', style: groupStyle()),
                    initiallyExpanded: canFacilitatorRole && !isEnterpriseAdmin,
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    children: [
                      navTile(
                        name: '/facilitator/dashboard',
                        icon: Icons.dashboard_outlined,
                        title: 'Dashboard',
                        screen: isDesktop
                            ? const FacilitatorDashboard()
                            : const MobileBottomNavLayout(initialKey: 'dashboard'),
                      ),
                      navTile(
                        name: '/facilitator/mijn-agenda',
                        icon: Icons.event_note_outlined,
                        title: 'Mijn Agenda',
                        screen: isDesktop
                            ? const AgendaScreen()
                            : const MobileBottomNavLayout(initialKey: 'agenda'),
                      ),
                      ExpansionTile(
                        leading: isDesktop
                            ? null
                            : const Icon(Icons.people_alt_outlined),
                        title: Text('Relaties (CRM)', style: groupStyle()),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(28, 0, 12, 8),
                        children: [
                          navTile(
                            name: '/facilitator/crm',
                            icon: Icons.groups_2_outlined,
                            title: 'Klantbeheer',
                            screen: isDesktop
                                ? const facilitator_crm.RelationsCrmScreen()
                                : const MobileBottomNavLayout(initialKey: 'crm'),
                          ),
                          navTile(
                            name: '/facilitator/projecten',
                            icon: Icons.view_kanban_outlined,
                            title: 'Projecten',
                            screen: isDesktop
                                ? const ProjectOverviewScreen()
                                : const MobileBottomNavLayout(initialKey: 'projecten'),
                          ),
                          navTile(
                            name: '/facilitator/contracts',
                            icon: Icons.handshake_outlined,
                            title: 'Contractbeheer',
                            screen: isDesktop
                                ? const ContractManagementScreen()
                                : const MobileBottomNavLayout(initialKey: 'contracts'),
                          ),
                        ],
                      ),
                      if (canSalesCentre)
                        ExpansionTile(
                          leading: isDesktop
                              ? null
                              : Icon(
                                  Icons.campaign_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          title: Text('Sales Centre', style: groupStyle()),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(28, 0, 12, 8),
                          children: [
                            navTile(
                              name: '/facilitator/quotes',
                              icon: Icons.request_quote_outlined,
                              title: 'Calculatie & Offertes',
                              screen: isDesktop
                                  ? const QuoteOverviewScreen()
                                  : const MobileBottomNavLayout(initialKey: 'offertes'),
                            ),
                            navTile(
                              name: '/facilitator/sales-centre',
                              icon: Icons.campaign_outlined,
                              title: 'Opnames & Leads',
                              screen: isDesktop
                                  ? const SalesCentreScreen()
                                  : const MobileBottomNavLayout(initialKey: 'sales-centre'),
                            ),
                          ],
                        )
                      else
                        navTile(
                          name: '/facilitator/quotes',
                          icon: Icons.request_quote_outlined,
                          title: 'Calculatie & Offertes',
                          screen: isDesktop
                              ? const QuoteOverviewScreen()
                              : const MobileBottomNavLayout(initialKey: 'offertes'),
                        ),
                      navTile(
                        name: '/facilitator/planning',
                        icon: Icons.calendar_month_outlined,
                        title: 'Planbord (Toewijzen)',
                        screen: isDesktop
                            ? const PlanbordScreen()
                            : const MobileBottomNavLayout(initialKey: 'planbord'),
                      ),
                      navTile(
                        name: '/facilitator/planning-agenda',
                        icon: Icons.event_available_outlined,
                        title: 'Planning (Agenda)',
                        screen: isDesktop
                            ? const PlanningAgendaScreen()
                            : const MobileBottomNavLayout(initialKey: 'planning-agenda'),
                      ),
                      navTile(
                        name: '/facilitator/dks',
                        icon: Icons.fact_check_outlined,
                        title: 'Kwaliteit (DKS)',
                        screen: isDesktop
                            ? const DksDashboardScreen()
                            : const MobileBottomNavLayout(initialKey: 'dks'),
                      ),
                      navTile(
                        name: '/facilitator/tickets',
                        icon: Icons.confirmation_number_outlined,
                        title: 'Tickets & Meldingen',
                        screen: isDesktop
                            ? const TicketOverviewScreen()
                            : const MobileBottomNavLayout(initialKey: 'tickets'),
                      ),

                    ],
                  ),
                if (isOperatorOnly)
                  ExpansionTile(
                    leading: isDesktop
                        ? null
                        : const Icon(Icons.engineering_rounded),
                    title: Text('Operator Portaal', style: groupStyle()),
                    initiallyExpanded: true,
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    children: [
                      navTile(
                        name: '/operator/dashboard',
                        icon: Icons.dashboard_outlined,
                        title: 'Dashboard',
                        screen: const OperatorDashboardScreen(),
                      ),
                      navTile(
                        name: '/operator/agenda',
                        icon: Icons.calendar_month_outlined,
                        title: 'Mijn Agenda',
                        screen: const OperatorAgendaScreen(),
                      ),
                      navTile(
                        name: '/operator/rooster',
                        icon: Icons.event_available_outlined,
                        title: 'Mijn Rooster',
                        screen: const OperatorRoosterScreen(),
                      ),
                      navTile(
                        name: '/operator/meldingen',
                        icon: Icons.warning_amber_rounded,
                        title: 'Mijn Meldingen',
                        screen: const OperatorMeldingenScreen(),
                      ),
                      navTile(
                        name: '/operator/voorraad',
                        icon: Icons.inventory_2_outlined,
                        title: 'Voorraad Tellen',
                        screen: const OperatorVoorraadScreen(),
                      ),
                      navTile(
                        name: '/operator/uren',
                        icon: Icons.schedule_outlined,
                        title: 'Mijn Uren',
                        screen: const OperatorUrenScreen(),
                      ),
                    ],
                  ),
                if (canKlant)
                  ListTile(
                    leading: isDesktop ? null : leadingOrSpacer(Icons.person_outline),
                    minLeadingWidth: isDesktop ? 0 : null,
                    title: const Text('Klant Portaal', style: TextStyle(fontSize: _fontSize, fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.of(context).maybePop();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const ClientDashboard()),
                      );
                    },
                  ),
              ],
            ),
          ),
          // Bottom area is outside the scrollview so logout is pinned by AppDrawerPanel.
        ],
      ),
    );
  }
}

/// Reusable panel content for permanent left sidebar.
class AppDrawerPanel extends StatelessWidget {
  const AppDrawerPanel({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onBody = theme.textTheme.bodyLarge?.color;

    final panelChild = child ?? const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          right: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          Expanded(child: panelChild),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.account_circle_outlined,
                    color: theme.iconTheme.color,
                  ),
                  title: Text(
                    'Mijn Profiel',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: onBody,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onTap: () {
                    Navigator.of(context).maybePop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: '/profile'),
                        builder: (_) => const ProfileScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  value: context.watch<ThemeModeProvider>().isDark,
                  onChanged: (_) => context.read<ThemeModeProvider>().toggle(),
                  dense: true,
                  title: const Text('Donkere modus'),
                  secondary: Icon(
                    context.watch<ThemeModeProvider>().isDark
                        ? Icons.dark_mode
                        : Icons.light_mode,
                    size: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.45),
                      ),
                      foregroundColor: onBody,
                    ),
                    onPressed: () async {
                      Navigator.of(context).maybePop();
                      await Supabase.instance.client.auth.signOut();
                      if (!context.mounted) return;
                      context.read<UserProvider>().clear();
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        '/login',
                        (route) => false,
                      );
                      if (kIsWeb) forceWebReload();
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Uitloggen'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
