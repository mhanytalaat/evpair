import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/enums.dart';
import '../models/wallet_transaction.dart';
import '../models/payout_request.dart';
import '../models/app_notification.dart';
import 'notification_service.dart';
import 'auth_service.dart' show kAdminEmail;

/// (Earlier fixes retained - see previous revisions for the full history
/// of the top-up visibility/notification fixes from 3/9 and 9/10.)
///
/// NEW (9/15 update - "once the charging is done the admin should have a
/// request to release the payment after the calculation (kw * price)
/// and it should be transferred to the host wallet"): previously,
/// completing a charging session paid the host their share INSTANTLY and
/// fully automatically via `settleBooking()` below - there was no admin
/// step at all. This is now a genuinely separate, ADDITIVE flow:
///   - `createPayoutRequest(...)` - called by
///     BookingService.completeSession() instead of directly crediting
///     the host. Persists a `PayoutRequest` (status `pendingReview`) to
///     a new `payoutRequests` Firestore collection, and notifies the
///     admin (same notify-on-create pattern as `_notifyAdminOfNewTopUp`
///     below).
///   - `reviewPayout(id, approve: ...)` - what the new Payouts tab (see
///     screens/admin/admin_home_screen.dart) calls. Only on approval is
///     the host's wallet actually credited; on rejection, nothing is
///     credited (funds simply aren't paid out - there is no "driver side"
///     to refund here since the driver was already correctly charged/
///     refunded for actual usage the moment the session ended).
///   - `listenToMyPayoutsForHost(hostId)` / `listenToAllPayoutsForAdmin()`
///     - live listeners mirroring the existing top-up pattern exactly,
///     so a host's payout history updates live, and the admin sees every
///     host's pending payouts without needing to know each host's uid
///     up front.
/// `settleBooking()` (the OLD, fully-automatic version) is left intact
/// below for any other, non-charging-session caller that might still
/// want an instant, non-reviewed payout - but BookingService.completeSession()
/// no longer calls it; see services/booking_service.dart.
class WalletService extends ChangeNotifier {
  WalletService({FirebaseFirestore? firestore, this.notificationService}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final NotificationService? notificationService;
  final _uuid = const Uuid();

  final Map<String, double> _balances = {};
  final Map<String, double> _heldForBooking = {};

  // Keyed by document id so live listener updates (create/update/delete)
  // merge cleanly with no duplicates, same pattern as
  // BookingService._bookingsById.
  final Map<String, TopUpRequest> _topUpRequestsById = {};
  final Map<String, PayoutRequest> _payoutRequestsById = {};
  final List<WalletLedgerEntry> _ledger = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _myTopUpsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _allTopUpsSubForAdmin;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _myPayoutsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _allPayoutsSubForAdmin;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _balanceSub;

  double balanceOf(String userId) => _balances[userId] ?? 0;

  List<TopUpRequest> get pendingTopUps =>
      _topUpRequestsById.values.where((t) => t.status == TopUpStatus.pendingProofReview).toList();
      
/// NEW (9/24 update): returns this driver's own top-up REQUESTS
  /// (pending/approved/rejected), most recent first - used by the new
  /// "My Top-Up Requests" section in wallet_screen.dart.
  List<TopUpRequest> topUpsForDriver(String driverId) =>
      _topUpRequestsById.values.where((t) => t.driverId == driverId).toList()
        ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

  List<WalletLedgerEntry> ledgerFor(String userId) =>
      _ledger.where((e) => e.userId == userId).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  // ---------------------------------------------------------------------
  // Payouts (NEW 9/15)
  // ---------------------------------------------------------------------

  List<PayoutRequest> get pendingPayouts =>
      _payoutRequestsById.values.where((p) => p.status == PayoutStatus.pendingReview).toList()
        ..sort((a, b) => a.requestedAt.compareTo(b.requestedAt));

  List<PayoutRequest> payoutsForHost(String hostId) =>
      _payoutRequestsById.values.where((p) => p.hostId == hostId).toList()
        ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

  /// Live listener for a host's OWN payout requests, so their payout
  /// history (Wallet screen) updates instantly once an admin approves or
  /// rejects one, with no restart needed. Safe to call for every signed-in
  /// user (not just hosts) - simply returns nothing if they've never
  /// hosted a charger.
  void listenToMyPayoutsForHost(String hostId) {
    _myPayoutsSub?.cancel();
    _myPayoutsSub = _db.collection('payoutRequests').where('hostId', isEqualTo: hostId).snapshots().listen(
      (snapshot) => _mergePayoutSnapshot(snapshot),
      onError: (e) => debugPrint('WalletService: my payouts listener error: $e'),
    );
  }

  /// Admin-only: live listener over the ENTIRE payoutRequests collection,
  /// exactly mirroring listenToAllTopUpRequestsForAdmin() below. Call
  /// this only when AuthService.isAdmin is true (see main.dart /
  /// sign_in_screen.dart / register_screen.dart).
  void listenToAllPayoutsForAdmin() {
    _allPayoutsSubForAdmin?.cancel();
    _allPayoutsSubForAdmin = _db.collection('payoutRequests').snapshots().listen(
      (snapshot) => _mergePayoutSnapshot(snapshot),
      onError: (e) => debugPrint('WalletService: admin all-payouts listener error: $e'),
    );
  }

  void _mergePayoutSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    for (final change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.removed) {
        _payoutRequestsById.remove(change.doc.id);
      } else {
        _payoutRequestsById[change.doc.id] = PayoutRequest.fromFirestore(change.doc.id, change.doc.data()!);
      }
    }
    notifyListeners();
  }

  /// Creates a pendingReview PayoutRequest for the host's share of a
  /// just-completed charging session, and notifies the admin. Does NOT
  /// touch the host's wallet balance at all - that only happens in
  /// reviewPayout() below, once approved.
  Future<PayoutRequest> createPayoutRequest({
    required String bookingId,
    required String hostId,
    required String driverId,
    required String chargerName,
    required double powerKw,
    required double pricePerUnit,
    required String pricingModelName,
    required double actualCost,
    required int actualDurationSeconds,
    double commissionRate = 0.10,
  }) async {
    final hostAmount = (actualCost * (1 - commissionRate)).roundToDouble();
    final request = PayoutRequest(
      id: _uuid.v4(),
      bookingId: bookingId,
      hostId: hostId,
      driverId: driverId,
      chargerName: chargerName,
      powerKw: powerKw,
      pricePerUnit: pricePerUnit,
      pricingModelName: pricingModelName,
      actualCost: actualCost,
      commissionRate: commissionRate,
      hostAmount: hostAmount,
      actualDurationSeconds: actualDurationSeconds,
    );
    _payoutRequestsById[request.id] = request;
    notifyListeners();
    await _persistPayout(request);
    await _notifyAdminOfNewPayout(request);
    return request;
  }

  Future<void> _notifyAdminOfNewPayout(PayoutRequest request) async {
    if (notificationService == null) return;
    try {
      final adminSnap = await _db.collection('users').where('email', isEqualTo: kAdminEmail).limit(1).get();
      if (adminSnap.docs.isEmpty) {
        debugPrint('WalletService: no user document found for admin email $kAdminEmail - '
            'cannot notify admin of new payout request ${request.id}.');
        return;
      }
      final adminUid = adminSnap.docs.first.id;
      await notificationService!.notify(
        recipientId: adminUid,
        type: NotificationType.other,
        title: 'Payout ready for review',
        body: '${request.hostAmount.toStringAsFixed(0)} EGP payout ready for "${request.chargerName}" '
            '(${request.calculationLabel}) - please review and release.',
      );
    } catch (e) {
      debugPrint('WalletService: failed to notify admin of new payout ${request.id}: $e');
    }
  }

  /// Called from the admin Payouts tab. On approval, credits the host's
  /// wallet with `hostAmount` and adds a ledger entry showing the exact
  /// calculation via `calculationLabel`. On rejection, nothing is
  /// credited - the request is simply marked rejected with an optional
  /// note.
  void reviewPayout(String requestId, {required bool approve, String? adminNote}) {
    final request = _payoutRequestsById[requestId];
    if (request == null) return;
    request.status = approve ? PayoutStatus.approved : PayoutStatus.rejected;
    request.reviewedAt = DateTime.now();
    request.adminNote = adminNote;

    if (approve) {
      final entry = WalletLedgerEntry(
        id: _uuid.v4(),
        userId: request.hostId,
        amount: request.hostAmount,
        reason: 'Payout released for "${request.chargerName}" (${request.calculationLabel})',
      );
      _balances[request.hostId] = balanceOf(request.hostId) + request.hostAmount;
      _ledger.add(entry);
      _persistBalance(request.hostId);
      _persistLedgerEntry(entry);
    }

    _persistPayout(request);
    notifyListeners();

    notificationService?.notify(
      recipientId: request.hostId,
      type: NotificationType.other,
      title: approve ? 'Payout released!' : 'Payout not released',
      body: approve
          ? '${request.hostAmount.toStringAsFixed(0)} EGP has been added to your wallet for "${request.chargerName}".'
          : 'Your payout for "${request.chargerName}" was not released.${adminNote != null ? ' Reason: $adminNote' : ''}',
    );
  }

  Future<void> _persistPayout(PayoutRequest request) {
    return _db
        .collection('payoutRequests')
        .doc(request.id)
        .set(request.toFirestore(), SetOptions(merge: true))
        .catchError((e) => debugPrint('WalletService: failed to persist payout ${request.id}: $e'));
  }

  // ---------------------------------------------------------------------
  // Firestore hydration / live listeners
  // ---------------------------------------------------------------------

  /// Call after sign-in/registration, and once at startup if already
  /// signed in (see main.dart). Sets up a LIVE balance listener (so an
  /// admin approval reflects instantly, no restart needed) plus a
  /// one-time ledger history fetch, and live listeners on this user's OWN
  /// top-up requests and payout requests.
  Future<void> hydrateFromFirestore(String userId) async {
    try {
      _balanceSub?.cancel();
      _balanceSub = _db.collection('wallets').doc(userId).snapshots().listen(
        (doc) {
          final data = doc.data();
          if (data != null && data['balance'] != null) {
            _balances[userId] = (data['balance'] as num).toDouble();
            notifyListeners();
          }
        },
        onError: (e) => debugPrint('WalletService: balance listener error: $e'),
      );

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

      listenToMyTopUpRequests(userId);
      listenToMyPayoutsForHost(userId);

      notifyListeners();
    } catch (e) {
      debugPrint('WalletService.hydrateFromFirestore failed: $e');
    }
  }

  /// Live listener for the SIGNED-IN user's own top-up requests. Kept as
  /// its own method (rather than only inside hydrateFromFirestore) so it
  /// can be re-attached independently if ever needed.
  void listenToMyTopUpRequests(String userId) {
    _myTopUpsSub?.cancel();
    _myTopUpsSub = _db.collection('topUpRequests').where('driverId', isEqualTo: userId).snapshots().listen(
      (snapshot) => _mergeTopUpSnapshot(snapshot),
      onError: (e) => debugPrint('WalletService: my top-ups listener error: $e'),
    );
  }

  /// Live listener over the ENTIRE topUpRequests collection, with no
  /// driverId filter - only ever call this for the admin account (see
  /// AuthService.isAdmin / kAdminEmail).
  void listenToAllTopUpRequestsForAdmin() {
    _allTopUpsSubForAdmin?.cancel();
    _allTopUpsSubForAdmin = _db.collection('topUpRequests').snapshots().listen(
      (snapshot) => _mergeTopUpSnapshot(snapshot),
      onError: (e) => debugPrint('WalletService: admin all-top-ups listener error: $e'),
    );
  }

  void _mergeTopUpSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    for (final change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.removed) {
        _topUpRequestsById.remove(change.doc.id);
      } else {
        _topUpRequestsById[change.doc.id] = _topUpFromDoc(change.doc.id, change.doc.data()!);
      }
    }
    notifyListeners();
  }

  void stopListening() {
    _myTopUpsSub?.cancel();
    _allTopUpsSubForAdmin?.cancel();
    _myPayoutsSub?.cancel();
    _allPayoutsSubForAdmin?.cancel();
    _balanceSub?.cancel();
    _topUpRequestsById.clear();
    _payoutRequestsById.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _myTopUpsSub?.cancel();
    _allTopUpsSubForAdmin?.cancel();
    _myPayoutsSub?.cancel();
    _allPayoutsSubForAdmin?.cancel();
    _balanceSub?.cancel();
    super.dispose();
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
    _topUpRequestsById[request.id] = request;
    notifyListeners();
    _persistTopUp(request);
    _notifyAdminOfNewTopUp(request);
    return request;
  }

  Future<void> _notifyAdminOfNewTopUp(TopUpRequest request) async {
    if (notificationService == null) return;
    try {
      final adminSnap = await _db.collection('users').where('email', isEqualTo: kAdminEmail).limit(1).get();
      if (adminSnap.docs.isEmpty) {
        debugPrint('WalletService: no user document found for admin email $kAdminEmail - '
            'cannot notify admin of new top-up request ${request.id}.');
        return;
      }
      final adminUid = adminSnap.docs.first.id;
      await notificationService!.notify(
        recipientId: adminUid,
        type: NotificationType.other,
        title: 'New top-up request',
        body: '${request.amount.toStringAsFixed(0)} EGP top-up submitted via ${request.method.name} '
            '(ref: ${request.referenceNote}) - please review and approve.',
      );
    } catch (e) {
      debugPrint('WalletService: failed to notify admin of new top-up ${request.id}: $e');
    }
  }

  void reviewTopUp(String requestId, {required bool approve, String? adminNote}) {
    final request = _topUpRequestsById[requestId];
    if (request == null) return;
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

  /// OLD, fully-automatic settlement (host paid instantly, no admin
  /// review). Kept intact for any other caller, but
  /// BookingService.completeSession() no longer uses this for the
  /// primary charging payout - see settleBookingWithPendingPayout below,
  /// which is what it calls instead.
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

  /// NEW (9/15 update): what BookingService.completeSession() now calls
  /// instead of settleBooking() above. The driver's UNUSED hold is still
  /// refunded immediately - that's simply returning the driver their own
  /// money for time they didn't use, there's no reason to gate that
  /// behind a review step. The HOST's share is NOT credited here at all
  /// - it only becomes a PayoutRequest (status pendingReview) via
  /// createPayoutRequest, and is only actually paid once an admin
  /// approves it (see reviewPayout above).
  Future<void> settleBookingWithPendingPayout({
    required String bookingId,
    required String driverId,
    required String hostId,
    required String chargerName,
    required double actualCost,
    required double powerKw,
    required double pricePerUnit,
    required String pricingModelName,
    required int actualDurationSeconds,
    double commissionRate = 0.10,
  }) async {
    final heldAmount = _heldForBooking.remove(bookingId);
    if (heldAmount != null) {
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
    }
    notifyListeners();
    await createPayoutRequest(
      bookingId: bookingId,
      hostId: hostId,
      driverId: driverId,
      chargerName: chargerName,
      powerKw: powerKw,
      pricePerUnit: pricePerUnit,
      pricingModelName: pricingModelName,
      actualCost: actualCost,
      actualDurationSeconds: actualDurationSeconds,
      commissionRate: commissionRate,
    );
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
