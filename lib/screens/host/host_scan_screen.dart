import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/booking_service.dart';
import '../../state/app_state.dart';
import '../../models/booking.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import '../../widgets/driver_info_line.dart';

/// Host-facing "Active Sessions" screen.
///
/// FIX (9/15 update - "host can be able to stop the service as the host
/// doesn't have the option of that"): the "Charging Now" card previously
/// showed only a live duration counter with no action at all - the host
/// had no way to end a session themselves and had to wait for the
/// driver to stop it. Added a "Stop Session" button that calls
/// `BookingService.hostStopSession()` (a clearly-named alias for the
/// same `completeSession()` logic the driver already uses), with a
/// confirmation dialog explaining that the payout now goes to admin for
/// review before landing in the host's wallet (see
/// services/wallet_service.dart's new payout-approval flow).
class HostScanScreen extends StatefulWidget {
  const HostScanScreen({super.key});
  @override
  State<HostScanScreen> createState() => _HostScanScreenState();
}

class _HostScanScreenState extends State<HostScanScreen> {
  Timer? _timer;
  final Set<String> _announcedInProgressIds = {};
  bool _seededInitialSessions = false;

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

  Future<void> _confirmAndStop(BuildContext context, Booking b) async {
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
    if (confirmed == true && context.mounted) {
      await context.read<BookingService>().hostStopSession(b.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session stopped. Payout is now waiting for admin review.'), backgroundColor: PsEvColors.emerald),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingService = context.watch<BookingService>();
    final currentUserId = context.watch<AppState>().currentUserId ?? '';
    final confirmed = bookingService.confirmedForHost(currentUserId);
    final inProgress = bookingService.inProgressForHost(currentUserId);
    final past = bookingService.completedForHost(currentUserId);
    final dateFmt = DateFormat('EEE, MMM d - h:mm a');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_seededInitialSessions) {
        _announcedInProgressIds.addAll(inProgress.map((b) => b.id));
        _seededInitialSessions = true;
        return;
      }
      for (final b in inProgress) {
        if (!_announcedInProgressIds.contains(b.id)) {
          _announcedInProgressIds.add(b.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('A driver started charging at ${b.chargerName}'),
              backgroundColor: PsEvColors.emerald,
            ),
          );
        }
      }
    });

    if (confirmed.isEmpty && inProgress.isEmpty && past.isEmpty) {
      return const Scaffold(
        appBar: PsEvAppBar(title: 'Active Sessions'),
        body: Center(child: Text('No sessions yet for your stations.', style: TextStyle(color: PsEvColors.mutedText))),
      );
    }
    return Scaffold(
      appBar: const PsEvAppBar(title: 'Active Sessions'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (confirmed.isNotEmpty) ...[
            const Text('Upcoming - Booked, Awaiting Start', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...confirmed.map((b) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.chargerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              DriverInfoLine(uid: b.driverId),
                              Text(
                                '${dateFmt.format(b.requestedStart)} - ${DateFormat('h:mm a').format(b.requestedEnd)}',
                                style: const TextStyle(color: PsEvColors.mutedText, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        PsEvStatusPill.bookedAwaitingScan(),
                      ],
                    ),
                  ),
                )),
            const SizedBox(height: 16),
          ],
          if (inProgress.isNotEmpty) ...[
            const Text('Charging Now', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...inProgress.map((b) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
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
                                  Text(b.chargerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  DriverInfoLine(uid: b.driverId),
                                ],
                              ),
                            ),
                            PsEvStatusPill.charging(),
                          ],
                        ),
                        if (b.sessionStartedAt != null) ...[
                          const SizedBox(height: 10),
                          const Text('Session duration', style: TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            decoration: BoxDecoration(color: PsEvColors.blueChip, borderRadius: BorderRadius.circular(14)),
                            child: Text(
                              _formatElapsed(DateTime.now().difference(b.sessionStartedAt!)),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: PsEvColors.blueChipText),
                            ),
                          ),
                        ],
                        // NEW (9/15 update): host-initiated stop, mirroring
                        // the driver's own Stop button on
                        // booking_status_screen.dart.
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _confirmAndStop(context, b),
                            icon: const Icon(Icons.stop_circle_outlined, color: PsEvColors.red, size: 18),
                            label: const Text('Stop Session', style: TextStyle(color: PsEvColors.red)),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: PsEvColors.red)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
            const SizedBox(height: 16),
          ],
          if (past.isNotEmpty) ...[
            const Text('Past Sessions', style: TextStyle(fontWeight: FontWeight.bold)),
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 8),
              child: Text('Stations you have previously rented out.', style: TextStyle(fontSize: 11, color: PsEvColors.mutedText)),
            ),
            ...past.map((b) => _pastSessionCard(b, dateFmt)),
          ],
        ],
      ),
    );
  }

  Widget _pastSessionCard(Booking b, DateFormat dateFmt) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.chargerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  DriverInfoLine(uid: b.driverId),
                  Text(
                    dateFmt.format(b.sessionEndedAt ?? b.requestedEnd),
                    style: const TextStyle(color: PsEvColors.mutedText, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              'Charged: ${b.actualCost?.toStringAsFixed(0) ?? '-'} EGP',
              style: const TextStyle(fontSize: 12, color: PsEvColors.emerald, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
