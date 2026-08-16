import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/booking.dart';
import '../models/charger_profile.dart';
import '../models/enums.dart';
import 'wallet_service.dart';
import 'pricing_service.dart';

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
/// allowed duration, or end <= start.
class TimeRangeUnavailableException implements BookingRequestException {
  @override
  final String message;
  TimeRangeUnavailableException(this.message);
}

/// Minimum booking duration - prevents drivers from requesting
/// unrealistically short charging windows (e.g. 2 minutes).
const int kMinBookingMinutes = 30;

class BookingService extends ChangeNotifier {
  final _uuid = const Uuid();
  final WalletService walletService;

  BookingService({required this.walletService});

  final List<Booking> _bookings = [];

  List<Booking> get all => List.unmodifiable(_bookings);

  List<Booking> bookingsForDriver(String driverId) => _bookings.where((b) => b.driverId == driverId).toList();

  List<Booking> ongoingForDriver(String driverId) => _bookings
      .where((b) => b.driverId == driverId && BookingService.ongoingStatuses.contains(b.status))
      .toList();

  List<Booking> pendingApprovalsForHost(String hostId) =>
      _bookings.where((b) => b.hostId == hostId && b.status == BookingStatus.pendingHostApproval).toList();

  List<Booking> confirmedForHost(String hostId) =>
      _bookings.where((b) => b.hostId == hostId && b.status == BookingStatus.confirmed).toList();

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

  /// Bookings for a specific charger that are still "live" (would block a
  /// new overlapping request) - used by `isRangeAvailable` below.
  List<Booking> _liveBookingsForCharger(String chargerId) =>
      _bookings.where((b) => b.chargerId == chargerId && ongoingStatuses.contains(b.status)).toList();

  /// Checks whether a CUSTOM time range from `start` up to (but not
  /// including) `end` can actually be booked on this charger:
  ///   1. It must fit entirely within at least one of the host's free
  ///      windows (e.g. a 2:00 PM-4:00 PM request must fit inside a
  ///      10:00 AM-10:00 PM window).
  ///   2. It must NOT overlap any other currently-live booking already
  ///      made on this same charger (by this or any other driver).
  bool isRangeAvailable(ChargerProfile charger, DateTime start, DateTime end) {
    final fitsSomeWindow = charger.freeSlots.any((s) => s.canFit(start, end));
    if (!fitsSomeWindow) return false;

    final overlaps = _liveBookingsForCharger(charger.chargerId).any(
      (b) => b.requestedStart.isBefore(end) && start.isBefore(b.requestedEnd),
    );
    return !overlaps;
  }

  /// Creates a booking request for a CUSTOM driver-chosen time range
  /// (which may be a sub-range of a larger host-defined free window).
  Booking createRequest({
    required String driverId,
    required ChargerProfile charger,
    required DateTime requestedStart,
    required DateTime requestedEnd,
    required String? driverCommunity,
  }) {
    if (!charger.isAccessibleToCommunity(driverCommunity)) {
      throw ChargerAccessDeniedException(
        'This charger is restricted to ${charger.restrictedCommunity} residents only.',
      );
    }

    if (!requestedEnd.isAfter(requestedStart)) {
      throw TimeRangeUnavailableException('End time must be after start time.');
    }
    final minutes = requestedEnd.difference(requestedStart).inMinutes;
    if (minutes < kMinBookingMinutes) {
      throw TimeRangeUnavailableException('Minimum booking duration is $kMinBookingMinutes minutes.');
    }
    if (!isRangeAvailable(charger, requestedStart, requestedEnd)) {
      throw TimeRangeUnavailableException(
        'That time range is no longer available - it may be outside the host\'s free window or overlap another booking.',
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

  bool confirmAccessByQr(String bookingId, String scannedPayload) {
    final booking = findById(bookingId);
    if (booking == null) return false;
    final ok = booking.validateScan(scannedPayload, DateTime.now());
    notifyListeners();
    return ok;
  }

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
