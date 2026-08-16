import 'package:flutter/material.dart';

class PsEvColors {
  static const emerald = Color(0xFF059669);
  static const emeraldDark = Color(0xFF047857);
  static const emeraldLight = Color(0xFF34D399);
  static const emeraldPale = Color(0xFFECFDF5);
  static const emeraldChip = Color(0xFFD1FAE5);
  static const emeraldChipText = Color(0xFF047857);

  static const slate950 = Color(0xFF020617);
  static const slate900 = Color(0xFF0F172A);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slateText = Color(0xFF334155);
  static const mutedText = Color(0xFF64748B);

  static const amber = Color(0xFFD97706);
  static const amberChip = Color(0xFFFEF3C7);
  static const amberChipText = Color(0xFFB45309);

  static const red = Color(0xFFDC2626);
  static const redChip = Color(0xFFFEE2E2);
  static const redChipText = Color(0xFFB91C1C);

  static const blue = Color(0xFF2563EB);
  static const blueChip = Color(0xFFDBEAFE);
  static const blueChipText = Color(0xFF1D4ED8);

  static const cardBackground = Colors.white;
  static const pageBackground = slate100;
}

class PsEvRadii {
  static const card = 20.0;
  static const pill = 999.0;
  static const button = 14.0;
  static const iconBox = 18.0;
  static const mapBox = 18.0;
}

ThemeData buildPsEvTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: PsEvColors.emerald,
      primary: PsEvColors.emerald,
      secondary: PsEvColors.emeraldLight,
      surface: PsEvColors.cardBackground,
    ),
    scaffoldBackgroundColor: PsEvColors.pageBackground,
  );

  return base.copyWith(
    cardTheme: CardThemeData(
      color: PsEvColors.cardBackground,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PsEvRadii.card)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: PsEvColors.emerald,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PsEvRadii.button)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PsEvColors.slateText,
        side: const BorderSide(color: PsEvColors.slate200, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PsEvRadii.button)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: PsEvColors.slate200, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: PsEvColors.slate200, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: PsEvColors.emerald, width: 1.5),
      ),
      labelStyle: const TextStyle(color: PsEvColors.mutedText, fontSize: 12),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: PsEvColors.emerald,
      unselectedItemColor: PsEvColors.mutedText,
      backgroundColor: Colors.white,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
    ),
  );
}

class PsEvTag extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;
  final IconData? icon;

  const PsEvTag({super.key, required this.label, this.background = PsEvColors.slate100, this.textColor = PsEvColors.slateText, this.icon});

  const PsEvTag.price({super.key, required this.label}) : background = PsEvColors.emeraldChip, textColor = PsEvColors.emeraldChipText, icon = null;

  const PsEvTag.restricted({super.key, required this.label}) : background = PsEvColors.redChip, textColor = PsEvColors.redChipText, icon = Icons.lock;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6, top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(PsEvRadii.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: textColor), const SizedBox(width: 3)],
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
        ],
      ),
    );
  }
}

class PsEvStatusPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;

  const PsEvStatusPill({super.key, required this.label, required this.background, required this.textColor});

  factory PsEvStatusPill.free() => const PsEvStatusPill(label: 'Free', background: PsEvColors.emeraldChip, textColor: PsEvColors.emeraldChipText);
  factory PsEvStatusPill.booked() => const PsEvStatusPill(label: 'Full', background: PsEvColors.amberChip, textColor: PsEvColors.amberChipText);
  factory PsEvStatusPill.locked() => const PsEvStatusPill(label: 'Residents only', background: PsEvColors.redChip, textColor: PsEvColors.redChipText);
  factory PsEvStatusPill.bookedAwaitingScan() =>
      const PsEvStatusPill(label: 'Booked · awaiting start', background: PsEvColors.amberChip, textColor: PsEvColors.amberChipText);
  factory PsEvStatusPill.charging() =>
      const PsEvStatusPill(label: 'Charging · running', background: PsEvColors.blueChip, textColor: PsEvColors.blueChipText);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(PsEvRadii.pill)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
    );
  }
}

class PsEvSoftButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;

  const PsEvSoftButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.background = PsEvColors.emeraldPale,
    this.foreground = PsEvColors.emerald,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PsEvRadii.button),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(PsEvRadii.button),
          border: Border.all(color: foreground.withOpacity(0.25), width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class PsEvFilledButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool expand;
  final Color color;

  const PsEvFilledButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.expand = true,
    this.color = PsEvColors.emerald,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 18, color: Colors.white), const SizedBox(width: 8)],
        Flexible(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PsEvRadii.button),
      child: Container(
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        decoration: BoxDecoration(
          color: onTap == null ? color.withOpacity(0.5) : color,
          borderRadius: BorderRadius.circular(PsEvRadii.button),
        ),
        child: child,
      ),
    );
  }
}
