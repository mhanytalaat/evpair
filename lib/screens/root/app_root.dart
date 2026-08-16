import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../services/auth_service.dart';
import '../driver/driver_home_screen.dart';
import '../host/host_home_screen.dart';
import '../admin/admin_home_screen.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final auth = context.watch<AuthService>();

    // The Admin tab is only ever visible when signed in with the
    // designated admin account (see AuthService.isAdmin / kAdminEmail).
    // Every other signed-in user and every guest only sees Driver/Host.
    final tabs = <Widget>[
      const DriverHomeScreen(),
      const HostHomeScreen(),
      if (auth.isAdmin) const AdminHomeScreen(),
    ];

    final navItems = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(icon: Icon(Icons.electric_car), label: 'Driver'),
      const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Host'),
      if (auth.isAdmin) const BottomNavigationBarItem(icon: Icon(Icons.shield), label: 'Admin'),
    ];

    // Guard against a stale Admin role index if the user signed out or
    // switched accounts while sitting on the Admin tab.
    var currentIndex = app.role.index;
    if (currentIndex >= tabs.length) {
      currentIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => app.setRole(AppRole.driver));
    }

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) => app.setRole(AppRole.values[i]),
        items: navItems,
      ),
    );
  }
}
