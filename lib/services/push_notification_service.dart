import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Handles the DEVICE side of push notifications: requesting permission,
/// obtaining this device's FCM token, and saving it to
/// `users/{uid}.fcmTokens` (an array, since a user might be signed in on
/// more than one device/phone). The actual sending of a push (when a
/// booking/top-up notification happens) is done server-side by a Cloud
/// Function (see functions/index.js), which reads these tokens.
///
/// Call `PushNotificationService.initAndRegister(uid)` once right after
/// a user signs in (see main.dart, register_screen.dart, sign_in_screen.dart)
/// - this is what makes "notifications should be active" true in
/// practice: without a registered token, the Cloud Function has nowhere
/// to send the push to, even though the Firestore notification document
/// itself would still be created correctly.
class PushNotificationService {
  PushNotificationService._();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Requests notification permission (required on iOS, and on Android
  /// 13+) and, if granted, saves this device's current FCM token to the
  /// user's Firestore document. Also listens for token refreshes (FCM
  /// tokens can change, e.g. after a reinstall) and keeps Firestore in
  /// sync automatically for the lifetime of the app.
  static Future<void> initAndRegister(String uid) async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('PushNotificationService: user denied notification permission.');
        return;
      }
      final token = await _messaging.getToken();
      if (token != null) {
        await _saveToken(uid, token);
      }
      _messaging.onTokenRefresh.listen((newToken) => _saveToken(uid, newToken));
    } catch (e) {
      debugPrint('PushNotificationService.initAndRegister failed: $e');
    }
  }

  static Future<void> _saveToken(String uid, String token) async {
    await _db.collection('users').doc(uid).set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]),
      },
      SetOptions(merge: true),
    ).catchError((e) => debugPrint('PushNotificationService: failed to save token: $e'));
  }

  /// Call on sign-out so a shared/borrowed device doesn't keep receiving
  /// pushes meant for the account that just signed out.
  static Future<void> removeTokenForCurrentDevice(String uid) async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await _db.collection('users').doc(uid).set(
        {
          'fcmTokens': FieldValue.arrayRemove([token]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('PushNotificationService.removeTokenForCurrentDevice failed: $e');
    }
  }
}
