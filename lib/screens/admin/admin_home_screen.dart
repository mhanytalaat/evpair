import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/wallet_service.dart';
import '../../services/booking_service.dart';
import '../../models/enums.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';

/// FIX (9/17 update - "I need the notification to redirect to the
/// request"): added an optional [initialTab] constructor param (0 =
/// Top-Ups, 1 = Payouts, 2 = Bookings; defaults to 0, matching the
/// previous always-Top-Ups-first behavior exactly) so
/// notifications_screen.dart can deep-link an admin straight into the
/// correct tab for a "New top-up request" or "Payout ready for review"
/// notification, instead of always landing on Top-Ups regardless of
/// which one was tapped.
class AdminHomeScreen extends StatefulWidget {
  final int initialTab;
  const AdminHomeScreen({super.key, this.initialTab = 0});
  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  late int _tab;
  String _bookingFilter = 'ongoing';

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  static const _statusText = {
    BookingStatus.pendingWalletHold: 'Pending wallet hold',
    BookingStatus.pendingHostApproval: 'Pending host approval',
    BookingStatus.confirmed: 'Confirmed',
    BookingStatus.inProgress: 'In progress',
    BookingStatus.completed: 'Completed',
    BookingStatus.declinedByHost: 'Declined by host',
    BookingStatus.cancelledByDriver: 'Cancelled by driver',
    BookingStatus.cancelledByAdmin: 'Cancelled by admin',
    BookingStatus.expired: 'Expired',
  };

  Color _statusColor(BookingStatus s) {
    if (s == BookingStatus.completed) return PsEvColors.emerald;
    if (BookingService.ongoingStatuses.contains(s)) return PsEvColors.amber;
    return PsEvColors.red;
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final bookingService = context.watch<BookingService>();
    return Scaffold(
      appBar: PsEvAppBar(title: 'Admin Panel', showBrandRow: true, actions: const [PsEvModePill(label: 'admin mode')]),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: PsEvColors.slate200, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Expanded(child: _tabButton('Top-Ups', 0, badge: wallet.pendingTopUps.length)),
                Expanded(child: _tabButton('Payouts', 1, badge: wallet.pendingPayouts.length)),
                Expanded(child: _tabButton('Bookings', 2)),
              ],
            ),
          ),
          Expanded(
            child: switch (_tab) {
              0 => _buildTopUps(wallet),
              1 => _buildPayouts(wallet),
              _ => _buildBookings(bookingService),
            },
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index, {int badge = 0}) {
    final active = _tab == index;
    return InkWell(
      onTap: () => setState(() => _tab = index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 4)] : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: active ? PsEvColors.emerald : PsEvColors.slateText, fontWeight: FontWeight.w600, fontSize: 13)),
            if (badge > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: const BoxDecoration(color: PsEvColors.red, shape: BoxShape.circle),
                child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopUps(WalletService wallet) {
    final pending = wallet.pendingTopUps;
    if (pending.isEmpty) {
      return const Center(child: Text('No pending top-up requests.', style: TextStyle(color: PsEvColors.mutedText)));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: pending.map((t) => Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _UserInfoText(uid: t.driverId, roleLabel: 'Driver'),
                  const SizedBox(height: 4),
                  Text('${t.amount.toStringAsFixed(0)} EGP via ${t.method.name}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                  Text('Ref: ${t.referenceNote}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: () => wallet.reviewTopUp(t.id, approve: false, adminNote: 'Proof invalid'), child: const Text('Reject'))),
                      const SizedBox(width: 8),
                      Expanded(child: ElevatedButton(onPressed: () => wallet.reviewTopUp(t.id, approve: true), child: const Text('Approve & Credit'))),
                    ],
                  ),
                ],
              ),
            ),
          )).toList(),
    );
  }

  Widget _buildPayouts(WalletService wallet) {
    final pending = wallet.pendingPayouts;
    if (pending.isEmpty) {
      return const Center(child: Text('No payouts waiting for release.', style: TextStyle(color: PsEvColors.mutedText)));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: pending.map((p) => Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(p.chargerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                      PsEvStatusPill(label: 'Pending release', background: PsEvColors.amberChip, textColor: PsEvColors.amberChipText),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _UserInfoText(uid: p.hostId, roleLabel: 'Host'),
                  const SizedBox(height: 4),
                  _UserInfoText(uid: p.driverId, roleLabel: 'Driver'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: PsEvColors.slate100, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Calculation', style: TextStyle(fontSize: 11, color: PsEvColors.mutedText, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(p.calculationLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          'Driver charged: ${p.actualCost.toStringAsFixed(0)} EGP  •  Commission: ${(p.commissionRate * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 11, color: PsEvColors.mutedText),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Amount to release: ${p.hostAmount.toStringAsFixed(0)} EGP',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: PsEvColors.emerald),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => wallet.reviewPayout(p.id, approve: false, adminNote: 'Withheld by admin'),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => wallet.reviewPayout(p.id, approve: true),
                          child: const Text('Release Payment'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )).toList(),
    );
  }

  Widget _buildBookings(BookingService bookingService) {
    final bookings = bookingService.filterByCategory(_bookingFilter).reversed.toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 6,
            children: [
              _filterChip('All', 'all'),
              _filterChip('Ongoing', 'ongoing'),
              _filterChip('Completed', 'completed'),
              _filterChip('Cancelled', 'cancelled'),
            ],
          ),
        ),
        Expanded(
          child: bookings.isEmpty
              ? const Center(child: Text('No bookings in this category.', style: TextStyle(color: PsEvColors.mutedText)))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: bookings.map((b) {
                    final isOngoing = BookingService.ongoingStatuses.contains(b.status);
                    return Card(
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
                                      Text(b.chargerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      _UserInfoText(uid: b.driverId, roleLabel: 'Driver'),
                                      Text(
                                        b.status == BookingStatus.completed
                                            ? 'Charged: ${b.actualCost?.toStringAsFixed(0) ?? '-'} EGP'
                                            : 'Held: ${b.heldAmount.toStringAsFixed(0)} EGP${b.walletHeld ? '' : ' (released)'}',
                                        style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText),
                                      ),
                                    ],
                                  ),
                                ),
                                PsEvStatusPill(label: _statusText[b.status] ?? b.status.name, background: _statusColor(b.status).withOpacity(0.12), textColor: _statusColor(b.status)),
                              ],
                            ),
                            if (isOngoing)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => bookingService.adminCancel(b.id),
                                  style: TextButton.styleFrom(foregroundColor: PsEvColors.red),
                                  child: const Text('Cancel this booking'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final active = _bookingFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => setState(() => _bookingFilter = value),
      selectedColor: PsEvColors.slate950,
      labelStyle: TextStyle(color: active ? Colors.white : PsEvColors.slateText, fontSize: 12),
    );
  }
}

