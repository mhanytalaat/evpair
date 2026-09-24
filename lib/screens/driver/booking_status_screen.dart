import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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

/// Option A business rule: the RESERVED WINDOW is fixed regardless of
/// when the driver actually starts charging.
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

  String _formatDuration(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Future<void> _startSession(BuildContext context, BookingService bookingService) async {
    final ok = await bookingService.startSession(widget.bookingId);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can start this session closer to your reserved time.'),
          backgroundColor: PsEvColors.amber,
        ),
      );
    }
  }
Future<void> _confirmAndCancel(BuildContext context, BookingService bookingService, dynamic booking) async {
    final isFundsHeld = booking.walletHeld;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Text(
          isFundsHeld
              ? 'Your held funds (${booking.heldAmount.toStringAsFixed(0)} EGP) will be refunded to your wallet immediately.'
              : 'Are you sure you want to cancel this booking request?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Booking')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel Booking')),
        ],
      ),
    );
    if (confirmed != true) return;
    await bookingService.driverCancel(booking.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled.'), backgroundColor: PsEvColors.emerald),
      );
    }
  }


  Future<bool> _confirmStopIfOverstaying(BuildContext context, dynamic booking) async {
    final lateBy = DateTime.now().difference(booking.requestedEnd).inMinutes;
    const grace = 15;
    if (lateBy <= grace) return true;
    final extraMinutes = lateBy - grace;
    final estimatedPenalty = extraMinutes * 2.0;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('You are past your reserved window'),
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

  Widget _reservedWindowCard(dynamic booking) {
    final dateFmt = DateFormat('EEE, MMM d, yyyy');
    final timeFmt = DateFormat('h:mm a');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: PsEvColors.slate100, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reserved Window', style: TextStyle(fontSize: 11, color: PsEvColors.mutedText, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(dateFmt.format(booking.requestedStart), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            '${timeFmt.format(booking.requestedStart)} → ${timeFmt.format(booking.requestedEnd)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _politeOverstayNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: PsEvColors.amberChip, borderRadius: BorderRadius.circular(12)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 15, color: PsEvColors.amberChipText),
              SizedBox(width: 6),
              Text('Please respect your reserved window', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: PsEvColors.amberChipText)),
            ],
          ),
          SizedBox(height: 4),
          Text(
            'If your vehicle remains connected or occupies the station after your booked end time, an '
            'overstay fee may apply after a short grace period. This helps keep chargers available for '
            'other EV drivers.',
            style: TextStyle(fontSize: 11, color: PsEvColors.amberChipText),
          ),
        ],
      ),
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
    final showHostContact = booking.status == BookingStatus.confirmed ||
        booking.status == BookingStatus.inProgress ||
        booking.status == BookingStatus.completed;
    final hasOverstayPenalty = booking.status == BookingStatus.completed && (booking.overstayPenalty ?? 0) > 0;
    final showRatePrompt = booking.status == BookingStatus.completed &&
        !ratingService.hasRatedBooking(booking.id, RaterRole.driver);

    final now = DateTime.now();
    final isPastReservedEnd = now.isAfter(booking.requestedEnd);
    final timeRemaining = isPastReservedEnd ? Duration.zero : booking.requestedEnd.difference(now);
    final overstayDuration = isPastReservedEnd ? now.difference(booking.requestedEnd) : Duration.zero;
    const graceDuration = Duration(minutes: 15);
    final overstayFeesAccruing = overstayDuration > graceDuration;

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
                  // FIX (3/9 update - "host name/phone keeps flashing/
                  // reloading"): _HostContactCard is now given a
                  // ValueKey based on hostId, and internally caches its
                  // Future in initState instead of calling .get() fresh
                  // inside `build`/FutureBuilder's `future:` parameter.
                  // Root cause: this whole screen has a Timer.periodic
                  // ticking every second (for the live counters below),
                  // which calls setState() every second and rebuilds
                  // this ENTIRE widget tree - including recreating
                  // _HostContactCard as a "new" widget each time, which
                  // made its old FutureBuilder start a BRAND NEW
                  // Firestore fetch every single second (loading -> data
                  // -> loading -> data, on a 1-second loop). Since
                  // hostId never actually changes for a given booking,
                  // keying the widget + caching the fetch means Flutter
                  // now reuses the SAME State object across every
                  // per-second rebuild, and the Firestore call only
                  // fires once.
                  if (showHostContact) ...[
                    const SizedBox(height: 14),
                    _HostContactCard(key: ValueKey('host_contact_${booking.hostId}'), hostId: booking.hostId),
                  ],
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

                  if (booking.status == BookingStatus.pendingWalletHold ||
                      booking.status == BookingStatus.pendingHostApproval ||
                      booking.status == BookingStatus.confirmed) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: 220,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmAndCancel(context, bookingService, booking),
                        icon: const Icon(Icons.cancel_outlined, color: PsEvColors.red, size: 18),
                        label: const Text('Cancel Booking', style: TextStyle(color: PsEvColors.red)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: PsEvColors.red)),
                      ),
                    ),
                  ],

                  if (booking.status == BookingStatus.confirmed) ...[
                    const SizedBox(height: 14),
                    _reservedWindowCard(booking),
                    const SizedBox(height: 10),
                    _politeOverstayNotice(),
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
                  if (booking.status == BookingStatus.inProgress) ...[
                    const SizedBox(height: 14),
                    _reservedWindowCard(booking),
                    if (booking.sessionStartedAt != null) ...[
                      const SizedBox(height: 14),
                      const Text('Charging Duration', style: TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(color: PsEvColors.blueChip, borderRadius: BorderRadius.circular(14)),
                        child: Text(
                          _formatDuration(now.difference(booking.sessionStartedAt!)),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: PsEvColors.blueChipText),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (!isPastReservedEnd) ...[
                      const Text('Time Remaining in Reservation', style: TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(color: PsEvColors.emeraldPale, borderRadius: BorderRadius.circular(14)),
                        child: Text(
                          _formatDuration(timeRemaining),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: PsEvColors.emeraldChipText),
                        ),
                      ),
                    ] else ...[
                      Text(
                        overstayFeesAccruing ? 'Overstay Time (fees accruing)' : 'Overstay Time (within grace period)',
                        style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: overstayFeesAccruing ? PsEvColors.redChip : PsEvColors.amberChip,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _formatDuration(overstayDuration),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: overstayFeesAccruing ? PsEvColors.redChipText : PsEvColors.amberChipText,
                          ),
                        ),
                      ),
                      if (overstayFeesAccruing)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Overstay fees are now accruing on your wallet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: PsEvColors.red, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
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
                          await bookingService.completeSession(booking.id);
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

/// Looks up the host's name + phone from `users/{hostId}` and shows it
/// with a tappable phone number.
///
/// FIX (3/9 update - "flashing/reloading"): the Firestore fetch is now
/// started ONCE in `initState()` and cached in `_future`, instead of
/// being created inline inside a `FutureBuilder(future: ...)` build
/// call. The old inline version created a BRAND NEW Future (and
/// therefore a brand new pending Firestore request) every single time
/// this widget was rebuilt - which, combined with BookingStatusScreen's
/// per-second Timer.periodic, meant it was re-fetching from Firestore
/// once every second. Caching the Future in State means this widget
/// keeps showing its already-loaded data across every parent rebuild,
/// and only re-fetches if it's ever actually recreated with a
/// DIFFERENT hostId (see the `didUpdateWidget` override below), or on
/// the very first build for a given hostId (the `key:` passed from
/// BookingStatusScreen also helps Flutter recognize this is "the same"
/// widget across rebuilds, rather than a new one, for extra safety).
class _HostContactCard extends StatefulWidget {
  final String hostId;
  const _HostContactCard({super.key, required this.hostId});

  @override
  State<_HostContactCard> createState() => _HostContactCardState();
}

class _HostContactCardState extends State<_HostContactCard> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirebaseFirestore.instance.collection('users').doc(widget.hostId).get();
  }

  @override
  void didUpdateWidget(covariant _HostContactCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-fetch if this card is ever reused for a genuinely
    // different host - never happens for a single booking's lifetime,
    // but kept correct just in case.
    if (oldWidget.hostId != widget.hostId) {
      _future = FirebaseFirestore.instance.collection('users').doc(widget.hostId).get();
    }
  }

  Future<void> _callHost(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the phone dialer.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 20, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))));
        }
        String name = 'Host';
        String? phone;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          final first = data?['firstName'] as String? ?? '';
          final last = data?['lastName'] as String? ?? '';
          final fullName = [first, last].where((v) => v.trim().isNotEmpty).join(' ');
          if (fullName.isNotEmpty) name = fullName;
          phone = data?['phone'] as String?;
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: PsEvColors.slate100, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              const CircleAvatar(radius: 18, backgroundColor: PsEvColors.emerald, child: Icon(Icons.person, color: Colors.white, size: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Host: $name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    if (phone != null && phone.trim().isNotEmpty)
                      Text(phone, style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                  ],
                ),
              ),
              if (phone != null && phone.trim().isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.call, color: PsEvColors.emerald),
                  onPressed: () => _callHost(context, phone!),
                ),
            ],
          ),
        );
      },
    );
  }
}
