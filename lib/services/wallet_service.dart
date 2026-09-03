import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/enums.dart';
import '../models/wallet_transaction.dart';
import '../models/app_notification.dart';
import 'notification_service.dart';

class WalletService extends ChangeNotifier {
  WalletService({FirebaseFirestore? firestore, this.notificationService}) : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  /// Optional so existing tests/usages that don't care about
  /// notifications still work - but main.dart always provides a real
  /// one, which is what actually sends the "mandatory" top-up
  /// approved/rejected notification to the driver (see reviewTopUp).
  final NotificationService? notificationService;
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

  // ---------------------------------------------------------------------
  // Firestore hydration
  // ---------------------------------------------------------------------

  Future<void> hydrateFromFirestore(String userId) async {
    try {
      final walletDoc = await _db.collection('wallets').doc(userId).get();
      final data = walletDoc.data();
      if (data != null && data['balance'] != null) {
        _balances[userId] = (data['balance'] as num).toDouble();
      }
      final ledgerSnapshot = await _db
          .collection('wallets')
          .doc(userId)
          .collection('ledger')
          .orderBy('timestamp', descending: true)
          .limit(200)
          .get();
      _ledger.removeWhere((e) => e.userId == userId);
      for (final doc in ledgerSnapshot.docs) {
        _ledger.add(_ledgerFromDoc(userId, doc.id, doc.data()));
      }
      final topUpSnapshot =
          await _db.collection('topUpRequests').where('driverId', isEqualTo: userId).get();
      _topUpRequests.removeWhere((t) => t.driverId == userId);
      for (final doc in topUpSnapshot.docs) {
        _topUpRequests.add(_topUpFromDoc(doc.id, doc.data()));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('WalletService.hydrateFromFirestore failed: $e');
    }
  }

  Future<void> hydrateAllTopUpRequests() async {
    try {
      final snapshot = await _db.collection('topUpRequests').get();
      _topUpRequests
        ..clear()
        ..addAll(snapshot.docs.map((d) => _topUpFromDoc(d.id, d.data())));
      notifyListeners();
    } catch (e) {
      debugPrint('WalletService.hydrateAllTopUpRequests failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------

  TopUpRequest submitTopUp({
    required String driverId,
    required double amount,
    required PaymentMethod method,
    required String referenceNote,
    required String proofImagePath,
    String? proofImageBase64,
  }) {
    final request = TopUpRequest(
      id: _uuid.v4(),
      driverId: driverId,
      amount: amount,
      method: method,
      referenceNote: referenceNote,
      proofImagePath: proofImagePath,
      proofImageBase64: proofImageBase64,
    );
    _topUpRequests.add(request);
    notifyListeners();
    _persistTopUp(request);
    return request;
  }

  /// Approves/rejects a pending top-up. Now ALSO sends a mandatory
  /// notification to the driver either way (approved -> credited amount,
  /// rejected -> reason) - see NotificationService. Previously there was
  /// no notification at all for this event; the driver would only find
  /// out by manually reopening the Wallet screen.
  void reviewTopUp(String requestId, {required bool approve, String? adminNote}) {
    final request = _topUpRequests.firstWhere((t) => t.id == requestId);
    request.status = approve ? TopUpStatus.approved : TopUpStatus.rejected;
    request.reviewedAt = DateTime.now();
    request.adminNote = adminNote;
    if (approve) {
      final entry = WalletLedgerEntry(
        id: _uuid.v4(),
        userId: request.driverId,
        amount: request.amount,
        reason: 'Top-up approved (${request.method.name}, ref: ${request.referenceNote})',
      );
      _balances[request.driverId] = balanceOf(request.driverId) + request.amount;
      _ledger.add(entry);
      _persistBalance(request.driverId);
      _persistLedgerEntry(entry);
    }
    _persistTopUp(request);
    notifyListeners();
    notificationService?.notify(
      recipientId: request.driverId,
      type: approve ? NotificationType.topUpApproved : NotificationType.topUpRejected,
      title: approve ? 'Top-up approved!' : 'Top-up rejected',
      body: approve
          ? '${request.amount.toStringAsFixed(0)} EGP has been added to your wallet. You can now complete your booking.'
          : 'Your top-up request could not be verified.${adminNote != null ? ' Reason: $adminNote' : ' Please try again with clearer proof.'}',
    );
  }

  void seedBalance(String userId, double amount) {
    final entry = WalletLedgerEntry(
      id: _uuid.v4(),
      userId: userId,
      amount: amount,
      reason: 'Starting demo balance',
    );
    _balances[userId] = balanceOf(userId) + amount;
    _ledger.add(entry);
    _persistBalance(userId);
    _persistLedgerEntry(entry);
    notifyListeners();
  }

  bool holdForBooking({required String driverId, required String bookingId, required double amount}) {
    if (balanceOf(driverId) < amount) return false;
    final entry = WalletLedgerEntry(
      id: _uuid.v4(),
      userId: driverId,
      amount: -amount,
      reason: 'Held for booking $bookingId',
    );
    _balances[driverId] = balanceOf(driverId) - amount;
    _heldForBooking[bookingId] = amount;
    _ledger.add(entry);
    _persistBalance(driverId);
    _persistLedgerEntry(entry);
    notifyListeners();
    return true;
  }

  void releaseHold({required String driverId, required String bookingId}) {
    final amount = _heldForBooking.remove(bookingId);
    if (amount == null) return;
    final entry = WalletLedgerEntry(
      id: _uuid.v4(),
      userId: driverId,
      amount: amount,
      reason: 'Hold released for booking $bookingId',
    );
    _balances[driverId] = balanceOf(driverId) + amount;
    _ledger.add(entry);
    _persistBalance(driverId);
    _persistLedgerEntry(entry);
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
      final refundEntry = WalletLedgerEntry(
        id: _uuid.v4(),
        userId: driverId,
        amount: refund,
        reason: 'Refund of unused hold for booking $bookingId (billed for actual usage only)',
      );
      _balances[driverId] = balanceOf(driverId) + refund;
      _ledger.add(refundEntry);
      _persistBalance(driverId);
      _persistLedgerEntry(refundEntry);
    }
    final hostShare = actualCost * (1 - commissionRate);
    final hostEntry = WalletLedgerEntry(
      id: _uuid.v4(),
      userId: hostId,
      amount: hostShare,
      reason: 'Payout for booking $bookingId (after ${(commissionRate * 100).toStringAsFixed(0)}% commission)',
    );
    _balances[hostId] = balanceOf(hostId) + hostShare;
    _ledger.add(hostEntry);
    _persistBalance(hostId);
    _persistLedgerEntry(hostEntry);
    notifyListeners();
  }

  void chargeOverstayPenalty({
    required String driverId,
    required String hostId,
    required String bookingId,
    required double penaltyAmount,
    required int overstayMinutes,
    double hostShareRate = 0.80,
  }) {
    if (penaltyAmount <= 0) return;
    final driverEntry = WalletLedgerEntry(
      id: _uuid.v4(),
      userId: driverId,
      amount: -penaltyAmount,
      reason: 'Overstay penalty for booking $bookingId ($overstayMinutes min past grace period)',
    );
    _balances[driverId] = balanceOf(driverId) - penaltyAmount;
    _ledger.add(driverEntry);
    _persistBalance(driverId);
    _persistLedgerEntry(driverEntry);
    final hostShare = (penaltyAmount * hostShareRate).roundToDouble();
    final hostEntry = WalletLedgerEntry(
      id: _uuid.v4(),
      userId: hostId,
      amount: hostShare,
      reason: 'Overstay compensation for booking $bookingId ($overstayMinutes min past grace period)',
    );
    _balances[hostId] = balanceOf(hostId) + hostShare;
    _ledger.add(hostEntry);
    _persistBalance(hostId);
    _persistLedgerEntry(hostEntry);
    notifyListeners();
  }

  void payForEquipment({
    required String driverId,
    required String ownerId,
    required String requestId,
    required double amount,
  }) {
    if (amount <= 0) return;
    final driverEntry = WalletLedgerEntry(
      id: _uuid.v4(),
      userId: driverId,
      amount: -amount,
      reason: 'Equipment purchase (request $requestId)',
    );
    _balances[driverId] = balanceOf(driverId) - amount;
    _ledger.add(driverEntry);
    _persistBalance(driverId);
    _persistLedgerEntry(driverEntry);
    final ownerEntry = WalletLedgerEntry(
      id: _uuid.v4(),
      userId: ownerId,
      amount: amount,
      reason: 'Equipment sale (request $requestId)',
    );
    _balances[ownerId] = balanceOf(ownerId) + amount;
    _ledger.add(ownerEntry);
    _persistBalance(ownerId);
    _persistLedgerEntry(ownerEntry);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Firestore write helpers
  // ---------------------------------------------------------------------

  Future<void> _persistBalance(String userId) {
    return _db
        .collection('wallets')
        .doc(userId)
        .set(
          {
            'balance': balanceOf(userId),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        )
        .catchError((e) => debugPrint('WalletService: failed to persist balance for $userId: $e'));
  }

  Future<void> _persistLedgerEntry(WalletLedgerEntry entry) {
    return _db
        .collection('wallets')
        .doc(entry.userId)
        .collection('ledger')
        .doc(entry.id)
        .set({
          'amount': entry.amount,
          'reason': entry.reason,
          'timestamp': Timestamp.fromDate(entry.timestamp),
        })
        .catchError((e) => debugPrint('WalletService: failed to persist ledger entry ${entry.id}: $e'));
  }

  Future<void> _persistTopUp(TopUpRequest request) {
    return _db
        .collection('topUpRequests')
        .doc(request.id)
        .set(
          {
            'driverId': request.driverId,
            'amount': request.amount,
            'method': request.method.name,
            'referenceNote': request.referenceNote,
            'proofImagePath': request.proofImagePath,
            'proofImageBase64': request.proofImageBase64,
            'status': request.status.name,
            'requestedAt': Timestamp.fromDate(request.requestedAt),
            'reviewedAt': request.reviewedAt == null ? null : Timestamp.fromDate(request.reviewedAt!),
            'adminNote': request.adminNote,
          },
          SetOptions(merge: true),
        )
        .catchError((e) => debugPrint('WalletService: failed to persist top-up ${request.id}: $e'));
  }

  WalletLedgerEntry _ledgerFromDoc(String userId, String id, Map<String, dynamic> data) {
    final ts = data['timestamp'];
    return WalletLedgerEntry(
      id: id,
      userId: userId,
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      reason: data['reason'] as String? ?? '',
      timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  TopUpRequest _topUpFromDoc(String id, Map<String, dynamic> data) {
    final requestedAt = data['requestedAt'];
    final reviewedAt = data['reviewedAt'];
    return TopUpRequest(
      id: id,
      driverId: data['driverId'] as String? ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      method: PaymentMethod.values.firstWhere(
        (m) => m.name == data['method'],
        orElse: () => PaymentMethod.other,
      ),
      referenceNote: data['referenceNote'] as String? ?? '',
      proofImagePath: data['proofImagePath'] as String? ?? '',
      proofImageBase64: data['proofImageBase64'] as String?,
      status: TopUpStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => TopUpStatus.pendingProofReview,
      ),
      requestedAt: requestedAt is Timestamp ? requestedAt.toDate() : DateTime.now(),
      reviewedAt: reviewedAt is Timestamp ? reviewedAt.toDate() : null,
      adminNote: data['adminNote'] as String?,
    );
  }
}
