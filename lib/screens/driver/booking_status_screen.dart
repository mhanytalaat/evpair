import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/booking_service.dart';
import '../../services/map_launcher_service.dart';
import '../../services/rating_service.dart';
import '../../models/enums.dart';
import '../../models/rating.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import '../shared/rate_user_dialog.dart';

class _StatusMeta {
  final String text;
  final Color color;
  final IconData icon;
  const _StatusMeta(this.text, this.color, this.icon);
}

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
    BookingStatus.confirmed: _StatusMeta('Confirmed! Head to the charger location and tap Start when you plug in.', PsEvColors.emerald, Icons.check_circle),
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

  /// Warns the driver BEFORE they stop the session if they're already
  /// past their booked end time + grace period, so the overstay penalty
  /// (charged in BookingService.completeSession) is never a surprise.
  Future<bool> _confirmStopIfOverstaying(BuildContext context, dynamic booking) async {
    final lateBy = DateTime.now().difference(booking.requestedEnd).inMinutes;
    const grace = 15; // kept in sync with kOverstayGraceMinutes in models/booking.dart
    if (lateBy <= grace) return true;

    final extraMinutes = lateBy - grace;
    final estimatedPenalty = extraMinutes * 2.0; // kept in sync with kOverstayPenaltyPerMinute

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('You are past your booked time'),
        content: Text(
          'Your reserved window ended $lateBy minutes ago. Stopping now will add an overstay '
          'penalty of approximately ${estimatedPenalty.toStringAsFixed(0)} EGP to your wallet, '
          'part of which goes to the host as compensation for the blocked station time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop Anyway')),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _rateHost(BuildContext context, dynamic booking) async {
    await showRateUserDialog(
      context,
      title: 'Rate Your Host',
      subtitle: 'How was your charging experience at ${booking.chargerName}?',
      bookingId: booking.id,
      chargerId: booking.chargerId,
      raterId: booking.driverId,
      raterRole: RaterRole.driver,
      rateeId: booking.hostId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingService = context.watch<BookingService>();
    final ratingService = context.watch<RatingService>();
    final booking = bookingService.findById(widget.bookingId);
    if (booking == null) {
      return Scaffold(appBar: const PsEvAppBar(title: 'Booking Status'), body: const Center(child: Text('Booking not found.')));
    }
    final meta = _statusMeta[booking.status]!;
    final showMapButton = booking.status == BookingStatus.confirmed || booking.status == BookingStatus.inProgress;
    final hasOverstayPenalty = booking.status == BookingStatus.completed && (booking.overstayPenalty ?? 0) > 0;
    final showRatePrompt = booking.status == BookingStatus.completed &&
        !ratingService.hasRatedBooking(booking.id, RaterRole.driver);

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
                  if (showMapButton) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: 240,
                      child: OutlinedButton.icon(
                        onPressed: () => showMapAppChooser(
                          context,
                          latitude: booking.chargerLatitude,
                          longitude: booking.chargerLongitude,
                          label: booking.chargerName,
                        ),
                        icon: const Icon(Icons.location_on, size: 18, color: PsEvColors.emerald),
                        label: const Text('Choose Maps App', style: TextStyle(color: PsEvColors.emerald, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                  if (booking.status == BookingStatus.confirmed) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 220,
                      child: PsEvFilledButton(
                        icon: Icons.play_arrow,
                        label: 'Start Charging Session',
                        onTap: () => _startSession(context, bookingService),
                      ),
                    ),
                  ],
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
                    if (DateTime.now().isAfter(booking.requestedEnd.add(const Duration(minutes: 15))))
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'You are past your reserved end time - an overstay penalty will apply when you stop.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: PsEvColors.red, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 220,
                      child: PsEvFilledButton(
                        icon: Icons.stop,
                        label: 'Stop Charging Session',
                        color: PsEvColors.red,
                        onTap: () async {
                          final proceed = await _confirmStopIfOverstaying(context, booking);
                          if (!proceed) return;
                          bookingService.completeSession(booking.id);
                        },
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
                  if (hasOverstayPenalty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: PsEvColors.redChip, borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          'Overstay penalty: ${booking.overstayPenalty!.toStringAsFixed(0)} EGP '
                          '(${booking.overstayMinutes} min past the grace period)',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: PsEvColors.redChipText, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),

                  // -----------------------------------------------------
                  // Rate Your Host - only shown once the session is
                  // completed and only until the driver actually submits
                  // (or explicitly skips) a rating for this booking. See
                  // RatingService.hasRatedBooking for the persistence
                  // logic.
                  // -----------------------------------------------------
                  if (showRatePrompt)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: PsEvColors.emeraldPale, borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          children: [
                            const Icon(Icons.star_rate_rounded, color: PsEvColors.amber, size: 28),
                            const SizedBox(height: 6),
                            const Text(
                              'How was your charging experience?',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: 200,
                              child: PsEvFilledButton(
                                icon: Icons.star_outline,
                                label: 'Rate Your Host',
                                onTap: () => _rateHost(context, booking),
                              ),
                            ),
                          ],
                        ),
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
