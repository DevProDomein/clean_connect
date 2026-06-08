import 'package:flutter/material.dart';

/// Laat child-schermen (bijv. dashboard quick actions) een tab kiezen.
class KlantNavScope extends InheritedWidget {
  const KlantNavScope({
    super.key,
    required this.goToTab,
    required super.child,
  });

  final void Function(String tabKey) goToTab;

  static KlantNavScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<KlantNavScope>();
  }

  @override
  bool updateShouldNotify(KlantNavScope oldWidget) => false;
}
