import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';

/// Bottom-navigation shell hosting the five primary tabs.
class HomeShell extends StatelessWidget {
  const HomeShell({required this.child, super.key});

  final Widget child;

  static const _tabs = <_TabInfo>[
    _TabInfo(Routes.dialer, Icons.dialpad, 'Dialer'),
    _TabInfo(Routes.callLog, Icons.history, 'Recents'),
    _TabInfo(Routes.contacts, Icons.person, 'Contacts'),
    _TabInfo(Routes.groups, Icons.groups, 'Groups'),
    _TabInfo(Routes.settings, Icons.settings, 'Settings'),
  ];

  int _indexFor(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final i = _tabs.indexWhere((t) => location.startsWith(t.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final index = _indexFor(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}

class _TabInfo {
  const _TabInfo(this.path, this.icon, this.label);
  final String path;
  final IconData icon;
  final String label;
}
