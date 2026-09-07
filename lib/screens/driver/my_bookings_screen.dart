import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../services/booking_service.dart';
import '../../models/booking.dart';
import '../../models/enums.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import 'booking_status_screen.dart';

/// Driver-facing booking history.
///
/// FIX (7/9 update, items #4/#9/#14): this screen previously only ever
/// showed [BookingService.ongoingForDriver] (pending/confirmed/in-
/// progress bookings) - a driver's PAST (completed, or
/// cancelled/declined/expired) sessions had no home anywhere in the app
/// at all. Now shows two clearly separated sections: "Upcoming &
/// Active" and "Past Sessions".
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  PsEvStatusPill _pillFor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pendingWalletHold:
      case BookingStatus.pendingHostApproval:
        return const PsEvStatusPill(label: 'Pending', background: PsEvColors.amberChip, textColor: PsEvColors.amberChipText);
      case BookingStatus.confirmed:
        return PsEvStatusPill.bookedAwaitingScan();
      case BookingStatus.inProgress:
        return PsEvStatusPill.charging();
      case BookingStatus.completed:
        return const PsEvStatusPill(label: 'Completed', background: PsEvColors.emeraldChip, textColor: PsEvColors.emeraldChipText);
      case BookingStatus.declinedByHost:
        return const PsEvStatusPill(label: 'Declined', background: PsEvColors.redChip, textColor: PsEvColors.redChipText);
      case BookingStatus.cancelledByDriver:
      case BookingStatus.cancelledByAdmin:
        return const PsEvStatusPill(label: 'Cancelled', background: PsEvColors.slate100, textColor: PsEvColors.slateText);
      case BookingStatus.expired:
        return const PsEvStatusPill(label: 'Expired', background: PsEvColors.slate100, textColor: PsEvColors.slateText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingService = context.watch<BookingService>();
    final currentUserId = context.watch<AppState>().currentUserId ?? '';
    final upcoming = bookingService.ongoingForDriver(currentUserId).reversed.toList();
    final past = bookingService.pastForDriver(currentUserId);
    final dateFmt = DateFormat('EEE, MMM d - h:mm a');

    if (upcoming.isEmpty && past.isEmpty) {
      return const Scaffold(
        appBar: PsEvAppBar(title: 'My Bookings'),
        body: Center(child: Text('No bookings yet.', style: TextStyle(color: PsEvColors.mutedText))),
      );
    }

    return Scaffold(
      appBar: const PsEvAppBar(title: 'My Bookings'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (upcoming.isNotEmpty) ...[
            const Text('Upcoming & Active', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
            const SizedBox(height: 8),
            ...upcoming.map((b) => _bookingCard(context, b, dateFmt)),
            const SizedBox(height: 12),
          ],
          if (past.isNotEmpty) ...[
            const Text('Past Sessions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
            const SizedBox(height: 8),
            ...past.map((b) => _bookingCard(context, b, dateFmt)),
          ],
        ],
      ),
    );
  }

  Widget _bookingCard(BuildContext context, Booking b, DateFormat dateFmt) {
    final inProgress = b.status == BookingStatus.inProgress && b.sessionStartedAt != null;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(PsEvRadii.card),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingStatusScreen(bookingId: b.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.chargerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(dateFmt.format(b.requestedStart), style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                      ],
                    ),
                  ),
                  _pillFor(b.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                b.status == BookingStatus.completed
                    ? 'Charged: ${b.actualCost?.toStringAsFixed(0) ?? '-'} EGP of ${b.heldAmount.toStringAsFixed(0)} EGP held'
                    : 'Held: ${b.heldAmount.toStringAsFixed(0)} EGP',
                style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText),
              ),
              if (inProgress) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: PsEvColors.blueChip, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    _formatElapsed(DateTime.now().difference(b.sessionStartedAt!)),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: PsEvColors.blueChipText),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
