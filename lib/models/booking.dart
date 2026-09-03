import 'package:cloud_firestore/cloud_firestore.dart';
import 'enums.dart';
import '../services/pricing_service.dart';

/// Grace period after the booked end time before an overstay penalty
/// starts accruing. Covers realistic cases like walking back to the car.
const int kOverstayGraceMinutes = 15;

/// Flat per-minute penalty (EGP) charged once a session is stopped more
/// than kOverstayGraceMinutes after the originally booked end time.
/// Models a driver leaving the car parked/plugged in well past their
/// reserved window, which blocks the next driver from using the station.
const double kOverstayPenaltyPerMinute = 2.0;

class Booking {
  final String id;
  final String driverId;
  final String hostId;
  final String chargerId;
  final String chargerName;
  final String carBrand;
  final String carModel;
  final String carPlateNumber;
  final String carConnector;
  final String carChargingStandard;
  final double carMaxAmpere;

  /// The driver's CUSTOM requested time range - can be any sub-range
  /// within a host's free window (e.g. a host window of 10:00 AM-10:00 PM
  /// lets a driver request just 2:00 PM-4:00 PM).
  final DateTime requestedStart;
  final DateTime requestedEnd;

  final PricingModel pricingModel;
  final double price;
  final double powerKw;
  final double heldAmount;
  final String? chargerMapLink;
  final double chargerLatitude;
  final double chargerLongitude;

  BookingStatus status;
  bool walletHeld;
  bool hostApproved;
  String? qrCodePayload;
  DateTime? qrScannedAt;
  DateTime? sessionStartedAt;
  DateTime? sessionEndedAt;
  double? actualCost;
  Duration? actualDuration;

  /// How many minutes past (requestedEnd + kOverstayGraceMinutes) the
  /// session was actually stopped, or 0 if stopped on time. Set by
  /// completeAndSettle().
  int? overstayMinutes;

  /// Penalty charged for the overstay above, in EGP. Set by
  /// completeAndSettle(). This is charged separately from actualCost/the
  /// wallet hold, since the held amount only ever covers the originally
  /// booked duration.
  double? overstayPenalty;

  Booking({
    required this.id,
    required this.driverId,
    required this.hostId,
    required this.chargerId,
    required this.chargerName,
    required this.carBrand,
    required this.carModel,
    required this.carPlateNumber,
    required this.carConnector,
    required this.carChargingStandard,
    required this.carMaxAmpere,
    required this.requestedStart,
    required this.requestedEnd,
    required this.pricingModel,
    required this.price,
    required this.powerKw,
    required this.heldAmount,
    required this.chargerLatitude,
    required this.chargerLongitude,
    this.chargerMapLink,
    this.status = BookingStatus.pendingWalletHold,
    this.walletHeld = false,
    this.hostApproved = false,
    this.qrCodePayload,
    this.qrScannedAt,
    this.sessionStartedAt,
    this.sessionEndedAt,
    this.actualCost,
    this.actualDuration,
    this.overstayMinutes,
    this.overstayPenalty,
  });

  Duration get reservedDuration => requestedEnd.difference(requestedStart);

