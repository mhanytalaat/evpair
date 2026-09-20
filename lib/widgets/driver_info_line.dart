import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/ps_ev_theme.dart';

/// Resolves a Firebase Auth uid into the driver's actual first/last name
/// (+ optional mobile number) by looking up the Firestore `users`
/// collection, instead of showing the raw uid/Firestore document id.
///
/// FIX (9/17 update - "active sessions keeps refreshing every second and
/// reloads the page, makes me dizzy"): this was previously a
/// StatelessWidget whose `build()` created a brand-new
/// `FirebaseFirestore...get()` Future INLINE inside its FutureBuilder,
/// every single time it was rebuilt. Both host_scan_screen.dart's
/// "Charging Now" list and my_bookings_screen.dart's host view have a
/// `Timer.periodic` ticking every second (to update the live duration
/// counter) which calls `setState()` and rebuilds their entire list -
/// including recreating every DriverInfoLine as a "new" widget each
/// time. That meant every visible driver's name was being RE-FETCHED
/// from Firestore once per second, visibly flashing "Driver: Loading..."
/// -> name on a 1-second loop - exactly the same root cause previously
/// found and fixed in booking_status_screen.dart's _HostContactCard.
///
/// FIX: converted to a StatefulWidget that fetches ONCE in `initState()`
/// and caches the Future - a per-second parent rebuild now reuses the
/// already-loaded data instead of re-querying Firestore, so the name
/// only ever loads once and stays stable.
class DriverInfoLine extends StatefulWidget {
  final String uid;
  final bool showPhone;
  final TextStyle? nameStyle;
  const DriverInfoLine({super.key, required this.uid, this.showPhone = true, this.nameStyle});

  @override
  State<DriverInfoLine> createState() => _DriverInfoLineState();
}

class _DriverInfoLineState extends State<DriverInfoLine> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
  }

  @override
  void didUpdateWidget(covariant DriverInfoLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-fetch if this widget instance is ever reused for a
    // genuinely different uid - never happens for a fixed booking card,
    // but kept correct just in case a list ever recycles widgets.
    if (oldWidget.uid != widget.uid) {
      _future = FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _future,
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
            Text('Driver: $name', style: widget.nameStyle ?? const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (widget.showPhone && phone != null && phone.trim().isNotEmpty)
              Text(phone, style: const TextStyle(color: PsEvColors.mutedText, fontSize: 11)),
          ],
        );
      },
    );
  }
}
