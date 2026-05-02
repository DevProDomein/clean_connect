import 'package:flutter/material.dart';

/// Standard layout wrapper (no permanent sidebar).
class MainLayout extends StatelessWidget {
  const MainLayout({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

