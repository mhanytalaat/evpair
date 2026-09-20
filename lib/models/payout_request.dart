import 'package:cloud_firestore/cloud_firestore.dart';
import 'enums.dart';

/// Represents the host's earnings for ONE completed booking, pending
/// admin review before the funds are actually credited to the host's
/// wallet.
///
/// NEW (9/15 update - "once the charging is done the admin should have
/// a request to release the payment after the calculation (kw * price)
/// and it should be transferred to the host wallet"): previously
/// `BookingService.completeSession()` called
/// `WalletService.settleBooking()`, which credited the host's share of
/// the actual charging cost INSTANTLY and automatically, with zero admin
/// involvement - the exact opposite of what's requested here. This
/// model, together with the new payout flow in `WalletService`
/// (`createPayoutRequest` / `reviewPayout`), replaces that automatic
/// credit with a review step: the calculated amount is held in a
/// `pendingReview` record instead of being credited right away, and only
/// actually lands in the host's wallet once an admin taps Approve on the
/// new Payouts tab (see `screens/admin/admin_home_screen.dart`).
class PayoutRequest {
  final String id;
  final String bookingId;
  final String hostId;
  final String driverId;
  final String chargerName;
  final double powerKw;
  /// EGP per minute or per kWh, depending on [pricingModelName].
  final double pricePerUnit;
  /// 'perMinute' or 'perKwh' - kept as a plain string (matching
  /// `PricingModel.name`) so this model has no dependency on
  /// pricing_service.dart.
  final String pricingModelName;
  /// What the driver was actually charged (before commission), i.e. the
  /// "kw * price" calculation result.
  final double actualCost;
  final double commissionRate;
  /// actualCost * (1 - commissionRate) - what the host will receive if
  /// this request is approved.
  final double hostAmount;
  final int actualDurationSeconds;
  PayoutStatus status;
  final DateTime requestedAt;
  DateTime? reviewedAt;
  String? adminNote;

  PayoutRequest({
    required this.id,
    required this.bookingId,
    required this.hostId,
    required this.driverId,
    required this.chargerName,
    required this.powerKw,
    required this.pricePerUnit,
    required this.pricingModelName,
    required this.actualCost,
    required this.commissionRate,
    required this.hostAmount,
    required this.actualDurationSeconds,
    this.status = PayoutStatus.pendingReview,
    DateTime? requestedAt,
    this.reviewedAt,
    this.adminNote,
  }) : requestedAt = requestedAt ?? DateTime.now();

  /// Human-readable calculation breakdown shown to the admin, e.g.
  /// "22.0 kW x 45 min x 2.00 EGP/min" or
  /// "22.0 kW x 0.35 kWh x 3.50 EGP/kWh" - directly answers "the
  /// calculation (kw * price)" from the admin's review screen.
  String get calculationLabel {
    final minutes = actualDurationSeconds / 60.0;
    if (pricingModelName == 'perKwh') {
      final kwh = powerKw * (minutes / 60.0);
      return '${powerKw.toStringAsFixed(1)} kW x ${kwh.toStringAsFixed(2)} kWh x ${pricePerUnit.toStringAsFixed(2)} EGP/kWh';
    }
    return '${powerKw.toStringAsFixed(1)} kW x ${minutes.toStringAsFixed(0)} min x ${pricePerUnit.toStringAsFixed(2)} EGP/min';
  }

  Map<String, dynamic> toFirestore() {
    return {
      'bookingId': bookingId,
      'hostId': hostId,
      'driverId': driverId,
      'chargerName': chargerName,
      'powerKw': powerKw,
      'pricePerUnit': pricePerUnit,
      'pricingModelName': pricingModelName,
      'actualCost': actualCost,
      'commissionRate': commissionRate,
      'hostAmount': hostAmount,
      'actualDurationSeconds': actualDurationSeconds,
      'status': status.name,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'reviewedAt': reviewedAt == null ? null : Timestamp.fromDate(reviewedAt!),
      'adminNote': adminNote,
    };
  }

  factory PayoutRequest.fromFirestore(String id, Map<String, dynamic> data) {
    final requestedAt = data['requestedAt'];
    final reviewedAt = data['reviewedAt'];
    return PayoutRequest(
      id: id,
      bookingId: data['bookingId'] as String? ?? '',
      hostId: data['hostId'] as String? ?? '',
      driverId: data['driverId'] as String? ?? '',
      chargerName: data['chargerName'] as String? ?? '',
      powerKw: (data['powerKw'] as num?)?.toDouble() ?? 0,
      pricePerUnit: (data['pricePerUnit'] as num?)?.toDouble() ?? 0,
      pricingModelName: data['pricingModelName'] as String? ?? 'perMinute',
      actualCost: (data['actualCost'] as num?)?.toDouble() ?? 0,
      commissionRate: (data['commissionRate'] as num?)?.toDouble() ?? 0.10,
      hostAmount: (data['hostAmount'] as num?)?.toDouble() ?? 0,
      actualDurationSeconds: (data['actualDurationSeconds'] as num?)?.toInt() ?? 0,
      status: PayoutStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => PayoutStatus.pendingReview,
      ),
      requestedAt: requestedAt is Timestamp ? requestedAt.toDate() : DateTime.now(),
      reviewedAt: reviewedAt is Timestamp ? reviewedAt.toDate() : null,
      adminNote: data['adminNote'] as String?,
    );
  }
}
