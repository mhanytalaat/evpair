import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/booking.dart';
import '../models/charger_profile.dart';
import '../models/enums.dart';
import '../models/availability_slot.dart';
import 'wallet_service.dart';
import 'pricing_service.dart';

class ChargerAccessDeniedException implements Exception {
  final String message;
  ChargerAccessDeniedException(this.message);
}

class BookingService extends ChangeNotifier {
  final _uuid = const Uuid();
  final WalletService walletService;

  BookingService({required this.walletService});

  final List<Booking> _bookings = [];

  List<Booking> get all => List.unmodifiable(_bookings);

  List<Booking> bookingsForDriver(String driverId) => _bookings.where((b) => b.driverId == driverId).toList();

  /// Driver's bookings that are still "alive": pending approval,
  /// confirmed (booked, awaiting driver to start), or actively charging.
  List<Booking> ongoingForDriver(String driverId) => _bookings
      .where((b) => b.driverId == driverId && BookingService.ongoingStatuses.contains(b.status))
      .toList();

  List<Booking> pendingApprovalsForHost(String hostId) =>
      _bookings.where((b) => b.hostId == hostId && b.status == BookingStatus.pendingHostApproval).toList();

  /// Bookings for this host that are CONFIRMED (booked, waiting for the
  /// driver to tap "Start") - NOT yet an active session.
  List<Booking> confirmedForHost(String hostId) =>
      _bookings.where((b) => b.hostId == hostId && b.status == BookingStatus.confirmed).toList();

  /// Bookings for this host where a session is ACTIVELY running (driver
  /// has tapped Start, charging in progress).
  List<Booking> inProgressForHost(String hostId) =>
      _bookings.where((b) => b.hostId == hostId && b.status == BookingStatus.inProgress).toList();

  List<Booking> activeForHost(String hostId) => _bookings
      .where((b) => b.hostId == hostId && (b.status == BookingStatus.confirmed || b.status == BookingStatus.inProgress))
      .toList();

  Booking? findById(String id) {
    try {
      return _bookings.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

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
  ];

  List<Booking> filterByCategory(String category) {
    switch (category) {
      case 'ongoing':
        return _bookings.where((b) => ongoingStatuses.contains(b.status)).toList();
      case 'completed':
        return _bookings.where((b) => b.status == BookingStatus.completed).toList();
      case 'cancelled':
        return _bookings.where((b) => cancelledStatuses.contains(b.status)).toList();
      default:
        return List.of(_bookings);
    }
  }

  Booking createRequest({
    required String driverId,
    required ChargerProfile charger,
    required AvailabilitySlot slot,
    required String? driverCommunity,
  }) {
    if (!charger.isAccessibleToCommunity(driverCommunity)) {
      throw ChargerAccessDeniedException(
        'This charger is restricted to ${charger.restrictedCommunity} residents only.',
      );
    }

    final minutes = slot.durationMinutes.toDouble();
    final heldAmount = PricingService.computeCost(
      model: charger.pricingModel,
      price: charger.price,
      powerKw: charger.powerKw,
      minutes: minutes,
    );

    final booking = Booking(
      id: _uuid.v4(),
      driverId: driverId,
      hostId: charger.hostId,
      chargerId: charger.chargerId,
      chargerName: charger.label,
      requestedStart: slot.start,
      requestedEnd: slot.end,
      pricingModel: charger.pricingModel,
      price: charger.price,
      powerKw: charger.powerKw,
      heldAmount: heldAmount,
    );

    final held = walletService.holdForBooking(driverId: driverId, bookingId: booking.id, amount: heldAmount);
    booking.walletHeld = held;
    booking.evaluateProgress();
    if (held) slot.isBooked = true;

    _bookings.add(booking);
    notifyListeners();
    return booking;
  }

  void hostRespond(String bookingId, {required bool approve}) {
    final booking = findById(bookingId);
    if (booking == null) return;
    if (!approve) {
      booking.status = BookingStatus.declinedByHost;
      if (booking.walletHeld) walletService.releaseHold(driverId: booking.driverId, bookingId: booking.id);
      notifyListeners();
      return;
    }
    booking.hostApproved = true;
    booking.evaluateProgress();
    notifyListeners();
  }

  void driverCancel(String bookingId) {
    final booking = findById(bookingId);
    if (booking == null || !ongoingStatuses.contains(booking.status)) return;
    booking.status = BookingStatus.cancelledByDriver;
    if (booking.walletHeld) walletService.releaseHold(driverId: booking.driverId, bookingId: booking.id);
    notifyListeners();
  }

  void adminCancel(String bookingId) {
    final booking = findById(bookingId);
    if (booking == null || !ongoingStatuses.contains(booking.status)) return;
    booking.status = BookingStatus.cancelledByAdmin;
    if (booking.walletHeld) walletService.releaseHold(driverId: booking.driverId, bookingId: booking.id);
    notifyListeners();
  }

  /// PAUSED FOR NOW: QR-scan-based session start. Kept intact/unused by
  /// the current UI - see the note on `Booking.validateScan()`.
  bool confirmAccessByQr(String bookingId, String scannedPayload) {
    final booking = findById(bookingId);
    if (booking == null) return false;
    final ok = booking.validateScan(scannedPayload, DateTime.now());
    notifyListeners();
    return ok;
  }

  /// NEW: starts the charging session directly (driver taps "Start" on
  /// BookingStatusScreen) - no QR required. Returns false (and leaves the
  /// booking unchanged) if the booking isn't confirmed yet, or if it's
  /// being started too far ahead of the reserved time.
  bool startSession(String bookingId) {
    final booking = findById(bookingId);
    if (booking == null) return false;
    final ok = booking.startSession(DateTime.now());
    notifyListeners();
    return ok;
  }

  void completeSession(String bookingId) {
    final booking = findById(bookingId);
    if (booking == null) return;
    booking.completeAndSettle(DateTime.now());
    walletService.settleBooking(
      driverId: booking.driverId,
      hostId: booking.hostId,
      bookingId: booking.id,
      actualCost: booking.actualCost ?? 0,
    );
    notifyListeners();
  }
}
