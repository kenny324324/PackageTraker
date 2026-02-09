/**
 * triggers.ts
 *
 * Firestore Trigger：監聽包裹狀態變化，
 * 當狀態變為 "arrivedAtStore" 時發送 FCM 推播通知。
 */

import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import {getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {sendPushNotification} from "./services/pushNotification";

export const onPackageStatusChange = onDocumentUpdated(
  {
    document: "users/{userId}/packages/{packageId}",
    region: "asia-east1",
  },
  async (event) => {
    if (!event.data) return;

    const before = event.data.before.data();
    const after = event.data.after.data();
    const {userId, packageId} = event.params;

    // 狀態未變化，跳過
    if (before.status === after.status) {
      return;
    }

    logger.info(
      `[Trigger] Status changed: ${after.trackingNumber} ` +
      `(${before.status} -> ${after.status})`
    );

    // 只在到貨時推播
    if (after.status !== "arrivedAtStore") {
      return;
    }

    // 避免重複推播
    if (after.lastNotifiedStatus === after.status) {
      logger.info("[Trigger] Already notified for this status, skipping");
      return;
    }

    // 取得用戶資料
    const db = getFirestore();
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();

    if (!userData || !userData.fcmToken) {
      logger.info("[Trigger] No FCM token, skipping");
      return;
    }

    // 檢查通知設定
    const settings = userData.notificationSettings;
    if (!settings?.enabled) {
      logger.info("[Trigger] Notifications disabled, skipping");
      return;
    }
    if (!settings?.arrivalNotification) {
      logger.info("[Trigger] Arrival notifications disabled, skipping");
      return;
    }

    // 組裝推播內容
    const packageName = after.customName || after.trackingNumber;
    const location =
      after.pickupLocation ||
      after.userPickupLocation ||
      after.storeName ||
      "取貨地點";

    const success = await sendPushNotification(userData.fcmToken, {
      title: "包裹已到達取貨點",
      body: `${packageName} 已到達 ${location}，請儘快取貨`,
      data: {
        packageId: packageId,
        trackingNumber: after.trackingNumber || "",
        status: after.status,
      },
    });

    if (success) {
      // 更新 lastNotifiedStatus 防止重複推播
      await event.data.after.ref.update({
        lastNotifiedStatus: after.status,
      });
      logger.info(`[Trigger] Push sent to user ${userId}`);
    } else {
      logger.warn(`[Trigger] Failed to send push to user ${userId}`);
    }
  }
);
