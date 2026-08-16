import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/booking_service.dart';
import '../../models/enums.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _tab = 0;
  String _bookingFilter = 'ongoing';

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
                Expanded(child: _tabButton('Top-Ups', 0)),
                Expanded(child: _tabButton('Bookings', 1)),
              ],
            ),
          ),
          Expanded(child: _tab == 0 ? _buildTopUps(wallet) : _buildBookings(bookingService)),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index) {
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
        child: Text(label, style: TextStyle(color: active ? PsEvColors.emerald : PsEvColors.slateText, fontWeight: FontWeight.w600, fontSize: 13)),
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
                  Text('Driver: ${t.driverId}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                                      Text('Driver: ${b.driverId}', style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
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
