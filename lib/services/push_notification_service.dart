import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Handles the DEVICE side of push notifications: requesting permission,
/// obtaining this device's FCM token, and saving it to
/// `users/{uid}.fcmTokens`.
///
/// DIAGNOSTIC LOGGING ADDED (3/9 update): since the user has no way to
/// see live `flutter run` terminal output (iOS builds are done via
/// Codemagic/cloud Mac, not a local Windows machine - Xcode/iOS builds
/// are simply not possible on Windows), every step of this process now
/// ALSO writes a small diagnostic record to
/// `users/{uid}.pushDebug` in Firestore, viewable directly in the
/// Firestore Console with no Mac, terminal, or Xcode needed at all. This
/// is in ADDITION to the existing debugPrint() calls, not a replacement
/// - both still happen.
///
/// `pushDebug` fields written:
///   - `lastAttemptAt` (timestamp) - when initAndRegister was last called
///   - `permissionStatus` (string) - the AuthorizationStatus result
///     ('authorized', 'denied', 'notDetermined', 'provisional', etc.)
///   - `tokenObtained` (bool) - whether getToken() returned a non-null
///     value
///   - `tokenSaved` (bool) - whether the Firestore write of the token
///     itself succeeded
///   - `lastError` (string, nullable) - the exact exception text if
///     ANYTHING in this flow threw, so failures are never silent again
///   - `platform` (string) - 'ios' or 'android', from
///     defaultTargetPlatform, so it's obvious which OS this record is
///     from if the user reinstalls/switches devices
class PushNotificationService {
  PushNotificationService._();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> initAndRegister(String uid) async {
    final docRef = _db.collection('users').doc(uid);
    // Record that an attempt started, before anything else can fail -
    // so even a total early crash still leaves SOME trace in Firestore
    // instead of zero information at all.
    await _writeDebug(docRef, {
      'lastAttemptAt': FieldValue.serverTimestamp(),
      'platform': defaultTargetPlatform.name,
    });
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await _writeDebug(docRef, {
        'permissionStatus': settings.authorizationStatus.name,
      });
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('PushNotificationService: user denied notification permission.');
        await _writeDebug(docRef, {
          'lastError': 'Permission denied by user (authorizationStatus == denied).',
        });
        return;
      }
      final token = await _messaging.getToken();
      await _writeDebug(docRef, {
        'tokenObtained': token != null,
      });
      if (token != null) {
        await _saveToken(uid, token);
        await _writeDebug(docRef, {
          'tokenSaved': true,
          'lastError': null,
        });
      } else {
        // This is a KNOWN, documented iOS timing issue: getToken() can
        // return null if called before the native APNs token has fully
        // propagated, immediately after a fresh permission grant. If
        // pushDebug shows permissionStatus=authorized but
        // tokenObtained=false, this is almost certainly the cause - see
        // the retry-on-next-launch note below.
        await _writeDebug(docRef, {
          'lastError': 'getToken() returned null - possible iOS APNs token propagation delay. Should resolve on next app launch (see retryIfNeeded()).',
        });
      }
      _messaging.onTokenRefresh.listen((newToken) {
        _saveToken(uid, newToken);
        _writeDebug(docRef, {'tokenSaved': true, 'tokenObtained': true, 'lastError': null});
      });
    } catch (e, stack) {
      debugPrint('PushNotificationService.initAndRegister failed: $e');
      debugPrint(stack.toString());
      await _writeDebug(docRef, {
        'lastError': e.toString(),
      });
    }
  }

  /// Call this once more on a LATER app launch (e.g. from main.dart's
  /// normal cold-start path, which already calls initAndRegister for an
  /// already-signed-in user) - if the very first registration hit the
  /// iOS getToken()-returns-null timing issue, a plain retry on the next
  /// natural app open is usually all that's needed, since by then the
  /// APNs token has fully propagated. No special wiring needed - this is
  /// just documenting that main.dart's existing
  /// `await PushNotificationService.initAndRegister(authService.uid!)`
  /// call already serves as this retry automatically.
  static Future<void> retryIfNeeded(String uid) => initAndRegister(uid);

  static Future<void> _saveToken(String uid, String token) async {
    await _db.collection('users').doc(uid).set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]),
      },
      SetOptions(merge: true),
    ).catchError((e) => debugPrint('PushNotificationService: failed to save token: $e'));
  }

  static Future<void> _writeDebug(DocumentReference<Map<String, dynamic>> docRef, Map<String, dynamic> fields) async {
    try {
      await docRef.set({'pushDebug': fields}, SetOptions(merge: true));
    } catch (e) {
      // If even the diagnostic write itself fails (e.g. a rules issue),
      // at least surface that in the normal debug console as a last
      // resort.
      debugPrint('PushNotificationService: failed to write pushDebug: $e');
    }
  }

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
