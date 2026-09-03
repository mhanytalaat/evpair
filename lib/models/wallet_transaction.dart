import '../models/enums.dart';

class TopUpRequest {
  final String id;
  final String driverId;
  final double amount;
  final PaymentMethod method;
  final String referenceNote;
  final String proofImagePath;
  /// Base64-encoded screenshot proof of the payment (InstaPay/Vodafone
  /// Cash confirmation). Stored directly on the Firestore document, same
  /// pattern already used for profile photos and charger photos
  /// elsewhere in the app (avoids Firebase Storage's CORS setup on
  /// Flutter Web). Null only for legacy requests submitted before this
  /// field existed.
  final String? proofImageBase64;
  TopUpStatus status;
  DateTime requestedAt;
  DateTime? reviewedAt;
  String? adminNote;

  TopUpRequest({
    required this.id,
    required this.driverId,
    required this.amount,
    required this.method,
    required this.referenceNote,
    required this.proofImagePath,
    this.proofImageBase64,
    this.status = TopUpStatus.pendingProofReview,
    DateTime? requestedAt,
    this.reviewedAt,
    this.adminNote,
  }) : requestedAt = requestedAt ?? DateTime.now();
}

class WalletLedgerEntry {
  final String id;
  final String userId;
  final double amount;
  final String reason;
  final DateTime timestamp;

  WalletLedgerEntry({
    required this.id,
    required this.userId,
    required this.amount,
    required this.reason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
