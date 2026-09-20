import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/booking.dart';
import '../models/charger_profile.dart';
import '../models/car_profile.dart';
import '../models/enums.dart';
import '../models/app_notification.dart';
import 'wallet_service.dart';
import 'pricing_service.dart';
import 'notification_service.dart';

/// Common base for errors that can occur when a driver tries to request a
/// booking, so the UI can catch a single type and read `.message`.
abstract class BookingRequestException implements Exception {
  String get message;
}

/// Driver's community doesn't match a residents-only charger's
/// restriction.
class ChargerAccessDeniedException implements BookingRequestException {
  @override
  final String message;
  ChargerAccessDeniedException(this.message);
}

/// The driver's chosen custom time range is invalid: it doesn't fit
/// within any of the host's free windows, it overlaps another driver's
/// existing booking on the same charger, it's shorter than the minimum
/// allowed duration, it's already in the past, or end <= start.
class TimeRangeUnavailableException implements BookingRequestException {
  @override
  final String message;
  TimeRangeUnavailableException(this.message);
}

/// Minimum booking duration - prevents drivers from requesting
/// unrealistically short charging windows (e.g. 2 minutes).
const int kMinBookingMinutes = 30;

/// Bookings are persisted to, and kept live-synced from, Firestore's
/// `bookings` collection via real-time listeners (see hydrate()) so a
/// booking created by a driver is immediately visible to the host on a
/// different device, and vice versa.
class BookingService extends ChangeNotifier {
  BookingService({required this.walletService, required this.notificationService, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final _uuid = const Uuid();
  final WalletService walletService;
  final NotificationService notificationService;
  final FirebaseFirestore _db;

  final Map<String, Booking> _bookingsById = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _asDriverSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _asHostSub;

  List<Booking> get all => List.unmodifiable(_bookingsById.values);

  /// Attaches live listeners for this user's bookings (as driver AND as
  /// host). Call after sign-in/registration, and once at startup if
  /// already signed in (see main.dart). Safe to call again on account
  /// switch - cancels any previous listeners first.
  void hydrate(String userId) {
    _asDriverSub?.cancel();
    _asHostSub?.cancel();
    _asDriverSub = _db.collection('bookings').where('driverId', isEqualTo: userId).snapshots().listen(
      (snapshot) => _mergeSnapshot(snapshot),
      onError: (e) => debugPrint('BookingService: driver listener error: $e'),
    );
    _asHostSub = _db.collection('bookings').where('hostId', isEqualTo: userId).snapshots().listen(
      (snapshot) => _mergeSnapshot(snapshot),
      onError: (e) => debugPrint('BookingService: host listener error: $e'),
    );
  }

  void _mergeSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    for (final change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.removed) {
        _bookingsById.remove(change.doc.id);
      } else {
        _bookingsById[change.doc.id] = Booking.fromFirestore(change.doc.id, change.doc.data()!);
      }
    }
    notifyListeners();
  }

  void stopListening() {
    _asDriverSub?.cancel();
    _asHostSub?.cancel();
    _bookingsById.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _asDriverSub?.cancel();
    _asHostSub?.cancel();
    super.dispose();
  }

  List<Booking> bookingsForDriver(String driverId) =>
      _bookingsById.values.where((b) => b.driverId == driverId).toList();

  List<Booking> ongoingForDriver(String driverId) => _bookingsById.values
      .where((b) => b.driverId == driverId && BookingService.ongoingStatuses.contains(b.status))
      .toList()
    ..sort((a, b) => a.requestedStart.compareTo(b.requestedStart));

  List<Booking> pastForDriver(String driverId) => _bookingsById.values
      .where((b) => b.driverId == driverId &&
          (b.status == BookingStatus.completed || BookingService.cancelledStatuses.contains(b.status)))
      .toList()
    ..sort((a, b) => (b.sessionEndedAt ?? b.requestedEnd).compareTo(a.sessionEndedAt ?? a.requestedEnd));

  List<Booking> pendingApprovalsForHost(String hostId) =>
      _bookingsById.values.where((b) => b.hostId == hostId && b.status == BookingStatus.pendingHostApproval).toList();