/// Resolves a Firebase Auth uid into the person's actual first/last name +
/// mobile number by looking up the Firestore `users` collection, instead of
/// showing the raw uid. `roleLabel` lets the same widget be reused for
/// both "Driver:" and "Host:" lines (see the Payouts tab, which needs to
/// show both on the same card).
///
/// FIX (9/17 update): converted to a StatefulWidget with a cached Future,
/// same fix pattern as widgets/driver_info_line.dart - this screen has
/// no per-second timer today so the impact was smaller here, but it's
/// the same underlying anti-pattern (re-fetching Firestore on every
/// rebuild) and is fixed for consistency/safety.
class _UserInfoText extends StatefulWidget {
  final String uid;
  final String roleLabel;
  const _UserInfoText({required this.uid, this.roleLabel = 'Driver'});
  @override
  State<_UserInfoText> createState() => _UserInfoTextState();
}

class _UserInfoTextState extends State<_UserInfoText> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
  }

  @override
  void didUpdateWidget(covariant _UserInfoText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _future = FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        String label = widget.uid;
        String? phone;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          final first = data?['firstName'] as String? ?? '';
          final last = data?['lastName'] as String? ?? '';
          final name = [first, last].where((s) => s.trim().isNotEmpty).join(' ');
          if (name.isNotEmpty) label = name;
          phone = data?['phone'] as String?;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.roleLabel}: $label', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (phone != null && phone.isNotEmpty)
              Text('Mobile: $phone', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
          ],
        );
      },
    );
  }
}
