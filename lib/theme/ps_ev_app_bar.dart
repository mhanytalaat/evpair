import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/profile/profile_screen.dart';
import '../services/auth_service.dart';
import 'ps_ev_theme.dart';
import '../screens/auth/sign_in_screen.dart';

class PsEvAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBrandRow;
  final List<Widget> actions;
  final bool showProfileAction;

  const PsEvAppBar({
    super.key,
    required this.title,
    this.showBrandRow = false,
    this.actions = const [],
    this.showProfileAction = true,
  });

  double get _height => showBrandRow ? 120 : 80;

  @override
  Size get preferredSize => Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final mergedActions = <Widget>[
      ...actions,
      if (showProfileAction)
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Consumer<AuthService>(
            builder: (context, auth, _) {
              return InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  if (!auth.isRegistered) {
                    Navigator.push( 
                      context,
                     MaterialPageRoute(builder: (context) => const SignInScreen(),
                    ),
                    );
                    return;
                  }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen(),
                  ),
                );
              },
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: PsEvColors.emerald,
                  child: Text(
                    auth.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ];

    return AppBar(
      toolbarHeight: _height,
      backgroundColor: Colors.white,
      foregroundColor: PsEvColors.slate950,
      elevation: 0,
      titleSpacing: 16,
      title: showBrandRow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'EVPair',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, color: PsEvColors.mutedText),
                ),
              ],
            )
          : Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
      actions: mergedActions,
    );
  }
}

class PsEvHeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final String? disabledMessage;

  const PsEvHeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.disabledMessage,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed ??
          () {
            if (disabledMessage == null) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(disabledMessage!)),
            );
          },
    );
  }
}

class PsEvModePill extends StatelessWidget {
  final String label;

  const PsEvModePill({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: PsEvColors.emeraldPale,
          borderRadius: BorderRadius.circular(PsEvRadii.pill),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: PsEvColors.emerald,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
