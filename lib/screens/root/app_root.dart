import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../services/auth_service.dart';
import '../../theme/ps_ev_theme.dart';
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

    final navItems = <_RoleNavItem>[
      const _RoleNavItem(icon: Icons.electric_car, label: 'Driver'),
      const _RoleNavItem(icon: Icons.home, label: 'Host'),
      if (auth.isAdmin) const _RoleNavItem(icon: Icons.shield, label: 'Admin'),
    ];

    // Guard against a stale Admin role index if the user signed out or
    // switched accounts while sitting on the Admin tab.
    var currentIndex = app.role.index;
    if (currentIndex >= tabs.length) {
      currentIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => app.setRole(AppRole.driver));
    }

    return Scaffold(
      // The Driver / Host / Admin switcher now lives in a top header bar
      // (previously a bottomNavigationBar) so it's the first thing the
      // user sees and taps, instead of being tucked away at the bottom.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: _RoleHeaderBar(
          currentIndex: currentIndex,
          items: navItems,
          onTap: (i) => app.setRole(AppRole.values[i]),
        ),
      ),
      body: IndexedStack(index: currentIndex, children: tabs),
    );
  }
}

class _RoleNavItem {
  final IconData icon;
  final String label;
  const _RoleNavItem({required this.icon, required this.label});
}

class _RoleHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  final int currentIndex;
  final List<_RoleNavItem> items;
  final ValueChanged<int> onTap;

  const _RoleHeaderBar({required this.currentIndex, required this.items, required this.onTap});

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 52,
                decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: PsEvColors.slate200, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: List.generate(items.length, (i) {
            final item = items[i];
            final selected = i == currentIndex;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(PsEvRadii.pill),
                onTap: () => onTap(i),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? PsEvColors.emeraldPale : Colors.transparent,
                    borderRadius: BorderRadius.circular(PsEvRadii.pill),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.icon, size: 18, color: selected ? PsEvColors.emerald : PsEvColors.mutedText),
                      const SizedBox(width: 6),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: selected ? PsEvColors.emerald : PsEvColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
