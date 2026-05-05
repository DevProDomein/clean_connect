import 'package:flutter/material.dart';

import '../../core/translations.dart';
import '../../core/widgets/app_drawer.dart';

class ClientDashboard extends StatelessWidget {
  const ClientDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppTexts.get('client_dashboard_title'))),
      drawer: const AppDrawer(),
      body: SelectionArea(
        child: Center(child: Text(AppTexts.get('coming_soon'))),
      ),
    );
  }
}

