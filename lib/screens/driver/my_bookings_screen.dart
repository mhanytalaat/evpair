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
import '../../widgets/driver_info_line.dart';
import 'booking_status_screen.dart';

enum _BookingsViewMode { asDriver, asHost }

/// Public-facing enum so callers outside this file (e.g.
/// DriverHomeScreen) can specify which tab opens first.
enum BookingsViewMode { asDriver, asHost }

/// Driver-facing / host-facing booking list.
///
/// FIX (9/10 update): added the "As Driver" / "As Host" toggle so a host
/// no longer has to separately open each station just to see or act on a
/// pending request.
///
/// FIX (9/15 update - "having under my bookings the upcoming and the
/// running, the past can be saved under booking history under profile"):
/// this screen is reachable from TWO different places -
/// DriverHomeScreen's footer "bolt" icon (quick, in-the-moment access -
/// should only ever show what's actionable RIGHT NOW: upcoming/active/
/// pending) and Profile's "Booking History" row (a deliberate look-back
/// - should show everything, past included). Previously both entry
/// points opened the exact same screen showing BOTH sections every time.
/// Added [showPastSessions] (default true, so Profile's existing
/// behavior is completely unchanged) and [initialMode] (which toggle tab
/// opens first) so DriverHomeScreen's footer icon and the new
/// host-pending/host-running banners on the home map can each open this
/// screen pre-filtered to exactly "Upcoming & Active" only, in whichever
/// mode makes sense for what the user just tapped.
///
/// FIX (9/15 update - "host can be able to stop the service"): the host
/// "As Host" view's in-progress card now has a "Stop Session" button
/// (previously only the driver's own booking_status_screen.dart had a
/// Stop button - a host had no way at all to end a session themselves).
class MyBookingsScreen extends StatefulWidget {
  final bool showPastSessions;
  final BookingsViewMode initialMode;

  const MyBookingsScreen({
    super.key,
    this.showPastSessions = true,
    this.initialMode = BookingsViewMode.asDriver,
  });

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  Timer? _timer;
  late _BookingsViewMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode == BookingsViewMode.asHost ? _BookingsViewMode.asHost : _BookingsViewMode.asDriver;
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

