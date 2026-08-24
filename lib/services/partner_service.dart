import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/partner_models.dart';
import 'wallet_service.dart';

/// Handles two related but independent features, kept in one simple
/// service since both are new and both are small:
///
/// 1. SERVICE REQUESTS - a driver asks for a home-related EV service:
///    a new home charging station install, an adaptor, a cable, or
///    maintenance on an existing station (see ServiceCategory). Any of
///    EVPair's (potentially multiple) partners can accept an open
///    request from a shared pool, optionally filtered to just the
///    category they handle - there is no manual admin assignment step,
///    which keeps this workable with zero or many partners without
///    extra admin UI.
///
/// 2. EQUIPMENT MARKETPLACE - a simple catalog of cables, adaptors, and
///    home charging stations that can be borrowed (against a deposit) or
///    bought outright, listed either by a partner or by EVPair itself
///    (kPlatformOwnerId).
///
/// Becoming a partner is intentionally NOT self-service in this version:
/// a document is created directly at `installPartners/{uid}` (e.g. via
/// the Firebase console, or a future admin screen) after you vet someone
/// - see `isPartner()` below, which just checks for that document.
class PartnerService extends ChangeNotifier {
  PartnerService({FirebaseFirestore? firestore, required this.walletService})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final WalletService walletService;
  final _uuid = const Uuid();

  bool _isPartner = false;
  bool get isPartner => _isPartner;

  List<InstallationRequest> _myInstallRequests = [];
  List<InstallationRequest> get myInstallRequests => List.unmodifiable(_myInstallRequests);

  List<InstallationRequest> _openInstallRequests = [];
  List<InstallationRequest> get openInstallRequests => List.unmodifiable(_openInstallRequests);

  List<InstallationRequest> _myPartnerJobs = [];
  List<InstallationRequest> get myPartnerJobs => List.unmodifiable(_myPartnerJobs);

  List<EquipmentListing> _listings = [];
  List<EquipmentListing> get listings => List.unmodifiable(_listings);

  List<EquipmentRequest> _myEquipmentRequests = [];
  List<EquipmentRequest> get myEquipmentRequests => List.unmodifiable(_myEquipmentRequests);

  /// Open requests, optionally narrowed to one category - used by the
  /// Partner Jobs screen's category filter chips so a cable-only partner
  /// doesn't have to scroll past every station-install request.
  List<InstallationRequest> openRequestsForCategory(ServiceCategory? category) {
    if (category == null) return openInstallRequests;
    return _openInstallRequests.where((r) => r.category == category).toList();
  }

