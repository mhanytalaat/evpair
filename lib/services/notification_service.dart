import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/app_notification.dart';

/// Keeps a live (real-time) list of the signed-in user's notifications,
/// and exposes `unreadCount` for the badge shown on the profile avatar in
/// the footer nav (see DriverHomeScreen._footerProfileAvatar).
///
/// FIX (3/9 update - "no notification badge appeared on the profile icon
/// even after opening the app"): the query previously combined
/// `.where('recipientId', isEqualTo: userId)` with
/// `.orderBy('createdAt', descending: true)`. Firestore REQUIRES a
/// composite index for a where-on-one-field + orderBy-on-a-different-
/// field query - without that index manually created in the console,
/// the query throws a `failed-precondition: The query requires an
/// index...` error. That error was only ever logged via
/// `onError: (e) => debugPrint(...)` and silently swallowed - so the
/// listener simply never delivered any data, the notification list
/// stayed empty, and the badge never appeared, even though the
/// `AppNotification` document itself was very likely created correctly
/// in Firestore by BookingService.createRequest.
///
/// FIX: the query now ONLY filters by `recipientId` (a single-field
/// equality filter, which Firestore always auto-indexes with zero setup
/// required) and sorts the results by `createdAt` CLIENT-SIDE in Dart
/// instead. This removes the need for you to ever manually create a
/// Firestore index for this feature.
class NotificationService extends ChangeNotifier {
  NotificationService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  final _uuid = const Uuid();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  List<AppNotification> _notifications = [];
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Attaches a live listener scoped to this user's own notifications.
  /// Call after sign-in/registration and once at app startup if already
  /// signed in (see main.dart). Cancels any previous listener first, so
  /// switching accounts never leaks a stale subscription pointed at the
  /// previous user's notifications.
  void listenFor(String userId) {
    _subscription?.cancel();
    _subscription = _db
        .collection('notifications')
        .where('recipientId', isEqualTo: userId)
        // NOTE: intentionally no .orderBy() here anymore - see class
        // doc above. Sorting happens client-side below instead, which
        // requires no Firestore composite index at all.
        .limit(200)
        .snapshots()
        .listen(
      (snapshot) {
        _notifications = snapshot.docs.map((d) => AppNotification.fromFirestore(d.id, d.data())).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        notifyListeners();
      },
      onError: (e) => debugPrint('NotificationService: listener error: $e'),
    );
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _notifications = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> markRead(String notificationId) async {
    await _db.collection('notifications').doc(notificationId).update({'isRead': true}).catchError(
        (e) => debugPrint('NotificationService: failed to mark $notificationId read: $e'));
  }

  Future<void> markAllRead() async {
    final unread = _notifications.where((n) => !n.isRead).toList();
    if (unread.isEmpty) return;
    final batch = _db.batch();
    for (final n in unread) {
      batch.update(_db.collection('notifications').doc(n.id), {'isRead': true});
    }
    await batch.commit().catchError((e) => debugPrint('NotificationService: failed to mark all read: $e'));
  }

  /// Creates a notification document for `recipientId`. This is the
  /// single call site every feature (bookings, top-ups, etc.) should use
  /// - see BookingService.createRequest/hostRespond and
  /// WalletService.reviewTopUp for real call sites.
  Future<void> notify({
    required String recipientId,
    required NotificationType type,
    required String title,
    required String body,
    String? bookingId,
    String? chargerId,
  }) async {
    final notification = AppNotification(
      id: _uuid.v4(),
      recipientId: recipientId,
      type: type,
      title: title,
      body: body,
      bookingId: bookingId,
      chargerId: chargerId,
    );
    await _db.collection('notifications').doc(notification.id).set(notification.toFirestore()).catchError(
        (e) => debugPrint('NotificationService: failed to create notification for $recipientId: $e'));
  }
}
