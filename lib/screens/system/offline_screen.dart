import 'package:flutter/material.dart';
import '../../services/connectivity_service.dart';
import '../../theme/ps_ev_theme.dart';

/// Full-screen "You're offline" state, shown instead of a blank white
/// screen whenever there's no working internet connection (item #1 of
/// the 7/9 update).
class OfflineScreen extends StatefulWidget {
  const OfflineScreen({super.key});

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await ConnectivityService.instance.checkNow();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: PsEvColors.slate100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wifi_off_rounded, size: 42, color: PsEvColors.mutedText),
                ),
                const SizedBox(height: 22),
                const Text(
                  "You're offline",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'EVPair needs an internet connection to load stations, bookings, and your '
                  'wallet. Please check your Wi-Fi or mobile data and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PsEvColors.mutedText, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 200,
                  child: PsEvFilledButton(
                    icon: Icons.refresh,
                    label: _retrying ? 'Checking...' : 'Try Again',
                    onTap: _retrying ? null : _retry,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] and transparently swaps in [OfflineScreen] whenever
/// [ConnectivityService] reports no connection - and swaps back to
/// [child] automatically the instant connectivity returns, with no user
/// action needed. Place this ABOVE the app's normal navigation stack
/// (see screens/system/app_bootstrap.dart) so it can react to
/// connectivity loss no matter which screen the user is currently on.
class OfflineGate extends StatefulWidget {
  final Widget child;
  const OfflineGate({super.key, required this.child});

  @override
  State<OfflineGate> createState() => _OfflineGateState();
}

class _OfflineGateState extends State<OfflineGate> {
  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    ConnectivityService.instance.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!ConnectivityService.instance.isOnline) {
      return const OfflineScreen();
    }
    return widget.child;
  }
}
