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
      default:
        return const PsEvStatusPill(label: 'Other', background: PsEvColors.slate100, textColor: PsEvColors.slateText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingService = context.watch<BookingService>();
    final bookings = bookingService.ongoingForDriver(kCurrentUserId).reversed.toList();
    final dateFmt = DateFormat('EEE, MMM d • h:mm a');

    return Scaffold(
      appBar: const PsEvAppBar(title: 'My Bookings'),
      body: bookings.isEmpty
          ? const Center(child: Text('No booked or ongoing sessions right now.', style: TextStyle(color: PsEvColors.mutedText)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: bookings.map((b) => _bookingCard(context, b, dateFmt)).toList(),
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
              Text('Held: ${b.heldAmount.toStringAsFixed(0)} EGP', style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
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
