import Flutter
import UIKit
import FirebaseMessaging
import UserNotifications

/// FIX (9/21 update, corrected) - "apnsTokenObtained: false, timed out
/// waiting for the APNs token after 10s" - persisted identically across
/// multiple devices/accounts, over both Wi-Fi and 5G, with App ID, APNs
/// Auth Key, entitlements, and provisioning profile all independently
/// verified as correctly configured.
///
/// CORRECTION: an earlier version of this file also called
/// `FirebaseApp.configure()` natively, assuming this project used the
/// classic GoogleService-Info.plist-based native setup. That was wrong
/// for this project - it uses the Dart-side FlutterFire CLI setup
/// (`Firebase.initializeApp()` in main.dart, backed by
/// `firebase_options.dart`), which does NOT bundle a
/// GoogleService-Info.plist. Calling `FirebaseApp.configure()` natively
/// with no such file present caused Firebase's own configure() method to
/// throw an NSException immediately on launch (visible in the crash log
/// as `+[FIRApp configure] + 84 (FIRApp.m:110)`), crashing the app
/// before Flutter/Dart ever ran. That native configure() call has been
/// REMOVED below - Dart's own `Firebase.initializeApp()` call already
/// handles Firebase setup correctly for this project, exactly as it did
/// before any of these changes.
///
/// What remains is only the actual fix for the APNs token issue: this
/// AppDelegate now explicitly registers for remote notifications and
/// manually forwards the raw APNs device token to
/// `Messaging.messaging()`, removing any dependency on Firebase's
/// automatic method swizzling (which is what silently wasn't forwarding
/// the token before).
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Explicit, manual token forwarding - removes any dependency on
  // Firebase's automatic method swizzling working correctly.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("EVPair: APNs registration explicitly FAILED with error: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
