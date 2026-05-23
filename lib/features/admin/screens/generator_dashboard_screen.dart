import 'package:flutter/material.dart';

import '../../../core/widgets/app_drawer.dart';
import '../../facilitator/screens/planbord_screen.dart';
import '../../facilitator/screens/quote_create_header_screen.dart';
import '../../facilitator/screens/relations_crm_screen.dart';
import 'invoice_bulk_run_screen.dart';
import 'uren_accorderen_screen.dart';

/// Apple-stijl controlecentrum voor Generator / beheerder.
class GeneratorDashboardScreen extends StatefulWidget {
  const GeneratorDashboardScreen({super.key});

  @override
  State<GeneratorDashboardScreen> createState() => _GeneratorDashboardScreenState();
}

class _GeneratorDashboardScreenState extends State<GeneratorDashboardScreen> {
  @override
  void initState() {
    super.initState();
    // TODO: KPI's en alerts koppelen aan Supabase-queries.
  }

  void _navigateTo(BuildContext context, String route) {
    final navigator = Navigator.of(context);
    switch (route) {
      case '/offerte-aanmaken':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/facilitator/quotes/create'),
            builder: (_) => const QuoteCreateHeaderScreen(),
          ),
        );
        return;
      case '/crm':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/facilitator/crm'),
            builder: (_) => const RelationsCrmScreen(),
          ),
        );
        return;
      case '/planbord':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/facilitator/planning'),
            builder: (_) => const PlanbordScreen(),
          ),
        );
        return;
      case '/uren-accorderen':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/admin/uren-accorderen'),
            builder: (_) => const UrenAccorderenScreen(),
          ),
        );
        return;
      case '/facturatie':
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/admin/sales/invoices/generate'),
            builder: (_) => const InvoiceBulkRunScreen(),
          ),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = const Color(0xFFF2F2F7);
    final Color cardColor = Colors.white;
    final borderRadius = BorderRadius.circular(16);
    final shadow = BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 20,
      offset: const Offset(0, 4),
    );

    return Scaffold(
      backgroundColor: bgColor,
      drawer: const AppDrawer(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Goedemiddag,',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Controlecentrum',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 800 ? 4 : 2;
                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.5,
                    children: [
                      _buildKpiCard(
                        'Open Meldingen',
                        '3',
                        Icons.warning_amber_rounded,
                        Colors.orange,
                        cardColor,
                        borderRadius,
                        shadow,
                      ),
                      _buildKpiCard(
                        'Uren te accorderen',
                        '12',
                        Icons.access_time,
                        Colors.blue,
                        cardColor,
                        borderRadius,
                        shadow,
                      ),
                      _buildKpiCard(
                        'Concept Facturen',
                        '5',
                        Icons.receipt_long,
                        Colors.green,
                        cardColor,
                        borderRadius,
                        shadow,
                      ),
                      _buildKpiCard(
                        'Actieve Projecten',
                        '48',
                        Icons.business,
                        Colors.purple,
                        cardColor,
                        borderRadius,
                        shadow,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 40),
              const Text(
                'Snelle Acties',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildActionChip(
                    context,
                    'Nieuwe Offerte',
                    Icons.add_circle,
                    Colors.blue,
                    '/offerte-aanmaken',
                  ),
                  _buildActionChip(
                    context,
                    'Klant Toevoegen',
                    Icons.person_add,
                    Colors.teal,
                    '/crm',
                  ),
                  _buildActionChip(
                    context,
                    'Planbord',
                    Icons.calendar_month,
                    Colors.indigo,
                    '/planbord',
                  ),
                  _buildActionChip(
                    context,
                    'Uren Accorderen',
                    Icons.fact_check,
                    Colors.orange,
                    '/uren-accorderen',
                  ),
                  _buildActionChip(
                    context,
                    'Factureren',
                    Icons.euro,
                    Colors.green,
                    '/facturatie',
                  ),
                ],
              ),
              const SizedBox(height: 40),
              const Text(
                'Aandacht Vereist',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: borderRadius,
                  boxShadow: [shadow],
                ),
                child: Column(
                  children: [
                    _buildAlertRow(
                      Icons.assignment_late,
                      '3 offertes wachten al langer dan 7 dagen op antwoord.',
                      Colors.orange,
                    ),
                    const Divider(height: 1),
                    _buildAlertRow(
                      Icons.no_accounts,
                      '2 ingeplande taken voor morgen hebben nog geen operator.',
                      Colors.red,
                    ),
                    const Divider(height: 1),
                    _buildAlertRow(
                      Icons.cleaning_services,
                      'DKS Controle vereist bij project: Jansen Logistics.',
                      Colors.blue,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard(
    String title,
    String value,
    IconData icon,
    Color iconColor,
    Color cardColor,
    BorderRadius radius,
    BoxShadow shadow,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: radius,
        boxShadow: [shadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: iconColor, size: 28),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    String route,
  ) {
    return InkWell(
      onTap: () => _navigateTo(context, route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertRow(IconData icon, String text, Color color) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {},
    );
  }
}
