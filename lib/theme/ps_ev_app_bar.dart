import 'package:flutter/material.dart';
import 'ps_ev_theme.dart';

class PsEvAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBrandRow;
  final List<Widget> actions;

  const PsEvAppBar({
    super.key,
    required this.title,
    this.showBrandRow = false,
    this.actions = const [],
  });

  double get _height => showBrandRow ? 120 : 80;

  @override
  Size get preferredSize => Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: _height,
      backgroundColor: PsEvColors.slate950,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 12,
      flexibleSpace: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/charger_header.png', fit: BoxFit.cover, alignment: const Alignment(0, -0.25)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.25), Colors.black.withOpacity(0.55), Colors.black.withOpacity(0.85)],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ],
      ),
      title: showBrandRow
          ? Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: PsEvColors.emeraldLight, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.bolt, size: 18, color: PsEvColors.slate950),
                    ),
                    const SizedBox(width: 8),
                    const Text('EVPair', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            )
          : Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
      actions: actions,
    );
  }
}

class PsEvModePill extends StatelessWidget {
  final String label;
  const PsEvModePill({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(999)),
      alignment: Alignment.center,
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }
}

/// A header icon button that stays fully visible (white) at all times,
/// even when its action is currently unavailable - shows an informative
/// SnackBar instead of visually disabling/greying out (a disabled plain
/// IconButton falls back to Theme.disabledColor, nearly invisible against
/// the dark photo header).
class PsEvHeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final String disabledMessage;

  const PsEvHeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.disabledMessage = 'Not available yet.',
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      tooltip: tooltip,
      onPressed: () {
        if (onPressed != null) {
          onPressed!();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(disabledMessage)));
        }
      },
    );
  }
}