  String get mapsUrl {
    if (chargerMapLink != null && chargerMapLink!.trim().isNotEmpty) {
      return chargerMapLink!;
    }
    return 'https://www.google.com/maps/search/?api=1&query=$chargerLatitude,$chargerLongitude';
  }

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
      qrCodePayload ??= _generateQrPayload();
    }
  }

  String _generateQrPayload() {
    return 'PSEV|booking=$id|driver=$driverId|charger=$chargerId|'
        'start=${requestedStart.toIso8601String()}|end=${requestedEnd.toIso8601String()}';
  }

  /// PAUSED FOR NOW: QR-code-based access confirmation. Kept intact for a
  /// possible future re-enable - use `startSession()` for the current
  /// "Start" button flow instead.
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
    // Overstay penalty: if the session is stopped more than the grace
    // period after the originally booked end time, charge a flat
    // per-minute penalty. This is separate from actualCost/heldAmount
    // because those only ever cover the booked duration - there is no
    // wallet hold covering extra time the driver wasn't supposed to use.
    final lateBy = now.difference(requestedEnd).inMinutes;
    if (lateBy > kOverstayGraceMinutes) {
      overstayMinutes = lateBy - kOverstayGraceMinutes;
      overstayPenalty = (overstayMinutes! * kOverstayPenaltyPerMinute).roundToDouble();
    } else {
      overstayMinutes = 0;
      overstayPenalty = 0;
    }
    status = BookingStatus.completed;
    return heldAmount - cappedCost;
  }

  /// Firestore document shape for the `bookings` collection. This is
  /// what actually fixes bookings only ever "existing" on the device
  /// that created them - previously BookingService kept bookings ONLY in
  /// an in-memory list, so a host on a different device/phone than the
  /// driver could never see a booking request at all, no matter how many
  /// times they opened Manage Charger. See services/booking_service.dart
  /// for the real-time listeners that now read this collection.
  Map<String, dynamic> toFirestore() {
    return {
      'driverId': driverId,
      'hostId': hostId,
      'chargerId': chargerId,
      'chargerName': chargerName,
      'carBrand': carBrand,
      'carModel': carModel,
      'carPlateNumber': carPlateNumber,
      'carConnector': carConnector,
      'carChargingStandard': carChargingStandard,
      'carMaxAmpere': carMaxAmpere,
      'requestedStart': Timestamp.fromDate(requestedStart),
      'requestedEnd': Timestamp.fromDate(requestedEnd),
      'pricingModel': pricingModel.name,
      'price': price,
      'powerKw': powerKw,
      'heldAmount': heldAmount,
      'chargerMapLink': chargerMapLink,
      'chargerLatitude': chargerLatitude,
      'chargerLongitude': chargerLongitude,
      'status': status.name,
      'walletHeld': walletHeld,
      'hostApproved': hostApproved,
      'qrCodePayload': qrCodePayload,
      'qrScannedAt': qrScannedAt == null ? null : Timestamp.fromDate(qrScannedAt!),
      'sessionStartedAt': sessionStartedAt == null ? null : Timestamp.fromDate(sessionStartedAt!),
      'sessionEndedAt': sessionEndedAt == null ? null : Timestamp.fromDate(sessionEndedAt!),
      'actualCost': actualCost,
      'actualDurationSeconds': actualDuration?.inSeconds,
      'overstayMinutes': overstayMinutes,
      'overstayPenalty': overstayPenalty,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory Booking.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? tsOrNull(dynamic v) => v is Timestamp ? v.toDate() : null;
    final actualDurationSeconds = data['actualDurationSeconds'] as num?;
    return Booking(
      id: id,
      driverId: data['driverId'] as String? ?? '',
      hostId: data['hostId'] as String? ?? '',
      chargerId: data['chargerId'] as String? ?? '',
      chargerName: data['chargerName'] as String? ?? '',
      carBrand: data['carBrand'] as String? ?? '',
      carModel: data['carModel'] as String? ?? '',
      carPlateNumber: data['carPlateNumber'] as String? ?? '',
      carConnector: data['carConnector'] as String? ?? '',
      carChargingStandard: data['carChargingStandard'] as String? ?? '',
      carMaxAmpere: (data['carMaxAmpere'] as num?)?.toDouble() ?? 0,
      requestedStart: tsOrNull(data['requestedStart']) ?? DateTime.now(),
      requestedEnd: tsOrNull(data['requestedEnd']) ?? DateTime.now(),
      pricingModel: PricingModel.values.firstWhere(
        (m) => m.name == data['pricingModel'],
        orElse: () => PricingModel.perMinute,
      ),
      price: (data['price'] as num?)?.toDouble() ?? 0,
      powerKw: (data['powerKw'] as num?)?.toDouble() ?? 0,
      heldAmount: (data['heldAmount'] as num?)?.toDouble() ?? 0,
      chargerMapLink: data['chargerMapLink'] as String?,
      chargerLatitude: (data['chargerLatitude'] as num?)?.toDouble() ?? 0,
      chargerLongitude: (data['chargerLongitude'] as num?)?.toDouble() ?? 0,
      status: BookingStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => BookingStatus.pendingWalletHold,
      ),
      walletHeld: data['walletHeld'] as bool? ?? false,
      hostApproved: data['hostApproved'] as bool? ?? false,
      qrCodePayload: data['qrCodePayload'] as String?,
      qrScannedAt: tsOrNull(data['qrScannedAt']),
      sessionStartedAt: tsOrNull(data['sessionStartedAt']),
      sessionEndedAt: tsOrNull(data['sessionEndedAt']),
      actualCost: (data['actualCost'] as num?)?.toDouble(),
      actualDuration: actualDurationSeconds == null ? null : Duration(seconds: actualDurationSeconds.toInt()),
      overstayMinutes: (data['overstayMinutes'] as num?)?.toInt(),
      overstayPenalty: (data['overstayPenalty'] as num?)?.toDouble(),
    );
  }
}
