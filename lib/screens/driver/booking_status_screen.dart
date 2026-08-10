import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/booking_service.dart';
import '../../models/enums.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';

class _StatusMeta {
  final String text;
  final Color color;
  final IconData icon;
  const _StatusMeta(this.text, this.color, this.icon);
}

/// UPDATED: the QR-code display (shown once a booking was `confirmed`) is
/// PAUSED FOR NOW - replaced with a simple "Start Charging Session"
/// button. Once started, a "Stop Charging Session" button appears next to
/// the live duration counter, letting the driver end their own session
/// (in addition to the host still being able to do so from their side).
/// The underlying QR code/scan machinery in Booking/BookingService is
/// untouched and can be re-enabled later if needed.
class BookingStatusScreen extends StatefulWidget {
  final String bookingId;
  const BookingStatusScreen({super.key, required this.bookingId});

  @override
  State<BookingStatusScreen> createState() => _BookingStatusScreenState();
}

class _BookingStatusScreenState extends State<BookingStatusScreen> {
  Timer? _timer;

  static const Map<BookingStatus, _StatusMeta> _statusMeta = {
    BookingStatus.pendingWalletHold: _StatusMeta('Waiting for wallet payment...', PsEvColors.amber, Icons.hourglass_top),
    BookingStatus.pendingHostApproval: _StatusMeta('Payment held. Waiting for host approval...', PsEvColors.amber, Icons.hourglass_top),
    BookingStatus.confirmed: _StatusMeta('Confirmed! Tap Start when you plug in.', PsEvColors.emerald, Icons.check_circle),
    BookingStatus.inProgress: _StatusMeta('Charging session in progress', PsEvColors.blue, Icons.bolt),
    BookingStatus.completed: _StatusMeta('Session completed. Thank you for using EVPair!', PsEvColors.emerald, Icons.check_circle),
    BookingStatus.declinedByHost: _StatusMeta('Host declined this request. Funds refunded.', PsEvColors.red, Icons.cancel),
    BookingStatus.cancelledByDriver: _StatusMeta('You cancelled this booking.', PsEvColors.mutedText, Icons.cancel),
    BookingStatus.cancelledByAdmin: _StatusMeta('Cancelled by admin. Funds refunded.', PsEvColors.red, Icons.cancel),
    BookingStatus.expired: _StatusMeta('This booking request expired.', PsEvColors.mutedText, Icons.cancel),
  };

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

  void _startSession(BuildContext context, BookingService bookingService) {
    final ok = bookingService.startSession(widget.bookingId);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can start this session closer to your reserved time.'),
          backgroundColor: PsEvColors.amber,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingService = context.watch<BookingService>();
    final booking = bookingService.findById(widget.bookingId);

    if (booking == null) {
      return Scaffold(appBar: const PsEvAppBar(title: 'Booking Status'), body: const Center(child: Text('Booking not found.')));
    }

    final meta = _statusMeta[booking.status]!;

    return Scaffold(
      appBar: const PsEvAppBar(title: 'Booking Status'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(meta.icon, size: 44, color: meta.color),
                  const SizedBox(height: 10),
                  Text(meta.text, style: TextStyle(color: meta.color, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(booking.chargerName, style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),

                  // ---- Confirmed: show Start button (QR paused for now) ----
                  if (booking.status == BookingStatus.confirmed) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 220,
                      child: PsEvFilledButton(
                        icon: Icons.play_arrow,
                        label: 'Start Charging Session',
                        onTap: () => _startSession(context, bookingService),
                      ),
                    ),
                  ],

                  // ---- In progress: live timer + Stop button ----
                  if (booking.status == BookingStatus.inProgress && booking.sessionStartedAt != null) ...[
                    const SizedBox(height: 12),
                    const Text('Session duration (billed for actual usage)', style: TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(color: PsEvColors.blueChip, borderRadius: BorderRadius.circular(14)),
                      child: Text(
                        _formatElapsed(DateTime.now().difference(booking.sessionStartedAt!)),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: PsEvColors.blueChipText),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 220,
                      child: PsEvFilledButton(
                        icon: Icons.stop,
                        label: 'Stop Charging Session',
                        color: PsEvColors.red,
                        onTap: () => bookingService.completeSession(booking.id),
                      ),
                    ),
                  ],

                  if (booking.status == BookingStatus.completed && booking.actualCost != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Charged: ${booking.actualCost!.toStringAsFixed(0)} EGP of ${booking.heldAmount.toStringAsFixed(0)} EGP held',
                        style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
