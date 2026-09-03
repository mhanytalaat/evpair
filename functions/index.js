/**
 * Cloud Function: sends an actual FCM push notification whenever a new
 * document is created in the `notifications` Firestore collection (see
 * NotificationService.notify() in the Flutter app).
 *
 * RENAMED from `sendNotificationPush` to `sendNotificationPushV2` -
 * purely to sidestep a persistent "Changing from an HTTPS function to a
 * background triggered function is not allowed" deploy error. An
 * earlier deploy attempt (before this file's content was finalized)
 * apparently created `sendNotificationPush` as an HTTPS function
 * somewhere in Google Cloud's underlying Cloud Run/Eventarc/Pub-Sub
 * layers, and `firebase functions:delete` did not fully tear down every
 * one of those pieces even though the CLI reported a successful delete.
 * Deploying under a new name avoids that stale conflict entirely - no
 * other code changes were needed, since the app side
 * (NotificationService.notify() in Flutter) only ever writes to the
 * `notifications` Firestore collection and has NO reference to this
 * function's name at all; this trigger just listens to that same
 * collection under a fresh identity.
 *
 * If you want to clean up the old, now-unused `sendNotificationPush`
 * later, you can try deleting it directly from the Google Cloud Console
 * (console.cloud.google.com/run and console.cloud.google.com/eventarc)
 * instead of the Firebase CLI - but there is no urgency to do this, it
 * costs nothing sitting idle and unused.
 *
 * WHY THIS MUST BE SERVER-SIDE (not done directly from the app):
 * Sending a push to ANOTHER user's device requires a Firebase Admin SDK
 * service account credential - if that credential were embedded in the
 * Flutter app, any user could extract it and impersonate your backend to
 * push to anyone. Cloud Functions run with that trusted credential
 * automatically, which is why the actual "send" step lives here instead
 * of in NotificationService.dart.
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

  const message = {
    notification: {
      title: notification.title || 'EVPair',
      body: notification.body || '',
    },
    data: {
      type: notification.type || 'other',
      bookingId: notification.bookingId || '',
      chargerId: notification.chargerId || '',
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
