import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../driver/driver_home_screen.dart';
import '../host/host_home_screen.dart';
import '../admin/admin_home_screen.dart';

/// Top-level app shell: a STANDARD Flutter bottom-navigation layout with
/// 3 tabs (Driver / Host / Admin). Navigating deeper uses Navigator.push,
/// so pushed screens automatically get a working back arrow/gesture.
///
/// NOTE: the Admin tab is demo-only. In production, remove it entirely and
/// ship admin tooling as its own separate, authenticated app.
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  static const _tabs = [
    DriverHomeScreen(),
    HostHomeScreen(),
    AdminHomeScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      body: IndexedStack(index: app.role.index, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: app.role.index,
        onTap: (i) => app.setRole(AppRole.values[i]),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.electric_car), label: 'Driver'),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Host'),
          BottomNavigationBarItem(icon: Icon(Icons.shield), label: 'Admin'),
        ],
      ),
    );
  }
}