  List<Booking> confirmedForHost(String hostId) =>
      _bookingsById.values.where((b) => b.hostId == hostId && b.status == BookingStatus.confirmed).toList()
        ..sort((a, b) => a.requestedStart.compareTo(b.requestedStart));

  List<Booking> inProgressForHost(String hostId) =>
      _bookingsById.values.where((b) => b.hostId == hostId && b.status == BookingStatus.inProgress).toList();

  List<Booking> completedForHost(String hostId) => _bookingsById.values
      .where((b) => b.hostId == hostId && b.status == BookingStatus.completed)
      .toList()
    ..sort((a, b) => (b.sessionEndedAt ?? b.requestedEnd).compareTo(a.sessionEndedAt ?? a.requestedEnd));

  List<Booking> activeForHost(String hostId) => _bookingsById.values
      .where((b) => b.hostId == hostId && (b.status == BookingStatus.confirmed || b.status == BookingStatus.inProgress))
      .toList();

  List<Booking> activeForDriver(String driverId) => _bookingsById.values
      .where((b) => b.driverId == driverId && (b.status == BookingStatus.confirmed || b.status == BookingStatus.inProgress))
      .toList()
    ..sort((a, b) => a.requestedStart.compareTo(b.requestedStart));

  Booking? findById(String id) => _bookingsById[id];

  static const List<BookingStatus> ongoingStatuses = [
    BookingStatus.pendingWalletHold,
    BookingStatus.pendingHostApproval,
    BookingStatus.confirmed,
    BookingStatus.inProgress,
  ];

  static const List<BookingStatus> cancelledStatuses = [
    BookingStatus.declinedByHost,
    BookingStatus.cancelledByDriver,
    BookingStatus.cancelledByAdmin,
    BookingStatus.expired,
  ];

  List<Booking> filterByCategory(String category) {
    switch (category) {
      case 'ongoing':
        return _bookingsById.values.where((b) => ongoingStatuses.contains(b.status)).toList();
      case 'completed':
        return _bookingsById.values.where((b) => b.status == BookingStatus.completed).toList();
      case 'cancelled':
        return _bookingsById.values.where((b) => cancelledStatuses.contains(b.status)).toList();
      default:
        return List.of(_bookingsById.values);
    }
  }

  List<Booking> _liveBookingsForCharger(String chargerId) =>
      _bookingsById.values.where((b) => b.chargerId == chargerId && ongoingStatuses.contains(b.status)).toList();

  List<({DateTime start, DateTime end})> bookedRangesFor(String chargerId) {
    final ranges = _liveBookingsForCharger(chargerId).map((b) => (start: b.requestedStart, end: b.requestedEnd)).toList();
    ranges.sort((a, b) => a.start.compareTo(b.start));
    return ranges;
  }

  bool isRangeAvailable(ChargerProfile charger, DateTime start, DateTime end) {
    final fitsSomeWindow = charger.freeSlots.any((s) => s.canFit(start, end));
    if (!fitsSomeWindow) return false;
    final overlaps = _liveBookingsForCharger(charger.chargerId).any(
      (b) => b.requestedStart.isBefore(end) && start.isBefore(b.requestedEnd),
    );
    return !overlaps;
  }