  Widget _modeToggle() {
    Widget button(String label, _BookingsViewMode value) {
      final active = _mode == value;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _mode = value),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 4)] : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: active ? PsEvColors.emerald : PsEvColors.slateText,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: PsEvColors.slate200, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          button('As Driver', _BookingsViewMode.asDriver),
          button('As Host', _BookingsViewMode.asHost),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingService = context.watch<BookingService>();
    final app = context.watch<AppState>();
    final currentUserId = app.currentUserId ?? '';

    return Scaffold(
      appBar: PsEvAppBar(title: widget.showPastSessions ? 'My Bookings' : 'Upcoming Bookings'),
      body: Column(
        children: [
          _modeToggle(),
          Expanded(
            child: _mode == _BookingsViewMode.asDriver
                ? _buildDriverView(bookingService, currentUserId)
                : _buildHostView(bookingService, app, currentUserId),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Driver view: bookings THIS user made on other people's chargers.
  // -------------------------------------------------------------------
  Widget _buildDriverView(BookingService bookingService, String currentUserId) {
    final upcoming = bookingService.ongoingForDriver(currentUserId).reversed.toList();
    final past = widget.showPastSessions ? bookingService.pastForDriver(currentUserId) : const <Booking>[];
    final dateFmt = DateFormat('EEE, MMM d - h:mm a');

    if (upcoming.isEmpty && past.isEmpty) {
      return Center(
        child: Text(
          widget.showPastSessions ? 'No bookings yet as a driver.' : 'No upcoming or active bookings as a driver.',
          style: const TextStyle(color: PsEvColors.mutedText),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (upcoming.isNotEmpty) ...[
          const Text('Upcoming & Active', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
          const SizedBox(height: 8),
          ...upcoming.map((b) => _driverBookingCard(context, b, dateFmt)),
          const SizedBox(height: 12),
        ],
        if (past.isNotEmpty) ...[
          const Text('Past Sessions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
          const SizedBox(height: 8),
          ...past.map((b) => _driverBookingCard(context, b, dateFmt)),
        ],
        if (!widget.showPastSessions)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBookingsScreen())),
                child: const Text('View full booking history →'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _driverBookingCard(BuildContext context, Booking b, DateFormat dateFmt) {
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

  // -------------------------------------------------------------------
  // Host view: bookings OTHER drivers made on THIS user's chargers.
  // -------------------------------------------------------------------
  Widget _buildHostView(BookingService bookingService, AppState app, String currentUserId) {
    if (app.myChargers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "You haven't added a charging station yet, so you have no bookings to show as a host.\n"
            "Add one from Profile -> My Stations.",
            textAlign: TextAlign.center,
            style: TextStyle(color: PsEvColors.mutedText),
          ),
        ),
      );
    }

    final pending = bookingService.pendingApprovalsForHost(currentUserId);
    final confirmed = bookingService.confirmedForHost(currentUserId);
    final inProgress = bookingService.inProgressForHost(currentUserId);
    final past = widget.showPastSessions ? bookingService.completedForHost(currentUserId) : const <Booking>[];
    final dateFmt = DateFormat('EEE, MMM d - h:mm a');

    if (pending.isEmpty && confirmed.isEmpty && inProgress.isEmpty && past.isEmpty) {
      return const Center(child: Text('No bookings yet for your stations.', style: TextStyle(color: PsEvColors.mutedText)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pending.isNotEmpty) ...[
          const Text('Pending Approval', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
          const SizedBox(height: 8),
          ...pending.map((b) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(b.chargerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                          _pillFor(b.status),
                        ],
                      ),
                      const SizedBox(height: 6),
                      DriverInfoLine(uid: b.driverId),
                      Text('${dateFmt.format(b.requestedStart)} - ${DateFormat('h:mm a').format(b.requestedEnd)}',
                          style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                      Text('Held: ${b.heldAmount.toStringAsFixed(0)} EGP ✓', style: const TextStyle(fontSize: 12, color: PsEvColors.emerald)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => bookingService.hostRespond(b.id, approve: false),
                              child: const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => bookingService.hostRespond(b.id, approve: true),
                              child: const Text('Approve'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 12),
        ],
        if (confirmed.isNotEmpty || inProgress.isNotEmpty) ...[
          const Text('Upcoming & Active', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
          const SizedBox(height: 8),
          ...confirmed.map((b) => _hostBookingCard(b, dateFmt, showElapsed: false)),
          ...inProgress.map((b) => _hostBookingCard(b, dateFmt, showElapsed: true)),
          const SizedBox(height: 12),
        ],
        if (past.isNotEmpty) ...[
          const Text('Past Sessions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
          const SizedBox(height: 8),
          ...past.map((b) => _hostBookingCard(b, dateFmt, showElapsed: false)),
        ],
        if (!widget.showPastSessions)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyBookingsScreen(initialMode: BookingsViewMode.asHost)),
                ),
                child: const Text('View full booking history →'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _hostBookingCard(Booking b, DateFormat dateFmt, {required bool showElapsed}) {
    final canStop = b.status == BookingStatus.inProgress;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(b.chargerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                _pillFor(b.status),
              ],
            ),
            const SizedBox(height: 6),
            DriverInfoLine(uid: b.driverId),
            Text(
              b.status == BookingStatus.completed
                  ? dateFmt.format(b.sessionEndedAt ?? b.requestedEnd)
                  : '${dateFmt.format(b.requestedStart)} - ${DateFormat('h:mm a').format(b.requestedEnd)}',
              style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12),
            ),
            if (b.status == BookingStatus.completed)
              Text('Charged: ${b.actualCost?.toStringAsFixed(0) ?? '-'} EGP', style: const TextStyle(fontSize: 12, color: PsEvColors.emerald, fontWeight: FontWeight.w700)),
            if (showElapsed && b.sessionStartedAt != null) ...[
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
            // NEW (9/15 update): lets the HOST stop a running session
            // themselves, instead of only ever being able to wait for
            // the driver to stop it. Calls the same completeSession()
            // logic (via hostStopSession, a clearly-named alias), which
            // now routes the host's earnings through admin approval -
            // see services/booking_service.dart / wallet_service.dart.
            if (canStop) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Stop this charging session?'),
                        content: const Text(
                          "This ends the driver's session now and calculates their final cost. "
                          'Your payout will be sent to admin for review before being released to your wallet.',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop Session')),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      // ignore: use_build_context_synchronously
                      await context.read<BookingService>().hostStopSession(b.id);
                    }
                  },
                  icon: const Icon(Icons.stop_circle_outlined, color: PsEvColors.red, size: 18),
                  label: const Text('Stop Session', style: TextStyle(color: PsEvColors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: PsEvColors.red)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
