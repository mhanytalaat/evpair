import 'package:cloud_firestore/cloud_firestore.dart';

/// What kind of event this notification represents - lets the UI show a
/// relevant icon/color and lets tapping it navigate somewhere sensible
/// (see NotificationsScreen).
enum NotificationType {
  bookingRequested, // host: a driver requested to book their charger
  bookingApproved, // driver: host approved their request
  bookingDeclined, // driver: host declined their request
  topUpApproved, // driver: their wallet top-up was approved
  topUpRejected, // driver: their wallet top-up was rejected
  sessionStarted, // host: a driver started their charging session
  other,
}

/// A single notification for ONE recipient (driverId or hostId - stored
/// generically as `recipientId`). Persisted to Firestore at
/// `notifications/{id}` so it survives app restarts and is visible across
/// every device the recipient signs into - this is what actually fixes
/// "the host doesn't get notified" bug, since notifications previously
/// didn't exist as a Firestore-backed concept at all.
///
/// A Cloud Function trigger (see functions/index.js) listens for new
/// documents in this collection and sends an actual push notification
/// (FCM) to the recipient's registered device token - so notifications
/// arrive even if the EVPair app is fully closed, not just when it's
/// open. This class only handles the in-app/Firestore side; the actual
/// push delivery happens server-side via that Cloud Function.
class AppNotification {
  final String id;
  final String recipientId;
  final NotificationType type;
  final String title;
  final String body;
  /// Optional deep-link-ish fields so tapping the notification can jump
  /// straight to the relevant screen (e.g. a specific booking or
  /// charger) - see NotificationsScreen._onTap.
  final String? bookingId;
  final String? chargerId;
  final DateTime createdAt;
  bool isRead;

  AppNotification({
    required this.id,
    required this.recipientId,
    required this.type,
    required this.title,
    required this.body,
    this.bookingId,
    this.chargerId,
    DateTime? createdAt,
    this.isRead = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toFirestore() {
    return {
      'recipientId': recipientId,
      'type': type.name,
      'title': title,
      'body': body,
      'bookingId': bookingId,
      'chargerId': chargerId,
      'createdAt': Timestamp.fromDate(createdAt),
      'isRead': isRead,
    };
  }

  factory AppNotification.fromFirestore(String id, Map<String, dynamic> data) {
    final created = data['createdAt'];
    return AppNotification(
      id: id,
      recipientId: data['recipientId'] as String? ?? '',
      type: NotificationType.values.firstWhere(
        (t) => t.name == data['type'],
        orElse: () => NotificationType.other,
      ),
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      bookingId: data['bookingId'] as String?,
      chargerId: data['chargerId'] as String?,
      createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
      isRead: data['isRead'] as bool? ?? false,
    );
  }
}
