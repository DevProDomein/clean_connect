import 'package:flutter/material.dart';

import '../../../core/widgets/app_drawer.dart';

class OpenItemsScreen extends StatelessWidget {
  const OpenItemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Openstaande posten'),
      ),
      body: const Center(
        child: Text(
          'Openstaande posten (placeholder)',
          style: TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

