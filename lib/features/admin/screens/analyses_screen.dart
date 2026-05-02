import 'package:flutter/material.dart';

import '../../../core/widgets/app_drawer.dart';

class AnalysesScreen extends StatelessWidget {
  const AnalysesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Analyses'),
      ),
      body: const Center(
        child: Text(
          'Analyses (placeholder)',
          style: TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

