/**
 * Cloud Function: sends an actual FCM push notification whenever a new
 * document is created in the `notifications` Firestore collection (see
 * NotificationService.notify() in the Flutter app).
 *
 * RENAMED from `sendNotificationPush` to `sendNotificationPushV2` -
 * purely to sidestep a persistent "Changing from an HTTPS function to a
 * background triggered function is not allowed" deploy error. (Unchanged
 * from before - see original comment history.)
 *
 * FIX (9/15 update - "notification for offline/standby is not working,
 * I don't get it in the notification bar same as normal sms/whatsapp
 * message, even though Test Notification correctly shows up while the
 * phone is locked"):
 *
 * Since Test Notifications DID display correctly on the lock screen,
 * the delivery pipeline itself (device token registration, APNs
 * entitlements, permissions) is proven to work. The actual gap is in
 * THIS payload: it previously only set the generic `notification` and
 * `data` fields with no explicit `apns` block at all. Without that,
 * Apple's push service (APNs) has no explicit priority/delivery hint
 * for this specific message, and can silently downgrade or delay
 * delivery for messages sent this way - especially once the target
 * device is locked, backgrounded, or the app has been fully killed.
 * This is a well-documented gap between FCM's generic "notification"
 * payload and iOS's actual requirements for guaranteed lock-screen
 * banner delivery.
 *
 * FIX: every message now explicitly includes:
 *   - `apns.headers['apns-priority'] = '10'` (deliver immediately,
 *     required for anything the user should see right away on the lock
 *     screen - '5' or unset can be queued/throttled by Apple).
 *   - `apns.headers['apns-push-type'] = 'alert'` (explicitly marks this
 *     as a user-visible alert, not a silent/background data push).
 *   - `apns.payload.aps.alert.title/body` (explicit aps alert block,
 *     rather than relying on FCM's implicit top-level `notification` ->
 *     `aps.alert` mapping, which is the part most likely to have been
 *     silently dropped/altered under certain iOS states).
 *   - `apns.payload.aps.sound = 'default'` and `badge` (ensures a full
 *     system notification - sound + banner + badge - exactly like a
 *     normal SMS/WhatsApp message, not a silent update).
 *   - `apns.payload.aps['mutable-content'] = 1` (future-proofs this for
 *     any notification service extension / rich media later).
 *   - `android.priority = 'high'` and an explicit notification channel
 *     (kept for parity/completeness, in case an Android device is ever
 *     added - has no effect on your current iOS-only devices).
 *
 * No changes were needed anywhere in the Flutter app for this - the
 * trigger condition (a new `notifications` doc) and the `data` fields
 * consumed by NotificationService/main.dart are unchanged.
 */
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
admin.initializeApp();

exports.sendNotificationPushV2 = onDocumentCreated('notifications/{notificationId}', async (event) => {
  const snap = event.data;
  if (!snap) return;
  const notification = snap.data();
  const recipientId = notification.recipientId;
  if (!recipientId) {
    console.log('Notification has no recipientId, skipping push.');
    return;
  }
  // Look up the recipient's registered device tokens (see
  // PushNotificationService.initAndRegister in the Flutter app, which
  // writes these to users/{uid}.fcmTokens).
  const userDoc = await admin.firestore().collection('users').doc(recipientId).get();
  const tokens = userDoc.exists ? (userDoc.data().fcmTokens || []) : [];
  if (tokens.length === 0) {
    console.log(`No FCM tokens registered for user ${recipientId} - notification saved in-app only.`);
    return;
  }

  const title = notification.title || 'EVPair';
  const body = notification.body || '';

  const message = {
    notification: {
      title,
      body,
    },
    data: {
      type: notification.type || 'other',
      bookingId: notification.bookingId || '',
      chargerId: notification.chargerId || '',
    },
    // FIX: explicit APNs config - this is what actually guarantees a
    // real system notification banner/sound while the device is locked
    // or the app is killed, matching normal SMS/WhatsApp-style delivery.
    apns: {
      headers: {
        'apns-priority': '10',
        'apns-push-type': 'alert',
      },
      payload: {
        aps: {
          alert: {
            title,
            body,
          },
          sound: 'default',
          badge: 1,
          'mutable-content': 1,
        },
      },
    },
    // Kept for parity/completeness if an Android device is ever added.
    android: {
      priority: 'high',
      notification: {
        channelId: 'high_importance_channel',
        sound: 'default',
      },
    },
    tokens: tokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`Push sent to ${recipientId}: ${response.successCount} succeeded, ${response.failureCount} failed.`);
    // Clean up any tokens that are no longer valid (e.g. app uninstalled,
    // token expired) so this array doesn't grow unbounded with dead
    // tokens over time.
    const invalidTokens = [];
    response.responses.forEach((resp, idx) => {
      if (!resp.success) {
        const code = resp.error && resp.error.code;
        if (code === 'messaging/invalid-registration-token' || code === 'messaging/registration-token-not-registered') {
          invalidTokens.push(tokens[idx]);
        }
      }
    });
    if (invalidTokens.length > 0) {
      await admin.firestore().collection('users').doc(recipientId).update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
      });
    }
  } catch (error) {
    console.error(`Failed to send push to ${recipientId}:`, error);
  }
});
