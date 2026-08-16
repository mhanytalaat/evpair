import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/booking_service.dart';
import '../../state/app_state.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';

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

  @override
  Widget build(BuildContext context) {
    final bookingService = context.watch<BookingService>();
    final confirmed = bookingService.confirmedForHost(kCurrentUserId);
    final inProgress = bookingService.inProgressForHost(kCurrentUserId);

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
              content: Text('${b.driverId} started charging at ${b.chargerName}'),
              backgroundColor: PsEvColors.emerald,
            ),
          );
        }
      }
    });

    if (confirmed.isEmpty && inProgress.isEmpty) {
      return const Scaffold(
        appBar: PsEvAppBar(title: 'Active Sessions'),
        body: Center(child: Text('No confirmed or active sessions right now.', style: TextStyle(color: PsEvColors.mutedText))),
      );
    }

    return Scaffold(
      appBar: const PsEvAppBar(title: 'Active Sessions'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (confirmed.isNotEmpty) ...[
            const Text('Booked · Awaiting Start', style: TextStyle(fontWeight: FontWeight.bold)),
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
                              Text('Driver: ${b.driverId}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
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
                                  Text('Driver: ${b.driverId}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
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
                      ],
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
