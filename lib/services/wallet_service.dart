import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/enums.dart';
import '../models/wallet_transaction.dart';

class WalletService extends ChangeNotifier {
  final _uuid = const Uuid();

  final Map<String, double> _balances = {};
  final Map<String, double> _heldForBooking = {};
  final List<TopUpRequest> _topUpRequests = [];
  final List<WalletLedgerEntry> _ledger = [];

  double balanceOf(String userId) => _balances[userId] ?? 0;

  List<TopUpRequest> get pendingTopUps =>
      _topUpRequests.where((t) => t.status == TopUpStatus.pendingProofReview).toList();

  List<WalletLedgerEntry> ledgerFor(String userId) =>
      _ledger.where((e) => e.userId == userId).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  TopUpRequest submitTopUp({
    required String driverId,
    required double amount,
    required PaymentMethod method,
    required String referenceNote,
    required String proofImagePath,
  }) {
    final request = TopUpRequest(
      id: _uuid.v4(),
      driverId: driverId,
      amount: amount,
      method: method,
      referenceNote: referenceNote,
      proofImagePath: proofImagePath,
    );
    _topUpRequests.add(request);
    notifyListeners();
    return request;
  }

  void reviewTopUp(String requestId, {required bool approve, String? adminNote}) {
    final request = _topUpRequests.firstWhere((t) => t.id == requestId);
    request.status = approve ? TopUpStatus.approved : TopUpStatus.rejected;
    request.reviewedAt = DateTime.now();
    request.adminNote = adminNote;

    if (approve) {
      _balances[request.driverId] = balanceOf(request.driverId) + request.amount;
      _ledger.add(WalletLedgerEntry(
        id: _uuid.v4(),
        userId: request.driverId,
        amount: request.amount,
        reason: 'Top-up approved (${request.method.name}, ref: ${request.referenceNote})',
      ));
    }
    notifyListeners();
  }

  /// Directly credits a balance without going through the top-up approval
  /// flow. Used ONLY for seeding demo data at app startup (see main.dart) -
  /// never expose this as a user-facing "just add money" shortcut.
  void seedBalance(String userId, double amount) {
    _balances[userId] = balanceOf(userId) + amount;
    _ledger.add(WalletLedgerEntry(id: _uuid.v4(), userId: userId, amount: amount, reason: 'Starting demo balance'));
    notifyListeners();
  }

  bool holdForBooking({required String driverId, required String bookingId, required double amount}) {
    if (balanceOf(driverId) < amount) return false;
    _balances[driverId] = balanceOf(driverId) - amount;
    _heldForBooking[bookingId] = amount;
    _ledger.add(WalletLedgerEntry(
      id: _uuid.v4(),
      userId: driverId,
      amount: -amount,
      reason: 'Held for booking $bookingId',
    ));
    notifyListeners();
    return true;
  }

  void releaseHold({required String driverId, required String bookingId}) {
    final amount = _heldForBooking.remove(bookingId);
    if (amount == null) return;
    _balances[driverId] = balanceOf(driverId) + amount;
    _ledger.add(WalletLedgerEntry(
      id: _uuid.v4(),
      userId: driverId,
      amount: amount,
      reason: 'Hold released for booking $bookingId',
    ));
    notifyListeners();
  }

  void settleBooking({
    required String driverId,
    required String hostId,
    required String bookingId,
    required double actualCost,
    double commissionRate = 0.10,
  }) {
    final heldAmount = _heldForBooking.remove(bookingId);
    if (heldAmount == null) return;

    final refund = heldAmount - actualCost;
    if (refund > 0) {
      _balances[driverId] = balanceOf(driverId) + refund;
      _ledger.add(WalletLedgerEntry(
        id: _uuid.v4(),
        userId: driverId,
        amount: refund,
        reason: 'Refund of unused hold for booking $bookingId (billed for actual usage only)',
      ));
    }

    final hostShare = actualCost * (1 - commissionRate);
    _balances[hostId] = balanceOf(hostId) + hostShare;
    _ledger.add(WalletLedgerEntry(
      id: _uuid.v4(),
      userId: hostId,
      amount: hostShare,
      reason: 'Payout for booking $bookingId (after ${(commissionRate * 100).toStringAsFixed(0)}% commission)',
    ));
    notifyListeners();
  }
}