  Future<Booking> createRequest({
    required String driverId,
    required String driverName,
    required ChargerProfile charger,
    required DateTime requestedStart,
    required DateTime requestedEnd,
    required String? driverCommunity,
    required CarProfile driverCar,
  }) async {
    if (driverCar.plateNumber.trim().isEmpty) {
      throw TimeRangeUnavailableException('Please add your car plate number in My Cars before booking.');
    }
    if (!charger.isAccessibleToCommunity(driverCommunity)) {
      throw ChargerAccessDeniedException(
        'This charger is restricted to ${charger.restrictedCommunity} residents only.',
      );
    }
    if (!requestedEnd.isAfter(requestedStart)) {
      throw TimeRangeUnavailableException('End time must be after start time.');
    }
    final now = DateTime.now();
    if (requestedStart.isBefore(now.subtract(const Duration(minutes: 1)))) {
      throw TimeRangeUnavailableException(
        'This time has already passed. Please pick a current or upcoming time.',
      );
    }
    final minutes = requestedEnd.difference(requestedStart).inMinutes;
    if (minutes < kMinBookingMinutes) {
      throw TimeRangeUnavailableException('Minimum booking duration is $kMinBookingMinutes minutes.');
    }
    if (!isRangeAvailable(charger, requestedStart, requestedEnd)) {
      throw TimeRangeUnavailableException(
        "That time range is no longer available - it may be outside the host's free window or overlap another booking.",
      );
    }
    final heldAmount = PricingService.computeCost(
      model: charger.pricingModel,
      price: charger.price,
      powerKw: charger.powerKw,
      minutes: minutes.toDouble(),
    );
    final booking = Booking(
      id: _uuid.v4(),
      driverId: driverId,
      hostId: charger.hostId,
      chargerId: charger.chargerId,
      chargerName: charger.label,
      carBrand: driverCar.brand,
      carModel: driverCar.model,
      carPlateNumber: driverCar.plateNumber.trim().toUpperCase(),
      carConnector: driverCar.connector.label,
      carChargingStandard: driverCar.chargingStandard.shortLabel,
      carMaxAmpere: driverCar.maxAmpere,
      requestedStart: requestedStart,
      requestedEnd: requestedEnd,
      pricingModel: charger.pricingModel,
      price: charger.price,
      powerKw: charger.powerKw,
      heldAmount: heldAmount,
      chargerMapLink: charger.mapLink,
      chargerLatitude: charger.latitude,
      chargerLongitude: charger.longitude,
    );
    final held = walletService.holdForBooking(driverId: driverId, bookingId: booking.id, amount: heldAmount);
    booking.walletHeld = held;
    booking.evaluateProgress();
    _bookingsById[booking.id] = booking;
    notifyListeners();
    await _db.collection('bookings').doc(booking.id).set(booking.toFirestore());
    await notificationService.notify(
      recipientId: charger.hostId,
      type: NotificationType.bookingRequested,
      title: 'New booking request',
      body: '$driverName requested to book "${charger.label}" for '
          '${_timeRangeLabel(requestedStart, requestedEnd)}.',
      bookingId: booking.id,
      chargerId: charger.chargerId,
    );
    return booking;
  }

  Future<void> hostRespond(String bookingId, {required bool approve}) async {
    final booking = findById(bookingId);
    if (booking == null) return;
    if (!approve) {
      booking.status = BookingStatus.declinedByHost;
      if (booking.walletHeld) walletService.releaseHold(driverId: booking.driverId, bookingId: booking.id);
    } else {
      booking.hostApproved = true;
      booking.evaluateProgress();
    }
    notifyListeners();
    await _db.collection('bookings').doc(bookingId).set(booking.toFirestore(), SetOptions(merge: true));
    await notificationService.notify(
      recipientId: booking.driverId,
      type: approve ? NotificationType.bookingApproved : NotificationType.bookingDeclined,
      title: approve ? 'Booking approved!' : 'Booking declined',
      body: approve
          ? 'Your booking at "${booking.chargerName}" was approved. Head over when it\'s time to charge.'
          : 'Your booking request at "${booking.chargerName}" was declined. Your held funds were refunded.',
      bookingId: booking.id,
      chargerId: booking.chargerId,
    );
  }

  Future<void> driverCancel(String bookingId) async {
    final booking = findById(bookingId);
    if (booking == null || !ongoingStatuses.contains(booking.status)) return;
    booking.status = BookingStatus.cancelledByDriver;
    if (booking.walletHeld) walletService.releaseHold(driverId: booking.driverId, bookingId: booking.id);
    notifyListeners();
    await _db.collection('bookings').doc(bookingId).set(booking.toFirestore(), SetOptions(merge: true));
  }

  Future<void> adminCancel(String bookingId) async {
    final booking = findById(bookingId);
    if (booking == null || !ongoingStatuses.contains(booking.status)) return;
    booking.status = BookingStatus.cancelledByAdmin;
    if (booking.walletHeld) walletService.releaseHold(driverId: booking.driverId, bookingId: booking.id);
    notifyListeners();
    await _db.collection('bookings').doc(bookingId).set(booking.toFirestore(), SetOptions(merge: true));
  }

