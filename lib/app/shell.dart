import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Navigasi adaptif: NavigationRail di layar lebar (Windows), NavigationBar di layar sempit (Android).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  static const _tabs = [
    ('/dashboard', Icons.dashboard_outlined, Icons.dashboard, 'Beranda'),
    ('/assets', Icons.inventory_2_outlined, Icons.inventory_2, 'Aset'),
    ('/scan', Icons.qr_code_scanner, Icons.qr_code_scanner, 'Scan'),
    ('/more', Icons.menu, Icons.menu, 'Lainnya'),
  ];

  int get _index {
    final i = _tabs.indexWhere((t) => location.startsWith(t.$1));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      void go(int i) => context.go(_tabs[i].$1);
      if (c.maxWidth >= 840) {
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final t in _tabs)
                  NavigationRailDestination(icon: Icon(t.$2), selectedIcon: Icon(t.$3), label: Text(t.$4)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ]),
        );
      }
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: go,
          destinations: [
            for (final t in _tabs) NavigationDestination(icon: Icon(t.$2), selectedIcon: Icon(t.$3), label: t.$4),
          ],
        ),
      );
    });
  }
}