  /// Loads everything relevant for the signed-in user: whether they are
  /// a partner, their own service requests, the shared open pool
  /// (only meaningfully used if they ARE a partner), their partner jobs
  /// (if any), the equipment catalog, and their own equipment requests.
  Future<void> hydrate(String userId) async {
    try {
      final partnerDoc = await _db.collection('installPartners').doc(userId).get();
      _isPartner = partnerDoc.exists;

      final myRequestsSnap =
          await _db.collection('installationRequests').where('driverId', isEqualTo: userId).get();
      _myInstallRequests = myRequestsSnap.docs.map((d) => InstallationRequest.fromFirestore(d.id, d.data())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (_isPartner) {
        final openSnap =
            await _db.collection('installationRequests').where('status', isEqualTo: InstallRequestStatus.open.name).get();
        _openInstallRequests = openSnap.docs.map((d) => InstallationRequest.fromFirestore(d.id, d.data())).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        final myJobsSnap =
            await _db.collection('installationRequests').where('partnerId', isEqualTo: userId).get();
        _myPartnerJobs = myJobsSnap.docs.map((d) => InstallationRequest.fromFirestore(d.id, d.data())).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }

      final listingsSnap = await _db.collection('equipmentListings').where('available', isEqualTo: true).get();
      _listings = listingsSnap.docs.map((d) => EquipmentListing.fromFirestore(d.id, d.data())).toList();

      final myEquipSnap =
          await _db.collection('equipmentRequests').where('driverId', isEqualTo: userId).get();
      _myEquipmentRequests = myEquipSnap.docs.map((d) => EquipmentRequest.fromFirestore(d.id, d.data())).toList()
        ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

      notifyListeners();
    } catch (e) {
      debugPrint('PartnerService.hydrate failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Service requests (stations, adaptors, cables, maintenance, other)
  // ---------------------------------------------------------------------

  Future<InstallationRequest> submitInstallationRequest({
    required String driverId,
    required String driverName,
    required String driverPhone,
    required ServiceCategory category,
    required String city,
    required String area,
    required String addressDetails,
    String? notes,
  }) async {
    final request = InstallationRequest(
      id: _uuid.v4(),
      driverId: driverId,
      driverName: driverName,
      driverPhone: driverPhone,
      category: category,
      city: city,
      area: area,
      addressDetails: addressDetails,
      notes: notes,
    );
    _myInstallRequests.insert(0, request);
    notifyListeners();
    await _db.collection('installationRequests').doc(request.id).set(request.toFirestore());
    return request;
  }

  void cancelInstallationRequest(String requestId) {
    final request = _myInstallRequests.where((r) => r.id == requestId).firstOrNull;
    if (request == null || request.status != InstallRequestStatus.open) return;
    request.status = InstallRequestStatus.cancelled;
    notifyListeners();
    _db.collection('installationRequests').doc(requestId).update({'status': InstallRequestStatus.cancelled.name}).catchError(
        (e) => debugPrint('PartnerService: failed to cancel request $requestId: $e'));
  }

  /// Called from the partner-facing screen: claims an open request from
  /// the shared pool. First partner to tap "Accept" gets it - no manual
  /// admin dispatching required.
  Future<bool> acceptInstallationRequest(String requestId, {required String partnerId, required String partnerName}) async {
    final request = _openInstallRequests.where((r) => r.id == requestId).firstOrNull;
    if (request == null) return false;

    request.status = InstallRequestStatus.accepted;
    request.partnerId = partnerId;
    request.partnerName = partnerName;
    request.acceptedAt = DateTime.now();
    _openInstallRequests.removeWhere((r) => r.id == requestId);
    _myPartnerJobs.insert(0, request);
    notifyListeners();

    try {
      await _db.collection('installationRequests').doc(requestId).update({
        'status': InstallRequestStatus.accepted.name,
        'partnerId': partnerId,
        'partnerName': partnerName,
        'acceptedAt': Timestamp.fromDate(request.acceptedAt!),
      });
      return true;
    } catch (e) {
      debugPrint('PartnerService: failed to accept request $requestId: $e');
      return false;
    }
  }

  Future<void> completeInstallationRequest(String requestId, {String? completionNotes}) async {
    final request = _myPartnerJobs.where((r) => r.id == requestId).firstOrNull;
    if (request == null) return;
    request.status = InstallRequestStatus.completed;
    request.completedAt = DateTime.now();
    request.completionNotes = completionNotes;
    notifyListeners();
    await _db.collection('installationRequests').doc(requestId).update({
      'status': InstallRequestStatus.completed.name,
      'completedAt': Timestamp.fromDate(request.completedAt!),
      'completionNotes': completionNotes,
    }).catchError((e) => debugPrint('PartnerService: failed to complete request $requestId: $e'));
  }

  // ---------------------------------------------------------------------
  // Equipment marketplace
  // ---------------------------------------------------------------------

  Future<EquipmentRequest> requestEquipment({
    required EquipmentListing listing,
    required String driverId,
    required String driverName,
  }) async {
    final request = EquipmentRequest(
      id: _uuid.v4(),
      listingId: listing.id,
      listingTitle: listing.title,
      mode: listing.mode,
      price: listing.price,
      driverId: driverId,
      driverName: driverName,
    );
    _myEquipmentRequests.insert(0, request);
    notifyListeners();
    await _db.collection('equipmentRequests').doc(request.id).set(request.toFirestore());

    // Charge/hold immediately on request: for "buy" this is a direct
    // charge (ownership transfers once the partner marks it fulfilled);
    // for "borrow" this is only a refundable deposit HOLD, released back
    // in full when returnEquipment() is called below.
    if (listing.mode == EquipmentMode.buy) {
      walletService.payForEquipment(
        driverId: driverId,
        ownerId: listing.ownerId,
        requestId: request.id,
        amount: listing.price,
      );
    } else {
      walletService.holdForBooking(driverId: driverId, bookingId: 'equip_${request.id}', amount: listing.price);
    }
    return request;
  }

  Future<void> markEquipmentFulfilled(String requestId) async {
    final request = _myEquipmentRequests.where((r) => r.id == requestId).firstOrNull;
    if (request == null) return;
    request.status = EquipmentRequestStatus.fulfilled;
    notifyListeners();
    await _db.collection('equipmentRequests').doc(requestId).update({'status': EquipmentRequestStatus.fulfilled.name}).catchError(
        (e) => debugPrint('PartnerService: failed to mark equipment fulfilled $requestId: $e'));
  }

  /// Driver returns a BORROWED item - releases the deposit hold in full.
  /// (A future enhancement could deduct a damage fee here instead of a
  /// full release, using the same wallet primitives.)
  Future<void> returnEquipment(String requestId, {required String driverId}) async {
    final request = _myEquipmentRequests.where((r) => r.id == requestId).firstOrNull;
    if (request == null || request.mode != EquipmentMode.borrow) return;
    request.status = EquipmentRequestStatus.returned;
    request.returnedAt = DateTime.now();
    notifyListeners();
    walletService.releaseHold(driverId: driverId, bookingId: 'equip_${request.id}');
    await _db.collection('equipmentRequests').doc(requestId).update({
      'status': EquipmentRequestStatus.returned.name,
      'returnedAt': Timestamp.fromDate(request.returnedAt!),
    }).catchError((e) => debugPrint('PartnerService: failed to mark equipment returned $requestId: $e'));
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
