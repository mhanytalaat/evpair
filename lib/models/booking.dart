import 'enums.dart';
import '../services/pricing_service.dart';

class Booking {
  final String id;
  final String driverId;
  final String hostId;
  final String chargerId;
  final String chargerName;
  final DateTime requestedStart;
  final DateTime requestedEnd;

  final PricingModel pricingModel;
  final double price;
  final double powerKw;

  final double heldAmount;

  BookingStatus status;

  bool walletHeld;
  bool hostApproved;

  /// QR-related fields are KEPT (not removed) since QR-based access may be
  /// re-enabled later - see the "stopped for now" note on
  /// `validateScan()` below. The current driver-facing flow does NOT use
  /// these; it uses `startSession()` instead (a simple Start button, no
  /// QR required).
  String? qrCodePayload;
  DateTime? qrScannedAt;

  DateTime? sessionStartedAt;
  DateTime? sessionEndedAt;

  double? actualCost;
  Duration? actualDuration;

  Booking({
    required this.id,
    required this.driverId,
    required this.hostId,
    required this.chargerId,
    required this.chargerName,
    required this.requestedStart,
    required this.requestedEnd,
    required this.pricingModel,
    required this.price,
    required this.powerKw,
    required this.heldAmount,
    this.status = BookingStatus.pendingWalletHold,
    this.walletHeld = false,
    this.hostApproved = false,
    this.qrCodePayload,
    this.qrScannedAt,
    this.sessionStartedAt,
    this.sessionEndedAt,
    this.actualCost,
    this.actualDuration,
  });

  Duration get reservedDuration => requestedEnd.difference(requestedStart);

  void evaluateProgress() {
    if (status == BookingStatus.declinedByHost ||
        status == BookingStatus.cancelledByDriver ||
        status == BookingStatus.cancelledByAdmin ||
        status == BookingStatus.expired) {
      return;
    }
    if (!walletHeld) {
      status = BookingStatus.pendingWalletHold;
      return;
    }
    if (!hostApproved) {
      status = BookingStatus.pendingHostApproval;
      return;
    }
    if (status == BookingStatus.pendingHostApproval && walletHeld && hostApproved) {
      status = BookingStatus.confirmed;
      // QR payload is still generated internally (kept for a possible
      // future re-enable), even though the current UI doesn't display or
      // require it.
      qrCodePayload ??= _generateQrPayload();
    }
  }

  String _generateQrPayload() {
    return 'PSEV|booking=$id|driver=$driverId|charger=$chargerId|'
        'start=${requestedStart.toIso8601String()}|end=${requestedEnd.toIso8601String()}';
  }

  /// PAUSED FOR NOW: QR-code-based access confirmation (host scans the
  /// driver's QR to start the session). Kept intact and unused by the
  /// current UI in case QR scanning is re-enabled later - use
  /// `startSession()` below for the current "Start" button flow instead.
  bool validateScan(String scannedPayload, DateTime now) {
    if (status != BookingStatus.confirmed) return false;
    if (scannedPayload != qrCodePayload) return false;

    final graceBefore = requestedStart.subtract(const Duration(minutes: 15));
    final graceAfter = requestedEnd.add(const Duration(minutes: 15));
    if (now.isBefore(graceBefore) || now.isAfter(graceAfter)) return false;

    qrScannedAt = now;
    sessionStartedAt = now;
    status = BookingStatus.inProgress;
    return true;
  }

  /// NEW: starts the charging session directly from a driver-tapped
  /// "Start" button - no QR scan required. Still requires the booking to
  /// be `confirmed` (wallet held + host approved), and still applies a
  /// light time-window guard (can't start more than 15 minutes before the
  /// reserved start time) to avoid a driver starting a booking way ahead
  /// of schedule, but otherwise has NO upper time bound since the driver
  /// may legitimately arrive later than planned.
  bool startSession(DateTime now) {
    if (status != BookingStatus.confirmed) return false;
    final earliestStart = requestedStart.subtract(const Duration(minutes: 15));
    if (now.isBefore(earliestStart)) return false;

    sessionStartedAt = now;
    status = BookingStatus.inProgress;
    return true;
  }

  double completeAndSettle(DateTime now) {
    sessionEndedAt = now;
    final elapsed = now.difference(sessionStartedAt ?? now);
    actualDuration = elapsed;

    final rawCost = PricingService.computeCost(
      model: pricingModel,
      price: price,
      powerKw: powerKw,
      minutes: elapsed.inSeconds / 60.0,
    );
    final cappedCost = rawCost > heldAmount ? heldAmount : (rawCost < 0 ? 0.0 : rawCost);
    actualCost = cappedCost;
    status = BookingStatus.completed;

    return heldAmount - cappedCost;
  }
}
