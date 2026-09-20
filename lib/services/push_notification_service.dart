import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Handles the DEVICE side of push notifications: requesting permission,
/// obtaining this device's FCM token, and saving it to
/// `users/{uid}.fcmTokens`.
///
/// DIAGNOSTIC LOGGING (3/9 update): every step of this process writes a
/// small diagnostic record to `users/{uid}.pushDebug` in Firestore,
/// viewable directly in the Firestore Console - see
/// screens/shared/push_diagnostics_screen.dart for the in-app viewer.
///
/// FIX (9/10 update - confirmed root cause of "host/admin never receive
/// a push, even though permissionStatus is authorized"): a real device's
/// `pushDebug` record showed:
///   permissionStatus: "authorized"
///   lastError: "[firebase_messaging/apns-token-not-set] APNS token has
///               not been received on the device yet. Please ensure the
///               APNS token is available before calling `getToken()`."
///
/// This is a KNOWN iOS/FCM timing issue: on iOS, Firebase Messaging's
/// `getToken()` internally needs Apple's native APNs device token FIRST
/// (obtained via `getAPNSToken()`), and that APNs token is not always
/// available the instant `requestPermission()` resolves - it can take
/// anywhere from under a second up to several seconds to propagate from
/// the OS. The PREVIOUS version of this file called `getToken()`
/// immediately after `requestPermission()` with no wait at all, so on
/// iOS it very often hit this exact race and threw
/// `apns-token-not-set`, which fell into the `catch` block, got logged
/// to `lastError`, and the token was simply never obtained/saved - so
/// no push notification could ever reach that device, even though the
/// user had correctly granted permission.
///
/// FIX: added `_waitForApnsToken()`, which - ONLY on iOS/macOS - polls
/// `getAPNSToken()` every 1 second (up to 10 attempts / 10 seconds) until
/// Apple's native token is actually available, before ever calling
/// `getToken()`. This removes the race entirely with no change needed
/// to Android (which has no APNs concept and is unaffected). If the APNs
/// token still isn't available after 10 seconds, this now logs a
/// specific, actionable `lastError` instead of the raw exception text,
/// and `retryIfNeeded()` (already called on every subsequent app launch)
/// will simply succeed the next time once APNs has caught up.
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

      // FIX: on iOS/macOS, wait for Apple's native APNs token to be
      // ready BEFORE calling getToken() - this is what actually fixes
      // the confirmed `apns-token-not-set` error. No-op on
      // Android/other platforms (there is no APNs concept there).
      if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
        final apnsReady = await _waitForApnsToken(docRef);
        if (!apnsReady) {
          await _writeDebug(docRef, {
            'lastError': 'Timed out waiting for the APNs token after 10s. This usually resolves itself on '
                'the next app launch/sign-in - if it keeps happening, check that push notifications '
                'capability + an APNs auth key are correctly configured for this app in the Apple '
                'Developer portal and Firebase Console.',
          });
          return;
        }
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
        await _writeDebug(docRef, {
          'lastError': 'getToken() returned null even after the APNs token was ready.',
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

  /// Polls `getAPNSToken()` once per second, up to [maxAttempts] times,
  /// until Apple's native APNs token is available. Returns true as soon
  /// as it is, or false if it never becomes available within the
  /// attempt budget. iOS/macOS only - do not call on other platforms.
  static Future<bool> _waitForApnsToken(
    DocumentReference<Map<String, dynamic>> docRef, {
    int maxAttempts = 10,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final apnsToken = await _messaging.getAPNSToken();
      if (apnsToken != null) {
        await _writeDebug(docRef, {'apnsTokenObtained': true});
        return true;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    await _writeDebug(docRef, {'apnsTokenObtained': false});
    return false;
  }

  /// Call this once more on a LATER app launch (e.g. from main.dart's
  /// normal cold-start path, which already calls initAndRegister for an
  /// already-signed-in user) - if the very first registration hit the
  /// iOS APNs timing issue and still timed out after the retries above,
  /// a plain retry on the next natural app open is usually all that's
  /// needed, since by then the APNs token has fully propagated. No
  /// special wiring needed - this is just documenting that main.dart's
  /// existing `await PushNotificationService.initAndRegister(authService.uid!)`
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
