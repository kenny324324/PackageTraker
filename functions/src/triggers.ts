/**
 * triggers.ts
 *
 * Firestore Trigger：監聽包裹狀態變化，
 * 當狀態變為 shipped 或 arrivedAtStore 時發送多語系 FCM 推播通知。
 */

import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import {getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {sendPushNotification} from "./services/pushNotification";
import {getNotificationText, normalizeLang} from "./i18n/notifications";
import {getCarrierDisplayName} from "./utils/carrierNames";

/** 需要推播的狀態清單 */
const NOTIFIABLE_STATUSES = ["shipped", "arrivedAtStore"];

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

    // 只在指定狀態推播
    if (!NOTIFIABLE_STATUSES.includes(after.status)) {
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

    // 根據狀態檢查對應的通知開關
    if (after.status === "arrivedAtStore" && !settings?.arrivalNotification) {
      logger.info("[Trigger] Arrival notifications disabled, skipping");
      return;
    }
    if (after.status === "shipped" && !settings?.shippedNotification) {
      logger.info("[Trigger] Shipped notifications disabled, skipping");
      return;
    }

    // 取得用戶語系
    const lang = normalizeLang(userData.language);

    // 組裝推播內容
    const packageName = after.customName || after.trackingNumber;

    // 優先使用具體門市名稱，否則使用 carrier 的中文顯示名稱
    let location =
      after.pickupLocation ||
      after.userPickupLocation ||
      after.storeName ||
      "";

    // 如果 location 為空或只是英文 carrier rawValue，使用中文顯示名稱
    if (!location || location === after.carrier) {
      location = getCarrierDisplayName(after.carrier, lang);
    }

    const text = getNotificationText(after.status, lang, {
      name: packageName,
      location: location,
    });

    if (!text) {
      logger.warn(`[Trigger] No template for status: ${after.status}`);
      return;
    }

    const success = await sendPushNotification(userData.fcmToken, {
      title: text.title,
      body: text.body,
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
      logger.info(`[Trigger] Push sent to user ${userId} (${after.status}, ${lang})`);
    } else {
      logger.warn(`[Trigger] Failed to send push to user ${userId}`);
    }
  }
);
