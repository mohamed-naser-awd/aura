import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-navigation shell hosting the five primary tabs. Backed by a
/// [StatefulNavigationShell] (IndexedStack) so each tab keeps its state and switching is instant.
class HomeShell extends StatelessWidget {
  const HomeShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  static const _tabs = <_TabInfo>[
    _TabInfo(Icons.dialpad, 'Dialer'),
    _TabInfo(Icons.history, 'Recents'),
    _TabInfo(Icons.person, 'Contacts'),
    _TabInfo(Icons.groups, 'Groups'),
    _TabInfo(Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(
          i,
          // Re-tapping the active tab pops it back to its root.
          initialLocation: i == shell.currentIndex,
        ),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}

class _TabInfo {
  const _TabInfo(this.icon, this.label);
  final IconData icon;
  final String label;
}
