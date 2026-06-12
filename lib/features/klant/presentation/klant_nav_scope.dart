import 'package:flutter/material.dart';

/// Bewaart de actieve klant-tab over AuthGate-rebuilds, pops en hot reload.
class KlantTabPersistence {
  KlantTabPersistence._();

  static const tabKeys = <String>[
    'dashboard',
    'planning',
    'logboek',
    'service',
  ];

  static int _index = 0;

  static int get index => _index;

  static String get tabKey =>
      tabKeys[_index.clamp(0, tabKeys.length - 1)];

  static void setIndex(int i) {
    if (i < 0 || i >= tabKeys.length) return;
    _index = i;
  }

  static int indexForKey(String? key) {
    final k = (key ?? '').trim().toLowerCase();
    if (k.isEmpty) return _index;
    final i = tabKeys.indexOf(k);
    return i >= 0 ? i : _index;
  }

  /// Alleen bij expliciete deep-link / named route het tabblad overschrijven.
  static void applyInitialKey(String? key) {
    final k = (key ?? '').trim().toLowerCase();
    if (k.isEmpty) return;
    final i = tabKeys.indexOf(k);
    if (i >= 0) _index = i;
  }
}

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
