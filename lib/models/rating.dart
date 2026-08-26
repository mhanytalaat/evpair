import 'package:cloud_firestore/cloud_firestore.dart';

/// Which side of the booking submitted this rating.
enum RaterRole { driver, host }

extension RaterRoleX on RaterRole {
  /// The role being rated, i.e. the opposite side of a booking.
  RaterRole get opposite => this == RaterRole.driver ? RaterRole.host : RaterRole.driver;
}

/// A single rating left by one side of a completed booking about the
/// other side - a driver rating the host they charged with, or a host
/// rating the driver who used their station. One Rating document per
/// (bookingId, raterRole) pair - see RatingService.hasRatedBooking,
/// which prevents a duplicate "Rate your experience" prompt from
/// appearing after the first submission.
class Rating {
  final String id;
  final String bookingId;
  final String chargerId;
  final String raterId;
  final RaterRole raterRole;
  final String rateeId;
  final int stars; // 1-5
  final String? comment;
  final DateTime createdAt;

  Rating({
    required this.id,
    required this.bookingId,
    required this.chargerId,
    required this.raterId,
    required this.raterRole,
    required this.rateeId,
    required this.stars,
    this.comment,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toFirestore() {
    return {
      'bookingId': bookingId,
      'chargerId': chargerId,
      'raterId': raterId,
      'raterRole': raterRole.name,
      'rateeId': rateeId,
      'stars': stars,
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Rating.fromFirestore(String id, Map<String, dynamic> data) {
    final created = data['createdAt'];
    return Rating(
      id: id,
      bookingId: data['bookingId'] as String? ?? '',
      chargerId: data['chargerId'] as String? ?? '',
      raterId: data['raterId'] as String? ?? '',
      raterRole: RaterRole.values.firstWhere(
        (r) => r.name == data['raterRole'],
        orElse: () => RaterRole.driver,
      ),
      rateeId: data['rateeId'] as String? ?? '',
      stars: (data['stars'] as num?)?.toInt() ?? 5,
      comment: data['comment'] as String?,
      createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
    );
  }
}

/// Aggregated rating summary for a single user (driver or host),
/// computed client-side from their received ratings - see
/// RatingService.fetchSummaryFor. For a high-volume app this would
/// eventually move to a maintained aggregate field (e.g. updated via a
/// Cloud Function trigger) instead of querying+averaging on every view,
/// but computing it on demand is simpler and perfectly fine at MVP scale.
class RatingSummary {
  final double average;
  final int count;

  const RatingSummary({required this.average, required this.count});

  static const empty = RatingSummary(average: 0, count: 0);

  String get displayLabel => count == 0 ? 'No ratings yet' : '${average.toStringAsFixed(1)} ($count)';
}
