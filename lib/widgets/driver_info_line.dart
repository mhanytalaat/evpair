import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/ps_ev_theme.dart';

/// Resolves a Firebase Auth uid into the driver's actual first/last name
/// (+ optional mobile number) by looking up the Firestore `users`
/// collection, instead of showing the raw uid/Firestore document id.
///
/// FIX (7/9 update, item #3): screens/host/host_scan_screen.dart's
/// "Active Sessions" list previously displayed `'Driver: ${b.driverId}'`
/// directly - i.e. the raw Firestore auto-generated document id/uid
/// characters (e.g. "Driver: X9aTONpkzbPlhg7L9iuHH3F9pm13") instead of
/// the driver's name, even though the exact same lookup already worked
/// correctly elsewhere in the app (see the charger detail / Manage
/// Charger screen). This widget centralizes that lookup so it's easy to
/// reuse anywhere a bare driverId/hostId needs to be shown as a name.
class DriverInfoLine extends StatelessWidget {
  final String uid;
  final bool showPhone;
  final TextStyle? nameStyle;
  const DriverInfoLine({super.key, required this.uid, this.showPhone = true, this.nameStyle});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Text('Driver: Loading...', style: TextStyle(color: PsEvColors.mutedText, fontSize: 12));
        }
        String name = 'Driver';
        String? phone;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          final first = data?['firstName'] as String? ?? '';
          final last = data?['lastName'] as String? ?? '';
          final fullName = [first, last].where((v) => v.trim().isNotEmpty).join(' ');
          if (fullName.isNotEmpty) name = fullName;
          phone = data?['phone'] as String?;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Driver: $name', style: nameStyle ?? const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (showPhone && phone != null && phone.trim().isNotEmpty)
              Text(phone, style: const TextStyle(color: PsEvColors.mutedText, fontSize: 11)),
          ],
        );
      },
    );
  }
}