  Future<bool> confirmAccessByQr(String bookingId, String scannedPayload) async {
    final booking = findById(bookingId);
    if (booking == null) return false;
    final ok = booking.validateScan(scannedPayload, DateTime.now());
    notifyListeners();
    if (ok) await _db.collection('bookings').doc(bookingId).set(booking.toFirestore(), SetOptions(merge: true));
    return ok;
  }

  Future<bool> startSession(String bookingId) async {
    final booking = findById(bookingId);
    if (booking == null) return false;
    final ok = booking.startSession(DateTime.now());
    notifyListeners();
    if (ok) {
      await _db.collection('bookings').doc(bookingId).set(booking.toFirestore(), SetOptions(merge: true));
      await notificationService.notify(
        recipientId: booking.hostId,
        type: NotificationType.sessionStarted,
        title: 'Charging session started',
        body: 'The driver has started charging at "${booking.chargerName}".',
        bookingId: booking.id,
        chargerId: booking.chargerId,
      );
    }
    return ok;
  }

  /// FIX (9/15 update - "host can be able to stop the service as the
  /// host doesn't have the option of that"): previously only the DRIVER
  /// could stop a charging session (see `completeSession` calls from
  /// screens/driver/booking_status_screen.dart) - a host had no
  /// equivalent action anywhere in the app, even though a host is just
  /// as likely to need to end a session (e.g. the driver already left,
  /// or the host needs the station back). `completeSession` itself
  /// already works identically regardless of who calls it (it doesn't
  /// check any role), so the actual fix is exposing a host-facing call
  /// site with clear naming for auditability/logging purposes - see the
  /// new Stop buttons in screens/host/host_scan_screen.dart and
  /// screens/driver/my_bookings_screen.dart's host "As Host" view.
  Future<void> hostStopSession(String bookingId) => completeSession(bookingId);

  /// FIX (9/15 update - "once the charging is done the admin should have
  /// a request to release the payment after the calculation (kw * x) and
  /// it should be transferred to the host wallet"): this method itself
  /// is UNCHANGED in terms of what it computes (Booking.completeAndSettle
  /// still calculates actualCost/overstay exactly as before) - the only
  /// change is which WalletService method is called to actually pay out.
  /// Previously `walletService.settleBooking(...)` credited the host
  /// INSTANTLY with zero admin involvement. It now calls
  /// `walletService.settleBookingWithPendingPayout(...)` instead, which
  /// still refunds the driver's unused hold immediately (that's just
  /// returning the driver their own money), but creates a PayoutRequest
  /// for the host's share instead of crediting it directly - the host is
  /// only actually paid once an admin approves it from the new Payouts
  /// tab (see screens/admin/admin_home_screen.dart).
  Future<void> completeSession(String bookingId) async {
    final booking = findById(bookingId);
    if (booking == null) return;
    booking.completeAndSettle(DateTime.now());

    await walletService.settleBookingWithPendingPayout(
      bookingId: booking.id,
      driverId: booking.driverId,
      hostId: booking.hostId,
      chargerName: booking.chargerName,
      actualCost: booking.actualCost ?? 0,
      powerKw: booking.powerKw,
      pricePerUnit: booking.price,
      pricingModelName: booking.pricingModel.name,
      actualDurationSeconds: booking.actualDuration?.inSeconds ?? 0,
    );

    final penalty = booking.overstayPenalty ?? 0;
    if (penalty > 0) {
      // Overstay compensation is a penalty mechanism, not the primary
      // "kw * price" charging payment - it remains an immediate,
      // automatic transfer (unchanged from before), since it's
      // compensating the host for blocked station time, not billing the
      // driver for energy/time actually delivered.
      walletService.chargeOverstayPenalty(
        driverId: booking.driverId,
        hostId: booking.hostId,
        bookingId: booking.id,
        penaltyAmount: penalty,
        overstayMinutes: booking.overstayMinutes ?? 0,
      );
    }
    notifyListeners();
    await _db.collection('bookings').doc(bookingId).set(booking.toFirestore(), SetOptions(merge: true));
  }

  static String _timeRangeLabel(DateTime start, DateTime end) {
    String two(int n) => n.toString().padLeft(2, '0');
    String fmt(DateTime d) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final ampm = d.hour >= 12 ? 'PM' : 'AM';
      return '$h:${two(d.minute)} $ampm';
    }
    return '${fmt(start)} - ${fmt(end)}';
  }
}
