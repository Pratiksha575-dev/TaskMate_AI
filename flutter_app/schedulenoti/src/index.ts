import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

export const scheduleNotificationFunction = onSchedule(
  "every 5 minutes",
  async () => {
    const now = admin.firestore.Timestamp.now();
    const fiveMinutesLater = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + 5 * 60 * 1000)
    );

    const notificationsQuery = await db
      .collection("notifications")
      .where("reminderTime", ">=", now)
      .where("reminderTime", "<=", fiveMinutesLater)
      .get();

    if (notificationsQuery.empty) {
      console.log("No notifications to send.");
      return;
    }

    const promises = notificationsQuery.docs.map(async (doc) => {
      const data = doc.data();
      const token = data.token;
      const title = data.title;
      const body = data.body;

      if (!token) {
        console.log(`Missing FCM token for notification ${doc.id}`);
        return;
      }

      const message = {notification: {title, body}, token: token};

      try {
        const response = await messaging.send(message);
        console.log(`Notification sent successfully: ${response}`);
        // ✅ Delete after sending (optional)
        await doc.ref.delete();
      } catch (error) {
        console.error("Error sending notification:", error);
      }
    });

    await Promise.all(promises);
  });
